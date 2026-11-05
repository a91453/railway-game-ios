import Foundation

/// Decision 585 PR-3 (FERRY3): the two ferries and the floating pier of
/// decision 579's studies in Swift, near and far, for the 3D map
/// (``Map3DFerries``). Translated from Codex's producer
/// `tools/ferry-studies/produce.py` (decision 579): the shapes, sizes,
/// colours, glowing lamps and triangle counts are its; the app does not load
/// its `.m3dmodel` or GLB files.
///
/// Sources (decision 579, the private `SOURCE.md`): the Tamsui–Bali boat is
/// the size of the Shunfeng 166, 18.00 × 4.43 m, 99 people; the Gushan–Cijin
/// double-ended ferry the Qigu No. 2's, 25.3 m long, 8.20 m moulded beam, 170
/// people. Cabin heights, the pier's parts and their sizes are proportions
/// read off photographs (UNVERIFIED, design values); no name or operator's
/// mark is drawn.
///
/// Space: native, +x the bow (for the double-ended ferry, the end it sails
/// out of its first pier with), +y port (left), +z up, metres; a boat's and
/// the pier's origin is the waterline (z 0) at its middle. The pier's +x
/// points out over the water: its pontoon lies round x 0, its gangway's
/// hinge at x −10 and its shore landing (top 1.65 m over the water) round x
/// −13, which stands on the bank.
public enum Map3DFerry {
    /// The two boats, as decision 579 drew them.
    public enum Boat: String, CaseIterable, Sendable {
        /// The Tamsui–Bali passenger boat: one hull, a bow, turns round.
        case tamsui
        /// The Gushan–Cijin double-ended ferry: sails either way.
        case cijin

        /// Length overall and beam, metres (decision 579).
        public var length: Float { self == .tamsui ? 18 : 25.3 }
        public var beam: Float { self == .tamsui ? 4.43 : 8.2 }
        /// People it takes (decision 579's sources; the game's boats take
        /// ``FerryRoute/capacity`` whichever is drawn).
        public var people: Int { self == .tamsui ? 99 : 170 }
        /// Whether it sails either end first instead of turning round.
        public var isDoubleEnded: Bool { self == .cijin }

        /// Decision 585 PR-4 (FERRYFOLLOW): where the follow camera sits
        /// in the boat, read off the model below. The bridge view's eye:
        /// how far ahead of the middle the wheelhouse's front window
        /// stands (the passenger boat's wheelhouse is forward, x 4.8,
        /// 2.6 m long; the double-ended ferry's in the middle, 11.8 m long,
        /// the same either way) and how high over the water (the
        /// wheelhouse's windows' middle: floor 2.95 m, 1.55 m tall; floor
        /// 5.73 m, 1.9 m tall).
        public var bridgeFront: Float { self == .tamsui ? 6.1 : 5.9 }
        public var bridgeEye: Float { self == .tamsui ? 3.95 : 6.9 }
        /// The cabin window view's seat: a seated eye 1.15 m over the
        /// saloon's floor (the open lower deck at 0.77 m; the upper saloon
        /// at 3.40 m), as far out to the side as the walls and posts
        /// stand within the near plane (1.2 m) and are not drawn over the
        /// view (posts at 1.98 m; the saloon's wall at 3.25 m).
        public var seatAcross: Float { self == .tamsui ? 1.3 : 2.6 }
        public var seatHeight: Float { self == .tamsui ? 1.92 : 4.55 }
        /// How tall it stands over the water, for the view beside it (to
        /// the wheelhouse's roof).
        public var height: Float { self == .tamsui ? 4.6 : 7.8 }

        /// The boat a route's crossing draws: the double-ended ferry on a
        /// short harbour crossing (under a kilometre, as Gushan–Cijin's
        /// 715 m), the passenger boat on a longer one (as Tamsui–Bali's
        /// 1,260 m).
        public static func drawn(forMetres metres: Int64) -> Boat {
            metres < 1_000 ? .cijin : .tamsui
        }
    }

    /// The pier's pontoon: how far its seaward end is from its origin.
    public static let pontoonReach: Float = 4
    /// The pier's origin from the bank's edge out over the water: the
    /// gangway's hinge (x −10) a little inside the edge, the shore landing
    /// on the bank.
    public static let pierOffshore: Float = 9.6

    /// Every model the 3D map draws (``Map3DModelPack/standard``): each
    /// boat and the pier, near then far.
    public static var drawn: [Map3DModelPack.Model] {
        var made: [Map3DModelPack.Model] = []
        for far in [false, true] {
            for boat in Boat.allCases { made.append(model(boat, far: far)) }
            made.append(pier(far: far))
        }
        return made
    }

    /// A boat's model name. "single": a whole vessel, no car before or
    /// behind it, for the pack's baked shade (``Map3DTrainOcclusion``).
    public static func name(_ boat: Boat, far: Bool = false) -> String {
        "ferry-" + boat.rawValue + "-single" + (far ? "-far" : "")
    }

    public static func pierName(far: Bool = false) -> String {
        "ferry-pier-single" + (far ? "-far" : "")
    }

    public static func model(_ boat: Boat, far: Bool = false) -> Map3DModelPack.Model {
        var m = CableMesh()
        solids(boat, far: far).append(to: &m.kit.mesh)
        return .flat(named: name(boat, far: far), from: m.kit.mesh)
    }

    public static func pier(far: Bool = false) -> Map3DModelPack.Model {
        var m = CableMesh()
        pierSolids(far: far).append(to: &m.kit.mesh)
        return .flat(named: pierName(far: far), from: m.kit.mesh)
    }

    /// The boat's closed solids (for the tests' closed-solid check).
    static func solids(_ boat: Boat, far: Bool) -> CableSolids {
        var s = CableSolids()
        switch boat {
        case .tamsui: s.tamsui(far: far)
        case .cijin: s.cijin(far: far)
        }
        return s
    }

    /// The pier assembly: pontoon, gangway, shelter, ticket kiosk, two
    /// railings and the shore landing (the producer's `dock`).
    static func pierSolids(far: Bool) -> CableSolids {
        var s = CableSolids()
        s.pier(far: far)
        return s
    }
}

/// The producer's palette (decision 579; the same values as
/// ``CableParts/Paint``).
private typealias Paint = CableParts.Paint

extension CableSolids {
    // MARK: - Shared pieces (produce.py's Mesh)

    /// A vertical x/z ring round (`x`, `y`, `z`) of radius `r`, its tube
    /// 0.085 m thick: a life ring or a tyre fender hung on the side.
    mutating func ring(_ x: Float, _ y: Float, _ z: Float, _ r: Float, _ color: UInt32, sides n: Int = 16) {
        var p: [P] = []
        let m = 6
        for i in 0..<n {
            let a = Float(i) * 2 * .pi / Float(n)
            for j in 0..<m {
                let b = Float(j) * 2 * .pi / Float(m)
                let rr = r + 0.085 * cosf(b)
                p.append(P(x + rr * cosf(a), y + 0.085 * sinf(b), z + rr * sinf(a)))
            }
        }
        var faces: [[Int]] = []
        for i in 0..<n {
            for j in 0..<m { faces.append([i * m + (j + 1) % m, ((i + 1) % n) * m + (j + 1) % m, ((i + 1) % n) * m + j, i * m + j]) }
        }
        solid(p, faces, color)
    }

    /// A bench: two legs, a seat, a back near.
    mutating func ferryBench(_ x: Float, _ y: Float, _ z: Float, far: Bool) {
        for dx: Float in [-0.6, 0.6] { box(x + dx, y, z, 0.12, 0.45, 0.43, Paint.steel) }
        box(x, y, z + 0.43, 1.7, 0.48, 0.09, Paint.blue)
        if !far { box(x, y + 0.20, z + 0.52, 1.7, 0.08, 0.42, Paint.blue) }
    }

    /// Every triangle from `start` on moved by `fn`.
    mutating func transform(from start: Int, _ fn: (P) -> P) {
        for i in start..<triangles.count {
            triangles[i].a = fn(triangles[i].a)
            triangles[i].b = fn(triangles[i].b)
            triangles[i].c = fn(triangles[i].c)
        }
    }

    /// The closed lower hull with its chine and sealed deck, and the
    /// bulwark and rubbing strake round it.
    mutating func hull(_ l: Float, _ w: Float, doubleEnded: Bool) {
        let outline: [(Float, Float)] = doubleEnded
            ? [(-l / 2, -w * 0.31), (-l * 0.38, -w / 2), (l * 0.38, -w / 2), (l / 2, -w * 0.31), (l / 2, w * 0.31), (l * 0.38, w / 2),
               (-l * 0.38, w / 2), (-l / 2, w * 0.31)]
            : [(-l / 2, -w * 0.31), (-l * 0.38, -w / 2), (l * 0.32, -w / 2), (l / 2, -w * 0.18), (l / 2, w * 0.18), (l * 0.32, w / 2),
               (-l * 0.38, w / 2), (-l / 2, w * 0.31)]
        let p = outline.map { P($0.0 * 0.92, $0.1 * 0.72, -0.84) } + outline.map { P($0.0, $0.1, 0.65) }
        var faces: [[Int]] = [Array((0..<8).reversed()), Array(8..<16)]
        for i in 0..<8 { faces.append([i, (i + 1) % 8, (i + 1) % 8 + 8, i + 8]) }
        solid(p, faces, doubleEnded ? Paint.red : Paint.white)
        for (i, corner) in outline.enumerated() {
            let next = outline[(i + 1) % 8]
            beam(P(corner.0, corner.1, 0.78), P(next.0, next.1, 0.78), 0.26, Paint.white)
            beam(P(corner.0, corner.1, 0.37), P(next.0, next.1, 0.37), 0.10, Paint.dark)
        }
    }

    /// A wheelhouse with lit windows round it and an overhanging roof.
    mutating func wheelhouse(_ x: Float, _ y: Float, _ z: Float, _ l: Float, _ w: Float, _ h: Float, far: Bool) {
        box(x, y, z, l, w, h, Paint.white)
        let n = far ? 2 : 4
        for sy: Float in [-1, 1] {
            for i in 0..<n {
                box(x - l / 2 + (Float(i) + 0.5) * l / Float(n), y + sy * (w / 2 + 0.012), z + 0.62, l / Float(n) - 0.10, 0.024, h - 0.78,
                    Paint.glass, glow: true)
            }
        }
        for sx: Float in [-1, 1] { box(x + sx * (l / 2 + 0.012), y, z + 0.62, 0.024, w - 0.25, h - 0.78, Paint.glass, glow: true) }
        box(x, y, z + h, l + 0.35, w + 0.35, 0.14, Paint.white)
    }

    /// Port red and starboard green side lights and the white masthead
    /// light, all lit.
    mutating func lamps(_ x: Float, _ z: Float, _ w: Float) {
        for (y, color) in [(w / 2, Paint.red), (-w / 2, Paint.green)] {
            box(x, y, z, 0.22, 0.22, 0.12, Paint.dark)
            box(x, y, z + 0.12, 0.17, 0.17, 0.16, color, glow: true)
        }
        box(x, 0, z, 0.075, 0.075, 1.6, Paint.steel)
        box(x, 0, z + 1.6, 0.17, 0.17, 0.18, Paint.white, glow: true)
    }

    // MARK: - The boats

    /// Tamsui–Bali: open saloon under a promenade deck, the wheelhouse
    /// forward on top, a blue belt.
    mutating func tamsui(far: Bool) {
        hull(Map3DFerry.Boat.tamsui.length, Map3DFerry.Boat.tamsui.beam, doubleEnded: false)
        box(-0.25, 0, 0.65, 15.1, 3.9, 0.12, Paint.deck)
        for y: Float in [-1.98, 1.98] {
            for x: Float in [-6.9, -4.6, -2.3, 0, 2.3, 4.6, 6.1] { box(x, y, 0.77, 0.16, 0.16, 2, Paint.white) }
            box(-0.4, y, 0.77, 14.0, 0.13, 0.48, Paint.white)
            beam(P(-7.1, y, 1.66), P(6.2, y, 1.66), 0.055, Paint.steel)
        }
        box(-0.4, 0, 2.77, 14.7, 4.16, 0.18, Paint.white)
        box(-0.4, 0, 2.77, 14.74, 4.18, 0.08, Paint.blue)
        wheelhouse(4.8, 0, 2.95, 2.6, 3.4, 1.55, far: far)
        for y: Float in [-1.94, 1.94] { rail(P(-7.3, y, 2.95), P(3.3, y, 2.95), far: far) }
        rail(P(-7.3, -1.94, 2.95), P(-7.3, 1.94, 2.95), far: far)
        for x: Float in far ? [-5, -1, 2] : [-5.8, -3.7, -1.6, 0.5, 2.6] {
            for y: Float in [-1.15, 1.15] { ferryBench(x, y, 0.77, far: far) }
        }
        box(-1, 0, 2.95, 0.62, 0.58, 0.95, Paint.white)
        box(-1, 0, 3.90, 0.68, 0.64, 0.15, Paint.dark)
        lamps(4.8, 4.64, 3.4)
        for y: Float in [-2.10, 2.10] {
            for x: Float in [-5, 1] {
                box(x, y, 1.10, 0.18, 0.12, 0.7, Paint.steel)
                ring(x, y + (y < 0 ? -0.145 : 0.145), 1.47, 0.30, Paint.red, sides: far ? 8 : 16)
            }
        }
    }

    /// Gushan–Cijin: red hull, an open lane through for scooters, the red
    /// saloon above it, the bridge on top, swept shoulders.
    mutating func cijin(far: Bool) {
        hull(Map3DFerry.Boat.cijin.length, Map3DFerry.Boat.cijin.beam, doubleEnded: true)
        box(0, 0, 0.65, 22, 7.6, 0.12, Paint.deck)
        for y: Float in [-3.7, 3.7] {
            if y < 0 {
                box(0, y, 0.77, 20.6, 0.18, 0.95, Paint.white)
            } else {
                for (x, l): (Float, Float) in [(-9.4, 1.8), (0, 10), (9.4, 1.8)] { box(x, y, 0.77, l, 0.18, 0.95, Paint.white) }
            }
            for x: Float in [-9, -6, -3, 0, 3, 6, 9] { box(x, y, 1.72, 0.20, 0.20, 1.5, Paint.white) }
            if y < 0 { beam(P(-10, y, 2.18), P(10, y, 2.18), 0.06, Paint.steel) } else { beam(P(-5, y, 2.18), P(5, y, 2.18), 0.06, Paint.steel) }
        }
        for x: Float in [-11.2, 11.2] {
            box(x, 0, 0.77, 1.0, 4, 0.10, Paint.steel)
            for y: Float in [-2.85, 2.85] { rail(P(x, y, 0.88), P(x, y < 0 ? 2.1 : -2.1, 0.88), far: far) }
        }
        for i in 0..<10 { box(-5.5 + Float(i) * 0.24, 2.4, 0.77, 0.24, 1, Float(i + 1) * 0.245, Paint.steel) }
        box(0, 0, 3.22, 22.2, 7.8, 0.18, Paint.white)
        box(0, 0, 3.40, 12.8, 6.5, 2.15, Paint.red)
        let n = far ? 5 : 9
        for y: Float in [-3.27, 3.27] {
            for i in 0..<n {
                let x = -6.4 + (Float(i) + 0.5) * 12.8 / Float(n)
                box(x, y, 4.05, 12.8 / Float(n) - 0.18, 0.04, 1.25, Paint.glass)
            }
        }
        for y: Float in [-3.75, 3.75] {
            for x: Float in [-6.5, -4.3, -2.1, 0.1, 2.3, 4.5, 6.5] { box(x, y, 3.40, 0.16, 0.16, 2.15, Paint.white) }
            rail(P(-10.8, y, 3.40), P(10.8, y, 3.40), far: far)
            for sign: Float in [-1, 1] { beam(P(sign * 10.7, y, 3.40), P(sign * 6.5, y, 5.55), 0.22, Paint.white) }
        }
        box(0, 0, 5.55, 13.8, 7.9, 0.18, Paint.white)
        wheelhouse(0, 0, 5.73, 11.8, 6.6, 1.9, far: far)
        for y: Float in [-3.65, 3.65] { rail(P(-6.4, y, 5.73), P(6.4, y, 5.73), far: far) }
        for x: Float in [-8.6, 8.6] {
            for y: Float in [-2.4, 2.4] { ferryBench(x, y, 3.40, far: far) }
        }
        for y: Float in [-4.02, 4.02] {
            let out: Float = y < 0 ? -0.145 : 0.145
            for x: Float in [-8, 8] {
                box(x, y, 3.60, 0.16, 0.12, 0.7, Paint.steel)
                ring(x, y + out, 3.97, 0.35, Paint.red, sides: far ? 8 : 16)
            }
            if !far {
                for x: Float in [-9, -6, -3, 0, 3, 6, 9] {
                    box(x, y, 0.32, 0.15, 0.18, 0.60, Paint.steel)
                    ring(x, y + out, 0.53, 0.39, Paint.dark)
                }
            }
        }
        lamps(0, 7.77, 6.6)
        box(0, 0, 8.4, 0.08, 2.2, 0.08, Paint.steel)
    }

    // MARK: - The pier

    mutating func pontoon(far: Bool) {
        for y: Float in [-2.1, 2.1] { box(0, y, -0.50, 8, 1.30, 0.95, Paint.dark) }
        box(0, 0, 0.45, 8, 6, 0.20, Paint.wood)
        if !far {
            for x in -3...3 { box(Float(x), 0, 0.65, 0.025, 5.9, 0.012, Paint.deck) }
        }
        for y: Float in [-2.75, 2.75] {
            for x: Float in [-3.6, 3.6] {
                box(x, y, 0.65, 0.18, 0.18, 0.30, Paint.steel)
                box(x, y, 0.95, 0.38, 0.18, 0.07, Paint.steel)
            }
        }
    }

    /// The gangway at its rest angle, its hinge at the origin, sloping
    /// down 1 m over its 6.1 m to the pontoon.
    mutating func gangway(far: Bool) {
        box(-0.20, 0, -0.40, 0.40, 2.8, 0.28, Paint.steel)
        for y: Float in [-1.25, 1.25] { box(0, y, -0.12, 0.34, 0.20, 0.24, Paint.steel) }
        beam(P(0, -1.35, 0), P(0, 1.35, 0), 0.12, Paint.steel)
        let start = triangles.count
        box(3.05, 0, -0.12, 6.1, 2.2, 0.12, Paint.deck)
        for y: Float in [-1.05, 1.05] {
            rail(P(0, y, 0), P(6.1, y, 0), far: far)
            beam(P(0, y, -0.06), P(6.1, y, -0.06), 0.13, Paint.steel)
        }
        if !far {
            for i in 1..<24 { box(Float(i) * 0.25, 0, 0, 0.035, 1.92, 0.012, Paint.steel) }
        }
        let theta = -asinf(1 / 6.1)
        transform(from: start) { p in P(cosf(theta) * p.x - sinf(theta) * p.z, p.y, sinf(theta) * p.x + cosf(theta) * p.z) }
    }

    mutating func shelter(far: Bool) {
        box(0, 0, 0, 5.8, 4.2, 0.12, Paint.deck)
        for x: Float in [-2.5, 2.5] {
            for y: Float in [-1.7, 1.7] { box(x, y, 0.12, 0.14, 0.14, 2.5, Paint.steel) }
        }
        box(0, 0, 2.62, 5.9, 4.3, 0.16, Paint.blue)
        box(0, 0, 2.78, 5.9, 0.20, 0.14, Paint.blue)
        for x: Float in [-1.3, 1.3] { ferryBench(x, 1.15, 0.12, far: far) }
    }

    mutating func pierRailing(far: Bool) {
        for x: Float in far ? [-1.45, 1.45] : [-1.45, -1.45 + 2.9 / 3, -1.45 + 5.8 / 3, 1.45] { box(x, 0, 0, 0.20, 0.20, 0.06, Paint.steel) }
        rail(P(-1.45, 0, 0.06), P(1.45, 0, 0.06), far: far)
    }

    mutating func ticketKiosk(far: Bool) {
        box(0, 0, 0, 2.4, 2.2, 0.12, Paint.deck)
        box(0, 0, 0.12, 2.1, 1.9, 2.3, Paint.white)
        box(1.06, 0, 1.02, 0.02, 1.45, 0.90, Paint.glass, glow: true)
        box(1.2, 0, 0.92, 0.5, 1.65, 0.10, Paint.wood)
        box(0, 0, 2.42, 2.6, 2.4, 0.18, Paint.blue)
        if !far {
            box(-0.4, -0.96, 0.12, 0.85, 0.02, 1.95, Paint.steel)
            box(-0.4, -0.98, 1.02, 0.65, 0.02, 0.80, Paint.glass)
        }
    }

    /// The producer's `dock`: each part at its place, then the shore
    /// landing under the shelter and the kiosk.
    mutating func pier(far: Bool) {
        let placements: [(P, (inout CableSolids) -> Void)] = [
            (P(0, 0, 0), { $0.pontoon(far: far) }),
            (P(-10, 0, 1.65), { $0.gangway(far: far) }),
            (P(-13, 0, 1.65), { $0.shelter(far: far) }),
            (P(-13, 4, 1.65), { $0.ticketKiosk(far: far) }),
            (P(0, 2.75, 0.65), { $0.pierRailing(far: far) }),
            (P(0, -2.75, 0.65), { $0.pierRailing(far: far) }),
        ]
        for (offset, part) in placements {
            let start = triangles.count
            part(&self)
            transform(from: start) { $0 + offset }
        }
        box(-13, 1.8, 0.90, 6.4, 9.0, 0.75, Paint.deck)
    }
}
