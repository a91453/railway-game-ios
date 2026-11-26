// Weather, typhoons and the fuel price (ARCHITECTURE decision 162, the
// second step of `docs/research/DISRUPTION_STUDY.md` plan B), on the
// switch and level of decision 154 (``Disruptions``).
//
// After the owner's `Ci/` reference:
//
// - `Ci/reference_snapshot/lib/aviation_disruptions__q_dc8f79f5de24b024.js`
//   closes a region's airports for weather (`airportClosed`), a typhoon in
//   Taiwan's and southern China's regions, and raises or lowers fuel
//   (`fuelUp`, `fuelDown`: `fuelIndex` 1.12–1.32 or 0.88–0.96, 7 to 14
//   days, never in the first six weeks);
// - its draws are FNV-1a over `seed|key` (`d(state, key)`), as
//   ``SeedDraw`` already is (decision 69).
//
// Here every draw's key names its day, year or month, so the weather of
// any day, the typhoons of any year and the fuel price of any month are
// worked out from the seed alone: nothing is stored day by day, and a batch,
// a minute at a time or a save carried on all give the same. The chances,
// the drops in demand, the typhoon season and the areas are this project's
// (gap: the reference has no railway weather), and so is the calm of the
// first 30 days.

/// A day's weather (decision 162).
public enum Weather: String, CaseIterable, Codable, Sendable {
    case clear
    case rain
    case thunderstorm

    /// What it takes off the whole network's demand at
    /// ``DisruptionLevel/standard``, in thousandths.
    var drop: Int64 {
        switch self {
        case .clear: 0
        case .rain: 100
        case .thunderstorm: 200
        }
    }
}

/// A typhoon (decision 162): announced days before it comes, it cuts the
/// demand of every station within its radius while it lasts.
public struct Typhoon: Hashable, Sendable {
    /// The day it is announced, the first day it blows and the day after
    /// its last.
    public let announced: Int64
    public let start: Int64
    public let end: Int64
    /// The middle of its area, and how far from it a station is hit, in
    /// world units.
    public let centre: PlanPoint
    public let radius: Int64
    /// What it takes off a station's demand, in thousandths, at the world's
    /// level.
    public let drop: Int64

    /// Whether it blows on game day `day`.
    public func isActive(onDay day: Int64) -> Bool {
        start <= day && day < end
    }

    /// Whether `point` is within its radius.
    public func covers(_ point: PlanPoint) -> Bool {
        let dx = point.x - centre.x, dy = point.y - centre.y
        return dx * dx + dy * dy <= radius * radius
    }
}

/// A spell of dearer or cheaper fuel (decision 162): from `start` to the day
/// before `end`, the day's energy costs `index` thousandths of its own.
public struct FuelSpell: Hashable, Sendable {
    public let start: Int64
    public let end: Int64
    public let index: Int64

    public func isActive(onDay day: Int64) -> Bool {
        start <= day && day < end
    }
}

extension Disruptions {
    /// No weather, typhoon or fuel spell in a game's first days.
    public static let calmDays: Int64 = 30
    /// The fuel price stays as it is for the reference's first six weeks.
    static let fuelCalmDays: Int64 = 42

    /// Each month's chance of rain and of a thunderstorm, in thousandths:
    /// a plum-rain spring and afternoon thunderstorms in summer, as a
    /// Taiwanese year has them (this project's), for Taiwan and every
    /// country ``countryRain`` has no table for.
    static let monthlyRain: [(rain: Int64, storm: Int64)] = [
        (250, 0), (300, 0), (300, 20), (300, 50), (450, 80), (450, 120),
        (200, 250), (200, 250), (200, 150), (200, 30), (200, 0), (200, 0),
    ]

    /// Decision 1003: the months of the countries whose maps the game has
    /// outside Taiwan, from their weather offices' 1991–2020 figures. A
    /// month's chance of a storm is its days with thunder over its days;
    /// its chance of rain is its days with 1 mm of rain or more over its
    /// days, less the storm's (a day with thunder is a stormy one), each
    /// rounded to the nearest thousandth.
    ///
    /// - Hong Kong: the Hong Kong Observatory's days with thunderstorms
    ///   (its 1991–2020 normals, Table 3) and its days of 1 mm or more,
    ///   counted from its daily rainfall of 1991–2020 (the same record
    ///   gives the normals' days of 0.1 mm or more exactly).
    /// - Japan: the Japan Meteorological Agency's 1991–2020 normals at
    ///   Fukuoka (47807), days of 1.0 mm or more (element 4600) and days
    ///   with thunder (5700); the game's Japan is Kyushu.
    /// - Finland: the Finnish Meteorological Institute's open data at
    ///   Rovaniemi airport (137190), days of 1 mm or more in 1998–2020
    ///   (its daily record there starts in 1998), and days with a lightning
    ///   stroke within 10 km of the town in 2011–2020 (a thunder day, as
    ///   thunder is heard that far). Rain falls as snow there in the 3D
    ///   map (decision 799).
    static let countryRain: [String: [(rain: Int64, storm: Int64)]] = [
        "HK": [
            (99, 7), (132, 21), (151, 44), (154, 104), (189, 189), (270, 271),
            (253, 257), (199, 287), (213, 169), (135, 27), (106, 6), (109, 0),
        ],
        "JP": [
            (271, 29), (280, 32), (274, 52), (273, 50), (235, 42), (320, 67),
            (184, 171), (126, 190), (230, 93), (193, 26), (233, 50), (242, 32),
        ],
        "FI": [
            (384, 0), (365, 0), (245, 0), (260, 0), (278, 6), (257, 63),
            (232, 123), (248, 65), (306, 17), (329, 0), (420, 0), (400, 0),
        ],
    ]

    /// `country`'s months (decision 1003): its own, or ``monthlyRain``.
    static func monthlyRain(of country: String) -> [(rain: Int64, storm: Int64)] {
        countryRain[country] ?? monthlyRain
    }

    /// Decision 1004: a weather station of a country whose map has more
    /// than one climate: where it is, in ten-millionths of a degree (as
    /// ``GeoAnchor``), and its months as ``monthlyRain``'s.
    struct WeatherStation: Sendable {
        let name: String
        let latitude: Int64
        let longitude: Int64
        let months: [(rain: Int64, storm: Int64)]
    }

    /// Decision 1004: the weather stations of each country whose weather
    /// differs from place to place; a place on a map takes the nearest's
    /// months (``GameWorld/weather(onDay:at:)``). Positions are NOAA's
    /// station list (`isd-history.csv`, public domain), to a thousandth of
    /// a degree.
    /// - Taiwan: the Central Weather Administration's lowland, coastal and
    ///   two mountain stations (Alishan, Sun Moon Lake), not the summits
    ///   (Yushan, Anbu, Zhuzihu) or the far islets. Each month's chances
    ///   are ``monthlyRain``'s times the station's days with 0.1 mm of rain
    ///   or more (its 1991–2020 normals) over the mean of the 19 stations':
    ///   the administration publishes no days of 1 mm or of thunder, so
    ///   the island as a whole keeps the old table and the stations share
    ///   it out as their wet days do (Keelung's January 484 per mille,
    ///   Kaohsiung's 79).
    /// - Kyushu: the Japan Meteorological Agency's normals of 1991–2020 at
    ///   Fukuoka, Saga, Nagasaki and Kumamoto, as decision 1003's Fukuoka:
    ///   days with 1.0 mm or more and days with thunder. Fukuoka's is
    ///   ``countryRain``'s Japan.
    static let weatherStations: [String: [WeatherStation]] = [
        "TW": [
            WeatherStation(name: "淡水", latitude: 251_670_000, longitude: 1_214_330_000, months: [
                (343, 0), (403, 0), (409, 27), (357, 59), (414, 74), (402, 107), (141, 177), (156, 195), (197, 148), (261, 39), (274, 0), (266, 0)]),
            WeatherStation(name: "臺北", latitude: 250_330_000, longitude: 1_215_170_000, months: [
                (333, 0), (377, 0), (390, 26), (378, 63), (487, 86), (514, 137), (204, 255), (209, 261), (224, 168), (270, 40), (272, 0), (268, 0)]),
            WeatherStation(name: "基隆", latitude: 251_500_000, longitude: 1_218_000_000, months: [
                (484, 0), (523, 0), (503, 34), (420, 70), (529, 94), (488, 130), (145, 181), (166, 208), (254, 190), (363, 54), (412, 0), (415, 0)]),
            WeatherStation(name: "花蓮", latitude: 239_830_000, longitude: 1_216_000_000, months: [
                (331, 0), (415, 0), (382, 25), (370, 62), (519, 92), (382, 102), (140, 175), (149, 186), (220, 165), (266, 40), (274, 0), (238, 0)]),
            WeatherStation(name: "蘇澳", latitude: 246_000_000, longitude: 1_218_500_000, months: [
                (496, 0), (561, 0), (495, 33), (440, 73), (634, 113), (484, 129), (162, 202), (165, 206), (269, 201), (431, 65), (458, 0), (457, 0)]),
            WeatherStation(name: "宜蘭", latitude: 247_500_000, longitude: 1_217_830_000, months: [
                (432, 0), (453, 0), (452, 30), (393, 66), (588, 105), (478, 127), (152, 189), (168, 209), (254, 190), (393, 59), (432, 0), (394, 0)]),
            WeatherStation(name: "澎湖", latitude: 235_000_000, longitude: 1_195_000_000, months: [
                (128, 0), (181, 0), (204, 14), (228, 38), (306, 54), (336, 90), (138, 172), (135, 168), (93, 70), (51, 8), (80, 0), (102, 0)]),
            WeatherStation(name: "臺南", latitude: 230_000_000, longitude: 1_202_170_000, months: [
                (94, 0), (120, 0), (113, 8), (155, 26), (296, 53), (399, 106), (221, 277), (226, 283), (142, 106), (59, 9), (53, 0), (64, 0)]),
            WeatherStation(name: "高雄", latitude: 226_330_000, longitude: 1_202_830_000, months: [
                (79, 0), (94, 0), (97, 6), (142, 24), (302, 54), (425, 113), (225, 281), (239, 299), (168, 126), (89, 13), (62, 0), (60, 0)]),
            WeatherStation(name: "嘉義", latitude: 235_000_000, longitude: 1_204_500_000, months: [
                (126, 0), (161, 0), (183, 12), (212, 35), (342, 61), (455, 121), (260, 326), (256, 320), (157, 118), (62, 9), (73, 0), (87, 0)]),
            WeatherStation(name: "臺中", latitude: 241_500_000, longitude: 1_206_830_000, months: [
                (163, 0), (234, 0), (272, 18), (283, 47), (404, 72), (465, 124), (230, 287), (226, 283), (142, 106), (64, 10), (91, 0), (113, 0)]),
            WeatherStation(name: "阿里山", latitude: 235_170_000, longitude: 1_208_000_000, months: [
                (195, 0), (243, 0), (264, 18), (328, 55), (634, 113), (649, 173), (358, 447), (324, 405), (280, 210), (195, 29), (146, 0), (157, 0)]),
            WeatherStation(name: "大武", latitude: 223_500_000, longitude: 1_209_000_000, months: [
                (269, 0), (316, 0), (282, 19), (288, 48), (431, 77), (438, 117), (218, 272), (212, 265), (260, 195), (278, 42), (217, 0), (211, 0)]),
            WeatherStation(name: "新竹", latitude: 248_180_000, longitude: 1_209_390_000, months: [
                (247, 0), (324, 0), (366, 24), (328, 55), (388, 69), (346, 92), (134, 168), (153, 192), (148, 111), (117, 18), (150, 0), (170, 0)]),
            WeatherStation(name: "恆春", latitude: 220_000_000, longitude: 1_207_500_000, months: [
                (126, 0), (146, 0), (86, 6), (113, 19), (309, 55), (494, 132), (269, 336), (251, 313), (225, 169), (183, 27), (104, 0), (85, 0)]),
            WeatherStation(name: "成功", latitude: 231_000_000, longitude: 1_213_670_000, months: [
                (370, 0), (438, 0), (417, 28), (383, 64), (556, 99), (399, 106), (167, 209), (169, 211), (254, 190), (331, 50), (321, 0), (300, 0)]),
            WeatherStation(name: "日月潭", latitude: 238_830_000, longitude: 1_208_500_000, months: [
                (195, 0), (240, 0), (285, 19), (351, 59), (602, 107), (659, 176), (312, 389), (272, 340), (200, 150), (125, 19), (117, 0), (136, 0)]),
            WeatherStation(name: "臺東", latitude: 227_500_000, longitude: 1_211_500_000, months: [
                (207, 0), (266, 0), (250, 17), (286, 48), (473, 84), (379, 101), (172, 215), (168, 209), (214, 160), (210, 32), (190, 0), (179, 0)]),
            WeatherStation(name: "梧棲", latitude: 242_500_000, longitude: 1_205_170_000, months: [
                (133, 0), (205, 0), (250, 17), (246, 41), (335, 60), (359, 96), (153, 192), (156, 195), (100, 75), (51, 8), (73, 0), (98, 0)]),
        ],
        "JP": [
            WeatherStation(name: "福岡", latitude: 335_830_000, longitude: 1_303_830_000, months: [
                (271, 29), (280, 32), (274, 52), (273, 50), (235, 42), (320, 67), (184, 171), (126, 190), (230, 93), (193, 26), (233, 50), (242, 32)]),
            WeatherStation(name: "佐賀", latitude: 332_670_000, longitude: 1_303_000_000, months: [
                (229, 6), (252, 21), (281, 32), (263, 47), (239, 35), (360, 60), (216, 171), (103, 223), (203, 97), (165, 19), (210, 37), (200, 10)]),
            WeatherStation(name: "長崎", latitude: 327_330_000, longitude: 1_298_670_000, months: [
                (271, 19), (283, 25), (284, 42), (254, 53), (259, 35), (376, 57), (229, 116), (164, 155), (213, 87), (152, 35), (220, 53), (233, 32)]),
            WeatherStation(name: "熊本", latitude: 328_170_000, longitude: 1_307_000_000, months: [
                (200, 10), (251, 25), (296, 39), (260, 53), (262, 35), (377, 93), (181, 216), (106, 223), (207, 103), (184, 26), (210, 33), (210, 13)]),
        ],
    ]

    /// The countries typhoons reach.
    static let typhoonCountries: Set<String> = ["TW", "CN", "HK", "JP", "KR", "VN"]
    /// The typhoon season: from 1 July (day 180 of the game's year) to the
    /// end of October (day 299).
    static let typhoonSeason: ClosedRange<Int64> = 180...299
    /// A year has up to three typhoons, each one this likely, in
    /// thousandths: half as many at the light level.
    static let typhoonSlots = 3
    var typhoonChance: Int64 { level == .standard ? 500 : 250 }

    /// What `drop` thousandths take off at this level: all of it, or half
    /// (rounded down) at the light level.
    func scaledDrop(_ drop: Int64) -> Int64 {
        level.scaled(drop)
    }

    /// The weather of game day `day`: clear without a seed or in the first
    /// ``calmDays``.
    public func weather(onDay day: Int64) -> Weather {
        weather(onDay: day, months: Self.monthlyRain(of: country))
    }

    /// Decision 1004: the weather of game day `day` under `months`' chances.
    /// The day's draw is the same for every place on the map, so a wet
    /// day falls on the wettest places first: it rains in the north while
    /// the south is clear, and on the wettest days everywhere.
    func weather(onDay day: Int64, months: [(rain: Int64, storm: Int64)]) -> Weather {
        guard let seed, day >= Self.calmDays else { return .clear }
        let year = FinancePeriod.year.days
        let month = Int(((day % year) + year) % year / FinancePeriod.month.days)
        let chances = months[month]
        let roll = SeedDraw(seed: seed).roll("weather.\(day)", in: 0...999)
        if roll < chances.storm { return .thunderstorm }
        return roll < chances.storm + chances.rain ? .rain : .clear
    }

    /// The typhoons of game year `year` (day `360 × year` on) in a world of
    /// `bounds`, by start: none without a seed or outside
    /// ``typhoonCountries``, and none starting in the first ``calmDays``.
    public func typhoons(ofYear year: Int64, in bounds: WorldBounds) -> [Typhoon] {
        guard let seed, Self.typhoonCountries.contains(country) else { return [] }
        let draw = SeedDraw(seed: seed)
        let first = year * FinancePeriod.year.days
        var typhoons: [Typhoon] = []
        for slot in 0..<Self.typhoonSlots {
            let key = "typhoon.\(year).\(slot)"
            guard draw.roll("\(key).comes", in: 0...999) < typhoonChance else { continue }
            let start = first + draw.roll("\(key).start", in: Self.typhoonSeason)
            guard start >= Self.calmDays else { continue }
            let side = max(bounds.width, bounds.height)
            typhoons.append(Typhoon(
                announced: start - draw.roll("\(key).notice", in: 1...3),
                start: start,
                end: start + draw.roll("\(key).days", in: 1...2),
                centre: PlanPoint(x: draw.roll("\(key).x", in: 0...bounds.width), y: draw.roll("\(key).y", in: 0...bounds.height)),
                radius: side * draw.roll("\(key).radius", in: 300...600) / 1_000,
                drop: scaledDrop(800)
            ))
        }
        return typhoons.sorted { $0.start < $1.start }
    }

    /// The fuel spell of game day `day`, or `nil`: each 30-day month after
    /// the first six weeks may have one, 7 to 14 days long, dearer three
    /// times in five (1.12–1.32) and cheaper otherwise (0.88–0.96), half as
    /// far from 1 at the light level.
    public func fuelSpell(onDay day: Int64) -> FuelSpell? {
        guard let seed else { return nil }
        let monthDays = FinancePeriod.month.days
        let month = CompanyAccounts.floorDivide(day, monthDays)
        let draw = SeedDraw(seed: seed)
        let key = "fuel.\(month)"
        guard draw.roll("\(key).comes", in: 0...999) < 300 else { return nil }
        let start = month * monthDays + draw.roll("\(key).start", in: 0...15)
        let spell = FuelSpell(
            start: start,
            end: start + draw.roll("\(key).days", in: 7...14),
            index: {
                let index = draw.roll("\(key).up", in: 0...4) < 3
                    ? draw.roll("\(key).index", in: 1_120...1_320)
                    : draw.roll("\(key).index", in: 880...960)
                return 1_000 + level.scaled(index - 1_000)
            }()
        )
        return start >= Self.fuelCalmDays && spell.isActive(onDay: day) ? spell : nil
    }
}

extension GameWorld {
    // MARK: - Queries

    /// The weather of game day `day` (decision 162): the map's, at its
    /// ``geoAnchor`` (decision 1004, ``weather(onDay:at:)``).
    public func weather(onDay day: Int64) -> Weather {
        weather(onDay: day, at: weatherAnchorPoint)
    }

    /// Decision 1004: the weather of game day `day` at `point`: under the
    /// months of the weather station nearest it when the map's country has
    /// several (``Disruptions/weatherStations``), else the country's.
    public func weather(onDay day: Int64, at point: PlanPoint) -> Weather {
        guard let disruptions else { return .clear }
        return disruptions.weather(onDay: day, months: weatherStation(at: point)?.months ?? Disruptions.monthlyRain(of: disruptions.country))
    }

    /// Decision 1004: whether the weather differs from place to place on
    /// this map: it is of a real place (``geoAnchor``) in a country with
    /// several weather stations.
    public var hasRegionalWeather: Bool {
        guard geoAnchor != nil, let disruptions else { return false }
        return Disruptions.weatherStations[disruptions.country] != nil
    }

    /// Decision 1004: the point ``geoAnchor`` is at: the middle of
    /// ``geoAnchorBounds``, or of the world.
    var weatherAnchorPoint: PlanPoint {
        let frame = geoAnchorBounds ?? bounds
        return PlanPoint(x: frame.width / 2, y: frame.height / 2)
    }

    /// Decision 1004: the weather station nearest `point`, or `nil` when
    /// the weather is the same all over the map. Distances are in metres
    /// on the map's own scale (true east–west at the anchor's latitude),
    /// compared squared; the first of equally near ones.
    func weatherStation(at point: PlanPoint) -> Disruptions.WeatherStation? {
        guard let anchor = geoAnchor, let country = disruptions?.country,
              let stations = Disruptions.weatherStations[country] else { return nil }
        let units = WorldCoordinate.unitsPerMetre
        let middle = weatherAnchorPoint
        let east = (point.x - middle.x) / units
        let north = (middle.y - point.y) / units
        let cosine = Self.cosineThousandths(ofLatitude: anchor.latitude)
        var best: (station: Disruptions.WeatherStation, squared: Int64)?
        for station in stations {
            let dy = (station.latitude - anchor.latitude) * Self.metresPerDegree / 10_000_000 - north
            let dx = (station.longitude - anchor.longitude) * Self.metresPerDegree / 10_000_000 * cosine / 1_000 - east
            let squared = dx * dx + dy * dy
            if best.map({ squared < $0.squared }) ?? true { best = (station, squared) }
        }
        return best?.station
    }

    /// Metres in a degree of latitude.
    static let metresPerDegree: Int64 = 111_320

    /// The cosine of `latitude` (ten-millionths of a degree) in
    /// thousandths, by Bhaskara's rule (within 2 thousandths of the true
    /// one): enough to say which weather station is nearest.
    static func cosineThousandths(ofLatitude latitude: Int64) -> Int64 {
        let hundredths = latitude / 100_000
        let square = hundredths * hundredths
        return 1_000 * (324_000_000 - 4 * square) / (324_000_000 + square)
    }

    /// The typhoons announced and not yet over on game day `day`, by start
    /// (decision 162).
    public func typhoons(onDay day: Int64) -> [Typhoon] {
        guard let disruptions else { return [] }
        // The season is inside the year, notice and all.
        let year = CompanyAccounts.floorDivide(day, FinancePeriod.year.days)
        return disruptions.typhoons(ofYear: year, in: bounds).filter { $0.announced <= day && day < $0.end }
    }

    /// The fuel spell of game day `day`, or `nil` (decision 162).
    public func fuelSpell(onDay day: Int64) -> FuelSpell? {
        disruptions?.fuelSpell(onDay: day)
    }

    /// What game day `day`'s weather takes off the whole network's demand,
    /// in thousandths, at the world's level: 0 on a clear day.
    public func weatherDrop(onDay day: Int64) -> Int64 {
        guard let disruptions else { return 0 }
        return disruptions.scaledDrop(weather(onDay: day).drop)
    }

    /// Decision 1004: what game day `day`'s weather at station `id` takes
    /// off the trips that start there, as ``weatherDrop(onDay:)``; the
    /// map's for a station that is not there.
    public func weatherDrop(onDay day: Int64, at id: StationID) -> Int64 {
        guard let disruptions else { return 0 }
        guard hasRegionalWeather, let point = station(id: id)?.point else { return weatherDrop(onDay: day) }
        return disruptions.scaledDrop(weather(onDay: day, at: point).drop)
    }

    /// How much today's weather leaves of the whole network's demand, in
    /// thousandths: 1000 on a clear day.
    var weatherMultiplier: Int64 {
        1_000 - weatherDrop(onDay: dayIndex(of: clock.now))
    }

    /// How much today's typhoons leave of station `id`'s demand, in
    /// thousandths: 1000 where none blows.
    func typhoonMultiplier(at id: StationID) -> Int64 {
        typhoonMultipliers()[id] ?? 1_000
    }

    /// How much today's typhoons leave of the demand of each station they
    /// blow over, in thousandths, by station: empty where none blows.
    /// Worked out once for a plan rather than once for each pair (each
    /// is a search of the year's typhoons).
    func typhoonMultipliers() -> [StationID: Int64] {
        guard disruptions?.seed != nil else { return [:] }
        let day = dayIndex(of: clock.now)
        let blowing = typhoons(onDay: day).filter { $0.isActive(onDay: day) }
        guard !blowing.isEmpty else { return [:] }
        var multipliers: [StationID: Int64] = [:]
        for station in stations {
            let drop = blowing.filter { $0.covers(station.point) }.map(\.drop).max() ?? 0
            if drop > 0 {
                multipliers[station.id] = 1_000 - drop
            }
        }
        return multipliers
    }

    /// `trips` from `origin` to `destination` as today's typhoons leave
    /// them: times the smaller of the two ends' `multipliers` (see
    /// ``typhoonMultipliers()``), rounded half up. A typhoon cuts the trips
    /// that set out from or go to a station it blows over, once even when
    /// it blows over both ends, and sends none of them elsewhere: the
    /// stations it misses keep their trips.
    static func typhoonTrips(_ trips: Int64, from origin: StationID, to destination: StationID,
                             multipliers: [StationID: Int64]) -> Int64 {
        let left = min(multipliers[origin] ?? 1_000, multipliers[destination] ?? 1_000)
        return left == 1_000 ? trips : (trips * left + 500) / 1_000
    }
}
