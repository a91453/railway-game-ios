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

    /// Laying and removing track on the network, and building stations at
    /// points, never touch the land (Stage F3c-3b: the grid's track and
    /// stations, which took a tile each, are gone from this test).
    func testTheMapHoldsLandAndTheNetworkHoldsEveryTrack() throws {
        var world = try makeWorld(width: 4, height: 2, balance: 100_000)
        let land = world.map
        try world.buildStation(named: "S", at: PlanPoint(x: 3_584, y: 512))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 512, y: 512))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 2_560, y: 512))
        let c = try world.buildTrackNode(at: WorldCoordinate(x: 2_560, y: 1_536))
        let main = try world.buildTrackEdge(from: a, to: b)
        let spur = try world.buildTrackEdge(from: b, to: c)

        XCTAssertEqual(world.map, land, "laying track never touches the land")
        XCTAssertEqual(world.map.tiles.map(\.type), Array(repeating: .empty, count: 8))
        XCTAssertEqual(world.network.edges.map(\.id), [main, spur])
        XCTAssertEqual(world.network.nodes.map(\.id), [a, b, c])

        try world.removeTrackEdge(spur)
        try world.removeTrackNode(c)
        XCTAssertEqual(world.map, land)
        XCTAssertEqual(world.network.edges.map(\.id), [main])
    }

    /// A save in the format every save had from Stage I to save version 1,
    /// every tile written out: a map of empty ground loads, and saves back
    /// as the map's occupied tiles (save version 2, Stage E1), of which
    /// there are none. Until Stage F3c grid track in those tiles went into
    /// the railway network; a map with grid track or a station on a tile,
    /// which only a save made by hand could hold, is now refused with the
    /// reason (decision 51).
    func testAnOldMapLoadsAndGridTrackInItIsRefused() throws {
        let world = try GameWorld(width: 2, height: 1, economy: GameEconomy(balance: 0, costs: testCosts))
        let saved = #"{"clock":{"now":0,"resumeSpeed":"normal","speed":"paused"},"economy":{"balance":0,"costs":{"station":1000,"track":100,"train":5000}},"map":{"height":1,"tiles":[TILES],"width":2},"nextStationID":1,"nextTrainID":1,"stations":[],"trains":[]}"#
        func load(_ tiles: String) throws -> GameWorld {
            try JSONDecoder().decode(GameWorld.self, from: Data(saved.replacingOccurrences(of: "TILES", with: tiles).utf8))
        }
        let loaded = try load(#"{"empty":{}},{"empty":{}}"#)
        XCTAssertEqual(loaded, world)
        let savedNow = saved.replacingOccurrences(of: #""tiles":[TILES]"#, with: #""occupied":[]"#)
        XCTAssertEqual(String(decoding: try encode(loaded), as: UTF8.self), savedNow)
        for tiles in [
            #"{"track":{"connections":2}},{"empty":{}}"#,
            #"{"turnout":{"connections":14,"stem":{"west":{}}}},{"empty":{}}"#,
            #"{"crossing":{}},{"empty":{}}"#,
            #"{"empty":{}},{"station":{"id":1}}"#,
        ] {
            XCTAssertThrowsError(try load(tiles), tiles) { error in
                XCTAssertTrue("\(error)".contains("the grid was removed in Stage F3c"), "\(tiles): \(error)")
            }
        }
        XCTAssertThrowsError(try load(#"{"empty":{}}"#), "a tile short")
        XCTAssertThrowsError(try load(#"{"pond":{}},{"empty":{}}"#), "not a kind of tile")
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

    func testPathAheadListsTheTraversalsStillToCome() throws {
        var (network, edge, _, b) = try makeLongEdge()
        XCTAssertEqual(network.pathAhead(of: first), [], "not placed")
        XCTAssertEqual(network.pathAhead(of: TrainID(rawValue: 9)), [], "no such train")
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
