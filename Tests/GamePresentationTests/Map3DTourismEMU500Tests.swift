import XCTest
@testable import GamePresentation

final class Map3DTourismEMU500Tests: XCTestCase {
    func testEveryRoleHasIndependentLegalNearAndFarStudy() {
        let pack=Map3DModelPack.studies
        for fleet in Map3DTourismEMU500.Fleet.allCases {
            for role in Map3DTourismEMU500.order {
                let near=Map3DTourismEMU500.model(fleet,role)
                let far=Map3DTourismEMU500.model(fleet,role,far:true)
                XCTAssertNotNil(pack.index(of:near.name));XCTAssertNotNil(pack.index(of:far.name))
                XCTAssertNil(Map3DModelPack.standard.index(of:near.name))
                XCTAssertLessThanOrEqual(near.triangleCount,Map3DModelFile.maximumTriangles)
                XCTAssertLessThan(far.triangleCount*2,near.triangleCount)
                XCTAssertEqual(near.minimum,far.minimum);XCTAssertEqual(near.maximum,far.maximum)
                XCTAssertEqual(near.minimum.z,0,accuracy:0.00001)
                if role == .ep { XCTAssertGreaterThan(near.maximum.z,4.9) }
                else { XCTAssertLessThan(near.maximum.z,4.0) }
                // A conversion changes actual openings, not just their colour.
                let base=Map3DEMU500.model(role)
                XCTAssertNotEqual(near.vertices.map(\.position),base.vertices.map(\.position))
            }
        }
    }
    func testTheTwoIdentitiesAreSeparateWithoutInventingAnUnprovenDifferentBody() {
        for role in Map3DTourismEMU500.order {
            for far in [false,true] {
                let a=Map3DTourismEMU500.model(.haifeng,role,far:far)
                let b=Map3DTourismEMU500.model(.shanlan,role,far:far)
                XCTAssertNotEqual(a.name,b.name)
                XCTAssertEqual(a.vertices.map(\.position),b.vertices.map(\.position))
                XCTAssertNotEqual(a.vertices.map(\.color),b.vertices.map(\.color))
            }
        }
    }
    func testIndependentSwiftAssemblyKeepsOrderSingleTailRotationAndRailPlane() {
        for fleet in Map3DTourismEMU500.Fleet.allCases {
            for far in [false,true] {
                let model=Map3DTourismEMU500.formation(fleet,far:far)
                var cursor=0
                for (i,role) in Map3DTourismEMU500.order.enumerated() {
                    let part=Map3DTourismEMU500.model(fleet,role,far:far)
                    let sign:Float=i == 3 ? -1:1
                    for v in part.vertices {
                        let a=model.vertices[cursor];cursor+=1
                        XCTAssertEqual(a.x,sign*v.x+Map3DTourismEMU500.centres[i],accuracy:0.00001)
                        XCTAssertEqual(a.y,sign*v.y,accuracy:0.00001)
                        XCTAssertEqual(a.z,v.z);XCTAssertEqual(a.color,v.color)
                    }
                }
                XCTAssertEqual(cursor,model.vertices.count)
                XCTAssertEqual(model.minimum.z,0,accuracy:0.00001)
            }
        }
    }
}
