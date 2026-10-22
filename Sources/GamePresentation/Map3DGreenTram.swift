import Foundation

/// Static three-section low-floor tram based on the owner's four views.
/// Each section has its own closed shell and common coupler datum. The
/// complete formation is a separate preview model, assembled from those
/// exact sections. Geometry is authored x-forward/y-up/z-right; `flat`
/// converts it once to the native x-forward/y-left/z-up convention.
public enum Map3DGreenTram {
    public static let sectionLength: Float = 10.88
    public static let gap: Float = 0.16
    public static let width: Float = 2.684 // widest door trim, not just shell
    public static let bodyHeight: Float = 3.18
    public static let body = Map3DPalette.crown
    public static let roof = Map3DPalette.tileWhite
    public static let glass = Map3DTrainStyle.glass

    public enum Section: String, CaseIterable, Sendable { case head, middle, tail }

    public static func model(_ section: Section) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.greenTramSection(section)
        return .flat(named: "green-tram-\(section.rawValue)", from: b.mesh)
    }

    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        let pitch = sectionLength + gap
        for (section, position) in [(.head, pitch), (.middle, 0), (.tail, -pitch)] as [(Section, Float)] {
            b.add(model(section), at: Map3DPoint(position, 0, 0))
        }
        return .flat(named: "green-tram-formation", from: b.mesh)
    }
}

extension StationKitBuilder {
    mutating func greenTramSection(_ section: Map3DGreenTram.Section) {
        let white = Map3DGreenTram.roof, green = Map3DGreenTram.body
        let ink = Self.ink, glass = Map3DGreenTram.glass, steel = Self.steel
        let pale = Map3DPalette.park, skirt = Map3DColor.shaded(green, 0.79)
        let isCab = section != .middle
        let cabAtFront = section == .head
        let centre = Map3DPoint(0, 1.6, 0)
        // The cab shoulder narrows in plan as well as rising in side view.
        // A full-width root ring keeps the long straight body; intermediate
        // rings form the distinct, shallow wedge at each driving end.
        func ring(_ x: Float, _ nose: Float = 0) -> [Map3DPoint] {
            let yz: [(Float, Float)] = [
                (0.28,-1.15),(0.35,-1.29),(1.34,-1.29),(2.78,-1.29),
                (3.04,-1.17),(3.18,-0.98),(3.18,0.98),
                (3.04,1.17),(2.78,1.29),(1.34,1.29),(0.35,1.29),(0.28,1.15)
            ]
            return yz.map { h,z in
                let rake = nose * max(0, h-0.35) * 0.125
                let taper = 1 - nose * 0.095
                return Map3DPoint(x - (x >= 0 ? rake : -rake),h,z*taper)
            }
        }
        let cabSign: Float = cabAtFront ? 1 : -1
        let rings: [[Map3DPoint]] = isCab
            ? (cabAtFront ? [ring(-5.42),ring(4.30),ring(4.85,0.35),ring(5.42,1)]
                          : [ring(-5.42,1),ring(-4.85,0.35),ring(-4.30),ring(5.42)])
            : [ring(-5.42),ring(5.42)]
        for k in 0..<(rings.count-1) {
            for i in 0..<rings[k].count {
                let j = (i+1)%rings[k].count
                let color = [2,4,5,6,7,8].contains(i) ? white
                    : (i == 0 || i == 11 ? skirt : green)
                let a = rings[k][i], b = rings[k][j]
                let c = rings[k+1][j], d = rings[k+1][i]
                face([a,b,c],inside:centre,color:color)
                face([a,c,d],inside:centre,color:color)
            }
        }
        face(rings[0],inside:centre,color:green)
        face(rings[rings.count-1],inside:centre,color:green)
        // Continuous sill and chassis; the tiny wheelsets sit partly within
        // the deep green skirt, as in the side views.
        box(0,0.31,0,10.65,2.05,0.15,ink)
        for axle: Float in [-3.92,3.92] { for side: Float in [-1,1] {
            civicTube(Map3DPoint(axle,0.32,side*0.92),Map3DPoint(axle,0.32,side*1.17),radius:0.32,color:Map3DStreetModel.tyre,sides:14)
            civicTube(Map3DPoint(axle,0.32,side*1.17),Map3DPoint(axle,0.32,side*1.185),radius:0.15,color:steel,sides:10)
        }}
        // A light shoulder, calm pale-green window surrounds and darker
        // green sill break up the former uninterrupted slab of saturated
        // green. Every pane is backed by the closed shell.
        for side: Float in [-1,1] {
            box(0,2.91,side*1.287,9.90,0.025,0.075,green)
            box(0,2.75,side*1.290,9.95,0.021,0.12,white)
            box(0,2.57,side*1.294,9.92,0.014,0.035,pale)
            box(0,1.34,side*1.291,9.88,0.014,0.045,pale)
            box(0,0.42,side*1.293,10.0,0.018,0.11,skirt)
            let windows: [(Float,Float)] = section == .middle
                ? [(-4.14,0.80),(0,2.20),(4.14,0.80)]
                : cabAtFront ? [(-4.17,0.78),(0.25,1.90),(3.17,1.15)]
                             : [(-3.17,1.15),(-0.25,1.90),(4.17,0.78)]
            for (x,w) in windows {
                box(x,1.45,side*1.298,w+0.11,0.018,1.25,pale)
                box(x,1.50,side*1.309,w,0.010,1.12,ink)
                box(x,1.53,side*1.317,w-0.055,0.008,1.04,glass)
                box(x,1.92,side*1.323,w-0.08,0.005,0.14,Map3DColor.shaded(glass,1.14))
            }
            let doors: [Float] = section == .middle ? [-2.61,2.61] : [cabAtFront ? -2.36 : 2.36]
            for x in doors {
                box(x,0.34,side*1.300,1.41,0.025,2.27,pale)
                for leaf: Float in [-1,1] {
                    box(x+leaf*0.32,0.37,side*1.319,0.61,0.014,2.13,green)
                    box(x+leaf*0.32,1.21,side*1.329,0.51,0.008,1.18,ink)
                    box(x+leaf*0.32,1.25,side*1.336,0.47,0.006,1.08,glass)
                }
                box(x,0.34,side*1.335,0.020,0.014,2.12,white)
                box(x,0.28,side*1.327,1.36,0.025,0.06,white)
                for leaf: Float in [-1,1] {
                    box(x+leaf*0.60,0.99,side*1.337,0.035,0.012,0.07,Map3DPalette.platformEdge)
                }
            }
        }
        if isCab {
            let sign = cabSign
            func plane(_ h: Float) -> Float { sign * (5.42 - max(0,h-0.35)*0.125) }
            func frontPanel(_ h0: Float,_ h1: Float,_ halfWidth: Float,_ lift: Float,_ color: UInt32) {
                let p = [Map3DPoint(plane(h0)+sign*lift,h0,-halfWidth),Map3DPoint(plane(h0)+sign*lift,h0,halfWidth),Map3DPoint(plane(h1)+sign*lift,h1,halfWidth),Map3DPoint(plane(h1)+sign*lift,h1,-halfWidth)]
                face(p,inside:centre,color:color)
            }
            frontPanel(0.80,2.78,1.08,0.014,white)
            frontPanel(1.02,2.61,0.97,0.025,ink)
            frontPanel(1.10,2.53,0.91,0.037,glass)
            frontPanel(0.64,0.94,1.07,0.032,skirt)
            for side: Float in [-1,1] {
                box(plane(0.88)+sign*0.052,0.86,side*0.77,0.034,0.30,0.17,white)
            }
            box(plane(0.49)+sign*0.035,0.48,0,0.035,0.60,0.04,ink)
            // A narrow central wiper stays on the glass support plane.
            beam(Map3DPoint(plane(1.14)+sign*0.055,1.14,-0.22),Map3DPoint(plane(1.58)+sign*0.055,1.58,0.23),0.018,ink)
        } else {
            // Open-looking but physically closed gangway ends. Middle has
            // neither a cab window nor headlamps.
            for sign: Float in [-1,1] { box(sign*5.43,0.38,0,0.045,2.31,2.55,ink) }
        }
        for x: Float in [-2.72,2.72] {
            box(x,3.18,0,1.38,1.32,0.11,ink)
            for slit: Float in [-0.42,-0.21,0,0.21,0.42] { box(x+slit,3.29,0,0.055,0.91,0.014,steel) }
        }
        box(0,3.18,0,0.67,0.74,0.045,steel)
        if section == .tail {
            // Raised pantograph only on the rear end section, braced at all
            // four feet; roof units remain visible below it.
            box(0.86,3.19,0,0.78,0.90,0.06,ink)
            for side: Float in [-1,1] {
                beam(Map3DPoint(0.58,3.25,side*0.33),Map3DPoint(0.93,3.78,0),0.042,ink)
                beam(Map3DPoint(1.15,3.25,side*0.33),Map3DPoint(0.93,3.78,0),0.042,ink)
            }
            beam(Map3DPoint(0.93,3.78,0),Map3DPoint(1.44,4.09,0),0.048,ink)
            beam(Map3DPoint(1.25,4.09,-0.56),Map3DPoint(1.63,4.09,0.56),0.065,ink)
        }
        // Dark flexible gangway at only the inward end of each cab section.
        if isCab { box(cabAtFront ? -5.46 : 5.46,0.34,0,0.10,2.42,2.64,ink) }
    }
}
