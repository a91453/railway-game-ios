import GameCore

// Real-world maps (Stage E2, ARCHITECTURE decision 50): a game's map laid
// over the Earth with its middle at the world's ``GeoAnchor``, and Apple's
// map drawn under the railway. GameCore keeps only the anchor; how the world
// lies over the Earth is decided here, and the map under it is the app's
// (MapKit).
//
// The references keep their games on the Earth directly: `Ci/`'s stations
// are latitudes and longitudes (GCJ-02 inside mainland China, converted to
// WGS-84 for its MapLibre engine, `gameGcjToOsmWgs`), and `Railway/`'s are
// the WGS-84 points of OpenStreetMap. Here the world stays in its own
// whole units and only its middle is pinned to the Earth: the rules never
// see a latitude.

extension GeoAnchor {
    /// Ten-millionths of a degree in a degree.
    public static let unitsPerDegree = 10_000_000.0

    /// The latitude in degrees, north positive.
    public var latitudeDegrees: Double {
        Double(latitude) / Self.unitsPerDegree
    }

    /// The longitude in degrees, east positive.
    public var longitudeDegrees: Double {
        Double(longitude) / Self.unitsPerDegree
    }

    /// The anchor nearest `latitude`° north and `longitude`° east: rounded
    /// to whole ten-millionths, with the longitude brought into −180° up to
    /// 180° (a map that has been panned round the Earth can report 190°).
    /// `nil` for a latitude beyond ±90°, or for a value that is not a
    /// number.
    public init?(latitudeDegrees latitude: Double, longitudeDegrees longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90 else { return nil }
        let turn = 360 * Self.unitsPerDegree
        var east = (longitude * Self.unitsPerDegree).rounded().truncatingRemainder(dividingBy: turn)
        if east >= turn / 2 { east -= turn }
        if east < -turn / 2 { east += turn }
        self.init(latitude: Int64((latitude * Self.unitsPerDegree).rounded()), longitude: Int64(east))
    }
}

/// How a real-world game's world lies over the Earth: the middle of its
/// bounds at the anchor, x east and y south, a world unit 1/64 m
/// (``WorldCoordinate/unitsPerMetre``).
///
/// The app's map under the world is Web Mercator (Apple's maps, as the
/// references' MapLibre and AMap): it draws a metre of the world as a metre
/// of the Earth at the anchor's latitude, all over the map, so the railway
/// and the map under it line up everywhere. Away from the anchor's
/// latitude a world metre is a little more or less than a metre on the
/// ground (Mercator's scale changes with latitude): on a 16 km map at most
/// 0.06% at Taipei's latitude, 0.22% at 60°.
public struct RealWorldFrame: Hashable, Sendable {
    public let anchor: GeoAnchor
    /// The world point at the anchor, in world units: the middle of the map.
    public let middleX: Double
    public let middleY: Double

    /// A world reaching as far as `bounds`, its middle at `anchor`.
    public init(anchor: GeoAnchor, bounds: WorldBounds) {
        self.anchor = anchor
        let region = WorldRegion(bounds: bounds)
        middleX = (region.minX + region.maxX) / 2
        middleY = (region.minY + region.maxY) / 2
    }

    /// `world`'s frame, or `nil` for a blank map.
    public init?(world: GameWorld) {
        guard let anchor = world.geoAnchor else { return nil }
        self.init(anchor: anchor, bounds: world.bounds)
    }

    /// How far the world point (`x`, `y`) lies east and south of the
    /// anchor, in metres.
    public func metresFromAnchor(worldX x: Double, worldY y: Double) -> (east: Double, south: Double) {
        let unitsPerMetre = Double(WorldCoordinate.unitsPerMetre)
        return ((x - middleX) / unitsPerMetre, (y - middleY) / unitsPerMetre)
    }

    /// The world point `east` and `south` metres from the anchor, in world
    /// units.
    public func worldPosition(east: Double, south: Double) -> (x: Double, y: Double) {
        let unitsPerMetre = Double(WorldCoordinate.unitsPerMetre)
        return (middleX + east * unitsPerMetre, middleY + south * unitsPerMetre)
    }

    /// Half the width and height of a world reaching as far as `bounds`, in
    /// metres: how far its edges lie from the anchor. A new game's world is
    /// 16,384 m a side, so 8,192 m.
    public static func halfExtent(of bounds: WorldBounds) -> (east: Double, south: Double) {
        let region = WorldRegion(bounds: bounds)
        let unitsPerMetre = Double(WorldCoordinate.unitsPerMetre)
        return (region.width / 2 / unitsPerMetre, region.height / 2 / unitsPerMetre)
    }
}

/// A place a real-world game can start at: the middle of its map, before
/// the player moves it.
///
/// The places are the references' own, not Apple's (Apple's map data may
/// not be kept, Attachment 6 §2.5 of the Apple Developer Program License
/// Agreement): the cities of `Ci/`'s `CITIES`, at its `center`, and the
/// Taiwan Railway stations of `Railway/`'s `data/tra.json`, from
/// OpenStreetMap. A place the player finds with the map's search is not
/// kept either: only the middle of the map the player settles on.
public struct RealWorldPlace: Identifiable, Hashable, Sendable {
    /// Where on the Earth the list groups it.
    public enum Region: CaseIterable, Hashable, Sendable {
        case taiwan
        case asia
        case europe
        case americas
        case oceaniaAndAfrica

        public func name(in language: DisplayLanguage) -> String {
            switch self {
            case .taiwan: language.text("Taiwan", "台灣")
            case .asia: language.text("Asia", "亞洲")
            case .europe: language.text("Europe", "歐洲")
            case .americas: language.text("Americas", "美洲")
            case .oceaniaAndAfrica: language.text("Oceania and Africa", "大洋洲與非洲")
            }
        }
    }

    /// The reference's key: `Ci/`'s city key, or `tra-` and the station.
    public let id: String
    public let region: Region
    public let anchor: GeoAnchor
    let english: String
    let chinese: String

    public func name(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    init(_ id: String, _ region: Region, _ english: String, _ chinese: String, latitude: Int64, longitude: Int64) {
        guard let anchor = GeoAnchor(latitude: latitude, longitude: longitude) else {
            preconditionFailure("\(id) is not on the Earth")
        }
        self.id = id
        self.region = region
        self.anchor = anchor
        self.english = english
        self.chinese = chinese
    }

    /// Every place, by region in ``Region``'s order and within a region in
    /// the reference's order.
    public static let all: [RealWorldPlace] = Region.allCases.flatMap { region in
        (taiwan + ciCities).filter { $0.region == region }
    }

    /// Where a real-world game starts when the player picks nothing:
    /// Taipei Main Station.
    public static let standard = taiwan[1]

    /// `Railway/site_archive_clean/data/tra.json`: the first station of each
    /// name along the Taiwan Railway lines, north to south and round the
    /// east (OpenStreetMap's points, seven decimals).
    static let taiwan: [RealWorldPlace] = [
        RealWorldPlace("tra-keelung", .taiwan, "Keelung", "基隆", latitude: 251_330_324, longitude: 1_217_392_299),
        RealWorldPlace("tra-taipei", .taiwan, "Taipei", "臺北", latitude: 250_479_308, longitude: 1_215_170_046),
        RealWorldPlace("tra-taoyuan", .taiwan, "Taoyuan", "桃園", latitude: 249_887_260, longitude: 1_213_137_769),
        RealWorldPlace("tra-hsinchu", .taiwan, "Hsinchu", "新竹", latitude: 248_014_026, longitude: 1_209_716_780),
        RealWorldPlace("tra-taichung", .taiwan, "Taichung", "臺中", latitude: 241_370_662, longitude: 1_206_868_667),
        RealWorldPlace("tra-chiayi", .taiwan, "Chiayi", "嘉義", latitude: 234_799_042, longitude: 1_204_415_839),
        RealWorldPlace("tra-tainan", .taiwan, "Tainan", "臺南", latitude: 229_972_146, longitude: 1_202_130_434),
        RealWorldPlace("tra-kaohsiung", .taiwan, "Kaohsiung", "高雄", latitude: 226_395_321, longitude: 1_203_025_585),
        RealWorldPlace("tra-yilan", .taiwan, "Yilan", "宜蘭", latitude: 247_545_601, longitude: 1_217_583_109),
        RealWorldPlace("tra-hualien", .taiwan, "Hualien", "花蓮", latitude: 239_926_399, longitude: 1_216_009_524),
        RealWorldPlace("tra-taitung", .taiwan, "Taitung", "臺東", latitude: 227_934_597, longitude: 1_211_224_316),
    ]

    /// `Ci/`'s `CITIES` (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`),
    /// in its order: each city's `center`, four decimals. Its names are in
    /// Simplified Chinese; these are Taiwan's.
    static let ciCities: [RealWorldPlace] = [
        RealWorldPlace("shanghai", .asia, "Shanghai", "上海", latitude: 312_304_000, longitude: 1_214_737_000),
        RealWorldPlace("beijing", .asia, "Beijing", "北京", latitude: 399_042_000, longitude: 1_164_074_000),
        RealWorldPlace("wuhan", .asia, "Wuhan", "武漢", latitude: 305_928_000, longitude: 1_143_055_000),
        RealWorldPlace("guangzhou", .asia, "Guangzhou", "廣州", latitude: 231_291_000, longitude: 1_132_644_000),
        RealWorldPlace("chengdu", .asia, "Chengdu", "成都", latitude: 305_728_000, longitude: 1_040_668_000),
        RealWorldPlace("shenzhen", .asia, "Shenzhen", "深圳", latitude: 225_431_000, longitude: 1_140_579_000),
        RealWorldPlace("nanjing", .asia, "Nanjing", "南京", latitude: 320_603_000, longitude: 1_187_969_000),
        RealWorldPlace("wuxi", .asia, "Wuxi", "無錫", latitude: 314_912_000, longitude: 1_203_119_000),
        RealWorldPlace("suzhou", .asia, "Suzhou", "蘇州", latitude: 312_989_000, longitude: 1_205_853_000),
        RealWorldPlace("zhongshan", .asia, "Zhongshan", "中山", latitude: 225_176_000, longitude: 1_133_928_000),
        RealWorldPlace("zhuhai", .asia, "Zhuhai", "珠海", latitude: 222_707_000, longitude: 1_135_767_000),
        RealWorldPlace("dongguan", .asia, "Dongguan", "東莞", latitude: 230_218_000, longitude: 1_137_518_000),
        RealWorldPlace("nanning", .asia, "Nanning", "南寧", latitude: 228_170_000, longitude: 1_083_660_000),
        RealWorldPlace("urumqi", .asia, "Ürümqi", "烏魯木齊", latitude: 438_256_000, longitude: 876_168_000),
        RealWorldPlace("dalian", .asia, "Dalian", "大連", latitude: 389_140_000, longitude: 1_216_147_000),
        RealWorldPlace("shenyang", .asia, "Shenyang", "瀋陽", latitude: 418_057_000, longitude: 1_234_315_000),
        RealWorldPlace("changchun", .asia, "Changchun", "長春", latitude: 438_160_000, longitude: 1_253_235_000),
        RealWorldPlace("harbin", .asia, "Harbin", "哈爾濱", latitude: 457_567_000, longitude: 1_266_425_000),
        RealWorldPlace("hangzhou", .asia, "Hangzhou", "杭州", latitude: 302_741_000, longitude: 1_201_551_000),
        RealWorldPlace("chongqing", .asia, "Chongqing", "重慶", latitude: 294_316_000, longitude: 1_069_123_000),
        RealWorldPlace("foshan", .asia, "Foshan", "佛山", latitude: 230_215_000, longitude: 1_131_214_000),
        RealWorldPlace("xian", .asia, "Xi’an", "西安", latitude: 343_416_000, longitude: 1_089_398_000),
        RealWorldPlace("tianjin", .asia, "Tianjin", "天津", latitude: 393_434_000, longitude: 1_173_616_000),
        RealWorldPlace("xiamen", .asia, "Xiamen", "廈門", latitude: 244_798_000, longitude: 1_180_819_000),
        RealWorldPlace("zhengzhou", .asia, "Zhengzhou", "鄭州", latitude: 347_466_000, longitude: 1_136_254_000),
        RealWorldPlace("qingdao", .asia, "Qingdao", "青島", latitude: 360_671_000, longitude: 1_203_826_000),
        RealWorldPlace("xianyang", .asia, "Xianyang", "咸陽", latitude: 343_296_000, longitude: 1_087_092_000),
        RealWorldPlace("singapore", .asia, "Singapore", "新加坡", latitude: 13_521_000, longitude: 1_038_198_000),
        RealWorldPlace("hongkong", .asia, "Hong Kong", "香港", latitude: 223_193_000, longitude: 1_141_694_000),
        RealWorldPlace("macau", .asia, "Macau", "澳門", latitude: 221_987_000, longitude: 1_135_439_000),
        RealWorldPlace("madrid", .europe, "Madrid", "馬德里", latitude: 404_168_000, longitude: -37_038_000),
        RealWorldPlace("paris", .europe, "Paris", "巴黎", latitude: 488_566_000, longitude: 23_522_000),
        RealWorldPlace("london", .europe, "London", "倫敦", latitude: 515_074_000, longitude: -1_278_000),
        RealWorldPlace("vancouver", .americas, "Vancouver", "溫哥華", latitude: 492_827_000, longitude: -1_231_207_000),
        RealWorldPlace("toronto", .americas, "Toronto", "多倫多", latitude: 436_532_000, longitude: -793_832_000),
        RealWorldPlace("bayarea", .americas, "San Francisco Bay Area", "舊金山灣區", latitude: 377_749_000, longitude: -1_224_194_000),
        RealWorldPlace("losangeles", .americas, "Los Angeles", "洛杉磯", latitude: 340_522_000, longitude: -1_182_437_000),
        RealWorldPlace("chicago", .americas, "Chicago", "芝加哥", latitude: 418_781_000, longitude: -876_298_000),
        RealWorldPlace("miami", .americas, "Miami", "邁阿密", latitude: 257_617_000, longitude: -801_918_000),
        RealWorldPlace("boston", .americas, "Boston", "波士頓", latitude: 423_601_000, longitude: -710_589_000),
        RealWorldPlace("washington", .americas, "Washington", "華盛頓", latitude: 389_072_000, longitude: -770_369_000),
        RealWorldPlace("newyork", .americas, "New York", "紐約", latitude: 407_128_000, longitude: -740_060_000),
        RealWorldPlace("buenosaires", .americas, "Buenos Aires", "布宜諾斯艾利斯", latitude: -346_037_000, longitude: -583_816_000),
        RealWorldPlace("melbourne", .oceaniaAndAfrica, "Melbourne", "墨爾本", latitude: -378_136_000, longitude: 1_449_631_000),
        RealWorldPlace("mumbai", .asia, "Mumbai", "孟買", latitude: 190_760_000, longitude: 728_777_000),
        RealWorldPlace("lagos", .oceaniaAndAfrica, "Lagos", "拉哥斯", latitude: 65_244_000, longitude: 33_792_000),
        RealWorldPlace("berlin", .europe, "Berlin", "柏林", latitude: 525_200_000, longitude: 134_050_000),
        RealWorldPlace("rome", .europe, "Rome", "羅馬", latitude: 419_028_000, longitude: 124_964_000),
        RealWorldPlace("munich", .europe, "Munich", "慕尼黑", latitude: 481_371_000, longitude: 115_754_000),
        RealWorldPlace("milan", .europe, "Milan", "米蘭", latitude: 454_642_000, longitude: 91_900_000),
        RealWorldPlace("copenhagen", .europe, "Copenhagen", "哥本哈根", latitude: 556_761_000, longitude: 125_683_000),
        RealWorldPlace("stockholm", .europe, "Stockholm", "斯德哥爾摩", latitude: 593_293_000, longitude: 180_686_000),
        RealWorldPlace("seoul", .asia, "Seoul", "首爾", latitude: 375_665_000, longitude: 1_269_780_000),
    ]
}
