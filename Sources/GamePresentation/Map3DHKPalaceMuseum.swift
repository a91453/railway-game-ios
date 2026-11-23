/// Decision 931: the Hong Kong Palace Museum at the west end of the West
/// Kowloon Cultural District: a block that steps out storey by storey to
/// its roof (an upturned measure), ringed by pale bands with dark joints,
/// a brown cut in each face. Modelled by the local studio from photographs
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hk-west-kowloon-museums-2026-11/revision-1`,
/// #282; lessons in `docs/studio/lessons/hk-west-kowloon-museums.md`), its
/// long faces to the harbour and to the north, and written here by
/// `tools/landmarks/glb_to_swift.py` (``encoded``).
enum Map3DHKPalaceMuseum {
    static let registration = Map3DLandmarkRegistration(
        id: "hk-palace-museum", map: "hongkong",
        // The middle of the Lands Department's outline of the museum's
        // body (85.7 m by 73.9 m), 59 m west and 12 m south of the middle
        // of its site (the game's tourist spot hk15).
        latitude: 22.301573, longitude: 114.155048,
        // band (the cladding's bands, the roof terrace), bandShadow (the
        // joints between them), recess (the cuts' brown walls), glass (in
        // the cuts), roofStorey, hall_lit (a strip of light in each cut).
        palette: [Map3DPalette.forecourt, Map3DPalette.arcade, Map3DPalette.timber, Map3DDepotFacilities.glass,
                  Map3DPalette.mtrCharcoal, Map3DPalette.tunnelLamp],
        encoded: encoded,
        // 96.8 m by 82.8 m at its roof (76 m by 62 m at the ground), 45 m high.
        size: (96.80, 82.80, 45.0))
}
