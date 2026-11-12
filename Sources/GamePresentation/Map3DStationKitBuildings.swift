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
        case .coastTimber:
            box(0,0,0,48,40,0.25,Map3DPalette.plaza)
            coastTimber(10,0.25,0)
            railCourt(length:34,at:-12,platforms:1)
        case .baoan:
            box(0,0,0,48,36,0.25,Map3DPalette.plaza)
            baoan(10,0.25,0)
            railCourt(length:30,at:-12,platforms:1)
        case .jiji:
            box(0,0,0,48,40,0.25,Map3DPalette.plaza)
            jiji(10,0.25,0)
            railCourt(length:34,at:-12,platforms:1)
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

// Zhuifen (追分, 1922), a Coast Line timber station: a long gabled hall
// under dark tiles, a band of high windows and name boards under the
// eaves, a lean-to roof on posts along both long sides, and over the
// platform side a cross gable with a round window. Shape and colours
// read from photographs (docs/art/model-look-2026-11-11/README.md); the
// sizes are estimates, not a survey.
extension StationKitBuilder {
    static let tile=Map3DPalette.arcade,timber=Map3DPalette.counters[1],plaster=Map3DPalette.schoolWalls,rust=Map3DPalette.brick

    /// The building, its middle at (`x`, `z`) on ground `y`: its front
    /// (+x) to the forecourt, its back to the platforms.
    mutating func coastTimber(_ x: Float,_ y: Float,_ z: Float) {
        let length: Float=22,depth: Float=8,eave: Float=5.3,rise: Float=3.1,porch: Float=2.0
        // Walls: a dark boarded base, plaster above, a dark rail under the high band.
        box(x,y,z,depth,length,1.0,Self.timber)
        box(x,y+1.0,z,depth-0.04,length-0.04,eave-1.0,Self.plaster)
        box(x,y+3.55,z,depth+0.06,length+0.06,0.16,Self.timber)
        // The hall's roof, its ridge along the platforms, with its ridge tiles.
        mesh.addGableRoof(base:Map3DPoint(x,y+eave,z),forward:Map3DPoint(0,0,1),length:length,width:depth,rise:rise,overhang:0.7,color:Self.tile,gable:Self.plaster)
        box(x,y+eave-0.14,z,depth+0.5,length+0.5,0.14,Self.tile)
        box(x,y+eave+rise-0.08,z,0.42,length+1.5,0.26,Map3DPalette.portal)
        for end: Float in [-1,1] {
            // The gable ends: posts and a tie beam in dark timber, a window between.
            let gz=z+end*(length/2+0.03)
            for dx: Float in [-depth/2+0.1,-1.4,1.4,depth/2-0.1] { box(x+dx,y+1.0,gz,0.2,0.08,eave-1.0,Self.timber) }
            box(x,y+eave-0.1,gz,depth,0.08,0.2,Self.timber)
            box(x,y+eave+0.2,gz,0.2,0.08,rise-0.6,Self.timber)
            box(x,y+1.9,gz,1.8,0.10,1.3,Self.glass)
        }
        for side: Float in [-1,1] {
            let wall=x+side*depth/2
            // The lean-to roof, its posts and braces.
            leanTo(from:wall,to:wall+side*porch,high:y+3.5,low:y+2.95,z:z,width:length+1.2,color:Self.rust)
            for dz in stride(from:-length/2,through:length/2,by:Float(3.666)) {
                box(wall+side*(porch-0.2),y,z+dz,0.18,0.18,2.9,Self.timber)
                beam(Map3DPoint(wall+side*(porch-0.2),y+2.1,z+dz),Map3DPoint(wall+side*(porch-0.95),y+3.05,z+dz),0.12,Self.timber)
            }
            // The high band: windows between white name boards.
            for (i,dz) in stride(from:-length/2+1.7,through:length/2-1.6,by:Float(2.66)).enumerated() {
                if i%2==0 { window(wall,y+3.85,z+dz,side:side,width:1.9,height:0.95) }
                else if side>0 { board(wall,y+3.75,z+dz,side:side,size:1.4) }
            }
            // Under the lean-to: doors and windows in dark frames.
            for dz in stride(from:-length/2+2.2,through:length/2-2,by:Float(3.5)) where abs(dz-5.3)>1 { window(wall,y+1.1,z+dz,side:side,width:2.2,height:1.7) }
            // The way through to the platform, open and in shadow.
            if side>0 { box(wall+0.03,y,z+5.3,0.10,2.6,2.7,Self.ink) }
        }
        crossGable(x,y,z,depth:depth,eave:eave,rise:rise)
        // Clipped trees between the building and the platform.
        for dz: Float in [-8.6,-5.4,6.6] {
            let tx=x-depth/2-porch-2.2
            box(tx,y,z+dz,0.26,0.26,1.9,Map3DPalette.trunk)
            box(tx,y+1.9,z+dz,2.3,2.6,0.9,Map3DPalette.crown)
            box(tx,y+2.8,z+dz,1.5,1.8,0.35,Map3DPalette.crown)
        }
        // The forecourt's hedges in brick planters, either side of the way in.
        for dz: Float in [-6.2,5.2] {
            let w: Float=dz<0 ? 8.5 : 5
            box(x+depth/2+porch+1.6,y,z+dz,1.5,w,0.5,Map3DPalette.brick)
            box(x+depth/2+porch+1.6,y+0.5,z+dz,1.3,w-0.2,0.8,Map3DPalette.crown)
        }
    }

    /// A closed sloping slab from the wall at `from` out to `to`.
    mutating func leanTo(from: Float,to: Float,high: Float,low: Float,z: Float,width: Float,color: UInt32) {
        let t: Float=0.12,inside=Map3DPoint((from+to)/2,(high+low)/2-t/2,z)
        func p(_ x: Float,_ y: Float,_ s: Float) -> Map3DPoint { Map3DPoint(x,y,z+s*width/2) }
        face([p(from,high,-1),p(to,low,-1),p(to,low,1),p(from,high,1)],inside:inside,color:color)
        face([p(from,high-t,-1),p(to,low-t,-1),p(to,low-t,1),p(from,high-t,1)],inside:inside,color:Map3DColor.shaded(color,0.7))
        face([p(to,low,-1),p(to,low,1),p(to,low-t,1),p(to,low-t,-1)],inside:inside,color:color)
        face([p(from,high,-1),p(from,high,1),p(from,high-t,1),p(from,high-t,-1)],inside:inside,color:color)
        for s: Float in [-1,1] { face([p(from,high,s),p(to,low,s),p(to,low-t,s),p(from,high-t,s)],inside:inside,color:color) }
    }
    /// A window on the wall at `wall`, facing `side` (+1 the front): glass in a dark frame.
    mutating func window(_ wall: Float,_ y: Float,_ z: Float,side: Float,width: Float,height: Float,frame: UInt32 = StationKitBuilder.timber) {
        box(wall+side*0.04,y,z,0.10,width+0.24,height+0.24,frame)
        box(wall+side*0.08,y+0.12,z,0.06,width,height,Self.glass)
    }
    /// A white name board with a dark mark, where the station's name is written.
    mutating func board(_ wall: Float,_ y: Float,_ z: Float,side: Float,size: Float) {
        box(wall+side*0.06,y,z,0.10,size,size,Self.white)
        box(wall+side*0.10,y+size*0.30,z,0.04,size*0.40,size*0.40,Map3DPalette.canopy)
    }
    /// The gable over the platform side (−x), with its round window.
    mutating func crossGable(_ x: Float,_ y: Float,_ z: Float,depth: Float,eave: Float,rise: Float) {
        let half: Float=4.2,top=y+eave+rise-0.05,low=y+eave,wall=x-depth/2-0.5,out=wall-0.6
        let inside=Map3DPoint(wall,low,z),t=Map3DPoint(0,0.12,0)
        // Its wall stands half a metre proud of the hall's.
        box(wall+0.5,y,z,1.0,half*2-0.5,1.0,Self.timber)
        box(wall+0.5,y+1.0,z,1.0,half*2-0.54,eave-1.0,Self.plaster)
        for s: Float in [-1,1] {
            let slope=[Map3DPoint(out,top,z),Map3DPoint(x,top,z),Map3DPoint(x-depth/2,low,z+s*half),Map3DPoint(out,low,z+s*half)]
            face(slope.map { $0+t },inside:inside,color:Map3DColor.shaded(Self.tile,s>0 ? 0.95 : 0.85))
            // The overhang's underside and its dark verge board.
            face([slope[0],slope[3],Map3DPoint(wall,low,z+s*half),Map3DPoint(wall,top,z)],inside:inside+Map3DPoint(0,5,0),color:Map3DColor.shaded(Self.tile,0.7))
            face([slope[0]+t,slope[3]+t,slope[3]-t,slope[0]-t],inside:inside,color:Self.timber)
            box(wall,y+1.0,z+s*(half-0.35),0.08,0.2,eave-1.0,Self.timber)
        }
        mesh.addFacet([Map3DPoint(wall-0.02,low,z+half-0.25),Map3DPoint(wall-0.02,low,z-half+0.25),Map3DPoint(wall-0.02,top-0.2,z)],color:Self.plaster)
        box(wall-0.03,low-0.1,z,0.08,half*2-0.5,0.2,Self.timber)
        // The round window, and the name boards either side of it.
        func ring(_ r: Float,_ dx: Float) -> [Map3DPoint] {
            (0..<10).map { i in let a=Float(i)*2*Float.pi/10;return Map3DPoint(wall-dx,low+1.45+sinf(a)*r,z-cosf(a)*r) }
        }
        mesh.addFacet(ring(0.62,0.05),color:Self.timber)
        mesh.addFacet(ring(0.38,0.08),color:Self.glass)
        for s: Float in [-1,1] {
            board(wall,low-1.2,z+s*1.9,side:-1,size:1.6)
            window(wall,y+1.3,z+s*2.1,side:-1,width:1.6,height:1.2)
        }
    }
}

// Jiji (集集, 1930, rebuilt after the 1999 earthquake), on the Jiji Line: a
// short gabled hall of cream boards under dark tiles, its gables and the
// band under its eaves boarded slate blue, and round all four sides a
// wide, low veranda roof in a lighter grey on cream posts with forked
// braces. A small white gable breaks the veranda's front, off centre,
// carrying the four white name boards; red lanterns hang along the eaves.
// Shape and colours read from photographs (Wikimedia Commons; the list is
// in this round's report); the sizes are estimates from the posts and the
// people in them, not a survey.
extension StationKitBuilder {
    static let slate=Map3DPalette.tinAwnings[3],cream=Map3DPalette.schoolWalls,skirt=Map3DPalette.tinRoofs[2]

    /// The building, its middle at (`x`, `z`) on ground `y`: its front
    /// (+x) to the forecourt, its back to the platforms.
    mutating func jiji(_ x: Float,_ y: Float,_ z: Float) {
        let length: Float=15.8,depth: Float=7.2,eave: Float=4.3,rise: Float=2.8
        let front: Float=3.0,back: Float=2.4,end: Float=4.0,high=y+3.5,low=y+2.85
        let hx=depth/2,hz=length/2,porchZ=z+3.4
        // The veranda's floor, a step above the forecourt.
        box(x+(front-back)/2,y,z,depth+front+back+0.3,length+end*2+0.3,0.12,Map3DPalette.granite)
        // Walls: a boarded dado, cream boards above, slate boards over the veranda's roof.
        box(x,y,z,depth+0.08,length+0.08,1.0,Map3DPalette.counters[0])
        box(x,y+1.0,z,depth,length,2.6,Self.cream)
        box(x,y+3.4,z,depth+0.04,length+0.04,eave-3.4,Self.slate)
        // The hall's roof, its ridge along the platforms, with its ridge tiles and slate fascias.
        mesh.addGableRoof(base:Map3DPoint(x,y+eave,z),forward:Map3DPoint(0,0,1),length:length,width:depth,rise:rise,overhang:0.6,color:Self.tile,gable:Self.slate)
        box(x,y+eave-0.14,z,depth+0.4,length+0.4,0.14,Self.tile)
        box(x,y+eave+rise-0.08,z,0.42,length+1.4,0.26,Map3DPalette.portal)
        let drop=rise*0.6/hx
        for side: Float in [-1,1] {
            box(x+side*(hx+0.6),y+eave-drop-0.2,z,0.08,length+1.2,0.2,Self.slate)
            tileCourses(low:Map3DPoint(x+side*(hx+0.6),y+eave-drop,z),high:Map3DPoint(x,y+eave+rise,z),count:5,color:Map3DColor.shaded(Self.tile,0.8)) { _ in length/2+0.6 }
        }
        for e: Float in [-1,1] {
            // The gable ends: verge boards, and a small window under a hood.
            let gz=z+e*(hz+0.6)
            for side: Float in [-1,1] { beam(Map3DPoint(x+side*(hx+0.6),y+eave-drop-0.1,gz),Map3DPoint(x,y+eave+rise-0.1,gz),0.2,Self.slate) }
            box(x,y+eave+0.35,z+e*(hz+0.05),1.3,0.10,1.1,Self.white)
            box(x,y+eave+0.47,z+e*(hz+0.09),1.06,0.06,0.86,Self.glass)
            box(x,y+eave+1.5,z+e*(hz+0.25),1.7,0.5,0.1,Self.slate)
            // Under the veranda: a window in the end wall.
            box(x,y+1.1,z+e*(hz+0.04),2.4,0.10,1.9,Map3DPalette.stone)
            box(x,y+1.22,z+e*(hz+0.08),2.16,0.06,1.66,Self.glass)
        }
        verandaRoof(x,z,hx:hx,hz:hz,front:front,back:back,end:end,high:high,low:low)
        // Its posts on stone feet, forked braces under the eaves' beam.
        let beamTop=low-0.14,fx=x+hx+front-0.25,bx=x-hx-back+0.25,ez=hz+end-0.25
        box(fx,beamTop-0.2,z,0.16,ez*2,0.2,Self.cream)
        box(bx,beamTop-0.2,z,0.16,ez*2,0.2,Self.cream)
        for e: Float in [-1,1] { box((fx+bx)/2,beamTop-0.2,z+e*ez,fx-bx,0.16,0.2,Self.cream) }
        for dz: Float in [-ez,-8.4,-5.2,-2.0,8.6,ez] { post(fx,y,z+dz,top:beamTop-0.2,alongZ:true) }
        for i in 0..<8 { post(bx,y,z-ez+Float(i)*ez*2/7,top:beamTop-0.2,alongZ:true) }
        for e: Float in [-1,1] { for dx: Float in [-2.7,0.3,3.3] { post(x+dx,y,z+e*ez,top:beamTop-0.2,alongZ:false) } }
        // Red lanterns hung from the eaves' edge, along the front and round both ends:
        // half out from under the roof, so the row shows from above too.
        let hung=low-0.14,edge=x+hx+front+0.05
        for dz: Float in [-10.6,-8.2,-5.8,-3.4,-1.0,7.4,9.8] {
            lantern(edge,hung,z+dz)
        }
        for e: Float in [-1,1] { for dx: Float in [-1.6,1.0,3.6] { lantern(x+dx,hung,z+e*(hz+end+0.05)) } }
        // Doors and windows in pale frames; the way through to the platform, open and in shadow.
        for side: Float in [-1,1] {
            let wall=x+side*hx
            for (dz,w) in [(Float(-5.6),Float(2.4)),(-2.2,2.4),(6.4,1.8)] { window(wall,y+1.1,z+dz,side:side,width:w,height:1.9,frame:Map3DPalette.stone) }
            box(wall+side*0.03,y,porchZ,0.10,2.6,2.7,Map3DPalette.arcade)
        }
        namePorch(x+hx,y,porchZ,reach:front+0.5,low:low)
        steamMonument(x+hx+front+3.6,y,z-1.2)
        // The forecourt's green: a tree at one corner, a flower bed in a brick kerb beside it.
        tree(x+hx+front+5.0,y,z-10.4,size:1.25)
        box(x+hx+front+2.8,y,z-6.6,2.4,3.6,0.45,Map3DPalette.brick)
        box(x+hx+front+2.8,y+0.45,z-6.6,2.1,3.3,0.55,Map3DPalette.crown)
    }

    /// The veranda's roof: four slopes from the walls (`hx`, `hz` from the
    /// middle) at `high` out to the eaves at `low`, a closed slab.
    mutating func verandaRoof(_ x: Float,_ z: Float,hx: Float,hz: Float,front: Float,back: Float,end: Float,high: Float,low: Float) {
        let t: Float=0.14
        func ring(_ px: Float,_ nx: Float,_ pz: Float,_ h: Float) -> [Map3DPoint] {
            [Map3DPoint(x+px,h,z-pz),Map3DPoint(x+px,h,z+pz),Map3DPoint(x-nx,h,z+pz),Map3DPoint(x-nx,h,z-pz)]
        }
        let inner=ring(hx,hx,hz,high),outer=ring(hx+front,hx+back,hz+end,low)
        let below=Map3DPoint(x,low-2,z),above=Map3DPoint(x,high+6,z),down=Map3DPoint(0,t,0)
        for i in 0..<4 {
            let j=(i+1)%4,shade: Float=[0.97,0.86,0.80,0.90][i]
            face([inner[i],inner[j],outer[j],outer[i]],inside:below,color:Map3DColor.shaded(Self.skirt,shade))
            face([inner[i]-down,inner[j]-down,outer[j]-down,outer[i]-down],inside:above,color:Map3DColor.shaded(Self.skirt,0.7))
            // The eaves' white fascia.
            let edge=[outer[i]+Map3DPoint(0,0.02,0),outer[j]+Map3DPoint(0,0.02,0),outer[j]-down,outer[i]-down]
            face(edge,inside:below+Map3DPoint(0,2,0),color:Self.white)
        }
    }

    /// A veranda post at (`x`, `z`): a stone foot, the shaft up to `top`,
    /// and two braces forking along the eaves' beam.
    mutating func post(_ x: Float,_ y: Float,_ z: Float,top: Float,alongZ: Bool) {
        box(x,y,z,0.36,0.36,0.5,Map3DPalette.concrete)
        box(x,y+0.5,z,0.2,0.2,top-y-0.5,Self.cream)
        for s: Float in [-1,1] {
            let reach: Float=0.8*s
            beam(Map3DPoint(x,top-0.85,z),Map3DPoint(x+(alongZ ? 0 : reach),top+0.02,z+(alongZ ? reach : 0)),0.12,Self.cream)
        }
    }

    /// The small gable over the way in, from the wall at `wall` out past
    /// the veranda's eaves, with the four name boards on its white front.
    mutating func namePorch(_ wall: Float,_ y: Float,_ z: Float,reach: Float,low: Float) {
        let half: Float=2.3,top=y+4.3,eaves=low+0.15,out=wall+reach,t=Map3DPoint(0,0.12,0)
        let inside=Map3DPoint(wall+reach/2,eaves,z)
        for s: Float in [-1,1] {
            let slope=[Map3DPoint(wall,top,z),Map3DPoint(out,top,z),Map3DPoint(out,eaves,z+s*half),Map3DPoint(wall,eaves,z+s*half)]
            face(slope,inside:inside,color:Map3DColor.shaded(Self.skirt,s>0 ? 0.92 : 0.84))
            face(slope.map { $0-t },inside:inside+Map3DPoint(0,5,0),color:Map3DColor.shaded(Self.skirt,0.7))
            // The white barge board, and the post under its foot.
            beam(Map3DPoint(out,eaves-0.05,z+s*(half+0.05)),Map3DPoint(out,top-0.05,z),0.42,Self.white)
            box(out-0.3,y,z+s*(half-0.15),0.36,0.36,0.5,Map3DPalette.concrete)
            box(out-0.3,y+0.5,z+s*(half-0.15),0.22,0.22,eaves-y-0.7,Self.cream)
        }
        // The front: a cream panel behind the barge boards, a tie beam, the boards.
        mesh.addFacet([Map3DPoint(out-0.1,eaves-0.12,z-half),Map3DPoint(out-0.1,top-0.12,z),Map3DPoint(out-0.1,eaves-0.12,z+half)],color:Self.cream)
        mesh.addFacet([Map3DPoint(out-0.1,eaves-0.12,z+half),Map3DPoint(out-0.1,top-0.12,z),Map3DPoint(out-0.1,eaves-0.12,z-half)],color:Map3DColor.shaded(Self.cream,0.8))
        box(out-0.3,eaves-0.4,z,0.22,half*2,0.22,Self.cream)
        // Its ridge tiles, and the four boards with the station's name.
        box((wall+out)/2,top-0.02,z,reach+0.1,0.3,0.12,Map3DPalette.portal)
        // Four boards step up to the gable's middle; a shorter name's stand level.
        let name=Self.boardName(real:"集集",game:gameName)
        nameBoards(name,x:out+0.3,y:eaves,z:z,facing:1,size:1.12,pitch:1.24,lifts:name.count==4 ? [-0.45,0.2,0.2,-0.45] : name.count==3 ? [-0.1,0.2,-0.1] : [0.2,0.2],board:Self.white,ink:Self.ink)
        // The English name board, hung under the tie beam.
        box(out-0.3,eaves-0.95,z,0.08,2.4,0.55,Self.white)
        box(out-0.25,eaves-0.72,z,0.04,1.5,0.07,Map3DPalette.stone)
    }

    /// The forecourt's monument: a small dark steam engine on a stone
    /// pedestal, in a round bed of white pebbles within a stone kerb.
    mutating func steamMonument(_ x: Float,_ y: Float,_ z: Float) {
        let iron=Map3DColor.shaded(Map3DPalette.arcade,0.55),gold=Map3DPalette.platformEdge
        cylinder(x,y,z,radius:2.7,height:0.3,color:Map3DPalette.stone,sides:16)
        cylinder(x,y+0.3,z,radius:2.3,height:0.08,color:Self.white,sides:16)
        box(x,y+0.38,z,1.9,4.2,0.45,Map3DPalette.granite)
        // The engine, side on to the station's front: frame, boiler, cab, chimney and dome.
        box(x,y+0.83,z,1.15,3.6,0.4,iron)
        barrel(Map3DPoint(x,y+1.72,z-0.55),Map3DPoint(x,y+1.72,z+1.75),radius:0.5,color:iron)
        barrel(Map3DPoint(x,y+1.72,z+1.75),Map3DPoint(x,y+1.72,z+1.8),radius:0.4,color:Map3DPalette.portal)
        box(x,y+1.23,z-1.15,1.25,1.2,1.55,iron)
        box(x,y+2.78,z-1.15,1.4,1.35,0.08,iron)
        cylinder(x,y+2.18,z+1.3,radius:0.2,height:0.75,color:iron,sides:8)
        cylinder(x,y+2.18,z+0.4,radius:0.27,height:0.35,color:iron,sides:8)
        for side: Float in [-1,1] {
            box(x+side*0.5,y+1.3,z+0.55,0.06,1.9,0.5,iron)
            box(x+side*0.54,y+1.42,z+0.55,0.04,1.6,0.22,gold)
            for dz: Float in [-0.6,0.3,1.2] { box(x+side*0.6,y+0.83,z+dz,0.04,0.6,0.6,Map3DPalette.portal) }
        }
    }

    /// A round red paper lantern hung at (`x`, `z`) from `top`, with its dark caps.
    mutating func lantern(_ x: Float,_ top: Float,_ z: Float) {
        box(x,top-0.12,z,0.08,0.08,0.12,Self.ink)
        cylinder(x,top-0.2,z,radius:0.2,height:0.08,color:Self.ink,sides:8)
        cylinder(x,top-0.72,z,radius:0.33,height:0.52,color:Map3DPalette.lantern,sides:8)
        cylinder(x,top-0.8,z,radius:0.2,height:0.08,color:Self.ink,sides:8)
    }

    /// A round bar from `a` to `b` along z (a boiler, a tank): eight sides and its two ends.
    mutating func barrel(_ a: Map3DPoint,_ b: Map3DPoint,radius: Float,color: UInt32) {
        let ring=(0..<8).map { i -> Map3DPoint in let t=(Float(i)+0.5)*Float.pi/4;return Map3DPoint(cosf(t)*radius,sinf(t)*radius,0) }
        let middle=(a+b)*0.5
        for i in 0..<8 { face([a+ring[i],a+ring[(i+1)%8],b+ring[(i+1)%8],b+ring[i]],inside:middle,color:Map3DColor.shaded(color,i<4 ? 1 : 0.8)) }
        face(ring.map { a+$0 },inside:middle,color:color)
        face(ring.map { b+$0 },inside:middle,color:color)
    }
}
