import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 610: the real buildings' street fronts close up (arcade
/// pillars, window grilles, air conditioners, blade signs, rooftop rooms).
final class Map3DRealFacadeTests: XCTestCase {
    private let metre = Double(WorldCoordinate.unitsPerMetre)

    /// The 4 m street cells of a road running east–west along z from
    /// `from` to `to` metres, x −40…60 m.
    private func street(z from: Float, to: Float) -> Set<Map3DScene.ChunkKey> {
        var cells = Set<Map3DScene.ChunkKey>()
        for row in Int((from / 4).rounded(.down))...Int((to / 4).rounded(.down)) {
            for column in -10...15 { cells.insert(Map3DScene.ChunkKey(column: column, row: row)) }
        }
        return cells
    }

    /// A 透天厝 street's shophouse 8 m wide and 14 m deep from (`x`, 0),
    /// its front on z = 14 m, four storeys, its street fronts built with
    /// the scene's origin at (`shift`, `shift / 2`) metres; the scene's
    /// street-front vertices put back where they stand on the map.
    private func front(x: Float = 0, shift: Float = 0, streets: Set<Map3DScene.ChunkKey>?, target: Map3DScene.Builder.Target = .near,
                       kind: Map3DScene.Builder.RealKind = .shophouse) -> [Map3DVertex] {
        let world = GameWorld.newGame()
        var builder = Map3DScene.Builder(originX: Double(shift) * metre, originY: Double(shift / 2) * metre, region: WorldRegion(bounds: world.bounds),
                                         world: world)
        builder.target = target
        builder.facadeStreets = streets.map { cells in
            // The cells, as the scene of that origin keeps them.
            Set(cells.map { Map3DScene.ChunkKey(column: $0.column - Int(shift / 4), row: $0.row - Int(shift / 8)) })
        }
        let shiftPoint = Map3DPoint(Float(Int(shift / 4) * 4), 0, Float(Int(shift / 8) * 4))
        let ring = [Map3DPoint(x, 0, 0), Map3DPoint(x + 8, 0, 0), Map3DPoint(x + 8, 0, 14), Map3DPoint(x, 0, 14)].map { $0 - shiftPoint }
        builder.addRealBuilding([[ring]], ground: 0, height: 14.2, storeys: 4, kind: kind)
        let chunks = builder.chunks()
        return chunks.flatMap(\.facade.vertices).map { vertex in
            var vertex = vertex
            vertex.x += shiftPoint.x
            vertex.z += shiftPoint.z
            return vertex
        }
    }

    private func bits(_ vertices: [Map3DVertex]) -> [UInt32] {
        vertices.flatMap { [$0.x.bitPattern, $0.y.bitPattern, $0.z.bitPattern, $0.nx.bitPattern, $0.ny.bitPattern, $0.nz.bitPattern, $0.color,
                            $0.u.bitPattern, $0.v.bitPattern, $0.layer.bitPattern] }
    }

    /// The same outline where it stands gives the same street front, bit
    /// for bit, built again or with the scene's origin elsewhere (it moves
    /// as track is laid); a shophouse's front has pillars, signs, grilles,
    /// air conditioners or a rooftop room in it.
    func testTheSameBuildingHasTheSameFrontEveryTime() {
        let streets = street(z: 16, to: 22)
        let home = front(streets: streets)
        XCTAssertGreaterThan(home.count, 40)
        XCTAssertEqual(bits(front(streets: streets)), bits(home))
        // Elsewhere, the same colours and faces, at the same places to a
        // millimetre (the scene's metres lose bits away from its origin).
        for shift: Float in [512, 1_024, 4_096] {
            let moved = front(shift: shift, streets: streets)
            XCTAssertEqual(moved.map { [$0.color, $0.layer.bitPattern] }, home.map { [$0.color, $0.layer.bitPattern] }, "origin moved \(shift) m")
            XCTAssertTrue(zip(moved, home).allSatisfy { a, b in
                [a.x - b.x, a.y - b.y, a.z - b.z, a.u - b.u, a.v - b.v].allSatisfy { abs($0) < 0.001 }
            }, "origin moved \(shift) m")
        }
        // Another building down the street, a different front.
        XCTAssertNotEqual(bits(front(x: 40, streets: streets).map { var v = $0; v.x -= 40; return v }), bits(home))
    }

    /// Only the wall that looks onto the street has a front, and it stands
    /// out of that wall (or on the roof behind it); none at all without a
    /// street, afar, or on a building whose kind has none.
    func testOnlyTheStreetWallHasAFrontAndOnlyClose() {
        let home = front(streets: street(z: 16, to: 22))
        XCTAssertTrue(home.allSatisfy { $0.x >= -0.6 && $0.x <= 8.6 }, "within the wall's ends")
        XCTAssertTrue(home.allSatisfy { $0.z >= 14 - 0.001 || $0.y >= 14.2 - 0.001 }, "out of the street wall, or on the roof")
        XCTAssertTrue(home.contains { $0.z > 14.5 }, "something out over the street")
        XCTAssertTrue(front(streets: nil).isEmpty)
        XCTAssertTrue(front(streets: street(z: -30, to: -24)).isEmpty, "no street by it")
        XCTAssertTrue(front(streets: street(z: 16, to: 22), target: .far).isEmpty)
        XCTAssertTrue(front(streets: street(z: 16, to: 22), kind: .temple).isEmpty)
        XCTAssertTrue(front(streets: street(z: 16, to: 22), kind: .industry).isEmpty)
        // The street on the north: the front on the north wall.
        let north = front(streets: street(z: -8, to: -2))
        XCTAssertFalse(north.isEmpty)
        XCTAssertTrue(north.allSatisfy { $0.z <= 0.001 || $0.y >= 14.2 - 0.001 })
    }

    /// A street of 600 shophouses in one chunk keeps its fronts to the
    /// chunk's budget, and keeps the same ones whichever order they were
    /// built in (a chunk built alone reads its footprints in another).
    func testABusyChunkKeepsToItsBudgetInAnyOrder() {
        let world = GameWorld.newGame()
        func built(_ order: [Int]) -> Map3DMesh {
            var builder = Map3DScene.Builder(originX: 0, originY: 0, region: WorldRegion(bounds: world.bounds), world: world)
            builder.target = .near
            var cells = Set<Map3DScene.ChunkKey>()
            for row in 0..<30 {
                for column in 0..<126 { cells.insert(Map3DScene.ChunkKey(column: column, row: row * 4 + 3)) }
            }
            builder.facadeStreets = cells
            for index in order {
                let x = Float(index % 60) * 8, z = Float(index / 60) * 16
                let ring = [Map3DPoint(x, 0, z), Map3DPoint(x + 8, 0, z), Map3DPoint(x + 8, 0, z + 12), Map3DPoint(x, 0, z + 12)]
                builder.addRealBuilding([[ring]], ground: 0, height: 14.2, storeys: 4, kind: .shophouse)
            }
            let fronts = builder.chunks().filter { !$0.facade.isEmpty }
            XCTAssertEqual(fronts.count, 1)
            return fronts.first?.facade ?? Map3DMesh()
        }
        let forward = built(Array(0..<600))
        XCTAssertLessThanOrEqual(forward.triangleCount, Map3DRealFacade.chunkBudget)
        XCTAssertGreaterThan(forward.triangleCount, Map3DRealFacade.chunkBudget * 9 / 10, "filled to near its budget")
        XCTAssertEqual(bits(built(Array((0..<600).reversed())).vertices), bits(forward.vertices))
        XCTAssertEqual(built(Array((0..<600).reversed())).indices, forward.indices)
    }

    /// Battery Saver, Low Power Mode, a hot phone and the lowest tier (an
    /// older device, or memory running short) leave the street fronts out.
    func testWhenTheMapDrawsTheFronts() {
        XCTAssertTrue(Map3DRealFacade.draws(quality: .automatic, lowPower: false, heat: .nominal, tier: .standard))
        XCTAssertTrue(Map3DRealFacade.draws(quality: .high, lowPower: true, heat: .serious, tier: .higher))
        XCTAssertFalse(Map3DRealFacade.draws(quality: .saving, lowPower: false, heat: .nominal, tier: .higher))
        XCTAssertFalse(Map3DRealFacade.draws(quality: .off, lowPower: false, heat: .nominal, tier: .higher))
        XCTAssertFalse(Map3DRealFacade.draws(quality: .automatic, lowPower: true, heat: .nominal, tier: .higher))
        XCTAssertFalse(Map3DRealFacade.draws(quality: .automatic, lowPower: false, heat: .serious, tier: .higher))
        XCTAssertFalse(Map3DRealFacade.draws(quality: .high, lowPower: false, heat: .critical, tier: .higher))
        XCTAssertFalse(Map3DRealFacade.draws(quality: .automatic, lowPower: false, heat: .nominal, tier: .lower))
        XCTAssertFalse(Map3DRealFacade.draws(quality: .automatic, lowPower: false, heat: .nominal, tier: nil))
    }
}
