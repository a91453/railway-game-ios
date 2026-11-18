// Sights and tourists (ARCHITECTURE decision 174): the second demand curve,
// beside the commuters'. Native: the reference has no tourism rules (its
// OpenWorld destination catalog only lists places), so the stars, the
// seasons and the shop are this project's own.
//
// An attraction has a base rating in hundredths of a star (100 to 500) and
// may have a souvenir shop of level 0 to 2 (a quarter star a level, up to
// five stars). Every day its rating draws a number of potential tourists
// (300, 800, 2,000, 4,500 and 9,000 at one to five stars, in between by
// line); the day of the week or a holiday, the season of its kind, the
// weather and a typhoon scale them; a fifth of them (``Tourism/captureRate``)
// are the ones a railway can fetch. They set out from the sources, the
// outside connections and the five stations with the most residents, in
// proportion to their weight, and ride the attraction's station by the
// morning's scenic curve and back by the afternoon's, as any other passenger
// of the passenger model: they pay the fare, change trains and crowd them.
//
// Everything is whole numbers and thousandths.

public struct AttractionID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: AttractionID, rhs: AttractionID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What kind of place an attraction is, which sets its season, and for a
/// night market its hours.
public enum AttractionKind: String, CaseIterable, Codable, Sendable {
    case coast
    case mountain
    case hotSpring
    case town
    /// A night market (decision 769): its tourists come in the evening and
    /// go home late (``Tourism/nightMarketArrivals``), not in the day as a
    /// sight's do. Last, so that a blank map's draw of the first four kinds
    /// is unchanged.
    case nightMarket
    /// A landmark (decision 772): a tower, a memorial hall, a fort, a
    /// bridge. Open all day and into the evening for the night view
    /// (``Tourism/landmarkArrivals``), busiest in the school holidays.
    case landmark
    /// A museum (decision 772): closed on Mondays that are not a holiday,
    /// not put off by rain, open in the day (``Tourism/museumArrivals``).
    case museum
    /// A temple (decision 772): pilgrims from early morning and again at
    /// dusk (``Tourism/templeArrivals``), the first and fifteenth of a
    /// month and the Spring Festival busiest, Mazu's month in spring.
    case temple
    /// A harbour (decision 773): a fishing port or a fisherman's wharf.
    /// Its tourists come for a seafood lunch and again for the sunset
    /// (``Tourism/harbourArrivals``), less held by the season than a
    /// beach's, and stay home in the rain and the storms more than other
    /// sights' do.
    case harbour
}

/// A place tourists go to.
public struct Attraction: Hashable, Sendable {
    public let id: AttractionID
    public let name: String
    public let englishName: String
    public let point: PlanPoint
    public internal(set) var kind: AttractionKind
    /// The rating before any shop, in hundredths of a star, 100 to 500.
    public let baseStars: Int
    /// The souvenir shop's level, 0 to ``Tourism/maximumSouvenirLevel``.
    public internal(set) var souvenir: Int
    /// The tourists of the day that last ended, and of the year so far and
    /// the year before (a year is 360 days).
    public internal(set) var yesterday: Int64
    public internal(set) var thisYear: Int64
    public internal(set) var lastYear: Int64

    public init(id: AttractionID, name: String, englishName: String, point: PlanPoint, kind: AttractionKind, baseStars: Int) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.point = point
        self.kind = kind
        self.baseStars = baseStars
        souvenir = 0
        yesterday = 0
        thisYear = 0
        lastYear = 0
    }

    /// This attraction with a souvenir shop of `level`, to ask what it would do.
    public func withSouvenir(level: Int) -> Attraction {
        var copy = self
        copy.souvenir = level
        return copy
    }

    /// The rating now, in hundredths of a star.
    public var stars: Int {
        min(500, baseStars + Tourism.starsPerSouvenirLevel * souvenir)
    }
}

/// Why an attraction draws no tourists today, or `ok`.
public enum AttractionStatus: String, Hashable, Sendable {
    case ok
    /// No station within 800 m with a passenger line calling at it.
    case noStation
    /// A station there, but no source station can ride to it.
    case noSource
    /// A typhoon blows over it today.
    case typhoon
}

/// The world's attractions (decision 174).
public struct Tourism: Hashable, Sendable {
    public internal(set) var attractions: [Attraction]
    /// The year the counters are for (day ÷ 360).
    public internal(set) var year: Int64
    public internal(set) var nextID: Int

    public static let maximumSouvenirLevel = 2

    /// When on game day `day` the network its tourists rode is read, to
    /// count them at midnight (decision 551): noon, when every line with
    /// service hours runs.
    static func countedAt(day: Int64) -> GameTime {
        GameTime(seconds: day * GameTime.secondsPerDay + GameTime.secondsPerDay / 2)
    }

    /// Decision 551, continued (review L6-1): when on game day `day` a
    /// line with hours `window` is read for its tourists: noon, when it
    /// runs then; otherwise the middle of its hours, so a line that runs
    /// only in the afternoon and night, or only in the morning, is counted
    /// too.
    static func countedAt(day: Int64, window: ServiceWindow) -> GameTime {
        let noon = countedAt(day: day)
        guard case .hours(let open, let close) = window, !window.contains(minuteOfDay: noon.minuteOfDay) else { return noon }
        let middle = Int64((open + close) / 2) % GameTime.minutesPerDay
        return GameTime(seconds: day * GameTime.secondsPerDay + middle * GameTime.secondsPerMinute)
    }

    /// Decision 551, continued (review L7-2): when on game day `day` `line`
    /// is read for its tourists: at ``countedAt(day:window:)`` when it is
    /// set to run a train then; otherwise at the first minute of the day,
    /// within its hours, of a service level it runs trains at (the start of
    /// a level's band, or the opening of its hours), so a line with no
    /// train off-peak is counted at the peak. A line that runs none at any
    /// level keeps ``countedAt(day:window:)``, where it adds nothing.
    static func countedAt(day: Int64, line: ServiceLine, serviceDay: ServiceDay) -> GameTime {
        let preferred = countedAt(day: day, window: line.window)
        func runs(_ minute: Int) -> Bool {
            line.window.contains(minuteOfDay: minute) && line.setsTrains(at: serviceDay.level(atMinuteOfDay: minute))
        }
        guard !runs(preferred.minuteOfDay) else { return preferred }
        var starts = serviceDay.bands.map(\.start)
        if case .hours(let open, _) = line.window { starts.append(open) }
        guard let minute = starts.sorted().first(where: runs) else { return preferred }
        return GameTime(seconds: day * GameTime.secondsPerDay + Int64(minute) * GameTime.secondsPerMinute)
    }

    /// Decision 551, continued: the network the tourists of game day `day`
    /// are counted on, each line as it runs at
    /// ``countedAt(day:line:serviceDay:)``. Since review L7-1 the day
    /// passes (and the subsidiaries' pass holders) are read on it too.
    static func countingGraph(of world: GameWorld, day: Int64) -> PassengerRouteGraph {
        PassengerRouteGraph(world: world, lineTime: { countedAt(day: day, line: $0, serviceDay: world.serviceDay) })
    }
    /// What a hotel within ``SubsidiaryRules/reach`` of an attraction adds to
    /// its rating, in hundredths of a star, and how many count (decision
    /// 174, a later fix): two hotels, half a star.
    public static let starsPerHotel = 25
    public static let hotelsCounted = 2
    /// What a sightseeing train (``TrainType/isSightseeing``, decision 286)
    /// calling at a station within ``reach`` of an attraction adds to its
    /// rating, in hundredths of a star: half a star, however many call.
    public static let starsPerSightseeingTrain = 50
    /// What the Ming-Ri, the luxury sightseeing train (decision 286, later),
    /// adds the same way: a whole star. Where several sightseeing trains
    /// call, the most any of them adds counts.
    public static let starsPerLuxuryTrain = 100
    /// What the Formosa Star, the round-the-island tour train (decision 286,
    /// later, third), adds the same way: three quarters of a star.
    public static let starsPerRoundIslandTrain = 75
    /// What the Midsummer Formosa, the CT273 steam train (decision 286,
    /// later, fourth), adds the same way: a star and a quarter.
    public static let starsPerSteamTrain = 125
    /// The rating of a temple the company built (decision 361) before any
    /// hotel or train near it, in hundredths of a star: two stars, a
    /// neighbourhood temple's.
    public static let templeStars = 200
    /// The rating of a night market the company built (decision 361's
    /// sequel), the same way: two and a half stars, a district's night
    /// market, below the famous ones the catalog holds as towns.
    public static let nightMarketStars = 250
    /// The rating of a railway museum the company built (decision 684)
    /// with nothing to show but papers and models, in hundredths of a
    /// star: a star and a half, a small local exhibition hall's.
    public static let museumStars = 150
    /// What each exhibit, a type of train the company has owned, adds to
    /// its museum, and how many count: fifteen hundredths of a star each,
    /// twelve, so a museum of twelve types is 3.3 stars, a city's well
    /// known museum below the island's famous sights.
    public static let starsPerExhibit = 15
    public static let exhibitsCounted = 12
    /// The rating of a railway museum with `exhibits` exhibits (decision
    /// 684), before any hotel or train near it.
    public static func museumStars(exhibits: Int) -> Int {
        museumStars + starsPerExhibit * max(0, min(exhibitsCounted, exhibits))
    }
    /// The share of an attraction's tourists who stay the night in a hotel
    /// near it, in thousandths (shared among the hotels there).
    public static let hotelStayPermille: Int64 = 80
    public static let starsPerSouvenirLevel = 25
    /// What a level of the shop costs: NT$900,000, in cents (decision
    /// 499: $300,000 times 3).
    public static let souvenirCost: Int64 = 90_000_000
    /// What a tourist spends in the shop, in cents, times its level.
    public static let spendPerLevel: Int64 = 1_200
    /// A shop's upkeep a day, in hundred-thousandths of what it cost.
    public static let upkeepPerDay: Int64 = 50
    /// How close a station must be to serve an attraction: 800 m.
    public static let reach: Int64 = Land.catchmentRadius
    /// The share of potential tourists a railway fetches, in thousandths.
    public static let captureRate: Int64 = 200
    /// A source station of the outside counts as this many residents.
    public static let outsideWeight: Int64 = 200_000
    public static let busiestSources = 5
    /// The most a world has (decision 250: from 64, so that the whole of
    /// Taiwan holds every sight of the app's catalog, and a blank map that
    /// buys its map five for each of its 25 tiles).
    public static let maximumAttractions = 256
    static let potential: [Int64] = [300, 800, 2_000, 4_500, 9_000]

    // Decision 769, this project's (the reference has no night market's
    // hours): `0.02 + g(h; 19, 1.6)` arriving and `0.02 + g(h; 21.5, 1.4)`
    // leaving, with `g(h; μ, σ) = exp(−½((h − μ)/σ)²)`, each normalised so
    // that the day's mean is 1, in thousandths. A Taiwanese night market
    // fills from about 17:00, is busiest from 19:00 to 21:00 and empties
    // towards midnight; nine in ten of its tourists ride between 17:00 and
    // midnight. These are the hours themselves, not times the day's
    // ``StationDemand/dayShape``, whose 23:00 is the night's.
    /// How strongly a night market's tourists arrive in each hour.
    public static let nightMarketArrivals: [Int64] = [
        107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107, 107,
        107, 112, 148, 342, 1030, 2559, 4512, 5462, 4512, 2559, 1030, 342,
    ]
    /// How strongly a night market's tourists leave in each hour.
    public static let nightMarketDepartures: [Int64] = [
        128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128,
        128, 128, 128, 129, 131, 165, 411, 1433, 3747, 6155, 6155, 3747,
    ]

    // Decision 772, this project's (the reference has no hours of a
    // museum, a temple or a landmark), the same way as decision 769's:
    // each `f(h)` normalised so that the day's mean is 1, in thousandths,
    // the hours themselves rather than times ``StationDemand/dayShape``.
    // A museum `0.01 + g(h; 11, 1.8)` arriving and `0.01 + g(h; 15.5,
    // 1.3)` leaving (open about 9:00 to 17:00); a temple `0.02 + 0.6 g(h;
    // 8, 1.5) + 0.4 g(h; 18.5, 1.5)` arriving and the same an hour and a
    // half later leaving (morning incense and the evening's); a landmark
    // `0.02 + g(h; 14, 3.5)` arriving and `0.02 + g(h; 17.5, 3)` leaving
    // (from the morning to the night view).
    public static let museumArrivals: [Int64] = [
        51, 51, 51, 51, 53, 70, 157, 478, 1310, 2775, 4379, 5101,
        4379, 2775, 1310, 478, 157, 70, 53, 51, 51, 51, 51, 51,
    ]
    public static let museumDepartures: [Int64] = [
        69, 69, 69, 69, 69, 69, 69, 69, 69, 69, 69, 86,
        252, 1148, 3594, 6439, 6439, 3594, 1148, 252, 86, 69, 69, 69,
    ]
    public static let templeArrivals: [Int64] = [
        113, 113, 114, 126, 210, 573, 1510, 2833, 3510, 2833, 1510, 573,
        210, 129, 140, 262, 678, 1487, 2255, 2255, 1487, 678, 262, 138,
    ]
    public static let templeDepartures: [Int64] = [
        114, 114, 114, 114, 118, 151, 337, 963, 2180, 3336, 3336, 2180,
        963, 338, 152, 126, 179, 421, 1047, 1932, 2385, 1932, 1047, 421,
    ]
    public static let landmarkArrivals: [Int64] = [
        53, 55, 59, 71, 96, 147, 243, 404, 651, 990, 1406, 1854,
        2262, 2550, 2654, 2550, 2262, 1854, 1406, 990, 651, 404, 243, 147,
    ]
    public static let landmarkDepartures: [Int64] = [
        61, 61, 61, 61, 61, 62, 63, 68, 82, 117, 196, 354,
        632, 1056, 1613, 2227, 2765, 3083, 3083, 2765, 2227, 1613, 1056, 632,
    ]

    // Decision 773, this project's (the reference has no harbour's hours),
    // the same way as decision 772's: a harbour `0.02 + 0.5 g(h; 11.5,
    // 1.5) + 0.5 g(h; 16.5, 1.5)` arriving (the seafood lunch, the sunset)
    // and `0.02 + 0.5 g(h; 13.5, 1.5) + 0.5 g(h; 19, 1.5)` leaving (after
    // lunch, after the sunset's dinner).
    public static let harbourArrivals: [Int64] = [
        113, 113, 113, 113, 113, 113, 117, 145, 299, 819, 1830, 2794,
        2822, 2016, 1525, 2016, 2822, 2794, 1830, 819, 299, 145, 117, 113,
    ]
    public static let harbourDepartures: [Int64] = [
        113, 113, 113, 113, 113, 113, 113, 114, 117, 145, 299, 819,
        1831, 2793, 2803, 1912, 1203, 1464, 2412, 2948, 2381, 1277, 496, 194,
    ]

    /// The hours `kind`'s tourists arrive and leave in (decisions 769, 772
    /// and 773), or `nil` for a sight's by the scenic curve times the day's.
    public static func hours(of kind: AttractionKind) -> (arrivals: [Int64], departures: [Int64])? {
        switch kind {
        case .nightMarket: (nightMarketArrivals, nightMarketDepartures)
        case .museum: (museumArrivals, museumDepartures)
        case .temple: (templeArrivals, templeDepartures)
        case .landmark: (landmarkArrivals, landmarkDepartures)
        case .harbour: (harbourArrivals, harbourDepartures)
        case .coast, .mountain, .hotSpring, .town: nil
        }
    }

    /// What a temple's day is worth beside ``dayFactor(weekday:holiday:)``
    /// (decision 772), in thousandths: the first and fifteenth of a month
    /// half as much again, the Spring Festival a quarter more.
    public static let templeNewMoonFactor: Int64 = 1_500
    public static let templeSpringFestivalFactor: Int64 = 1_250
    /// A museum's weather when it is not clear (decision 772), in
    /// thousandths: people go in out of the rain, where other sights lose
    /// three in ten.
    public static let museumRainFactor: Int64 = 1_100

    /// The day's factor of a sight of `kind` (decision 772): that of
    /// ``dayFactor(weekday:holiday:)``, none for a museum on a Monday
    /// that is not a holiday, and a temple's more on the first and
    /// fifteenth of the month (`dayOfMonth`, 1 to 30) and in the Spring
    /// Festival.
    public static func dayFactor(_ kind: AttractionKind, weekday: Int, holiday: HolidayKind?, dayOfMonth: Int) -> Int64 {
        let base = dayFactor(weekday: weekday, holiday: holiday != nil)
        switch kind {
        case .museum:
            return weekday == 1 && holiday == nil ? 0 : base
        case .temple:
            var factor = base
            if dayOfMonth == 1 || dayOfMonth == 15 { factor = factor * templeNewMoonFactor / 1_000 }
            if holiday == .springFestival { factor = factor * templeSpringFestivalFactor / 1_000 }
            return factor
        case .coast, .mountain, .hotSpring, .town, .nightMarket, .landmark, .harbour:
            return base
        }
    }

    /// The sights a save from before decision 772 holds as towns that are
    /// landmarks, museums or temples, by English name: the app's catalog's
    /// (`AttractionCatalog`, which `SightKindsCatalogTests` checks against
    /// this) and the blank map's (``GameWorld/blankSightKinds``).
    public static let sightKindsByName: [String: AttractionKind] = {
        let landmarks = [
            "85 Sky Tower", "Anping Old Fort", "Baguashan Buddha", "Changhua Roundhouse", "Chiang Kai-shek Memorial Hall",
            "Chihkan Tower", "Cihu", "Danjiang Bridge", "Fort San Domingo", "Hengchun Old Town", "Luce Memorial Chapel",
            "National Taichung Theater", "Old Iron Bridge of Dashu", "Sun Yat-sen Memorial Hall", "Taipei 101",
            "Taoyuan Martyrs' Shrine", "Taozhu Yinyuan", "Wanjin Basilica", "Weiwuying", "Xiluo Bridge",
        ]
        let museums = [
            "921 Earthquake Museum", "Chimei Museum", "Juming Museum", "Lanyang Museum", "Miaoli Railway Museum",
            "National Museum of Taiwan History", "National Palace Museum", "Shanshang Water Museum",
            "Southern Branch of the Palace Museum", "Yuanli Rush Weaving Museum",
        ]
        let temples = [
            "Beigang Chaotian Temple", "Chung Tai Chan Monastery", "Dajia Jenn Lann Temple", "Donglong Temple", "Fo Guang Shan",
            "Hsinchu City God Temple", "Lungshan Temple", "Madou Daitian Temple", "Nankunshen Daitian Temple", "Qingxiu Temple",
            "Tainan Confucius Temple", "Xingang Fengtian Temple", "Zhulinshan Guanyin Temple",
        ]
        var kinds = GameWorld.blankSightKinds
        for name in landmarks { kinds[name] = .landmark }
        for name in museums { kinds[name] = .museum }
        for name in temples { kinds[name] = .temple }
        return kinds
    }()

    /// A harbour's weather (decision 773), in thousandths: rain keeps
    /// more away than from other sights (the wharf is all outdoors), and
    /// a thunderstorm most (the harbour cruises and the boats stay in).
    public static let harbourRainFactor: Int64 = 600
    public static let harbourThunderstormFactor: Int64 = 300

    /// The weather's factor of a sight of `kind` (decision 772), in
    /// thousandths.
    public static func weatherFactor(_ kind: AttractionKind, clear: Bool) -> Int64 {
        weatherFactor(kind, weather: clear ? .clear : .rain)
    }

    /// The weather's factor of a sight of `kind` (decisions 772 and 773),
    /// in thousandths: a museum's more out of the rain, a harbour's less.
    public static func weatherFactor(_ kind: AttractionKind, weather: Weather) -> Int64 {
        switch (weather, kind) {
        case (.clear, _): 1_000
        case (_, .museum): museumRainFactor
        case (.rain, .harbour): harbourRainFactor
        case (.thunderstorm, .harbour): harbourThunderstormFactor
        default: 700
        }
    }

    /// The sights a save from before decision 773 holds as coasts that are
    /// harbours, by English name: the app's catalog's (`AttractionCatalog`,
    /// which `HarbourCatalogTests` checks against this) and the blank map's
    /// (``GameWorld/blankHarbourName``).
    public static let harbourNames: Set<String> = [
        "Dongshi Fisherman's Wharf", "Keziliao Fishing Port", "Nanfang'ao", "Nanliao Fishing Port", "Tamsui Fisherman's Wharf",
        "Wanggong Fishing Port", "Wuqi Fishing Port", "Yong'an Fishing Port", "Zhengbin Fishing Port", "Zhuwei Fishing Port",
        GameWorld.blankHarbourName,
    ]

    public init(attractions: [Attraction] = [], year: Int64 = 0, nextID: Int = 1) {
        self.attractions = attractions
        self.year = year
        self.nextID = nextID
    }

    /// Potential tourists a day at `stars` hundredths of a star.
    public static func potentialTourists(stars: Int) -> Int64 {
        let clamped = max(100, min(500, stars))
        let low = clamped / 100 - 1
        guard low < 4 else { return potential[4] }
        let into = Int64(clamped - 100 * (low + 1))
        return potential[low] + (potential[low + 1] - potential[low]) * into / 100
    }

    /// The day's factor, in thousandths: a holiday, a Saturday, a Sunday or
    /// a weekday.
    public static func dayFactor(weekday: Int, holiday: Bool) -> Int64 {
        if holiday { return 2_000 }
        switch weekday {
        case 6: return 1_600
        case 0: return 1_300
        default: return 600
        }
    }

    /// The season's factor of `kind` in `month` (1 to 12), in thousandths.
    public static func seasonFactor(_ kind: AttractionKind, month: Int) -> Int64 {
        switch kind {
        case .coast:
            if (6...8).contains(month) { return 1_500 }
            if month == 12 || month <= 2 { return 500 }
        case .mountain:
            if month == 10 || month == 11 { return 1_300 }
            if month == 1 || month == 2 { return 1_200 }
            if month == 7 || month == 8 { return 800 }
        case .hotSpring:
            if month >= 11 || month <= 2 { return 1_400 }
            if (6...8).contains(month) { return 700 }
        case .landmark:
            // Decision 772: the summer and winter school holidays.
            if month == 7 || month == 8 { return 1_200 }
            if month == 1 || month == 2 { return 1_100 }
        case .museum:
            if month == 7 || month == 8 { return 1_200 }
        case .harbour:
            // Decision 774, by the Tourism Administration's monthly counts
            // of the island's fishing ports (2023 and 2024, a day's mean of
            // each month): a seafood lunch is had all year; only December
            // and January, the northeast monsoon's, are a tenth quieter.
            // The Spring Festival's peak is the holiday's own factor.
            if month == 12 || month == 1 { return 900 }
        case .temple:
            // Decision 772: Mazu's pilgrimages of the third lunar month.
            if month == 4 { return 1_300 }
        case .town, .nightMarket:
            break
        }
        return 1_000
    }

    /// The tourists who set out for an attraction of `stars` on a day with
    /// these factors (all in thousandths), rounded half up.
    public static func tourists(stars: Int, day: Int64, season: Int64, weather: Int64) -> Int64 {
        let scale: Int64 = 1_000_000_000_000
        return (potentialTourists(stars: stars) * day * season * weather * captureRate + scale / 2) / scale
    }

    /// Decision 880: everyone who comes to an attraction of `stars` on a
    /// day with these factors (all in thousandths), however they come,
    /// rounded half up: ``tourists(stars:day:season:weather:)`` before
    /// ``captureRate``.
    public static func visitors(stars: Int, day: Int64, season: Int64, weather: Int64) -> Int64 {
        let scale: Int64 = 1_000_000_000
        return (potentialTourists(stars: stars) * day * season * weather + scale / 2) / scale
    }

    /// What the day's tourists spend at a shop of `level`.
    public static func shopRevenue(tourists: Int64, level: Int) -> Money {
        Money(tourists * spendPerLevel * Int64(level))
    }
}

/// The tourists' trips between stations, for one day: by origin and then
/// destination, outbound and back.
struct TouristFlows: Sendable {
    struct Pair: Sendable {
        var outbound: Int64 = 0
        var back: Int64 = 0
        /// Decision 533: the riders of the company's schools and
        /// hospitals, already shared among the 24 hours (empty for none).
        var hours: [Int64] = []

        var total: Int64 { outbound + back + hours.reduce(0, +) }
    }

    var pairs: [StationID: [StationID: Pair]] = [:]
    /// Decision 586: the rides the tourists of sights no station serves
    /// on foot take on from the station they ride to
    /// (``GameWorld/feederAccess(to:onDay:)``), there and back, by feeder.
    var feederRides: [FeederAccess.Feeder: Int64] = [:]

    var isEmpty: Bool { pairs.isEmpty }

    func trips(from origin: StationID, to destination: StationID) -> Int64 {
        pairs[origin]?[destination]?.total ?? 0
    }

    /// The pair's trips in each hour: the outbound by the scenic arrival
    /// curve of the day, the way back by its departure curve.
    func hourly(from origin: StationID, to destination: StationID) -> [Int64] {
        guard let pair = pairs[origin]?[destination] else { return Array(repeating: 0, count: 24) }
        let out = GameWorld.apportion(pair.outbound, by: Self.weights(arrival: true))
        let back = GameWorld.apportion(pair.back, by: Self.weights(arrival: false))
        let tourists = zip(out, back).map { $0 + $1 }
        return pair.hours.isEmpty ? tourists : zip(tourists, pair.hours).map { $0 + $1 }
    }

    private static func weights(arrival: Bool) -> [Int64] {
        let shape = arrival ? StationDemandKind.scenic.arrivalShape : StationDemandKind.scenic.departureShape
        return (0..<24).map { StationDemand.dayShape[$0] * shape[$0] }
    }

    mutating func add(outbound: Int64, back: Int64, from origin: StationID, to destination: StationID) {
        var pair = pairs[origin]?[destination] ?? Pair()
        pair.outbound += outbound
        pair.back += back
        pairs[origin, default: [:]][destination] = pair
    }

    /// Adds riders already shared among the 24 hours (decision 533).
    mutating func add(hours: [Int64], from origin: StationID, to destination: StationID) {
        var pair = pairs[origin]?[destination] ?? Pair()
        pair.hours = pair.hours.isEmpty ? hours : zip(pair.hours, hours).map { $0 + $1 }
        pairs[origin, default: [:]][destination] = pair
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns tourism on with these attractions, or off with `nil`
    /// (decision 174). Free. Each attraction is numbered from 1 in the
    /// order given and starts with no shop and no tourists.
    public mutating func setTourism(_ attractions: [Attraction]?) {
        // The shops go with the attractions they were in: their records
        // are written off (a later fix: a record naming a shop that no
        // longer exists made the save unloadable).
        for attraction in tourism?.attractions ?? [] where attraction.souvenir > 0 {
            disposeAsset(.souvenirShop, owner: attraction.id.rawValue)
        }
        guard let attractions, !attractions.isEmpty else {
            guard tourism != nil else { return }
            tourism = nil
            passengerPlan = PassengerPlanCache()
            return
        }
        var list: [Attraction] = []
        for (offset, source) in attractions.prefix(Tourism.maximumAttractions).enumerated() {
            list.append(Attraction(id: AttractionID(rawValue: offset + 1), name: source.name, englishName: source.englishName,
                                   point: source.point, kind: source.kind, baseStars: max(100, min(500, source.baseStars))))
        }
        tourism = Tourism(attractions: list, year: dayIndex(of: clock.now) / FinancePeriod.year.days, nextID: list.count + 1)
        passengerPlan = PassengerPlanCache()
    }

    /// Turns tourism on for a blank map with three to five attractions drawn
    /// from `seed` for each tile of ``MapExpansion/tileLength`` (16.384 km)
    /// a side (decision 174; decision 250: by the map's area, so a map that
    /// buys its map has them across all its tiles): on a cell of leisure
    /// land first, then on a steep slope or by the water (a cell next to
    /// water), and, if the tile has too few of those, anywhere inside it at
    /// least 600 m from its edge. Two are at least 3 km apart. Each has a
    /// kind that fits where it stands (water: coast, steep: mountain,
    /// leisure: a hot spring or a town), a name from its kind's list not
    /// used yet while one is left, and 2 to 4 stars.
    ///
    /// The tile with the world's middle draws as the whole map did before
    /// decision 250, so a map of one tile has the same places, kinds and
    /// stars (the names, from longer lists, differ), and the middle tile of
    /// a map that buys its map the usual map's.
    public mutating func foundAttractions(seed: UInt32) {
        let draw = SeedDraw(seed: seed)
        let tile = MapExpansion.tileLength
        let columns = (bounds.width + tile - 1) / tile, rows = (bounds.height + tile - 1) / tile
        let middle = (row: bounds.height / 2 / tile, column: bounds.width / 2 / tile)
        enum Place { case leisure, water, steep, open }
        var candidates: [(point: PlanPoint, place: Place)] = []
        for cell in land.cells where cell.use == .leisure {
            candidates.append((cellCentre(row: cell.row, column: cell.column), .leisure))
        }
        for run in terrain.steep {
            for column in run.column..<run.column + run.count { candidates.append((cellCentre(row: run.row, column: column), .steep)) }
        }
        for run in terrain.water {
            // The cell beside the run's west end, if it is dry.
            let beside = run.column - 1
            if beside >= 0, !terrain.isWater(row: run.row, column: beside) { candidates.append((cellCentre(row: run.row, column: beside), .water)) }
        }
        let margin: Int64 = 600 * WorldCoordinate.unitsPerMetre
        var chosen: [(point: PlanPoint, place: Place, key: String, index: Int)] = []
        func far(_ point: PlanPoint) -> Bool {
            let spacing = 3_000 * WorldCoordinate.unitsPerMetre
            return chosen.allSatisfy { other in
                let dx = other.point.x - point.x, dy = other.point.y - point.y
                return dx * dx + dy * dy >= spacing * spacing
            }
        }
        // The middle tile first, then the others row by row.
        var tiles = [middle]
        for row in 0..<rows {
            for column in 0..<columns where (row, column) != middle { tiles.append((row, column)) }
        }
        for (row, column) in tiles {
            let key = (row, column) == middle ? "tourism." : "tourism.\(row).\(column)."
            let west = column * tile, north = row * tile
            let east = min(west + tile, bounds.width), south = min(north + tile, bounds.height)
            let inside = candidates.filter { $0.point.x >= west && $0.point.x < west + tile && $0.point.y >= north && $0.point.y < north + tile }
            var wanted = Int(draw.roll("\(key)count", in: 3...5))
            if columns * rows > 1 {
                // A part of a tile at the world's edge: as many for its area.
                let area = (east - west) * (south - north)
                wanted = Int((Int64(wanted) * area + tile * tile / 2) / (tile * tile))
            }
            var found = 0
            var attempt = 0
            while found < wanted, attempt < 200, chosen.count < Tourism.maximumAttractions {
                defer { attempt += 1 }
                let point: PlanPoint
                let place: Place
                if !inside.isEmpty, attempt < 100 {
                    let pick = inside[Int(draw.roll("\(key)pick.\(attempt)", in: 0...Int64(inside.count - 1)))]
                    (point, place) = pick
                } else {
                    let x = draw.roll("\(key)x.\(attempt)", in: west + margin...max(west + margin, east - margin))
                    let y = draw.roll("\(key)y.\(attempt)", in: north + margin...max(north + margin, south - margin))
                    (point, place) = (PlanPoint(x: x, y: y), .open)
                }
                guard point.x >= 0, point.y >= 0, point.x < bounds.width, point.y < bounds.height, far(point) else { continue }
                chosen.append((point, place, key, found))
                found += 1
            }
        }
        var list: [Attraction] = []
        var used: Set<String> = []
        for (number, spot) in chosen.enumerated() {
            let kind: AttractionKind = switch spot.place {
            case .water: .coast
            case .steep: .mountain
            case .leisure: draw.roll("\(spot.key)kind.\(spot.index)", in: 0...1) == 0 ? .hotSpring : .town
            case .open: AttractionKind.allCases[Int(draw.roll("\(spot.key)kind.\(spot.index)", in: 0...3))]
            }
            let names = Self.attractionNames[kind]!
            // The drawn name, or the next one not used yet.
            let drawn = Int(draw.roll("\(spot.key)name.\(spot.index)", in: 0...Int64(names.count - 1)))
            let name = (0..<names.count).lazy.map { names[(drawn + $0) % names.count] }.first { !used.contains($0.chinese) } ?? names[drawn]
            used.insert(name.chinese)
            // Decision 769: the town named a night market is one; decision
            // 772: those named a temple, a museum or a landmark too.
            // Decision 773: the coast named a harbour is one.
            let named = name.english == Self.blankNightMarketName ? AttractionKind.nightMarket
                : name.english == Self.blankHarbourName ? .harbour : Self.blankSightKinds[name.english] ?? kind
            list.append(Attraction(id: AttractionID(rawValue: number + 1), name: name.chinese, englishName: name.english, point: spot.point,
                                   kind: named, baseStars: Int(draw.roll("\(spot.key)stars.\(spot.index)", in: 2...4)) * 100))
        }
        setTourism(list)
    }

    private func cellCentre(row: Int, column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * Land.cellLength + Land.cellLength / 2, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
    }

    /// The English name of the blank map's town that is a night market
    /// (decision 769).
    static let blankNightMarketName = "Night Market"

    /// The blank map's coast that is a harbour (decision 773).
    static let blankHarbourName = "Fishing Harbour"

    /// The blank map's towns that are a temple, a museum or a landmark
    /// (decision 772), by English name.
    static let blankSightKinds: [String: AttractionKind] = [
        "Mazu Temple": .temple, "Confucius Temple": .temple, "Museum": .museum, "Old Town Gate": .landmark,
    ]

    /// A blank map's names of each kind (decision 250: sixteen of each, so
    /// a map of many tiles repeats few; the first three are decision 174's).
    static let attractionNames: [AttractionKind: [(chinese: String, english: String)]] = [
        .coast: [
            ("海岬燈塔", "Cape Lighthouse"), ("白沙灣", "White Sand Bay"), ("礁岩海岸", "Reef Coast"), ("漁港碼頭", "Fishing Harbour"),
            ("夕陽海堤", "Sunset Seawall"), ("貝殼沙灘", "Shell Beach"), ("海蝕洞", "Sea Caves"), ("紅樹林", "Mangrove Shore"),
            ("觀浪步道", "Wave-watching Trail"), ("濕地鳥園", "Wetland Bird Park"), ("藍色海灣", "Blue Bay"), ("防風林海岸", "Windbreak Coast"),
            ("岬角草原", "Headland Meadow"), ("鹽田", "Salt Pans"), ("潮間帶", "Tidal Flats"), ("沙丘", "Sand Dunes"),
        ],
        .mountain: [
            ("雲海山頂", "Sea-of-Clouds Peak"), ("森林步道", "Forest Trail"), ("高山湖", "Alpine Lake"), ("瀑布谷", "Waterfall Valley"),
            ("茶園山坡", "Tea Hills"), ("神木林", "Giant Tree Grove"), ("吊橋峽谷", "Suspension Bridge Gorge"), ("楓紅山谷", "Maple Valley"),
            ("觀日峰", "Sunrise Peak"), ("竹林小徑", "Bamboo Path"), ("櫻花林道", "Cherry Blossom Road"), ("螢火蟲谷", "Firefly Valley"),
            ("水庫湖畔", "Reservoir Shore"), ("石壁步道", "Cliff Trail"), ("高山牧場", "Highland Ranch"), ("星空草原", "Starlit Meadow"),
        ],
        .hotSpring: [
            ("溫泉鄉", "Hot Spring Village"), ("湯谷溫泉", "Hot Valley Spa"), ("碧潭溫泉", "Green Pool Spa"), ("冷泉公園", "Cold Spring Park"),
            ("泥漿溫泉", "Mud Spring"), ("溪畔湯屋", "Riverside Baths"), ("硫磺谷", "Sulphur Valley"), ("地熱谷", "Thermal Valley"),
            ("山中湯宿", "Mountain Spa Inn"), ("竹林溫泉", "Bamboo Grove Spa"), ("碳酸泉", "Soda Spring"), ("雲霧溫泉", "Misty Spa"),
            ("櫻花溫泉", "Blossom Spa"), ("足湯廣場", "Foot Bath Square"), ("野溪溫泉", "Wild Creek Spring"), ("溫泉老街", "Spa Street"),
        ],
        .town: [
            ("老街", "Old Street"), ("古城門", "Old Town Gate"), ("市集廣場", "Market Square"), ("夜市", "Night Market"),
            ("媽祖廟", "Mazu Temple"), ("糖廠", "Sugar Mill"), ("舊車站", "Old Station"), ("眷村", "Military Village"),
            ("紅磚古厝", "Red Brick Mansion"), ("文創園區", "Creative Park"), ("藝術村", "Art Village"), ("主題樂園", "Theme Park"),
            ("博物館", "Museum"), ("觀光工廠", "Factory Tour"), ("燈會廣場", "Lantern Square"), ("孔廟", "Confucius Temple"),
        ],
    ]

    /// Builds the next level of attraction `id`'s souvenir shop: $300,000 a
    /// level, kept as a building asset (30 years).
    ///
    /// - Throws: ``GameError/tourismNotEnabled``,
    ///   ``GameError/unknownAttraction(_:)``, ``GameError/attractionMaxedOut``,
    ///   ``GameError/insufficientFunds(required:available:)``.
    public mutating func investInSouvenirShop(of id: AttractionID) throws(GameError) {
        guard let tourism else { throw .tourismNotEnabled }
        guard let index = tourism.attractions.firstIndex(where: { $0.id == id }) else { throw .unknownAttraction(id) }
        guard tourism.attractions[index].souvenir < Tourism.maximumSouvenirLevel else { throw .attractionMaxedOut }
        let price = Money(Tourism.souvenirCost)
        try economy.spend(price)
        self.tourism!.attractions[index].souvenir += 1
        recordSouvenirAsset(of: id, cost: price)
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - Queries

    public func attraction(id: AttractionID) -> Attraction? {
        tourism?.attractions.first { $0.id == id }
    }

    /// The station that serves attraction `id`: the nearest within 800 m
    /// that a passenger line calls at and that takes passengers, or `nil`.
    /// Since decision 586, when none does, the station a cableway with a
    /// stop near it meets (``feederAccess(to:onDay:)``), whether or not
    /// it runs today; since decision 589, when no cableway does, the one a
    /// ferry route with a pier near it sails from; since decision 587,
    /// when neither does, the one a bus route with a stop near it brings
    /// riders to.
    public func attractionStation(of id: AttractionID) -> StationID? {
        guard let attraction = attraction(id: id) else { return nil }
        return servingStation(at: attraction.point) ?? feederAccess(to: attraction.point, onDay: nil)?.station
    }

    func servingStation(at point: PlanPoint) -> StationID? {
        let limit = Tourism.reach * Tourism.reach
        var best: (StationID, Int64)?
        for station in stations {
            let dx = station.point.x - point.x, dy = station.point.y - point.y
            let squared = dx * dx + dy * dy
            guard squared <= limit, takesTourists(station.id) else { continue }
            if best == nil || (squared, station.id) < (best!.1, best!.0) { best = (station.id, squared) }
        }
        return best?.0
    }

    /// Whether station `id` can take tourists: it takes passengers, has
    /// demand and a passenger line calls at it.
    func takesTourists(_ id: StationID) -> Bool {
        allowsService(at: id) && stationDemand(of: id) != nil
            && lines.contains(where: { !$0.isFreight && $0.hasTrainsCalling(at: id) })
    }

    /// Decision 586: the station whose tourists come to `point` on game
    /// day `day`: the one that serves it on foot (``servingStation(at:)``)
    /// or, when none does, the one a feeder brings them from
    /// (``feederAccess(to:onDay:)``); `nil` for neither.
    func touristStation(at point: PlanPoint, onDay day: Int64) -> StationID? {
        servingStation(at: point) ?? feederAccess(to: point, onDay: day)?.station
    }

    /// Decision 586: how tourists reach `point` on game day `day` when no
    /// station serves it on foot: by train to the station a feeder meets,
    /// then on by the feeder to its stop within ``Tourism/reach`` of the
    /// point. A cableway first (``cablewayAccess(to:onDay:)``); since
    /// decision 589, when none reaches it, a ferry route
    /// (``ferryAccess(to:onDay:)``); since decision 587, when neither
    /// does, a bus route (``busAccess(to:)``), the order the land near
    /// them is shared in (decision 585). `nil` for none. Called only after
    /// ``servingStation(at:)`` found none: a station within reach keeps its
    /// sights.
    func feederAccess(to point: PlanPoint, onDay day: Int64?) -> FeederAccess? {
        cablewayAccess(to: point, onDay: day) ?? ferryAccess(to: point, onDay: day) ?? busAccess(to: point)
    }

    /// Decision 589: the ferry routes with a boat that sail that day
    /// (``ferryRouteIsOpen(_:onDay:)``; any day for `nil`) and have a
    /// station taking tourists (``takesTourists(_:)``) within
    /// ``Tourism/reach`` of a pier, the nearest (then the lower station,
    /// then the earlier pier): tourists walk to and from the boats as they
    /// walk to a sight, farther than a commuter's ``BusRoute/stopReach``
    /// (MRT Tamsui is some 700 m from its ferry pier). The sight's pier is
    /// one of the route's within ``Tourism/reach`` of `point` other than
    /// the one by that station (from there they would walk), the nearest,
    /// then the lower route, then the earlier pier. `nil` for none.
    func ferryAccess(to point: PlanPoint, onDay day: Int64?) -> FeederAccess? {
        guard !ferryRoutes.isEmpty else { return nil }
        let limit = Tourism.reach * Tourism.reach
        var best: (squared: Int64, route: Int, pier: Int, station: StationID)?
        for route in ferryRoutes where route.headway != nil {
            guard day.map({ ferryRouteIsOpen(route.id, onDay: $0) && route.dailyDepartures(onDay: $0) > 0 }) ?? true else { continue }
            let near = route.piers.indices.compactMap { index -> (squared: Int64, pier: Int)? in
                let squared = Self.squaredDistance(Self.middle(of: route.piers[index]), point)
                return squared <= limit ? (squared, index) : nil
            }
            guard !near.isEmpty else { continue }
            var meets: (squared: Int64, station: StationID, pier: Int)?
            for (index, cell) in route.piers.enumerated() {
                let middle = Self.middle(of: cell)
                for station in stations {
                    let squared = Self.squaredDistance(middle, station.point)
                    guard squared <= limit, takesTourists(station.id) else { continue }
                    if meets.map({ (squared, station.id.rawValue, index) < ($0.squared, $0.station.rawValue, $0.pier) }) ?? true {
                        meets = (squared, station.id, index)
                    }
                }
            }
            guard let meets else { continue }
            for (squared, pier) in near where pier != meets.pier {
                let candidate = (squared, route.id.rawValue, pier, meets.station)
                if best.map({ (candidate.0, candidate.1, candidate.2) < ($0.squared, $0.route, $0.pier) }) ?? true { best = candidate }
            }
        }
        return best.map { FeederAccess(station: $0.station, feeder: .ferry(FerryRouteID(rawValue: $0.route))) }
    }

    /// Decision 586: the cableways that meet a station taking tourists
    /// (``takesTourists(_:)``) and run that day
    /// (``cablewayIsOpen(_:onDay:)``; any day for `nil`); the stop is a
    /// boarding stop other than the one that meets the station (from
    /// there they would walk), the nearest, then the lower cableway, then
    /// the earlier stop. `nil` for none.
    func cablewayAccess(to point: PlanPoint, onDay day: Int64?) -> FeederAccess? {
        guard !cableways.isEmpty else { return nil }
        let limit = Tourism.reach * Tourism.reach
        var best: (squared: Int64, cableway: Int, stop: Int, station: StationID)?
        for cableway in cableways {
            guard let transfer = cableway.transfer, takesTourists(transfer.station),
                  day.map({ cablewayIsOpen(cableway.id, onDay: $0) }) ?? true else { continue }
            for (index, stop) in cableway.stops.enumerated() where stop.boards && index != transfer.stop {
                let squared = Self.squaredDistance(Self.middle(of: stop.cell), point)
                guard squared <= limit else { continue }
                let candidate = (squared, cableway.id.rawValue, index, transfer.station)
                if best.map({ (candidate.0, candidate.1, candidate.2) < ($0.squared, $0.cableway, $0.stop) }) ?? true { best = candidate }
            }
        }
        return best.map { FeederAccess(station: $0.station, feeder: .cableway(CablewayID(rawValue: $0.cableway))) }
    }

    /// Decision 587: the bus routes that run (a departure a day at least)
    /// and bring riders to a station taking tourists: a feeder's own
    /// station, or for a city route ``busTouristTransfer(of:)``. The stop
    /// is one of the route's within ``Tourism/reach`` of `point` other than
    /// the one a city route meets the station at (from there they would
    /// walk), the nearest, then the lower route, then the earlier stop.
    /// Buses run every day. `nil` for none.
    func busAccess(to point: PlanPoint) -> FeederAccess? {
        guard !busRoutes.isEmpty else { return nil }
        let limit = Tourism.reach * Tourism.reach
        var best: (squared: Int64, route: Int, stop: Int, station: StationID)?
        for route in busRoutes where route.dailyDepartures > 0 {
            let near = route.stops.indices.compactMap { index -> (squared: Int64, stop: Int)? in
                let squared = Self.squaredDistance(Self.middle(of: route.stops[index]), point)
                return squared <= limit ? (squared, index) : nil
            }
            guard !near.isEmpty else { continue }
            let meets: BusTransfer
            if let station = route.station {
                guard takesTourists(station) else { continue }
                meets = BusTransfer(station: station, stop: route.stops.count)
            } else {
                guard let transfer = busTouristTransfer(of: route) else { continue }
                meets = transfer
            }
            for (squared, stop) in near where stop != meets.stop {
                let candidate = (squared, route.id.rawValue, stop, meets.station)
                if best.map({ (candidate.0, candidate.1, candidate.2) < ($0.squared, $0.route, $0.stop) }) ?? true { best = candidate }
            }
        }
        return best.map { FeederAccess(station: $0.station, feeder: .bus(BusRouteID(rawValue: $0.route))) }
    }

    /// Decision 587: the station a city route brings tourists to, as its
    /// ``BusRoute/transfer`` is found but among the stations that take
    /// them (``takesTourists(_:)``; a depot on a bought line does not):
    /// the nearest within ``BusRoute/stopReach`` of a stop's middle, then
    /// the lower station, then the earlier stop. `nil` for none.
    func busTouristTransfer(of route: BusRoute) -> BusTransfer? {
        let reach = BusRoute.stopReach * BusRoute.stopReach
        var best: (squared: Int64, station: Int, stop: Int)?
        for (stop, cell) in route.stops.enumerated() {
            let middle = Self.middle(of: cell)
            for station in landStations {
                let squared = Self.squaredDistance(middle, station.location)
                guard squared <= reach else { continue }
                let candidate = (squared, station.id.rawValue, stop)
                if best.map({ candidate < $0 }) ?? true, takesTourists(station.id) { best = candidate }
            }
        }
        return best.map { BusTransfer(station: StationID(rawValue: $0.station), stop: $0.stop) }
    }

    /// The company's hotels within ``SubsidiaryRules/reach`` of
    /// `attraction`.
    public func hotelsNear(_ attraction: Attraction) -> Int {
        let reach = SubsidiaryRules.reach
        return placedBuildings.count { building in
            guard building.kind == .hotel else { return false }
            let dx = building.centre.x - attraction.point.x, dy = building.centre.y - attraction.point.y
            return dx * dx + dy * dy <= reach * reach
        }
    }

    /// The rating of `attraction` now, in hundredths of a star: its own
    /// (``Attraction/stars``, with its shop), a quarter star for each of
    /// the first two hotels near it and half a star when a sightseeing
    /// train calls near it (decision 286; a whole star for the Ming-Ri,
    /// three quarters for the Formosa Star, a star and a quarter for the
    /// Midsummer Formosa), five stars at most.
    public func stars(of attraction: Attraction) -> Int {
        stars(of: attraction, sightseeingStops: sightseeingStops())
    }

    /// The same, given ``sightseeingStops()``, worked out once for every
    /// sight.
    func stars(of attraction: Attraction, sightseeingStops: [SightseeingStop]) -> Int {
        let train = Self.sightseeingStars(near: attraction, of: sightseeingStops)
        return min(500, attraction.stars + Tourism.starsPerHotel * min(Tourism.hotelsCounted, hotelsNear(attraction)) + train)
    }

    /// Whether a sightseeing train (decision 286) calls at a station within
    /// ``Tourism/reach`` of `attraction`.
    public func hasSightseeingTrain(near attraction: Attraction) -> Bool {
        sightseeingTrainStars(near: attraction) > 0
    }

    /// What the sightseeing trains calling within ``Tourism/reach`` of
    /// `attraction` add to it, in hundredths of a star: the most any of
    /// them adds (decision 286), none when none calls.
    public func sightseeingTrainStars(near attraction: Attraction) -> Int {
        Self.sightseeingStars(near: attraction, of: sightseeingStops())
    }

    /// A station a sightseeing train calls at, and the most a train calling
    /// there adds (``TrainType/sightseeingStars``).
    struct SightseeingStop {
        let point: PlanPoint
        let stars: Int
    }

    /// The stations that take passengers where a passenger line, or one of
    /// its patterns, has a train of a sightseeing type (decision 286) to
    /// call; empty, and quick, when the company has none.
    func sightseeingStops() -> [SightseeingStop] {
        var starsOfTrain: [TrainID: Int] = [:]
        for train in trains {
            if let stars = train.type?.sightseeingStars, stars > 0 { starsOfTrain[train.id] = stars }
        }
        guard !starsOfTrain.isEmpty else { return [] }
        func most(_ trains: [TrainID]) -> Int { trains.reduce(0) { max($0, starsOfTrain[$1] ?? 0) } }
        var called: [StationID: Int] = [:]
        func call(_ station: StationID, _ stars: Int) { called[station] = max(called[station] ?? 0, stars) }
        for line in lines where !line.isFreight {
            let stars = most(line.trains)
            if stars > 0 { for station in line.stops { call(station, stars) } }
            for pattern in line.patterns {
                let stars = most(pattern.trains)
                guard stars > 0 else { continue }
                for index in pattern.calls where line.stops.indices.contains(index) { call(line.stops[index], stars) }
            }
        }
        return stations.compactMap { station in
            guard let stars = called[station.id], allowsService(at: station.id) else { return nil }
            return SightseeingStop(point: station.point, stars: stars)
        }
    }

    /// The most a stop within ``Tourism/reach`` of `attraction` adds.
    static func sightseeingStars(near attraction: Attraction, of stops: [SightseeingStop]) -> Int {
        stops.reduce(0) { most, stop in
            let dx = stop.point.x - attraction.point.x, dy = stop.point.y - attraction.point.y
            return dx * dx + dy * dy <= Tourism.reach * Tourism.reach ? max(most, stop.stars) : most
        }
    }

    // MARK: - The company's sights (decision 361 and its sequel)

    /// The ID a temple's or a night market's sight goes by: its
    /// building's, negative, so it is never an attraction's.
    static func companySightID(of building: PlacedBuildingID) -> AttractionID {
        AttractionID(rawValue: -building.rawValue)
    }

    /// The company's temples (decision 361) and night markets (its sequel)
    /// as sights, by building: each a town of ``Tourism/templeStars`` or
    /// ``Tourism/nightMarketStars`` at its centre, with how many of the
    /// company's buildings of its kind within ``Tourism/reach`` of it
    /// (itself included) share its tourists. None without tourism.
    func companySights() -> [(building: PlacedBuildingID, sight: Attraction, sharing: Int64)] {
        guard tourism != nil else { return [] }
        let sights = placedBuildings.filter(\.kind.isSight)
        let reach = Tourism.reach * Tourism.reach
        return sights.map { building in
            let sharing = sights.count { other in
                let dx = other.centre.x - building.centre.x, dy = other.centre.y - building.centre.y
                return other.kind == building.kind && dx * dx + dy * dy <= reach
            }
            let (name, englishName, stars) = switch building.kind {
            case .temple: ("廟", "Temple", Tourism.templeStars)
            case .railwayMuseum: ("鐵道博物館", "Railway museum", Tourism.museumStars(exhibits: building.exhibits.count))
            default: ("夜市", "Night market", Tourism.nightMarketStars)
            }
            // Decision 769: a night market keeps a night market's hours.
            // Decision 772 leaves the company's temple and museum towns:
            // they are its own buildings, of their own rules (decisions 361
            // and 684), not the island's famous ones.
            let sight = Attraction(id: Self.companySightID(of: building.id), name: name, englishName: englishName,
                                   point: building.centre, kind: building.kind == .nightMarket ? .nightMarket : .town, baseStars: stars)
            return (building.id, sight, Int64(max(1, sharing)))
        }
    }

    /// Decision 769, a save from before it: the sights it holds as towns
    /// that are night markets become ``AttractionKind/nightMarket``. A
    /// save names its sights but keeps no key to the catalog they came
    /// from, so a night market is told by its English name: each of the
    /// catalog's (the app's `AttractionCatalog`) and the blank map's ends in
    /// "Night Market", and no other sight's does.
    mutating func reclassifyNightMarkets() {
        guard var tourism else { return }
        for index in tourism.attractions.indices
        where tourism.attractions[index].kind == .town && tourism.attractions[index].englishName.hasSuffix("Night Market") {
            tourism.attractions[index].kind = .nightMarket
        }
        self.tourism = tourism
    }

    /// Decision 772, a save from before it: the sights it holds as towns
    /// that are landmarks, museums or temples take their kind, told by
    /// English name as decision 769's night markets are
    /// (``Tourism/sightKindsByName``).
    mutating func reclassifySightKinds() {
        guard var tourism else { return }
        for index in tourism.attractions.indices where tourism.attractions[index].kind == .town {
            if let kind = Tourism.sightKindsByName[tourism.attractions[index].englishName] {
                tourism.attractions[index].kind = kind
            }
        }
        self.tourism = tourism
    }

    /// Decision 773, a save from before it: the sights it holds as coasts
    /// that are harbours take their kind, told by English name
    /// (``Tourism/harbourNames``).
    mutating func reclassifyHarbours() {
        guard var tourism else { return }
        for index in tourism.attractions.indices
        where tourism.attractions[index].kind == .coast && Tourism.harbourNames.contains(tourism.attractions[index].englishName) {
            tourism.attractions[index].kind = .harbour
        }
        self.tourism = tourism
    }

    /// The world's railway museum (decision 684), or `nil`.
    public var railwayMuseum: PlacedBuilding? {
        placedBuildings.first { $0.kind == .railwayMuseum }
    }

    /// The types of train the company owns now, each once, in the
    /// catalog's order (decision 684): what a museum takes as exhibits. A
    /// train of the standard car, of no type, is none.
    public func ownedTrainTypes() -> [TrainType] {
        Set(trains.compactMap(\.type)).sorted { $0.row < $1.row }
    }

    /// Adds the types of train the company owns now to its museum's
    /// exhibits (decision 684); those it has stay.
    mutating func collectMuseumExhibits() {
        guard let index = placedBuildings.firstIndex(where: { $0.kind == .railwayMuseum }) else { return }
        let owned = ownedTrainTypes()
        guard !owned.allSatisfy(placedBuildings[index].exhibits.contains) else { return }
        placedBuildings[index].exhibits = Set(placedBuildings[index].exhibits + owned).sorted { $0.row < $1.row }
    }

    /// Why the company's sight `id`, a temple, a night market or a railway
    /// museum, draws no tourists now, or ``AttractionStatus/ok``
    /// (decision 684, for the sights panel); ``AttractionStatus/noStation``
    /// for none or without tourism.
    public func companySightStatus(of id: PlacedBuildingID) -> AttractionStatus {
        guard let sight = companySight(of: id) else { return .noStation }
        var asked = AttractionStatusAsked(day: dayIndex(of: clock.now))
        return attractionStatus(of: sight, asked: &asked)
    }

    /// The station that serves `sight`, any sight value, on foot, as
    /// ``attractionStation(of:)`` an attraction's (decision 684).
    public func servingStationID(of sight: Attraction) -> StationID? {
        servingStation(at: sight.point)
    }

    /// The company's temple or night market `id` as a sight (decision 361
    /// and its sequel), to rate it with ``stars(of:)``, or `nil` for none
    /// or without tourism.
    public func companySight(of id: PlacedBuildingID) -> Attraction? {
        companySights().first { $0.building == id }?.sight
    }

    /// The tourists temple or night market `building` draws on game day
    /// `day` (decision 361 and its sequel): the day that has just closed as
    /// it counted them (``PlacedBuilding/visitors``), any other day its
    /// share of those expected if a station serves it. None without
    /// tourism.
    public func sightVisitors(of building: PlacedBuilding, onDay day: Int64) -> Int64 {
        guard building.kind.isSight, tourism != nil else { return 0 }
        if day == dayIndex(of: clock.now) - 1 { return building.visitors }
        guard let entry = companySights().first(where: { $0.building == building.id }), touristStation(at: building.centre, onDay: day) != nil else {
            return 0
        }
        return touristsExpected(for: entry.sight, onDay: day) / entry.sharing
    }

    /// The tourists of game day `day` who stay in hotels near `attraction`,
    /// counted for one hotel's customers (decision 174): the day that has
    /// just closed as the sight counted it (``Attraction/yesterday``),
    /// any other day as expected if a station serves it.
    func hotelGuests(of attraction: Attraction, onDay day: Int64) -> Int64 {
        let tourists: Int64
        if day == dayIndex(of: clock.now) - 1 {
            tourists = attraction.yesterday
        } else {
            tourists = touristStation(at: attraction.point, onDay: day) == nil ? 0 : touristsExpected(for: attraction, onDay: day)
        }
        return tourists * Tourism.hotelStayPermille / 1_000 / Int64(max(1, hotelsNear(attraction)))
    }

    /// The tourists attraction `id` draws on game day `day` before the
    /// railway is asked: its rating, the day, the season, the weather and
    /// any typhoon. 0 while a typhoon blows over it.
    public func touristsExpected(at id: AttractionID, onDay day: Int64) -> Int64 {
        guard let attraction = attraction(id: id) else { return 0 }
        return touristsExpected(for: attraction, onDay: day)
    }

    /// The same for any attraction value, for example one with the next level of shop.
    public func touristsExpected(for attraction: Attraction, onDay day: Int64) -> Int64 {
        guard let factors = dayFactors(of: attraction, onDay: day) else { return 0 }
        return Tourism.tourists(stars: stars(of: attraction), day: factors.day, season: factors.season, weather: factors.weather)
    }

    /// Decision 880: everyone who comes to `attraction` on game day `day`,
    /// however they come (``Tourism/visitors(stars:day:season:weather:)``):
    /// ``touristsExpected(for:onDay:)`` before ``Tourism/captureRate``. 0
    /// while a typhoon blows over it.
    public func visitorsExpected(for attraction: Attraction, onDay day: Int64) -> Int64 {
        guard let factors = dayFactors(of: attraction, onDay: day) else { return 0 }
        return Tourism.visitors(stars: stars(of: attraction), day: factors.day, season: factors.season, weather: factors.weather)
    }

    /// The day's, the season's and the weather's factors of `attraction` on
    /// game day `day`, in thousandths; `nil` while a typhoon blows over it.
    private func dayFactors(of attraction: Attraction, onDay day: Int64) -> (day: Int64, season: Int64, weather: Int64)? {
        let blowing = typhoons(onDay: day).contains { $0.isActive(onDay: day) && $0.covers(attraction.point) }
        guard !blowing else { return nil }
        let year = FinancePeriod.year.days
        let dayOfYear = day - CompanyAccounts.floorDivide(day, year) * year
        let month = Int(dayOfYear / 30) + 1
        // Decision 772: by the sight's kind.
        let dayFactor = Tourism.dayFactor(attraction.kind, weekday: StationDemand.weekday(ofDay: day), holiday: holiday(onDay: day)?.holiday.kind,
                                          dayOfMonth: Int(dayOfYear % 30) + 1)
        // Decision 773: a harbour's by the kind of weather.
        let weather = Tourism.weatherFactor(attraction.kind, weather: self.weather(onDay: day))
        return (dayFactor, Tourism.seasonFactor(attraction.kind, month: month), weather)
    }

    /// Why attraction `id` draws no tourists now, or ``AttractionStatus/ok``.
    public func attractionStatus(of id: AttractionID) -> AttractionStatus {
        guard let attraction = attraction(id: id) else { return .noStation }
        var asked = AttractionStatusAsked(day: dayIndex(of: clock.now))
        return attractionStatus(of: attraction, asked: &asked)
    }

    /// ``attractionStatus(of:)`` of every attraction, the same answers
    /// worked out together: the day's network (``Tourism/countingGraph(of:day:)``,
    /// a tenth of a second for one bought metro line), the stations
    /// tourists set out from and which of them can ride to a station, once
    /// for all of them rather than once for each sight. The sights panel
    /// asks it (CRASH-SIGHTS: once a sight each, its rows took seconds on
    /// a big network and froze the game while it stayed open).
    public func attractionStatuses() -> [AttractionID: AttractionStatus] {
        var asked = AttractionStatusAsked(day: dayIndex(of: clock.now))
        var statuses: [AttractionID: AttractionStatus] = [:]
        for attraction in tourism?.attractions ?? [] {
            statuses[attraction.id] = attractionStatus(of: attraction, asked: &asked)
        }
        return statuses
    }

    /// What ``attractionStatus(of:)`` works out once for any number of
    /// sights on day `day`: the network, the stations tourists set out
    /// from, and whether each can ride to a station.
    struct AttractionStatusAsked {
        struct Pair: Hashable {
            let from: StationID
            let to: StationID
        }

        let day: Int64
        var graph: PassengerRouteGraph??
        var candidates: [(station: StationID, outside: Bool, residents: Int64)]?
        var reaches: [Pair: Bool] = [:]
    }

    func attractionStatus(of attraction: Attraction, asked: inout AttractionStatusAsked) -> AttractionStatus {
        let day = asked.day
        if typhoons(onDay: day).contains(where: { $0.isActive(onDay: day) && $0.covers(attraction.point) }) { return .typhoon }
        guard let station = touristStation(at: attraction.point, onDay: day) else { return .noStation }
        // Decision 551: the network at today's noon, as the day is counted,
        // so a sight does not read "nobody can ride there" at night; each
        // line within its hours (decision 551, continued).
        if asked.graph == nil {
            asked.graph = .some(passengerRoutingMode == .network ? Tourism.countingGraph(of: self, day: day) : nil)
        }
        let graph = asked.graph ?? nil
        if asked.candidates == nil { asked.candidates = touristCandidates() }
        var known = asked.reaches
        let sources = touristSources(to: station, among: asked.candidates ?? []) { origin in
            let pair = AttractionStatusAsked.Pair(from: origin, to: station)
            if let answer = known[pair] { return answer }
            let answer = reaches(from: origin, to: station, graph: graph)
            known[pair] = answer
            return answer
        }
        asked.reaches = known
        return sources.isEmpty ? .noSource : .ok
    }

    /// Whether anyone at `origin` can ride to `destination`.
    func reaches(from origin: StationID, to destination: StationID, graph: PassengerRouteGraph?) -> Bool {
        if let graph { return !passengerRouteChoices(from: origin, to: destination, graph: graph).isEmpty }
        return passengerTrip(from: origin, to: destination) != nil
    }

    /// The stations tourists could set out from, worked out once for a day's
    /// flows: those that take passengers and have demand, with whether each
    /// is an outside connection and its residents (decision 137, Phase 6a).
    func touristCandidates() -> [(station: StationID, outside: Bool, residents: Int64)] {
        stations.compactMap { candidate in
            guard allowsEntry(at: candidate.id), stationDemand(of: candidate.id) != nil else { return nil }
            return (candidate.id, isOutsideConnection(candidate.id), landCatchment(of: candidate.id)?.residents ?? 0)
        }
    }

    /// The stations tourists set out from for the attraction served by
    /// `station`, with their weight, among those `reaches` says can ride
    /// there: each outside connection at ``Tourism/outsideWeight``, and the
    /// busiest ``Tourism/busiestSources`` of them by residents at their
    /// residents (the two add up for a station that is both); by ascending
    /// station, never `station` itself. Decision 601: the busiest are picked
    /// among those that can ride there, not on the whole map and then
    /// dropped when they cannot (a branch line's sights had no tourists
    /// once five bigger stations stood anywhere else); `reaches` is asked
    /// in order of residents and no more once five have answered.
    func touristSources(to station: StationID,
                        among candidates: [(station: StationID, outside: Bool, residents: Int64)],
                        reaches: (StationID) -> Bool) -> [(station: StationID, weight: Int64)] {
        var weights: [StationID: Int64] = [:]
        var answered: [StationID: Bool] = [:]
        func rides(_ source: StationID) -> Bool {
            if let known = answered[source] { return known }
            let found = reaches(source)
            answered[source] = found
            return found
        }
        var residential: [(StationID, Int64)] = []
        for candidate in candidates where candidate.station != station {
            if candidate.outside, rides(candidate.station) { weights[candidate.station, default: 0] += Tourism.outsideWeight }
            if candidate.residents > 0 { residential.append((candidate.station, candidate.residents)) }
        }
        // Decision 695: those who land at an airport set out from its
        // station, at the airport's passengers of a day.
        if !airports.isEmpty {
            let landing = airportTouristWeights()
            for id in landing.keys.sorted() where id != station && rides(id) {
                weights[id, default: 0] += landing[id]!
            }
        }
        residential.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        var picked = 0
        for (id, residents) in residential where picked < Tourism.busiestSources && rides(id) {
            weights[id, default: 0] += residents
            picked += 1
        }
        return weights.keys.sorted().map { ($0, weights[$0]!) }
    }

    /// The tourists' trips on game day `day`, each attraction's tourists
    /// shared among the sources that can ride to its station (and back),
    /// `reaches` saying which pairs can ride. Empty without tourism. With a
    /// day pass on sale (decision 324), its buyers' rides on to the next
    /// sight and back too, counted as that sight's visitors, and the day's
    /// passes.
    func touristFlows(onDay day: Int64, reaches: (StationID, StationID) -> Bool)
        -> (flows: TouristFlows, arrivals: [AttractionID: Int64], passes: DayPassDay) {
        var flows = TouristFlows()
        var arrivals: [AttractionID: Int64] = [:]
        var passes = DayPassDay()
        guard let tourism else { return (flows, arrivals, passes) }
        let candidates = touristCandidates()
        // Several sights a station serves share its sources (decision 601).
        var sourcesOf: [StationID: [(station: StationID, weight: Int64)]] = [:]
        var visited: [(station: StationID, tourists: [(source: StationID, count: Int64, back: Bool)])] = []
        // Decision 361: the company's temples (and since its sequel night
        // markets), after the sights; those of a kind near one another
        // share their tourists.
        let rated = tourism.attractions.map { (sight: $0, sharing: Int64(1)) } + companySights().map { ($0.sight, $0.sharing) }
        for (attraction, sharing) in rated {
            let expected = touristsExpected(for: attraction, onDay: day) / sharing
            guard expected > 0 else { continue }
            // Decision 586: a sight no station serves on foot, by train to
            // the station a feeder meets and on by the feeder.
            let served = servingStation(at: attraction.point)
            let feeder = served == nil ? feederAccess(to: attraction.point, onDay: day) : nil
            guard let station = served ?? feeder?.station else { continue }
            let sources: [(station: StationID, weight: Int64)]
            if let known = sourcesOf[station] {
                sources = known
            } else {
                sources = touristSources(to: station, among: candidates) { reaches($0, station) }
                sourcesOf[station] = sources
            }
            guard !sources.isEmpty else { continue }
            let shares = Self.apportion(expected, by: sources.map(\.weight))
            var tourists: [(source: StationID, count: Int64, back: Bool)] = []
            // Decision 769: a night market's tourists ride in its evening;
            // decision 772: a museum's, a temple's and a landmark's in theirs.
            let hours = Tourism.hours(of: attraction.kind)
            for (source, share) in zip(sources, shares) where share > 0 {
                if let hours {
                    flows.add(hours: Self.apportion(share, by: hours.arrivals), from: source.station, to: station)
                } else {
                    flows.add(outbound: share, back: 0, from: source.station, to: station)
                }
                let back = reaches(station, source.station)
                if back, let hours {
                    flows.add(hours: Self.apportion(share, by: hours.departures), from: station, to: source.station)
                } else if back {
                    flows.add(outbound: 0, back: share, from: station, to: source.station)
                }
                tourists.append((source.station, share, back))
                if let feeder { flows.feederRides[feeder.feeder, default: 0] += back ? 2 * share : share }
            }
            arrivals[attraction.id] = shares.reduce(0, +)
            // A temple's pilgrims and a night market's visitors ride there
            // and back; the day pass is sold to those of the sights. Not
            // to those a feeder takes on (decision 586): the pass is the
            // railway's, and the ride on is not on it.
            guard attraction.id.rawValue > 0, feeder == nil else { continue }
            visited.append((station, tourists))
        }
        guard accounts.mode == .management, let price = accounts.dayPass else { return (flows, arrivals, passes) }
        // Decision 324: who buys a pass, and the rides it adds.
        let sights = tourism.attractions.compactMap { sight in servingStation(at: sight.point).map { (id: sight.id, station: $0) } }
        for (station, tourists) in visited {
            let next = nextSight(from: station, among: sights, reaches: reaches)
            let ride = next.map { passFare(from: station, to: $0.station) + passFare(from: $0.station, to: station) } ?? .zero
            for tourist in tourists {
                let journey = passFare(from: tourist.source, to: station) + (tourist.back ? passFare(from: station, to: tourist.source) : .zero)
                let buyers = tourist.count * DayPass.uptake(price: price, value: journey + ride) / 1_000
                guard buyers > 0 else { continue }
                passes.sold += buyers
                passes.journeyFares = passes.journeyFares + Money(buyers * journey.amount)
                passes.visits[station, default: 0] += buyers
                if let next {
                    flows.add(outbound: buyers, back: 0, from: station, to: next.station)
                    flows.add(outbound: 0, back: buyers, from: next.station, to: station)
                    arrivals[next.id, default: 0] += buyers
                    passes.visits[next.station, default: 0] += buyers
                    passes.rides += 2 * buyers
                    passes.rideFares = passes.rideFares + Money(buyers * ride.amount)
                }
            }
        }
        passes.sales = Self.wholeDollars(passes.sold * price.amount)
        passes.journeyFares = Self.wholeDollars(passes.journeyFares.amount)
        passes.rideFares = Self.wholeDollars(passes.rideFares.amount)
        return (flows, arrivals, passes)
    }

    /// Today's tourist trips as the passenger model reaches them now (an
    /// empty set without tourism).
    /// Since decision 533 with the riders of the company's schools and
    /// hospitals too (``passengerExtraFlows(onDay:reaches:)``).
    func currentTouristFlows() -> TouristFlows {
        guard tourism != nil || !civicRiderBuildings.isEmpty || !airports.isEmpty || !coachStops.isEmpty else { return TouristFlows() }
        let world = self
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        return world.passengerExtraFlows(onDay: dayIndex(of: clock.now)) { world.reaches(from: $0, to: $1, graph: graph) }
    }

    /// The trips the passenger plan adds to the stations' own on game day
    /// `day`: the tourists' (decision 174, none without tourism) and the
    /// riders of the company's schools and hospitals (decision 533).
    func passengerExtraFlows(onDay day: Int64, reaches: (StationID, StationID) -> Bool) -> TouristFlows {
        var flows = tourism == nil ? TouristFlows() : touristFlows(onDay: day, reaches: reaches).flows
        addCivicFlows(onDay: day, to: &flows, reaches: reaches)
        addAirportFlows(onDay: day, to: &flows, reaches: reaches)
        addCoachFlows(onDay: day, to: &flows, reaches: reaches)
        return flows
    }

    // MARK: - Midnight

    /// Counts the tourists of the day that ended, rolls the counters at the
    /// year's end. Runs at midnight, before the day is settled.
    mutating func closeTourismDay(_ day: Int64) {
        guard var tourism, day >= 0 else { return }
        let world = self
        // Decision 551: the network as it ran at noon of the day that
        // ended, not at midnight, when a line with service hours is closed
        // and its graph has no paths: counted then, every sight's day was
        // 0 (107.1's player report: yesterday, this year and last 0).
        // Decision 551, continued: a line that does not run at noon, at
        // the middle of its hours.
        let graph = passengerRoutingMode == .network ? Tourism.countingGraph(of: self, day: day) : nil
        let counted = world.touristFlows(onDay: day) { world.reaches(from: $0, to: $1, graph: graph) }
        let arrived = counted.arrivals
        // Decision 586: the cableways' riders of the day that ended, before
        // it is settled, take on those of the sights they reach; decision
        // 587: the bus routes' too; decision 589: the ferry routes'.
        countFeederRides(counted.flows.feederRides)
        // Decision 880: and the sights' visitors who came for the ride.
        countCablewaySightseers(onDay: day)
        let year = day / FinancePeriod.year.days
        if year != tourism.year {
            for index in tourism.attractions.indices {
                tourism.attractions[index].lastYear = year == tourism.year + 1 ? tourism.attractions[index].thisYear : 0
                tourism.attractions[index].thisYear = 0
            }
            tourism.year = year
        }
        for index in tourism.attractions.indices {
            let count = arrived[tourism.attractions[index].id] ?? 0
            tourism.attractions[index].yesterday = count
            tourism.attractions[index].thisYear += count
        }
        self.tourism = tourism
        // Decision 361: each temple's (and night market's) tourists, its
        // customers tonight.
        for index in placedBuildings.indices where placedBuildings[index].kind.isSight {
            placedBuildings[index].visitors = arrived[Self.companySightID(of: placedBuildings[index].id)] ?? 0
        }
        // Decision 684: the museum takes in the types bought since, after
        // the day's visitors are counted at the rating they came for.
        collectMuseumExhibits()
    }

    /// Settles day `day`'s shop takings and upkeep as one ledger row at
    /// `time`.
    mutating func settleTourism(day: Int64, time: GameTime) {
        guard let tourism else { return }
        var revenue = Money.zero, upkeep = Money.zero
        for attraction in tourism.attractions where attraction.souvenir > 0 {
            revenue = revenue + Tourism.shopRevenue(tourists: attraction.yesterday, level: attraction.souvenir)
            let cost = Tourism.souvenirCost * Int64(attraction.souvenir)
            upkeep = upkeep + Money((cost * Tourism.upkeepPerDay + 50_000) / 100_000)
        }
        guard revenue > .zero || upkeep > .zero else { return }
        write(LedgerEntry(
            kind: .dailyTourism, time: time, amount: revenue - upkeep,
            breakdown: [
                LedgerLine(item: .tourismRevenue, amount: revenue),
                LedgerLine(item: .tourismUpkeep, amount: .zero - upkeep),
            ]
        ), day: day)
    }

    /// Records a level of attraction `id`'s souvenir shop as an asset of
    /// its own, bought now: added to the first level's record, its cost was
    /// written down on that record's days, all at once on the next day, or
    /// never once the first level was written off.
    mutating func recordSouvenirAsset(of id: AttractionID, cost: Money) {
        acquireAsset(.souvenirShop, owner: id.rawValue, cost: cost)
    }

    // MARK: - Validation

    func tourismProblem() -> String? {
        guard let tourism else { return nil }
        guard !tourism.attractions.isEmpty, tourism.attractions.count <= Tourism.maximumAttractions else {
            return "A world with tourism has one to \(Tourism.maximumAttractions) attractions."
        }
        guard zip(tourism.attractions, tourism.attractions.dropFirst()).allSatisfy({ $0.id < $1.id }),
              tourism.attractions.allSatisfy({ $0.id.rawValue >= 1 && $0.id.rawValue < tourism.nextID })
        else { return "Attractions are listed once each, by ascending ID, below the next ID." }
        for attraction in tourism.attractions {
            guard (100...500).contains(attraction.baseStars), (0...Tourism.maximumSouvenirLevel).contains(attraction.souvenir),
                  (0...Self.maximumAccrued).contains(attraction.yesterday), (0...Self.maximumAccrued).contains(attraction.thisYear),
                  (0...Self.maximumAccrued).contains(attraction.lastYear), !attraction.name.isEmpty
            else { return "An attraction's rating, shop or counts are out of range." }
            guard attraction.point.x >= 0, attraction.point.y >= 0, attraction.point.x < bounds.width, attraction.point.y < bounds.height else {
                return "An attraction lies outside the world."
            }
        }
        return nil
    }
}

// MARK: - Codable

extension Attraction: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, englishName, x, y, kind, baseStars, souvenir, yesterday, thisYear, lastYear
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AttractionID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        englishName = try container.decode(String.self, forKey: .englishName)
        point = PlanPoint(x: try container.decode(Int64.self, forKey: .x), y: try container.decode(Int64.self, forKey: .y))
        kind = try container.decode(AttractionKind.self, forKey: .kind)
        baseStars = try container.decode(Int.self, forKey: .baseStars)
        souvenir = try container.decodeIfPresent(Int.self, forKey: .souvenir) ?? 0
        yesterday = try container.decodeIfPresent(Int64.self, forKey: .yesterday) ?? 0
        thisYear = try container.decodeIfPresent(Int64.self, forKey: .thisYear) ?? 0
        lastYear = try container.decodeIfPresent(Int64.self, forKey: .lastYear) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(englishName, forKey: .englishName)
        try container.encode(point.x, forKey: .x)
        try container.encode(point.y, forKey: .y)
        try container.encode(kind, forKey: .kind)
        try container.encode(baseStars, forKey: .baseStars)
        if souvenir != 0 { try container.encode(souvenir, forKey: .souvenir) }
        if yesterday != 0 { try container.encode(yesterday, forKey: .yesterday) }
        if thisYear != 0 { try container.encode(thisYear, forKey: .thisYear) }
        if lastYear != 0 { try container.encode(lastYear, forKey: .lastYear) }
    }
}

extension Tourism: Codable {
    private enum CodingKeys: String, CodingKey {
        case attractions, year, nextID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attractions = try container.decode([Attraction].self, forKey: .attractions)
        year = try container.decodeIfPresent(Int64.self, forKey: .year) ?? 0
        nextID = try container.decode(Int.self, forKey: .nextID)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(attractions, forKey: .attractions)
        if year != 0 { try container.encode(year, forKey: .year) }
        try container.encode(nextID, forKey: .nextID)
    }
}
