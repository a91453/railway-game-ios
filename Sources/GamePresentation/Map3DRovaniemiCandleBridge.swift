/// Decision 907: the Lumberjack's Candle (Jätkänkynttilä), Rovaniemi's
/// cable-stayed road bridge over the Kemijoki: one pylon of two square
/// columns a third of the way along, a fan of stays each side and a lamp
/// on each column's top. Modelled by the local studio from photographs
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/rovaniemi-landmarks-2026-11/revision-4`,
/// #226; lessons in `docs/studio/lessons/rovaniemi-landmarks.md`), turned
/// 155.5° as OpenStreetMap's outline (way `man_made=bridge`), the pylon
/// toward the town's (north-west) bank, and written here by
/// `tools/landmarks/glb_to_swift.py` (``encoded``). Its z 0 is the river's
/// surface.
enum Map3DRovaniemiCandleBridge {
    static let registration = Map3DLandmarkRegistration(
        id: "rovaniemi-candle-bridge", map: "rovaniemi",
        // The middle of OpenStreetMap's outline.
        latitude: 66.5029052, longitude: 25.7422479,
        // steel (deck girders and stays), roadGrey (the road), dark (the
        // railings), concrete (pylon and piers), beacon_lit (the lamps).
        palette: [Map3DPalette.steel, Map3DPalette.arcade, Map3DPalette.dark, Map3DPalette.concrete, CableParts.Paint.warm],
        encoded: encoded,
        // 320 m by 25.5 m turned 155.5°, the pylon 54.5 m over the river.
        size: (301.76, 155.9, 54.5))
}
