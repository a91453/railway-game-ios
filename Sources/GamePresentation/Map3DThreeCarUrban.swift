import Foundation

/// Reference-proportioned three-car urban rail set. Static art library only.
/// Authoring axes: x forward, y up, z right. Model.flat converts exactly once.
public enum Map3DThreeCarUrban {
    public enum Unit: String, CaseIterable, Sendable { case leading, middle, trailing }
    public static let bodyLength: Float = 15
    public static let pitch: Float = 15.28
    public static let green = Map3DPalette.containers[2] // soft game green; accent rather than whole-body paint
    public static let white = Map3DPalette.tileWhite
    public static let glass = Map3DTrainStyle.glass

    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.threeCarUrban(unit)
        return .flat(named: "urban-three-\(unit.rawValue)", from: b.mesh)
    }
    public static func formation() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        for (unit, x) in [(Unit.leading, pitch), (.middle, Float(0)), (.trailing, -pitch)] {
            b.add(model(unit), at: Map3DPoint(x, 0, 0))
        }
        return .flat(named: "urban-three-formation", from: b.mesh)
    }
}

extension StationKitBuilder {
    mutating func threeCarUrban(_ unit: Map3DThreeCarUrban.Unit) {
        let green = Map3DThreeCarUrban.green, white = Map3DThreeCarUrban.white
        let glass = Map3DThreeCarUrban.glass, ink = Self.ink, steel = Self.steel
        let darkGreen = Map3DColor.shaded(green, 0.72)
        let cab: Float = unit == .leading ? 1 : unit == .trailing ? -1 : 0
        let inside = Map3DPoint(0, 1.95, 0)
        // A chamfered, almost rectangular section: no rounded commuter roof
        // or tram body is reused. The short cab rake is built into the rings.
        let section: [(Float, Float)] = [
            (0.66,-1.17),(0.79,-1.325),(3.10,-1.325),(3.34,-1.12),
            (3.34,1.12),(3.10,1.325),(0.79,1.325),(0.66,1.17)
        ]
        func ring(_ x: Float) -> [Map3DPoint] {
            section.map { h, z in
                let isCab = cab != 0 && x * cab > 7
                return Map3DPoint(x - (isCab ? cab * max(0,h-0.79)*0.065 : 0), h,
                                  z * (isCab ? 0.97 : 1))
            }
        }
        let rings = [-Float(7.5),-6.95,6.95,7.5].map(ring)
        for k in 0..<3 {
            for i in section.indices {
                let j = (i+1)%section.count
                let color = i == 7 ? steel : ([0,2,4,6].contains(i) ? green : white)
                face([rings[k][i],rings[k][j],rings[k+1][j]],inside:inside,color:color)
                face([rings[k][i],rings[k+1][j],rings[k+1][i]],inside:inside,color:color)
            }
        }
        face(rings[0],inside:inside,color:white)
        face(rings[3],inside:inside,color:white)
        box(0,0.59,0,14.65,2.19,0.18,ink)
        // Two conventional bogies, each with two continuous supported axles.
        for centre: Float in [-4.98,4.98] {
            box(centre,0.42,0,2.65,2.12,0.24,ink)
            for offset: Float in [-0.84,0.84] {
                let x = centre + offset
                civicTube(Map3DPoint(x,0.34,-1.20),Map3DPoint(x,0.34,1.20),radius:0.085,color:steel,sides:8)
                for side: Float in [-1,1] {
                    civicTube(Map3DPoint(x,0.34,side*1.02),Map3DPoint(x,0.34,side*1.20),radius:0.34,color:Map3DStreetModel.tyre,sides:12)
                    civicTube(Map3DPoint(x,0.34,side*1.20),Map3DPoint(x,0.34,side*1.212),radius:0.19,color:steel,sides:10)
                }
            }
            for side: Float in [-1,1] { box(centre,0.37,side*1.19,2.34,0.07,0.16,ink) }
        }
        // Suspended cabinets meet the closed floor; no floating underside boxes.
        for x: Float in [-1.55,1.55] { box(x,0.34,0,2.25,1.86,0.27,steel) }
        for side: Float in [-1,1] {
            box(0,0.69,side*1.267,14.60,0.10,0.13,steel)
            box(0,1.13,side*1.326,13.92,0.008,0.075,darkGreen)
            // Thin window surrounds and fully supported opaque matte glass.
            // Four main bays between/around the two doors.
            for (x,w): (Float,Float) in [(-5.44,2.28),(-1.27,2.40),(1.27,2.40),(5.44,2.28)] {
                let nearCab = cab != 0 && x*cab > 5
                let width: Float = nearCab ? 1.88 : w
                let centre = nearCab ? x-cab*0.20 : x
                box(centre,1.82,side*1.329,width+0.12,0.012,1.04,ink)
                box(centre,1.88,side*1.338,width,0.008,0.92,glass)
                box(centre,2.67,side*1.343,width*0.85,0.002,0.065,Map3DColor.shaded(Map3DPalette.glazing,0.45))
            }
            if cab != 0 {
                box(cab*6.70,1.82,side*1.329,0.65,0.012,1.04,ink)
                box(cab*6.70,1.88,side*1.338,0.55,0.008,0.92,glass)
                box(cab*6.70,2.67,side*1.343,0.44,0.002,0.065,Map3DColor.shaded(Map3DPalette.glazing,0.45))
                box(cab*6.26,0.85,side*1.334,0.016,0.01,2.09,steel)
            }
            for x: Float in [-3.44,3.44] {
                box(x,0.81,side*1.329,1.58,0.018,2.09,ink)
                for leaf: Float in [-1,1] {
                    box(x+leaf*0.384,0.84,side*1.343,0.737,0.012,2.01,Map3DPalette.tankSteel)
                    box(x+leaf*0.384,1.95,side*1.352,0.51,0.009,0.79,ink)
                    box(x+leaf*0.384,2.00,side*1.360,0.43,0.006,0.69,glass)
                    box(x+leaf*0.384,2.59,side*1.364,0.35,0.002,0.05,Map3DColor.shaded(Map3DPalette.glazing,0.45))
                    box(x+leaf*0.09,1.38,side*1.360,0.025,0.014,0.23,white)
                }
                box(x,0.80,side*1.349,1.62,0.12,0.045,white)
                box(x+0.91,1.70,side*1.334,0.055,0.012,0.075,Map3DPalette.platformEdge)
            }
        }
        // Both inner faces have a gangway. Middle unit has two, no cab gear.
        for sign: Float in [-1,1] where sign != cab {
            box(sign*7.51,0.79,0,0.10,1.94,2.27,ink)
            for step: Float in [0,1,2] {
                box(sign*(7.55+step*0.025),0.83,0,0.045,1.67,2.17,Map3DColor.shaded(steel,0.53+step*0.04))
            }
            box(sign*7.58,0.44,0,0.12,0.38,0.21,ink)
        }
        if cab != 0 {
            func frontX(_ h: Float,_ lift: Float) -> Float { cab*(7.5-max(0,h-0.79)*0.065+lift) }
            func plate(_ outline: [(Float,Float)],_ lift: Float,_ color: UInt32) {
                let front=outline.map { Map3DPoint(frontX($0.0,lift),$0.0,$0.1) }
                let back=outline.map { Map3DPoint(frontX($0.0,-0.002),$0.0,$0.1) }
                let centre=(front+back).reduce(Map3DPoint.zero) { $0+$1*(1/Float(front.count+back.count)) }
                face(front,inside:centre,color:color);face(back,inside:centre,color:color)
                for i in front.indices { let j=(i+1)%front.count
                    face([front[i],front[j],back[j],back[i]],inside:centre,color:color)
                }
            }
            func panel(_ h0: Float,_ h1: Float,_ z0: Float,_ z1: Float,_ lift: Float,_ color: UInt32) {
                plate([(h0,z0),(h0,z1),(h1,z1),(h1,z0)],lift,color)
            }
            // Convex clipped corners keep the single tall windscreen distinct.
            func clippedPanel(_ bottom: Float,_ top: Float,_ half: Float,_ cut: Float,_ lift: Float,_ color: UInt32) {
                let points: [(Float,Float)] = [(bottom,-half+cut),(bottom,half-cut),(bottom+cut,half),
                    (top-cut,half),(top,half-cut),(top,-half+cut),(top-cut,-half),(bottom+cut,-half)]
                plate(points,lift,color)
            }
            clippedPanel(0.96,3.14,1.13,0.16,0.012,green)
            clippedPanel(1.04,3.07,0.96,0.12,0.022,ink)
            clippedPanel(1.39,2.91,0.77,0.06,0.033,glass)
            panel(2.70,2.81,-0.66,0.66,0.035,Map3DColor.shaded(Map3DPalette.glazing,0.45))
            // An attached wiper follows the same sloping windscreen plane.
            beam(Map3DPoint(frontX(1.48,0.047),1.48,-0.59),Map3DPoint(frontX(2.16,0.047),2.16,0.25),0.025,ink)
            beam(Map3DPoint(frontX(1.98,0.049),1.98,0.20),Map3DPoint(frontX(2.46,0.049),2.46,0.34),0.027,ink)
            for side: Float in [-1,1] {
                panel(1.18,1.76,side*1.02-0.045,side*1.02+0.045,0.029,white)
                panel(1.09,1.15,side*1.02-0.034,side*1.02+0.034,0.029,Map3DPalette.templeRidge)
            }
            panel(0.74,0.93,-0.64,0.64,0.021,ink)
            box(cab*7.63,0.41,0,0.26,0.58,0.25,ink)
            box(cab*7.77,0.46,0,0.07,0.29,0.12,steel)
        }
        // Roof package: one shallow tapered HVAC housing plus two vents.
        let hvacBottom = [Map3DPoint(-1.44,3.34,-0.72),Map3DPoint(1.44,3.34,-0.72),
                          Map3DPoint(1.44,3.34,0.72),Map3DPoint(-1.44,3.34,0.72)]
        let hvacTop = [Map3DPoint(-1.32,3.59,-0.64),Map3DPoint(1.32,3.59,-0.64),
                       Map3DPoint(1.32,3.59,0.64),Map3DPoint(-1.32,3.59,0.64)]
        let hc = Map3DPoint(0,3.45,0)
        face(hvacBottom,inside:hc,color:steel);face(hvacTop,inside:hc,color:steel)
        for i in 0..<4 { let j=(i+1)%4;face([hvacBottom[i],hvacBottom[j],hvacTop[j],hvacTop[i]],inside:hc,color:steel) }
        cylinder(-0.56,3.591,0,radius:0.38,height:0.008,color:ink,sides:12)
        cylinder(-0.56,3.600,0,radius:0.23,height:0.006,color:steel,sides:10)
        for x: Float in [0.23,0.38,0.53,0.68,0.83,0.98] { box(x,3.592,0,0.045,0.84,0.008,ink) }
        for x: Float in [-5.53,5.53] {
            box(x,3.34,0,1.15,0.71,0.028,steel)
            for dx: Float in [-0.42,-0.28,-0.14,0,0.14,0.28,0.42] { box(x+dx,3.368,0,0.035,0.55,0.006,ink) }
        }
    }
}
