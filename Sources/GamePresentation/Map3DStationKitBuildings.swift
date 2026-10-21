import Foundation

extension StationKitBuilder {
    mutating func station(_ station: Map3DStationKit.Station) {
        let p=station.profile,v=Int(station.seed%7)
        switch p {
        case .taipei: taipei()
        case .taichung: taichung()
        case .kaohsiung: kaohsiung()
        case .hsinchu,.tainan,.chiayi,.heritage,.timber:
            let wood=p == .timber,grand=p == .hsinchu || p == .tainan
            let width: Float=grand ? 43 : 21+Float(v)*2
            box(0,0,0,48,width+16,0.25,Map3DPalette.plaza)
            historic(10,0.25,0,length:13,width:width,wood:wood,clock:grand || p == .chiayi)
            railCourt(length:width+10,at:-12,platforms:1)
        case .banqiao,.nangang:
            let w: Float=p == .nangang ? 74 : 64
            box(0,0,0,66,w+16,0.3,Map3DPalette.plaza)
            facade(0,0.3,0,38,w,10,Self.white,bays:12)
            for sign: Float in [-1,1] {
                let h: Float=p == .nangang ? 55 : 39
                facade(-7,10.3,sign*w*0.30,23,w*0.28,h,Map3DPalette.concrete,bays:5)
                for floor in 1..<Int(h/4) { box(-7,10.3+Float(floor)*4,sign*w*0.30,23.15,w*0.28+0.15,0.22,Self.white) }
                box(-7,h+10.3,sign*w*0.30,23.5,w*0.28+0.5,0.45,Self.steel)
            }
            canopy(24,7,0,length:10,width:w*0.8,rise:2,color:Self.glass)
            for z: Float in [-w*0.35,w*0.35] { box(27,0.3,z,0.4,0.4,7.55,Self.steel) }
        case .hualien:
            box(0,0,0,62,76,0.25,Map3DPalette.plaza)
            facade(8,0.25,0,28,62,6.5,Self.white,bays:10)
            for z: Float in [-22,0,22] {
                for x: Float in [-5,21] { box(x,0.25,z,0.5,0.5,8,Self.steel) }
                hip(8,8.25,z,30,23,4,Self.white)
            }
            railCourt(length:68,at:-20,platforms:1)
        case .taitung:
            box(0,0,0,58,82,0.25,Map3DPalette.plaza)
            facade(10,0.25,0,22,62,5.8,Map3DPalette.schoolWalls,bays:10)
            for z: Float in [-22,0,22] {
                canopy(9,7,z,length:27,width:22,rise:4,color:Self.white)
                for x: Float in [-3,21] { for dz: Float in [-9,9] { box(x,0.25,z+dz,0.35,0.35,7.55,Map3DPalette.brick) }}
            }
            railCourt(length:68,at:-18,platforms:1)
        case .keelung:
            box(0,0,0,55,66,0.25,Map3DPalette.plaza)
            facade(4,0.25,0,30,52,7,Self.white,bays:8)
            canopy(4,7.25,0,length:32,width:54,rise:9,color:Self.white)
            for z: Float in [-24,0,24] { beam(Map3DPoint(20,0.25,z),Map3DPoint(20,7.25+9*sinf((z+27)/54*Float.pi),z),0.45,Self.steel) }
            railCourt(length:58,at:-21,platforms:1)
        case .zuoying,.hsrTaichung,.hsrTaoyuan,.hsrHsinchu,.hsrTainan,.highSpeed:
            highSpeed(profile:p,variant:v)
        case .formosa,.centralPark,.underground:
            underground(profile:p,variant:v)
        case .elevated: elevated(variant:v)
        case .lightRail:
            box(0,0,0,38,17,0.20,Map3DPalette.plaza)
            track(-18,18,0,at:0.2)
            for z: Float in [-5.3,5.3] {
                var local=StationKitBuilder();local.platform(length:30,width:3,height:0.35,roof:true)
                add(.flat(named:"platform",from:local.mesh),at:Map3DPoint(0,0.2,z))
            }
        case .regional,.halt:
            let tier=station.tier,small=p == .halt
            let width: Float=small ? 10+Float(v) : 22+Float(4-tier)*5+Float(v)
            box(0,0,0,60,width+18,0.25,Map3DPalette.plaza)
            facade(13,0.25,0,12,width,small ? 4.2 : 6.2,Map3DPalette.schoolWalls,bays:small ? 3 : 7)
            if v%2==0 { gable(13,small ? 4.45 : 6.45,0,13,width+1,small ? 1.6 : 2.4,Map3DPalette.gymGreen) }
            else { box(13,small ? 4.45 : 6.45,0,13,width+1,0.25,Map3DPalette.tinRoofs[v%5]) }
            box(20,2.8,0,3,width+2,0.20,Map3DPalette.canopy)
            for z: Float in [-width*0.43,width*0.43] { box(21.2,0.25,z,0.24,0.24,2.55,Self.steel) }
            railCourt(length:width+10,at:-10,platforms:small ? 1 : 2)
        }
    }

    mutating func platform(length: Float,width: Float,height: Float = 1.15,roof: Bool) {
        box(0,0,0,length,width,height,Map3DPalette.platform)
        for z: Float in [-width/2+0.15,width/2-0.15] { box(0,height,z,length,0.20,0.025,Map3DPalette.platformEdge) }
        if roof {
            for x in stride(from:-length/2+2,through:length/2-1,by:Float(7)) { box(x,height,0,0.22,0.22,3.58,Self.steel) }
            canopy(0,height+3.2,0,length:length,width:width+0.5,rise:0.60,color:Map3DPalette.canopy)
        }
        if length>12 { bench(1,height,0) }
    }
    mutating func trackAcross(_ x: Float,_ y: Float,_ z: Float,length: Float) {
        var b=StationKitBuilder();b.track(-length/2,length/2,0,at:y)
        add(.flat(named:"track",from:b.mesh),at:Map3DPoint(x,0,z),angle:.pi/2)
    }
    mutating func railCourt(length: Float,at x: Float,platforms: Int) {
        for i in 0..<platforms {
            let cx=x-Float(i)*11
            var b=StationKitBuilder();b.platform(length:length,width:4.6,roof:true)
            add(.flat(named:"platform",from:b.mesh),at:Map3DPoint(cx,0.25,0),angle:.pi/2)
            trackAcross(cx-4.5,0.25,0,length:length+3)
        }
    }
    mutating func historic(_ x: Float,_ y: Float,_ z: Float,length: Float,width: Float,wood: Bool,clock: Bool) {
        let wall=wood ? Map3DPalette.counters[1] : Map3DPalette.brick,h: Float=wood ? 4.4 : 6.5
        facade(x,y,z,length,width,h,wall,bays:max(3,Int(width/4)))
        hip(x,y+h,z,length+1,width+1,wood ? 2 : 3,wood ? Map3DPalette.gymGreen : Map3DPalette.templeRidge)
        if clock {
            box(x+length/2-2,y,z,5.5,7,h+5,wall)
            hip(x+length/2-2,y+h+5,z,6.2,8,2.2,Map3DPalette.templeRidge)
            clockFace(x+length/2+0.79,y+h+2.0,z,size:1.6)
        }
        box(x+length/2+1.1,y+3.2,z,3,width*0.70,0.2,Map3DPalette.gymGreen)
        for dz: Float in [-width*0.31,width*0.31] { box(x+length/2+2.3,y,z+dz,0.23,0.23,3.2,Self.white) }
    }
    mutating func clockFace(_ x: Float,_ y: Float,_ z: Float,size: Float) {
        box(x,y-size/2,z,0.12,size,size,Self.white)
        box(x+0.07,y-0.04,z+size*0.10,0.025,size*0.28,0.06,Self.ink)
        box(x+0.075,y,z,0.025,0.06,size*0.30,Self.ink)
    }

    mutating func taipei() {
        box(0,0,0,88,110,0.35,Map3DPalette.plaza)
        facade(0,0.35,0,64,82,16,Map3DPalette.stone,bays:16)
        // Native adaptation of the reference's open courtyard roof, with
        // new proportions, ribs, column spacing and the game's matte paint.
        courtyardRoof(y:16.35,length:72,width:92,rise:12,opening:0.43)
        box(0,17.0,0,27,35,0.30,Self.glass)
        for z in stride(from:Float(-36),through:36,by:6) {
            for sign: Float in [-1,1] { box(sign*32.3,0.35,z,0.7,1,15.7,Map3DPalette.schoolWalls) }
        }
        for z: Float in [-28,0,28] {
            box(35,4.8,z,6,16,0.35,Map3DPalette.templeRidge)
            for dz: Float in [-6,6] { box(37,0.35,z+dz,0.4,0.4,4.45,Map3DPalette.schoolWalls) }
        }
        for z: Float in [-47,47] { for x: Float in [-30,30] { tree(x,0.35,z,size:1.2) }}
    }
    mutating func courtyardRoof(y: Float,length: Float,width: Float,rise: Float,opening: Float) {
        let n=9
        func ring(_ t: Float,_ down: Float) -> [Map3DPoint] {
            let l=length*(opening+(1-opening)*t)/2,w=width*(opening+(1-opening)*t)/2
            let h=y+rise*powf(1-t,2.1)-down
            return [Map3DPoint(-l,h,-w),Map3DPoint(l,h,-w),Map3DPoint(l,h,w),Map3DPoint(-l,h,w)]
        }
        for i in 0..<n {
            let t=Float(i)/Float(n),u=Float(i+1)/Float(n),a=ring(t,0),b=ring(u,0),c=ring(t,0.3),d=ring(u,0.3)
            for k in 0..<4 {
                let j=(k+1)%4
                mesh.addQuad(a[k],a[j],b[j],b[k],color:Map3DPalette.templeRidge)
                mesh.addQuad(c[k],d[k],d[j],c[j],color:Map3DColor.shaded(Map3DPalette.templeRidge,0.7))
                if i==0 { face([a[k],c[k],c[j],a[j]],inside:Map3DPoint(0,y,0),color:Map3DPalette.templeRidge) }
                if i==n-1 { face([b[k],b[j],d[j],d[k]],inside:Map3DPoint(0,y,0),color:Map3DPalette.templeRidge) }
                for r in 1..<8 {
                    let f=Float(r)/8
                    beam(a[k]+(a[j]-a[k])*f+Map3DPoint(0,0.08,0),b[k]+(b[j]-b[k])*f+Map3DPoint(0,0.08,0),0.10,Map3DPalette.templeRoof)
                }
            }
        }
    }
    mutating func taichung() {
        box(0,0,0,100,100,0.30,Map3DPalette.plaza)
        box(-12,0.3,0,1,1,9,Self.steel)
        // Elevated train hall with open, supported curved roof; the old
        // brick station remains a separate mass on the forecourt.
        box(-12,9,0,42,86,0.8,Map3DPalette.concrete)
        for x: Float in [-28,4] { for z: Float in [-36,-12,12,36] { box(x,0.3,z,0.65,0.65,8.7,Self.steel) }}
        supportedRoof(x:-12,y:15,z:0,length:45,width:90,rise:6,wave:false,color:Self.white,base:9.8)
        for x: Float in [-20,-4] { trackAcross(x,9.8,0,length:84) }
        historic(28,0.3,0,length:13,width:35,wood:false,clock:true)
        stairs(12,0.3,35,run:16,width:4,rise:9.5)
    }
    mutating func kaohsiung() {
        box(0,0,0,148,138,0.30,Map3DPalette.plaza)
        let l: Float=98,w: Float=116,nx=14,nz=16
        func point(_ i: Int,_ j: Int) -> Map3DPoint {
            let x = -l/2+l*Float(i)/Float(nx),z = -w/2+w*Float(j)/Float(nz)
            return Map3DPoint(x,9+2.5*cosf(x/l*2*Float.pi)*cosf(z/w*2*Float.pi),z)
        }
        for i in 0..<nx { for j in 0..<nz {
            if (5...8).contains(i) && (6...9).contains(j) { continue }
            let p=[point(i,j),point(i,j+1),point(i+1,j+1),point(i+1,j)]
            mesh.addFacet(p,color:Map3DPalette.gymGreen)
            mesh.addFacet(p.reversed().map { $0-Map3DPoint(0,0.3,0) },color:Map3DPalette.concrete)
            for edge in 0..<4 {
                let a=p[edge],b=p[(edge+1)%4]
                face([a,b,b-Map3DPoint(0,0.3,0),a-Map3DPoint(0,0.3,0)],inside:Map3DPoint(0,0,0),color:Map3DPalette.gymGreen)
            }
        }}
        for i in stride(from:1,to:nx,by:3) { for j in stride(from:1,to:nz,by:3) {
            if (5...9).contains(i) && (6...10).contains(j) { continue }
            let top=point(i,j)-Map3DPoint(0,0.3,0),fork=Map3DPoint(top.x,5,top.z)
            box(top.x,0.3,top.z,0.6,0.6,4.7,Self.white)
            for dx: Float in [-1.2,1.2] {
                let h=9+2.5*cosf((top.x+dx)/l*2*Float.pi)*cosf(top.z/w*2*Float.pi)-0.3
                beam(fork,Map3DPoint(top.x+dx,h,top.z),0.28,Self.white)
            }
        }}
        historic(61,0.3,0,length:13,width:27,wood:false,clock:true)
        for z: Float in [-56,56] { for x: Float in [-60,-30,0,30,60] { tree(x,0.3,z,size:1.2) }}
    }
    mutating func highSpeed(profile: Map3DStationKit.Profile,variant: Int) {
        let wave=profile == .hsrTaoyuan || profile == .hsrTainan
        let length: Float=profile == .zuoying ? 58 : 42+Float(variant),width: Float=profile == .hsrTaichung ? 104 : 76+Float(variant)*2
        box(0,0,0,length+24,width+18,0.3,Map3DPalette.plaza)
        facade(0,0.3,0,length,width,7,Self.white,bays:14)
        supportedRoof(x:0,y:10,z:0,length:length+7,width:width+5,rise:wave ? 1.8 : 7,wave:wave,color:Self.white,base:0.3)
        box(length/2+6,5.3,0,12,width*0.70,0.22,Self.glass)
        for z: Float in [-width*0.30,width*0.30] { box(length/2+11,0.3,z,0.40,0.40,5,Self.steel) }
        for z: Float in [-width*0.41,width*0.41] { box(-length/2-3,0.3,z,5,8,3.7,Map3DPalette.canopy) }
    }
    mutating func supportedRoof(x: Float,y: Float,z: Float,length: Float,width: Float,rise: Float,wave: Bool,color: UInt32,base: Float) {
        canopy(x,y,z,length:length,width:width,rise:rise,color:color,wave:wave)
        for t: Float in [0.08,0.29,0.50,0.71,0.92] {
            let roof=y+(wave ? cosf(t*2*Float.pi) : sinf(t*Float.pi))*rise-0.22
            for sign: Float in [-1,1] {
                let px=x+sign*(length/2-1.4),pz=z-width/2+t*width
                box(px,base,pz,0.45,0.45,roof-base,Self.steel)
            }
        }
    }
    mutating func elevated(variant: Int) {
        let length: Float=42+Float(variant)*2,width: Float=16
        box(0,0,0,length+12,width+12,0.25,Map3DPalette.plaza)
        for x in stride(from:-length/2+3,through:length/2-2,by:Float(10)) { for z: Float in [-5,5] { box(x,0.25,z,0.8,0.8,8.75,Map3DPalette.concrete) }}
        box(0,9,0,length,width,0.7,Map3DPalette.concrete)
        track(-length/2,length/2,0,at:9.7)
        for z: Float in [-5,5] { box(0,9.7,z,length-2,4,1.1,Map3DPalette.platform) }
        supportedRoof(x:0,y:14.1,z:0,length:length+1,width:17,rise:3,wave:false,color:Map3DPalette.gymGreen,base:10.8)
        for z: Float in [-7.2,7.2] { box(0,10.8,z,length-2,0.12,1.4,Self.glass) }
        stairs(length/2,0.25,11,run:14,width:3,rise:10.55)
        box(length/2+2,10.6,8.7,12,7.5,0.2,Map3DPalette.concrete)
    }
    mutating func underground(profile: Map3DStationKit.Profile,variant: Int) {
        let l: Float=36+Float(variant)*2,w: Float=20
        box(0,-5.2,0,l,w,0.25,Map3DPalette.concrete)
        for sign: Float in [-1,1] {
            box(sign*l/2,-5,0,0.35,w,5,Map3DPalette.concrete)
            box(0,-5,sign*w/2,l,0.35,5,Map3DPalette.concrete)
            box(0,-0.1,sign*(w/2+1.6),l+4,3.2,0.25,Map3DPalette.plaza)
            track(-l/2+1,l/2-1,sign*5.8,at:-4.9)
            stairs(l/2-5,-4.8,sign*2.6,run:10,width:2.4,rise:4.8)
        }
        box(0,-4.8,0,l-3,5,0.9,Map3DPalette.platform)
        for z: Float in [-2.2,2.2] { box(0,-3.9,z,l-3,0.18,0.025,Map3DPalette.platformEdge) }
        for sign: Float in [-1,1] {
            let x=l/2-2,z=sign*3
            for dz: Float in [-1.8,1.8] { box(x,0,z+dz,0.12,0.12,2.8,Self.steel) }
            canopy(x,2.8,z,length:5.6,width:4.4,rise:0.6,color:Self.glass)
        }
        if profile == .formosa {
            box(-l/2-6,0,0,12.5,26,0.15,Map3DPalette.plaza)
            for sign: Float in [-1,1] {
                hip(-l/2-6,4.6,sign*6,9,9,4,Self.glass)
                for dx: Float in [-3.2,3.2] { for dz: Float in [-3.2,3.2] { box(-l/2-6+dx,0,sign*6+dz,0.15,0.15,4.6,Self.steel) }}
            }
        } else if profile == .centralPark {
            supportedRoof(x:0,y:6.8,z:0,length:l+3,width:26,rise:2.2,wave:true,color:Map3DPalette.gymGreen,base:0)
        }
    }
}
