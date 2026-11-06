import Foundation

/// Decision 615: the Sun Moon Lake Ropeway's cabins, Codex's studies
/// (#1813, `tools/sunmoon-cabin-studies/produce.py`) in Swift: the shapes,
/// sizes and colours are the producer's; native space as ``CableParts``
/// (+x along the rope, +y left, +z up, metres, the origin on the rope).
///
/// Known (the producer's SOURCE): a door 80 cm wide, 140 cm deep inside, 8
/// seated in a standard cabin and 6 in a crystal one. The body 2.20 × 1.90 ×
/// 2.20 m, the hanger and the 40 mm glass floor are proportions read off
/// photographs (UNVERIFIED); the cherry-blossom paintings and the
/// operator's marks are left out. One change from the producer: the body
/// hangs 0.60 m lower on a longer hanger, its floor at
/// ``CableParts/cabinFloor`` (−4.38 m) as the Maokong cabin's, so it is
/// level with the platform of the halls the 3D map draws (decision 575,
/// ``Map3DCableCar/stationRopeHeight``); the producer's floor is −3.78 m.
extension CableSolids {
    /// The producer's body sections (height, length, width, corner radius),
    /// floor to roof, before the body is lowered.
    static let sunMoonProfile: [(Float, Float, Float, Float)] = [
        (-3.72, 1.94, 1.60, 0.32), (-3.40, 2.12, 1.82, 0.36), (-2.85, 2.20, 1.90, 0.38), (-2.45, 2.20, 1.90, 0.38),
        (-2.05, 2.05, 1.74, 0.32), (-1.82, 1.84, 1.58, 0.23), (-1.78, 1.78, 1.50, 0.19)
    ]

    /// The body's length, width and corner radius at height `z`.
    static func sunMoonSection(at z: Float) -> (Float, Float, Float) {
        let p = sunMoonProfile
        for (a, b) in zip(p, p.dropFirst()) where z <= b.0 {
            let t = (z - a.0) / (b.0 - a.0)
            return (a.1 + t * (b.1 - a.1), a.2 + t * (b.2 - a.2), a.3 + t * (b.3 - a.3))
        }
        let last = p[p.count - 1]
        return (last.1, last.2, last.3)
    }

    /// How much lower than the producer's the body hangs (see above).
    static let sunMoonLowering: Float = -CableParts.cabinFloor - 3.78

    /// An ellipsoid of `radii` round `centre`.
    mutating func ellipsoid(_ centre: P, _ radii: P, _ color: UInt32, far: Bool) {
        let n = far ? 8 : 12, rings = far ? 4 : 7
        var v = [centre + P(0, 0, -radii.z)]
        for i in 1..<rings {
            let a = -Float.pi / 2 + Float(i) * Float.pi / Float(rings)
            for j in 0..<n {
                let b = 2 * Float.pi * Float(j) / Float(n)
                v.append(centre + P(radii.x * cosf(a) * cosf(b), radii.y * cosf(a) * sinf(b), radii.z * sinf(a)))
            }
        }
        v.append(centre + P(0, 0, radii.z))
        let top = v.count - 1, last = 1 + (rings - 2) * n
        var f: [[Int]] = (0..<n).map { [0, 1 + ($0 + 1) % n, 1 + $0] }
        f += (0..<n).map { [top, last + $0, last + ($0 + 1) % n] }
        for i in 0..<(rings - 2) {
            for j in 0..<n { f.append([1 + i * n + j, 1 + i * n + (j + 1) % n, 1 + (i + 1) * n + (j + 1) % n, 1 + (i + 1) * n + j]) }
        }
        solid(v, f, color)
    }

    /// A closed door panel from `x0` to `x1` on the door side (−y),
    /// following the glazing's surface through `levels`.
    mutating func doorPatch(_ x0: Float, _ x1: Float, _ levels: [Float], _ color: UInt32) {
        var p: [P] = []
        for z in levels {
            let y = -Self.sunMoonSection(at: z).1 / 2 - 0.005
            p += [P(x0, y - 0.011, z), P(x1, y - 0.011, z), P(x1, y + 0.011, z), P(x0, y + 0.011, z)]
        }
        var faces: [[Int]] = [[0, 3, 2, 1], Array((p.count - 4)..<p.count)]
        for i in 0..<(levels.count - 1) {
            for j in 0..<4 { faces.append([4 * i + j, 4 * i + (j + 1) % 4, 4 * (i + 1) + (j + 1) % 4, 4 * (i + 1) + j]) }
        }
        solid(p, faces, color)
    }

    /// A Sun Moon Lake cabin of `livery`, near or far.
    static func sunMoonCabin(_ livery: Map3DCableCar.SunMoonCabin, far lod: Bool) -> CableSolids {
        typealias C = Map3DCableCar.SunMoonPaint
        var m = CableSolids()
        let crystal = livery == .crystal
        let accent: UInt32
        switch livery {
        case .red: accent = C.red
        case .yellow: accent = C.yellow
        case .blue: accent = C.blue
        case .crystal: accent = C.green
        }
        let floor: Float = -3.78
        let n = lod ? 8 : 12
        let profile = sunMoonProfile
        m.loft([(-3.86, 1.78, 1.44, 0.28), (-3.72, 1.94, 1.60, 0.32)], accent, far: lod, hollow: true, thickness: 0.045, nearSegments: 6)
        m.loft(profile, C.glass, far: lod, hollow: true, glass: true, thickness: 0.012, nearSegments: 6)
        m.loft([(-1.78, 1.78, 1.50, 0.19), (-1.72, 1.86, 1.56, 0.20), (-1.66, 1.78, 1.50, 0.23)], accent, far: lod, nearSegments: 6)
        if crystal {
            m.loft([(-3.86, 1.78, 1.44, 0.28), (-3.78, 1.90, 1.56, 0.30)], C.steel, far: lod, hollow: true, thickness: 0.13, nearSegments: 6)
            m.box(0, 0, floor - 0.040, 1.64, 1.30, 0.040, C.glass, glass: true)
        } else {
            m.loft([(-3.86, 1.78, 1.44, 0.28), (-3.78, 1.90, 1.56, 0.30)], C.deck, far: lod, nearSegments: 6)
        }
        // Four curved coloured corner mullions, their gaskets and buffers.
        let corner = Float(1) / Float(2).squareRoot()
        for sx: Float in [-1, 1] {
            for sy: Float in [-1, 1] {
                let levels = [(Float(-3.82), Float(1.84), Float(1.50), Float(0.30))] + profile + [(-1.72, 1.86, 1.56, 0.20)]
                let path = levels.map { z, l, w, r in P(sx * (l / 2 - r + r * corner), sy * (w / 2 - r + r * corner), z) }
                m.tube(path, 0.065, C.dark, far: lod)
                m.tube(path.map { P($0.x + sx * 0.018, $0.y + sy * 0.018, $0.z) }, 0.053, accent, far: lod)
                let (l, w, r) = sunMoonSection(at: -2.98)
                m.ellipsoid(P(sx * (l / 2 - r + r * corner + 0.02), sy * (w / 2 - r + r * corner + 0.02), -2.98), P(0.080, 0.080, 0.23), C.dark, far: lod)
            }
        }
        // Two benches facing each other, folded down.
        for sign: Float in [-1, 1] {
            for y: Float in [-0.45, 0.45] { m.box(sign * 0.86, y, floor, 0.08, 0.10, 0.44, C.steel) }
            m.box(sign * 0.70, 0, floor + 0.44, 0.40, 1.24, 0.08, C.blue)
            m.box(sign * 0.87, 0, floor + 0.52, 0.06, 1.24, 0.42, C.blue)
            m.cylinder(P(sign * 0.86, -0.61, floor + 0.46), P(sign * 0.86, 0.61, floor + 0.46), 0.025, C.steel, sides: n)
            if !lod { for y: Float in [-0.31, 0, 0.31] { m.box(sign * 0.70, y, floor + 0.52, 0.36, 0.009, 0.005, C.steel) } }
        }
        // The door: 0.80 m clear between the frames, two lower panels.
        let doorLevels = [(floor, Float(0.77))] + profile.map { ($0.0, $0.2 / 2) }
        for x: Float in [-0.43, 0, 0.43] {
            m.tube(doorLevels.map { P(x, -$0.1 - 0.007, $0.0) }, x != 0 ? 0.03 : 0.02, x != 0 ? accent : C.dark, far: lod)
        }
        m.beam(P(-0.43, -0.757, -1.78), P(0.43, -0.757, -1.78), 0.05, accent)
        m.box(0, -0.755, floor - 0.025, 0.86, 0.08, 0.025, C.steel)
        for (a, b) in [(Float(-0.40), Float(-0.012)), (0.012, 0.40)] { m.doorPatch(a, b, [-3.72, -3.40, -3.34], accent) }
        if !lod {
            for z: Float in [-3.05, -2.75, -2.45] {
                let y = -sunMoonSection(at: z).1 / 2
                for (a, b) in [(Float(-0.35), Float(-0.07)), (0.07, 0.35)] {
                    m.beam(P(a, y - 0.025, z), P(b, y - 0.025, z), 0.018, C.steel)
                    for x in [a, b] { m.beam(P(x, y + 0.006, z), P(x, y - 0.025, z), 0.018, C.steel) }
                }
            }
        }
        // Vent strips on the broad end windows.
        for sx: Float in [-1, 1] {
            for z: Float in lod ? [-1.98] : [-2.07, -2.00, -1.93] {
                let x = sx * (sunMoonSection(at: z).0 / 2 - 0.003)
                m.beam(P(x, -0.48, z), P(x, 0.48, z), 0.018, C.steel)
            }
            for y: Float in [-0.47, 0.47] {
                m.tube([Float(-2.10), -1.90].map { P(sx * (sunMoonSection(at: $0).0 / 2 - 0.003), y, $0) }, 0.014, C.dark, far: lod)
            }
        }
        m.loft([(-3.84, 2.00, 1.65, 0.32), (-3.815, 2.00, 1.65, 0.32)], C.steel, far: lod, hollow: true, thickness: 0.025, nearSegments: 6)
        for x: Float in [-0.60, 0.60] {
            for sy: Float in [-1, 1] { m.beam(P(x, sy * 0.65, -3.827), P(x, sy * 0.81, -3.827), 0.025, C.steel) }
        }
        // The roof lamp (its place an estimate), lit at night.
        m.box(0, -0.32, -1.796, 0.46, 0.12, 0.016, C.steel)
        m.box(0, -0.32, -1.802, 0.42, 0.10, 0.006, C.warm, glow: true)
        // Four roof pads and the spider frame on the closed roof.
        for x: Float in [-0.62, 0.62] {
            for y: Float in [-0.50, 0.50] {
                m.cylinder(P(x, y, -1.66), P(x, y, -1.58), 0.06, C.dark, sides: n)
                m.beam(P(x, y, -1.58), P(0, 0, -1.38), 0.065, C.steel)
            }
        }
        for y: Float in [-0.50, 0.50] { m.beam(P(-0.62, y, -1.57), P(0.62, y, -1.57), 0.055, C.steel) }
        m.box(0, 0, -1.46, 0.40, 0.32, 0.12, C.steel)
        m.cylinder(P(0, -0.20, -1.40), P(0, 0.20, -1.40), 0.065, C.steel, sides: n)
        // The solar panel, tilted 30°, on four feet.
        let angle = Float.pi / 6, ca = cosf(angle), sa = sinf(angle)
        for u: Float in [-0.25, 0.25] {
            for v: Float in [-0.28, 0.28] {
                let q = P(0.52 + ca * u, v, -1.40 - sa * u)
                m.beam(P(q.x, q.y, -1.66), q, 0.027, C.steel)
            }
        }
        let start = m.triangles.count
        m.box(0, 0, 0, 0.64, 0.72, 0.035, C.steel)
        m.box(0, 0, 0.035, 0.58, 0.66, 0.005, C.dark)
        if !lod {
            for u: Float in [-0.145, 0, 0.145] { m.box(u, 0, 0.040, 0.004, 0.65, 0.002, C.steel) }
            for v: Float in [-0.22, 0, 0.22] { m.box(0, v, 0.040, 0.57, 0.004, 0.002, C.steel) }
        }
        m.transform(from: start) { p in P(0.52 + ca * p.x + sa * p.z, p.y, -1.40 - sa * p.x + ca * p.z) }
        // The body hangs lower (see the type's note); the bent hanger
        // grows by as much in its straight part.
        let drop = sunMoonLowering
        m.shift(from: 0, dz: -drop)
        m.tube([P(0, 0, -1.40 - drop), P(0, 0.22, -1.32 - drop), P(0, 0.41, -1.05 - drop), P(0, 0.39, -0.65), P(0, 0.20, -0.14)],
               0.065, C.steel, far: lod)
        // The grip on the rope: its outside only, the channel along +x.
        m.box(0, 0, -0.18, 0.68, 0.32, 0.10, C.steel)
        m.box(0, 0, -0.08, 0.65, 0.18, 0.025, C.dark)
        for y: Float in [-0.075, 0.075] { m.box(0, y, -0.055, 0.65, 0.04, 0.11, C.steel) }
        m.box(0, 0, 0.055, 0.65, 0.19, 0.035, C.steel)
        if !lod {
            for x: Float in [-0.25, 0.25] { m.beam(P(x, -0.12, -0.16), P(x, -0.22, 0.12), 0.035, C.steel) }
            m.cylinder(P(-0.25, -0.22, 0.12), P(0.25, -0.22, 0.12), 0.035, C.dark, sides: 12)
            for i in 0..<7 {
                let x = -0.24 + Float(i) * 0.07
                m.cylinder(P(x, -0.22, 0.12), P(x + 0.025, -0.22, 0.12), 0.055, C.steel, sides: 8)
            }
            m.beam(P(0.25, -0.22, 0.12), P(0.43, -0.22, 0.20), 0.04, C.steel)
        }
        return m
    }
}

extension Map3DCableCar {
    /// Decision 615: the Sun Moon Lake Ropeway's cabins: the standard
    /// cabin in its three colours and the green crystal cabin.
    public enum SunMoonCabin: String, CaseIterable, Sendable { case red, yellow, blue, crystal }

    /// Codex's palette for them (#1813); the glass a dark navy tint.
    enum SunMoonPaint {
        static let blue = Map3DColor.rgb(0x5F8BC0)
        static let red = Map3DColor.rgb(0xC65A4E)
        static let green = Map3DColor.rgb(0x5E8F86)
        static let yellow = Map3DColor.rgb(0xFFC86B)
        static let steel = Map3DColor.rgb(0x6E747B)
        static let dark = Map3DColor.rgb(0x26385C)
        static let deck = Map3DColor.rgb(0xDCD6C8)
        static let glass = Map3DColor.rgb(0x26385C)
        static let warm = Map3DColor.rgb(0xFFE2A6)
    }

    /// Decision 615: a cabin's marked glass see-through
    /// (``Map3DTransparentGlass``) in the near model; the far model keeps
    /// it opaque, mirroring the sky as a train's windows do. Each frame the
    /// renderer sorts every see-through triangle on the main thread, and
    /// a cabin past ``Map3DCableways/nearReach`` is a few pixels.
    static func seeThrough(_ model: Map3DModelPack.Model, far: Bool) -> Map3DModelPack.Model {
        far ? model : Map3DTransparentGlass.applying(to: model)
    }

    /// Decision 615: a Sun Moon Lake cabin, its glass see-through near.
    public static func model(_ cabin: SunMoonCabin, far: Bool = false) -> Map3DModelPack.Model {
        var m = CableMesh()
        CableSolids.sunMoonCabin(cabin, far: far).append(to: &m.kit.mesh)
        let made = Map3DModelPack.Model.flat(named: "cablecar-cabin-sunmoon-" + cabin.rawValue + (far ? "-far" : ""), from: m.kit.mesh)
        return seeThrough(made, far: far)
    }

    /// The livery of Sun Moon Lake cabin `number`: crystal as the Maokong
    /// cabins' rule picks (``CablewayCabins/isCrystal(_:)``), the others
    /// red, yellow and blue in turn.
    public static func sunMoonCabin(_ number: Int) -> SunMoonCabin {
        if CablewayCabins.isCrystal(number) { return .crystal }
        return [SunMoonCabin.red, .yellow, .blue][((number % 3) + 3) % 3]
    }
}
