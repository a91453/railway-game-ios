import Foundation
@testable import GameCore
import XCTest

/// Decision 951: each edge's track system (ordinary track or the guideway
/// of a straddle monorail, a maglev or a suspended monorail), which train
/// runs on which, what a guideway costs and how fast it is run, and what a
/// save from before version 112 becomes.
final class TrackSystemTests: XCTestCase {
    private let line = LineID(rawValue: 1)

    private func makeWorld() throws -> GameWorld {
        try GameWorld(
            bounds: WorldBounds(width: 65_536, height: 65_536),
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500))
        )
    }

    private func refused(_ expected: GameError, in world: GameWorld, file: StaticString = #filePath, line: UInt = #line, _ body: (inout GameWorld) throws -> Void) {
        var copy = world
        do {
            try body(&copy)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? GameError, expected, file: file, line: line)
            XCTAssertEqual(copy, world, "a refused command changes nothing", file: file, line: line)
        }
    }

    private struct Built {
        var world: GameWorld
        let nodes: [TrackNodeID]
        let edges: [TrackEdgeID]
        let a: StationID
        let b: StationID
    }

    /// Three 64 m edges in a row at `y`, 8 m up on a viaduct, of `system`
    /// (`nil`: the default, ordinary track), station A on the first and B
    /// on the last, and a line A–B all day.
    private func build(_ system: TrackSystem?, y: Int64 = 2_048, in given: GameWorld? = nil, named name: String = "Line") throws -> Built {
        var world = try given ?? makeWorld()
        let nodes = try [2_048, 6_144, 10_240, 14_336].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: y, z: 512)) }
        let edges = try (0..<3).map { try world.buildTrackEdge(from: nodes[$0], to: nodes[$0 + 1], structure: .elevated, system: system) }
        let a = try world.buildStation(named: name + " A", at: PlanPoint(x: 4_096, y: y + 512)).id
        try world.addTrackPlatform(a, on: edges[0], from: 0, to: 4_096)
        let b = try world.buildStation(named: name + " B", at: PlanPoint(x: 12_288, y: y + 512)).id
        try world.addTrackPlatform(b, on: edges[2], from: 0, to: 4_096)
        let id = try world.createLine(named: name, stops: [a, b]).id
        try world.setLineServiceWindow(id, to: .allDay)
        try world.setLineTrainsInService(id, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        return Built(world: world, nodes: nodes, edges: edges, a: a, b: b)
    }

    private func start(_ built: Built) -> TrainPosition {
        .onEdge(TrackTraversal(edge: built.edges[0], direction: .forward), offset: 4_096)
    }

    // MARK: - Building

    func testAnEdgeIsOfTheSystemItIsBuiltAs() throws {
        let ordinary = try build(nil)
        XCTAssertEqual(ordinary.world.network.edges.map(\.system), [.conventional, .conventional, .conventional])
        XCTAssertEqual(ordinary.world.network.edges.map(\.kind), [.conventional, .conventional, .conventional])
        XCTAssertEqual(ordinary.world.network.edge(ordinary.edges[0])?.speedLimits, [])
        XCTAssertEqual(ordinary.world.trackKinds(ofLine: line), [.conventional])
        for (system, speed) in [(TrackSystem.straddle, Int64(80)), (.maglev, 100), (.suspended, 75)] {
            let built = try build(system)
            XCTAssertEqual(built.world.network.edges.map(\.system), [system, system, system])
            XCTAssertEqual(built.world.network.edge(built.edges[1])?.speedLimits, [TrackSpeedLimit(start: 0, end: 4_096, speed: speed)])
            XCTAssertEqual(built.world.trackKinds(ofLine: line), [TrackKind(system: system, mountain: false)])
            XCTAssertEqual(system.speedLimit, speed)
        }
        XCTAssertNil(TrackSystem.conventional.speedLimit)
    }

    func testAGuidewayCostsMoreThanOrdinaryTrackCarriedTheSameWay() throws {
        var world = try makeWorld()
        let from = WorldCoordinate(x: 2_048, y: 2_048, z: 512), to = WorldCoordinate(x: 6_144, y: 2_048, z: 512)
        let ordinary = try world.trackEdgePrice(from: from, to: to, structure: .elevated)
        // Four pricing lengths at 100, three times on a viaduct.
        XCTAssertEqual(ordinary, Money(1_200))
        XCTAssertEqual(try world.trackEdgePrice(from: from, to: to, structure: .elevated, system: .straddle), Money(1_440))
        XCTAssertEqual(try world.trackEdgePrice(from: from, to: to, structure: .elevated, system: .suspended), Money(1_560))
        XCTAssertEqual(try world.trackEdgePrice(from: from, to: to, structure: .elevated, system: .maglev), Money(1_920))
        XCTAssertEqual(try world.trackEdgePrice(from: from, to: to, structure: .elevated, system: .conventional), ordinary)
        XCTAssertEqual(TrackSystem.price(of: 1_001, on: .straddle).value, 1_201, "rounded half up")
        XCTAssertEqual(TrackSystem.price(of: 1_003, on: .straddle).value, 1_204)

        let nodes = try [from, to].map { try world.buildTrackNode(at: $0) }
        let before = world.economy.balance
        let edge = try world.buildTrackEdge(from: nodes[0], to: nodes[1], structure: .elevated, system: .maglev)
        XCTAssertEqual(before - world.economy.balance, Money(1_920), "charged what it quotes")
        XCTAssertEqual(world.network.edge(edge)?.system, .maglev)
    }

    func testAnEdgeTakesTheSystemOfTheTrackItJoins() throws {
        var built = try build(.straddle)
        let spur = try built.world.buildTrackNode(at: WorldCoordinate(x: 18_432, y: 2_048, z: 512))
        let joined = try built.world.buildTrackEdge(from: built.nodes[3], to: spur, structure: .elevated)
        XCTAssertEqual(built.world.network.edge(joined)?.system, .straddle)
        let far = try built.world.buildTrackNode(at: WorldCoordinate(x: 22_528, y: 2_048, z: 512))
        let more = try built.world.buildTrackEdges([TrackEdgePlan(from: far, to: spur, structure: .elevated)])
        XCTAssertEqual(built.world.network.edge(more[0])?.system, .straddle, "from the node it ends at too")
        // Track that joins nothing is ordinary track.
        let alone = try [30_720, 34_816].map { try built.world.buildTrackNode(at: WorldCoordinate(x: $0, y: 2_048)) }
        let apart = try built.world.buildTrackEdge(from: alone[0], to: alone[1])
        XCTAssertEqual(built.world.network.edge(apart)?.system, .conventional)
    }

    func testAGuidewayJoinsOnlyItsOwnSystem() throws {
        var built = try build(.straddle)
        let spur = try built.world.buildTrackNode(at: WorldCoordinate(x: 18_432, y: 2_048, z: 512))
        for other in [TrackSystem.conventional, .maglev, .suspended] {
            refused(.trackSystemMismatch(built.edges[2]), in: built.world) {
                _ = try $0.buildTrackEdge(from: built.nodes[3], to: spur, structure: .elevated, system: other)
            }
            refused(.trackSystemMismatch(built.edges[2]), in: built.world) {
                _ = try $0.buildTrackEdges([TrackEdgePlan(from: spur, to: built.nodes[3], structure: .elevated, system: other)])
            }
        }
        // Ordinary track refuses a guideway the same way.
        let ordinary = try build(nil, y: 8_192, in: built.world, named: "Ordinary")
        built.world = ordinary.world
        let end = try built.world.buildTrackNode(at: WorldCoordinate(x: 18_432, y: 8_192, z: 512))
        refused(.trackSystemMismatch(ordinary.edges[2]), in: built.world) {
            _ = try $0.buildTrackEdge(from: ordinary.nodes[3], to: end, structure: .elevated, system: .maglev)
        }
        // And the two never join through a new edge.
        refused(.trackSystemMismatch(ordinary.edges[2]), in: built.world) {
            _ = try $0.buildTrackEdge(from: built.nodes[3], to: ordinary.nodes[3], structure: .elevated)
        }
        // Mountain track is ordinary track.
        refused(.trackSystemMismatch(.edge(0)), in: built.world) {
            _ = try $0.buildTrackEdge(from: spur, to: end, structure: .elevated, mountain: true, system: .straddle)
        }
    }

    func testSplittingAGuidewayKeepsItsSystem() throws {
        var built = try build(.suspended)
        let node = try built.world.splitTrackEdge(built.edges[1], at: 2_048)
        let halves = built.world.network.edges.filter { $0.from == node || $0.to == node }
        XCTAssertEqual(halves.count, 2)
        XCTAssertEqual(halves.map(\.system), [.suspended, .suspended])
        XCTAssertEqual(halves.map(\.speedLimits), halves.map { [TrackSpeedLimit(start: 0, end: $0.length, speed: 75)] })
    }

    // MARK: - Trains

    func testTheTableOfTrainsAndTrack() {
        let rows: [(TrainType?, [TrackKind])] = [
            (nil, [.conventional]), (.a, [.conventional]), (.highSpeed, [.conventional]), (.alishan, [.conventional, .mountain]),
            (.monorail, [.straddle]), (.maglev, [.maglev]), (.skyRail, [.suspended]),
        ]
        for (type, kinds) in rows {
            for kind in TrackKind.allCases {
                XCTAssertEqual(TrackCompatibility.runs(type, on: kind), kinds.contains(kind), "\(type?.rawValue ?? "standard") on \(kind)")
            }
        }
        // Every other type runs on ordinary track.
        for type in TrainType.allCases where ![.monorail, .maglev, .skyRail].contains(type) {
            XCTAssertEqual(type.trackSystem, .conventional)
            XCTAssertTrue(TrackCompatibility.runs(type, on: .conventional))
        }
        XCTAssertEqual(TrackKind.allCases.map(\.system), [.conventional, .conventional, .straddle, .maglev, .suspended])
    }

    func testOnlyItsOwnTrainsRunOnAGuideway() throws {
        var built = try build(.straddle)
        let ordinary = try built.world.purchaseTrain(named: "Blue").id
        let maglev = try built.world.purchaseTrain(named: "Maglev", as: .maglev).id
        let monorail = try built.world.purchaseTrain(named: "Monorail", as: .monorail).id
        refused(.trainTrackMismatch(ordinary), in: built.world) { try $0.assignTrain(ordinary, to: line) }
        refused(.trainTrackMismatch(maglev), in: built.world) { try $0.assignTrain(maglev, to: line) }
        refused(.trainTrackMismatch(ordinary), in: built.world) { try $0.placeTrain(ordinary, at: start(built)) }
        refused(.trainTrackMismatch(maglev), in: built.world) { try $0.placeTrain(maglev, at: start(built)) }
        try built.world.assignTrain(monorail, to: line)
        // Unplaced, it may change type, but not to one of another system.
        refused(.trainTrackMismatch(monorail), in: built.world) { try $0.setTrainType(monorail, to: nil) }
        refused(.trainTrackMismatch(monorail), in: built.world) { try $0.setTrainType(monorail, to: .skyRail) }
        try built.world.placeTrain(monorail, at: start(built))
        try built.world.advance(ticks: 1_800)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(built.world)), built.world, "the world still loads")
    }

    func testAGuidewayTrainRunsNowhereElse() throws {
        var built = try build(nil)
        let monorail = try built.world.purchaseTrain(named: "Monorail", as: .monorail).id
        let ordinary = try built.world.purchaseTrain(named: "Blue", as: .a).id
        refused(.trainTrackMismatch(monorail), in: built.world) { try $0.assignTrain(monorail, to: line) }
        // With no guideway in the world, as with one.
        refused(.trainTrackMismatch(monorail), in: built.world) { try $0.placeTrain(monorail, at: start(built)) }
        try built.world.assignTrain(ordinary, to: line)
        refused(.trainTrackMismatch(ordinary), in: built.world) { try $0.setTrainType(ordinary, to: .monorail) }
        try built.world.setTrainType(ordinary, to: .b)
    }

    func testATrainIsNotSentByHandOntoAnotherSystem() throws {
        // A guideway and ordinary track side by side never join, so a way
        // from one onto the other does not exist; what is refused is a
        // train of the wrong system on the way itself.
        var built = try build(.maglev)
        let maglev = try built.world.purchaseTrain(named: "Maglev", as: .maglev).id
        try built.world.placeTrain(maglev, at: .onEdge(TrackTraversal(edge: built.edges[0], direction: .forward), offset: 2_048))
        try built.world.setTrainContinuation(maglev, along: [TrackTraversal(edge: built.edges[1], direction: .forward)])
    }

    func testALineMovedOntoAGuidewayKeepsOnlyItsTrains() throws {
        var world = try makeWorld()
        let nodes = try [2_048, 6_144, 10_240, 14_336].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: 2_048, z: 512)) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1], structure: .elevated, system: .straddle)
        let last = try world.buildTrackEdge(from: nodes[2], to: nodes[3], structure: .elevated, system: .straddle)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 4_096, y: 2_560)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 12_288, y: 2_560)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.createLine(named: "Monorail", stops: [a, b])
        // A and B are not joined yet: the line runs on nothing, and any
        // train may be given it.
        XCTAssertEqual(world.trackKinds(ofLine: line), [])
        let ordinary = try world.purchaseTrain(named: "Blue").id
        let maglev = try world.purchaseTrain(named: "Maglev", as: .maglev).id
        let monorail = try world.purchaseTrain(named: "Monorail", as: .monorail).id
        for train in [ordinary, maglev, monorail] { try world.assignTrain(train, to: line) }

        _ = try world.buildTrackEdge(from: nodes[1], to: nodes[2], structure: .elevated)
        XCTAssertEqual(world.trackKinds(ofLine: line), [.straddle])
        XCTAssertEqual(world.line(id: line)?.trains, [monorail], "the trains of other systems are taken off")
        XCTAssertNil(world.assignedLine(of: ordinary))
        XCTAssertNil(world.assignedLine(of: maglev))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world, "the world still loads")
    }

    // MARK: - Saving

    func testASystemIsSavedOnlyForAGuideway() throws {
        let built = try build(.maglev)
        let world = try build(nil, y: 8_192, in: built.world, named: "Ordinary").world
        let text = String(decoding: try JSONEncoder().encode(world), as: UTF8.self)
        XCTAssertEqual(text.components(separatedBy: "\"system\":\"maglev\"").count, 4, "the three guideway edges say so")
        XCTAssertFalse(text.contains("\"system\":\"conventional\""))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8)), world)

        let plain = String(decoding: try JSONEncoder().encode(try build(nil).world), as: UTF8.self)
        XCTAssertFalse(plain.contains("\"system\""), "a world with no guideway reads as before decision 951")
    }

    func testASaveThatBreaksTheRulesIsRejected() throws {
        let built = try build(.maglev)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(built.world)) as? [String: Any])
        // The world with its edges' objects changed by `change` (the
        // edge's number, its object): whether it loads.
        func loads(_ change: (Int, inout [String: Any]) -> Void) throws -> Bool {
            var object = object
            var network = try XCTUnwrap(object["network"] as? [String: Any])
            var edges = try XCTUnwrap(network["edges"] as? [[String: Any]])
            for index in edges.indices { change(try XCTUnwrap(edges[index]["id"] as? Int), &edges[index]) }
            network["edges"] = edges
            object["network"] = network
            return (try? JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))) != nil
        }
        XCTAssertTrue(try loads { _, _ in })
        XCTAssertTrue(try loads { _, edge in XCTAssertEqual(edge["system"] as? String, "maglev") })
        XCTAssertFalse(try loads { id, edge in if id == 2 { edge["system"] = "straddle" } }, "two systems at a node")
        XCTAssertFalse(try loads { id, edge in if id == 2 { edge["system"] = nil } }, "a guideway joined to ordinary track")
        XCTAssertFalse(try loads { _, edge in edge["system"] = "conventional" }, "ordinary track writes no system")
        XCTAssertFalse(try loads { _, edge in edge["system"] = "rubber" }, "an unknown system")
        XCTAssertFalse(try loads { _, edge in edge["mountain"] = true }, "mountain track on a guideway")
    }

    // MARK: - Saves from before version 112

    /// `world` as version 111 wrote it, with every train of type `A`
    /// whose name is in `types` made that type: before version 112 any
    /// train ran on any track, which no command of this build does.
    private func versionOneEleven(_ world: GameWorld, retyping types: [String: TrainType]) throws -> Data {
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
        for index in trains.indices {
            guard let name = trains[index]["name"] as? String, let type = types[name] else { continue }
            XCTAssertEqual(trains[index]["type"] as? String, "A")
            trains[index]["type"] = type.rawValue
        }
        object["trains"] = trains
        return try JSONSerialization.data(withJSONObject: ["saveVersion": 111, "world": object], options: [.sortedKeys])
    }

    func testAnOldLineOfGuidewayTrainsBecomesTheirGuideway() throws {
        // Two lines apart: the first run by two trains to be monorails,
        // one of them out on the line, the second by an ordinary train.
        var built = try build(nil)
        let ordinary = try build(nil, y: 8_192, in: built.world, named: "Ordinary")
        built.world = ordinary.world
        let one = try built.world.purchaseTrain(named: "One", as: .a).id
        let two = try built.world.purchaseTrain(named: "Two", as: .a).id
        let blue = try built.world.purchaseTrain(named: "Blue", as: .a).id
        try built.world.assignTrain(one, to: line)
        try built.world.assignTrain(two, to: line)
        try built.world.placeTrain(one, at: start(built))
        try built.world.assignTrain(blue, to: LineID(rawValue: 2))
        try built.world.placeTrain(blue, at: start(ordinary))
        try built.world.advance(ticks: 900)

        let data = try versionOneEleven(built.world, retyping: ["One": .monorail, "Two": .monorail])
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(built.edges.map { loaded.network.edge($0)?.system }, [.straddle, .straddle, .straddle])
        XCTAssertEqual(ordinary.edges.map { loaded.network.edge($0)?.system }, [.conventional, .conventional, .conventional])
        XCTAssertEqual(loaded.network.edge(built.edges[1])?.speedLimits.map(\.speed), [80])
        XCTAssertEqual(loaded.line(id: line)?.trains, [one, two])
        XCTAssertEqual(loaded.economy, built.world.economy, "nothing is charged")
        // It saves as version 112, loads the same, and runs on.
        let saved = try JSONEncoder().encode(SavedGame(world: loaded))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: saved).world, loaded)
        try loaded.advance(ticks: 3_600)
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: loaded))).world, loaded)
        XCTAssertEqual(loaded.assignedLine(of: blue), LineID(rawValue: 2))
        let green = try loaded.purchaseTrain(named: "Green", as: .a).id
        refused(.trainTrackMismatch(green), in: loaded) { world in try world.assignTrain(green, to: line) }
    }

    func testOldTrackGuidewayTrainsShareStaysOrdinaryTrack() throws {
        // One line run by a monorail and an ordinary train together.
        var built = try build(nil)
        let mono = try built.world.purchaseTrain(named: "Mono", as: .a).id
        let blue = try built.world.purchaseTrain(named: "Blue", as: .a).id
        try built.world.assignTrain(mono, to: line)
        try built.world.assignTrain(blue, to: line)
        try built.world.placeTrain(mono, at: start(built))
        try built.world.advance(ticks: 900)
        let data = try versionOneEleven(built.world, retyping: ["Mono": .monorail])
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.network.edges.map(\.system), [.conventional, .conventional, .conventional])
        XCTAssertEqual(loaded.line(id: line)?.trains, [mono, blue], "the monorail stays on its line")
        // It runs on as it did, through edits too, and may be put back on
        // the track by hand while its line holds it.
        try loaded.advance(ticks: 3_600)
        _ = try loaded.buildTrackNode(at: WorldCoordinate(x: 30_720, y: 30_720))
        try loaded.renameLine(line, to: "Shared")
        XCTAssertEqual(loaded.line(id: line)?.trains, [mono, blue])
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: loaded))).world, loaded)
        // Taken off, it does not come back.
        try loaded.unassignTrain(mono)
        refused(.trainTrackMismatch(mono), in: loaded) { try $0.assignTrain(mono, to: line) }
    }

    func testOldTrackJoinedToAnOrdinaryLinesStaysOrdinaryTrack() throws {
        // The monorail's line and an ordinary line on one piece of track:
        // the second line's edges carry on from the first's.
        var built = try build(nil)
        let more = try [18_432, 22_528].map { try built.world.buildTrackNode(at: WorldCoordinate(x: $0, y: 2_048, z: 512)) }
        let link = try built.world.buildTrackEdge(from: built.nodes[3], to: more[0], structure: .elevated)
        let far = try built.world.buildTrackEdge(from: more[0], to: more[1], structure: .elevated)
        let c = try built.world.buildStation(named: "C", at: PlanPoint(x: 20_480, y: 2_560)).id
        try built.world.addTrackPlatform(c, on: far, from: 0, to: 4_096)
        let second = try built.world.createLine(named: "On", stops: [built.b, c]).id
        let mono = try built.world.purchaseTrain(named: "Mono", as: .a).id
        let blue = try built.world.purchaseTrain(named: "Blue", as: .a).id
        try built.world.assignTrain(mono, to: line)
        try built.world.assignTrain(blue, to: second)
        let data = try versionOneEleven(built.world, retyping: ["Mono": .monorail])
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual((built.edges + [link, far]).map { loaded.network.edge($0)?.system }, Array(repeating: .conventional, count: 5))
        XCTAssertEqual(loaded.line(id: line)?.trains, [mono])

        // With no train on the second line, the whole piece is the
        // monorail's, its spur too.
        var alone = built.world
        try alone.unassignTrain(blue)
        let turned = try JSONDecoder().decode(SavedGame.self, from: versionOneEleven(alone, retyping: ["Mono": .monorail])).world
        XCTAssertEqual((built.edges + [link, far]).map { turned.network.edge($0)?.system }, Array(repeating: .straddle, count: 5))
        // But not with a train of another system standing on it.
        try alone.placeTrain(blue, at: .onEdge(TrackTraversal(edge: far, direction: .forward), offset: 2_048))
        let stood = try JSONDecoder().decode(SavedGame.self, from: versionOneEleven(alone, retyping: ["Mono": .monorail])).world
        XCTAssertEqual(stood.network.edges.map(\.system), Array(repeating: .conventional, count: 5))
    }

    func testAVersion112SaveIsNotTurned() throws {
        // What version 112 wrote is kept: ordinary track a line of
        // guideway trains still runs on stays ordinary track.
        var built = try build(nil)
        let mono = try built.world.purchaseTrain(named: "Mono", as: .a).id
        try built.world.assignTrain(mono, to: line)
        let old = try versionOneEleven(built.world, retyping: ["Mono": .monorail])
        let text = String(decoding: old, as: UTF8.self).replacingOccurrences(of: "\"saveVersion\":111", with: "\"saveVersion\":112")
        let loaded = try JSONDecoder().decode(SavedGame.self, from: Data(text.utf8)).world
        XCTAssertEqual(loaded.network.edges.map(\.system), [.conventional, .conventional, .conventional])
    }

    /// The version 112 save (decision 951): a straddle beam with a
    /// monorail running its line beside ordinary track with an ordinary
    /// train on its own, run 30 minutes; it loads as the same world and
    /// runs on the same. Written with `TRACK_SYSTEM_SAVE_NEW=1` by the
    /// build that first made it.
    func testTheVersion112SaveKeepsItsGuideway() throws {
        var built = try build(.straddle)
        let ordinary = try build(nil, y: 8_192, in: built.world, named: "Ordinary")
        built.world = ordinary.world
        let monorail = try built.world.purchaseTrain(named: "Monorail", as: .monorail).id
        let blue = try built.world.purchaseTrain(named: "Blue", as: .a).id
        try built.world.assignTrain(monorail, to: line)
        try built.world.placeTrain(monorail, at: start(built))
        try built.world.assignTrain(blue, to: LineID(rawValue: 2))
        try built.world.placeTrain(blue, at: start(ordinary))
        try built.world.advance(ticks: 1_800)
        let world = built.world
        let url = SavedGameTests.fixtures.appendingPathComponent("v112-track-system.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["TRACK_SYSTEM_SAVE_NEW"] != nil, SavedGame.currentVersion == 112 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 112)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(built.edges.map { loaded.network.edge($0)?.system }, [.straddle, .straddle, .straddle])
        XCTAssertEqual(ordinary.edges.map { loaded.network.edge($0)?.system }, [.conventional, .conventional, .conventional])
        XCTAssertEqual(loaded.train(id: monorail)?.type, .monorail)
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 600)
        try running.advance(ticks: 600)
        XCTAssertEqual(loaded, running)
    }
}
