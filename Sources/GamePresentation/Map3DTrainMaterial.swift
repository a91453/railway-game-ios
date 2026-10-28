/// Decision 450: which faces of a train model are window glass and which
/// a stainless body, marked once as the pack is made (before decision
/// 439's shade is baked into the colour), so the shader can mirror the sky
/// in them and catch the sun (``Map3DReflection``, `map3dShade`).
///
/// The recipes paint their glass with a few colours (``glassColours``),
/// each at its own darkness; a face of any shade of one of them, not
/// looking down, is glass. A lamp-lit pane (``Map3DVertex/glowing``)
/// stays lit and becomes ``Map3DVertex/trainGlassLit``.
///
/// Stainless is a set's, not a colour's: the sets built of unpainted
/// stainless steel (``stainlessSets``, the reference's garage models'
/// silver bodies), their light neutral faces (``isSteelColour(_:)``) that
/// do not look down; a band in the line's colour (alpha below 1), a
/// painted face and the dark under-frame stay as they are.
public enum Map3DTrainMaterial {
    /// The colours the recipes paint glass with (any shade of them):
    /// ``Map3DPalette/glazing`` (EMU500, EMU800, EMU900, EMU3000, C341,
    /// E500, the LRTs, the refreshed shapes…), ``Map3DTrainStyle/glass``
    /// (the drawn styles, the TEMU1000's cab, the trams) and the TEMUs'
    /// passenger glass.
    static let glassColours: [UInt32] = [Map3DPalette.glazing, Map3DTrainStyle.glass, Map3DTEMU2000.glass]

    /// The sets of unpainted stainless steel, by the key their models are
    /// named with (`set-<key>-…`, `set-<key>Far-…`, `<key>-…`): the
    /// EMU500, EMU800, EMU900, the Taipei Metro's C341 and C381, the
    /// DR1000 railcar and the DR3100 diesel express.
    static let stainlessSets: Set<String> = ["emu500", "emu800", "emu900", "c341", "c371", "c381", "metroC341", "metroC381",
                                             "dieselRailcar", "dieselExpress"]

    /// A face looking down more than this (its normal's z) is neither: an
    /// under-floor is not seen against the sky.
    static let lowestNormal: Float = -0.3

    /// Whether model `name` is of a stainless set.
    static func isStainless(_ name: String) -> Bool {
        var parts = name.split(separator: "-").map(String.init)
        if parts.first == "set" { parts.removeFirst() }
        guard var key = parts.first else { return false }
        if key.hasSuffix("Far") { key.removeLast(3) }
        return stainlessSets.contains(key)
    }

    /// Whether `colour` is a shade of `glass`: each channel `glass`'s
    /// times one factor, give or take the rounding. The darkest glass a
    /// recipe paints is the glazing at 0.42 (the EMU800); below 0.35 the
    /// rounding lets dark greys through (a locomotive's under-frame).
    static func isShade(_ colour: UInt32, of glass: UInt32) -> Bool {
        let c = channels(colour), g = channels(glass)
        let factor = (c.0 * g.0 + c.1 * g.1 + c.2 * g.2) / (g.0 * g.0 + g.1 * g.1 + g.2 * g.2)
        guard factor >= 0.35, factor <= 1.02 else { return false }
        return abs(c.0 - g.0 * factor) <= 1.2 && abs(c.1 - g.1 * factor) <= 1.2 && abs(c.2 - g.2 * factor) <= 1.2
    }

    /// Whether `colour` is a recipe's glass.
    /// Darker than this (luminance), a shade of glass is something else:
    /// the R200's louvres are its dark band at 0.4, nearly glass's hue;
    /// the darkest glass, ``Map3DTrainStyle/glass`` at 0.7, is 0.13.
    static let darkestGlass: Float = 0.11

    public static func isGlassColour(_ colour: UInt32) -> Bool {
        colour >> 24 == 0xFF && luminance(colour) >= darkestGlass && glassColours.contains { isShade(colour, of: $0) }
    }

    static func luminance(_ colour: UInt32) -> Float {
        let c = channels(colour)
        return (0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2) / 255
    }

    /// Whether `colour` is a stainless body's: light (luminance 0.55 or
    /// more) and neutral (its channels within 16 of each other).
    public static func isSteelColour(_ colour: UInt32) -> Bool {
        guard colour >> 24 == 0xFF else { return false }
        let c = channels(colour)
        return luminance(colour) >= 0.55 && max(c.0, c.1, c.2) - min(c.0, c.1, c.2) <= 16
    }

    static func channels(_ colour: UInt32) -> (Float, Float, Float) {
        (Float(colour & 0xFF), Float((colour >> 8) & 0xFF), Float((colour >> 16) & 0xFF))
    }

    /// Every model of `models` with its glass and stainless faces marked
    /// (``marked(_:)``); not a train's (``Map3DTrainOcclusion/isTrain(_:)``)
    /// as it was.
    static func marked(_ models: [Map3DModelPack.Model]) -> [Map3DModelPack.Model] {
        models.map(marked)
    }

    /// Model `model` with its glass and stainless faces marked, by
    /// triangle (a triangle is one colour, one face).
    public static func marked(_ model: Map3DModelPack.Model) -> Map3DModelPack.Model {
        guard Map3DTrainOcclusion.isTrain(model.name) else { return model }
        let stainless = isStainless(model.name)
        var vertices = model.vertices
        var changed = false
        for start in stride(from: 0, to: vertices.count - 2, by: 3) {
            let first = vertices[start]
            guard first.layer == Map3DVertex.plain || first.layer == Map3DVertex.glowing, first.nz >= lowestNormal else { continue }
            let layer: Float
            if isGlassColour(first.color) {
                layer = first.glows ? Map3DVertex.trainGlassLit : Map3DVertex.trainGlass
            } else if stainless, !first.glows, isSteelColour(first.color) {
                layer = Map3DVertex.trainSteel
            } else {
                continue
            }
            for k in 0..<3 { vertices[start + k].layer = layer }
            changed = true
        }
        return changed ? Map3DModelPack.Model(name: model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum) : model
    }
}
