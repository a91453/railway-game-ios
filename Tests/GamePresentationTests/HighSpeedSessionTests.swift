import Foundation
import GameCore
import GamePresentation
import XCTest

/// High-speed rail in the session and its text (decision 168). A high-speed
/// line is not declared: it is a line planned at high speed, which the line
/// menu's "High-speed rail" makes, and so does a high-speed set put on a line
/// that runs nothing else.
@MainActor
final class HighSpeedSessionTests: XCTestCase {
    private static let alpha = StationID(rawValue: 1)
    private static let beta = StationID(rawValue: 2)
    private static let fast = LineID(rawValue: 1)
    private static let goods = LineID(rawValue: 2)

    private static func world() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 40_960, height: 4_096), economy: GameEconomy(balance: 100_000_000, costs: testCosts)
        )
        for (name, x) in [("Alpha", 2_048), ("Beta", 10_240)] as [(String, Int64)] {
            try world.buildStation(named: name, at: PlanPoint(x: x, y: 2_048))
        }
        try world.createLine(named: "Fast", stops: [alpha, beta])
        try world.createLine(named: "Goods", stops: [alpha, beta])
        world.enableFreight()
        try world.setLineFreight(goods, to: true)
        return world
    }

    func testAHighSpeedSetPutOnALineMakesItAHighSpeedLine() throws {
        var world = try Self.world()
        let train = try world.purchaseTrain(named: "N700").id
        let session = GameSession(world: world)
        session.selectTrain(train)
        session.setSelectedTrainType(.highSpeed)
        session.selectLine(Self.fast)
        XCTAssertEqual(session.world.line(id: Self.fast)?.performance, .standard)
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, false)

        session.assignSelectedTrainToSelectedLine()
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.line(id: Self.fast)?.performance, .highSpeed, "planned at PERF_HSR")
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, true)
        XCTAssertEqual(session.world.highSpeedStations, [Self.alpha, Self.beta])
        XCTAssertTrue(session.message?.text.contains("a high-speed line") ?? false, session.message?.text ?? "")

        // One edit: Undo takes the assignment and the performance back together.
        session.undo()
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, false)
        XCTAssertEqual(session.world.line(id: Self.fast)?.performance, .standard)
        XCTAssertNil(session.world.assignedLine(of: train))
        XCTAssertEqual(session.world.train(id: train)?.type, .highSpeed, "the set is still a set")
    }

    func testTheSetChosenAfterItIsOnTheLineDoesTheSame() throws {
        var world = try Self.world()
        let train = try world.purchaseTrain(named: "N700").id
        let session = GameSession(world: world)
        session.selectTrain(train)
        session.selectLine(Self.fast)
        session.assignSelectedTrainToSelectedLine()
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, false, "an ordinary train")

        session.setSelectedTrainType(.highSpeed)
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, true)
        XCTAssertTrue(session.message?.text.contains("a high-speed line") ?? false, session.message?.text ?? "")
        session.undo()
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, false)
        XCTAssertNil(session.world.train(id: train)?.type)
    }

    /// A line the player has already planned keeps its performance, and a
    /// line that runs other trains too is not a line of high-speed sets.
    func testALinePlannedByThePlayerOrRunByOtherTrainsStaysAsItIs() throws {
        var world = try Self.world()
        let set = try world.purchaseTrain(named: "N700").id
        try world.setTrainType(set, to: .highSpeed)
        let session = GameSession(world: world)

        // Planned as a Tze-Chiang express by the player: it stays one.
        session.selectLine(Self.fast)
        session.setSelectedLinePerformance(.express)
        session.selectTrain(set)
        session.assignSelectedTrainToSelectedLine()
        XCTAssertEqual(session.world.line(id: Self.fast)?.performance, .express)
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, false)

        // Back at the standard performance, with an ordinary train on it first.
        var other = try Self.world()
        let one = try other.purchaseTrain(named: "N700").id
        let two = try other.purchaseTrain(named: "Metro").id
        try other.setTrainType(one, to: .highSpeed)
        let mixed = GameSession(world: other)
        mixed.selectLine(Self.fast)
        mixed.selectTrain(two)
        mixed.assignSelectedTrainToSelectedLine()
        mixed.selectTrain(one)
        mixed.assignSelectedTrainToSelectedLine()
        XCTAssertEqual(mixed.world.line(id: Self.fast)?.trains, [one, two])
        XCTAssertEqual(mixed.world.line(id: Self.fast)?.isHighSpeed, false, "one of the two is an ordinary train")
    }

    /// "Run every five minutes" on a high-speed line buys high-speed sets.
    func testStaffingAHighSpeedLineBuysHighSpeedSets() throws {
        let track = TestLine(tiles: 9, row: 1)
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 100_000_000, speed: .normal)
        try track.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try track.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        let main = try world.createLine(named: "Main", stops: stops).id
        try world.setLineServiceWindow(main, to: .allDay)

        let plain = GameSession(world: world)
        plain.selectLine(main)
        plain.staffSelectedLine(headway: 5)
        XCTAssertEqual(plain.message?.kind, .success, plain.message?.text ?? "")
        XCTAssertTrue(plain.world.trains.allSatisfy { $0.type == nil && $0.performance == .standard }, "an ordinary line's trains are ordinary")

        try world.setLinePerformance(main, to: .highSpeed)
        let session = GameSession(world: world)
        session.selectLine(main)
        session.staffSelectedLine(headway: 5)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertFalse(session.world.trains.isEmpty)
        XCTAssertTrue(session.world.trains.allSatisfy { $0.type == .highSpeed && $0.performance == .highSpeed })
        XCTAssertEqual(session.undoCount, 1, "one edit")
    }

    func testAFreightLineIsNeverHighSpeed() throws {
        let session = GameSession(world: try Self.world())
        session.selectLine(Self.goods)
        session.setSelectedLinePerformance(.highSpeed)
        XCTAssertEqual(session.world.line(id: Self.goods)?.performance, .highSpeed)
        XCTAssertEqual(session.world.line(id: Self.goods)?.isHighSpeed, false, "freight is carried by the ton")
        XCTAssertEqual(session.world.highSpeedStations, [])
        XCTAssertNil(session.world.highSpeedLineText(Self.goods, in: .english))
    }

    func testTheLineSaysWhereItsTripsComeFrom() throws {
        var world = try Self.world()
        try world.setLinePerformance(Self.fast, to: .highSpeed)
        // The land sets nobody's ridership here, so the hinterlands are given.
        try world.setStationDemand(Self.alpha, to: StationDemand(kind: .office, dailyTrips: 0, hinterland: 3_652_324))
        try world.setStationDemand(Self.beta, to: StationDemand(kind: .residential, dailyTrips: 0, hinterland: 1_540_955))
        XCTAssertNil(world.highSpeedLineText(Self.goods, in: .english), "an ordinary line has none")
        XCTAssertEqual(world.highSpeedLineText(Self.fast, in: .english), "People within 8 km: Alpha 3,652,324 · Beta 1,540,955")
        XCTAssertEqual(world.highSpeedLineText(Self.fast, in: .traditionalChinese), "8 公里內的人口：Alpha 3,652,324 · Beta 1,540,955")
        let help = world.highSpeedLineHelp(in: .english)
        for part in ["$ 0.45 a kilometre", "network's fare", "8 km", "none under 10 km", "all from 80 km"] {
            XCTAssertTrue(help.contains(part), part)
        }
        XCTAssertTrue(world.highSpeedLineHelp(in: .traditionalChinese).contains("每公里 $ 0.45"))
    }

    func testAHighSpeedSetRunsAtHighSpeed() throws {
        var world = try Self.world()
        let train = try world.purchaseTrain(named: "N700").id
        let session = GameSession(world: world)
        session.selectTrain(train)
        XCTAssertEqual(session.world.train(id: train)?.performance, .standard)
        session.setSelectedTrainType(.highSpeed)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.train(id: train)?.type, .highSpeed)
        XCTAssertEqual(session.world.train(id: train)?.performance, .highSpeed, "PERF_HSR with the set")
        session.undo()
        XCTAssertNil(session.world.train(id: train)?.type)
        XCTAssertEqual(session.world.train(id: train)?.performance, .standard)

        // A train the player gave a performance keeps it; another type changes nothing of it.
        session.setSelectedTrainPerformance(.express)
        session.setSelectedTrainType(.highSpeed)
        XCTAssertEqual(session.world.train(id: train)?.performance, .express)
        session.setSelectedTrainType(.a)
        XCTAssertEqual(session.world.train(id: train)?.performance, .express)
    }

    func testTheHighSpeedSetIsOfferedAndNamed() throws {
        let world = try Self.world()
        XCTAssertTrue(world.offeredTrainTypes.contains(.highSpeed))
        XCTAssertEqual(TrainType.highSpeed.title(in: .english), "High-speed set")
        XCTAssertEqual(TrainType.highSpeed.title(in: .traditionalChinese), "高鐵列車")
        XCTAssertEqual(Train.typeText(.highSpeed, in: .english), "High-speed set · 80 a car · 2 doors")
        XCTAssertEqual(Train.typeText(.highSpeed, in: .traditionalChinese), "高鐵列車 · 每節 80 人 · 2 門")
    }
}
