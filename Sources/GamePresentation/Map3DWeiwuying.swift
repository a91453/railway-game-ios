/// Decision 928: the National Kaohsiung Center for the Arts (衛武營): one
/// white roof that rolls over four halls, the open plaza under it between
/// them, and the outdoor theatre where the roof comes down to the lawn.
/// Modelled by the local studio from photographs
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-weiwuying-2026-11/revision-3`,
/// #296; lessons in `docs/studio/lessons/tw-weiwuying.md`), already turned
/// as OpenStreetMap's outline stands (its long side bearing 110°), and
/// written here by `tools/landmarks/glb_to_swift.py` (``encoded``).
enum Map3DWeiwuying {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-weiwuying", map: "taiwan",
        // OpenStreetMap's outline's middle (way 203360692).
        latitude: 22.6229169, longitude: 120.3423926,
        // roofWhite, ceilingGrey (under the roof), hallWall, glazing,
        // opening, lawn, seatWhite (the outdoor theatre), warm_lit.
        palette: [Map3DPalette.tileWhite, Map3DPalette.tankSteel, Map3DPalette.concrete, Map3DPalette.shadedGlass,
                  Map3DPalette.mtrCharcoal, Map3DPalette.park, Map3DPalette.sidewalk, Map3DPalette.tunnelLamp],
        encoded: encoded,
        // The turned roof, 264.5 m by 226 m; its highest crest 39.5 m.
        size: (264.48, 226.04, 39.5))
}

extension Map3DPalette {
    /// Decision 928: glass in the shade (under a deep roof, behind a
    /// depot's doors): the dark glass the depots, the street's shops and
    /// the old models already wrote for themselves, now the palette's.
    static let shadedGlass = Map3DColor.rgb(0x26313D)
}
