import XCTest
@testable import GamePresentation

final class Map3DE500Tests: XCTestCase {
    func testActualE500DispatchAndFarKeepDedicatedGeometry() throws {
        for key in ["E500CK", "MINGRI", "STAR"] {
            let near=try XCTUnwrap(Map3DTrainSet.named(key)), far=try XCTUnwrap(Map3DTrainSet.named(key+"Far"))
            XCTAssertEqual(near.far,key+"Far")
            XCTAssertTrue(near.ownLengths)
            XCTAssertEqual(near.build().head.vertices,Map3DE500.model().vertices)
            XCTAssertEqual(far.build().head.vertices,Map3DE500.model(far:true).vertices)
            XCTAssertEqual(Map3DTrainSet.reach(of:key),500)
            XCTAssertEqual(near.build().middle?.vertices,far.build().middle?.vertices)
        }
    }
    func testPackActuallySelectsNearFarAndExistingBoxFallback() throws {
        let pack=Map3DModelPack.standard
        for key in ["E500CK", "MINGRI", "STAR"] {
            let near=try XCTUnwrap(pack.index(of:"set-"+key+"-head"))
            let far=try XCTUnwrap(pack.index(of:"set-"+key+"Far-head"))
            XCTAssertEqual(pack.model(near,forType:key,count:7,at:499),near)
            XCTAssertEqual(pack.model(near,forType:key,count:7,at:500),far)
            XCTAssertNil(pack.model(near,forType:key,count:7,at:900))
            let layout=try XCTUnwrap(pack.layout(forType:key,count:7))
            XCTAssertEqual(layout.count,7)
            XCTAssertEqual(layout[0].length,20.77,accuracy:0.0001)
            XCTAssertEqual(pack.models[near].vertices,Map3DE500.model().vertices)
        }
    }
    private func section(_ vertices:[Map3DVertex],at height:Float)->[[Map3DPoint]] {
        var result:[[Map3DPoint]]=[]
        for i in stride(from:0,to:vertices.count,by:3) {
            let t=vertices[i..<i+3].map(\.position)
            if height<t.map(\.z).min()! || height>t.map(\.z).max()! {continue}
            var points:[Map3DPoint]=[]
            for j in 0..<3 {
                let a=t[j],b=t[(j+1)%3],d=b.z-a.z
                if abs(d)<0.000001 {if abs(a.z-height)<0.000001 {points += [a,b]}}
                else {let u=(height-a.z)/d;if u>=0 && u<=1 {points.append(a+(b-a)*u)}}
            }
            if points.count>=2 {result.append(points)}
        }
        return result
    }
    private func frameSpan(_ vertices:[Map3DVertex],side:Float,end:Float)->Float {
        var intervals:[(Float,Float)]=[]
        for points in section(vertices,at:0.84) {
            let p=points.filter {$0.y*side>=0.99 && $0.y*side<=1.23 && $0.x*end>3.5 && $0.x*end<8.6}
            if p.count>=2 {intervals.append((p.map(\.x).min()!,p.map(\.x).max()!))}
        }
        intervals.sort {$0.0<$1.0}
        guard let first=intervals.first else {return 0}
        var start=first.0,finish=first.1,best:Float=0
        for (a,b) in intervals.dropFirst() {
            if a<=finish+0.0001 {finish=max(finish,b)}
            else {best=max(best,finish-start);start=a;finish=b}
        }
        return max(best,finish-start)
    }
    func testVisibleFramesAndSingleArmProjectionRejectActualDefects() {
        for far in [false,true] {
            let v=Map3DE500.model(far:far).vertices
            for side:Float in [-1,1] {for end:Float in [-1,1] {XCTAssertGreaterThan(frameSpan(v,side:side,end:end),4)}}
            let arm=section(v,at:5.10).flatMap {$0}
            XCTAssertFalse(arm.isEmpty)
            XCTAssertLessThan(arm.map(\.y).max()!-arm.map(\.y).min()!,0.1)
            var broken:[Map3DVertex]=[]
            for i in stride(from:0,to:v.count,by:3) {
                let t=v[i..<i+3]
                if !t.allSatisfy({$0.y>0.99 && $0.y<1.23 && $0.x>3.5 && $0.x<8.6}) {broken.append(contentsOf:t)}
            }
            XCTAssertLessThan(frameSpan(broken,side:1,end:1),4,"removing the actual outboard frame must fail continuity")
        }
    }
    func testNativeGeometryAtRailDatumAndMeasuredBudget() {
        for far in [false,true] {
            let m=Map3DE500.model(far:far)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.00001)
            XCTAssertEqual(m.length,20.77,accuracy:0.0001)
            XCTAssertTrue(m.triangleCount<(far ? 4100:10000))
            XCTAssertTrue(m.maximum.z>5.2 && m.maximum.z<5.5) // raised collector; not stowed height
            for v in m.vertices {
                XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite)
                XCTAssertEqual(v.nx*v.nx+v.ny*v.ny+v.nz*v.nz,1,accuracy:0.0001)
            }
        }
    }
}
