import Foundation

/// Decision 531: the Alishan Forest Railway's mountain train (`ALISHAN`,
/// decision 515), the DL-38 diesel locomotive and the ordinary Alishan
/// coach behind it, rebuilt (revision 2) the way the R21 study was
/// (`Map3DG12`, #1485): part by part against photographs on Wikimedia
/// Commons (`docs/art/alishan-2026-11-01/README.md` lists each one, its
/// author, licence and what it was used for).
///
/// The DL-38 (Nippon Sharyo, 1980, the 25 t prototype of the DL-39 to
/// DL-43): a long hood with the radiator grille at its front, a number
/// board above it and two yellow beacons on its corners; the white band
/// along the side and round the front pillars; louvred doors; a taller cab
/// near the back and a short hood behind it whose end carries a white V;
/// deep black end beams with sand boxes, link couplers and chains; two
/// open two-axle bogies and the fuel tank between them.
///
/// The coach in its service livery (2009–2016 photographs): red below a
/// white line, a dark-green window band, a red curved roof; eight
/// silver-framed windows, a door at each end of each side, a gangway door
/// at each end, two lamps low on the ends.
///
/// No drawing gives either vehicle's dimensions: the lengths stay the
/// game's (8.9 m and 13.0 m over couplers, decision 515's `carMetres`),
/// the heights, widths, wheel sizes and the hood, cab and bogie positions
/// are measured off the photographs against the 762 mm gauge. Builder
/// metres: x the front (the locomotive's radiator; either end of the
/// coach), y up, z right; `Model.flat` turns them into the native axes.
public enum Map3DAlishan {
    public static let ids = ["afr-dl38", "afr-dl38-far", "afr-alicoach", "afr-alicoach-far"]
    /// The locomotive's and the coaches' red (the reference's `dl38`
    /// body), the white band, the coaches' dark-green window band.
    public static let red = Map3DColor.rgb(0xB83230)
    public static let cream = Map3DColor.rgb(0xE9E1CF)
    public static let green = Map3DColor.rgb(0x1E4A3E)
    public static let metal = Map3DColor.rgb(0x97A6AB)
    public static let silver = Map3DColor.rgb(0xC9CED0)
    public static let doorGrey = Map3DColor.rgb(0x8E9496)
    public static let chassis = Map3DColor.rgb(0x34424A)
    /// The reference's frame #18232A a touch more neutral: that blue-black
    /// is a shade of the trains' glass (``Map3DTrainLights/isGlass(_:)``),
    /// and the louvres and window frames would light as windows at night.
    public static let frame = Map3DColor.rgb(0x1F2124)
    public static let grille = Map3DColor.rgb(0x2C2B2A)
    public static let beacon = Map3DColor.rgb(0xF2C230)
    public static let glass = Map3DTrainStyle.glass
    public static let lamp = Map3DPalette.tunnelLamp

    /// The coach's half length over its body and over its couplers.
    static let coachHalf: Float = 6.2
    static let coachCouplers: Float = 6.5
    /// The locomotive's half length over its end beams and over its couplers.
    static let locoHalf: Float = 4.16
    static let locoCouplers: Float = 4.45

    /// The DL-38 locomotive.
    public static func locomotive(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.alishanLocomotive(far: far)
        return .flat(named: ids[far ? 1 : 0], from: b.mesh)
    }

    /// An Alishan coach, the same at either end.
    public static func coach(far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.alishanCoach(far: far)
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
        afrExtrude([(-half, bottom), (half, bottom), (half, top), (-half, top)], x0, x1, color)
    }

    /// A closed prism of the cross-section `outline` (z, y) from `x0` to `x1`.
    private mutating func afrExtrude(_ outline: [(Float, Float)], _ x0: Float, _ x1: Float, _ color: UInt32) {
        afrPrism(outline.map { Map3DPoint(x0, $0.1, $0.0) }, outline.map { Map3DPoint(x1, $0.1, $0.0) }, color)
    }

    /// A thin closed plate on an end, facing along `end`, its outer face
    /// `colour` and the rest `rim`: an end pane has no sides, so the night
    /// lights do not take it for a side window.
    private mutating func afrEndPlate(_ end: Float, _ x: Float, _ y: Float, _ z: Float, width: Float, height: Float,
                                      face colour: UInt32, rim: UInt32 = Map3DAlishan.frame, depth: Float = 0.012) {
        func corners(_ at: Float) -> [Map3DPoint] {
            [Map3DPoint(at, y, z - width / 2), Map3DPoint(at, y, z + width / 2),
             Map3DPoint(at, y + height, z + width / 2), Map3DPoint(at, y + height, z - width / 2)]
        }
        let a = corners(x - end * depth), b = corners(x)
        let inside = Map3DPoint(x - end * depth / 2, y + height / 2, z)
        face(a, inside: inside, color: rim)
        face(b, inside: inside, color: colour)
        for i in a.indices { let j = (i + 1) % a.count; face([a[i], a[j], b[j], b[i]], inside: inside, color: rim) }
    }

    /// A round lamp facing along `end` at `x`: a dark housing and its lens.
    private mutating func afrLens(_ end: Float, _ x: Float, height: Float, across: Float, radius: Float, far: Bool,
                                  housing: UInt32 = Map3DAlishan.frame) {
        if far {
            afrEndPlate(end, x + end * 0.05, height - radius, across, width: radius * 2, height: radius * 2, face: Map3DAlishan.lamp)
            return
        }
        civicTube(Map3DPoint(x, height, across), Map3DPoint(x + end * 0.07, height, across),
                  radius: radius + 0.035, color: housing, sides: 12)
        civicTube(Map3DPoint(x + end * 0.07, height, across), Map3DPoint(x + end * 0.085, height, across),
                  radius: radius, color: Map3DAlishan.lamp, sides: 12)
    }

    /// A number board facing along `end`: white with a dark rim and, near,
    /// "DL-38" in dark strokes (the vehicle's number, read as on the photos).
    private mutating func afrNumberBoard(_ end: Float, _ x: Float, _ y: Float, width: Float, height: Float, far: Bool) {
        afrEndPlate(end, x + end * 0.03, y, 0, width: width, height: height, face: Map3DAlishan.frame, depth: 0.03)
        afrEndPlate(end, x + end * 0.042, y + 0.02, 0, width: width - 0.04, height: height - 0.04, face: Map3DAlishan.cream, depth: 0.012)
        guard !far else { return }
        let ink = Map3DAlishan.frame, paint = x + end * 0.05, reading: Float = end > 0 ? -1 : 1
        let glyphHeight = height * 0.52, glyphWidth = glyphHeight * 0.62, bottom = y + height * 0.24
        let glyphs: [[(Float, Float, Float, Float)]] = [
            [(0, 0, 0, 1), (0, 1, 0.65, 1), (0.65, 1, 1, 0.72), (1, 0.72, 1, 0.28), (1, 0.28, 0.65, 0), (0.65, 0, 0, 0)],  // D
            [(0, 1, 0, 0), (0, 0, 1, 0)],                                                                            // L
            [(0.15, 0.5, 0.85, 0.5)],                                                                                // -
            [(0, 1, 1, 1), (1, 1, 1, 0), (1, 0, 0, 0), (0.25, 0.5, 1, 0.5)],                                         // 3
            [(0, 0, 1, 0), (1, 0, 1, 1), (1, 1, 0, 1), (0, 1, 0, 0), (0, 0.5, 1, 0.5)],                              // 8
        ]
        let pitch = glyphWidth * 1.45, start = -pitch * Float(glyphs.count - 1) / 2 - glyphWidth / 2
        for (n, strokes) in glyphs.enumerated() {
            let left = start + Float(n) * pitch
            for s in strokes {
                beam(Map3DPoint(paint, bottom + s.1 * glyphHeight, reading * (left + s.0 * glyphWidth)),
                     Map3DPoint(paint, bottom + s.3 * glyphHeight, reading * (left + s.2 * glyphWidth)), 0.018, ink)
            }
        }
    }

    /// A white warning plate on an end (its lettering as three red strokes).
    private mutating func afrWarningPlate(_ end: Float, _ x: Float, _ y: Float, _ z: Float, far: Bool) {
        afrEndPlate(end, x + end * 0.015, y, z, width: 0.11, height: 0.34, face: Map3DAlishan.cream, rim: Map3DAlishan.cream, depth: 0.015)
        guard !far else { return }
        for k in 0..<3 {
            box(x + end * 0.018, y + 0.05 + Float(k) * 0.1, z, 0.012, 0.05, 0.07, Map3DAlishan.red)
        }
    }

    /// A yellow rotating beacon on a hood's top corner.
    private mutating func afrBeacon(_ x: Float, _ top: Float, _ z: Float, far: Bool) {
        if far {
            box(x, top, z, 0.16, 0.16, 0.14, Map3DAlishan.beacon)
            return
        }
        civicTube(Map3DPoint(x, top, z), Map3DPoint(x, top + 0.05, z), radius: 0.075, color: Map3DAlishan.frame, sides: 10)
        civicTube(Map3DPoint(x, top + 0.05, z), Map3DPoint(x, top + 0.15, z), radius: 0.085, color: Map3DAlishan.beacon, sides: 10)
        // The cap is a box so the far beacon's flat faces share its shades.
        box(x, top + 0.15, z, 0.1, 0.1, 0.03, Map3DAlishan.beacon)
    }

    /// A louvre: a dark opening and, near, `slats` horizontal slats.
    private mutating func afrLouvre(_ x: Float, _ y: Float, _ z: Float, side: Float, length: Float, height: Float,
                                    slats: Int, slat: UInt32, far: Bool) {
        box(x, y, z + side * 0.006, length, 0.012, height, Map3DAlishan.grille)
        guard !far else { return }
        for k in 0..<slats {
            let yk = y + 0.02 + Float(k) * (height - 0.04) / Float(max(slats - 1, 1))
            box(x, yk - 0.012, z + side * 0.016, length - 0.03, 0.012, 0.024, slat)
        }
    }

    /// A link coupler at an end: the pocket, the round head, the chains
    /// and the air hose.
    private mutating func afrCoupler(_ end: Float, beamFace: Float, tip: Float, height: Float, far: Bool) {
        let dark = Map3DAlishan.frame, metal = Map3DAlishan.metal
        box(end * (beamFace + 0.08), height - 0.17, 0, 0.16, 0.46, 0.34, dark)
        civicTube(Map3DPoint(end * (beamFace + 0.16), height, 0), Map3DPoint(end * (tip - 0.04), height, 0),
                  radius: 0.15, color: Map3DColor.shaded(metal, 0.62), sides: far ? 8 : 12)
        box(end * (tip - 0.02), height - 0.05, 0, 0.04, 0.08, 0.10, dark)
        if far { return }
        for side: Float in [-1, 1] {
            // Safety chains hanging from the beam to the coupler.
            beam(Map3DPoint(end * (beamFace + 0.03), height + 0.28, side * 0.42),
                 Map3DPoint(end * (beamFace + 0.10), height - 0.08, side * 0.40), 0.035, metal)
            beam(Map3DPoint(end * (beamFace + 0.10), height - 0.08, side * 0.40),
                 Map3DPoint(end * (beamFace + 0.20), height - 0.02, side * 0.16), 0.035, metal)
        }
        // The air hose.
        beam(Map3DPoint(end * (beamFace + 0.02), height + 0.22, -0.26), Map3DPoint(end * (beamFace + 0.14), height - 0.12, -0.24), 0.05, dark)
        beam(Map3DPoint(end * (beamFace + 0.14), height - 0.12, -0.24), Map3DPoint(end * (beamFace + 0.22), height - 0.02, -0.12), 0.05, dark)
    }

    /// An open two-axle bogie centred at `x`: four wheels of `radius` on
    /// the 762 mm gauge, the axle boxes and springs, the side frames
    /// outside the wheels and the bolster.
    private mutating func afrBogie(_ x: Float, wheelbase: Float, radius: Float, frameTop: Float, far: Bool) {
        let dark = Map3DAlishan.frame, wheel = Map3DAlishan.chassis, metal = Map3DAlishan.metal
        for dx in [-wheelbase / 2, wheelbase / 2] {
            for side: Float in [-1, 1] {
                civicTube(Map3DPoint(x + dx, radius, side * 0.35), Map3DPoint(x + dx, radius, side * 0.45),
                          radius: radius, color: wheel, sides: far ? 8 : 12)
                if !far {
                    // The tread's rim and the hub.
                    civicTube(Map3DPoint(x + dx, radius, side * 0.45), Map3DPoint(x + dx, radius, side * 0.47),
                              radius: radius * 0.55, color: Map3DColor.shaded(wheel, 0.8), sides: 10)
                }
            }
            if !far { civicTube(Map3DPoint(x + dx, radius, -0.35), Map3DPoint(x + dx, radius, 0.35), radius: 0.06, color: dark, sides: 6) }
        }
        for side: Float in [-1, 1] {
            let z = side * 0.58
            // The side frame between the axle boxes, the boxes, the springs.
            box(x, radius + 0.06, z, wheelbase + 0.34, 0.08, 0.16, dark)
            for dx in [-wheelbase / 2, wheelbase / 2] {
                box(x + dx, radius - 0.17, z, 0.26, 0.14, 0.32, dark)
                if !far {
                    box(x + dx, radius - 0.12, z + side * 0.075, 0.18, 0.02, 0.22, metal)
                    civicTube(Map3DPoint(x + dx, radius + 0.22, z), Map3DPoint(x + dx, frameTop - 0.08, z), radius: 0.07, color: metal, sides: 8)
                    // The brake shoe at the wheel's inner face.
                    box(x + dx - (dx > 0 ? radius + 0.03 : -(radius + 0.03)), radius - 0.12, side * 0.40, 0.06, 0.08, 0.24, dark)
                }
            }
        }
        box(x, frameTop - 0.12, 0, 0.42, 1.30, 0.12, dark)
    }

    /// Steps hung under an end corner: two posts, two treads.
    private mutating func afrCornerStep(_ x: Float, _ z: Float, top: Float, far: Bool) {
        let metal = Map3DAlishan.metal
        for dz: Float in [-0.13, 0.13] { box(x, 0.16, z + dz, 0.05, 0.04, top - 0.16, Map3DAlishan.frame) }
        box(x, 0.16, z, 0.22, 0.32, 0.04, metal)
        if !far { box(x, (top + 0.16) / 2, z, 0.22, 0.32, 0.04, metal) }
    }

    /// One of the locomotive's hoods from `x0` to `x1`, `top` high: red
    /// with the white band, its top's edges rounded.
    private mutating func afrHood(_ x0: Float, _ x1: Float, top: Float, half: Float, deck: Float, band: (Float, Float)) {
        let red = Map3DAlishan.red
        afrShell(x0, x1, deck, band.0, half: half, red)
        afrShell(x0, x1, band.0, band.1, half: half, Map3DAlishan.cream)
        afrShell(x0, x1, band.1, top - 0.08, half: half, red)
        afrExtrude([(-half, top - 0.08), (half, top - 0.08), (half - 0.02, top - 0.035), (half - 0.07, top - 0.005),
                    (half - 0.12, top), (-half + 0.12, top), (-half + 0.07, top - 0.005), (-half + 0.02, top - 0.035)], x0, x1, red)
    }

    /// Decision 531, revision 2: the DL-38 as photographed (see the type's
    /// notes): long hood forward (+x), cab and short hood at the back.
    mutating func alishanLocomotive(far: Bool) {
        let red = Map3DAlishan.red, cream = Map3DAlishan.cream, dark = Map3DAlishan.frame
        let metal = Map3DAlishan.metal, glass = Map3DAlishan.glass
        let beamFace = Map3DAlishan.locoHalf
        let deck: Float = 1.10, band: (Float, Float) = (1.74, 1.90), hoodHalf: Float = 0.86
        let hoodTop: Float = 2.42, shortTop: Float = 2.30, cabTop: Float = 2.86, cabHalf: Float = 1.02
        let nose: Float = 3.96, cabFront: Float = -1.72, cabBack: Float = -3.36, tail: Float = -4.04

        // The frame: a deep black sill and the deck edge.
        box(0, 0.80, 0, beamFace * 2 - 0.3, 2.04, deck - 0.80, dark)
        box(0, deck - 0.04, 0, beamFace * 2 - 0.02, 2.18, 0.04, Map3DAlishan.chassis)
        for end: Float in [-1, 1] {
            // The deep end beam and its sand boxes on the corners.
            box(end * (beamFace - 0.14), 0.52, 0, 0.28, 2.10, deck - 0.52, dark)
            for side: Float in [-1, 1] {
                box(end * (beamFace - 0.02), 0.78, side * 0.78, 0.30, 0.44, 0.32, dark)
                if !far { box(end * (beamFace + 0.13), 0.84, side * 0.78, 0.012, 0.30, 0.20, Map3DColor.shaded(dark, 1.6)) }
                afrCornerStep(end * (beamFace - 0.02), side * 0.98, top: 0.52, far: far)
            }
            afrCoupler(end, beamFace: beamFace, tip: Map3DAlishan.locoCouplers, height: 0.66, far: far)
            // The low guard bar across the end.
            box(end * (beamFace + 0.02), 0.16, 0, 0.06, 1.40, 0.06, dark)
        }
        for x: Float in [-2.55, 2.55] { afrBogie(x, wheelbase: 1.44, radius: 0.33, frameTop: 0.80, far: far) }
        // The fuel tank and an air reservoir between the bogies.
        civicTube(Map3DPoint(-1.15, 0.56, 0.18), Map3DPoint(1.15, 0.56, 0.18), radius: 0.26, color: dark, sides: far ? 8 : 14)
        if !far {
            civicTube(Map3DPoint(-0.95, 0.60, -0.62), Map3DPoint(0.85, 0.60, -0.62), radius: 0.12, color: Map3DAlishan.chassis, sides: 10)
            for x: Float in [-0.9, 0.9] { box(x, 0.56, 0.18, 0.08, 0.6, 0.24, dark) }
        }

        // The long hood.
        afrHood(cabFront, nose, top: hoodTop, half: hoodHalf, deck: deck, band: band)
        // Its front: the radiator grille in a raised red surround, the
        // number board over it, a headlamp on its right pillar, a warning
        // plate on each pillar, two beacons on the corners.
        box(nose + 0.01, 1.22, 0, 0.02, 1.12, 0.90, Map3DAlishan.grille)
        let surround = Map3DColor.shaded(red, 0.9)
        box(nose + 0.025, 1.14, 0, 0.05, 1.28, 0.08, surround)
        box(nose + 0.025, 2.12, 0, 0.05, 1.28, 0.08, surround)
        for side: Float in [-1, 1] { box(nose + 0.025, 1.22, side * 0.60, 0.05, 0.08, 0.90, surround) }
        for k in 0..<(far ? 4 : 12) {
            let y = 1.25 + Float(k) * (far ? 0.24 : 0.075)
            box(nose + 0.02, y, 0, 0.03, 1.10, far ? 0.05 : 0.026, Map3DColor.shaded(Map3DAlishan.metal, 0.6))
        }
        afrNumberBoard(1, nose, 2.22, width: 0.56, height: 0.17, far: far)
        afrLens(1, nose, height: band.0 + 0.08, across: 0.74, radius: 0.085, far: far)
        for side: Float in [-1, 1] {
            afrWarningPlate(1, nose, 1.28, side * 0.74, far: far)
            afrBeacon(nose - 0.14, hoodTop, side * 0.70, far: far)
        }
        if !far {
            // The grab rail over the front edge of the hood.
            beam(Map3DPoint(nose - 0.08, hoodTop + 0.12, -0.55), Map3DPoint(nose - 0.08, hoodTop + 0.12, 0.55), 0.03, dark)
            for z: Float in [-0.55, 0.55] { beam(Map3DPoint(nose - 0.08, hoodTop, z), Map3DPoint(nose - 0.08, hoodTop + 0.12, z), 0.03, dark) }
        }
        // The muffler's dome and the exhaust ahead of the cab.
        civicTube(Map3DPoint(cabFront + 0.42, hoodTop, 0), Map3DPoint(cabFront + 0.42, hoodTop + 0.12, 0), radius: 0.22, color: red, sides: far ? 8 : 14)
        civicTube(Map3DPoint(cabFront + 0.42, hoodTop + 0.12, 0), Map3DPoint(cabFront + 0.42, hoodTop + 0.18, 0), radius: 0.15, color: red, sides: far ? 8 : 14)
        civicTube(Map3DPoint(cabFront + 0.95, hoodTop, -0.2), Map3DPoint(cabFront + 0.95, hoodTop + 0.16, -0.2), radius: 0.08, color: dark, sides: far ? 6 : 10)
        // The hood's sides: the big louvre behind the pillar, a grab bar,
        // eight doors with their louvres, handles and seams.
        let doorsFrom = cabFront + 0.08, doorsTo = nose - 0.72
        let door = (doorsTo - doorsFrom) / 8
        for side: Float in [-1, 1] {
            let z = side * hoodHalf
            afrLouvre(nose - 0.36, 1.22, z, side: side, length: 0.42, height: 1.08, slats: 14, slat: Map3DColor.shaded(red, 0.8), far: far)
            if !far {
                beam(Map3DPoint(nose - 0.66, 1.30, z + side * 0.06), Map3DPoint(nose - 0.66, 2.24, z + side * 0.06), 0.03, dark)
                for y: Float in [1.30, 2.24] { beam(Map3DPoint(nose - 0.66, y, z), Map3DPoint(nose - 0.66, y, z + side * 0.06), 0.025, dark) }
            }
            for i in 0..<8 {
                let x = doorsFrom + (Float(i) + 0.5) * door
                afrLouvre(x, band.1 + 0.08, z, side: side, length: door * 0.42, height: 0.36, slats: 5, slat: Map3DColor.shaded(red, 0.8), far: far)
                if i % 2 == 1 {
                    afrLouvre(x, deck + 0.14, z, side: side, length: door * 0.42, height: 0.44, slats: 6, slat: Map3DColor.shaded(red, 0.8), far: far)
                }
                guard !far else { continue }
                box(x - door / 2, deck + 0.04, z + side * 0.004, 0.014, 0.01, hoodTop - deck - 0.14, Map3DColor.shaded(red, 0.62))
                box(x + door * 0.3, band.0 - 0.14, z + side * 0.012, 0.03, 0.02, 0.08, metal)
            }
        }

        // The cab: taller and wider, the band round it, a rounded roof
        // overhanging its ends.
        afrShell(cabBack, cabFront, deck, band.0, half: cabHalf, red)
        afrShell(cabBack, cabFront, band.0, band.1, half: cabHalf, cream)
        afrShell(cabBack, cabFront, band.1, cabTop, half: cabHalf, red)
        afrExtrude([(-cabHalf - 0.04, cabTop), (cabHalf + 0.04, cabTop), (cabHalf + 0.04, cabTop + 0.05), (0.92, cabTop + 0.13),
                    (0.55, cabTop + 0.19), (0, cabTop + 0.21), (-0.55, cabTop + 0.19), (-0.92, cabTop + 0.13), (-cabHalf - 0.04, cabTop + 0.05)],
                   cabBack - 0.07, cabFront + 0.07, red)
        // The horn on the roof's front, a trumpet facing forward.
        civicTube(Map3DPoint(cabFront - 0.32, cabTop + 0.24, 0.36), Map3DPoint(cabFront - 0.05, cabTop + 0.24, 0.36), radius: 0.045, color: red, sides: 10)
        civicTube(Map3DPoint(cabFront - 0.05, cabTop + 0.24, 0.36), Map3DPoint(cabFront + 0.02, cabTop + 0.24, 0.36), radius: 0.11, color: red, sides: 12)
        box(cabFront - 0.28, cabTop + 0.17, 0.36, 0.08, 0.06, 0.04, dark)
        // Its windows: two forward over the long hood, two back over the
        // short hood (end panes), one window and the door each side.
        for side: Float in [-1, 1] {
            afrEndPlate(1, cabFront + 0.03, hoodTop + 0.06, side * 0.47, width: 0.70, height: 0.38, face: glass, depth: 0.03)
            afrEndPlate(-1, cabBack - 0.03, shortTop + 0.12, side * 0.47, width: 0.70, height: 0.40, face: glass, depth: 0.03)
            if !far {
                // The wipers' arms.
                beam(Map3DPoint(cabFront + 0.05, hoodTop + 0.44, side * 0.47), Map3DPoint(cabFront + 0.05, hoodTop + 0.12, side * 0.38), 0.02, dark)
            }
            let z = side * cabHalf
            box(-3.04, 2.06, z, 0.62, 0.03, 0.70, dark)
            box(-3.04, 2.10, z + side * 0.01, 0.54, 0.02, 0.62, glass)
            // The door: its outline, two tall narrow panes, grab bars, steps.
            box(-2.17, deck + 0.04, z, 0.64, 0.016, 1.68, Map3DColor.shaded(red, 0.62))
            box(-2.17, deck + 0.05, z + side * 0.006, 0.60, 0.014, 1.66, red)
            for dx: Float in [-0.13, 0.13] {
                box(-2.17 + dx, 2.04, z + side * 0.012, 0.20, 0.03, 0.70, dark)
                box(-2.17 + dx, 2.07, z + side * 0.02, 0.15, 0.02, 0.64, glass)
            }
            box(-2.95, band.0 - 0.26, z + side * 0.005, 0.40, 0.02, 0.16, dark)
            box(-2.95, band.0 - 0.245, z + side * 0.012, 0.37, 0.02, 0.13, cream)
            if !far {
                for x: Float in [-2.55, -1.79] {
                    beam(Map3DPoint(x, deck + 0.10, z + side * 0.07), Map3DPoint(x, 2.62, z + side * 0.07), 0.03, dark)
                    for y: Float in [deck + 0.10, 2.62] { beam(Map3DPoint(x, y, z), Map3DPoint(x, y, z + side * 0.07), 0.025, dark) }
                }
                box(-1.98, 1.62, z + side * 0.02, 0.06, 0.03, 0.04, metal)
            }
            box(-2.17, 0.52, side * 0.98, 0.50, 0.24, 0.04, metal)
            box(-2.17, 0.52, side * 1.08, 0.04, 0.04, 0.58, dark)
            box(-2.17, 0.80, side * 0.98, 0.50, 0.24, 0.03, metal)
        }

        // The short hood behind the cab, its end with the white V.
        afrHood(tail, cabBack, top: shortTop, half: hoodHalf, deck: deck, band: band)
        let columns = far ? 6 : 16, vBottom: Float = 1.40
        for i in 0..<columns {
            let z0 = -hoodHalf + 2 * hoodHalf * Float(i) / Float(columns)
            let z1 = -hoodHalf + 2 * hoodHalf * Float(i + 1) / Float(columns)
            let y0 = vBottom + (band.0 - vBottom) * abs(z0) / hoodHalf
            let y1 = vBottom + (band.0 - vBottom) * abs(z1) / hoodHalf
            let t = band.1 - band.0
            func panel(_ a0: Float, _ a1: Float, _ b0: Float, _ b1: Float, _ colour: UInt32) {
                let back = [Map3DPoint(tail - 0.004, a0, z0), Map3DPoint(tail - 0.004, a1, z1), Map3DPoint(tail - 0.004, b1, z1), Map3DPoint(tail - 0.004, b0, z0)]
                afrPrism(back, back.map { Map3DPoint(tail - 0.022, $0.y, $0.z) }, colour)
            }
            panel(deck, deck, y0, y1, red)
            panel(y0, y1, y0 + t, y1 + t, cream)
            panel(y0 + t, y1 + t, shortTop - 0.1, shortTop - 0.1, red)
        }
        afrNumberBoard(-1, tail - 0.02, 2.04, width: 0.50, height: 0.16, far: far)
        afrLens(-1, tail - 0.02, height: band.1 + 0.06, across: -0.42, radius: 0.075, far: far)
        for side: Float in [-1, 1] {
            afrWarningPlate(-1, tail - 0.02, 1.20, side * 0.74, far: far)
            afrBeacon(tail + 0.13, shortTop, side * 0.70, far: far)
        }
        if !far {
            beam(Map3DPoint(tail + 0.08, shortTop + 0.12, -0.5), Map3DPoint(tail + 0.08, shortTop + 0.12, 0.5), 0.03, dark)
            for z: Float in [-0.5, 0.5] { beam(Map3DPoint(tail + 0.08, shortTop, z), Map3DPoint(tail + 0.08, shortTop + 0.12, z), 0.03, dark) }
        }
    }

    /// Decision 531, revision 2: an ordinary Alishan coach in its service
    /// livery (see the type's notes), the same at either end.
    mutating func alishanCoach(far: Bool) {
        let red = Map3DAlishan.red, green = Map3DAlishan.green, cream = Map3DAlishan.cream
        let dark = Map3DAlishan.frame, glass = Map3DAlishan.glass, silver = Map3DAlishan.silver
        let half = Map3DAlishan.coachHalf, width: Float = 1.10
        let bottom: Float = 0.98, sill: Float = 1.80, line: Float = 1.88, eave: Float = 2.56
        // Underframe, its equipment and the bogies.
        box(0, 0.78, 0, half * 2 - 0.1, 1.90, bottom - 0.78, dark)
        for x: Float in [-1.5, 1.3] { box(x, 0.50, 0, 1.3, 1.2, 0.30, Map3DAlishan.chassis) }
        if !far {
            civicTube(Map3DPoint(-0.4, 0.62, -0.55), Map3DPoint(0.5, 0.62, -0.55), radius: 0.13, color: dark, sides: 10)
            box(0.0, 0.48, 0.45, 0.5, 0.3, 0.32, dark)
        }
        for x: Float in [-4.3, 4.3] { afrBogie(x, wheelbase: 1.2, radius: 0.27, frameTop: 0.78, far: far) }
        // The body: red, the white line, the dark-green window band.
        afrShell(-half, half, bottom, sill, half: width, red)
        afrShell(-half, half, sill, line, half: width, cream)
        afrShell(-half, half, line, eave, half: width, green)
        // The curved red roof, a little over the ends, and its rain strips.
        let roof: [(Float, Float)] = [(-width - 0.02, eave), (width + 0.02, eave), (width + 0.02, eave + 0.06), (1.02, eave + 0.20),
                                      (0.86, eave + 0.32), (0.58, eave + 0.40), (0.2, eave + 0.44), (-0.2, eave + 0.44),
                                      (-0.58, eave + 0.40), (-0.86, eave + 0.32), (-1.02, eave + 0.20), (-width - 0.02, eave + 0.06)]
        afrExtrude(roof, -half - 0.04, half + 0.04, red)
        for side: Float in [-1, 1] { box(0, eave + 0.04, side * (width + 0.03), half * 2 - 0.1, 0.03, 0.03, silver) }
        // Torpedo ventilators along the roof's middle.
        for x: Float in [-3.75, -1.25, 1.25, 3.75] {
            civicTube(Map3DPoint(x - 0.22, eave + 0.50, 0), Map3DPoint(x + 0.22, eave + 0.50, 0), radius: 0.07, color: Map3DColor.shaded(red, 0.8), sides: 8)
        }
        for side: Float in [-1, 1] {
            let z = side * width
            // A door at each end: grey with a tall window, its grab bars, the step.
            for end: Float in [-1, 1] {
                let x = end * (half - 0.58)
                box(x, bottom + 0.02, z, 0.70, 0.016, 1.50, dark)
                box(x, bottom + 0.04, z + side * 0.008, 0.64, 0.016, 1.46, Map3DAlishan.doorGrey)
                box(x, 1.96, z + side * 0.016, 0.30, 0.02, 0.46, dark)
                box(x, 1.99, z + side * 0.024, 0.24, 0.02, 0.40, glass)
                box(x, 0.66, side * (width - 0.04), 0.58, 0.20, 0.04, Map3DAlishan.metal)
                if !far {
                    box(x, 0.66, side * (width + 0.04), 0.04, 0.04, bottom - 0.66, dark)
                    for dx: Float in [-0.42, 0.42] {
                        beam(Map3DPoint(x + dx, 1.25, z + side * 0.045), Map3DPoint(x + dx, 2.15, z + side * 0.045), 0.028, silver)
                        for y: Float in [1.25, 2.15] { beam(Map3DPoint(x + dx, y, z), Map3DPoint(x + dx, y, z + side * 0.045), 0.022, silver) }
                    }
                }
            }
            if far {
                // One strip, cut where the lamps' ends' 2.8 m reach ends, so
                // its middle lights at night (Map3DTrainLights.windowModel).
                box(0, 1.98, z, 7.4, 0.024, 0.48, glass)
                for end: Float in [-1, 1] { box(end * 4.25, 1.98, z, 1.1, 0.024, 0.48, glass) }
            } else {
                // Eight windows, silver frames, a sash bar a third down.
                for i in 0..<8 {
                    let x = -4.375 + Float(i) * 1.25
                    box(x, 1.94, z, 1.04, 0.024, 0.58, silver)
                    box(x, 1.98, z + side * 0.012, 0.96, 0.02, 0.50, glass)
                    box(x, 2.30, z + side * 0.024, 0.96, 0.012, 0.03, silver)
                    box(x, 1.98, z + side * 0.024, 0.03, 0.012, 0.32, silver)
                }
                // The car's number plate under the middle window.
                box(0.625, 1.52, z + side * 0.008, 0.46, 0.012, 0.14, cream)
            }
        }
        for end: Float in [-1, 1] {
            let x = end * half
            // The end: the gangway door in the middle with its window, a
            // window either side in the green, the lamps low on the red.
            afrEndPlate(end, x + end * 0.016, bottom + 0.04, 0, width: 0.66, height: 1.46, face: Map3DAlishan.doorGrey, depth: 0.016)
            afrEndPlate(end, x + end * 0.026, 1.96, 0, width: 0.30, height: 0.44, face: glass, depth: 0.01)
            for side: Float in [-1, 1] {
                afrEndPlate(end, x + end * 0.016, 1.96, side * 0.70, width: 0.40, height: 0.46, face: glass, depth: 0.016)
                afrLens(end, x, height: 1.30, across: side * 0.78, radius: 0.06, far: far, housing: red)
            }
            if !far {
                // The gangway's footplate and its chains.
                box(end * (half + 0.10), bottom - 0.02, 0, 0.20, 0.70, 0.04, Map3DAlishan.metal)
                for side: Float in [-1, 1] {
                    beam(Map3DPoint(x + end * 0.02, 1.95, side * 0.40), Map3DPoint(x + end * 0.14, 1.30, side * 0.40), 0.025, Map3DAlishan.metal)
                }
            }
            // The headstock under the end, the coupler.
            box(end * (half - 0.10), 0.58, 0, 0.22, 1.70, bottom - 0.58, dark)
            afrCoupler(end, beamFace: half, tip: Map3DAlishan.coachCouplers, height: 0.66, far: far)
            for side: Float in [-1, 1] { afrCornerStep(end * (half - 0.05), side * 0.88, top: 0.58, far: far) }
        }
    }
}
