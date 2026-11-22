import Foundation

/// Decision 923: Japan's utility poles, pedestrian signals and bus stop on
/// Fukuoka's map, beside its traffic signals (``Map3DJapanSignal``,
/// decision 921), in place of Taiwan's pole (``Map3DProp/pole``), the
/// pedestrian faces with no countdown and Taiwan's bus shelter that stood
/// there with no models of their own.
///
/// - The utility poles are the owner's own models from the earlier
///   version (its list's 「電柱」, 401–405), written here by
///   `tools/fukuoka-map/japan_pole.py` (``poleEncoded``) in the game's
///   colours: a concrete pole about 10 m tall with two galvanised
///   crossarms and white insulators; one with a transformer; one with two
///   transformers on a frame and their cut-outs; a bare one with its step
///   bolts; and a shorter one with a street light on a short arm, lit
///   after dark. The crossarms, the cut-outs and the light reach toward
///   the model's left (the road, as ``Map3DProp/lamp``'s).
/// - The pedestrian signals were modelled by the local studio from
///   photographs (`a91453/railway-assets-private-2`
///   `game-art-previews/docs/art/jp-street-signals-2026-11/revision-2`,
///   whose head is dark as Japan's are; the first round's was pale)
///   and written here by `tools/train-models/glb_to_swift.py`
///   (``encoded``): a slim post 2.95 m tall and a dark head of two
///   squares, the red figure standing over the green one walking, each
///   under its hood, no countdown. Its face looks toward its left (as
///   ``Map3DPedestrianSignal``'s), as the studio drew it.
/// - The bus stop, the local studio's too
///   (`game-art-previews/docs/art/jp-bus-stop-2026-11/revision-1`, the
///   same tool): a concrete foot, a slim post and an upright sign rounded
///   at its top, white with a red route block over a pale timetable panel,
///   its faces along the road and its edge toward the model's left (the
///   road), as Fukuoka's stops stand; no shelter.
///
/// No word, number or mark is drawn.
public enum Map3DJapanStreet {
    /// The models, by their names in ``Map3DModelPack``.
    public enum Unit: String, CaseIterable, Sendable {
        case pole = "jp-pole"
        case poleTransformer = "jp-pole-transformer"
        case poleTransformers = "jp-pole-transformers"
        case polePlain = "jp-pole-plain"
        case poleLamp = "jp-pole-lamp"
        case walkStop = "jp-walk-stop"
        case walkDark = "jp-walk-dark"
        case walkWalk = "jp-walk-walk"
        case busStop = "jp-bus-stop"

        /// A pedestrian signal's face.
        var isWalk: Bool { self == .walkStop || self == .walkDark || self == .walkWalk }

        /// One the studio made (``encoded``), not the earlier version's
        /// (``poleEncoded``).
        var isStudios: Bool { isWalk || self == .busStop }
    }

    /// The utility poles' colours, in `japan_pole.py`'s order: concrete,
    /// steel, insulator, tankSteel, lamp_lit. All the game's own: Taiwan's
    /// pole's concrete (``Map3DPalette/concrete``), the galvanised grey
    /// (``Map3DPalette/steel``), the insulators' white
    /// (``Map3DPalette/tileWhite``), the pale grey of the light's shade
    /// (``Map3DPalette/tankSteel``) and the street lights' warm white
    /// (``Map3DProp/lampLight``).
    static let polePalette: [UInt32] = [
        Map3DPalette.concrete, Map3DPalette.steel, Map3DPalette.tileWhite, Map3DPalette.tankSteel, Map3DProp.lampLight,
    ]

    /// The studio's models' colours, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names steel, tankSteel, dark, red_lit, red_unlit, green_lit,
    /// green_unlit, signWhite, signRed, concrete. The galvanised and pale
    /// greys (the pale one is the bus stop's alone since the pedestrian
    /// signals' second round, and keeps its place so the later ones keep
    /// theirs), the signals' housing for the heads and the faces
    /// (``Map3DProp/signalHousing``) and the signals' red and green
    /// (``Map3DProp/signalLights``), as Finland's (decision 846); the bus
    /// stop's sign white (``Map3DPalette/sidewalk``), route red
    /// (``Map3DScene/Builder/barrierRed``) and concrete foot.
    static let studioPalette: [UInt32] = [
        Map3DPalette.steel, Map3DPalette.tankSteel, Map3DProp.signalHousing,
        Map3DProp.signalLights[0].lit, Map3DProp.signalLights[0].unlit,
        Map3DProp.signalLights[2].lit, Map3DProp.signalLights[2].unlit,
        Map3DPalette.sidewalk, Map3DScene.Builder.barrierRed, Map3DPalette.concrete,
    ]

    /// The colours that glow: the light's lens, a lit figure.
    static let lit: Set<UInt32> = [Map3DProp.lampLight, Map3DProp.signalLights[0].lit, Map3DProp.signalLights[2].lit]

    /// How far toward its left the light of ``Unit/poleLamp`` is from its
    /// foot, metres: where the pool of its light lies.
    static let lampReach: Float = 0.6

    /// The utility poles along a minor road, and how often each stands
    /// (out of 20): mostly the crossarms and a transformer, a light every
    /// fourth or fifth pole.
    static let poleMix: [(unit: Unit, share: Int)] = [
        (.pole, 6), (.poleTransformer, 4), (.poleTransformers, 3), (.polePlain, 2), (.poleLamp, 5),
    ]

    /// The pole for `random` in 0..<1 (``poleMix``).
    static func pole(_ random: Float) -> Unit {
        let total = poleMix.reduce(0) { $0 + $1.share }
        var left = Int(random * Float(total))
        for entry in poleMix {
            if left < entry.share { return entry.unit }
            left -= entry.share
        }
        return poleMix[poleMix.count - 1].unit
    }

    /// The nine models, for ``Map3DModelPack``: after Japan's traffic
    /// signals and before the route bus, which stays last.
    static var drawn: [Map3DModelPack.Model] {
        Unit.allCases.compactMap { model($0) }.map(Map3DLook.restyle)
    }

    /// `unit`'s model; `nil` if its mesh does not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        let name = unit.rawValue
        guard let text = unit.isStudios ? encoded[name] : poleEncoded[name],
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: unit.isStudios ? studioPalette : polePalette)
        else { return nil }
        let vertices = model.vertices.map { vertex -> Map3DVertex in
            var vertex = vertex
            if lit.contains(vertex.color) { vertex.layer = Map3DVertex.glowing }
            return vertex
        }
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }
}
