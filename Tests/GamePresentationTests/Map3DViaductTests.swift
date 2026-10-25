import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 407: each line's viaduct as its kind of railway builds it: the
/// High Speed Rail's wide box girder on one tall pier, the Taiwan
/// Railway's double-track girder on a wall pier, a metro's on one column
/// under a T-shaped cap, and a steel truss over a river.
final class Map3DViaductTests: XCTestCase {
    /// Two tracks of `system` 400 m east, 12 m over the ground, `apart`
    /// millionths of a degree (about 0.11 m each) north of each other,
    /// laid in a builder round Taipei; its chunks' meshes, near and close.
    private func pair(_ system: String, apart: Int, height: Int = 120, water: Bool = false) throws -> (mesh: Map3DMesh, rail: Float, middle: Float) {
        let latitude = 25.0478, longitude = 121.5170
        let world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude)))
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let origin = frame.worldPosition(latitude: latitude, longitude: longitude)
        var builder = Map3DScene.Builder(originX: origin.x, originY: origin.y,
                                         region: WorldRegion(minX: origin.x - 2_000 * metre, minY: origin.y - 2_000 * metre,
                                                             maxX: origin.x + 2_000 * metre, maxY: origin.y + 2_000 * metre),
                                         world: world)
        if water {
            // A river under the whole of it.
            for x in stride(from: -320.0, through: 320, by: 32) {
                for z in stride(from: -64.0, through: 64, by: 32) {
                    let ring = [(-400.0, -100.0), (400, -100), (400, 100), (-400, 100)].map { Map3DBaseMap.Point(x: $0.0, z: $0.1) }
                    builder.waterCells[Map3DScene.ChunkKey(column: builder.gridCell(x, origin: builder.originX),
                                                           row: builder.gridCell(z, origin: builder.originY))] = [[ring]]
                }
            }
        }
        let lon = Int(longitude * 1e6) - 2_000, lat = Int(latitude * 1e6)
        let json = #"{"systems":["\#(system)"],"ways":[{"system":0,"kind":"b","points":[\#(lon),\#(lat),\#(height),4000,0,0]},"#
            + #"{"system":0,"kind":"b","points":[\#(lon),\#(lat - apart),\#(height),4000,0,0]}]}"#
        _ = builder.realTracks(try RealRailTracks(data: Data(json.utf8)), systems: [system], frame: frame, clearOf: Map3DRealTrains.PlayerTrack([]))
        let mesh = builder.chunks().reduce(into: Map3DMesh()) { $0.append($1.mesh); $0.append($1.close) }
        let a = builder.point(x: origin.x, y: origin.y, height: 0)
        let ground = builder.drawnGround(x: a.x, z: a.z)
        let north = frame.worldPosition(latitude: latitude, longitude: longitude)
        let south = frame.worldPosition(latitude: latitude - Double(apart) / 1e6, longitude: longitude)
        let middle = (builder.point(x: north.x, y: north.y, height: 0).z + builder.point(x: south.x, y: south.y, height: 0).z) / 2
        return (mesh, ground + 12 + Map3DScene.railLift, middle)
    }

    /// The piers' feet, the vertices on the ground away from the ends,
    /// in clusters along the line (x): each cluster's middle and spread
    /// across it (z).
    private func piers(_ mesh: Map3DMesh, under rail: Float) -> [(x: Float, across: ClosedRange<Float>)] {
        let feet = mesh.vertices.filter { $0.y < rail - 10 && abs($0.x) < 150 }.sorted { $0.x < $1.x }
        var clusters: [[Map3DVertex]] = []
        for foot in feet {
            if let last = clusters.last?.last, foot.x - last.x < 4 { clusters[clusters.count - 1].append(foot) } else { clusters.append([foot]) }
        }
        // Those whole within the stretch looked at.
        return clusters.map { cluster in
            (cluster.map(\.x).reduce(0, +) / Float(cluster.count), cluster.map(\.z).min()!...cluster.map(\.z).max()!)
        }.filter { abs($0.x) < 140 }
    }

    /// How wide the deck is, across both tracks, at the bed's foot.
    private func deck(_ mesh: Map3DMesh, rail: Float) -> Float {
        let top = mesh.vertices.filter { abs($0.y - (rail - Map3DScene.Builder.bedDrop)) < 0.05 && abs($0.x) < 150 }.map(\.z)
        return (top.max() ?? 0) - (top.min() ?? 0)
    }

    /// The High Speed Rail's two tracks, 4.5 m apart, on one box girder
    /// 13 m wide, on one pier every 35 m under their middle.
    func testTheHighSpeedRailsViaductIsOneWideGirderOnOnePier() throws {
        let (mesh, rail, middle) = try pair("thsr_sched", apart: 41)
        XCTAssertEqual(deck(mesh, rail: rail), 13, accuracy: 0.6)
        let standing = piers(mesh, under: rail)
        XCTAssertGreaterThanOrEqual(standing.count, 7)
        for (a, b) in zip(standing, standing.dropFirst()) { XCTAssertEqual(b.x - a.x, 35, accuracy: 0.5) }
        for pier in standing {
            XCTAssertLessThanOrEqual(pier.across.upperBound - pier.across.lowerBound, 5, "one pier for both tracks")
            XCTAssertEqual((pier.across.lowerBound + pier.across.upperBound) / 2, middle, accuracy: 0.3, "under their middle")
        }
    }

    /// A metro's two tracks on one round column each span, a T-shaped cap
    /// across both girders on top.
    func testAMetrosViaductStandsOnOneColumnUnderATCap() throws {
        let (mesh, rail, middle) = try pair("mrt", apart: 34)
        let standing = piers(mesh, under: rail)
        XCTAssertGreaterThanOrEqual(standing.count, 8)
        for (a, b) in zip(standing, standing.dropFirst()) { XCTAssertEqual(b.x - a.x, 30, accuracy: 0.5) }
        for pier in standing {
            XCTAssertLessThanOrEqual(pier.across.upperBound - pier.across.lowerBound, 2.1, "one column")
            XCTAssertEqual((pier.across.lowerBound + pier.across.upperBound) / 2, middle, accuracy: 0.3)
            // The cap: under the girders, wider than both tracks.
            let cap = mesh.vertices.filter { abs($0.x - pier.x) < 1.5 && $0.y < rail - 2.3 && $0.y > rail - 5 }.map(\.z)
            XCTAssertGreaterThanOrEqual((cap.max() ?? 0) - (cap.min() ?? 0), 3.7 + 3, "a T across both tracks")
        }
    }

    /// The Taiwan Railway's two tracks, 4 m apart, on one wall pier a
    /// span, 32 m apart as the reference's (rail-3d `PIER_M`).
    func testTheRailwaysDoubleTrackStandsOnOneWallPier() throws {
        let (mesh, rail, middle) = try pair("tra_sched", apart: 36)
        XCTAssertEqual(deck(mesh, rail: rail), 9, accuracy: 0.6)
        let standing = piers(mesh, under: rail)
        XCTAssertGreaterThanOrEqual(standing.count, 8)
        for (a, b) in zip(standing, standing.dropFirst()) { XCTAssertEqual(b.x - a.x, 32, accuracy: 0.5) }
        for pier in standing {
            XCTAssertEqual((pier.across.lowerBound + pier.across.upperBound) / 2, middle, accuracy: 0.3)
        }
    }

    /// Over a river the Taiwan Railway's tracks cross on a steel truss
    /// standing 6 m over the rails, its sides outside both tracks, none
    /// between them.
    func testTheRailwayCrossesARiverOnASteelTruss() throws {
        let (mesh, rail, middle) = try pair("tra_sched", apart: 36, water: true)
        let high = mesh.vertices.filter { $0.y > rail + 5 && abs($0.x) < 150 }
        XCTAssertFalse(high.isEmpty, "the truss's top")
        XCTAssertFalse(mesh.vertices.contains { abs($0.z - middle) < 1 && $0.y > rail + 1 && $0.y < rail + 5 && abs($0.x) < 150 }, "no side between the tracks")
        let (dry, dryRail, _) = try pair("tra_sched", apart: 36)
        XCTAssertFalse(dry.vertices.contains { $0.y > dryRail + 2 }, "no truss over dry land")
    }

    /// The player's track over the water (a bridge) is a truss too.
    func testThePlayersBridgeIsATruss() {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
        let line = stride(from: Float(0), through: 240, by: 16).map { Map3DPoint($0, 12, 100) }
        builder.addTrackPiece(line, kind: .bridge)
        let mesh = builder.chunks().reduce(into: Map3DMesh()) { $0.append($1.mesh); $0.append($1.close) }
        XCTAssertTrue(mesh.vertices.contains { $0.y > 17 })
    }
}
