// Decision 1018 (continued 4): three shrines on the Fukuoka map: Munakata
// Taisha's Hetsu-gu (宗像大社辺津宮), Yutoku Inari (祐徳稲荷神社) on its
// stage over the hillside, and Aoi Aso (青井阿蘇神社) with its thatched
// halls, a National Treasure. Modelled by the local studio from
// photographs and OpenStreetMap's outlines
// (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/jp-shrines-2026-11/revision-3`; lessons in
// `docs/studio/lessons/jp-shrines.md`), the studio's +x along each
// outline's long side, and written here by
// `tools/landmarks/glb_to_swift.py --centre --turn` (``encoded``).
//
// Each stands at the middle of its OpenStreetMap outline's box (the
// studio's origin) moved by the offset the converter printed.

/// Munakata Taisha's Hetsu-gu: the bark-roofed main hall (本殿) and the
/// worship hall (拝殿) before it, their white walls and vermilion
/// pillars, the main hall to the south-east (+x at 138.7°).
enum Map3DMunakataTaisha {
    /// barkRoof, dark, portal, slate, tileWhite, timber, vermilion, woodDark.
    static let palette: [UInt32] = [Map3DPalette.trunk, Map3DPalette.dark, Map3DPalette.portal, Map3DPalette.roofSlate,
                                    Map3DPalette.tileWhite, Map3DPalette.timber, Map3DPalette.lantern, Map3DPalette.cityRoofs[2].color]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-shrines-munakata", map: "fukuoka",
        // The two halls' outlines (relations 10384942 and 10384943) in one
        // box, 29.5 m by 14.4 m along 138.7°, moved 0.75 m east and 0.63 m
        // south.
        latitude: 33.8311476, longitude: 130.5143067,
        palette: palette,
        encoded: encoded,
        size: (29.66, 31.26, 11.50))
}

/// Yutoku Inari: the vermilion main hall and its stage on a scaffold of
/// red-brown pillars (懸造) over the 17 m drop of the hillside, its front
/// to the east (+x at 4.5°, the hill to the west).
enum Map3DYutokuInari {
    /// copper, dark, gold, kakeRed (the scaffold), portal (the stone
    /// terraces), slate, vermilion, woodDark.
    static let palette: [UInt32] = [Map3DPalette.gymGreen, Map3DPalette.dark, Map3DPalette.gold, Map3DPalette.hallWalls[3],
                                    Map3DPalette.portal, Map3DPalette.roofSlate, Map3DPalette.lantern, Map3DPalette.cityRoofs[2].color]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-shrines-yutoku-inari", map: "fukuoka",
        // OpenStreetMap's outline (way 614228251, 32.4 m by 23.0 m, its
        // long side at 4.5°): its box's middle moved 0.21 m west and
        // 0.39 m north.
        latitude: 33.0738546, longitude: 130.1077502,
        palette: palette,
        encoded: encoded,
        size: (25.07, 33.32, 29.00))
}

/// Aoi Aso: the steep thatched worship and offering halls, the slate
/// karahafu porch, the main hall behind with its crossed chigi and the
/// low vermilion fence, the worship hall's front to the south-south-east
/// (+x at 161.6°).
enum Map3DAoiAsoShrine {
    /// copper, dark, portal, slate, thatch, timber, vermilion, woodDark.
    static let palette: [UInt32] = [Map3DPalette.gymGreen, Map3DPalette.dark, Map3DPalette.portal, Map3DPalette.roofSlate,
                                    Map3DPalette.arcade, Map3DPalette.timber, Map3DPalette.lantern, Map3DPalette.cityRoofs[2].color]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-shrines-aoi-aso", map: "fukuoka",
        // OpenStreetMap's outline (way 464706203, 39.2 m by 17.5 m, its
        // long side at 161.6°): its box's middle moved 1.27 m east and
        // 0.29 m south.
        latitude: 32.2134651, longitude: 130.7528825,
        palette: palette,
        encoded: encoded,
        size: (27.32, 41.03, 12.60))
}
