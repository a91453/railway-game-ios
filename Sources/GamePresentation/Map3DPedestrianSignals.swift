import Foundation
import GameCore

// Decision 445: the 3D map's junctions get Taiwan's pedestrian signals
// (行人專用號誌) beside decision 429's traffic signals, read off the same
// clock and keeping no state of their own. As the rules for signs,
// markings and signals have them (道路交通標誌標線號誌設置規則): a square
// face of two 30 cm lights, the red standing figure over the green walking
// one (articles 200, 202, 203), the green one walking and a countdown
// beside it (article 204), at each end of a crossing (article 201), 2.1–3 m
// up (article 220); the green flashes, once a second (article 233), for as
// long as it takes to cross at 1 m/s (article 231: t = dw / v), here the
// widest road with signals. Seven walking frames, faster as the green runs
// out, are Taipei's first animated signal's (1999, as
// docs/research/TAIWAN_STREETSCAPE_2026-10-28.md has it); the frames'
// 0.45 s to 0.13 s are hebe13579/slop-taipei's `TAIWAN_STREETSCAPE.md`
// (§c.10, its own value). The walking figure, faster near the end, and the
// countdown follow the TW3D pack's `createWalkFaceMaterial`,
// `createCountdownMaterial` and `walkState` (the private reference's
// `Railway/tw3d-reference-clean/source/js/street-details.js` and
// `city-config.js`; slop-newyork, MIT, copyright (c) 2026 Mr.doob), whose
// seven-segment digits' masks are the usual ones.

/// What the 3D map's pedestrian signals show, and their models.
public enum Map3DPedestrianSignal {
    public typealias Road = Map3DSignalTiming.Road

    /// The walking figure's frames.
    public static let frames = 7
    /// How fast a pedestrian is taken to cross, metres a second (article
    /// 231's for most crossings).
    static let walkingSpeed = 1.0
    /// How long the green flashes, in game seconds: long enough to cross
    /// the widest road with signals (a trunk road's 11 m) at
    /// ``walkingSpeed``.
    public static let flashing = Int64((Double(Map3DBaseMap.RoadKind.trunk.width(ramp: false)) / walkingSpeed).rounded(.up))
    /// How long a frame lasts as the green starts, and as it ends.
    static let slowestStep = 0.45
    static let fastestStep = 0.13

    /// When pedestrians walking alongside `road`'s traffic may cross, in
    /// a cycle's seconds: while that traffic has its green.
    static func window(_ road: Road) -> Range<Int64> {
        switch road {
        case .main: 0..<Map3DSignalTiming.mainAmber
        case .cross: (Map3DSignalTiming.mainRed + 1)..<Map3DSignalTiming.crossAmber
        }
    }

    /// The seconds the pedestrians alongside `road` have left to cross,
    /// `second` into the clock (the countdown, down to 1); `nil` while
    /// theirs is red.
    public static func left(_ road: Road, at second: Int64) -> Int64? {
        let cycle = Map3DSignalTiming.cycle
        let t = (second % cycle + cycle) % cycle, window = window(road)
        return window.contains(t) ? window.upperBound - t : nil
    }

    /// How long a walking frame lasts with `left` seconds of a green of
    /// `length` left: from ``slowestStep`` as it starts to
    /// ``fastestStep`` in its last second.
    static func step(left: Int64, of length: Int64) -> Double {
        let share = Double(max(0, min(left, length) - 1)) / Double(max(1, length - 1))
        return fastestStep + (slowestStep - fastestStep) * share
    }

    /// What a pedestrian signal's face shows.
    public struct Face: Sendable, Equatable {
        public enum Figure: Sendable, Equatable {
            /// The red standing figure.
            case stop
            /// The green walking figure, at one of its ``frames``.
            case walk(Int)
            /// Neither: the green flashing off.
            case dark
        }

        public let figure: Figure
        /// The countdown's seconds; `nil` when it is blank.
        public let count: Int64?
    }

    /// What the pedestrians alongside `road` at a junction of `group` see
    /// at `clock`, `time` seconds into the screen's own clock (for the
    /// figure's steps and the flashing). With no clock, or one too fast for
    /// the lights to change, as the traffic signals stand (decision 429:
    /// the main road's green) and no countdown. Paused or with Reduce
    /// Motion, the figure stands in its first frame and the green does not
    /// flash; the countdown still shows.
    public static func face(_ road: Road, group: Int, clock: Map3DSignalTiming.Clock?, time: Double, reduceMotion: Bool) -> Face {
        guard let clock, clock.changes else { return Face(figure: road == .main ? .walk(0) : .stop, count: nil) }
        guard let left = left(road, at: clock.second + Map3DSignalTiming.offset(group)) else { return Face(figure: .stop, count: nil) }
        guard !reduceMotion, !clock.paused else { return Face(figure: .walk(0), count: left) }
        let fraction = time - time.rounded(.down)
        if left <= flashing, fraction >= 0.5 { return Face(figure: .dark, count: left) }
        let steps = Int64((time / step(left: left, of: Int64(window(road).count))).rounded(.down))
        return Face(figure: .walk(Int((steps % Int64(frames) + Int64(frames)) % Int64(frames))), count: left)
    }

    /// The group a pedestrian signal's instances carry
    /// (``Map3DInstance/group``): its junction's group and, past
    /// ``Map3DSignalTiming/groups``, whether its pedestrians walk
    /// alongside the crossing road.
    public static func group(_ junction: Int, road: Road) -> Int {
        junction + (road == .cross ? Map3DSignalTiming.groups : 0)
    }

    /// The junction's group and the road of an instance's `group`.
    static func junction(of group: Int) -> (group: Int, road: Road) {
        (group % Map3DSignalTiming.groups, group >= Map3DSignalTiming.groups ? .cross : .main)
    }

    // MARK: The models

    /// The models' names in ``Map3DModelPack``: the face with the red
    /// figure lit, with neither, with each walking frame; the countdown's
    /// tens (1–9) and ones (0–9).
    static let stopName = "walk-stop"
    static let darkName = "walk-dark"
    static func walkName(_ frame: Int) -> String { "walk-\(frame)" }
    static func tensName(_ digit: Int) -> String { "walk-tens-\(digit)" }
    static func onesName(_ digit: Int) -> String { "walk-ones-\(digit)" }

    /// The models, for ``Map3DModelPack``.
    static func models() -> [Map3DModelPack.Model] {
        var models = [head(stopName, figure: .stop), head(darkName, figure: .dark)]
        models += (0..<frames).map { head(walkName($0), figure: .walk($0)) }
        models += (1...9).map { digit(tensName($0), $0, cell: 0) }
        models += (0...9).map { digit(onesName($0), $0, cell: 1) }
        return models.map(Map3DLook.restyle)
    }

    /// How many models there are.
    public static let modelCount = 2 + frames + 9 + 10

    /// The lights' colours (decision 355's red and green, lit and unlit),
    /// the housing's and the pole's.
    static let red = Map3DProp.signalLights[0]
    static let green = Map3DProp.signalLights[2]
    static let housing = Map3DColor.rgb(0x2B2F36)
    static let steel = Map3DColor.rgb(0x8A9099)

    /// Where the face is: a lens's side (30 cm), the two lenses' middles
    /// (the red over the green), how far the face stands out from the pole
    /// (toward −z, the way it looks), and the countdown's middle beside
    /// the green lens.
    static let lens: Float = 0.3
    static let redMiddle = Map3DPoint(0, 2.78, 0)
    static let greenMiddle = Map3DPoint(0, 2.42, 0)
    static let face: Float = -0.265
    static let countMiddle = Map3DPoint(0.36, 2.42, 0)

    /// The pole, the housing with its two lenses' figures (the lit one
    /// glowing), and the countdown's box, its face toward −z.
    static func head(_ name: String, figure: Face.Figure) -> Map3DModelPack.Model {
        var mesh = Map3DMesh()
        let back = Map3DPoint(0, 0, -1)
        mesh.addCylinder(base: .zero, radius: 0.06, height: 2.95, sides: 6, top: steel, side: steel)
        mesh.addBox(base: Map3DPoint(0, 2.24, -0.16), forward: back, length: 0.2, width: 0.36, height: 0.72, top: housing, side: housing)
        mesh.addBox(base: Map3DPoint(0.36, 2.24, -0.16), forward: back, length: 0.2, width: 0.36, height: 0.36, top: housing, side: housing)
        let stopLit = figure == .stop, walkLit: Bool, frame: Int
        if case .walk(let f) = figure { (walkLit, frame) = (true, f) } else { (walkLit, frame) = (false, 0) }
        addFigure(&mesh, limbs: standing, at: redMiddle, colour: stopLit ? red.lit : red.unlit, lit: stopLit)
        addFigure(&mesh, limbs: walking(frame), at: greenMiddle, colour: walkLit ? green.lit : green.unlit, lit: walkLit)
        return Map3DModelPack.Model.flat(named: name, from: mesh)
    }

    /// A figure's head (middle, radius) and limbs (from, to, thickness),
    /// in metres on a lens, +x right and +y up.
    struct Limbs {
        let head: (x: Float, y: Float, radius: Float)
        let limbs: [(from: (Float, Float), to: (Float, Float), width: Float)]
    }

    /// The red figure: standing, arms down.
    static let standing = Limbs(head: (0, 0.095, 0.026), limbs: [
        ((0, 0.064), (0, -0.02), 0.045),
        ((-0.028, 0.06), (-0.036, -0.02), 0.02), ((0.028, 0.06), (0.036, -0.02), 0.02),
        ((-0.012, -0.02), (-0.016, -0.115), 0.024), ((0.012, -0.02), (0.016, -0.115), 0.024),
    ])

    /// The green figure at `frame`: striding to the right, legs and arms
    /// swinging opposite ways through a whole step over the frames.
    static func walking(_ frame: Int) -> Limbs {
        let swing = sin(Float(frame) / Float(frames) * 2 * .pi)
        let hip: (Float, Float) = (0.002, -0.02), shoulder: (Float, Float) = (0.012, 0.058)
        return Limbs(head: (0.016, 0.095, 0.026), limbs: [
            ((0.012, 0.064), hip, 0.042),
            (shoulder, (0.012 + 0.04 * swing, -0.012), 0.02), (shoulder, (0.012 - 0.04 * swing, -0.012), 0.02),
            (hip, (0.002 + 0.05 * swing, -0.115), 0.024), (hip, (0.002 - 0.05 * swing, -0.115), 0.024),
        ])
    }

    /// `limbs` on the face at `middle`, in `colour`, glowing when `lit`.
    static func addFigure(_ mesh: inout Map3DMesh, limbs: Limbs, at middle: Map3DPoint, colour: UInt32, lit: Bool) {
        let start = mesh.vertices.count
        func point(_ x: Float, _ y: Float) -> Map3DPoint { Map3DPoint(middle.x + x, middle.y + y, face) }
        let head = (0..<6).map { index -> Map3DPoint in
            let angle = Float(index) / 6 * 2 * .pi
            return point(limbs.head.x + cos(angle) * limbs.head.radius, limbs.head.y + sin(angle) * limbs.head.radius)
        }
        addFacing(&mesh, head, colour: colour)
        for limb in limbs.limbs {
            let dx = limb.to.0 - limb.from.0, dy = limb.to.1 - limb.from.1, length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { continue }
            let nx = -dy / length * limb.width / 2, ny = dx / length * limb.width / 2
            addFacing(&mesh, [point(limb.from.0 - nx, limb.from.1 - ny), point(limb.from.0 + nx, limb.from.1 + ny),
                              point(limb.to.0 + nx, limb.to.1 + ny), point(limb.to.0 - nx, limb.to.1 - ny)], colour: colour)
        }
        if lit { mesh.makeGlowing(from: start) }
    }

    /// A flat face of `corners` looking toward −z, whichever way they run.
    static func addFacing(_ mesh: inout Map3DMesh, _ corners: [Map3DPoint], colour: UInt32) {
        let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0])
        mesh.addFacet(normal.z > 0 ? corners.reversed() : corners, color: colour)
    }

    /// The seven segments (a to g) each digit lights.
    static let segments: [UInt8] = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]

    /// `digit`'s lit segments, glowing green, in the countdown's left
    /// (`cell` 0, the tens) or right cell (1, the ones).
    static func digit(_ name: String, _ digit: Int, cell: Int) -> Map3DModelPack.Model {
        var mesh = Map3DMesh()
        let x = countMiddle.x + (cell == 0 ? -0.07 : 0.07), y = countMiddle.y
        let w: Float = 0.1, h: Float = 0.2, t: Float = 0.022
        // Each segment's middle and size: across (a, g, d) or up the sides.
        let bars: [(Float, Float, Float, Float)] = [
            (0, h / 2 - t / 2, w, t), (w / 2 - t / 2, h / 4, t, h / 2), (w / 2 - t / 2, -h / 4, t, h / 2),
            (0, -h / 2 + t / 2, w, t), (-w / 2 + t / 2, -h / 4, t, h / 2), (-w / 2 + t / 2, h / 4, t, h / 2), (0, 0, w, t),
        ]
        for (index, bar) in bars.enumerated() where segments[digit] & (1 << index) != 0 {
            let cx = x + bar.0, cy = y + bar.1
            addFacing(&mesh, [Map3DPoint(cx - bar.2 / 2, cy - bar.3 / 2, face), Map3DPoint(cx - bar.2 / 2, cy + bar.3 / 2, face),
                              Map3DPoint(cx + bar.2 / 2, cy + bar.3 / 2, face), Map3DPoint(cx + bar.2 / 2, cy - bar.3 / 2, face)],
                      colour: green.lit)
        }
        mesh.makeGlowing(from: 0)
        return Map3DModelPack.Model.flat(named: name, from: mesh)
    }

    /// A pack's pedestrian signal models, for a renderer to draw what the
    /// clock shows. Each signal stands in a chunk as three instances in
    /// one place: its face (as ``placed``'s `head`), the countdown's tens
    /// and its ones; their ``Map3DInstance/group`` is ``group(_:road:)``.
    public struct Models: Sendable, Equatable {
        let stop: Int
        let dark: Int
        let walk: [Int]
        /// By digit; the tens' 0 is none (a blank).
        let tens: [Int?]
        let ones: [Int]

        public init?(pack: Map3DModelPack) {
            guard let stop = pack.index(of: Map3DPedestrianSignal.stopName), let dark = pack.index(of: Map3DPedestrianSignal.darkName) else { return nil }
            let walk = (0..<Map3DPedestrianSignal.frames).compactMap { pack.index(of: Map3DPedestrianSignal.walkName($0)) }
            let tens = (1...9).compactMap { pack.index(of: Map3DPedestrianSignal.tensName($0)) }
            let ones = (0...9).compactMap { pack.index(of: Map3DPedestrianSignal.onesName($0)) }
            guard walk.count == Map3DPedestrianSignal.frames, tens.count == 9, ones.count == 10 else { return nil }
            (self.stop, self.dark, self.walk, self.tens, self.ones) = (stop, dark, walk, [nil] + tens, ones)
        }

        /// The models a signal's three instances are placed with.
        public var placed: (head: Int, tens: Int, ones: Int) { (stop, tens[1] ?? stop, ones[0]) }

        /// Whether `model` is one a pedestrian signal is placed with: drawn
        /// only close up (decision 267), and casting no shadow.
        public func places(_ model: Int) -> Bool {
            model == placed.head || model == placed.tens || model == placed.ones
        }

        /// The model to draw the instances of `model` of `group` with: what
        /// the face or countdown shows (``Map3DPedestrianSignal/face(_:group:clock:time:reduceMotion:)``),
        /// `nil` for a blank digit; any other model itself.
        public func model(_ model: Int, group: Int, clock: Map3DSignalTiming.Clock?, time: Double, reduceMotion: Bool) -> Int? {
            guard places(model) else { return model }
            let (junction, road) = Map3DPedestrianSignal.junction(of: group)
            let face = Map3DPedestrianSignal.face(road, group: junction, clock: clock, time: time, reduceMotion: reduceMotion)
            switch model {
            case placed.head:
                switch face.figure {
                case .stop: return stop
                case .dark: return dark
                case .walk(let frame): return walk[frame]
                }
            case placed.tens:
                return face.count.flatMap { $0 >= 10 ? tens[Int(min($0 / 10, 9))] : nil }
            default:
                return face.count.map { ones[Int($0 % 10)] }
            }
        }

        /// The most triangles `runs`' pedestrian signals draw in a frame
        /// (decision 417's budget): their faces' and both digits' at most.
        public func triangles(_ runs: [Map3DPropRuns.Run], in pack: Map3DModelPack) -> Int {
            let head = ([stop, dark] + walk).map { pack.models[$0].triangleCount }.max() ?? 0
            let tensMost = tens.compactMap { $0 }.map { pack.models[$0].triangleCount }.max() ?? 0
            let onesMost = ones.map { pack.models[$0].triangleCount }.max() ?? 0
            return runs.reduce(0) { sum, run in
                switch run.model {
                case placed.head: sum + head * run.count
                case placed.tens: sum + tensMost * run.count
                case placed.ones: sum + onesMost * run.count
                default: sum
                }
            }
        }
    }
}
