/// Decision 931: M+ in the West Kowloon Cultural District, beside Kowloon
/// station on the harbour: a thin tall slab of dense horizontal fins
/// standing on a long low dark podium that floats over a set-back ground
/// floor (an upside-down T from the sea). Modelled by the local studio
/// from photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hk-west-kowloon-museums-2026-11/revision-1`,
/// #282; lessons in `docs/studio/lessons/hk-west-kowloon-museums.md`), the
/// slab on the podium's north side and its lit windows to the harbour,
/// turned 4° anticlockwise as the Lands Department's outline of the slab
/// lies, and written here by `tools/landmarks/glb_to_swift.py`
/// (``encoded``, `--turn 4`).
enum Map3DHKMPlus {
    static let registration = Map3DLandmarkRegistration(
        id: "hk-m-plus", map: "hongkong",
        // The middle of OpenStreetMap's outline (way 549702815), the
        // game's tourist spot hk14.
        latitude: 22.300780, longitude: 114.159062,
        // podium (its finned wall, the dark paving under its overhang),
        // slab, window (the bright rows to the sea, the crown), glass (the
        // ground floor), roofTop (the roofs, the eaves band, the columns),
        // hall_lit (the back walls of the five entrances).
        palette: [Map3DPalette.dark, Map3DPalette.mtrCharcoal, Map3DPalette.glazing, Map3DDepotFacilities.glass,
                  Map3DPalette.portal, Map3DPalette.tunnelLamp],
        encoded: encoded,
        // The podium's outline, 132.3 m by 121.3 m, turned 4°; the slab's
        // top 66 m up.
        size: (140.44, 130.24, 66.0))
}
