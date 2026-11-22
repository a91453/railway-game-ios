/// Decision 925: the Hong Kong Observation Wheel on the Central waterfront,
/// beside the Star Ferry's Central piers: a white wheel 60 m high with 42
/// red cabins, on two A-shaped pairs of legs over a low boarding deck.
/// Modelled by the local studio from photographs
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hk-observation-wheel-2026-11/revision-1`,
/// #292; lessons in `docs/studio/lessons/hk-observation-wheel.md`), its
/// wheel along the shore (north-north-west to south-south-east), and
/// written here by `tools/landmarks/glb_to_swift.py` (``encoded``).
enum Map3DHKObservationWheel {
    static let registration = Map3DLandmarkRegistration(
        id: "hk-observation-wheel", map: "hongkong",
        // The game's tourist spot hk16, the wheel's axle.
        latitude: 22.28545, longitude: 114.16172,
        // white (rim, spokes, legs, cabin bands), hub, cabinRed, glass
        // (the cabins' windows), base (the deck), dark (the hangers),
        // rim_lit (the warm band inside the rim).
        palette: [Map3DPalette.tileWhite, Map3DOverheadLine.mastSteel, Map3DPalette.mtrRed, Map3DPalette.glazing,
                  Map3DPalette.granite, Map3DPalette.dark, Map3DPalette.tunnelLamp],
        encoded: encoded,
        // The A-legs' feet 25.6 m apart east to west, the wheel 55.1 m
        // along the shore, its top 60 m up.
        size: (25.58, 55.14, 60.0))
}
