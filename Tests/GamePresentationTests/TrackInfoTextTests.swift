import GameCore
import GamePresentation
import XCTest

/// Stage C2: the read-only track facts of Stage S1 as the app shows them:
/// sections between branch points, single and double track between a
/// line's stops, and track two trains occupy at once. On the track network
/// since Stage F3c.
final class TrackInfoTextTests: XCTestCase {
    /// A main line along row 1, columns 0 to 7 (nodes 1–8, edges 1–6 and
    /// 10), with a passing loop below it on row 3 (nodes 9 and 10): an
    /// S-curve from node 2 down (edge 7), a straight (edge 8) and an
    /// S-curve back up to node 7 (edge 9). Alpha has a platform on edge 1;
    /// Beta on edge 4 and on the loop's edge 8; Gamma on edge 6 and on the
    /// loop's edge 9; Delta on edge 10; Epsilon (7, 4) is away from the
    /// track.
    private func makeBypass() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 5_120, balance: 1_000_000)
        for (x, y) in [(0, 1), (1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (3, 3), (4, 3)] {
            let centre = TestLine.centre(x, y)
            try world.buildTrackNode(at: WorldCoordinate(x: centre.x, y: centre.y))
        }
        for node in 1...6 {
            try world.buildTrackEdge(from: .node(node), to: .node(node + 1))
        }
        func s(_ from: Int, _ to: Int) throws {
            let a = try XCTUnwrap(world.network.node(.node(from))).position
            let b = try XCTUnwrap(world.network.node(.node(to))).position
            try world.buildTrackEdge(from: .node(from), to: .node(to), curve: .cubic(PlanPoint(x: a.x + 1_024, y: a.y), PlanPoint(x: b.x - 1_024, y: b.y)))
        }
        try s(2, 9)
        try world.buildTrackEdge(from: .node(9), to: .node(10))
        try s(10, 7)
        try world.buildTrackEdge(from: .node(7), to: .node(8))
        for (name, x, y, edges) in [("Alpha", 0, 0, [1]), ("Beta", 3, 0, [4, 8]), ("Gamma", 5, 0, [6, 9]), ("Delta", 7, 0, [10]), ("Epsilon", 7, 4, [])] {
            let station = try world.buildStation(named: name, at: TestLine.centre(x, y)).id
            for edge in edges {
                let length = try XCTUnwrap(world.network.edge(.edge(edge))).length
                try world.addTrackPlatform(station, on: .edge(edge), from: 0, to: length)
            }
        }
        return world
    }

    func testSectionsRunBetweenBranchPoints() throws {
        let world = try makeBypass()
        // Node 1 to the turnout at node 2; the main line and the loop from
        // node 2 to the turnout at node 7; node 7 to node 8.
        XCTAssertEqual(world.networkSections().count, 4)
        XCTAssertEqual(world.trackSectionsSummary(in: .english), "4 sections")
        XCTAssertEqual(world.trackSectionsSummary(in: .traditionalChinese), "4 個區段")
        XCTAssertNil(try makeWorld().trackSectionsSummary(in: .english), "no track")
    }

    /// A ring of a straight, two quarter turns, a straight and two quarter
    /// turns back: every node plain.
    func testARingWithoutABranchPointIsALoop() throws {
        var world = try makeWorld(width: 8_192, height: 5_120, balance: 1_000_000)
        for (x, y) in [(1, 1), (2, 1), (3, 2), (2, 3), (1, 3), (0, 2)] {
            let centre = TestLine.centre(x, y)
            try world.buildTrackNode(at: WorldCoordinate(x: centre.x, y: centre.y))
        }
        let quarter: Int64 = 563
        func turn(_ from: Int, _ to: Int, leaving: (Int64, Int64), arriving: (Int64, Int64)) throws {
            let a = try XCTUnwrap(world.network.node(.node(from))).position
            let b = try XCTUnwrap(world.network.node(.node(to))).position
            try world.buildTrackEdge(
                from: .node(from), to: .node(to),
                curve: .cubic(
                    PlanPoint(x: a.x + leaving.0 * quarter, y: a.y + leaving.1 * quarter),
                    PlanPoint(x: b.x - arriving.0 * quarter, y: b.y - arriving.1 * quarter)
                )
            )
        }
        try world.buildTrackEdge(from: .node(1), to: .node(2))
        try turn(2, 3, leaving: (1, 0), arriving: (0, 1))
        try turn(3, 4, leaving: (0, 1), arriving: (-1, 0))
        try world.buildTrackEdge(from: .node(4), to: .node(5))
        try turn(5, 6, leaving: (-1, 0), arriving: (0, -1))
        try turn(6, 1, leaving: (0, -1), arriving: (1, 0))
        XCTAssertEqual(world.trackSectionsSummary(in: .english), "1 section · 1 loop")
        XCTAssertEqual(world.trackSectionsSummary(in: .traditionalChinese), "1 個區段 · 1 個環線")
    }

    func testALineSaysHowManyTracksJoinEachPairOfStops() throws {
        var world = try makeBypass()
        let ids = (1...5).map { StationID(rawValue: $0) }
        // Alpha, Beta, Gamma, Delta, Epsilon: Alpha's only way out is the
        // end of edge 1; Beta and Gamma are joined along the main line and
        // along the loop; Delta's only way in is the start of edge 10.
        let line = try world.createLine(named: "Main", stops: ids)
        XCTAssertEqual(world.lineTrackCounts(line.id), [1, 2, 1, 0])
        XCTAssertEqual(world.lineTrackCountTexts(line.id, in: .english), [
            "Alpha–Beta · single track",
            "Beta–Gamma · double track",
            "Gamma–Delta · single track",
            "Delta–Epsilon · no track",
        ])
        XCTAssertEqual(world.lineTrackCountTexts(line.id, in: .traditionalChinese), [
            "Alpha–Beta · 單線", "Beta–Gamma · 雙線", "Gamma–Delta · 單線", "Delta–Epsilon · 沒有軌道",
        ])
        XCTAssertEqual(world.lineTrackCountTexts(LineID(rawValue: 9), in: .english), [])
    }

    func testTrainsSharingTrackAreListed() throws {
        var world = try makeBypass()
        XCTAssertEqual(world.occupancyConflictTexts(in: .english), [])
        // Both half way along edge 3, a train of one car: its one span.
        for name in ["T1", "T2"] {
            let train = try world.purchaseTrain(named: name)
            try world.placeTrain(train.id, at: .onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 512))
        }
        XCTAssertEqual(world.occupancyConflictTexts(in: .english), ["T1 and T2 on edge #3, 0–1024"])
        XCTAssertEqual(world.occupancyConflictTexts(in: .traditionalChinese), ["T1、T2 都在軌段 #3, 0–1024"])
        // At a node, the node.
        try world.unplaceTrain(TrainID(rawValue: 1))
        try world.unplaceTrain(TrainID(rawValue: 2))
        for id in [TrainID(rawValue: 1), TrainID(rawValue: 2)] {
            try world.placeTrain(id, at: .onEdge(TrackTraversal(edge: .edge(3), direction: .forward), offset: 1_024))
        }
        XCTAssertEqual(world.occupancyConflictTexts(in: .english), ["T1 and T2 on node #4"])
        XCTAssertEqual(world.occupancyConflictTexts(in: .traditionalChinese), ["T1、T2 都在節點 #4"])
        XCTAssertEqual(TrackResource.span(TrackSpan(edge: .edge(4), start: 1_024, end: 2_048)).displayText(in: .english), "Edge #4, 1024–2048")
        XCTAssertEqual(TrackResource.node(.node(2)).displayText(in: .traditionalChinese), "節點 #2")
    }
}
