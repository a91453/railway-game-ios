// Decision 1018 (continued 4): two bridges of Kumamoto on the Fukuoka map:
// the Tsujun Bridge (通潤橋, 1854), a stone arch aqueduct over a valley,
// and the Tenmon Bridge (天門橋, 1966), the first of the Amakusa Five
// Bridges, a 502 m continuous steel truss over the strait. Modelled by the
// local studio from photographs, the official sizes and OpenStreetMap
// (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/jp-bridges-2026-11/revision-3`; lessons in
// `docs/studio/lessons/jp-bridges.md`), each with its +x along its axis,
// and written here by `tools/landmarks/glb_to_swift.py --centre --turn`
// (``encoded``).

/// The Tsujun Bridge: its single stone arch 27.6 m across, the battered
/// walls, the grass along its top, 76 m long and 20.2 m high, its +x at
/// 342° (north-north-west). Shown without its water display.
enum Map3DTsujunBridge {
    /// arcade (the stone), stoneDark (the arch's soffit, the bands),
    /// embankment (the grass on its top), dark (the outlets).
    static let palette: [UInt32] = [Map3DPalette.arcade, Map3DPalette.cityRoofs[2].color, Map3DPalette.embankment, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-bridges-tsujun", map: "fukuoka",
        // The middle of OpenStreetMap's line (way 113769483).
        latitude: 32.6815660, longitude: 130.9937600,
        palette: palette,
        encoded: encoded,
        size: (31.70, 74.96, 20.20))
}

/// The Tenmon Bridge: a flat top chord over the whole length, the bottom
/// chord deepening in arches to its two piers in the sea, 508 m from
/// abutment to abutment, its +x at 109.7° (east-south-east). Its road
/// 43.24 m over its foot, set level with the roads at its ends
/// (BRIDGE-LANDMARK-DECK), the map's own bridge left out under it.
enum Map3DTenmonBridge {
    /// tankSteel (the trusses), steel (the floor beams and bracing),
    /// concrete (piers, abutments, kerbs), dark (the road).
    static let palette: [UInt32] = [Map3DPalette.tankSteel, Map3DPalette.steel, Map3DPalette.concrete, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-bridges-tenmon", map: "fukuoka",
        // The middle of OpenStreetMap's outline (way 549450098, 508.5 m by
        // 12.0 m, its long side at 109.7°).
        latitude: 32.6111551, longitude: 130.4586635,
        deck: 43.24,
        palette: palette,
        encoded: encoded,
        // 508 m by 12 m turned 19.7°, its top chord 54 m over the sea.
        size: (482.32, 182.54, 54.07))
}
