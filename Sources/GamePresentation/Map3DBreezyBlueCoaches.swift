import Foundation

/// Breezy Blue's restored non-air-conditioned passenger-car families.
/// New shells, door/window stations and TR31/TR35/TR40 interpretations;
/// not recoloured Chu-Kuang, PP, blue-seven or the legacy BLUE coach.
/// Native metres: +X is the chosen lavatory end, +Y left looking toward +X,
/// +Z up, rail Z=0. Official end numbers and a dated fleet's car directions
/// remain unverified. 20 m is the published maximum length; the +/-10 m
/// coupling faces are an explicit display contract, not an engineering datum.
public enum Map3DBreezyBlueCoaches {
    public enum Role: String, CaseIterable, Sendable {
        case mixed, exhibition, longSeat = "long-seat", rotatingSeat = "rotating-seat"
        public var identifier: String { "tra-breezy-blue-coach-" + rawValue }
        public var family: String {
            switch self {
            case .mixed: return "40TPK32200"
            case .exhibition, .longSeat: return "35TP32850"
            case .rotatingSeat: return "35SPK32700"
            }
        }
        public var height: Float { self == .longSeat || self == .exhibition ? 3.963 : 3.953 }
    }
    public static let length: Float = 20
    public static let width: Float = 2.865
    public static let blue = Map3DColor.rgb(0x315B6B)
    public static let white = Map3DColor.rgb(0xE9EBE5)
    public static let roof = Map3DColor.rgb(0x9B9C96)
    public static let frame = Map3DColor.rgb(0xAFB7B5)
    public static let dark = Map3DColor.rgb(0x30383B)
    public static let steel = Map3DColor.rgb(0x626B6B)
    public static let bogieCentres: [Float] = [-6.75, 6.75]
    public static let axleOffsets: [Float] = [-1.05, 1.05]
    public static let wheelRadius: Float = 0.43

    public static func model(_ role: Role, far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.breezyCoach(role, far: far)
        return .flat(named: role.identifier + (far ? "-far" : ""), from: b.mesh)
    }

    /// Photo-recorded rhythms; not a surveyed dimensional drawing. A TP/SPK
    /// lavatory pane is opaque, a TPK additionally has a conductor end pane.
    public static func windowStations(_ role: Role) -> [Float] {
        if role == .rotatingSeat { return (0..<16).map { -7.65 + Float($0) * 1.02 } }
        return [-8.75, -7.15, -6.30, -5.45, -3.35, -2.45, -1.55, -0.65,
                 0.25, 1.15, 2.05, 2.95, 5.55, 6.40, 7.25, 8.75]
    }
    public static func doorStations(_ role: Role) -> [Float] {
        role == .rotatingSeat ? [-8.92, 8.92] : [-4.36, 4.36]
    }
}

extension StationKitBuilder {
    // Fan caps preserve collinear paint-boundary stations in the closed shell.
    private mutating func bbFace(_ p: [Map3DPoint], inside: Map3DPoint, color: UInt32) {
        let c = p.reduce(.zero, +) * (1 / Float(p.count))
        for i in p.indices {
            let j = (i + 1) % p.count
            if (p[i]-c).cross(p[j]-c).length > 0.00000001 {
                face([c,p[i],p[j]], inside: inside, color: color)
            }
        }
    }
    private mutating func bbPrism(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32) {
        let c = (a+b).reduce(.zero, +) * (1 / Float(a.count+b.count))
        bbFace(a, inside: c, color: color); bbFace(b, inside: c, color: color)
        for i in a.indices {
            let j = (i+1) % a.count
            bbFace([a[i],a[j],b[j],b[i]], inside: c, color: color)
        }
    }
    private func bbRounded(_ x: Float, _ h: Float, _ w: Float, _ height: Float, _ r: Float, far: Bool) -> [Map3DPoint] {
        var p: [Map3DPoint] = []
        let count = far ? 1 : 4
        for (cx,cy,a) in [(x+w/2-r,h+height/2-r,Float(0)),
                          (x-w/2+r,h+height/2-r,Float.pi/2),
                          (x-w/2+r,h-height/2+r,Float.pi),
                          (x+w/2-r,h-height/2+r,Float.pi*1.5)] {
            for i in 0...count {
                let t = a + Float(i)*Float.pi/(2*Float(count))
                p.append(Map3DPoint(cx+cosf(t)*r,cy+sinf(t)*r,0))
            }
        }
        return p
    }
    private mutating func bbWindow(_ x: Float, _ h: Float, side: Float, width: Float, height: Float,
                                   frosted: Bool = false, far: Bool) {
        let border = bbRounded(x,h,width+0.055,height+0.055,0.055,far:far)
        let pane = bbRounded(x,h,width,height,0.045,far:far)
        bbPrism(border.map { Map3DPoint($0.x,$0.y,side*1.399) },
                border.map { Map3DPoint($0.x,$0.y,side*1.423) },Map3DBreezyBlueCoaches.frame)
        bbPrism(pane.map { Map3DPoint($0.x,$0.y,side*1.421) },
                pane.map { Map3DPoint($0.x,$0.y,side*1.4325) },
                frosted ? Map3DColor.rgb(0xB4C5C5) : Map3DTrainStyle.glass)
        if !far && !frosted {
            // Real upper sash divider: attached to the window frame, not a
            // continuous dark window band or a replacement body skin.
            box(x,h+0.18,side*1.430,width,0.005,0.018,Map3DBreezyBlueCoaches.frame)
        }
    }
    fileprivate mutating func breezyCoach(_ role: Map3DBreezyBlueCoaches.Role, far: Bool) {
        let blue=Map3DBreezyBlueCoaches.blue,white=Map3DBreezyBlueCoaches.white
        let roof=Map3DBreezyBlueCoaches.roof,dark=Map3DBreezyBlueCoaches.dark
        let steel=Map3DBreezyBlueCoaches.steel
        let half: Float = 9.65
        let shoulder: Float = role == .mixed ? 3.19 : 3.14
        let crown: Float = 3.75
        let roofSteps = far ? 6 : 12
        // Own section: ICF's tucked-in lower side is independent of the
        // Japanese TP/SPK straight lower side. White line is a shell band.
        let bottomHalf: Float = role == .mixed ? 1.29 : 1.40
        var section: [(Float,Float)] = [(-bottomHalf,1.12),(bottomHalf,1.12),
            (1.40,1.39),(1.40,2.06),(1.40,2.18),(1.40,shoulder)]
        for i in 1..<roofSteps {
            let a=Float(i)*Float.pi/Float(roofSteps)
            section.append((1.40*cosf(a),shoulder+(crown-shoulder)*sinf(a)))
        }
        section += [(-1.40,shoulder),(-1.40,2.18),(-1.40,2.06),(-1.40,1.39)]
        let a=section.map {Map3DPoint(-half,$0.1,$0.0)},b=section.map {Map3DPoint(half,$0.1,$0.0)}
        let inside=Map3DPoint(0,2.4,0)
        for i in section.indices {
            let j=(i+1)%section.count
            let color: UInt32
            if i==3 || i==section.count-3 { color=white }
            else if i>=5 && i<5+roofSteps { color=roof }
            else { color=blue }
            bbFace([a[i],a[j],b[j],b[i]],inside:inside,color:color)
        }
        // End section is subdivided at identical side levels. Caps close each
        // paint strip and the curved roof without a T junction.
        for end:Float in [-1,1] {
            let x=end*half
            for (lo,hi,c): (Float,Float,UInt32) in [(1.12,1.39,blue),(1.39,2.06,blue),(2.06,2.18,white),(2.18,shoulder,blue)] {
                let wl:Float=lo<1.2 ? bottomHalf:1.4
                bbFace([Map3DPoint(x,lo,-wl),Map3DPoint(x,lo,wl),Map3DPoint(x,hi,1.4),Map3DPoint(x,hi,-1.4)],inside:inside,color:c)
            }
            let ring=(end<0 ? a:b)
            bbFace(Array(ring[5...5+roofSteps]),inside:inside,color:roof)
        }
        box(0,0.98,0,19.15,2.52,0.15,dark)
        for side:Float in [-1,1] {
            let windows=Map3DBreezyBlueCoaches.windowStations(role)
            for (i,x) in windows.enumerated() {
                let frosted = (side<0 && i==windows.count-1) || (side>0 && i==0)
                let conductor=role == .mixed && ((side<0 && i==0) || (side>0 && i==windows.count-1))
                bbWindow(x,2.64,side:side,width:role == .rotatingSeat ? 0.73 : 0.69,
                         height:conductor ? 0.52:0.64,frosted:frosted,far:far)
            }
            for x in Map3DBreezyBlueCoaches.doorStations(role) {
                let w:Float=role == .rotatingSeat ? 0.65:1.28
                box(x,0.87,side*1.411,w+0.07,0.022,2.19,dark)
                box(x,0.90,side*1.425,w,0.008,2.12,blue)
                if role == .rotatingSeat {
                    bbWindow(x,2.64,side:side,width:0.35,height:0.75,far:far)
                } else {
                    for dx:Float in [-0.30,0.30] { bbWindow(x+dx,2.64,side:side,width:0.26,height:0.71,far:far) }
                    box(x,0.91,side*1.431,0.018,0.003,2.08,dark)
                }
                // The white waist crosses the door at the same height.
                box(x,2.06,side*1.430,w,0.004,0.12,white)
                box(x,0.91,side*1.32,w+0.03,0.22,0.055,steel)
                box(x,0.70,side*1.33,w-0.05,0.205,0.055,steel)
                if !far {
                    for dx:Float in [-1,1] { beam(Map3DPoint(x+dx*(w/2+0.025),0.76,side*1.38),Map3DPoint(x+dx*(w/2+0.025),1.18,side*1.38),0.027,steel) }
                }
            }
            if !far { box(0,2.21,side*1.407,0.73,0.012,0.13,dark) }
        }
        for end:Float in [-1,1] {
            // Attached end door and deep diaphragm; no cab, headlights or
            // pantograph. Rear markers are lenses on the real end sides.
            box(end*9.666,1.15,0,0.032,0.82,2.03,dark)
            box(end*9.689,1.19,0,0.026,0.73,1.94,blue)
            box(end*9.709,2.39,0,0.018,0.43,0.57,Map3DTrainStyle.glass)
            let folds=far ? 2:5
            for i in 0..<folds {
                let x=end*(9.67+(Float(i)+0.5)*0.23/Float(folds))
                for z:Float in [-0.52,0.52] { box(x,1.13,z,0.23/Float(folds),0.09,2.12,dark) }
                box(x,3.18,0,0.23/Float(folds),1.13,0.075,dark)
                box(x,1.13,0,0.23/Float(folds),1.13,0.075,dark)
            }
            box(end*9.78,0.83,0,0.36,0.27,0.22,dark)
            box(end*9.96,0.83,0,0.08,0.40,0.22,steel)
            for side:Float in [-1,1] {
                box(end*9.67,1.53,side*1.22,0.07,0.16,0.16,steel)
                box(end*9.715,1.56,side*1.22,0.022,0.10,0.10,Map3DColor.rgb(0x9D413A))
            }
        }
        // Roof boxes sit on the curved crown. SPK: nine equal small vents;
        // TP/TPK: larger vents over both double doors and centre.
        for i in 0..<9 {
            let x:Float = -8.2+Float(i)*2.05
            let large=role != .rotatingSeat && [2,4,6].contains(i)
            let l:Float=large ? 0.88:0.47,w:Float=large ? 0.61:0.40
            box(x,3.735,0,l,w,role.height-3.735,roof)
            if !far {
                box(x,role.height-0.030,0,l-0.08,w+0.006,0.018,dark)
                for dx:Float in [-0.3,0,0.3] { box(x+dx*l,role.height-0.014,0,0.025,w+0.009,0.014,roof) }
            }
        }
        // Two two-axle bogies. Stations/radius are photo estimates; no survey
        // of TR31/35/40 centres or spring rates is claimed.
        for centre in Map3DBreezyBlueCoaches.bogieCentres {
            box(centre,0.83,0,3.15,1.80,0.19,dark)
            for dx in Map3DBreezyBlueCoaches.axleOffsets {
                civicTube(Map3DPoint(centre+dx,0.43,-0.72),Map3DPoint(centre+dx,0.43,0.72),radius:0.075,color:steel,sides:far ? 6:10)
                for side:Float in [-1,1] {
                    civicTube(Map3DPoint(centre+dx,0.43,side*0.50),Map3DPoint(centre+dx,0.43,side*0.68),radius:0.43,color:dark,sides:far ? 8:20)
                    box(centre+dx,0.33,side*0.99,0.37,0.23,0.27,steel)
                    if role == .mixed {
                        // ICF TR40: coil/axlebox towers and short side frame.
                        box(centre+dx,0.58,side*0.99,0.32,0.20,0.20,dark)
                    } else if !far {
                        beam(Map3DPoint(centre+dx-0.30,0.72,side*0.99),Map3DPoint(centre+dx,0.51,side*0.99),0.075,steel)
                        beam(Map3DPoint(centre+dx,0.51,side*0.99),Map3DPoint(centre+dx+0.30,0.72,side*0.99),0.075,steel)
                    }
                }
            }
            for side:Float in [-1,1] {
                box(centre,0.63,side*0.99,2.92,0.14,0.17,dark)
                box(centre,0.54,side*0.99,0.70,0.19,0.26,steel)
                if !far { for dx:Float in [-0.18,0,0.18] {box(centre+dx,0.60,side*1.095,0.055,0.018,0.14,dark)} }
            }
        }
        // Underframe equipment is intentionally asymmetric. Restored SPK and
        // TPK have vacuum waste tanks; preserved TP toilets were not rebuilt
        // to that layout. No air-conditioning unit is added to any role.
        box(-3.0,0.42,-0.68,2.05,0.81,0.54,dark)
        box(0.2,0.43,0.68,1.65,0.78,0.53,dark)
        box(3.2,0.52,-0.62,1.45,0.88,0.44,steel)
        if role == .mixed || role == .rotatingSeat {
            box(4.82,0.40,0.56,1.25,0.92,0.55,steel)
            box(-4.5,0.51,-0.49,1.15,0.84,0.44,steel)
        } else {
            box(4.5,0.45,-0.55,1.20,0.78,0.51,dark)
        }
        civicTube(Map3DPoint(1.45,0.71,-0.73),Map3DPoint(2.55,0.71,-0.73),radius:0.18,color:dark,sides:far ? 8:16)
        // Axle generator, hanging from the rear bogie. Simplified housing,
        // preserving which end contains the equipment rather than mirroring it.
        box(-7.65,0.50,-0.50,0.47,0.52,0.39,steel)
    }
}
