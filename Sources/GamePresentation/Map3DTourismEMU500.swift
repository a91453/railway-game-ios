import Foundation

/// EMU573 / EMU583 exterior studies, converted from the project's EMU500.
/// Native metres +X cab, +Y left, +Z up. Unmeasured locations are photo estimates.
public enum Map3DTourismEMU500 {
    public enum Fleet: String, CaseIterable, Sendable { case haifeng, shanlan }
    public typealias Unit = Map3DEMU500.Unit
    public static let order: [Unit] = [.emc, .ep, .et, .em]
    public static let centres: [Float] = [30.495,10.165,-10.165,-30.495]
    public static let rotations: [Float] = [0,0,0,.pi]
    public static func model(_ fleet: Fleet, _ unit: Unit, far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.tourismEMU500(fleet,unit,far:far)
        return .flat(named:"\(fleet.rawValue)-emu500-\(unit.rawValue)" + (far ? "-far" : ""),from:b.mesh)
    }
    public static func formation(_ fleet: Fleet, far: Bool = false) -> Map3DModelPack.Model {
        var b=StationKitBuilder()
        for i in order.indices { b.add(model(fleet,order[i],far:far),at:Map3DPoint(centres[i],0,0),angle:rotations[i]) }
        return .flat(named:"\(fleet.rawValue)-emu500-formation" + (far ? "-far" : ""),from:b.mesh)
    }
    /// Paint sampled by height, with the pale lower fog and broad upper sea/field.
    /// These are painted derivatives, not the baseline's warm white/turquoise livery.
    static func paint(_ fleet: Fleet, _ height: Float, _ x: Float = 0) -> UInt32 {
        let t=max(0,min(1,(height-1.15)/2.3))
        let low: [Float] = fleet == .haifeng ? [211,232,222] : [232,237,188]
        let high: [Float] = fleet == .haifeng ? [129,200,191] : [196,211,104]
        let channels=(0..<3).map { UInt32((low[$0]*(1-t)+high[$0]*t).rounded()) }
        return 0xff000000 | channels[0] | channels[1]<<8 | channels[2]<<16
    }
}

extension StationKitBuilder {
    mutating func tourismEMU500(_ fleet: Map3DTourismEMU500.Fleet,_ unit: Map3DEMU500.Unit,far: Bool) {
        let cab=unit == .emc || unit == .em
        let silver=Map3DEMU500.silver, glass=Map3DEMU500.glass, dark=Map3DEMU500.maskColor
        let frame=Map3DEMU500.rubberColor
        func paint(_ y: Float)->UInt32 { Map3DTourismEMU500.paint(fleet,y) }
        // Baseline cross-section and shallow cab cap are retained. Split the REAL
        // side shell at colour heights; no second shell or floating paint overlay.
        var section:[(Float,Float)]=[]
        let original=Self.e500Section
        for i in original.indices {
            let p=original[i],q=original[(i+1)%original.count]
            var stops:[Float]=[0]
            if abs(q.0-p.0)>0.01 { for y:Float in [1.35,1.6,1.85,2.1,2.35,2.6,2.85,3.1] {
                let t=(y-p.0)/(q.0-p.0);if t>0 && t<1 { stops.append(t) }
            } }
            for t in stops.sorted() { section.append((p.0+(q.0-p.0)*t,p.1+(q.1-p.1)*t)) }
        }
        let a:Float = -9.94, b:Float = cab ? 9.52 : 9.94
        for x in [a,b] {
            for i in section.indices { let p=section[i],q=section[(i+1)%section.count]
                face([Map3DPoint(x,2.2,0),Map3DPoint(x,p.0,p.1),Map3DPoint(x,q.0,q.1)],inside:Map3DPoint(0,2.2,0),color:paint(2.3))
            }
        }
        for i in section.indices {
            let p=section[i],q=section[(i+1)%section.count]
            face([Map3DPoint(a,p.0,p.1),Map3DPoint(b,p.0,p.1),Map3DPoint(b,q.0,q.1),Map3DPoint(a,q.0,q.1)],inside:Map3DPoint(0,2.2,0),color:min(p.0,q.0)>=3.55 ? Map3DEMU500.roofColor:paint((p.0+q.0)/2))
        }
        if cab {
            let grid=Self.e500CabGrid()
            for row in 0..<(grid.count-1) { for col in 0..<(grid[0].count-1) {
                let p=grid[row][col],q=grid[row][col+1],r=grid[row+1][col+1],s=grid[row+1][col]
                for tri in [[p,q,r],[p,r,s]] {
                    // Subdivide the original plane without altering its surface.
                    // The coarse baseline grid otherwise paints giant wedges.
                    let count=far ? 2:4
                    func point(_ u:Int,_ v:Int)->Map3DPoint {
                        let f=Float(u)/Float(count),g=Float(v)/Float(count)
                        return tri[0]*(1-f-g)+tri[1]*f+tri[2]*g
                    }
                    for u in 0..<count { for v in 0..<(count-u) {
                        var pieces=[[point(u,v),point(u+1,v),point(u,v+1)]]
                        if u+v<count-1 { pieces.append([point(u+1,v),point(u+1,v+1),point(u,v+1)]) }
                        for piece in pieces {
                            let c=piece.reduce(Map3DPoint.zero){$0+$1*(1/3)}
                            let color=Map3DTourismEMU500.paint(fleet,c.y-abs(c.z)*0.3)
                            face(piece,inside:c-Map3DPoint(0.1,0,0),color:color)
                            face(piece.map{Map3DPoint(b,$0.y,$0.z)},inside:Map3DPoint(9.62,c.y,c.z),color:color)
                        }
                    } }

                }
            } }
            var border=grid[0];border += grid.dropFirst().map{$0.last!};border += grid.last!.dropLast().reversed();border += grid.dropFirst().dropLast().reversed().map{$0[0]}
            for i in border.indices {
                let p=border[i],q=border[(i+1)%border.count],count=far ? 2:4
                for j in 0..<count {
                    let pp=p*(1-Float(j)/Float(count))+q*(Float(j)/Float(count))
                    let qq=p*(1-Float(j+1)/Float(count))+q*(Float(j+1)/Float(count))
                    face([Map3DPoint(b,pp.y,pp.z),Map3DPoint(b,qq.y,qq.z),qq,pp],inside:Map3DPoint(9.7,2.2,0),color:paint((pp.y+qq.y)/2))
                }
            }

        }
        box(0,0.96,0,19.6,2.53,0.16,dark)
        func panel(_ x:Float,_ y:Float,_ z:Float,_ w:Float,_ h:Float,_ color:UInt32,_ depth:Float = 0.012) {
            // Same rounded prism primitive at both LODs: keep window rhythm.
            if far { box(x,y,z,w,depth,h,color) } else { e500Panel(x:x,y:y,z:z,w:w,h:h,depth:depth,front:false,color:color,radius:0.12) }
        }
        for side:Float in [-1,1] {
            // Two retained entrance pairs; the middle pair is removed entirely.
            for x:Float in [-5.9,5.9] {
                if !far { panel(x,1.17,side*1.437,1.30,1.94,Map3DEMU500.frameColor,0.020) }
                for dx:Float in [-0.323,0.323] {
                    panel(x+dx,1.20,side*1.451,0.625,1.88,paint(2.15),0.016)
                    panel(x+dx,1.45,side*1.465,0.43,1.46,glass,0.012)
                }
            }
            // Photo-based large fixed windows and floor-reaching former centre
            // doorway. Kitchen / accessible roles are separately laid out.
            let windows:[(Float,Float,Float,Float)]
            if unit == .ep {
                windows = side < 0 ? [(-8,0.62,2.48,0.40),(-3.8,1.22,2.25,0.76),(-1.9,1.22,2.25,0.76),(0,1.22,2.25,0.76),(1.9,1.22,2.25,0.76),(3.8,1.22,2.25,0.76),(8,1.22,2.25,0.76)] : [(-8,0.62,2.48,0.4),(8,1.22,2.25,0.76)]
            } else {
                windows=[(-8,unit == .et ? 0.62 : 1.22,2.25,0.76),(-3.9,1.3,2.25,0.76),(-1.95,1.3,2.25,0.76),(0,1.3,1.25,1.76),(1.95,1.3,2.25,0.76),(3.9,1.3,2.25,0.76),(8,1.22,2.25,0.76)]
            }
            for (x,w,y,h) in windows {
                panel(x,y,side*1.437,w+0.05,h+0.05,frame,0.018)
                panel(x,y+0.025,side*1.452,w,h,glass,0.012)
            }
            if cab { panel(9.05,2.4,side*1.437,0.60,0.65,glass,0.020) }
            if !far {
                // Retained stainless flutes, painted as part of the conversion.
                for y:Float in [1.32,1.49,1.66,1.83] {
                    // No flute crosses a floor-reaching window or an entrance.
                    for (x,w): (Float,Float) in [(-8,3.6),(-3.2,3.9),(3.2,3.9),(8,3.6)] {
                        box(x,y,side*1.429,w,0.006,0.012,paint(y))
                    }
                }
                if unit == .ep && side>0 {
                    for x:Float in [-3.5,0,3.5] { box(x,2.72,side*1.438,1.15,0.014,0.10,dark) }
                }
            }
        }
        // Two separate two-axle bogies; 860 mm tyres at native rail Z=0.
        for bx: Float in [-6.65,6.65] {
            box(bx,0.57,0,3.25,1.65,0.18,Map3DTrainStyle.under)
            for side: Float in [-1,1] {
                box(bx,0.56,side*0.84,3.2,0.14,0.18,Map3DTrainStyle.under)
            }
            box(bx,0.75,0,1.15,1.65,0.21,dark)
            for ax: Float in [-1.4,1.4] {
                if !far { beam(Map3DPoint(bx+ax,0.43,-0.72),Map3DPoint(bx+ax,0.43,0.72),0.13,dark) }
                for side: Float in [-1,1] {
                    let z=side*0.615,tyre=far ? 8 : 12
                    func circle(_ zz: Float)->[Map3DPoint] { (0..<tyre).map { i in let a=Float(i)*2*Float.pi/Float(tyre);return Map3DPoint(bx+ax+0.43*cosf(a),0.43+0.43*sinf(a),zz) } }
                    e500Prism(circle(z-0.09),circle(z+0.09),Map3DEMU500.maskColor)
                    func hub(_ zz: Float)->[Map3DPoint] { (0..<8).map { i in let a=Float(i)*2*Float.pi/8;return Map3DPoint(bx+ax+0.18*cosf(a),0.43+0.18*sinf(a),zz) } }
                    if !far { e500Prism(hub(side*0.705),hub(side*0.735),Map3DEMU500.frameColor) }
                }
            }
        }
        for (i,x) in [Float(-3.8),-1.4,1.5,3.8].enumerated() {
            box(x,0.56,unit == .ep ? 0.15 : -0.12,1.8,1.8,i % 2 == 0 ? 0.40 : 0.33,dark)
            if !far { box(x,0.87,0,0.30,1.65,0.09,dark) }
        }
        // Roof AC housings seated on real roof, with shallow matte grille panels.
        for x: Float in [-7.8,7.8] {
            box(x,3.65,0,2.60,1.75,0.064,silver)
            let section:[(Float,Float)]=[(3.714,-0.79),(3.88,-0.79),(3.964,-0.60),(3.964,0.60),(3.88,0.79),(3.714,0.79)]
            func end(_ xx: Float)->[Map3DPoint] { section.map { Map3DPoint(xx,$0.0,$0.1) } }
            e500Prism(end(x-1.175),end(x+1.175),Map3DEMU500.roofColor)
            if !far { for side: Float in [-1,1] {
                for dx: Float in [-0.58,0.15] { box(x+dx,3.75,side*0.794,0.64,0.012,0.10,Map3DEMU500.frameColor) }
            } }
            box(x,3.964,0,1.86,1.05,0.006,Map3DEMU500.roofColor)
        }
        if unit == .ep {
            box(-5.3,3.65,0,1.9,1.6,0.10,dark)
            for z: Float in [-0.5,0.5] {
                if !far { cylinder(-5.3,3.75,z,radius:0.10,height:0.18,color:silver,sides:8) }
                beam(Map3DPoint(-5.8,3.93,z),Map3DPoint(-4.5,4.48,z),0.065,dark)
                beam(Map3DPoint(-4.5,4.48,z),Map3DPoint(-5.6,4.95,z),0.055,dark)
            }
            box(-5.6,4.95,0,0.10,1.75,0.05,dark)
        }
        // Supported intermediate gangways and couplers, as baseline.
        for end:Float in [-1,1] {
            box(end*10.03,0.70,0,0.27,0.36,0.25,dark)
            if end<0 || !cab { box(end*9.99,1.25,0,0.10,1.04,1.95,dark) }
        }
        if cab {
            // Conversion closes the old walk-through portal: there is no old
            // door / raised portal / white plaque behind this three-window face.
            e500CabPanel(2.05,0,0.51,1.03,0.004,0.014,frame)
            e500CabPanel(2.08,0,0.46,0.97,0.020,0.012,glass)
            for side:Float in [-1,1] {
                e500CabPanel(2.08,side*0.97,0.72,1.12,0.003,0.015,frame)
                e500CabPanel(2.11,side*0.97,0.66,1.06,0.020,0.012,glass)
                if !far {
                    let y:Float=2.2,z=side*0.97
                    beam(Map3DPoint(Self.e500CabX(y,z)+0.040,y,z),Map3DPoint(Self.e500CabX(2.86,z+side*0.05)+0.040,2.86,z+side*0.05),0.014,frame)
                }
                // Original paired lower lights, round body-coloured pods.
                for z:Float in [side*1.055,side*0.765] {
                    let rr:Float=abs(z)>0.9 ? 0.17 : 0.125
                    let points=(0..<(far ? 8:12)).map { i -> Map3DPoint in
                        let angle=Float(i)*2*Float.pi/Float(far ? 8:12)
                        let y:Float=1.55+rr*sinf(angle),zz=z+rr*cosf(angle)
                        return Map3DPoint(Self.e500CabX(y,zz)+0.008,y,zz)
                    }
                    e500Prism(points,points.map{$0+Map3DPoint(0.034,0,0)},paint(1.6))
                    let lens=points.map { p -> Map3DPoint in
                        let y:Float=1.55+(p.y-1.55)*0.60,zz=z+(p.z-z)*0.60
                        return Map3DPoint(Self.e500CabX(y,zz)+0.044,y,zz)
                    }
                    e500Prism(lens,lens.map{$0+Map3DPoint(0.008,0,0)},abs(z)>0.9 ? frame:Map3DEMU500.lampColor)
                }
                // Plain black apron: baseline yellow hazard stripes removed.
                let outline:[(Float,Float)]=[(0.22,0.655),(0.22,1.265),(0.28,1.325),(1.11,1.325),(1.11,0.595),(0.28,0.595)]
                let skirt=outline.map{Map3DPoint(9.81,$0.0,side*$0.1)}
                e500Prism(skirt,skirt.map{$0+Map3DPoint(0.14,0,0)},frame)
            }
            e500CabPanel(3.37,0,0.63,0.25,0.002,0.050,paint(3.5))
            for z:Float in [-0.16,0.16] {
                let p=(0..<(far ? 8:12)).map { i -> Map3DPoint in
                    let a=Float(i)*2*Float.pi/Float(far ? 8:12),y:Float=3.495+0.088*sinf(a),zz=z+0.088*cosf(a)
                    return Map3DPoint(Self.e500CabX(y,zz)+0.054,y,zz)
                }
                e500Prism(p,p.map{$0+Map3DPoint(0.010,0,0)},Map3DEMU500.lampColor)
            }
            box(9.74,0.29,0,0.12,1.20,0.76,dark)
            box(10.08,0.72,0,0.17,0.34,0.23,frame)
        }
    }
}
