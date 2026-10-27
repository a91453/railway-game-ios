import Foundation

/// Independent EMU500 static reconstruction; no prior vehicle mesh is reused.
/// Builder X/front Y/up Z/right; Model.flat converts to native metres Z/up.
public enum Map3DEMU500 {
    public enum Unit: String, CaseIterable, Sendable { case emc, ep, et, em }
    public static let pitch: Float = 20.33
    public static let order: [Unit] = [.emc, .ep, .et, .em]
    public static let centres: [Float] = [30.495, 10.165, -10.165, -30.495]
    public static let rotations: [Float] = [0, 0, 0, .pi]
    public static let blue = Map3DColor.rgb(0x1D4F91)
    public static let silver = Map3DColor.rgb(0xC8D0D2)
    public static let glass = Map3DColor.rgb(0x263C40)
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var b = StationKitBuilder(); b.emu500(unit)
        return .flat(named: "emu500-\(unit.rawValue)", from: b.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for i in order.indices { b.add(model(order[i]), at: Map3DPoint(centres[i],0,0), angle: rotations[i]) }
        return .flat(named: "emu500-formation", from: b.mesh)
    }
}

extension StationKitBuilder {
    static let e500Section: [(Float,Float)] = [(1.12,-1.34),(1.18,-1.4265),(3.22,-1.4265),(3.40,-1.39),(3.55,-1.27),(3.63,-1.04),(3.65,-0.65),(3.65,0.65),(3.63,1.04),(3.55,1.27),(3.40,1.39),(3.22,1.4265),(1.18,1.4265),(1.12,1.34)]
    static func e500CabRim(_ y: Float, _ z: Float) -> Map3DPoint {
        Map3DPoint(9.99 - 0.18 * powf(abs(z)/1.4265,4) - 0.035 * max(0,(y-3.0)/0.65),y,z)
    }
    static func e500CabGrid() -> [[Map3DPoint]] {
        let levels:[(Float,Float)]=[(1.12,1.34),(1.18,1.4265),(3.22,1.4265),(3.40,1.39),(3.55,1.27),(3.63,1.04),(3.65,0.65)]
        let across:[Float]=[-1,-0.9,-0.7,-0.4,0,0.4,0.7,0.9,1]
        return levels.map { y,w in across.map { Self.e500CabRim(y,$0*w) } }
    }
    /// Exact barycentric interpolation of the actual longitudinal cab cap grid.
    static func e500CabX(_ y: Float, _ z: Float) -> Float {
        let grid=e500CabGrid()
        for row in 0..<(grid.count-1) {
            for col in 0..<(grid[0].count-1) {
                let a=grid[row][col],b=grid[row][col+1],c=grid[row+1][col+1],d=grid[row+1][col]
                for tri in [[a,b,c],[a,c,d]] {
                    let p=tri[0],q=tri[1],r=tri[2]
                    let ay=q.y-p.y,az=q.z-p.z,by=r.y-p.y,bz=r.z-p.z
                    let det=ay*bz-az*by
                    if abs(det)<0.000001 { continue }
                    let u=((y-p.y)*bz-(z-p.z)*by)/det
                    let v=(ay*(z-p.z)-az*(y-p.y))/det
                    if u >= -0.0001 && v >= -0.0001 && u+v <= 1.0001 {
                        return p.x*(1-u-v)+q.x*u+r.x*v
                    }
                }
            }
        }
        return 9.95
    }
    static func e500Round(_ w: Float,_ h: Float,_ radius: Float) -> [(Float,Float)] {
        let r=min(radius,min(w,h)*0.48)
        let corners:[(Float,Float,Float)]=[(w/2-r,r,-90),(w/2-r,h-r,0),(-w/2+r,h-r,90),(-w/2+r,r,180)]
        return corners.flatMap { x,y,angle in (0..<3).map { i in
            let a=(angle+Float(i)*45)*Float.pi/180
            return (x+r*cosf(a),y+r*sinf(a))
        } }
    }
    mutating func e500CabPanel(_ y: Float,_ z: Float,_ w: Float,_ h: Float,_ offset: Float,_ depth: Float,_ color: UInt32) {
        let p=Self.e500Round(w,h,min(0.14,min(w,h)*0.22))
        func layer(_ d: Float)->[Map3DPoint] { p.map { u,v in
            Map3DPoint(Self.e500CabX(y+v,z+u)+d,y+v,z+u)
        } }
        // Rounded perimeter vertices are placed relative to the actual shallow cap.
        // Visibility and backing are independently checked on the resulting triangles.
        e500Prism(layer(offset),layer(offset+depth),color)
    }
    /// A convex closed prism with outward winding on every face.
    mutating func e500Prism(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32) {
        let centre = (a+b).reduce(Map3DPoint.zero) { $0+$1*(1/Float(a.count+b.count)) }
        face(a,inside:centre,color:color); face(b,inside:centre,color:color)
        for i in a.indices { let j=(i+1)%a.count; face([a[i],a[j],b[j],b[i]],inside:centre,color:color) }
    }
    mutating func e500Panel(x: Float, y: Float, z: Float, w: Float, h: Float, depth: Float, front: Bool, color: UInt32, radius: Float? = nil) {
        let r=radius ?? min(0.13,min(w,h)*0.22)
        let octagon:[(Float,Float)]=[(-w/2+r,0),(w/2-r,0),(w/2,r),(w/2,h-r),(w/2-r,h),(-w/2+r,h),(-w/2,h-r),(-w/2,r)]
        let p=color == Map3DEMU500.glass && (w>0.6 || front) ? Self.e500Round(w,h,r) : octagon
        func layer(_ d: Float)->[Map3DPoint] { p.map { u,v in front ? Map3DPoint(x+d,y+v,z+u) : Map3DPoint(x+u,y+v,z+d) } }
        e500Prism(layer(-depth/2),layer(depth/2),color)
    }
    mutating func emu500(_ unit: Map3DEMU500.Unit) {
        let cab = unit == .emc || unit == .em
        let silver=Map3DEMU500.silver, blue=Map3DEMU500.blue, glass=Map3DEMU500.glass
        let dark=Map3DPalette.playerRim, white=Map3DPalette.tileWhite, yellow=Map3DColor.rgb(0xFFC86B)
        // Fresh cross-section: upright sides, rolled shoulders, broad shallow roof.
        let profile=Self.e500Section
        func ring(_ x: Float)->[Map3DPoint] { profile.map { Map3DPoint(x,$0.0,$0.1) } }
        e500Prism(ring(-9.94),ring(cab ? 9.52 : 9.94),silver)
        if cab {
            let grid=Self.e500CabGrid(),inside=Map3DPoint(9.7,2.20,0)
            for row in 0..<(grid.count-1) {
                for col in 0..<(grid[0].count-1) {
                    let a=grid[row][col],b=grid[row][col+1],c=grid[row+1][col+1],d=grid[row+1][col]
                    for tri in [[a,b,c],[a,c,d]] {
                        let local=tri.reduce(Map3DPoint.zero) { $0+$1*(1/3) }
                        face(tri,inside:local-Map3DPoint(0.1,0,0),color:blue)
                        let back=tri.map { Map3DPoint(9.52,$0.y,$0.z) }
                        face(back,inside:Map3DPoint(9.62,local.y,local.z),color:blue)
                    }
                }
            }
            var border=grid[0]
            border += grid.dropFirst().map { $0.last! }
            border += grid.last!.dropLast().reversed()
            border += grid.dropFirst().dropLast().reversed().map { $0[0] }
            for i in border.indices {
                let a=border[i],b=border[(i+1)%border.count]
                face([Map3DPoint(9.52,a.y,a.z),Map3DPoint(9.52,b.y,b.z),b,a],inside:inside,color:blue)
            }
        }
        box(0,0.96,0,19.6,2.53,0.16,dark)
        // Waist stripes sit on the vertical body; doors overlay them locally.
        for side: Float in [-1,1] {
            box(0,2.12,side*1.433,19.84,0.014,0.075,blue)
            box(0,2.205,side*1.433,19.84,0.014,0.045,white)
            box(0,3.22,side*1.426,19.5,0.016,0.05,blue)
            for y: Float in [1.32,1.49,1.66,1.83] { box(0,y,side*1.431,19.5,0.01,0.018,silver) }
            // Three pairs of flush passenger doors. All dimensions proportional estimates.
            for x: Float in [-5.9,0,5.9] {
                e500Panel(x:x,y:1.17,z:side*1.438,w:1.33,h:1.94,depth:0.024,front:false,color:dark)
                for dx: Float in [-0.323,0.323] {
                    box(x+dx,1.19,side*1.463,0.625,0.018,1.9,silver)
                    e500Panel(x:x+dx,y:2.30,z:side*1.480,w:0.43,h:0.65,depth:0.014,front:false,color:glass)
                }
            }
            let windows: [Float] = [-8.0,-3.95,-1.98,1.98,3.95,8.0]
            for (i,x) in windows.enumerated() {
                let small = (unit == .ep && i == 0) || (unit == .et && i == 5)
                let w: Float = small ? 0.62 : 1.22
                let y: Float = small ? 2.49 : 2.32
                e500Panel(x:x,y:y,z:side*1.438,w:w+0.07,h:small ? 0.43 : 0.77,depth:0.023,front:false,color:dark)
                e500Panel(x:x,y:y+0.035,z:side*1.454,w:w,h:small ? 0.36 : 0.70,depth:0.014,front:false,color:glass)
                if !small && i % 3 == 0 { box(x,y+0.53,side*1.476,w,0.012,0.025,silver) }
            }
            if cab {
                // Slanting blue cab-side boundary observed in the supplied views.
                let a=[Map3DPoint(8.30,3.20,side*1.4265),Map3DPoint(9.50,3.20,side*1.4265),Map3DPoint(9.50,1.18,side*1.4265),Map3DPoint(9.20,1.18,side*1.4265)]
                e500Prism(a,a.map { $0+Map3DPoint(0,0,side*0.009) },blue)
                e500Panel(x:9.05,y:2.40,z:side*1.435,w:0.60,h:0.65,depth:0.025,front:false,color:glass) }
        }
        // Two separate two-axle bogies; 860 mm tyres at native rail Z=0.
        for bx: Float in [-6.65,6.65] {
            box(bx,0.57,0,3.25,1.65,0.18,Map3DColor.rgb(0x4A5964))
            for side: Float in [-1,1] {
                box(bx,0.56,side*0.84,3.2,0.14,0.18,Map3DColor.rgb(0x4A5964))
            }
            box(bx,0.75,0,1.15,1.65,0.21,dark)
            for ax: Float in [-1.4,1.4] {
                beam(Map3DPoint(bx+ax,0.43,-0.72),Map3DPoint(bx+ax,0.43,0.72),0.13,dark)
                for side: Float in [-1,1] {
                    let z=side*0.615
                    func circle(_ zz: Float)->[Map3DPoint] { (0..<12).map { i in let a=Float(i)*2*Float.pi/12;return Map3DPoint(bx+ax+0.43*cosf(a),0.43+0.43*sinf(a),zz) } }
                    e500Prism(circle(z-0.09),circle(z+0.09),Map3DColor.rgb(0x303C46))
                    func hub(_ zz: Float)->[Map3DPoint] { (0..<8).map { i in let a=Float(i)*2*Float.pi/8;return Map3DPoint(bx+ax+0.18*cosf(a),0.43+0.18*sinf(a),zz) } }
                    e500Prism(hub(side*0.705),hub(side*0.735),Map3DColor.rgb(0x83949D))
                }
            }
        }
        for (i,x) in [Float(-3.8),-1.4,1.5,3.8].enumerated() {
            box(x,0.56,unit == .ep ? 0.15 : -0.12,1.8,1.8,i % 2 == 0 ? 0.40 : 0.33,dark)
            box(x,0.87,0,0.30,1.65,0.09,dark)
        }
        // Roof AC housings seated on real roof, with shallow matte grille panels.
        for x: Float in [-7.8,7.8] {
            box(x,3.65,0,2.60,1.75,0.064,silver)
            let section:[(Float,Float)]=[(3.714,-0.79),(3.88,-0.79),(3.964,-0.60),(3.964,0.60),(3.88,0.79),(3.714,0.79)]
            func end(_ xx: Float)->[Map3DPoint] { section.map { Map3DPoint(xx,$0.0,$0.1) } }
            e500Prism(end(x-1.175),end(x+1.175),silver)
            for side: Float in [-1,1] {
                for dx: Float in [-0.58,0.15] { box(x+dx,3.75,side*0.794,0.64,0.012,0.10,Map3DColor.rgb(0x83949D)) }
            }
            box(x,3.964,0,1.86,1.05,0.006,Map3DColor.rgb(0xAAB7BF))
        }
        if unit == .ep {
            box(-5.3,3.65,0,1.9,1.6,0.10,dark)
            for z: Float in [-0.5,0.5] {
                cylinder(-5.3,3.75,z,radius:0.10,height:0.18,color:silver,sides:8)
                beam(Map3DPoint(-5.8,3.93,z),Map3DPoint(-4.5,4.48,z),0.065,dark)
                beam(Map3DPoint(-4.5,4.48,z),Map3DPoint(-5.6,4.95,z),0.055,dark)
            }
            box(-5.6,4.95,0,0.10,1.75,0.05,dark)
        }
        // Couplers and supported gangways; no cab features on EP / ET.
        for end: Float in [-1,1] {
            box(end*10.03,0.70,0,0.27,0.36,0.25,dark)
            if end < 0 || !cab { box(end*9.99,1.25,0,0.10,1.04,1.95,dark) }
        }
        if cab {
            let steel=Map3DColor.rgb(0x89969B), rubber=Map3DColor.rgb(0x303C46)
            // Thin grey portal, deep blue door and a discrete gasket reveal.
            e500Panel(x:10.008,y:1.13,z:0,w:0.97,h:2.17,depth:0.050,front:true,color:rubber,radius:0.025)
            e500Panel(x:10.029,y:1.17,z:0,w:0.77,h:2.07,depth:0.020,front:true,color:blue,radius:0.025)
            for side: Float in [-1,1] {
                box(10.045,1.12,side*0.515,0.064,0.10,2.24,steel)
            }
            box(10.045,3.25,0,0.064,1.12,0.12,steel)
            box(10.045,1.10,0,0.064,1.10,0.10,steel)
            e500Panel(x:10.044,y:2.04,z:0,w:0.43,h:0.92,depth:0.012,front:true,color:glass,radius:0.15)
            e500Panel(x:10.044,y:1.57,z:0,w:0.68,h:0.37,depth:0.012,front:true,color:white,radius:0.025)
            // Two broad independent driving panes. Rounded corners are geometric.
            for side: Float in [-1,1] {
                let z=side*0.98
                e500CabPanel(2.12,z,0.72,1.08,0.002,0.022,rubber)
                e500CabPanel(2.15,z,0.66,1.02,0.023,0.012,glass)
                // Small supported windscreen wiper rather than a heavy frame.
                let p=Map3DPoint(Self.e500CabX(2.20,z)+0.046,2.20,z)
                let q=Map3DPoint(Self.e500CabX(2.72,z+side*0.07)+0.046,2.72,z+side*0.07)
                beam(p,q,0.018,rubber)
                // White livery ribbons turn inward and descend beside the portal.
                for dy: Float in [0,0.105,0.21] {
                    let path:[(Float,Float)]=[(1.92+dy,side*1.29),(1.92+dy,side*0.85),(1.90+dy,side*0.78),(1.85+dy,side*0.72),(1.57+dy,side*0.72)]
                    for i in 0..<(path.count-1) {
                        let a=path[i],b=path[i+1]
                        beam(Map3DPoint(Self.e500CabX(a.0,a.1)+0.016,a.0,a.1),Map3DPoint(Self.e500CabX(b.0,b.1)+0.016,b.0,b.1),0.038,white)
                    }
                }
                // Distinct blue marker pod and silver auxiliary lamp at each side.
                for (lateral,radius,color) in [(side*1.055,Float(0.155),blue),(side*0.765,Float(0.112),steel)] {
                    let points=(0..<12).map { i in
                        let a=Float(i)*2*Float.pi/12,y=1.55+radius*sinf(a),z=lateral+radius*cosf(a)
                        return Map3DPoint(Self.e500CabX(y,z)+0.008,y,z)
                    }
                    e500Prism(points,points.map { $0+Map3DPoint(0.045,0,0) },color)
                    let lensRadius=radius*0.63
                    let lens=(0..<12).map { i in
                        let a=Float(i)*2*Float.pi/12,y=1.55+lensRadius*sinf(a),z=lateral+lensRadius*cosf(a)
                        return Map3DPoint(Self.e500CabX(y,z)+0.052,y,z)
                    }
                    e500Prism(lens,lens.map { $0+Map3DPoint(0.010,0,0) },radius>0.13 ? rubber : white)
                }
            }
            e500CabPanel(3.37,0,0.63,0.25,0.002,0.060,rubber)
            for z: Float in [-0.16,0.16] {
                let p=(0..<12).map { i in
                    let a=Float(i)*2*Float.pi/12,y=3.495+0.088*sinf(a),zz=z+0.088*cosf(a)
                    return Map3DPoint(Self.e500CabX(y,zz)+0.061,y,zz)
                }
                e500Prism(p,p.map { $0+Map3DPoint(0.012,0,0) },yellow)
            }
            // Lower apron is a supported U: the coupler sits in a real open recess.
            for side: Float in [-1,1] {
                box(9.88,0.22,side*0.96,0.14,0.73,0.89,rubber)
                // Painted polygons clipped to the side apron; no protruding bars.
                for offset: Float in [-0.4,0,0.4] {
                    let polygon:[(Float,Float)]=[(0.22,0.42+offset),(0.22,0.62+offset),(1.11,1.27+offset),(1.11,1.07+offset)]
                    // Clip the stripe in lateral/height space against apron edges.
                    var poly=polygon
                    for (bound,keepGreater) in [(Float(0.595),true),(Float(1.325),false)] {
                        var clipped:[(Float,Float)]=[]
                        if !poly.isEmpty {
                            for i in poly.indices {
                                let a=poly[i],b=poly[(i+1)%poly.count]
                                let aa=keepGreater ? a.1>=bound : a.1<=bound
                                let bb=keepGreater ? b.1>=bound : b.1<=bound
                                if aa { clipped.append(a) }
                                if aa != bb { let t=(bound-a.1)/(b.1-a.1);clipped.append((a.0+t*(b.0-a.0),bound)) }
                            }
                        }
                        poly=clipped
                    }
                    if poly.count>=3 {
                        let a=poly.map { Map3DPoint(9.951,$0.0,side*$0.1) }
                        e500Prism(a,a.map { $0+Map3DPoint(0.004,0,0) },yellow)
                    }
                }
            }
            // Recessed structural bulkhead backs the opening and anchors the coupler.
            // It meets the underframe, keeping the recess deep without seeing through the car.
            box(9.74,0.29,0,0.12,1.20,0.76,dark)
            box(9.83,0.85,0,0.28,0.20,0.16,steel)
            box(9.88,0.17,0,0.14,1.20,0.15,rubber)
            box(9.94,0.69,0,0.16,0.50,0.32,steel)
            box(10.08,0.72,0,0.17,0.34,0.23,rubber)
            for side: Float in [-1,1] {
                beam(Map3DPoint(9.98,1.10,side*0.45),Map3DPoint(10.01,0.49,side*0.37),0.055,rubber)
                beam(Map3DPoint(10.01,0.49,side*0.37),Map3DPoint(10.08,0.70,side*0.21),0.055,rubber)
            }
        }
    }
}
