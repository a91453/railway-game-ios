import Foundation

extension SceneKitBuilder {
    mutating func train(_ asset: Map3DSceneKit.Asset) {
        let v=asset.variant
        let original=Map3DTrainStyle.all
        var style=original[0],tint=Map3DPalette.canopy
        var isLocomotive=false,single=false
        switch asset.family {
        case .traModern:
            style=original[v<3 ? 1 : 0]
            tint=v==2 || v==5 ? Map3DPalette.templeRoof : v==4 ? Map3DPalette.crown : v==3 ? Map3DPalette.canopy : Map3DPalette.lantern
            if v==1 { style.nose=3.4;style.drop=0.8;style.band=0.2...0.43;style.line=nil;style.screenDown=0.58 }
            if v==2 { style.nose=4.2;style.drop=1;style.band=0.27...0.36;style.line=nil;style.windowWidth=0.85 }
            if v==3 { style.nose=1.8;style.screenDown=0.55;style.band=0.3...0.45 }
            if v==4 { style.nose=2.2;style.tuck=0.18;style.screenDown=0.5 }
            isLocomotive=v==5
        case .metro:
            if v==0 {
                style=original[2]
                // 700T's rounded shorter nose, rather than copying the native
                // high-speed style's N700ST shoulder wing and cockpit ridge.
                style.nose=7.2;style.wing=0;style.canopy=0.06;style.cap=0.62
                style.drop=1.5;style.dive=0.12;style.screenTo=0.60
                style.length=24;style.halfWidth=1.69;tint=Map3DPalette.templeRoof
            } else {
                style=original[v==2 ? 4 : 3]
                tint=v==3 || v==5 ? Map3DPalette.crown : v==4 ? Map3DPalette.shopAwnings[2] : Map3DPalette.canopy
                style.length=v==2 ? 12.6 : v==4 ? 20 : 22
                style.nose=v==4 ? 2.7 : v==1 ? 0.65 : 1.1
                style.doors=v==2 ? 2 : v==4 ? 3 : 4
                style.band=v==4 ? 0.26...0.39 : 0.34...0.41
            }
        case .traClassic:
            style=original[v==3 ? 1 : 0]
            style.nose=v==0 || v==2 ? 0.25 : v==1 ? 2.1 : 2.8
            style.drop=v==0 || v==2 ? 0.1 : 0.5
            style.doors=v==0 ? 3 : v==2 ? 2 : 1
            style.doorLayout=v>=2 ? .carEnds : .even
            style.band=v>=2 ? 0.2...0.42 : 0.31...0.39
            style.length=v==2 ? 20 : 19.4
            tint=v<2 ? Map3DPalette.canopy : Map3DPalette.templeRoof
            single=v==2;isLocomotive=v>=4
        case .lightRail:
            style=original[v<3 ? 4 : 3]
            if v<3 {
                style.length=11;style.floor=0.28;style.roof=3.2
                style.nose=2+Float(v)*0.2;style.windows=0.3...0.83
                style.doors=2;style.screenDown=0.68
            } else { style.length=v==3 ? 20 : 21;style.nose=v==4 ? 0.4 : 1.9 }
            tint=v==0 || v==2 ? Map3DPalette.crown : v==1 ? Map3DPalette.shopAwnings[0] : v==5 ? Map3DPalette.platformEdge : Map3DPalette.canopy
        default: break
        }
        if isLocomotive {
            locomotive(variant:v,modern:asset.family == .traModern)
            style.nose=0.15;style.drop=0.05;style.doors=2;style.band=0.22...0.6
            let coach=Map3DTrainBuilder(style:style,cab:false).model(named:asset.id+"-coach")
            addModel(coach,at:Map3DPoint(-19,0,0),tint:tint)
        } else {
            let head=Map3DTrainBuilder(style:style,cab:true).model(named:asset.id+"-head")
            addModel(head,at:Map3DPoint(single ? 0 : style.length/2+0.18,0,0),tint:tint)
            if !single {
                let tail=Map3DTrainBuilder(style:style,cab:false,pantograph:asset.family == .traModern && v<3).model(named:asset.id+"-tail")
                addModel(tail,at:Map3DPoint(-style.length/2-0.18,0,0),tint:tint)
                box(0,0.75,0,0.65,1.7,1.9,Map3DTrainStyle.under)
            }
        }
    }

    mutating func locomotive(variant: Int,modern: Bool) {
        let color=Map3DPalette.templeRoof
        box(0,0.5,0,17.5,2.9,0.7,Map3DTrainStyle.under)
        if modern || variant==5 {
            box(0,1.2,0,15.9,2.8,2.7,color)
            box(6.9,1.2,0,2.3,2.9,2.7,Map3DPalette.tileWhite)
            box(8.08,2.25,0,0.08,2.1,1.15,Map3DTrainStyle.glass)
            box(0,3.9,0,15.4,2.8,0.16,Self.ink)
        } else {
            box(-1.9,1.2,0,11.3,2.2,2.15,color)
            box(5.2,1.2,0,3.8,2.8,2.9,color)
            box(7.14,2.55,0,0.08,2.1,1,Map3DTrainStyle.glass)
            box(-1.9,3.35,0,11,2.25,0.12,Map3DPalette.tileWhite)
        }
        for x: Float in [-5,5] { for z: Float in [-1.2,1.2] { for dx: Float in [-0.75,0.75] {
            wheel(x+dx,0.55,z,radius:0.5,width:0.2)
        }}}
        box(8.9,1.0,0,0.4,1.5,0.25,Self.ink)
    }

    mutating func station(_ v: Int) {
        switch v {
        case 0:
            box(0,0,0,17,25,0.3,Map3DPalette.plaza)
            box(0,0.3,0,12,20,5,Map3DPalette.brick)
            windows(length:12,width:20,floors:1,start:0.3)
            hip(0,5.3,0,length:13,width:21,rise:3,color:Map3DPalette.gymGreen)
            box(7,3.5,0,4,24,0.2,Map3DPalette.gymGreen)
            for z: Float in [-10,-5,0,5,10] { box(8.5,0.3,z,0.25,0.25,3.2,Map3DPalette.stone) }
        case 1,2:
            let length: Float=v==2 ? 36 : 24,width: Float=v==2 ? 44 : 31
            commercialBlock(x:0,z:0,length:length,width:width,floors:v==2 ? 3 : 2,variant:v)
            if v==2 {
                mesh.addBarrelRoof(base:Map3DPoint(0,10,0),forward:Self.forward,length:length+2,width:width+2,rise:6,color:Map3DPalette.roof,end:Self.glass)
            } else { box(0,7.2,0,length+3,width+3,0.3,Map3DPalette.tileWhite) }
            box(length/2+3,3.8,0,6,width*0.8,0.2,Self.glass)
            for z: Float in [-width*0.35,width*0.35] { box(length/2+5,0,z,0.3,0.3,3.8,Self.steel) }
        case 3:
            // Stairs descend into a real opening, not a picture on a base.
            for i in 0..<10 { box(-4+Float(i)*0.65,-2.5+Float(i)*0.25,0,0.65,3.2,0.25,Map3DPalette.concrete) }
            for z: Float in [-1.8,1.8] {
                box(0,-2.5,z,7,0.25,3.2,Map3DPalette.concrete)
                box(1,0.7,z,0.12,0.12,2.5,Self.steel)
                box(-3,0.7,z,0.12,0.12,2.5,Self.steel)
            }
            box(-0.6,3.2,0,7.5,4.4,0.18,Map3DPalette.canopy)
        case 4:
            for x: Float in [-16,0,16] { for z: Float in [-3,3] { box(x,0,z,1,1,8,Map3DPalette.concrete) }}
            box(0,8,0,43,13,0.7,Map3DPalette.concrete)
            box(0,8.7,0,40,11,5,Map3DPalette.tileWhite)
            windows(length:40,width:11,floors:1,start:8.7,office:true)
            mesh.addBarrelRoof(base:Map3DPoint(0,13.7,0),forward:Self.forward,length:43,width:14,rise:2,color:Map3DPalette.roof,end:Map3DPalette.roof)
        case 5,6:
            platform(length:v==5 ? 22 : 42,width:v==5 ? 3.5 : 6.4,height:v==5 ? 0.3 : 1.15)
        case 7:
            box(0,5.2,0,5,22,0.5,Map3DPalette.concrete)
            for sign: Float in [-1,1] {
                for step in 0..<12 { box(Float(step)*0.65,Float(step)*0.4,sign*9,0.65,3.3,0.4,Map3DPalette.concrete) }
                beam(Map3DPoint(0,1,sign*10.7),Map3DPoint(7.8,5.8,sign*10.7),thickness:0.12,color:Self.steel)
                box(0,5.7,sign*10.7,5,0.12,1,Self.steel)
            }
        default:
            box(0,0,0,33,24,0.3,Map3DPalette.concrete)
            box(0,0.3,0,29,21,7,Map3DPalette.shedWalls[0])
            gable(0,7.3,0,length:30,width:22,rise:3,color:Map3DPalette.tinRoofs[0])
            for z: Float in [-5,5] {
                box(14.55,0.3,z,0.1,5.5,5,Map3DTrainStyle.glass)
                track(from:Map3DPoint(-10,0.4,z),to:Map3DPoint(22,0.4,z))
            }
        }
    }

    mutating func platform(length: Float,width: Float,height: Float) {
        box(0,0,0,length,width,height,Map3DPalette.platform)
        for z: Float in [-width/2+0.12,width/2-0.12] { box(0,height,z,length,0.18,0.02,Map3DPalette.platformEdge) }
        for x in stride(from:-length/2+3,through:length/2-2,by:Float(5)) {
            box(x,height,0,0.18,0.18,3.3,Self.steel)
        }
        gable(0,height+3.3,0,length:length-2,width:width+0.6,rise:0.6,color:Map3DPalette.canopy)
        bench(0,height,0)
    }

    mutating func track(from a: Map3DPoint,to b: Map3DPoint,gauge: Float = 1.067) {
        guard let direction=(b-a).normalized else { return }
        let across=Map3DPoint(-direction.z,0,direction.x)
        let length=sqrtf((b-a).dot(b-a))
        let centre=(a+b)*0.5
        mesh.addBox(base:centre,forward:direction,length:length,width:3.1,height:0.2,top:Map3DPalette.ballast,side:Map3DPalette.ballast)
        for sign: Float in [-1,1] { beam(a+across*(sign*gauge/2)+Map3DPoint(0,0.3,0),b+across*(sign*gauge/2)+Map3DPoint(0,0.3,0),thickness:0.1,color:Map3DPalette.railTop) }
        let sleepers=max(1,Int(length/0.7))
        for i in 0...sleepers {
            let middle=a+(b-a)*(Float(i)/Float(sleepers))+Map3DPoint(0,0.22,0)
            mesh.addBox(base:middle,forward:direction,length:0.2,width:2.05,height:0.1,top:Map3DPalette.concrete,side:Map3DPalette.concrete)
        }
    }

    mutating func railway(_ v: Int) {
        switch v {
        case 0: track(from:Map3DPoint(-10,0,0),to:Map3DPoint(10,0,0))
        case 1: track(from:Map3DPoint(0,0,-10),to:Map3DPoint(0,0,10))
        case 2:
            for i in 0..<12 {
                let a=Float(i)*Float.pi/24,b=Float(i+1)*Float.pi/24
                track(from:Map3DPoint(cosf(a)*14-7,0,sinf(a)*14-7),to:Map3DPoint(cosf(b)*14-7,0,sinf(b)*14-7))
            }
        case 3:
            track(from:Map3DPoint(-10,0,0),to:Map3DPoint(10,0,0))
            track(from:Map3DPoint(-3,0,0),to:Map3DPoint(10,0,5))
        case 4,5:
            box(0,6,0,30,6,0.7,v==4 ? Map3DPalette.concrete : Map3DPalette.bridge)
            for x: Float in [-12,12] { box(x,0,0,1.8,3,6,Map3DPalette.concrete) }
            track(from:Map3DPoint(-15,6.7,0),to:Map3DPoint(15,6.7,0))
            if v==5 {
                for z: Float in [-2.7,2.7] {
                    beam(Map3DPoint(-15,11,z),Map3DPoint(15,11,z),thickness:0.3,color:Map3DPalette.bridge)
                    for x in stride(from:Float(-15),to:15,by:5) {
                        beam(Map3DPoint(x,6.7,z),Map3DPoint(x+5,11,z),thickness:0.25,color:Map3DPalette.bridge)
                        beam(Map3DPoint(x,11,z),Map3DPoint(x+5,6.7,z),thickness:0.25,color:Map3DPalette.bridge)
                    }
                }
            }
        case 6:
            box(0,0,-3.9,5,2,7,Map3DPalette.portal);box(0,0,3.9,5,2,7,Map3DPalette.portal)
            box(0,6,0,5,6,1.2,Map3DPalette.portal)
            track(from:Map3DPoint(-7,0,0),to:Map3DPoint(7,0,0))
        case 7:
            box(0,0,0,10,16,0.15,Map3DPalette.road(.minor))
            track(from:Map3DPoint(-10,0.15,0),to:Map3DPoint(10,0.15,0))
            for sign: Float in [-1,1] {
                box(sign*3,0.15,sign*3,0.4,0.4,1.3,Map3DPalette.platformEdge)
                beam(Map3DPoint(sign*3,1.4,sign*3),Map3DPoint(sign*3,5.2,sign*2),thickness:0.12,color:Map3DPalette.lantern)
            }
        case 8: signal()
        case 9:
            for z: Float in [-4.5,4.5] { box(0,0,z,0.3,0.3,6.5,Self.steel) }
            box(0,6.2,0,0.3,9.4,0.3,Self.steel)
            for z: Float in [-1,1] { beam(Map3DPoint(0,5.5,z),Map3DPoint(0,6.3,z+0.5),thickness:0.07,color:Self.steel) }
        case 10:
            track(from:Map3DPoint(-3,0,0),to:Map3DPoint(3,0,0))
            box(1.7,0.3,0,0.3,2.1,1.4,Map3DPalette.platformEdge)
            for z: Float in [-0.8,0.8] { beam(Map3DPoint(-0.5,0.3,z),Map3DPoint(1.7,1.6,z),thickness:0.25,color:Map3DPalette.platformEdge) }
        default:
            box(0,0,0,1.2,0.8,2,Self.steel);box(1.2,0,0,0.55,0.6,1.2,Map3DPalette.plant)
        }
    }

    mutating func signal() {
        box(0,0,0,0.7,0.7,0.3,Map3DPalette.concrete)
        cylinder(0,0.3,0,radius:0.09,height:4.8,color:Self.steel,sides:6)
        box(0.12,3.8,0,0.22,0.6,1.5,Self.ink)
        for (i,color) in [Map3DPalette.lantern,Map3DPalette.platformEdge,Map3DPalette.crown].enumerated() {
            box(0.25,4+Float(i)*0.43,0,0.08,0.35,0.28,color)
        }
    }
}
