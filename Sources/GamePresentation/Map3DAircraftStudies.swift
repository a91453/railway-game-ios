import Foundation

/// On-demand geometry for studies. Native x forward, y left, z up; metres.
/// These models are not registered in the game scene or used for operations.
///
/// Decision 698 rebuilt their look: a lofted fuselage with a nose and an
/// upswept tail, aerofoil wings and tails, nacelles with propellers or
/// intakes, and round wheels. Length, wingspan and height are the makers'
/// published figures; the rest is read off photographs.
public enum Map3DAircraftStudies {
    public enum Kind: String, CaseIterable, Sendable {
        case commuter19, regional70, narrowJet, wideJet
    }
    public struct Dimensions: Sendable {
        public let length: Float
        public let wingspan: Float
        public let height: Float
    }
    public struct Joint: Sendable {
        public let part: String
        public let pivot: Map3DPoint
        public let axis: Map3DPoint
        public let lower: Float
        public let upper: Float
    }
    public struct Metadata: Sendable {
        public let dimensions: Dimensions
        public let door: Map3DPoint
        public let joints: [Joint]
        public let glowParts: [String]
    }

    /// The shape of one type. Stations run from the nose (`s`, metres
    /// behind it); `top` and `bottom` are in half-heights from the fuselage
    /// centre line.
    struct Shape {
        var halfWidth: Float, halfHeight: Float, centre: Float, exponent: Float
        var hull: [(s: Float, k: Float, top: Float, bottom: Float)]
        var cockpit: Int
        /// The band behind the windscreen carries the side windows.
        var sideWindows = false
        var cabin: (from: Float, to: Float, pitch: Float, width: Float, low: Float, high: Float)
        var door: (s: Float, width: Float)
        var wing: [(y: Float, s: Float, chord: Float, z: Float, t: Float)]
        var winglet: [(y: Float, s: Float, chord: Float, z: Float, t: Float, lean: Float)] = []
        var fin: [(z: Float, s: Float, chord: Float, t: Float)]
        var tail: [(y: Float, s: Float, chord: Float, z: Float, t: Float)]
        var engine: (y: Float, z: Float, r: Float, from: Float, to: Float, cone: Float, propeller: Float, blades: Int)
        var noseGear: (s: Float, r: Float, offset: Float)
        var mainGear: (s: Float, y: Float, r: Float, offset: Float, bogie: Float)
        var sponson: (from: Float, to: Float, y: Float, z: Float, halfWidth: Float, halfHeight: Float)?
        var paintedTipBands = 0

        func sideY(_ z: Float) -> Float {
            halfWidth * powf(1 - powf(min(1, abs(z / halfHeight)), exponent), 1 / exponent)
        }
    }

    /// Review L19, P3-3: each type's shape, made once (the lamps and the
    /// camera's seat read it every frame).
    private static let shapes: [Kind: Shape] = Dictionary(uniqueKeysWithValues: Kind.allCases.map { ($0, made($0)) })

    static func shape(_ kind: Kind) -> Shape { shapes[kind] ?? made(kind) }

    private static func made(_ kind: Kind) -> Shape {
        switch kind {
        case .commuter19:
            Shape(halfWidth: 0.80, halfHeight: 0.95, centre: 1.57, exponent: 3.6,
                  hull: [(0, 0.07, -0.38, -0.56), (0.5, 0.34, -0.12, -0.80), (1.4, 0.62, 0.18, -0.95), (2.35, 0.86, 0.50, -1),
                         (3.25, 1, 1, -1), (9.6, 1, 1, -1), (12.2, 0.72, 1, -0.30), (15.2, 0.34, 0.96, 0.30), (16.56, 0.10, 0.90, 0.62)],
                  cockpit: 3, cabin: (3.9, 9.3, 0.80, 0.40, 0.10, 0.58), door: (9.9, 0.72),
                  wing: [(0, 5.75, 2.05, 2.67, 0.30), (5.0, 5.75, 2.05, 2.71, 0.28), (7.6, 6.45, 1.25, 2.73, 0.18), (8.485, 7.25, 0.42, 2.74, 0.07)],
                  fin: [(2.36, 12.1, 3.7, 0.20), (2.9, 13.0, 2.9, 0.18), (4.86, 14.55, 1.75, 0.12)],
                  tail: [(0.2, 14.3, 1.50, 2.16, 0.14), (3.25, 14.6, 1.15, 2.22, 0.10)],
                  engine: (2.45, 2.34, 0.34, 4.35, 7.9, 0, 1.25, 5),
                  noseGear: (1.75, 0.24, 0), mainGear: (8.0, 1.65, 0.34, 0, 0),
                  sponson: (6.6, 9.1, 1.10, 0.92, 0.50, 0.34), paintedTipBands: 2)
        case .regional70:
            Shape(halfWidth: 1.435, halfHeight: 1.435, centre: 2.15, exponent: 2,
                  hull: [(0, 0.07, -0.30, -0.46), (0.45, 0.40, 0.02, -0.72), (1.3, 0.70, 0.42, -0.90), (1.75, 0.78, 0.58, -0.93), (2.5, 0.90, 0.82, -0.98), (3.1, 0.95, 0.92, -0.99),
                         (3.9, 1, 1, -1), (15.8, 1, 1, -1), (19.5, 0.80, 1, -0.35), (23.5, 0.45, 0.98, 0.25), (26.2, 0.14, 0.95, 0.72)],
                  cockpit: 3, sideWindows: true, cabin: (4.9, 18.4, 0.78, 0.30, 0.16, 0.50), door: (19.6, 0.70),
                  wing: [(0, 10.9, 2.62, 3.68, 0.47), (4.7, 10.9, 2.62, 3.74, 0.45), (13.525, 11.35, 1.55, 3.88, 0.24)],
                  fin: [(3.44, 17.2, 8.6, 0.30), (4.4, 20.6, 5.4, 0.30), (7.65, 24.5, 2.5, 0.20)],
                  tail: [(0, 24.9, 2.27, 7.48, 0.20), (3.65, 25.6, 1.40, 7.50, 0.14)],
                  engine: (4.05, 3.18, 0.50, 8.75, 15.2, 0, 1.965, 6),
                  noseGear: (2.6, 0.23, 0.16), mainGear: (13.4, 2.05, 0.42, 0.20, 0),
                  sponson: (11.0, 15.8, 1.50, 1.20, 0.70, 0.52))
        case .narrowJet:
            Shape(halfWidth: 1.975, halfHeight: 2.07, centre: 3.72, exponent: 2,
                  hull: [(0, 0.06, -0.12, -0.30), (0.6, 0.40, 0.18, -0.62), (1.5, 0.64, 0.46, -0.82), (2.25, 0.78, 0.66, -0.90), (2.9, 0.86, 0.82, -0.955), (3.6, 0.93, 0.92, -0.98),
                         (5.4, 1, 1, -1), (29.5, 1, 1, -1), (34, 0.86, 1, -0.55), (39, 0.52, 0.98, 0.05), (43.3, 0.20, 0.92, 0.52), (44.51, 0.07, 0.86, 0.70)],
                  cockpit: 3, sideWindows: true, cabin: (6.6, 36.4, 0.56, 0.30, 0.30, 0.72), door: (5.6, 0.90),
                  wing: [(1.2, 14.9, 7.0, 2.44, 0.85), (1.95, 15.3, 6.6, 2.46, 0.80), (6.3, 17.6, 4.2, 2.80, 0.50), (16.6, 23.0, 1.65, 3.75, 0.18)],
                  winglet: [(17.25, 23.45, 1.45, 3.98, 0.16, 0.5), (17.70, 23.95, 1.15, 4.60, 0.12, 1), (17.84, 24.85, 0.55, 6.15, 0.10, 1)],
                  fin: [(5.58, 34.0, 6.6, 0.45), (11.76, 41.0, 2.3, 0.16)],
                  tail: [(0.3, 37.4, 4.4, 4.45, 0.36), (6.22, 41.3, 1.5, 5.0, 0.14)],
                  engine: (5.75, 1.74, 1.22, 11.6, 16.4, 17.7, 0, 0),
                  noseGear: (5.6, 0.37, 0.25), mainGear: (22.4, 3.8, 0.58, 0.42, 0))
        case .wideJet:
            Shape(halfWidth: 2.98, halfHeight: 3.045, centre: 5.10, exponent: 2,
                  hull: [(0, 0.06, -0.15, -0.32), (0.8, 0.42, 0.20, -0.66), (2.0, 0.66, 0.50, -0.84), (3.1, 0.80, 0.70, -0.91), (3.95, 0.88, 0.84, -0.965), (4.9, 0.94, 0.93, -0.985),
                         (7.2, 1, 1, -1), (43.5, 1, 1, -1), (51, 0.86, 1, -0.50), (59, 0.50, 0.98, 0.08), (65, 0.20, 0.93, 0.55), (66.8, 0.07, 0.88, 0.72)],
                  cockpit: 3, sideWindows: true, cabin: (8.8, 54.5, 0.60, 0.32, 0.28, 0.66), door: (8.0, 1.05),
                  wing: [(1.5, 23.0, 13.0, 3.25, 1.5), (2.95, 24.0, 12.0, 3.30, 1.3), (10.2, 29.3, 6.6, 3.95, 0.75), (28.5, 42.2, 2.6, 6.10, 0.26),
                         (30.6, 44.6, 1.7, 6.75, 0.18), (31.8, 46.6, 0.9, 7.35, 0.12), (32.375, 48.3, 0.35, 7.90, 0.06)],
                  fin: [(8.0, 50.5, 9.6, 0.70), (17.05, 61.0, 3.4, 0.24)],
                  tail: [(0.5, 56.0, 6.6, 6.30, 0.50), (9.35, 62.2, 2.2, 7.10, 0.20)],
                  engine: (10.5, 2.70, 1.95, 23.4, 29.9, 31.6, 0, 0),
                  noseGear: (6.6, 0.50, 0.33), mainGear: (35.4, 5.3, 0.68, 0.60, 0.95), paintedTipBands: 3)
        }
    }

    static func isJet(_ kind: Kind) -> Bool { kind == .narrowJet || kind == .wideJet }
    /// The livery colours: blue, green, red, navy. No operator's marks.
    static let paints: [UInt32] = [Map3DStudyColor.blue, Map3DStudyColor.green, Map3DStudyColor.red, Map3DStudyColor.navy]
    static func defaultPalette(_ kind: Kind) -> Int {
        switch kind { case .commuter19: 2; case .regional70: 0; case .narrowJet: 1; case .wideJet: 3 }
    }

    public static func metadata(_ kind: Kind) -> Metadata {
        let d = dimensions(kind), s = shape(kind), sill = s.centre - s.halfHeight * 0.42
        func x(_ behind: Float) -> Float { d.length / 2 - behind }
        let props: [Joint] = isJet(kind) ? [] : [-1, 1].map { side in
            Joint(part: "propeller-\(side)", pivot: Map3DPoint(x(s.engine.from - 0.22), Float(side) * s.engine.y, s.engine.z),
                  axis: Map3DPoint(1, 0, 0), lower: 0, upper: 2 * .pi)
        }
        return Metadata(dimensions: d, door: Map3DPoint(x(s.door.s + s.door.width / 2), s.sideY(0), sill),
            joints: props + [Joint(part: "landing-gear", pivot: Map3DPoint(x(s.mainGear.s), 0, s.centre - s.halfHeight * 0.55),
                                   axis: Map3DPoint(0, 1, 0), lower: 0, upper: kind == .commuter19 ? 0 : 1.2),
                             Joint(part: "door", pivot: Map3DPoint(x(s.door.s), s.sideY(0), sill), axis: Map3DPoint(0, 0, 1), lower: 0, upper: 1.57)],
            glowParts: ["left-red", "right-green", "tail-white", "anti-collision-red", "strobe-white", "cabin-windows"])
    }
    public static func dimensions(_ kind: Kind) -> Dimensions {
        switch kind {
        case .commuter19: Dimensions(length:16.56,wingspan:16.97,height:4.86)
        case .regional70: Dimensions(length:27.17,wingspan:27.05,height:7.65)
        case .narrowJet: Dimensions(length:44.51,wingspan:35.80,height:11.76)
        case .wideJet: Dimensions(length:66.80,wingspan:64.75,height:17.05)
        }
    }

    /// `palette` picks the livery colour (0 blue, 1 green, 2 red, 3 navy);
    /// `nil` is the type's own.
    public static func model(_ kind: Kind, far: Bool = false, palette: Int? = nil) -> Map3DModelPack.Model {
        let length = dimensions(kind).length, s = shape(kind), jet = isJet(kind)
        let paint = paints[max(0, min(paints.count - 1, palette ?? defaultPalette(kind)))]
        let c = Map3DStudyColor.self
        let hw = s.halfWidth, hh = s.halfHeight, zc = s.centre
        func x(_ behind: Float) -> Float { length / 2 - behind }
        let n = far ? 16 : 24
        var m = Map3DStudyMesh()

        // Fuselage: one closed skin. The windscreen, the belly and the
        // painted tail are colours of its own faces, so nothing floats on it.
        let rings = s.hull.map { Map3DStudyMesh.section(x($0.s), zc + hh * ($0.top + $0.bottom) / 2, hw * $0.k, hh * ($0.top - $0.bottom) / 2, hh * ($0.top - $0.bottom) / 2, n, s.exponent) }
        let tailFrom = s.hull.firstIndex { $0.s > length * 0.5 && $0.k < 1 }! - 1
        m.loft(rings) { band, i in
            guard case .band(let k) = band else { return (band == .start ? c.white : paint, false) }
            let up = min(i, n / 2 - 1 - i)          // 0 is the face just above the waist, either side
            if k == s.cockpit && up >= 1 && i < n / 2 { return (c.cockpit, false) }      // the windscreen: a strip round the nose
            if s.sideWindows && k == s.cockpit + 1 && up >= 1 && up <= (far ? 1 : 2) && i < n / 2 { return (c.cockpit, false) }   // and the side windows behind it
            if k >= tailFrom + (jet ? 1 : 2) { return (paint, false) }
            if jet && i >= n / 2 && min(i - n / 2, n - 1 - i) >= n / 8 { return (c.belly, false) }
            if !jet && (i == n - 1 || i == n / 2) && s.cockpit < k { return (paint, false) }   // cheat line at the waist
            return (c.white, false)
        }
        func onSide(_ s0: Float, _ s1: Float, _ z0: Float, _ z1: Float, _ color: UInt32, glow: Bool, sides: [Float] = [-1, 1], out: Float = 0.02, back: Float = 0.04) {
            for side in sides {
                let corners = [Map3DPoint(x(s0), side * s.sideY(z0), zc + z0), Map3DPoint(x(s1), side * s.sideY(z0), zc + z0),
                               Map3DPoint(x(s1), side * s.sideY(z1), zc + z1), Map3DPoint(x(s0), side * s.sideY(z1), zc + z1)]
                m.slab(side > 0 ? corners : corners.reversed(), color, glow: glow, out: out, back: back)
            }
        }
        if far {
            onSide(s.cabin.from, s.cabin.to, s.cabin.low * hh, s.cabin.high * hh, c.window, glow: true)
        } else {
            for i in 0...Int((s.cabin.to - s.cabin.from) / s.cabin.pitch) {
                let from = s.cabin.from + Float(i) * s.cabin.pitch
                onSide(from, from + s.cabin.width, s.cabin.low * hh, s.cabin.high * hh, c.window, glow: true)
            }
            for (low, high) in [(-0.42, -0.14), (-0.14, 0.14), (0.14, 0.42)] as [(Float, Float)] {
                onSide(s.door.s, s.door.s + s.door.width, low * hh, high * hh, c.belly, glow: false, sides: [1], out: 0.025, back: 0.03)
            }
        }

        // Wings, tailplane and fin: aerofoil sections, thick at the root.
        for side: Float in [-1, 1] {
            var w = s.wing.map { Map3DStudyMesh.aerofoil(Map3DPoint(x($0.s), side * $0.y, $0.z), $0.chord, $0.t) }
            let tips = w.count
            for g in s.winglet {
                let lean = Map3DPoint(0, side * g.lean, 1 - g.lean)
                w.append(Map3DStudyMesh.aerofoil(Map3DPoint(x(g.s), side * g.y, g.z), g.chord, g.t, across: lean * (1 / lean.length)))
            }
            let tipFrom = s.winglet.isEmpty ? w.count - s.paintedTipBands : tips - 1, count = w.count
            m.loft(w) { band, _ in
                switch band {
                case .start: (c.belly, false)
                case .end: (tipFrom < count ? paint : c.belly, false)
                case .band(let k): (tipFrom < count && k >= tipFrom ? paint : c.belly, false)
                }
            }
            m.loft(s.tail.map { Map3DStudyMesh.aerofoil(Map3DPoint(x($0.s), side * $0.y, $0.z), $0.chord, $0.t) }, c.belly)
        }
        m.loft(s.fin.map { Map3DStudyMesh.aerofoil(Map3DPoint(x($0.s), 0, $0.z), $0.chord, $0.t, across: Map3DPoint(0, 1, 0)) }, paint)
        let tip = s.wing[s.wing.count - 1], top = zc + hh
        if !far {
            for side: Float in [-1, 1] {
                m.box(x(tip.s) - 0.2, side * (tip.y - 0.42), tip.z + 0.02, 0.22, 0.18, 0.09, c.lamp, glow: true)
                m.box(x(tip.s) - 0.02, side * (tip.y - 0.42), tip.z + 0.02, 0.20, 0.18, 0.09, side > 0 ? c.lampRed : c.lampGreen, glow: true)
            }
            m.box(-length / 2 + 0.25, 0, zc + hh * s.hull[s.hull.count - 1].top - 0.02, 0.22, 0.14, 0.10, c.lamp, glow: true)
            m.box(x(length * 0.42), 0, top - 0.03, 0.30, 0.26, 0.16, c.lampRed, glow: true)
            m.box(x(length * 0.46), 0, zc - hh - 0.10, 0.28, 0.24, 0.13, c.lampRed, glow: true)
        } else {
            for _ in 0..<5 { m.box(x(length * 0.42), 0, top - 0.03, 0.30, 0.26, 0.12, c.lampRed, glow: true) }
        }

        let e = s.engine
        for side: Float in [-1, 1] {
            let ey = side * e.y, sides = far ? 8 : 14, a = e.from, b = e.to, r = e.r
            func ring(_ behind: Float, _ radius: Float, _ dz: Float = 0) -> [Map3DPoint] {
                (0..<sides).map { i in
                    let angle = 2 * Float.pi * Float(i) / Float(sides)
                    return Map3DPoint(x(behind), ey + radius * cosf(angle), e.z + dz + radius * sinf(angle))
                }
            }
            if jet {
                m.loft([ring(a, r * 0.84), ring(a + 0.22, r * 0.97), ring(a + 0.5, r), ring(a + (b - a) * 0.55, r), ring(b, r * 0.70)]) { band, _ in
                    switch band {
                    case .start, .end: (c.cockpit, false)
                    case .band(0): (c.hub, false)
                    case .band(1), .band(2): (paint, false)
                    default: (c.belly, false)
                    }
                }
                m.loft([ring(b - 0.2, r * 0.46), ring(e.cone, r * 0.12)], c.metal)
                if !far { m.loft([ring(a + 0.5, r * 0.30), ring(a - 0.12, r * 0.06)], c.hub) }
                let leading = s.wing[2].s, under = s.wing[2].z - 0.12
                func pylon(_ y: Float) -> [Map3DPoint] {
                    [Map3DPoint(x(a + (b - a) * 0.30), y, e.z + r * 0.85), Map3DPoint(x(b + 0.3), y, e.z + r * 0.35),
                     Map3DPoint(x(leading + (b - a) * 0.55), y, under), Map3DPoint(x(leading - 0.2), y, under)]
                }
                m.loft([pylon(ey - 0.17), pylon(ey + 0.17)], c.belly)
            } else {
                m.loft([ring(a, r * 0.62), ring(a + 0.5, r), ring(a + (b - a) * 0.5, r * 0.96, 0.04), ring(b, r * 0.22, 0.16)]) { band, _ in
                    if case .band = band { return (c.white, false) }
                    return (c.metal, false)
                }
                m.loft([ring(a + 0.02, r * 0.50), ring(a - 0.55, r * 0.10)], paint)
                let hub = Map3DPoint(x(a - 0.22), ey, e.z), blades = far ? 3 : e.blades
                for k in 0..<blades {
                    let angle = 2 * Float.pi * Float(k) / Float(blades) + 0.3, radial = Map3DPoint(0, cosf(angle), sinf(angle))
                    m.bar(hub + radial * (r * 0.3), hub + radial * e.propeller, e.propeller * 0.13, 0.07, c.tyre, up: Map3DPoint(1, 0, 0))
                }
            }
        }

        // Undercarriage: round wheels on struts that reach the airframe.
        let nose = s.noseGear
        m.cylinder(Map3DPoint(x(nose.s), 0, nose.r), Map3DPoint(x(nose.s), 0, zc - hh * 0.80), kind == .wideJet ? 0.14 : 0.09, c.metal, sides: 6)
        for y in (nose.offset > 0 && !far ? [-nose.offset, nose.offset] : [0]) {
            m.wheel(x(nose.s), y, nose.r, nose.offset > 0 ? 0.16 : 0.20, far: far)
        }
        let main = s.mainGear
        for side: Float in [-1, 1] {
            let strutTop = jet ? s.wing[1].z - 0.1 : zc - hh * 0.55
            m.cylinder(Map3DPoint(x(main.s), side * main.y, main.r), Map3DPoint(x(main.s), side * (jet ? main.y : main.y - 0.35), strutTop), jet ? 0.13 : 0.08, c.metal, sides: 6)
            for dx in (main.bogie > 0 ? [-main.bogie, main.bogie] : [0]) {
                if main.bogie > 0 {
                    m.bar(Map3DPoint(x(main.s) - main.bogie, side * main.y, main.r), Map3DPoint(x(main.s) + main.bogie, side * main.y, main.r), 0.2, 0.2, c.metal)
                }
                for dy in (main.offset > 0 && !far ? [-main.offset, main.offset] : [0]) {
                    m.wheel(x(main.s) + dx, side * main.y + dy, main.r, main.offset > 0 ? main.r * 0.62 : main.r * 0.7, far: far)
                }
            }
            if let p = s.sponson {
                let stations: [(Float, Float)] = [(0, 0.25), (0.25, 0.9), (0.6, 1), (1, 0.3)]
                m.loft(stations.map { Map3DStudyMesh.section(x(p.from + (p.to - p.from) * $0.0), p.z, p.halfWidth * $0.1, p.halfHeight * $0.1, p.halfHeight * $0.1, far ? 8 : 12, 2.6, y: side * p.y) }, c.white)
            }
        }
        if jet {
            // The belly fairing under the wing, and the flap-track fairings behind it.
            let ws = s.wing, a = ws[1].s - ws[1].chord * 0.12, b = ws[1].s + ws[1].chord * 1.12
            let stations: [(Float, Float)] = [(0, 0.3), (0.2, 0.9), (0.75, 1), (1, 0.3)]
            m.loft(stations.map { Map3DStudyMesh.section(x(a + (b - a) * $0.0), zc - hh * 0.80, hw * 1.06 * $0.1, hh * 0.36 * $0.1, hh * 0.36 * $0.1, far ? 8 : 12, 2.6) }, c.belly)
            if !far {
                let reach = s.winglet.isEmpty ? ws[3].y : ws[ws.count - 1].y
                for side: Float in [-1, 1] {
                    for f: Float in [0.30, 0.52, 0.74] {
                        let y = ws[1].y + reach * f
                        let k = (0..<(ws.count - 1)).first { ws[$0].y <= y && y <= ws[$0 + 1].y }!, lo = ws[k], hi = ws[k + 1]
                        let u = (y - lo.y) / (hi.y - lo.y)
                        let trailing = lo.s + lo.chord + (hi.s + hi.chord - lo.s - lo.chord) * u, z = lo.z + (hi.z - lo.z) * u, chord = lo.chord + (hi.chord - lo.chord) * u
                        let shape: [(Float, Float)] = [(0, 0.4), (0.35, 1), (1, 0.25)]
                        m.loft(shape.map { Map3DStudyMesh.section(x(trailing - chord * 0.55 + chord * 0.85 * $0.0), z - 0.10 - chord * 0.03, hw * 0.085 * $0.1 + 0.04, hw * 0.075 * $0.1 + 0.04, hw * 0.075 * $0.1 + 0.04, 6, 2, y: side * y) }, c.belly)
                    }
                }
            }
        }
        if kind == .regional70 && !far {
            let stations: [(Float, Float)] = [(9.2, 0.3), (10.6, 1), (13.6, 1), (16.2, 0.3)]
            m.loft(stations.map { Map3DStudyMesh.section(x($0.0), zc + hh - 0.05, 1.05 * $0.1, 0.50 * $0.1, 0.2, 12, 2.4) }, c.white)
        }
        return m.model(named: "aircraft-\(kind.rawValue)-\(far ? "far" : "near")")
    }
}
