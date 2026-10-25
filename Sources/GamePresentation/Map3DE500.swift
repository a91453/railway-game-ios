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
    private func e500Rounded(_ p:[(Float,Float)], far:Bool)->[(Float,Float)] {
        var out:[(Float,Float)]=[]
        for i in p.indices {
            let a=p[(i+p.count-1)%p.count],b=p[i],c=p[(i+1)%p.count],f:Float=0.23
            let u=(b.0+(a.0-b.0)*f,b.1+(a.1-b.1)*f),v=(b.0+(c.0-b.0)*f,b.1+(c.1-b.1)*f)
            let n=far ? 1:3
            for j in 0...n {let t=Float(j)/Float(n),q=1-t
                out.append((q*q*u.0+2*q*t*b.0+t*t*v.0,q*q*u.1+2*q*t*b.1+t*t*v.1))
            }
        }
        return out
    }
    fileprivate mutating func e500Body(far: Bool) {
        let teal=Map3DE500.bodyColor, dark=Map3DE500.maskColor, glass=Map3DE500.glassColor
        let steel=Self.steel, white=Map3DPalette.shopAwnings[3], tyre=Map3DStreetModel.tyre
        // Preserve the longitudinal rake and maximum body width; round only the cab's plan corners.
        let hs:[Float]=[1.15,2.45,2.65,3.25,3.62,3.75]
        let ws:[Float]=[1.3795,1.3795,1.3795,1.3795,1.16,0.98]
        func noseX(_ h:Float)->Float { 9.99-max(0,h-2.45)*0.64 }
        func ring(_ h:Float,_ w:Float)->[Map3DPoint] {
            let f=noseX(h),d:Float=0.30,r:Float=0.15,n=far ? 2:5
            var q:[Map3DPoint]=[]
            for end:Float in [-1,1] {
                for side:Float in [-1,1] {
                    // Each corner travels from side to face; mirrored order follows the convex perimeter.
                    let reverse = end*side<0
                    for j in 0...n {
                        let t=Float(reverse ? n-j:j)*Float.pi/(2*Float(n))
                        q.append(Map3DPoint(end*(f-d+d*sinf(t)),h,side*(w-r+r*cosf(t))))
                    }
                }
            }
            return q.sorted { atan2f($0.z,$0.x)<atan2f($1.z,$1.x) }
        }
        for k in 0..<hs.count-1 {
            let lower=ring(hs[k],ws[k]),upper=ring(hs[k+1],ws[k+1])
            for i in lower.indices {
                let j=(i+1)%lower.count,mid=(lower[i]+lower[j])*0.5
                let onFace=abs(lower[i].x-lower[j].x)<0.00001 && abs(mid.x)>9
                let corner=abs(mid.x)>9.0 && !onFace
                let c=(k>=4 || (k>=1 && corner)) ? dark:teal
                face([lower[i],lower[j],upper[j],upper[i]],inside:Map3DPoint(0,2.5,0),color:c)
            }
            if k==0 {face(lower,inside:Map3DPoint(0,2.5,0),color:dark)}
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
                box(door,2.74,s*1.422,0.25,0.012,0.66,glass)
                box(door-end*0.19,2.19,s*1.427,0.12,0.035,0.04,white)
                box(window,2.53,s*1.39,0.90,0.028,0.94,dark)
                for shift:Float in [-0.205,0.205] {box(window+shift,2.59,s*1.412,0.37,0.025,0.82,glass)}
                if !far {
                    box(window,2.59,s*1.44,0.025,0.014,0.82,steel)
                    let hand=door-end*0.43
                    beam(Map3DPoint(hand,1.84,s*1.44),Map3DPoint(hand,2.74,s*1.44),0.035,steel)
                    for h:Float in [1.84,2.74] {box(hand,h,s*1.412,0.09,0.06,0.04,steel)}
                }
                box(door,1.19,s*1.45,0.7,0.18,0.09,steel)
                if !far {for y:Float in [1.55,1.8] {box(door, y,s*1.40,0.52,0.04,0.035,steel)}}
            }
        }
        // Planar face mapping preserves the frontal shape of both windscreen and lamps.
        for end:Float in [-1,1] {
            let mask:[(Float,Float)]=[(-0.86,2.48),(-1.08,2.55),(-1.20,2.76),(-1.20,3.27),(-1.01,3.61),(1.01,3.61),(1.20,3.27),(1.20,2.76),(1.08,2.55),(0.86,2.48)]
            e500Panel(e500Rounded(mask,far:far).map { z,h in Map3DPoint(end*(noseX(h)+0.008),h,z) },offset:Map3DPoint(end*0.012,0,0),color:dark)
            let outline:[(Float,Float)]=[(-1.04,2.63),(-1.14,2.78),(-1.14,3.35),(-0.98,3.54),(0.98,3.54),(1.14,3.35),(1.14,2.78),(1.04,2.63)]
            let p=e500Rounded(outline,far:far).map { z,h in Map3DPoint(end*(noseX(h)+0.025),h,z) }
            e500Panel(p,offset:Map3DPoint(end*0.025,0,0),color:glass)
            for z:Float in [-0.85,0.85] {
                let lamp:[(Float,Float)]=[(z-0.19,1.94),(z-0.30,2.02),(z-0.30,2.16),(z-0.19,2.24),(z+0.19,2.24),(z+0.30,2.16),(z+0.30,2.02),(z+0.19,1.94)]
                e500Panel(e500Rounded(lamp,far:far).map { y,h in Map3DPoint(end*9.999,h,y) },offset:Map3DPoint(end*0.03,0,0),color:dark)
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
            // End beam and supported coupling mass replace the empty frontal frame.
            box(end*9.99,0.94,0,0.15,2.26,0.36,dark)
            box(end*10.13,0.88,0,0.51,0.37,0.26,dark)
            box(end*10.27,0.77,0,0.23,0.48,0.29,steel)
            box(end*10.35,0.82,0,0.065,0.30,0.17,dark)
            if !far {for z:Float in [-0.79,-0.50,0.50,0.79] {
                let a=Map3DPoint(end*10.10,1.25,z),b=Map3DPoint(end*10.20,0.57,z*0.86),c=Map3DPoint(end*10.18,0.48,z*0.54)
                beam(a,b,0.046,dark);beam(b,c,0.046,dark)
                box(end*10.09,1.25,z,0.10,0.12,0.08,steel)
            }}
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
                    civicTube(Map3DPoint(x,0.462,s*0.69),Map3DPoint(x,0.462,s*1.08),radius:0.10,color:steel,sides:far ? 4:8)
                    box(x,0.36,s*1.10,0.40,0.22,0.27,dark)
                    if !far {civicTube(Map3DPoint(x,0.462,s*1.20),Map3DPoint(x,0.462,s*1.23),radius:0.12,color:steel,sides:8)}
                }
            }
            for side:Float in [-1,1] {
                let outer=side*1.10
                box(c,0.79,outer,4.60,0.20,0.13,steel)
                for dx:Float in [-1.65,0,1.65] {
                    box(c+dx,0.61,outer,0.52,0.20,0.20,steel)
                    if !far {for d:Float in [-0.35,0.35] {beam(Map3DPoint(c+dx,0.68,outer),Map3DPoint(c+dx+d,0.85,outer),0.09,steel)}}
                }
                for dx:Float in [-0.825,0.825] {
                    box(c+dx,0.59,outer,0.46,0.29,0.08,dark)
                    cylinder(c+dx,0.67,outer,radius:0.12,height:0.27,color:dark,sides:far ? 4:8)
                    if !far {for h:Float in [0.69,0.76,0.83,0.90] {cylinder(c+dx,h,outer,radius:0.15,height:0.025,color:steel,sides:8)}}
                    box(c+dx,0.94,outer,0.46,0.30,0.09,steel)
                }
                if !far {for dx:Float in [-2.18,2.18] {
                    beam(Map3DPoint(c+dx,0.55,outer),Map3DPoint(c+dx*0.88,0.82,outer),0.11,steel)
                }}
                if !far {beam(Map3DPoint(c-1.8,0.54,side*1.25),Map3DPoint(c+1.8,0.54,side*1.25),0.035,steel)}
            }
        }
        for x:Float in [-8.05,-4.25,4.25,8.05] {for z:Float in [-1.05,1.05] {
            cylinder(x,0.52,z,radius:0.14,height:0.50,color:steel,sides:far ? 6:10)
            box(x,1.0,z,0.38,0.36,0.08,dark)
        }}
        box(0,0.67,0,5.9,1.5,0.35,dark)
        for x:Float in [-2.7,2.7] {civicTube(Map3DPoint(x,0.75,-0.94),Map3DPoint(x,0.75,0.94),radius:0.17,color:steel,sides:far ? 8:12)}
        // Toshiba Fig.4/5: one HV/pantograph module, central louver housings, a separate long end housing.
        box(0,3.75,0,14.5,2.38,0.10,steel)
        for x:Float in [-8.4,8.4] {
            box(x,3.75,0,1.45,1.9,0.27,steel)
            if !far {for i in 0..<6 {box(x-0.50+Float(i)*0.2,3.83,0.957,0.035,0.02,0.14,dark)}}
        }
        func module(_ x:Float,_ length:Float,_ top:Float,_ upperWidth:Float)->[Map3DPoint] {
            [(Float(3.85),Float(-1.08)),(3.85,1.08),(top,upperWidth/2),(top,-upperWidth/2)].map { h,z in Map3DPoint(x,h,z) }
        }
        let housings:[(Float,Float,Float,Float)]=[(-5.35,3.10,4.20,1.75),(-2.40,2.10,4.27,1.70),(-0.15,2.10,4.27,1.70),(2.10,2.10,4.27,1.70)]
        for (x,length,top,width) in housings {
            let a=module(x-length/2,length,top,width),b=module(x+length/2,length,top,width),inside=Map3DPoint(x,4,0)
            face(a,inside:inside,color:steel);face(b,inside:inside,color:steel)
            for j in 0..<4 {let n=(j+1)%4;face([a[j],a[n],b[n],b[j]],inside:inside,color:steel)}
            for side:Float in [-1,1] {
                // Inset dark louver band follows the actual sloping housing side, with backing.
                let low:Float=3.91,high=top-0.08
                func lateral(_ h:Float)->Float {side*(1.08-(h-3.85)/(top-3.85)*(1.08-width/2)+0.009)}
                let inset:Float=length>3 ? 0.22:0.12
                let p=[Map3DPoint(x-length/2+inset,low,lateral(low)),Map3DPoint(x+length/2-inset,low,lateral(low)),Map3DPoint(x+length/2-inset,high,lateral(high)),Map3DPoint(x-length/2+inset,high,lateral(high))]
                e500Panel(p,offset:Map3DPoint(0,0,side*0.012),color:dark)
                if !far {
                    let count=Int(length/0.16)
                    for i in 1..<count {
                        let X=x-length/2+inset+Float(i)*(length-2*inset)/Float(count)
                        beam(Map3DPoint(X,low,lateral(low)+side*0.025),Map3DPoint(X,high,lateral(high)+side*0.025),0.025,steel)
                    }
                }
            }
            if !far {
                box(x,top,0,0.56,width*0.68,0.025,steel)
                box(x,top+0.025,0,0.41,width*0.54,0.018,dark)
            }
        }
        // Asymmetric HV tray with supported insulators and single-arm collector.
        box(5.15,3.85,0,3.65,2.16,0.055,steel)
        for x:Float in [3.72,4.48] {
            cylinder(x,3.905,0.53,radius:0.16,height:0.36,color:dark,sides:far ? 6:8)
            if !far {for h:Float in [3.97,4.06,4.15,4.24] {cylinder(x,h,0.53,radius:0.20,height:0.025,color:steel,sides:8)}}
        }
        let x:Float=6.02
        for dx:Float in [-0.52,0.52] {for z:Float in [-0.43,0.43] {cylinder(x+dx,3.905,z,radius:0.105,height:0.18,color:white,sides:far ? 6:8)}}
        box(x,4.085,0,1.40,1.16,0.065,dark)
        // Lower arms stay separated; upper arm is a narrow central member, avoiding an A-frame in front view.
        let pivot=Map3DPoint(x-0.48,4.15,0),elbow=Map3DPoint(x+0.62,4.73,0),tip=Map3DPoint(x-0.63,5.35,0)
        for z:Float in [-0.32,0.32] {
            beam(pivot+Map3DPoint(0,0,z),elbow+Map3DPoint(0,0,z*0.65),0.060,steel)
        }
        beam(elbow,tip,0.070,steel)
        beam(elbow+Map3DPoint(0,0,-0.22),elbow+Map3DPoint(0,0,0.22),0.065,steel)
        beam(pivot+Map3DPoint(0.13,0.02,0),elbow+Map3DPoint(-0.23,0.04,0),0.025,dark)
        beam(tip+Map3DPoint(0,0,-0.68),tip+Map3DPoint(0,0,0.68),0.055,dark)
        for side:Float in [-1,1] {beam(tip+Map3DPoint(0,0,side*0.68),tip+Map3DPoint(0,-0.14,side*0.86),0.040,steel)}
    }
}
