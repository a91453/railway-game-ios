import Foundation
@testable import GamePresentation
import XCTest

final class Map3DSceneKitTests: XCTestCase {
    private let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testEveryRequestedImageSubjectHasANativeRecipe() throws {
        let path=root.appendingPathComponent("docs/art/generated-2026-10-21-scene-kit/manifest.json")
        let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
        let sheets=try XCTUnwrap(manifest["assets"] as? [[String:Any]])
        let ids=Set(sheets.flatMap { ($0["frames"] as? [[String:Any]] ?? []).compactMap { $0["id"] as? String } })
        XCTAssertEqual(ids.count,156)
        XCTAssertEqual(Set(Map3DSceneKit.assets.map(\.id)),ids)
        XCTAssertEqual(Map3DSceneKit.assets.count,ids.count,"native IDs are unique")
        XCTAssertNil(Map3DSceneKit.asset(id:"not-an-asset"))
    }

    func testAllGeometryIsFiniteOpaqueWithinBudgetAndFacesEveryDirection() {
        let directions=[Map3DPoint(1,0,0),Map3DPoint(-1,0,0),Map3DPoint(0,1,0),Map3DPoint(0,-1,0),Map3DPoint(0,0,1),Map3DPoint(0,0,-1)]
        for asset in Map3DSceneKit.assets {
            let model=Map3DSceneKit.model(for:asset)
            XCTAssertEqual(model.name,asset.id)
            XCTAssertGreaterThan(model.triangleCount,0,asset.id)
            XCTAssertLessThanOrEqual(model.triangleCount,Map3DModelFile.maximumTriangles,asset.id)
            for direction in directions {
                XCTAssertTrue(model.vertices.contains { Map3DPoint($0.nx,$0.ny,$0.nz).dot(direction)>0.1 },"Missing side \(direction) for \(asset.id)")
            }
            for v in model.vertices {
                XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite),asset.id)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001,asset.id)
                XCTAssertEqual(v.color>>24,255,"No unresolved instance tint in \(asset.id)")
                XCTAssertTrue(v.layer==Map3DVertex.plain || v.layer==Map3DVertex.glowing,"No private texture layers")
            }
        }
    }

    func testRebuildingDoesNotDependOnOrderTimeOrARandomSeed() throws {
        let ids=["01_TRA_modern_3x2-01","02_HSR_MRT_3x2-01","07_residential_low-04","09_residential_high-06","14_public_services-03","18_roads_plazas-04"]
        let assets=try ids.map { try XCTUnwrap(Map3DSceneKit.asset(id:$0)) }
        let first=assets.map { Map3DSceneKit.model(for:$0).vertices }
        for (i,asset) in assets.enumerated().reversed() {
            XCTAssertEqual(Map3DSceneKit.model(for:asset).vertices,first[i])
        }
    }

    func testNativeRendererPackCanLookUpTheModelsWithoutASeparateFormat() throws {
        let house=try XCTUnwrap(Map3DSceneKit.asset(id:"07_residential_low-01"))
        let station=try XCTUnwrap(Map3DSceneKit.asset(id:"03_stations_3x3-01"))
        let pack=Map3DModelPack(sceneKit:[house,station],includeStandard:false)
        XCTAssertEqual(pack.models.count,2)
        XCTAssertEqual(pack.index(of:station.id),1)
        XCTAssertEqual(pack.models[0].vertices,Map3DSceneKit.model(for:house).vertices)
        let combined=Map3DModelPack(sceneKit:[station])
        XCTAssertEqual(combined.index(of:station.id),Map3DModelPack.standard.models.count)
        XCTAssertEqual(Array(combined.models.prefix(Map3DModelPack.standard.models.count)).map(\.name),Map3DModelPack.standard.models.map(\.name))
    }

    func testModelsHaveRealDepthRoofsUndersidesAndDifferentTransportScales() throws {
        func model(_ id: String) throws -> Map3DModelPack.Model { Map3DSceneKit.model(for:try XCTUnwrap(Map3DSceneKit.asset(id:id))) }
        let house=try model("07_residential_low-01")
        XCTAssertGreaterThan(house.maximum.z,8)
        XCTAssertGreaterThan(house.maximum.y-house.minimum.y,5)
        XCTAssertTrue(house.vertices.contains { $0.nz < -0.9 && $0.z<0.01 },"closed foundation visible from below")
        let entrance=try model("03_stations_3x3-04")
        XCTAssertLessThan(entrance.minimum.z,-2,"stairs descend below street level")
        let railbus=try model("05_TRA_classic_3x2-03"),hsr=try model("02_HSR_MRT_3x2-01")
        XCTAssertGreaterThan(hsr.length,railbus.length*2)
        let bridge=try model("04_tracks_props_4x3-06")
        XCTAssertGreaterThan(bridge.maximum.z,10)
        let pole=try model("17_street_props-12")
        XCTAssertGreaterThan(pole.maximum.z,9)
    }

    func testCommittedModelsReadThroughTheNativeLoaderAndMatchTheirRecipes() throws {
        let folder=root.appendingPathComponent("docs/art/generated-2026-10-21-scene-kit/native3d/models")
        for asset in Map3DSceneKit.assets {
            let data=try Data(contentsOf:folder.appendingPathComponent(asset.id+".m3dmodel"))
            let decoded=try Map3DModelFile(decoding:data,named:asset.id)
            XCTAssertEqual(decoded.model.vertices,Map3DSceneKit.model(for:asset).vertices,asset.id)
            let provenance=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(decoded.provenance.utf8)) as? [String:Any])
            let extra=try XCTUnwrap(provenance["extras"] as? [String:Any])
            XCTAssertEqual(extra["assetId"] as? String,asset.id)
            XCTAssertEqual(extra["source"] as? String,"native-procedural")
        }
    }
}
