import Foundation

/// Assembly grid is illustrative; it is not surveyed airport engineering data.
///
/// Decision 698 rebuilt the look: asphalt runways with painted markings and
/// edge lights, terminals standing on their own ground with the tower and the
/// hangar, vehicles on round wheels, and lamps that light the pavement at
/// night (a pool is the pavement's own colour with the glow flag).
public enum Map3DAirportStudies {
    public enum Kind: String, CaseIterable, Sendable {
        case cityTerminal, islandTerminal, runway, runwayEnd, taxiway, apron
        case papi, windsock, fence, tug, baggageCart, boardingStairs, fuelTruck
    }
    public struct Stand: Sendable {
        public let id: String
        public let noseStop: Map3DPoint
        public let heading: Map3DPoint
        public let maxWingspan: Float
        public let aircraftClass: String
    }
    public struct Link: Sendable {
        public let position: Map3DPoint
        public let heading: Map3DPoint
        public let length: Float
    }
    public struct Jetbridge: Sendable {
        public let id: String
        public let pivot: Map3DPoint
        public let exit: Map3DPoint
        public let translationAxis: Map3DPoint
        public let extensionRange: ClosedRange<Float>
    }
    public struct Connections: Sendable {
        public let stands: [Stand]
        public let runwayEnds: [Link]
        public let taxiwayLinks: [Link]
        public let jetbridges: [Jetbridge]
    }
    /// The city terminal's four bridges, along its airside face (+x).
    static let bridgeOffsets: [Float] = [-66, -22, 22, 66]

    public static func connections(_ kind: Kind) -> Connections {
        let stands: [Stand] = kind == .apron ? zip([-24,0,24] as [Float],[17,36,65] as [Float]).enumerated().map { i,p in
            Stand(id:"S\(i+1)",noseStop:Map3DPoint(9,p.0,0),heading:Map3DPoint(1,0,0),maxWingspan:p.1,aircraftClass:["A","C","D"][i])
        } : []
        let ends: [Link] = kind == .runway ? [-30,30].map { x in Link(position:Map3DPoint(Float(x),0,0),heading:Map3DPoint(x < 0 ? 1 : -1,0,0),length:60) } :
            (kind == .runwayEnd ? [Link(position:Map3DPoint(-30,0,0),heading:Map3DPoint(1,0,0),length:60)] : [])
        let taxi: [Link] = kind == .runway ? [Link(position:Map3DPoint(0,15,0),heading:Map3DPoint(0,1,0),length:30)] :
            (kind == .taxiway ? [-15,15].map { Link(position:Map3DPoint(Float($0),0,0),heading:Map3DPoint(1,0,0),length:30) } : [])
        let bridges: [Jetbridge] = kind == .cityTerminal ? bridgeOffsets.enumerated().map { i,y in
            Jetbridge(id:"J\(i+1)",pivot:Map3DPoint(17.2,y,3.75),exit:Map3DPoint(37,y,3.45),translationAxis:Map3DPoint(1,0,0),extensionRange:0...7)
        } : []
        return Connections(stands:stands,runwayEnds:ends,taxiwayLinks:taxi,jetbridges:bridges)
    }

    public static func model(_ kind: Kind, far: Bool = false) -> Map3DModelPack.Model {
        var m = Map3DStudyMesh()
        let c = Map3DStudyColor.self
        switch kind {
        case .cityTerminal: m.cityTerminal(far)
        case .islandTerminal: m.islandTerminal(far)
        case .runway: m.runwayTile(far, end: false)
        case .runwayEnd: m.runwayTile(far, end: true)
        case .taxiway: m.taxiTile(far)
        case .apron:
            m.pavement(-40, 40, -40, 40, c.deck, joints: far ? nil : 10)
            for y: Float in [-24, 0, 24] {
                m.box(0, y, 0.09, 24, 0.30, 0.015, c.warm)
                m.box(9, y, 0.09, 0.40, 3, 0.015, c.warm)
            }
            for y: Float in [-36, 36] { m.box(0, y, 0.09, 76, 0.30, 0.015, c.red) }
            for y: Float in [-12, 12] { m.mast(-37, y, 14, pools: [(-27, y, 9)], far) }
        case .papi:
            m.box(0, 3.3, 0, 2.2, 9.4, 0.10, c.deck)
            for i in 0..<4 {
                let y = Float(i) * 2.2
                for dy: Float in [-0.3, 0.3] { m.box(0, y + dy, 0.10, 0.10, 0.10, 0.40, c.metal) }
                m.box(0, y, 0.50, 1.0, 0.9, 0.42, c.orange)
                m.box(0.52, y, 0.58, 0.06, 0.62, 0.26, i < 2 ? c.lampRed : c.lamp, glow: true)
            }
        case .windsock:
            m.box(0, 0, 0, 0.9, 0.9, 0.12, c.deck)
            m.cylinder(Map3DPoint(0, 0, 0.12), Map3DPoint(0, 0, 6.2), 0.08, c.metal, sides: 6)
            let n = far ? 6 : 10
            let stations: [(Float, Float)] = [(0.12, 0.45), (0.9, 0.40), (1.7, 0.34), (2.5, 0.27), (3.3, 0.20)]
            let rings = stations.map { x, r in (0..<n).map { i in
                let angle = 2 * Float.pi * Float(i) / Float(n)
                return Map3DPoint(x, r * cosf(angle), 5.75 - 0.14 * x + r * sinf(angle))
            } }
            m.loft(rings) { band, _ in (band == .band(1) || band == .band(3) ? c.white : c.orange, false) }
            m.box(0, 0, 6.2, 0.22, 0.22, 0.16, c.lampRed, glow: true)
        case .fence:
            for x: Float in [-4, 0, 4] {
                m.box(x, 0, 0, 0.10, 0.10, 2.5, c.steel)
                m.beam(Map3DPoint(x, 0, 2.45), Map3DPoint(x, 0.32, 2.8), 0.06, c.steel)
            }
            for z: Float in [0.15, 1.25, 2.35] { m.box(0, 0, z, 8, 0.055, 0.055, c.steel) }
            m.box(0, 0.32, 2.78, 8, 0.04, 0.04, c.steel)
            if !far { for i in -15...15 { m.box(Float(i) * 0.25, 0, 0.2, 0.028, 0.03, 2.15, c.metal) } }
        case .tug:
            // A low pushback tractor: wide flat body, the cab at one end.
            let l: Float = 5.2, w: Float = 2.4
            m.vehicleWheels([-1.55, 1.55], w, 0.50, far)
            m.box(0, 0, 0.30, l, w - 0.5, 0.40, c.tyre)
            m.box(0, 0, 0.55, l, w, 0.55, c.white)
            m.box(0, 0, 0.55, l + 0.02, w + 0.02, 0.16, c.warm)
            m.box(-1.2, 0, 1.10, 2.4, w * 0.82, 0.30, c.white)
            m.box(1.45, 0, 1.10, 1.7, w * 0.80, 1.05, c.white)
            m.box(1.45, 0, 1.55, 1.74, w * 0.82, 0.48, c.cockpit)
            m.box(1.45, 0, 2.15, 1.8, w * 0.84, 0.08, c.white)
            m.box(1.45, 0, 2.23, 0.22, 0.22, 0.16, c.orange, glow: true)
            m.box(l / 2 + 0.25, 0, 0.45, 0.5, 0.22, 0.16, c.tyre)
        case .baggageCart:
            // A small tractor and two dollies with containers.
            m.vehicleWheels([-4.3, -2.9], 1.4, 0.30, far)
            m.box(-3.6, 0, 0.30, 2.3, 1.4, 0.50, c.white)
            m.box(-3.6, 0, 0.30, 2.32, 1.42, 0.14, c.warm)
            m.box(-3.9, 0, 0.80, 0.9, 1.1, 0.45, c.tyre)
            m.box(-3.9, 0, 1.25, 1.0, 1.3, 0.08, c.white)
            for y: Float in [-0.6, 0.6] { m.box(-3.45, y, 0.80, 0.07, 0.07, 0.45, c.metal) }
            for (i, x) in ([-0.6, 2.8] as [Float]).enumerated() {
                m.vehicleWheels([x - 0.9, x + 0.9], 1.5, 0.24, far)
                m.box(x, 0, 0.40, 2.9, 1.6, 0.12, c.metal)
                m.box(x - 1.75, 0, 0.40, 0.7, 0.10, 0.08, c.tyre)
                m.box(x, 0, 0.52, 2.3, 1.5, 1.45, i > 0 ? c.belly : c.blue)
                if !far { m.box(x, 0.76, 0.62, 1.9, 0.04, 1.2, c.wall) }
            }
        case .boardingStairs:
            let l: Float = 6.4, w: Float = 2.2
            m.vehicleWheels([-2.1, 1.9], w, 0.42, far)
            m.box(0, 0, 0.35, l, w - 0.4, 0.35, c.tyre)
            m.box(-2.45, 0, 0.70, 1.4, w, 1.35, c.white)
            m.box(-2.45, 0, 1.35, 1.44, w + 0.02, 0.45, c.cockpit)
            let steps = far ? 5 : 10, x0: Float = -1.6, x1: Float = 2.6, z0: Float = 0.78, z1: Float = 3.55
            for side: Float in [-1, 1] {
                let y = side * (w / 2 - 0.08)
                func ring(_ yy: Float) -> [Map3DPoint] {
                    [Map3DPoint(x0, yy, z0 - 0.1), Map3DPoint(x1 + 0.9, yy, z1 - 0.4), Map3DPoint(x1 + 0.9, yy, z1 + 1.0), Map3DPoint(x1, yy, z1 + 1.0), Map3DPoint(x0, yy, z0 + 1.0)]
                }
                m.loft([ring(y - 0.05), ring(y + 0.05)], c.blue)
            }
            func body(_ yy: Float) -> [Map3DPoint] {
                [Map3DPoint(x0, yy, 0.70), Map3DPoint(x1 + 0.9, yy, 0.70), Map3DPoint(x1 + 0.9, yy, z1 - 0.12), Map3DPoint(x1, yy, z1 - 0.12), Map3DPoint(x0, yy, z0)]
            }
            m.loft([body(-w / 2 + 0.2), body(w / 2 - 0.2)], c.white)
            for i in 0..<steps {
                m.box(x0 + (Float(i) + 0.5) * (x1 - x0) / Float(steps), 0, z0 + Float(i + 1) * (z1 - z0) / Float(steps) - 0.12, (x1 - x0) / Float(steps) + 0.02, w - 0.3, 0.12, c.metal)
            }
            m.box(x1 + 0.45, 0, z1 - 0.12, 0.9, w - 0.3, 0.12, c.metal)
            for y: Float in [-0.9, 0.9] { m.cylinder(Map3DPoint(x1 + 0.85, y, 0.70), Map3DPoint(x1 + 0.85, y, z1 - 0.12), 0.06, c.metal, sides: 6) }
        case .fuelTruck:
            let l: Float = 9.0, w: Float = 2.5
            m.vehicleWheels([-3.4, -2.2, 3.1], w, 0.50, far)
            m.box(0, 0, 0.45, l, w - 0.5, 0.30, c.tyre)
            m.box(3.35, 0, 0.75, 2.0, w, 1.75, c.white)
            m.box(3.75, 0, 1.55, 1.24, w + 0.02, 0.62, c.cockpit)
            m.box(3.35, 0, 0.75, 2.02, w + 0.02, 0.18, c.warm)
            let n = far ? 8 : 14
            let stations: [(Float, Float)] = [(-4.4, 0.72), (-4.1, 1), (2.0, 1), (2.25, 0.72)]
            let rings = stations.map { x, k in (0..<n).map { i in
                let angle = 2 * Float.pi * Float(i) / Float(n)
                return Map3DPoint(x, k * 1.18 * cosf(angle), 1.82 + k * 1.02 * sinf(angle))
            } }
            m.loft(rings) { band, i in (band == .band(1) && (i == n - 1 || i == n / 2) ? c.red : c.white, false) }
            m.box(-1.1, 0, 0.75, 6.3, w - 0.5, 0.22, c.metal)
            m.box(-1.1, 0, 2.84, 5.4, 0.5, 0.06, c.metal)
            if !far {
                m.box(-4.1, 0, 0.75, 0.6, w - 0.3, 0.85, c.metal)
                m.box(3.35, 0, 2.50, 0.22, 0.22, 0.16, c.orange, glow: true)
            }
        }
        return m.model(named:"airport-\(kind.rawValue)-\(far ? "far" : "near")")
    }
}

private func positiveRemainder(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }

extension Map3DStudyMesh {
    /// A light fitting and the pavement it lights. `inward` moves the pool
    /// onto the pavement when the fitting stands at its edge. The far model
    /// is seen small: its lamps are what is left of a runway at night.
    mutating func lamp(_ x: Float, _ y: Float, _ color: UInt32, pool: UInt32, radius: Float, far: Bool, size: Float = 0.9, inward: (Float, Float) = (0, 0)) {
        let size = far ? size * 1.8 : size
        box(x, y, 0.08, size, size, size * 0.38, color, glow: true)
        if !far { disc(x + inward.0, y + inward.1, 0.082, radius, pool, glow: true) }
    }

    /// Seven-segment runway numerals: tall along x, read from the threshold.
    mutating func digit(_ d: Character, _ x: Float, _ y: Float, _ z: Float) {
        let h: Float = 7.0, w: Float = 2.8, t: Float = 0.75
        let segments: [Character: String] = ["0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
                                             "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abfgcd"]
        let geometry: [Character: (Float, Float, Float, Float)] = [
            "a": (h - t / 2, 0, t, w), "g": (h / 2, 0, t, w), "d": (t / 2, 0, t, w),
            "f": (h * 0.75, w / 2 - t / 2, h / 2, t), "b": (h * 0.75, -(w / 2 - t / 2), h / 2, t),
            "e": (h * 0.25, w / 2 - t / 2, h / 2, t), "c": (h * 0.25, -(w / 2 - t / 2), h / 2, t)]
        for k in segments[d] ?? "" {
            let g = geometry[k]!
            box(x + g.0, y + g.1, z, g.2, g.3, 0.015, Map3DStudyColor.white)
        }
    }

    mutating func mast(_ x: Float, _ y: Float, _ height: Float, pools: [(Float, Float, Float)], _ far: Bool) {
        let c = Map3DStudyColor.self
        cylinder(Map3DPoint(x, y, 0), Map3DPoint(x, y, height), 0.22, c.metal, sides: 6, endRadius: 0.14)
        box(x, y, height, 1.0, 2.6, 0.35, c.metal)
        for dy: Float in [-0.8, 0, 0.8] { box(x + 0.3, y + dy, height - 0.22, 0.5, 0.55, 0.22, c.lamp, glow: true) }
        if !far { for p in pools { disc(p.0, p.1, 0.082, p.2, c.litDeck, glow: true, sides: 14) } }
    }

    mutating func pavement(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ color: UInt32, joints: Float? = nil) {
        let h: Float = 0.08
        box((x0 + x1) / 2, (y0 + y1) / 2, 0, x1 - x0, y1 - y0, h, color)
        guard let joints else { return }
        var k = (x0 / joints).rounded(.up) * joints
        while k < x1 - 0.01 {
            if k > x0 + 0.01 { box(k, (y0 + y1) / 2, h + 0.004, 0.14, y1 - y0 - 0.2, 0.006, Map3DStudyColor.joint) }
            k += joints
        }
        k = (y0 / joints).rounded(.up) * joints
        while k < y1 - 0.01 {
            if k > y0 + 0.01 { box((x0 + x1) / 2, k, h + 0.004, x1 - x0 - 0.2, 0.14, 0.006, Map3DStudyColor.joint) }
            k += joints
        }
    }

    mutating func runwayTile(_ far: Bool, end: Bool) {
        let c = Map3DStudyColor.self
        box(0, 0, 0, 60, 30, 0.08, c.asphalt)
        for y: Float in [-13.6, 13.6] { box(0, y, 0.09, 60, 0.9, 0.015, c.white) }
        if end {
            for y: Float in [-11.4, -9.0, -6.6, -4.2, 4.2, 6.6, 9.0, 11.4] { box(-21, y, 0.09, 12, 1.5, 0.015, c.white) }
            digit("1", -11, 2.4, 0.09); digit("0", -11, -2.4, 0.09)
            for y: Float in [-7.5, 7.5] { box(17, y, 0.09, 14, 4.2, 0.015, c.white) }
            box(2.5, 0, 0.09, 5, 0.9, 0.015, c.white)
            for i in 0..<10 {
                lamp(-29.5, -12.6 + Float(i) * 2.8, c.lampGreen, pool: c.litAsphalt, radius: 2.2, far: far || i % 3 != 0, size: 0.8, inward: (1.8, 0))
            }
        } else {
            for x: Float in [-20, 0, 20] { box(x, 0, 0.09, 12, 0.9, 0.015, c.white) }
            if !far { for x: Float in [-18, 18] { for y: Float in [-9, 9] { box(x, y, 0.09, 9, 1.4, 0.015, c.white) } } }
        }
        for x: Float in [-22.5, -7.5, 7.5, 22.5] {
            for y: Float in [-14.5, 14.5] { lamp(x, y, c.lamp, pool: c.litAsphalt, radius: 2.6, far: far, inward: (0, y > 0 ? -2.1 : 2.1)) }
        }
        for x in stride(from: -25, through: 25, by: 10) { box(Float(x), 0, 0.09, far ? 1.1 : 0.7, far ? 1.1 : 0.7, 0.03, c.lamp, glow: true) }
    }

    mutating func taxiTile(_ far: Bool) {
        let c = Map3DStudyColor.self
        box(0, 0, 0, 30, 12, 0.08, c.taxi)
        box(0, 0, 0.09, 30, 0.36, 0.015, c.warm)
        for y: Float in [-5.2, 5.2] { box(0, y, 0.09, 30, 0.22, 0.015, c.warm) }
        for x: Float in [-10, 0, 10] {
            for y: Float in [-5.65, 5.65] { lamp(x, y, c.lampBlue, pool: c.litTaxi, radius: 1.6, far: far, size: 0.7, inward: (0, y > 0 ? -1.3 : 1.3)) }
        }
    }

    mutating func vehicleWheels(_ xs: [Float], _ width: Float, _ radius: Float, _ far: Bool) {
        for x in xs { for side: Float in [-1, 1] { wheel(x, side * (width / 2 - 0.16), radius, 0.30, far: far) } }
    }

    /// A hall under a shallow arched roof; `alongY` is the ridge's axis.
    mutating func archBlock(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, wall: Float, rise: Float, alongY: Bool,
                            wallColor: UInt32, roofColor: UInt32, over: Float, steps: Int, ribs: [Float]) {
        let (a0, a1, b0, b1) = alongY ? (y0, y1, x0, x1) : (x0, x1, y0, y1)   // extrude a, arch across b
        func point(_ a: Float, _ p: (Float, Float)) -> Map3DPoint { alongY ? Map3DPoint(p.0, a, p.1) : Map3DPoint(a, p.0, p.1) }
        let mid = (b0 + b1) / 2, half = (b1 - b0) / 2
        func arc(_ scale: Float, _ dz: Float) -> [(Float, Float)] {
            (0...steps).map { i in
                let t = Float(i) / Float(steps)
                return (mid + (half + over * scale) * cosf(Float.pi * (1 - t)), wall + dz + rise * sinf(Float.pi * t))
            }
        }
        var body: [(Float, Float)] = [(b0, Float(0)), (b0, wall)]
        body += arc(0, -0.05)[1..<steps]
        body += [(b1, wall), (b1, Float(0))]
        loft([a0, a1].map { a in body.map { point(a, $0) } }, wallColor)
        let roof = arc(1, 0.45) + arc(1, 0).reversed()
        loft([a0 - over, a1 + over].map { a in roof.map { point(a, $0) } }, roofColor)
        let fascia = arc(1.02, 0.62) + arc(1.02, -0.12).reversed()
        for end in [a0 - over - 0.3, a1 + over - 0.3] {          // white barge boards close the roof's ends
            loft([end, end + 0.6].map { a in fascia.map { point(a, $0) } }, Map3DStudyColor.white)
        }
        let band = arc(1, 0.68) + arc(1, 0.40).reversed()
        for rib in ribs { loft([rib - 0.45, rib + 0.45].map { a in band.map { point(a, $0) } }, Map3DStudyColor.white) }
    }

    /// From the concourse to `end` (x, y, sill): rotunda, tunnel, cab, drive legs.
    mutating func jetbridge(_ y: Float, end: Map3DPoint, _ far: Bool) {
        let c = Map3DStudyColor.self, x0: Float = 14.0, rx = x0 + 3.2
        cylinder(Map3DPoint(rx, y, 0), Map3DPoint(rx, y, 3.5), 0.55, c.metal, sides: 8)
        cylinder(Map3DPoint(rx, y, 3.5), Map3DPoint(rx, y, 6.6), 2.3, c.white, sides: far ? 8 : 12)
        cylinder(Map3DPoint(rx, y, 6.6), Map3DPoint(rx, y, 6.8), 2.5, c.roof, sides: far ? 8 : 12)
        box(x0 + 1.0, y, 3.6, 2.4, 2.6, 2.7, c.white)
        let a = Map3DPoint(rx, y, 5.0), b = Map3DPoint(end.x, end.y, end.z + 1.25)
        bar(a, b, 2.6, 2.6, c.white)
        let d = (b - a) * (1 / (b - a).length), s0 = Map3DPoint(0, 0, 1).cross(d), side = s0 * (1 / s0.length)
        if !far {
            for s: Float in [-1, 1] {
                let o = side * (s * 1.31)
                bar(a + d * 2.6 + o, b + d * (-2.4) + o, 0.06, 1.0, c.pane, glow: true)
            }
        }
        bar(a + Map3DPoint(0, 0, 1.36), b + Map3DPoint(0, 0, 1.36), 2.8, 0.14, c.roof)
        let cab = b + d * (-1.0)
        cylinder(Map3DPoint(cab.x, cab.y, end.z - 0.15), Map3DPoint(cab.x, cab.y, end.z + 2.75), 1.9, c.white, sides: far ? 8 : 10)
        cylinder(Map3DPoint(cab.x, cab.y, end.z + 2.75), Map3DPoint(cab.x, cab.y, end.z + 2.95), 2.05, c.roof, sides: far ? 8 : 10)
        let leg = b + d * (-4.2)
        for s: Float in [-1, 1] {
            let p = leg + side * (s * 1.6)
            cylinder(Map3DPoint(p.x, p.y, 0.45), Map3DPoint(p.x, p.y, leg.z - 1.2), 0.16, c.metal, sides: 6)
            wheel(p.x, p.y, 0.45, 0.32, far: far)
        }
        bar(Map3DPoint(leg.x - side.x * 1.8, leg.y - side.y * 1.8, leg.z - 1.25), Map3DPoint(leg.x + side.x * 1.8, leg.y + side.y * 1.8, leg.z - 1.25), 0.3, 0.3, c.metal)
    }

    static func octagon(_ x: Float, _ y: Float, _ z: Float, _ radius: Float) -> [Map3DPoint] {
        (0..<8).map { i in
            let angle = 2 * Float.pi * (Float(i) + 0.5) / 8
            return Map3DPoint(x + radius * cosf(angle), y + radius * sinf(angle), z)
        }
    }

    mutating func tower(_ x: Float, _ y: Float, _ h: Float, _ far: Bool) {
        let c = Map3DStudyColor.self, r: Float = 3.0
        func ring(_ z: Float, _ radius: Float) -> [Map3DPoint] { Self.octagon(x, y, z, radius) }
        loft([ring(0, r), ring(h, r * 0.82)], c.wall)
        loft([ring(h, r * 1.45), ring(h + 0.6, r * 1.55)], c.base)
        loft([ring(h + 0.6, r * 1.25), ring(h + 3.8, r * 1.62)], c.pane, glow: true)
        loft([ring(h + 3.8, r * 1.75), ring(h + 4.3, r * 1.50)], c.roof)
        cylinder(Map3DPoint(x, y, h + 4.3), Map3DPoint(x, y, h + 8.0), 0.12, c.metal, sides: 6)
        box(x, y, h + 8.0, 0.3, 0.3, 0.22, c.lampRed, glow: true)
        if !far {
            for i in 0..<3 {
                let f = Float(i)
                loft([ring(h * (0.25 + 0.22 * f), r * (0.955 - 0.04 * f) + 0.04), ring(h * (0.25 + 0.22 * f) + 0.5, r * (0.95 - 0.04 * f) + 0.04)], c.base)
            }
        }
    }

    /// Airside is +x. Everything stands on one plate: car park, forecourt
    /// road, hall, concourse, tower and hangar are a single place.
    mutating func cityTerminal(_ far: Bool) {
        let c = Map3DStudyColor.self
        pavement(-104, 14, -92, 130, c.deck)
        box(-88, 0, 0.08, 24, 150, 0.02, c.asphalt)
        box(-72.5, 0, 0.08, 5, 150, 0.10, c.grass)
        let cars = [c.wall, c.red, c.blue, c.belly, c.navy]
        for (i, y) in stride(from: -70, through: 70, by: 5).enumerated() {
            for x: Float in [-94.5, -81.5] {
                if !far && i % 2 == 0 { box(x, Float(y), 0.10, 5, 0.15, 0.012, c.white) }
                if positiveRemainder(i * 7 + Int(x), 3) == 0 {
                    box(x, Float(y) + 2.5, 0.10, 4.2, 1.8, 0.9, cars[positiveRemainder(i + Int(x), 5)])
                    if !far { box(x - 0.2, Float(y) + 2.5, 1.0, 2.2, 1.6, 0.5, c.cockpit) }
                }
            }
        }
        box(-62, 0, 0.08, 14, 176, 0.02, c.asphalt)
        for y in stride(from: -80, through: 80, by: 16) { box(-62, Float(y), 0.10, 0.25, 6, 0.012, c.white) }
        box(-51.5, 0, 0.08, 3, 150, 0.14, c.wall)
        archBlock(-40, 0, -45, 45, wall: 9.5, rise: 5.2, alongY: true, wallColor: c.white, roofColor: c.roof, over: 2.0, steps: far ? 6 : 10,
                  ribs: stride(from: -36, through: 36, by: 12).map { Float($0) })
        box(-20, 0, 14.95, 6, 84, 0.35, c.pane, glow: true)
        box(-45, 0, 5.4, 10, 84, 0.30, c.roof)
        for y in stride(from: -36, through: 36, by: 12) { cylinder(Map3DPoint(-49, Float(y), 0), Map3DPoint(-49, Float(y), 5.4), 0.28, c.white, sides: 6) }
        let bays = far ? 6 : 12
        for i in 0..<bays {
            box(-40.06, -42 + (Float(i) + 0.5) * 84 / Float(bays), 1.0, 0.14, 84 / Float(bays) - 0.9, 7.6, c.pane, glow: true)
        }
        box(-40.1, 0, 0, 0.22, 86, 1.0, c.base)
        for y: Float in [-45.06, 45.06] { box(-20, y, 2.0, 30, 0.14, 6.5, c.pane, glow: true) }
        box(7, 0, 0, 14, 176, 7.6, c.white)
        box(7, 0, 0, 14.12, 176.12, 3.0, c.base)
        box(7, 0, 7.6, 14.6, 176.6, 0.35, c.wall)
        for x: Float in [0, 14] { box(x, 0, 7.6, 0.7, 176.8, 0.7, c.roof) }
        box(7, 0, 7.95, 4, 150, 0.9, c.pane, glow: true)
        for y: Float in [-70, 70] { box(7, y, 7.95, 6, 9, 1.6, c.metal) }
        box(14.06, 0, 3.5, 0.14, 172, 3.0, c.pane, glow: true)
        if !far { for y in stride(from: -80, through: 80, by: 10) { box(14.12, Float(y), 3.0, 0.22, 0.5, 4.6, c.white) } }
        box(-30, -72, 0, 18, 14, 7, c.wall)
        box(-30, -72, 3.2, 18.1, 14.1, 1.2, c.pane, glow: true)
        tower(-30, -72, 27, far)
        archBlock(-38, 4, 92, 126, wall: 11, rise: 4.4, alongY: false, wallColor: c.belly, roofColor: c.metal, over: 1.0, steps: far ? 6 : 10, ribs: [-28, -17, -6])
        for y: Float in [98.6, 109, 119.4] {
            box(4.08, y, 0, 0.18, 9.8, 9.2, c.metal)
            box(4.12, y, 9.4, 0.2, 9.8, 1.0, c.pane, glow: true)
        }
        for y in Map3DAirportStudies.bridgeOffsets { jetbridge(y, end: Map3DPoint(37.0, y, 3.45), far) }
    }

    /// The island terminal: one low white block with a red band, a small
    /// control cab on its roof and porches on both sides.
    mutating func islandTerminal(_ far: Bool) {
        let c = Map3DStudyColor.self
        pavement(-30, 6, -20, 20, c.deck)
        box(-23, 0, 0.08, 12, 34, 0.02, c.asphalt)
        if !far { for y in stride(from: -15, through: 15, by: 5) { box(-23, Float(y), 0.10, 5, 0.15, 0.012, c.white) } }
        box(-6.5, 0, 0, 13, 25, 3.7, c.white)
        box(-6.5, 0, 3.7, 13.5, 25.5, 0.35, c.red)
        box(-6.5, 0, 3.7, 12.7, 24.7, 0.36, c.wall)
        box(-6.5, 0, 3.05, 13.56, 25.56, 0.40, c.red)
        for y: Float in [2, 6] { box(-9, y, 4.06, 1.6, 1.2, 0.9, c.metal) }
        cylinder(Map3DPoint(-3.5, 9.5, 4.06), Map3DPoint(-3.5, 9.5, 5.7), 0.9, c.metal, sides: 8)
        box(-6.5, 0, 0, 13.1, 25.1, 0.5, c.base)
        for (side, x) in [(1, 0.04), (-1, -13.04)] as [(Int, Float)] {
            for i in 0..<5 {
                let y = -10 + Float(i) * 5
                if side > 0 && i == 3 { box(x, y, 0.1, 0.12, 2.2, 2.4, c.cockpit) }
                else if side < 0 && i == 2 { box(x, y, 0.1, 0.12, 3.0, 2.5, c.cockpit) }
                else { box(x, y, 1.15, 0.12, 3.2, 1.5, c.pane, glow: true) }
            }
        }
        box(2.2, 2.5, 2.85, 4.4, 14, 0.18, c.red)
        for y: Float in [-3.5, 2.5, 8.5] { cylinder(Map3DPoint(4.0, y, 0), Map3DPoint(4.0, y, 2.85), 0.10, c.white, sides: 6) }
        box(-15.0, 0, 2.85, 4.0, 8, 0.18, c.red)
        for y: Float in [-3.4, 3.4] { cylinder(Map3DPoint(-16.6, y, 0), Map3DPoint(-16.6, y, 2.85), 0.10, c.white, sides: 6) }
        box(-8, -8.5, 4.05, 5, 5, 2.4, c.white)
        box(-8, -8.5, 6.0, 5.06, 5.06, 0.30, c.red)
        loft([Self.octagon(-8, -8.5, 6.45, 2.3), Self.octagon(-8, -8.5, 8.3, 2.9)], c.pane, glow: true)
        loft([Self.octagon(-8, -8.5, 8.3, 3.2), Self.octagon(-8, -8.5, 8.65, 2.7)], c.red)
        cylinder(Map3DPoint(-8, -8.5, 8.65), Map3DPoint(-8, -8.5, 11.0), 0.07, c.metal, sides: 6)
        box(5.0, 2.5, 0.08, 2.0, 1.8, 0.02, c.warm)
    }
}
