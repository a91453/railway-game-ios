import Foundation
import GameCore
import XCTest
@testable import GamePresentation

/// Tests inspect generated geometry and runtime dispatch, not just recipe inputs.
final class Map3DEMU3000Tests: XCTestCase {
    private let pack=Map3DModelPack.standard

    func testAnActualWorldEMUUsesTheNewMeshesAtTheirOwnScale() throws {
        var world=try makeWorld(width:128_000,height:65_536,balance:100_000_000)
        let a=try world.buildTrackNode(at:WorldCoordinate(x:4_096,y:32_768))
        let b=try world.buildTrackNode(at:WorldCoordinate(x:118_784,y:32_768))
        try world.buildTrackEdge(from:a,to:b)
        let train=try world.purchaseTrain(named:"EMU miniature",as:.emu3000).id
        try world.setTrainCars(train,to:12)
        try world.placeTrain(train,at:.onEdge(TrackTraversal(edge:.edge(1),direction:.forward),offset:64_000))
        let scene=Map3DScene(world:world),motion=TrainMotion(world:world,time:0),heights=Map3DTrains.Heights(world:world)
        let boxes=Map3DTrains.frame(motion,progress:1,heights:heights,in:scene,models:nil,eye:nil)
        let first=try XCTUnwrap(boxes.boxes.vertices.first?.position)
        let near=Map3DTrains.frame(motion,progress:1,heights:heights,in:scene,models:pack,eye:first+Map3DPoint(0,100,0))
        XCTAssertEqual(near.instances.count,12);XCTAssertTrue(near.boxes.isEmpty)
        XCTAssertEqual(near.instances.map {pack.models[$0.model].name},["head","car","panto","car","et","em6","ep7","car","car","ep10","car","tail"].map {"set-emu3000-"+$0})
        for instance in near.instances {
            let t=instance.transform
            XCTAssertEqual(sqrt(t[0]*t[0]+t[1]*t[1]+t[2]*t[2]),1,accuracy:0.001,"native metre scale, no generic 20m stretch")
        }
        let far=Map3DTrains.frame(motion,progress:1,heights:heights,in:scene,models:pack,eye:first+Map3DPoint(0,700,0))
        XCTAssertEqual(far.instances.count,12)
        XCTAssertTrue(far.instances.allSatisfy {pack.models[$0.model].name.hasPrefix("set-emu3000Far-")})
    }
    func testRealTwelveCarRolesReachTheRuntimeAndFarLOD() throws {
        let cars=try XCTUnwrap(pack.layout(forType:"EMU3000",count:12))
        let names=["head","car","panto","car","et","em6","ep7","car","car","ep10","car","tail"]
        XCTAssertEqual(cars.map {pack.models[$0.model].name},names.map {"set-emu3000-"+$0})
        XCTAssertEqual(cars.reduce(Float(0)) {$0+$1.length+$1.gap},245.7,accuracy:0.001)
        for (i,car) in cars.enumerated() {
            let m=pack.models[car.model]
            XCTAssertEqual(car.gap,0)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.00001)
            XCTAssertEqual(pack.model(car.model,forType:"EMU3000",count:12,at:499),car.model)
            let farIndex=try XCTUnwrap(pack.model(car.model,forType:"EMU3000",count:12,at:500))
            let far=pack.models[farIndex]
            XCTAssertEqual(far.name,"set-emu3000Far-"+names[i])
            XCTAssertLessThan(far.triangleCount,m.triangleCount*2/3)
            XCTAssertEqual(far.length,m.length,accuracy:0.00001)
            XCTAssertEqual(m.maximum.z>4.3,[2,6,9].contains(i),"actual raised collectors only on cars3/7/10")
            if i>0 && i<11 {XCTAssertFalse(m.vertices.contains(where:\.glows),"no cab lamps on intermediate units")}
            XCTAssertNil(pack.model(car.model,forType:"EMU3000",count:12,at:900))
        }
        let head=pack.models[cars[0].model],tail=pack.models[cars[11].model]
        XCTAssertFalse(head.vertices.filter(\.glows).isEmpty)
        XCTAssertTrue(head.vertices.filter(\.glows).allSatisfy {$0.x>0})
        XCTAssertTrue(tail.vertices.filter(\.glows).allSatisfy {$0.x<0})
        XCTAssertFalse(pack.isTurned(forType:"EMU3000",carIndex:11,count:12),"tail already rotated")
    }
    func testExistingGameCarCountsAndLocksStillWork() throws {
        for count in 1...16 {
            let cars=try XCTUnwrap(pack.layout(forType:"EMU3000",count:count))
            XCTAssertEqual(cars.count,count)
            for i in 0..<count {XCTAssertNotNil(pack.modelIndex(forType:"EMU3000",carIndex:i,count:count))}
        }
        var locked=pack;locked.locked.insert("emu3000")
        XCTAssertEqual(locked.models[try XCTUnwrap(locked.modelIndex(forType:"EMU3000",carIndex:0,count:12))].name,"express-cab")
        XCTAssertNil(locked.layout(forType:"EMU3000",count:12))
        for code in ["HSR","n700sG","E200CK","puyuma","taroko","emu800"] {XCTAssertNotNil(pack.models(forType:code),code)}
    }
    func testActualMeshesHaveClosedOutwardSurfacesAndRejectVisibleDefects() throws {
        for far in [false,true] {for unit in Map3DEMU3000.Unit.allCases {
            let m=Map3DEMU3000.model(unit,far:far)
            XCTAssertLessThan(m.triangleCount,far ? 3600:8800)
            try closed(m.vertices)
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=Array(m.vertices[i..<i+3]),n=try XCTUnwrap((t[1].position-t[0].position).cross(t[2].position-t[0].position).normalized)
                XCTAssertGreaterThan(n.dot(Map3DPoint(t[0].nx,t[0].ny,t[0].nz)),0.999)
            }
        }}
        let good=Map3DEMU3000.model(.ed).vertices
        XCTAssertThrowsError(try closed(Array(good.dropFirst(3))),"missing visible face")
        var reversed=good;reversed.swapAt(0,1)
        XCTAssertThrowsError(try closed(reversed),"reversed visible face")
    }
    func testPassengerWindowDifferencesArePresentInTheActualGeometry() {
        let expected:[Map3DEMU3000.Unit:Int]=[.ed:10,.em:13,.ep3:12,.et:13,.em6:10,.ep7:11,.ep10:13,.tail:10]
        for (unit,count) in expected {
            let m=Map3DEMU3000.model(unit)
            func key(_ v:Map3DVertex)->String {[v.x,v.y,v.z].map {String(Int(($0*100000).rounded()))}.joined(separator:",")}
            let bay:ClosedRange<Float> = unit == .ed ? -7.8...3.2:unit == .tail ? -3.2...7.8:-7.4...7.4
            var parts:[Set<String>]=[],points:[String:Map3DVertex]=[:]
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let t=Array(m.vertices[i..<i+3])
                guard t.allSatisfy({$0.color==Map3DEMU3000.glassColor && bay.contains($0.x) && $0.y>1.0 && $0.z>1.8 && $0.z<2.8}) else {continue}
                var keys=Set(t.map(key))
                for v in t {points[key(v)]=v}
                for k in parts.indices.reversed() where !parts[k].isDisjoint(with:keys) {keys.formUnion(parts.remove(at:k))}
                parts.append(keys)
            }
            let windows=parts.filter {p in
                let xs=p.compactMap {points[$0]?.x}
                return (xs.max() ?? 0)-(xs.min() ?? 0)>0.60
            }
            XCTAssertEqual(windows.count,count,"\(unit): actual dark main windows, excluding blank/service bays")
        }
    }
    func testTrailerAndCollectorUnderfloorEquipmentAreDistinct() {
        let em=Map3DEMU3000.model(.em),et=Map3DEMU3000.model(.et),ep=Map3DEMU3000.model(.ep3)
        let under:(Map3DModelPack.Model)->[Float] = {m in m.vertices.filter {$0.z<0.9 && abs($0.x)<5}.flatMap {[$0.x,$0.y,$0.z]}}
        XCTAssertNotEqual(under(em),under(et));XCTAssertNotEqual(under(em),under(ep))
        XCTAssertNotEqual(under(et),under(ep))
    }
    func testHeadHasShortSlopingNoseWhiteChinAndAttachedMask() {
        let m=Map3DEMU3000.model(.ed)
        let black=m.vertices.filter {$0.color==Map3DEMU3000.maskColor && $0.x>5 && $0.z>1.5}
        XCTAssertGreaterThan(black.count,200)
        let lowerMask=black.filter {$0.z>1.40 && $0.z<1.85}
        XCTAssertGreaterThan((lowerMask.map(\.y).max() ?? 0)-(lowerMask.map(\.y).min() ?? 0),0.9,"rounded U-shaped lower mask, no narrow central spike")
        XCTAssertLessThan(black.map(\.z).min() ?? 10,1.9,"rounded lower edge of black mask")
        let chin=m.vertices.filter {$0.color==Map3DEMU3000.bodyColor && $0.x>10 && $0.z<1.7 && $0.z>0.9}
        XCTAssertGreaterThan(chin.count,10,"substantial white chin, not a needle")
        XCTAssertLessThan(m.vertices.filter {$0.x>9.5}.map(\.z).max() ?? 10,2.5)
    }
    func testCabSideProfileHasTheReferenceCrownAndContinuousDiagonalNose() {
        for far in [false,true] {
            let head=Map3DEMU3000.model(.ed,far:far)
            func shellTop(_ x:Float)->Float {
                var high:Float=0
                for i in stride(from:0,to:head.vertices.count,by:3) {
                    let t=Array(head.vertices[i..<i+3])
                    guard t.allSatisfy({$0.color==Map3DEMU3000.bodyColor || $0.color==Map3DEMU3000.maskColor}) else {continue}
                    for j in 0..<3 {
                        let a=t[j],b=t[(j+1)%3]
                        if (a.x-x)*(b.x-x)<0 {high=max(high,a.z+(b.z-a.z)*(x-a.x)/(b.x-a.x))}
                    }
                }
                return high
            }
            XCTAssertGreaterThan(shellTop(7.0),3.60,"rounded raised cab crown")
            XCTAssertGreaterThan(shellTop(8.0),3.20,"upper slope starts above the side window")
            XCTAssertLessThan(shellTop(10.0),1.80,"diagonal nose continues down instead of flattening into a beak")
            let chin=head.vertices.filter {$0.color==Map3DEMU3000.bodyColor && $0.x>8}
            let low=chin.map(\.z).min() ?? 0
            XCTAssertGreaterThan(low,0.20);XCTAssertLessThan(low,0.35)
            XCTAssertGreaterThan(chin.filter {$0.z<low+0.02}.map(\.x).min() ?? 0,9.95,"tight rounded lower corner")
            XCTAssertGreaterThan(head.vertices.filter {$0.color==Map3DEMU3000.glassColor && $0.x>7.3 && $0.x<8.8 && abs($0.y)>1 && $0.z>2.3 && $0.z<3.2}.count,30,"triangular quarterlight follows the new cab position")
        }
    }
    func testHeadlampsAreIndividualModulesAndTailHasOnlyTwoMarkers() {
        func modules(_ model:Map3DModelPack.Model)->Int {
            func key(_ v:Map3DVertex)->String {[v.x,v.y,v.z].map {String(Int(($0*100000).rounded()))}.joined(separator:",")}
            var parts:[Set<String>]=[]
            for i in stride(from:0,to:model.vertices.count,by:3) {
                let t=Array(model.vertices[i..<i+3]);guard t.allSatisfy(\.glows) else {continue}
                var keys=Set(t.map(key))
                for k in parts.indices.reversed() where !parts[k].isDisjoint(with:keys) {keys.formUnion(parts.remove(at:k))}
                parts.append(keys)
            }
            return parts.count
        }
        for far in [false,true] {
            XCTAssertEqual(modules(Map3DEMU3000.model(.ed,far:far)),4,"two upper headlamps and two cheek headlights")
            let tail=Map3DEMU3000.model(.tail,far:far)
            XCTAssertEqual(modules(tail),2,"only lower red markers; upper headlamps off")
        }
    }
    func testDoorGlassRemainsVisibleAboveItsRealCurvedBodyBacking() {
        func occlusions(_ vertices:[Map3DVertex],_ doors:[Float])->(samples:Int,hidden:Int) {
            let triangles=stride(from:0,to:vertices.count,by:3).map {Array(vertices[$0..<$0+3])}
            var samples=0,hidden=0
            for t in triangles {
                let p=t.map(\.position),c=p.reduce(.zero,+)*(1/3)
                guard t.allSatisfy({$0.color==Map3DEMU3000.glassColor}),abs(t[0].ny)>0.7,
                      t[0].ny*c.y>0,abs(c.y)>1.0,doors.contains(where:{abs(c.x-$0)<0.25}) else {continue}
                let d=Map3DPoint(0,c.y>0 ? -1:1,0),o=c-d*0.4
                var nearest:Float=10
                for q in triangles {
                    let a=q[0].position,b=q[1].position,e=q[2].position
                    guard c.x>=min(a.x,min(b.x,e.x))-0.000001,
                          c.x<=max(a.x,max(b.x,e.x))+0.000001,
                          c.z>=min(a.z,min(b.z,e.z))-0.000001,
                          c.z<=max(a.z,max(b.z,e.z))+0.000001 else {continue}
                    let ab=b-a,ac=e-a,h=d.cross(ac),det=ab.dot(h)
                    if abs(det)<0.0000001 {continue}
                    let s=o-a,u=s.dot(h)/det,k=s.cross(ab),v=d.dot(k)/det,t=ac.dot(k)/det
                    if u >= -0.000001 && v >= -0.000001 && u+v<=1.000001 && t>=0 {nearest=min(nearest,t)}
                }
                samples+=1
                if nearest<0.397 {hidden+=1}
            }
            return (samples,hidden)
        }
        for far in [false,true] {for unit in Map3DEMU3000.Unit.allCases {
            let m=Map3DEMU3000.model(unit,far:far)
            let doors:[Float]=unit == .ed ? [-8.5,5.3,7.0]:unit == .tail ? [8.5,-5.3,-7.0]:[-8,8]
            let result=occlusions(m.vertices,doors)
            XCTAssertGreaterThan(result.samples,20,"both door sides have real visible glazing samples")
            XCTAssertEqual(result.hidden,0,"\(unit) far=\(far): door glass hidden by hull/leaf")
        }}
        // Mutate actual glazing inward; a closed manifold alone would pass this defect.
        let good=Map3DEMU3000.model(.em).vertices
        let bad=good.map {v in
            guard v.color==Map3DEMU3000.glassColor,abs(v.x-8)<0.3,v.y>0 else {return v}
            return Map3DVertex(v.position+Map3DPoint(0,-0.10,0),normal:Map3DPoint(v.nx,v.ny,v.nz),color:v.color,layer:v.layer)
        }
        XCTAssertGreaterThan(occlusions(bad,[-8,8]).hidden,0,"buried-door mutation must fail")
    }
    private enum Defect: Error {case openOrInverted}
    private func closed(_ vertices:[Map3DVertex]) throws {
        func key(_ v:Map3DVertex)->String {[v.x,v.y,v.z].map {String(Int(($0*100000).rounded()))}.joined(separator:",")}
        var balance:[String:Int]=[:]
        for i in stride(from:0,to:vertices.count,by:3) {
            let p=vertices[i..<i+3].map(key)
            for j in 0..<3 {let a=p[j],b=p[(j+1)%3],k=a<b ? a+"|"+b:b+"|"+a;balance[k,default:0]+=a<b ? 1:-1}
        }
        guard balance.values.allSatisfy({$0==0}) else {throw Defect.openOrInverted}
    }
}
