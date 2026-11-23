/// Decision 928: the Luce Memorial Chapel (路思義教堂) at Tunghai
/// University, Taichung: four curved walls of yellow glazed tile leaning
/// together, a slot of glass along the ridge and at both ends. Modelled by
/// the local studio from photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-luce-chapel-2026-11/revision-2`,
/// #293; lessons in `docs/studio/lessons/tw-luce-chapel.md`), already
/// turned as OpenStreetMap's outline stands, and written here by
/// `tools/landmarks/glb_to_swift.py` (``encoded``). Which end the door is
/// at (taken as the south-east one, bearing 134°) is not verified.
enum Map3DLuceChapel {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-luce-chapel", map: "taiwan",
        // OpenStreetMap's outline's middle (way 227101621).
        latitude: 24.1788938, longitude: 120.6005433,
        // tile, rib (the walls' edges), slot (the glass), cross, base.
        palette: [Map3DPalette.gold, Map3DPalette.concrete, Map3DPalette.mtrCharcoal, Map3DPalette.dark, Map3DPalette.granite],
        encoded: encoded,
        // The turned chapel on its base, 26.3 m by 26.2 m; the cross
        // 21.4 m.
        size: (26.30, 26.16, 21.4))
}
