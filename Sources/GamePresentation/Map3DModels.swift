import Foundation
import GameCore

/// The 3D map's train models (ARCHITECTURE decision 230), made in code.
///
/// The owner, 2026-10-15, after seeing the reference repository's white
/// models in the game: they looked the same as the originals, so they are
/// not used (art-style §7). What was learned from them is the method and the
/// proportions: a car is about 2.9–3.1 m wide and 3.6–3.7 m tall, its windows
/// between some 1.6 and 3.0 m above the rail, the Wenhu Line's cars smaller
/// (2.6 m by 3.3 m). The shape is swept the way this project's own city view
/// sweeps its trains (`Web/CityView/src/world/trains.js` `shellRing` and
/// `shellGeometry`, MIT): rings of a rounded section along the car, a cab
/// car's front rings narrowing and dropping into its nose. The livery is
/// painted by height, as there: the skirt, a band in the line's colour,
/// windows and doors standing a little proud of the body, the windscreen.
///
/// A model's space: +x the front, +y the left, +z up, the rail at z 0,
/// metres, the car's middle at x 0. A vertex whose alpha is below 1 takes
/// the line's colour in that share.
public struct Map3DModelPack: Sendable {
    public struct Model: Sendable {
        public let name: String
        /// Three to a triangle, each with the triangle's own normal (flat,
        /// the miniature look).
        public let vertices: [Map3DVertex]
        public let minimum: Map3DPoint
        public let maximum: Map3DPoint

        public var length: Float { maximum.x - minimum.x }
        public var triangleCount: Int { vertices.count / 3 }
    }

    public let models: [Model]

    /// Every style's cab car and middle car, made once.
    public static let standard = Map3DModelPack(styles: Map3DTrainStyle.all)

    public init(styles: [Map3DTrainStyle]) {
        var models: [Model] = []
        for style in styles {
            models.append(Map3DTrainBuilder(style: style, cab: true).model(named: style.name + "-cab"))
            models.append(Map3DTrainBuilder(style: style, cab: false).model(named: style.name + "-car"))
        }
        // Decision 244: and the street furniture.
        models += Map3DProp.allCases.map { $0.model() }
        self.models = models
    }

    /// The model called `name`'s index.
    public func index(of name: String) -> Int? {
        models.firstIndex { $0.name == name }
    }

    /// The style of each train type, by its code (`""` for a train with no
    /// type: a commuter EMU). Types with no style (maglev, skyrail,
    /// monorail, steam) are drawn as boxes.
    public static let styleByType: [String: String] = [
        "": "commuter", "EMU3000": "express", "HSR": "highSpeed",
        "A": "metro", "B": "metro", "C": "metro", "L": "metro", "D": "metro", "APM": "peopleMover",
    ]

    /// The cab and middle car models' indices for a train of type `code`,
    /// or `nil` when it has none.
    public func models(forType code: String) -> (head: Int, middle: Int)? {
        guard let style = Self.styleByType[code], let head = index(of: style + "-cab"), let middle = index(of: style + "-car") else { return nil }
        return (head, middle)
    }
}

/// How one kind of train looks (decision 230): its section, its nose and
/// its livery. Heights are shares of the section (0 the skirt's hem, 1 the
/// roof), as `trains.js`'s liveries are.
public struct Map3DTrainStyle: Sendable {
    public let name: String
    /// The car's length as drawn, metres (``TrainCars/drawnCarLength`` less
    /// the gap between cars).
    public var length: Float = 19.4
    public var halfWidth: Float
    /// The section's bottom and top above the rail.
    public var floor: Float
    public var roof: Float
    /// The cab car's nose: its length, how far its top drops and its bottom
    /// lifts, how much it narrows, how much its tip rounds over.
    public var nose: Float
    public var drop: Float
    public var lift: Float = 0.05
    public var tuck: Float
    public var cap: Float
    /// The body's colour, the skirt's and how high the skirt reaches.
    public var body: UInt32 = Map3DColor.rgb(0xF2F3F1)
    public var skirt: UInt32 = Map3DColor.rgb(0x9AA0A4)
    public var skirtTop: Float = 0.14
    /// The band in the line's colour, and a thin dark line, if any.
    public var band: ClosedRange<Float>
    public var line: ClosedRange<Float>?
    /// The windows: their heights, the distance between their middles and
    /// their width, in metres.
    public var windows: ClosedRange<Float>
    public var windowPitch: Float
    public var windowWidth: Float
    /// Doors on each side, evenly spaced (on a cab car, one less is behind
    /// a long nose), and their width.
    public var doors: Int
    public var doorWidth: Float = 1.3
    /// The windscreen: where it starts along the nose (0 at the body, 1 at
    /// the tip) and how high it reaches down.
    public var screenFrom: Float
    public var screenDown: Float

    static let glass = Map3DColor.rgb(0x26313D)
    static let doorColour = Map3DColor.rgb(0x5D6670)
    static let darkLine = Map3DColor.rgb(0x2A3340)
    static let roofColour = Map3DColor.rgb(0xC5C9CD)
    static let under = Map3DColor.rgb(0x474B51)

    /// The styles, from what the reference's trains measure and this
    /// project's own city view (`trains.js` `EMU3000_STOCK`, `HSR_STOCK`).
    public static let all: [Map3DTrainStyle] = [
        // A TRA commuter EMU: a short, upright cab; three doors a side.
        Map3DTrainStyle(name: "commuter", halfWidth: 1.45, floor: 0.6, roof: 3.7, nose: 1.4, drop: 0.35, tuck: 0.06, cap: 0.22,
                        band: 0.33...0.40, line: nil, windows: 0.46...0.80, windowPitch: 1.9, windowWidth: 1.4, doors: 3,
                        screenFrom: 0.0, screenDown: 0.47),
        // The EMU3000 (trains.js EMU3000_STOCK): a long sloping nose, white,
        // a thin dark line under the windows; one door a side at the end.
        Map3DTrainStyle(name: "express", halfWidth: 1.455, floor: 0.53, roof: 3.49, nose: 5.4, drop: 1.15, lift: 0.18, tuck: 0.3, cap: 0.46,
                        band: 0.40...0.44, line: 0.70...0.726, windows: 0.47...0.70, windowPitch: 1.35, windowWidth: 0.7, doors: 1,
                        doorWidth: 1.0, screenFrom: 0.15, screenDown: 0.62),
        // High speed (trains.js HSR_STOCK): a 9 m duck-bill nose.
        Map3DTrainStyle(name: "highSpeed", halfWidth: 1.45, floor: 0.62, roof: 3.75, nose: 9, drop: 1.78, lift: 0.1, tuck: 0.34, cap: 0.56,
                        band: 0.38...0.50, line: 0.50...0.566, windows: 0.56...0.78, windowPitch: 1.0, windowWidth: 0.5, doors: 1,
                        doorWidth: 0.85, screenFrom: 0.10, screenDown: 0.64),
        // A metro car: wider, a flat front, four doors a side.
        Map3DTrainStyle(name: "metro", halfWidth: 1.55, floor: 0.55, roof: 3.6, nose: 1.0, drop: 0.22, tuck: 0.04, cap: 0.2,
                        band: 0.34...0.41, line: nil, windows: 0.45...0.82, windowPitch: 1.9, windowWidth: 1.3, doors: 4,
                        screenFrom: 0.0, screenDown: 0.45),
        // A people mover (the Wenhu Line's size): small and rounded.
        Map3DTrainStyle(name: "peopleMover", length: 13, halfWidth: 1.3, floor: 0.7, roof: 3.3, nose: 1.8, drop: 0.55, tuck: 0.1, cap: 0.35,
                        band: 0.28...0.35, line: nil, windows: 0.40...0.80, windowPitch: 2.0, windowWidth: 1.6, doors: 2,
                        screenFrom: 0.0, screenDown: 0.40),
    ]
}

/// Builds one car of a style (decision 230). Works in a frame with y up
/// (x the front, z the right), so ``Map3DMesh``'s boxes stand the right way,
/// and turns the result into the model's frame (z up, y the left) at the end.
struct Map3DTrainBuilder {
    let style: Map3DTrainStyle
    let cab: Bool
    static let ringPoints = 20

    private var mesh = Map3DMesh()

    init(style: Map3DTrainStyle, cab: Bool) {
        self.style = style
        self.cab = cab
    }

    // MARK: The shell

    /// `trains.js` `shellRing`: the section at `along` metres, `t` along the
    /// nose (0 at the body, 1 at the tip). Each point with its height's
    /// share of the section, for the livery.
    func ring(at along: Float, t: Float) -> [(point: Map3DPoint, share: Float)] {
        func ease(_ x: Float) -> Float { let v = min(1, max(0, x)); return v * v * (3 - 2 * v) }
        let halfWidth = style.halfWidth * (1 - style.tuck * ease((t - 0.45) / 0.55))
        let top = style.roof - style.drop * ease(t), bottom = style.floor + style.lift * ease((t - 0.6) / 0.4)
        let cap = 1 - style.cap * ease((t - 0.88) / 0.12)
        let middle = (top + bottom) / 2, half = (top - bottom) / 2 * cap
        let low = 2 / (8.5 - 5.6 * ease(t)), up = 2 / (4.6 - 2.3 * ease(t))
        return (0..<Self.ringPoints).map { k in
            let a = -Float.pi / 2 + 2 * Float.pi * Float(k) / Float(Self.ringPoints)
            let c = cosf(a), s = sinf(a)
            let y = middle + (s < 0 ? -1 : 1) * powf(abs(s), s < 0 ? low : up) * half
            let across = (c < 0 ? -1 : 1) * powf(abs(c), low) * halfWidth * cap
            return (Map3DPoint(along, y, across), (y - style.floor) / (style.roof - style.floor))
        }
    }

    /// The paint of the shell at `share` of the height, `t` along the nose.
    func paint(share: Float, t: Float, front: Bool) -> UInt32 {
        if share < style.skirtTop { return style.skirt }
        // The windscreen: the nose's upper part from screenFrom on, and on a
        // flat front, its face above screenDown.
        if cab, (t > style.screenFrom && t < 0.92 && share > style.screenDown) || (front && style.nose < 2 && share > style.screenDown && share < 0.92) {
            return Map3DTrainStyle.glass
        }
        if share > 0.9 { return Map3DTrainStyle.roofColour }
        return style.body
    }

    /// The line's colour stands in for this: alpha 0 (``Map3DModelPack``).
    static let lineColour: UInt32 = Map3DColor.rgb(0x2F6DB5) & 0x00FF_FFFF

    mutating func addShell() {
        let half = style.length / 2
        let nose = cab ? style.nose : 0
        var rings: [(along: Float, t: Float)] = [(-half, 0)]
        if nose > 0 {
            let steps = max(3, Int((nose / 0.6).rounded()))
            rings.append((half - nose, 0))
            for i in 1...steps { rings.append((half - nose + nose * Float(i) / Float(steps), Float(i) / Float(steps))) }
        } else {
            rings.append((half, 0))
        }
        let sections = rings.map { ring(at: $0.along, t: $0.t) }
        let axisHeight = (style.floor + style.roof) / 2
        for i in 0..<(sections.count - 1) {
            for k in 0..<Self.ringPoints {
                let j = (k + 1) % Self.ringPoints
                let a = sections[i][k], b = sections[i][j], c = sections[i + 1][j], d = sections[i + 1][k]
                let t0 = rings[i].t, t1 = rings[i + 1].t
                let corners = [(a, t0), (b, t0), (c, t1), (d, t1)].map { ($0.0.point, paint(share: $0.0.share, t: $0.1, front: false)) }
                let centre = Map3DPoint((rings[i].along + rings[i + 1].along) / 2, axisHeight, 0)
                addTriangle(corners[0], corners[1], corners[2], outFrom: centre)
                addTriangle(corners[0], corners[2], corners[3], outFrom: centre)
            }
        }
        // The two ends: the back flat, the front its nose's tip or flat face.
        for (index, front) in [(0, false), (sections.count - 1, true)] {
            let section = sections[index]
            let middle = section.reduce(Map3DPoint.zero) { $0 + $1.point * (1 / Float(Self.ringPoints)) }
            let share = section.reduce(Float(0)) { $0 + $1.share } / Float(Self.ringPoints)
            let t = rings[index].t
            let centreColour = paint(share: share, t: t, front: front && cab)
            let outside = middle + Map3DPoint(front ? -1 : 1, 0, 0)
            for k in 0..<Self.ringPoints {
                let j = (k + 1) % Self.ringPoints
                addTriangle((middle, centreColour), (section[k].point, paint(share: section[k].share, t: t, front: front && cab)),
                            (section[j].point, paint(share: section[j].share, t: t, front: front && cab)), outFrom: outside)
            }
        }
    }

    /// A triangle facing away from `inside`.
    mutating func addTriangle(_ a: (Map3DPoint, UInt32), _ b: (Map3DPoint, UInt32), _ c: (Map3DPoint, UInt32), outFrom inside: Map3DPoint) {
        guard let normal = (b.0 - a.0).cross(c.0 - a.0).normalized else { return }
        let middle = (a.0 + b.0 + c.0) * (1 / 3)
        let corners = normal.dot(middle - inside) >= 0 ? [a, b, c] : [a, c, b]
        let facing = normal.dot(middle - inside) >= 0 ? normal : -normal
        mesh.appendTriangle(corners.map { Map3DVertex($0.0, normal: facing, color: $0.1) })
    }

    // MARK: Windows, doors, bands

    /// How far out the body's side stands at `share` of its height, on the
    /// straight part of the car.
    func side(at share: Float) -> Float {
        let section = ring(at: 0, t: 0).filter { $0.point.z > 0 }.sorted { $0.share < $1.share }
        guard let above = section.firstIndex(where: { $0.share >= share }), above > 0 else { return style.halfWidth }
        let a = section[above - 1], b = section[above]
        let s = b.share > a.share ? (share - a.share) / (b.share - a.share) : 0
        return a.point.z + (b.point.z - a.point.z) * s
    }

    func height(at share: Float) -> Float { style.floor + share * (style.roof - style.floor) }

    /// A panel on both sides from `along0` to `along1`, between two
    /// heights' shares, standing `proud` metres off the body; in three
    /// pieces up the side, so it follows where the side curves in.
    mutating func addPanels(along along0: Float, to along1: Float, shares: ClosedRange<Float>, proud: Float, colour: UInt32) {
        guard along1 > along0 else { return }
        let steps = 3
        let cuts = (0...steps).map { shares.lowerBound + (shares.upperBound - shares.lowerBound) * Float($0) / Float(steps) }
        for sign: Float in [-1, 1] {
            for piece in 0..<steps {
                let low = height(at: cuts[piece]), high = height(at: cuts[piece + 1])
                let outLow = side(at: cuts[piece]) + proud, outHigh = side(at: cuts[piece + 1]) + proud
                let a = Map3DPoint(along0, low, sign * outLow), b = Map3DPoint(along1, low, sign * outLow)
                let c = Map3DPoint(along1, high, sign * outHigh), d = Map3DPoint(along0, high, sign * outHigh)
                let inside = Map3DPoint((along0 + along1) / 2, (low + high) / 2, 0)
                addTriangle((a, colour), (b, colour), (c, colour), outFrom: inside)
                addTriangle((a, colour), (c, colour), (d, colour), outFrom: inside)
            }
        }
    }

    mutating func addLivery() {
        let half = style.length / 2
        let back = -half + 0.5, front = half - (cab ? style.nose : 0) - 0.3
        guard front > back else { return }
        // The band in the line's colour, and the dark line, the whole body
        // long; the doors stand over them.
        addPanels(along: back, to: front, shares: style.band, proud: 0.01, colour: Self.lineColour)
        if let line = style.line { addPanels(along: back, to: front, shares: line, proud: 0.012, colour: Map3DTrainStyle.darkLine) }
        // Doors: evenly spaced along the straight body.
        let count = max(1, style.doors)
        let span = front - back
        let doorCentres = (0..<count).map { i -> Float in
            count == 1 ? (cab ? back + style.doorWidth : front - style.doorWidth) : back + span * (Float(i) + 0.5) / Float(count)
        }
        for centre in doorCentres {
            addPanels(along: centre - style.doorWidth / 2, to: centre + style.doorWidth / 2,
                      shares: style.skirtTop...style.windows.upperBound, proud: 0.025, colour: Map3DTrainStyle.doorColour)
        }
        // Windows at their pitch, clear of the doors.
        var at = back + style.windowPitch / 2
        while at + style.windowWidth / 2 < front {
            let from = at - style.windowWidth / 2, to = at + style.windowWidth / 2
            if !doorCentres.contains(where: { abs($0 - at) < (style.doorWidth + style.windowWidth) / 2 + 0.15 }) {
                addPanels(along: from, to: to, shares: style.windows, proud: 0.02, colour: Map3DTrainStyle.glass)
            }
            at += style.windowPitch
        }
    }

    // MARK: Under and on top

    mutating func addKit() {
        let half = style.length / 2
        let back = -half + 1.2, front = half - (cab ? style.nose : 0) + (cab && style.nose > 2 ? 1.4 : -1.2)
        let length = front - back, middle = (back + front) / 2
        let forward = Map3DPoint(1, 0, 0)
        // The underframe and two bogies.
        mesh.addBox(base: Map3DPoint(middle, 0.2, 0), forward: forward, length: length, width: style.halfWidth * 1.5, height: max(0.2, style.floor - 0.2),
                    top: Map3DTrainStyle.under, side: Map3DTrainStyle.under)
        for z in [back + 2.4, front - 2.4] where length > 6 {
            mesh.addBox(base: Map3DPoint(z, 0, 0), forward: forward, length: 2.8, width: style.halfWidth * 1.45, height: 0.75,
                        top: Map3DTrainStyle.under, side: Map3DTrainStyle.under)
        }
        // The air-conditioning boxes along the roof.
        let units = max(1, Int((length - 1.2) / 4.5))
        for i in 0..<units {
            let z = back + 0.6 + (length - 1.2) * (Float(i) + 0.5) / Float(units)
            mesh.addBox(base: Map3DPoint(z, style.roof - 0.02, 0), forward: forward, length: 2.2, width: style.halfWidth * 1.25, height: 0.3,
                        top: Map3DTrainStyle.roofColour, side: Map3DColor.shaded(Map3DTrainStyle.roofColour, 0.92))
        }
    }

    // MARK: The model

    func model(named name: String) -> Map3DModelPack.Model {
        var builder = self
        builder.addShell()
        builder.addLivery()
        builder.addKit()
        // Into the model's frame: x stays the front, the left is −z, up is y;
        // three vertices to a triangle, each with the triangle's normal.
        return Map3DModelPack.Model.flat(named: name, from: builder.mesh)
    }
}

/// One car drawn with a model (decision 230): which model, where it stands
/// and the line's colour for its stripes. Laid out as Metal reads it: a
/// 4 × 4 matrix (model space to the scene), then the stripe colour as four
/// floats: 80 bytes.
public struct Map3DInstance: Sendable {
    public let model: Int
    /// Column by column.
    public let transform: [Float]
    public let stripe: (Float, Float, Float)

    /// The 20 floats the shader reads.
    public var floats: [Float] {
        transform + [stripe.0, stripe.1, stripe.2, 1]
    }
}
