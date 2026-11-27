// Decision 1018 (continued 5): the Manda Pit (万田坑, Omuta and Arao, a
// World Heritage site of the Miike coal mine) on the Fukuoka map: the
// steel headframe of its second shaft (1908), 18.9 m to the top of its
// mast, with its two winding wheels, and the red-brick winding house
// beside it with its slate roofs. Modelled by the local studio from
// photographs, the Agency for Cultural Affairs' record and OpenStreetMap
// (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/jp-manda-pit-2026-11/revision-2`, #655;
// lessons in `docs/studio/lessons/jp-manda-pit.md`), its origin the
// shaft (node 2517094468), its +x toward the winding house (19.9°), and
// written here by `tools/landmarks/glb_to_swift.py --centre --turn 70.1
// --raise 1.5` (``encoded``): raised by the 1.5 m its footings reach
// into the ground, which ``registration``'s `sink` lowers again.

/// It stands where OpenStreetMap's winding house (way 832591924) is, which
/// it covers; the brick sheds north and east of it (ways 832591921–923)
/// and the museum (way 244384012) stay.
enum Map3DMandaPit {
    /// tankSteel (the headframe, the wheels), steel (the cables, walkways,
    /// window bars), redBrick (the winding house), concrete (the shaft's
    /// collar, the footings, the stone bands), mtrCharcoal (the slate
    /// roofs), roofRidge (the ridges, the lantern), dark (the windows and
    /// doors, the shaft).
    static let palette: [UInt32] = [Map3DPalette.tankSteel, Map3DPalette.steel, Map3DPalette.redBrick, Map3DPalette.concrete,
                                    Map3DPalette.mtrCharcoal, Map3DPalette.cityRoofs[1].color, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "jp-manda-pit", map: "fukuoka",
        // The shaft (node 2517094468) moved by the 6.03 m east and 12.26 m
        // north `--centre` printed.
        latitude: 33.0028177, longitude: 130.4493625,
        sink: 1.5,
        palette: palette,
        encoded: encoded,
        // Its outline (an L, 32.26 m by 21.33 m at most) turned 70.1°;
        // the headframe's mast 18.9 m up, its footings 1.5 m under the
        // ground.
        size: (23.52, 35.87, 20.40))
}
