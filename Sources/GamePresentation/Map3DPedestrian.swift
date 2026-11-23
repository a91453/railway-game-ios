import Foundation

/// Decision 918: five more people the streets, platforms and bus stops
/// show close up, beside decision 787's commuter
/// (``Map3DCommuterFigure``): an office worker with a briefcase, a student
/// with a school bag, an elder with a cloth bag, someone under an umbrella
/// and a traveller pulling a suitcase, each standing and mid-stride.
///
/// Made with Meshy (AI-generated, the owner's plan) and rebuilt for the
/// game by the local studio (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/pedestrians-2026-11/revision-4`, #257;
/// lessons in `docs/studio/lessons/pedestrians.md`), each a closed body of
/// at most 360 triangles; written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``): +x the way the
/// figure faces, +y its left, the middle of its feet at the origin.
///
/// Each figure close to the eye is one of the six, the same one every
/// frame (``kind(_:)``); farther, the block figure stands in as before.
public enum Map3DPedestrian {
    /// The five people.
    public enum Kind: String, CaseIterable, Sendable {
        case office, student, elderly, umbrella, traveller
    }

    /// `kind`'s model's name in ``Map3DModelPack``, standing or mid-stride:
    /// its GLB's file name.
    public static func name(_ kind: Kind, walking: Bool) -> String { "ped-\(kind.rawValue)-\(walking ? "walking" : "standing")" }

    /// The colour of each of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names skin, hair, shirt (alpha 0: the instance's colour, as the
    /// commuter's), trousers, dark (shoes, bags, the suitcase, a cap),
    /// white (the office worker's and the student's shirts), greyHair,
    /// bag (the elder's cloth bag) and umbrella. All the game's own.
    static let palette: [UInt32] = [
        Map3DStreetModel.skin, Map3DStreetModel.hair, Map3DColor.rgb(0xFFFFFF) & 0x00FF_FFFF, Map3DStreetModel.trousers, Map3DStreetModel.tyre,
        Map3DPalette.sidewalk, Map3DPalette.tankSteel, Map3DPalette.terrazzo, Map3DPalette.tankBlue,
    ]

    /// How often each stands among the close-up figures, out of 12; the
    /// rest (3) are the commuter. The umbrella and the suitcase are the
    /// rare ones: a street of umbrellas reads as rain.
    static let mix: [(kind: Kind, share: Int)] = [(.office, 3), (.student, 2), (.elderly, 2), (.traveller, 1), (.umbrella, 1)]

    /// Who a figure is close up, for its own `random` in 0..<1: one of
    /// the five, or `nil` for the commuter.
    static func kind(_ random: Float) -> Kind? {
        var left = Int(min(max(random, 0), 0.999_999) * 12)
        for entry in mix {
            if left < entry.share { return entry.kind }
            left -= entry.share
        }
        return nil
    }

    /// The ten models, for ``Map3DModelPack``: after the bicycles and
    /// before the route bus, which stays last.
    static var drawn: [Map3DModelPack.Model] {
        Kind.allCases.flatMap { kind in [false, true].compactMap { model(kind, walking: $0) } }
    }

    /// `kind`'s model; `nil` if its mesh does not decode.
    public static func model(_ kind: Kind, walking: Bool) -> Map3DModelPack.Model? {
        let name = name(kind, walking: walking)
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: palette)
    }
}
