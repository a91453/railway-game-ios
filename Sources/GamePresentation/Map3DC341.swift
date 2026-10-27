import Foundation

/// Independent C341 static study. Unsourced metres are proportional estimates.
/// Native +X front, +Y left, +Z up; rail Z=0. No operating-type binding.
public enum Map3DC341 {
    public enum Unit: String, CaseIterable, Sendable { case dm, t, m, rear }
    public static let body = Map3DPalette.shopAwnings[3]
    public static let accent = Map3DPalette.containers[1]
    public static let lamp = Map3DPalette.tunnelLamp
    public static let mask = Map3DPalette.playerRim
    public static let glass = Map3DColor.shaded(Map3DPalette.glazing, 0.62)
    public static let pitch: Float = 23.5
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        if unit == .rear {
            var b = StationKitBuilder(); b.add(model(.dm), at: .zero, angle: .pi)
            return .flat(named: "c341-rear", from: b.mesh)
        }
        var b = C341Builder(cab: unit == .dm, trailer: unit == .t)
        b.build()
        return .flat(named: "c341-" + unit.rawValue, from: b.kit.mesh)
    }
    public static let arrangement: [Unit] = [.dm, .t, .m, .m, .t, .rear]
    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for (i,u) in arrangement.enumerated() { b.add(model(u), at: Map3DPoint((2.5-Float(i))*pitch,0,0)) }
        return .flat(named: "c341-formation", from: b.mesh)
    }
}

private struct C341Builder {
    let cab: Bool
    let trailer: Bool
    var kit = StationKitBuilder()
    let half: Float = 11.55
    let profile: [(Float,Float)] = [(0.99,-1.43),(1.13,-1.59),(3.16,-1.59),(3.36,-1.53),(3.53,-1.32),(3.62,-0.90),(3.66,0),(3.62,0.90),(3.53,1.32),(3.36,1.53),(3.16,1.59),(1.13,1.59),(0.99,1.43)]
    func ring(_ x: Float) -> [Map3DPoint] {
        profile.map { h,z in
            let end: Float = cab && x > 10.9 ? (x-10.9)/0.65 : 0
            return Map3DPoint(x-end*max(0,h-1.35)*0.055,h,z*(1-end*0.035))
        }
    }
    mutating func solid(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32) {
        let centre = (a+b).reduce(Map3DPoint.zero) { $0+$1*(1/Float(a.count+b.count)) }
        kit.face(a,inside:centre,color:color);kit.face(b,inside:centre,color:color)
        for i in a.indices { let j=(i+1)%a.count;kit.face([a[i],a[j],b[j],b[i]],inside:centre,color:color) }
    }
    mutating func frontPanel(_ z: Float,_ y: Float,_ width: Float,_ height: Float,_ depth: Float,_ color: UInt32,_ offset: Float = 0) {
        func points(_ d: Float) -> [Map3DPoint] {
            let r: Float = color == Map3DC341.glass ? 0.055 : 0
            let outline: [(Float,Float)] = r>0 ? [(y,z-width/2+r),(y,z+width/2-r),(y+r,z+width/2),(y+height-r,z+width/2),(y+height,z+width/2-r),(y+height,z-width/2+r),(y+height-r,z-width/2),(y+r,z-width/2)] : [(y,z-width/2),(y,z+width/2),(y+height,z+width/2),(y+height,z-width/2)]
            return outline.map { h,w in Map3DPoint(half-max(0,h-1.35)*0.055+d,h,w) }
        }
        solid(points(offset),points(offset+depth),color)
    }
    mutating func sidePanel(_ x: Float,_ y: Float,_ width: Float,_ height: Float,_ color: UInt32,_ proud: Float = 0.008) {
        for sign: Float in [-1,1] {
            if color == Map3DC341.glass || color == Map3DC341.mask && height < 1.2 {
                let r: Float = min(0.055,min(width,height)*0.15)
                let points: [(Float,Float)] = [(-width/2+r,0),(width/2-r,0),(width/2,r),(width/2,height-r),(width/2-r,height),(-width/2+r,height),(-width/2,height-r),(-width/2,r)]
                solid(points.map { Map3DPoint(x+$0.0,y+$0.1,sign*1.59) },points.map { Map3DPoint(x+$0.0,y+$0.1,sign*(1.59+proud)) },color)
            } else { kit.box(x,y,sign*(1.59+proud/2),width,proud,height,color) }
        }
    }
    mutating func build() {
        let white=Map3DC341.body,blue=Map3DC341.accent,ink=Map3DC341.mask,glass=Map3DC341.glass
        // Long straight sides, gently rounded roof shoulders, short upright cab.
        let xs: [Float] = [-half,10.9,half]
        let rings=xs.map(ring)
        for i in 0..<2 { for j in profile.indices {
            let k=(j+1)%profile.count,centre=Map3DPoint((xs[i]+xs[i+1])/2,2.25,0)
            kit.face([rings[i][j],rings[i][k],rings[i+1][k],rings[i+1][j]],inside:centre,color:white)
        } }
        kit.face(rings[0],inside:Map3DPoint(0,2.2,0),color:white)
        kit.face(rings[2],inside:Map3DPoint(0,2.2,0),color:white)
        kit.box(0,0.88,0,23.0,2.7,0.11,StationKitBuilder.steel)
        // Waist band below independent passenger glass; doors get their own band segments.
        sidePanel(0,1.44,23.10,0.32,blue,0.006)
        let doors: [Float] = [-8.05,-2.85,2.35,7.55]
        for d in doors {
            sidePanel(d,1.05,1.48,2.10,StationKitBuilder.steel,0.012)
            for leaf: Float in [-1,1] {
                sidePanel(d+leaf*0.365,1.07,0.714,2.06,white,0.020)
                sidePanel(d+leaf*0.365,1.44,0.714,0.32,blue,0.027)
                sidePanel(d+leaf*0.365,2.18,0.34,0.73,ink,0.029)
                sidePanel(d+leaf*0.365,2.205,0.29,0.68,glass,0.036)
            }
        }
        // Three pairs of broad independent windows, plus distinct end windows.
        for x: Float in [-6.25,-4.65,-1.05,0.55,4.15,5.75,-10.05] {
            sidePanel(x,2.12,1.40,0.91,ink,0.012)
            sidePanel(x,2.15,1.34,0.85,glass,0.020)
        }
        if !cab { sidePanel(9.85,2.12,1.50,0.91,ink,0.012);sidePanel(9.85,2.15,1.44,0.85,glass,0.020) }
        else {
            sidePanel(9.6,1.10,0.55,2.04,StationKitBuilder.steel,0.014)
            sidePanel(9.6,2.28,0.32,0.67,glass,0.022)
            sidePanel(10.45,2.03,0.66,1.10,ink,0.014)
            sidePanel(10.45,2.07,0.60,1.02,glass,0.022)
        }
        // Bogies: two two-axle frames, eight wheels with exact rail contacts.
        for bx: Float in [-7.8,7.8] {
            kit.box(bx,0.57,0,3.3,2.05,0.25,StationKitBuilder.steel)
            kit.box(bx,0.82,0,1.5,1.6,0.07,ink)
            for dx: Float in [-1.05,1.05] {
                kit.beam(Map3DPoint(bx+dx,0.42,-0.82),Map3DPoint(bx+dx,0.42,0.82),0.14,StationKitBuilder.steel)
                for sign: Float in [-1,1] {
                    kit.civicTube(Map3DPoint(bx+dx,0.42,sign*0.66),Map3DPoint(bx+dx,0.42,sign*0.84),radius:0.42,color:Map3DStreetModel.tyre,sides:12)
                    kit.civicTube(Map3DPoint(bx+dx,0.42,sign*0.84),Map3DPoint(bx+dx,0.42,sign*0.86),radius:0.20,color:StationKitBuilder.steel,sides:8)
                }
            }
        }
        // Equipment is deliberately schematic; trailer differs from motor underfloor.
        for x: Float in trailer ? [-3.8,0,3.8] : [-4.4,-1.4,1.8,4.5] { kit.box(x,0.52,0,2.2,1.8,0.36,StationKitBuilder.steel) }
        for x: Float in [-5.6,5.6] {
            kit.box(x,3.66,0,4.1,1.65,0.04,StationKitBuilder.steel)
            for dx: Float in [-1.4,-0.7,0,0.7,1.4] { kit.box(x+dx,3.70,0,0.045,1.5,0.012,ink) }
        }
        for sign: Float in [-1,1] where !cab || sign<0 {
            kit.box(sign*11.64,1.18,0,0.18,1.70,1.85,ink)
            kit.box(sign*11.72,1.22,0,0.035,1.60,1.77,StationKitBuilder.steel)
            kit.box(sign*11.70,0.65,0,0.30,0.32,0.20,ink)
        }
        if cab {
            // Rounded, crowned front mask follows the roof shoulder instead of a rectangle.
            let outline: [(Float,Float)] = [(-1.44,1.98),(1.44,1.98),(1.44,3.30),(1.34,3.43),(0.90,3.53),(0,3.57),(-0.90,3.53),(-1.34,3.43),(-1.44,3.30)]
            let maskRings = [Float(0),Float(0.012)].map { d in outline.map { z,h in Map3DPoint(half-max(0,h-1.35)*0.055+d,h,z) } }
            solid(maskRings[0],maskRings[1],ink)
            // Central escape door separates two distinct driving windows.
            frontPanel(0,1.06,0.75,2.30,0.022,ink,0.014)
            frontPanel(0,1.08,0.70,2.25,0.012,white,0.037)
            frontPanel(0,2.00,0.70,1.33,0.012,ink,0.050)
            frontPanel(0,1.44,2.99,0.32,0.012,blue,0.050)
            for s: Float in [-1,1] {
                frontPanel(s*0.94,2.04,0.80,1.04,0.008,glass,0.026)
                frontPanel(s*0.94,3.17,0.78,0.17,0.008,StationKitBuilder.steel,0.026)
                frontPanel(s*0.94,3.20,0.69,0.07,0.004,s<0 ? Map3DPalette.tunnelLamp : blue,0.035)
                let marker = (0..<12).map { i -> (Float,Float) in
                    let a=Float(i)*2*Float.pi/12
                    return (3.40+0.045*sinf(a),s*1.20+0.045*cosf(a))
                }
                let markerRings=[Float(0.012),Float(0.025)].map { d in marker.map { h,w in Map3DPoint(half-(h-1.35)*0.055+d,h,w) } }
                solid(markerRings[0],markerRings[1],Map3DPalette.tunnelLamp)
                frontPanel(s*0.95,1.46,0.70,0.28,0.022,ink,0.066)
                for dz: Float in [-0.18,0.18] {
                    let z=s*0.95+dz
                    let points = (0..<12).map { i -> (Float,Float) in
                        let a=Float(i)*2*Float.pi/12
                        return (1.60+0.105*sinf(a),z+0.105*cosf(a))
                    }
                    let rings = [Float(0.088),Float(0.101)].map { d in points.map { h,w in Map3DPoint(half-max(0,h-1.35)*0.055+d,h,w) } }
                    solid(rings[0],rings[1],dz*s<0 ? Map3DPalette.tunnelLamp : StationKitBuilder.steel)
                }
                kit.beam(Map3DPoint(11.53,2.02,s*0.95),Map3DPoint(11.49,2.49,s*0.79),0.026,ink)
            }
            frontPanel(0,0.60,2.78,0.42,0.03,ink)
            kit.box(11.65,0.64,0,0.24,0.36,0.20,ink)
            kit.box(11.53,0.70,0,0.28,0.40,0.12,StationKitBuilder.steel)
        }
    }
}
