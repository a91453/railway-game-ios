import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 315: buying a real branch line on a real-world map, its track,
/// stations, trains and TRA's own timetable in one command.
@MainActor
final class RealLineAcquisitionTests: XCTestCase {
    /// A real-world game round the middle of `line`'s stations, with the
    /// bundled railways and `balance`.
    private func game(round network: String, balance: Money = Money(100_000_000_000), side: Int64 = 1 << 20, heights: Bool = false, transfers: Bool = false) throws -> GameSession {
        let railways = try BundledRealData.railways()
        let runs = try XCTUnwrap(railways.branchRuns[network])
        let stations = try runs.stops.map { try BundledRealData.station($0, in: "tra_sched") }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        var world = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: side, height: side), balance: balance)
        if heights { try world.mapGround() }
        if transfers { world.setRealTransfers(true) }
        let session = GameSession(world: world, language: .traditionalChinese)
        session.railways = railways
        if heights { session.heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat")) }
        return session
    }

    private func line(_ network: String, in session: GameSession) throws -> RealBranchLine {
        try XCTUnwrap(session.buyableRealLines.first { $0.network == network }, "\(network) on sale")
    }

    func testThePingxiLineIsBoughtAsOneCommandAndRunsItsRealTrains() throws {
        let session = try game(round: "PINGXI")
        let pingxi = try line("PINGXI", in: session)
        XCTAssertEqual(pingxi.stops, ["三貂嶺", "大華", "十分", "望古", "嶺腳", "平溪", "菁桐"])
        XCTAssertEqual(session.buyableRealLine(through: "十分"), pingxi)
        XCTAssertNil(session.buyableRealLine(through: "三貂嶺"), "the junction is the main line's")

        let offer = session.realLineOffer(for: pingxi)
        XCTAssertNil(offer.problem)
        let price = try XCTUnwrap(offer.price)
        let acquisition = try XCTUnwrap(offer.acquisition)
        print("Pingxi: building \(price.building.moneyText), trains \(price.trains.moneyText), riders \(price.riders.moneyText) (\(acquisition.dailyRiders) a day), total \(price.total.moneyText)")
        XCTAssertGreaterThan(price.building, .zero)
        XCTAssertGreaterThan(price.trains, .zero)
        XCTAssertEqual(price.riders, LineAcquisition.value(ofDailyRiders: acquisition.dailyRiders))
        XCTAssertGreaterThan(acquisition.dailyRiders, 0)
        XCTAssertEqual(acquisition.trains.count, 3)

        let before = session.world
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        XCTAssertEqual(session.world.economy.balance, before.economy.balance - price.total)
        let bought = try XCTUnwrap(session.world.acquisition(of: "tra:PINGXI"))
        let line = try XCTUnwrap(session.world.line(id: bought.line))
        XCTAssertEqual(line.stops.count, 7)
        XCTAssertEqual(line.trains.count, 3)
        XCTAssertFalse(session.buyableRealLines.contains(pingxi), "bought once")
        let card = try XCTUnwrap(session.lastLineAcquired)
        XCTAssertEqual(card.ends.from, "三貂嶺")
        XCTAssertEqual(card.ends.to, "菁桐")
        XCTAssertEqual(card.trains, 3)
        print(card.sizeText(in: .traditionalChinese), card.timetableText(in: .traditionalChinese))

        // One command, logged as itself; it codes and decodes to itself.
        guard case .command(let command)? = session.commandLog.entries.last?.action, case .acquireRealLine = command else {
            return XCTFail("logged as a purchase")
        }
        let data = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: data), command)

        // Two days of the real timetable: each day every run goes.
        var world = session.world
        try world.advance(ticks: 2 * 24 * 60)
        let runDays = try XCTUnwrap(world.line(id: bought.line)?.runDays)
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        let missed = zip(line.runs, runDays).filter { run, day in
            run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
        }
        XCTAssertEqual(missed.count, 0, "runs not sent out yesterday: \(missed.count) of \(line.runs.count)")

        // Undo takes all of it back.
        session.undo()
        XCTAssertEqual(session.world, before)
    }

    /// Each line on sale, over the app's heights: bought, and two days of
    /// its real timetable run, every run sent out.
    func testEveryLineOnSaleIsBoughtOverTheRealGroundAndRunsItsDay() throws {
        for network in ["PINGXI", "SHENAO", "JIJI", "NEIWAN"] {
            let session = try game(round: network, side: 1 << 21, heights: true)
            let line = try line(network, in: session)
            let offer = session.realLineOffer(for: line)
            XCTAssertNil(offer.problem, network)
            guard let price = offer.price, let acquisition = offer.acquisition else { continue }
            print("\(network): building \(price.building.moneyText), trains \(price.trains.moneyText) (\(acquisition.trains.count)), riders \(price.riders.moneyText) (\(acquisition.dailyRiders) a day), total \(price.total.moneyText)")
            XCTAssertTrue(session.acquireRealLine(offer), "\(network): \(session.message?.text ?? "")")
            var world = session.world
            let bought = try XCTUnwrap(world.acquisition(of: line.id))
            try world.advance(ticks: 2 * 24 * 60)
            let runs = try XCTUnwrap(world.line(id: bought.line))
            let today = world.clock.now.seconds / GameTime.secondsPerDay
            let missed = zip(runs.runs, runs.runDays).filter { run, day in
                run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
            }
            XCTAssertEqual(missed.count, 0, "\(network): runs not sent out yesterday: \(missed.count) of \(runs.runs.count)")
        }
    }

    /// A line bought runs the company's trains: the map draws no real ones
    /// on it, and still those of the lines not bought.
    func testTheMapDrawsNoRealTrainsOnALineBought() throws {
        let operations = try XCTUnwrap(try BundledRealData.railways().operations)
        let all = RealTrainTraffic(operations: operations) { _ in true }
        let rest = RealTrainTraffic(operations: operations, bought: ["tra:PINGXI"]) { _ in true }
        XCTAssertTrue(all.lines.contains { $0.system == "tra" && $0.line.id == "PINGXI" })
        XCTAssertFalse(rest.lines.contains { $0.system == "tra" && $0.line.id == "PINGXI" })
        XCTAssertEqual(rest.lines.count, all.lines.count - 1)
    }

    /// Past the junction, the station card calls Taiwan Railway's riders
    /// the line's regulars; at the junction they still change from it.
    func testTheStationCardCallsTheRidersAlongALineBoughtItsRegulars() throws {
        let session = try game(round: "PINGXI", transfers: true)
        let offer = session.realLineOffer(for: try line("PINGXI", in: session))
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")
        let stops = try XCTUnwrap(session.world.line(id: try XCTUnwrap(session.world.acquisition(of: "tra:PINGXI")).line)?.stops)
        let shifen = try XCTUnwrap(stops.first { session.world.station(id: $0)?.name == "十分" })
        let text = try XCTUnwrap(session.transferText(of: shifen))
        XCTAssertTrue(text.hasPrefix("沿線的常客：每天約 "), text)
        let junction = try XCTUnwrap(session.transferText(of: stops[0]))
        XCTAssertTrue(junction.hasPrefix("從台鐵轉乘"), junction)
    }
}
