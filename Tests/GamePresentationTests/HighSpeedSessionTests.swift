import Foundation
import GameCore
import GamePresentation
import XCTest

/// High-speed rail in the session and its text (decision 168): the switch goes
/// through GameCore's command, and the text is derived from the world.
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

    func testTheSessionMakesALineHighSpeedAndPlansItAtHighSpeed() throws {
        let session = GameSession(world: try Self.world())
        session.selectLine(Self.fast)
        XCTAssertEqual(session.world.line(id: Self.fast)?.performance, .standard)
        session.setSelectedLineHighSpeed(true)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, true)
        XCTAssertEqual(session.world.line(id: Self.fast)?.performance, .highSpeed, "planned at PERF_HSR")
        XCTAssertEqual(session.world.highSpeedStations, [Self.alpha, Self.beta])

        // One edit: Undo takes the switch and the performance back together.
        XCTAssertTrue(session.canUndo)
        session.undo()
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, false)
        XCTAssertEqual(session.world.line(id: Self.fast)?.performance, .standard)

        // A line the player gave a performance keeps it.
        session.setSelectedLinePerformance(.express)
        session.setSelectedLineHighSpeed(true)
        XCTAssertEqual(session.world.line(id: Self.fast)?.performance, .express)
        session.setSelectedLineHighSpeed(false)
        XCTAssertEqual(session.world.line(id: Self.fast)?.isHighSpeed, false)
        XCTAssertEqual(session.world.highSpeedStations, [])
    }

    func testAFreightLineCannotBeMadeHighSpeed() throws {
        let session = GameSession(world: try Self.world())
        session.selectLine(Self.goods)
        session.setSelectedLineHighSpeed(true)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertEqual(session.message?.text, GameError.lineIsFreight(Self.goods).playerMessage(in: session.language))
        XCTAssertEqual(session.world.line(id: Self.goods)?.isHighSpeed, false)

        session.selectLine(Self.fast)
        session.setSelectedLineHighSpeed(true)
        session.selectLine(Self.fast)
        session.setSelectedLineFreight(true)
        XCTAssertEqual(session.message?.text, GameError.lineIsHighSpeed(Self.fast).playerMessage(in: session.language))
    }

    func testTheLineSaysWhereItsTripsComeFrom() throws {
        var world = try Self.world()
        try world.setLineHighSpeed(Self.fast, to: true)
        // The land sets nobody's ridership here, so the hinterlands are given.
        try world.setStationDemand(Self.alpha, to: StationDemand(kind: .office, dailyTrips: 0, hinterland: 3_652_324))
        try world.setStationDemand(Self.beta, to: StationDemand(kind: .residential, dailyTrips: 0, hinterland: 1_540_955))
        XCTAssertNil(world.highSpeedLineText(Self.goods, in: .english), "an ordinary line has none")
        XCTAssertEqual(world.highSpeedLineText(Self.fast, in: .english), "People within 8 km: Alpha 3,652,324 · Beta 1,540,955")
        XCTAssertEqual(world.highSpeedLineText(Self.fast, in: .traditionalChinese), "8 公里內的人口：Alpha 3,652,324 · Beta 1,540,955")
        let help = world.highSpeedLineHelp(in: .english)
        for part in ["$ 20", "$ 0.45", "8 km", "none under 10 km", "all from 80 km"] {
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
