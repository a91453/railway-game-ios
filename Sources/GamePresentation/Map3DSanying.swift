import Foundation

/// New Taipei Sanying Line's two-car, third-rail metro as a static study.
/// The published 17.7 × 2.6 × 3.8 m car envelope anchors the proportions;
/// positions of smaller fittings are visual estimates from the cited photos.
public enum Map3DSanying {
    public enum Unit: String, CaseIterable, Sendable { case a, b }
    public static func id(_ unit: Unit, far: Bool = false) -> String {
        "sanying-\(unit.rawValue)\(far ? "-far" : "")"
    }
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model {
        var builder = SanyingBuilder(unit: unit, far: far)
        builder.build()
        return .flat(named: id(unit, far: far), from: builder.k.mesh)
    }
}

private struct SanyingBuilder {
    let unit: Map3DSanying.Unit
    let far: Bool
    var k = StationKitBuilder()
    let white = Map3DPalette.concreteWalls[2]
    let roof = Map3DPalette.concreteWalls[0]
    let blue = Map3DColor.rgb(0x13A9CF)
    let pale = Map3DColor.rgb(0x7DCFE3)
    let dark = Map3DColor.rgb(0x323C45)
    let glass = Map3DColor.shaded(Map3DPalette.glazing, 0.62)
    let steel = Map3DColor.rgb(0x626B70)

    mutating func face(_ points: [Map3DPoint], _ inside: Map3DPoint, _ color: UInt32) {
        if points.count == 4 {
            k.face([points[0], points[1], points[2]], inside: inside, color: color)
            k.face([points[0], points[2], points[3]], inside: inside, color: color)
        } else { k.face(points, inside: inside, color: color) }
    }
    mutating func solid(_ points: [Map3DPoint], _ delta: Map3DPoint, _ color: UInt32) {
        let other = points.map { $0 + delta }
        let centre = (points + other).reduce(Map3DPoint.zero,+) * (1 / Float(points.count * 2))
        for i in 1..<(points.count-1) {
            face([points[0],points[i],points[i+1]],centre,color)
            face([other[0],other[i],other[i+1]],centre,color)
        }
        for i in points.indices {
            let j=(i+1)%points.count
            face([points[i],points[j],other[j],other[i]],centre,color)
        }
    }
    mutating func panel(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ side: Float, _ offset: Float, _ color: UInt32) {
        let z = side * offset
        solid([.init(x0,y0,z),.init(x1,y0,z),.init(x1,y1,z),.init(x0,y1,z)],
              .init(0,0,side*0.012),color)
    }
    mutating func nose() {
        // Eight-sided cross sections taper in plan and profile. The front
        // ring is appreciably narrower than the passenger compartment.
        let rear: [(Float,Float)] = [(1.00,-1.12),(1.00,1.12),(1.30,1.30),(3.24,1.30),(3.53,1.08),(3.53,-1.08),(3.24,-1.30),(1.30,-1.30)]
        let tip: [(Float,Float)] = [(0.90,-0.84),(0.90,0.84),(1.32,1.06),(3.13,1.06),(3.43,0.82),(3.43,-0.82),(3.13,-1.06),(1.32,-1.06)]
        let a = rear.map { Map3DPoint(7.37,$0.0,$0.1) }
        let b = tip.map { Map3DPoint(8.64,$0.0,$0.1) }
        for i in a.indices {
            let j = (i+1) % a.count
            let c: UInt32 = (i == 2 || i == 4) ? blue : (i == 3 ? roof : (i == 0 ? dark : white))
            face([a[i],a[j],b[j],b[i]],.init(7.1,2.1,0),c)
        }
        face(a,.init(7.8,2.1,0),white)
        face(b,.init(7.5,2.1,0),blue)
        // Sloped panoramic windscreen and thin silver band are backed by
        // the solid cab end; there is no unsupported floating glass.
        let wind: [Map3DPoint] = [
            .init(8.67,1.79,-0.78),.init(8.67,1.79,0.78),
            .init(8.67,3.22,0.82),.init(8.67,3.22,-0.82)]
        solid(wind,.init(0.012,0,0),glass)
        let band: [Map3DPoint] = [
            .init(8.71,1.74,-0.88),.init(8.71,1.74,0.88),
            .init(8.71,1.84,0.91),.init(8.71,1.84,-0.91)]
        solid(band,.init(0.012,0,0),roof)
        for side: Float in [-1,1] {
            let z = side * 0.82
            k.box(8.58,1.52,z,0.18,0.30,0.13,roof)
            k.box(8.69,1.53,z,0.06,0.20,0.075,Map3DPalette.tunnelLamp)
            panel(6.88,7.68,1.64,3.07,side,1.311,glass)
        }
        k.box(8.54,1.03,0,0.30,1.95,0.43,dark)
        k.box(8.83,0.74,0,0.40,0.55,0.23,steel)
    }
    mutating func build() {
        // Central closed body. The flat-sided envelope makes three equally
        // spaced double doors visible on each side.
        k.box(-0.58,0.94,0,15.9,2.58,2.55,white)
        k.box(-0.58,3.53,0,15.9,2.38,0.14,roof)
        k.box(-0.58,0.90,0,15.9,2.45,0.12,dark)
        nose()
        for side: Float in [-1,1] {
            // Window ribbon remains behind individual door and window panes.
            panel(-8.20,6.60,2.16,3.15,side,1.299,dark)
            panel(-8.20,6.55,1.44,1.79,side,1.302,blue)
            panel(-8.20,6.55,3.18,3.25,side,1.302,pale)
            for x: Float in [-5.86,-0.74,4.38] {
                panel(x-0.78,x+0.78,1.08,3.13,side,1.308,white)
                for leaf: Float in far ? [0] : [-1,1] {
                    let halfWidth: Float = far ? 0.62 : 0.32
                    panel(x+leaf*0.38-halfWidth,x+leaf*0.38+halfWidth,2.10,3.04,side,1.319,glass)
                }
                if !far { k.box(x,1.08,side*1.33,0.025,0.012,2.05,dark) }
            }
            let windows: [(Float,Float)] = [(-7.94,-6.80),(-4.95,-3.42),(-3.30,-1.70),
                                           (0.16,1.66),(1.79,3.42),(5.25,6.40)]
            if !far { for (lo,hi) in windows { panel(lo,hi,2.22,3.10,side,1.316,glass) } }
            // A broad turquoise wave at the cab end, following the lower skirt.
            solid([.init(4.90,1.08,side*1.307),.init(6.86,1.08,side*1.307),
                  .init(7.40,1.58,side*1.29),.init(5.40,1.78,side*1.307)],
                 .init(0,0,side*0.012),blue)
            if !far {
                for x: Float in [-7.65,-2.15,2.85] {
                    k.box(x,1.64,side*1.34,0.08,0.03,0.11,Map3DPalette.lantern)
                }
            }
        }
        // Two roof HVAC banks with direct feet to the roof; third-rail car
        // has no pantograph. Underbody collector shoes sit near the bogies.
        for x: Float in [-4.38,2.95] {
            k.box(x,3.60,0,3.48,1.66,0.18,roof)
            if !far {
                for dx: Float in [-1.30,1.30] { k.box(x+dx,3.57,0,0.16,1.40,0.19,steel) }
                for i in 0..<6 { k.box(x-1.22+Float(i)*0.48,3.755,0,0.045,1.22,0.012,steel) }
            }
        }
        k.box(-0.60,0.56,0,4.10,1.68,0.52,steel)
        for bx: Float in [-5.63,5.54] {
            k.box(bx,0.64,0,2.60,1.38,0.26,dark)
            for dx: Float in [-0.90,0.90] {
                for side: Float in [-1,1] {
                    // Cylinder's axis follows the builder's vertical axis;
                    // a closed polygonal wheel is instead extruded sideways.
                    let n = far ? 8 : 16
                    let ring = (0..<n).map { i -> Map3DPoint in
                        let t=Float(i)*2*Float.pi/Float(n)
                        return .init(bx+dx+0.37*cosf(t),0.37+0.37*sinf(t),side*0.68)
                    }
                    solid(ring,.init(0,0,side*0.16),dark)
                }
            }
            for side: Float in [-1,1] {
                k.box(bx,0.52,side*1.05,0.50,0.24,0.16,roof)
                k.box(bx,0.32,side*1.22,0.44,0.18,0.11,dark)
            }
        }
        // Half of the flexible gangway belongs to each car.
        k.box(-8.58,1.05,0,0.28,2.10,2.00,dark)
        if far { k.box(-8.73,1.05,0,0.305,2.10,2.00,dark) }
        if !far {
            for i in 0..<4 { k.box(-8.72-Float(i)*0.05,1.05,0,0.025,2.15,2.03,roof) }
        }
    }
}
