import Foundation

/// Decision 531: the Alishan Forest Railway's mountain train (`ALISHAN`,
/// decision 515), the DL-38 diesel locomotive and the Alishan coaches
/// (`alicoach`) behind it.
///
/// Colours are the reference's garage models'
/// (`Railway/taiwan-rail-reference-clean/source/rail-3d/assets/garage-blender-v1/`
/// `dl38.json` and `alicoach.json`, their `specification`): the locomotive
/// red #B83230 with a cream #E9E1CF line, the coach cream #E6D7B0 with a red
/// #AD333A window band, the shared roof, chassis and frame greys (the
/// frame a touch more neutral, ``frame``). Their
/// shapes follow those models (a cab at one end and a long hood with
/// louvres, a cream line and a V on its radiator; the coach's big windows
/// on a red band, a door at each end, a flush roof), but not their
/// lengths, which the reference drew short ("Q proportions"). No published
/// drawing gives either vehicle's dimensions, so they are estimates for
/// the 762 mm gauge: the coach 13.0 m over couplers (`ALISHAN`'s
/// `carMetres`), 2.2 m wide and 3.0 m high (the reference's `W` and `H`),
/// the locomotive 8.9 m, 2.15 m wide and 3.05 m high. Metres, +x the front
/// (the locomotive's radiator, either end of the coach), +y left, z up.
public enum Map3DAlishan {
    public static let ids = ["afr-dl38", "afr-dl38-far", "afr-alicoach", "afr-alicoach-far"]
    public static let red = Map3DColor.rgb(0xB83230)
    public static let cream = Map3DColor.rgb(0xE9E1CF)
    public static let coachCream = Map3DColor.rgb(0xE6D7B0)
    public static let coachRed = Map3DColor.rgb(0xAD333A)
    public static let roof = Map3DColor.rgb(0xB5BFC0)
    public static let metal = Map3DColor.rgb(0x97A6AB)
    public static let chassis = Map3DColor.rgb(0x34424A)
    /// The reference's frame #18232A a touch more neutral: that blue-black
    /// is a shade of the trains' glass (``Map3DTrainLights/isGlass(_:)``),
    /// and the louvres and window frames would light as windows at night.
    public static let frame = Map3DColor.rgb(0x1F2124)
    public static let glass = Map3DTrainStyle.glass
    public static let lamp = Map3DPalette.tunnelLamp

    /// The coach's half length over its body and over its couplers.
    static let coachHalf: Float = 6.2
    static let coachCouplers: Float = 6.5
    /// The locomotive's half length over its frame and over its couplers.
    static let locoHalf: Float = 4.2
    static let locoCouplers: Float = 4.45

    /// The DL-38 locomotive.
    public static func locomotive(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.alishanLocomotive(far: far)
        return .flat(named: ids[far ? 1 : 0], from: b.mesh)
    }

    /// An Alishan coach, the same at either end; `body` and `band` its
    /// two colours (a preview can swap them; the game draws the reference's).
    public static func coach(far: Bool = false, body: UInt32 = coachCream, band: UInt32 = coachRed) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.alishanCoach(far: far, body: body, band: band)
        return .flat(named: ids[far ? 3 : 2], from: b.mesh)
    }
}

extension StationKitBuilder {
    private mutating func afrPrism(_ a: [Map3DPoint], _ b: [Map3DPoint], _ color: UInt32) {
        let inside = (a + b).reduce(Map3DPoint.zero, +) * (1 / Float(a.count + b.count))
        face(a, inside: inside, color: color); face(b, inside: inside, color: color)
        for i in a.indices { let j = (i + 1) % a.count; face([a[i], a[j], b[j], b[i]], inside: inside, color: color) }
    }

    /// A body block from `x0` to `x1`, `bottom` to `top`, `half` either side.
    private mutating func afrShell(_ x0: Float, _ x1: Float, _ bottom: Float, _ top: Float, half: Float, _ color: UInt32) {
        func p(_ x: Float) -> [Map3DPoint] {
            [Map3DPoint(x, bottom, -half), Map3DPoint(x, bottom, half), Map3DPoint(x, top, half), Map3DPoint(x, top, -half)]
        }
        afrPrism(p(x0), p(x1), color)
    }

    /// A two-axle bogie centred at `x`: its frame, side frames and four
    /// wheels on the 762 mm gauge.
    private mutating func afrBogie(_ x: Float, base: Float, far: Bool) {
        box(x, base, 0, 1.9, 1.05, 0.26, Map3DAlishan.chassis)
        for dx: Float in [-0.6, 0.6] {
            for side: Float in [-1, 1] {
                civicTube(Map3DPoint(x + dx, 0.29, side * 0.33), Map3DPoint(x + dx, 0.29, side * 0.45),
                          radius: 0.29, color: Map3DAlishan.chassis, sides: far ? 8 : 12)
            }
        }
        for side: Float in [-1, 1] {
            box(x, 0.18, side * 0.56, 2.0, 0.10, 0.30, Map3DAlishan.frame)
            if !far { box(x, 0.24, side * 0.62, 0.34, 0.03, 0.20, Map3DAlishan.metal) }
        }
    }

    /// A flat pane of glass on an end, facing along `end`: no sides, so
    /// the night lights do not take it for a side window.
    private mutating func afrEndPane(_ end: Float, _ x: Float, _ y: Float, _ z: Float, width: Float, height: Float) {
        face([Map3DPoint(x, y, z - width / 2), Map3DPoint(x, y, z + width / 2),
              Map3DPoint(x, y + height, z + width / 2), Map3DPoint(x, y + height, z - width / 2)],
             inside: Map3DPoint(x - end, y + height / 2, z), color: Map3DAlishan.glass)
    }

    /// A round lamp lens facing along `end` at `x`, `height` up, `across`.
    private mutating func afrLens(_ end: Float, _ x: Float, height: Float, across: Float, radius: Float, far: Bool) {
        if far {
            // A square lens, the same colour, flat on the end.
            let r = radius, f = x + end * 0.03
            face([Map3DPoint(f, height - r, across - r), Map3DPoint(f, height - r, across + r),
                  Map3DPoint(f, height + r, across + r), Map3DPoint(f, height + r, across - r)],
                 inside: Map3DPoint(x - end, height, across), color: Map3DAlishan.lamp)
            return
        }
        civicTube(Map3DPoint(x, height, across), Map3DPoint(x + end * 0.03, height, across),
                  radius: radius + 0.03, color: Map3DAlishan.frame, sides: 12)
        civicTube(Map3DPoint(x + end * 0.03, height, across), Map3DPoint(x + end * 0.045, height, across),
                  radius: radius, color: Map3DAlishan.lamp, sides: 12)
    }

    /// Decision 531: the DL-38, a cab at its back and the long hood
    /// forward, on two bogies, as the reference's `dl38` is drawn.
    mutating func alishanLocomotive(far: Bool) {
        let red = Map3DAlishan.red, cream = Map3DAlishan.cream, frame = Map3DAlishan.frame
        let glass = Map3DAlishan.glass, half = Map3DAlishan.locoHalf
        // The frame and walkway, the buffer beams at its ends.
        box(0, 0.86, 0, half * 2, 2.15, 0.20, frame)
        for end: Float in [-1, 1] {
            box(end * (half - 0.08), 0.62, 0, 0.16, 2.0, 0.26, Map3DAlishan.chassis)
            // The coupler and its pocket.
            box(end * (half + 0.10), 0.62, 0, 0.30, 0.34, 0.20, frame)
            box(end * (Map3DAlishan.locoCouplers - 0.06), 0.60, 0, 0.12, 0.26, 0.24, Map3DAlishan.metal)
            // Steps at the corners.
            for side: Float in [-1, 1] {
                box(end * (half - 0.32), 0.40, side * 0.98, 0.42, 0.20, 0.04, Map3DAlishan.metal)
                if !far { box(end * (half - 0.32), 0.40, side * 1.06, 0.42, 0.03, 0.46, frame) }
            }
        }
        for x: Float in [-2.5, 2.5] { afrBogie(x, base: 0.56, far: far) }
        // The fuel tank between the bogies.
        box(0, 0.50, 0, 1.6, 1.5, 0.36, Map3DAlishan.chassis)

        // The long hood, from the cab forward, narrower than the frame.
        let hoodBack: Float = -1.55, hoodFront: Float = half - 0.18, hoodHalf: Float = 0.86
        afrShell(hoodBack, hoodFront, 1.06, 2.04, half: hoodHalf, red)
        afrShell(hoodBack, hoodFront, 2.04, 2.15, half: hoodHalf, cream)
        afrShell(hoodBack, hoodFront, 2.15, 2.46, half: hoodHalf, red)
        // Its top, slightly rounded at the shoulders.
        afrPrism([Map3DPoint(hoodBack, 2.46, -hoodHalf), Map3DPoint(hoodBack, 2.46, hoodHalf),
                  Map3DPoint(hoodBack, 2.55, hoodHalf - 0.12), Map3DPoint(hoodBack, 2.55, -hoodHalf + 0.12)],
                 [Map3DPoint(hoodFront, 2.46, -hoodHalf), Map3DPoint(hoodFront, 2.46, hoodHalf),
                  Map3DPoint(hoodFront, 2.55, hoodHalf - 0.12), Map3DPoint(hoodFront, 2.55, -hoodHalf + 0.12)], red)
        // The exhaust and the horn.
        civicTube(Map3DPoint(0.2, 2.55, 0), Map3DPoint(0.2, 2.80, 0), radius: 0.11, color: frame, sides: far ? 6 : 10)
        box(-1.2, 2.55, 0.42, 0.30, 0.10, 0.10, Map3DAlishan.metal)
        for side: Float in [-1, 1] {
            let z = side * (hoodHalf + 0.012)
            // The hood's doors and louvres, five a side.
            for i in 0..<5 {
                let x = hoodBack + 0.55 + Float(i) * 1.07
                box(x, 2.20, z, 0.62, 0.02, 0.20, frame)
                if !far {
                    for k in 0..<4 { box(x, 2.22 + Float(k) * 0.05, z + side * 0.008, 0.58, 0.02, 0.018, Map3DAlishan.metal) }
                    box(x - 0.52, 1.10, z, 0.022, 0.02, 0.92, Map3DColor.shaded(red, 0.72))
                    box(x + 0.25, 1.52, z + side * 0.006, 0.03, 0.02, 0.14, Map3DAlishan.metal)
                }
            }
            if !far {
                // The handrail along the walkway.
                beam(Map3DPoint(hoodBack, 1.72, side * 1.02), Map3DPoint(hoodFront, 1.72, side * 1.02), 0.035, Map3DAlishan.metal)
                for x in stride(from: hoodBack + 0.2, through: hoodFront, by: 1.4) {
                    beam(Map3DPoint(x, 1.06, side * 1.02), Map3DPoint(x, 1.72, side * 1.02), 0.03, Map3DAlishan.metal)
                }
            }
        }
        // The radiator at the hood's front: slats, a cream V, two lamps.
        let nose = hoodFront
        afrPrism([Map3DPoint(nose, 1.12, -0.78), Map3DPoint(nose, 1.12, 0.78), Map3DPoint(nose, 2.40, 0.78), Map3DPoint(nose, 2.40, -0.78)],
                 [Map3DPoint(nose + 0.03, 1.12, -0.78), Map3DPoint(nose + 0.03, 1.12, 0.78),
                  Map3DPoint(nose + 0.03, 2.40, 0.78), Map3DPoint(nose + 0.03, 2.40, -0.78)], Map3DColor.shaded(red, 0.62))
        for k in 0..<(far ? 4 : 11) {
            let y = 1.18 + Float(k) * (far ? 0.30 : 0.112)
            box(nose + 0.045, y, 0, 0.03, 1.50, far ? 0.08 : 0.045, Map3DColor.shaded(red, 0.85))
        }
        for side: Float in [-1, 1] {
            beam(Map3DPoint(nose + 0.07, 2.02, side * 0.74), Map3DPoint(nose + 0.07, 1.22, 0), 0.10, cream)
            afrLens(1, nose + 0.02, height: 2.30, across: side * 0.62, radius: 0.085, far: far)
        }

        // The cab, full width, its roof overhanging.
        let cabBack: Float = -half + 0.12, cabFront = hoodBack
        afrShell(cabBack, cabFront, 1.06, 2.04, half: 1.04, red)
        afrShell(cabBack, cabFront, 2.04, 2.15, half: 1.04, cream)
        afrShell(cabBack, cabFront, 2.15, 2.92, half: 1.04, red)
        box((cabBack + cabFront) / 2, 2.92, 0, cabFront - cabBack + 0.24, 2.20, 0.10, red)
        box((cabBack + cabFront) / 2, 3.02, 0, cabFront - cabBack + 0.06, 1.90, 0.03, Map3DAlishan.roof)
        // Its windows: two over the hood, two at the back, one each side.
        for end: Float in [-1, 1] {
            let x = end > 0 ? cabFront : cabBack
            for side: Float in [-1, 1] {
                box(x + end * 0.012, 2.22, side * 0.50, 0.024, 0.78, 0.60, frame)
                afrEndPane(end, x + end * 0.026, 2.26, side * 0.50, width: 0.70, height: 0.52)
            }
        }
        for side: Float in [-1, 1] {
            let z = side * 1.052
            box(-3.35, 2.18, z, 0.92, 0.024, 0.62, frame)
            box(-3.35, 2.22, z + side * 0.012, 0.84, 0.02, 0.54, glass)
            // The cab door.
            box(-2.25, 1.10, z, 0.66, 0.022, 1.72, Map3DColor.shaded(red, 0.9))
            box(-2.25, 2.24, z + side * 0.012, 0.50, 0.02, 0.48, glass)
            if !far { box(-1.98, 1.50, z, 0.03, 0.03, 0.18, Map3DAlishan.metal) }
            // The cab's back lamps.
            afrLens(-1, cabBack - 0.02, height: 2.62, across: side * 0.66, radius: 0.075, far: far)
        }
        if !far {
            // The number plate under the back windows (blank: no lettering).
            box(cabBack - 0.012, 1.62, 0, 0.02, 0.56, 0.16, cream)
        }
    }

    /// Decision 531: an Alishan coach, as the reference's `alicoach`:
    /// `body` with a `band` along the windows, a door at each end of
    /// each side, a flush roof with two air conditioners, a gangway and
    /// two windows at each end, lamps low at the ends.
    mutating func alishanCoach(far: Bool, body: UInt32, band: UInt32) {
        let frame = Map3DAlishan.frame, glass = Map3DAlishan.glass
        let half = Map3DAlishan.coachHalf, width: Float = 1.1
        // Underframe, its equipment boxes and the bogies.
        box(0, 0.80, 0, half * 2, 2.0, 0.16, frame)
        for x: Float in [-1.6, 1.2] { box(x, 0.50, 0, 1.4, 1.3, 0.32, Map3DAlishan.chassis) }
        if !far { box(-0.2, 0.56, 0, 0.6, 1.5, 0.22, Map3DAlishan.metal) }
        for x: Float in [-4.35, 4.35] { afrBogie(x, base: 0.52, far: far) }
        // The body: cream, the red band, cream, a red line under the roof.
        afrShell(-half, half, 0.96, 1.58, half: width, body)
        afrShell(-half, half, 1.58, 1.64, half: width, band)
        afrShell(-half, half, 1.64, 1.72, half: width, body)
        afrShell(-half, half, 1.72, 2.52, half: width, band)
        afrShell(-half, half, 2.52, 2.82, half: width, body)
        // The flush roof: low shoulders up to a gentle crown.
        func roof(_ x: Float) -> [Map3DPoint] {
            [Map3DPoint(x, 2.82, -width), Map3DPoint(x, 2.82, width), Map3DPoint(x, 2.93, width - 0.12),
             Map3DPoint(x, 3.0, 0.62), Map3DPoint(x, 3.02, 0), Map3DPoint(x, 3.0, -0.62), Map3DPoint(x, 2.93, -width + 0.12)]
        }
        afrPrism(roof(-half), roof(half), body)
        box(0, 3.0, 0, half * 2 - 0.2, 1.1, 0.025, Map3DAlishan.roof)
        // The air conditioners.
        for x: Float in [-3.2, 3.2] {
            let a = [Map3DPoint(x - 0.9, 2.98, -0.55), Map3DPoint(x - 0.9, 2.98, 0.55),
                     Map3DPoint(x - 0.9, 3.22, 0.42), Map3DPoint(x - 0.9, 3.22, -0.42)]
            afrPrism(a, a.map { Map3DPoint(x + 0.9, $0.y, $0.z) }, Map3DAlishan.roof)
            if !far { for i in -2...2 { box(x + Float(i) * 0.3, 3.2, 0, 0.03, 0.70, 0.015, Map3DAlishan.metal) } }
        }
        for side: Float in [-1, 1] {
            let z = side * (width + 0.012)
            // A door at each end: a dark frame, its window, a red kick line.
            for end: Float in [-1, 1] {
                let x = end * (half - 0.62)
                box(x, 0.98, z, 0.80, 0.022, 1.86, frame)
                box(x, 1.00, z + side * 0.008, 0.72, 0.02, 1.80, body)
                box(x, 1.82, z + side * 0.016, 0.52, 0.02, 0.66, glass)
                box(x, 1.24, z + side * 0.016, 0.72, 0.02, 0.07, band)
                if !far { box(x + end * -0.28, 1.50, z + side * 0.011, 0.03, 0.03, 0.22, Map3DAlishan.metal) }
            }
            // The big windows between the doors, eight a side.
            if far {
                // One strip, cut where the lamps' ends' 2.8 m reach ends, so
                // its middle lights at night (Map3DTrainLights.windowModel).
                box(0, 1.80, z, 7.4, 0.024, 0.66, glass)
                for end: Float in [-1, 1] { box(end * 4.2, 1.80, z, 1.0, 0.024, 0.66, glass) }
            } else {
                for i in 0..<8 {
                    let x = -4.4 + Float(i) * 1.257
                    box(x, 1.76, z, 1.04, 0.024, 0.74, frame)
                    box(x, 1.80, z + side * 0.012, 0.96, 0.02, 0.66, glass)
                }
            }
            // The step under each door.
            for end: Float in [-1, 1] { box(end * (half - 0.62), 0.66, side * 1.0, 0.70, 0.22, 0.04, Map3DAlishan.metal) }
        }
        for end: Float in [-1, 1] {
            let x = end * half
            // The end: two windows either side of the gangway door, its
            // bellows, the coupler and the lamps low at the corners.
            for side: Float in [-1, 1] {
                box(x + end * 0.012, 1.76, side * 0.64, 0.024, 0.54, 0.70, frame)
                afrEndPane(end, x + end * 0.026, 1.80, side * 0.64, width: 0.46, height: 0.62)
                afrLens(end, x + end * 0.01, height: 1.22, across: side * 0.78, radius: 0.06, far: far)
            }
            box(x + end * 0.012, 0.98, 0, 0.024, 0.66, 1.80, Map3DColor.shaded(body, 0.85))
            afrEndPane(end, x + end * 0.026, 1.84, 0, width: 0.40, height: 0.56)
            if !far { box(x + end * 0.14, 0.98, 0, 0.26, 0.86, 1.92, Map3DAlishan.frame) }
            box(end * (half + 0.12), 0.58, 0, 0.30, 0.34, 0.20, frame)
            box(end * (Map3DAlishan.coachCouplers - 0.06), 0.56, 0, 0.12, 0.26, 0.24, Map3DAlishan.metal)
        }
    }
}
