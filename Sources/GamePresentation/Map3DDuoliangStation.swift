// Decision 1020: Duoliang Station (多良車站), the closed halt on the South
// Link Line between Longxi and Jinlun, where the line runs along the
// cliff over the sea: two platforms on their retaining walls with red
// railings all along, the small white station house with red pilasters
// and its roof terrace. Modelled by the local studio from photographs and
// OpenStreetMap's outlines (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/duoliang-station-2026-11/revision-1`;
// lessons in `docs/studio/lessons/duoliang-station.md`) and written here
// by `tools/landmarks/glb_to_swift.py --centre --raise 2.5` (its retaining
// walls reach 2.5 m under the rails). Not one of the game's stations (it
// is the attraction t142): a station landmark set on the line's rails
// (``Map3DStationLandmark/railHeight``), the line running between its two
// platforms (8.1 m to 9.8 m apart at their edges).
enum Map3DDuoliangStation {
    static let registration = Map3DLandmarkRegistration(
        id: "duoliang-station", map: "taiwan",
        // The model's footprint middle: the station house's middle
        // (OpenStreetMap way 427804286) moved 11.90 m west and 42.39 m
        // south, between the two platforms.
        latitude: 22.5071179, longitude: 120.9587750,
        // railRed (the palette's red nearest the railings' #B83230),
        // dark, wallWhite, eaveYellow, platform, platformEdge, stone,
        // glass (lit at night).
        palette: [Map3DPalette.templeRidge, Map3DPalette.dark, Map3DPalette.cityConcreteWalls[4], Map3DPalette.gold,
                  Map3DPalette.platform, Map3DPalette.platformEdge, Map3DPalette.cityConcreteWalls[3], Map3DPalette.glazing],
        glass: [7],
        encoded: encoded,
        // Its rails 2.5 m over its foot (the retaining walls' foot).
        station: Map3DStationLandmark(railHeight: 2.5),
        size: (48.99, 103.70, 8.55))
}
