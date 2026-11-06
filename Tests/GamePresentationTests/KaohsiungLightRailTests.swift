import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 535 (continued, KLRT): the Kaohsiung Circular Light Rail on
/// sale, a ring with no terminal. It is laid round with a seam stretch
/// where the ring closes, its light rail depot inside the ring by the
/// real one past Lizihnei, every trainset standing there overnight, and
/// its trains going round each way across the seam.
@MainActor
final class KaohsiungLightRailTests: XCTestCase {
    static let id = "krtc:C"

    /// Bought with its depot: a ring, every trainset in the depot
    /// overnight, runs both ways, its route preferences ones a ring takes.
    func testTheRingIsBoughtWithItsRealDepot() throws {
        let session = try RealLineAcquisitionTests.game(round: Self.id, side: 1 << 21, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id }, "the light rail on sale")
        XCTAssertTrue(line.isRing)
        XCTAssertEqual(line.tier, .lightRail)
        let runs = try XCTUnwrap(session.railways?.metroRuns[Self.id])
        XCTAssertTrue(runs.ring)
        XCTAssertEqual(runs.stops.count, 38)
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        XCTAssertEqual(acquisition.ring, true)
        XCTAssertEqual(acquisition.depot?.platforms.count, RealLineDepotSite.klrt.sidings)
        XCTAssertEqual(acquisition.trains.count, runs.overnight.values.reduce(0, +))
        XCTAssertEqual(acquisition.runs.count, runs.runs.count)
        let price = try XCTUnwrap(offer.price)
        FileHandle.standardError.write(Data(
            "KLRT: building \(price.building.moneyText), trains \(price.trains.moneyText), riders \(price.riders.moneyText) (\(acquisition.dailyRiders) a day), total \(price.total.moneyText)\n".utf8
        ))
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let bought = try XCTUnwrap(world.lines.first)
        XCTAssertTrue(bought.isRing)
        XCTAssertEqual(Set(bought.runs.compactMap(\.way)), [.inner, .outer])
        XCTAssertTrue(bought.runs.allSatisfy { $0.way != nil })
        let depot = try XCTUnwrap(world.stations.first(where: \.isDepot))
        XCTAssertEqual(depot.name, "輕軌機廠")
        XCTAssertEqual(bought.depots, [depot.id])
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let real = WorldVector(frame.worldPosition(latitude: 22.6096, longitude: 120.3255))
        let away = (WorldVector(depot.location) - real).length / RealLineAcquisition.metre
        FileHandle.standardError.write(Data("KLRT depot \(Int(away)) m from the real yard's middle\n".utf8))
        XCTAssertLessThan(away, 400)
        let standing = world.trains.count { world.stationsStoppedAt(by: $0.id).contains(depot.id) }
        XCTAssertEqual(standing, acquisition.trains.count)
        XCTAssertEqual(bought.trains.count % 2, 0, "a ring's trains are even")
    }
}

/// Decision 535 (continued, KLRT): two real days under each rule, with
/// traffic control on and off: no deadlock, every run of the second day
/// sent out. A class of its own so CI can shard it.
@MainActor
final class KaohsiungLightRailDayTests: XCTestCase {
    func testTheRingRunsTwoRealDays() throws {
        for rules in [NewGameRules.simple, .realistic] {
            try DanhaiDepotTests.buyAndRun([KaohsiungLightRailTests.id], round: KaohsiungLightRailTests.id, rules: rules)
        }
    }

    func testTheRingRunsTwoRealDaysWithoutTrafficControl() throws {
        try DanhaiDepotTests.buyAndRun([KaohsiungLightRailTests.id], round: KaohsiungLightRailTests.id, rules: .simple, trafficControl: false)
    }
}

/// Decision 535 (continued, KLRT): run only with `KLRT_TRACE` set: the
/// ring bought and played minute by minute to the first deadlock, each
/// train in it described, for diagnosing.
@MainActor
final class KaohsiungLightRailTraceTests: XCTestCase {
    func testTraceTheFirstDeadlock() throws {
        guard let value = ProcessInfo.processInfo.environment["KLRT_TRACE"] else { throw XCTSkip("KLRT_TRACE") }
        let rules: NewGameRules = value == "realistic" ? .realistic : .simple
        let session = try RealLineAcquisitionTests.game(round: KaohsiungLightRailTests.id, side: 1 << 21, heights: true, rules: rules)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == KaohsiungLightRailTests.id })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        var world = session.world
        func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
        func nearest(_ train: Train) -> String {
            guard let position = train.position, let location = world.location(of: position) else { return "?" }
            let at = WorldVector(location.position.plan)
            let station = world.stations.min { (WorldVector($0.location) - at).length < (WorldVector($1.location) - at).length }
            let away = station.map { Int((WorldVector($0.location) - at).length / RealLineAcquisition.metre) } ?? -1
            return "\(station?.name ?? "?") \(away) m"
        }
        func describe(_ id: TrainID) -> String {
            guard let train = world.train(id: id) else { return "\(id)" }
            let heading = train.execution.flatMap { execution in
                train.timetable.indices.contains(execution.stop) ? world.station(id: train.timetable[execution.stop].station)?.name : nil
            } ?? "-"
            var edge = "-"
            if case .onEdge(let traversal, let offset) = train.position { edge = "\(traversal) @\(offset / 64) m" }
            return "\(train.name): near \(nearest(train)), \(edge), next \(heading) \(train.execution.map { "\($0)" } ?? "idle"), late \((world.lateness(of: id) ?? 0) / 60) min"
        }
        let snapshots = Set((ProcessInfo.processInfo.environment["KLRT_AT"] ?? "").split(separator: ",").compactMap { Int($0) })
        for minute in 0..<(51 * 60) {
            try world.advance(ticks: 1)
            if snapshots.contains(minute) {
                log("minute \(minute):")
                for train in world.trains {
                    let route = train.timetable.isEmpty ? "" : " [\(world.station(id: train.timetable[0].station)?.name ?? "?") \(train.timetable[0].departure.seconds / 60 % 1440) → \(world.station(id: train.timetable[train.timetable.count - 1].station)?.name ?? "?"), \(train.timetable.count) stops\(train.isDeadheading ? ", empty" : "")]"
                    log("  " + describe(train.id) + route)
                }
            }
            if let last = snapshots.max(), minute >= last { return }
            if ProcessInfo.processInfo.environment["KLRT_PAST"] != nil { continue }
            let stuck = world.deadlockedTrains()
            if !stuck.isEmpty {
                log("first deadlock at minute \(minute), \(world.clock.now.seconds % GameTime.secondsPerDay / 60) of the day: \(stuck.count) trains")
                for id in stuck { log("  " + describe(id)) }
                for train in world.trains where !stuck.contains(train.id) { log("  (other) " + describe(train.id)) }
                return
            }
        }
        log("no deadlock in 51 hours")
    }
}

/// Decision 535 (continued, KLRT): run only with `KLRT_LAPS` set (a rule
/// name, and `off` for traffic control off): each hour, how late the
/// line's trains in service run, the latest first, and which rule
/// switches the world has, for diagnosing the ring's delays.
@MainActor
final class KaohsiungLightRailLapTests: XCTestCase {
    func testHowLateEachHour() throws {
        guard let value = ProcessInfo.processInfo.environment["KLRT_LAPS"] else { throw XCTSkip("KLRT_LAPS") }
        let rules: NewGameRules = value.hasPrefix("realistic") ? .realistic : .simple
        let session = try RealLineAcquisitionTests.game(round: KaohsiungLightRailTests.id, side: 1 << 21, heights: true, rules: rules)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == KaohsiungLightRailTests.id })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        var world = session.world
        if value.hasSuffix("off") { try world.setTrafficControl(false) }
        func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
        for hour in 0..<30 {
            try world.advance(ticks: 60)
            let late = world.trains.compactMap { train in world.lateness(of: train.id).map { (train.name, $0 / 60) } }.sorted { $0.1 > $1.1 }
            log("hour \(hour + 1): " + late.prefix(8).map { "\($0.0.suffix(3)) \($0.1)" }.joined(separator: ", "))
        }
    }
}
