import Foundation

extension StationKitBuilder {
    mutating func coastalCamp(_ part: Map3DCoastalKit.Part) {
        let wood=Self.coastalWood,steel=Self.steel,white=Self.white,green=Self.coastalGreen,blue=Self.coastalBlue
        switch part {
        case .domeTent:
            box(0,0,0,2.8,2.5,0.06,Self.ink)
            // Three closed faceted bands, with a continuous ridge cap.
            let xs: [Float]=[-1.35,-0.9,0,0.9,1.35],ys: [Float]=[0.06,0.95,1.6,0.95,0.06]
            for i in 0..<4 {
                let a=Map3DPoint(xs[i],ys[i],0),b=Map3DPoint(xs[i+1],ys[i+1],0)
                coastalPanel(a,b,width:2.4,thickness:0.045,color:green)
            }
            for z: Float in [-1.18,1.18] {
                // Solid end wall provides the backed, closed zip-door silhouette.
                let p=zip(xs,ys).map { Map3DPoint($0.0,$0.1,z-0.025) }
                coastalPrism(p,p.map { $0+Map3DPoint(0,0,0.05) },green)
                for i in 0..<4 { beam(Map3DPoint(xs[i],ys[i],z),Map3DPoint(xs[i+1],ys[i+1],z),0.04,white) }
            }
            box(0,0.06,-1.225,0.75,0.035,1.0,Self.ink)
            box(0,0.06,-1.25,0.025,0.02,1.0,white)
        case .ridgeTent:
            box(0,0,0,3.8,2.6,0.06,Self.ink)
            let a=Map3DPoint(-1.6,0.06,0),b=Map3DPoint(0,1.7,0),c=Map3DPoint(1.6,0.06,0)
            coastalPanel(a,b,width:2.4,thickness:0.045,color:blue);coastalPanel(b,c,width:2.4,thickness:0.045,color:blue)
            for z: Float in [-1.18,1.18] {
                let p=[Map3DPoint(-1.6,0.06,z),Map3DPoint(1.6,0.06,z),Map3DPoint(0,1.7,z)]
                coastalPrism(p,p.map { $0+Map3DPoint(0,0,0.045) },blue)
            }
            box(0,0.06,-1.21,0.7,0.04,1.1,Self.ink)
            // Rear edge enters the backed triangular end wall; keep its width
            // inside the actual wall height at y=1.2. Front edge has two posts.
            for x: Float in [-0.42,0.42] {
                box(x,0,-2,0.055,0.055,1.2,steel)
                beam(Map3DPoint(x,1.2,-2),Map3DPoint(x,1.2,-1.1),0.05,steel)
            }
            box(0,1.2,-1.6,0.9,1.0,0.04,white)
        case .hammockStand:
            for x: Float in [-1.65,1.65] {
                box(x,0,0,0.3,1.3,0.12,wood)
                for z: Float in [-0.55,0.55] { beam(Map3DPoint(x,0.1,z),Map3DPoint(x,1.45,0),0.10,wood) }
            }
            box(0,0.12,0,3.35,0.12,0.12,wood)
            // Thick sagging cloth and ropes meet exactly the same end nodes.
            for i in 0..<8 {
                let x=Float(i)/8*2.6-1.3,nx=Float(i+1)/8*2.6-1.3
                let y: Float=0.58+0.47*(x/1.3)*(x/1.3),ny: Float=0.58+0.47*(nx/1.3)*(nx/1.3)
                coastalPanel(Map3DPoint(x,y,0),Map3DPoint(nx,ny,0),width:0.85,thickness:0.035,color:i%2==0 ? green:white)
            }
            for sign: Float in [-1,1] { for z: Float in [-0.42,0.42] {
                civicTube(Map3DPoint(sign*1.3,1.05,z),Map3DPoint(sign*1.65,1.4,0),radius:0.025,color:steel,sides:8)
            } }
        case .campKitchen:
            civicLegs(0,0,0,length:1.5,width:0.65,height:0.88,color:steel)
            box(0,0.88,0,1.8,0.85,0.06,wood)
            box(0,0.25,0,1.6,0.7,0.05,steel)
            box(0,0.94,0.38,1.8,0.06,0.24,steel)
            box(-0.48,0.94,0,0.65,0.58,0.07,Self.ink)
            for x: Float in [-0.62,-0.33] { coastalRing(Map3DPoint(x,1.025,0),radius:0.11,tube:0.018,color:steel,segments:8) }
            cylinder(0.48,0.30,0,radius:0.18,height:0.42,color:blue,sides:10)
            cylinder(0.48,0.72,0,radius:0.06,height:0.08,color:steel,sides:8)
            // Gas line is held by the worktop, rather than hanging in air.
            civicTube(Map3DPoint(0.48,0.8,0),Map3DPoint(0.48,0.91,0.28),radius:0.02,color:Self.ink,sides:6)
        case .foldingChair:
            for z: Float in [-0.32,0.32] {
                for x: Float in [-0.35,0.35] { box(x,0,z,0.09,0.09,0.05,steel) }
                beam(Map3DPoint(-0.35,0.04,z),Map3DPoint(0.30,0.52,z),0.055,steel)
                beam(Map3DPoint(0.35,0.04,z),Map3DPoint(-0.28,0.52,z),0.055,steel)
                box(-0.28,0.5,z,0.055,0.055,0.55,steel)
                box(-0.02,0.69,z,0.62,0.08,0.05,wood)
            }
            box(0,0.49,0,0.65,0.65,0.04,green)
            box(-0.28,0.65,0,0.05,0.65,0.40,green)
        case .campTable:
            for z: Float in [-0.35,0.35] {
                for x: Float in [-0.65,0.65] { box(x,0,z,0.09,0.09,0.05,steel) }
                beam(Map3DPoint(-0.65,0.025,z),Map3DPoint(0.60,0.64,z),0.05,steel)
                beam(Map3DPoint(0.65,0.025,z),Map3DPoint(-0.60,0.64,z),0.05,steel)
            }
            box(0,0.64,0,1.6,0.85,0.06,wood)
            box(0,0.30,0,0.06,0.75,0.06,steel)
        case .firePit:
            for z: Float in [-0.35,0.35] {
                for x: Float in [-0.4,0.4] { box(x,0,z,0.09,0.09,0.05,steel) }
                beam(Map3DPoint(-0.4,0.025,z),Map3DPoint(0.32,0.5,z),0.05,steel)
                beam(Map3DPoint(0.4,0.025,z),Map3DPoint(-0.32,0.5,z),0.05,steel)
            }
            box(0,0.35,0,0.65,0.65,0.06,Self.ink)
            for z: Float in [-0.32,0.32] { beam(Map3DPoint(-0.36,0.49,z),Map3DPoint(0.36,0.49,z),0.08,steel) }
            for x: Float in [-0.32,0.32] { box(x,0.40,0,0.06,0.7,0.12,steel) }
            // Unlit crossed firewood: a static asset with no fire/heat simulation.
            beam(Map3DPoint(-0.22,0.43,-0.18),Map3DPoint(0.22,0.43,0.18),0.09,wood)
            beam(Map3DPoint(0.22,0.52,-0.18),Map3DPoint(-0.22,0.52,0.18),0.09,wood)
        case .kayakRack:
            for x: Float in [-1,1] {
                box(x,0,0,0.35,1.8,0.10,wood);box(x,0.1,0,0.14,0.14,2.1,wood)
                for y: Float in [0.65,1.45] { box(x,y,0,0.14,1.6,0.10,wood) }
            }
            beam(Map3DPoint(-1,0.2,0),Map3DPoint(1,2.0,0),0.08,steel)
            // Two long low closed hulls, each resting on its own rack arm.
            for (y,z) in [(Float(0.75),Float(-0.45)),(1.55,0.45)] {
                let p=[Map3DPoint(-1.7,y,z),Map3DPoint(-1.25,y,z-0.23),Map3DPoint(1.25,y,z-0.23),Map3DPoint(1.7,y,z),Map3DPoint(1.25,y,z+0.23),Map3DPoint(-1.25,y,z+0.23)]
                coastalPrism(p,p.map { $0+Map3DPoint(0,0.18,0) },y<1 ? blue:green)
                box(0,y+0.18,z,0.65,0.3,0.025,Self.ink)
            }
        default: break
        }
    }
}
