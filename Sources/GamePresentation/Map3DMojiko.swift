// Decision 1018 (continued 3): Mojiko Retro (門司港レトロ) at the north tip of
// Kyushu, on the Fukuoka map: Mojiko station's wooden neo-Renaissance hall
// (1914), the red brick Former Moji Customs House (1912) on the harbour and
// the half-timbered Former Moji Mitsui Club (1921). Modelled by the local
// studio from photographs and OpenStreetMap's outlines
// (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/jp-mojiko-2026-11/revision-3`; lessons in
// `docs/studio/lessons/jp-mojiko.md`), the studio's +x along each outline's
// long side, and written here by `tools/landmarks/glb_to_swift.py --centre
// --turn` (``encoded``).
//
// Each stands at the middle of its OpenStreetMap outline's box (the
// studio's origin) moved by the offset the converter printed: the middle of
// the turned model's footprint, which an outline that is not a rectangle
// moves off the box's middle. The studio's window glass is drawn in the
// palette's dark, which the palette keeps for dark windows and glass.

/// Mojiko station: its symmetric front of warm grey plaster between two
/// slate mansard towers, the copper-framed clock in the roof, the low wings
/// and the long canopy, the hall's back wings toward the tracks.
enum Map3DMojikoStation {
    /// terrazzo, tileWhite, slate, copper, woodDark, dark, glass.
    static let palette: [UInt32] = [Map3DPalette.terrazzo, Map3DPalette.tileWhite, Map3DPalette.roofSlate, Map3DPalette.gymGreen,
                                    Map3DPalette.cityRoofs[2].color, Map3DPalette.dark, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-mojiko-station", map: "fukuoka",
        // OpenStreetMap's outline (relation 2532442, 65.1 m by 38.7 m, its
        // long side at 127.8°): its box's middle moved 2.18 m west and
        // 2.04 m south, to the turned model's footprint middle.
        latitude: 33.9451280, longitude: 130.9614742,
        palette: palette,
        encoded: encoded,
        size: (71.26, 66.90, 16.60))
}

/// The Former Moji Customs House: red brick over a pale stone band, its
/// grey slate roofs, the copper spire at its corner.
enum Map3DMojikoCustoms {
    /// brick, terrazzo, tileWhite, slate, copper, woodDark, dark, glass.
    static let palette: [UInt32] = [Map3DPalette.hallWalls[3], Map3DPalette.terrazzo, Map3DPalette.tileWhite, Map3DPalette.roofSlate,
                                    Map3DPalette.gymGreen, Map3DPalette.cityRoofs[2].color, Map3DPalette.dark, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-mojiko-customs", map: "fukuoka",
        // OpenStreetMap's outline (way 976479446, 33.9 m by 20.3 m, its
        // long side at 117.2°): its box's middle moved 0.54 m east and
        // 2.41 m north.
        latitude: 33.9477331, longitude: 130.9635841,
        palette: palette,
        encoded: encoded,
        size: (38.55, 29.12, 14.00))
}

/// The Former Moji Mitsui Club: dark half-timbering on its blue-grey upper
/// storey, white window frames, the steep slate roof over a stone ground
/// floor.
enum Map3DMojikoMitsuiClub {
    /// wallGrey, woodDark, tileWhite, slate, copper, concrete, glass.
    static let palette: [UInt32] = [Map3DPalette.bridge, Map3DPalette.cityRoofs[2].color, Map3DPalette.tileWhite, Map3DPalette.roofSlate,
                                    Map3DPalette.gymGreen, Map3DPalette.concrete, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-mojiko-mitsui-club", map: "fukuoka",
        // OpenStreetMap's outline (way 627252021, 30.1 m by 19.9 m, its
        // long side at 135.1°): its box's middle moved 0.63 m east and
        // 0.13 m north.
        latitude: 33.9457279, longitude: 130.9625731,
        palette: palette,
        encoded: encoded,
        size: (33.60, 35.38, 13.50))
}
