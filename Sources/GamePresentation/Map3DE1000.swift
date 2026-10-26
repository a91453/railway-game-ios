import Foundation

/// E1000 single-cab power car. Official overall dimensions and photo-estimated
/// stations are distinguished in docs/art/e1000-pp-2026-10-26.
public enum Map3DE1000 {
    public static let couplingHalfLength: Float = 8.6055
    public static let bodyHalfLength: Float = 8.25
    public static let glassColor = Map3DE500.glassColor
    public static func model(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.e1000PowerCar(far: far)
        return .flat(named: far ? "e1000-far" : "e1000", from: b.mesh)
    }
}

extension StationKitBuilder {
    private func pp1000Nose(_ h: Float) -> Float {
        let hs: [Float] = [1.15,1.55,1.75,2.00,2.65,3.12,3.40,3.65,3.82,3.904]
        let xs: [Float] = [8.25,8.25,8.20,8.03,7.35,6.74,6.34,5.94,5.61,5.40]
        for i in 0..<hs.count-1 where h <= hs[i+1] {
            return xs[i]+(xs[i+1]-xs[i])*(h-hs[i])/(hs[i+1]-hs[i])
        }
        return xs.last!
    }
    private mutating func pp1000Panel(_ p: [Map3DPoint], offset: Map3DPoint, color: UInt32) {
        let q=p.map{$0+offset},c=(p+q).reduce(.zero,+)*(1/Float(p.count*2))
        face(p,inside:c,color:color);face(q,inside:c,color:color)
        for i in p.indices {let j=(i+1)%p.count;face([p[i],p[j],q[j],q[i]],inside:c,color:color)}
    }
    fileprivate mutating func e1000PowerCar(far: Bool) {
        let white=Map3DPalette.shopAwnings[3],teal=Map3DE500.bodyColor
        let dark=Self.ink,steel=Self.steel,glass=Map3DE1000.glassColor,tire=Map3DStreetModel.tyre
        let hs: [Float]=[1.15,1.55,1.62,1.67,1.75,2.00,2.25,2.65,3.12,3.40,3.65,3.82,3.904]
        let ws: [Float]=[1.30,1.4425,1.4425,1.4425,1.4425,1.4425,1.4425,1.4425,1.4425,1.4425,1.32,1.03,0.65]
        func ring(_ h: Float,_ w: Float)->[Map3DPoint] {
            var p:[Map3DPoint]=[]
            for end:Float in [-1,1] {for side:Float in [-1,1] {
                let f=end>0 ? pp1000Nose(h):Float(8.25),dx:Float=end>0 ? 0.43:0.08,r:Float=end>0 ? 0.22:0.08,n=far ? 2:4
                for j in 0...n {
                    let t=Float(end*side<0 ? n-j:j)*Float.pi/(2*Float(n))
                    p.append(Map3DPoint(end*(f-dx+dx*sinf(t)),h,side*(w-r+r*cosf(t))))
                }
            }}
            return p.sorted{atan2f($0.z,$0.x)<atan2f($1.z,$1.x)}
        }
        for k in 0..<hs.count-1 {
            let lo=ring(hs[k],ws[k]),hi=ring(hs[k+1],ws[k+1])
            for i in lo.indices {
                let j=(i+1)%lo.count,c=(lo[i]+lo[j])*0.5
                let nose=c.x>pp1000Nose((hs[k]+hs[k+1])/2)-0.45
                let color:UInt32 = k==2 ? dark : (hs[k]>=1.75 && hs[k+1]<=3.12 && (!nose || hs[k+1]<=2.25)) ? teal:white
                face([lo[i],lo[j],hi[j],hi[i]],inside:Map3DPoint(0,2.4,0),color:color)
            }
            if k==0 {face(lo,inside:Map3DPoint(0,2.4,0),color:dark)}
            if k==hs.count-2 {face(hi,inside:Map3DPoint(0,2.4,0),color:white)}
        }
        box(0,1.05,0,16.25,2.50,0.10,dark)
        // Round each screen in frontal physical coordinates, then clip at the
        // actual nose's height bends before mapping onto its surface.
        func rounded(_ raw:[(Float,Float)])->[(Float,Float)] {
            var out:[(Float,Float)]=[]
            for i in raw.indices {
                let a=raw[(i+raw.count-1)%raw.count],b=raw[i],c=raw[(i+1)%raw.count],f:Float=0.12
                let u=(b.0+(a.0-b.0)*f,b.1+(a.1-b.1)*f),v=(b.0+(c.0-b.0)*f,b.1+(c.1-b.1)*f)
                for j in 0...(far ? 2:4) {let t=Float(j)/Float(far ? 2:4),q=1-t;out.append((q*q*u.0+2*q*t*b.0+t*t*v.0,q*q*u.1+2*q*t*b.1+t*t*v.1))}
            }
            return out
        }
        func clipped(_ input:[(Float,Float)],_ h:Float,_ above:Bool)->[(Float,Float)] {
            var out:[(Float,Float)]=[]
            for i in input.indices {let a=input[i],b=input[(i+1)%input.count],ia=above ? a.1>=h:a.1<=h,ib=above ? b.1>=h:b.1<=h
                if ia {out.append(a)}
                if ia != ib {let t=(h-a.1)/(b.1-a.1);out.append((a.0+(b.0-a.0)*t,h))}
            }
            return out
        }
        for side:Float in [-1,1] {
            for (proud,color,trim) in [(Float(0.012),dark,Float(0.045)),(Float(0.027),glass,Float(0))] {
                let outline=rounded([(0.10-trim,2.65-trim),(1.12+trim,2.65-trim),(1.105+trim,3.40+trim),(0.10-trim,3.40+trim)])
                let cuts:[Float]=[2.65-trim,2.65,3.12,3.40,3.40+trim]
                for i in 0..<cuts.count-1 where cuts[i+1]-cuts[i]>0.00001 {
                    let piece=clipped(clipped(outline,cuts[i],true),cuts[i+1],false)
                    if piece.count>=3 {pp1000Panel(piece.map{Map3DPoint(pp1000Nose($0.1)+proud,$0.1,side*$0.0)},offset:Map3DPoint(0.009,0,0),color:color)}
                }
            }
            let p:[Map3DPoint]=[Map3DPoint(5.65,2.18,side*1.444),Map3DPoint(7.30,2.18,side*1.444),Map3DPoint(6.00,3.30,side*1.444),Map3DPoint(5.65,3.30,side*1.444)]
            pp1000Panel(p,offset:Map3DPoint(0,0,side*0.012),color:dark)
            let pane:[Map3DPoint]=[Map3DPoint(5.71,2.25,side*1.457),Map3DPoint(7.16,2.25,side*1.457),Map3DPoint(6.04,3.23,side*1.457),Map3DPoint(5.71,3.23,side*1.457)]
            pp1000Panel(pane,offset:Map3DPoint(0,0,side*0.012),color:glass)
            box(5.17,1.24,side*1.444,0.61,0.012,2.08,dark)
            box(5.17,1.27,side*1.457,0.55,0.012,2.02,white)
            box(5.17,2.59,side*1.470,0.29,0.010,0.64,glass)
            box(5.17,1.10,side*1.49,0.65,0.20,0.08,steel)
            // Only the two narrow visible intake locations, no fictional side grille row.
            for x:Float in [-5.8,3.65] {
                box(x,2.64,side*1.444,0.49,0.012,0.94,dark)
                if !far {for j in 0..<7 {box(x,2.72+Float(j)*0.11,side*1.46,0.43,0.014,0.025,steel)}}
            }
            if !far {
                for h:Float in [0.90,0.70] {box(5.17,h,side*1.49,0.55,0.20,0.055,steel)}
                for x:Float in [4.91,5.43] {beam(Map3DPoint(x,0.7,side*1.49),Map3DPoint(x,1.24,side*1.43),0.035,steel)}
                for x:Float in [-6.7,-5.8,-4.9] {box(x,1.83,side*1.444,0.7,0.015,0.40,white)}
            }
        }
        // Frontal light pairs and a central upper lamp; no red material or brand.
        for z:Float in [-0.79,0.79] {
            box(8.12,1.72,z,0.12,0.56,0.28,dark)
            for dz:Float in [-0.13,0.13] {
                let start=mesh.vertices.count
                civicTube(Map3DPoint(8.18,1.86,z+dz),Map3DPoint(8.23,1.86,z+dz),radius:0.085,color:white,sides:far ? 8:12)
                mesh.makeGlowing(from:start)
            }
        }
        for (width,height,proud,color) in [(Float(0.49),Float(0.19),Float(0.012),dark),(Float(0.37),Float(0.12),Float(0.027),white)] {
            let p=(0..<16).map{j -> Map3DPoint in let t=Float(j)*Float.pi/8,h:Float=3.56+sinf(t)*height/2;return Map3DPoint(pp1000Nose(h)+proud,h,cosf(t)*width/2)}
            pp1000Panel(p,offset:Map3DPoint(0.01,0,0),color:color)
        }
        // Couplers and rear gangway: the rear is a real passenger passage, unlike E500.
        for end:Float in [-1,1] {
            box(end*8.12,0.98,0,0.32,2.20,0.17,dark)
            box(end*8.36,0.78,0,0.36,0.34,0.24,dark)
            box(end*(Map3DE1000.couplingHalfLength-0.05),0.78,0,0.10,0.44,0.24,steel)
        }
        pp1000Panel([Map3DPoint(8.21,1.15,-1.30),Map3DPoint(8.21,1.15,1.30),Map3DPoint(8.21,0.50,1.17),Map3DPoint(8.21,0.50,-1.17)],offset:Map3DPoint(0.06,0,0),color:white)
        box(8.21,0.35,0,0.15,2.25,0.22,steel)
        box(-8.27,1.23,0,0.04,1.05,2.05,dark)
        box(-8.30,1.28,0,0.025,0.80,1.93,white)
        box(-8.32,2.52,0,0.02,0.46,0.50,glass)
        for z:Float in [-0.60,0.60] {box(-8.46,1.20,z,0.27,0.12,2.15,dark)}
        box(-8.46,3.25,0,0.27,1.32,0.10,dark)
        box(-8.46,1.18,0,0.27,1.32,0.10,dark)
        // Bo'Bo' running gear: wheel diameter/axle stations are proportion estimates.
        for c:Float in [-4.9,4.9] {
            box(c,0.87,0,3.75,0.80,0.24,steel);box(c,1.00,0,1.30,1.85,0.15,dark)
            for dx:Float in [-1.25,1.25] {
                let x=c+dx
                civicTube(Map3DPoint(x,0.50,-0.70),Map3DPoint(x,0.50,0.70),radius:0.08,color:steel,sides:6)
                for side:Float in [-1,1] {
                    civicTube(Map3DPoint(x,0.50,side*0.50),Map3DPoint(x,0.50,side*0.68),radius:0.50,color:tire,sides:far ? 8:12)
                    civicTube(Map3DPoint(x,0.50,side*0.68),Map3DPoint(x,0.50,side*0.72),radius:0.30,color:steel,sides:far ? 8:12)
                    civicTube(Map3DPoint(x,0.50,side*0.72),Map3DPoint(x,0.50,side*1.10),radius:0.10,color:steel,sides:6)
                    box(x,0.41,side*1.10,0.44,0.20,0.27,dark)
                }
            }
            for side:Float in [-1,1] {
                box(c,0.66,side*1.10,3.65,0.20,0.21,steel)
                for dx:Float in [-0.67,0.67] {
                    cylinder(c+dx,0.75,side*1.10,radius:0.18,height:0.25,color:dark,sides:far ? 6:10)
                    box(c+dx,1.00,side*1.10,0.50,0.40,0.09,steel)
                    if !far {for y:Float in [0.79,0.86,0.93] {cylinder(c+dx,y,side*1.10,radius:0.20,height:0.025,color:steel,sides:10)}}
                }
            }
        }
        box(-0.1,0.62,0,5.5,1.75,0.38,steel)
        // Roof resistor housings, narrow installation feet and one single-arm collector.
        for (x,l) in [(Float(-1.9),Float(2.2)),(Float(1.1),Float(2.1))] {
            for z:Float in [-0.45,0.45] {box(x,3.904,z,l,0.15,0.06,dark)}
            box(x,3.964,0,l,1.65,0.27,steel)
            for z:Float in [-0.834,0.834] {
                box(x,4.00,z,l-0.12,0.016,0.17,dark)
                if !far {for j in 0..<9 {box(x-l/2+0.15+Float(j)*(l-0.30)/8,4.00,z*1.01,0.025,0.012,0.17,steel)}}
            }
        }
        for z:Float in [-0.40,0.40] {for x:Float in [-5.65,-4.75] {cylinder(x,3.904,z,radius:0.11,height:0.28,color:steel,sides:far ? 6:10)}}
        box(-5.20,4.184,0,1.30,1.12,0.07,dark)
        let a=Map3DPoint(-5.62,4.254,0),b=Map3DPoint(-4.42,4.76,0),c=Map3DPoint(-5.50,5.27,0)
        for z:Float in [-0.32,0.32] {beam(a+Map3DPoint(0,0,z),b+Map3DPoint(0,0,z*0.7),0.055,steel)}
        beam(b+Map3DPoint(0,0,-0.26),b+Map3DPoint(0,0,0.26),0.065,steel)
        beam(b,c,0.065,steel);beam(c+Map3DPoint(0,0,-0.65),c+Map3DPoint(0,0,0.65),0.055,dark)
        if !far {beam(a+Map3DPoint(0.12,0.02,0),b+Map3DPoint(-0.2,0.02,0),0.025,dark)}
    }
}
