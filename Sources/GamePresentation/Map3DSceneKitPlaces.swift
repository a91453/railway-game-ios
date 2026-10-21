import Foundation

extension SceneKitBuilder {
    mutating func street(_ v: Int) {
        switch v {
        case 0,1: tank(0,0,0,blue:v==0)
        case 2:
            for z: Float in [-0.8,0.8] {
                box(0,0,z,0.7,0.9,0.75,Map3DPalette.acUnit)
                wheel(0.37,0.38,z,radius:0.26,width:0.06)
            }
        case 3:
            box(0,0,0,2.5,2,2.4,Map3DPalette.shedWalls[0])
            gable(0,2.4,0,length:2.7,width:2.2,rise:0.45,color:Map3DPalette.tinRoofs[0])
            box(1.27,0,0,0.06,0.8,1.9,Map3DPalette.rollerDoor)
        case 4:
            box(0,2.4,0,2,4,0.13,Map3DPalette.shopAwnings[0])
            for z: Float in [-1.9,1.9] { box(0.8,0,z,0.09,0.09,2.4,Self.steel) }
            box(0.95,2,0,0.1,4,0.4,Map3DPalette.shopAwnings[0])
        case 5:
            for z: Float in [-1.8,1.8] {
                box(0,0,z,0.45,0.45,0.16,Map3DPalette.concrete)
                addModel(Map3DProp.lamp.model(),at:Map3DPoint(0,0.16,z),scale:0.85)
            }
        case 6: signal()
        case 7:
            planter(0,0,-1.5,size:1.8);planter(0,0,1.5,size:1.5)
        case 8:
            box(0,0,0,3.4,6,0.15,Map3DPalette.platform)
            for z: Float in [-2.7,2.7] {
                box(-1,0.15,z,0.12,0.12,2.8,Self.steel)
                box(1,0.15,z,0.12,0.12,2.8,Self.steel)
            }
            box(-1,0.8,0,0.08,5.5,1.8,Self.glass)
            box(0,2.95,0,3.8,6.3,0.15,Map3DPalette.canopy)
            bench(0,0.15,0,length:4)
        case 9:
            // Parked, unoccupied scooters: no rider from the street-life
            // model, and no face or private reference mesh.
            for i in 0..<3 {
                let z=Float(i)*1.1
                wheel(-0.55,0.3,z,radius:0.3,width:0.14)
                wheel(0.6,0.3,z,radius:0.3,width:0.14)
                box(0,0.3,z,1.3,0.45,0.35,Map3DPalette.shopAwnings[i])
                box(-0.25,0.65,z,0.65,0.45,0.12,Self.ink)
                beam(Map3DPoint(0.6,0.5,z),Map3DPoint(0.45,1.1,z),thickness:0.09,color:Self.steel)
                box(0.45,1.05,z,0.08,0.6,0.08,Self.steel)
            }
        case 10:
            bench(0,0,-1);bench(0,0,1)
            cylinder(1.6,0,0,radius:0.3,height:0.8,color:Map3DPalette.stone,sides:8)
        default:
            addModel(Map3DProp.pole.model())
            for z: Float in [-0.8,0,0.8] { beam(Map3DPoint(0,9.4,z),Map3DPoint(4,9.1,z),thickness:0.035,color:Self.ink) }
        }
    }

    mutating func park(_ v: Int) {
        let length: Float=v==1 || v==6 ? 24 : 16,width: Float=v==1 ? 5 : v==6 ? 6 : 15
        box(0,0,0,length,width,0.15,v==7 ? Map3DPalette.farm : Map3DPalette.park)
        switch v {
        case 0:
            box(0,0.15,0,13,12,0.05,Map3DPalette.plaza)
            for x: Float in [-4,4] { planter(x,0.2,-3,size:2.4) }
            bench(0,0.2,3,length:3)
        case 1:
            for x: Float in [-8,0,8] { tree(x,0.15,0,size:1.2) }
        case 2:
            box(0,0.15,0,12,11,0.07,Map3DPalette.gymGreen)
            for x: Float in [-1.5,1.5] { for z: Float in [-1.3,1.3] { box(x,0.22,z,0.15,0.15,2.8,Map3DPalette.trunk) }}
            box(0,2,0,3.5,3,0.15,Map3DPalette.counters[1])
            hip(0,3.1,0,length:4,width:3.6,rise:1,color:Map3DPalette.canopy)
            // An actual sloping slide, not a texture.
            for z: Float in [-0.6,0.6] { beam(Map3DPoint(1.7,2.1,z),Map3DPoint(5,0.3,z),thickness:0.12,color:Map3DPalette.platformEdge) }
            mesh.addFacet([Map3DPoint(1.7,2,-0.6),Map3DPoint(1.7,2,0.6),Map3DPoint(5,0.25,0.6),Map3DPoint(5,0.25,-0.6)],color:Map3DPalette.roof)
            for i in 0..<6 { box(-2.2,Float(i)*0.3,-2.2+Float(i)*0.25,0.9,0.25,0.3,Map3DPalette.platformEdge) }
        case 3:
            box(0,0.15,0,8,8,0.25,Map3DPalette.plaza)
            for x: Float in [-3.3,3.3] { for z: Float in [-3.3,3.3] { box(x,0.4,z,0.25,0.25,3.1,Map3DPalette.concrete) }}
            hip(0,3.5,0,length:8.5,width:8.5,rise:2,color:Map3DPalette.roof)
            bench(-1,0.4,0);bench(1,0.4,0)
        case 4:
            box(0,0.15,0,14,12,0.06,Map3DPalette.gymGreen)
            for sign: Float in [-1,1] {
                box(sign*6.7,0.22,0,0.12,11.6,0.02,Map3DPalette.tileWhite)
                box(0,0.22,sign*5.7,13.4,0.12,0.02,Map3DPalette.tileWhite)
            }
            box(-5.5,0.2,0,0.15,0.15,3.4,Self.steel)
            box(-5.3,3,0,0.1,1.7,1,Map3DPalette.tileWhite)
            beam(Map3DPoint(-5.2,3.1,0),Map3DPoint(-4.4,3.1,0),thickness:0.12,color:Map3DPalette.templeRoof)
        case 5:
            box(0,0.15,0,14,13,0.08,Map3DPalette.plaza)
            planter(0,0.23,0,size:3.5)
            for x: Float in [-4,4] { bench(x,0.23,0,length:3) }
        case 6:
            box(0,0.15,0,24,4.4,0.15,Map3DPalette.plaza)
            for x in stride(from:Float(-11),through:11,by:3) { box(x,0.3,-2.6,0.1,0.1,1.1,Self.steel) }
            for y: Float in [0.65,1.3] { beam(Map3DPoint(-12,y,-2.6),Map3DPoint(12,y,-2.6),thickness:0.09,color:Self.steel) }
            for x: Float in [-8,8] { tree(x,0.3,1.9,size:0.8) }
        case 7:
            for x: Float in [-5,0,5] { for z: Float in [-4,0,4] {
                box(x,0.15,z,3.3,2.2,0.3,Map3DPalette.trunk)
                for row: Float in [-0.6,0,0.6] { box(x,0.45,z+row,3,0.25,0.25,Map3DPalette.crown) }
            }}
        default:
            box(0,0.15,0,13,10,0.1,Map3DPalette.plaza)
            for z in stride(from:Float(-4),through:4,by:1) {
                beam(Map3DPoint(-1,0.3,z),Map3DPoint(-1,1.1,z),thickness:0.07,color:Self.steel)
                beam(Map3DPoint(1,0.3,z),Map3DPoint(1,1.1,z),thickness:0.07,color:Self.steel)
            }
            for x: Float in [-5,5] { tree(x,0.25,0,size:0.8) }
        }
    }

    mutating func ground(_ v: Int) {
        let road=Map3DPalette.road(.secondary),walk=Map3DPalette.sidewalk,yellow=Map3DPalette.centreLine
        switch v {
        case 0:
            box(0,0,0,24,10,0.15,road)
            for z: Float in [-6,6] { box(0,0,z,24,2,0.3,walk) }
            for z: Float in [-0.1,0.1] { box(0,0.16,z,24,0.08,0.015,yellow) }
        case 1,2:
            box(0,0,0,24,24,0.15,walk)
            box(0,0.15,0,24,9,0.03,road)
            box(0,0.15,v==2 ? 6 : 0,9,v==2 ? 12 : 24,0.03,road)
            for sign: Float in [-1,1] {
                zebra(x:sign*7,z:0,alongX:true)
                if v==1 || sign>0 { zebra(x:0,z:sign*7,alongX:false) }
            }
        case 3:
            // A quarter-circle assembled from native strips, including
            // kerbs and the centre line. Road surfaces remain composable
            // in 3D without painted perspective baked into a PNG.
            let points=(0...16).map { i -> Map3DPoint in
                let a=Float(i)*Float.pi/32
                return Map3DPoint(cosf(a)*14-7,0.16,sinf(a)*14-7)
            }
            closedRibbon(points,width:12,depth:0.3,color:walk)
            closedRibbon(points.map { $0+Map3DPoint(0,0.02,0) },width:9,depth:0.03,color:road)
            closedRibbon(points.map { $0+Map3DPoint(0,0.06,0) },width:0.12,depth:0.01,color:yellow)
        case 4,7:
            box(0,0,0,24,14,0.2,Map3DPalette.plaza)
            for x: Float in [-8,8] { planter(x,0.2,0,size:2.5) }
            bench(0,0.2,3,length:3)
        case 5,6:
            box(0,0,0,24,16,0.15,road)
            for i in 0...6 { box(-11+Float(i)*3.6,0.16,0,0.08,10,0.02,Map3DPalette.tileWhite) }
            box(0,0.16,-5,22,0.08,0.02,Map3DPalette.tileWhite)
            if v==5 {
                for x: Float in [-10,10] { box(x,0.15,6.5,0.15,0.15,3.2,Self.steel) }
                box(0,3.35,6.5,23,2.5,0.15,Map3DPalette.canopy)
            }
        default:
            box(0,0,0,24,4.2,0.15,Map3DPalette.gymGreen)
            for z: Float in [-2.8,2.8] { box(0,0,z,24,1.4,0.3,walk) }
            for z: Float in [-1.8,1.8] { box(0,0.16,z,24,0.08,0.02,Map3DPalette.tileWhite) }
        }
    }

    mutating func zebra(x: Float,z: Float,alongX: Bool) {
        for i in -3...3 {
            if alongX { box(x,0.2,z+Float(i)*0.9,2.5,0.45,0.02,Map3DPalette.tileWhite) }
            else { box(x+Float(i)*0.9,0.2,z,0.45,2.5,0.02,Map3DPalette.tileWhite) }
        }
    }

    mutating func closedRibbon(_ points: [Map3DPoint],width: Float,depth: Float,color: UInt32) {
        mesh.addRibbon(along:points,width:width,depth:depth,top:color,side:color)
        let across=Map3DMesh.acrossDirections(points),drop=Map3DPoint(0,-depth,0)
        for i in 0..<points.count-1 {
            let a=points[i]-across[i]*(width/2)+drop,b=points[i+1]-across[i+1]*(width/2)+drop
            let c=points[i+1]+across[i+1]*(width/2)+drop,d=points[i]+across[i]*(width/2)+drop
            mesh.addFacet([a,b,c,d],color:Map3DColor.shaded(color,0.7))
        }
    }
}
