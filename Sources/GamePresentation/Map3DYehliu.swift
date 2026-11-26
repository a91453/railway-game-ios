// Decision 1018: the Queen's Head (女王頭) and two mushroom rocks (蕈狀岩)
// at Yehliu on the Taiwan map's north coast. Modelled by the local studio
// from photographs (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/yehliu-queens-head-2026-11/revision-2`;
// lessons in `docs/studio/lessons/yehliu-queens-head.md`) and written here
// by `tools/landmarks/glb_to_swift.py --raise 0.20` (``encoded``): each
// rock's foot goes 0.20 m into the ground (`sink`), as the studio built it.
// Not turned: OpenStreetMap maps the rocks as points with no bearing.

/// sandstone, rockHead, rockDark: the pale neck and mound, the brown head
/// and its darker honeycomb.
private let yehliuPalette: [UInt32] = [Map3DPalette.slatGold, Map3DPalette.trunk, Map3DPalette.arcade]

/// The Queen's Head.
enum Map3DYehliuQueensHead {
    static let registration = Map3DLandmarkRegistration(
        id: "yehliu-queens-head", map: "taiwan",
        // OSM node 4199791991 (女王頭).
        latitude: 25.2087809, longitude: 121.6931330,
        sink: 0.20,
        palette: yehliuPalette,
        encoded: encoded,
        size: (2.09, 1.95, 2.70))
}

/// Two mushroom rocks along the path to the Queen's Head.
enum Map3DYehliuMushroomRocks {
    /// The rock `id`'s near and far meshes alone.
    static func model(_ id: String) -> [String: String] {
        [id: encoded[id] ?? "", id + "-far": encoded[id + "-far"] ?? ""]
    }

    static let rockA = Map3DLandmarkRegistration(
        id: "yehliu-mushroom-rock-a", map: "taiwan",
        // OSM node 4199791990 (冰淇淋石).
        latitude: 25.2075065, longitude: 121.6909667,
        sink: 0.20,
        palette: yehliuPalette,
        encoded: model("yehliu-mushroom-rock-a"),
        size: (2.03, 1.84, 1.80))

    static let rockB = Map3DLandmarkRegistration(
        id: "yehliu-mushroom-rock-b", map: "taiwan",
        // OSM node 13890675029 (俏皮公主).
        latitude: 25.2079437, longitude: 121.6919598,
        sink: 0.20,
        palette: yehliuPalette,
        encoded: model("yehliu-mushroom-rock-b"),
        size: (2.32, 2.09, 1.50))
}
