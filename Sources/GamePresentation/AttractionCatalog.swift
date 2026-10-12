import GameCore

// The sights of Taiwan a real-world game starts with (ARCHITECTURE decision
// 174). The list is OpenWorld's `destination-catalog.js`
// (`OpenWorld/reference_snapshot/play/src/world/destination-catalog.js` of
// the owner's reference repository) without the places a railway cannot
// reach (the offshore islands) and the invented ones, with the hot springs
// and the Pingxi sky lanterns added; the places are put on the map by
// `tools/tourism-spots/build_tourism_spots.py` from OpenStreetMap
// (ODbL 1.0), which writes `tools/tourism-spots/taiwan_attractions.json`;
// `AttractionCatalogTests` checks this table against that file. It is Swift
// rather than a resource because it is 25 short rows every new game reads.

public enum AttractionCatalog {
    /// One place: its reference key, names, kind, rating in hundredths of a
    /// star, and where it is on the Earth in degrees.
    public struct Spot: Hashable, Sendable {
        public let id: String
        public let name: String
        public let englishName: String
        public let kind: AttractionKind
        public let stars: Int
        public let latitude: Double
        public let longitude: Double

        init(_ id: String, _ name: String, _ englishName: String, _ kind: AttractionKind, _ stars: Int, _ latitude: Double, _ longitude: Double) {
            self.id = id
            self.name = name
            self.englishName = englishName
            self.kind = kind
            self.stars = stars
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public static let spots: [Spot] = [
        Spot("s01", "墾丁・小灣", "Kenting Xiaowan", .coast, 400, 21.94509, 120.79897),
        Spot("s02", "九份", "Jiufen", .town, 400, 25.10873, 121.84357),
        Spot("s04", "清水斷崖", "Qingshui Cliff", .mountain, 400, 24.21887, 121.68914),
        Spot("s06", "日月潭", "Sun Moon Lake", .mountain, 450, 23.85472, 120.91679),
        Spot("s07", "阿里山", "Alishan", .mountain, 450, 23.50863, 120.80127),
        Spot("s08", "太魯閣", "Taroko", .mountain, 450, 24.1555, 121.62163),
        Spot("s09", "野柳", "Yehliu", .coast, 350, 25.20535, 121.69142),
        Spot("s11", "合歡山", "Hehuanshan", .mountain, 350, 24.13204, 121.29521),
        Spot("s12", "高美濕地", "Gaomei Wetlands", .coast, 350, 24.31111, 120.56278),
        Spot("s15", "池上伯朗大道", "Chishang Brown Avenue", .mountain, 300, 23.1243, 121.2208),
        Spot("s16", "七星潭", "Qixingtan", .coast, 300, 24.03844, 121.6242),
        Spot("s17", "陽明山擎天崗", "Qingtiangang", .mountain, 300, 25.16498, 121.57558),
        Spot("s18", "清境", "Qingjing", .mountain, 350, 24.04585, 121.15662),
        Spot("s20", "玉山群峰", "Yushan", .mountain, 400, 23.54289, 120.90859),
        Spot("s21", "遠雄海洋公園", "Farglory Ocean Park", .town, 300, 23.90155, 121.60149),
        Spot("s23", "陶朱隱園", "Taozhu Yinyuan", .town, 300, 25.0386, 121.5462),
        Spot("s25", "淡江大橋", "Tamsui River Bridge", .town, 250, 25.1744, 121.431),
        Spot("s26", "麗寶賽車場", "Lihpao Racing Park", .town, 250, 24.32392, 120.69589),
        Spot("s27", "Xpark・水族探索", "Xpark", .town, 350, 25.01713, 121.21404),
        Spot("h01", "北投溫泉", "Beitou Hot Springs", .hotSpring, 350, 25.13661, 121.50713),
        Spot("h02", "烏來溫泉", "Wulai Hot Springs", .hotSpring, 350, 24.86416, 121.55144),
        Spot("h03", "礁溪溫泉", "Jiaoxi Hot Springs", .hotSpring, 350, 24.67, 121.77),
        Spot("h04", "關子嶺溫泉", "Guanziling Hot Springs", .hotSpring, 300, 23.33952, 120.50412),
        Spot("h05", "四重溪溫泉", "Sichongxi Hot Springs", .hotSpring, 300, 22.08335, 120.73428),
        Spot("p01", "平溪天燈", "Pingxi Sky Lanterns", .town, 350, 25.04266, 121.77678),
    ]

    /// The spots that lie inside a world of `bounds` laid over the Earth as
    /// `frame` says, as attractions numbered from 1 in the catalog's order.
    /// Empty away from Taiwan.
    public static func attractions(in frame: RealWorldFrame, bounds: WorldBounds, only ids: Set<String>? = nil) -> [Attraction] {
        var found: [Attraction] = []
        for spot in spots where ids?.contains(spot.id) ?? true {
            let position = frame.worldPosition(latitude: spot.latitude, longitude: spot.longitude)
            guard position.x >= 0, position.y >= 0, position.x < Double(bounds.width), position.y < Double(bounds.height) else { continue }
            found.append(Attraction(
                id: AttractionID(rawValue: found.count + 1), name: spot.name, englishName: spot.englishName,
                point: PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded())), kind: spot.kind, baseStars: spot.stars
            ))
        }
        return found
    }
}
