import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 400 A.8: on a real-world map, a real station's pin with no
/// track within 400 m offers the station: a short stretch of track along
/// the real line and its platform, for what building them costs.
@MainActor
final class RealStationPurchaseTests: XCTestCase {
    /// A real-world game round real station `name` of `system`, with the
    /// railways, the platform tool chosen, and the app's heights when
    /// `heights`.
    private func game(round name: String, in system: String = "tra_sched", heights: Bool = false) throws -> (GameSession, RealStationSuggestion) {
        let real = try BundledRealData.station(name, in: system)
        var world = GameWorld.newGame(anchor: try XCTUnwrap(real.anchor))
        if heights { try world.mapGround() }
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        if heights { session.heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat")) }
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        let at = try BundledRealData.point(real.coordinate, in: session.world)
        let pin = try XCTUnwrap(session.nearestRealStation(to: at))
        return (session, pin)
    }

    func testAPinWithoutTrackNearOpensTheStationsCard() throws {
        let (session, pin) = try game(round: "猴硐")
        session.pickRealStation(pin)
        XCTAssertNil(session.message)
        XCTAssertNil(session.platformSitePlanPoint, "no track to put a platform on")
        let offer = try XCTUnwrap(session.shownRealStationOffer)
        XCTAssertEqual(offer.suggestion.id, pin.id)
        XCTAssertEqual(offer.system.id, "tra_sched")
        XCTAssertNil(offer.problem)
        XCTAssertNotNil(offer.purchase)
        XCTAssertTrue(offer.summaryText(in: .traditionalChinese).contains("\(offer.metres) 公尺"), offer.summaryText(in: .traditionalChinese))
    }

    func testTheStationIsBoughtAsOneCommandForWhatBuildingItCosts() throws {
        let (session, pin) = try game(round: "猴硐")
        let offer = session.realStationOffer(for: pin)
        let purchase = try XCTUnwrap(offer.purchase, offer.problem ?? "")
        let price = try XCTUnwrap(offer.price)
        // The platform as decision 295 makes it, and 150 m on past each end.
        let platform = Double(try XCTUnwrap(session.realPlatformCars(forStationNamed: "猴硐", at: pin.point))) * Double(session.world.platformCarLength)
            / Double(WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(Double(offer.metres), platform + 300, accuracy: 2)
        // Only what building costs: the station's $200,000 and the track,
        // no value for a line's running.
        let station = Money(20_000_000)
        XCTAssertGreaterThan(price, station)
        XCTAssertLessThan(price, station + Money(Int64(offer.metres) * 20_000))
        print("猴硐: \(offer.metres) m, \(price.moneyText)")

        let before = session.world
        session.shownRealStationOffer = offer
        XCTAssertTrue(session.buyRealStation(offer), session.message?.text ?? "")
        XCTAssertNil(session.shownRealStationOffer, "the card closes")
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.economy.balance, before.economy.balance - price)
        XCTAssertEqual(session.world.stations.count, 1)
        let built = try XCTUnwrap(session.world.stations.first)
        XCTAssertEqual(built.name, "猴硐")
        XCTAssertEqual(session.world.network.platforms(of: built.id).count, 1)
        XCTAssertFalse(session.realStations(named: built.name, at: built.location).isEmpty, "recognised as the real one")
        XCTAssertFalse(session.realStationSuggestions.contains { $0.id == pin.id }, "built: no pin")
        XCTAssertTrue(session.world.acquisitions.isEmpty, "nothing records it was bought")
        guard case .command(let command)? = session.commandLog.entries.last?.action, case .buyRealStation = command else {
            return XCTFail("logged as a purchase")
        }
        let data = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: data), command)
        XCTAssertEqual(purchase.name, "猴硐")

        // One Undo takes all of it back.
        session.undo()
        XCTAssertEqual(session.world, before)
    }

    func testABigStationOnAMainLineCanBeBoughtAlongItsLines() throws {
        for name in ["臺北", "板橋"] {
            let (session, pin) = try game(round: name, heights: true)
            let systems = session.realStationSystems(of: pin).map(\.id)
            XCTAssertEqual(systems.first, "tra_sched", "\(name): the TRA's by default")
            XCTAssertGreaterThan(systems.count, 1, "\(name): \(systems)")
            let offer = session.realStationOffer(for: pin)
            XCTAssertNotNil(offer.purchase, "\(name): \(offer.problem ?? "")")
            print("\(name): \(offer.metres) m, \(offer.price?.moneyText ?? "-")")

            // Another of its systems' lines.
            session.shownRealStationOffer = offer
            let other = try XCTUnwrap(systems.dropFirst().first)
            session.chooseRealStationSystem(other)
            let along = try XCTUnwrap(session.shownRealStationOffer)
            XCTAssertEqual(along.system.id, other)
            XCTAssertNotNil(along.purchase, "\(name) along \(other): \(along.problem ?? "")")

            let before = session.world.economy.balance
            XCTAssertTrue(session.buyRealStation(offer), "\(name): \(session.message?.text ?? "")")
            XCTAssertEqual(session.world.economy.balance, before - (offer.price ?? .zero))
            // On the ground, as the game's stations are, though the real
            // station is under it: no tunnel of the real line's.
            for stretch in offer.purchase?.stretches ?? [] {
                let ground = try XCTUnwrap(session.world.groundHeight(at: stretch.from.plan))
                XCTAssertLessThan(abs(stretch.from.z - ground), 10 * WorldCoordinate.unitsPerMetre, "\(name): on the ground")
            }
        }
    }

    func testWhatIsInTheWayIsSaidAndNothingIsBought() throws {
        let (free, pin) = try game(round: "猴硐")
        let first = try XCTUnwrap(free.realStationOffer(for: pin).purchase?.stretches.first)
        // A track of the player's across the real line near its end, more
        // than 400 m from the station.
        let real = try BundledRealData.station("猴硐", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(real.anchor))
        let metre = WorldCoordinate.unitsPerMetre
        let a = try world.buildTrackNode(at: WorldCoordinate(x: first.from.x - 200 * metre, y: first.from.y - 200 * metre))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: first.from.x + 200 * metre, y: first.from.y + 200 * metre))
        try world.buildTrackEdge(from: a, to: b)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        let blocked = session.realStationOffer(for: pin)
        XCTAssertNil(blocked.purchase)
        XCTAssertNotNil(blocked.problem)
        print("blocked: \(blocked.problem ?? "")")
        let before = session.world
        XCTAssertFalse(session.buyRealStation(blocked))
        XCTAssertEqual(session.world, before)
    }

    func testTheCardSaysWhatTheCashLacks() throws {
        let (session, pin) = try game(round: "猴硐")
        let offer = session.realStationOffer(for: pin)
        let price = try XCTUnwrap(offer.price)
        XCTAssertNil(offer.shortfallText(balance: price, in: .traditionalChinese))
        XCTAssertEqual(offer.shortfallText(balance: price - Money(1_000), in: .traditionalChinese), "還差 \(Money(1_000).moneyText)。")
    }
}
