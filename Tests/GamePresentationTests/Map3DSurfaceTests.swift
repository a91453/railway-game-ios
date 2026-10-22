import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 231: the 3D map's textures: how a face is laid
/// over its layer, what each part of the scene is painted with, and the
/// app's texture file holding a layer for each ``Map3DSurface``.
final class Map3DSurfaceTests: XCTestCase {
    // MARK: - The vertex and the file

    func testAVertexIsLaidOutAsMetalReadsIt() {
        // Map3DMetalView's vertex descriptor: position at 0, normal at 12,
        // colour at 24, texture (u, v, layer) at 28; 40 bytes a vertex.
        XCTAssertEqual(MemoryLayout<Map3DVertex>.stride, 40)
        XCTAssertEqual(MemoryLayout<Map3DVertex>.offset(of: \.nx), 12)
        XCTAssertEqual(MemoryLayout<Map3DVertex>.offset(of: \.color), 24)
        XCTAssertEqual(MemoryLayout<Map3DVertex>.offset(of: \.u), 28)
        XCTAssertEqual(MemoryLayout<Map3DVertex>.offset(of: \.v), 32)
        XCTAssertEqual(MemoryLayout<Map3DVertex>.offset(of: \.layer), 36)
        let plain = Map3DVertex(.zero, normal: .up, color: 1)
        XCTAssertNil(plain.surface, "a vertex is plain unless it is painted")
    }

    func testTheTextureFileHoldsALayerForEverySurface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/Map3D/Map3DSurfaces.png"))
        let bytes = [UInt8](data.prefix(26))
        XCTAssertEqual(Array(bytes[0..<8]), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "a PNG")
        XCTAssertEqual(String(decoding: bytes[12..<16], as: UTF8.self), "IHDR")
        func number(_ at: Int) -> Int { bytes[at..<(at + 4)].reduce(0) { $0 << 8 | Int($1) } }
        // Each layer's colour and its mask side by side, the layers one
        // under another in Map3DSurface's order.
        XCTAssertEqual(number(16), 2 * Map3DSurface.side, "width")
        XCTAssertEqual(number(20), Map3DSurface.side * Map3DSurface.allCases.count, "height")
        XCTAssertEqual(bytes[24], 8, "eight bits a channel")
        XCTAssertEqual(bytes[25], 2, "RGB with no alpha: Xcode premultiplies a PNG's alpha, which would lose the glass's colours")
    }

    // MARK: - Laying a face over its layer

    func testAWallFitsWholeBaysAndFloors() {
        var mesh = Map3DMesh()
        // 10 m across the front (three 3.2 m bays), 4 m deep, three floors.
        mesh.addBox(base: .zero, forward: Map3DPoint(1, 0, 0), length: 4, width: 10, height: 9.6, top: 1, side: 2,
                    frontPaint: .bays(.flatWindows, bay: 3.2, floors: 3), flankPaint: .tile(.plaster, 4))
        let front = mesh.vertices[4..<8]
        XCTAssertEqual(front.map(\.u).min(), 0)
        XCTAssertEqual(front.map(\.u).max(), 3)
        XCTAssertEqual(front.map(\.v).min(), 0)
        XCTAssertEqual(front.map(\.v).max(), 3)
        XCTAssertTrue(front.allSatisfy { $0.surface == .flatWindows })
        // A flank 4 m deep and 9.6 m high, in 4 m repeats; the top plain.
        let flank = mesh.vertices[8..<12]
        XCTAssertTrue(flank.allSatisfy { $0.surface == .plaster })
        XCTAssertEqual(flank.map(\.u).max() ?? 0, 1, accuracy: 1e-5)
        XCTAssertEqual(flank.map(\.v).max() ?? 0, 2.4, accuracy: 1e-5)
        XCTAssertTrue(mesh.vertices[0..<4].allSatisfy { $0.surface == nil })
        // Seen from outside, u grows to the right: the bays read the right
        // way round on every side.
        for quad in 1...4 {
            let face = Array(mesh.vertices[(quad * 4)..<(quad * 4 + 4)])
            let normal = Map3DPoint(face[0].nx, face[0].ny, face[0].nz)
            let right = Map3DPoint.up.cross(normal)
            let low = face.min { $0.u < $1.u }!, high = face.max { $0.u < $1.u }!
            XCTAssertGreaterThan((high.position - low.position).dot(right), 0, "face \(quad)")
        }
    }

    func testANarrowWallStillHoldsOneBay() {
        var mesh = Map3DMesh()
        mesh.addBox(base: .zero, length: 4, width: 1.5, height: 3, top: 1, side: 2, frontPaint: .bays(.homeWindows, bay: 6, floors: 1))
        XCTAssertEqual(mesh.vertices[4..<8].map(\.u).max(), 1)
    }

    func testTopsSideBySideMeetWithoutASeam() {
        var mesh = Map3DMesh()
        mesh.addQuad(Map3DPoint(0, 0, 0), Map3DPoint(0, 0, 10), Map3DPoint(10, 0, 10), Map3DPoint(10, 0, 0), color: 1, paint: .tile(.grass, 40))
        mesh.addQuad(Map3DPoint(10, 0, 0), Map3DPoint(10, 0, 10), Map3DPoint(20, 0, 10), Map3DPoint(20, 0, 0), color: 1, paint: .tile(.grass, 40))
        // The shared edge's corners fall on the same place in the layer.
        XCTAssertEqual(mesh.vertices[2].u, mesh.vertices[5].u)
        XCTAssertEqual(mesh.vertices[2].v, mesh.vertices[5].v)
        XCTAssertEqual(mesh.vertices[2].u, 0.25, accuracy: 1e-6)
    }

    func testTheBedShowsItsMiddleAndItsSleepersRunAlong() {
        var mesh = Map3DMesh()
        let line = [Map3DPoint(0, 0, 0), Map3DPoint(0, 0, -24)]
        mesh.addRibbon(along: line, width: 3.4, top: 1, topPaint: Map3DPaint(.ballast, .tile(width: 5, height: 2.4)))
        let top = mesh.vertices[0..<4]
        // A 3.4 m bed shows the middle 3.4 of the layer's 5 m.
        XCTAssertEqual(top.map(\.u).min() ?? 0, 0.5 - 1.7 / 5, accuracy: 1e-5)
        XCTAssertEqual(top.map(\.u).max() ?? 0, 0.5 + 1.7 / 5, accuracy: 1e-5)
        // 24 m along: ten repeats of four sleepers.
        XCTAssertEqual(top.map(\.v).max() ?? 0, 10, accuracy: 1e-5)
        XCTAssertTrue(top.allSatisfy { $0.surface == .ballast })
    }

    // MARK: - The scene

    private func lineBetweenTwoTowns() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return try newGameLine(through: [towns[0], towns[1]])
    }

    func testTheSceneIsPaintedPartByPart() throws {
        let world = try lineBetweenTwoTowns()
        let scene = Map3DScene(world: world)
        let vertices = scene.chunks.flatMap(\.mesh.vertices)
        let painted = Dictionary(grouping: vertices.compactMap(\.surface)) { $0 }.mapValues(\.count)
        // The ground and the track, the platforms, the city's walls and
        // roofs: every surface but the shops (no shops stand low on this
        // map) is somewhere on it, flats with and without blinds.
        for surface in [Map3DSurface.grass, .paving, .ballast, .concrete, .roof, .plaster, .homeWindows, .homeBalcony, .shutter, .flatWindows,
                        .officeGlass, .metalSheet, .flatBlinds] {
            XCTAssertGreaterThan(painted[surface] ?? 0, 0, "\(surface)")
        }
        // Decision 241: the ground plain, as the 2D map's land (grass
        // only on parks, farms and banks); the water and rails plain too.
        XCTAssertTrue(vertices.filter { $0.color == Map3DPalette.ground || $0.color == Map3DPalette.water || $0.color == Map3DPalette.railTop }
            .allSatisfy { $0.surface == nil })
        // Decision 268: or glowing at night, as a temple's lanterns.
        XCTAssertTrue(vertices.allSatisfy { $0.layer == Map3DVertex.plain || $0.glows || $0.surface != nil })
        // Decision 242: homes faced with tiles and grit, offices and
        // schools with concrete and tiles; only on walls a surface tints.
        let faced = Set(vertices.compactMap(\.detail))
        XCTAssertTrue(faced.isSuperset(of: [.brickTile, .mosaicTile, .terrazzo]), "\(faced)")
        XCTAssertTrue(faced.isSubset(of: Set(Map3DSurface.materials)))
    }

    func testAMaterialRidesUnderItsSurface() {
        // Decision 242: the shader finds the materials from layer 18 on, in
        // this order (Map3DShaders.metal's firstMaterial, detailRepeat).
        XCTAssertEqual(Map3DSurface.materials.map(\.rawValue), [18, 19, 20, 21])
        XCTAssertEqual(Map3DSurface.materials.map(\.detailRepeat), [3.6, 1.8, 1.8, 1.8])
        // Decision 355: and the road paint after them.
        XCTAssertEqual(Map3DSurface.allCases.count, 24)
        let paint = Map3DPaint.bays(.flatWindows, bay: 3.2, floors: 4).on(.brickTile)
        XCTAssertEqual(paint.layer, Float(Map3DSurface.flatWindows.rawValue + 64 * 20))
        XCTAssertEqual(paint.on(nil).layer, Float(Map3DSurface.flatWindows.rawValue))
        var mesh = Map3DMesh()
        mesh.addBox(base: .zero, length: 10, width: 8, height: 12, top: 1, side: 2, frontPaint: paint, flankPaint: Map3DPaint.tile(.plaster, 4))
        let front = mesh.vertices.filter { $0.surface == .flatWindows }
        XCTAssertFalse(front.isEmpty)
        XCTAssertTrue(front.allSatisfy { $0.detail == .brickTile })
        XCTAssertTrue(mesh.vertices.filter { $0.surface == .plaster }.allSatisfy { $0.detail == nil })
        XCTAssertTrue(mesh.vertices.filter { $0.surface == nil }.allSatisfy { $0.detail == nil })
    }

    func testTheBedStandsOverTheGround() throws {
        // Decision 231: drawn at the track's height, the bed was under the
        // ground the game lays track on; lifted, its top shows.
        let world = try lineBetweenTwoTowns()
        let scene = Map3DScene(world: world)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let tops = scene.chunks.flatMap(\.mesh.vertices).filter { $0.surface == .ballast && $0.ny > 0.9 }
        XCTAssertFalse(tops.isEmpty)
        let above = tops.filter { vertex in
            let at = scene.worldPosition(of: vertex.position)
            let ground = Double(world.groundHeight(at: PlanPoint(x: Int64(at.x.rounded()), y: Int64(at.y.rounded()))) ?? 0) / metre
            return Double(vertex.y) > ground + 0.05
        }
        XCTAssertGreaterThan(Double(above.count) / Double(tops.count), 0.9, "\(above.count) of \(tops.count) over the ground")
    }

    func testShopsAndFlatsAreOfEveryKind() throws {
        // Decision 231 (continued): the towers' podiums are shops of every
        // trade on the demo map, picked by where they stand, and the same
        // every time.
        let scene = Map3DScene(world: DemoWorld.make(in: .english))
        let painted = Set(scene.chunks.flatMap(\.mesh.vertices).compactMap(\.surface))
        for shop in Map3DSurface.shops { XCTAssertTrue(painted.contains(shop), "\(shop)") }
        XCTAssertEqual(Map3DScene(world: DemoWorld.make(in: .english)).chunks.map(\.mesh.vertices), scene.chunks.map(\.mesh.vertices))
    }

    func testTrainsStayPlain() throws {
        var world = try lineBetweenTwoTowns()
        try world.advance(ticks: 30)
        let scene = Map3DScene(world: world)
        let mesh = Map3DTrains.mesh(TrainMotion(world: world, time: 0), progress: 1, heights: Map3DTrains.Heights(world.railwaySnapshot()), in: scene)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertTrue(mesh.vertices.allSatisfy { $0.surface == nil })
        XCTAssertTrue(Map3DModelPack.standard.models.allSatisfy { $0.vertices.allSatisfy { $0.surface == nil } })
    }
}
