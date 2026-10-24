import Foundation
@testable import GamePresentation
import XCTest

final class Map3DRecreationKitTests: XCTestCase {
    func test24UniqueAssetsAndFourCategories() {
        let parts=Map3DRecreationKit.Part.allCases
        XCTAssertEqual(parts.count,24);XCTAssertEqual(Set(parts.map(\.id)).count,24)
        for c in Map3DRecreationKit.Category.allCases { XCTAssertEqual(parts.filter { $0.category==c }.count,6) }
        let models=parts.map(Map3DRecreationKit.model(for:))
        for i in models.indices { for j in 0..<i { XCTAssertNotEqual(models[i].vertices,models[j].vertices) } }
    }
    func testMeshesGroundFeetNormalsAndLoaderBudget() {
        let models=Map3DRecreationKit.Part.allCases.map(Map3DRecreationKit.model(for:))+Map3DRecreationKit.Example.allCases.map(Map3DRecreationKit.model(for:))
        for m in models {
            XCTAssertEqual(m.minimum.z,0,accuracy:0.001,m.name)
            XCTAssertGreaterThan(m.triangleCount,0);XCTAssertLessThanOrEqual(m.triangleCount,Map3DModelFile.maximumTriangles,m.name)
            XCTAssertTrue(m.vertices.contains { $0.nz < -0.5 },m.name)
            for v in m.vertices {
                XCTAssertTrue([v.x,v.y,v.z,v.nx,v.ny,v.nz].allSatisfy(\.isFinite),m.name)
                XCTAssertEqual(v.color>>24,255,m.name)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001,m.name)
            }
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=m.vertices[i..<i+3].map { Map3DPoint($0.x,$0.y,$0.z) },n=(t[1]-t[0]).cross(t[2]-t[0])
                XCTAssertGreaterThan(n.dot(n),1e-15,m.name)
            }
        }
    }
    func testEveryExteriorWindowHasActualBacking() {
        var checked=0
        let glassColors=Set([Map3DPalette.glazing]+[Float(0.92),0.80,0.70,0.86].map { Map3DColor.shaded(Map3DPalette.glazing,$0) })
        for part in Map3DRecreationKit.Part.allCases {
            let m=Map3DRecreationKit.model(for:part)
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=Array(m.vertices[i..<i+3]);guard glassColors.contains(t[0].color) else { continue }
                let normal=Map3DPoint(t[0].nx,t[0].ny,t[0].nz)
                guard (t[0].color==Map3DPalette.glazing && abs(normal.x)>0.9) || abs(normal.y)>0.9 else { continue }
                let c=t.reduce(Map3DPoint.zero) { $0+Map3DPoint($1.x,$1.y,$1.z)*(1/3) }
                XCTAssertLessThan(ray(c+normal*0.001,normal * -1,m,excludingColors:glassColors),0.25,part.id+" window has no backing")
                checked+=1
            }
        }
        XCTAssertGreaterThan(checked,100)
    }

    func testAllVenueFrontColumnsMeetActualRoof() {
        let specs: [(Map3DRecreationKit.Part,Float,Float,Float)]=[(.fitnessStudio,10,12,3.5),(.multipurposeHall,14,18,5),(.bowlingLounge,16,10,3.6),(.swimPavilion,18,14,5),(.climbingHall,12,10,9),(.dojo,12,12,3.4)]
        for (p,l,w,h) in specs {
            let m=Map3DRecreationKit.model(for:p)
            for sign: Float in [-1,1] {
                XCTAssertLessThan(ray(.init(l/2-0.12,sign*(w/2-0.12),h+0.15),.init(0,0,1),m),0.1,p.id)
            }
            XCTAssertGreaterThan(ray(.init(l/2+0.3,0,1.2),.init(-1,0,0),m),l*0.8,p.id+" front opening must remain clear")
        }
    }
    func testTreadmillHandrailsMeetUprightsAndConsole() {
        let m=Map3DRecreationKit.model(for:.treadmill)
        for y: Float in [-0.43,0.43] {
            XCTAssertLessThan(ray(.init(0.75,y,1.34),.init(0,0,-1),m),0.10)
            XCTAssertLessThan(ray(.init(0.75,y,0.14),.init(0,0,-1),m),0.04)
        }
    }
    func testDumbbellPlatesRestOnShelves() {
        let m=Map3DRecreationKit.model(for:.dumbbellRack)
        for h: Float in [0.56,0.90] { for x: Float in [-0.6,0,0.6] { for y: Float in [-0.16,0.16] {
            XCTAssertLessThan(ray(.init(x,y,h+0.001),.init(0,0,-1),m,upwardOnly:true),0.01)
        } } }
    }
    func testClimbingHoldsHaveBacking() {
        let m=Map3DRecreationKit.model(for:.climbingWall)
        for i in 0..<7 {
            let h=0.6+Float(i)*0.55,x = -0.3+(h-0.16)/4.34
            XCTAssertLessThan(ray(.init(x+0.12,0,h+0.06),.init(-1,0,0),m,only:[Map3DPalette.tileWhite]),0.25)
        }
    }
    func testPoolDeckAndWaterContactsUseNativeUp() throws {
        let part=Map3DRecreationKit.Part.trainingPool,m=Map3DRecreationKit.model(for:part)
        let c=try XCTUnwrap(part.connectors.first { $0.name=="frontDeck" })
        XCTAssertEqual(c.normal,Map3DPoint(0,0,1))
        XCTAssertEqual(ray(c.position+Map3DPoint(0,0,0.02),.init(0,0,-1),m),0.02,accuracy:0.0001)
        let placements=Map3DRecreationKit.placements(for:.swimmingCenter)
        let pool=try XCTUnwrap(placements.first { $0.part == .trainingPool }),start=try XCTUnwrap(placements.first { $0.part == .startBlock })
        XCTAssertEqual(start.position.z-pool.position.z,c.position.z,accuracy:0.0001)
        XCTAssertEqual(start.support,"poolDeck")
    }
    func testDivingLadderAndCantileverReallyJoinPlatform() {
        let m=Map3DRecreationKit.model(for:.divingPlatform)
        XCTAssertLessThan(ray(.init(0.65,0,2.79),.init(0,0,-1),m,upwardOnly:true),0.03)
        for y: Float in [-0.6,0.6] { XCTAssertLessThan(ray(.init(-1,y,2.69),.init(0,0,-1),m),0.10) }
        for x: Float in [-1,1] { for y: Float in [-0.65,0.65] { XCTAssertLessThan(ray(.init(x,y,2.61),.init(0,0,1),m),0.05) } }
    }
    func testReturnBallActuallyTouchesBothRails() throws {
        let m=Map3DRecreationKit.model(for:.bowlingLane)
        let ball=m.vertices.filter { $0.x>1 && $0.color==Map3DPalette.player }
        let x=(try XCTUnwrap(ball.map(\.x).min())+XCTUnwrap(ball.map(\.x).max()))/2
        let y=(try XCTUnwrap(ball.map(\.y).min())+XCTUnwrap(ball.map(\.y).max()))/2
        for offset: Float in [-0.12,0.12] {
            let bottom=0.4+ray(.init(x,y+offset,0.4),.init(0,0,1),m,only:[Map3DPalette.player])
            let rail=1-ray(.init(x,y+offset,1),.init(0,0,-1),m,only:[Map3DPalette.tankStand])
            XCTAssertLessThanOrEqual(bottom,rail+0.005,"Return ball floats above rail")
            XCTAssertGreaterThanOrEqual(bottom,rail-0.04,"Return ball penetrates rail")
        }
    }
    func testBallCartWheelsReachTheActualBasketUnderside() {
        let m=Map3DRecreationKit.model(for:.ballCart),underside=Map3DColor.shaded(Map3DPalette.tileWhite,0.7)
        for x: Float in [-0.48,0.48] { for y: Float in [-0.34,0.34] {
            XCTAssertLessThanOrEqual(ray(.init(x,y,0.12),.init(0,0,1),m,only:[underside]),0.121)
        } }
    }
    func testShowerHeadMeetsItsPipeAndReelAxleMeetsSupport() {
        let shower=Map3DRecreationKit.model(for:.showerArch)
        XCTAssertLessThan(ray(.init(0.3,0,2.31),.init(0,0,-1),shower),0.04)
        let reel=Map3DRecreationKit.model(for:.poolLaneReel)
        for y: Float in [-1,1] { XCTAssertLessThan(ray(.init(0,y,0.93),.init(0,0,-1),reel),0.05) }
    }
    func testDeterministicOptionalLoadingAndAllFourExamples() {
        for p in Map3DRecreationKit.Part.allCases {
            XCTAssertEqual(Map3DRecreationKit.model(for:p).vertices,Map3DRecreationKit.model(for:p).vertices)
            XCTAssertEqual(p.connectors[0].normal,Map3DPoint(0,0,-1))
        }
        XCTAssertEqual(Map3DRecreationKit.model(for:.fitnessStudio).name,"recreation-fitnessStudio")
        XCTAssertEqual(Map3DRecreationKit.Example.allCases.count,4)
        XCTAssertEqual(Map3DModelPack(recreationKit:[.treadmill,.swimPavilion]).models.count,2)
        XCTAssertNil(Map3DModelPack.standard.index(of:"recreation-treadmill"))
    }
    private func ray(_ origin: Map3DPoint,_ direction: Map3DPoint,_ model: Map3DModelPack.Model,excluding: UInt32? = nil,only: [UInt32]? = nil,upwardOnly: Bool = false,excludingColors: Set<UInt32> = []) -> Float {
        var result=Float.infinity
        for i in stride(from:0,to:model.vertices.count,by:3) {
            let t=Array(model.vertices[i..<i+3])
            if excludingColors.contains(t[0].color) { continue }
            if upwardOnly && t[0].nz<0.9 { continue }
            if let excluding,t[0].color==excluding { continue }
            if let only,!only.contains(t[0].color) { continue }
            let p=t.map { Map3DPoint($0.x,$0.y,$0.z) },e=p[1]-p[0],f=p[2]-p[0],h=direction.cross(f),det=e.dot(h)
            if abs(det)<0.0000001 { continue }
            let s=origin-p[0],u=s.dot(h)/det,q=s.cross(e),v=direction.dot(q)/det,d=f.dot(q)/det
            if u >= -0.00001 && v >= -0.00001 && u+v<=1.00001 && d>0.00001 { result=min(result,d) }
        }
        return result
    }
}
