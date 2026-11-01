import Foundation
@testable import GamePresentation
import XCTest

final class Map3DBreezyBlueTests: XCTestCase {
    func testEveryCoachHasIndependentNearFarUnitsAndOneMetreContract() throws {
        var ids=Set<String>()
        for role in Map3DBreezyBlueCoaches.Role.allCases {
            let near=Map3DBreezyBlueCoaches.model(role),far=Map3DBreezyBlueCoaches.model(role,far:true)
            XCTAssertTrue(ids.insert(near.name).inserted)
            XCTAssertTrue(ids.insert(far.name).inserted)
            XCTAssertLessThanOrEqual(near.triangleCount,15_000)
            XCTAssertLessThan(far.triangleCount*2,near.triangleCount)
            for m in [near,far] {
                XCTAssertEqual(m.minimum.x,-10,accuracy:0.0001)
                XCTAssertEqual(m.maximum.x,10,accuracy:0.0001)
                XCTAssertEqual(m.minimum.z,0,accuracy:0.0001)
                XCTAssertEqual(m.maximum.z,role.height,accuracy:0.0001)
                XCTAssertEqual(m.maximum.y-m.minimum.y,2.865,accuracy:0.0001)
                XCTAssertTrue(m.vertices.allSatisfy {
                    [$0.x,$0.y,$0.z,$0.nx,$0.ny,$0.nz,$0.u,$0.v,$0.layer].allSatisfy(\.isFinite)
                })
            }
        }
        XCTAssertEqual(ids.count,8)
    }

    func testEveryPhotographedAxleHasTwoTyresOnTheRail() {
        for role in Map3DBreezyBlueCoaches.Role.allCases {
            for far in [false,true] {
                let m=Map3DBreezyBlueCoaches.model(role,far:far)
                for centre in Map3DBreezyBlueCoaches.bogieCentres {
                    for dx in Map3DBreezyBlueCoaches.axleOffsets {
                        for side:Float in [-1,1] {
                            XCTAssertTrue(m.vertices.contains {
                                abs($0.x-centre-dx)<0.0001 && abs($0.z)<0.0001 && $0.y*side>0.49 && $0.y*side<0.69
                            },"\(m.name): each of eight wheels must reach the common rail")
                        }
                    }
                }
                // Passenger bogies are two-axle; no centre locomotive wheel.
                for centre in Map3DBreezyBlueCoaches.bogieCentres {
                    XCTAssertFalse(m.vertices.contains {abs($0.x-centre)<0.0001 && abs($0.z)<0.0001})
                }
            }
        }
    }

    func testRestoredNonAirConditionedFamiliesAreDifferentGeometry() {
        let mixed=Map3DBreezyBlueCoaches.model(.mixed)
        let long=Map3DBreezyBlueCoaches.model(.longSeat)
        let rotating=Map3DBreezyBlueCoaches.model(.rotatingSeat)
        XCTAssertNotEqual(mixed.vertices.map(\.position),long.vertices.map(\.position))
        XCTAssertNotEqual(rotating.vertices.map(\.position),long.vertices.map(\.position))
        XCTAssertEqual(Map3DBreezyBlueCoaches.doorStations(.rotatingSeat),[-8.92,8.92])
        XCTAssertEqual(Map3DBreezyBlueCoaches.doorStations(.mixed),[-4.36,4.36])
        // ICF lower edge tucks in; Japanese TP/SPK lower edge remains full width.
        XCTAssertTrue(mixed.vertices.contains {abs($0.z-1.12)<0.0001 && abs(abs($0.y)-1.29)<0.0001})
        XCTAssertTrue(long.vertices.contains {abs($0.z-1.12)<0.0001 && abs(abs($0.y)-1.4)<0.0001})
        for m in [mixed,long,rotating] {
            let rooftop=m.vertices.filter {$0.z>3.80}
            XCTAssertFalse(rooftop.isEmpty)
            XCTAssertTrue(rooftop.allSatisfy {abs($0.y)<0.32},"individual ventilators, not wide air-conditioning units")
        }
    }
}
