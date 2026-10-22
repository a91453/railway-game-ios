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
        let isCab = section != .middle
        let cabAtFront = section == .head
        let centre = Map3DPoint(0, 1.6, 0)
        // Six-sided shoulder, flat crown and tapered skirt. The cab end
        // changes x at three heights; it is not a flat plane with trim on it.
        func endX(_ positive: Bool, _ h: Float) -> Float {
            let sign: Float = positive ? 1 : -1
            let driving = isCab && positive == cabAtFront
            if !driving { return sign * 5.42 }
            if h > 3 { return sign * 5.12 }
            if h > 2.6 { return sign * 5.20 }
            if h > 1.2 { return sign * 5.36 }
            return sign * 5.42
        }
        func ring(_ positive: Bool) -> [Map3DPoint] {
            let yz: [(Float, Float)] = [
                (0.28,-1.15),(0.35,-1.29),(2.78,-1.29),
                (3.04,-1.17),(3.18,-0.98),(3.18,0.98),
                (3.04,1.17),(2.78,1.29),(0.35,1.29),(0.28,1.15)
            ]
            return yz.map { h,z in Map3DPoint(endX(positive,h),h,z) }
        }
        let rear = ring(false), front = ring(true)
        for i in 0..<rear.count {
            let j = (i+1)%rear.count
            let color = (i >= 2 && i <= 6) ? white : green
            face([rear[i],rear[j],front[j],front[i]],inside:centre,color:color)
        }
        face(front,inside:centre,color:green)
        face(rear,inside:centre,color:green)
        // Continuous sill and chassis; the tiny wheelsets sit partly within
        // the deep green skirt, as in the side views.
        box(0,0.31,0,10.65,2.05,0.15,ink)
        for axle: Float in [-3.92,3.92] { for side: Float in [-1,1] {
            civicTube(Map3DPoint(axle,0.32,side*0.92),Map3DPoint(axle,0.32,side*1.17),radius:0.32,color:Map3DStreetModel.tyre,sides:14)
            civicTube(Map3DPoint(axle,0.32,side*1.17),Map3DPoint(axle,0.32,side*1.185),radius:0.15,color:steel,sides:10)
        }}
        // White brow continues into the roof shoulder; the slim green rail
        // remains visible along the top of both sides and both cab faces.
        for side: Float in [-1,1] {
            box(0,2.91,side*1.287,10.25,0.025,0.075,green)
            box(0,2.75,side*1.290,10.22,0.021,0.12,white)
            box(0,2.60,side*1.294,10.18,0.016,0.035,green)
            let windows: [(Float,Float)] = section == .middle
                ? [(-4.14,0.80),(0,2.20),(4.14,0.80)]
                : cabAtFront ? [(-4.17,0.78),(0.25,1.90),(3.17,1.15)]
                             : [(-3.17,1.15),(-0.25,1.90),(4.17,0.78)]
            for (x,w) in windows {
                box(x,1.48,side*1.298,w,0.018,1.15,ink)
                box(x,1.53,side*1.308,w-0.07,0.012,1.05,glass)
            }
            let doors: [Float] = section == .middle ? [-2.61,2.61] : [cabAtFront ? -2.36 : 2.36]
            for x in doors {
                box(x,0.34,side*1.300,1.32,0.025,2.21,ink)
                for leaf: Float in [-1,1] {
                    box(x+leaf*0.32,0.37,side*1.319,0.62,0.014,2.15,ink)
                    box(x+leaf*0.32,1.21,side*1.329,0.52,0.008,1.20,glass)
                }
                box(x,0.34,side*1.335,0.025,0.014,2.18,steel)
                box(x,0.28,side*1.327,1.36,0.025,0.06,white)
            }
        }
        if isCab {
            let sign: Float = cabAtFront ? 1 : -1
            func plane(_ h: Float) -> Float { sign * (5.42 - (h-0.28)*0.095) }
            func frontPanel(_ h0: Float,_ h1: Float,_ halfWidth: Float,_ lift: Float,_ color: UInt32) {
                let p = [Map3DPoint(plane(h0)+sign*lift,h0,-halfWidth),Map3DPoint(plane(h0)+sign*lift,h0,halfWidth),Map3DPoint(plane(h1)+sign*lift,h1,halfWidth),Map3DPoint(plane(h1)+sign*lift,h1,-halfWidth)]
                face(p,inside:centre,color:color)
            }
            frontPanel(0.87,2.66,1.07,0.018,white)
            frontPanel(1.12,2.49,0.96,0.030,ink)
            frontPanel(1.25,2.43,0.89,0.041,glass)
            frontPanel(0.53,0.78,1.08,0.036,green)
            for side: Float in [-1,1] {
                box(plane(0.91)+sign*0.055,0.89,side*0.78,0.035,0.27,0.19,white)
            }
            box(plane(0.49)+sign*0.035,0.48,0,0.035,0.65,0.04,ink)
            // A narrow central wiper stays on the glass support plane.
            beam(Map3DPoint(plane(1.29)+sign*0.052,1.29,-0.25),Map3DPoint(plane(1.71)+sign*0.052,1.71,0.20),0.018,ink)
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
