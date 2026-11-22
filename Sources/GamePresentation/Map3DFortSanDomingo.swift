/// Decision 926: Fort San Domingo (淡水紅毛城) at Tamsui: the red fort
/// with its battlements, two brick corner turrets and flagpole, and the
/// lower brick wing to its east-south-east, on a stone plinth. Modelled
/// by the local studio from photographs and OpenStreetMap's outline
/// (relation 3986680; `a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-fort-san-domingo-2026-11/revision-1`,
/// #271), already turned 16.3° clockwise as that outline, and written
/// here by `tools/landmarks/glb_to_swift.py` (``encoded``).
enum Map3DFortSanDomingo {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-fort-san-domingo", map: "taiwan",
        // The middle of the model's footprint: 4.66 m north and 3.03 m
        // west of the mean of OpenStreetMap's outline points.
        latitude: 25.1753837, longitude: 121.4329044,
        // wall, wallTop, brick, opening, shutter, stone, pole, flag.
        palette: [Map3DPalette.templeWall, Map3DPalette.redBrick, Map3DPalette.brick, Map3DPalette.dark,
                  Map3DPalette.gymGreen, Map3DPalette.stone, Map3DPalette.mastSteel, Map3DPalette.awningCream],
        encoded: encoded,
        size: (32.26, 27.44, 22.60))
}
