import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 378: the double track's preview is worked out on the main
/// actor, and a place where either track cannot be cut is passed by before
/// any crossover is built there (lesson 5's track with a train on it held
/// the preview most of a second in a release build).
@MainActor
final class DoubleTrackPreviewCostTests: XCTestCase {
    private func lesson5(drafting pick: (GameSession) -> TrackEdgeID?, whole: Bool) throws -> GameSession {
        let session = GameSession(world: .newGame(lesson: Lesson.all[4]), language: .english)
        session.setSpeed(.paused)
        session.selectTool(.select)
        let id = try XCTUnwrap(pick(session))
        let geometry = try XCTUnwrap(session.world.trackGeometry(of: id))
        session.tapMap(at: geometry.location(at: geometry.length / 3).position.plan, reach: 64)
        XCTAssertEqual(session.selectedTrackEdge, id)
        session.trackUpgradeWholeRun = whole
        session.beginTrackUpgrade(.doubleTrack)
        return session
    }

    /// The track a train stands on: no crossover can be cut into it, and
    /// none is tried; the second track is laid without them, as before.
    func testNoCrossoverIsTriedOnTrackATrainIsOn() throws {
        let session = try lesson5(drafting: { session in
            session.world.network.edges.first { edge in
                if case .trackReserved = session.world.trackEdgeSplitRefusal(edge.id, at: edge.length / 2) {
                    return !session.hasTrackBeside(edge.id)
                }
                return false
            }?.id
        }, whole: false)
        let preview = try XCTUnwrap(session.trackUpgradePreview)
        XCTAssertTrue(preview.note?.contains("No room for a crossover at an end") ?? false, preview.note ?? "")
        XCTAssertEqual(session.crossoverTrials, 0)
    }

    /// The stretch lesson 5's guide points at: a crossover at each end,
    /// each built at the first place tried past the stations' platforms.
    func testEachCrossoverIsBuiltAtTheFirstPlaceTried() throws {
        let session = try lesson5(drafting: { $0.tutorialDoubleTrackStretch }, whole: true)
        let preview = try XCTUnwrap(session.trackUpgradePreview)
        XCTAssertNil(preview.problem, preview.problem ?? "")
        XCTAssertTrue(preview.note?.contains("Crossovers join the two tracks at both ends.") ?? false, preview.note ?? "")
        XCTAssertEqual(session.crossoverTrials, 2)
    }

    /// A report, on request only: how long each preview takes on lesson
    /// 5's tracks and the Yilan Line demo's longest ones. Run it in a
    /// release build:
    /// `DOUBLE_TRACK_PREVIEW_REPORT=1 swift test -c release -Xswiftc -enable-testing --filter DoubleTrackPreviewCostTests`.
    func testPreviewTimesReport() throws {
        guard ProcessInfo.processInfo.environment["DOUBLE_TRACK_PREVIEW_REPORT"] != nil else {
            throw XCTSkip("Set DOUBLE_TRACK_PREVIEW_REPORT=1 to measure the double track's preview.")
        }
        func measure(_ name: String, _ world: GameWorld, _ edge: TrackEdge) {
            for whole in [true, false] {
                let session = GameSession(world: world, language: .english)
                session.setSpeed(.paused)
                session.selectTool(.select)
                guard let geometry = session.world.trackGeometry(of: edge.id) else { continue }
                session.tapMap(at: geometry.location(at: geometry.length / 3).position.plan, reach: 64)
                guard session.selectedTrackEdge == edge.id, session.canDoubleSelectedTrack else { continue }
                session.trackUpgradeWholeRun = whole
                let start = Date()
                session.beginTrackUpgrade(.doubleTrack)
                let preview = session.trackUpgradePreview
                let seconds = Date().timeIntervalSince(start)
                print(String(
                    format: "%@ %@ %.1f km %@: %.0f ms, %d crossovers tried, %@", name, "\(edge.id)", Double(edge.length) / 64_000,
                    whole ? "to the switches" : "this piece", seconds * 1_000, session.crossoverTrials, preview?.problem ?? "built"
                ))
            }
        }
        let lesson = GameWorld.newGame(lesson: Lesson.all[4])
        for edge in lesson.network.edges.sorted(by: { $0.length > $1.length }) {
            measure("Lesson 5", lesson, edge)
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func resource(_ path: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/\(path)"))
        }
        let railways = try RealRailways(
            lines: resource("RealRailways/track_lines.geojson"), stations: resource("RealRailways/track_stations.geojson"),
            names: resource("RealRailways/station_names.json"),
            pingxiRuns: RealLineRuns(data: resource("RealRailways/tra_pingxi_runs.json")),
            structures: RealRailStructures(data: resource("RealRailways/rail_structures.json"))
        )
        let demo = RealWorldDemo.makeFlat(in: .english, railways: railways)
        for edge in demo.network.edges.sorted(by: { $0.length > $1.length }).prefix(6) {
            measure("Yilan Line demo", demo, edge)
        }
    }
}
