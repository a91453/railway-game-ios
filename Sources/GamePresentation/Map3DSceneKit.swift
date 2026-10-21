import Foundation

/// Native, texture-free models corresponding to the 156 scene-kit subjects.
/// Coordinates match Map3DModelPack: +x front, +y left, +z up, metres.
/// PNGs supply subject labels only; all sides are built from real geometry.
public enum Map3DSceneKit {
    public enum Family: String, CaseIterable, Sendable {
        case traModern
        case metro
        case station
        case railway
        case traClassic
        case lightRail
        case house
        case apartment
        case tower
        case traditional
        case retail
        case food
        case office
        case civic
        case industrial
        case park
        case street
        case ground
    }
    public struct Asset: Sendable {
        public let id: String
        public let name: String
        public let category: String
        public let family: Family
        public let variant: Int
    }
    public static let assets: [Asset] = [
        Asset(id: "01_TRA_modern_3x2-01", name: "EMU3000", category: "railway", family: .traModern, variant: 0),
        Asset(id: "01_TRA_modern_3x2-02", name: "普悠瑪 TEMU2000", category: "railway", family: .traModern, variant: 1),
        Asset(id: "01_TRA_modern_3x2-03", name: "太魯閣 TEMU1000", category: "railway", family: .traModern, variant: 2),
        Asset(id: "01_TRA_modern_3x2-04", name: "EMU800", category: "railway", family: .traModern, variant: 3),
        Asset(id: "01_TRA_modern_3x2-05", name: "EMU900", category: "railway", family: .traModern, variant: 4),
        Asset(id: "01_TRA_modern_3x2-06", name: "E1000 推拉式自強號", category: "railway", family: .traModern, variant: 5),
        Asset(id: "02_HSR_MRT_3x2-01", name: "高鐵 700T", category: "railway", family: .metro, variant: 0),
        Asset(id: "02_HSR_MRT_3x2-02", name: "台北捷運 C381", category: "railway", family: .metro, variant: 1),
        Asset(id: "02_HSR_MRT_3x2-03", name: "文湖線", category: "railway", family: .metro, variant: 2),
        Asset(id: "02_HSR_MRT_3x2-04", name: "高雄捷運", category: "railway", family: .metro, variant: 3),
        Asset(id: "02_HSR_MRT_3x2-05", name: "機場捷運直達車", category: "railway", family: .metro, variant: 4),
        Asset(id: "02_HSR_MRT_3x2-06", name: "台中捷運", category: "railway", family: .metro, variant: 5),
        Asset(id: "03_stations_3x3-01", name: "復古台鐵車站", category: "railway", family: .station, variant: 0),
        Asset(id: "03_stations_3x3-02", name: "現代台鐵車站", category: "railway", family: .station, variant: 1),
        Asset(id: "03_stations_3x3-03", name: "高鐵車站", category: "railway", family: .station, variant: 2),
        Asset(id: "03_stations_3x3-04", name: "地下捷運入口", category: "railway", family: .station, variant: 3),
        Asset(id: "03_stations_3x3-05", name: "高架捷運站", category: "railway", family: .station, variant: 4),
        Asset(id: "03_stations_3x3-06", name: "輕軌站", category: "railway", family: .station, variant: 5),
        Asset(id: "03_stations_3x3-07", name: "島式月台", category: "railway", family: .station, variant: 6),
        Asset(id: "03_stations_3x3-08", name: "跨線天橋", category: "railway", family: .station, variant: 7),
        Asset(id: "03_stations_3x3-09", name: "維修車庫", category: "railway", family: .station, variant: 8),
        Asset(id: "04_tracks_props_4x3-01", name: "直軌 A", category: "railway", family: .railway, variant: 0),
        Asset(id: "04_tracks_props_4x3-02", name: "直軌 B", category: "railway", family: .railway, variant: 1),
        Asset(id: "04_tracks_props_4x3-03", name: "彎軌", category: "railway", family: .railway, variant: 2),
        Asset(id: "04_tracks_props_4x3-04", name: "道岔", category: "railway", family: .railway, variant: 3),
        Asset(id: "04_tracks_props_4x3-05", name: "高架橋", category: "railway", family: .railway, variant: 4),
        Asset(id: "04_tracks_props_4x3-06", name: "鋼構鐵橋", category: "railway", family: .railway, variant: 5),
        Asset(id: "04_tracks_props_4x3-07", name: "隧道入口", category: "railway", family: .railway, variant: 6),
        Asset(id: "04_tracks_props_4x3-08", name: "平交道", category: "railway", family: .railway, variant: 7),
        Asset(id: "04_tracks_props_4x3-09", name: "鐵路號誌", category: "railway", family: .railway, variant: 8),
        Asset(id: "04_tracks_props_4x3-10", name: "電車線架", category: "railway", family: .railway, variant: 9),
        Asset(id: "04_tracks_props_4x3-11", name: "止衝擋", category: "railway", family: .railway, variant: 10),
        Asset(id: "04_tracks_props_4x3-12", name: "電氣設備箱", category: "railway", family: .railway, variant: 11),
        Asset(id: "05_TRA_classic_3x2-01", name: "EMU500", category: "railway", family: .traClassic, variant: 0),
        Asset(id: "05_TRA_classic_3x2-02", name: "EMU700", category: "railway", family: .traClassic, variant: 1),
        Asset(id: "05_TRA_classic_3x2-03", name: "DR1000", category: "railway", family: .traClassic, variant: 2),
        Asset(id: "05_TRA_classic_3x2-04", name: "DR3100", category: "railway", family: .traClassic, variant: 3),
        Asset(id: "05_TRA_classic_3x2-05", name: "R20", category: "railway", family: .traClassic, variant: 4),
        Asset(id: "05_TRA_classic_3x2-06", name: "R200", category: "railway", family: .traClassic, variant: 5),
        Asset(id: "06_more_transit_3x2-01", name: "高雄輕軌", category: "railway", family: .lightRail, variant: 0),
        Asset(id: "06_more_transit_3x2-02", name: "淡海輕軌", category: "railway", family: .lightRail, variant: 1),
        Asset(id: "06_more_transit_3x2-03", name: "安坑輕軌", category: "railway", family: .lightRail, variant: 2),
        Asset(id: "06_more_transit_3x2-04", name: "機場捷運普通車", category: "railway", family: .lightRail, variant: 3),
        Asset(id: "06_more_transit_3x2-05", name: "台北捷運 C301", category: "railway", family: .lightRail, variant: 4),
        Asset(id: "06_more_transit_3x2-06", name: "環狀線", category: "railway", family: .lightRail, variant: 5),
        Asset(id: "07_residential_low-01", name: "台灣透天住宅 01", category: "residential", family: .house, variant: 0),
        Asset(id: "07_residential_low-02", name: "台灣透天住宅 02", category: "residential", family: .house, variant: 1),
        Asset(id: "07_residential_low-03", name: "台灣透天住宅 03", category: "residential", family: .house, variant: 2),
        Asset(id: "07_residential_low-04", name: "台灣透天住宅 04", category: "residential", family: .house, variant: 3),
        Asset(id: "07_residential_low-05", name: "台灣透天住宅 05", category: "residential", family: .house, variant: 4),
        Asset(id: "07_residential_low-06", name: "台灣透天住宅 06", category: "residential", family: .house, variant: 5),
        Asset(id: "07_residential_low-07", name: "台灣透天住宅 07", category: "residential", family: .house, variant: 6),
        Asset(id: "07_residential_low-08", name: "台灣透天住宅 08", category: "residential", family: .house, variant: 7),
        Asset(id: "07_residential_low-09", name: "台灣透天住宅 09", category: "residential", family: .house, variant: 8),
        Asset(id: "08_residential_mid-01", name: "台灣中層公寓 01", category: "residential", family: .apartment, variant: 0),
        Asset(id: "08_residential_mid-02", name: "台灣中層公寓 02", category: "residential", family: .apartment, variant: 1),
        Asset(id: "08_residential_mid-03", name: "台灣中層公寓 03", category: "residential", family: .apartment, variant: 2),
        Asset(id: "08_residential_mid-04", name: "台灣中層公寓 04", category: "residential", family: .apartment, variant: 3),
        Asset(id: "08_residential_mid-05", name: "台灣中層公寓 05", category: "residential", family: .apartment, variant: 4),
        Asset(id: "08_residential_mid-06", name: "台灣中層公寓 06", category: "residential", family: .apartment, variant: 5),
        Asset(id: "08_residential_mid-07", name: "台灣中層公寓 07", category: "residential", family: .apartment, variant: 6),
        Asset(id: "08_residential_mid-08", name: "台灣中層公寓 08", category: "residential", family: .apartment, variant: 7),
        Asset(id: "08_residential_mid-09", name: "台灣中層公寓 09", category: "residential", family: .apartment, variant: 8),
        Asset(id: "09_residential_high-01", name: "高層住宅社區 01", category: "residential", family: .tower, variant: 0),
        Asset(id: "09_residential_high-02", name: "高層住宅社區 02", category: "residential", family: .tower, variant: 1),
        Asset(id: "09_residential_high-03", name: "高層住宅社區 03", category: "residential", family: .tower, variant: 2),
        Asset(id: "09_residential_high-04", name: "高層住宅社區 04", category: "residential", family: .tower, variant: 3),
        Asset(id: "09_residential_high-05", name: "高層住宅社區 05", category: "residential", family: .tower, variant: 4),
        Asset(id: "09_residential_high-06", name: "高層住宅社區 06", category: "residential", family: .tower, variant: 5),
        Asset(id: "09_residential_high-07", name: "高層住宅社區 07", category: "residential", family: .tower, variant: 6),
        Asset(id: "09_residential_high-08", name: "高層住宅社區 08", category: "residential", family: .tower, variant: 7),
        Asset(id: "09_residential_high-09", name: "高層住宅社區 09", category: "residential", family: .tower, variant: 8),
        Asset(id: "10_traditional_houses-01", name: "傳統住宅與老街 01", category: "residential", family: .traditional, variant: 0),
        Asset(id: "10_traditional_houses-02", name: "傳統住宅與老街 02", category: "residential", family: .traditional, variant: 1),
        Asset(id: "10_traditional_houses-03", name: "傳統住宅與老街 03", category: "residential", family: .traditional, variant: 2),
        Asset(id: "10_traditional_houses-04", name: "傳統住宅與老街 04", category: "residential", family: .traditional, variant: 3),
        Asset(id: "10_traditional_houses-05", name: "傳統住宅與老街 05", category: "residential", family: .traditional, variant: 4),
        Asset(id: "10_traditional_houses-06", name: "傳統住宅與老街 06", category: "residential", family: .traditional, variant: 5),
        Asset(id: "10_traditional_houses-07", name: "傳統住宅與老街 07", category: "residential", family: .traditional, variant: 6),
        Asset(id: "10_traditional_houses-08", name: "傳統住宅與老街 08", category: "residential", family: .traditional, variant: 7),
        Asset(id: "10_traditional_houses-09", name: "傳統住宅與老街 09", category: "residential", family: .traditional, variant: 8),
        Asset(id: "11_retail_shops-01", name: "商店與站前店家 01", category: "commercial", family: .retail, variant: 0),
        Asset(id: "11_retail_shops-02", name: "商店與站前店家 02", category: "commercial", family: .retail, variant: 1),
        Asset(id: "11_retail_shops-03", name: "商店與站前店家 03", category: "commercial", family: .retail, variant: 2),
        Asset(id: "11_retail_shops-04", name: "商店與站前店家 04", category: "commercial", family: .retail, variant: 3),
        Asset(id: "11_retail_shops-05", name: "商店與站前店家 05", category: "commercial", family: .retail, variant: 4),
        Asset(id: "11_retail_shops-06", name: "商店與站前店家 06", category: "commercial", family: .retail, variant: 5),
        Asset(id: "11_retail_shops-07", name: "商店與站前店家 07", category: "commercial", family: .retail, variant: 6),
        Asset(id: "11_retail_shops-08", name: "商店與站前店家 08", category: "commercial", family: .retail, variant: 7),
        Asset(id: "11_retail_shops-09", name: "商店與站前店家 09", category: "commercial", family: .retail, variant: 8),
        Asset(id: "12_food_market-01", name: "餐飲與市場 01", category: "commercial", family: .food, variant: 0),
        Asset(id: "12_food_market-02", name: "餐飲與市場 02", category: "commercial", family: .food, variant: 1),
        Asset(id: "12_food_market-03", name: "餐飲與市場 03", category: "commercial", family: .food, variant: 2),
        Asset(id: "12_food_market-04", name: "餐飲與市場 04", category: "commercial", family: .food, variant: 3),
        Asset(id: "12_food_market-05", name: "餐飲與市場 05", category: "commercial", family: .food, variant: 4),
        Asset(id: "12_food_market-06", name: "餐飲與市場 06", category: "commercial", family: .food, variant: 5),
        Asset(id: "12_food_market-07", name: "餐飲與市場 07", category: "commercial", family: .food, variant: 6),
        Asset(id: "12_food_market-08", name: "餐飲與市場 08", category: "commercial", family: .food, variant: 7),
        Asset(id: "12_food_market-09", name: "餐飲與市場 09", category: "commercial", family: .food, variant: 8),
        Asset(id: "13_office_commerce-01", name: "商辦百貨與旅館 01", category: "commercial", family: .office, variant: 0),
        Asset(id: "13_office_commerce-02", name: "商辦百貨與旅館 02", category: "commercial", family: .office, variant: 1),
        Asset(id: "13_office_commerce-03", name: "商辦百貨與旅館 03", category: "commercial", family: .office, variant: 2),
        Asset(id: "13_office_commerce-04", name: "商辦百貨與旅館 04", category: "commercial", family: .office, variant: 3),
        Asset(id: "13_office_commerce-05", name: "商辦百貨與旅館 05", category: "commercial", family: .office, variant: 4),
        Asset(id: "13_office_commerce-06", name: "商辦百貨與旅館 06", category: "commercial", family: .office, variant: 5),
        Asset(id: "13_office_commerce-07", name: "商辦百貨與旅館 07", category: "commercial", family: .office, variant: 6),
        Asset(id: "13_office_commerce-08", name: "商辦百貨與旅館 08", category: "commercial", family: .office, variant: 7),
        Asset(id: "13_office_commerce-09", name: "商辦百貨與旅館 09", category: "commercial", family: .office, variant: 8),
        Asset(id: "14_public_services-01", name: "公共建築 01", category: "public", family: .civic, variant: 0),
        Asset(id: "14_public_services-02", name: "公共建築 02", category: "public", family: .civic, variant: 1),
        Asset(id: "14_public_services-03", name: "公共建築 03", category: "public", family: .civic, variant: 2),
        Asset(id: "14_public_services-04", name: "公共建築 04", category: "public", family: .civic, variant: 3),
        Asset(id: "14_public_services-05", name: "公共建築 05", category: "public", family: .civic, variant: 4),
        Asset(id: "14_public_services-06", name: "公共建築 06", category: "public", family: .civic, variant: 5),
        Asset(id: "14_public_services-07", name: "公共建築 07", category: "public", family: .civic, variant: 6),
        Asset(id: "14_public_services-08", name: "公共建築 08", category: "public", family: .civic, variant: 7),
        Asset(id: "14_public_services-09", name: "公共建築 09", category: "public", family: .civic, variant: 8),
        Asset(id: "15_industrial_logistics-01", name: "工業倉儲與物流 01", category: "industrial", family: .industrial, variant: 0),
        Asset(id: "15_industrial_logistics-02", name: "工業倉儲與物流 02", category: "industrial", family: .industrial, variant: 1),
        Asset(id: "15_industrial_logistics-03", name: "工業倉儲與物流 03", category: "industrial", family: .industrial, variant: 2),
        Asset(id: "15_industrial_logistics-04", name: "工業倉儲與物流 04", category: "industrial", family: .industrial, variant: 3),
        Asset(id: "15_industrial_logistics-05", name: "工業倉儲與物流 05", category: "industrial", family: .industrial, variant: 4),
        Asset(id: "15_industrial_logistics-06", name: "工業倉儲與物流 06", category: "industrial", family: .industrial, variant: 5),
        Asset(id: "15_industrial_logistics-07", name: "工業倉儲與物流 07", category: "industrial", family: .industrial, variant: 6),
        Asset(id: "15_industrial_logistics-08", name: "工業倉儲與物流 08", category: "industrial", family: .industrial, variant: 7),
        Asset(id: "15_industrial_logistics-09", name: "工業倉儲與物流 09", category: "industrial", family: .industrial, variant: 8),
        Asset(id: "16_parks_greenery-01", name: "公園與綠地模組 01", category: "landscape", family: .park, variant: 0),
        Asset(id: "16_parks_greenery-02", name: "公園與綠地模組 02", category: "landscape", family: .park, variant: 1),
        Asset(id: "16_parks_greenery-03", name: "公園與綠地模組 03", category: "landscape", family: .park, variant: 2),
        Asset(id: "16_parks_greenery-04", name: "公園與綠地模組 04", category: "landscape", family: .park, variant: 3),
        Asset(id: "16_parks_greenery-05", name: "公園與綠地模組 05", category: "landscape", family: .park, variant: 4),
        Asset(id: "16_parks_greenery-06", name: "公園與綠地模組 06", category: "landscape", family: .park, variant: 5),
        Asset(id: "16_parks_greenery-07", name: "公園與綠地模組 07", category: "landscape", family: .park, variant: 6),
        Asset(id: "16_parks_greenery-08", name: "公園與綠地模組 08", category: "landscape", family: .park, variant: 7),
        Asset(id: "16_parks_greenery-09", name: "公園與綠地模組 09", category: "landscape", family: .park, variant: 8),
        Asset(id: "17_street_props-01", name: "街景與屋頂配件 01", category: "props", family: .street, variant: 0),
        Asset(id: "17_street_props-02", name: "街景與屋頂配件 02", category: "props", family: .street, variant: 1),
        Asset(id: "17_street_props-03", name: "街景與屋頂配件 03", category: "props", family: .street, variant: 2),
        Asset(id: "17_street_props-04", name: "街景與屋頂配件 04", category: "props", family: .street, variant: 3),
        Asset(id: "17_street_props-05", name: "街景與屋頂配件 05", category: "props", family: .street, variant: 4),
        Asset(id: "17_street_props-06", name: "街景與屋頂配件 06", category: "props", family: .street, variant: 5),
        Asset(id: "17_street_props-07", name: "街景與屋頂配件 07", category: "props", family: .street, variant: 6),
        Asset(id: "17_street_props-08", name: "街景與屋頂配件 08", category: "props", family: .street, variant: 7),
        Asset(id: "17_street_props-09", name: "街景與屋頂配件 09", category: "props", family: .street, variant: 8),
        Asset(id: "17_street_props-10", name: "街景與屋頂配件 10", category: "props", family: .street, variant: 9),
        Asset(id: "17_street_props-11", name: "街景與屋頂配件 11", category: "props", family: .street, variant: 10),
        Asset(id: "17_street_props-12", name: "街景與屋頂配件 12", category: "props", family: .street, variant: 11),
        Asset(id: "18_roads_plazas-01", name: "道路與站前鋪面 01", category: "ground", family: .ground, variant: 0),
        Asset(id: "18_roads_plazas-02", name: "道路與站前鋪面 02", category: "ground", family: .ground, variant: 1),
        Asset(id: "18_roads_plazas-03", name: "道路與站前鋪面 03", category: "ground", family: .ground, variant: 2),
        Asset(id: "18_roads_plazas-04", name: "道路與站前鋪面 04", category: "ground", family: .ground, variant: 3),
        Asset(id: "18_roads_plazas-05", name: "道路與站前鋪面 05", category: "ground", family: .ground, variant: 4),
        Asset(id: "18_roads_plazas-06", name: "道路與站前鋪面 06", category: "ground", family: .ground, variant: 5),
        Asset(id: "18_roads_plazas-07", name: "道路與站前鋪面 07", category: "ground", family: .ground, variant: 6),
        Asset(id: "18_roads_plazas-08", name: "道路與站前鋪面 08", category: "ground", family: .ground, variant: 7),
        Asset(id: "18_roads_plazas-09", name: "道路與站前鋪面 09", category: "ground", family: .ground, variant: 8),
    ]

    public static func asset(id: String) -> Asset? { assets.first { $0.id == id } }

    /// Build on demand; callers retain models they place repeatedly.
    public static func model(for asset: Asset) -> Map3DModelPack.Model {
        var builder = SceneKitBuilder()
        switch asset.family {
        case .traModern, .metro, .traClassic, .lightRail: builder.train(asset)
        case .house, .apartment, .tower, .traditional, .retail, .food, .office, .civic, .industrial: builder.building(asset)
        case .station: builder.station(asset.variant)
        case .railway: builder.railway(asset.variant)
        case .park: builder.park(asset.variant)
        case .street: builder.street(asset.variant)
        case .ground: builder.ground(asset.variant)
        }
        return .flat(named: asset.id, from: builder.mesh)
    }
}

extension Map3DModelPack {
    /// A pack the native renderer can index normally, optionally alongside
    /// the existing trains and street furniture. The standard pack is unchanged.
    public init(sceneKit assets: [Map3DSceneKit.Asset], includeStandard: Bool = true) {
        models = (includeStandard ? Self.standard.models : []) + assets.map { Map3DSceneKit.model(for: $0) }
    }
}
