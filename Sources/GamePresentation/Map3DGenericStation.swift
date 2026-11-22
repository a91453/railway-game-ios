import Foundation
import GameCore

/// Decision 899: the station the player builds, and every small station
/// with no model of its own (``Map3DStationKit/Profile/regional`` and
/// ``Map3DStationKit/Profile/halt``), from the local studio's models
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/player-station-basic-2026-11/revision-2`,
/// #182, and `player-station-generic-2026-11/extras/revision-2`, #186;
/// lessons in `docs/studio/lessons/player-station-basic.md` and
/// `player-station-generic.md`), written in with
/// `tools/train-models/glb_to_swift.py` (``Map3DGenericStationMesh``): a
/// flat-roofed one-floor station with a green canopy, a two-floor one
/// with a blue band, a halt with its rounded shelter, the wings and front
/// canopy an expansion adds, a viaduct's stair head and an underground
/// exit. No name, letter or mark on any of them: the name boards are
/// blocks of colour.
///
/// The models' own space: metres, +x along the platforms, +y towards
/// them (the back), +z up, the ground at z 0, the origin in the middle of
/// the main body's plan (a wing's, the canopy unit's, a stair's).
enum Map3DGenericStation {
    enum Model: String, CaseIterable, Sendable {
        case oneFloor = "1f", twoFloor = "2f", halt
        case wing1 = "wing-1", wing2 = "wing-2", frontCanopy = "front-canopy"
        case stairHead = "stair-head", undergroundExit = "underground-exit"

        /// Whether the studio made a far version.
        var hasFar: Bool {
            switch self {
            case .oneFloor, .twoFloor, .halt, .wing1, .wing2: true
            case .frontCanopy, .stairHead, .undergroundExit: false
            }
        }
    }

    /// The colours of the mesh's palette indices, in the order the
    /// studio's material names were given to `glb_to_swift.py` (the
    /// brief's §5, each the game's own): tileWhite, wallCream, concrete,
    /// stone, glass, glassBright, dark, grille, steel, canopyGreen,
    /// signBlue.
    static let meshPalette: [UInt32] = [
        Map3DPalette.tileWhite, Map3DPalette.schoolWalls, Map3DPalette.concrete, Map3DPalette.stone,
        Map3DDepotFacilities.glass, Map3DPalette.cityOfficeWalls[4], Map3DPalette.dark, Map3DPalette.arcade,
        Map3DPalette.steel, Map3DPalette.gymGreen, Map3DPalette.canopy,
    ]

    /// The main body's depth (the brief's §3): a station's back is half
    /// of it behind the origin.
    static let bodyDepth: Float = 12
    static let haltDepth: Float = 6

    /// `model` in its own space, near or `far` (the near one when it has
    /// no far version); `nil` if its mesh does not decode.
    static func model(_ model: Model, far: Bool = false) -> Map3DModelPack.Model? {
        let name = "station-generic-" + model.rawValue + (far && model.hasFar ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette)
    }

    /// The building for a station of `profile` (regional or halt) and
    /// `tier` (1 the busiest): the two-floor one for the busier regional
    /// stations, the one-floor one for the rest, the halt's own.
    static func building(profile: Map3DStationKit.Profile, tier: Int) -> Model {
        profile == .halt ? .halt : tier <= 2 ? .twoFloor : .oneFloor
    }
}

extension StationKitBuilder {
    /// Decision 899: a model of the studio's generic station with its
    /// back (+y) towards −x, the kit's platform side, and its middle at
    /// `at`: the model's −y is the kit's +x, its +x the kit's −z.
    mutating func genericStation(_ model: Map3DGenericStation.Model, at: Map3DPoint, far: Bool = false) {
        guard let mesh = Map3DGenericStation.model(model, far: far) else { return }
        add(mesh, at: at, angle: -Float.pi / 2)
    }

    /// Decision 899: a regional station's or a halt's building from the
    /// studio's models, its back at x 7 (as the boxes before it), and an
    /// expanded one's wings either side and its front canopy.
    mutating func genericHouse(_ station: Map3DStationKit.Station, expansion: StationExpansion?, far: Bool = false) {
        // Decision 922: in Japan, the earlier version's wooden station.
        if japanese, Map3DJapanStation.replaces(profile: station.profile, expansion: expansion) {
            japanStation(back: 7, far: far)
            return
        }
        let model = Map3DGenericStation.building(profile: station.profile, tier: station.tier)
        let depth = model == .halt ? Map3DGenericStation.haltDepth : Map3DGenericStation.bodyDepth
        let back: Float = 7, x = back + depth / 2
        genericStation(model, at: Map3DPoint(x, 0.25, 0), far: far)
        guard let expansion, let body = Map3DGenericStation.model(model) else { return }
        // The body's length along the platforms (the model's x).
        let length = body.maximum.x - body.minimum.x
        let wing: Map3DGenericStation.Model = expansion == .hall ? .wing2 : .wing1
        // A wing is 10 m square, its back with the building's back.
        for sign: Float in [-1, 1] {
            genericStation(wing, at: Map3DPoint(back + 5, 0.25, sign * (length / 2 + 5)), far: far)
        }
        guard expansion == .hall, !far else { return }
        // The front canopy in 12 m units along the whole front, wings
        // and all, its back against the body's front.
        let span = length + 20, units = max(1, Int(span / 12))
        let first = -Float(units - 1) * 6
        for unit in 0..<units {
            genericStation(.frontCanopy, at: Map3DPoint(back + depth + 3.5, 0.25, first + Float(unit) * 12))
        }
        // The last unit's far post (each unit has only its −x one).
        let end = first + Float(units - 1) * 12 + 6
        box(back + depth + 6.8, 0.25, -end, 0.2, 0.2, 6.2, Map3DPalette.steel)
    }
}
