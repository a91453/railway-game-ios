// Decision 1018: three of Hong Kong's best-known temples on the Hong Kong
// map: Wong Tai Sin Temple (黃大仙祠) with its entrance arch, Chi Lin
// Nunnery (志蓮淨苑) and Che Kung Temple (車公廟) at Tai Wai. Modelled by
// the local studio from photographs (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/hk-temples-2026-11/revision-2`; lessons in
// `docs/studio/lessons/hk-temples.md`) with their fronts to the south, and
// written here by `tools/landmarks/glb_to_swift.py --centre --turn`
// (``encoded``), each turned to face the way OpenStreetMap's outlines
// show its entrance. Each model's middle is set from its main hall's
// OpenStreetMap outline and where that hall stands in the model.

extension Map3DPalette {
    /// Decision 1018: the green-glazed eave bands and tiles of Wong Tai
    /// Sin's and Che Kung's halls (the studio's `teal`, the cable cars'),
    /// and Chi Lin Nunnery's cream outer wall (`cream`, the Alishan
    /// coaches' band).
    static let templeTeal = Map3DColor.rgb(0x12A08F)
    static let wallCream = Map3DColor.rgb(0xE9E1CF)
}

/// Wong Tai Sin Temple's main hall and its courtyard, turned 19°
/// anticlockwise to face south-south-east as the hall does.
enum Map3DWongTaiSin {
    /// granite, stone, tileWhite, lantern, dark, teal, templeRidge,
    /// templeRoof.
    static let palette: [UInt32] = [Map3DPalette.granite, Map3DPalette.stone, Map3DPalette.tileWhite, Map3DPalette.lantern,
                                    Map3DPalette.dark, Map3DPalette.templeTeal, Map3DPalette.templeRidge, Map3DPalette.templeRoof]

    static let registration = Map3DLandmarkRegistration(
        id: "hk-wong-tai-sin", map: "hongkong",
        // 15 m south-south-east of the main hall's outline middle (OSM way
        // 264463013, 28.6 m by 20.8 m; the model's hall 30 m by 20 m stands
        // 15 m behind its middle).
        latitude: 22.3427105, longitude: 114.1933774,
        palette: palette,
        encoded: encoded,
        size: (57.38, 66.92, 16.00))
}

/// The arch at Wong Tai Sin Temple's entrance.
enum Map3DWongTaiSinGate {
    /// stone, lantern, teal, dark, templeRidge, templeRoof.
    static let palette: [UInt32] = [Map3DPalette.stone, Map3DPalette.lantern, Map3DPalette.templeTeal, Map3DPalette.dark,
                                    Map3DPalette.templeRidge, Map3DPalette.templeRoof]

    static let registration = Map3DLandmarkRegistration(
        id: "hk-wong-tai-sin-gate", map: "hongkong",
        // OSM way 264462878 (the arch, 13.3 m wide, facing south).
        latitude: 22.3419123, longitude: 114.1935320,
        palette: palette,
        encoded: encoded,
        size: (13.48, 4.86, 9.80))
}

/// Chi Lin Nunnery's halls round their courtyard, turned 29° clockwise
/// along the line from the Hall of Deva Kings to the Main Hall.
enum Map3DChiLinNunnery {
    /// granite, dark, cream, timberSiding, slate, stone, water.
    static let palette: [UInt32] = [Map3DPalette.granite, Map3DPalette.dark, Map3DPalette.wallCream, Map3DPalette.timberSiding,
                                    Map3DPalette.roofSlate, Map3DPalette.stone, Map3DPalette.water]

    static let registration = Map3DLandmarkRegistration(
        id: "hk-chi-lin-nunnery", map: "hongkong",
        // The model's Hall of Deva Kings and Main Hall on OpenStreetMap's
        // (ways 109743694 and 109743732, 45.6 m apart along a bearing of
        // 29°; the model's 47 m).
        latitude: 22.3405259, longitude: 114.2051093,
        palette: palette,
        encoded: encoded,
        size: (121.10, 134.74, 20.00))
}

/// Che Kung Temple's main hall and its square, turned 53° clockwise to
/// face south-west, where the square and the paths in are.
enum Map3DCheKungTemple {
    /// granite, stone, templeWall, dark, templeRoof, teal, slate.
    static let palette: [UInt32] = [Map3DPalette.granite, Map3DPalette.stone, Map3DPalette.templeWall, Map3DPalette.dark,
                                    Map3DPalette.templeRoof, Map3DPalette.templeTeal, Map3DPalette.roofSlate]

    static let registration = Map3DLandmarkRegistration(
        id: "hk-che-kung-temple", map: "hongkong",
        // 20 m south-west of the hall's outline middle (OSM way 137331553,
        // 45.1 m along its front; the model's hall stands 20 m behind its
        // middle).
        latitude: 22.3733565, longitude: 114.1828640,
        palette: palette,
        encoded: encoded,
        size: (103.78, 101.54, 22.00))
}
