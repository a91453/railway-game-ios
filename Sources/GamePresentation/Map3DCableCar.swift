import Foundation

/// Decision 575: the Maokong Gondola's native 3D studies, near and far: the
/// two cabins (standard and crystal), a tower with its sheave batteries, the
/// rope between two towers, and three station halls (through, angle and
/// terminal). Static models for the tools and the train garage (the studies
/// pack); nothing in the game draws them until the cable-car type of
/// decision 574 places them.
///
/// Sources and what is not known (UNVERIFIED = a design value, not a survey):
/// the line is a POMA monocable detachable gondola, 4.03 km (POMA's page:
/// 4,105 m), four stations, 47 towers, 147 cabins at 6 m/s; a standard cabin
/// takes 8 sitting (640 kg), a crystal cabin 5 (400 kg) and has a 48 mm
/// laminated glass floor (30 cabins, from 2010-03-30) — Wikipedia "Maokong
/// Gondola", poma.net, Taipei Fun Pass. The cabins and the station
/// furnishings are Codex's studies (#1791, #1786) in Swift, see
/// ``CableParts``; the rope spacing, the tower height, the hall sizes and the
/// tower's and halls' colours are UNVERIFIED design values; no photograph was
/// taken from the reference repositories (`docs/art/cable-maokong-2026-11-04`).
///
/// Space: native, +x along the rope (the way the cabin faces), +y left, +z
/// up, metres. A cabin's origin is its rope (z 0, the grip on it, the body
/// hangs below at negative z); the tower, the stations and the span stand on
/// the ground at z 0 with the rope line at x ±, y ±``ropeSpacing`` / 2.
public enum Map3DCableCar {
    public enum Cabin: String, CaseIterable, Sendable { case standard, crystal }
    public enum Station: String, CaseIterable, Sendable { case through, corner, terminal }
    /// Station furnishings that stand alone (the platform, gate and queue
    /// rails are part of the stations): Codex's studies, #1786.
    public enum Support: String, CaseIterable, Sendable { case gate, kiosk, catwalk }

    /// The two ropes' distance apart, up line and down line.
    public static let ropeSpacing: Float = 5.2
    /// How far the corner station turns the line, to the right (−y).
    public static let cornerAngle: Float = 24 * .pi / 180
    /// The boarding platform's top above the station floor's foot (Codex's
    /// study, #1786).
    public static let platformHeight: Float = 0.60
    /// The ropes' height in a station: the cabin floor level with the
    /// platform, plus the cabin's drop.
    public static let stationRopeHeight: Float = platformHeight + cabinDrop
    public static let towerHeight: Float = 14

    /// Where the cabin's floor is below the rope (Codex's study, #1791: the
    /// body hangs 0.78 m lower than the first draft's 3.6 m).
    public static let cabinDrop: Float = -CableParts.cabinFloor
    /// The cabin body: length along the rope, width across it. From the
    /// customer-service figure 1.98 × 1.873 m (UNVERIFIED, not a drawing).
    public static let cabinLength: Float = 1.98
    public static let cabinWidth: Float = 1.873

    /// All the studies, in the order the models pack takes them.
    public static var models: [Map3DModelPack.Model] {
        var made: [Map3DModelPack.Model] = []
        for far in [false, true] {
            for cabin in Cabin.allCases { made.append(model(cabin, far: far)) }
            made.append(tower(far: far))
            for station in Station.allCases { made.append(model(station, far: far)) }
            for support in Support.allCases { made.append(model(support, far: far)) }
        }
        made.append(span())
        return made
    }

    public static func model(_ cabin: Cabin, far: Bool = false) -> Map3DModelPack.Model {
        var m = CableMesh()
        CableSolids.cabin(crystal: cabin == .crystal, far: far).append(to: &m.kit.mesh)
        return .flat(named: "cablecar-cabin-" + cabin.rawValue + (far ? "-far" : ""), from: m.kit.mesh)
    }

    public static func model(_ support: Support, far: Bool = false) -> Map3DModelPack.Model {
        var m = CableMesh()
        let part: CableSolids
        switch support {
        case .gate: part = .gate(far: far)
        case .kiosk: part = .kiosk(far: far)
        case .catwalk: part = .catwalk(far: far)
        }
        part.append(to: &m.kit.mesh)
        return .flat(named: "cablecar-" + support.rawValue + (far ? "-far" : ""), from: m.kit.mesh)
    }

    public static func tower(height: Float = towerHeight, far: Bool = false) -> Map3DModelPack.Model {
        var m = CableMesh()
        CableTowerRecipe(height: height, far: far).build(&m)
        return .flat(named: "cablecar-tower" + (far ? "-far" : ""), from: m.kit.mesh)
    }

    public static func model(_ station: Station, far: Bool = false) -> Map3DModelPack.Model {
        var m = CableMesh()
        CableStationRecipe(kind: station, far: far).build(&m)
        return .flat(named: "cablecar-station-" + station.rawValue + (far ? "-far" : ""), from: m.kit.mesh)
    }

    /// Two ropes over a span: `length` between two towers with `sag` at the
    /// middle, ends at the ropes' height 0, the middle of the span at x 0.
    public static func span(length: Float = 60, sag: Float = 1.1) -> Map3DModelPack.Model {
        var m = CableMesh()
        let ends = (Map3DPoint(-length / 2, 0, -ropeSpacing / 2), Map3DPoint(length / 2, 0, -ropeSpacing / 2))
        for side: Float in [-1, 1] {
            let a = Map3DPoint(ends.0.x, 0, side * ropeSpacing / 2), b = Map3DPoint(ends.1.x, 0, side * ropeSpacing / 2)
            let line = ropePoints(from: a, to: b, sag: sag, segments: 24)
            for i in 0..<(line.count - 1) { m.kit.beam(line[i], line[i + 1], CableColor.ropeThickness, CableColor.rope) }
        }
        return .flat(named: "cablecar-span", from: m.kit.mesh)
    }

    /// A rope hung between `a` and `b` (scene space, y up), `segments + 1`
    /// points. The rope sags `sag` below the chord at the middle: a
    /// parabola, which follows a catenary to within 0.1 % while the sag
    /// stays under 2 % of the span (a cable car's span does), so the rope is
    /// a straight line when `sag` is 0.
    public static func ropePoints(from a: Map3DPoint, to b: Map3DPoint, sag: Float, segments: Int) -> [Map3DPoint] {
        let count = max(1, segments)
        return (0...count).map { i in
            let t = Float(i) / Float(count)
            return a + (b - a) * t + Map3DPoint(0, -4 * sag * t * (1 - t), 0)
        }
    }

    /// The rope's height of a tower of `height`: the sheaves' tops.
    public static func ropeHeight(ofTower height: Float) -> Float { height + 0.85 + 0.25 }
}

// MARK: - Colours and the mesh

enum CableColor {
    static let white = Map3DPalette.tileWhite
    static let steel = Map3DPalette.tankStand
    static let dark = Map3DColor.rgb(0x3A4048)
    static let glass = Map3DPalette.glazing
    static let teal = Map3DColor.rgb(0x12A08F)
    static let yellow = Map3DColor.rgb(0xFFC86B)
    static let roof = Map3DColor.rgb(0x5E6A78)
    static let concrete = Map3DPalette.concrete
    static let rope = Map3DColor.rgb(0x2F3338)
    static let ropeThickness: Float = 0.09
}

/// The recipes work in the station kit's space (x forward, y up, z right);
/// ``Map3DModelPack/Model/flat(named:from:)`` turns it into the native one.
struct CableMesh {
    var kit = StationKitBuilder()

    /// A box turned `yaw` about the vertical, `u` along the turned x, `v`
    /// across it (right), standing on `y`.
    mutating func rbox(_ origin: Map3DPoint, _ u: Float, _ v: Float, _ y: Float, _ length: Float, _ width: Float, _ height: Float,
                       yaw: Float, color: UInt32) {
        let c = cosf(yaw), s = sinf(yaw)
        let base = Map3DPoint(origin.x + c * u - s * v, y, origin.z + s * u + c * v)
        kit.mesh.addBox(base: base, forward: Map3DPoint(c, 0, s), length: length, width: width, height: height, top: color, side: color)
    }


    /// A prism over a rounded rectangle `length` × `width` (corner `radius`,
    /// `segments` flats a corner) from `y` up `height`.
    mutating func rounded(_ length: Float, _ width: Float, radius: Float, y: Float, height: Float, color: UInt32, segments: Int,
                          x: Float = 0, z: Float = 0) {
        let r = min(radius, min(length, width) / 2 - 0.001)
        var ring: [Map3DPoint] = []
        let centres: [(Float, Float, Float)] = [(1, 1, 0), (-1, 1, 0.5), (-1, -1, 1), (1, -1, 1.5)]
        for (sx, sz, quarter) in centres {
            for i in 0...segments {
                let a = (quarter + Float(i) / Float(segments) * 0.5) * Float.pi
                ring.append(Map3DPoint(x + sx * (length / 2 - r) + cosf(a) * r, y, z + sz * (width / 2 - r) + sinf(a) * r))
            }
        }
        let up = Map3DPoint(0, height, 0)
        let centre = Map3DPoint(x, y + height / 2, z)
        kit.face(ring, inside: centre, color: Map3DColor.shaded(color, 0.7))
        kit.face(ring.map { $0 + up }, inside: centre, color: color)
        for i in ring.indices {
            let j = (i + 1) % ring.count
            kit.face([ring[i], ring[j], ring[j] + up, ring[i] + up], inside: centre, color: color)
        }
    }

    /// A wheel of `sides` flats: standing (axis along z) at `x`,`h`, or lying
    /// (axis up) when `horizontal`.
    mutating func wheel(_ x: Float, _ h: Float, _ z: Float, radius: Float, width: Float, horizontal: Bool, color: UInt32, sides: Int) {
        let ring = (0..<sides).map { i -> Map3DPoint in
            let a = Float(i) * 2 * Float.pi / Float(sides)
            return horizontal ? Map3DPoint(x + cosf(a) * radius, h, z + sinf(a) * radius)
                : Map3DPoint(x + cosf(a) * radius, h + sinf(a) * radius, z - width / 2)
        }
        let offset = horizontal ? Map3DPoint(0, width, 0) : Map3DPoint(0, 0, width)
        let centre = ring.reduce(Map3DPoint.zero) { $0 + $1 * (1 / Float(ring.count)) } + offset * 0.5
        kit.face(ring, inside: centre, color: color)
        kit.face(ring.map { $0 + offset }, inside: centre, color: color)
        for i in ring.indices {
            let j = (i + 1) % ring.count
            kit.face([ring[i], ring[j], ring[j] + offset, ring[i] + offset], inside: centre, color: color)
        }
    }
}

// MARK: - Tower

private struct CableTowerRecipe {
    let height: Float
    let far: Bool

    func build(_ m: inout CableMesh) {
        let spacing = Map3DCableCar.ropeSpacing
        // Footing and the mast in three tapering drums.
        m.kit.box(0, 0, 0, 2.2, 2.2, 0.5, CableColor.concrete)
        let third: Float = (height - 0.5) / 3
        var rings: [(Float, Float)] = [(0.5, far ? 0.36 : 0.44)]
        if !far {
            rings.append((0.5 + third, 0.36))
            rings.append((0.5 + third * 2, 0.28))
        }
        for (index, ring) in rings.enumerated() {
            let top = index + 1 < rings.count ? rings[index + 1].0 : height
            m.kit.cylinder(0, ring.0, 0, radius: ring.1, height: top - ring.0, color: CableColor.steel, sides: far ? 6 : 10)
        }
        // Crossarm and the work platform under it.
        m.kit.box(0, height - 0.15, 0, 1.2, spacing + 3.2, 0.55, CableColor.dark)
        if !far {
            m.kit.box(0, height - 0.60, 0, 2.0, spacing + 1.4, 0.10, CableColor.steel)
            // The ladder up the mast, one side.
            for dz: Float in [-0.12, 0.12] { m.kit.box(-0.50, 0.5, dz, 0.04, 0.04, height - 0.9, CableColor.steel) }
            var rung: Float = 0.9
            while rung < height - 1 { m.kit.box(-0.50, rung, 0, 0.04, 0.28, 0.03, CableColor.steel); rung += 0.45 }
        }
        // A sheave battery over each rope: a balance beam on a post, four
        // wheels (blocks far), the rope riding their tops.
        for side: Float in [-1, 1] {
            let z = side * spacing / 2
            m.kit.box(0, height + 0.40, z, 0.30, 0.30, 0.35, CableColor.dark)
            if far {
                m.kit.box(0, height + 0.55, z, 3.1, 0.30, 0.50, CableColor.dark)
            } else {
                m.kit.box(0, height + 0.62, z, 2.9, 0.34, 0.20, CableColor.dark)
                for x: Float in [-1.1, -0.4, 0.4, 1.1] {
                    m.wheel(x, height + 0.85, z, radius: 0.25, width: 0.22, horizontal: false, color: CableColor.steel, sides: 12)
                }
                // The rope guards, a hoop at each end of the battery.
                for x: Float in [-1.55, 1.55] {
                    m.kit.box(x, height + 0.85, z - 0.22, 0.04, 0.04, 0.22, CableColor.steel)
                    m.kit.box(x, height + 0.85, z + 0.22, 0.04, 0.04, 0.22, CableColor.steel)
                }
            }
        }
    }
}

// MARK: - Stations

private struct CableStationRecipe {
    let kind: Map3DCableCar.Station
    let far: Bool

    let length: Float = 22
    let width: Float = 11
    let wall: Float = 6.6
    let rise: Float = 1.7
    var railY: Float { Map3DCableCar.stationRopeHeight }
    var lane: Float { Map3DCableCar.ropeSpacing / 2 }

    /// What closes a hall's end: both ropes' portals, a plain wall, nothing.
    enum End { case portal, wall, open }

    func build(_ m: inout CableMesh) {
        switch kind {
        case .through:
            hall(&m, at: .zero, yaw: 0, length: length, back: .portal, front: .portal)
            lanes(&m, at: .zero, yaw: 0, from: -length / 2, to: length / 2)
            platform(&m, at: .zero, yaw: 0, from: -length / 2 + 2, to: length / 2 - 2)
        case .terminal:
            hall(&m, at: .zero, yaw: 0, length: length, back: .portal, front: .wall)
            lanes(&m, at: .zero, yaw: 0, from: -length / 2, to: length / 2 - 3.4)
            platform(&m, at: .zero, yaw: 0, from: -length / 2 + 2, to: length / 2 - 4)
            // The bullwheel the ropes turn round, lying, in a pit of steel.
            let x = length / 2 - 3.4
            m.kit.box(x, 0, 0, 5.8, 5.9, 0.35, CableColor.concrete)
            m.wheel(x, railY - 0.35, 0, radius: lane + 0.35, width: 0.30, horizontal: true, color: CableColor.steel, sides: far ? 12 : 24)
            if !far {
                m.kit.cylinder(x, 0.35, 0, radius: 0.45, height: railY - 0.35, color: CableColor.dark, sides: 10)
            }
        case .corner:
            // The line comes in along −x to the pivot, leaves 24° to the
            // right; each wing is a hall half the length, an angle wheel at
            // the pivot with the ropes' sheaves round it.
            let a = Map3DCableCar.cornerAngle
            let half = length / 2 + 1
            hall(&m, at: .zero, yaw: 0, length: half, back: .portal, front: .open, centre: -half / 2)
            hall(&m, at: .zero, yaw: a, length: half, back: .open, front: .portal, centre: half / 2)
            // The knuckle: a round floor and roof where the wings meet.
            m.kit.cylinder(0, 0, 0, radius: width / 2 + 0.3, height: 0.30, color: CableColor.concrete, sides: far ? 12 : 20)
            m.kit.cylinder(0, wall - 0.02, 0, radius: width / 2 + 0.7, height: 0.30, color: CableColor.roof, sides: far ? 12 : 20)
            lanes(&m, at: .zero, yaw: 0, from: -half, to: 0)
            lanes(&m, at: .zero, yaw: a, from: 0, to: half)
            platform(&m, at: .zero, yaw: 0, from: -half + 2, to: -1)
            platform(&m, at: .zero, yaw: a, from: 1, to: half - 2, furnished: false)
            m.wheel(0, railY - 0.35, 0, radius: lane - 0.25, width: 0.30, horizontal: true, color: CableColor.steel, sides: far ? 10 : 20)
            if !far { m.kit.cylinder(0, 0.35, 0, radius: 0.40, height: railY - 0.35, color: CableColor.dark, sides: 10) }
        }
    }

    /// A hall `length` long centred `centre` along its axis, which runs
    /// `yaw` right of +x through `at`.
    func hall(_ m: inout CableMesh, at p: Map3DPoint, yaw: Float, length: Float, back: End, front: End, centre: Float = 0) {
        let t: Float = 0.45
        let c = centre
        m.rbox(p, c, 0, 0, length, width, 0.30, yaw: yaw, color: CableColor.concrete)
        // Side walls: a white plinth, a glass band, the white fascia under
        // the roof; posts between them near.
        for side: Float in [-1, 1] {
            let v = side * (width / 2 - t / 2)
            m.rbox(p, c, v, 0.30, length, t, 1.0, yaw: yaw, color: CableColor.white)
            m.rbox(p, c, v, 1.30, length - 0.4, t * 0.6, wall - 0.9 - 1.30, yaw: yaw, color: CableColor.glass)
            m.rbox(p, c, v, wall - 0.9, length, t, 0.9, yaw: yaw, color: CableColor.white)
            m.rbox(p, c, v, wall - 1.0, length + 0.02, t + 0.02, 0.12, yaw: yaw, color: CableColor.teal)
            if !far {
                var u = -length / 2 + 1.0
                while u < length / 2 {
                    m.rbox(p, c + u, v, 1.30, 0.28, t, wall - 1.30 - 0.9, yaw: yaw, color: CableColor.white)
                    u += 4.5
                }
            }
        }
        for (end, sign) in [(back, Float(-1)), (front, Float(1))] {
            let u = c + sign * (length / 2 - t / 2)
            switch end {
            case .open: break
            case .wall:
                m.rbox(p, u, 0, 0.30, t, width, wall - 0.30, yaw: yaw, color: CableColor.white)
            case .portal:
                // Two openings for the ropes' lanes, 2.6 m wide, 5.9 m high.
                let open: Float = 2.6, high: Float = 5.9
                let outer = (width - 2 * (lane + open / 2)) / 2
                for side: Float in [-1, 1] {
                    m.rbox(p, u, side * (width / 2 - outer / 2), 0.30, t, outer, wall - 0.30, yaw: yaw, color: CableColor.white)
                }
                let middle = 2 * (lane - open / 2)
                m.rbox(p, u, 0, 0.30, t, middle, wall - 0.30, yaw: yaw, color: CableColor.white)
                for side: Float in [-1, 1] {
                    m.rbox(p, u, side * lane, 0.30 + high, t, open, wall - 0.30 - high, yaw: yaw, color: CableColor.white)
                }
            }
        }
        // The roof: a low gable over the hall, the ridge along its axis.
        let c0 = cosf(yaw), s0 = sinf(yaw)
        let base = Map3DPoint(p.x + c0 * c, wall, p.z + s0 * c)
        m.kit.mesh.addGableRoof(base: base, forward: Map3DPoint(c0, 0, s0), length: length, width: width, rise: rise, overhang: 0.6,
                                color: CableColor.roof, gable: CableColor.white)
        m.kit.mesh.addBox(base: base + Map3DPoint(0, -0.10, 0), forward: Map3DPoint(c0, 0, s0), length: length + 1.2, width: width + 1.2, height: 0.12,
                          top: CableColor.roof, side: CableColor.roof)
    }

    /// Each lane's rail the carriers run on, hung from the roof, over `from`
    /// to `to` along the turned axis.
    func lanes(_ m: inout CableMesh, at p: Map3DPoint, yaw: Float, from: Float, to: Float) {
        for side: Float in [-1, 1] {
            m.rbox(p, (from + to) / 2, side * lane, railY + 0.55, to - from, 0.16, 0.16, yaw: yaw, color: CableColor.dark)
            if !far {
                var u = from + 1
                while u < to {
                    m.rbox(p, u, side * lane, railY + 0.70, 0.08, 0.08, wall - railY - 0.70 + 0.4, yaw: yaw, color: CableColor.steel)
                    u += 3
                }
            }
        }
    }

    /// Puts a furnishing (native, +x along the hall's axis) `u` along the
    /// turned axis, `v` to the right of it, `h` up.
    func put(_ part: CableSolids, _ m: inout CableMesh, at p: Map3DPoint, yaw: Float, u: Float, v: Float = 0, h: Float = 0) {
        let c = cosf(yaw), s = sinf(yaw)
        part.append(to: &m.kit.mesh) { q in
            let along = q.x + u, right = -q.y + v
            return Map3DPoint(p.x + c * along - s * right, h + q.z, p.z + s * along + c * right)
        }
    }

    /// The boarding platform between the lanes (Codex's island, top 0.60 m,
    /// steps at its −x end), and with `furnished` the gate and a queue rail
    /// each side of it near the steps.
    func platform(_ m: inout CableMesh, at p: Map3DPoint, yaw: Float, from: Float, to: Float, furnished: Bool = true) {
        put(.platform(length: to - from, far: far), &m, at: p, yaw: yaw, u: (from + to) / 2)
        guard furnished else { return }
        let gate = from + 3.4, top = Map3DCableCar.platformHeight
        put(.gate(far: far), &m, at: p, yaw: yaw, u: gate, h: top)
        for side: Float in [-1, 1] {
            put(.queue(far: far), &m, at: p, yaw: yaw, u: gate - 1.3, v: side * 0.85, h: top)
            put(.queue(far: far), &m, at: p, yaw: yaw, u: gate + 2.4, v: side * 0.85, h: top)
        }
    }
}
