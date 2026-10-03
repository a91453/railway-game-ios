import GameCore
import GamePresentation
import XCTest

/// Stage C2: the read-only track facts of Stage S1 as the app shows them:
/// sections between branch points, single and double track between a
/// line's stops, and track two trains occupy at once.
final class TrackInfoTextTests: XCTestCase {
    /// Track along y = 1 from (0, 1) to (6, 1), and a bypass along y = 2
    /// from (1, 1) round to (5, 1); Alpha (1, 0), Beta (3, 0), Gamma
    /// (5, 0) and Epsilon (6, 0) beside it, Delta (7, 3) away from it.
    private func makeBypass() throws -> GameWorld {
        var world = try makeWorld(width: 8, height: 4, balance: 100_000)
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: .east)
        try world.buildTrack(at: GridPosition(x: 1, y: 1), connections: [.east, .south, .west])
        for x in 2...4 {
            try world.buildTrack(at: GridPosition(x: x, y: 1), connections: [.east, .west])
            try world.buildTrack(at: GridPosition(x: x, y: 2), connections: [.east, .west])
        }
        try world.buildTrack(at: GridPosition(x: 5, y: 1), connections: [.east, .south, .west])
        try world.buildTrack(at: GridPosition(x: 6, y: 1), connections: .west)
        try world.buildTrack(at: GridPosition(x: 1, y: 2), connections: [.north, .east])
        try world.buildTrack(at: GridPosition(x: 5, y: 2), connections: [.north, .west])
        for (name, x, y) in [("Alpha", 1, 0), ("Beta", 3, 0), ("Gamma", 5, 0), ("Epsilon", 6, 0), ("Delta", 7, 3)] {
            try world.buildStation(named: name, at: GridPosition(x: x, y: y))
        }
        return world
    }

    func testSectionsRunBetweenBranchPoints() throws {
        let world = try makeBypass()
        XCTAssertEqual(world.trackSectionsSummary(in: .english), "4 sections")
        XCTAssertEqual(world.trackSectionsSummary(in: .traditionalChinese), "4 個區段")
        XCTAssertEqual(world.sectionTexts(at: GridPosition(x: 3, y: 1), in: .english), ["5 tiles, (1, 1)–(5, 1)"])
        XCTAssertEqual(
            world.sectionTexts(at: GridPosition(x: 1, y: 1), in: .english),
            ["2 tiles, (0, 1)–(1, 1)", "5 tiles, (1, 1)–(5, 1)", "7 tiles, (1, 1)–(5, 1)"],
            "a branch point ends several sections"
        )
        XCTAssertEqual(world.sectionTexts(at: GridPosition(x: 3, y: 2), in: .traditionalChinese), ["7 格，(1, 1)–(5, 1)"])
        XCTAssertEqual(world.sectionTexts(at: GridPosition(x: 7, y: 3), in: .english), [], "no track")
    }

    func testARingWithoutABranchPointIsALoop() throws {
        var world = try makeWorld()
        try world.buildTrack(at: GridPosition(x: 0, y: 0), connections: [.east, .south])
        try world.buildTrack(at: GridPosition(x: 1, y: 0), connections: [.south, .west])
        try world.buildTrack(at: GridPosition(x: 1, y: 1), connections: [.north, .west])
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: [.north, .east])
        XCTAssertEqual(world.trackSectionsSummary(in: .english), "1 section · 1 loop")
        XCTAssertEqual(world.trackSectionsSummary(in: .traditionalChinese), "1 個區段 · 1 個環線")
        XCTAssertEqual(world.sectionTexts(at: GridPosition(x: 1, y: 1), in: .english), ["Loop of 4 tiles through (0, 0)"])
        XCTAssertEqual(world.sectionTexts(at: GridPosition(x: 1, y: 1), in: .traditionalChinese), ["環線 4 格，經過 (0, 0)"])
        XCTAssertNil(try makeWorld().trackSectionsSummary(in: .english))
    }

    func testALineSaysHowManyTracksJoinEachPairOfStops() throws {
        var world = try makeBypass()
        let ids = (1...5).map { StationID(rawValue: $0) }
        // Alpha, Beta, Gamma, Epsilon, Delta.
        let line = try world.createLine(named: "Main", stops: [ids[0], ids[1], ids[2], ids[3], ids[4]])
        XCTAssertEqual(world.lineTrackCounts(line.id), [2, 2, 1, 0])
        XCTAssertEqual(world.lineTrackCountTexts(line.id, in: .english), [
            "Alpha–Beta · double track",
            "Beta–Gamma · double track",
            "Gamma–Epsilon · single track",
            "Epsilon–Delta · no track",
        ])
        XCTAssertEqual(world.lineTrackCountTexts(line.id, in: .traditionalChinese), [
            "Alpha–Beta · 雙線", "Beta–Gamma · 雙線", "Gamma–Epsilon · 單線", "Epsilon–Delta · 沒有軌道",
        ])
        XCTAssertEqual(world.lineTrackCountTexts(LineID(rawValue: 9), in: .english), [])
    }

    /// Stage F3c: the track network counts too. Two straight lines of the
    /// network along rows 1 and 3 (nodes 1–4 and 5–8, edges 1–3 and 4–6),
    /// each with a platform of Alpha at its west end and one of Beta at its
    /// east end; Gamma has no platform.
    func testTheTrackNetworkHasSectionsAndTracksToo() throws {
        var world = try makeWorld(width: 8, height: 4, balance: 100_000)
        for y in [1, 3] {
            for x in 0...3 {
                try world.buildTrackNode(at: WorldCoordinate(x: Int64(x) * 1_024 + 512, y: Int64(y) * 1_024 + 512))
            }
        }
        for first in [1, 5] {
            for node in first..<(first + 3) {
                try world.buildTrackEdge(from: .node(node), to: .node(node + 1))
            }
        }
        let alpha = try world.buildStation(named: "Alpha", at: PlanPoint(x: 512, y: 2_560)).id
        let beta = try world.buildStation(named: "Beta", at: PlanPoint(x: 3_584, y: 2_560)).id
        let gamma = try world.buildStation(named: "Gamma", at: PlanPoint(x: 6_656, y: 512)).id
        for (station, edges) in [(alpha, [1, 4]), (beta, [3, 6])] {
            for edge in edges {
                try world.addTrackPlatform(station, on: .edge(edge), from: 0, to: 1_024)
            }
        }
        XCTAssertEqual(world.trackSectionsSummary(in: .english), "2 sections")
        let line = try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        XCTAssertEqual(world.lineTrackCountTexts(line.id, in: .english), ["Alpha–Beta · double track", "Beta–Gamma · no track"])
        XCTAssertEqual(world.lineTrackCountTexts(line.id, in: .traditionalChinese), ["Alpha–Beta · 雙線", "Beta–Gamma · 沒有軌道"])
    }

    func testTrainsSharingTrackAreListed() throws {
        var world = try makeBypass()
        XCTAssertEqual(world.occupancyConflictTexts(in: .english), [])
        for name in ["T1", "T2"] {
            let train = try world.purchaseTrain(named: name)
            try world.placeTrain(train.id, at: .atNode(GridPosition(x: 3, y: 1), heading: .east))
        }
        XCTAssertEqual(world.occupancyConflictTexts(in: .english), ["T1 and T2 on tile (3, 1)"])
        XCTAssertEqual(world.occupancyConflictTexts(in: .traditionalChinese), ["T1、T2 都在格 (3, 1)"])
        XCTAssertEqual(TrackResource.link(between: GridPosition(x: 4, y: 1), and: GridPosition(x: 3, y: 1)).displayText(in: .english), "Link (3, 1)–(4, 1)")
        XCTAssertEqual(TrackResource.span(TrackSpan(edge: .edge(4), start: 1_024, end: 2_048)).displayText(in: .english), "Edge #4, 1024–2048")
        XCTAssertEqual(TrackResource.node(.node(2)).displayText(in: .traditionalChinese), "節點 #2")
    }
}
