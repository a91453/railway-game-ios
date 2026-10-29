import Foundation
@testable import GamePresentation
import XCTest

/// Every `.m3dmodel` the app bundles is a mesh the 3D map can draw right:
/// no triangle without area, every triangle wound the way its neighbours
/// are, and the whole facing out. The map draws both sides of a triangle
/// but lights it by its winding, so one wound the wrong way shows its
/// inside (2026-10-29: the garbage truck's remesh had holes and turned
/// faces, black on the device at night; the Kenney tank was inside out).
final class Map3DBundledModelFilesTests: XCTestCase {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Resources/Models")

    static func bundled() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == Map3DGarbageTruck.fileExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A corner, exactly as the file has it: shared corners are written
    /// with the same bits.
    struct Corner: Hashable {
        let x: UInt32, y: UInt32, z: UInt32
        init(_ p: Map3DPoint) { (x, y, z) = (p.x.bitPattern, p.y.bitPattern, p.z.bitPattern) }
    }

    struct Mesh {
        let fileTriangles: Int
        let triangles: [[Map3DPoint]]

        init(_ url: URL) throws {
            let bytes = try Data(contentsOf: url)
            fileTriangles = bytes.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 8, as: UInt32.self).littleEndian) }
            let model = try Map3DModelFile(decoding: bytes, named: url.lastPathComponent).model
            triangles = stride(from: 0, to: model.vertices.count, by: 3).map { start in (0..<3).map { model.vertices[start + $0].position } }
        }

        /// The edges two triangles share that both walk the same way: one
        /// of the two is turned round. A triangle with a twin the other
        /// way round over the same corners (a leaf card drawn from both
        /// sides) is left out; so are edges more than two triangles share.
        var edgesWoundAlike: Int {
            let corners = triangles.map { $0.map(Corner.init) }
            var faces: [Set<Corner>: Int] = [:]
            for c in corners { faces[Set(c), default: 0] += 1 }
            var walks: [Set<Corner>: [(Corner, Corner)]] = [:]
            for c in corners where faces[Set(c)] == 1 {
                for k in 0..<3 { walks[[c[k], c[(k + 1) % 3]], default: []].append((c[k], c[(k + 1) % 3])) }
            }
            return walks.values.filter { $0.count == 2 && $0[0] == $0[1] }.count
        }

        /// The volume the triangles wind round, cubic metres: below 0 when
        /// they face in.
        var signedVolume: Float {
            triangles.reduce(0) { $0 + $1[0].dot($1[1].cross($1[2])) / 6 }
        }

        /// The length of the edges only one triangle has, metres: the
        /// rims of the mesh's holes.
        var openEdges: Float {
            var walks: [Set<Corner>: (count: Int, length: Float)] = [:]
            for t in triangles {
                for k in 0..<3 {
                    let a = t[k], b = t[(k + 1) % 3], key: Set<Corner> = [Corner(a), Corner(b)]
                    walks[key, default: (0, (b - a).length)].count += 1
                }
            }
            return walks.values.filter { $0.count == 1 }.reduce(0) { $0 + $1.length }
        }
    }

    func testEveryBundledModelIsDrawnTheRightWayOut() throws {
        let files = try Self.bundled()
        XCTAssertGreaterThanOrEqual(files.count, 11)
        for url in files {
            let name = url.lastPathComponent, mesh = try Mesh(url)
            XCTAssertEqual(mesh.triangles.count, mesh.fileTriangles, "\(name): a triangle with no area")
            XCTAssertEqual(mesh.edgesWoundAlike, 0, "\(name): triangles wound against their neighbours")
            XCTAssertGreaterThan(mesh.signedVolume, -0.001, "\(name): inside out")
        }
    }

    /// The garbage truck's body has no holes the night shows through: the
    /// rims of its open edges come to less than its length (Meshy's remesh
    /// had 31 m of them, round holes in the cab and the box).
    func testTheGarbageTruckIsClosed() throws {
        let mesh = try Mesh(Self.folder.appendingPathComponent("garbage-truck.\(Map3DGarbageTruck.fileExtension)"))
        let extent = mesh.triangles.joined().reduce((low: Map3DPoint(.infinity, .infinity, .infinity), high: Map3DPoint(-.infinity, -.infinity, -.infinity))) {
            (Map3DPoint(min($0.low.x, $1.x), min($0.low.y, $1.y), min($0.low.z, $1.z)), Map3DPoint(max($0.high.x, $1.x), max($0.high.y, $1.y), max($0.high.z, $1.z)))
        }
        XCTAssertLessThan(mesh.openEdges, extent.high.x - extent.low.x)
    }

    /// The checks find what they are for: a triangle turned round, and a
    /// model turned inside out.
    func testTheChecksFindTurnedTriangles() throws {
        let mesh = try Mesh(Self.folder.appendingPathComponent("city-bus.\(Map3DGarbageTruck.fileExtension)"))
        var one = mesh.triangles
        one[0] = [one[0][0], one[0][2], one[0][1]]
        XCTAssertGreaterThan(Mesh(fileTriangles: one.count, triangles: one).edgesWoundAlike, 0)
        let inside = mesh.triangles.map { [$0[0], $0[2], $0[1]] }
        XCTAssertLessThan(Mesh(fileTriangles: inside.count, triangles: inside).signedVolume, -1)
    }
}

extension Map3DBundledModelFilesTests.Mesh {
    init(fileTriangles: Int, triangles: [[Map3DPoint]]) {
        self.fileTriangles = fileTriangles
        self.triangles = triangles
    }
}
