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
        let low: [Float] = fleet == .haifeng ? [225,244,232] : [242,246,213]
        let high: [Float] = fleet == .haifeng ? [160,224,211] : [220,233,136]
        let channels=(0..<3).map { UInt32((low[$0]*(1-t)+high[$0]*t).rounded()) }
        return 0xff000000 | channels[0] | channels[1]<<8 | channels[2]<<16
    }
}

extension StationKitBuilder {
    /// Clip each rounded cap to the original cab triangles. Both glass and
    /// backing then follow the SAME surface planes: a fan chord through a
    /// curved cap must not intersect the adjacent pane or seal.
    mutating func tourismCabPanel(_ y: Float,_ z: Float,_ w: Float,_ h: Float,_ offset: Float,_ depth: Float,_ color: UInt32,far _: Bool) {
        let outline=Self.e500Round(w,h,min(0.14,min(w,h)*0.22)).map { Map3DPoint(0,y+$0.1,z+$0.0) }
        func cross(_ a:Map3DPoint,_ b:Map3DPoint,_ p:Map3DPoint)->Float { (b.y-a.y)*(p.z-a.z)-(b.z-a.z)*(p.y-a.y) }
        func snap(_ p:Map3DPoint)->Map3DPoint { Map3DPoint(0,(p.y*1e5).rounded()/1e5,(p.z*1e5).rounded()/1e5) }
        func layer(_ p:Map3DPoint,_ d:Float)->Map3DPoint { Map3DPoint(Self.e500CabX(p.y,p.z)+d,p.y,p.z) }
        let grid=Self.e500CabGrid()
        var boundary=outline.map(snap)
        for row in 0..<(grid.count-1) { for col in 0..<(grid[0].count-1) {
            let a=grid[row][col],b=grid[row][col+1],c=grid[row+1][col+1],d=grid[row+1][col]
            for tri in [[a,b,c],[a,c,d]] {
                var polygon=outline
                let sign:Float=cross(tri[0],tri[1],tri[2])>=0 ? 1:-1
                for edge in 0..<3 {
                    guard !polygon.isEmpty else { break }
                    let p=tri[edge],q=tri[(edge+1)%3]
                    var clipped:[Map3DPoint]=[]
                    for i in polygon.indices {
                        let u=polygon[i],v=polygon[(i+1)%polygon.count]
                        let du=sign*cross(p,q,u),dv=sign*cross(p,q,v)
                        if du>=0 { clipped.append(u) }
                        if (du>=0) != (dv>=0) { clipped.append(u+(v-u)*(du/(du-dv))) }
                    }
                    polygon=clipped
                }
                var clean:[Map3DPoint]=[]
                for p in polygon.map(snap) where clean.last != p { clean.append(p) }
                if clean.count>1 && clean.first == clean.last { clean.removeLast() }
                guard clean.count>=3,abs(cross(clean[0],clean[1],clean[2]))>1e-8 else { continue }
                boundary += clean
                let back=clean.map{layer($0,offset)},front=clean.map{layer($0,offset+depth)}
                let centre=(back+front).reduce(Map3DPoint.zero){$0+$1*(1/Float(back.count+front.count))}
                face(back,inside:centre,color:color);face(front,inside:centre,color:color)
            }
        } }
        for i in outline.indices {
            let p=snap(outline[i]),q=snap(outline[(i+1)%outline.count]),v=q-p
            let length=v.y*v.y+v.z*v.z
            let edge=boundary.filter { a in
                abs(cross(p,q,a))<1e-5 && (a-p).dot(v) >= -1e-6 && (a-q).dot(v)<=1e-6
            }
            let points=Set(edge).sorted { ($0-p).dot(v)/length < ($1-p).dot(v)/length }
            for j in 0..<(points.count-1) {
                let a=points[j],b=points[j+1]
                let centre=Map3DPoint(Self.e500CabX(y+h/2,z)+offset+depth/2,y+h/2,z)
                face([layer(a,offset),layer(b,offset),layer(b,offset+depth),layer(a,offset+depth)],inside:centre,color:color)
            }
        }
    }

    /// Paint on the actual shell vertices, interpolated by the native renderer
    /// and GLB. This avoids faceted colour wedges without another surface.
    mutating func tourismPaintFace(_ points: [Map3DPoint], inside: Map3DPoint, fleet: Map3DTourismEMU500.Fleet) {
        let cross=(points[1]-points[0]).cross(points[2]-points[0])
        let centre=points.reduce(Map3DPoint.zero){$0+$1*(1/Float(points.count))}
        let p=cross.dot(centre-inside)>=0 ? points : Array(points.reversed())
        guard let normal=(p[1]-p[0]).cross(p[2]-p[0]).normalized else { return }
        for i in 1..<(p.count-1) {
            mesh.appendTriangle([p[0],p[i],p[i+1]].map {
                Map3DVertex($0,normal:normal,color:Map3DTourismEMU500.paint(fleet,$0.y))
            })
        }
    }

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
                tourismPaintFace([Map3DPoint(x,2.2,0),Map3DPoint(x,p.0,p.1),Map3DPoint(x,q.0,q.1)],inside:Map3DPoint(0,2.2,0),fleet:fleet)
            }
        }
        for i in section.indices {
            let p=section[i],q=section[(i+1)%section.count]
            let panel=[Map3DPoint(a,p.0,p.1),Map3DPoint(b,p.0,p.1),Map3DPoint(b,q.0,q.1),Map3DPoint(a,q.0,q.1)]
            if min(p.0,q.0)>=3.55 { face(panel,inside:Map3DPoint(0,2.2,0),color:Map3DEMU500.roofColor) }
            else { tourismPaintFace(panel,inside:Map3DPoint(0,2.2,0),fleet:fleet) }
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
                            tourismPaintFace(piece,inside:c-Map3DPoint(0.1,0,0),fleet:fleet)
                            tourismPaintFace(piece.map{Map3DPoint(b,$0.y,$0.z)},inside:Map3DPoint(9.62,c.y,c.z),fleet:fleet)
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
                    tourismPaintFace([Map3DPoint(b,pp.y,pp.z),Map3DPoint(b,qq.y,qq.z),qq,pp],inside:Map3DPoint(9.7,2.2,0),fleet:fleet)
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
            if end<0 || !cab {
                box(end*10.03,0.70,0,0.27,0.36,0.25,dark)
                box(end*9.99,1.25,0,0.10,1.04,1.95,dark)
            }
        }
        if cab {
            // Conversion closes the old walk-through portal: there is no old
            // door / raised portal / white plaque behind this three-window face.
            let apron:UInt32=0xff3b3936, hardware:UInt32=0xff858784, hose:UInt32=0xff292b29
            tourismCabPanel(2.05,0,0.61,1.12,0.004,0.014,frame,far:far)
            tourismCabPanel(2.08,0,0.55,1.06,0.020,0.012,glass,far:far)
            for side:Float in [-1,1] {
                tourismCabPanel(2.08,side*0.94,0.75,1.15,0.003,0.015,frame,far:far)
                tourismCabPanel(2.11,side*0.94,0.69,1.09,0.020,0.012,glass,far:far)
                if !far {
                    let y:Float=2.2,z=side*0.94
                    beam(Map3DPoint(Self.e500CabX(y,z)+0.040,y,z),Map3DPoint(Self.e500CabX(2.86,z+side*0.05)+0.040,2.86,z+side*0.05),0.014,frame)
                }
                // Raised shared pod and separate metal bezels, all seated on
                // the final cab surface. Lens sizes remain readable at far LOD.
                e500CabPanel(1.365,side*0.93,0.69,0.37,0.006,0.055,paint(1.9))
                for z:Float in [side*1.09,side*0.78] {
                    let rr:Float=0.137
                    let points=(0..<(far ? 8:12)).map { i -> Map3DPoint in
                        let angle=Float(i)*2*Float.pi/Float(far ? 8:12)
                        let y:Float=1.55+rr*sinf(angle),zz=z+rr*cosf(angle)
                        return Map3DPoint(Self.e500CabX(y,zz)+0.061,y,zz)
                    }
                    e500Prism(points,points.map{$0+Map3DPoint(0.025,0,0)},hardware)
                    let lens=points.map { p -> Map3DPoint in
                        let y:Float=1.55+(p.y-1.55)*0.73,zz=z+(p.z-z)*0.73
                        return Map3DPoint(Self.e500CabX(y,zz)+0.087,y,zz)
                    }
                    e500Prism(lens,lens.map{$0+Map3DPoint(0.008,0,0)},abs(z)>0.9 ? hose:Map3DEMU500.lampColor)
                }
                // Thin tapered apron leaves an exposed coupler/pipe recess.
                let outline:[(Float,Float)]=[(0.28,0.91),(0.28,1.18),(0.37,1.30),(1.11,1.30),(1.11,0.69),(0.46,0.77)]
                let skirt=outline.map{Map3DPoint(9.81,$0.0,side*$0.1)}
                e500Prism(skirt,skirt.map{$0+Map3DPoint(0.07,0,0)},apron)
                // Only major visible hose paths; not a pneumatic reconstruction.
                box(9.94,1.12,side*0.91,0.11,0.10,0.12,hardware)
                let pipe=[Map3DPoint(9.99,1.16,side*0.91),Map3DPoint(10.02,0.77,side*0.99),Map3DPoint(10.02,0.40,side*0.74),Map3DPoint(10.02,0.32,side*0.45),Map3DPoint(10.02,0.50,side*0.28)]
                for i in 0..<(pipe.count-1) { beam(pipe[i],pipe[i+1],far ? 0.055:0.045,hose) }
                beam(Map3DPoint(10.03,0.39,side*0.45),Map3DPoint(10.03,0.45,side*0.62),0.045,0xff4844a4)
                if !far { box(9.94,0.30,side*1.12,0.12,0.15,0.055,hardware) }
            }
            tourismCabPanel(3.325,0,0.69,0.31,0.002,0.025,paint(3.55),far:far)
            tourismCabPanel(3.345,0,0.65,0.27,0.028,0.044,paint(1.4),far:far)
            for z:Float in [-0.16,0.16] {
                let rim=(0..<(far ? 8:12)).map { i -> Map3DPoint in
                    let a=Float(i)*2*Float.pi/Float(far ? 8:12),y:Float=3.49+0.113*sinf(a),zz=z+0.113*cosf(a)
                    return Map3DPoint(Self.e500CabX(y,zz)+0.073,y,zz)
                }
                e500Prism(rim,rim.map{$0+Map3DPoint(0.021,0,0)},hardware)
                let p=(0..<(far ? 8:12)).map { i -> Map3DPoint in
                    let a=Float(i)*2*Float.pi/Float(far ? 8:12),y:Float=3.495+0.088*sinf(a),zz=z+0.088*cosf(a)
                    return Map3DPoint(Self.e500CabX(y,zz)+0.095,y,zz)
                }
                e500Prism(p,p.map{$0+Map3DPoint(0.010,0,0)},Map3DEMU500.lampColor)
            }
            // Recessed support, projecting drawbar and knuckle head. No flat
            // internal seal protrudes below the nose or fills the open recess.
            box(9.70,0.59,0,0.14,0.70,0.35,apron)
            box(9.94,0.67,0,0.30,0.23,0.18,hardware)
            e500Panel(x:10.115,y:0.56,z:0,w:0.42,h:0.34,depth:0.10,front:true,color:apron,radius:0.055)
            box(10.145,0.62,0.10,0.04,0.11,0.23,hardware)
            box(10.163,0.68,-0.045,0.004,0.11,0.12,hose)
        }
    }
}
