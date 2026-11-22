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
    /// Decision 932: the dark brown boards of a timber station's walls, the
    /// second batch's Chiayi-style siding's colour
    /// (`Map3DStationExteriorBatch2`), given a name so Checheng's walls can
    /// use it (decision 891: a colour of the palette, not a new one).
    static let timberSiding = Map3DColor.rgb(0x4E392F)
}

/// Decision 932: Jingtong's station, the Pingxi Line's terminus, from the
/// local studio (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-stations-jingtong-checheng-2026-11/revision-2`,
/// #348; lessons in `docs/studio/lessons/tw-stations-jingtong-checheng.md`),
/// in place of the Alishan line's `timber` recipe: white boarded walls
/// under a dark grey tiled gable roof, a narrow brown awning along the
/// front with five white lozenge boards above it (blocks of colour, no
/// word on any), a lower open porch at one end, a lean-to gallery on white
/// posts on the platform side, a red brick plinth.
enum Map3DJingtongStation {
    /// The mesh's palette, in the order given to `glb_to_swift.py`:
    /// wallWhite, trim, roofTile, woodDark, brickBase, glazingDark, dark.
    static let meshPalette: [UInt32] = [
        Map3DPalette.tankWhite, Map3DPalette.tileWhite, Map3DPalette.arcade, Map3DPalette.cityRoofs[2].color,
        Map3DContainerWagon.rust, Map3DDepotFacilities.glass, Map3DPalette.dark,
    ]
}

/// Decision 932: Checheng's station, the Jiji Line's terminus, from the
/// same studio ticket: a long house of dark brown boards under a red-brown
/// tiled gable roof, a raised monitor roof with a louvred band along the
/// middle of its ridge, a grey sheet-roofed gallery on a row of dark posts
/// with braces on the platform side, a plain timber board under the eaves
/// (no word on it).
enum Map3DChechengStation {
    /// The mesh's palette, in the order given to `glb_to_swift.py`:
    /// timberWall, woodDark, roofTerracotta, metalRoof, concrete,
    /// timberBoard, glazingDark, dark.
    static let meshPalette: [UInt32] = [
        Map3DPalette.timberSiding, Map3DPalette.cityRoofs[2].color, Map3DPalette.cityRoofs[5].color, Map3DPalette.steel,
        Map3DPalette.concrete, Map3DPalette.timber, Map3DDepotFacilities.glass, Map3DPalette.dark,
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
    /// Decision 932.
    case jingtong = "station-tra_sched-b2e8d7d9"
    case checheng = "station-tra_sched-49f63912"

    /// How far behind the origin the platform side's clear line is.
    static let platformLine: Float = 6

    var name: String {
        switch self {
        case .pingxi: "station-pingxi"
        case .rinan: "station-rinan"
        case .jingtong: "station-jingtong"
        case .checheng: "station-checheng"
        }
    }

    var meshPalette: [UInt32] {
        switch self {
        case .pingxi: Map3DPingxiStation.meshPalette
        case .rinan: Map3DRinanStation.meshPalette
        case .jingtong: Map3DJingtongStation.meshPalette
        case .checheng: Map3DChechengStation.meshPalette
        }
    }

    /// The model, near or `far`; `nil` if its mesh does not decode.
    func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = name + (far ? "-far" : "")
        let text: String? = switch self {
        case .pingxi: Map3DPingxiStation.encoded[name]
        case .rinan: Map3DRinanStation.encoded[name]
        case .jingtong: Map3DJingtongStation.encoded[name]
        case .checheng: Map3DChechengStation.encoded[name]
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
