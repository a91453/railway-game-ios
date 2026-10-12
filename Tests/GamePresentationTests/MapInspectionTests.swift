import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 184: the select tool shows the track it picks
/// (the lines along it and its "signal": the train on it or that has
/// reserved it) and, for a train, its line, load and lateness.
@MainActor
final class MapInspectionTests: XCTestCase {
    private func world() throws -> (GameWorld, PlanPoint, PlanPoint) {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.renameLine(try XCTUnwrap(world.lines.first).id, to: "Red")
        return (world, towns[0], towns[1])
    }

    func testTheTrackShowsItsLinesAndTheTrainOnIt() throws {
        let (world, _, _) = try world()
        let line = try XCTUnwrap(world.lines.first)
        let train = try XCTUnwrap(world.trains.first)
        let edge = try XCTUnwrap(world.network.edges.first).id
        let inspection = try XCTUnwrap(world.trackInspection(of: edge))
        XCTAssertEqual(inspection.lines, [line.id])
        XCTAssertEqual(inspection.signal, .occupied(train.id), "the train stands at the first platform")
        let text = try XCTUnwrap(world.trackInspectionText(of: edge, in: .english))
        XCTAssertTrue(text.hasPrefix("Track · "), text)
        XCTAssertTrue(text.contains("Lines: Red · Signal: stop, \(train.name) on it"), text)
        let chinese = try XCTUnwrap(world.trackInspectionText(of: edge, in: .traditionalChinese))
        XCTAssertTrue(chinese.contains("路線：Red · 號誌：紅燈（\(train.name) 佔用中）"), chinese)
    }

    func testTrackNoTrainHoldsIsClear() throws {
        var (world, a, _) = try world()
        let from = try world.buildTrackNode(at: WorldCoordinate(x: a.x, y: a.y + 40_000))
        let to = try world.buildTrackNode(at: WorldCoordinate(x: a.x + 40_000, y: a.y + 40_000))
        let spur = try world.buildTrackEdge(from: from, to: to)
        let inspection = try XCTUnwrap(world.trackInspection(of: spur))
        XCTAssertEqual(inspection.lines, [])
        XCTAssertEqual(inspection.signal, .clear)
        XCTAssertEqual(inspection.length, 40_000)
        let text = try XCTUnwrap(world.trackInspectionText(of: spur, in: .traditionalChinese))
        XCTAssertEqual(text, "軌道 · 625 公尺 · \(inspection.structure.name(in: .traditionalChinese)) · 沒有路線經過 · 號誌：綠燈（無列車）")
        XCTAssertEqual(world.signalText(.reserved(try XCTUnwrap(world.trains.first).id), in: .english),
                       "Signal: caution, reserved for \(try XCTUnwrap(world.trains.first).name)")
        XCTAssertNil(world.trackInspection(of: TrackEdgeID.edge(9_999)))
    }

    func testATapOnTheTrackSelectsIt() throws {
        let (world, a, b) = try world()
        let session = GameSession(world: world, language: .english)
        XCTAssertEqual(session.tool, .select)
        let middle = PlanPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        session.tapMap(at: middle, reach: 2_000)
        let edge = try XCTUnwrap(session.selectedTrackEdge)
        XCTAssertEqual(session.selectionText(), session.world.trackInspectionText(of: edge, in: .english))

        // A station or a clear selection lets it go.
        session.selectStation(try XCTUnwrap(session.world.stations.first).id)
        XCTAssertNil(session.selectedTrackEdge)
        session.tapMap(at: middle, reach: 2_000)
        XCTAssertNotNil(session.selectedTrackEdge)
        session.clearSelection()
        XCTAssertNil(session.selectedTrackEdge)

        // Other tools pick no track.
        session.selectTool(.train)
        session.tapMap(at: middle, reach: 2_000)
        XCTAssertNil(session.selectedTrackEdge)
    }

    func testATrainShowsItsLineLoadAndLateness() throws {
        var (world, _, _) = try world()
        let train = try XCTUnwrap(world.trains.first)
        XCTAssertEqual(world.trainInspectionText(of: train.id, in: .english)?.hasPrefix("Line: Red · Load 0%"), true)
        XCTAssertEqual(world.trainInspectionText(of: train.id, in: .traditionalChinese)?.hasPrefix("路線：Red · 滿載率 0%"), true)
        try world.unassignTrain(train.id)
        XCTAssertEqual(world.trainInspectionText(of: train.id, in: .traditionalChinese)?.hasPrefix("未配屬路線 · 滿載率 0%"), true)
        XCTAssertNil(world.trainInspectionText(of: TrainID(rawValue: 99), in: .english))
    }
}
