// Decision 928: the front and rear halls of Sun Moon Lake's Wenwu Temple
// (文武廟), either side of the middle hall the map already builds
// (``Map3DSunMoonLandmarks``, `wenwu-temple`). Modelled by the local
// studio (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/tw-landmark-wenwu-halls-2026-11/revision-3`,
// #312; lessons in `docs/studio/lessons/tw-wenwu-halls.md`), already
// turned as the temple stands, and written here by
// `tools/landmarks/glb_to_swift.py --raise 2` (``encoded``): each hall's
// stone base reaches 2 m below its floor down the hillside, so each is
// sunk that far and its floor stands on the ground at its middle.

/// The front hall (the gate hall toward the lake), from photographs.
enum Map3DWenwuFrontHall {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-wenwu-front-hall", map: "taiwan",
        // OpenStreetMap's outline's middle (way 799608744).
        latitude: 23.8698184, longitude: 120.9274299,
        sink: 2,
        palette: Map3DWenwuRearHall.palette,
        encoded: encoded,
        size: (37.72, 48.40, 20.20))
}

/// The rear hall (Dacheng Hall, up the hill). The studio had no photograph
/// of it: its shape follows the front hall's and OpenStreetMap's outline
/// (not verified).
enum Map3DWenwuRearHall {
    /// stone, timber, templeRoof, templeWall, gold, terrazzo, bracketBand.
    static let palette: [UInt32] = [Map3DPalette.stone, Map3DPalette.timber, Map3DPalette.templeRoof, Map3DPalette.templeWall,
                                    Map3DPalette.gold, Map3DPalette.terrazzo, Map3DPalette.bracketGreen]

    static let registration = Map3DLandmarkRegistration(
        id: "tw-wenwu-rear-hall", map: "taiwan",
        // OpenStreetMap's outline's middle (way 799608746).
        latitude: 23.8700890, longitude: 120.9278931,
        sink: 2,
        palette: palette,
        encoded: encoded,
        size: (39.85, 49.90, 18.55))
}

extension Map3DPalette {
    /// Decision 928: the dark green of a temple's painted bracket band
    /// under its eaves: the green the N700S already wrote for itself, now
    /// the palette's.
    static let bracketGreen = Map3DColor.rgb(0x1D4A44)
}
