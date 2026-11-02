import Foundation

/// EMU700 study, independent shell. Builder x forward, y up, z right;
/// Model.flat converts once to native +X forward/+Y left/+Z up, metres.
public enum Map3DEMU700 {
    public enum Role: String, CaseIterable, Sendable { case emc, ep, et, em }
    public static func pitch(_ role: Role) -> Float { role == .emc ? 20.743 : 20.3 }
    public static func model(_ role: Role, far: Bool = false, shellOnly: Bool = false) -> Map3DModelPack.Model {
        var r = EMU700Recipe(role: role, far: far)
        r.shell()
        if !shellOnly { r.details() }
        return .flat(named: "tra-emu700-" + role.rawValue + (far ? "-far" : "") + (shellOnly ? "-shell" : ""), from: r.kit.mesh)
    }
}

private struct EMU700Recipe {
    let role: Map3DEMU700.Role
    let far: Bool
    var kit = StationKitBuilder()
    let silver = Map3DColor.rgb(0xC4C9CD)
    let blue = Map3DColor.rgb(0x344B80)
    let orange = Map3DColor.rgb(0xE9AD59)
    let steel = Map3DColor.rgb(0x78828C)
    let dark = Map3DColor.rgb(0x30363D)
    let rubber = Map3DColor.rgb(0x202329)
    let glass = Map3DTrainStyle.glass
    var cab: Bool { role == .emc }
    var end: Float { Map3DEMU700.pitch(role)/2 }
    // Straight 301L shell with rounded shoulders; paint boundaries are real
    // section edges, never an overlay shell. Roof height excludes AC/pantograph.
    let section: [(Float,Float)] = [
        (-1.32,1.12),(-1.4445,1.24),(-1.4445,1.68),(-1.4445,1.76),
        (-1.4445,1.86),(-1.4445,2.02),(-1.4445,3.12),(-1.40,3.36),
        (-1.24,3.56),(-0.9,3.68),(-0.45,3.70),(0.45,3.70),
        (0.9,3.68),(1.24,3.56),(1.40,3.36),(1.4445,3.12),
        (1.4445,2.02),(1.4445,1.86),(1.4445,1.76),(1.4445,1.68),
        (1.4445,1.24),(1.32,1.12)
    ]
    func noseX(_ h: Float,_ w: Float) -> Float {
        // Characteristic projecting lower nose, recessed broad windscreen.
        let points: [(Float,Float)] = [(1.12,0.10),(1.6,0.0),(1.95,0.06),(2.15,0.31),(2.4,0.60),(3.12,0.83),(3.36,0.91),(3.70,1.10)]
        var setback=points.last!.1
        for i in 0..<(points.count-1) where h>=points[i].0 && h<=points[i+1].0 {
            let t=(h-points[i].0)/(points[i+1].0-points[i].0)
            setback=points[i].1+(points[i+1].1-points[i].1)*t
        }
        return end-0.05-setback-0.075*powf(abs(w)/1.4445,2)
    }
    mutating func face(_ p: [Map3DPoint],_ inside: Map3DPoint,_ c: UInt32) {
        let center=p.reduce(.zero,+)*(1/Float(p.count))
        let normal=(p[1]-p[0]).cross(p[2]-p[0])
        kit.mesh.addFacet(normal.dot(center-inside)>0 ? p : Array(p.reversed()),color:c)
    }
    mutating func prism(_ a:[Map3DPoint],_ b:[Map3DPoint],_ c:UInt32) {
        let inside=(a+b).reduce(.zero,+)*(1/Float(a.count+b.count))
        face(a,inside,c);face(b,inside,c)
        for i in a.indices { let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],inside,c) }
    }
    mutating func shellFace(_ original:[Map3DPoint],_ inside:Map3DPoint,_ color:UInt32,_ paintEnds:Bool = false) {
        func clip(_ p:[Map3DPoint],_ f:(Map3DPoint)->Float,_ sign:Float)->[Map3DPoint] {
            var q:[Map3DPoint]=[]
            for i in p.indices {
                let a=p[i],b=p[(i+1)%p.count],da=f(a)*sign,db=f(b)*sign
                if da>=0 {q.append(a)}
                if (da>0 && db<0) || (da<0 && db>0) {q.append(a+(b-a)*(da/(da-db)))}
            }
            return q
        }
        let fields:[(Map3DPoint)->Float]=[{ $0.x-7.0-($0.y-2.02)*1.27 },{ -$0.x-7.0-($0.y-2.02)*1.27 }]
        var polygons=[original]
        for f in fields {polygons=polygons.flatMap { p in [clip(p,f,1),clip(p,f,-1)].filter{$0.count>=3} }}
        for p in polygons {
            let c=p.reduce(.zero,+)*(1/Float(p.count))
            let endBlue=paintEnds && c.y>=2.02 && c.y<3.25 && abs(c.x)>7.0+(c.y-2.02)*1.27
            // Centre fans preserve collinear clipping boundary subdivisions.
            for i in p.indices {
                let tri=[c,p[i],p[(i+1)%p.count]]
                let n=(tri[1]-tri[0]).cross(tri[2]-tri[0])
                if n.dot(n)>1e-12 {face(tri,inside,endBlue ? blue : color)}
            }
        }
    }
    mutating func shell() {
        let hs:[Float]=[1.12,1.24,1.6,1.68,1.76,1.8,1.86,1.95,2.02,2.08,2.15,2.4,2.7,3.12,3.25,3.33,3.36,3.56,3.68,3.70]
        let ws:[Float]=far ? [-1,-0.92,0,0.92,1] : [-1,-0.92,-0.8,-0.62,-0.38,0,0.38,0.62,0.8,0.92,1]
        func width(_ h:Float)->Float {
            if h<=3.12 {return h<1.24 ? 1.32+(h-1.12)/0.12*0.1245 : 1.4445}
            if h<3.36 {return 1.4445-(h-3.12)/0.24*0.0445}
            if h<3.56 {return 1.4-(h-3.36)/0.2*0.16}
            if h<3.68 {return 1.24-(h-3.56)/0.12*0.34}
            return 0.9-(h-3.68)/0.02*0.45
        }
        var ring:[(Float,Float)]=ws.map{($0*width(hs[0]),hs[0])}
        ring += hs.dropFirst().map{(width($0),$0)}
        ring += ws.dropLast().reversed().map{($0*width(hs.last!),hs.last!)}
        ring += hs.dropFirst().dropLast().reversed().map{(-width($0),$0)}
        let front=cab ? end-1.6 : end-0.3
        let a=ring.map{Map3DPoint(-end+0.3,$0.1,$0.0)}
        let b=ring.map{Map3DPoint(front,$0.1,$0.0)}
        let n=ring.map{Map3DPoint(noseX($0.1,$0.0),$0.1,$0.0)}
        // Centre fans preserve every boundary edge, including collinear paint cuts.
        func cap(_ p:[Map3DPoint],_ c:UInt32,_ recipe:inout EMU700Recipe) {
            let center=p.reduce(.zero,+)*(1/Float(p.count))
            for i in p.indices {recipe.shellFace([center,p[i],p[(i+1)%p.count]],.init(0,2.3,0),c)}
        }
        cap(a,silver,&self)
        if !cab {cap(b,silver,&self)}
        for i in ring.indices {
            let j=(i+1)%ring.count,h=(ring[i].1+ring[j].1)/2
            let color:UInt32 = h>=1.68 && h<1.76 ? orange : ((h>=1.86 && h<2.02) || (h>=3.25 && h<3.33) ? blue : silver)
            shellFace([a[i],a[j],b[j],b[i]],.init(0,2.3,0),color,true)
            if cab {shellFace([b[i],b[j],n[j],n[i]],.init(front-0.1,2.3,0),blue)}
        }
        guard cab else{return}
        for i in 0..<(hs.count-1) {for j in 0..<(ws.count-1) {
            let h0=hs[i],h1=hs[i+1],w0=ws[j],w1=ws[j+1]
            let p=[Map3DPoint(noseX(h0,w0*width(h0)),h0,w0*width(h0)),Map3DPoint(noseX(h0,w1*width(h0)),h0,w1*width(h0)),Map3DPoint(noseX(h1,w1*width(h1)),h1,w1*width(h1)),Map3DPoint(noseX(h1,w0*width(h1)),h1,w0*width(h1))]
            let h=(h0+h1)/2,w=abs((w0+w1)/2),smile:Float=1.80+0.28*w*w
            let color:UInt32=h<smile ? blue : (h<2.15 && w<0.93 ? orange : (w>0.93 ? blue : silver))
            shellFace(p,.init(front,2.3,0),color)
        }}
    }
    mutating func sidePanel(_ x:Float,_ h:Float,_ width:Float,_ height:Float,_ sign:Float,_ color:UInt32) {
        kit.box(x,h,sign*1.4505,width,0.012,height,color)
    }
    mutating func roundedSide(_ x:Float,_ h:Float,_ width:Float,_ height:Float,_ sign:Float) {
        if far {
            kit.box(x,h,sign*1.455,width,0.012,height,dark)
            kit.box(x,h+0.045,sign*1.467,width-0.11,0.012,height-0.09,glass)
            return
        }
        let radius:Float=0.10
        var a:[Map3DPoint]=[],b:[Map3DPoint]=[]
        let count=far ? 2 : 4
        for (cx,cy,start) in [(x+width/2-radius,h+radius,Float(-90)),(x+width/2-radius,h+height-radius,Float(0)),(x-width/2+radius,h+height-radius,Float(90)),(x-width/2+radius,h+radius,Float(180))] {
            for k in 0...count {
                let t=(start+Float(k)*90/Float(count))*Float.pi/180
                let xx=cx+radius*cosf(t),yy=cy+radius*sinf(t)
                a.append(.init(xx,yy,sign*1.449));b.append(.init(xx,yy,sign*1.461))
            }
        }
        prism(a,b,dark)
        kit.box(x,h+0.045,sign*1.467,width-0.11,0.012,height-0.09,glass)
    }
    mutating func frontPanel(_ h:Float,_ w:Float,_ width:Float,_ height:Float,_ color:UInt32) {
        let columns=max(1,Int(ceilf(width/(far ? 0.32 : 0.16)))),rows=max(1,Int(ceilf(height/(far ? 0.24 : 0.12))))
        let offset:Float=color == glass ? 0.026 : 0.010
        for i in 0..<rows {for j in 0..<columns {
            let h0=h+height*Float(i)/Float(rows),h1=h+height*Float(i+1)/Float(rows)
            let w0=w-width/2+width*Float(j)/Float(columns),w1=w-width/2+width*Float(j+1)/Float(columns)
            let p=[Map3DPoint(noseX(h0,w0)+offset,h0,w0),.init(noseX(h0,w1)+offset,h0,w1),.init(noseX(h1,w1)+offset,h1,w1),.init(noseX(h1,w0)+offset,h1,w0)]
            prism(p,p.map{$0 + .init(0.016,0,0)},color)
        }}
    }
    mutating func frontOval(_ h:Float,_ w:Float,_ width:Float,_ height:Float,_ color:UInt32) {
        let n=far ? 12 : 24
        let p=(0..<n).map { i -> Map3DPoint in
            let t=Float(i)*2*Float.pi/Float(n),y=h+height/2+height/2*sinf(t),z=w+width/2*cosf(t)
            return .init(noseX(y,z)+0.025,y,z)
        }
        prism(p,p.map{$0 + .init(0.018,0,0)},color)
    }
    mutating func cylinder(_ x:Float,_ y:Float,_ z:Float,radius:Float,height:Float,color:UInt32,sides:Int) {
        let p=(0..<sides).map { i -> Map3DPoint in
            let t=Float(i)*2*Float.pi/Float(sides)
            return .init(x+radius*cosf(t),y,z+radius*sinf(t))
        }
        prism(p,p.map{$0 + .init(0,height,0)},color)
    }
    mutating func wheel(_ x:Float,_ z:Float) {
        let n=far ? 8 : 20
        let a=(0..<n).map { i -> Map3DPoint in let t=Float(i)*2*Float.pi/Float(n);return .init(x+0.43*cosf(t),0.43+0.43*sinf(t),z-0.065) }
        prism(a,a.map {$0 + .init(0,0,0.13)},rubber)
    }
    mutating func endDetails(_ sign:Float,_ junction:Bool) {
        let x=sign*(end-0.29)
        kit.box(x,1.32,0,0.04,0.95,1.75,dark)
        kit.box(x+sign*0.025,1.36,0,0.04,0.74,1.64,steel)
        kit.box(x+sign*0.05,2.28,0,0.025,0.46,0.53,glass)
        for z:Float in [-0.59,0.59] { kit.box(x+sign*0.10,1.26,z,0.20,0.10,1.95,rubber) }
        kit.box(x+sign*0.10,3.11,0,0.20,1.28,0.10,rubber)
        // Central EM-EM interface and ordinary car ends share semi-permanent
        // couplers; additional protected end equipment remains a source gap.
        kit.box(sign*(end-0.12),0.77,0,0.24,junction ? 0.28 : 0.23,0.16,dark)
    }
    mutating func details() {
        kit.box(0,0.98,0,18.9,2.50,0.14,dark)
        for bogie:Float in [-7.15,7.15] {
            for axle:Float in [-1.15,1.15] {
                for sign:Float in [-1,1] {wheel(bogie+axle,sign*0.60)}
                kit.beam(.init(bogie+axle,0.43,-0.62),.init(bogie+axle,0.43,0.62),0.12,steel)
            }
            for sign:Float in [-1,1] {
                kit.beam(.init(bogie-1.3,0.53,sign*0.84),.init(bogie+1.3,0.53,sign*0.84),0.17,dark)
                for xx:Float in [-0.7,0.7] {cylinder(bogie+xx,0.69,sign*0.72,radius:0.19,height:0.17,color:rubber,sides:far ? 4 : 12)}
            }
            kit.beam(.init(bogie,0.59,-0.86),.init(bogie,0.59,0.86),0.2,dark)
        }
        for sign:Float in [-1,1] {
            for door:Float in [-6.4,0,6.4] {
                sidePanel(door,1.184,1.38,2.02,sign,steel)
                for dx:Float in [-0.345,0.345] {
                    sidePanel(door+dx,1.22,0.66,1.94,sign,silver)
                    roundedSide(door+dx,2.20,0.44,0.75,sign)
                }
                sidePanel(door,1.22,0.025,1.92,sign,dark)
            }
            for x:Float in [-8.45,-4.65,-2.55,2.55,4.65,8.45] {
                if cab && x>8 {continue}
                // Toilet-side blind panels are role-specific rather than cab clones.
                if (role == .ep && x > 8) || (role == .et && x < -8 && sign<0) { continue }
                roundedSide(x,2.18,1.55,0.82,sign)
            }
            if role == .ep || (role == .et && sign<0) {
                let x:Float=role == .ep ? 8.45 : -8.45
                let n=far ? 8 : 20
                let p=(0..<n).map { i -> Map3DPoint in
                    let t=Float(i)*2*Float.pi/Float(n)
                    return .init(x+0.18*cosf(t),2.56+0.18*sinf(t),sign*1.449)
                }
                prism(p,p.map{$0 + .init(0,0,sign*0.024)},glass)
            }
            if cab {
                sidePanel(8.45,1.28,0.62,1.95,sign,steel)
                roundedSide(8.45,2.35,0.42,0.67,sign)
            }
            if !far {
                for h:Float in [1.38,1.46,1.54] {sidePanel(-0.8,h,17.2,0.014,sign,steel)}
            }
        }
        endDetails(-1,role == .em)
        if !cab {endDetails(1,false)}
        if cab {
            frontPanel(2.34,0,2.47,0.89,dark)
            frontPanel(2.40,0,2.33,0.76,glass)
            frontOval(3.34,0,0.82,0.29,dark)
            for z:Float in [-0.21,0.21] {frontOval(3.39,z,0.21,0.19,Map3DTrainStyle.headlamp)}
            frontPanel(3.38,0.98,0.48,0.21,dark)
            for z:Float in [-0.95,-0.69,0.69,0.95] {
                frontOval(2.13,z,0.20,0.20,steel)
                frontOval(2.17,z,0.11,0.11,abs(z)>0.9 ? Map3DColor.rgb(0xA54E56) : Map3DTrainStyle.headlamp)
            }
            if !far {
                for z:Float in [-0.66,0.66] {kit.beam(.init(noseX(2.4,z)+0.04,2.4,z),.init(noseX(2.59,z-0.30)+0.04,2.59,z-0.30),0.022,dark)}
            }
            // Normal running position: closed automatic coupler cover. The
            // maintenance/open-coupler state is not claimed by this study.
        }
        let airConditioners:[Float]=role == .ep ? [-6.45,3.40] : [-6.45,6.45]
        for x in airConditioners {
            let p=[Map3DPoint(x-1.55,3.70,-0.92),.init(x+1.55,3.70,-0.92),.init(x+1.32,3.95,-0.92),.init(x-1.32,3.95,-0.92)]
            prism(p,p.map{$0 + .init(0,0,1.84)},steel)
        }
        if role == .ep {
            let x:Float = 8.0
            kit.box(x,3.70,0,1.55,1.3,0.10,dark)
            for z:Float in [-0.48,0.48] {cylinder(x,3.80,z,radius:0.10,height:0.17,color:silver,sides:far ? 4 : 8)}
            for z:Float in (far ? [0] : [-0.35,0.35]) {
                kit.beam(.init(x+0.55,3.97,z),.init(x-0.8,4.43,z),0.065,dark)
                kit.beam(.init(x-0.8,4.43,z),.init(x+0.25,4.95,z),0.045,dark)
            }
            kit.beam(.init(x+0.25,4.95,-0.85),.init(x+0.25,4.95,0.85),0.055,dark)
            kit.box(-1.7,3.70,0,0.9,0.8,0.22,dark)
        }
        // Role equipment volumes are simplified; do not imply a full BOM.
        let boxes:[Float]=role == .et ? [-3.7,-1.6,1.0,3.4] : (role == .ep ? [-3.7,-0.8,2.3] : [-3.6,-1.1,1.5,3.5])
        for x in boxes {kit.box(x,0.48,0,1.35,1.60,0.47,steel)}
    }
}
