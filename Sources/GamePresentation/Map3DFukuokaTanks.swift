/// Decision 924: Fukuoka's spherical gas holders and water towers where
/// OpenStreetMap maps them (`man_made=gasometer`, `man_made=water_tower`),
/// drawn as the owner's earlier version drew them (SwiftRailMac's
/// ガスタンク `item_a14610e919ffb965d418ca71` and 給水塔
/// `item_2cedf43508c08f24c37b0c88`), as registered landmarks (decision
/// 895), so the surveyed outline under each is not drawn again. The
/// models are `tools/old-models/old_tanks.py`'s (``encoded``): the gas
/// holders at two sizes (the large ones as PLATEAU measures Saibu Gas's
/// two at 37 m, the smaller ones beside them 21 m), the water towers 21 m
/// (原団地給水塔 30 m, its `height`). Outlines under 4 m across, and the
/// water "towers" over 9 m across (service reservoirs on the ground), are
/// left as they are.
enum Map3DFukuokaTanks {
    /// A gas holder's sphere and its legs: the factory tanks' white and
    /// the water tank's stand (the same slots the game's yard tanks use).
    static let gasPalette: [UInt32] = [Map3DPalette.tankWhite, Map3DPalette.tankStand]
    /// A water tower's tank, its legs, catwalk and ladder, and the pale
    /// panels round its legs.
    static let waterPalette: [UInt32] = [Map3DPalette.steel, Map3DPalette.tankStand, Map3DPalette.concrete]

    /// The model `name`'s near and far meshes under the landmark `id`'s
    /// names (one model stands in several places).
    static func model(_ name: String, as id: String) -> [String: String] {
        [id: encoded[name] ?? "", id + "-far": encoded[name + "-far"] ?? ""]
    }

    // OSM way 701217744 (PLATEAU 36.9 m).
    static let gasHolder701217744 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-701217744", map: "fukuoka", latitude: 33.570188, longitude: 130.2863062,
        palette: gasPalette, encoded: model("fukuoka-gas-holder-large", as: "fukuoka-gas-holder-701217744"), size: (34.04, 34.04, 35.81))
    // OSM way 701217745 (PLATEAU 37.4 m).
    static let gasHolder701217745 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-701217745", map: "fukuoka", latitude: 33.5696233, longitude: 130.2860842,
        palette: gasPalette, encoded: model("fukuoka-gas-holder-large", as: "fukuoka-gas-holder-701217745"), size: (34.04, 34.04, 35.81))
    // OSM way 804614370.
    static let gasHolder804614370 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-804614370", map: "fukuoka", latitude: 33.6175508, longitude: 130.4109335,
        palette: gasPalette, encoded: model("fukuoka-gas-holder-large", as: "fukuoka-gas-holder-804614370"), size: (34.04, 34.04, 35.81))
    // OSM way 804614371.
    static let gasHolder804614371 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-804614371", map: "fukuoka", latitude: 33.6172914, longitude: 130.4103376,
        palette: gasPalette, encoded: model("fukuoka-gas-holder-large", as: "fukuoka-gas-holder-804614371"), size: (34.04, 34.04, 35.81))
    // OSM way 727497179.
    static let gasHolder727497179 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-727497179", map: "fukuoka", latitude: 33.6174083, longitude: 130.4095921,
        palette: gasPalette, encoded: model("fukuoka-gas-holder", as: "fukuoka-gas-holder-727497179"), size: (20.42, 20.42, 21.49))
    // OSM way 727497184.
    static let gasHolder727497184 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-727497184", map: "fukuoka", latitude: 33.618175, longitude: 130.4080086,
        palette: gasPalette, encoded: model("fukuoka-gas-holder", as: "fukuoka-gas-holder-727497184"), size: (20.42, 20.42, 21.49))
    // OSM way 727497186.
    static let gasHolder727497186 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-727497186", map: "fukuoka", latitude: 33.6179704, longitude: 130.4082629,
        palette: gasPalette, encoded: model("fukuoka-gas-holder", as: "fukuoka-gas-holder-727497186"), size: (20.42, 20.42, 21.49))
    // OSM way 727497187.
    static let gasHolder727497187 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-727497187", map: "fukuoka", latitude: 33.6177085, longitude: 130.4081247,
        palette: gasPalette, encoded: model("fukuoka-gas-holder", as: "fukuoka-gas-holder-727497187"), size: (20.42, 20.42, 21.49))
    // OSM way 727497188.
    static let gasHolder727497188 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-727497188", map: "fukuoka", latitude: 33.6179517, longitude: 130.4079304,
        palette: gasPalette, encoded: model("fukuoka-gas-holder", as: "fukuoka-gas-holder-727497188"), size: (20.42, 20.42, 21.49))
    // OSM way 804613317.
    static let gasHolder804613317 = Map3DLandmarkRegistration(id: "fukuoka-gas-holder-804613317", map: "fukuoka", latitude: 33.6182178, longitude: 130.4083552,
        palette: gasPalette, encoded: model("fukuoka-gas-holder", as: "fukuoka-gas-holder-804613317"), size: (20.42, 20.42, 21.49))
    // OSM way 292979178.
    static let waterTower292979178 = Map3DLandmarkRegistration(id: "fukuoka-water-tower-292979178", map: "fukuoka", latitude: 33.6486585, longitude: 130.4243316,
        palette: waterPalette, encoded: model("fukuoka-water-tower", as: "fukuoka-water-tower-292979178"), size: (11.53, 11.28, 20.98))
    // OSM way 603581064.
    static let waterTower603581064 = Map3DLandmarkRegistration(id: "fukuoka-water-tower-603581064", map: "fukuoka", latitude: 33.5316659, longitude: 130.4366693,
        palette: waterPalette, encoded: model("fukuoka-water-tower", as: "fukuoka-water-tower-603581064"), size: (11.53, 11.28, 20.98))
    // OSM way 715740961.
    static let waterTower715740961 = Map3DLandmarkRegistration(id: "fukuoka-water-tower-715740961", map: "fukuoka", latitude: 33.5448639, longitude: 130.3850522,
        palette: waterPalette, encoded: model("fukuoka-water-tower", as: "fukuoka-water-tower-715740961"), size: (11.53, 11.28, 20.98))
    // OSM way 964202521.
    static let waterTower964202521 = Map3DLandmarkRegistration(id: "fukuoka-water-tower-964202521", map: "fukuoka", latitude: 33.5620819, longitude: 130.3279561,
        palette: waterPalette, encoded: model("fukuoka-water-tower", as: "fukuoka-water-tower-964202521"), size: (11.53, 11.28, 20.98))
    // OSM way 964502374.
    static let waterTower964502374 = Map3DLandmarkRegistration(id: "fukuoka-water-tower-964502374", map: "fukuoka", latitude: 33.5475462, longitude: 130.3815321,
        palette: waterPalette, encoded: model("fukuoka-water-tower", as: "fukuoka-water-tower-964502374"), size: (11.53, 11.28, 20.98))
    // OSM way 1175768613 (油山団地給水塔).
    static let waterTower1175768613 = Map3DLandmarkRegistration(id: "fukuoka-water-tower-1175768613", map: "fukuoka", latitude: 33.5356158, longitude: 130.3779566,
        palette: waterPalette, encoded: model("fukuoka-water-tower", as: "fukuoka-water-tower-1175768613"), size: (11.53, 11.28, 20.98))
    // OSM way 1418044218 (原団地給水塔, 30 m).
    static let waterTower1418044218 = Map3DLandmarkRegistration(id: "fukuoka-water-tower-1418044218", map: "fukuoka", latitude: 33.5715036, longitude: 130.3427531,
        palette: waterPalette, encoded: model("fukuoka-water-tower-tall", as: "fukuoka-water-tower-1418044218"), size: (16.47, 16.12, 29.97))
}
