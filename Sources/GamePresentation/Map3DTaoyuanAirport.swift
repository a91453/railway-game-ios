import Foundation

/// Airport MRT studies. Metres; native +X is the cab end of a driving unit.
/// No timetable or operating fleet substitution. See the source contract.
public enum Map3DTaoyuanAirport {
    public enum Role: String, CaseIterable, Sendable {
        case dmc1, mc1, mc2, dmc2, dme1, me1, me3, me4, dmb
        var cab: Bool { [.dmc1,.dmc2,.dme1,.dmb].contains(self) }
        var commuter: Bool { [.dmc1,.mc1,.mc2,.dmc2].contains(self) }
        public var pitch: Float { cab ? 20.78 : 20.25 }
    }
    public static func model(_ role: Role, far: Bool = false, shellOnly: Bool = false) -> Map3DModelPack.Model {
        var r = AirportRecipe(role: role, far: far)
        r.build(details: !shellOnly)
        return .flat(named: "taoyuan-airport-" + role.rawValue + (far ? "-far" : "") + (shellOnly ? "-shell" : ""), from: r.kit.mesh)
    }
}

private struct AirportRecipe {
    let role: Map3DTaoyuanAirport.Role
    let far: Bool
    var kit = StationKitBuilder()
    let silver = Map3DColor.rgb(0xC4C9CD)
    let roof = Map3DColor.rgb(0xADB5BC)
    let dark = Map3DColor.rgb(0x343C46)
    let glass = Map3DTrainStyle.glass
    let blue = Map3DColor.rgb(0x5478C8)
    let purple = Map3DColor.rgb(0x9B73AC)
    var paint: UInt32 { role.commuter ? blue : purple }
    var half: Float { role.pitch / 2 }
    // Original photo-fit section; only overall dimensions are official.
    var section: [(Float,Float)] { [(-1.40,1.02),(-1.515,1.18),(-1.515,1.53),(-1.515,1.88),(-1.515,3.08),(-1.50,3.25),(-1.39,3.48),(-1.14,3.65),(-0.70,3.763),(0.70,3.763),(1.14,3.65),(1.39,3.48),(1.50,3.25),(1.515,3.08),(1.515,1.88),(1.515,1.53),(1.515,1.18),(1.40,1.02)] }
    mutating func face(_ points: [Map3DPoint], inside: Map3DPoint, color: UInt32) {
        var n = Map3DPoint.zero
        for i in 1..<(points.count-1) { n = n + (points[i]-points[0]).cross(points[i+1]-points[0]) }
        let c = points.reduce(.zero,+)*(1/Float(points.count))
        kit.mesh.addFacet(n.dot(c-inside)>0 ? points : Array(points.reversed()), color:color)
    }
    mutating func prism(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32) {
        let c = (a+b).reduce(.zero,+)*(1/Float(a.count+b.count))
        face(a,inside:c,color:color);face(b,inside:c,color:color)
        for i in a.indices { let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],inside:c,color:color) }
    }
    func front(_ height: Float, _ lateral: Float) -> Float {
        half - 0.28 - max(0,height-1.50)*0.15 - pow(abs(lateral)/1.515,4)*0.20
    }
    mutating func body() {
        let a=section.map { Map3DPoint(-half+0.20,$0.1,$0.0) }
        let b=section.map { Map3DPoint(role.cab ? front($0.1,$0.0) : half-0.20,$0.1,$0.0) }
        let center=Map3DPoint(0,2,0)
        face(a,inside:center,color:silver)
        // Cap and sides form one shell. Main paint boundaries are shell edges.
        if !role.cab { face(b,inside:center,color:silver) }
        for i in section.indices {
            let j=(i+1)%section.count
            let h=(section[i].1+section[j].1)/2
            let c: UInt32 = h>3.60 ? roof : (h>=1.53 && h<1.88 ? paint : (h>=3.08 && h<3.25 ? purple : silver))
            if role.cab {
                let pi=Map3DPoint(half-1.90,section[i].1,section[i].0)
                let pj=Map3DPoint(half-1.90,section[j].1,section[j].0)
                face([a[i],a[j],pj,pi],inside:center,color:c)
                face([pi,pj,b[j],b[i]],inside:center,color:(h>1.88 && h<3.60) ? paint : c)
            } else {
                face([a[i],a[j],b[j],b[i]],inside:center,color:c)
            }
        }
        if role.cab {
            // Front cap triangulated through original section centre; the
            // individual front panes below follow this same front surface.
            let c=Map3DPoint(front(2.25,0),2.25,0)
            for i in section.indices { let j=(i+1)%section.count;face([c,b[i],b[j]],inside:center,color:(section[i].1+section[j].1)/2<1.9 ? silver : paint) }
        }
    }
    mutating func frontPanel(_ y0:Float,_ y1:Float,_ z0:Float,_ z1:Float,_ color:UInt32) {
        let radius:Float = min(0.075,min(y1-y0,z1-z0)*0.25)
        let q:[(Float,Float)] = [(y0,z0+radius),(y0,z1-radius),(y0+radius,z1),(y1-radius,z1),(y1,z1-radius),(y1,z0+radius),(y1-radius,z0),(y0+radius,z0)]
        frontShape(q,color)
    }
    mutating func frontShape(_ polygon:[(Float,Float)],_ color:UInt32) {
        let origin=(Float(2.25),Float(0))
        func cross(_ a:(Float,Float),_ b:(Float,Float),_ c:(Float,Float)) -> Float {
            (b.0-a.0)*(c.1-a.1)-(b.1-a.1)*(c.0-a.0)
        }
        for i in section.indices {
            let j=(i+1)%section.count
            let t=[origin,(section[i].1,section[i].0),(section[j].1,section[j].0)]
            let sign:Float=cross(t[0],t[1],t[2])>0 ? 1 : -1
            var q=polygon
            for k in 0..<3 {
                var out:[(Float,Float)]=[]
                for m in q.indices {
                    let a=q[m],b=q[(m+1)%q.count]
                    let da=sign*cross(t[k],t[(k+1)%3],a),db=sign*cross(t[k],t[(k+1)%3],b)
                    if da>=0 { out.append(a) }
                    if (da>=0) != (db>=0) { let f=da/(da-db);out.append((a.0+f*(b.0-a.0),a.1+f*(b.1-a.1))) }
                }
                q=out
            }
            if q.count<3 { continue }
            let area=cross(t[0],t[1],t[2])
            func point(_ v:(Float,Float),_ d:Float) -> Map3DPoint {
                let a=cross(v,t[1],t[2])/area,b=cross(t[0],v,t[2])/area,c=1-a-b
                return Map3DPoint(a*front(t[0].0,t[0].1)+b*front(t[1].0,t[1].1)+c*front(t[2].0,t[2].1)+d,v.0,v.1)
            }
            let lift:Float = color == glass ? 0.024 : (color == Map3DTrainStyle.headlamp ? 0.030 : 0.012)
            prism(q.map { point($0,lift) },q.map { point($0,-0.025) },color)
        }
    }
    mutating func build(details: Bool) {
        body()
        guard details else { return }
        kit.box(0,0.92,0,role.pitch-0.6,2.50,0.10,dark)
        // Passenger roof HVAC versus baggage's cab-only HVAC.
        let ac: [Float] = role == .dmb ? [8.05] : [-6.25,6.25]
        for x in ac {
            let length:Float = role == .dmb ? 1.8 : 3.35
            kit.box(x,3.763,0,length,1.35,0.17,roof)
            if !far { for dx:Float in [-0.50,0,0.50] { kit.box(x+dx,3.933,0,0.32,1.05,0.012,dark) } }
        }
        for x:Float in [-6.75,6.75] {
            kit.box(x,0.51,0,3.25,1.10,0.29,dark)
            kit.box(x,0.80,0,1.1,0.9,0.12,dark)
            for dx:Float in [-1.05,1.05] {
                kit.beam(Map3DPoint(x+dx,0.425,-0.78),Map3DPoint(x+dx,0.425,0.78),0.12,dark)
                for side:Float in [-1,1] {
                    let count=far ? 8 : 20
                    let a=(0..<count).map { i -> Map3DPoint in let t=Float(i)*2*Float.pi/Float(count);return Map3DPoint(x+dx+cosf(t)*0.425,0.425+sinf(t)*0.425,side*0.7675-0.05) }
                    prism(a,a.map { $0+Map3DPoint(0,0,0.10) },dark)
                    if !far {
                        kit.box(x+dx,0.35,side*1.0,0.31,0.16,0.16,roof)
                        let hub=(0..<20).map { i -> Map3DPoint in
                            let t=Float(i)*2*Float.pi/20
                            return Map3DPoint(x+dx+cosf(t)*0.22,0.425+sinf(t)*0.22,side*0.83)
                        }
                        prism(hub,hub.map { $0+Map3DPoint(0,0,side*0.04) },roof)
                        kit.cylinder(x+dx,0.68,side*0.53,radius:0.14,height:0.23,color:roof,sides:16)
                    }
                }
            }
            for side:Float in [-1,1] { kit.box(x,0.28,side*1.12,0.70,0.50,0.09,dark) }
        }
        let compressor = ![Map3DTaoyuanAirport.Role.dmc1,.dmc2,.dme1,.dmb,.me3].contains(role)
        for x:Float in compressor ? [-3.3,0,3.2] : [-3.5,0.5] {
            kit.box(x,0.46,compressor ? 0.17 : -0.17,2.25,1.65,0.46,dark)
            if !far { for dx:Float in [-0.7,-0.35,0,0.35,0.7] { kit.box(x+dx,0.60,-1.01,0.035,0.02,0.23,roof) } }
        }
        for side:Float in [-1,1] {
            if role == .dmb {
                // Five solid baggage loading doors: no passenger windows.
                for x:Float in [-7.15,-3.85,-0.55,2.75,6.05] {
                    kit.box(x,1.16,side*1.52,2.30,0.025,0.37,silver)
                    kit.box(x,1.88,side*1.52,2.30,0.025,1.18,silver)
                    // Paint is integrated in door pieces, rather than a cover strip.
                    kit.box(x,1.53,side*1.52,2.30,0.025,0.35,paint)
                    if !far { kit.box(x,1.16,side*1.535,0.025,0.018,1.90,dark) }
                }
            } else {
                let doors:[Float] = [-6.20,0,6.20]
                for x in doors {
                    // Two supported silver leaves, window and narrow seam.
                    for dx:Float in [-0.38,0.38] {
                        kit.box(x+dx,1.14,side*1.522,0.75,0.024,0.39,silver)
                        kit.box(x+dx,1.88,side*1.522,0.75,0.024,1.22,silver)
                        kit.box(x+dx,1.53,side*1.522,0.75,0.024,0.35,paint)
                        kit.box(x+dx,2.16,side*1.54,0.43,0.018,0.69,glass)
                    }
                    if !far { kit.box(x,1.14,side*1.535,0.018,0.012,1.96,dark) }
                }
                let windows:[Float] = [-8.35,-4.10,-2.10,2.10,4.10,8.25]
                for x in windows where !(role.cab && x>7.5) {
                    kit.box(x,2.10,side*1.521,role.commuter ? 1.40 : 1.25,0.024,0.78,glass)
                }
            }
            if role.cab {
                kit.box(8.45,1.16,side*1.52,0.72,0.025,1.93,silver)
                kit.box(8.45,2.19,side*1.54,0.42,0.022,0.68,glass)
            }
        }
        if role.cab {
            frontPanel(2.02,3.22,-1.20,-0.57,glass)
            frontPanel(2.02,3.22,0.57,1.20,glass)
            frontPanel(1.95,2.70,-0.18,0.18,glass)
            frontPanel(3.26,3.46,-0.34,0.34,dark)
            for side:Float in [-1,1] {
                frontPanel(1.48,1.86,side<0 ? -1.17 : 0.70,side<0 ? -0.70 : 1.17,dark)
                for z:Float in [0.82,1.04] {
                    let count=far ? 8 : 16
                    let circle=(0..<count).map { i -> (Float,Float) in
                        let a=Float(i)*2*Float.pi/Float(count)
                        return (1.63+0.065*sinf(a),side*z+0.065*cosf(a))
                    }
                    frontShape(circle,Map3DTrainStyle.headlamp)
                }
            }
            kit.box(half-0.28,0.68,0,0.56,0.36,0.27,dark)
            kit.box(half-0.75,0.88,0,0.60,0.48,0.15,dark)
        }
        let ends:[Float] = role.cab ? [-1] : [-1,1]
        for end in ends {
            kit.box(end*(half-0.12),1.10,0,0.24,1.55,2.15,dark)
            if !far { for dx:Float in [-0.07,0,0.07] { kit.box(end*(half-0.12)+dx,1.10,0,0.018,1.58,2.15,roof) } }
            kit.box(end*(half-0.20),0.72,0,0.40,0.25,0.18,dark)
        }
    }
}
