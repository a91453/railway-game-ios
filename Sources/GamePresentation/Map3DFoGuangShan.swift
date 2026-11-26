// Decision 1018: the Fo Guang Shan Buddha Memorial Center (佛光山佛陀紀念館)
// on the Taiwan map: the great bronze Buddha on its terrace, the main hall
// with its stupa, and the eight pagodas along the avenue between them.
// Modelled by the local studio from photographs and OpenStreetMap's
// outlines (`a91453/railway-assets-private-2`
// `game-art-previews/docs/art/fgs-big-buddha-2026-11/revision-2`; lessons
// in `docs/studio/lessons/fgs-big-buddha.md`) and written here by
// `tools/landmarks/glb_to_swift.py --centre` (``encoded``). The Buddha and
// the hall share the studio's origin (22.7573656, 120.4404136, the hall's
// outline middle in `fgs-footprints.json`); each is centred here and set
// at that origin plus the offset the converter printed, so the two stand
// where the studio placed them. The pagoda is turned 20.3° clockwise
// (`--turn -20.3`) to lie along the avenue's bearing of 110.3°.

/// The bronze Buddha seated on its terrace, the great stair below it.
enum Map3DFoGuangShanBuddha {
    /// gold, sandstone, terrace, dark: the bronze, the pale stone of the
    /// terrace walls, its paving, the shadowed openings.
    static let palette: [UInt32] = [Map3DPalette.gold, Map3DPalette.cityConcreteWalls[3], Map3DPalette.terrazzo, Map3DPalette.dark]

    static let registration = Map3DLandmarkRegistration(
        id: "fgs-big-buddha", map: "taiwan",
        // The studio's origin, 109.84 m west and 36.58 m north.
        latitude: 22.7576959, longitude: 120.4393441,
        palette: palette,
        encoded: encoded,
        size: (115.23, 90.93, 86.50))
}

/// The main hall (本館) on its platform, the stupa at its middle.
enum Map3DFoGuangShanMainHall {
    /// sandstone, terrace, gold, dark, pagodaBody.
    static let palette: [UInt32] = [Map3DPalette.cityConcreteWalls[3], Map3DPalette.terrazzo, Map3DPalette.gold, Map3DPalette.dark, Map3DPalette.arcade]

    static let registration = Map3DLandmarkRegistration(
        id: "fgs-main-hall", map: "taiwan",
        // The studio's origin, 15.69 m west and 1.45 m north.
        latitude: 22.7573787, longitude: 120.4402608,
        palette: palette,
        encoded: encoded,
        size: (138.46, 140.24, 44.00))
}

/// The eight pagodas (八塔), one model at each pagoda's outline middle.
enum Map3DFoGuangShanPagodas {
    /// templeRoof, pagodaBody, sandstone, terrace, gold, dark.
    static let palette: [UInt32] = [Map3DPalette.templeRoof, Map3DPalette.arcade, Map3DPalette.cityConcreteWalls[3], Map3DPalette.terrazzo, Map3DPalette.gold, Map3DPalette.dark]

    /// The pagoda's near and far meshes under the landmark `id`'s names.
    static func model(as id: String) -> [String: String] {
        [id: encoded["fgs-pagoda"] ?? "", id + "-far": encoded["fgs-pagoda-far"] ?? ""]
    }

    // OSM way 471316484 (一教塔).
    static let first = Map3DLandmarkRegistration(id: "fgs-pagoda-1", map: "taiwan", latitude: 22.7562443, longitude: 120.4423483,
        palette: palette, encoded: model(as: "fgs-pagoda-1"), size: (33.10, 29.08, 38.00))
    // OSM way 471316481 (二眾塔).
    static let second = Map3DLandmarkRegistration(id: "fgs-pagoda-2", map: "taiwan", latitude: 22.7570118, longitude: 120.4426512,
        palette: palette, encoded: model(as: "fgs-pagoda-2"), size: (33.10, 29.08, 38.00))
    // OSM way 526772902 (三好塔).
    static let third = Map3DLandmarkRegistration(id: "fgs-pagoda-3", map: "taiwan", latitude: 22.7560396, longitude: 120.4429417,
        palette: palette, encoded: model(as: "fgs-pagoda-3"), size: (33.10, 29.08, 38.00))
    // OSM way 526772901 (四給塔).
    static let fourth = Map3DLandmarkRegistration(id: "fgs-pagoda-4", map: "taiwan", latitude: 22.7568000, longitude: 120.4432265,
        palette: palette, encoded: model(as: "fgs-pagoda-4"), size: (33.10, 29.08, 38.00))
    // OSM way 526772903 (五和塔).
    static let fifth = Map3DLandmarkRegistration(id: "fgs-pagoda-5", map: "taiwan", latitude: 22.7558380, longitude: 120.4435290,
        palette: palette, encoded: model(as: "fgs-pagoda-5"), size: (33.10, 29.08, 38.00))
    // OSM way 526772905 (六度塔).
    static let sixth = Map3DLandmarkRegistration(id: "fgs-pagoda-6", map: "taiwan", latitude: 22.7565920, longitude: 120.4438271,
        palette: palette, encoded: model(as: "fgs-pagoda-6"), size: (33.10, 29.08, 38.00))
    // OSM way 526772904 (七誡塔).
    static let seventh = Map3DLandmarkRegistration(id: "fgs-pagoda-7", map: "taiwan", latitude: 22.7556303, longitude: 120.4441159,
        palette: palette, encoded: model(as: "fgs-pagoda-7"), size: (33.10, 29.08, 38.00))
    // OSM way 526772906 (八道塔).
    static let eighth = Map3DLandmarkRegistration(id: "fgs-pagoda-8", map: "taiwan", latitude: 22.7563941, longitude: 120.4444180,
        palette: palette, encoded: model(as: "fgs-pagoda-8"), size: (33.10, 29.08, 38.00))
}
