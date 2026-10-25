import XCTest
@testable import GamePresentation

final class Map3DTEMU1000Tests: XCTestCase {
    func testIndependentUnitsAndAssembly() {
        let parts = Map3DTEMU1000.Unit.allCases.map(Map3DTEMU1000.model)
        let all = Map3DTEMU1000.formation()
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(all.triangleCount, Map3DTEMU1000.order.reduce(0) { $0 + Map3DTEMU1000.model($1).triangleCount })
        XCTAssertLessThan(all.triangleCount, Map3DModelFile.maximumTriangles)
        XCTAssertEqual(Map3DTEMU1000.order.first, .trailing)
        XCTAssertEqual(Map3DTEMU1000.order.last, .leading)
        XCTAssertEqual(Map3DTEMU1000.order.filter { $0 == .pantograph }.count, 2)
        XCTAssertGreaterThan(all.length, 185)
        XCTAssertLessThan(all.length, 195)
        XCTAssertEqual(all.minimum.z, 0, accuracy: 0.012)
        XCTAssertTrue(parts.allSatisfy { abs($0.minimum.z) < 0.012 })
        XCTAssertGreaterThan(Map3DTEMU1000.model(.pantograph).maximum.z, Map3DTEMU1000.model(.middle).maximum.z + 0.5)
    }

    func testOperatingTarokoUsesNewUnits() throws {
        let pack = Map3DModelPack.standard
        let layout = try XCTUnwrap(pack.layout(forType: "taroko", count: 8))
        XCTAssertEqual(layout.count, 8)
        let names = layout.map { pack.models[$0.model].name }
        XCTAssertEqual(names.first, "set-taroko-head")
        XCTAssertEqual(names.last, "set-taroko-tail")
        XCTAssertEqual(names.filter { $0 == "set-taroko-panto" }.count, 2)
        XCTAssertFalse(pack.isTurned(forType: "taroko", carIndex: 7, count: 8))
        XCTAssertEqual(pack.models[layout[0].model].triangleCount, Map3DTEMU1000.model(.leading).triangleCount + 24)
    }

    func testRevisedCabHasBroadScreenAndRoundedLowNose() {
        let head = Map3DTEMU1000.model(.leading)
        let screen = head.vertices.filter { $0.color == Map3DTEMU1000.glass && $0.x > 10.8 && $0.z > 2.2 }
        XCTAssertFalse(screen.isEmpty)
        XCTAssertGreaterThan((screen.map(\.y).max() ?? 0) - (screen.map(\.y).min() ?? 0), 2.0,
                             "front windscreen must span the broad shoulders")
        XCTAssertGreaterThan((screen.map(\.z).max() ?? 0) - (screen.map(\.z).min() ?? 0), 0.75,
                             "front windscreen must extend down the cab")
        XCTAssertLessThan(screen.map(\.z).min() ?? 10, 2.4,
                          "the dark screen must reach the lowered nose")
        if let top = screen.max(by: { $0.z < $1.z }),
           let bottom = screen.min(by: { $0.z < $1.z }) {
            let rake = (top.x-bottom.x)/(top.z-bottom.z)
            let depth = screen.map { $0.x-rake*$0.z }
            XCTAssertGreaterThan((depth.max() ?? 0)-(depth.min() ?? 0), 0.025,
                                 "windscreen must bend across the cab, not form a flat billboard")
        }
        let arc = head.vertices.filter { $0.color == Map3DTEMU1000.band && $0.x > 12.2 }
        let centreHeight = arc.filter { abs($0.y) < 0.2 }.map(\.z).min() ?? 10
        let sideHeight = arc.filter { abs($0.y) > 1.1 }.map(\.z).min() ?? 0
        XCTAssertLessThan(centreHeight + 0.3, sideHeight,
                          "front waist arc must dip below its side ends")
        let front = head.vertices.filter { $0.x > 12.35 && $0.color == Map3DTEMU1000.shell }
        let low = front.filter { $0.z < 0.95 }.map { abs($0.y) }.max() ?? 0
        let shoulder = front.filter { $0.z > 1.3 && $0.z < 2.2 }.map { abs($0.y) }.max() ?? 0
        XCTAssertGreaterThan(low, 0.7)
        XCTAssertLessThan(low, shoulder * 0.87, "lower nose must round inward")
        let lowTip = front.filter { $0.z < 0.8 }.map(\.x).max() ?? 0
        let curvedTip = front.filter { $0.z > 1.1 && $0.z < 1.5 }.map(\.x).max() ?? 0
        XCTAssertGreaterThan(curvedTip-lowTip, 0.15,
                             "side silhouette must end in a rounded nose, not a tall flat wall")
        XCTAssertLessThan(front.filter { abs($0.y) < 0.5 }.map(\.z).max() ?? 10, 2.1,
                          "the foremost cap must taper below the windshield")
    }

    func testMiddleHasNoCabGlassAtEnd() {
        let middle = Map3DTEMU1000.model(.middle)
        let head = Map3DTEMU1000.model(.leading)
        let glass = Map3DTEMU1000.glass
        XCTAssertFalse(middle.vertices.contains { $0.color == glass && abs($0.x) > 10.8 && $0.z > 3.1 })
        XCTAssertTrue(head.vertices.contains { $0.color == glass && $0.x > 10.8 && $0.z > 3.1 })
    }

    func testCabKeepsTwinUpperLampsAndSymmetricNosePaint() {
        for unit in [Map3DTEMU1000.Unit.leading, .trailing] {
            let model = Map3DTEMU1000.model(unit)
            let lamps = model.vertices.filter {
                $0.color == Map3DStreetModel.headlamp && $0.z > 3.15 && abs($0.y) < 0.35
            }
            XCTAssertGreaterThan(lamps.count, 50,"both upper lenses must be part of the native cab")
            XCTAssertTrue(lamps.contains { $0.y < -0.08 })
            XCTAssertTrue(lamps.contains { $0.y > 0.08 })
            let nose: Float = unit == .leading ? 1 : -1
            let paint = model.vertices.filter {
                $0.color == Map3DTEMU1000.band && $0.x*nose > 12.2 && abs($0.y) < 1.30
            }
            XCTAssertGreaterThan(paint.count, 100,"the curved front paint must cover the nose")
            let left = paint.filter { $0.y > 0.01 }
            let right = paint.filter { $0.y < -0.01 }
            XCTAssertTrue(left.allSatisfy { vertex in
                right.contains { abs($0.x-vertex.x) < 0.003 &&
                                 abs($0.y+vertex.y) < 0.003 &&
                                 abs($0.z-vertex.z) < 0.003 }
            },"paint on the native front must mirror across the centreline")
        }
    }

    func testPassengerWindowsAreIndividualAndWheelsStaySmallOnRail() {
        for unit in Map3DTEMU1000.Unit.allCases {
            let model = Map3DTEMU1000.model(unit)
            let paneColours = Set([0.70,0.80,0.86,0.92,1.0].map {
                Map3DColor.shaded(Map3DTEMU1000.passengerGlass,$0)
            })
            let panes = model.vertices.filter { paneColours.contains($0.color) &&
                                                 abs($0.y) > 1.43 && $0.z > 1.8 && $0.z < 2.6 }
            let paneEdges = Set(panes.map { Int(($0.x*100).rounded()) })
            XCTAssertGreaterThan(paneEdges.count, 16,
                                 "the side must show separate passenger panes, not a solid black band")
            XCTAssertTrue(panes.contains { $0.y > 1.43 })
            XCTAssertTrue(panes.contains { $0.y < -1.43 })
            for axle: Float in [-9.31,-7.25,7.25,9.31] {
                let wheel = model.vertices.filter { $0.color == Map3DTEMU1000.ink &&
                    abs($0.x-axle) < 0.35 && abs($0.y) > 1.12 && $0.z < 0.85 }
                XCTAssertFalse(wheel.isEmpty)
                XCTAssertEqual(wheel.map(\.z).min() ?? -1,0,accuracy:0.012,
                               "each tyre bottom must remain on the rail plane")
                XCTAssertLessThan(wheel.map(\.z).max() ?? 10,0.72,
                                  "the wheel disc should not dominate the lower car")
            }
        }
    }

    func testRoofGreyStaysAboveCentredWhiteCabFace() {
        for unit in [Map3DTEMU1000.Unit.leading, .trailing] {
            let model = Map3DTEMU1000.model(unit)
            let forward: Float = unit == .leading ? 1 : -1
            let roof = model.vertices.filter { $0.color == Map3DPalette.roof && $0.x*forward > 9 }
            XCTAssertFalse(roof.isEmpty)
            XCTAssertGreaterThan(roof.map(\.z).min() ?? 0,2.85,
                                 "grey roof paint must not descend around one side of the front window")
            let left = roof.filter { $0.y > 0.01 }
            let right = roof.filter { $0.y < -0.01 }
            XCTAssertTrue(left.allSatisfy { vertex in
                right.contains { abs($0.x-vertex.x) < 0.003 &&
                                 abs($0.y+vertex.y) < 0.003 &&
                                 abs($0.z-vertex.z) < 0.003 }
            },"grey roof boundary must be mirrored across the cab centreline")
        }
    }
}
