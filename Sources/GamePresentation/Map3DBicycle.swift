import Foundation

/// Decision 918: the bicycles parked by some of the streets' bus stops
/// (decision 949: in the kits' racks, there and by the station exits): an
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

    /// Of those on Taiwan's maps, this share are a row of public bicycles.
    static let publicShare: Float = 0.4
    /// The pavement a rack across it needs, metres: a bicycle's 1.8 m and
    /// room to walk past.
    static let rowPavement = 2.5
    /// Decision 949: the rack's middle stands this far on from the stop's
    /// middle, metres, its first hoop 5.2 m on: clear of the shelter (its
    /// sign 2.75 m along) and of the vending machine (3.4 m).
    static let rackAhead = 6.2
    /// And this far in from the pavement's back, the bicycles' middles
    /// with it.
    static let rackFromBack = 1.0

    /// The bicycles by a stop whose pavement is `pavement` metres wide on
    /// `region`'s map, for three random numbers in 0..<1 (whether any,
    /// which kind, how many). Decision 949: in the rack
    /// (``Map3DBikeParking``) at ``rackAhead``, across the pavement
    /// (their front wheels to the buildings), two or three, public ones
    /// always three, as a dock's; none where the pavement is too narrow
    /// for the rack, nor past the region's ``Map3DStreetRegion/stopRackShare``.
    static func parked(pavement: Double, region: Map3DStreetRegion, random: (any: Float, kind: Float, count: Float)) -> [Parked] {
        guard random.any < region.stopRackShare, pavement >= rowPavement else { return [] }
        let load = Map3DBikeParking.rackLoad(publicBikes: region.hasPublicBicycles, publicShare: publicShare, kind: random.kind, count: random.count)
        return zip(Map3DBikeParking.inRack(load.count), load).map { offset, unit in
            Parked(unit: unit, ahead: rackAhead + offset, fromBack: rackFromBack, across: true)
        }
    }
}
