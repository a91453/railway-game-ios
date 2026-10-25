import Foundation

/// Photo-led, unbranded EMU3000 miniatures. Builder axes x/front, y/up, z/right;
/// the public models use metres, x/front, y/left, z/up, wheel tread at z=0.
/// Coupler pitches are sourced; fittings, nose sections and unseen side are estimates.
public enum Map3DEMU3000 {
    public enum Unit: String, CaseIterable, Sendable {
        case ed, em, ep3, et, em6, ep7, ep10, tail
        public var id: String { "emu3000-" + rawValue }
        public var isCab: Bool { self == .ed || self == .tail }
        public var pitch: Float { isCab ? 21.35 : 20.3 }
        public var hasPantograph: Bool { self == .ep3 || self == .ep7 || self == .ep10 }
    }
    public static let sequence: [Unit] = [.ed,.em,.ep3,.em,.et,.em6,.ep7,.em,.em,.ep10,.em,.tail]
    public static let bodyColor = Map3DPalette.shopAwnings[3]
    public static let accentColor = Map3DPalette.shopAwnings[0]
    public static let maskColor = Map3DColor.shaded(Map3DPalette.tankStand, 0.42)
    public static let glassColor = Map3DColor.shaded(Map3DPalette.glazing, 0.53)
    public static let steelColor = Map3DPalette.tankStand
    public static let lampColor = Map3DPalette.tunnelLamp

    /// Twelve-car real-world order; shorter game formations keep their selected count.
    public static func unit(at index: Int, count: Int) -> Unit {
        if count == 12, sequence.indices.contains(index) { return sequence[index] }
        if index == 0 { return .ed }
        if index == count-1 { return .tail }
        return index == 2 ? .ep3 : .em
    }
    public struct Placement: Sendable {
        public let unit: Unit
        public let x: Float
        /// Tail geometry is already turned; no second rotation at assembly time.
        public let rotation: Float = 0
    }
    public static var placements: [Placement] {
        let length = sequence.reduce(Float(0)) { $0+$1.pitch }
        var end = length/2
        return sequence.map { unit in
            let p = Placement(unit: unit, x: end-unit.pitch/2)
            end -= unit.pitch
            return p
        }
    }
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.emuCar(unit, far: far)
        let raw = Map3DModelPack.Model.flat(named: unit.id + (far ? "-far" : ""), from: b.mesh)
        let m = Map3DModelPack.Model(name:raw.name,vertices:raw.vertices.map { v in
            guard v.color == lampColor else { return v }
            return Map3DVertex(v.position,normal:Map3DPoint(v.nx,v.ny,v.nz),
                               color:unit == .tail ? Map3DPalette.lantern:Map3DTrainStyle.headlamp,layer:Map3DVertex.glowing)
        },minimum:raw.minimum,maximum:raw.maximum)
        guard unit == .tail else { return m }
        // Rotate the actual native model, including outward normals, about rail origin.
        return Map3DModelPack.Model(name:m.name, vertices:m.vertices.map {
            Map3DVertex(Map3DPoint(-$0.x,-$0.y,$0.z), normal:Map3DPoint(-$0.nx,-$0.ny,$0.nz),color:$0.color,layer:$0.layer)
        }, minimum:Map3DPoint(-m.maximum.x,-m.maximum.y,m.minimum.z),maximum:Map3DPoint(-m.minimum.x,-m.minimum.y,m.maximum.z))
    }
    // Minimal runtime adapter. Shared generic builders stay independent of this recipe.
    static func trainSet(far: Bool = false) -> Map3DTrainSet {
        Map3DTrainSet(key:far ? "emu3000Far":"emu3000",pantographCars:[2,6,9],ownLengths:true,far:far ? nil:"emu3000Far") {
            Map3DTrainSet.Cars(head:model(.ed,far:far),middle:model(.em,far:far),tail:model(.tail,far:far))
        }
    }
    static func gameName(_ unit: Unit, far: Bool) -> String {
        let role: String
        switch unit {case .ed: role="head";case .em: role="car";case .ep3: role="panto";default:role=unit.rawValue}
        return "set-"+(far ? "emu3000Far":"emu3000")+"-"+role
    }
    static func gameModels(far: Bool) -> [Map3DModelPack.Model] {
        Unit.allCases.map { unit in
            let m=model(unit,far:far)
            return Map3DModelPack.Model(name:gameName(unit,far:far),vertices:m.vertices,minimum:m.minimum,maximum:m.maximum)
        }
    }

    public static func formation(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for p in placements { b.add(model(p.unit, far: far),at:Map3DPoint(p.x,0,0)) }
        return .flat(named:"emu3000-formation"+(far ? "-far":""),from:b.mesh)
    }
}

private extension StationKitBuilder {
    typealias EU = Map3DEMU3000.Unit
    static var ew: UInt32 { Map3DEMU3000.bodyColor }
    static var ek: UInt32 { Map3DEMU3000.maskColor }
    static var eg: UInt32 { Map3DEMU3000.glassColor }
    static var es: UInt32 { Map3DEMU3000.steelColor }
    static var ea: UInt32 { Map3DEMU3000.accentColor }

    // A short, steep oval nose, independently sectioned from EMU references.
    // These are proportion estimates, not engineering sections or a scaled HSR nose.
    static func emuStations(_ cab: Bool) -> [(Float,Float,Float,Float)] {
        if !cab { return [(-9.8,3.49,0.90,1.455),(9.8,3.49,0.90,1.455)] }
        return [(-10.5,3.49,0.90,1.455),(6.2,3.49,0.90,1.455),
                (6.7,3.68,0.90,1.45),(7.3,3.63,0.90,1.40),
                (7.9,3.40,0.90,1.33),(8.5,2.96,0.77,1.21),
                (9.1,2.45,0.52,1.05),(9.65,1.99,0.30,0.90),
                (10.05,1.66,0.24,0.72),(10.35,1.42,0.36,0.53),
                (10.55,1.26,0.60,0.32),(10.65,1.18,0.84,0.18),(10.675,1.13,1.13,0)]
    }
    static func emuDimensions(_ x: Float,_ cab: Bool) -> (Float,Float,Float) {
        let s = emuStations(cab)
        for i in 1..<s.count where x <= s[i].0 {
            let a=s[i-1],b=s[i],t=max(0,min(1,(x-a.0)/(b.0-a.0)))
            return (a.1+(b.1-a.1)*t,a.2+(b.2-a.2)*t,a.3+(b.3-a.3)*t)
        }
        let b=s[s.count-1]; return (b.1,b.2,b.3)
    }
    /// Polygonal section, interpolated on the same diagonal as the shell triangles.
    static func emuPoint(_ x: Float,_ angle: Float,_ cab: Bool,_ sides: Int) -> Map3DPoint {
        func ring(_ x: Float,_ a: Float) -> Map3DPoint {
            let (top,bottom,width)=emuDimensions(x,cab)
            let s: Float=abs(sinf(a))<0.000001 ? 0:sinf(a),c: Float=abs(cosf(a))<0.000001 ? 0:cosf(a)
            let y=(top+bottom)/2+(s<0 ? -1:1)*powf(abs(s),0.60)*(top-bottom)/2
            let z=(c<0 ? -1:1)*powf(abs(c),0.58)*width
            return Map3DPoint(x,y,z)
        }
        let step=2*Float.pi/Float(sides),a0=floorf(angle/step)*step,t=(angle-a0)/step
        // In the straight section no longitudinal interpolation is required.
        let ss=emuStations(cab)
        for i in 1..<ss.count where x <= ss[i].0 {
            let xa=ss[i-1].0,xb=ss[i].0,u=max(0,min(1,(x-xa)/(xb-xa)))
            let p=ring(xa,a0),q=ring(xb,a0),r=ring(xb,a0+step),s=ring(xa,a0+step)
            return u>=t ? p+(q-p)*u+(r-q)*t : p+(r-s)*u+(s-p)*t
        }
        return ring(x,a0)*(1-t)+ring(x,a0+step)*t
    }
    static func emuSurface(_ x: Float,_ a: Float,_ cab: Bool,_ sides: Int,_ offset: Float) -> Map3DPoint {
        let p=emuPoint(x,a,cab,sides)
        let dx: Float=0.002,da: Float=0.002
        let vx=emuPoint(x-dx,a,cab,sides)-emuPoint(x+dx,a,cab,sides)
        let va=emuPoint(x,a-da,cab,sides)-emuPoint(x,a+da,cab,sides)
        var n=vx.cross(va).normalized ?? Map3DPoint(0,sinf(a),cosf(a))
        if n.dot(Map3DPoint(0,sinf(a),cosf(a)))<0 { n=n * -1 }
        return p+n*offset
    }
    static func emuMaskField(_ x: Float,_ a: Float,_ p: Map3DPoint) -> Float {
        // A single projected U-shaped field controls the helmet's lower face.
        // An angular band would pinch into a black spike as the section collapses.
        let height=max(0,min(1,(p.y-1.20)/2.29))
        let halfWidth:Float=1.36*sqrtf(max(0,1-(1-height)*(1-height)))
        let rear:Float=6.25+0.60*(p.z/1.36)*(p.z/1.36)
        return min(p.y-1.20,min(halfWidth-abs(p.z),x-rear))
    }
    mutating func emuShell(_ cab: Bool,_ sides: Int) {
        let stations=Self.emuStations(cab),inside=Map3DPoint(0,2.1,0)
        // Paint is clipped INTO each original shell triangle. Both colours share
        // identical cut vertices; there is no floating black overlay or white poke-through.
        func painted(_ points:[Map3DPoint],_ params:[(Float,Float)]) -> [([Map3DPoint],UInt32)] {
            guard cab else {return [(points,Self.ew)]}
            let values=zip(points,params).map {Self.emuMaskField($0.1.0,$0.1.1,$0.0)}
            func clip(_ positive:Bool)->[Map3DPoint] {
                var result:[Map3DPoint]=[]
                for i in points.indices {
                    let j=(i+1)%points.count,a=points[i],b=points[j],fa=values[i],fb=values[j]
                    if positive ? fa>=0:fa<=0 {result.append(a)}
                    if fa*fb<0 {
                        // Canonical endpoint order makes neighbouring triangle cuts bit-identical.
                        let ordered=a.x != b.x ? a.x<b.x:a.y != b.y ? a.y<b.y:a.z<b.z
                        let p=ordered ? a:b,q=ordered ? b:a,f=ordered ? fa:fb,g=ordered ? fb:fa
                        result.append(p+(q-p)*(f/(f-g)))
                    }
                }
                return result
            }
            return [(clip(false),Self.ew),(clip(true),Self.ek)].filter {$0.0.count>=3}
        }
        for i in 1..<stations.count {
            for j in 0..<sides {
                let a=Float(j)*2*Float.pi/Float(sides),b=Float(j+1)*2*Float.pi/Float(sides),xa=stations[i-1].0,xb=stations[i].0
                let p=Self.emuPoint(xa,a,cab,sides),q=Self.emuPoint(xb,a,cab,sides)
                let r=Self.emuPoint(xb,b,cab,sides),s=Self.emuPoint(xa,b,cab,sides)
                let x=(p.x+q.x)/2,d=Self.emuDimensions(x,cab),c=Map3DPoint(x,(d.0+d.1)/2,0)
                for (points,params) in [([p,q,r],[(xa,a),(xb,a),(xb,b)]),([p,r,s],[(xa,a),(xb,b),(xa,b)])] {
                    for (polygon,color) in painted(points,params) {face(polygon,inside:c,color:color)}
                }
            }
        }
        for x in [stations[0].0,stations[stations.count-1].0] {
            let d=Self.emuDimensions(x,cab),centre=Map3DPoint(x,(d.0+d.1)/2,0)
            for j in 0..<sides {face([centre,Self.emuPoint(x,Float(j)*2*Float.pi/Float(sides),cab,sides),Self.emuPoint(x,Float(j+1)*2*Float.pi/Float(sides),cab,sides)],inside:inside,color:Self.ew)}
        }
    }
    /// Closed solid panel; back penetrates its supporting surface by 3 cm.
    /// p/q are corresponding front/back loops, not a two-sided decal.
    mutating func emuSolid(_ p: [Map3DPoint],_ q: [Map3DPoint],_ color: UInt32) {
        let inside=(p+q).reduce(.zero,+)*(1/Float(p.count+q.count))
        face(p,inside:inside,color:color);face(q,inside:inside,color:color)
        for i in p.indices { let j=(i+1)%p.count;face([p[i],q[i],q[j],p[j]],inside:inside,color:color) }
    }
    /// Rounded rectangular opening: single manifold solid, fine gasket ring, glass centre.
    mutating func emuOpening(_ x: Float,_ y: Float,_ width: Float,_ height: Float,_ side: Float,
                             _ cab: Bool,_ sides: Int,_ fill: UInt32,_ frame: UInt32,_ rim: Float=0.025) {
        let radius=min(0.10,min(width,height)*0.16)
        func outline(_ inset: Float) -> [Map3DPoint] {
            let w=width/2-inset,h=height/2-inset,r=max(0.001,min(radius-inset,min(w,h)*0.95))
            return [(Float(-1),Float(-1)),(1,-1),(1,1),(-1,1)].flatMap { sx,sy in
                let start=atan2f(sy,sx)-Float.pi/4
                let corners=sides<=12 ? 2:3
                return (0..<corners).map { k in
                    let a=start+Float(k)*Float.pi/(2*Float(corners-1))
                    let xx=x+sx*(w-r)+cosf(a)*r,yy=y+sy*(h-r)+sinf(a)*r
                    let d=Self.emuDimensions(xx,cab),s=max(-1,min(1,(yy-(d.0+d.1)/2)/((d.0-d.1)/2)))
                    let angle=asinf((s<0 ? -1:1)*powf(abs(s),1/0.60))
                    return Self.emuPoint(xx,side>0 ? angle:Float.pi-angle,cab,sides)
                }
            }
        }
        let base=outline(0),inner=outline(rim)
        let p=base.map { $0+Map3DPoint(0,0,side*0.012) },q=base.map { $0-Map3DPoint(0,0,side*0.03) }
        let r=inner.map { $0+Map3DPoint(0,0,side*0.012) }
        let inside=(p+q).reduce(.zero,+)*(1/Float(p.count+q.count))
        face(r,inside:inside,color:fill);face(q,inside:inside,color:frame)
        for i in p.indices { let j=(i+1)%p.count
            face([p[i],r[i],r[j],p[j]],inside:inside,color:frame)
            face([p[i],q[i],q[j],p[j]],inside:inside,color:frame)
        }
    }
    /// Door leaves use the white hull itself; only the fitted gasket is added.
    /// Logical faces are split at real section planes BEFORE projection. This
    /// prevents a large fan bridging the convex shoulder and hiding the glass.
    mutating func emuFittedOpening(_ x: Float,_ y: Float,_ width: Float,_ height: Float,
                                   _ side: Float,_ cab: Bool,_ sides: Int,
                                   _ fill: UInt32,_ frame: UInt32,_ rim: Float,
                                   outlineOnly: Bool = false) {
        let radius=min(0.10,min(width,height)*0.16),front:Float=0.018,back:Float = -0.025
        func outline(_ inset:Float,_ depth:Float)->[Map3DPoint] {
            let w=width/2-inset,h=height/2-inset,r=max(0.001,min(radius-inset,min(w,h)*0.95))
            return [(Float(-1),Float(-1)),(1,-1),(1,1),(-1,1)].flatMap { sx,sy in
                let start=atan2f(sy,sx)-Float.pi/4,corners=sides<=12 ? 2:3
                return (0..<corners).map {k in
                    let a=start+Float(k)*Float.pi/(2*Float(corners-1))
                    return Map3DPoint(x+sx*(w-r)+cosf(a)*r,y+sy*(h-r)+sinf(a)*r,side*depth)
                }
            }
        }
        // Solve the real polygonal section, including its longitudinal diagonal.
        // This also fits the driver's door on the tapered cab, not a straight plane.
        func crossSection(_ x:Float)->[Map3DPoint] {
            let stations=Self.emuStations(cab)
            var u:Float=0
            for i in 1..<stations.count where x<=stations[i].0 {
                u=max(0,min(1,(x-stations[i-1].0)/(stations[i].0-stations[i-1].0)));break
            }
            var angles:[Float]=[]
            for j in -sides/4..<sides/4 {
                angles.append(Float(j)*2*Float.pi/Float(sides))
                if cab && x>6.2 && u>0.000001 && u<0.999999 {angles.append((Float(j)+u)*2*Float.pi/Float(sides))}
            }
            angles.append(Float.pi/2)
            return angles.map {Self.emuPoint(x,$0,cab,sides)}
        }
        let section=crossSection(x)
        let levels=Array(Set(section.map {$0.y})).sorted()
        func projected(_ p:Map3DPoint)->Map3DPoint {
            let local=crossSection(p.x)
            var z:Float=0
            for i in 1..<local.count {
                let a=local[i-1],b=local[i]
                if p.y>=min(a.y,b.y)-0.000001 && p.y<=max(a.y,b.y)+0.000001 && abs(a.y-b.y)>0.000001 {
                    let t=max(0,min(1,(p.y-a.y)/(b.y-a.y)))
                    z=max(z,abs(a.z+(b.z-a.z)*t))
                }
            }
            return Map3DPoint(p.x,p.y,side*z+p.z)
        }
        func clip(_ points:[Map3DPoint],_ level:Float,_ above:Bool)->[Map3DPoint] {
            var out:[Map3DPoint]=[]
            for i in points.indices {
                let a=points[i],b=points[(i+1)%points.count]
                if above ? a.y>=level:a.y<=level {out.append(a)}
                if (a.y-level)*(b.y-level)<0 {
                    let p=a.y<b.y ? a:b,q=a.y<b.y ? b:a
                    let v=p+(q-p)*((level-p.y)/(q.y-p.y))
                    out.append(Map3DPoint(v.x,level,v.z))
                }
            }
            var clean:[Map3DPoint]=[]
            for p in out where clean.last != p {clean.append(p)}
            if clean.count>1 && clean.first==clean.last {clean.removeLast()}
            return clean
        }
        func triangulated(_ points:[Map3DPoint],_ inside:Map3DPoint)->[[Map3DPoint]] {
            let n=(points[1]-points[0]).cross(points[2]-points[0]),c=points.reduce(.zero,+)*(1/Float(points.count))
            let loop=n.dot(c-inside)>=0 ? points:Array(points.reversed())
            var out:[[Map3DPoint]]=[]
            for j in 1..<levels.count {
                let slice=clip(clip(loop,levels[j-1],true),levels[j],false)
                if slice.count>=3 {out.append(slice.map(projected))}
            }
            return out
        }
        let p=outline(0,front),q=outline(0,back),r=outline(rim,front),s=outline(rim,back)
        let inside=Map3DPoint(x,y,side*(front+back)/2)
        if !outlineOnly {
            for polygon in triangulated(r,inside) {mesh.addFacet(polygon,color:fill)}
            for polygon in triangulated(q,inside) {mesh.addFacet(polygon,color:frame)}
        }
        for i in p.indices {
            let j=(i+1)%p.count,local=([p[i],p[j],q[i],q[j],r[i],r[j],s[i],s[j]]).reduce(.zero,+)*0.125
            var faces=[[p[i],r[i],r[j],p[j]],[p[i],q[i],q[j],p[j]]]
            if outlineOnly {faces += [[q[i],s[i],s[j],q[j]],[r[i],s[i],s[j],r[j]]]}
            for face in faces {for polygon in triangulated(face,outlineOnly ? local:inside) {mesh.addFacet(polygon,color:frame)}}
        }
    }
    /// Tessellated CLOSED quarterlight bonded to the actual faceted side.
    /// A single planar five-corner face bridges the shoulder and exposes white chips.
    mutating func emuQuarterlight(_ side: Float,_ sides: Int,_ far: Bool) {
        let outline:[(Float,Float)]=[(7.35,2.58),(7.34,3.07),(7.95,2.94),(8.68,2.43),(8.37,2.39)]
        let centre=outline.reduce((Float(0),Float(0))) {($0.0+$1.0/5,$0.1+$1.1/5)},n=far ? 2:5
        var vertices:[String:(Map3DPoint,Map3DPoint)]=[:],edges:[String:([String],Int,Map3DPoint)]=[:]
        func vertex(_ x:Float,_ y:Float)->String {
            let xx=(x*100000).rounded()/100000,yy=(y*100000).rounded()/100000,key="\(xx),\(yy)"
            if vertices[key]==nil {
                let d=Self.emuDimensions(xx,true),s=(yy-(d.0+d.1)/2)/((d.0-d.1)/2)
                let a=asinf(powf(max(0,min(1,s)),1/0.60)),angle=side>0 ? a:Float.pi-a
                vertices[key]=(Self.emuSurface(xx,angle,true,sides,0.012),Self.emuSurface(xx,angle,true,sides,-0.028))
            }
            return key
        }
        var triangles:[[String]]=[]
        for k in outline.indices {
            let a=centre,b=outline[k],c=outline[(k+1)%outline.count]
            func point(_ i:Int,_ j:Int)->String {let u=Float(i)/Float(n),v=Float(j)/Float(n);return vertex(a.0+(b.0-a.0)*u+(c.0-a.0)*v,a.1+(b.1-a.1)*u+(c.1-a.1)*v)}
            for i in 0..<n {for j in 0..<n-i {
                triangles.append([point(i,j),point(i+1,j),point(i,j+1)])
                if i+j<n-1 {triangles.append([point(i+1,j),point(i+1,j+1),point(i,j+1)])}
            }}
        }
        for ids in triangles {
            let p=ids.map {vertices[$0]!.0},q=ids.map {vertices[$0]!.1},inside=(p+q).reduce(.zero,+)*(1/6)
            face(p,inside:inside,color:Self.eg);face(q,inside:inside,color:Self.eg)
            for i in 0..<3 {
                let a=ids[i],b=ids[(i+1)%3],key=[a,b].sorted().joined(separator:"|")
                let old=edges[key];edges[key]=([a,b],(old?.1 ?? 0)+1,inside)
            }
        }
        for key in edges.keys.sorted() {
            guard let edge=edges[key],edge.1==1 else {continue}
            let a=vertices[edge.0[0]]!,b=vertices[edge.0[1]]!
            face([a.0,a.1,b.1,b.0],inside:edge.2,color:Self.eg)
        }
    }
    mutating func emuDoorsAndWindows(_ unit: EU,_ cab: Bool,_ sides: Int,_ far: Bool) {
        let doors: [Float]=cab ? [-8.5,5.30]:[-8.0,8.0]
        for side: Float in [-1,1] {
            for x in doors {
                emuFittedOpening(x,2.16,0.90,2.02,side,cab,sides,Self.ew,Self.es,0.018,outlineOnly:true)
                emuFittedOpening(x,2.72,0.45,0.69,side,cab,sides,Self.eg,Self.ek,0.024)
                if !far { emuOpening(x-0.29,1.80,0.035,0.22,side,cab,sides,Self.es,Self.es,0.009) }
            }
            if cab {
                emuFittedOpening(7.0,2.17,0.59,2.03,side,cab,sides,Self.ew,Self.es,0.016,outlineOnly:true)
                emuFittedOpening(7.0,2.76,0.31,0.58,side,cab,sides,Self.eg,Self.ek,0.019)
                emuQuarterlight(side,sides,far)
            }
            let count=cab ? 10:unit == .ep3 || unit == .ep7 || unit == .em6 ? 12:13
            for i in 0..<count {
                let x=cab ? -7.25+Float(i)*1.10 : -6.65+Float(i)*(13.3/Float(count-1))
                // Illustration's car1 side is +x. Business has two blank windows;
                // EP7 has a service bay, independent of the normal EP3/EP10 units.
                let blank = unit == .em6 && i>=count-2 || unit == .ep7 && i==count-2
                emuOpening(x,2.35,cab ? 0.68:0.72,0.74,side,cab,sides,blank ? Self.ew:Self.eg,Self.ek,far ? 0.024:0.029)
            }
            if !cab || !far { emuOpening(cab ? -9.66:-9.1,2.54,0.48,0.45,side,cab,sides,Self.eg,Self.ek,0.023) }
            if !far {
                for x in doors { emuOpening(x-0.88,3.03,0.72,0.20,side,cab,sides,Self.ek,Self.es,0.012) }
            }
            // Narrow roof-shoulder accent, below the roof edge. Deliberate game palette.
            let start: Float=cab ? -10.35:-9.65,end: Float=cab ? 4.7:9.65
            emuOpening((start+end)/2,3.28,end-start,0.055,side,cab,sides,Self.ea,Self.ea,0.010)
        }
    }
    /// Closed gridded patch bonded to the actual shell; walls only on the perimeter.
    mutating func emuPatch(_ cab: Bool,_ sides: Int,_ columns: Int,_ rows: Int,
                           _ range: (Float,Float,Float,Float),_ color: UInt32,_ offset: Float = 0.010) {
        let (u0,u1,v0,v1)=range
        func point(_ u: Float,_ v: Float,_ o: Float)->Map3DPoint {
            let t=(u-0.5)*2,cap=sqrtf(max(0,1-t*t))
            let rear: Float=6.25+0.20*(1-cap),front: Float=10.58-0.72*(1-cap)
            let x=rear+(front-rear)*v,a=Float.pi/2+t*(0.98-0.16*v)
            return Self.emuSurface(x,a,cab,sides,o)
        }
        func u(_ i: Int)->Float {u0+(u1-u0)*Float(i)/Float(columns)}
        func v(_ j: Int)->Float {v0+(v1-v0)*Float(j)/Float(rows)}
        func p(_ i: Int,_ j: Int,_ back: Bool)->Map3DPoint {point(u(i),v(j),back ? offset-0.05:offset)}
        for i in 0..<columns { for j in 0..<rows {
            let front=[p(i,j,false),p(i+1,j,false),p(i+1,j+1,false),p(i,j+1,false)]
            let back=[p(i,j,true),p(i+1,j,true),p(i+1,j+1,true),p(i,j+1,true)]
            let centre=(front+back).reduce(.zero,+)*0.125
            face(front,inside:centre,color:color);face(back,inside:centre,color:color)
            for edge in 0..<4 where edge==0 && j==0 || edge==1 && i==columns-1 || edge==2 && j==rows-1 || edge==3 && i==0 {
                let k=(edge+1)%4
                face([front[edge],back[edge],back[k],front[k]],inside:centre,color:color)
            }
        } }
    }

    mutating func emuLens(_ u: Float,_ v: Float,_ ru: Float,_ rv: Float,_ sides: Int,_ color: UInt32) {
        func point(_ a:Float,_ offset:Float)->Map3DPoint {
            let uu=u+cosf(a)*ru,vv=v+sinf(a)*rv,t=(uu-0.5)*2,cap=sqrtf(max(0,1-t*t))
            let rear:Float=6.25+0.20*(1-cap),front:Float=10.58-0.72*(1-cap)
            return Self.emuSurface(rear+(front-rear)*vv,Float.pi/2+t*(0.98-0.16*vv),true,sides,offset)
        }
        let angles=(0..<8).map {Float($0)*Float.pi/4}
        emuSolid(angles.map {point($0,0.026)},angles.map {point($0,-0.025)},color)
    }
    /// Subtle U-shaped access-hatch seam projected onto the real nose triangles.
    /// It is closed solid geometry with its back bonded into the hull, not a decal.
    mutating func emuHatchSeam(_ sides:Int) {
        let stations=Self.emuStations(true)
        var triangles:[[Map3DPoint]]=[]
        for i in 1..<stations.count {for j in 0..<sides {
            let a=Float(j)*2*Float.pi/Float(sides),b=Float(j+1)*2*Float.pi/Float(sides)
            let p=Self.emuPoint(stations[i-1].0,a,true,sides),q=Self.emuPoint(stations[i].0,a,true,sides)
            let r=Self.emuPoint(stations[i].0,b,true,sides),s=Self.emuPoint(stations[i-1].0,b,true,sides)
            triangles.append([p,q,r]);triangles.append([p,r,s])
        }}
        func project(_ y:Float,_ z:Float)->(Map3DPoint,Map3DPoint)? {
            let origin=Map3DPoint(11,y,z),direction=Map3DPoint(-1,0,0)
            var nearest:Float=100,hit:(Map3DPoint,Map3DPoint)?
            for t in triangles {
                let e=t[1]-t[0],f=t[2]-t[0],h=direction.cross(f),d=e.dot(h)
                if abs(d)<0.000001 {continue}
                let s=origin-t[0],u=s.dot(h)/d,q=s.cross(e),v=direction.dot(q)/d,dist=f.dot(q)/d
                if u>=0 && v>=0 && u+v<=1 && dist>0 && dist<nearest {
                    nearest=dist
                    var n=e.cross(f).normalized ?? .zero;if n.x<0 {n=n * -1}
                    let surface=origin+direction*dist
                    hit=(surface+n*0.006,surface-n*0.012)
                }
            }
            return hit
        }
        let outline:[(Float,Float)]=[(2.0,-0.84),(1.70,-0.92),(1.10,-0.86),(0.48,-0.65),
                                    (0.35,-0.30),(0.34,0),(0.35,0.30),(0.48,0.65),
                                    (1.10,0.86),(1.70,0.92),(2.0,0.84)]
        var path:[(Float,Float)]=[]
        for i in 1..<outline.count {for j in 0..<4 {
            let t=Float(j)/4,a=outline[i-1],b=outline[i]
            path.append((a.0+(b.0-a.0)*t,a.1+(b.1-a.1)*t))
        }}
        path.append(outline[outline.count-1])
        var rings:[[Map3DPoint]]=[]
        for i in path.indices {
            let a=path[max(0,i-1)],b=path[min(path.count-1,i+1)],p=path[i]
            let dy=b.0-a.0,dz=b.1-a.1,length=sqrtf(dy*dy+dz*dz),oy = -dz/length*0.006,oz=dy/length*0.006
            guard let left=project(p.0+oy,p.1+oz),let right=project(p.0-oy,p.1-oz) else {return}
            rings.append([left.0,right.0,right.1,left.1])
        }
        let color=Map3DColor.shaded(Self.ew,0.74)
        for i in 1..<rings.count {
            let a=rings[i-1],b=rings[i],inside=(a+b).reduce(.zero,+)*0.125
            for j in 0..<4 {let k=(j+1)%4;face([a[j],a[k],b[k],b[j]],inside:inside,color:color)}
        }
        let first=rings[0],last=rings[rings.count-1]
        face(first,inside:(first+rings[1]).reduce(.zero,+)*0.125,color:color)
        face(last,inside:(last+rings[rings.count-2]).reduce(.zero,+)*0.125,color:color)
    }

    mutating func emuCab(_ sides: Int,_ far: Bool,_ tail: Bool) {
        // More upright cab, compact trapezoid glazing, restrained dark gasket.
        emuPatch(true,sides,far ? 4:10,far ? 2:5,(0.20,0.80,0.39,0.71),Map3DColor.shaded(Self.es,0.58),0.022)
        emuPatch(true,sides,far ? 4:10,far ? 2:5,(0.212,0.788,0.405,0.695),Self.eg,0.034)
        emuPatch(true,sides,4,2,(0.458,0.542,0.24,0.38),Self.es)
        for u:Float in [0.486,0.514] {emuLens(u,0.31,0.010,0.045,sides,tail ? Self.eg:Map3DEMU3000.lampColor)}
        // Broad slanted cheek housings with two round lenses, not razor strips.
        for u:Float in [0.13,0.87] {
            emuPatch(true,sides,3,4,(u-0.11,u+0.11,0.70,0.90),Self.es)
            emuLens(u,0.755,0.060,0.043,sides,tail ? Self.eg:Map3DEMU3000.lampColor)
            emuLens(u,0.845,0.027,0.029,sides,tail ? Map3DEMU3000.lampColor:Self.eg)
        }
        if !far {
            emuHatchSeam(sides)
            let a=Self.emuSurface(9.05,1.43,true,sides,0.045),b=Self.emuSurface(8.65,1.26,true,sides,0.045)
            beam(a,b,0.022,Self.ek)
            beam(b,Self.emuSurface(8.25,1.26,true,sides,0.045),0.025,Self.ek)
            civicTube(a-Map3DPoint(0,0.09,0),a,radius:0.040,color:Self.ek,sides:8)
        }
    }
    mutating func emuRunningGear(_ unit: EU,_ far: Bool) {
        let cab=unit.isCab
        let centres: [Float]=cab ? [-6.55,6.15]:[-6.75,6.75]
        box(cab ? -1.4:0,0.84,0,cab ? 16.9:18.9,2.42,0.20,Self.ek)
        for x in centres {
            box(x,0.60,0,2.90,0.82,0.29,Self.ek)
            box(x,0.88,0,1.55,1.10,0.15,Self.es)
            for dx: Float in [-1.02,1.02] {
                let xx=x+dx
                civicTube(Map3DPoint(xx,0.41,-0.79),Map3DPoint(xx,0.41,0.79),radius:far ? 0.10:0.07,color:Self.es,sides:far ? 6:8)
                for side: Float in [-1,1] {
                    civicTube(Map3DPoint(xx,0.41,side*0.4935),Map3DPoint(xx,0.41,side*0.6535),radius:0.41,color:Self.ek,sides:far ? 8:12)
                    if !far {
                        civicTube(Map3DPoint(xx,0.41,side*0.65),Map3DPoint(xx,0.41,side*0.675),radius:0.26,color:Self.es,sides:12)
                        box(xx,0.41,side*0.78,0.35,0.24,0.20,Self.es)
                        box(xx,0.66,side*0.73,0.20,0.20,0.19,Self.ek)
                    }
                }
            }
        }
        // Equipment kept BETWEEN the bogie swept envelopes, never hiding wheels.
        let equipment:[(Float,Float)]
        if unit == .et {equipment=[(-3.6,2.0),(1.0,2.0),(3.5,2.2)]}
        else if unit.hasPantograph {equipment=[(-3.4,2.4),(1.4,3.6)]}
        else {equipment=[(-3.5,2.4),(-0.7,2.4),(2.5,2.1)]}
        for (x,length) in equipment {
            box(x,0.44,0,length,2.08,0.46,Self.es)
            if !far {for z: Float in [-1.047,1.047] {box(x,0.60,z,length*0.70,0.018,0.16,Self.ek)}}
        }
        // Distinct trailer/collector underfloor equipment, observed arrangement
        // interpreted at miniature detail density; hidden equipment is not confirmed.
        if unit == .et || unit.hasPantograph {
            let x: Float=unit == .et ? -1.1:-1.3
            for z: Float in [-0.62,0.62] {
                civicTube(Map3DPoint(x-0.55,0.56,z),Map3DPoint(x+0.55,0.56,z),radius:0.19,color:Self.ek,sides:far ? 6:12)
            }
            for dx: Float in [-0.35,0.35] {box(x+dx,0.71,0,0.15,1.62,0.16,Self.es)}
        }
        for end: Float in [-1,1] where !cab || end<0 {
            let x=end*(cab ? 10.56:9.86)
            box(x,1.20,0,0.12,1.60,1.86,Self.ek)
            // Bellows reach half the coupler gap; assembled units share this plane.
            box(end*(cab ? 10.6175:10.0),1.30,0,cab ? 0.115:0.30,1.48,1.70,Self.es)
            if !far { for d: Float in [-0.038,0.038] { box(x+d,1.23,0,0.018,1.66,1.80,Self.ek) } }
            box(end*(cab ? 10.625:10.0),0.69,0,cab ? 0.10:0.30,0.29,0.24,Self.ek)
        }
    }
    mutating func emuRoof(_ unit: EU,_ far: Bool) {
        let cab=unit.isCab
        for x: Float in cab ? [-5.2,1.4]:[-3.9,3.9] {
            box(x,3.46,0,3.0,1.70,0.25,Self.es)
            box(x,3.71,0,2.62,1.34,0.04,Map3DPalette.concrete)
            if !far {
                for dx: Float in [-0.75,0.75] {
                    box(x+dx,3.752,0,0.91,1.10,0.012,Self.es)
                    for z:Float in [-0.32,0,0.32] {box(x+dx,3.764,z,0.74,0.026,0.008,Map3DPalette.concrete)}
                }
                for z: Float in [-0.85,0.85] {for dx: Float in [-0.8,0,0.8] {box(x+dx,3.54,z,0.47,0.025,0.08,Self.es)}}
            }
        }
        if cab {
            box(4.6,3.46,0,0.70,0.61,0.11,Self.es)
            if !far { box(4.6,3.57,0,0.24,0.24,0.09,Self.ew) }
        }
        guard unit.hasPantograph else { return }
        let direction: Float=unit == .ep10 ? -1:1,x: Float=direction*6.9
        box(x,3.45,0,1.70,1.45,0.13,Self.es)
        for dx: Float in [-0.60,0.60] { for z: Float in [-0.52,0.52] {
            cylinder(x+dx,3.58,z,radius:0.09,height:0.22,color:Self.ew,sides:far ? 6:8)
        } }
        box(x,3.78,0,1.34,1.18,0.08,Self.ek)
        let base=Map3DPoint(x-direction*0.40,3.86,0),elbow=Map3DPoint(x+direction*0.62,4.30,0),top=Map3DPoint(x-direction*0.15,4.76,0)
        // Raised contact height is an explicitly estimated display pose.
        for z: Float in [-0.27,0.27] {
            beam(base+Map3DPoint(0,0,z),elbow+Map3DPoint(0,0,z),far ? 0.075:0.065,Self.es)
            beam(elbow+Map3DPoint(0,0,z),top+Map3DPoint(0,0,z*1.6),far ? 0.065:0.052,Self.es)
        }
        beam(top+Map3DPoint(0,0,-0.67),top+Map3DPoint(0,0,0.67),0.055,Self.ek)
        if !far {
            for z: Float in [-0.50,0.50] { beam(top+Map3DPoint(-0.16,0,z),top+Map3DPoint(0.16,0,z),0.034,Self.es) }
            box(x-direction*1.14,3.46,0.33,0.44,0.48,0.47,Self.es)
            for z: Float in [-0.65,0.65] { cylinder(x-direction*1.12,3.46,z,radius:0.10,height:0.43,color:Self.ew,sides:8) }
            beam(Map3DPoint(x-direction*1.12,3.9,-0.65),Map3DPoint(x-direction*1.12,3.9,0.65),0.035,Self.es)
        }
    }
    mutating func emuCar(_ unit: EU,far: Bool) {
        let sides=far ? 12:32,cab=unit.isCab
        emuShell(cab,sides)
        emuRunningGear(unit,far)
        emuDoorsAndWindows(unit,cab,sides,far)
        if cab { emuCab(sides,far,unit == .tail) }
        emuRoof(unit,far)
    }
}
