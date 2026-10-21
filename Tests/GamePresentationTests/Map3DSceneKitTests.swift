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
        let nativeIDs=Set(Map3DSceneKit.assets.map(\.id))
        XCTAssertTrue(ids.isSubset(of:nativeIDs),"keep all original subjects when adding recipes")
        XCTAssertEqual(Map3DSceneKit.assets.count,nativeIDs.count,"native IDs are unique")
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

    func testResidentialGlazingHasAWallImmediatelyBehindItIncludingTheArcade() {
        for variant in 0..<6 {
            var builder=SceneKitBuilder()
            builder.home(x:0,z:0,length:9,width:6,floors:3,variant:variant)
            let vertices=Map3DModelPack.Model.flat(named:"house",from:builder.mesh).vertices
            for i in stride(from:0,to:vertices.count,by:3) {
                let triangle=Array(vertices[i..<i+3])
                guard triangle.allSatisfy({ $0.color == SceneKitBuilder.glass }) else { continue }
                let a=triangle[0],normal=Map3DPoint(a.nx,a.ny,a.nz)
                guard abs(normal.z)<0.1 else { continue }
                let centre=triangle.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
                let distance=nearestSurface(from:centre-normal*0.001,direction: -normal,vertices:vertices)
                XCTAssertLessThan(distance,0.12,"Floating pane in variant \(variant) at \(centre)")
            }
        }
    }

    func testExposedTrainEndsHaveGlazingAndMarkerLights() {
        // Native box faces shade palette colours; swept panes keep the base.
        let glazing=Set([Float(1),0.92,0.80,0.70,0.86].map { Map3DColor.shaded(Map3DTrainStyle.glass,$0) })
        for asset in Map3DSceneKit.assets where [.traModern,.traClassic,.metro,.lightRail].contains(asset.family) {
            let model=Map3DSceneKit.model(for:asset)
            for sign: Float in [-1,1] {
                let end=sign>0 ? model.maximum.x : -model.minimum.x
                XCTAssertTrue(model.vertices.contains {
                    $0.x*sign>end-model.length*0.24 && $0.nx*sign>0.1 && glazing.contains($0.color)
                },"Missing outward glazing: \(asset.id), end \(sign)")
                XCTAssertTrue(model.vertices.contains {
                    $0.x*sign>end-model.length*0.24 && $0.glows
                },"Missing end marker lights: \(asset.id), end \(sign)")
            }
        }
    }

    func testFrontWindscreenRemainsVisibleAcrossTheCurvedNose() throws {
        let asset=try XCTUnwrap(Map3DSceneKit.asset(id:"01_TRA_modern_3x2-01"))
        let model=Map3DSceneKit.model(for:asset)
        for lateral: Float in [-0.4,0,0.4] {
            for height: Float in [2.05,2.35,2.65] {
                let hit=nearestHit(from:Map3DPoint(model.maximum.x+1,lateral,height),direction:Map3DPoint(-1,0,0),vertices:model.vertices)
                XCTAssertEqual(hit.color,Map3DTrainStyle.glass,"Windscreen sinks through the nose at \(lateral), \(height)")
            }
        }
        let puyuma=Map3DSceneKit.model(for:try XCTUnwrap(Map3DSceneKit.asset(id:"01_TRA_modern_3x2-02")))
        for lateral: Float in [-0.3,0,0.3] {
            for height: Float in [1.25,1.5] {
                let hit=nearestHit(from:Map3DPoint(puyuma.maximum.x+1,lateral,height),direction:Map3DPoint(-1,0,0),vertices:puyuma.vertices)
                XCTAssertEqual(hit.color,Map3DPalette.lantern,"Puyuma's red face has a gap")
            }
        }
    }

    private func nearestSurface(from origin: Map3DPoint,direction: Map3DPoint,vertices: [Map3DVertex]) -> Float {
        nearestHit(from:origin,direction:direction,vertices:vertices).distance
    }

    private func nearestHit(from origin: Map3DPoint,direction: Map3DPoint,vertices: [Map3DVertex]) -> (distance: Float,color: UInt32) {
        var nearest=Float.infinity,color: UInt32=0
        for i in stride(from:0,to:vertices.count,by:3) {
            let points=vertices[i..<i+3].map { Map3DPoint($0.x,$0.y,$0.z) }
            let e1=points[1]-points[0],e2=points[2]-points[0],h=direction.cross(e2),det=e1.dot(h)
            if abs(det)<0.000001 { continue }
            let s=origin-points[0],u=s.dot(h)/det
            if u < -0.00001 || u>1.00001 { continue }
            let q=s.cross(e1),v=direction.dot(q)/det
            if v < -0.00001 || u+v>1.00001 { continue }
            let distance=e2.dot(q)/det
            if distance>0.0001 && distance<nearest { nearest=distance;color=vertices[i].color }
        }
        return (nearest,color)
    }
}
