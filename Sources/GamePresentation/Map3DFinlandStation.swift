import Foundation
import GameCore

/// Decision 929: a small station in Finland
/// (``Map3DRegionLook/Buildings/nordic``, the Rovaniemi map) is the local
/// studio's Finnish country station (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/station-generic-finland-2026-11/revision-3`,
/// #302; lessons in `docs/studio/lessons/station-generic-finland.md`), not
/// Taiwan's flat-roofed one: yellow boards with dark seams, white corner
/// boards and window frames, a grey pitched roof whose slope runs on over
/// the porch, a brick chimney, a blue name board with no name on it.
/// Written in with `tools/train-models/glb_to_swift.py`
/// (``Map3DFinlandStationMesh``).
///
/// The model's own space is the generic station's (decision 899):
/// metres, +x along the platforms, +y towards them (the back), +z up,
/// the ground at z 0. Its platform-side wall stands at y 6, the line the
/// generic one-floor station's back wall stands on.
enum Map3DFinlandStation {
    /// The colours of the mesh's palette indices, in the order the
    /// studio's material names were given to `glb_to_swift.py`: plinth,
    /// wall, trim, roof, chimney, steel, steps, glass, door, signBlue
    /// (the model's colour table, each the game's own slot).
    static let meshPalette: [UInt32] = [
        Map3DPalette.steel, Map3DPalette.gold, Map3DPalette.tileWhite, Map3DPalette.arcade,
        Map3DPalette.redBrick, Map3DPalette.steel, Map3DPalette.steel, Map3DDepotFacilities.glass,
        Map3DPalette.cityRoofs[2].color, Map3DPalette.finnishSignBlue,
    ]

    /// How far the platform-side wall stands behind the model's origin.
    static let backWall: Float = 6

    /// The model, near or `far`; `nil` if its mesh does not decode.
    static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = "station-generic-finland" + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }

    /// Whether a station of `profile` with `expansion` is drawn as the
    /// Finnish country station in Finland: a regional station or a halt
    /// not yet expanded. An expanded station keeps the studio's building
    /// with its wings.
    static func replaces(profile: Map3DStationKit.Profile, expansion: StationExpansion?) -> Bool {
        (profile == .regional || profile == .halt) && expansion == nil
    }
}

extension StationKitBuilder {
    /// Decision 929: the Finnish station with its platform-side wall at
    /// x `back`, towards −x, the kit's platform side, as
    /// ``genericStation(_:at:far:)`` lays the studio's.
    mutating func finlandStation(back: Float, far: Bool = false) {
        guard let model = Map3DFinlandStation.model(far: far) else { return }
        add(model, at: Map3DPoint(back + Map3DFinlandStation.backWall, 0.25, 0), angle: -Float.pi / 2)
    }
}
