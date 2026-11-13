import GameCore

// Decision 712: the flights that open a city's map. A city outside Taiwan
// is opened by running an airport that flies to it: once one such airport
// had enough passengers on the company's trains in a day (yesterday's
// count, which every midnight writes, ``Airport/yesterdayRiders``), the
// flights "open" and the city's map can be chosen for a new game. The rule
// only reads the world, so GameCore, the saves and the golden scenarios
// know nothing of it; what has opened is kept on the device
// (``LauncherPreferences/airRoutesOpened``), as the lessons' stars are.

extension OverseasMap {
    /// The city's name.
    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .hongKong: language.text("Hong Kong", "香港")
        }
    }

    /// The name the airports' destinations call the city by
    /// (``AirDestination/name``, from ``AirportCatalog/destinations``).
    var destinationName: String {
        switch self {
        case .hongKong: "香港"
        }
    }

    /// How many passengers an airport that flies to the city must have had
    /// on the company's trains in one day, to it and from it together, for
    /// its flights to open the city's map.
    public var ridersToOpen: Int64 {
        switch self {
        case .hongKong: 500
        }
    }
}

extension OverseasMap {
    /// What opens the city's map, for the map picker's row while it is
    /// closed.
    public func howToOpen(in language: DisplayLanguage) -> String {
        let name = name(in: language)
        return language.text(
            "Not open yet. On a map of Taiwan, carry \(ridersToOpen.groupedText) passengers in one day to or from an airport that flies to \(name), and its flights open this map.",
            "還沒開航。在台灣的地圖上，讓一座飛\(name)的機場一天有 \(ridersToOpen.groupedText) 人搭你的列車，就會開航。"
        )
    }

    /// What the city's map is, for the map picker's row once it is open.
    public func mapSummary(in language: DisplayLanguage) -> String {
        switch self {
        case .hongKong: language.text(
            "The whole of Hong Kong, about 63 by 45 km, all open from the start. You can buy the MTR's lines.",
            "整個香港，約 63 × 45 公里，一開始全部開放，可以收購港鐵的路線。"
        )
        }
    }
}

extension Airport {
    /// Whether the airport's flights go to `city`.
    public func flies(to city: OverseasMap) -> Bool {
        destinations.contains { !$0.isRest && !$0.isDomestic && $0.name == city.destinationName }
    }
}

/// The cities this build of the game offers and those whose flights the
/// player has opened: what a game shows of them (the airport's row) and
/// what the map picker lists.
public struct AirRoutes: Equatable, Sendable {
    /// The cities whose maps the app has read (``GameLauncher/overseasGrounds``).
    public var offered: Set<OverseasMap> = []
    /// Those of them whose flights are open.
    public var opened: Set<OverseasMap> = []

    public init(offered: Set<OverseasMap> = [], opened: Set<OverseasMap> = []) {
        self.offered = offered
        self.opened = opened.intersection(offered)
    }

    /// The cities of `offered` not yet opened whose flights `world` opens:
    /// one of its airports that fly there had the city's riders yesterday.
    /// In the order of ``OverseasMap/allCases``.
    public func earned(in world: GameWorld) -> [OverseasMap] {
        OverseasMap.allCases.filter { city in
            offered.contains(city) && !opened.contains(city)
                && world.airports.contains { $0.flies(to: city) && $0.yesterdayRiders >= city.ridersToOpen }
        }
    }
}

extension AirportDay {
    /// How far the airport is from opening each city it flies to, or that
    /// the city is open (decision 712): a sentence for each city of
    /// `routes.offered` the airport flies to; `nil` when there is none.
    public func airRouteText(in language: DisplayLanguage, routes: AirRoutes) -> String? {
        let lines = OverseasMap.allCases.filter { routes.offered.contains($0) && airport.flies(to: $0) }.map { city in
            let name = city.name(in: language)
            if routes.opened.contains(city) {
                return language.text("\(name) flights are open: you can start a game on the \(name) map.", "\(name)航線已開航，可以到\(name)的地圖經營。")
            }
            return language.text(
                "\(name) flights: \(airport.yesterdayRiders.groupedText) of \(city.ridersToOpen.groupedText) rode your trains yesterday. Reach \(city.ridersToOpen.groupedText) in a day to open the \(name) map.",
                "\(name)航線：昨天 \(airport.yesterdayRiders.groupedText)／\(city.ridersToOpen.groupedText) 人搭你的列車，一天滿 \(city.ridersToOpen.groupedText) 人就開航，可以到\(name)經營。"
            )
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

extension GameSession {
    /// Says that the flights to `cities` opened in this game (decision
    /// 712): a line of news for each and the status line, with the sound of
    /// an achievement.
    public func noteAirRoutesOpened(_ cities: [OverseasMap]) {
        guard let first = cities.first else { return }
        for city in cities {
            news.add(day: world.clock.now.seconds / GameTime.secondsPerDay, .achievement) { language in
                Self.airRouteOpenedText(city, in: language)
            }
        }
        isMessageKeptOutOfNews = true
        message = StatusMessage(kind: .success, text: Self.airRouteOpenedText(first, in: language))
        isMessageKeptOutOfNews = false
        playSound?(.income)
    }

    static func airRouteOpenedText(_ city: OverseasMap, in language: DisplayLanguage) -> String {
        let name = city.name(in: language)
        return language.text(
            "Flights between Taiwan and \(name) are open. Start a new game on a real-world map to choose \(name).",
            "台灣↔\(name)開航了。開新遊戲時，在實景地圖可以選「\(name)」。"
        )
    }
}

extension GameLauncher {
    /// The cities the app offers and those open to this player (decision
    /// 712): the ones the device remembers, and every one in the demo mode,
    /// as the lessons are.
    public var airRoutes: AirRoutes {
        let offered = Set(overseasGrounds.map(\.city))
        let remembered = Set((preferences.airRoutesOpened ?? []).compactMap(OverseasMap.init(rawValue:)))
        return AirRoutes(offered: offered, opened: isDemoMode ? offered : remembered)
    }

    /// Opens the flights `session`'s airports earned yesterday, remembers
    /// them on the device and says so in the game; and hands the game what
    /// is open. A demo, the tutorial and the lessons open none: their
    /// trains are not the player's.
    func checkAirRoutes(of session: GameSession) {
        defer { session.airRoutes = airRoutes }
        guard session.collectsStationStamps else { return }
        let earned = airRoutes.earned(in: session.world)
        guard !earned.isEmpty else { return }
        rememberAirRoutes(earned)
        session.noteAirRoutesOpened(earned)
    }
}
