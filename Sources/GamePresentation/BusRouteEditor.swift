import GameCore

// Decision 400, 10i-5: the player's own bus routes. The bus tool draws a
// route from a station out along the roads, a stop at each tap, and shows
// what it would cost, how often its buses would come and how many riders
// its stops reach, worked out by running GameCore's own commands
// (`createBusRoute`, `setBusRouteStops`, `setBusRuns`, `setBusCount`,
// 10i-2) on a copy of the world. Nothing here is a game rule: GameCore
// finds the way along the roads and refuses what cannot run, and a refused
// route changes nothing. The map draws each route along the road cells
// between its stops (``BusRoadPath``), for the eye only: GameCore keeps
// each leg's metres, not its way.
//
// The references have no editor for a company's own buses (geo-scene's
// `BusEngine.ts` moves real buses, the Taiwan rail site lists real stops):
// the taps, the last stop taken back and the ✓ beside it follow the map's
// own new-line draft (decision 100, `MapLineDraft`).

/// The bus route the bus tool draws (presentation state only): the station
/// it feeds, then its stops in the order the player tapped them, from the
/// station outwards. GameCore lists a route's stops the other way, the
/// farthest first and the station after the last (``coreStops``).
public struct BusRouteDraft: Hashable, Sendable {
    /// The station the route feeds, picked by the first tap.
    public var station: StationID?
    /// The stops, nearest the station first.
    public var stops: [CellPosition] = []
    /// When its buses leave: every ``headwayChoices`` minutes for a new
    /// route; an edited route keeps its own until the player picks one.
    public var service: BusService = .every(minutes: BusRouteDraft.defaultHeadway)
    public var buses = BusRouteDraft.defaultBuses
    /// The route whose stops it moves, or `nil` for a new route.
    public var route: BusRouteID?

    /// A new route's buses: one every 10 minutes, two buses (the
    /// balance's measured route, decision 400).
    public static let defaultHeadway: Int64 = 10
    public static let defaultBuses = 2
    /// The headways the tool and the route card offer, in minutes.
    public static let headwayChoices: [Int64] = [5, 10, 15, 20, 30, 60]

    public init() {}

    /// The stops as GameCore takes them: the farthest first.
    public var coreStops: [CellPosition] {
        stops.reversed()
    }

    /// The minutes between buses it sets, as a headway.
    public var headway: Int64 {
        switch service {
        case .every(let minutes): minutes
        case .runs: service.averageMinutes
        }
    }
}

extension BusService {
    /// The minutes between buses on average: the headway, or the runs'
    /// average gap, rounded half up (a day for one run).
    var averageMinutes: Int64 {
        switch self {
        case .every(let minutes):
            return minutes
        case .runs(let minutes):
            guard minutes.count >= 2, let first = minutes.first, let last = minutes.last else { return GameTime.minutesPerDay }
            let gaps = Int64(minutes.count - 1)
            return ((last - first) * 2 + gaps) / (2 * gaps)
        }
    }
}

/// What the drawn route would be, as GameCore makes it on a copy of the
/// world.
public struct BusRoutePreview: Hashable, Sendable {
    /// What opening it (or the stops and buses it adds) costs.
    public let price: Money
    /// The road's metres from the farthest stop to the station; 0 when
    /// GameCore refused it.
    public let metres: Int64
    /// The minutes between buses its buses keep, or `nil` with none or
    /// when refused.
    public let headway: Int64?
    /// The buses it runs each way a day.
    public let departures: Int64
    /// What its buses cost a day to run.
    public let dailyCost: Money
    /// The trips a day its stops reach, at most: some take the bus, some
    /// a scooter (``BusRoute/riderShare``).
    public let riders: Int64
    /// The minutes from door to station, on average.
    public let minutes: Int64
    /// Why it cannot open, as the player reads it; `nil` when it can.
    public let problem: String?
    /// The stop and the next (or the station) no road joins, when GameCore
    /// said so: two points, or none.
    public let brokenLeg: [PlanPoint]
    /// Whether it changes nothing (an edited route as it was).
    public let isUnchanged: Bool

    public var canOpen: Bool {
        problem == nil && !isUnchanged
    }

    /// `draft` run on a copy of `world` (``GameWorld/pricingCopy()``),
    /// whose price is its cash before less after; refused there, or more
    /// than the company has, its problem says why. `nil` before a station
    /// and a stop are picked.
    public static func make(_ draft: BusRouteDraft, in world: GameWorld, language: DisplayLanguage) -> BusRoutePreview? {
        guard let station = draft.station, !draft.stops.isEmpty else { return nil }
        var copy = world.pricingCopy()
        let before = copy.economy.balance
        let id: BusRouteID
        do throws(GameError) {
            id = try BusRouteEdits.run(draft, on: &copy)
        } catch {
            var broken: [PlanPoint] = []
            if case .busStopsNotConnected(let leg) = error, let location = world.station(id: station)?.location {
                let ends = draft.coreStops.map(\.middle) + [location]
                if leg + 1 < ends.count { broken = [ends[leg], ends[leg + 1]] }
            }
            return BusRoutePreview(price: .zero, metres: 0, headway: nil, departures: 0, dailyCost: .zero, riders: 0, minutes: 0,
                                   problem: error.playerMessage(in: language), brokenLeg: broken, isUnchanged: false)
        }
        let price = before - copy.economy.balance
        let route = copy.busRoute(id: id)
        var problem: String?
        if world.accounts.mode == .management, price > .zero, !world.economy.canAfford(price) {
            problem = GameError.insufficientFunds(required: price, available: world.economy.balance).playerMessage(in: language)
        }
        let unchanged = draft.route.flatMap { world.busRoute(id: $0) }.map {
            $0.stops == draft.coreStops && $0.service == draft.service && $0.buses == draft.buses
        } ?? false
        return BusRoutePreview(
            price: price, metres: route?.metres ?? 0, headway: route?.headway, departures: route?.dailyDepartures ?? 0,
            dailyCost: route?.dailyCost ?? .zero, riders: route?.feederTrips ?? 0, minutes: route?.feederMinutes ?? 0,
            problem: problem, brokenLeg: [], isUnchanged: unchanged
        )
    }

    /// The figures the bus tool shows, a line each: length and stops, the
    /// buses, the riders, the running cost.
    public func lines(for draft: BusRouteDraft, in language: DisplayLanguage) -> [String] {
        guard metres > 0 else { return [] }
        var lines = [language.text(
            "\(BusRouteText.distance(metres, in: language)) · \(BusRouteText.stops(draft.stops.count))",
            "\(BusRouteText.distance(metres, in: language)) · \(draft.stops.count) 個站牌"
        )]
        if let headway {
            var service = language.text("A bus every \(headway) min · \(BusRouteText.buses(draft.buses))", "每 \(headway) 分一班 · \(draft.buses) 輛車")
            if headway > draft.headway {
                service += language.text(" (too few buses for every \(draft.headway) min)", "（車不夠每 \(draft.headway) 分一班）")
            }
            lines.append(service)
        } else {
            lines.append(language.text("No buses: the route does not run.", "沒有車：路線不會開。"))
        }
        if riders > 0 {
            lines.append(language.text(
                "Its stops reach up to \(Money(riders).displayText) trips a day, about \(minutes) min door to station",
                "站牌一帶每天最多 \(Money(riders).displayText) 人次，門口到車站約 \(minutes) 分"
            ))
        } else if headway != nil {
            lines.append(language.text(
                "Few people live beyond walking distance of a station along it.",
                "沿線走路到不了車站的地方人很少。"
            ))
        }
        lines.append(language.text("Running cost \(dailyCost.moneyText) a day", "營運成本每天 \(dailyCost.moneyText)"))
        return lines
    }
}

/// The bus edits GameCore runs, shared by the commands (``PlayerCommand/Edit``)
/// and the bus tool's preview, so both make the same route.
enum BusRouteEdits {
    /// Opens `draft` as a new route, or moves the stops of the route it
    /// edits and sets its buses: returns the route.
    static func run(_ draft: BusRouteDraft, on world: inout GameWorld) throws(GameError) -> BusRouteID {
        guard let station = draft.station else { throw .invalidBusRoute }
        if let id = draft.route {
            try revise(id, stops: draft.coreStops, service: draft.service, buses: draft.buses, on: &world)
            return id
        }
        return try world.createBusRoute(to: station, stops: draft.coreStops, service: draft.service, buses: draft.buses).id
    }

    /// Route `id` with `stops`, `service` and `buses`, all or none.
    static func revise(_ id: BusRouteID, stops: [CellPosition], service: BusService, buses: Int, on world: inout GameWorld) throws(GameError) {
        var copy = world
        if copy.busRoute(id: id)?.stops != stops { try copy.setBusRouteStops(id, stops: stops) }
        try copy.setBusRuns(id, to: service)
        try copy.setBusCount(id, to: buses)
        world = copy
    }
}

extension CellPosition {
    /// The middle of the land cell, on the plan.
    public var middle: PlanPoint {
        PlanPoint(x: Int64(column) * Land.cellLength + Land.cellLength / 2, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
    }

    /// The land cell `point` lies in.
    public init(containing point: PlanPoint) {
        self.init(row: Int(point.y / Land.cellLength), column: Int(point.x / Land.cellLength))
    }
}

/// The way along the road cells between two cells, for drawing a bus
/// route: the same search as GameCore's ``GameWorld/busRoadMetres(from:to:)``
/// (eight neighbours, 64 m straight, 90 m corner to corner, the nearest
/// first, then by row and column), keeping the cells it went through.
public enum BusRoadPath {
    /// The most cells searched, as GameCore's.
    static let searchLimit = 65_536

    /// The cells from `start` to `end`, both included, or `nil` when no
    /// road joins them.
    public static func cells(from start: CellPosition, to end: CellPosition, roads: Set<CellPosition>) -> [CellPosition]? {
        guard roads.contains(start), roads.contains(end) else { return nil }
        guard start != end else { return [start] }
        var best: [CellPosition: Int64] = [start: 0]
        var parent: [CellPosition: CellPosition] = [:]
        var heap = Heap()
        heap.push((0, start))
        var settled = 0
        while let (metres, cell) = heap.pop() {
            guard metres == best[cell] else { continue }
            if cell == end {
                var path = [end]
                while let previous = parent[path[path.count - 1]] { path.append(previous) }
                return path.reversed()
            }
            settled += 1
            guard settled <= searchLimit else { return nil }
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 {
                    let next = CellPosition(row: cell.row + dr, column: cell.column + dc)
                    guard roads.contains(next) else { continue }
                    let way = metres + (dr != 0 && dc != 0 ? RoadGrid.diagonalMetres : RoadGrid.straightMetres)
                    if best[next].map({ way < $0 }) ?? true {
                        best[next] = way
                        parent[next] = cell
                        heap.push((way, next))
                    }
                }
            }
        }
        return nil
    }

    /// The line a route is drawn along: from its first stop through each
    /// stop to `station`, along the roads, a straight line where none
    /// joins two of them.
    public static func points(stops: [CellPosition], station: PlanPoint, roads: Set<CellPosition>) -> [PlanPoint] {
        let ends = stops + [CellPosition(containing: station)]
        var points: [PlanPoint] = []
        for (from, to) in zip(ends, ends.dropFirst()) {
            let cells = Self.cells(from: from, to: to, roads: roads) ?? [from, to]
            points += (points.isEmpty ? cells : Array(cells.dropFirst())).map(\.middle)
        }
        if points.isEmpty, let only = stops.first { points = [only.middle] }
        points.append(station)
        return points
    }

    /// A binary heap of (metres, cell), the least first, then by row and
    /// column.
    private struct Heap {
        private var items: [(Int64, CellPosition)] = []

        private static func before(_ a: (Int64, CellPosition), _ b: (Int64, CellPosition)) -> Bool {
            a.0 != b.0 ? a.0 < b.0 : a.1 < b.1
        }

        mutating func push(_ item: (Int64, CellPosition)) {
            items.append(item)
            var child = items.count - 1
            while child > 0 {
                let up = (child - 1) / 2
                guard Self.before(items[child], items[up]) else { break }
                items.swapAt(child, up)
                child = up
            }
        }

        mutating func pop() -> (Int64, CellPosition)? {
            guard !items.isEmpty else { return nil }
            items.swapAt(0, items.count - 1)
            let top = items.removeLast()
            var parent = 0
            while true {
                let left = parent * 2 + 1, right = left + 1
                var least = parent
                if left < items.count, Self.before(items[left], items[least]) { least = left }
                if right < items.count, Self.before(items[right], items[least]) { least = right }
                guard least != parent else { break }
                items.swapAt(parent, least)
                parent = least
            }
            return top
        }
    }
}

/// The player's bus routes on the 2D map (docs/MAP_LAYERS.md 24.8), and
/// the one the bus tool draws.
public struct BusMapOverlay: Hashable, Sendable {
    public struct Route: Hashable, Sendable {
        public let id: BusRouteID
        /// The line whose colour it takes: the first line calling at its
        /// station, or none.
        public let line: LineID?
        public let color: LineColor?
        /// Its way, the farthest stop first and the station last.
        public let points: [PlanPoint]
        public let stops: [PlanPoint]
        /// Whether it runs: a route of no bus is drawn faint.
        public let runs: Bool
    }

    /// The route the bus tool draws, over the others.
    public struct Draft: Hashable, Sendable {
        /// Its way along the roads, from the station out.
        public let points: [PlanPoint]
        public let stops: [PlanPoint]
        public let station: PlanPoint
        /// Two ends no road joins, drawn as a broken line.
        public let broken: [PlanPoint]
        public let isBuildable: Bool
    }

    public var routes: [Route] = []
    public var draft: Draft?

    public init(routes: [Route] = [], draft: Draft? = nil) {
        self.routes = routes
        self.draft = draft
    }
}

/// The words for buses.
public enum BusRouteText {
    /// "640 m" or "1.8 km".
    public static func distance(_ metres: Int64, in language: DisplayLanguage) -> String {
        guard metres >= 1_000 else { return language.text("\(metres) m", "\(metres) 公尺") }
        let tenths = (metres + 50) / 100
        return language.text("\(tenths / 10).\(tenths % 10) km", "\(tenths / 10).\(tenths % 10) 公里")
    }

    /// "1 stop", "3 stops".
    static func stops(_ count: Int) -> String {
        count == 1 ? "1 stop" : "\(count) stops"
    }

    /// "1 bus", "3 buses".
    static func buses(_ count: Int) -> String {
        count == 1 ? "1 bus" : "\(count) buses"
    }

    /// A route's name: "Feeder bus 3".
    public static func name(_ id: BusRouteID, in language: DisplayLanguage) -> String {
        language.text("Feeder bus \(id.rawValue)", "接駁公車 \(id.rawValue) 號")
    }
}

/// A bus route as the station panel lists it (decision 400): its way, its
/// buses and its last day's takings, booked with the property row.
public struct BusRouteCard: Hashable, Sendable, Identifiable {
    public let id: BusRouteID
    public let title: String
    /// "1.8 km · 3 stops".
    public let wayText: String
    /// "A bus every 10 min · 2 buses", or that it does not run.
    public let serviceText: String
    /// Yesterday's riders, fares, cost and what was left, or that it has
    /// not run a whole day yet.
    public let dayText: String
    /// The last day's fares less its cost; `nil` before one.
    public let net: Money?
    public let headway: Int64
    public let buses: Int
}

extension GameWorld {
    /// The cards of the bus routes feeding station `id`, by number.
    public func busRouteCards(feeding id: StationID, in language: DisplayLanguage) -> [BusRouteCard] {
        busRoutes.filter { $0.station == id }.map { route in
            let way = language.text(
                "\(BusRouteText.distance(route.metres, in: language)) · \(BusRouteText.stops(route.stops.count))",
                "\(BusRouteText.distance(route.metres, in: language)) · \(route.stops.count) 個站牌"
            )
            let service: String
            if let headway = route.headway {
                service = language.text("A bus every \(headway) min · \(BusRouteText.buses(route.buses))", "每 \(headway) 分一班 · \(route.buses) 輛車")
            } else {
                service = language.text("No buses: it does not run.", "沒有車：路線停駛中。")
            }
            let day: String
            if let last = route.days.last {
                let net = last.fares - last.cost
                day = language.text(
                    "Last day: \(Money(last.riders).displayText) riders · fares \(last.fares.moneyText) · cost \(last.cost.moneyText) · \(net.moneyText)",
                    "前一天：\(Money(last.riders).displayText) 人搭 · 票收 \(last.fares.moneyText) · 成本 \(last.cost.moneyText) · \(net.moneyText)"
                )
            } else {
                day = language.text("No whole day run yet.", "還沒跑滿一天。")
            }
            return BusRouteCard(
                id: route.id, title: BusRouteText.name(route.id, in: language), wayText: way, serviceText: service, dayText: day,
                net: route.days.last.map { $0.fares - $0.cost }, headway: route.service.averageMinutes, buses: route.buses
            )
        }
    }
}

extension GameSession {
    /// Whether the bus tool is open: in a game with roads, outside the
    /// tutorial and the lessons.
    public var allowsBusTool: Bool {
        world.roads != nil && tutorial == nil && lesson == nil
    }

    /// A tap with the bus tool at `point`, reaching `reach`: the first picks
    /// the station the route feeds (one a road reaches); then each tap on a
    /// road puts a stop there, and a tap on a stop takes it away. Never
    /// changes the world.
    public func tapBusTool(at point: PlanPoint, reach: Int64) {
        guard world.bounds.contains(point), let roads = world.roads else { return }
        message = nil
        guard busDraft.station != nil else {
            guard let station = world.station(near: point, within: reach) else {
                message = StatusMessage(kind: .failure, text: language.text(
                    "Tap the station the bus route feeds first.", "先點公車路線要接的車站。"
                ))
                return
            }
            guard roads.cells.contains(CellPosition(containing: station.location)) else {
                message = StatusMessage(kind: .failure, text: language.text(
                    "No road reaches \(station.name) yet: build its station road in the station's panel first.",
                    "\(station.name) 還沒有路接到：先在車站面板鋪站前路。"
                ))
                return
            }
            busDraft.station = station.id
            refreshBusPreview()
            return
        }
        let cell = CellPosition(containing: point)
        if let index = busDraft.stops.firstIndex(of: cell) {
            busDraft.stops.remove(at: index)
        } else if busDraft.stops.isEmpty, busDraft.route == nil, let station = world.station(near: point, within: reach / 2),
                  station.id != busDraft.station, roads.cells.contains(CellPosition(containing: station.location)) {
            // Another station, before any stop: the route starts there.
            busDraft.station = station.id
        } else if !roads.cells.contains(cell) {
            message = StatusMessage(kind: .failure, text: language.text("Bus stops go on roads.", "公車站牌要放在路上。"))
            return
        } else if busDraft.stops.count >= BusRoute.maximumStops {
            message = StatusMessage(kind: .failure, text: language.text(
                "A bus route has at most \(BusRoute.maximumStops) stops.", "一條公車路線最多 \(BusRoute.maximumStops) 個站牌。"
            ))
            return
        } else {
            busDraft.stops.append(cell)
        }
        refreshBusPreview()
    }

    /// Takes back the last stop, then the station.
    public func removeLastBusStop() {
        if busDraft.stops.isEmpty {
            guard busDraft.route == nil else { return }
            busDraft.station = nil
        } else {
            busDraft.stops.removeLast()
        }
        refreshBusPreview()
    }

    /// Lets go of the route drawn: a new one starts from a station again.
    public func clearBusDraft() {
        busDraft = BusRouteDraft()
        busPreview = nil
        busDraftPath = []
    }

    /// Sets the drawn route's headway.
    public func setBusDraftHeadway(_ minutes: Int64) {
        guard minutes != busDraft.headway || busDraft.service != .every(minutes: minutes) else { return }
        busDraft.service = .every(minutes: minutes)
        refreshBusPreview()
    }

    /// Sets the drawn route's buses.
    public func setBusDraftBuses(_ buses: Int) {
        let buses = min(max(buses, 1), BusRoute.maximumBuses)
        guard buses != busDraft.buses else { return }
        busDraft.buses = buses
        refreshBusPreview()
    }

    /// Opens the drawn route, or saves the stops of the one edited, and
    /// pays for it. Returns whether it did.
    @discardableResult
    public func confirmBusRoute() -> Bool {
        guard let station = busDraft.station, busPreview?.canOpen == true else { return false }
        let draft = busDraft
        let stops = draft.coreStops.map(PlayerCommand.Edit.BusStop.init)
        let edit: PlayerCommand.Edit = if let id = draft.route {
            .reviseBusRoute(id, stops: stops, service: draft.service, buses: draft.buses)
        } else {
            .createBusRoute(station, stops: stops, service: draft.service, buses: draft.buses)
        }
        let done = perform(edit) { _, before, after in
            let price = before.economy.balance - after.economy.balance
            let name = after.station(id: station)?.name ?? ""
            return draft.route == nil
                ? language.text("A bus now runs to \(name), for \(price.moneyText).", "接到\(name)的公車開通了，花費 \(price.moneyText)。")
                : language.text("The bus route to \(name) is changed, for \(price.moneyText).", "接到\(name)的公車改好了，花費 \(price.moneyText)。")
        }
        guard done != nil else { return false }
        clearBusDraft()
        return true
    }

    /// Opens the bus tool on route `id`, to move its stops.
    public func editBusRoute(_ id: BusRouteID) {
        guard let route = world.busRoute(id: id) else { return }
        selectTool(.bus)
        var draft = BusRouteDraft()
        draft.station = route.station
        draft.stops = route.stops.reversed()
        draft.service = route.service
        draft.buses = route.buses
        draft.route = id
        busDraft = draft
        refreshBusPreview()
    }

    /// Opens the bus tool with a new route from station `id`.
    public func startBusRoute(from id: StationID) {
        selectTool(.bus)
        clearBusDraft()
        busDraft.station = id
        refreshBusPreview()
    }

    /// Runs `buses` buses on route `id` (the route card).
    public func setBusCount(_ id: BusRouteID, to buses: Int) {
        perform(.setBusCount(id, buses: buses)) { _, before, after in
            let price = before.economy.balance - after.economy.balance
            return price > .zero
                ? language.text("\(BusRouteText.buses(buses)) now run, for \(price.moneyText).", "現在跑 \(buses) 輛車，花費 \(price.moneyText)。")
                : language.text("\(BusRouteText.buses(buses)) now run.", "現在跑 \(buses) 輛車。")
        }
        refreshBusPreview()
    }

    /// Sends route `id`'s buses every `minutes` (the route card).
    public func setBusHeadway(_ id: BusRouteID, to minutes: Int64) {
        perform(.setBusRuns(id, .every(minutes: minutes))) { _, _, _ in
            language.text("A bus every \(minutes) min from now on.", "之後每 \(minutes) 分一班。")
        }
        refreshBusPreview()
    }

    /// Closes route `id` (the route card): its stops and buses are not sold
    /// back.
    public func removeBusRoute(_ id: BusRouteID) {
        if busDraft.route == id { clearBusDraft() }
        perform(.removeBusRoute(id)) { _, _, _ in
            language.text("The bus route is closed.", "公車路線停駛了。")
        }
    }

    /// Works the bus tool's preview out again for the drawn route.
    func refreshBusPreview() {
        busPreview = BusRoutePreview.make(busDraft, in: world, language: language)
        if let station = busDraft.station.flatMap({ world.station(id: $0) }), let roads = world.roads, !busDraft.stops.isEmpty {
            busDraftPath = BusRoadPath.points(stops: busDraft.coreStops, station: station.location, roads: roads.cells).reversed()
        } else {
            busDraftPath = []
        }
    }

    /// The player's bus routes and the one drawn, for the map; `nil` with
    /// neither.
    public var busMapOverlay: BusMapOverlay? {
        guard let roads = world.roads, !world.busRoutes.isEmpty || busDraft.station != nil else { return nil }
        var overlay = BusMapOverlay()
        for route in world.busRoutes where route.id != busDraft.route || tool != .bus {
            guard let station = world.station(id: route.station) else { continue }
            let points: [PlanPoint]
            if let memo = busPathMemo[route.id], memo.stops == route.stops, memo.station == station.location {
                points = memo.points
            } else {
                points = BusRoadPath.points(stops: route.stops, station: station.location, roads: roads.cells)
                busPathMemo[route.id] = (route.stops, station.location, points)
            }
            let line = world.lines(callingAt: route.station).first
            overlay.routes.append(BusMapOverlay.Route(
                id: route.id, line: line?.id, color: line?.color, points: points, stops: route.stops.map(\.middle), runs: route.buses > 0
            ))
        }
        if tool == .bus, let id = busDraft.station, let station = world.station(id: id) {
            overlay.draft = BusMapOverlay.Draft(
                points: busDraftPath, stops: busDraft.stops.map(\.middle), station: station.location,
                broken: busPreview?.brokenLeg ?? [], isBuildable: busPreview?.canOpen ?? false
            )
        }
        return overlay
    }
}
