import XCTest
@testable import GamePresentation

final class Map3DThreeCarUrbanTests: XCTestCase {
    func testIndependentUnitsAssembleWithOutwardCabsAndCommonDatum() {
        let train = Map3DThreeCarUrban.formation()
        var offset = 0
        for (unit, shift) in [(Map3DThreeCarUrban.Unit.leading, Float(15.28)), (.middle,0), (.trailing,-15.28)] {
            let model = Map3DThreeCarUrban.model(unit)
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.001)
            XCTAssertEqual(model.maximum.z, 3.606, accuracy: 0.002)
            for v in model.vertices {
                let q = train.vertices[offset]
                XCTAssertEqual(q.x, v.x+shift, accuracy: 0.0001)
                XCTAssertEqual(q.y, v.y, accuracy: 0.0001)
                XCTAssertEqual(q.z, v.z, accuracy: 0.0001)
                XCTAssertEqual(q.color,v.color)
                offset += 1
            }
        }
        XCTAssertEqual(offset,train.vertices.count)
        XCTAssertGreaterThan(train.length,45)
        XCTAssertLessThan(train.length,47)
    }
    func testEveryVisibleGlassTriangleHasBodySupportAndFacesOut() {
        for unit in Map3DThreeCarUrban.Unit.allCases {
            let model = Map3DThreeCarUrban.model(unit)
            let cab: Float = unit == .leading ? 1 : unit == .trailing ? -1 : 0
            let glassColors: [Float] = [1,0.92,0.80,0.70,0.86]
            let family = glassColors.map { Map3DColor.shaded(Map3DThreeCarUrban.glass,$0) }
            var frontCount=0,sideCount=0
            for start in stride(from: 0,to: model.vertices.count,by: 3) {
                let vs = Array(model.vertices[start..<start+3])
                guard family.contains(vs[0].color) else { continue }
                let centre = vs.reduce(Map3DPoint.zero) { $0+$1.position*(1/3) }
                let n = Map3DPoint(vs[0].nx,vs[0].ny,vs[0].nz)
                if abs(centre.x)>7 {
                    let lift = abs(centre.x)-(7.5-(centre.z-0.79)*0.065)
                    guard abs(lift-0.033)<0.0001 else { continue } // hidden backing / plate edges
                    frontCount += 1
                    XCTAssertNotEqual(cab,0,"No driving glass on middle unit")
                    XCTAssertGreaterThan(n.x*cab,0.9)
                    XCTAssertGreaterThan(centre.x*cab,7.2)
                    // Cab shell: x = 7.5 - (z - .79)*.065. Glazing 33 mm above it.
                    XCTAssertEqual(abs(centre.x)-(7.5-(centre.z-0.79)*0.065),0.033,accuracy:0.001)
                } else {
                    let nearDoor = abs(abs(centre.x)-3.44)<0.7
                    let outerPlane: Float = nearDoor ? 1.363 : 1.342
                    guard abs(abs(centre.y)-outerPlane)<0.0001 else { continue } // hidden backing / plate edges
                    sideCount += 1
                    XCTAssertGreaterThan(n.y*centre.y,1.2,"Side glass must face the viewer")
                    XCTAssertLessThan(abs(centre.y)-1.325,0.05,"No floating side glass")
                }
            }
            XCTAssertGreaterThanOrEqual(sideCount,32,"Audit both sides and both pairs of door leaves")
            if cab == 0 { XCTAssertEqual(frontCount,0) } else { XCTAssertGreaterThan(frontCount,2) }
        }
    }
    func testBogieWheelsAndDoorOpeningsAppearAtTheReferenceLocations() {
        for unit in Map3DThreeCarUrban.Unit.allCases {
            let model=Map3DThreeCarUrban.model(unit)
            let wheels=model.vertices.filter { $0.color == Map3DStreetModel.tyre }
            for x: Float in [-5.82,-4.14,4.14,5.82] {
                for sign: Float in [-1,1] {
                    let wheel=wheels.filter { abs($0.x-x)<0.35 && $0.y*sign>1 }
                    XCTAssertGreaterThan(wheel.count,20)
                    XCTAssertEqual(wheel.map(\.z).min()!,0,accuracy:0.001)
                }
            }
            // Door glazing is high and narrow; cluster actual geometry into
            // four leaves per side rather than trusting a declared door count.
            for sign: Float in [-1,1] {
                let doorGlass=model.vertices.filter { $0.color == Map3DThreeCarUrban.glass && $0.y*sign>1.35 }
                for x: Float in [-3.824,-3.056,3.056,3.824] {
                    XCTAssertTrue(doorGlass.contains { abs($0.x-x)<0.23 && $0.z>2 })
                }
                XCTAssertFalse(doorGlass.contains { abs($0.x)<2.5 },"No accidental third central door")
            }
        }
    }
    func testGeometryIsFiniteNondegenerateAndWithinBudget() {
        for model in Map3DThreeCarUrban.Unit.allCases.map(Map3DThreeCarUrban.model)+[Map3DThreeCarUrban.formation()] {
            XCTAssertLessThan(model.triangleCount,15_000)
            for i in stride(from:0,to:model.vertices.count,by:3) {
                let a=model.vertices[i],b=model.vertices[i+1],c=model.vertices[i+2]
                XCTAssertGreaterThan((b.position-a.position).cross(c.position-a.position).length,0.0000001)
                XCTAssertTrue([a.x,a.y,a.z,a.nx,a.ny,a.nz].allSatisfy(\.isFinite))
            }
        }
    }
}
