import XCTest
@testable import GamePresentation

/// Decision 956: the Keikyu New 1000 (``Map3DRedCommuter``), the owner's
/// old detailed cars as the local studio cut them into palette faces.
final class Map3DKeikyuNew1000Tests: XCTestCase {
    /// Each car near and far: 20.00 m coupler to coupler, 2.80 m wide, the
    /// wheels' treads on the rail, the roof 3.904 m up, and within the
    /// brief's triangles (6,000 near, 1,200 far and under half the near).
    func testEveryCarIsTheBriefsSizeNearAndFar() throws {
        for (name, near, far) in [("cab", Map3DRedCommuter.cab(), Map3DRedCommuter.cab(far: true)),
                                  ("middle", Map3DRedCommuter.middle(), Map3DRedCommuter.middle(far: true))] {
            let near = try XCTUnwrap(near, name), far = try XCTUnwrap(far, name)
            for model in [near, far] {
                XCTAssertEqual(model.length, 20.00, accuracy: 0.005, model.name)
                XCTAssertEqual(model.minimum.y, -1.40, accuracy: 0.005, model.name)
                XCTAssertEqual(model.maximum.y, 1.40, accuracy: 0.005, model.name)
                XCTAssertEqual(model.minimum.z, 0, accuracy: 0.002, model.name)
                XCTAssertEqual(model.maximum.z, 3.904, accuracy: 0.005, model.name)
            }
            XCTAssertEqual(far.minimum.x, near.minimum.x, accuracy: 0.01)
            XCTAssertEqual(far.maximum.x, near.maximum.x, accuracy: 0.01)
            XCTAssertLessThanOrEqual(near.triangleCount, 6_000, name)
            XCTAssertLessThanOrEqual(far.triangleCount, 1_200, name)
            XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, name)
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), name)
        }
        XCTAssertEqual(Map3DRedCommuter.cab()?.triangleCount, 1_314)
        XCTAssertEqual(Map3DRedCommuter.middle()?.triangleCount, 1_100)
        XCTAssertEqual(Map3DRedCommuter.cab(far: true)?.triangleCount, 634)
        XCTAssertEqual(Map3DRedCommuter.middle(far: true)?.triangleCount, 532)
    }

    /// The body's underside 1.00 m up (its dark underframe), the red side
    /// from 1.16 m, the white band's edges about 1.91 and 3.24 m, a side's
    /// windows its glass material's faces.
    func testTheBodyAndBandAreAtTheBriefsHeights() throws {
        let middle = try XCTUnwrap(Map3DRedCommuter.middle())
        let body = middle.vertices.filter { abs($0.x) < 8 && abs($0.y) > 0.9 && $0.z > 0.5 }
        XCTAssertEqual(body.map(\.z).min() ?? 0, 1.00, accuracy: 0.005, "the body's underside")
        let side = body.filter { $0.y > 1.39 }
        XCTAssertEqual(side.filter { $0.color == Map3DPalette.trainRed }.map(\.z).min() ?? 0, 1.16, accuracy: 0.01, "the red side's foot")
        let white = side.filter { $0.color == Map3DPalette.acUnit }.map(\.z)
        XCTAssertEqual(white.min() ?? 0, 1.915, accuracy: 0.01, "the band's lower edge")
        XCTAssertEqual(white.max() ?? 0, 3.24, accuracy: 0.01, "the band's upper edge")
        XCTAssertTrue(side.contains { $0.color == Map3DTrainStyle.glass && $0.layer == Map3DVertex.trainGlass })
    }

    /// The lamps are the cab's own lenses, at its face (x over 9.8 m, some
    /// 1.48 m up), white and red; the middle car has none.
    func testTheLampsAreTheCabsOwnLenses() throws {
        for far in [false, true] {
            let cab = try XCTUnwrap(Map3DRedCommuter.cab(far: far))
            let lit = cab.vertices.filter(\.glows)
            XCTAssertTrue(lit.contains { $0.color == Map3DTrainStyle.headlamp })
            XCTAssertTrue(lit.contains { $0.color == Map3DPalette.lantern })
            XCTAssertGreaterThan(lit.map(\.x).min() ?? 0, 9.8)
            XCTAssertEqual((lit.map(\.z).min()! + lit.map(\.z).max()!) / 2, 1.48, accuracy: 0.1)
            let middle = try XCTUnwrap(Map3DRedCommuter.middle(far: far))
            XCTAssertFalse(middle.vertices.contains(where: \.glows))
        }
    }

    /// Four cars at their own 20 m, the cab turned round at the back, and
    /// a far set of its own.
    func testTheSetIsLaidAtItsOwnLengthsWithAFarSet() throws {
        let set = try XCTUnwrap(Map3DTrainSet.byKey[Map3DRedCommuter.key])
        XCTAssertEqual(set.far, Map3DRedCommuter.key + "Far")
        XCTAssertNotNil(Map3DTrainSet.byKey[Map3DRedCommuter.key + "Far"])
        let pack = Map3DModelPack.standard
        let layout = try XCTUnwrap(pack.layout(forType: Map3DRedCommuter.key, count: 4))
        XCTAssertEqual(layout.map(\.length).reduce(0, +), 80.0, accuracy: 0.05)
        XCTAssertEqual(Map3DShowcase.entry(Map3DRedCommuter.key)?.category, .japan)
        XCTAssertEqual(Map3DShowcase.entry(Map3DRedCommuter.key)?.chinese, "京急新1000形")
    }

    /// Decision 956's comparison: the car clears the bore, the footbridge's
    /// corridor and the contact wire, and stands no wider than a
    /// platform's edge allows; its floor is some 0.15 m under a platform.
    func testTheCarClearsTheGamesStructures() throws {
        let cab = try XCTUnwrap(Map3DRedCommuter.cab())
        let platform = Map3DScene.Builder.platformHeight
        XCTAssertEqual(platform - 1.00, 0.15, accuracy: 0.001)
        XCTAssertLessThan(cab.maximum.y, Map3DScene.Builder.platformEdge)
        XCTAssertLessThan(cab.maximum.z, Map3DStationFootbridge.deck + platform)
        XCTAssertLessThan(cab.maximum.z, Map3DScene.Builder.contactHeight)
        // The bore's roof flat reaches from its crown (6 m) to 1.8 m either
        // side, past the car's 1.40 m.
        XCTAssertLessThan(cab.maximum.z, Map3DScene.Builder.boreCrown)
        XCTAssertLessThan(cab.maximum.y, Map3DScene.Builder.boreHalfWidth - Map3DScene.Builder.boreSlope)
    }
}
