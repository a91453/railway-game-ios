import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Review L14-3: the 3D button's nearest track point (decision 645) skips
/// the edges that cannot hold a nearer point, and still finds the same one
/// as looking at every point of every edge.
@MainActor
final class Map3DNearestTrackTests: XCTestCase {
    /// Every node, every point along every edge and every station: what it
    /// looked at before.
    private func everyPoint(nearest point: (x: Double, y: Double), in world: GameWorld) -> (x: Double, y: Double)? {
        var best: (x: Double, y: Double)?, bestDistance = Double.infinity
        func consider(_ x: Int64, _ y: Int64) {
            let distance = (Double(x) - point.x) * (Double(x) - point.x) + (Double(y) - point.y) * (Double(y) - point.y)
            if distance < bestDistance { (bestDistance, best) = (distance, (Double(x), Double(y))) }
        }
        for node in world.network.nodes { consider(node.position.x, node.position.y) }
        for edge in world.network.edges { for p in world.trackGeometry(of: edge.id)?.points ?? [] { consider(p.x, p.y) } }
        for station in world.stations { consider(station.location.x, station.location.y) }
        return best
    }

    func testTheHighSpeedDemoFindsTheSamePointAsBefore() throws {
        let world = try HighSpeedDemoTests.opened.get()
        let (w, h) = (Double(world.bounds.width), Double(world.bounds.height))
        for (fx, fy) in [(0.9, 0.9), (0.1, 0.5), (0.5, 0.5), (0.33, 0.71), (0.62, 0.18)] {
            let point = (x: w * fx, y: h * fy)
            let found = Map3DHandoff.nearestTrack(to: point, in: world)
            let expected = everyPoint(nearest: point, in: world)
            XCTAssertEqual(found?.x, expected?.x, "\(fx), \(fy)")
            XCTAssertEqual(found?.y, expected?.y, "\(fx), \(fy)")
        }
        XCTAssertNil(Map3DHandoff.nearestTrack(to: (0, 0), in: GameWorld.newGame()))
    }
}
