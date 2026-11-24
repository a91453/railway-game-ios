import Foundation

/// Decision 957: the steam train's old wooden coach, the author's own
/// earlier model (SwiftRailMac's `item_3be063aafeecef486b52bc5b.glb`)
/// as the local studio carried it over in Blender: the author's mesh
/// kept, its texture taken off and its faces cut into the game's palette
/// colours, scaled by 0.85 (its end door 1.79 m), 12.12 m between its
/// coupler faces, 2.38 m wide and 3.40 m to the top of its ventilators,
/// on the 1,067 mm gauge: the navy body with twelve small windows a side
/// framed in white, the red-brown arched roof with its eaves and four
/// ventilators, an open platform with its railings at each end, two
/// bogies; the last coach with two red tail lamps on its back railings
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/tra-steam-coach-2026-11/revision-3`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
/// No lettering, plate or number is drawn.
public enum Map3DSteamCoach {
    /// The two coaches.
    public enum Unit: String, CaseIterable, Sendable {
        case middle = "steam-coach-middle"
        case tail = "steam-coach-tail"
    }

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names body, trim, roofBrown, glass, door, hardware, dark, taillamp.
    /// The steam train's coach livery (``TrainLivery/blueTrain``'s navy
    /// and white line, the colours its coaches had before), the city's
    /// red-brown roof tile for the roof and the end doors, the trains'
    /// glass, the urban line train's hardware and underframe greys
    /// (decision 786) and the tail lamp's red; no new colour.
    static let meshPalette: [UInt32] = [
        colour(TrainLivery.blueTrain.body), colour(TrainLivery.blueTrain.stripe), Map3DPalette.cityRoofs[5].color,
        Map3DTrainStyle.glass, Map3DPalette.cityRoofs[5].color, Map3DMTRUrbanLine.meshPalette[10],
        Map3DMTRUrbanLine.meshPalette[11], Map3DPalette.lantern,
    ]

    private static func colour(_ rgb: Int?) -> UInt32 { Map3DColor.rgb(UInt32(rgb ?? 0)) }

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors
    /// the sky in.
    static let glassIndex = 3

    /// The coach's length between its coupler faces, in metres: the
    /// model's, not the type catalogue's 8 m (decision 153), which only
    /// counts riders.
    public static let length: Float = 12.12

    /// `unit`'s coach, the tail's lamps at -x; `far`, the light version
    /// drawn from 500 m out. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit, far: Bool = false) -> Map3DModelPack.Model? {
        let name = unit.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DSteamCoach {
    /// Decision 957: the steam train's sets, near and far (the duplex
    /// locomotive and its tender have light versions since the decision's
    /// later note, ``Map3DDuplexSteam/model(_:far:)``), and their cars'
    /// triangles (the coaches 1,944 and 2,024 near, 566 and 614 far; the
    /// locomotive 8,000 to 10,500 near, decision 399, and 2,296 far; the
    /// tender 3,048 and 1,068) and lengths (the coaches 12.12 m, the locomotive and
    /// its tender 9 to 15.4 m). Its showcase row stays the hand-written one.
    static let registration = Map3DTrainRegistration(
        id: "steam-coach",
        sets: [Map3DTrainSet.steamTrain(), .steamTrain(far: true)],
        showcase: [],
        triangles: 560...10_500, length: 9...15.5)
}

extension Map3DTrainSet {
    /// Decision 957: the steam train (decision 399's duplex locomotive
    /// and its tender) hauling the studio's wooden coaches
    /// (``Map3DSteamCoach``) in place of the scene kit's modern coach.
    static func steamTrain(far: Bool = false) -> Map3DTrainSet {
        steam("STEAM", formation: .duplex, coach: steamCoach, far: far)
    }

    /// Decision 957: the steam train's coach. A coach that fails to
    /// decode draws as the scene kit's blue coach it had before.
    static let steamCoach: Coach = {
        var wooden = coach(TrainLivery.blueTrain, band: 0.38...0.43)
        wooden.steam = true
        return wooden
    }()
}
