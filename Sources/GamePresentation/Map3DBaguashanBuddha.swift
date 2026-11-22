/// Decision 927: the Great Buddha of Baguashan (八卦山大佛), Changhua: the
/// seated Buddha on his lotus over a round plinth, facing west over the
/// town, its steps on the west. Modelled by the local studio from
/// photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/baguashan-buddha-2026-11/revision-3`,
/// #270; lessons in `docs/studio/lessons/baguashan-buddha.md`) and
/// written here by `tools/landmarks/glb_to_swift.py` (``encoded``).
enum Map3DBaguashanBuddha {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-baguashan-buddha", map: "taiwan",
        // OpenStreetMap's outline (way 1272641026) has its middle at the
        // plinth's; the model's footprint reaches 6 m further west over
        // its steps, so its middle is 3.2 m west of it.
        latitude: 24.0785735, longitude: 120.5488369,
        // buddha, buddhaShade (the lotus's windows), lotus, lotusEdge,
        // lotusRim, base (the plinth), steps.
        palette: [Map3DPalette.counters[1], Map3DPalette.dark, Map3DPalette.templeRoof, Map3DPalette.templeRidge,
                  Map3DPalette.gymGreen, Map3DPalette.stone, Map3DPalette.ballast],
        encoded: encoded,
        // The plinth 20 m across, the steps 6 m west of it, the Buddha's
        // head 26 m up.
        size: (26.4, 20.0, 25.99))
}
