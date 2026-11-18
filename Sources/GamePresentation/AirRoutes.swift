import GameCore

// Decision 712: the flights that open a city's map. A city outside Taiwan
// is opened by running an airport that flies to it: once one such airport
// had enough passengers on the company's trains in a day (yesterday's
// count, which every midnight writes, ``Airport/yesterdayRiders``), the
// flights "open" and the city's map can be chosen for a new game. The rule
// only reads the world, so GameCore, the saves and the golden scenarios
// know nothing of it; what has opened is kept on the device
// (``LauncherPreferences/airRoutesOpened``), as the lessons' stars are.
//
// Decision 763: the second way. Owning an air route (GameCore's
// ``GameWorld/airRoutes``, decision 758) to one of a map's airports opens
// that map too, the moment it is bought, whatever its riders.

extension OverseasMap {
    /// The city's name.
    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .hongKong: language.text("Hong Kong", "香港")
        case .rovaniemi: language.text("Rovaniemi", "羅瓦涅米")
        case .fukuoka: language.text("Fukuoka", "福岡")
        }
    }

    /// The name the airports' destinations call the city by
    /// (``AirDestination/name``, from ``AirportCatalog/destinations``).
    var destinationName: String {
        switch self {
        case .hongKong: "香港"
        case .rovaniemi: "羅瓦涅米"
        case .fukuoka: "福岡"
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
        case .rovaniemi: language.text(
            "Rovaniemi in Finnish Lapland and the country round it, from Muurola to Kemijärvi, about 107 by 55 km, all open from the start. You can buy the line to Kemijärvi and the main line to Muurola.",
            "芬蘭拉普蘭的羅瓦涅米，從穆羅拉一路到凱米耶爾維，約 107 × 55 公里，一開始全部開放，可以收購往凱米耶爾維與往穆羅拉的路線。"
        )
        case .fukuoka: language.text(
            "The city of Fukuoka in Japan, from Meinohama to Fukuoka Airport and Kaizuka, about 18 by 22 km, all open from the start. You can buy the Fukuoka City Subway's three lines.",
            "日本的福岡市，從姪濱到福岡機場與貝塚，約 18 × 22 公里，一開始全部開放，可以收購福岡市地鐵的三條路線。"
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
    /// city; nothing at all while there is no city. Decision 818: a city
    /// whose map no flights open (``OverseasMap/opensByFlights``) is left
    /// out: the picker offers it from the start, and choosing it first
    /// leaves the others as they were.
    public init(cities: Set<OverseasMap>, opened: Set<String> = [], here: String = AirMap.taiwan.id, best: [String: Int64] = [:]) {
        let cities = OverseasMap.allCases.filter { cities.contains($0) && $0.opensByFlights }.map(AirMap.init)
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

    /// Whether `world` owns an air route (decision 758) to one of the
    /// airports of `route`'s map (decision 763).
    func owns(along route: AirRoute, in world: GameWorld) -> Bool {
        guard let to = map(route.to) else { return false }
        return world.airRoutes.contains { to.airports.contains($0.destination) }
    }

    /// The maps not yet open whose flights `world`, a game on ``here``,
    /// opens: one of its airports that fly there had the route's riders
    /// yesterday, or it owns an air route there (decision 763). In the
    /// order of ``maps``.
    public func earned(in world: GameWorld) -> [AirMap] {
        maps.filter { map in
            !opened.contains(map.id) && routes.contains {
                $0.from == here && $0.to == map.id && (riders(along: $0, in: world) >= $0.riders || owns(along: $0, in: world))
            }
        }
    }

    /// What buying an air route to `destination` (an ``AirDestination/name``)
    /// opens, for its offer while that map is closed (decision 763): `nil`
    /// when the destination is no airport of a map the game's own has
    /// flights to, or that map is open.
    public func opensByBuying(_ destination: String, in language: DisplayLanguage) -> String? {
        guard let map = maps.first(where: { $0.airports.contains(destination) }), !opened.contains(map.id),
              routes.contains(where: { $0.from == here && $0.to == map.id }) else { return nil }
        let name = map.name(in: language)
        return language.text(
            "Buying this route also opens the \(name) map: you can start a new game there.",
            "收購這條航線也會開航\(name)：之後開新遊戲可以選\(name)的地圖。"
        )
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
            "Not open yet. On a map of \(from.joined(separator: " or ")), buy an air route to \(name), or carry \(riders) passengers in one day to or from an airport that flies there, and its flights open this map.",
            "還沒開航。在\(from.joined(separator: "或"))的地圖上，收購一條飛\(name)的航線，或讓一座飛\(name)的機場一天有 \(riders) 人搭你的列車，就會開航。"
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
                "\(name) flights: \(airport.yesterdayRiders.groupedText) of \(route.riders.groupedText) rode your trains yesterday. Reach \(route.riders.groupedText) in a day, or buy an air route to \(name), to open the \(name) map.",
                "\(name)航線：昨天 \(airport.yesterdayRiders.groupedText)／\(route.riders.groupedText) 人搭你的列車，一天滿 \(route.riders.groupedText) 人或收購一條飛\(name)的航線就開航，可以到\(name)經營。"
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
        // Decision 858: a city whose map pack is still to come has its
        // flights all the same: what the player opened does not wait for
        // a download.
        let cities = Set(overseasGrounds.map(\.city)).union(overseasAwaited.map(\.city))
        let all = AirRoutes(cities: cities)
        return AirRoutes(
            cities: cities, opened: isDemoMode ? Set(all.maps.map(\.id)) : Set(preferences.airRoutesOpened ?? []),
            best: preferences.airRouteBest ?? [:]
        )
    }

    /// Decision 818: the map picker's rows of the cities outside Taiwan, in
    /// order: each city whose flights the app offers (decision 712), closed
    /// with the way to open it until they open, and each city no flights
    /// open (Rovaniemi), open from the start. Decision 858: a city whose
    /// map pack is not on the device yet is closed, with how its download
    /// stands (`status`), until it is. None while the real-world data is
    /// read.
    public func overseasMapRows(
        in language: DisplayLanguage, status: (OverseasMap) -> MapPackStatus = MapPackDownloads.status
    ) -> [OverseasMapRow] {
        guard !isLoadingRealWorldData else { return [] }
        let routes = airRoutes
        let read = Set(overseasGrounds.map(\.city))
        let awaited = Set(overseasAwaited.map(\.city))
        return OverseasMap.allCases.compactMap { city in
            let waiting = awaited.contains(city) ? city.notDownloadedText(status(city), in: language) : nil
            if routes.offers(city.rawValue) {
                guard routes.canStart(city.rawValue) else {
                    return OverseasMapRow(city: city, closed: routes.howToOpen(city.rawValue, in: language))
                }
                return OverseasMapRow(city: city, closed: waiting, waitsForDownload: waiting != nil)
            }
            guard !city.opensByFlights, read.contains(city) || awaited.contains(city) else { return nil }
            return OverseasMapRow(city: city, closed: waiting, waitsForDownload: waiting != nil)
        }
    }

    /// The id of the map `world` is on: the city whose ground holds it
    /// (or, decision 858, whose map it is while its pack is to come), or
    /// Taiwan.
    func airMap(of world: GameWorld) -> String {
        (overseasGrounds.first { $0.holds(world) }?.city ?? awaitedCity(of: world))?.rawValue ?? AirMap.taiwan.id
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
        // Decision 763: an air route bought opens its map at once.
        session.onAirRouteBought = { [weak self, weak session] in
            guard let self, let session else { return }
            self.checkAirRoutes(of: session)
        }
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

/// Decision 818: a city's row in the map picker (``GameLauncher/overseasMapRows(in:)``).
public struct OverseasMapRow: Equatable, Sendable {
    public let city: OverseasMap
    /// Why a new game cannot start there yet, `nil` when it can.
    public let closed: String?
    /// Decision 858: whether it is closed because its map pack is not on
    /// the device yet, not because its flights have not opened.
    public var waitsForDownload = false
}
