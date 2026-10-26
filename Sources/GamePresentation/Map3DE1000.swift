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
        let hs: [Float] = [1.15,1.55,1.75,2.00,2.15,2.25,2.65,3.12,3.40,3.65,3.82,3.904]
        let xs: [Float] = [8.05,8.25,8.25,8.18,8.10,7.99,7.57,7.02,6.58,6.12,5.74,5.40]
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
    /// Bond each fitting to the actual faceted hull. Clip projected outlines
    /// at every triangle boundary; close only the outer perimeter of the patch.
    /// This adapts the project's accepted projection method, not its train shape.
    private mutating func pp1000Patch(_ shell:[[Map3DPoint]],_ outline:[Map3DPoint],
                                     axis:Int,sign:Float,offset:Float,color:UInt32) {
        func u(_ p:Map3DPoint)->Float {axis==0 ? p.z:p.x}
        let direction=axis==0 ? Map3DPoint(sign,0,0):Map3DPoint(0,0,sign)
        let area=outline.indices.reduce(Float(0)){sum,i in let j=(i+1)%outline.count;return sum+u(outline[i])*outline[j].y-u(outline[j])*outline[i].y}
        let orientation:Float=area>=0 ? 1:-1
        func clip(_ points:[Map3DPoint],_ a:Map3DPoint,_ b:Map3DPoint)->[Map3DPoint] {
            let du=u(b)-u(a),dv=b.y-a.y
            let values=points.map {p->Float in let f=orientation*(du*(p.y-a.y)-dv*(u(p)-u(a)));return abs(f)<0.0000001 ? 0:f}
            var result:[Map3DPoint]=[]
            for i in points.indices {
                let j=(i+1)%points.count,p=points[i],q=points[j],f=values[i],g=values[j]
                if f>=0 {result.append(p)}
                if f*g<0 {
                    let order=p.x != q.x ? p.x<q.x:p.y != q.y ? p.y<q.y:p.z<q.z
                    let a=order ? p:q,b=order ? q:p,fa=order ? f:g,fb=order ? g:f
                    result.append(a+(b-a)*(fa/(fa-fb)))
                }
            }
            return result
        }
        var vertices:[String:Map3DPoint]=[:],polygons:[[String]]=[],edges:[String:([String],Int)]=[:]
        func vertex(_ p:Map3DPoint)->String {
            let key="\(Int((p.x*100000).rounded())),\(Int((p.y*100000).rounded())),\(Int((p.z*100000).rounded()))"
            if vertices[key]==nil {vertices[key]=p};return key
        }
        for triangle in shell {
                let n=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])
                let centre=triangle.reduce(.zero,+)*(1/3)
                let component=axis==0 ? n.x:n.z
                guard component*sign>0.000001 && centre.x>5.3 else {continue}
                var polygon=triangle
                for k in outline.indices {
                    polygon=clip(polygon,outline[k],outline[(k+1)%outline.count]);if polygon.count<3 {break}
                }
                guard polygon.count>=3 else {continue}
                var ids:[String]=[]
                for point in polygon {let key=vertex(point);if ids.last != key {ids.append(key)}}
                if ids.first==ids.last {ids.removeLast()}
                guard ids.count>=3 else {continue}
                polygons.append(ids)
                for k in ids.indices {let edge=[ids[k],ids[(k+1)%ids.count]],key=edge.sorted().joined(separator:"|");edges[key]=(edge,(edges[key]?.1 ?? 0)+1)}
        }
        for ids in polygons {
            let p=ids.map {vertices[$0]!+direction*offset},q=ids.map {vertices[$0]!+direction*(offset-0.04)}
            let collinear=p.indices.contains {i in
                let a=p[(i+p.count-1)%p.count],b=p[i],c=p[(i+1)%p.count],n=(b-a).cross(c-b)
                return n.dot(n)<0.000000000001
            }
            if !collinear {mesh.addFacet(p,color:color);mesh.addFacet(Array(q.reversed()),color:color)}
            else {
                let a=p.reduce(.zero,+)*(1/Float(p.count)),b=q.reduce(.zero,+)*(1/Float(q.count))
                for i in p.indices {let j=(i+1)%p.count;mesh.addFacet([a,p[i],p[j]],color:color);mesh.addFacet([b,q[j],q[i]],color:color)}
            }
        }
        for key in edges.keys.sorted() {
            guard let edge=edges[key],edge.1==1 else {continue}
            let a=vertices[edge.0[0]]!,b=vertices[edge.0[1]]!,p=[a+direction*offset,b+direction*offset],q=[a+direction*(offset-0.04),b+direction*(offset-0.04)]
            mesh.addFacet([p[0],q[0],q[1],p[1]],color:color)
        }
    }
    fileprivate mutating func e1000PowerCar(far: Bool) {
        let white=Map3DPalette.shopAwnings[3],teal=Map3DE500.bodyColor
        let dark=Self.ink,steel=Self.steel,glass=Map3DE1000.glassColor,tire=Map3DStreetModel.tyre
        // Height rings independently constrain the side slope, frontal arch and
        // transverse nose curvature. Rear body and equipment retain their profile.
        let hs: [Float]=[1.15,1.55,1.62,1.67,1.75,2.00,2.15,2.25,2.65,3.12,3.40,3.65,3.82,3.904]
        let ws: [Float]=[1.30,1.4425,1.4425,1.4425,1.4425,1.4425,1.4425,1.4425,1.4425,1.4425,1.40,1.18,0.78,0.06]
        let cabWidths: [Float]=[1.19,1.40,1.425,1.435,1.4425,1.4425,1.44,1.43,1.40,1.35,1.23,0.99,0.65,0.06]
        let segments=far ? 6:10
        func ring(_ k:Int)->[Map3DPoint] {
            let h=hs[k],w=ws[k],cw=cabWidths[k],front=pp1000Nose(h)
            let depth:Float=h>3.65 ? 0.25:0.63
            var p:[Map3DPoint]=[]
            // Elliptical plan contour across almost the full nose width; the
            // previous narrow corner rounding left a large flat bus-like face.
            for j in 0...segments {
                let t = -Float.pi/2+Float(j)*Float.pi/Float(segments)
                let lateral=sinf(t),height:Float
                if h>=1.55 && h<=1.75 {height=h-0.13*(1-lateral*lateral)}
                else if h==2.00 {height=h-0.04*lateral*lateral}
                else if h==2.15 {height=h+0.07-0.16*lateral*lateral}
                else {height=h}
                p.append(Map3DPoint(front-depth+depth*cosf(t),height,cw*lateral))
            }
            p.append(Map3DPoint(4.90,h,w))
            p.append(Map3DPoint(-8.17,h,w))
            p.append(Map3DPoint(-8.25,h,w-0.08))
            p.append(Map3DPoint(-8.25,h,-w+0.08))
            p.append(Map3DPoint(-8.17,h,-w))
            p.append(Map3DPoint(4.90,h,-w))
            return p
        }
        for k in 0..<hs.count-1 {
            let lo=ring(k),hi=ring(k+1)
            for i in lo.indices {
                let j=(i+1)%lo.count
                let front=i<segments
                let color:UInt32 = k==2 ? dark : (hs[k]>=1.75 && hs[k+1]<=3.12 && (!front || hs[k+1]<=2.15)) ? teal:white
                face([lo[i],lo[j],hi[j],hi[i]],inside:Map3DPoint(0,2.4,0),color:color)
            }
            if k==0 {face(lo,inside:Map3DPoint(0,2.4,0),color:dark)}
            if k==hs.count-2 {face(hi,inside:Map3DPoint(0,2.4,0),color:white)}
        }
        let shell=stride(from:0,to:mesh.indices.count,by:3).map {i in mesh.indices[i..<i+3].map {mesh.vertices[Int($0)].position}}
        box(-0.34,1.05,0,15.57,2.50,0.10,dark)
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
        for side:Float in [-1,1] {
            for (proud,color,trim) in [(Float(0.012),dark,Float(0.04)),(Float(0.030),glass,Float(0))] {
                // Broader, lower trapezoids follow the actual receding cab face.
                let outline=rounded([(0.105-trim,2.76-trim),(1.185+trim,2.79-trim),(1.025+trim,3.34+trim),(0.15-trim,3.36+trim)])
                pp1000Patch(shell,outline.map{Map3DPoint(0,$0.1,side*$0.0)},axis:0,sign:1,offset:proud,color:color)
            }
            let frame=rounded([(5.68,2.55),(6.88,2.55),(6.20,3.22),(5.68,3.22)])
            let pane=rounded([(5.74,2.61),(6.74,2.61),(6.17,3.16),(5.74,3.16)])
            pp1000Patch(shell,frame.map{Map3DPoint($0.0,$0.1,0)},axis:2,sign:side,offset:0.012,color:dark)
            pp1000Patch(shell,pane.map{Map3DPoint($0.0,$0.1,0)},axis:2,sign:side,offset:0.030,color:glass)
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
        // Paired circular lamps in curved oval bezels, projected in physical
        // frontal coordinates rather than attached to a rectangular block.
        for lateral:Float in [-0.91,0.91] {
            let rim=(0..<16).map{j -> Map3DPoint in let t=Float(j)*Float.pi/8;return Map3DPoint(0,1.91+sinf(t)*0.13,lateral+cosf(t)*0.28)}
            pp1000Patch(shell,rim,axis:0,sign:1,offset:0.018,color:dark)
            for delta:Float in [-0.125,0.125] {
                let start=mesh.vertices.count
                let lens=(0..<(far ? 8:12)).map{j -> Map3DPoint in let t=Float(j)*2*Float.pi/Float(far ? 8:12);return Map3DPoint(0,1.91+sinf(t)*0.078,lateral+delta+cosf(t)*0.078)}
                pp1000Patch(shell,lens,axis:0,sign:1,offset:0.036,color:white)
                mesh.makeGlowing(from:start)
            }
        }
        for (width,height,proud,color) in [(Float(0.49),Float(0.19),Float(0.012),dark),(Float(0.37),Float(0.12),Float(0.030),white)] {
            let p=(0..<16).map{j -> Map3DPoint in let t=Float(j)*Float.pi/8;return Map3DPoint(0,3.54+sinf(t)*height/2,cosf(t)*width/2)}
            pp1000Patch(shell,p,axis:0,sign:1,offset:proud,color:color)
        }
        // Couplers and rear gangway: the rear is a real passenger passage, unlike E500.
        for end:Float in [-1,1] {
            if end<0 {box(end*8.12,0.98,0,0.32,2.20,0.17,dark)}
            else {box(7.98,0.98,0,0.65,0.42,0.17,dark)}
            box(end*8.36,0.78,0,0.36,0.34,0.24,dark)
            box(end*(Map3DE1000.couplingHalfLength-0.05),0.78,0,0.10,0.44,0.24,steel)
        }
        // Lower skirt is a tapered continuation of the oval nose, with a
        // shallow central coupler slot, not a flat rectangular bumper below it.
        var skirtLow:[Map3DPoint]=[],skirtHigh:[Map3DPoint]=[]
        for j in 0...segments {
            let t = -Float.pi/2+Float(j)*Float.pi/Float(segments)
            skirtLow.append(Map3DPoint(7.36+0.36*cosf(t),0.36+0.10*abs(sinf(t)),0.94*sinf(t)))
            skirtHigh.append(Map3DPoint(7.42+0.63*cosf(t),1.15,1.19*sinf(t)))
        }
        for j in 0..<segments {
            let a=skirtLow[j],b=skirtLow[j+1],c=skirtHigh[j+1],d=skirtHigh[j]
            pp1000Panel([a,b,c],offset:Map3DPoint(-0.08,0,0),color:white)
            pp1000Panel([a,c,d],offset:Map3DPoint(-0.08,0,0),color:white)
        }
        // Short supporting ribs behind the skirt remain visually subordinate.
        box(7.36,0.65,0,0.30,0.44,0.30,dark)
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
        // Keep the existing equipment, bridge its original feet onto the round crown.
        for (x,l) in [(Float(-1.9),Float(2.2)),(Float(1.1),Float(2.1))] {
            for z:Float in [-0.45,0.45] {box(x,3.80,z,l,0.15,0.104,dark)}
        }
        for z:Float in [-0.40,0.40] {for x:Float in [-5.65,-4.75] {box(x,3.82,z,0.18,0.18,0.084,steel)}}
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
