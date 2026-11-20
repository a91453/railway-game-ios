/// FUKUOKA-LANDMARKS (decision 854's later note): Fukuoka Dome, the local
/// studio's model, rebuilt from the earlier version's dome and photographs
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/fukuoka-landmarks-2026-11/revision-4`),
/// written here by `tools/landmarks/glb_to_swift.py` (``encoded``).
/// Decision 895: a registered landmark.
enum Map3DFukuokaDome {
    static let registration = Map3DLandmarkRegistration(
        id: "fukuoka-dome", map: "fukuoka",
        // The middle of the model's footprint: OpenStreetMap's outline's
        // centroid (way 28445837) moved 3.94 m east and 4.45 m south for
        // the hall on its south-east side (glb_to_swift.py --centre).
        latitude: 33.5952487, longitude: 130.3621835,
        // wallWarm, bandDark (not lit), roofWarm, wallPale.
        palette: [Map3DPalette.cityConcreteWalls[3], Map3DPalette.dark, Map3DPalette.cityRoofs[2].color, Map3DPalette.cityConcreteWalls[4]],
        encoded: encoded,
        // OpenStreetMap's outline, 84 m high, with the hall on its
        // south-east side.
        size: (224.9, 223.9, 84.85))
}
