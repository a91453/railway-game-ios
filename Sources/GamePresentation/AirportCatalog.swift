import GameCore

// Taiwan's airports on a real-world map (decision 695): where each
// passenger terminal stands, and the passengers and flights of its average
// day. The figures are each airport's passengers and aircraft movements of
// 2025 as the Chinese Wikipedia's pages give them (the Civil Aviation
// Administration's statistics; Taoyuan's 47.8 million agrees with the
// press), divided by the days of the year; the coordinates are the
// terminals' in OpenStreetMap (ODbL 1.0, the game's own
// `taiwan_no_build.json`). The hours are Songshan's 06:00 to 23:00,
// Kaohsiung's curfew to 06:30 and Taichung's 07:00 to 23:00 (2022).
// Taoyuan's two terminals are two entries, each beside its own station of
// the Airport MRT; the split of its passengers and flights between them is
// this project's estimate, not a published figure.

public enum AirportCatalog {
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
    }

    /// The year the figures are of.
    public static let sourceYear = 2025

    static let places: [Place] = [
        Place(key: "tpe1", chinese: "桃園機場第一航廈", english: "Taoyuan Airport Terminal 1",
              latitude: 25.0814, longitude: 121.2374, yearlyPassengers: 21_500_000, yearlyFlights: 118_000, firstHour: 0, lastHour: 24),
        Place(key: "tpe2", chinese: "桃園機場第二航廈", english: "Taoyuan Airport Terminal 2",
              latitude: 25.0773, longitude: 121.2322, yearlyPassengers: 26_295_969, yearlyFlights: 144_217, firstHour: 0, lastHour: 24),
        Place(key: "tsa", chinese: "臺北松山機場", english: "Taipei Songshan Airport",
              latitude: 25.0641, longitude: 121.5522, yearlyPassengers: 5_624_611, yearlyFlights: 52_022, firstHour: 6, lastHour: 23),
        Place(key: "rmq", chinese: "臺中國際機場", english: "Taichung International Airport",
              latitude: 24.2539, longitude: 120.5996, yearlyPassengers: 2_758_195, yearlyFlights: 27_235, firstHour: 7, lastHour: 23),
        Place(key: "khh", chinese: "高雄國際機場", english: "Kaohsiung International Airport",
              latitude: 22.5702, longitude: 120.3421, yearlyPassengers: 6_971_162, yearlyFlights: 59_057, firstHour: 6, lastHour: 24),
    ]

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
                firstHour: place.firstHour, lastHour: place.lastHour
            ))
        }
        return list
    }

    /// `world` with the airports of its map, when it is a free game on a
    /// real-world map saved before there were airports (decision 695): its
    /// sights are the catalogue's and it has no scenario. Any other world
    /// is returned as it is.
    public static func withAirports(_ world: GameWorld) -> GameWorld {
        guard world.airports.isEmpty, world.tourism != nil, world.scenario == nil, let frame = RealWorldFrame(world: world) else { return world }
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
