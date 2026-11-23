import Foundation

/// Decision 918: the bicycles parked by some of the streets' bus stops: an
/// ordinary bicycle with a front basket, and Taiwan's public hire bicycle
/// (orange, a low step-through frame) in rows of three on Taiwan's maps.
///
/// Their shapes follow the owner's Meshy models (`meshy-batch-2026-10`'s
/// `bicycle` and `public-bike`, text-to-3D, so the data-source page says
/// they are generated), rebuilt for the game by the local studio
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/meshy-bicycles-2026-11/revision-1`, #256;
/// lessons in `docs/studio/lessons/meshy-bicycles.md`): tyres, tubes and
/// handlebars about twice as thick as real ones, so that a bicycle a few
/// pixels long still reads as two wheels. Written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``): +x its front wheel,
/// +y its left, standing upright on its two wheels' feet.
public enum Map3DBicycle {
    /// The models, by their names in ``Map3DModelPack``.
    public enum Unit: String, CaseIterable, Sendable {
        case bicycle
        case publicBike = "public-bike"
    }

    /// The colours, in the order `glb_to_swift.py --materials` gave them:
    /// the studio's material names frameBlue, frameOrange, tyre, hub,
    /// seat. All the game's own.
    static let palette: [UInt32] = [
        Map3DPalette.trimBlue, Map3DPalette.temu1000Orange, Map3DPalette.dark, Map3DPalette.mtrSilver, Map3DPalette.mtrCharcoal,
    ]

    /// The two models, for ``Map3DModelPack``: after Japan's street
    /// furniture and before the route bus, which stays last.
    static var drawn: [Map3DModelPack.Model] {
        Unit.allCases.compactMap { model($0) }.map(Map3DLook.restyle)
    }

    /// `unit`'s model; `nil` if its mesh does not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        guard let text = encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: unit.rawValue, palette: palette)
    }

    /// One parked bicycle by a bus stop: how far along the street from the
    /// stop's middle and how far in from the pavement's back its middle
    /// stands, metres, and whether it stands across the pavement (its
    /// front wheel toward the buildings) or along it.
    struct Parked: Equatable, Sendable {
        var unit: Unit
        var ahead: Double
        var fromBack: Double
        var across: Bool
    }

    /// Bicycles stand by this share of the bus stops.
    static let stopShare: Float = 0.35
    /// Of those on Taiwan's maps, this share are a row of public bicycles.
    static let publicShare: Float = 0.4
    /// A row's bicycles stand this far apart, metres (the studio's rack
    /// spacing: their 0.62 m handlebars clear each other by 8 cm).
    static let spacing = 0.7
    /// The pavement a row across it needs, metres: a bicycle's 1.8 m and
    /// room to walk past.
    static let rowPavement = 2.5
    /// The first bicycle stands this far on from the stop's middle,
    /// metres: clear of the shelter (its sign 2.75 m along) and of the
    /// vending machine (3.4 m).
    static let firstAhead = 5.2

    /// The bicycles by a stop whose pavement is `pavement` metres wide,
    /// for three random numbers in 0..<1 (whether any, which kind, how
    /// many); `publicBikes` where the map has Taiwan's public bicycles.
    /// On a wide pavement a row across it of two or three (public ones
    /// always three, as a dock's); on a narrow one a single bicycle along
    /// its back, and no public ones.
    static func parked(pavement: Double, publicBikes: Bool, random: (any: Float, kind: Float, count: Float)) -> [Parked] {
        guard random.any < stopShare, pavement >= 1.2 else { return [] }
        guard pavement >= rowPavement else {
            return [Parked(unit: .bicycle, ahead: firstAhead + 0.9, fromBack: 0.4, across: false)]
        }
        let isPublic = publicBikes && random.kind < publicShare
        let count = isPublic ? 3 : random.count < 0.5 ? 2 : 3
        return (0..<count).map { Parked(unit: isPublic ? .publicBike : .bicycle, ahead: firstAhead + Double($0) * spacing, fromBack: 1.0, across: true) }
    }
}
