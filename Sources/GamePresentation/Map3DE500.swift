import Foundation

/// Photo-led E500. Dimensions and estimated fittings are documented in tools/e500-refresh.
/// Builder: X front, Y up, Z right. Model.flat converts once to native X front/Y left/Z up.
public enum Map3DE500 {
    public static let bodyColor = Map3DPalette.shopAwnings[0]
    public static let maskColor = Map3DPalette.playerRim
    public static let glassColor = Map3DColor.shaded(Map3DPalette.glazing, 0.5)
    public static func model(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.e500Body(far: far)
        return .flat(named: far ? "e500-far" : "e500", from: b.mesh)
    }
}

extension StationKitBuilder {
    private mutating func e500Panel(_ p: [Map3DPoint], offset: Map3DPoint, color: UInt32) {
        let q=p.map { $0+offset }, centre=(p+q).reduce(Map3DPoint.zero,+)*(1/Float(p.count*2))
        face(p,inside:centre,color:color);face(q,inside:centre,color:color)
        for i in p.indices { let j=(i+1)%p.count;face([p[i],p[j],q[j],q[i]],inside:centre,color:color) }
    }
    fileprivate mutating func e500Body(far: Bool) {
        let teal=Map3DE500.bodyColor, dark=Map3DE500.maskColor, glass=Map3DE500.glassColor
        let steel=Self.steel, white=Map3DPalette.shopAwnings[3], tyre=Map3DStreetModel.tyre
        // Each level has its own width and front station: longitudinal rake and transverse shoulders separate.
        let hs:[Float]=[1.15,2.45,2.65,3.25,3.62,3.75]
        let ws:[Float]=[1.3795,1.3795,1.3795,1.3795,1.16,0.98]
        func noseX(_ h:Float)->Float { 9.99-max(0,h-2.45)*0.64 }
        for k in 0..<hs.count-1 {
            let h=hs[k], H=hs[k+1], w=ws[k], W=ws[k+1]
            let ring=[Map3DPoint(-noseX(h),h,-w+0.15),Map3DPoint(-noseX(h)+0.3,h,-w),Map3DPoint(noseX(h)-0.3,h,-w),Map3DPoint(noseX(h),h,-w+0.15),Map3DPoint(noseX(h),h,w-0.15),Map3DPoint(noseX(h)-0.3,h,w),Map3DPoint(-noseX(h)+0.3,h,w),Map3DPoint(-noseX(h),h,w-0.15)]
            let upper=[Map3DPoint(-noseX(H),H,-W+0.15),Map3DPoint(-noseX(H)+0.3,H,-W),Map3DPoint(noseX(H)-0.3,H,-W),Map3DPoint(noseX(H),H,-W+0.15),Map3DPoint(noseX(H),H,W-0.15),Map3DPoint(noseX(H)-0.3,H,W),Map3DPoint(-noseX(H)+0.3,H,W),Map3DPoint(-noseX(H),H,W-0.15)]
            for i in ring.indices { let j=(i+1)%ring.count
                let c=(k>=4 || (k>=1 && [0,2,4,6].contains(i))) ? dark:teal
                face([ring[i],ring[j],upper[j],upper[i]],inside:Map3DPoint(0,2.5,0),color:c)
            }
            if k==0 {face(ring,inside:Map3DPoint(0,2.5,0),color:dark)}
            if k==hs.count-2 {face(upper,inside:Map3DPoint(0,2.5,0),color:dark)}
        }
        box(0,1.03,0,19.5,2.5,0.12,dark)
        // Smooth machine-room sides; no fictional row of large side grilles.
        for s:Float in [-1,1] {
            box(0,1.18,s*1.384,14.65,0.018,2.48,teal)
            box(0,3.64,s*1.35,14.7,0.06,0.06,steel)
            box(0,1.37,s*1.40,14.6,0.025,0.035,dark)
            for end:Float in [-1,1] {
                let door=end*7.6, window=end*8.55
                box(door,1.4,s*1.39,0.62,0.025,2.12,dark)
                box(door,1.45,s*1.408,0.55,0.015,2.02,teal)
                box(door,2.78,s*1.422,0.25,0.012,0.55,glass)
                box(door-end*0.19,2.19,s*1.427,0.12,0.035,0.04,white)
                box(window,2.6,s*1.39,0.86,0.028,0.83,dark)
                box(window,2.66,s*1.412,0.73,0.025,0.69,glass)
                box(door,1.19,s*1.45,0.7,0.18,0.09,steel)
                if !far {for y:Float in [1.55,1.8] {box(door, y,s*1.40,0.52,0.04,0.035,steel)}}
            }
        }
        // Planar face mapping preserves the frontal shape of both windscreen and lamps.
        for end:Float in [-1,1] {
            let mask:[(Float,Float)]=[(-0.86,2.48),(-1.08,2.55),(-1.20,2.76),(-1.20,3.27),(-1.01,3.61),(1.01,3.61),(1.20,3.27),(1.20,2.76),(1.08,2.55),(0.86,2.48)]
            e500Panel(mask.map { z,h in Map3DPoint(end*(noseX(h)+0.008),h,z) },offset:Map3DPoint(end*0.012,0,0),color:dark)
            let outline:[(Float,Float)]=[(-1.04,2.63),(-1.14,2.78),(-1.14,3.35),(-0.98,3.54),(0.98,3.54),(1.14,3.35),(1.14,2.78),(1.04,2.63)]
            let p=outline.map { z,h in Map3DPoint(end*(noseX(h)+0.025),h,z) }
            e500Panel(p,offset:Map3DPoint(end*0.025,0,0),color:glass)
            for z:Float in [-0.85,0.85] {
                box(end*10.005,1.94,z,0.035,0.59,0.30,dark)
                for dz:Float in [-0.15,0.15] {
                    let start=mesh.vertices.count
                    civicTube(Map3DPoint(end*10.022,2.09,z+dz),Map3DPoint(end*10.055,2.09,z+dz),radius:0.098,color:dz*end>0 ? white:steel,sides:far ? 8:12)
                    if end>0 && dz>0 {mesh.makeGlowing(from:start)}
                }
            }
            for z:Float in [-0.145,0.145] {
                let h:Float=3.63
                civicTube(Map3DPoint(end*(noseX(h)+0.015),h,z),Map3DPoint(end*(noseX(h)+0.07),h,z),radius:0.095,color:white,sides:far ? 8:12)
            }
            if !far {for s:Float in [-1,1] {
                let a:Float=2.68, H:Float=2.87
                beam(Map3DPoint(end*(noseX(a)+0.065),a,s*0.63),Map3DPoint(end*(noseX(H)+0.065),H,s*0.2),0.022,dark)
            }}
            for side:Float in [-1,1] {
                let skirt=[Map3DPoint(end*8.48,1.18,side*1.34),Map3DPoint(end*9.28,0.55,side*1.34),Map3DPoint(end*9.99,0.55,side*1.34),Map3DPoint(end*9.99,1.18,side*1.34)]
                e500Panel(skirt,offset:Map3DPoint(0,0,side*0.035),color:teal)
            }
            box(end*9.94,1.29,0,0.15,2.5,0.12,teal)
            box(end*10.13,0.88,0,0.51,0.37,0.26,dark)
            let pilot=[Map3DPoint(end*10.14,0.22,-0.93),Map3DPoint(end*10.14,0.22,0.93),Map3DPoint(end*10.03,0.52,1.12),Map3DPoint(end*10.03,0.52,-1.12)]
            e500Panel(pilot,offset:Map3DPoint(-end*0.06,0,0),color:steel)
            for z:Float in [-0.93,0.93] {
                beam(Map3DPoint(end*9.87,0.48,z),Map3DPoint(end*9.87,1.3,z),0.08,steel)
                if !far {beam(Map3DPoint(end*10.06,1.35,z),Map3DPoint(end*10.08,0.57,z*0.65),0.045,dark)}
            }
        }
        // Two Co-Co bogies: gauge and wheel diameter are sourced; centres/axle pitch estimated.
        for c:Float in [-6.1,6.1] {
            box(c,0.61,0,4.5,0.8,0.26,steel)
            box(c,0.87,0,1.3,1.8,0.16,dark)
            for dx:Float in [-1.65,0,1.65] {
                let x=c+dx
                civicTube(Map3DPoint(x,0.462,-0.68),Map3DPoint(x,0.462,0.68),radius:0.07,color:steel,sides:6)
                for s:Float in [-1,1] {
                    civicTube(Map3DPoint(x,0.462,s*0.50),Map3DPoint(x,0.462,s*0.66),radius:0.462,color:tyre,sides:far ? 8:12)
                    civicTube(Map3DPoint(x,0.462,s*0.66),Map3DPoint(x,0.462,s*0.69),radius:0.28,color:steel,sides:far ? 8:12)
                    box(x,0.38,s*0.91,0.36,0.2,0.27,dark)
                    if !far {for a:Float in [-0.38,0.38] {cylinder(x+a,0.57,s*0.88,radius:0.095,height:0.23,color:dark,sides:8)}}
                }
            }
            for s:Float in [-1,1] {box(c,0.60,s*0.87,4.55,0.14,0.16,steel)}
        }
        for x:Float in [-8.05,-4.25,4.25,8.05] {for z:Float in [-1.05,1.05] {
            cylinder(x,0.52,z,radius:0.14,height:0.50,color:steel,sides:far ? 6:10)
            box(x,1.0,z,0.38,0.36,0.08,dark)
        }}
        box(0,0.67,0,5.9,1.5,0.35,dark)
        for x:Float in [-2.7,2.7] {civicTube(Map3DPoint(x,0.75,-0.94),Map3DPoint(x,0.75,0.94),radius:0.17,color:steel,sides:far ? 8:12)}
        // Roof modules. Main HV area toward +X; rear pantograph stowed.
        box(0,3.75,0,14.5,2.38,0.10,steel)
        for x:Float in [-5.7,-4.35,-3,-1.65,-0.3,1.05] {
            let section:[(Float,Float)]=[(3.85,-1.05),(3.85,1.05),(4.18,0.78),(4.18,-0.78)]
            let a=section.map { h,z in Map3DPoint(x-0.61,h,z) },b=section.map { h,z in Map3DPoint(x+0.61,h,z) },inside=Map3DPoint(x,4,0)
            face(a,inside:inside,color:steel);face(b,inside:inside,color:steel)
            for j in 0..<4 {let n=(j+1)%4;face([a[j],a[n],b[n],b[j]],inside:inside,color:steel)}
            if !far {for z:Float in [-1,1] {for i in 0..<7 {beam(Map3DPoint(x-0.5+Float(i)*0.16,3.89,z*1.02),Map3DPoint(x-0.5+Float(i)*0.16,4.14,z*0.82),0.026,dark)}}}
        }
        for x:Float in [-8.4,8.4] {box(x,3.75,0,1.45,1.9,0.34,steel)}
        for x:Float in [5.7,-6.55] {
            for z:Float in [-0.45,0.45] {cylinder(x,3.85,z,radius:0.12,height:0.20,color:white,sides:8)}
            box(x,4.05,0,1.1,1.15,0.06,dark)
            let raised=x>0, base:Float=4.11, knee:Float=raised ? 4.75:4.19, tip:Float=raised ? 5.35:4.28
            for z:Float in [-0.37,0.37] {
                beam(Map3DPoint(x-0.4,base,z),Map3DPoint(x+0.6,knee,z*0.5),0.055,steel)
                beam(Map3DPoint(x+0.6,knee,z*0.5),Map3DPoint(x-0.55,tip,0),0.045,steel)
            }
            box(x-0.55,tip-0.035,0,0.12,1.72,0.035,dark)
        }
        for x:Float in [3.1,4.15] {
            cylinder(x,3.85,0.55,radius:0.17,height:0.40,color:dark,sides:8)
            if !far {for h:Float in [3.95,4.05,4.15] {cylinder(x,h,0.55,radius:0.21,height:0.025,color:steel,sides:8)}}
        }
    }
}
