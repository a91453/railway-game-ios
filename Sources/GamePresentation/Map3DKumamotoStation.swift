// Decision 1020: Kumamoto Station (熊本駅), the Kyushu Shinkansen's
// terminus on the Fukuoka map's south end: the long grey station over its
// platforms with its slanting ribbed walls and dark eaves, the white
// canopy over the Shirakawa exit's square, and the station tower south of
// it, dark-framed glass under a white box. Modelled by the local studio
// from photographs and OpenStreetMap's outlines
// (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/kumamoto-station-2026-11/revision-2`;
// lessons in `docs/studio/lessons/kumamoto-station.md`) and written here
// by `tools/landmarks/glb_to_swift.py --centre` (``encoded``). The station
// is a station landmark (``Map3DStationLandmark``): the Shinkansen's
// viaduct and platforms run through the room the model leaves for the
// real platforms (rails 10 m up, its roof 16.5 m up).

/// The station over its platforms and the Shirakawa exit's canopy.
enum Map3DKumamotoStation {
    static let registration = Map3DLandmarkRegistration(
        id: "kumamoto-station", map: "fukuoka",
        // The model's footprint middle: the middle of OpenStreetMap's
        // part of the station (way 489068318) moved 27.77 m east and
        // 52.01 m south.
        latitude: 32.7899893, longitude: 130.6889398,
        // ribWall, roofSlate, wallPale, bandDark, glassBlueGrey (lit at
        // night).
        palette: [Map3DPalette.arcade, Map3DPalette.cityRoofs[1].color, Map3DPalette.cityConcreteWalls[4],
                  Map3DPalette.dark, Map3DPalette.cityOfficeWalls[5]],
        glass: [4],
        encoded: encoded,
        station: Map3DStationLandmark(),
        // The four real platforms' outlines with 10 m at either end, and
        // the canopy to the east.
        size: (298.92, 302.04, 25.0))
}

/// The station tower (12 floors, 59.4 m) south of the station.
enum Map3DKumamotoStationTower {
    static let registration = Map3DLandmarkRegistration(
        id: "kumamoto-station-tower", map: "fukuoka",
        // OpenStreetMap's outline (way 922794562), its middle 9.69 m west
        // and 183.03 m south of the station's.
        latitude: 32.7888079, longitude: 130.6885399,
        // bandDark, roofSlate, wallPale, glassBlueGrey (lit at night),
        // woodBand, hotelWhite.
        palette: [Map3DPalette.dark, Map3DPalette.cityRoofs[1].color, Map3DPalette.cityConcreteWalls[4],
                  Map3DPalette.cityOfficeWalls[5], Map3DPalette.timber, Map3DPalette.tileWhite],
        glass: [3],
        encoded: encoded,
        size: (118.70, 151.49, 59.40))
}
