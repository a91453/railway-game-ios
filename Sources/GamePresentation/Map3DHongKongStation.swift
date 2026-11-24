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
    /// Hong Kong: the three main bodies (decision 933) and, since
    /// decision 967, the two wings and the front canopy an expansion adds
    /// (`hk-station-wings-2026-11/revision-1`). The stair head and the
    /// underground exit are Taiwan's still.
    static let models: [Map3DGenericStation.Model] = [.oneFloor, .twoFloor, .halt, .wing1, .wing2, .frontCanopy]

    /// `model` (one of ``models``), near or `far` (the near one when it
    /// has no far version), its cream walls (the brief's `wallCream`) in
    /// `walls`; `nil` for another model or if its mesh does not decode.
    static func model(_ model: Map3DGenericStation.Model, far: Bool = false,
                      walls: UInt32 = Map3DHongKong.civicWalls[1]) -> Map3DModelPack.Model? {
        guard models.contains(model) else { return nil }
        let name = "station-generic-hk-" + model.rawValue + (far && model.hasFar ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        var palette = meshPalette
        palette[1] = walls
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: palette)
    }

    /// Decision 967: the walls of a wing beside `body`: the body's own
    /// wall colour (the brief's §6), grey-green beside the one-floor one,
    /// pale grey beside the halt, cream beside the two-floor one.
    static func wingWalls(beside body: Map3DGenericStation.Model) -> UInt32 {
        switch body {
        case .oneFloor: Map3DHongKong.tenementWalls[8]
        case .halt: Map3DHongKong.civicWalls[3]
        default: Map3DHongKong.civicWalls[1]
        }
    }

    /// Whether a station of `profile` is drawn as the Hong Kong station
    /// there: a regional station or a halt, expanded or not (decision
    /// 967: an expanded one gets Hong Kong's wings and canopy).
    static func replaces(profile: Map3DStationKit.Profile) -> Bool {
        profile == .regional || profile == .halt
    }

    /// The model-space y of a body's platform-side wall (decision 933).
    static func backWall(_ body: Map3DGenericStation.Model) -> Float {
        body == .halt ? 3 : 6
    }

    /// Decision 967: the model-space y of the front canopy's back edge,
    /// the front edge of the body and its wings (the brief's §4): the
    /// body's covered walkway at y −9, the halt's wings' at y −10.
    static func canopyBack(_ body: Map3DGenericStation.Model) -> Float {
        body == .halt ? -10 : -9
    }
}

extension StationKitBuilder {
    /// Decision 933: Hong Kong's `model` where
    /// ``genericHouse(_:expansion:far:)`` lays Taiwan's: its
    /// platform-side wall at x `back`, towards −x, the kit's platform
    /// side. Decision 967: an `expansion` adds Hong Kong's wings at both
    /// ends (the first level's one-floor ones, the second's two-floor
    /// ones), their back walls with the body's, against the body's own
    /// outline at each end (the bodies are not symmetric); the second
    /// level also the front canopy in 12 m units in front of body and
    /// wings, near only, as Taiwan's.
    mutating func hongKongStation(_ model: Map3DGenericStation.Model, back: Float,
                                  expansion: StationExpansion? = nil, far: Bool = false) {
        guard let mesh = Map3DHongKongStation.model(model, far: far) else { return }
        let depth = model == .halt ? Map3DGenericStation.haltDepth : Map3DGenericStation.bodyDepth
        // The kit point of the model's origin: model (x, y) is kit
        // (origin − y, −x) (``genericStation(_:at:far:)``).
        let origin = back + depth / 2
        add(mesh, at: Map3DPoint(origin, 0.25, 0), angle: -Float.pi / 2)
        guard let expansion, let body = Map3DHongKongStation.model(model) else { return }
        let wingKind: Map3DGenericStation.Model = expansion == .hall ? .wing2 : .wing1
        let walls = Map3DHongKongStation.wingWalls(beside: model)
        guard let wing = Map3DHongKongStation.model(wingKind, far: far, walls: walls) else { return }
        // A wing is 10 m square about its origin, its back wall at its
        // y +5 on the body's.
        let wingX = origin - (Map3DHongKongStation.backWall(model) - 5)
        for end in [body.minimum.x - 5, body.maximum.x + 5] {
            add(wing, at: Map3DPoint(wingX, 0.25, -end), angle: -Float.pi / 2)
        }
        guard expansion == .hall, !far, let canopy = Map3DHongKongStation.model(.frontCanopy) else { return }
        // From the left wing's outer end to the right one's, centred; the
        // posts are inside each unit, so none is added at the end.
        let span = body.maximum.x - body.minimum.x + 20, middle = (body.minimum.x + body.maximum.x) / 2
        let units = max(1, Int(span / 12))
        let canopyX = origin - (Map3DHongKongStation.canopyBack(model) - 3.5)
        for unit in 0..<units {
            let x = middle + (Float(unit) - Float(units - 1) / 2) * 12
            add(canopy, at: Map3DPoint(canopyX, 0.25, -x), angle: -Float.pi / 2)
        }
    }
}
