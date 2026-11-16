import GameCore

/// Decision 795: the Christmas livery (``Map3DWinterDecor/christmasLivery``,
/// decision 790) put on each running car by its own parts, as the trains'
/// livery bands are drawn (the rolling-stock skill §4): its body red, its
/// band white, its thin lines gold; its roof, front, windows, lamps, dark
/// window bands and frames and running gear as they are.
///
/// Worked out once a model, from its recipe, when the model pack is made:
/// a byte a vertex (``Map3DModelPack/christmas``), the part in its low two
/// bits and the shade the pack baked into it (decision 439's soft shade) in
/// the other six. The app makes a second vertex buffer of a model the first
/// time a car of it is drawn in the livery (``recoloured(_:table:livery:)``);
/// no model and no vertex of the pack changes, so their hashes do not.
public enum Map3DChristmasLivery {
    /// A part of a car the livery repaints.
    public enum Part: UInt8, Sendable {
        /// Left as it is: the roof, the front, glass, lamps, the dark
        /// window bands and frames, the running gear.
        case keep = 0
        /// The body (most of a car's sides, its doors with it).
        case body = 1
        /// The band: the line's colour band, or a wide second colour.
        case band = 2
        /// A thin line: a narrow stripe or a small second colour.
        case line = 3
    }

    /// A triangle whose normal turns this far to the side (model space +y
    /// the left) is a side; the rest (roof, front, floor) keep their paint.
    static let sideward: Float = 0.6
    /// The share of a car's height its side's paint is looked for between:
    /// above the running gear, below the roof's edge.
    static let lowest: Float = 0.18
    static let highest: Float = 0.93
    /// A second colour covering at least this share of a side is a band;
    /// less, a thin line.
    static let bandShare: Float = 0.12
    /// Darker than this (relative luminance) is a window band, a frame or
    /// a skirt, never repainted unless it is the body itself.
    static let dark: Float = 0.2

    /// Each vertex's part in `recipe` (three alike a triangle).
    public static func parts(of recipe: Map3DModelPack.Model) -> [Part] {
        classified(recipe).map(\.part)
    }

    /// Each vertex's part and the colour its shade is measured from: its
    /// colour family's (the shades of one colour a recipe turns a side
    /// with keep their steps), a band's own.
    static func classified(_ recipe: Map3DModelPack.Model) -> [(part: Part, base: UInt32)] {
        let vertices = recipe.vertices
        var parts = vertices.map { (part: Part.keep, base: $0.color) }
        let bottom = recipe.minimum.z, height = recipe.maximum.z - recipe.minimum.z
        guard height > 0, vertices.count >= 3 else { return parts }
        struct Face { let first: Int; let area: Float; let low: Float; let high: Float }
        var opaque: [UInt32: [Face]] = [:]
        var striped: [Face] = []
        for first in stride(from: 0, to: vertices.count - 2, by: 3) {
            let a = vertices[first], b = vertices[first + 1], c = vertices[first + 2]
            guard a.layer == Map3DVertex.plain, abs(a.ny) >= sideward else { continue }
            let colour = a.color
            if colour >> 24 == 0xFF {
                guard !Map3DTrainLights.isGlass(colour), !Map3DTrainLights.lensColours.contains(colour) else { continue }
            }
            let middle = ((a.z + b.z + c.z) / 3 - bottom) / height
            guard middle >= lowest, middle <= highest else { continue }
            let area = ((b.position - a.position).cross(c.position - a.position)).length / 2
            guard area > 0 else { continue }
            let face = Face(first: first, area: area, low: min(a.z, b.z, c.z), high: max(a.z, b.z, c.z))
            if colour >> 24 == 0xFF { opaque[colour, default: []].append(face) } else { striped.append(face) }
        }
        // The opaque colours, shades of one colour (as a recipe shades a
        // face by the way it turns) taken together.
        let colours = opaque.keys.sorted { lhs, rhs in
            let l = opaque[lhs]!.reduce(0) { $0 + $1.area }, r = opaque[rhs]!.reduce(0) { $0 + $1.area }
            return l != r ? l > r : lhs < rhs
        }
        var families: [(base: UInt32, colours: [UInt32], area: Float)] = []
        for colour in colours {
            let area = opaque[colour]!.reduce(0) { $0 + $1.area }
            if let at = families.firstIndex(where: { Self.isShade(colour, of: $0.base) }) {
                families[at].colours.append(colour)
                families[at].area += area
            } else {
                families.append((colour, [colour], area))
            }
        }
        // The line's colour bands, by the heights they cover.
        var bands: [(faces: [Face], low: Float, high: Float, area: Float)] = []
        for face in striped.sorted(by: { $0.low != $1.low ? $0.low < $1.low : $0.first < $1.first }) {
            if let last = bands.indices.last, face.low <= bands[last].high + 0.05 {
                bands[last].faces.append(face)
                bands[last].high = max(bands[last].high, face.high)
                bands[last].area += face.area
            } else {
                bands.append(([face], face.low, face.high, face.area))
            }
        }
        let bandOrder = bands.indices.sorted { bands[$0].area != bands[$1].area ? bands[$0].area > bands[$1].area : $0 < $1 }
        func mark(_ faces: [Face], _ part: Part, base: UInt32? = nil) {
            for face in faces { for at in face.first..<face.first + 3 { parts[at] = (part, base ?? vertices[at].color) } }
        }
        // The body: the most of the side, a dark colour counted at half
        // (a window band is dark; a dark body is still found).
        let weight = { (family: (base: UInt32, colours: [UInt32], area: Float)) -> Float in
            family.area * (Self.luminance(family.base) < dark ? 0.5 : 1)
        }
        let bodyFamily = families.indices.max { weight(families[$0]) != weight(families[$1]) ? weight(families[$0]) < weight(families[$1]) : $0 > $1 }
        // A car painted all in the line's colour (a named formation's
        // main colour drawn as a band) has that band for its body.
        let stripedBody = bandOrder.first.map { bands[$0].area > (bodyFamily.map { families[$0].area } ?? 0) } ?? false
        let sideArea = families.reduce(0) { $0 + $1.area }
        for (at, family) in families.enumerated() {
            let faces = family.colours.flatMap { opaque[$0]! }
            let base = family.colours.max { channels($0).reduce(0, +) < channels($1).reduce(0, +) } ?? family.base
            if at == bodyFamily, !stripedBody {
                mark(faces, .body, base: base)
            } else if Self.luminance(family.base) >= dark {
                mark(faces, at == bodyFamily || family.area >= bandShare * sideArea ? .band : .line, base: base)
            }
        }
        for (rank, at) in bandOrder.enumerated() {
            mark(bands[at].faces, rank == 0 ? (stripedBody ? .body : .band) : .line)
        }
        return parts
    }

    /// Each vertex's byte of the table: its part in `recipe` and the shade
    /// `baked` (the pack's copy) has over it; `nil` when they do not match
    /// or nothing is repainted.
    static func table(recipe: Map3DModelPack.Model, baked: Map3DModelPack.Model) -> [UInt8]? {
        guard recipe.vertices.count == baked.vertices.count else { return nil }
        let parts = classified(recipe)
        guard parts.contains(where: { $0.part != .keep }) else { return nil }
        return parts.indices.map { at in
            let (part, base) = parts[at]
            guard part != .keep else { return 0 }
            // A band's alpha share is never shaded (decision 439); a side's
            // colour is its family's brightest in the recipe's steps, then
            // the pack's soft shade.
            let shade = recipe.vertices[at].color >> 24 == 0xFF
                ? Self.shade(of: baked.vertices[at].color, over: base) : 1
            return part.rawValue | (UInt8((shade * 63).rounded()) << 2)
        }
    }

    /// `vertices` (a model's in the pack) in `livery` where `table` says:
    /// the part's colour in the vertex's own shade, a band no longer the
    /// line's colour, a stainless body painted.
    public static func recoloured(
        _ vertices: [Map3DVertex], table: [UInt8], livery: Map3DWinterDecor.Livery = Map3DWinterDecor.christmasLivery
    ) -> [Map3DVertex] {
        guard table.count == vertices.count else { return vertices }
        var out = vertices
        for at in out.indices {
            let byte = table[at]
            guard let part = Part(rawValue: byte & 0b11), part != .keep else { continue }
            let colour: UInt32 = switch part {
            case .body: livery.body
            case .band: livery.band
            case .line: livery.line
            case .keep: out[at].color
            }
            out[at].color = Map3DColor.shaded(colour | 0xFF00_0000, Float(byte >> 2) / 63)
            // Decision 450: painted, it is no longer stainless.
            if out[at].layer == Map3DVertex.trainSteel {
                out[at].layer = Map3DVertex.plain
                out[at].u = 0
            }
        }
        return out
    }

    /// How bright `colour` is beside `base`, 0 to 1.
    static func shade(of colour: UInt32, over base: UInt32) -> Float {
        let sum = channels(base).reduce(0, +)
        guard sum > 0 else { return 1 }
        return min(1, max(0, channels(colour).reduce(0, +) / sum))
    }

    /// Whether `colour` is a shade of `base` (as a recipe shades a face by
    /// the way it turns, at most some 12 % darker or lighter; a grey or
    /// white 30 %).
    static func isShade(_ colour: UInt32, of base: UInt32) -> Bool {
        let a = channels(colour), b = channels(base)
        let sa = a.reduce(0, +), sb = b.reduce(0, +)
        // A grey or white (a stainless or white body and its lower panel)
        // is one body over a wider range.
        let neutral = [a, b].allSatisfy { ($0.max() ?? 0) - ($0.min() ?? 0) <= 16 }
        guard sa > 0, sb > 0, min(sa, sb) / max(sa, sb) >= (neutral ? 0.7 : 0.88) else { return false }
        return (0..<3).allSatisfy { abs(a[$0] / sa - b[$0] / sb) < 0.02 }
    }

    static func channels(_ colour: UInt32) -> [Float] {
        [0, 8, 16].map { Float((colour >> UInt32($0)) & 0xFF) }
    }

    static func luminance(_ colour: UInt32) -> Float {
        let c = channels(colour)
        return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255
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
}
