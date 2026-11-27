// Decision 1018 (continued 4): Dazaifu Tenmangu (太宰府天満宮) on the
// Fukuoka map: the main hall (御本殿, 1591), its two-storeyed gate
// (楼門) and the three bridges over the Shinji pond (心字池), arched, flat
// and arched. Modelled by the local studio from photographs and
// OpenStreetMap's outlines (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/jp-dazaifu-2026-11/revision-3`; lessons in
// `docs/studio/lessons/jp-dazaifu.md`), the hall and the gate with their
// +x along the precinct's 91.8°, and written here by
// `tools/landmarks/glb_to_swift.py --centre --turn` (``encoded``).
//
// OpenStreetMap draws the hall, its cloister and the gate as one outline
// (relation 7396059, 78.5 m by 50.7 m, its long side at 1.8°): the hall
// stands in its northern bay, the gate in the notch of its southern wall,
// each at the middle of its body there, moved by the offset the converter
// printed. The cloister between them is not modelled; the outline is not
// drawn (``Map3DLandmarkRegistration/replaces``).

/// The main hall: its thick curved cypress-bark roof, the wide karahafu
/// porch in the middle of its front, vermilion pillars and gilt carving,
/// its front to the south (181.8°).
enum Map3DDazaifuHonden {
    /// portal (the stone base), dark, tileWhite, barkRoof, woodDark, gold,
    /// vermilion, paintGreen (the painted ground under the eaves).
    static let palette: [UInt32] = [Map3DPalette.portal, Map3DPalette.dark, Map3DPalette.tileWhite, Map3DPalette.arcade,
                                    Map3DPalette.cityRoofs[2].color, Map3DPalette.gold, Map3DPalette.lantern, Map3DPalette.cityRoofs[3].color]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-dazaifu-honden", map: "fukuoka",
        // The precinct outline's northern bay (24.7 m wide, its back wall
        // 40.2 m north of the outline's middle along 1.8°), the hall's body
        // (26.1 m by 20.3 m) against its back, moved 0.17 m north.
        latitude: 33.5215138, longitude: 130.5348300,
        palette: palette,
        encoded: encoded,
        // The precinct's outline, whose middle (the mean of its corners)
        // is in the courtyard, 1.8 m west and 21.3 m south of the hall's.
        replaces: [(east: -1.84, north: -21.28)],
        // LANDMARK-PLINTH: the precinct is level; the map's ground under
        // the hall rises 2.6 m to its south-east corner.
        plinth: Map3DPalette.portal,
        size: (29.11, 25.13, 14.00))
}

/// The two-storeyed vermilion gate: three open bays below, a railed
/// balcony and white walls above, under two cypress-bark roofs.
enum Map3DDazaifuRomon {
    /// portal, vermilion, tileWhite, dark, barkRoof, woodDark, gold.
    static let palette: [UInt32] = [Map3DPalette.portal, Map3DPalette.lantern, Map3DPalette.tileWhite, Map3DPalette.dark,
                                    Map3DPalette.arcade, Map3DPalette.cityRoofs[2].color, Map3DPalette.gold]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-dazaifu-romon", map: "fukuoka",
        // The notch in the precinct outline's southern wall (16.2 m wide,
        // 37.9 m south of the outline's middle along 181.8°), the gate's
        // body (15.0 m by 7.7 m) with its front there.
        latitude: 33.5209343, longitude: 130.5347796,
        palette: palette,
        encoded: encoded,
        // LANDMARK-PLINTH: the map's ground under the gate rises 1.4 m to
        // its south-east corner.
        plinth: Map3DPalette.portal,
        size: (19.74, 11.80, 12.80))
}

/// The three bridges over the Shinji pond (the past, the present and the
/// future): stone arches and piers under vermilion railings with bronze
/// finials. The pond is not modelled; the piers reach 1 m below the
/// bridges' ends.
enum Map3DDazaifuTaikoBridge {
    /// portal (the stone), vermilion (the railings), bronze (the finials).
    static let palette: [UInt32] = [Map3DPalette.portal, Map3DPalette.lantern, Map3DPalette.cityRoofs[1].color]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-dazaifu-taiko-bridge", map: "fukuoka",
        // The middle of the flat bridge (way 171847957), the line through
        // the three (ways 171847955, 171847957, 171847953) at 3.4°, moved
        // 0.82 m south to the middle of the model, longer to the south.
        latitude: 33.5200816, longitude: 130.5347055,
        palette: palette,
        encoded: encoded,
        size: (8.02, 58.67, 5.84))
}
