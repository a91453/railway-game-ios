// Taiwan's named festivals (ARCHITECTURE decision 576): the Dajia Mazu
// pilgrimage, the Lantern Festival (Pingxi sky lanterns), the New Year's
// Eve crowd at Taipei 101 and the Mid-Autumn moon-viewing, each held at a
// place on the map and each raising the demand of the stations round it
// for its days, announced before it starts (a ``DemandEvent`` of kind
// ``DemandEventKind/festival`` that names its festival).
//
// The dates follow the lunar calendar as Taiwan's public holidays do
// (decision 211): the Hong Kong Observatory's Gregorian-lunar tables,
// written by `tools/holiday-calendar/build_taiwan_lunar_dates.py`, a year
// outside 2025 to 2100 taking the year a multiple of 19 years away inside
// it. The game's months have 30 days (``TaiwanHolidays/Week``), so a date
// is put on the same month and day of them.
//
// Where the reference has nothing (gap, decision 576): the boosts, the
// notice and the length are this project's. The Dajia pilgrimage's real
// start is drawn by divination at the Lantern Festival each year, so the
// game fixes it at the first day of the third lunar month, which is the
// real one in 2026 (17 April, 22:05, Dajia Jenn Lann Temple's announcement);
// other years' real starts are UNVERIFIED.

/// A named festival of Taiwan.
public enum FestivalKind: String, CaseIterable, Codable, Sendable {
    /// The Dajia Mazu pilgrimage (大甲媽祖遶境進香), nine days from the
    /// first day of the third lunar month.
    case mazuProcession
    /// The Lantern Festival (元宵, 15th of the first lunar month) and the
    /// sky lanterns of Pingxi (平溪天燈).
    case lanternFestival
    /// New Year's Eve (跨年, 31 December) at Taipei 101.
    case newYearsEve
    /// The Mid-Autumn Festival (中秋, 15th of the eighth lunar month): the
    /// barbecues by the river.
    case midAutumn
}

extension FestivalKind {
    /// How many days it runs.
    public var days: Int64 {
        switch self {
        case .mazuProcession: 9
        case .lanternFestival: 3
        case .newYearsEve, .midAutumn: 1
        }
    }

    /// How much it adds to a station's demand, in thousandths.
    public var boost: Int64 {
        switch self {
        case .mazuProcession: 800
        case .lanternFestival: 1_000
        case .newYearsEve: 1_200
        case .midAutumn: 400
        }
    }

    /// How many days before it starts it is announced.
    public var notice: Int64 {
        switch self {
        case .mazuProcession: 14
        case .lanternFestival: 7
        case .newYearsEve: 5
        case .midAutumn: 3
        }
    }

    /// The hours of the day it draws its crowd, as the first hour and the
    /// hour after the last. A record for the news; demand events run in
    /// whole days (decision 576's next step: shape the hours).
    public var hours: Range<Int> {
        switch self {
        case .mazuProcession: 0..<24
        case .lanternFestival: 17..<23
        case .newYearsEve: 20..<24
        case .midAutumn: 17..<23
        }
    }

    /// How near a station is to the place for the festival to reach it:
    /// twice a sight's reach.
    static var reach: Int64 { Tourism.reach * 2 }

    /// The most stations one place's festival raises: the nearest.
    static let stationsPerSite = 3

    /// The first day of the festival in game year `year` (day 0 the first
    /// day of game year 0, which is 2026).
    public func start(inGameYear year: Int64) -> Int64 {
        let real = TaiwanHolidays.firstGameYear + year
        switch self {
        case .mazuProcession: return TaiwanHolidays.day(Self.lunarDates(ofRealYear: real)[1], inYear: year)
        case .lanternFestival: return TaiwanHolidays.day(Self.lunarDates(ofRealYear: real)[0], inYear: year)
        case .newYearsEve: return TaiwanHolidays.day(1_231, inYear: year)
        case .midAutumn: return TaiwanHolidays.day(TaiwanHolidays.lunarDates(ofRealYear: real)[3], inYear: year)
        }
    }

    /// Whether the festival starts on game day `day`.
    public func starts(onDay day: Int64) -> Bool {
        start(inGameYear: CompanyAccounts.floorDivide(day, FinancePeriod.year.days)) == day
    }

    /// For each real year from 2025, the Gregorian month and day (MMDD) of
    /// the Lantern Festival and of the first day of the third lunar month.
    static let lunarDates: [[Int]] = [
        [212, 329], // 2025
        [303, 417], // 2026
        [220, 407], // 2027
        [209, 326], // 2028
        [227, 414], // 2029
        [217, 403], // 2030
        [206, 323], // 2031
        [225, 410], // 2032
        [214, 331], // 2033
        [305, 419], // 2034
        [222, 408], // 2035
        [211, 328], // 2036
        [301, 416], // 2037
        [218, 405], // 2038
        [207, 325], // 2039
        [226, 411], // 2040
        [215, 401], // 2041
        [205, 420], // 2042
        [224, 410], // 2043
        [213, 329], // 2044
        [303, 417], // 2045
        [220, 406], // 2046
        [209, 326], // 2047
        [228, 413], // 2048
        [216, 402], // 2049
        [206, 323], // 2050
        [225, 411], // 2051
        [215, 331], // 2052
        [305, 419], // 2053
        [222, 408], // 2054
        [211, 328], // 2055
        [229, 415], // 2056
        [218, 404], // 2057
        [207, 324], // 2058
        [226, 412], // 2059
        [216, 401], // 2060
        [204, 322], // 2061
        [223, 410], // 2062
        [212, 330], // 2063
        [302, 417], // 2064
        [219, 406], // 2065
        [209, 326], // 2066
        [228, 414], // 2067
        [217, 402], // 2068
        [206, 323], // 2069
        [225, 411], // 2070
        [214, 331], // 2071
        [304, 418], // 2072
        [221, 407], // 2073
        [210, 327], // 2074
        [301, 415], // 2075
        [219, 404], // 2076
        [207, 324], // 2077
        [226, 412], // 2078
        [216, 402], // 2079
        [205, 321], // 2080
        [223, 409], // 2081
        [212, 329], // 2082
        [303, 417], // 2083
        [220, 405], // 2084
        [209, 326], // 2085
        [228, 414], // 2086
        [217, 403], // 2087
        [207, 323], // 2088
        [224, 411], // 2089
        [213, 331], // 2090
        [304, 419], // 2091
        [221, 407], // 2092
        [210, 327], // 2093
        [301, 415], // 2094
        [219, 405], // 2095
        [208, 324], // 2096
        [226, 412], // 2097
        [215, 402], // 2098
        [204, 420], // 2099
        [223, 410], // 2100
    ]

    static func lunarDates(ofRealYear year: Int64) -> [Int] {
        let first = TaiwanHolidays.firstTableYear
        let last = first + Int64(lunarDates.count) - 1
        var inside = year
        if inside > last {
            inside -= (inside - last + TaiwanHolidays.cycle - 1) / TaiwanHolidays.cycle * TaiwanHolidays.cycle
        } else if inside < first {
            inside += (first - inside + TaiwanHolidays.cycle - 1) / TaiwanHolidays.cycle * TaiwanHolidays.cycle
        }
        return lunarDates[Int(inside - first)]
    }
}

/// Where a festival is held on the map: its place in world coordinates
/// (the presentation puts a real place on the map; decision 576).
public struct FestivalSite: Hashable, Codable, Sendable {
    public let kind: FestivalKind
    public let point: PlanPoint

    public init(kind: FestivalKind, point: PlanPoint) {
        self.kind = kind
        self.point = point
    }
}

extension GameWorld {
    /// Sets the places festivals are held at, one for each kind (the last
    /// of a kind wins). Needs demand events (``setDemandEvents(seed:)``):
    /// without them it does nothing. Places outside the map are left out.
    public mutating func setFestivalSites(_ sites: [FestivalSite]) {
        guard demandEvents != nil else { return }
        var kept: [FestivalKind: FestivalSite] = [:]
        for site in sites where (0..<bounds.width).contains(site.point.x) && (0..<bounds.height).contains(site.point.y) {
            kept[site.kind] = site
        }
        demandEvents?.sites = FestivalKind.allCases.compactMap { kept[$0] }
    }

    /// The nearest stations to `point`, at most ``FestivalKind/stationsPerSite``
    /// within ``FestivalKind/reach``, that a passenger line calls at and
    /// that take passengers.
    func festivalStations(near point: PlanPoint) -> [StationID] {
        let limit = FestivalKind.reach * FestivalKind.reach
        var found: [(StationID, Int64)] = []
        for station in stations {
            let dx = station.point.x - point.x, dy = station.point.y - point.y
            let squared = dx * dx + dy * dy
            guard squared <= limit, allowsService(at: station.id), stationDemand(of: station.id) != nil,
                  lines.contains(where: { !$0.isFreight && $0.hasTrainsCalling(at: station.id) })
            else { continue }
            found.append((station.id, squared))
        }
        found.sort { ($0.1, $0.0) < ($1.1, $1.0) }
        return found.prefix(FestivalKind.stationsPerSite).map(\.0)
    }

    /// The named festivals announced at the midnight that began game day
    /// `day`: each place's, when its festival starts after its notice.
    func namedFestivalEvents(on day: Int64, sites: [FestivalSite]) -> [DemandEvent] {
        var events: [DemandEvent] = []
        for site in sites where site.kind.starts(onDay: day + site.kind.notice) {
            let start = day + site.kind.notice
            for station in festivalStations(near: site.point) {
                events.append(DemandEvent(
                    kind: .festival, station: station, announced: day, start: start, end: start + site.kind.days,
                    boost: site.kind.boost, festival: site.kind
                ))
            }
        }
        return events
    }
}
