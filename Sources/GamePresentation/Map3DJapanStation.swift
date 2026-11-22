import Foundation
import GameCore

/// Decision 922: a small station in Japan (decision 802's ``Map3DRegionLook/Buildings/japan``)
/// is the owner's own wooden station from the earlier version
/// (SwiftRailMac `item_98459549367e2d2e4456f07d`, its list's
/// 「田舎駅（木造駅舎）」), not Taiwan's studio station: boards under a
/// grey tiled roof, a long canopy on posts over the platform side, a
/// porch over the door, plaster panels over the windows.
///
/// The earlier version painted its windows and panels on a texture; the
/// game draws none, so `tools/old-models/bake_texture.py` cut each wall
/// into faces of the game's colours where the texture showed them
/// (``Map3DJapanStationMesh``), at half the old size (it drew its
/// buildings larger than life). The far version is the same shape, each
/// face the colour most of it was.
///
/// The model's own space is the generic station's (decision 899):
/// metres, +x along the platforms, +y towards them (the back), +z up,
/// the ground at z 0.
enum Map3DJapanStation {
    /// The colours of the mesh's palette indices, in the order
    /// `bake_texture.py` gave them: timber, plaster, glass, roof,
    /// concrete, stone. Each is a slot the game's own stations use for the
    /// same part (the studio's Rinan station: its boards, white plaster,
    /// panes and tiled roof).
    static let meshPalette: [UInt32] = [
        Map3DPalette.timber, Map3DPalette.tileWhite, Map3DPalette.glazing, Map3DPalette.arcade,
        Map3DPalette.concrete, Map3DPalette.stone,
    ]

    /// The model, near or `far`; `nil` if its mesh does not decode.
    static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = "japan-wooden-station" + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }

    /// Whether a station of `profile` with `expansion` is drawn as the
    /// wooden station in Japan: a regional station not yet expanded. A
    /// halt keeps its shelter, and an expanded station the studio's
    /// building with its wings.
    static func replaces(profile: Map3DStationKit.Profile, expansion: StationExpansion?) -> Bool {
        profile == .regional && expansion == nil
    }
}

extension StationKitBuilder {
    /// Decision 922: the wooden station with its back (+y, the canopy's
    /// edge) at x `back`, towards −x, the kit's platform side, as
    /// ``genericStation(_:at:far:)`` lays the studio's.
    mutating func japanStation(back: Float, far: Bool = false) {
        guard let model = Map3DJapanStation.model(far: far) else { return }
        add(model, at: Map3DPoint(back + model.maximum.y, 0.25, 0), angle: -Float.pi / 2)
    }
}
