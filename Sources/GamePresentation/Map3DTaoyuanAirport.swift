import Foundation

/// Original Airport MRT geometry. Metres, native +X cabward / +Y left / +Z up.
/// Prototype dimensions are sourced; section radii and fittings are photo fits.
public enum Map3DTaoyuanAirport {
    public enum Role: String, CaseIterable, Sendable {
        case dmc1, mc1, mc2, dmc2, dme1, me1, me3, me4, dmb
        var cab: Bool { [.dmc1,.dmc2,.dme1,.dmb].contains(self) }
        var commuter: Bool { [.dmc1,.mc1,.mc2,.dmc2].contains(self) }
        public var pitch: Float { cab ? 20.78 : 20.25 }
    }
    public static func model(_ role: Role, far: Bool = false, shellOnly: Bool = false) -> Map3DModelPack.Model {
        var r = AirportRecipe(role: role, far: far)
        r.body()
        if !shellOnly { r.details() }
        let name = "taoyuan-airport-" + role.rawValue + (far ? "-far" : "") + (shellOnly ? "-shell" : "")
        return .flat(named: name, from: r.kit.mesh)
    }
}

private struct AirportUV {
    var h: Float
    var w: Float
    init(_ h: Float,_ w: Float) { self.h=h;self.w=w }
}

private struct AirportRecipe {
    let role: Map3DTaoyuanAirport.Role
    let far: Bool
    var kit = StationKitBuilder()
    let silver = Map3DColor.rgb(0xC4C9CD)
    let roof = Map3DColor.rgb(0xADB5BC)
    let steel = Map3DColor.rgb(0x7A858E)
    let hardware = Map3DColor.rgb(0x4B535C)
    let dark = Map3DColor.rgb(0x30363D)
    let rubber = Map3DColor.rgb(0x202329)
    let glass = Map3DTrainStyle.glass
    let blue = Map3DColor.rgb(0x5478C8)
    let purple = Map3DColor.rgb(0x9B73AC)
    var paint: UInt32 { role.commuter ? blue : purple }
    var half: Float { role.pitch/2 }
    // Same prototype section at both LODs. The driving end tucks and lowers
    // through longitudinal stations, rather than ending in a single flat cap.
    let section: [AirportUV] = [
        .init(1.02,-1.40),.init(1.18,-1.515),.init(3.08,-1.515),
        .init(3.25,-1.50),.init(3.43,-1.415),.init(3.58,-1.25),
        .init(3.69,-1.02),.init(3.75,-0.68),.init(3.763,-0.30),
        .init(3.763,0.30),.init(3.75,0.68),.init(3.69,1.02),
        .init(3.58,1.25),.init(3.43,1.415),.init(3.25,1.50),
        .init(3.08,1.515),.init(1.18,1.515),.init(1.02,1.40)
    ]
    // Include every section and paint station so side facets and front grid
    // share actual boundary vertices. LODs deliberately share this surface.
    var heights: [Float] {
        far ? [0.70,1.02,1.18,1.25,1.53,1.5848,1.6848,1.88,2.1424,2.88,3.25,3.763]
            : [0.70,1.02,1.18,1.25,1.53,1.5848,1.6848,1.88,2.1424,2.55,2.88,3.08,3.25,3.43,3.58,3.69,3.75,3.763]
    }
    var widths: [Float] {
        far ? [-1.515,-0.50,0,0.50,1.515] : [-1.515,-1.40,-1.02,-0.50,0,0.50,1.02,1.40,1.515]
    }
    func lerp(_ x: Float,_ knots: [Float],_ values: [Float]) -> Float {
        if x<=knots[0] { return values[0] }
        for i in 0..<(knots.count-1) where x<=knots[i+1] {
            return values[i]+(values[i+1]-values[i])*(x-knots[i])/(knots[i+1]-knots[i])
        }
        return values.last!
    }
    func sideWidth(_ h: Float) -> Float {
        lerp(h,[1.02,1.18,3.08,3.25,3.43,3.58,3.69,3.75,3.763],
             [1.40,1.515,1.515,1.50,1.415,1.25,1.02,0.68,0.30])
    }
    func frontX(_ p: AirportUV) -> Float {
        let setback=lerp(p.h,[0.70,1.02,1.25,1.53,1.88,2.25,2.55,2.88,3.25,3.43,3.58,3.69,3.763],
                         [0.10,0.10,0.075,0.075,0.10,0.15,0.22,0.32,0.47,0.58,0.67,0.73,0.77])
        return half-setback-0.11*(p.w*p.w)/(1.515*1.515)
    }
    func frontPoint(_ p: AirportUV) -> Map3DPoint {
        let h=Float((Double(p.h)*100000).rounded()/100000)
        let w=Float((Double(p.w)*100000).rounded()/100000)
        return Map3DPoint(frontX(.init(h,w)),h,w)
    }
    func cross(_ a: AirportUV,_ b: AirportUV,_ c: AirportUV) -> Float {
        (b.h-a.h)*(c.w-a.w)-(b.w-a.w)*(c.h-a.h)
    }
    func clean(_ p: [AirportUV]) -> [AirportUV] {
        var out: [AirportUV]=[]
        for a in p {
            if let b=out.last, abs(a.h-b.h)+abs(a.w-b.w)<0.000002 { continue }
            out.append(a)
        }
        if out.count>1, let a=out.first, let b=out.last, abs(a.h-b.h)+abs(a.w-b.w)<0.000002 { out.removeLast() }
        return out
    }
    func clip(_ p: [AirportUV],_ field: (AirportUV)->Float,_ positive: Bool = true) -> [AirportUV] {
        guard !p.isEmpty else { return [] }
        var out: [AirportUV]=[]
        for i in p.indices {
            let a=p[i],b=p[(i+1)%p.count]
            let da=field(a),db=field(b)
            let ia=positive ? da>=0 : da<=0,ib=positive ? db>=0 : db<=0
            if ia { out.append(a) }
            if ia != ib {
                let t=da/(da-db)
                out.append(.init(a.h+(b.h-a.h)*t,a.w+(b.w-a.w)*t))
            }
        }
        return clean(out)
    }
    func area(_ p: [AirportUV]) -> Float {
        guard p.count>=3 else { return 0 }
        return abs((1..<(p.count-1)).reduce(Float(0)) { $0+cross(p[0],p[$1],p[$1+1]) })
    }
    mutating func face(_ p: [Map3DPoint],_ inside: Map3DPoint,_ color: UInt32) {
        guard p.count>=3 else { return }
        if p.count == 3 {
            let c=(p[0]+p[1]+p[2])*(1/3)
            let n=(p[1]-p[0]).cross(p[2]-p[0])
            if n.dot(n)>1e-14 { kit.mesh.addFacet(n.dot(c-inside)>0 ? p : Array(p.reversed()),color:color) }
            return
        }
        if p.count == 4 {
            let n1=(p[1]-p[0]).cross(p[2]-p[0]),n2=(p[2]-p[0]).cross(p[3]-p[0])
            if n1.dot(n1)>1e-14 && n2.dot(n2)>1e-14 {
                face([p[0],p[1],p[2]],inside,color);face([p[0],p[2],p[3]],inside,color)
                return
            }
        }
        // Use a centre fan: preserves collinear boundary subdivisions without
        // emitting degenerate triangles along the vehicle's long straight sides.
        let c=p.reduce(.zero,+)*(1/Float(p.count))
        for i in p.indices {
            let a=p[i],b=p[(i+1)%p.count]
            let n=(a-c).cross(b-c)
            if n.dot(n)<1e-14 { continue }
            kit.mesh.addFacet(n.dot(c-inside)>0 ? [c,a,b] : [c,b,a],color:color)
        }
    }
    mutating func prism(_ a: [Map3DPoint],_ b: [Map3DPoint],_ color: UInt32) {
        guard a.count>=3 else { return }
        let c=(a+b).reduce(.zero,+)*(1/Float(a.count+b.count))
        face(a,c,color);face(b,c,color)
        for i in a.indices { let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],c,color) }
    }
    // Split the original outline at the same grid lines used by the front.
    var boundary: [AirportUV] {
        var result: [AirportUV]=[]
        for i in section.indices {
            let a=section[i],b=section[(i+1)%section.count]
            var ts: [Float]=[0]
            if a.h != b.h { ts += heights.map { ($0-a.h)/(b.h-a.h) }.filter { $0>0.00001 && $0<0.99999 } }
            if a.w != b.w { ts += widths.map { ($0-a.w)/(b.w-a.w) }.filter { $0>0.00001 && $0<0.99999 } }
            for t in Array(Set(ts)).sorted() { result.append(.init(a.h+(b.h-a.h)*t,a.w+(b.w-a.w)*t)) }
        }
        return clean(result)
    }
    var frontTriangles: [[AirportUV]] {
        var result: [[AirportUV]]=[]
        for i in 0..<(heights.count-1) { for j in 0..<(widths.count-1) {
            let h0=heights[i],h1=heights[i+1],w0=widths[j],w1=widths[j+1]
            var p: [AirportUV]=[.init(h0,w0),.init(h0,w1),.init(h1,w1),.init(h1,w0)]
            // Section is clockwise in (height,lateral), use its half planes.
            let direction:Float=cross(section[0],section[1],section[2])>=0 ? 1 : -1
            for k in section.indices { p=clip(p,{ direction*cross(section[k],section[(k+1)%section.count],$0) }) }
            if area(p)<1e-9 { continue }
            if p.count==3 { result.append(p);continue }
            if p.count==4 && abs(cross(p[0],p[1],p[2]))>1e-9 && abs(cross(p[0],p[2],p[3]))>1e-9 {
                result.append([p[0],p[1],p[2]]);result.append([p[0],p[2],p[3]]);continue
            }
            // Grid cells may cross a curved section edge; a centre fan keeps
            // all intersections and gives panels the exact same triangle map.
            let c=AirportUV(p.map(\.h).reduce(0,+)/Float(p.count),p.map(\.w).reduce(0,+)/Float(p.count))
            for k in p.indices { let q=[c,p[k],p[(k+1)%p.count]];if area(q)>1e-9 { result.append(q) } }
        } }
        return result
    }
    mutating func coloredFront(_ p: [AirportUV],_ map: (AirportUV)->Map3DPoint,_ interior: Map3DPoint) {
        let upper: (AirportUV)->Float = { $0.h-1.90-0.16*abs($0.w) }
        let up=clip(p,upper),low=clip(p,upper,false)
        if area(up)>1e-9 { face(up.map(map),interior,paint) }
        if area(low)<1e-9 { return }
        // Painted wings sweep upward to the cheeks, leaving the emergency
        // door centre silver. These are cuts of the shell, never floating decals.
        let inner=clip(low,{ 0.50-abs($0.w) })
        let outer=clip(low,{ abs($0.w)-0.50 })
        let bottom: (AirportUV)->Float = { $0.h-1.10-0.32*abs($0.w) }
        let top: (AirportUV)->Float = { $0.h-1.20-0.32*abs($0.w) }
        // Preserve the wing intersections on the central silver region too;
        // otherwise the common .50m boundary acquires a T junction.
        for q in [clip(inner,bottom,false),clip(clip(inner,bottom),top,false),clip(inner,top)] where area(q)>1e-9 {
            face(q.map(map),interior,silver)
        }
        let below=clip(outer,bottom,false),above=clip(outer,top)
        let band=clip(clip(outer,bottom),top,false)
        for q in [below,above] where area(q)>1e-9 { face(q.map(map),interior,silver) }
        if area(band)>1e-9 { face(band.map(map),interior,paint) }
    }
    mutating func body() {
        let ring=boundary,center=Map3DPoint(0,2.3,0)
        let rear=ring.map { Map3DPoint(-half+0.20,$0.h,$0.w) }
        face(rear,center,silver)
        let transitions: [Float]=role.cab ? [-half+0.20,half-2.00,half-1.25] : [-half+0.20,half-0.20]
        var previous=rear
        for x in transitions.dropFirst() {
            let next=ring.map { Map3DPoint(x,$0.h,$0.w) }
            for i in ring.indices {
                let j=(i+1)%ring.count,h=(ring[i].h+ring[j].h)/2
                let col:UInt32=h>3.58 ? roof : (h>=1.53 && h<1.88 ? paint : (h>=3.08 && h<3.25 ? purple : silver))
                face([previous[i],previous[j],next[j],next[i]],center,col)
            }
            previous=next
        }
        if role.cab {
            let front=ring.map(frontPoint)
            for i in ring.indices {
                let j=(i+1)%ring.count,h=(ring[i].h+ring[j].h)/2
                // Cab side upper paint; source confirms the broad wrap at
                // the crew door. Lower stripe remains continuous with body.
                let col:UInt32=h>3.58 ? roof : (h>1.53 ? paint : silver)
                face([previous[i],previous[j],front[j],front[i]],center,col)
            }
            for tri in frontTriangles { coloredFront(tri,frontPoint,center) }
        } else { face(previous,center,silver) }
    }
    func rounded(_ h0: Float,_ h1: Float,_ w0: Float,_ w1: Float,_ radius: Float) -> [AirportUV] {
        let r=min(radius,min(h1-h0,w1-w0)/2),n=far ? 1 : 3
        let centres:[AirportUV]=[.init(h0+r,w0+r),.init(h0+r,w1-r),.init(h1-r,w1-r),.init(h1-r,w0+r)]
        var out:[AirportUV]=[]
        for (k,c) in centres.enumerated() {
            for i in 0...n {
                let quarter = Float.pi / 2
                let a = -quarter - Float(k)*quarter - Float(i)*quarter/Float(n)
                out.append(.init(c.h+r*cosf(a),c.w+r*sinf(a)))
            }
        }
        return clean(out)
    }
    func inset(_ p:[AirportUV],_ scale:Float) -> [AirportUV] {
        let h=p.map(\.h).reduce(0,+)/Float(p.count),w=p.map(\.w).reduce(0,+)/Float(p.count)
        return p.map { .init(h+($0.h-h)*scale,w+($0.w-w)*scale) }
    }
    mutating func frontPatch(_ polygon:[AirportUV],_ color:UInt32,_ lift:Float,_ back:Float = -0.030) {
        // One curved solid per pane, not a closed prism for every grid cell.
        // Interior tessellation edges are shared; walls belong only to the
        // true outer contour. This preserves support while keeping units legal.
        struct Edge { var count:Int; let a:Map3DPoint;let b:Map3DPoint;let c:Map3DPoint;let d:Map3DPoint;let inside:Map3DPoint }
        var edges:[String:Edge]=[:]
        var points:[String:[Map3DPoint]]=[:]
        func shared(_ v:AirportUV)->Map3DPoint {
            let h=Int(floor(Double(v.h)*10000)),w=Int(floor(Double(v.w)*10000))
            for dh in -1...1 { for dw in -1...1 {
                for p in points["\(h+dh),\(w+dw)"] ?? [] where abs(p.y-v.h)+abs(p.z-v.w)<0.00002 { return p }
            } }
            let p=frontPoint(v)
            points["\(h),\(w)",default:[]].append(p)
            return p
        }
        func key(_ p:AirportUV)->String { "\(Int((p.h*100000).rounded())),\(Int((p.w*100000).rounded()))" }
        for tri in frontTriangles {
            let sign:Float=cross(tri[0],tri[1],tri[2])>0 ? 1 : -1
            var p=polygon
            for k in 0..<3 { p=clip(p,{ sign*cross(tri[k],tri[(k+1)%3],$0) }) }
            if area(p)<1e-9 { continue }
            func mapped(_ v:AirportUV,_ d:Float)->Map3DPoint {
                shared(v)+Map3DPoint(d,0,0)
            }
            let a=p.map { mapped($0,lift) },b=p.map { mapped($0,back) }
            let center=(a+b).reduce(.zero,+)*(1/Float(a.count+b.count))
            face(a,center,color);face(b,center,color)
            for i in p.indices {
                let j=(i+1)%p.count,ki=key(.init(a[i].y,a[i].z)),kj=key(.init(a[j].y,a[j].z)),id=ki<kj ? ki+"|"+kj : kj+"|"+ki
                if var edge=edges[id] { edge.count+=1;edges[id]=edge }
                else { edges[id]=Edge(count:1,a:a[i],b:a[j],c:b[j],d:b[i],inside:center) }
            }
        }
        for id in edges.keys.sorted() {
            let e=edges[id]!
            if e.count==1 { face([e.a,e.b,e.c,e.d],e.inside,color) }
        }
    }
    mutating func sidePatch(_ polygon:[AirportUV],_ side:Float,_ color:UInt32,_ front:Float,_ back:Float = -0.008) {
        // Here UV means height / longitudinal x; actual lateral support
        // follows each piecewise-linear side plane, including the shoulder.
        let breaks:[Float]=[0.70,1.02,1.18,3.08,3.25,3.43,3.58,3.69,3.75,3.763]
        for i in 0..<(breaks.count-1) {
            let p=clip(clip(polygon,{ $0.h-breaks[i] }),{ breaks[i+1]-$0.h })
            if area(p)<1e-9 { continue }
            let a=p.map { Map3DPoint($0.w,$0.h,side*(sideWidth($0.h)+front)) }
            let b=p.map { Map3DPoint($0.w,$0.h,side*(sideWidth($0.h)+back)) }
            prism(a,b,color)
        }
    }
    mutating func sideLeaf(_ p:[AirportUV],_ side:Float,_ depth:Float) {
        let a=clip(p,{1.53-$0.h}),b=clip(clip(p,{$0.h-1.53}),{1.88-$0.h}),c=clip(p,{$0.h-1.88})
        for (q,col) in [(a,silver),(b,paint),(c,silver)] where area(q)>1e-9 { sidePatch(q,side,col,depth) }
    }
    mutating func sideWindow(_ x:Float,_ h:Float,_ width:Float,_ height:Float,_ side:Float,_ radius:Float) {
        sidePatch(rounded(h-0.022,h+height+0.022,x-width/2-0.022,x+width/2+0.022,radius+0.02),side,steel,0.020)
        sidePatch(rounded(h,h+height,x-width/2,x+width/2,radius),side,glass,0.035,0.012)
    }
    mutating func doorsAndWindows() {
        for side:Float in [-1,1] {
            if role == .dmb {
                for x:Float in [-7.15,-3.85,-0.55,2.75,6.05] {
                    let p=rounded(1.16,3.06,x-1.15,x+1.15,0.065)
                    sidePatch(p,side,steel,0.013)
                    sideLeaf(rounded(1.18,3.04,x-1.125,x+1.125,0.045),side,0.023)
                    // Full-width baggage loading doors have a central seam
                    // and low latches; no remnants of passenger saloon glass.
                    kit.box(x,1.18,side*1.544,0.018,0.010,1.86,rubber)
                    if !far { for dx:Float in [-0.38,0.38] { kit.box(x+dx,1.34,side*1.544,0.070,0.010,0.10,hardware) } }
                }
            } else {
                for x:Float in [-6.20,0,6.20] {
                    sidePatch(rounded(1.14,3.10,x-0.79,x+0.79,0.11),side,hardware,0.015)
                    for dx:Float in [-0.385,0.385] {
                        sideLeaf(rounded(1.16,3.08,x+dx-0.378,x+dx+0.378,0.085),side,0.024)
                        sideWindow(x+dx,2.09,0.445,0.78,side,0.105)
                    }
                    kit.box(x,1.16,side*1.547,0.014,0.010,1.90,rubber)
                    if !far {
                        for dx:Float in [-0.14,0.14] { kit.box(x+dx,1.91,side*1.544,0.025,0.009,0.11,hardware) }
                    }
                }
                for x:Float in [-8.35,-4.10,-2.10,2.10,4.10,8.25] where !(role.cab && x>7.5) {
                    sideWindow(x,2.10,role.commuter ? 1.40 : 1.25,0.78,side,0.10)
                }
                // Unlettered display housing only. Actual headsigns belong
                // to the game's display mechanism, which this study does not change.
                sidePatch(rounded(3.10,3.25,3.07,3.83,0.04),side,rubber,0.025)
            }
            if role.cab {
                sidePatch(rounded(1.16,3.08,7.96,8.72,0.065),side,hardware,0.017)
                sideLeaf(rounded(1.18,3.06,7.98,8.70,0.045),side,0.027)
                sideWindow(8.34,2.12,0.43,0.80,side,0.09)
                if !far { kit.box(8.58,1.70,side*1.544,0.035,0.010,0.12,steel) }
            }
        }
    }
    mutating func cabDetails() {
        // Broad trapezoidal windscreens: curved top, sloping lower sill.
        for side:Float in [-1,1] {
            let p:[AirportUV]=[.init(2.03,side*0.50),.init(3.41,side*0.50),.init(3.36,side*0.84),.init(3.22,side*1.25),.init(3.09,side*1.29),.init(2.28,side*1.29)]
            if !far { frontPatch(p,steel,0.013) }
            frontPatch(inset(p,0.940),glass,0.027,-0.025)
        }
        // Full emergency-door outline. Paint is split through the door's
        // physical face at the same height as the prototype's centre panel.
        frontPatch(rounded(1.18,3.22,-0.445,0.445,0.035),rubber,0.016)
        let door=rounded(1.20,3.20,-0.425,0.425,0.025)
        frontPatch(clip(door,{1.91-$0.h}),silver,0.025)
        frontPatch(clip(door,{$0.h-1.91}),paint,0.025)
        if !far { frontPatch(rounded(2.10,2.94,-0.225,0.225,0.105),steel,0.034,0.013) }
        frontPatch(rounded(2.135,2.905,-0.187,0.187,0.078),glass,0.046,0.021)
        if !far { frontPatch(rounded(3.29,3.52,-0.365,0.365,0.035),steel,0.015) }
        frontPatch(rounded(3.31,3.50,-0.343,0.343,0.025),rubber,0.024)
        for side:Float in [-1,1] {
            let housing:[AirportUV]=[.init(1.35,side*0.54),.init(1.61,side*0.54),.init(1.89,side*1.29),.init(1.59,side*1.24),.init(1.43,side*0.80)]
            frontPatch(housing,steel,0.014)
            frontPatch(inset(housing,0.92),rubber,0.024)
            for (h,w,r,col):(Float,Float,Float,UInt32) in [(1.575,0.83,0.085,Map3DTrainStyle.headlamp),(1.675,1.085,0.064,Map3DColor.rgb(0x8D444D))] {
                let count=far ? 8 : 16
                func circle(_ radius:Float)->[AirportUV] {
                    (0..<count).map { i in let a=Float(i)*2*Float.pi/Float(count);return AirportUV(h+radius*sinf(a),side*w+radius*cosf(a)) }
                }
                frontPatch(circle(r+0.017),steel,0.030,0.010)
                frontPatch(circle(r),col,0.041,0.020)
            }
            // Lower corner aprons leave a real central coupler opening.
            let cheek:[AirportUV]=[.init(0.70,side*0.91),.init(0.70,side*1.36),.init(1.19,side*1.48),.init(1.19,side*0.91)]
            let a=cheek.map { Map3DPoint(frontX($0)-0.005,$0.h,$0.w) }
            prism(a,a.map { $0-Map3DPoint(0.21,0,0) },silver)
            if !far {
                // Resting wiper below the glass sill; no broad black cover
                // or exception capable of hiding an occluded windscreen.
                let a=AirportUV(2.00,side*0.58),b=AirportUV(2.20,side*1.17)
                kit.beam(frontPoint(a)+Map3DPoint(0.045,0,0),frontPoint(b)+Map3DPoint(0.045,0,0),0.018,rubber)
            }
        }
        // Supported stalk and an actual recessed socket. The flange's
        // foremost plane is exactly the official +half coupling plane.
        kit.box(half-0.56,0.72,0,0.72,0.24,0.16,hardware)
        let count=far ? 8 : 16
        func rimPoint(_ angle:Float,_ inner:Bool)->Map3DPoint {
            let c=cosf(angle),s=sinf(angle)
            let r:Float=inner ? 0.10 : min(0.20/max(abs(c),0.00001),0.145/max(abs(s),0.00001))
            return Map3DPoint(half,0.805+r*s,r*c)
        }
        for i in 0..<count {
            let a=Float(i)*2*Float.pi/Float(count),b=Float(i+1)*2*Float.pi/Float(count)
            let q=[rimPoint(a,false),rimPoint(b,false),rimPoint(b,true),rimPoint(a,true)]
            prism(q,q.map { $0-Map3DPoint(0.20,0,0) },steel)
        }
        let socket=(0..<count).map { i -> Map3DPoint in
            let a=Float(i)*2*Float.pi/Float(count)
            return Map3DPoint(half-0.195,0.805+0.10*sinf(a),0.10*cosf(a))
        }
        prism(socket,socket.map { $0-Map3DPoint(0.02,0,0) },rubber)
        if !far { for side:Float in [-1,1] { kit.box(half-0.10,0.69,side*0.145,0.20,0.024,0.06,hardware) } }
    }
    mutating func wheel(_ x:Float,_ side:Float) {
        let count=far ? 8 : 24,z=side*0.7675
        let p=(0..<count).map { i -> Map3DPoint in let a=Float(i)*2*Float.pi/Float(count);return Map3DPoint(x+0.425*cosf(a),0.425+0.425*sinf(a),z-0.05) }
        prism(p,p.map { $0+Map3DPoint(0,0,0.10) },rubber)
        // Thin steel tyre rim, rather than an oversized bright centre disc.
        let n=far ? 8 : 16
        for i in 0..<n {
            let a=Float(i)*2*Float.pi/Float(n),b=Float(i+1)*2*Float.pi/Float(n)
            let uv:[(Float,Float)]=[(0.425,a),(0.425,b),(0.375,b),(0.375,a)]
            let q=uv.map { Map3DPoint(x+$0.0*cosf($0.1),0.425+$0.0*sinf($0.1),z+side*0.054) }
            prism(q,q.map { $0-Map3DPoint(0,0,side*0.015) },steel)
        }
    }
    mutating func runningGear() {
        kit.box(0,0.92,0,role.pitch-0.60,2.50,0.10,hardware)
        for x:Float in [-6.75,6.75] {
            kit.box(x,0.66,0,2.50,1.34,0.14,hardware)
            kit.box(x,0.80,0,1.10,0.90,0.12,hardware)
            for dx:Float in [-1.05,1.05] {
                kit.beam(Map3DPoint(x+dx,0.425,-1.02),Map3DPoint(x+dx,0.425,1.02),0.11,hardware)
                for side:Float in [-1,1] {
                    wheel(x+dx,side)
                    kit.box(x+dx,0.32,side*1.005,0.30,0.22,0.23,hardware)
                    kit.beam(Map3DPoint(x+dx,0.50,side*0.98),Map3DPoint(x+dx*0.65,0.70,side*0.98),0.13,hardware)
                }
            }
            for side:Float in [-1,1] {
                kit.box(x,0.65,side*0.98,2.63,0.14,0.13,hardware)
                kit.box(x,0.28,side*1.12,0.70,0.50,0.09,dark)
                if !far {
                    for dx:Float in [-0.60,0.60] {
                        kit.cylinder(x+dx,0.72,side*0.88,radius:0.14,height:0.13,color:rubber,sides:12)
                        kit.box(x+dx,0.85,side*0.88,0.30,0.32,0.07,hardware)
                    }
                }
            }
        }
        let compressor = ![Map3DTaoyuanAirport.Role.dmc1,.dmc2,.dme1,.dmb,.me3].contains(role)
        let stations:[Float]=compressor ? [-3.3,0,3.2] : [-3.5,0.5]
        for x in stations {
            kit.box(x,0.48,compressor ? 0.17 : -0.17,2.25,1.65,0.44,hardware)
            if !far {
                for side:Float in [-1,1] {
                    for dx:Float in [-0.75,-0.50,-0.25,0,0.25,0.50,0.75] {
                        kit.box(x+dx,0.57,side*0.999,0.027,0.016,0.24,dark)
                    }
                }
            }
        }
    }
    mutating func roofDetails() {
        for x:Float in role == .dmb ? [8.05] : [-6.25,6.25] {
            let length:Float=role == .dmb ? 1.8 : 3.35
            kit.box(x,3.763,0,length,1.35,0.14,roof)
            if !far {
                for dx:Float in [-0.50,0,0.50] {
                    kit.box(x+dx,3.903,0,0.37,1.08,0.016,hardware)
                    for dz:Float in [-0.40,-0.20,0,0.20,0.40] { kit.box(x+dx,3.919,dz,0.34,0.035,0.008,roof) }
                }
            } else { kit.box(x,3.903,0,length*0.62,1.08,0.024,hardware) }
        }
    }
    mutating func ends() {
        for end:Float in role.cab ? [-1] : [-1,1] {
            kit.box(end*(half-0.12),1.10,0,0.24,1.55,2.15,rubber)
            // Bellows have a rim and actual repeated ribs; endpoints still
            // reach the same coupling plane, no new assembly spacing.
            if !far {
                for dx:Float in [-0.075,-0.025,0.025,0.075] {
                    kit.box(end*(half-0.12)+dx,1.10,-0.79,0.018,0.035,2.15,hardware)
                    kit.box(end*(half-0.12)+dx,1.10,0.79,0.018,0.035,2.15,hardware)
                    kit.box(end*(half-0.12)+dx,3.215,0,0.018,1.58,0.035,hardware)
                }
            }
            kit.box(end*(half-0.20),0.72,0,0.40,0.25,0.18,hardware)
        }
    }
    mutating func details() {
        runningGear();roofDetails();doorsAndWindows();ends()
        if role.cab { cabDetails() }
    }
}
