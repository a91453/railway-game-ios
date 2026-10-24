import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 295: on a real-world map the platform tool offers
/// the real stations no station of the world is yet; a tap on one picks the
/// nearest track for the platform and names the station after it.
@MainActor
final class RealStationSuggestionTests: XCTestCase {
    /// A real-world game round 猴硐, with the railways, and a straight
    /// track 600 m long running east to west `offset` metres north of the
    /// station.
    private func makeSession(
        trackOffsetMetres offset: Int64? = 60, stationNamed station: String? = nil, language: DisplayLanguage = .traditionalChinese
    ) throws -> (GameSession, PlanPoint) {
        let houtong = try BundledRealData.station("猴硐", in: "tra_sched")
        var world = GameWorld.newGame(anchor: try XCTUnwrap(houtong.anchor))
        let at = try BundledRealData.point(houtong.coordinate, in: world)
        if let offset {
            let metre = WorldCoordinate.unitsPerMetre
            let y = at.y - offset * metre
            let west = try world.buildTrackNode(at: WorldCoordinate(x: at.x - 300 * metre, y: y))
            let east = try world.buildTrackNode(at: WorldCoordinate(x: at.x + 300 * metre, y: y))
            try world.buildTrackEdge(from: west, to: east)
        }
        if let station {
            _ = try world.buildStation(named: station, at: PlanPoint(x: at.x + 100 * WorldCoordinate.unitsPerMetre, y: at.y))
        }
        let session = GameSession(world: world, language: language)
        session.railways = try BundledRealData.railways()
        return (session, at)
    }

    func testTheRealStationsOfOnePlaceAreOneSuggestion() throws {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let session = GameSession(world: GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor)), language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        let taipei = try BundledRealData.point(tra.coordinate, in: session.world)
        let nearest = try XCTUnwrap(session.nearestRealStation(to: taipei))
        XCTAssertEqual(RealRailways.stationKey(nearest.name(in: .traditionalChinese)), "台北")
        XCTAssertLessThan(nearest.distanceMetres, 450)
        let systems = Set(nearest.systems.map(\.id))
        XCTAssertTrue(systems.contains("tra_sched"), "\(systems)")
        XCTAssertGreaterThan(systems.count, 1, "the TRA's and the others' 台北 are one place: \(systems)")

        let around = session.realStations(near: taipei, within: 2_000)
        XCTAssertEqual(around.first?.id, nearest.id)
        XCTAssertEqual(around.map(\.distanceMetres), around.map(\.distanceMetres).sorted(), "nearest first")
        XCTAssertEqual(Set(around.map(\.id)).count, around.count)
    }

    func testNoRealStationOnABlankMapOrFarFromOne() throws {
        let blank = GameSession(world: GameWorld.newGame(), language: .english)
        blank.railways = try BundledRealData.railways()
        XCTAssertNil(blank.nearestRealStation(to: PlanPoint(x: 1_000, y: 1_000)))

        let (session, houtong) = try makeSession(trackOffsetMetres: nil)
        XCTAssertEqual(session.nearestRealStation(to: houtong)?.name(in: .traditionalChinese), "猴硐")
        let far = PlanPoint(x: houtong.x + 3_000 * WorldCoordinate.unitsPerMetre, y: houtong.y)
        XCTAssertNil(session.nearestRealStation(to: far), "past 450 m")
    }

    func testThePinsShowOnlyWhileChoosingWhereAPlatformGoes() throws {
        let (session, _) = try makeSession()
        XCTAssertEqual(session.realStationSuggestions, [], "the select tool")
        session.selectTool(.network)
        XCTAssertEqual(session.realStationSuggestions, [], "laying track")
        session.setNetworkMode(.platform)
        let pins = session.realStationSuggestions
        XCTAssertTrue(pins.contains { $0.name(in: .traditionalChinese) == "猴硐" }, "\(pins.map { $0.name(in: .traditionalChinese) })")
        for pin in pins {
            XCTAssertTrue(session.world.bounds.contains(pin.point))
            XCTAssertTrue(session.world.ownsGround(at: pin.point), "\(pin.id) on land not owned")
        }
        XCTAssertEqual(Set(pins.map(\.id)).count, pins.count)
    }

    func testARealStationAlreadyBuiltIsNotOfferedAgain() throws {
        for name in ["猴硐", "Houtong"] {
            let (session, _) = try makeSession(trackOffsetMetres: nil, stationNamed: name)
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            XCTAssertFalse(session.realStationSuggestions.contains { $0.name(in: .traditionalChinese) == "猴硐" }, name)
        }
    }

    func testATapOnAPinPicksTheNearestTrackAndTheRealName() throws {
        let (session, houtong) = try makeSession()
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        session.stationName = "我的車站"
        let pin = try XCTUnwrap(session.realStationSuggestions.first { $0.name(in: .traditionalChinese) == "猴硐" })
        session.pickRealStation(pin)
        XCTAssertNil(session.message)
        let site = try XCTUnwrap(session.platformSitePlanPoint)
        XCTAssertEqual(site.y, houtong.y - 60 * WorldCoordinate.unitsPerMetre, "on the track")
        XCTAssertLessThan(abs(site.x - houtong.x), WorldCoordinate.unitsPerMetre, "right beside the real one")
        XCTAssertEqual(session.stationName, "猴硐", "the pin was asked for, over a typed name")

        session.addNetworkPlatform()
        let station = try XCTUnwrap(session.world.stations.first)
        XCTAssertEqual(station.name, "猴硐")
        XCTAssertFalse(session.realStations(named: station.name, at: station.location).isEmpty, "recognised as the real one")
        XCTAssertFalse(session.realStationSuggestions.contains { $0.id == pin.id }, "built: no pin")
    }

    func testAPinInEnglishNamesTheStationInEnglish() throws {
        let (session, _) = try makeSession(language: .english)
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        let pin = try XCTUnwrap(session.realStationSuggestions.first { $0.name(in: .traditionalChinese) == "猴硐" })
        session.pickRealStation(pin)
        XCTAssertEqual(session.stationName, "Houtong")
    }

    /// Decision 400 A.8: without track within 400 m, the pin offers the
    /// station for sale instead (``RealStationPurchaseTests``).
    func testWithoutTrackNearAPinNothingIsPickedAndTheStationIsOffered() throws {
        let (session, _) = try makeSession(trackOffsetMetres: 500)
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        let pin = try XCTUnwrap(session.realStationSuggestions.first { $0.name(in: .traditionalChinese) == "猴硐" })
        session.pickRealStation(pin)
        XCTAssertNil(session.platformSitePlanPoint)
        XCTAssertNil(session.message)
        XCTAssertEqual(session.shownRealStationOffer?.suggestion.id, pin.id)
    }
}

extension RealStationSuggestionTests {
    func testAPinOverlappingABusierOneWaitsUntilTheMapIsCloser() throws {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let session = GameSession(world: GameWorld.newGame(anchor: try XCTUnwrap(tra.anchor)), language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        let taipei = try BundledRealData.point(tra.coordinate, in: session.world)
        let places = session.realStations(near: taipei, within: 3_000)
        let busy = try XCTUnwrap(places.first { $0.systems.count > 1 })
        let quiet = try XCTUnwrap(places.first { $0.systems.count == 1 })

        // Close together, the place more systems stop at stays, whatever
        // the order.
        let close = RealStationSuggestion.shown([(quiet, 100, 100), (busy, 120, 105)])
        XCTAssertEqual(close, [busy.id])
        // Apart, both show.
        let apart = RealStationSuggestion.shown([(quiet, 100, 100), (busy, 100 + RealStationSuggestion.pinWidth, 100)])
        XCTAssertEqual(apart, [busy.id, quiet.id])
    }
}
