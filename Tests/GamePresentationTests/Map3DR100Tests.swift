import XCTest
@testable import GamePresentation

final class Map3DR100Tests: XCTestCase {
    func testTwoDatedLiveriesHaveCompleteLegalNearAndFarLocomotives() {
        for livery in Map3DR100.Livery.allCases {
            let near=Map3DR100.model(livery:livery),far=Map3DR100.model(livery:livery,far:true)
            XCTAssertEqual(near.name,livery.identifier)
            for m in [near,far] {
                XCTAssertLessThanOrEqual(m.triangleCount,15000)
                XCTAssertEqual(m.minimum.x,-7.9,accuracy:0.0001)
                XCTAssertEqual(m.maximum.x,7.9,accuracy:0.0001)
                XCTAssertEqual(m.minimum.z,0,accuracy:0.0001)
                XCTAssertEqual(m.maximum.z,3.92,accuracy:0.0001)
                XCTAssertEqual(m.maximum.y,1.475,accuracy:0.0001)
                XCTAssertEqual(m.minimum.y,-1.475,accuracy:0.0001)
                XCTAssertTrue(m.vertices.allSatisfy { [$0.x,$0.y,$0.z,$0.nx,$0.ny,$0.nz].allSatisfy(\.isFinite) })
            }
            XCTAssertEqual(near.minimum,far.minimum)
            XCTAssertEqual(near.maximum,far.maximum)
            XCTAssertLessThan(far.triangleCount*2,near.triangleCount)
        }
    }
    func testEveryA1AA1AWheelTouchesRailAndShortCabEndIsDistinct() {
        for far in [false,true] {
            let m=Map3DR100.model(far:far)
            for centre in Map3DR100.bogieCentres {
                for offset in Map3DR100.axleOffsets {
                    for side:Float in [-1,1] {
                        XCTAssertTrue(m.vertices.contains { abs($0.x-centre-offset)<0.0001 && abs($0.z)<0.0001 && side*$0.y>0.53 && side*$0.y<0.72 })
                    }
                }
            }
            XCTAssertTrue(m.vertices.contains { $0.x>5.23 && $0.x<5.25 && $0.z>3 && $0.color==Map3DTrainStyle.glass })
            XCTAssertFalse(m.vertices.contains { $0.x < -6 && $0.z>2.9 && $0.color==Map3DTrainStyle.glass })
        }
    }
    func testPaintChangesWithoutChangingUnderlyingWheelAndCabGeometry() {
        let a=Map3DR100.model(livery:.orange),b=Map3DR100.model(livery:.breezyBlue)
        XCTAssertEqual(a.vertices.map(\.position),b.vertices.map(\.position))
        XCTAssertNotEqual(a.vertices.map(\.color),b.vertices.map(\.color))
    }
    func testTheNavyRestorationHasItsOwnRoofColourAndTheLongEndHasNoSecondCab() {
        XCTAssertNotEqual(Map3DR100.Livery.orange.roof,Map3DR100.Livery.breezyBlue.roof)
        for livery in Map3DR100.Livery.allCases {
            for far in [false,true] {
                let m=Map3DR100.model(livery:livery,far:far)
                let roof=m.vertices.filter { $0.x > 0.8 && $0.x < 2.8 && $0.z > 3.30 && $0.nz > 0.5 }
                XCTAssertFalse(roof.isEmpty)
                XCTAssertTrue(roof.allSatisfy { $0.color==livery.roof })
                XCTAssertFalse(m.vertices.contains { $0.x < -6 && $0.z > 2.9 && $0.color==Map3DTrainStyle.glass })
            }
        }
    }
}
