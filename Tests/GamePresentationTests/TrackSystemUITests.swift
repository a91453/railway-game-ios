import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 955: the network tool lays guideways (decision 951's
/// `TrackEdge.system`), and the train type menus list only what a line's
/// track carries.
final class TrackSystemUITests: XCTestCase {
    private static let reach: Int64 = 512

    private func world() throws -> GameWorld {
        try makeWorld(width: 32_768, height: 16_384, balance: 100_000_000, speed: .paused)
    }

    /// A guideway is elevated unless the player forced another structure;
    /// ordinary track gives the automatic choice back.
    @MainActor
    func testChoosingAGuidewayMakesItElevated() throws {
        let session = GameSession(world: try world())
        XCTAssertEqual(session.networkSystem, .conventional)
        XCTAssertEqual(session.networkStructure, .automatic)
        XCTAssertNil(session.networkSystemNote)
        session.chooseNetworkSystem(.straddle)
        XCTAssertEqual(session.networkSystem, .straddle)
        XCTAssertEqual(session.networkStructure, .elevated)
        XCTAssertEqual(
            session.networkSystemNote,
            "Only \(Train.typeText(.monorail, in: .english)) trains run on it, and it joins only the same guideway. It can't cross ordinary track on the level: go over or under it."
        )
        session.chooseNetworkSystem(.maglev)
        XCTAssertEqual(session.networkStructure, .elevated)
        session.chooseNetworkSystem(.conventional)
        XCTAssertEqual(session.networkStructure, .automatic)

        session.networkStructure = .tunnel
        session.chooseNetworkSystem(.suspended)
        XCTAssertEqual(session.networkStructure, .tunnel, "a forced structure stays")
        session.chooseNetworkSystem(.conventional)
        XCTAssertEqual(session.networkStructure, .tunnel)
        XCTAssertEqual(TrackSystem.offered, TrackSystem.allCases)
    }

    /// The tool lays the chosen guideway, its preview priced as GameCore
    /// prices it (the guideway's part apart), and the command log keeps the
    /// system.
    @MainActor
    func testTheToolLaysTheChosenGuidewayAtItsPrice() throws {
        let from = PlanPoint(x: 2_048, y: 8_192), to = PlanPoint(x: 12_288, y: 8_192)
        func previewed(_ system: TrackSystem) throws -> (session: GameSession, cost: Money) {
            let session = GameSession(world: try world())
            session.selectTool(.network)
            session.chooseNetworkSystem(system)
            session.networkStructure = .elevated
            session.tapNetwork(at: from, reach: Self.reach)
            session.tapNetwork(at: to, reach: Self.reach)
            let preview = try XCTUnwrap(session.networkPreview)
            XCTAssertNil(preview.problem, "\(system)")
            return (session, try XCTUnwrap(preview.cost))
        }
        let ordinary = try previewed(.conventional).cost
        for system in [TrackSystem.straddle, .maglev, .suspended] {
            let (session, cost) = try previewed(system)
            XCTAssertEqual(cost.amount, (ordinary.amount * system.costPermille + 500) / 1_000, "\(system)")
            if let parts = session.networkPreview?.costParts {
                XCTAssertEqual(parts.track.guideway, cost - ordinary, "\(system)")
                XCTAssertTrue(parts.lines(in: .traditionalChinese).contains { $0.name == "軌道梁" })
            }
            session.buildNetworkTrack()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
            let edge = try XCTUnwrap(session.world.network.edges.last)
            XCTAssertEqual(edge.system, system)
            XCTAssertEqual(edge.structure, .elevated)
            let commands = session.commandLog.entries.compactMap { entry -> PlayerCommand? in
                if case .command(let command) = entry.action { command } else { nil }
            }
            guard case .buildTrack(let stretch)? = commands.last else { return XCTFail("\(system)") }
            XCTAssertEqual(stretch.system, system)
        }
    }

    /// The command keeps its system in a log, and a log without one (from
    /// before decision 955) reads as following the track it joins.
    func testTheCommandKeepsItsSystem() throws {
        let stretch = PlayerCommand.TrackStretch(
            start: .point(PlanPoint(x: 0, y: 0)), end: .point(PlanPoint(x: 4_096, y: 0)),
            from: WorldCoordinate(x: 0, y: 0), to: WorldCoordinate(x: 4_096, y: 0), curve: .straight, profile: .uniform,
            structure: .elevated, ground: [], system: .maglev
        )
        let data = try JSONEncoder().encode(PlayerCommand.buildTrack(stretch))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"system\":\"maglev\""))
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: data), .buildTrack(stretch))

        let following = PlayerCommand.TrackStretch(
            start: stretch.start, end: stretch.end, from: stretch.from, to: stretch.to, curve: .straight, profile: .uniform,
            structure: .elevated, ground: []
        )
        let old = try JSONEncoder().encode(PlayerCommand.buildTrack(following))
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("system"))
        XCTAssertEqual(try JSONDecoder().decode(PlayerCommand.self, from: old), .buildTrack(following))
    }

    /// A guideway drawn across ordinary track on the level is refused
    /// before it is built, saying why and what to do.
    @MainActor
    func testAGuidewayCrossingOrdinaryTrackOnTheLevelIsExplained() throws {
        var world = try world()
        let north = try world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: 2_048))
        let south = try world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: 14_336))
        _ = try world.buildTrackEdge(from: north, to: south)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.chooseNetworkSystem(.straddle)
        session.networkStructure = .surface
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 8_192), reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: 14_336, y: 8_192), reach: Self.reach)
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertEqual(
            preview.problem,
            "A guideway and other track can't cross on the level. Make this stretch elevated or a tunnel to pass over or under it."
        )
        XCTAssertNil(preview.cost)

        // Ordinary track over the same place may cross at a diamond
        // (decision 887): no such note.
        session.chooseNetworkSystem(.conventional)
        XCTAssertNotEqual(session.networkPreview?.problem, preview.problem)
    }

    /// A line on a guideway lists only the guideway's trains, one on
    /// ordinary track none of the guideway trains; the line's default is
    /// the guideway's train.
    @MainActor
    func testTheTypeMenusListWhatTheLinesTrackCarries() throws {
        func line(on system: TrackSystem) throws -> (world: GameWorld, line: LineID, train: TrainID) {
            var world = try world()
            let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
            let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
            let edge = try world.buildTrackEdge(from: a, to: b, system: system)
            let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
            let east = try world.buildStation(named: "East", at: PlanPoint(x: 14_336, y: 8_704)).id
            try world.addTrackPlatform(west, on: edge, from: 1_024, to: 5_120)
            try world.addTrackPlatform(east, on: edge, from: 10_240, to: 14_336)
            let line = try world.createLine(named: "Line", stops: [west, east]).id
            let train = system == .straddle ? try world.purchaseTrain(named: "One", as: .monorail).id : try world.purchaseTrain(named: "One").id
            try world.assignTrain(train, to: line)
            return (world, line, train)
        }
        let beam = try line(on: .straddle)
        let session = GameSession(world: beam.world)
        let types = session.trainTypeMenuChoices(for: beam.train).map(\.id)
        XCTAssertEqual(types, [.monorail])
        XCTAssertEqual(session.trainTypeCardChoices(forLine: beam.line).map(\.id), [.monorail])
        XCTAssertEqual(beam.world.lineStaffingPlan(beam.line, headway: 10)?.type, .monorail)

        let rails = try line(on: .conventional)
        let ordinary = GameSession(world: rails.world)
        let guided: Set<TrainType?> = [.monorail, .maglev, .skyRail]
        XCTAssertTrue(ordinary.trainTypeMenuChoices(for: rails.train).allSatisfy { !guided.contains($0.id) })
        XCTAssertTrue(ordinary.trainTypeMenuChoices(for: rails.train).contains { $0.id == nil }, "the standard car")
        XCTAssertTrue(ordinary.trainTypeCardChoices(forLine: rails.line).allSatisfy { !guided.contains($0.id) })
        XCTAssertNil(rails.world.lineStaffingPlan(rails.line, headway: 10)?.type)

        // A train on no line is offered everything.
        var idle = rails.world
        let spare = try idle.purchaseTrain(named: "Spare").id
        XCTAssertTrue(GameSession(world: idle).trainTypeMenuChoices(for: spare).contains { $0.id == .maglev })
    }

    /// A train made a guideway train with no guideway laid yet is told to
    /// lay one first; once there is one, it is not.
    @MainActor
    func testAGuidewayTrainWithNoGuidewaySaysToLayOne() throws {
        var world = try world()
        let train = try world.purchaseTrain(named: "One").id
        let session = GameSession(world: world)
        session.selectTrain(train)
        session.setSelectedTrainType(.maglev)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.hasSuffix(" It runs only on its own guideway: lay one first, choosing Maglev guideway in the track tool.") == true,
                      session.message?.text ?? "")
        XCTAssertEqual(
            world.guidewayFirstHint(for: .maglev, in: .traditionalChinese),
            "它只能跑自己的軌道梁：請先在鋪軌工具選「磁浮軌道梁」蓋梁。"
        )
        XCTAssertNil(world.guidewayFirstHint(for: nil, in: .english))

        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 8_192, y: 8_192))
        _ = try world.buildTrackEdge(from: a, to: b, system: .maglev)
        XCTAssertNil(world.guidewayFirstHint(for: .maglev, in: .english))
        XCTAssertNotNil(world.guidewayFirstHint(for: .monorail, in: .english), "another guideway")
    }

    /// The network tool's double track lays both tracks as the chosen
    /// guideway, and a stretch drawn on from a guideway's end continues it.
    @MainActor
    func testADoubleGuidewayAndItsContinuationAreGuideways() throws {
        let session = GameSession(world: try world())
        session.selectTool(.network)
        session.chooseNetworkSystem(.maglev)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 8_192), reach: Self.reach)
        session.tapNetwork(at: PlanPoint(x: 12_288, y: 8_192), reach: Self.reach)
        XCTAssertNil(session.networkPreview?.problem)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertEqual(session.world.network.edges.count, 2)
        XCTAssertTrue(session.world.network.edges.allSatisfy { $0.system == .maglev })

        // Ordinary track from the guideway's end is refused, and said why.
        session.networkBuildsDouble = false
        session.chooseNetworkSystem(.conventional)
        session.tapNetwork(at: PlanPoint(x: 20_480, y: 8_192), reach: Self.reach)
        XCTAssertEqual(session.networkPreview?.refusal.map { if case .trackSystemMismatch = $0 { true } else { false } }, true)
        session.chooseNetworkSystem(.maglev)
        XCTAssertNil(session.networkPreview?.problem)
    }
}
