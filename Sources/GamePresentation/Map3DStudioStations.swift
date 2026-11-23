import Foundation
import GameCore

/// Decision 929: Pingxi's station, from the local studio
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-stations-pingxi-rinan-2026-11/revision-3`,
/// #304; lessons in `docs/studio/lessons/tw-stations-pingxi-rinan.md`),
/// in place of the kit's brick `heritage` building it shared with a
/// dozen others: the small stone house on its hillside, the timber deck
/// and stairs in front with their dark railings, the five boards on its
/// front as blocks of colour (no name or word on any). The real station
/// stands on a slope; the game's ground is flat, so the deck and stairs
/// stand on it at the heights the model has.
enum Map3DPingxiStation {
    /// The railings' wood: the frames' dark wood, a colour of the palette
    /// (decision 891).
    static let railWood = Map3DPalette.cityRoofs[2].color

    /// The mesh's palette, in the order given to `glb_to_swift.py`: stone,
    /// glazing, trim, concrete, roofDark, woodDark, dark, grille, deck,
    /// railWood (the model's colour table).
    static let meshPalette: [UInt32] = [
        Map3DPalette.stone, Map3DPalette.glazing, Map3DPalette.tileWhite, Map3DPalette.concrete,
        Map3DPalette.cityRoofs[1].color, Map3DPalette.cityRoofs[2].color, Map3DPalette.dark, Map3DPalette.arcade,
        Map3DPalette.counters[1], railWood,
    ]
}

/// Decision 929: Rinan's station, from the same studio ticket: the timber
/// station of the Coast Line under its tiled roof with the cross gable,
/// the gallery on posts round it, dark panes, braces of the kit's gold.
enum Map3DRinanStation {
    /// The mesh's palette, in the order given to `glb_to_swift.py`:
    /// wallCream, trim, plinth, dark, roofTile, woodDark, glazing, brace.
    /// Its panes are the dark ones (the photographs' are), not Pingxi's.
    static let meshPalette: [UInt32] = [
        Map3DPalette.hallWalls[4], Map3DPalette.tileWhite, Map3DPalette.bridge, Map3DPalette.dark,
        Map3DPalette.arcade, Map3DPalette.cityRoofs[2].color, Map3DDepotFacilities.glass, Map3DPalette.gold,
    ]
}

extension Map3DPalette {
    /// Decision 937: the grey-pink stone of the low house by Shifen's
    /// entrance, measured on the studio's photograph (in shade, so the
    /// stone itself may be lighter). The palette had no pink between its
    /// greys and its reds: the nearest, `arcade`, is a plain grey.
    static let stonePink = Map3DColor.rgb(0x786565)
}

/// Decision 937: Shanjia's station, from the local studio
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-stations-shanjia-shifen-2026-11/revision-2`;
/// lessons in `docs/studio/lessons/tw-stations-shanjia-shifen.md`), in
/// place of the kit's brick `heritage` building: the old ochre station
/// under its grey tiled roof with the timber porch in front, and behind
/// it, its back on the platform line, the new dark grey building with its
/// stepped eaves and the clock tower of green glass (no figures on the
/// clock, no word on any board).
enum Map3DShanjiaStation {
    /// The mesh's palette, in the order given to `glb_to_swift.py`:
    /// stoneBase, wallDark, roofDark, glazing, trim, glassGreen,
    /// wallOchre, roofTile, porchRoof, wood.
    static let meshPalette: [UInt32] = [
        Map3DPalette.stone, Map3DPalette.cityRoofs[1].color, Map3DPalette.dark, Map3DDepotFacilities.glass,
        Map3DPalette.tileWhite, Map3DPalette.gymGreen, Map3DPalette.plaza, Map3DPalette.steel,
        Map3DPalette.arcade, Map3DPalette.counters[1],
    ]
}

/// Decision 937: Shifen's station, from the same studio ticket: the long
/// light grey station with the red brick gateway at its entrance and the
/// low stone house beside it, a red-edged canopy on steel posts with
/// forked braces along the platform side, white boards along the roof
/// (blocks of colour, no word on any).
enum Map3DShifenStation {
    /// The mesh's palette, in the order given to `glb_to_swift.py`:
    /// concrete, wallLight, wallDark, glazing, trim, roofDark, canopyRed,
    /// steel, brick, wallPink.
    static let meshPalette: [UInt32] = [
        Map3DPalette.concrete, Map3DPalette.concreteWalls[2], Map3DPalette.cityRoofs[1].color, Map3DDepotFacilities.glass,
        Map3DPalette.tileWhite, Map3DPalette.dark, Map3DScene.Builder.barrierRed, Map3DPalette.steel,
        Map3DPalette.templeRidge, Map3DPalette.stonePink,
    ]
}

/// Decision 929: the real stations whose building is the studio's own
/// model of it, by the catalog's id. The models' own space is the generic
/// station's (decision 899): metres, +x along the platforms, +y towards
/// them, +z up, the ground at z 0, the origin in the middle of the main
/// body's plan, the platform side clear from y 6 on (but eaves).
enum Map3DStudioStation: String, CaseIterable, Sendable {
    case pingxi = "station-tra_sched-a5dcd0a9"
    case rinan = "station-tra_sched-333125bf"
    /// Decision 937.
    case shanjia = "station-tra_sched-6dd93a9d"
    case shifen = "station-tra_sched-683ebb50"

    /// How far behind the origin the platform side's clear line is.
    static let platformLine: Float = 6

    var name: String {
        switch self {
        case .pingxi: "station-pingxi"
        case .rinan: "station-rinan"
        case .shanjia: "station-shanjia"
        case .shifen: "station-shifen"
        }
    }

    var meshPalette: [UInt32] {
        switch self {
        case .pingxi: Map3DPingxiStation.meshPalette
        case .rinan: Map3DRinanStation.meshPalette
        case .shanjia: Map3DShanjiaStation.meshPalette
        case .shifen: Map3DShifenStation.meshPalette
        }
    }

    /// The model, near or `far`; `nil` if its mesh does not decode.
    func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = name + (far ? "-far" : "")
        let text: String? = switch self {
        case .pingxi: Map3DPingxiStation.encoded[name]
        case .rinan: Map3DRinanStation.encoded[name]
        case .shanjia: Map3DShanjiaStation.encoded[name]
        case .shifen: Map3DShifenStation.encoded[name]
        }
        guard let text, let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }
}

extension StationKitBuilder {
    /// Decision 929: `station`'s own model with its platform line at
    /// x `back`, towards −x, the kit's platform side, as
    /// ``genericStation(_:at:far:)`` lays the studio's.
    mutating func studioStation(_ station: Map3DStudioStation, back: Float = 7, far: Bool = false) {
        guard let model = station.model(far: far) else { return }
        add(model, at: Map3DPoint(back + Map3DStudioStation.platformLine, 0.25, 0), angle: -Float.pi / 2)
    }
}
