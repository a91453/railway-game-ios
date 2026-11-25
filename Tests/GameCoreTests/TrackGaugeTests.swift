import Foundation
@testable import GameCore
import XCTest

/// Decision 970: each ordinary edge's gauge (its rails, 762, 1,067, 1,435
/// or 1,524 mm, and its loading gauge, conventional or the Shinkansen's),
/// which real train runs on which, and what a save from before version 114
/// becomes.
final class TrackGaugeTests: XCTestCase {
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
        let line: LineID
    }

    /// Three 64 m edges in a row at `y` of `gauge` (`nil`: the default,
    /// or that of the track it joins), station A on the first and B on the
    /// last, and a line A–B all day.
    private func build(_ gauge: TrackGauge?, y: Int64 = 2_048, in given: GameWorld? = nil, named name: String = "Line") throws -> Built {
        var world = try given ?? makeWorld()
        let nodes = try [2_048, 6_144, 10_240, 14_336].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: y)) }
        let edges = try (0..<3).map { try world.buildTrackEdge(from: nodes[$0], to: nodes[$0 + 1], gauge: gauge) }
        let a = try world.buildStation(named: name + " A", at: PlanPoint(x: 4_096, y: y + 512)).id
        try world.addTrackPlatform(a, on: edges[0], from: 0, to: 4_096)
        let b = try world.buildStation(named: name + " B", at: PlanPoint(x: 12_288, y: y + 512)).id
        try world.addTrackPlatform(b, on: edges[2], from: 0, to: 4_096)
        let id = try world.createLine(named: name, stops: [a, b]).id
        try world.setLineServiceWindow(id, to: .allDay)
        try world.setLineTrainsInService(id, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        return Built(world: world, nodes: nodes, edges: edges, line: id)
    }

    private func start(_ built: Built) -> TrainPosition {
        .onEdge(TrackTraversal(edge: built.edges[0], direction: .forward), offset: 4_096)
    }

    // MARK: - Which train runs on which track

    func testTheTableOfWheelsAndRails() {
        // 在來線: the Taiwan Railway's and Japan's conventional lines.
        XCTAssertTrue(TrainGauge.cape.runs(on: .cape))
        XCTAssertFalse(TrainGauge.cape.runs(on: .standard))
        XCTAssertFalse(TrainGauge.cape.runs(on: .shinkansen), "a Taiwan Railway train does not share the high-speed railway's track")
        // 新幹線: its wide cars only on track built for them.
        XCTAssertTrue(TrainGauge.shinkansen.runs(on: .shinkansen))
        XCTAssertFalse(TrainGauge.shinkansen.runs(on: .standard), "a Shinkansen car is too wide for a conventional line of 1,435 mm")
        XCTAssertFalse(TrainGauge.shinkansen.runs(on: .cape))
        // ミニ新幹線: a 1,435 mm car of the conventional loading gauge runs
        // on the Shinkansen and on the regauged Yamagata and Akita lines.
        XCTAssertTrue(TrainGauge.standard.runs(on: .shinkansen))
        XCTAssertTrue(TrainGauge.standard.runs(on: .standard))
        XCTAssertFalse(TrainGauge.standard.runs(on: .cape))
        // 林鐵 and Finland.
        XCTAssertTrue(TrainGauge.forest.runs(on: .forest))
        XCTAssertFalse(TrainGauge.forest.runs(on: .cape))
        XCTAssertFalse(TrainGauge(.broad).runs(on: .cape))
        // A third rail carries both.
        let threeRail = TrackGauge(rails: [.cape, .standard], loading: .shinkansen)
        XCTAssertTrue(TrainGauge.cape.runs(on: threeRail))
        XCTAssertTrue(TrainGauge.shinkansen.runs(on: threeRail))
    }

    func testTheRealModelsHaveTheirRealGauges() {
        XCTAssertEqual(TrainType.highSpeed.gauge, .shinkansen)
        XCTAssertEqual(TrainType.alishan.gauge, .forest)
        XCTAssertEqual(TrainType.c381.gauge, .standard)
        for type in [TrainType.puyuma, .taroko, .emu3000, .emu800, .pushPull, .dr3100, .steam, .blueTrain] {
            XCTAssertEqual(type.gauge, .cape, "\(type.rawValue)")
        }
        // The reference's types and the standard car are of no real model.
        for type in [TrainType.a, .b, .c, .l, .d, .apm] { XCTAssertNil(type.gauge) }
        XCTAssertTrue(TrackCompatibility.runs(nil, onGauge: .cape))
        XCTAssertTrue(TrackCompatibility.runs(.a, onGauge: .shinkansen))
        XCTAssertFalse(TrackCompatibility.runs(.a, onGauge: .forest), "only the forest railway's trains run on 762 mm")
    }

    func testARealLinesGauge() {
        XCTAssertEqual(TrackGauge.ofRealLine("tra:PINGXI"), .cape)
        XCTAssertEqual(TrackGauge.ofRealLine("thsr_sched"), .shinkansen)
        XCTAssertEqual(TrackGauge.ofRealLine("afr:MAIN"), .forest)
        XCTAssertEqual(TrackGauge.ofRealLine("trtc:BL"), .standard)
        XCTAssertEqual(TrackGauge.ofRealLine("hkmtr:TCL"), .standard)
        XCTAssertEqual(TrackGauge.ofRealLine("vr:R"), .broad)
        XCTAssertEqual(TrackGauge.ofRealLine("fksubway:N"), .standard, "the Nanakuma Line")
        XCTAssertEqual(TrackGauge.ofRealLine("fksubway:K"), .cape, "the Kūkō Line")
        XCTAssertNil(TrackGauge.ofRealLine("nowhere:X"))
    }

    func testACodeNamesAGauge() {
        for gauge in TrackGauge.offered + [TrackGauge(rails: [.forest, .cape])] {
            XCTAssertEqual(TrackGauge(code: gauge.code), gauge, gauge.code)
        }
        XCTAssertEqual(TrackGauge.cape.code, "1067")
        XCTAssertEqual(TrackGauge.shinkansen.code, "1435s")
        XCTAssertNil(TrackGauge(code: ""))
        XCTAssertNil(TrackGauge(code: "1000"))
    }

    // MARK: - Building

    func testAnEdgeIsOfTheGaugeItIsBuiltAtOrJoins() throws {
        let plain = try build(nil)
        XCTAssertEqual(plain.world.network.edges.map(\.gauge), [.cape, .cape, .cape], "1,067 mm unless asked")
        var built = try build(.shinkansen)
        XCTAssertEqual(built.world.network.edges.map(\.gauge), [.shinkansen, .shinkansen, .shinkansen], "the second edge on joins the first")
        // Track laid on from its end takes its gauge; asked, its own.
        let far = try built.world.buildTrackNode(at: WorldCoordinate(x: 18_432, y: 2_048))
        let on = try built.world.buildTrackEdge(from: built.nodes[3], to: far)
        XCTAssertEqual(built.world.network.edge(on)?.gauge, .shinkansen)
        let farther = try built.world.buildTrackNode(at: WorldCoordinate(x: 22_528, y: 2_048))
        let other = try built.world.buildTrackEdge(from: far, to: farther, gauge: .cape)
        XCTAssertEqual(built.world.network.edge(other)?.gauge, .cape)
        // Split, both halves keep it.
        let middle = try built.world.splitTrackEdge(built.edges[1], at: 2_048)
        XCTAssertTrue(built.world.network.edges.filter { $0.from == middle || $0.to == middle }.allSatisfy { $0.gauge == .shinkansen })
    }

    func testAGuidewayHasNoGauge() throws {
        var world = try makeWorld()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048, z: 512))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048, z: 512))
        let edge = try world.buildTrackEdge(from: a, to: b, structure: .elevated, system: .straddle, gauge: .forest)
        XCTAssertEqual(world.network.edge(edge)?.gauge, .default)
    }

    // MARK: - Running

    func testOnlyTrainsOfItsGaugeRunOnALine() throws {
        var built = try build(.shinkansen)
        let puyuma = try built.world.purchaseTrain(named: "Puyuma", as: .puyuma).id
        refused(.trainGaugeMismatch(puyuma), in: built.world) { try $0.assignTrain(puyuma, to: built.line) }
        refused(.trainGaugeMismatch(puyuma), in: built.world) { try $0.placeTrain(puyuma, at: start(built)) }
        let hsr = try built.world.purchaseTrain(named: "700T", as: .highSpeed).id
        try built.world.assignTrain(hsr, to: built.line)
        try built.world.placeTrain(hsr, at: start(built))
        // A type of no real model runs on any gauge but the forest's.
        let car = try built.world.purchaseTrain(named: "Car").id
        try built.world.assignTrain(car, to: built.line)
        XCTAssertTrue(built.world.fitsGauge(nil, ofLine: built.line))
        XCTAssertFalse(built.world.fitsGauge(.puyuma, ofLine: built.line))
        XCTAssertEqual(built.world.trackGauges(ofLine: built.line), [.shinkansen])
    }

    func testAShinkansenTrainDoesNotFitAConventionalStandardGaugeLine() throws {
        var built = try build(.standard)
        let hsr = try built.world.purchaseTrain(named: "700T", as: .highSpeed).id
        refused(.trainGaugeMismatch(hsr), in: built.world) { try $0.assignTrain(hsr, to: built.line) }
        let metro = try built.world.purchaseTrain(named: "C381", as: .c381).id
        try built.world.assignTrain(metro, to: built.line)
    }

    func testATrainOnALineKeepsToItsGaugeWhenRefitted() throws {
        var built = try build(nil)
        let train = try built.world.purchaseTrain(named: "Puyuma", as: .puyuma).id
        try built.world.assignTrain(train, to: built.line)
        refused(.trainGaugeMismatch(train), in: built.world) { try $0.setTrainType(train, to: .highSpeed) }
        try built.world.setTrainType(train, to: .taroko)
    }

    func testAnAlishanTrainRunsOnlyOnForestTrack() throws {
        var built = try build(nil)
        let alishan = try built.world.purchaseTrain(named: "Alishan", as: .alishan).id
        refused(.trainGaugeMismatch(alishan), in: built.world) { try $0.placeTrain(alishan, at: start(built)) }
        refused(.trainGaugeMismatch(alishan), in: built.world) { try $0.assignTrain(alishan, to: built.line) }
        let forest = try build(.forest, y: 8_192, in: built.world, named: "Forest")
        built.world = forest.world
        try built.world.assignTrain(alishan, to: forest.line)
        try built.world.placeTrain(alishan, at: start(forest))
        let car = try built.world.purchaseTrain(named: "Car").id
        refused(.trainGaugeMismatch(car), in: built.world) { try $0.assignTrain(car, to: forest.line) }
    }

    func testALineMovedOntoAnotherGaugeKeepsOnlyItsTrains() throws {
        // Two pieces of track not yet joined, one of 1,067 mm and one of
        // 1,435 mm high-speed: the line A–B has no way through yet.
        var world = try makeWorld()
        let nodes = try [2_048, 6_144, 10_240, 14_336].map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: 2_048)) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1], gauge: .cape)
        let last = try world.buildTrackEdge(from: nodes[2], to: nodes[3], gauge: TrackGauge(rails: [.cape, .standard], loading: .shinkansen))
        let a = try world.buildStation(named: "A", at: PlanPoint(x: 4_096, y: 2_560)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: 12_288, y: 2_560)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.createLine(named: "Line", stops: [a, b])
        let puyuma = try world.purchaseTrain(named: "Puyuma", as: .puyuma).id
        let hsr = try world.purchaseTrain(named: "700T", as: .highSpeed).id
        try world.assignTrain(puyuma, to: line)
        try world.assignTrain(hsr, to: line)
        _ = try world.buildTrackEdge(from: nodes[1], to: nodes[2], gauge: .cape)
        XCTAssertEqual(world.line(id: line)?.trains, [puyuma], "the train too wide for the 1,067 mm stretch is taken off")
        XCTAssertNil(world.assignedLine(of: hsr))
    }

    // MARK: - Saving

    func testAGaugeIsSavedOnlyWhereItIsNotTheDefault() throws {
        let plain = try build(nil)
        let text = String(decoding: try JSONEncoder().encode(plain.world), as: UTF8.self)
        XCTAssertFalse(text.contains("\"gauge\""), "1,067 mm track writes nothing, as every save before")
        var built = try build(.shinkansen)
        let other = try build(TrackGauge(rails: [.forest, .cape]), y: 8_192, in: built.world, named: "Three")
        built.world = other.world
        let saved = String(decoding: try JSONEncoder().encode(built.world), as: UTF8.self)
        XCTAssertEqual(saved.components(separatedBy: #""gauge":{"#).count - 1, 6)
        XCTAssertTrue(saved.contains(#""loading":"shinkansen""#))
        XCTAssertTrue(saved.contains(#""rails":[762,1067]"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(built.world)), built.world)
    }

    // MARK: - Saves from before version 114

    /// `world` as version 112 wrote it: no edge says its gauge, and every
    /// train of type `A` whose name is in `types` made that type, as an
    /// older build let any train run on any ordinary track.
    private func versionOneTwelve(_ world: GameWorld, retyping types: [String: TrainType]) throws -> Data {
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var trains = try XCTUnwrap(object["trains"] as? [[String: Any]])
        for index in trains.indices {
            guard let name = trains[index]["name"] as? String, let type = types[name] else { continue }
            XCTAssertEqual(trains[index]["type"] as? String, "A")
            trains[index]["type"] = type.rawValue
        }
        object["trains"] = trains
        let text = String(decoding: try JSONSerialization.data(withJSONObject: ["saveVersion": 112, "world": object], options: [.sortedKeys]), as: UTF8.self)
        XCTAssertFalse(text.contains("\"gauge\""))
        return Data(text.utf8)
    }

    func testAnOldLineTakesTheGaugeOfItsTrains() throws {
        // Three lines apart: one run by a high-speed train standing on it,
        // one by an Alishan train and a Puyuma together (once any train ran
        // anywhere), and one by the standard car.
        var built = try build(nil)
        let mixed = try build(nil, y: 8_192, in: built.world, named: "Mixed")
        let plain = try build(nil, y: 14_336, in: mixed.world, named: "Plain")
        built.world = plain.world
        let hsr = try built.world.purchaseTrain(named: "HSR", as: .a).id
        let alishan = try built.world.purchaseTrain(named: "Alishan", as: .a).id
        let puyuma = try built.world.purchaseTrain(named: "Puyuma", as: .a).id
        let car = try built.world.purchaseTrain(named: "Car").id
        try built.world.assignTrain(hsr, to: built.line)
        try built.world.placeTrain(hsr, at: start(built))
        try built.world.assignTrain(alishan, to: mixed.line)
        try built.world.assignTrain(puyuma, to: mixed.line)
        try built.world.assignTrain(car, to: plain.line)
        try built.world.advance(ticks: 600)

        let data = try versionOneTwelve(built.world, retyping: ["HSR": .highSpeed, "Alishan": .alishan, "Puyuma": .puyuma])
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(built.edges.map { loaded.network.edge($0)?.gauge }, [.shinkansen, .shinkansen, .shinkansen])
        XCTAssertEqual(mixed.edges.map { loaded.network.edge($0)?.gauge }, Array(repeating: TrackGauge(rails: [.forest, .cape]), count: 3),
                       "a third rail, so that neither train is stranded")
        XCTAssertEqual(plain.edges.map { loaded.network.edge($0)?.gauge }, [.cape, .cape, .cape])
        XCTAssertEqual(loaded.line(id: built.line)?.trains, [hsr])
        XCTAssertEqual(loaded.line(id: mixed.line)?.trains, [alishan, puyuma])
        XCTAssertEqual(loaded.economy, built.world.economy, "nothing is charged")
        // It saves as this version, loads the same, and runs on.
        let saved = try JSONEncoder().encode(SavedGame(world: loaded))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: saved).world, loaded)
        try loaded.advance(ticks: 1_800)
        XCTAssertEqual(loaded.line(id: mixed.line)?.trains, [alishan, puyuma])
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: loaded))).world, loaded)
    }

    func testAVersion114SaveIsNotTurned() throws {
        var built = try build(nil)
        let hsr = try built.world.purchaseTrain(named: "HSR", as: .a).id
        try built.world.assignTrain(hsr, to: built.line)
        let old = try versionOneTwelve(built.world, retyping: ["HSR": .highSpeed])
        let text = String(decoding: old, as: UTF8.self).replacingOccurrences(of: "\"saveVersion\":112", with: "\"saveVersion\":114")
        let loaded = try JSONDecoder().decode(SavedGame.self, from: Data(text.utf8)).world
        XCTAssertEqual(built.edges.map { loaded.network.edge($0)?.gauge }, [.cape, .cape, .cape], "a save of this version says its own gauges")
    }

    func testTheVersion114SaveKeepsItsGauges() throws {
        var built = try build(.shinkansen)
        let forest = try build(.forest, y: 8_192, in: built.world, named: "Forest")
        built.world = forest.world
        let hsr = try built.world.purchaseTrain(named: "700T", as: .highSpeed).id
        let alishan = try built.world.purchaseTrain(named: "Alishan", as: .alishan).id
        try built.world.assignTrain(hsr, to: built.line)
        try built.world.placeTrain(hsr, at: start(built))
        try built.world.assignTrain(alishan, to: forest.line)
        try built.world.placeTrain(alishan, at: start(forest))
        try built.world.advance(ticks: 1_800)
        let world = built.world
        let url = SavedGameTests.fixtures.appendingPathComponent("v114-track-gauge.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["TRACK_GAUGE_SAVE_NEW"] != nil, SavedGame.currentVersion == 114 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 114)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(built.edges.map { loaded.network.edge($0)?.gauge }, [.shinkansen, .shinkansen, .shinkansen])
        XCTAssertEqual(forest.edges.map { loaded.network.edge($0)?.gauge }, [.forest, .forest, .forest])
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 600)
        try running.advance(ticks: 600)
        XCTAssertEqual(loaded, running)
    }
}
