// Decision 1018 (continued): Kokura Castle (小倉城) in Kitakyushu and
// Karatsu Castle (唐津城) on its point over Karatsu Bay, on the Fukuoka
// map: each keep on its stone wall, modelled by the local studio from
// photographs and OpenStreetMap's outlines (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/jp-castles-2026-11/revision-2`; lessons in
// `docs/studio/lessons/jp-castles.md`), the studio's +x along each
// outline's long side, and written here by `tools/landmarks/glb_to_swift.py
// --centre --turn` (``encoded``). Their stone walls stand on the lowest
// ground under them, as the real ones rise from the moat (Kokura) and the
// point's foot (Karatsu): the ground under each outline falls some 8 to 9
// metres, about the walls' height.

/// Kokura's five-storey keep, its top storey wider than the one below
/// (唐造り), with its entrance turret (付櫓) to the west-north-west, on its
/// dark rough-stone wall.
enum Map3DKokuraCastle {
    /// stoneDark, stoneWarm, tileWhite, slate, copper, dark: the wall's
    /// dark stone, its corner stones, the white plaster and eaves, the grey
    /// tile roofs, the green copper ridge fish (鯱), the black window
    /// boards. The studio's colours, each already the game's.
    static let palette: [UInt32] = [Map3DPalette.cityRoofs[2].color, Map3DPalette.arcade, Map3DPalette.tileWhite,
                                    Map3DPalette.roofSlate, Map3DPalette.gymGreen, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-castles-kokura", map: "fukuoka",
        // OpenStreetMap's outline (way 153209407, 55.3 m by 27.9 m, its long
        // side at 113.9°): its box's middle, 3.5 m east of which is the
        // middle of the turned model's footprint, the keep's end being wider
        // than the turret's.
        latitude: 33.8844951, longitude: 130.8741605,
        palette: palette,
        encoded: encoded,
        size: (57.55, 50.46, 32.85))
}

/// Karatsu's five-storey keep (1966), its top storey's vermilion
/// balcony, on its warm grey stone wall.
enum Map3DKaratsuCastle {
    /// stoneWarm, stoneDark, tileWhite, slate, vermilion, dark: the wall's
    /// stone, its corner stones, the white plaster, the grey tile roofs,
    /// the top storey's railing (the lanterns' red), the dark boards.
    static let palette: [UInt32] = [Map3DPalette.arcade, Map3DPalette.cityRoofs[2].color, Map3DPalette.tileWhite,
                                    Map3DPalette.roofSlate, Map3DPalette.lantern, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-castles-karatsu", map: "fukuoka",
        // The middle of OpenStreetMap's outline (way 500427895, 23.9 m by
        // 22.5 m, its long side at 105.3°).
        latitude: 33.4535132, longitude: 129.9781934,
        palette: palette,
        encoded: encoded,
        size: (31.15, 30.10, 30.50))
}
