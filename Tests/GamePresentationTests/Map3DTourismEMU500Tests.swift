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

    // MARK: Decision 554: the running Hai-Feng and Shan-Lan

    private func payload(_ model: Map3DModelPack.Model) -> [UInt32] {
        model.vertices.flatMap { v in
            [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern, v.nx.bitPattern, v.ny.bitPattern, v.nz.bitPattern,
             v.color, v.u.bitPattern, v.v.bitPattern, v.layer.bitPattern]
        }
    }

    func testTheTwoSightseeingTrainsRunTheirOwnSetsNearAndFar() throws {
        XCTAssertEqual(Map3DTrainSet.key(type: .haiFeng, performance: .haiFeng), "HAIFENG")
        XCTAssertEqual(Map3DTrainSet.key(type: .shanLan, performance: .haiFeng), "SHANLAN")
        for key in ["HAIFENG", "SHANLAN"] {
            XCTAssertEqual(Map3DTrainSet.named(key)?.far, key + "Far")
            XCTAssertNotNil(Map3DTrainSet.named(key + "Far"))
            XCTAssertTrue(Map3DTrainSet.nearOnly.contains(key))
            XCTAssertFalse(TrainPack.sets.contains(key))
            XCTAssertEqual(Map3DTrainSet.variant(of: key, number: 7), key)
        }
    }

    /// Four cars as they run, EMC EP ET EM, each its own length, the EM
    /// the tail model (not the head turned round); other lengths keep the
    /// order from the front.
    func testTheFormationAtItsOwnLengths() throws {
        let pack = Map3DModelPack.standard
        func names(_ key: String, _ count: Int) throws -> [String] {
            try XCTUnwrap(pack.layout(forType: key, count: count), key).map { pack.models[$0.model].name }
        }
        for key in ["HAIFENG", "SHANLAN"] {
            XCTAssertEqual(try names(key, 4), ["set-\(key)-head", "set-\(key)-panto", "set-\(key)-car", "set-\(key)-tail"])
            XCTAssertEqual(try names(key, 2), ["set-\(key)-head", "set-\(key)-tail"])
            XCTAssertEqual(try names(key, 6), ["set-\(key)-head", "set-\(key)-panto", "set-\(key)-car",
                                               "set-\(key)-panto", "set-\(key)-car", "set-\(key)-tail"])
            let laid = try XCTUnwrap(pack.layout(forType: key, count: 4))
            XCTAssertTrue(laid.allSatisfy { $0.gap == 0 })
            for car in laid { XCTAssertEqual(car.length, 20.33, accuracy: 0.05) }
            for count in 2...8 { XCTAssertFalse(pack.isTurned(forType: key, carIndex: count - 1, count: count)) }
            for index in 0..<4 {
                let near = try XCTUnwrap(pack.modelIndex(forType: key, carIndex: index, count: 4))
                let far = try XCTUnwrap(pack.farModel(of: near, forType: key, count: 4))
                XCTAssertEqual(pack.models[far].name, pack.models[near].name.replacingOccurrences(of: key, with: key + "Far"))
            }
        }
    }

    /// The set's cars are #1539's units to the bit, but the cabs' lamp
    /// lenses lit (white at the front, red at the back) and the EM turned.
    func testTheSetsCarsAreTheStudysUnits() throws {
        let unbaked = Map3DModelPack.unbaked
        for fleet in Map3DTourismEMU500.Fleet.allCases {
            let key = fleet == .haifeng ? "HAIFENG" : "SHANLAN"
            for far in [false, true] {
                let set = far ? key + "Far" : key
                func recipe(_ unit: String) throws -> Map3DModelPack.Model {
                    unbaked.models[try XCTUnwrap(unbaked.index(of: "set-\(set)-\(unit)"), unit)]
                }
                XCTAssertEqual(payload(try recipe("panto")), payload(Map3DTourismEMU500.model(fleet, .ep, far: far)))
                XCTAssertEqual(payload(try recipe("car")), payload(Map3DTourismEMU500.model(fleet, .et, far: far)))
                let head = try recipe("head"), emc = Map3DTourismEMU500.model(fleet, .emc, far: far)
                XCTAssertEqual(head.vertices.map(\.position), emc.vertices.map(\.position))
                let tail = try recipe("tail"), em = Map3DTourismEMU500.model(fleet, .em, far: far).turned
                XCTAssertEqual(tail.vertices.map(\.position), em.vertices.map(\.position))
                XCTAssertTrue(head.vertices.filter(\.glows).allSatisfy { $0.x > 9 && $0.color == Map3DTrainStyle.headlamp })
                XCTAssertTrue(tail.vertices.filter(\.glows).allSatisfy { $0.x < -9 && $0.color == Map3DPalette.lantern })
                XCTAssertFalse(head.vertices.filter(\.glows).isEmpty)
                XCTAssertFalse(tail.vertices.filter(\.glows).isEmpty)
            }
        }
    }
}
