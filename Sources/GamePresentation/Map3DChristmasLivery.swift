import Foundation
import GameCore

/// Decision 806 (in place of decision 795's whole car painted red): the
/// Christmas livery as decoration on a car's own paint. Every car's roof
/// under snow, a garland with a row of bulbs along both edges of the roof,
/// lit at night; a cab car also a wreath on its front and two ribbons
/// crossed over its roof behind the cab, a bow where they cross. A car's
/// sides, its line's colour and its shape stay its own.
///
/// What a model wears (``Wear``) is worked out when the model pack is made,
/// from its name and its side walls; the decoration itself the first time a
/// car of it is drawn so (``dressed(_:minimum:maximum:wear:)``), from the
/// model's own triangles: the app makes a second vertex buffer, the model's
/// vertices with the roof repainted and the decoration's after them. No
/// model and no vertex of the pack changes, so their hashes do not.
public enum Map3DChristmasLivery {
    /// What a running car's model wears.
    public struct Wear: Equatable, Sendable {
        /// A cab at its front (model +x): the wreath, the ribbons and the bow there.
        public let front: Bool
        /// A cab at its back.
        public let back: Bool
        /// A far set's car (decision 408): the snow and a lit line along
        /// each edge of the roof, nothing else.
        public let far: Bool
        /// The top of its side walls, metres over the rail.
        public let top: Float
    }

    // The four colours, the winter decorations' own (decision 790): no new colour.
    static let red = Map3DWinterDecor.Material.ornamentRed.colour
    static let green = Map3DWinterDecor.Material.firGreen.colour
    static let gold = Map3DWinterDecor.Material.starGold.colour
    static let snow = Map3DWinterDecor.Material.ornamentWhite.colour
    static let bulb = Map3DWinterDecor.Material.bulbWarm.colour
    static let redBulb = Map3DWinterDecor.Material.bulbRed.colour

    /// A triangle whose normal turns this far to the side (model space +y
    /// the left) is a side.
    static let sideward: Float = 0.6
    /// A roof face looks up at least this much,
    static let upward: Float = 0.5
    /// and lies between this far under the side walls' top and this far over it.
    static let roofUnder: Float = 0.3
    static let roofOver: Float = 0.8
    /// A roof more saturated than this keeps its own colour (the Alishan
    /// cars' red); a grey one, however dark, is under snow.
    static let ownColour: Float = 0.5
    /// Metres from one bulb to the next, a bulb's half width, and every
    /// which bulb is red.
    static let bulbPitch: Float = 1
    static let bulbSize: Float = 0.2
    static let redEvery = 4
    /// The garland's width, the red line's along its inner edge, and how
    /// far in from the side wall its middle lies.
    static let garland: Float = 0.42
    static let trim: Float = 0.16
    static let inset: Float = 0.2
    /// The ribbons' width, and the share of it each gold edge takes.
    static let ribbon: Float = 1.1
    static let ribbonEdge: Float = 0.18
    /// The wreath's width, as a share of the car's.
    static let wreath: Float = 0.42
    /// WREATH-NOSE: a cab whose windscreen's lower edge lies this far
    /// behind its front has a long nose (the 700T's, the Puyuma's, the
    /// EMU3000's): its wreath, this share of the usual size and thicker
    /// (it is small), lies on the tip, at least ``wreathGap`` under the
    /// glass and over the tip, and the windscreen stays clear.
    static let longNose: Float = 1
    static let noseWreath: Float = 0.7
    static let wreathGap: Float = 0.12
    /// The least height of slope between the tip and the glass a nose's wreath needs.
    static let noseRoom: Float = 0.5
    /// The front share of a car its cab's glass is looked for in.
    static let cabShare: Float = 0.35
    /// A far car's lit line's width.
    static let farLine: Float = 0.24

    /// What `model` wears: `nil` for one that is no running car.
    static func wear(of model: Map3DModelPack.Model) -> Wear? {
        guard Map3DTrainLights.isRunning(model.name), !model.vertices.isEmpty else { return nil }
        let unit = model.name.split(separator: "-").last.map(String.init) ?? ""
        let far = farPrefixes.contains { model.name.hasPrefix($0) }
        return Wear(front: ["head", "cab", "single"].contains(unit), back: ["tail", "single"].contains(unit), far: far,
                    top: wallTop(model.vertices, minimum: model.minimum, maximum: model.maximum))
    }

    /// The names the far sets' cars begin with.
    static let farPrefixes: [String] = Set(Map3DTrainSet.all.compactMap(\.far)).sorted().map { "set-\($0)-" }

    /// The top of a car's side walls: the highest sideward face out by its
    /// sides (a pantograph and what stands on the roof are nearer the middle).
    static func wallTop(_ vertices: [Map3DVertex], minimum: Map3DPoint, maximum: Map3DPoint) -> Float {
        let half = max(abs(minimum.y), abs(maximum.y))
        var top: Float = 0
        for first in stride(from: 0, to: vertices.count - 2, by: 3) where abs(vertices[first].ny) >= sideward {
            for at in first..<first + 3 where abs(vertices[at].y) >= half * 0.8 { top = max(top, vertices[at].z) }
        }
        return top > 0 ? top : minimum.z + (maximum.z - minimum.z) * 0.85
    }

    /// `vertices` (a model's in the pack, three to a triangle) in the
    /// livery: its roof under snow, then the decoration's own triangles.
    public static func dressed(_ vertices: [Map3DVertex], minimum: Map3DPoint, maximum: Map3DPoint, wear: Wear) -> [Map3DVertex] {
        var out = vertices
        for first in stride(from: 0, to: out.count - 2, by: 3) where isRoof(out, first, top: wear.top) {
            for at in first..<first + 3 {
                out[at].color = Map3DColor.shaded(snow, min(1, max(0.86, 0.8 + 0.25 * luminance(out[at].color))))
                // Decision 450: under snow, it is no longer stainless.
                if out[at].layer == Map3DVertex.trainSteel {
                    out[at].layer = Map3DVertex.plain
                    out[at].u = 0
                }
            }
        }
        return out + decoration(of: vertices, minimum: minimum, maximum: maximum, wear: wear)
    }

    /// Whether the triangle at `first` is a roof face the snow lies on.
    static func isRoof(_ vertices: [Map3DVertex], _ first: Int, top: Float) -> Bool {
        let a = vertices[first]
        guard a.nz >= upward, a.layer == Map3DVertex.plain || a.layer == Map3DVertex.trainSteel, a.color >> 24 == 0xFF,
              !Map3DTrainLights.isGlass(a.color), !Map3DTrainLights.lensColours.contains(a.color) else { return false }
        let middle = (a.z + vertices[first + 1].z + vertices[first + 2].z) / 3
        guard middle >= top - roofUnder, middle <= top + roofOver else { return false }
        return Map3DGlow.saturation(a.color) <= ownColour
    }

    /// The decoration's triangles for a model's `vertices`.
    public static func decoration(of vertices: [Map3DVertex], minimum: Map3DPoint, maximum: Map3DPoint, wear: Wear) -> [Map3DVertex] {
        var dresser = Dresser(vertices, minimum: minimum, maximum: maximum, top: wear.top)
        if wear.far {
            dresser.addEdges(far: true)
        } else {
            dresser.addEdges(far: false)
            for nose: Float in (wear.front ? [1] : []) + (wear.back ? [-1] : []) {
                dresser.addWreath(nose: nose)
                dresser.addRibbons(nose: nose)
            }
        }
        return dresser.out
    }

    /// The two soft glows over a car in the livery at night, in its model's
    /// space: one over each half of its roof, for all its bulbs together
    /// (a glow a bulb would be 40 a car). None for a far car.
    public static func halos(minimum: Map3DPoint, maximum: Map3DPoint, wear: Wear) -> [Map3DGlow.Spot] {
        guard !wear.far else { return [] }
        let length = maximum.x - minimum.x
        let c = channels(bulb), most = max(c[0], c[1], c[2], 1)
        return [0.27, 0.73].map { share in
            Map3DGlow.Spot(centre: Map3DPoint(minimum.x + length * share, 0, wear.top + 0.3), radius: min(max(length * 0.2, 2.2), 4),
                           red: c[0] / most, green: c[1] / most, blue: c[2] / most, strength: haloStrength)
        }
    }

    static let haloStrength: Float = 0.5

    /// How bright the cars' glows are `seconds` into the app's clock: a slow
    /// swell, once in ``twinklePeriod`` seconds, between ``twinkleLow`` and 1.
    /// The bulbs themselves stay lit. Steady with Reduce Motion (the motion
    /// skill §3: nothing loops by itself).
    public static func twinkle(seconds: Double, reduceMotion: Bool) -> Float {
        guard !reduceMotion else { return 1 }
        let phase = (seconds / twinklePeriod).truncatingRemainder(dividingBy: 1)
        // A triangle wave eased at both ends.
        let wave = Float(phase < 0.5 ? phase * 2 : 2 - phase * 2)
        let eased = wave * wave * (3 - 2 * wave)
        return twinkleLow + (1 - twinkleLow) * eased
    }

    static let twinklePeriod: Double = 3.2
    static let twinkleLow: Float = 0.6

    static func channels(_ colour: UInt32) -> [Float] {
        [0, 8, 16].map { Float((colour >> UInt32($0)) & 0xFF) }
    }

    static func luminance(_ colour: UInt32) -> Float {
        let c = channels(colour)
        return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255
    }
}

/// A car's mesh asked where its surface is, and the decoration laid on it.
struct Dresser {
    private let corners: [Map3DPoint]
    /// The window glass's triangles that do not face sideways, over the
    /// floor (under it, a box coloured as glass): their first corners, and
    /// how far each faces forward (model +x).
    private var glass: [(first: Int32, forward: Float)] = []
    /// The triangles over each half metre of the car's length.
    private var bins: [[Int32]]
    private let low: Map3DPoint, high: Map3DPoint
    private let half: Float, top: Float, bottom: Float
    /// A car whose sides are red wears green ribbons and a gold bow.
    private let redBody: Bool
    var out: [Map3DVertex] = []

    private static let cell: Float = 0.5

    init(_ vertices: [Map3DVertex], minimum: Map3DPoint, maximum: Map3DPoint, top: Float) {
        corners = vertices.map(\.position)
        low = minimum
        high = maximum
        self.top = top
        half = max(abs(minimum.y), abs(maximum.y))
        bottom = minimum.z + (maximum.z - minimum.z) * 0.18
        bins = Array(repeating: [], count: max(1, Int(((maximum.x - minimum.x) / Self.cell).rounded(.up)) + 1))
        var red: Float = 0, sides: Float = 0
        for first in stride(from: 0, to: vertices.count - 2, by: 3) {
            let a = corners[first], b = corners[first + 1], c = corners[first + 2]
            let from = Int((min(a.x, b.x, c.x) - minimum.x) / Self.cell), to = Int((max(a.x, b.x, c.x) - minimum.x) / Self.cell)
            for bin in max(0, from)...min(bins.count - 1, max(0, to)) { bins[bin].append(Int32(first)) }
            let v = vertices[first]
            if [Map3DVertex.trainGlass, Map3DVertex.trainGlassLit].contains(v.layer), abs(v.ny) < Map3DChristmasLivery.sideward,
               min(a.z, b.z, c.z) >= minimum.z + (maximum.z - minimum.z) * 0.3 {
                glass.append((Int32(first), v.nx))
            }
            guard abs(v.ny) >= Map3DChristmasLivery.sideward, v.color >> 24 == 0xFF, !Map3DTrainLights.isGlass(v.color),
                  a.z >= bottom, a.z <= top else { continue }
            let area = (b - a).cross(c - a).length / 2
            let ch = Map3DChristmasLivery.channels(v.color)
            sides += area
            if ch[0] > max(ch[1], ch[2]) * 1.6 { red += area }
        }
        redBody = red > sides * 0.5
    }

    /// The surface farthest along `axis` (0 x, 1 y, 2 z; `sign` its way)
    /// over the point (`u`, `v`) of the other two axes, in their order;
    /// nothing farther than `limit`.
    private func surface(axis: Int, sign: Float, _ u: Float, _ v: Float, below limit: Float = .infinity) -> Float? {
        var best: Float?
        func parts(_ p: Map3DPoint) -> (Float, Float, Float) { axis == 0 ? (p.y, p.z, p.x) : axis == 1 ? (p.x, p.z, p.y) : (p.x, p.y, p.z) }
        func look(_ first: Int) {
            let (au, av, aw) = parts(corners[first]), (bu, bv, bw) = parts(corners[first + 1]), (cu, cv, cw) = parts(corners[first + 2])
            guard u >= min(au, bu, cu), u <= max(au, bu, cu), v >= min(av, bv, cv), v <= max(av, bv, cv) else { return }
            let d = (bv - cv) * (au - cu) + (cu - bu) * (av - cv)
            guard abs(d) > 1e-9 else { return }
            let l1 = ((bv - cv) * (u - cu) + (cu - bu) * (v - cv)) / d, l2 = ((cv - av) * (u - cu) + (au - cu) * (v - cv)) / d, l3 = 1 - l1 - l2
            guard l1 >= -1e-4, l2 >= -1e-4, l3 >= -1e-4 else { return }
            let w = (l1 * aw + l2 * bw + l3 * cw) * sign
            guard w <= limit else { return }
            if best == nil || w > best! { best = w }
        }
        if axis == 0 {
            for first in stride(from: 0, to: corners.count - 2, by: 3) { look(first) }
        } else {
            let bin = Int((u - low.x) / Self.cell)
            guard bins.indices.contains(bin) else { return nil }
            for first in bins[bin] { look(Int(first)) }
        }
        return best
    }

    /// The side wall's distance from the middle at (`x`, `z`), on the left (`s` 1) or the right (-1).
    private func side(_ x: Float, _ z: Float, _ s: Float) -> Float? {
        guard let y = surface(axis: 1, sign: s, x, z), y > half * 0.45 else { return nil }
        return y
    }

    /// The roof's height at (`x`, `y`), under what stands on it.
    private func roof(_ x: Float, _ y: Float) -> Float? { surface(axis: 2, sign: 1, x, y, below: top + 0.5) }

    // MARK: Triangles

    /// A triangle seen from the side `outward` points to.
    private mutating func tri(_ a: Map3DPoint, _ b: Map3DPoint, _ c: Map3DPoint, _ colour: UInt32, outward: Map3DPoint, lit: Bool = false) {
        var n = (b - a).cross(c - a)
        guard n.length > 0 else { return }
        let turned = n.x * outward.x + n.y * outward.y + n.z * outward.z < 0
        if turned { n = n * -1 }
        n = n * (1 / n.length)
        // A face is shaded by the way it turns, as the pack's own are (decision 439); a bulb is not.
        let shown = lit ? colour : Map3DColor.shaded(colour, 0.8 + 0.2 * max(0, n.z))
        for p in turned ? [a, c, b] : [a, b, c] {
            out.append(Map3DVertex(p, normal: n, color: shown, layer: lit ? Map3DVertex.glowing : Map3DVertex.plain))
        }
    }

    private mutating func quad(_ a: Map3DPoint, _ b: Map3DPoint, _ c: Map3DPoint, _ d: Map3DPoint, _ colour: UInt32, outward: Map3DPoint, lit: Bool = false) {
        tri(a, b, c, colour, outward: outward, lit: lit)
        tri(a, c, d, colour, outward: outward, lit: lit)
    }

    /// A triangle seen from both sides.
    private mutating func leaf(_ a: Map3DPoint, _ b: Map3DPoint, _ c: Map3DPoint, _ colour: UInt32) {
        let n = (b - a).cross(c - a)
        tri(a, b, c, colour, outward: n)
        tri(a, b, c, colour, outward: n * -1)
    }

    /// The ribbons' width: narrower on a narrow car.
    private var ribbonWidth: Float { min(Map3DChristmasLivery.ribbon, half * 0.7) }

    /// Away from the car's long axis at `p`.
    private func away(_ p: Map3DPoint) -> Map3DPoint { Map3DPoint(0, p.y, p.z - (bottom + top) / 2) }

    // MARK: The roof's edges

    /// Along both edges of the roof: the garland, its red line and the
    /// bulbs; a far car's lit line alone.
    mutating func addEdges(far: Bool) {
        let up = Map3DPoint(0, 0, 1)
        let pitch = far ? Map3DChristmasLivery.bulbPitch * 2 : Map3DChristmasLivery.bulbPitch
        let inset = Map3DChristmasLivery.inset, r = Map3DChristmasLivery.bulbSize
        let width = far ? Map3DChristmasLivery.farLine : Map3DChristmasLivery.garland
        var before: [Float: Float] = [:]
        for s: Float in [1, -1] {
            var last: (inner: Map3DPoint, outer: Map3DPoint, trim: Map3DPoint)?
            var count = 0
            var x = low.x + 0.5
            while x <= high.x - 0.5 {
                defer { x += pitch }
                // The eave here: the side walls' top, or a lower bonnet's own where it runs level.
                let crown = roof(x, 0) ?? top
                let level = abs(crown - (before[s] ?? crown)) < 0.12
                before[s] = crown
                let eave = crown < top - 0.35 && level && crown > bottom + (top - bottom) * 0.4 ? crown : top
                guard let edge = side(x, eave - 0.12, s), let middle = roof(x, (edge - inset) * s), middle > eave - 0.35 else {
                    last = nil
                    continue
                }
                let innerY = edge - inset - width / 2, outerY = edge - inset + width / 2
                let innerZ = roof(x, innerY * s) ?? middle, outerZ = roof(x, outerY * s) ?? min(middle, eave) - 0.04
                let trimY = innerY - Map3DChristmasLivery.trim, trimZ = roof(x, trimY * s) ?? innerZ
                let inner = Map3DPoint(x, innerY * s, max(innerZ, eave - 0.4) + 0.05), outer = Map3DPoint(x, outerY * s, max(outerZ, eave - 0.4) + 0.05)
                let trim = Map3DPoint(x, trimY * s, max(trimZ, eave - 0.4) + 0.05)
                if let l = last {
                    if far {
                        quad(l.inner, inner, outer, l.outer, Map3DChristmasLivery.bulb, outward: up, lit: true)
                    } else {
                        quad(l.inner, inner, outer, l.outer, Map3DChristmasLivery.green, outward: up)
                        quad(l.trim, trim, inner, l.inner, Map3DChristmasLivery.red, outward: up)
                    }
                }
                last = (inner, outer, trim)
                guard !far else { continue }
                // A bulb: a small four-sided cap standing on the garland.
                let c = Map3DPoint(x, (edge - inset) * s, max(middle, eave - 0.4) + 0.06)
                let colour = count % Map3DChristmasLivery.redEvery == Map3DChristmasLivery.redEvery - 1 ? Map3DChristmasLivery.redBulb : Map3DChristmasLivery.bulb
                count += 1
                let base = [Map3DPoint(r, r, 0), Map3DPoint(-r, r, 0), Map3DPoint(-r, -r, 0), Map3DPoint(r, -r, 0)].map { c + $0 }
                let tip = c + Map3DPoint(0, 0, r * 1.3)
                for at in 0..<4 {
                    let a = base[at], b = base[(at + 1) % 4]
                    tri(a, b, tip, colour, outward: (a + b) * 0.5 - c + up * 0.1, lit: true)
                }
            }
        }
    }

    // MARK: A cab's end

    /// Where the roof behind the cab at `nose` reaches its full height:
    /// past a long nose's slope.
    private func shoulder(_ nose: Float) -> Float {
        var x = nose > 0 ? high.x : low.x
        for _ in 0..<80 {
            if let z = roof(x, 0), z > top - 0.3 { break }
            x -= nose * 0.25
        }
        return x
    }

    /// Two ribbons crossed over the roof behind the cab, as round a
    /// parcel, and a bow where they cross.
    mutating func addRibbons(nose: Float) {
        let length = high.x - low.x, lean = min(length * 0.2, 4)
        let centre = shoulder(nose) - nose * (lean / 2 + 0.7)
        addRibbon(at: centre, lean: lean)
        addRibbon(at: centre, lean: -lean)
        addBow(at: centre)
    }

    /// A band up one side, over the roof and down the other, `lean`
    /// metres along the car from one hem to the other.
    private mutating func addRibbon(at centre: Float, lean: Float) {
        let step: Float = 0.5, rise = top - bottom, across = half * 2, whole = rise * 2 + across
        var path: [Map3DPoint] = []
        func x(_ d: Float) -> Float { centre + lean * (d / whole - 0.5) }
        var z = bottom
        while z < top - 0.02 {
            if let y = side(x(z - bottom), z, 1) { path.append(Map3DPoint(x(z - bottom), y + 0.04, z)) }
            z += step
        }
        var y = half
        while y >= -half {
            let d = rise + (half - y)
            if let over = roof(x(d), y * 0.97) { path.append(Map3DPoint(x(d), y * 0.97, max(over, top - 0.4) + 0.07)) }
            y -= step
        }
        z = top - 0.02
        while z >= bottom {
            let d = rise + across + (top - z)
            if let y = side(x(d), z, -1) { path.append(Map3DPoint(x(d), -(y + 0.04), z)) }
            z -= step
        }
        let h = ribbonWidth / 2, edge = ribbonWidth * Map3DChristmasLivery.ribbonEdge
        let cuts: [Float] = [-h, edge - h, h - edge, h]
        let colours: [UInt32] = [Map3DChristmasLivery.gold, redBody ? Map3DChristmasLivery.green : Map3DChristmasLivery.red, Map3DChristmasLivery.gold]
        for (p, q) in zip(path, path.dropFirst()) where (q - p).length < 1.6 {
            let outward = away((p + q) * 0.5)
            for at in 0..<3 {
                let a = Map3DPoint(cuts[at], 0, 0), b = Map3DPoint(cuts[at + 1], 0, 0)
                quad(p + a, p + b, q + b, q + a, colours[at], outward: outward)
            }
        }
    }

    /// A bow on the roof: two loops across the car, two tails along it.
    private mutating func addBow(at x: Float) {
        guard let over = roof(x, 0) else { return }
        let r = ribbonWidth * 1.3, colour = redBody ? Map3DChristmasLivery.gold : Map3DChristmasLivery.red
        let c = Map3DPoint(x, 0, max(over, top - 0.4) + 0.12)
        for s: Float in [1, -1] {
            leaf(c, c + Map3DPoint(r * 0.55, s * r, 0.45), c + Map3DPoint(-r * 0.55, s * r, 0.45), colour)
            leaf(c, c + Map3DPoint(s * r * 0.9, r * 0.3, 0.05), c + Map3DPoint(s * r * 0.9, -r * 0.3, 0.05), Map3DColor.shaded(colour, 0.85))
        }
    }

    /// The lower edge of the windscreen of the cab at `nose`: the lowest
    /// corner of the glass facing that way (not sideways) in the car's front
    /// part, among the panes over the middle `span` metres either side of
    /// its axis. `nil` for a cab with no such glass.
    func windscreen(nose: Float, span: Float) -> (x: Float, z: Float)? {
        let front = nose > 0 ? high.x : -low.x, reach = (high.x - low.x) * Map3DChristmasLivery.cabShare
        var best: (x: Float, z: Float)?
        for (first, forward) in glass where forward * nose > 0 {
            let at = Int(first), a = corners[at], b = corners[at + 1], c = corners[at + 2]
            guard [a, b, c].allSatisfy({ $0.x * nose > front - reach }),
                  min(a.y, b.y, c.y) <= span, max(a.y, b.y, c.y) >= -span else { continue }
            for p in [a, b, c] where best.map({ p.z < $0.z }) ?? true { best = (p.x, p.z) }
        }
        return best
    }

    /// The windscreen's lower edge (``windscreen(nose:span:)``) of the cab
    /// at `nose` if it has a long nose: that edge at least
    /// ``Map3DChristmasLivery/longNose`` behind its front, where a wreath on
    /// its front would lie on the glass; otherwise `nil`.
    func longNose(_ nose: Float) -> (x: Float, z: Float)? {
        let front = nose > 0 ? high.x : -low.x
        guard let edge = windscreen(nose: nose, span: half * Map3DChristmasLivery.wreath),
              front - edge.x * nose >= Map3DChristmasLivery.longNose else { return nil }
        return edge
    }

    /// A wreath on the cab's front: on a long nose (``longNose(_:)``) a
    /// smaller one on its tip under the windscreen, which stays clear;
    /// otherwise on the front, leaning with it.
    mutating func addWreath(nose: Float) {
        if let edge = longNose(nose), addNoseWreath(nose: nose, under: edge.z) { return }
        let outer = half * Map3DChristmasLivery.wreath, inner = outer * 0.55, height = bottom + (top - bottom) * 0.62
        func front(_ y: Float, _ z: Float) -> Float? { surface(axis: 0, sign: nose, y, z) }
        guard let mid = front(0, height) else { return }
        let over = front(0, height + outer) ?? mid, foot = front(0, height - outer) ?? mid
        // The plane it lies in: leaning with the nose, never further than 70 degrees back.
        let lean = max(-2.7, min(2.7, (over - foot) / (2 * outer)))
        func at(_ r: Float, _ t: Float, _ off: Float = 0) -> Map3DPoint {
            let z = sin(t * 2 * .pi) * r
            // Never out past the car's own front (a bonnet under a cab leans it forward).
            let reach = min(max(mid, (over + foot) / 2) + lean * z, (nose > 0 ? high.x : -low.x) + 0.02)
            return Map3DPoint((reach + 0.08 + off) * nose, cos(t * 2 * .pi) * r, height + z)
        }
        let outward = Map3DPoint(nose, 0, 0.6)
        let steps = 12
        for step in 0..<steps {
            let a = Float(step) / Float(steps), b = Float(step + 1) / Float(steps)
            quad(at(inner, a), at(outer, a), at(outer, b), at(inner, b), Map3DColor.shaded(Map3DChristmasLivery.green, step % 2 == 0 ? 1 : 0.8), outward: outward)
        }
        let knot = at(outer * 0.82, 0.75, 0.04), w = outer * 0.55, h = outer * 0.4
        let knotColour = redBody ? Map3DChristmasLivery.gold : Map3DChristmasLivery.red
        tri(knot, knot + Map3DPoint(0, -w, h * 0.6), knot + Map3DPoint(0, -w, -h), knotColour, outward: outward)
        tri(knot, knot + Map3DPoint(0, w, -h), knot + Map3DPoint(0, w, h * 0.6), knotColour, outward: outward)
    }

    /// The wreath on a long nose's tip: lying on the slope between the tip
    /// and ``Map3DChristmasLivery/wreathGap`` under the windscreen's lower
    /// edge `glass`, round on the slope, never out past the car's front.
    /// `false`, and nothing, where the nose there is no slope (a hood's
    /// flat top) or has no room.
    @discardableResult
    mutating func addNoseWreath(nose: Float, under glass: Float) -> Bool {
        let front = nose > 0 ? high.x : -low.x, ceiling = glass - Map3DChristmasLivery.wreathGap
        func ahead(_ y: Float, _ z: Float) -> Float? { surface(axis: 0, sign: nose, y, z) }
        // The nose's middle, every 5 cm up to under the glass: its tip is the
        // highest of its foremost points.
        var profile: [(z: Float, x: Float)] = []
        var z = bottom
        while z <= ceiling {
            if let x = ahead(0, z) { profile.append((z, x)) }
            z += 0.05
        }
        guard let foremost = profile.map(\.x).max(), let tip = profile.last(where: { $0.x >= foremost - 0.05 }),
              let under = profile.last else { return false }
        let lower = tip.z + Map3DChristmasLivery.wreathGap, room = ceiling - lower
        // Metres back for each metre up, over that stretch; a ring this
        // round on the slope is that much lower than wide.
        let lean = (tip.x - under.x) / max(under.z - tip.z, 0.01)
        guard room >= Map3DChristmasLivery.noseRoom, lean >= 0.3, lean <= 6 else { return false }
        let cosine = 1 / (1 + lean * lean).squareRoot()
        let outer = min(half * Map3DChristmasLivery.wreath * Map3DChristmasLivery.noseWreath, room / 2 / cosine), inner = outer * 0.45
        let middle = lower + room / 2
        let normal = Map3DPoint(nose * cosine, 0, lean * cosine), upSlope = Map3DPoint(-nose * lean * cosine, 0, cosine)
        func at(_ r: Float, _ t: Float, _ lift: Float = 0.06) -> Map3DPoint {
            let y = cos(t * 2 * .pi) * r, z = middle + sin(t * 2 * .pi) * r * cosine
            let x = ahead(y, z) ?? ahead(0, z) ?? foremost
            return Map3DPoint(min(x + lift * cosine, front) * nose, y, z + lift * lean * cosine)
        }
        let outward = normal + Map3DPoint(0, 0, 0.3)
        let steps = 12
        for step in 0..<steps {
            let a = Float(step) / Float(steps), b = Float(step + 1) / Float(steps)
            quad(at(inner, a), at(outer, a), at(outer, b), at(inner, b), Map3DColor.shaded(Map3DChristmasLivery.green, step % 2 == 0 ? 1 : 0.8), outward: outward)
        }
        let knot = at(outer * 0.82, 0.75, 0.1), w = outer * 0.55, h = outer * 0.4
        let side = Map3DPoint(0, 1, 0)
        let knotColour = redBody ? Map3DChristmasLivery.gold : Map3DChristmasLivery.red
        tri(knot, knot - side * w + upSlope * (h * 0.6), knot - side * w - upSlope * h, knotColour, outward: outward)
        tri(knot, knot + side * w - upSlope * h, knot + side * w + upSlope * (h * 0.6), knotColour, outward: outward)
        return true
    }
}

extension GameSession {
    /// Decision 795: the passenger lines drawn in the Christmas livery now:
    /// those chosen that still run passengers, while it can be chosen.
    public var christmasLiveryLines: Set<LineID> {
        guard christmasLiveryAvailable, !christmasLiveryChosen.isEmpty else { return [] }
        return Set(world.lines.filter { !$0.isFreight && christmasLiveryChosen.contains($0.id) }.map(\.id))
    }

    /// Decision 795: whether `line` wears the Christmas livery.
    public func wearsChristmasLivery(_ line: LineID) -> Bool {
        christmasLiveryLines.contains(line)
    }

    /// Decision 795: puts the Christmas livery on `line` or takes it off;
    /// nothing while it cannot be chosen. Only how its trains look: no
    /// command, nothing saved with the game.
    public func setChristmasLivery(_ on: Bool, for line: LineID) {
        guard christmasLiveryAvailable, world.lines.contains(where: { $0.id == line && !$0.isFreight }) else { return }
        var chosen = christmasLiveryChosen.filter { id in world.lines.contains { $0.id == id } }
        if on { chosen.insert(line) } else { chosen.remove(line) }
        guard chosen != christmasLiveryChosen else { return }
        christmasLiveryChosen = chosen
        christmasLiveryChanged?(chosen)
    }

    /// Decision 795 (later): whether every passenger line wears the
    /// Christmas livery; false with none to wear it.
    public var allPassengerLinesWearChristmasLivery: Bool {
        let passenger = world.lines.filter { !$0.isFreight }
        return !passenger.isEmpty && christmasLiveryLines.count == passenger.count
    }

    /// Decision 795 (later): puts the Christmas livery on every passenger
    /// line the company has now, or takes it off them all, in one change;
    /// nothing while it cannot be chosen. A line opened afterwards is
    /// chosen on its own.
    public func setChristmasLiveryOnAllPassengerLines(_ on: Bool) {
        guard christmasLiveryAvailable else { return }
        let chosen = on ? Set(world.lines.filter { !$0.isFreight }.map(\.id)) : []
        guard chosen != christmasLiveryChosen else { return }
        christmasLiveryChosen = chosen
        christmasLiveryChanged?(chosen)
    }
}
