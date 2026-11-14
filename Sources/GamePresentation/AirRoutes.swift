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
}

extension OverseasMap {
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

/// A map a game can be played on that flights reach (decision 712,
/// continued): the whole of Taiwan, or a city with a map pack. Data, not a
/// rule: a new map is one more of these and the routes to it.
public struct AirMap: Hashable, Sendable, Identifiable {
    public let id: String
    public let english: String
    public let chinese: String
    /// The names the airports of other maps call this map's airports by
    /// (``AirDestination/name``).
    public let airports: Set<String>

    public init(id: String, english: String, chinese: String, airports: Set<String>) {
        self.id = id
        self.english = english
        self.chinese = chinese
        self.airports = airports
    }

    public func name(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    /// The name of the map's row in the map picker: Taiwan's is "the whole
    /// of Taiwan", a city's its name.
    public func rowName(in language: DisplayLanguage) -> String {
        id == AirMap.taiwan.id ? language.text("The whole of Taiwan", "全台灣") : name(in: language)
    }

    /// Taiwan: its airports are the ones the catalog's tables call
    /// domestic.
    public static let taiwan = AirMap(
        id: "taiwan", english: "Taiwan", chinese: "台灣",
        airports: Set(AirportCatalog.destinations.values.filter(\.domestic).map(\.chinese))
    )

    /// The map of `city`.
    public init(_ city: OverseasMap) {
        self.init(id: city.rawValue, english: city.name(in: .english), chinese: city.name(in: .traditionalChinese), airports: [city.destinationName])
    }
}

/// Flights from one map to another: an airport of `from` that flies to
/// `to` opens `to`'s map once it had `riders` passengers on the company's
/// trains in a day, to it and from it together.
public struct AirRoute: Hashable, Sendable {
    public static let standardRiders: Int64 = 500

    public let from: String
    public let to: String
    public let riders: Int64

    public init(from: String, to: String, riders: Int64 = AirRoute.standardRiders) {
        self.from = from
        self.to = to
        self.riders = riders
    }
}

extension Airport {
    /// Whether the airport's flights go to `map`.
    public func flies(to map: AirMap) -> Bool {
        destinations.contains { !$0.isRest && !$0.isDomestic && map.airports.contains($0.name) }
    }

    /// Whether the airport's flights go to `city`.
    public func flies(to city: OverseasMap) -> Bool {
        flies(to: AirMap(city))
    }
}

/// The maps this build of the game offers, the flights between them and
/// the maps open to the player: what a game shows of them (the airport's
/// row) and what the map picker lists. The player's first real map is open
/// from the start, whichever it is; every other is opened by flights from
/// a map already open.
public struct AirRoutes: Equatable, Sendable {
    /// The maps, in the picker's order; Taiwan alone offers no flights.
    public var maps: [AirMap] = []
    public var routes: [AirRoute] = []
    /// The ids of the maps open to the player; none until the first is
    /// chosen, when any can be.
    public var opened: Set<String> = []
    /// The map the game is on.
    public var here: String = AirMap.taiwan.id
    /// The most passengers in a day so far towards opening each map, by
    /// its id, for the picker's closed rows.
    public var best: [String: Int64] = [:]

    public init(maps: [AirMap] = [], routes: [AirRoute] = [], opened: Set<String> = [], here: String = AirMap.taiwan.id, best: [String: Int64] = [:]) {
        self.maps = maps
        self.routes = routes.filter { route in maps.contains { $0.id == route.from } && maps.contains { $0.id == route.to } }
        self.opened = opened.intersection(maps.map(\.id))
        self.here = here
        self.best = best
    }

    /// Taiwan and `cities`, with flights both ways between Taiwan and each
    /// city; nothing at all while there is no city.
    public init(cities: Set<OverseasMap>, opened: Set<String> = [], here: String = AirMap.taiwan.id, best: [String: Int64] = [:]) {
        let cities = OverseasMap.allCases.filter(cities.contains).map(AirMap.init)
        self.init(
            maps: cities.isEmpty ? [] : [.taiwan] + cities,
            routes: cities.flatMap { [AirRoute(from: AirMap.taiwan.id, to: $0.id), AirRoute(from: $0.id, to: AirMap.taiwan.id)] },
            opened: opened, here: here, best: best
        )
    }

    public func map(_ id: String) -> AirMap? {
        maps.first { $0.id == id }
    }

    /// Whether the app offers the map `id`.
    public func offers(_ id: String) -> Bool {
        map(id) != nil
    }

    /// Whether a new game can start on the map `id`: it is open, or the
    /// player has not chosen a first map yet, or the app offers no other
    /// map (so there is nothing to open).
    public func canStart(_ id: String) -> Bool {
        opened.isEmpty || opened.contains(id) || !offers(id)
    }

    /// The flights that can open the map `id`: from each map with a route
    /// to it.
    public func routes(to id: String) -> [AirRoute] {
        routes.filter { $0.to == id }
    }

    /// The most passengers yesterday at one of `world`'s airports that fly
    /// along `route`.
    func riders(along route: AirRoute, in world: GameWorld) -> Int64 {
        guard let to = map(route.to) else { return 0 }
        return world.airports.filter { $0.flies(to: to) }.map(\.yesterdayRiders).max() ?? 0
    }

    /// The maps not yet open whose flights `world`, a game on ``here``,
    /// opens: one of its airports that fly there had the route's riders
    /// yesterday. In the order of ``maps``.
    public func earned(in world: GameWorld) -> [AirMap] {
        maps.filter { map in
            !opened.contains(map.id) && routes.contains { $0.from == here && $0.to == map.id && riders(along: $0, in: world) >= $0.riders }
        }
    }

    /// What opens the map `id`, for the map picker's row while it is
    /// closed: from which maps, how many passengers, and the most so far.
    public func howToOpen(_ id: String, in language: DisplayLanguage) -> String {
        guard let map = map(id) else { return "" }
        let name = map.name(in: language)
        let ways = routes(to: id)
        let from = ways.compactMap { self.map($0.from)?.name(in: language) }
        let riders = (ways.map(\.riders).min() ?? AirRoute.standardRiders).groupedText
        var text = language.text(
            "Not open yet. On a map of \(from.joined(separator: " or ")), carry \(riders) passengers in one day to or from an airport that flies to \(name), and its flights open this map.",
            "還沒開航。在\(from.joined(separator: "或"))的地圖上，讓一座飛\(name)的機場一天有 \(riders) 人搭你的列車，就會開航。"
        )
        if let best = best[id], best > 0 {
            text += language.text(" Best day so far: \(best.groupedText) of \(riders).", "目前最多的一天：\(best.groupedText)／\(riders) 人。")
        }
        return text
    }
}

extension AirportDay {
    /// How far the airport is from opening each map it flies to, or that
    /// the map is open (decision 712): a sentence for each map the game's
    /// own has flights to and the airport flies to; `nil` when there is
    /// none.
    public func airRouteText(in language: DisplayLanguage, routes: AirRoutes) -> String? {
        let lines = routes.routes.filter { $0.from == routes.here }.compactMap { route -> String? in
            guard let map = routes.map(route.to), airport.flies(to: map) else { return nil }
            let name = map.name(in: language)
            if routes.opened.contains(map.id) {
                return language.text(
                    "\(name) flights are open. On the start screen, tap New Game, then Real-World Map: \(map.rowName(in: language)) is at the top of the list.",
                    "\(name)航線已開航。回開始畫面按「新遊戲」→「實景地圖」，清單最上面就有「\(map.rowName(in: language))」。"
                )
            }
            return language.text(
                "\(name) flights: \(airport.yesterdayRiders.groupedText) of \(route.riders.groupedText) rode your trains yesterday. Reach \(route.riders.groupedText) in a day to open the \(name) map.",
                "\(name)航線：昨天 \(airport.yesterdayRiders.groupedText)／\(route.riders.groupedText) 人搭你的列車，一天滿 \(route.riders.groupedText) 人就開航，可以到\(name)經營。"
            )
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

extension GameSession {
    /// Says that the flights to `maps` opened in this game (decision 712):
    /// a line of news for each and the status line, with the sound of an
    /// achievement.
    public func noteAirRoutesOpened(_ maps: [AirMap]) {
        guard let first = maps.first else { return }
        let here = airRoutes.map(airRoutes.here) ?? .taiwan
        for map in maps {
            news.add(day: world.clock.now.seconds / GameTime.secondsPerDay, .achievement) { language in
                Self.airRouteOpenedText(map, from: here, in: language)
            }
        }
        isMessageKeptOutOfNews = true
        message = StatusMessage(kind: .success, text: Self.airRouteOpenedText(first, from: here, in: language))
        isMessageKeptOutOfNews = false
        playSound?(.income)
    }

    static func airRouteOpenedText(_ map: AirMap, from here: AirMap, in language: DisplayLanguage) -> String {
        let name = map.name(in: language)
        return language.text(
            "Flights between \(here.name(in: language)) and \(name) are open. On the start screen, tap New Game, then Real-World Map: \(map.rowName(in: language)) is at the top of the list.",
            "\(here.name(in: language))↔\(name)開航了。回開始畫面按「新遊戲」→「實景地圖」，清單最上面就有「\(map.rowName(in: language))」。"
        )
    }
}

extension GameLauncher {
    /// The maps the app offers, the flights between them and the maps
    /// open to this player (decision 712): the ones the device remembers,
    /// and every one in the demo mode, as the lessons are.
    public var airRoutes: AirRoutes {
        let cities = Set(overseasGrounds.map(\.city))
        let all = AirRoutes(cities: cities)
        return AirRoutes(
            cities: cities, opened: isDemoMode ? Set(all.maps.map(\.id)) : Set(preferences.airRoutesOpened ?? []),
            best: preferences.airRouteBest ?? [:]
        )
    }

    /// The id of the map `world` is on: the city whose ground holds it, or
    /// Taiwan.
    func airMap(of world: GameWorld) -> String {
        overseasGrounds.first { $0.holds(world) }?.city.rawValue ?? AirMap.taiwan.id
    }

    /// Opens the flights `session`'s airports earned yesterday, remembers
    /// them on the device and says so in the game; and hands the game what
    /// is open. A demo, the tutorial and the lessons open none: their
    /// trains are not the player's.
    func checkAirRoutes(of session: GameSession) {
        var routes = airRoutes
        routes.here = airMap(of: session.world)
        defer {
            var after = airRoutes
            after.here = routes.here
            session.airRoutes = after
        }
        session.airRoutes = routes
        guard session.collectsStationStamps, !isDemoMode, !routes.opened.isEmpty else { return }
        var best = preferences.airRouteBest ?? [:]
        for route in routes.routes where route.from == routes.here && !routes.opened.contains(route.to) {
            best[route.to] = max(best[route.to] ?? 0, routes.riders(along: route, in: session.world))
        }
        best = best.filter { $0.value > 0 }
        rememberAirRouteBest(best)
        let earned = routes.earned(in: session.world)
        guard !earned.isEmpty else { return }
        rememberAirRoutes(earned.map(\.id))
        session.noteAirRoutesOpened(earned)
    }

    /// Before a new game on the real map `id`: `false`, with the way to
    /// open it, while it is closed; and the player's first real map is
    /// remembered as open.
    func takeMap(_ id: String) -> Bool {
        let routes = airRoutes
        guard routes.canStart(id) else {
            message = StatusMessage(kind: .failure, text: routes.howToOpen(id, in: language))
            return false
        }
        if !isDemoMode, routes.offers(id), routes.opened.isEmpty { rememberAirRoutes([id]) }
        return true
    }
}
