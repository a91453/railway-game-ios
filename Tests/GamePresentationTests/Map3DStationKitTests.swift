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
    /// model-look: Bao'an is its own low timber hall, not the brick
    /// archetype: a hip-and-gable roof whose ridge stops short of the
    /// hipped ends, a skirt roof below the eaves (deep over the platform
    /// side, on posts down to the ground, the name signs on its edge), a
    /// gabled porch at the front only, and the palm taller than the ridge.
    func testBaoanIsALowTimberHallUnderAHipAndGableRoof() throws {
        let station=try XCTUnwrap(Map3DStationKit.stations.first { $0.system=="tra_sched" && $0.name=="保安" })
        XCTAssertEqual(station.profile,.baoan);XCTAssertTrue(station.isLandmark)
        var builder=StationKitBuilder();builder.house(station)
        // Native axes: x front, y left, z up; the hall's walls at x ±3.4, its ends at y ±8.5.
        let v=Map3DModelPack.Model.flat(named:"baoan",from:builder.mesh).vertices
        // The middle of the hall, clear of the palm's fronds over the front eaves.
        let hall=v.filter { abs($0.x)<3 }
        let ridge=try XCTUnwrap(hall.map(\.z).max())
        XCTAssertEqual(ridge,7.6,accuracy:0.4)
        // Hipped at the ends: the eaves reach past the end walls, the ridge stops short of them.
        XCTAssertTrue(v.contains { abs($0.x)<4.2 && abs($0.y)>9 && $0.z>4 && $0.z<5 })
        XCTAssertFalse(hall.contains { abs($0.y)>7.6 && $0.z>6.5 })
        // A gable under each end of the ridge, set back from the hip below it.
        for end: Float in [-1,1] { XCTAssertTrue(hall.contains { abs($0.x)<0.01 && abs($0.y*end-6.6)<0.1 && $0.z>7.2 },"gable \(end)") }
        // The skirt roof below the eaves: shallow at the front, deep over the platform side, on posts.
        XCTAssertTrue(v.contains { $0.x>4.6 && $0.x<4.8 && (2.8...3.2).contains($0.z) })
        XCTAssertTrue(v.contains { $0.x < -6.3 && (2.8...3.2).contains($0.z) })
        XCTAssertTrue(v.contains { $0.x < -6.0 && $0.x > -6.4 && $0.z<0.3 })
        // The name signs stand on the platform side's edge; the porch's gable is before the front.
        XCTAssertTrue(v.contains { $0.x < -6.2 && $0.x > -6.5 && $0.z>3.9 })
        XCTAssertTrue(v.contains { $0.x>5.5 && (1.2...3).contains($0.y) && $0.z>4.3 })
        XCTAssertFalse(v.contains { $0.x < -4.2 && $0.z>4.3 })
        XCTAssertTrue(v.contains { $0.x>5 && $0.z>ridge+2 },"the palm")
    }
    /// model-look: Jiji is its own timber hall, not the green hipped
    /// archetype: a tall gabled roof whose ridge runs along the platforms,
    /// a low veranda roof on posts round all four sides, and the name
    /// boards' small gable breaking the veranda at the front only.
    func testJijiIsAGabledHallInsideAVerandaWithItsNameGableAtTheFront() throws {
        let station=try XCTUnwrap(Map3DStationKit.stations.first { $0.system=="tra_sched" && $0.name=="集集" })
        XCTAssertEqual(station.profile,.jiji);XCTAssertTrue(station.isLandmark)
        var builder=StationKitBuilder();builder.house(station)
        // Native axes: x front, y left, z up; the hall's walls at x ±3.6, y ±7.9.
        let v=Map3DModelPack.Model.flat(named:"jiji",from:builder.mesh).vertices
        let ridge=try XCTUnwrap(v.map(\.z).max())
        XCTAssertEqual(ridge,7.5,accuracy:0.3)
        XCTAssertTrue(v.contains { $0.z>ridge-0.4 && $0.y>7 } && v.contains { $0.z>ridge-0.4 && $0.y < -7 })
        XCTAssertFalse(v.contains { $0.color==Map3DPalette.gymGreen },"the archetype's green roof")
        // The veranda's eaves, well below the hall's (4.5 m), past each wall, and a post's foot under each.
        let eaves: ClosedRange<Float>=2.9...3.3
        XCTAssertTrue(v.contains { $0.x>6.4 && eaves.contains($0.z) } && v.contains { $0.x>6 && $0.x<6.7 && $0.z<0.3 },"front")
        XCTAssertTrue(v.contains { $0.x < -5.8 && eaves.contains($0.z) } && v.contains { $0.x < -5.5 && $0.z<0.3 },"platform side")
        for end: Float in [-1,1] {
            XCTAssertTrue(v.contains { $0.y*end>11.6 && eaves.contains($0.z) } && v.contains { $0.y*end>11.4 && abs($0.x)<4 && $0.z<0.3 },"end \(end)")
        }
        // The name gable stands above the veranda's eaves at the front, and nothing does at the back.
        XCTAssertTrue(v.contains { $0.x>6.9 && $0.x<7.6 && $0.z>4.2 })
        XCTAssertFalse(v.contains { $0.x < -5.8 && $0.z>3.4 })
    }
    /// Decision 705: the boards carry the station's name in strokes, not a
    /// block of colour: every character the two stations hang has strokes,
    /// each a flat quad on the board's face, inside its square, read from
    /// the side the board faces.
    func testNameBoardsCarryTheirCharactersInStrokesOnTheBoardsFace() throws {
        for character in "集集車站〇保安車站" { XCTAssertGreaterThan(StationKitBuilder.nameStrokes[character]?.count ?? 0,5,"\(character)") }
        for facing: Float in [1,-1] {
            var plain=StationKitBuilder();plain.nameBoards("",x:2,y:3,z:1,facing:facing,size:1,pitch:1.2,board:StationKitBuilder.white,ink:StationKitBuilder.ink)
            XCTAssertTrue(plain.mesh.isEmpty)
            var builder=StationKitBuilder();builder.nameBoards("車站",x:2,y:3,z:1,facing:facing,size:1,pitch:1.2,board:StationKitBuilder.white,ink:StationKitBuilder.ink)
            let v=Map3DModelPack.Model.flat(named:"boards",from:builder.mesh).vertices,ink=v.filter { $0.color==StationKitBuilder.ink }
            XCTAssertEqual(ink.count,(8+11)*6)
            // Native axes: x front, y left, z up. On the face, a little before it, within the two boards.
            XCTAssertTrue(ink.allSatisfy { abs($0.x-(2+facing*0.012))<0.001 && (3.05...3.95).contains($0.z) && abs($0.y+1)<1.1 })
            // Read left to right from the side it faces: 車 (only its upright reaches the cell's foot) is on the
            // reader's left, which is the model's right (−y) before a board that faces the front.
            let foot=try XCTUnwrap(ink.map(\.z).min()),left=ink.filter { $0.z==foot }.map(\.y)
            XCTAssertTrue(left.allSatisfy { ($0+1)*facing < -0.4 },"車 on the reader's left, facing \(facing)")
        }
    }
    /// Decision 705: what shows of the two stations from straight above:
    /// Jiji's red lanterns hang past its veranda's eaves, front and ends,
    /// and both tiled roofs carry courses a shade darker than their tiles.
    func testJijiAndBaoanShowTheirLanternsAndTileCoursesFromAbove() throws {
        func house(_ name: String) throws -> [Map3DVertex] {
            let station=try XCTUnwrap(Map3DStationKit.stations.first { $0.system=="tra_sched" && $0.name==name })
            var builder=StationKitBuilder();builder.house(station)
            return Map3DModelPack.Model.flat(named:name,from:builder.mesh).vertices
        }
        let jiji=try house("集集"),lanterns=jiji.filter { $0.color==Map3DPalette.lantern }
        XCTAssertTrue(lanterns.contains { $0.x>6.8 } && lanterns.contains { $0.y>12.1 } && lanterns.contains { $0.y < -12.1 })
        XCTAssertFalse(lanterns.contains { $0.x < -4 },"none over the platform side")
        XCTAssertTrue(lanterns.allSatisfy { $0.z<3.1 && $0.z>2.1 },"hung under the eaves")
        let course=Map3DColor.shaded(StationKitBuilder.tile,0.8)
        XCTAssertTrue(jiji.contains { $0.color==course && $0.z>5.5 && $0.x>0 } && jiji.contains { $0.color==course && $0.z>5.5 && $0.x<0 })
        let baoan=try house("保安"),baoanCourse=Map3DColor.shaded(StationKitBuilder.tile,0.78)
        XCTAssertTrue(baoan.contains { $0.color==baoanCourse && $0.z>6.2 } && baoan.contains { $0.color==baoanCourse && $0.z<5.6 })
        // Bao'an's row on the platform side: the railway's mark and four characters, in the sign blue.
        let blue: UInt32=Map3DPalette.canopy,edge: Float = -6.3,strokes: Int=48*6
        XCTAssertEqual(baoan.filter { $0.color==blue && $0.x<edge }.count,strokes)
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
