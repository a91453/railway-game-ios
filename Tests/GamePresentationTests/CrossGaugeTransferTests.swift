import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 990: a station on two tracks of different gauges side by side
/// (a conventional line's 1,067 mm beside the Shinkansen's 1,435 mm, as at
/// Shin-Yatsushiro in 2004–2011). The platform tool gives the track beside
/// the same station's platform, or the island layout an island between
/// the two, but lays no crossover between them: no train could cross one.
/// Passengers change across the island (decision 912).
@MainActor
final class CrossGaugeTransferTests: XCTestCase {
    /// A 1,067 mm track 500 m long west to east along y = 10,240, and a
    /// second 5 m north of it of `beside`'s gauge; the platform mode on.
    private func tracks(beside: TrackGauge) throws -> GameSession {
        var world = try makeWorld(width: 40_960, height: 20_480, balance: 100_000_000, speed: .paused)
        for (y, gauge) in [(Int64(10_240), TrackGauge.cape), (10_240 - DoubleTrack.spacing, beside)] {
            let west = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: y))
            let east = try world.buildTrackNode(at: WorldCoordinate(x: 34_816, y: y))
            try world.buildTrackEdge(from: west, to: east, gauge: gauge)
        }
        XCTAssertEqual(Set(world.network.edges.map(\.gauge)), [beside, .cape])
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.platform)
        session.platformCars = 4
        return session
    }

    /// Builds station "Middle" in `layout` on the 1,067 mm track.
    private func build(_ layout: StationLayout, on session: GameSession) throws -> StationID {
        session.stationLayout = layout
        session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 64)
        session.stationName = "Middle"
        XCTAssertEqual(session.networkStationLayout, layout)
        session.addNetworkPlatform()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        return try XCTUnwrap(session.world.stations.first { $0.name == "Middle" }?.id)
    }

    /// No node joins track of one gauge to track with none of its rails.
    private func assertNoNodeJoinsTheGauges(_ world: GameWorld, file: StaticString = #filePath, line: UInt = #line) {
        for node in world.network.nodes {
            let rails = node.ends.compactMap { world.network.edge($0.edge)?.gauge.rails }
            for (index, first) in rails.enumerated() {
                for second in rails.dropFirst(index + 1) {
                    XCTAssertFalse(first.isDisjoint(with: second), "node \(node.id) joins two gauges", file: file, line: line)
                }
            }
        }
    }

    func testTwoSidePlatformsBesideAnotherGaugeGetNoCrossover() throws {
        let session = try tracks(beside: .shinkansen)
        let edges = session.world.network.edges.count
        let station = try build(.doubleSide, on: session)
        XCTAssertEqual(session.world.trackPlatforms(of: station).count, 2, "both tracks call at it")
        XCTAssertEqual(session.world.network.edges.count, edges, "no crossover cut into either track")
        assertNoNodeJoinsTheGauges(session.world)
        XCTAssertTrue(session.message?.text.contains("of another gauge, gets a platform too") ?? false, session.message?.text ?? "")
        XCTAssertFalse(session.message?.text.contains("crossover") ?? true)
    }

    /// The same track, both of one gauge, still gets decision 571's
    /// crossovers: what the rule leaves out is only the other gauge's.
    func testTwoSidePlatformsOnOneGaugeStillGetCrossovers() throws {
        let session = try tracks(beside: .cape)
        let edges = session.world.network.edges.count
        _ = try build(.doubleSide, on: session)
        XCTAssertGreaterThan(session.world.network.edges.count, edges)
        XCTAssertTrue(session.message?.text.contains("crossover") ?? false, session.message?.text ?? "")
    }

    func testAnIslandBetweenTwoGaugesIsChangedAcross() throws {
        let session = try tracks(beside: .shinkansen)
        let station = try build(.doubleIsland, on: session)
        let world = session.world
        let platforms = world.trackPlatforms(of: station)
        XCTAssertEqual(platforms.count, 2)
        assertNoNodeJoinsTheGauges(world)
        let gauges = Set(platforms.compactMap { world.network.edge($0.edge)?.gauge })
        XCTAssertEqual(gauges, [.cape, .shinkansen], "the track swung out round the island keeps the Shinkansen's gauge")
        let change = try XCTUnwrap(world.platformChange(from: platforms[0], to: platforms[1]))
        XCTAssertEqual(change.kind, .acrossPlatform)
        XCTAssertEqual(change.minimumSeconds, 60)
    }
}
