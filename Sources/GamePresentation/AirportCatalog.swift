import GameCore

// Taiwan's airports on a real-world map (decisions 695 and 700): where
// each passenger terminal stands, the passengers and flights of its
// average day, and where its flights go. The figures are the Civil
// Aviation Administration's annual statistics of 2025 (民航統計年報 114
// 年): each airport's passengers and aircraft movements and their domestic
// part (tables 28, 35 and 37), the domestic routes (table 48) and the
// international and cross-strait destinations of each airport (tables
// 50-1 to 50-6), divided by the days of the year. The coordinates are the
// terminals' in OpenStreetMap (ODbL 1.0). The hours are Songshan's 06:00
// to 23:00, Kaohsiung's curfew to 06:30 and Taichung's 07:00 to 23:00
// (2022); those of the eight smaller airports are the hours of their first
// and last flights in the Administration's domestic timetable of December
// 2026. Taoyuan's two terminals are two entries, each beside its own
// station of the Airport MRT; the split of its passengers, flights and
// destinations between them is this project's estimate, not a published
// figure. Taitung's flights are those of its scheduled routes: most of
// its 41,545 movements are training flights with no passengers. Wang'an
// (170 flights a year) and Hengchun (none) are left out, and Kinmen and
// Matsu lie outside the map: they are destinations only.

public enum AirportCatalog {
    /// The passengers and the flights between an airport and one of its
    /// destinations in the year, both ways together.
    struct Route {
        let to: String
        let passengers: Int64
        let flights: Int64

        init(_ to: String, _ passengers: Int64, _ flights: Int64) {
            self.to = to
            self.passengers = passengers
            self.flights = flights
        }
    }

    /// One terminal.
    struct Place {
        let key: String
        let chinese: String
        let english: String
        let latitude: Double
        let longitude: Double
        /// The passengers and the flights of its year.
        let yearlyPassengers: Int64
        let yearlyFlights: Int64
        /// The hours flights land and leave in (the last not included).
        let firstHour: Int
        let lastHour: Int
        /// The domestic part of its year.
        var domesticPassengers: Int64 = 0
        var domesticFlights: Int64 = 0
        /// Its main destinations; the rest of each kind is worked out.
        var routes: [Route] = []
        /// The passengers of the whole airport `routes` and the domestic
        /// part describe, when the place is one terminal of several; 0
        /// when they are its own.
        var routesOf: Int64 = 0
    }

    /// The year the figures are of.
    public static let sourceYear = 2025

    /// A destination's names and whether its flights are domestic.
    static let destinations: [String: (chinese: String, english: String, domestic: Bool)] = [
        "knh": ("金門", "Kinmen", true), "mzg": ("澎湖", "Penghu", true), "lzn": ("馬祖南竿", "Matsu Nangan", true),
        "mfk": ("馬祖北竿", "Matsu Beigan", true), "ttt": ("臺東", "Taitung", true), "hun": ("花蓮", "Hualien", true),
        "cmj": ("七美", "Qimei", true), "wot": ("望安", "Wang'an", true), "tsa": ("臺北", "Taipei", true),
        "khh": ("高雄", "Kaohsiung", true), "rmq": ("臺中", "Taichung", true), "tnn": ("臺南", "Tainan", true),
        "cyi": ("嘉義", "Chiayi", true), "kyd": ("蘭嶼", "Lanyu", true), "gni": ("綠島", "Green Island", true),
        "hkg": ("香港", "Hong Kong", false), "nrt": ("東京成田", "Tokyo Narita", false), "hnd": ("東京羽田", "Tokyo Haneda", false),
        "osa": ("大阪", "Osaka", false), "icn": ("首爾仁川", "Seoul Incheon", false), "gmp": ("首爾金浦", "Seoul Gimpo", false),
        "bkk": ("曼谷", "Bangkok", false), "sin": ("新加坡", "Singapore", false), "mnl": ("馬尼拉", "Manila", false),
        "oka": ("沖繩", "Okinawa", false), "mfm": ("澳門", "Macau", false), "sgn": ("胡志明市", "Ho Chi Minh City", false),
        "sha": ("上海虹橋", "Shanghai Hongqiao", false),
    ]

    /// Taoyuan's main destinations (table 50-1; Bangkok is its two
    /// airports together), shared between the terminals by their
    /// passengers.
    private static let taoyuanRoutes = [
        Route("hkg", 4_905_000, 27_044), Route("nrt", 3_472_299, 15_471), Route("osa", 2_925_614, 12_773), Route("bkk", 2_747_310, 13_809),
        Route("icn", 2_453_298, 9_372), Route("sin", 1_994_149, 7_513), Route("mnl", 1_785_334, 8_906), Route("oka", 1_568_890, 9_027),
    ]

    static let places: [Place] = [
        Place(key: "tpe1", chinese: "桃園機場第一航廈", english: "Taoyuan Airport Terminal 1",
              latitude: 25.0814, longitude: 121.2374, yearlyPassengers: 21_500_000, yearlyFlights: 118_000, firstHour: 0, lastHour: 24,
              routes: taoyuanRoutes, routesOf: 47_795_969),
        Place(key: "tpe2", chinese: "桃園機場第二航廈", english: "Taoyuan Airport Terminal 2",
              latitude: 25.0773, longitude: 121.2322, yearlyPassengers: 26_295_969, yearlyFlights: 144_217, firstHour: 0, lastHour: 24,
              routes: taoyuanRoutes, routesOf: 47_795_969),
        Place(key: "tsa", chinese: "臺北松山機場", english: "Taipei Songshan Airport",
              latitude: 25.0641, longitude: 121.5522, yearlyPassengers: 5_624_611, yearlyFlights: 52_022, firstHour: 6, lastHour: 23,
              domesticPassengers: 2_598_347, domesticFlights: 36_176,
              routes: [Route("knh", 1_101_045, 11_512), Route("mzg", 935_711, 11_870), Route("lzn", 273_303, 4_646), Route("ttt", 196_350, 3_617),
                       Route("mfk", 76_657, 1_688), Route("hun", 14_205, 688),
                       Route("hnd", 1_467_240, 5_840), Route("sha", 655_356, 2_704), Route("gmp", 245_076, 1_460)]),
        Place(key: "rmq", chinese: "臺中國際機場", english: "Taichung International Airport",
              latitude: 24.2539, longitude: 120.5996, yearlyPassengers: 2_758_195, yearlyFlights: 27_235, firstHour: 7, lastHour: 23,
              domesticPassengers: 1_040_575, domesticFlights: 16_093,
              routes: [Route("mzg", 500_094, 7_929), Route("knh", 466_329, 6_815), Route("lzn", 65_115, 1_066), Route("hun", 9_931, 283),
                       Route("hkg", 438_977, 2_416), Route("icn", 289_765, 1_859), Route("mfm", 210_258, 1_516), Route("sgn", 186_833, 1_296),
                       Route("oka", 127_286, 776)]),
        Place(key: "khh", chinese: "高雄國際機場", english: "Kaohsiung International Airport",
              latitude: 22.5702, longitude: 120.3421, yearlyPassengers: 6_971_162, yearlyFlights: 59_057, firstHour: 6, lastHour: 24,
              domesticPassengers: 1_231_830, domesticFlights: 21_226,
              routes: [Route("mzg", 777_991, 12_534), Route("knh", 404_140, 6_272), Route("cmj", 17_681, 1_338), Route("hun", 17_070, 670),
                       Route("lzn", 3_485, 60), Route("wot", 1_766, 170),
                       Route("hkg", 1_253_468, 7_512), Route("nrt", 563_125, 3_776), Route("osa", 562_164, 3_382), Route("icn", 415_460, 2_314),
                       Route("mfm", 324_799, 2_432), Route("oka", 242_680, 1_628)]),
        // Decision 700: the other airports of the map with scheduled
        // flights, after the five of decision 695 so those keep their
        // numbers.
        Place(key: "mzg", chinese: "澎湖機場", english: "Penghu Airport",
              latitude: 23.5607, longitude: 119.6296, yearlyPassengers: 2_401_323, yearlyFlights: 35_946, firstHour: 7, lastHour: 21,
              domesticPassengers: 2_400_167, domesticFlights: 35_889,
              routes: [Route("tsa", 935_711, 11_870), Route("khh", 777_991, 12_534), Route("rmq", 500_094, 7_929), Route("tnn", 135_858, 2_186),
                       Route("cyi", 42_319, 720), Route("cmj", 4_424, 605), Route("knh", 2_488, 45)]),
        Place(key: "hun", chinese: "花蓮機場", english: "Hualien Airport",
              latitude: 24.0257, longitude: 121.6140, yearlyPassengers: 82_461, yearlyFlights: 2_331, firstHour: 8, lastHour: 21,
              domesticPassengers: 41_227, domesticFlights: 1_641,
              routes: [Route("khh", 17_070, 670), Route("tsa", 14_205, 688), Route("rmq", 9_931, 283), Route("hkg", 35_466, 418)]),
        Place(key: "ttt", chinese: "臺東機場", english: "Taitung Airport",
              latitude: 22.7563, longitude: 121.1069, yearlyPassengers: 257_611, yearlyFlights: 7_557, firstHour: 7, lastHour: 21,
              domesticPassengers: 253_132, domesticFlights: 7_557,
              routes: [Route("tsa", 196_350, 3_617), Route("kyd", 32_627, 2_304), Route("gni", 22_015, 1_636)]),
        Place(key: "tnn", chinese: "臺南機場", english: "Tainan Airport",
              latitude: 22.9479, longitude: 120.2158, yearlyPassengers: 272_777, yearlyFlights: 4_361, firstHour: 7, lastHour: 19,
              domesticPassengers: 269_803, domesticFlights: 4_324,
              routes: [Route("mzg", 135_858, 2_186), Route("knh", 133_963, 2_138)]),
        Place(key: "cyi", chinese: "嘉義機場", english: "Chiayi Airport",
              latitude: 23.4546, longitude: 120.4038, yearlyPassengers: 82_409, yearlyFlights: 1_366, firstHour: 12, lastHour: 17,
              domesticPassengers: 82_409, domesticFlights: 1_366,
              routes: [Route("mzg", 42_319, 720), Route("knh", 40_091, 644)]),
        Place(key: "cmj", chinese: "七美機場", english: "Qimei Airport",
              latitude: 23.2117, longitude: 119.4179, yearlyPassengers: 22_115, yearlyFlights: 1_947, firstHour: 8, lastHour: 17,
              domesticPassengers: 22_115, domesticFlights: 1_947,
              routes: [Route("khh", 17_681, 1_338), Route("mzg", 4_424, 605)]),
        Place(key: "kyd", chinese: "蘭嶼機場", english: "Lanyu Airport",
              latitude: 22.0278, longitude: 121.5359, yearlyPassengers: 32_627, yearlyFlights: 2_306, firstHour: 8, lastHour: 17,
              domesticPassengers: 32_627, domesticFlights: 2_306,
              routes: [Route("ttt", 32_627, 2_304)]),
        Place(key: "gni", chinese: "綠島機場", english: "Green Island Airport",
              latitude: 22.6725, longitude: 121.4673, yearlyPassengers: 22_015, yearlyFlights: 2_232, firstHour: 8, lastHour: 17,
              domesticPassengers: 22_015, domesticFlights: 2_232,
              routes: [Route("ttt", 22_015, 1_636)]),
    ]

    /// Where `place`'s flights go: its main destinations in its order,
    /// then the rest of its domestic and of its international ones, so
    /// they add up to its year.
    static func destinations(of place: Place) -> [AirDestination] {
        // A terminal of several takes its share of the airport's routes.
        func own(_ value: Int64) -> Int64 {
            place.routesOf > 0 ? value * place.yearlyPassengers / place.routesOf : value
        }
        var list: [AirDestination] = []
        var named: (home: (passengers: Int64, flights: Int64), abroad: (passengers: Int64, flights: Int64)) = ((0, 0), (0, 0))
        for route in place.routes {
            guard let names = destinations[route.to] else { continue }
            let passengers = own(route.passengers), flights = own(route.flights)
            list.append(AirDestination(name: names.chinese, englishName: names.english, isDomestic: names.domestic,
                                       yearlyPassengers: passengers, yearlyFlights: flights))
            if names.domestic {
                named.home = (named.home.passengers + passengers, named.home.flights + flights)
            } else {
                named.abroad = (named.abroad.passengers + passengers, named.abroad.flights + flights)
            }
        }
        let home = (passengers: own(place.domesticPassengers), flights: own(place.domesticFlights))
        if home.passengers > named.home.passengers {
            list.append(AirDestination(name: "", englishName: "", isDomestic: true, yearlyPassengers: home.passengers - named.home.passengers,
                                       yearlyFlights: max(0, home.flights - named.home.flights)))
        }
        let abroad = (passengers: place.yearlyPassengers - home.passengers, flights: place.yearlyFlights - home.flights)
        if abroad.passengers > named.abroad.passengers {
            list.append(AirDestination(name: "", englishName: "", isDomestic: false, yearlyPassengers: abroad.passengers - named.abroad.passengers,
                                       yearlyFlights: max(0, abroad.flights - named.abroad.flights)))
        }
        return list
    }

    /// The airports that lie inside a world of `bounds` laid over the Earth
    /// as `frame` says, in the catalogue's order.
    public static func airports(in frame: RealWorldFrame, bounds: WorldBounds) -> [Airport] {
        var list: [Airport] = []
        for place in places {
            let position = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
            guard position.x >= 0, position.y >= 0, position.x < Double(bounds.width), position.y < Double(bounds.height) else { continue }
            list.append(Airport(
                id: list.count + 1, name: place.chinese, englishName: place.english,
                point: PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded())),
                dailyPassengers: place.yearlyPassengers / 365, dailyFlights: place.yearlyFlights / 365,
                firstHour: place.firstHour, lastHour: place.lastHour, destinations: destinations(of: place)
            ))
        }
        return list
    }

    /// `world` with the airports of its map, when it is a free game on a
    /// real-world map (decision 695): its sights are the catalogue's and
    /// it has no scenario. One saved before there were airports gets them;
    /// one whose airports are an earlier catalogue's gets today's
    /// (decision 700: the destinations and the smaller airports), each
    /// airport it had keeping yesterday's counts. Any other world is
    /// returned as it is.
    public static func withAirports(_ world: GameWorld) -> GameWorld {
        guard world.tourism != nil, world.scenario == nil, let frame = RealWorldFrame(world: world) else { return world }
        let names = Set(places.map(\.chinese))
        guard world.airports.allSatisfy({ names.contains($0.name) }) else { return world }
        var world = world
        world.setAirports(airports(in: frame, bounds: world.bounds))
        return world
    }
}

extension Airport {
    public func title(in language: DisplayLanguage) -> String {
        language.text(englishName, name)
    }
}

extension AirportDay {
    /// The airport's day in a sentence or two: its flights and passengers,
    /// and how many ride the company's trains.
    public func summary(in language: DisplayLanguage) -> String {
        if isClosed {
            return language.text("Closed by the typhoon today: no flights.", "今天因颱風關閉，沒有航班。")
        }
        let today = language.text(
            "\(flights.groupedText) flights and \(passengers.groupedText) air passengers today.",
            "今天 \(flights.groupedText) 架次航班、\(passengers.groupedText) 位旅客進出。"
        )
        guard station != nil else {
            return today + language.text(
                " No station yet: build one that trains call at within 800 m of the terminal and its passengers will ride your trains.",
                "還沒有車站：在航廈 800 公尺內蓋一座有列車停靠的車站，旅客就會搭你的車。"
            )
        }
        guard riders > 0 else {
            return today + language.text(
                " Nobody rides your trains yet: its station needs a line to stations where people live.",
                "還沒有人搭你的車：這一站要有路線通到有人住的車站。"
            )
        }
        return today + language.text(
            " \(ridersFrom.groupedText) ride your trains from the airport and \(ridersTo.groupedText) to it.",
            "其中 \(ridersFrom.groupedText) 人搭你的車離開機場、\(ridersTo.groupedText) 人搭你的車來搭機。"
        )
    }

    /// The day's domestic and international passengers and where its
    /// flights leave for (decision 700): the four destinations with the
    /// most flights today, then the rest together. `nil` when the airport
    /// is closed or lists no destinations.
    public func destinationsText(in language: DisplayLanguage) -> String? {
        guard !isClosed, !departures.isEmpty else { return nil }
        let kinds: String
        if domesticPassengers == 0 {
            kinds = language.text("All its flights are international or cross-strait.", "都是國際及兩岸航線。")
        } else if internationalPassengers == 0 {
            kinds = language.text("All its flights are domestic.", "都是國內線。")
        } else {
            kinds = language.text(
                "\(domesticPassengers.groupedText) domestic passengers, \(internationalPassengers.groupedText) international and cross-strait.",
                "國內線 \(domesticPassengers.groupedText) 人、國際及兩岸航線 \(internationalPassengers.groupedText) 人。"
            )
        }
        let named = departures.enumerated().filter { !$0.element.destination.isRest && $0.element.flights > 0 }
            .sorted { $0.element.flights != $1.element.flights ? $0.element.flights > $1.element.flights : $0.offset < $1.offset }
            .prefix(4).map(\.element)
        guard !named.isEmpty else { return kinds }
        let others = departures.reduce(Int64(0)) { $0 + $1.flights } - named.reduce(Int64(0)) { $0 + $1.flights }
        var parts = named.map { language.text("\($0.destination.englishName) \($0.flights.groupedText)", "\($0.destination.name) \($0.flights.groupedText) 班") }
        if others > 0 {
            parts.append(language.text("others \(others.groupedText)", "其他 \(others.groupedText) 班"))
        }
        return kinds + language.text(" Flights leaving today: ", "今天飛往：") + parts.joined(separator: language.text(", ", "、")) + language.text(".", "。")
    }

    /// Yesterday's count, or `nil` before the first day ends.
    public func yesterdayText(in language: DisplayLanguage) -> String? {
        guard airport.yesterdayFlights > 0 || airport.yesterdayRiders > 0 else { return nil }
        return language.text(
            "Yesterday: \(airport.yesterdayFlights.groupedText) flights, \(airport.yesterdayPassengers.groupedText) air passengers, \(airport.yesterdayRiders.groupedText) on your trains.",
            "昨天：\(airport.yesterdayFlights.groupedText) 架次、\(airport.yesterdayPassengers.groupedText) 位旅客，\(airport.yesterdayRiders.groupedText) 人搭你的車。"
        )
    }

    /// What more the railway can do, or `nil` when it carries all it can.
    public func growthText(in language: DisplayLanguage) -> String? {
        guard !isClosed, station != nil, riders > 0, riders < 2 * ridersAtMost else { return nil }
        return language.text(
            "Link its station to more stations where people live and more passengers ride; the airport draws more flights as they do.",
            "讓這一站通到更多有人住的車站，搭車的旅客會更多，機場的航班也跟著增加。"
        )
    }
}
