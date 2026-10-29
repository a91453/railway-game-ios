import Foundation
@testable import GamePresentation
import XCTest

final class Map3DKaohsiungLightRailTests: XCTestCase {
    func testFiveUnequalModulesAndOnlyThreeBogieModulesPerFleet() {
        for far in [false,true] {
            for unit in Map3DKaohsiungCAF.Unit.allCases {
                let m=Map3DKaohsiungCAF.model(unit,far:far)
                XCTAssertEqual(m.minimum.z, [.s1,.s2].contains(unit) ? 0.18:0,accuracy:0.001,m.name)
            }
            for unit in Map3DKaohsiungCitadis.Unit.allCases {
                let m=Map3DKaohsiungCitadis.model(unit,far:far)
                XCTAssertEqual(m.minimum.z, [.sc1,.sc2].contains(unit) ? 0.20:0,accuracy:0.001,m.name)
            }
        }
        XCTAssertNotEqual(Map3DKaohsiungCAF.length(.c1),Map3DKaohsiungCAF.length(.r))
        XCTAssertNotEqual(Map3DKaohsiungCitadis.length(.m1),Map3DKaohsiungCitadis.length(.np))
        XCTAssertEqual(2*Map3DKaohsiungCAF.length(.c1)+2*Map3DKaohsiungCAF.length(.s1)+Map3DKaohsiungCAF.length(.r)+4*Map3DKaohsiungCAF.joint,34.166,accuracy:0.00001)
        XCTAssertEqual(2*Map3DKaohsiungCitadis.length(.m1)+2*Map3DKaohsiungCitadis.length(.sc1)+Map3DKaohsiungCitadis.length(.np)+4*Map3DKaohsiungCitadis.joint,33.4,accuracy:0.00001)
    }

    func testBothIndependentFleetsHaveLegalNearFarUnits() {
        var pairs: [(Map3DModelPack.Model,Map3DModelPack.Model)]=[]
        pairs += Map3DKaohsiungCAF.Unit.allCases.map { (Map3DKaohsiungCAF.model($0),Map3DKaohsiungCAF.model($0,far:true)) }
        pairs += Map3DKaohsiungCitadis.Unit.allCases.map { (Map3DKaohsiungCitadis.model($0),Map3DKaohsiungCitadis.model($0,far:true)) }
        for (near,far) in pairs {
            XCTAssertLessThanOrEqual(near.triangleCount,Map3DModelFile.maximumTriangles,near.name)
            XCTAssertLessThan(far.triangleCount*2,near.triangleCount,near.name)
            XCTAssertEqual(near.minimum.x,far.minimum.x,accuracy:0.025,near.name)
            XCTAssertEqual(near.maximum.x,far.maximum.x,accuracy:0.025,near.name)
            XCTAssertEqual(near.minimum.z,far.minimum.z,accuracy:0.001,near.name)
            XCTAssertEqual(near.maximum.z,far.maximum.z,accuracy:0.025,near.name)
            for m in [near,far] {
                XCTAssertTrue(m.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && abs(Map3DPoint($0.nx,$0.ny,$0.nz).length-1)<0.001 },m.name)
            }
        }
    }

    func testStudiesDoNotReplaceTheSharedOperatingTramOrMetro() throws {
        let standard=Map3DModelPack.standard,studies=Map3DModelPack.studies
        XCTAssertFalse(standard.models.contains { $0.name.hasPrefix("klrt-") })
        XCTAssertEqual(studies.models.filter { $0.name.hasPrefix("klrt-") }.count,20)
        let unlocked=try XCTUnwrap(Map3DTrainSet.set(forKey:"greenTram",count:2))
        XCTAssertEqual(unlocked.key,"fiveSectionLRT")
        XCTAssertEqual(Map3DTrainSet.set(forKey:"greenTram",count:2,locked:TrainPack.sets)?.key,"greenTram")
        XCTAssertNil(standard.layout(forType:"greenTram",count:2))
        for id in ["set-greenTram-head","set-fiveSectionLRT-head","set-kaohsiung-head","set-kaohsiungFar-head"] {
            XCTAssertNotNil(standard.index(of:id),id)
        }
        XCTAssertFalse(TrainPack.sets.contains { $0.hasPrefix("klrt-") })
    }

    func testRoofEquipmentBelongsToDifferentModuleRoles() {
        // Actual output above the roof, not a recipe constant: the CAF ACRs
        // are on cabs; the taller Citadis Ecopack covers are on suspended SCs.
        let cafCab=Map3DKaohsiungCAF.model(.c1),cafSC=Map3DKaohsiungCAF.model(.s1)
        let citCab=Map3DKaohsiungCitadis.model(.m1),citSC=Map3DKaohsiungCitadis.model(.sc1)
        XCTAssertGreaterThan(cafCab.maximum.z,cafSC.maximum.z+0.10)
        XCTAssertGreaterThan(citSC.maximum.z,citCab.maximum.z+0.10)
        let central=Map3DKaohsiungCitadis.model(.np)
        XCTAssertTrue(central.vertices.contains { $0.x>0.9 && $0.z>3.45 },"separate compact E-collect missing")
        let caf=Map3DKaohsiungCAF.model(.r)
        XCTAssertFalse(caf.vertices.contains { $0.x>0.9 && $0.z>3.45 },"CAF acquired Alstom collector")
    }
}
