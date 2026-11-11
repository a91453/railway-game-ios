import Foundation
@testable import GamePresentation
import XCTest

final class Map3DStationKitTests: XCTestCase {
    private let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testEveryBundledStationHasExactlyOneRecipeAndItsRealSourcePoint() throws {
        let data=try Data(contentsOf:root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/track_stations.geojson"))
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        let features=try XCTUnwrap(json["features"] as? [[String:Any]])
        var expected=Set<String>()
        for f in features {
            let p=try XCTUnwrap(f["properties"] as? [String:Any]),name=try XCTUnwrap(p["name"] as? String),system=try XCTUnwrap(p["sys"] as? String)
            expected.insert(system+"|"+name)
        }
        let stations=Map3DStationKit.stations
        XCTAssertEqual(Set(stations.map { $0.system+"|"+$0.name }),expected)
        XCTAssertEqual(Set(stations.map(\.id)).count,stations.count)
        XCTAssertEqual(stations.count,544)
        for s in stations {
            XCTAssertTrue((-90...90).contains(s.latitude) && (-180...180).contains(s.longitude))
            XCTAssertFalse(s.lines.isEmpty)
            XCTAssertEqual(s.planned,s.system=="sanying")
        }
    }
    func testNamedStationsKeepDistinctLandmarkProfiles() throws {
        let stations=Map3DStationKit.stations
        for (name,profile) in [("臺北",Map3DStationKit.Profile.taipei),("臺中",.taichung),("高雄",.kaohsiung)] {
            let s=try XCTUnwrap(stations.first { $0.system=="tra_sched" && $0.name==name })
            XCTAssertEqual(s.profile,profile);XCTAssertTrue(s.isLandmark)
        }
        let hero=stations.filter { $0.system=="tra_sched" && [.taipei,.taichung,.kaohsiung].contains($0.profile) }.map(Map3DStationKit.model(for:))
        XCTAssertEqual(Set(hero.map(\.triangleCount)).count,3,"different structures, rather than renamed copies")
        XCTAssertNil(Map3DStationKit.model(id:"missing-station"))
    }
    /// model-look's trial: Zhuifen is the Coast Line timber hall, not the
    /// brick archetype: a gabled roof whose ridge runs along the platforms,
    /// a cross gable up to the ridge over the platform side only, and a
    /// lean-to roof along both long sides whose posts stand on the ground.
    func testZhuifenIsATimberHallWithACrossGableOverThePlatformSide() throws {
        let station=try XCTUnwrap(Map3DStationKit.stations.first { $0.system=="tra_sched" && $0.name=="追分" })
        XCTAssertEqual(station.profile,.coastTimber);XCTAssertTrue(station.isLandmark)
        var builder=StationKitBuilder();builder.house(station)
        // Native axes: x front, y left, z up; the hall's walls at x ±4.
        let v=Map3DModelPack.Model.flat(named:"zhuifen",from:builder.mesh).vertices
        let ridge=try XCTUnwrap(v.map(\.z).max())
        XCTAssertEqual(ridge,8.8,accuracy:0.3)
        // The ridge runs the hall's whole length.
        XCTAssertTrue(v.contains { $0.z>ridge-0.4 && $0.y>10 } && v.contains { $0.z>ridge-0.4 && $0.y < -10 })
        // The cross gable reaches past the platform-side wall near the ridge's height; nothing does at the front.
        XCTAssertTrue(v.contains { $0.x < -4.9 && $0.z>8 })
        XCTAssertFalse(v.contains { $0.x>4.9 && $0.z>6 })
        // Lean-to roofs both sides, below the high windows, and posts under them down to the forecourt.
        for side: Float in [-1,1] {
            XCTAssertTrue(v.contains { $0.x*side>5.8 && (2.8...3.6).contains($0.z) },"lean-to \(side)")
            XCTAssertTrue(v.contains { $0.x*side>5.5 && $0.x*side<6.1 && $0.z<0.3 },"post \(side)")
        }
    }
    func testLightRailAndElevatedCatalogLinesUseAppropriateGameArchetypes() {
        let stations=Map3DStationKit.stations
        let light=stations.filter { $0.system=="krtc" && $0.lines.contains("C") }
        XCTAssertGreaterThan(light.count,30)
        XCTAssertTrue(light.allSatisfy { $0.profile == .lightRail })
        let elevated=stations.filter { $0.system=="mrt" && $0.lines.contains(where: { ["BR","Y"].contains($0) }) }
        XCTAssertGreaterThan(elevated.count,30)
        XCTAssertTrue(elevated.allSatisfy { $0.profile == .elevated })
    }
    func testAllModelsAreOpaqueFiniteHaveUndersidesAndStayWithinTheNativeBudget() {
        let models=Map3DStationKit.stations.map(Map3DStationKit.model(for:))+Map3DStationKit.Part.allCases.map(Map3DStationKit.model(for:))+[Map3DStationKit.exampleModel()]
        for model in models {
            XCTAssertGreaterThan(model.triangleCount,0,model.name)
            XCTAssertLessThanOrEqual(model.triangleCount,Map3DModelFile.maximumTriangles,model.name)
            XCTAssertTrue(model.vertices.contains { $0.nz < -0.5 },"missing underside: "+model.name)
            XCTAssertGreaterThan(model.maximum.z-model.minimum.z,0.01,model.name)
            for v in model.vertices {
                XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite),model.name)
                XCTAssertEqual(v.color>>24,255,model.name)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001,model.name)
            }
        }
    }
    func testModularPartsHaveNamesMountsAndConnectorsInNativeCoordinates() {
        let parts=Map3DStationKit.Part.allCases
        XCTAssertEqual(parts.count,96);XCTAssertEqual(Set(parts.map(\.id)).count,96)
        XCTAssertEqual(parts.filter { $0.category=="building-part" }.count,32)
        XCTAssertEqual(Map3DStationKit.Part.acBracket.mount,.wall)
        for p in parts {
            XCTAssertFalse(p.name.isEmpty)
            for c in p.connectors { XCTAssertEqual(c.normal.dot(c.normal),1,accuracy:0.0001,p.id) }
        }
        let platform=Map3DStationKit.model(for:.platformStraight)
        XCTAssertEqual(platform.minimum.x,-4,accuracy:0.001)
        XCTAssertEqual(platform.maximum.x,4,accuracy:0.001)
        XCTAssertTrue(Map3DStationKit.Part.wallWindow.connectors.contains { $0.name=="next-floor" && $0.position.z==3.2 })
    }
    func testPlatformCanopyHasNoGapAboveItsSupportColumns() {
        let m=Map3DStationKit.model(for:.platformCanopy),steel=Map3DPalette.tankStand
        let roofColors=Set([Map3DPalette.canopy,Map3DColor.shaded(Map3DPalette.canopy,0.7)])
        var roof: [Map3DVertex]=[]
        for i in stride(from:0,to:m.vertices.count,by:3) {
            let t=m.vertices[i..<i+3]
            if t.allSatisfy({ roofColors.contains($0.color) }) { roof += t }
        }
        var caps=0
        for i in stride(from:0,to:m.vertices.count,by:3) {
            let t=Array(m.vertices[i..<i+3])
            guard t.allSatisfy({ $0.color==steel && $0.nz>0.9 }) else { continue }
            let p=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
            // Start below the cap and query only the roof. A cap that embeds
            // a few millimetres in a curved roof is supported, not floating.
            XCTAssertLessThan(nearest(from:p-Map3DPoint(0,0,0.05),direction:Map3DPoint(0,0,1),in:roof)-0.05,0.04,"floating roof above \(p)")
            caps+=1
        }
        XCTAssertGreaterThan(caps,0)
    }
    func testWindowAndBalconyPanesAreBackedByWalls() {
        for part in [Map3DStationKit.Part.wallWindow,.wallTwinWindow,.wallDoor,.balcony,.arcadeBay] {
            let m=Map3DStationKit.model(for:part)
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=Array(m.vertices[i..<i+3])
                guard t.allSatisfy({ $0.color==Map3DPalette.glazing && $0.nx>0.9 }) else { continue }
                let p=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
                XCTAssertLessThan(nearest(from:p-Map3DPoint(0.001,0,0),direction:Map3DPoint(-1,0,0),in:m.vertices),0.12,part.id)
            }
        }
    }
    func testOnDemandPackAndRebuildingAreDeterministic() throws {
        let s=try XCTUnwrap(Map3DStationKit.stations.first { $0.profile == .taipei })
        let a=Map3DStationKit.model(for:s)
        let pack=Map3DModelPack(stationKit:[s],parts:[.wallWindow],includeStandard:false)
        XCTAssertEqual(pack.models.count,2);XCTAssertEqual(pack.index(of:s.id),0)
        _=Map3DStationKit.model(for:.waterTank)
        XCTAssertEqual(Map3DStationKit.model(for:s).vertices,a.vertices)
    }
    private func nearest(from origin: Map3DPoint,direction: Map3DPoint,in vertices: [Map3DVertex]) -> Float {
        var nearest=Float.infinity
        for i in stride(from:0,to:vertices.count,by:3) {
            let p=vertices[i..<i+3].map { Map3DPoint($0.x,$0.y,$0.z) },e=p[1]-p[0],f=p[2]-p[0],h=direction.cross(f),det=e.dot(h)
            if abs(det)<0.000001 { continue }
            let s=origin-p[0],u=s.dot(h)/det,q=s.cross(e),v=direction.dot(q)/det,d=f.dot(q)/det
            if u >= -0.00001 && v >= -0.00001 && u+v<=1.00001 && d>0.0001 { nearest=min(nearest,d) }
        }
        return nearest
    }
}
