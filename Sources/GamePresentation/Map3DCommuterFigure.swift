import Foundation

/// Decision 787: the commuter the streets, platforms and bus stops show
/// close up, in place of decision 259's block figure: a standing commuter
/// with a backpack, made with Meshy (AI-generated, the owner's plan) and
/// cut down in Blender to a closed body of 288 triangles (the assets repository's
/// `commuter-figure-2026-11/revision-1`), its colours mended and its
/// walking stride made by `tools/commuter-figure/to_swift.py`
/// (``encodedStanding``, ``encodedWalking``), and passed by the local
/// studio's review against photographs (round 2).
///
/// It is drawn within ``detailReach`` of the eye, for at most
/// ``mostCloseUp(of:)`` of a frame's people, the nearest first; farther
/// and beyond that the block figure stands in, as decision 446's scooters
/// do, so a crowd's triangles stay near the budget's
/// (``Map3DMotionBudget/personTriangles``).
public enum Map3DCommuterFigure {
    /// The two close-up models, standing and mid-stride.
    public static let models: [Map3DStreetModel] = [.commuterStanding, .commuterWalking]

    /// How far from the eye a figure is drawn as the commuter, metres:
    /// farther, at the size a phone shows it, the block reads the same.
    public static let detailReach: Float = 120

    /// The most of a frame's `people` drawn as the commuter: a quarter of
    /// them, at most 150 (about 31,000 triangles more than as many
    /// blocks).
    public static func mostCloseUp(of people: Int) -> Int { min(150, people / 4) }

    /// The colour of each of the mesh's palette indices: skin, hair, the
    /// shirt (alpha 0: the instance's colour, as the block figure's
    /// body), the trousers, and the shoes and backpack, the block
    /// figure's own colours.
    static let palette: [UInt32] = [
        Map3DStreetModel.skin, Map3DStreetModel.hair, Map3DColor.rgb(0xFFFFFF) & 0x00FF_FFFF, Map3DStreetModel.trousers, Map3DStreetModel.tyre,
    ]

    /// `model`'s mesh, named as it; `nil` if it does not decode.
    static func model(_ model: Map3DStreetModel) -> Map3DModelPack.Model? {
        let text = model == .commuterWalking ? encodedWalking : encodedStanding
        guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: model.modelName, palette: palette)
    }

    /// The pack's close-up models, after Hong Kong's vehicles and before
    /// the route bus.
    static var drawn: [Map3DModelPack.Model] { models.map { $0.model() } }
}
