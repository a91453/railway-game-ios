/// Decision 931: M+ in the West Kowloon Cultural District, beside Kowloon
/// station on the harbour: a thin tall slab of dense horizontal fins
/// standing on a long low dark podium that floats over a set-back ground
/// floor (an upside-down T from the sea). Modelled by the local studio
/// from photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hk-west-kowloon-museums-2026-11/revision-2`,
/// #376; lessons in `docs/studio/lessons/hk-west-kowloon-museums.md`), the
/// slab 110.6 m by 12 m across the podium's middle as the Lands Department
/// measured it, its lit windows to the harbour, turned 4° anticlockwise as
/// that outline lies, and written here by `tools/landmarks/glb_to_swift.py`
/// (``encoded``, `--centre --turn 4`).
enum Map3DHKMPlus {
    static let registration = Map3DLandmarkRegistration(
        id: "hk-m-plus", map: "hongkong",
        // The middle of OpenStreetMap's outline of the podium (way
        // 549702815), 9.2 m east and 5.6 m north of the tourist spot hk14,
        // which stays where players tap it.
        latitude: 22.300831, longitude: 114.159151,
        // podium (its finned wall, the dark paving under its overhang),
        // slab, window (the bright rows to the sea, the crown), glass (the
        // ground floor), roofTop (the roofs, the eaves band, the columns),
        // hall_lit (the back walls of the five entrances).
        palette: [Map3DPalette.dark, Map3DPalette.mtrCharcoal, Map3DPalette.glazing, Map3DDepotFacilities.glass,
                  Map3DPalette.portal, Map3DPalette.tunnelLamp],
        encoded: encoded,
        // The podium's outline, 121.3 m east to west by 132.3 m north to
        // south, turned 4°; the slab's top 66 m up.
        size: (130.24, 140.44, 66.0))
}
