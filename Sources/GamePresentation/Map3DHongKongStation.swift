import Foundation
import GameCore

/// Decision 933: a small station in Hong Kong
/// (``Map3DRegionLook/Buildings/hongKong``) is the local studio's
/// new-town station of the East Rail line (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/station-generic-hk-2026-11/revision-2`;
/// lessons in `docs/studio/lessons/station-generic-hk.md`), not Taiwan's
/// white-tiled one: pale painted concrete under a flat roof, a thick
/// eaves board, bands of windows, a covered walkway along the front and
/// the head of a covered footbridge towards the platforms. The one-floor
/// one is grey-green with a sloped eaves board (Fanling), the two-floor
/// one cream below and brick-red panels above (Sheung Shui and Fo Tan),
/// the halt a grey box under a silver barrel-roofed bridge head with a
/// green belt (Tai Wo). No name, letter or mark on any of them. Written
/// in with `tools/train-models/glb_to_swift.py`
/// (``Map3DHongKongStationMesh``).
///
/// The models' own space is the generic station's (decision 899):
/// metres, +x along the platforms, +y towards them (the back), +z up,
/// the ground at z 0, the origin in the middle of the main body's plan.
/// The platform-side wall stands at y 6 (the halt's at y 3), the line
/// the generic station's back wall stands on; the footbridge head's
/// dark opening (2.4 m wide, 2.5 m high, its floor at z 6.5) is in that
/// wall.
enum Map3DHongKongStation {
    /// The colours of the mesh's palette indices, in the order the
    /// studio's material names were given to `glb_to_swift.py` (the
    /// brief's §5, each the game's own slot): wallGreen, wallCream,
    /// wallGrey, cladding, trim, concrete, glass, dark, steel,
    /// roofSilver, bandGreen, bridgeGlass, bridgeWhite.
    static let meshPalette: [UInt32] = [
        Map3DHongKong.tenementWalls[8], Map3DHongKong.civicWalls[1], Map3DHongKong.civicWalls[3],
        Map3DPalette.brick, Map3DPalette.tileWhite, Map3DPalette.concrete, Map3DDepotFacilities.glass,
        Map3DPalette.dark, Map3DPalette.steel, Map3DPalette.mtrRoofSilver, Map3DPalette.gymGreen,
        Map3DPalette.glazing, Map3DPalette.tankSteel,
    ]

    /// Which of the generic station's buildings the studio made for
    /// Hong Kong: the three main bodies. The wings, the front canopy and
    /// the stairs are Taiwan's still.
    static let models: [Map3DGenericStation.Model] = [.oneFloor, .twoFloor, .halt]

    /// `model` (one of ``models``), near or `far`; `nil` for another
    /// model or if its mesh does not decode.
    static func model(_ model: Map3DGenericStation.Model, far: Bool = false) -> Map3DModelPack.Model? {
        guard models.contains(model) else { return nil }
        let name = "station-generic-hk-" + model.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }

    /// Whether a station of `profile` with `expansion` is drawn as the
    /// Hong Kong station there: a regional station or a halt not yet
    /// expanded. An expanded station keeps the studio's Taiwanese
    /// building with its wings (there are no Hong Kong wings yet).
    static func replaces(profile: Map3DStationKit.Profile, expansion: StationExpansion?) -> Bool {
        (profile == .regional || profile == .halt) && expansion == nil
    }
}

extension StationKitBuilder {
    /// Decision 933: Hong Kong's `model` where
    /// ``genericHouse(_:expansion:far:)`` lays Taiwan's: its
    /// platform-side wall at x `back`, towards −x, the kit's platform
    /// side.
    mutating func hongKongStation(_ model: Map3DGenericStation.Model, back: Float, far: Bool = false) {
        guard let mesh = Map3DHongKongStation.model(model, far: far) else { return }
        let depth = model == .halt ? Map3DGenericStation.haltDepth : Map3DGenericStation.bodyDepth
        add(mesh, at: Map3DPoint(back + depth / 2, 0.25, 0), angle: -Float.pi / 2)
    }
}
