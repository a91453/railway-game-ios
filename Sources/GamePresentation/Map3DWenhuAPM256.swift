import Foundation

/// Independent APM256 static study. Native metres; +X is the role's X end.
/// Prototype role/orientation conflicts and photo-fit dimensions: docs/art/wenhu.
public enum Map3DWenhuAPM256 {
    public enum Role: String, CaseIterable, Sendable { case a, b }
    public static func model(_ role: Role, far: Bool = false, shellOnly: Bool = false) -> Map3DModelPack.Model {
        var r = APM256Recipe(role: role, far: far)
        r.body()
        if !shellOnly { r.details() }
        return .flat(named: "wenhu-apm256-" + role.rawValue + (far ? "-far" : ""), from: r.m.kit.mesh)
    }
}

private struct APM256Recipe {
    let role: Map3DWenhuAPM256.Role
    let far: Bool
    var m = WenhuMesh()
    let white = Map3DPalette.tileWhite
    let glass = Map3DTrainStyle.glass
    let grey = Map3DPalette.tankStand
    let rubber = Map3DColor.rgb(0x24292E)
    let blue = Map3DColor.rgb(0x397BAD)
    let green = Map3DColor.rgb(0x468D63)
    let windowBand = Map3DColor.rgb(0xA8B1C1)
    let section: [(Float,Float)] = [(-1.10,0.86),(-1.27,1.06),(-1.27,2.98),(-1.24,3.15),(-1.12,3.30),(-0.85,3.38),(0.85,3.38),(1.12,3.30),(1.24,3.15),(1.27,2.98),(1.27,1.06),(1.10,0.86)]
    func endX(_ h: Float, _ w: Float) -> Float {
        let hs: [Float] = [0.86,1.06,1.50,1.90,2.60,3.38]
        let xs: [Float] = [6.10,6.35,6.44,6.39,6.29,6.14]
        var x=xs.last!
        for i in 0..<(hs.count-1) where h<=hs[i+1] {
            let t=max(0,(h-hs[i])/(hs[i+1]-hs[i]));x=xs[i]+t*(xs[i+1]-xs[i]);break
        }
        return x - powf(abs(w)/1.27,4)*0.32
    }
    func paint(_ h: Float) -> UInt32 {
        h < 1.02 ? rubber : (h < 1.42 ? blue : (h < 1.47 ? white : (h < 1.52 ? green : (h > 1.80 && h < 2.98 ? windowBand : white))))
    }
    func frontPaint(_ h: Float) -> UInt32 { h<1.02 ? rubber : (h<1.42 ? blue:(h<1.47 ? white:(h<1.52 ? green:white))) }
    mutating func body() {
        // Explicit rings include colour levels: paint changes cut the shell itself.
        var sec: [(Float,Float)] = []
        let levels: [Float] = far ? [0.86,0.88,1.02,1.06,1.18,1.35,1.40,1.50,1.85,1.90,2.45,2.60,1.42,1.47,1.52,1.55,1.80,1.90,2.02,2.98,3.02,3.03,3.08,3.15,3.20,3.30,3.38] : [0.86,0.88,1.02,1.06,1.18,1.35,1.40,1.50,1.85,1.90,2.45,2.60,1.42,1.47,1.52,1.55,1.80,1.90,2.02,2.35,2.38,2.75,2.80,2.98,3.02,3.03,3.08,3.15,3.20,3.30,3.38]
        let sortedLevels=Array(Set(levels)).sorted()
        let ws: [Float] = far ? [-1.28,-0.99,0,0.99,1.28] : [-1.28,-1.27,-1.20,-1.12,-0.99,-0.85,-0.5,0,0.5,0.85,0.99,1.12,1.20,1.27,1.28]
        for i in section.indices {
            let a=section[i],b=section[(i+1)%section.count]
            var cuts: [(Float,Float)] = [(0,a.1)]
            for h in sortedLevels.filter({ $0 > min(a.1,b.1) && $0 < max(a.1,b.1) }).sorted(by: { a.1<b.1 ? $0<$1 : $0>$1 }) {
                cuts.append(((h-a.1)/(b.1-a.1),h))
            }
            for w in ws where w > min(a.0,b.0) && w < max(a.0,b.0) {
                let t=(w-a.0)/(b.0-a.0)
                cuts.append((t,a.1+(b.1-a.1)*t))
            }
            var last: Float = -1
            for (t,h) in cuts.sorted(by: { $0.0<$1.0 }) where t-last>0.000001 {
                sec.append((a.0+(b.0-a.0)*t,h));last=t
            }
        }
        let stations: [Float] = [-1,-0.92,0.92,1]
        func point(_ i: Int,_ t: Float) -> Map3DPoint {
            let (w,h)=sec[i]
            let x=abs(t)==1 ? endX(h,w)*(t<0 ? -1:1) : t*6.0
            return Map3DPoint(x,h,w)
        }
        for k in 0..<(stations.count-1) {
            for i in sec.indices {
                let j=(i+1)%sec.count
                let h=(sec[i].1+sec[j].1)/2
                m.kit.face([point(i,stations[k]),point(j,stations[k]),point(j,stations[k+1]),point(i,stations[k+1])],inside:Map3DPoint(0,2,0),color:paint(h))
            }
        }
        for t: Float in [-1,1] {
            // Front face uses the same cut levels and subdivided cross-section.
            let contour=section.map { Map3DPoint(0,$0.1,$0.0) }
            let hs = sortedLevels
            for i in 0..<(hs.count-1) { for j in 0..<(ws.count-1) {
                var poly=m.clip(contour,axis:0,level:hs[i],above:true)
                poly=m.clip(poly,axis:0,level:hs[i+1],above:false)
                poly=m.clip(poly,axis:1,level:ws[j],above:true)
                poly=m.clip(poly,axis:1,level:ws[j+1],above:false)
                poly=poly.map { Map3DPoint(signX(t,$0.y,$0.z),$0.y,$0.z) }
                if poly.count>=3 { m.kit.face(poly,inside:Map3DPoint(0,2,0),color:frontPaint((hs[i]+hs[i+1])/2)) }
            } }
        }
    }
    func signX(_ t: Float,_ h: Float,_ w: Float) -> Float { t*endX(h,w) }
    mutating func details() {
        // Four load tyres on two single-axle assemblies, not steel-wheel bogies.
        for x: Float in [-4.65,4.65] {
            m.kit.box(x,0.35,0,0.55,1.88,0.24,grey)
            for side: Float in [-1,1] {
                m.wheel(x,0.40,side*0.94,radius:0.40,width:0.26,horizontal:false,color:rubber,sides:far ? 8:24)
                if !far { m.wheel(x,0.40,side*1.075,radius:0.16,width:0.025,horizontal:false,color:grey,sides:12) }
                for dx: Float in [-0.48,0.48] {
                    m.wheel(x+dx,0.31,side*1.02,radius:0.20,width:0.15,horizontal:true,color:rubber,sides:far ? 8:16)
                }
                // Hidden safety/turnout detail remains a declared source gap.
                m.kit.box(x-0.6,0.26,side*1.13,0.36,0.16,0.10,grey)
            }
        }
        m.kit.box(0,0.60,0,6.4,1.35,0.25,rubber)
        for side: Float in [-1,1] {
            for x: Float in [-3.10,3.10] {
                // Two outside-hung double doors per side; each leaf has its own glass.
                let cuts: [Float] = [1.01,1.42,1.47,1.52,1.55,1.80,2.927]
                for k in 0..<(cuts.count-1) {
                    let lo=cuts[k],hi=cuts[k+1]
                    m.kit.box(x,lo,side*1.278,2.10,0.020,hi-lo,paint((lo+hi)/2))
                }
                for dx: Float in [-0.525,0.525] {
                    m.sidePane(x+dx,1.68,side,1.297,0.77,1.10,glass,segments:far ? 1:4)
                }
                m.kit.box(x,1.02,side*1.31,0.025,0.015,1.89,rubber)
                if !far {
                    m.kit.box(x+1.12,1.75,side*1.28,0.09,0.028,0.12,Map3DColor.rgb(0xB84447))
                }
            }
            for (x,len) in [(Float(-5.08),Float(1.20)),(-0.85,1.45),(0.85,1.45),(5.08,1.20)] {
                m.sidePane(x,1.79,side,1.279,len+0.07,1.15,rubber,segments:far ? 1:4)
                m.sidePane(x,1.83,side,1.297,len,1.07,glass,segments:far ? 1:4)
            }
        }
        for sign: Float in [-1,1] {
            // Thin solid glazing follows the final nose at every height/width cell.
            let low: Float = 1.98,high: Float = 3.12,half: Float = 0.98,radius: Float = 0.12
            var contour: [Map3DPoint] = []
            for (h,w,start) in [(high-radius,half-radius,Float(0)),(high-radius,-half+radius,Float.pi*0.5),(low+radius,-half+radius,Float.pi),(low+radius,half-radius,Float.pi*1.5)] {
                for i in 0...4 {
                    let angle=start+Float(i)*Float.pi/8
                    contour.append(Map3DPoint(0,h+sinf(angle)*radius,w+cosf(angle)*radius))
                }
            }
            let heights: [Float] = [low,2.35,2.38,2.45,2.60,2.75,2.80,2.98,3.02,3.03,3.08,high]
            let widths: [Float] = far ? [-half,-0.99,0,0.99,half].sorted() : [-half,-0.99,-0.85,-0.5,0,0.5,0.85,0.99,half].sorted()
            for i in 0..<(widths.count-1) where widths[i+1]-widths[i]>0.00001 { for j in 0..<(heights.count-1) {
                var poly=m.clip(contour,axis:0,level:heights[j],above:true)
                poly=m.clip(poly,axis:0,level:heights[j+1],above:false)
                poly=m.clip(poly,axis:1,level:widths[i],above:true)
                poly=m.clip(poly,axis:1,level:widths[i+1],above:false)
                poly=poly.map { Map3DPoint(sign*(endX($0.y,$0.z)+0.006),$0.y,$0.z) }
                if poly.count>=3 { m.prism(poly,offset:Map3DPoint(sign*0.015,0,0),color:glass) }
            } }
            // Outer AX (A) and BY (B) have automatic heads; AY/BX are semi-permanent.
            let outer = (role == .a && sign>0) || (role == .b && sign<0)
            m.kit.box(sign*6.58,0.73,0,0.62,outer ? 0.52:0.26,outer ? 0.29:0.20,grey)
            if outer {
                for side: Float in [-1,1] {
                    let h: Float = 1.76
                    let w: Float = 0.59*side
                    let radius: Float = 0.085
                    let ring=(0..<(far ? 8:20)).map { n -> Map3DPoint in
                        let angle=Float(n)*2*Float.pi/Float(far ? 8:20)
                        let z=w+sinf(angle)*radius,y=h+cosf(angle)*radius
                        return Map3DPoint(sign*(endX(y,z)+0.01),y,z)
                    }
                    m.prism(ring,offset:Map3DPoint(sign*0.025,0,0),color:Map3DTrainStyle.headlamp)
                    let marker=ring.map { p -> Map3DPoint in
                        let z=p.z-side*0.23
                        return Map3DPoint(sign*(endX(p.y,z)+0.01),p.y,z)
                    }
                    m.prism(marker,offset:Map3DPoint(sign*0.025,0,0),color:Map3DColor.rgb(0xB84447))
                }
                m.kit.box(sign*5.55,0.12,0,0.10,2.05,0.09,grey)
            }
        }
        // Roof housings: photo-fit section, two per car, neither a pantograph nor generic boxes.
        for x: Float in [-4.1,4.1] {
            let base: Float = 3.38
            m.prism([Map3DPoint(x-1.225,base,-0.81),Map3DPoint(x-1.225,base+0.15,-0.65),Map3DPoint(x-1.225,base+0.15,0.65),Map3DPoint(x-1.225,base,0.81)],offset:Map3DPoint(2.45,0,0),color:white)
            if !far { for dx in stride(from:Float(-0.85),through:0.85,by:0.17) { m.kit.box(x+dx,base+0.152,0,0.045,1.2,0.008,grey) } }
        }
        if role == .b { for x: Float in [-1.0,0,1.0] { m.kit.box(x,3.38,0,0.22,0.22,0.15,grey) } }
    }
}
