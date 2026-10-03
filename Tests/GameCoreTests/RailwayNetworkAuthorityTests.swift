import Foundation
import GameCore
import XCTest

/// Stage S3A (ARCHITECTURE decision 29): the railway network is the one
/// record of all track, the map holds only land, and the resources along an
/// edge are its spans. Expected values are worked out by hand from the
/// rules.
final class RailwayNetworkAuthorityTests: XCTestCase {
    private let first = TrainID(rawValue: 1)
    private let second = TrainID(rawValue: 2)

    private func p(_ x: Int, _ y: Int) -> GridPosition {
        GridPosition(x: x, y: y)
    }

    private func forward(_ edge: TrackEdgeID) -> TrackTraversal {
        TrackTraversal(edge: edge, direction: .forward)
    }

    private func backward(_ edge: TrackEdgeID) -> TrackTraversal {
        TrackTraversal(edge: edge, direction: .backward)
    }

    private func span(_ edge: TrackEdgeID, _ start: Int64, _ end: Int64) -> TrackResource {
        .span(TrackSpan(edge: edge, start: start, end: end))
    }

    /// A world's save with its keys sorted.
    private func encode(_ world: GameWorld) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(world)
    }

    // MARK: - One authority

    func testTheMapHoldsLandAndTheNetworkHoldsEveryTrack() throws {
        var world = try makeWorld(width: 4, height: 2)
        let station = try world.buildStation(named: "S", at: p(3, 0))
        let land = world.map

        let plain = try world.buildTrack(at: p(0, 0), connections: .east)
        let turnout = try world.buildTurnout(at: p(1, 0), connections: [.east, .south, .west], stem: .west)
        let crossing = try world.buildCrossing(at: p(1, 1))

        XCTAssertEqual(world.map, land, "laying track never touches the land")
        XCTAssertEqual(world.map.tiles.map(\.type), [.empty, .empty, .empty, .station(id: station.id), .empty, .empty, .empty, .empty])
        XCTAssertEqual(world.tracks, [plain, turnout, crossing], "row-major order")
        XCTAssertEqual(world.network.tracks, world.tracks)
        XCTAssertEqual(world.network.track(at: p(1, 0)), turnout)
        XCTAssertNil(world.track(at: p(3, 0)), "a station is land, not track")

        try world.removeTrack(at: p(1, 1))
        XCTAssertEqual(world.map, land)
        XCTAssertEqual(world.tracks, [plain, turnout])
    }

    func testGridTrackAndStationsStillTakeATileEach() throws {
        var world = try makeWorld(width: 3, height: 1)
        try world.buildStation(named: "S", at: p(0, 0))
        try world.buildTrack(at: p(1, 0), connections: [.east, .west])
        let before = world

        XCTAssertThrowsGameError(try world.buildTrack(at: p(0, 0), connections: .east), .tileOccupied(p(0, 0)))
        XCTAssertThrowsGameError(try world.buildTrack(at: p(1, 0), connections: .east), .tileOccupied(p(1, 0)))
        XCTAssertThrowsGameError(try world.buildCrossing(at: p(1, 0)), .tileOccupied(p(1, 0)))
        XCTAssertThrowsGameError(try world.buildStation(named: "T", at: p(1, 0)), .tileOccupied(p(1, 0)))
        XCTAssertEqual(world, before)
    }

    /// A save in the format every save had from Stage I to save version 1,
    /// with grid track in the map's tiles: its track goes into the railway
    /// network on loading, and comes back out on saving as the map's
    /// occupied tiles (save version 2, Stage E1), each tile byte for byte as
    /// before.
    func testASavedMapsTrackMovesIntoTheNetworkAndSavesBackExactly() throws {
        var world = try GameWorld(width: 4, height: 1, economy: GameEconomy(balance: 10_000, costs: testCosts))
        try world.buildTrack(at: p(0, 0), connections: .east)
        try world.buildTurnout(at: p(1, 0), connections: [.east, .south, .west], stem: .west)
        try world.buildCrossing(at: p(2, 0))
        try world.buildStation(named: "S", at: p(3, 0))
        let saved = #"{"clock":{"now":0,"resumeSpeed":"normal","speed":"paused"},"economy":{"balance":8700,"costs":{"station":1000,"track":100,"train":5000}},"map":{"height":1,"tiles":[{"track":{"connections":2}},{"turnout":{"connections":14,"stem":{"west":{}}}},{"crossing":{}},{"station":{"id":1}}],"width":4},"nextStationID":2,"nextTrainID":1,"stations":[{"id":1,"name":"S","position":{"x":3,"y":0}}],"trains":[]}"#
        let savedNow = saved.replacingOccurrences(
            of: #""tiles":[{"track":{"connections":2}},{"turnout":{"connections":14,"stem":{"west":{}}}},{"crossing":{}},{"station":{"id":1}}]"#,
            with: #""occupied":[{"tile":{"track":{"connections":2}},"x":0,"y":0},{"tile":{"turnout":{"connections":14,"stem":{"west":{}}}},"x":1,"y":0},{"tile":{"crossing":{}},"x":2,"y":0},{"tile":{"station":{"id":1}},"x":3,"y":0}]"#
        )
        XCTAssertNotEqual(savedNow, saved)

        XCTAssertEqual(String(decoding: try encode(world), as: UTF8.self), savedNow)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(savedNow.utf8)), world)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: Data(saved.utf8))
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.map.tiles.map(\.type), [.empty, .empty, .empty, .station(id: StationID(rawValue: 1))])
        XCTAssertEqual(loaded.network.tracks, [
            Track(position: p(0, 0), connections: .east),
            Track(position: p(1, 0), connections: [.east, .south, .west], layout: .turnout(stem: .west)),
            Track(position: p(2, 0), connections: [.north, .east, .south, .west], layout: .crossing),
        ])
        XCTAssertEqual(String(decoding: try encode(loaded), as: UTF8.self), savedNow)
    }

    func testSavedTrackThatBreaksTheRulesIsRefused() throws {
        let valid = #"{"clock":{"now":0,"resumeSpeed":"normal","speed":"paused"},"economy":{"balance":0,"costs":{"station":1000,"track":100,"train":5000}},"map":{"height":1,"tiles":[TILES],"width":2},"nextStationID":1,"nextTrainID":1,"stations":[],"trains":[]}"#
        func load(_ tiles: String) -> GameWorld? {
            try? JSONDecoder().decode(GameWorld.self, from: Data(valid.replacingOccurrences(of: "TILES", with: tiles).utf8))
        }
        XCTAssertNotNil(load(#"{"track":{"connections":2}},{"crossing":{}}"#))
        XCTAssertNil(load(#"{"track":{"connections":0}},{"empty":{}}"#), "no exits")
        XCTAssertNil(load(#"{"track":{"connections":16}},{"empty":{}}"#), "not a direction")
        XCTAssertNil(load(#"{"turnout":{"connections":10,"stem":{"north":{}}}},{"empty":{}}"#), "two exits")
        XCTAssertNil(load(#"{"track":{"connections":2}}"#), "a tile short")
        XCTAssertNil(load(#"{"station":{"id":1}},{"empty":{}}"#), "a station tile with no station")
    }

    // MARK: - Spans

    func testAnEdgeIsCutIntoTheFewestEqualSpansNoLongerThanATile() {
        let edge = TrackEdgeID.edge(1)
        func bounds(_ length: Int64) -> [Int64] {
            RailwayNetwork.spans(of: edge, length: length).map(\.end)
        }
        XCTAssertEqual(bounds(1), [1])
        XCTAssertEqual(bounds(396), [396])
        XCTAssertEqual(bounds(1_024), [1_024])
        // Two parts of 1025: ⌊1025 ÷ 2⌋ = 512.
        XCTAssertEqual(bounds(1_025), [512, 1_025])
        XCTAssertEqual(bounds(2_048), [1_024, 2_048])
        // Three parts of 2560: ⌊2560 ÷ 3⌋ = 853, ⌊5120 ÷ 3⌋ = 1706.
        XCTAssertEqual(bounds(2_560), [853, 1_706, 2_560])
        XCTAssertEqual(bounds(5_120), [1_024, 2_048, 3_072, 4_096, 5_120])
        // 2 km at 64 units a metre is 128000: 125 spans of 1024.
        XCTAssertEqual(RailwayNetwork.spans(of: edge, length: 128_000), (0..<125).map { TrackSpan(edge: edge, start: $0 * 1_024, end: ($0 + 1) * 1_024) })

        for length in Int64(1)...5_000 {
            let spans = RailwayNetwork.spans(of: edge, length: length)
            XCTAssertEqual(spans.count, Int((length + 1_023) / 1_024), "\(length)")
            XCTAssertEqual(spans.first?.start, 0)
            XCTAssertEqual(spans.last?.end, length)
            XCTAssertTrue(zip(spans, spans.dropFirst()).allSatisfy { $0.end == $1.start }, "\(length): end to end")
            let lengths = spans.map(\.length)
            XCTAssertTrue(lengths.allSatisfy { $0 > 0 && $0 <= 1_024 }, "\(length)")
            XCTAssertLessThanOrEqual(lengths.max()! - lengths.min()!, 1, "\(length): equal to within one")
        }
    }

    func testAGridLinkIsOneSpanAndItsResourceIsUnchanged() throws {
        var world = try makeWorld(width: 3, height: 1)
        try world.buildTrack(at: p(0, 0), connections: .east)
        try world.buildTrack(at: p(1, 0), connections: [.east, .west])
        let link = TrackEdgeID.link(between: p(0, 0), and: p(1, 0))

        XCTAssertEqual(world.trackSpans(of: link), [TrackSpan(edge: link, start: 0, end: 1_024)])
        XCTAssertEqual(TrackResource.link(between: p(1, 0), and: p(0, 0)), .span(TrackSpan(edge: link, start: 0, end: 1_024)))
        XCTAssertEqual(world.trackSpans(of: .link(between: p(1, 0), and: p(2, 0))), [], "no track at (2, 0)")
        XCTAssertEqual(world.trackSpans(of: .edge(1)), [], "no such edge")

        try world.purchaseTrain(named: "A")
        try world.placeTrain(first, at: .onLink(from: p(0, 0), to: p(1, 0), offset: 300))
        XCTAssertEqual(world.occupiedResources(of: first), [.link(between: p(0, 0), and: p(1, 0))])
    }

    /// A 2048 edge from (512, 512) to (2560, 512): two spans, 0–1024 and
    /// 1024–2048.
    private func makeLongEdge() throws -> (world: GameWorld, edge: TrackEdgeID, from: TrackNodeID, to: TrackNodeID) {
        var world = try makeWorld(width: 4, height: 2, balance: 100_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 512))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 2_560, y: 512))
        let edge = try world.buildTrackEdge(from: a, to: b)
        try world.purchaseTrain(named: "A")
        try world.purchaseTrain(named: "B")
        return (world, edge, a, b)
    }

    func testATrainHoldsOnlyTheSpansItIsOnAndBothAtABoundary() throws {
        var (world, edge, a, b) = try makeLongEdge()
        XCTAssertEqual(world.trackSpans(of: edge), [TrackSpan(edge: edge, start: 0, end: 1_024), TrackSpan(edge: edge, start: 1_024, end: 2_048)])

        // One car is a point.
        try world.placeTrain(first, at: .onEdge(forward(edge), offset: 1_000))
        XCTAssertEqual(world.occupiedResources(of: first), [span(edge, 0, 1_024)])
        try world.unplaceTrain(first)
        try world.placeTrain(first, at: .onEdge(forward(edge), offset: 1_024))
        XCTAssertEqual(world.occupiedResources(of: first), [span(edge, 0, 1_024), span(edge, 1_024, 2_048)], "on the boundary: both")
        try world.unplaceTrain(first)
        // Backward, 500 from the `to` node is 1548 from the `from` node.
        try world.placeTrain(first, at: .onEdge(backward(edge), offset: 500))
        XCTAssertEqual(world.occupiedResources(of: first), [span(edge, 1_024, 2_048)])
        try world.unplaceTrain(first)

        // Two cars, 1024 long, head at the boundary: 0–1024, from node A.
        try world.setTrainCars(first, to: 2)
        try world.placeTrain(first, at: .onEdge(forward(edge), offset: 1_024))
        XCTAssertEqual(world.occupiedResources(of: first), [.node(a), span(edge, 0, 1_024), span(edge, 1_024, 2_048)])
        try world.unplaceTrain(first)
        // No room behind A for a body 1024 long.
        XCTAssertThrowsGameError(try world.placeTrain(first, at: .onEdge(forward(edge), offset: 700)), .invalidTrainPosition)
        try world.placeTrain(first, at: .onEdge(forward(edge), offset: 2_048))
        // 1024 to 2048: node B, and the first span at its end.
        XCTAssertEqual(world.occupiedResources(of: first), [.node(b), span(edge, 0, 1_024), span(edge, 1_024, 2_048)])
    }

    func testTwoTrainsOnOneLongEdgeConflictOnlyWhereTheyShareASpan() throws {
        var (world, edge, _, _) = try makeLongEdge()
        try world.placeTrain(first, at: .onEdge(forward(edge), offset: 300))
        try world.placeTrain(second, at: .onEdge(forward(edge), offset: 1_800))
        XCTAssertEqual(world.occupancyConflicts(), [], "one edge, two spans: no conflict")

        try world.unplaceTrain(second)
        try world.placeTrain(second, at: .onEdge(backward(edge), offset: 1_100))
        // 2048 − 1100 = 948 from A: the first span, which the first train holds.
        XCTAssertEqual(world.occupancyConflicts(), [TrackConflict(resource: span(edge, 0, 1_024), trains: [first, second])])
    }

    func testSpansComeFromTheLengthAloneNeverFromTheSamples() throws {
        var world = try makeWorld(width: 16, height: 16, balance: 1_000_000)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 512))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 8_704, y: 512))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 8_704, y: 8_704))
        let straight = try world.buildTrackEdge(from: a, to: b)
        let curve = try world.buildTrackEdge(from: b, to: c, curve: .cubic(PlanPoint(x: 12_800, y: 512), PlanPoint(x: 12_800, y: 8_704)))
        for id in [straight, curve] {
            let edge = try XCTUnwrap(world.trackEdge(id))
            XCTAssertEqual(world.trackSpans(of: id), RailwayNetwork.spans(of: id, length: edge.length))
        }
        XCTAssertEqual(world.trackSpans(of: straight).count, 8, "8192 long")
        XCTAssertGreaterThan(try XCTUnwrap(world.trackGeometry(of: curve)).points.count, world.trackSpans(of: curve).count + 1)
    }

    // MARK: - The way ahead

    func testPathAheadListsTheTraversalsStillToComeOnEitherKindOfTrack() throws {
        var world = try makeWorld(width: 5, height: 1)
        for x in 0..<5 {
            try world.buildTrack(at: p(x, 0), connections: x == 0 ? .east : x == 4 ? .west : [.east, .west])
        }
        try world.purchaseTrain(named: "A")
        XCTAssertEqual(world.pathAhead(of: first), [], "not placed")
        XCTAssertEqual(world.pathAhead(of: TrainID(rawValue: 9)), [], "no such train")
        try world.placeTrain(first, at: .onLink(from: p(0, 0), to: p(1, 0), offset: 100))
        try world.setTrainContinuation(first, to: [p(2, 0), p(3, 0), p(4, 0)])
        XCTAssertEqual(world.pathAhead(of: first), [.link(from: p(1, 0), to: p(2, 0)), .link(from: p(2, 0), to: p(3, 0)), .link(from: p(3, 0), to: p(4, 0))])
        // A removed link is still ahead: the train waits for it.
        try world.removeTrack(at: p(3, 0))
        XCTAssertEqual(world.pathAhead(of: first).count, 3)

        var (network, edge, _, b) = try makeLongEdge()
        let c = try network.buildTrackNode(at: WorldCoordinate(x: 3_584, y: 512))
        let beyond = try network.buildTrackEdge(from: b, to: c)
        try network.placeTrain(first, at: .onEdge(forward(edge), offset: 100))
        XCTAssertEqual(network.pathAhead(of: first), [])
        try network.setTrainContinuation(first, along: [forward(beyond)])
        XCTAssertEqual(network.pathAhead(of: first), [forward(beyond)])
        // A removed edge never comes back: the way ahead stops before it.
        try network.removeTrackEdge(beyond)
        XCTAssertEqual(network.pathAhead(of: first), [])
    }
}
