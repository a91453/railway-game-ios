@testable import GamePresentation
import GameCore
import XCTest

/// Decision 1033: a street tram's stop is the studio's unroofed model,
/// low beside embedded track; other platforms stay as they were.
final class Map3DTramStopTests: XCTestCase {
    /// The model's size (the studio's README: 26 m over the ramps, 2.4 m
    /// back from the rail side, the sign post 2.85 m), its top 0.35 m.
    func testTheModel() {
        for full in [true, false] {
            let model = Map3DTramStop.model(full: full)
            XCTAssertFalse(model.vertices.isEmpty)
            guard !model.vertices.isEmpty else { continue }
            let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
            XCTAssertEqual(xs.max()! - xs.min()!, Map3DTramStop.length, accuracy: 0.05)
            XCTAssertEqual(ys.min()!, 0, accuracy: 0.01, "the rail side's edge")
            XCTAssertEqual(ys.max()!, Map3DTramStop.width, accuracy: 0.05)
            XCTAssertEqual(zs.min()!, 0, accuracy: 0.01)
            XCTAssertEqual(zs.max()!, 2.85, accuracy: 0.05)
            XCTAssertTrue(Set(model.vertices.map(\.color)).isSubset(of: Set(Map3DTramStop.palette)))
        }
        XCTAssertEqual(Map3DTramStop.model(full: true).indices.count / 3, 824)
        XCTAssertEqual(Map3DTramStop.model(full: false).indices.count / 3, 224)
    }

    /// Placed beside a track running east with the stop to its south, it
    /// reaches south from the edge, its ends along the track.
    func testItReachesBackFromTheTrack() {
        let mesh = Map3DTramStop.placed(full: true, edge: Map3DPoint(10, 2, 20), along: Map3DPoint(1, 0, 0), back: Map3DPoint(0, 0, 1))
        let xs = mesh.vertices.map(\.x), ys = mesh.vertices.map(\.y), zs = mesh.vertices.map(\.z)
        XCTAssertEqual(xs.min()!, -3, accuracy: 0.05)
        XCTAssertEqual(xs.max()!, 23, accuracy: 0.05)
        XCTAssertEqual(zs.min()!, 20, accuracy: 0.01)
        XCTAssertEqual(zs.max()!, 20 + Map3DTramStop.width, accuracy: 0.05)
        XCTAssertEqual(ys.min()!, 2, accuracy: 0.01)
        let north = Map3DTramStop.placed(full: true, edge: Map3DPoint(0, 0, 0), along: Map3DPoint(1, 0, 0), back: Map3DPoint(0, 0, -1))
        XCTAssertEqual(north.vertices.map(\.z).min()!, -Map3DTramStop.width, accuracy: 0.05)
        XCTAssertEqual(north.vertices.map(\.z).max()!, 0, accuracy: 0.01)
    }

    /// A straight with a station at each end whose platforms are
    /// `metres` long, a train of `type` on the line between them.
    private func built(_ type: TrainType, metres: Int64) throws -> Map3DScene.Builder {
        var world = GameWorld(
            bounds: try WorldBounds(width: 65_536, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(minutes: 600), speed: .paused)
        )
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 14_336, y: 8_704)).id
        let length = metres * 64
        try world.addTrackPlatform(west, on: edge, from: 2_048, to: 2_048 + length)
        try world.addTrackPlatform(east, on: edge, from: 10_240, to: 10_240 + length)
        let line = try world.createLine(named: "Line", stops: [west, east]).id
        try world.assignTrain(try world.purchaseTrain(named: "One", as: type).id, to: line)
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        var builder = Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
        let snapshot = world.railwaySnapshot()
        builder.trackCover = Map3DTrackCover(snapshot, builder: &builder)
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        return builder
    }

    func testAStreetTramsShortPlatformIsTheStop() throws {
        let tram = try built(.c, metres: 24)
        XCTAssertEqual(tram.state.platforms.laidPlatforms.map(\.tramStop), [true, true])
        let near = Set(tram.nearMeshes.values.flatMap(\.vertices).map(\.color))
        XCTAssertTrue(near.contains(Map3DPalette.timber), "its bench")
        // Its top is the stop's, low over the rails.
        let laid = try XCTUnwrap(tram.state.platforms.laidPlatforms.first)
        let rails = try XCTUnwrap(tram.state.track.trackLines.first?.points.first).y
        XCTAssertEqual(laid.line[0].y + Map3DScene.Builder.platformHeight, rails + Map3DTramStop.top, accuracy: 0.05)

        for (type, metres) in [(TrainType.c, Int64(64)), (.a, 24), (.emu3000, 24)] {
            let other = try built(type, metres: metres)
            XCTAssertEqual(other.state.platforms.laidPlatforms.map(\.tramStop), [false, false], "\(type) \(metres) m")
        }
    }
}
