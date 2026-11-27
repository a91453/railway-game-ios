// Decision 1018 (continued 5): two buildings of the Yoshinogari site
// (吉野ヶ里遺跡, Saga) on the Fukuoka map, rebuilt as the park stands
// them in its north inner enclosure: the main hall (主祭殿) raised on its
// posts, three floors under its thatched roof, and the watchtower
// (物見櫓) on its six legs. Modelled by the local studio from
// photographs and OpenStreetMap's outlines (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/jp-yoshinogari-2026-11/revision-2`, #654;
// lessons in `docs/studio/lessons/jp-yoshinogari.md`), the studio's +x
// along each ridge, and written here by `tools/landmarks/glb_to_swift.py
// --centre --turn --raise 0.6` (``encoded``): raised by the 0.6 m its
// posts reach into the ground, which each registration's `sink` lowers
// again. Its colours are the palette's: the thatch the city's dark brown
// roof, the weathered wood ballast's grey and the arcade's.

/// The main hall, its ridge at 97.4° (east, a little south).
enum Map3DYoshinogariSanctuary {
    /// dark, thatch, timber (the stairs' treads), timberDark (the eaves'
    /// cut edges, the ridge's saddles), woodGrey (posts, beams,
    /// railings), woodWall (the inner walls, the boarded eaves).
    static let palette: [UInt32] = [Map3DPalette.dark, Map3DPalette.cityRoofs[2].color, Map3DPalette.timber, Map3DPalette.timberSiding,
                                    Map3DPalette.ballast, Map3DPalette.arcade]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-yoshinogari-sanctuary", map: "fukuoka",
        // The mean of the corners of OpenStreetMap's way 177863632 (15.2 m
        // by 14.5 m along 97.4°), 2.1 m from the brief's point.
        latitude: 33.3268654, longitude: 130.3863193,
        sink: 0.6,
        palette: palette,
        encoded: encoded,
        size: (16.96, 16.34, 17.10))
}

/// The watchtower, its ridge at 78.5°, on way 177863646 north of the hall.
enum Map3DYoshinogariWatchtower {
    /// thatch, timber, timberDark, woodGrey.
    static let palette: [UInt32] = [Map3DPalette.cityRoofs[2].color, Map3DPalette.timber, Map3DPalette.timberSiding, Map3DPalette.ballast]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-yoshinogari-watchtower", map: "fukuoka",
        // The middle of OpenStreetMap's way 177863646 (its roof, 6.8 m by
        // 6.9 m).
        latitude: 33.3272774, longitude: 130.3864404,
        sink: 0.6,
        palette: palette,
        encoded: encoded,
        size: (8.09, 8.17, 12.60))
}
