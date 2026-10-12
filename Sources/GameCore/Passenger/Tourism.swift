// Sights and tourists (ARCHITECTURE decision 174): the second demand curve,
// beside the commuters'. Native: the reference has no tourism rules (its
// OpenWorld destination catalog only lists places), so the stars, the
// seasons and the shop are this project's own, after the idea of A-Train's
// sightseeing development.
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

/// What kind of place an attraction is, which sets its season.
public enum AttractionKind: String, CaseIterable, Codable, Sendable {
    case coast
    case mountain
    case hotSpring
    case town
}

/// A place tourists go to.
public struct Attraction: Hashable, Sendable {
    public let id: AttractionID
    public let name: String
    public let englishName: String
    public let point: PlanPoint
    public let kind: AttractionKind
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
    public static let starsPerSouvenirLevel = 25
    /// What a level of the shop costs: $300,000, in cents.
    public static let souvenirCost: Int64 = 30_000_000
    /// What a tourist spends in the shop, in cents, times its level.
    public static let spendPerLevel: Int64 = 400
    /// A shop's upkeep a day, in hundred-thousandths of what it cost.
    public static let upkeepPerDay: Int64 = 50
    /// How close a station must be to serve an attraction: 800 m.
    public static let reach: Int64 = Land.catchmentRadius
    /// The share of potential tourists a railway fetches, in thousandths.
    public static let captureRate: Int64 = 200
    /// A source station of the outside counts as this many residents.
    public static let outsideWeight: Int64 = 200_000
    public static let busiestSources = 5
    public static let maximumAttractions = 64
    static let potential: [Int64] = [300, 800, 2_000, 4_500, 9_000]

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
        case .town:
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
    }

    var pairs: [StationID: [StationID: Pair]] = [:]

    var isEmpty: Bool { pairs.isEmpty }

    func trips(from origin: StationID, to destination: StationID) -> Int64 {
        guard let pair = pairs[origin]?[destination] else { return 0 }
        return pair.outbound + pair.back
    }

    /// The pair's trips in each hour: the outbound by the scenic arrival
    /// curve of the day, the way back by its departure curve.
    func hourly(from origin: StationID, to destination: StationID) -> [Int64] {
        guard let pair = pairs[origin]?[destination] else { return Array(repeating: 0, count: 24) }
        let out = GameWorld.apportion(pair.outbound, by: Self.weights(arrival: true))
        let back = GameWorld.apportion(pair.back, by: Self.weights(arrival: false))
        return zip(out, back).map { $0 + $1 }
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
}

extension GameWorld {
    // MARK: - Commands

    /// Turns tourism on with these attractions, or off with `nil`
    /// (decision 174). Free. Each attraction is numbered from 1 in the
    /// order given and starts with no shop and no tourists.
    public mutating func setTourism(_ attractions: [Attraction]?) {
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
    /// from `seed` (decision 174): on a cell of leisure land first, then on
    /// a steep slope or by the water (a cell next to water), and, if the map
    /// has too few of those, anywhere inside the world at least 600 m from
    /// its edge. Two are at least 3 km apart. Each has a kind that fits where
    /// it stands (water: coast, steep: mountain, leisure: a hot spring or a
    /// town), a name from its kind's list and 2 to 4 stars.
    public mutating func foundAttractions(seed: UInt32) {
        let draw = SeedDraw(seed: seed)
        let wanted = Int(draw.roll("tourism.count", in: 3...5))
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
        var chosen: [(point: PlanPoint, place: Place)] = []
        func far(_ point: PlanPoint) -> Bool {
            let spacing = 3_000 * WorldCoordinate.unitsPerMetre
            return chosen.allSatisfy { other in
                let dx = other.point.x - point.x, dy = other.point.y - point.y
                return dx * dx + dy * dy >= spacing * spacing
            }
        }
        var attempt = 0
        while chosen.count < wanted, attempt < 200 {
            defer { attempt += 1 }
            let point: PlanPoint
            let place: Place
            if !candidates.isEmpty, attempt < 100 {
                let pick = candidates[Int(draw.roll("tourism.pick.\(attempt)", in: 0...Int64(candidates.count - 1)))]
                (point, place) = pick
            } else {
                let x = draw.roll("tourism.x.\(attempt)", in: margin...max(margin, bounds.width - margin))
                let y = draw.roll("tourism.y.\(attempt)", in: margin...max(margin, bounds.height - margin))
                (point, place) = (PlanPoint(x: x, y: y), .open)
            }
            guard point.x >= 0, point.y >= 0, point.x < bounds.width, point.y < bounds.height, far(point) else { continue }
            chosen.append((point, place))
        }
        var list: [Attraction] = []
        for (index, spot) in chosen.enumerated() {
            let kind: AttractionKind = switch spot.place {
            case .water: .coast
            case .steep: .mountain
            case .leisure: draw.roll("tourism.kind.\(index)", in: 0...1) == 0 ? .hotSpring : .town
            case .open: AttractionKind.allCases[Int(draw.roll("tourism.kind.\(index)", in: 0...3))]
            }
            let names = Self.attractionNames[kind]!
            let name = names[Int(draw.roll("tourism.name.\(index)", in: 0...Int64(names.count - 1)))]
            list.append(Attraction(id: AttractionID(rawValue: index + 1), name: name.chinese, englishName: name.english, point: spot.point,
                                   kind: kind, baseStars: Int(draw.roll("tourism.stars.\(index)", in: 2...4)) * 100))
        }
        setTourism(list)
    }

    private func cellCentre(row: Int, column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * Land.cellLength + Land.cellLength / 2, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
    }

    static let attractionNames: [AttractionKind: [(chinese: String, english: String)]] = [
        .coast: [("海岬燈塔", "Cape Lighthouse"), ("白沙灣", "White Sand Bay"), ("礁岩海岸", "Reef Coast")],
        .mountain: [("雲海山頂", "Sea-of-Clouds Peak"), ("森林步道", "Forest Trail"), ("高山湖", "Alpine Lake")],
        .hotSpring: [("溫泉鄉", "Hot Spring Village"), ("湯谷溫泉", "Hot Valley Spa"), ("碧潭溫泉", "Green Pool Spa")],
        .town: [("老街", "Old Street"), ("古城門", "Old Town Gate"), ("市集廣場", "Market Square")],
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
    public func attractionStation(of id: AttractionID) -> StationID? {
        guard let attraction = attraction(id: id) else { return nil }
        return servingStation(at: attraction.point)
    }

    func servingStation(at point: PlanPoint) -> StationID? {
        let limit = Tourism.reach * Tourism.reach
        var best: (StationID, Int64)?
        for station in stations {
            let dx = station.point.x - point.x, dy = station.point.y - point.y
            let squared = dx * dx + dy * dy
            guard squared <= limit, allowsService(at: station.id), stationDemand(of: station.id) != nil,
                  lines.contains(where: { !$0.isFreight && $0.stops.contains(station.id) && !$0.trains.isEmpty })
            else { continue }
            if best == nil || (squared, station.id) < (best!.1, best!.0) { best = (station.id, squared) }
        }
        return best?.0
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
        let blowing = typhoons(onDay: day).contains { $0.isActive(onDay: day) && $0.covers(attraction.point) }
        guard !blowing else { return 0 }
        let year = FinancePeriod.year.days
        let dayOfYear = day - CompanyAccounts.floorDivide(day, year) * year
        let month = Int(dayOfYear / 30) + 1
        let dayFactor = Tourism.dayFactor(weekday: StationDemand.weekday(ofDay: day), holiday: holiday(onDay: day) != nil)
        let weather: Int64 = self.weather(onDay: day) == .clear ? 1_000 : 700
        return Tourism.tourists(stars: attraction.stars, day: dayFactor,
                                season: Tourism.seasonFactor(attraction.kind, month: month), weather: weather)
    }

    /// Why attraction `id` draws no tourists now, or ``AttractionStatus/ok``.
    public func attractionStatus(of id: AttractionID) -> AttractionStatus {
        guard let attraction = attraction(id: id) else { return .noStation }
        let day = dayIndex(of: clock.now)
        if typhoons(onDay: day).contains(where: { $0.isActive(onDay: day) && $0.covers(attraction.point) }) { return .typhoon }
        guard let station = servingStation(at: attraction.point) else { return .noStation }
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        let sources = touristSources(excluding: station, among: touristCandidates())
        return sources.contains { reaches(from: $0.station, to: station, graph: graph) } ? .ok : .noSource
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
    /// `station`, with their weight: each outside connection at
    /// ``Tourism/outsideWeight``, and the busiest ``Tourism/busiestSources``
    /// stations by residents at their residents (the two add up for a station
    /// that is both); by ascending station, never `station` itself.
    func touristSources(excluding station: StationID,
                        among candidates: [(station: StationID, outside: Bool, residents: Int64)]) -> [(station: StationID, weight: Int64)] {
        var weights: [StationID: Int64] = [:]
        var residential: [(StationID, Int64)] = []
        for candidate in candidates where candidate.station != station {
            if candidate.outside { weights[candidate.station, default: 0] += Tourism.outsideWeight }
            if candidate.residents > 0 { residential.append((candidate.station, candidate.residents)) }
        }
        residential.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        for (id, residents) in residential.prefix(Tourism.busiestSources) { weights[id, default: 0] += residents }
        return weights.keys.sorted().map { ($0, weights[$0]!) }
    }

    /// The tourists' trips on game day `day`, each attraction's tourists
    /// shared among the sources that can ride to its station (and back),
    /// `reaches` saying which pairs can ride. Empty without tourism.
    func touristFlows(onDay day: Int64, reaches: (StationID, StationID) -> Bool) -> (flows: TouristFlows, arrivals: [AttractionID: Int64]) {
        var flows = TouristFlows()
        var arrivals: [AttractionID: Int64] = [:]
        guard let tourism else { return (flows, arrivals) }
        let candidates = touristCandidates()
        for attraction in tourism.attractions {
            let expected = touristsExpected(for: attraction, onDay: day)
            guard expected > 0, let station = servingStation(at: attraction.point) else { continue }
            let sources = touristSources(excluding: station, among: candidates).filter { reaches($0.station, station) }
            guard !sources.isEmpty else { continue }
            let shares = Self.apportion(expected, by: sources.map(\.weight))
            for (source, share) in zip(sources, shares) where share > 0 {
                flows.add(outbound: share, back: 0, from: source.station, to: station)
                if reaches(station, source.station) {
                    flows.add(outbound: 0, back: share, from: station, to: source.station)
                }
            }
            arrivals[attraction.id] = shares.reduce(0, +)
        }
        return (flows, arrivals)
    }

    /// Today's tourist trips as the passenger model reaches them now (an
    /// empty set without tourism).
    func currentTouristFlows() -> TouristFlows {
        guard tourism != nil else { return TouristFlows() }
        let world = self
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        return world.touristFlows(onDay: dayIndex(of: clock.now)) { world.reaches(from: $0, to: $1, graph: graph) }.flows
    }

    // MARK: - Midnight

    /// Counts the tourists of the day that ended, rolls the counters at the
    /// year's end. Runs at midnight, before the day is settled.
    mutating func closeTourismDay(_ day: Int64) {
        guard var tourism, day >= 0 else { return }
        let world = self
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        let arrived = world.touristFlows(onDay: day) { world.reaches(from: $0, to: $1, graph: graph) }.arrivals
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

    mutating func recordSouvenirAsset(of id: AttractionID, cost: Money) {
        guard accounts.mode == .management else { return }
        if let index = accounts.assets.firstIndex(where: { $0.kind == .souvenirShop && $0.owner == id.rawValue }) {
            accounts.assets[index].cost = accounts.assets[index].cost + cost
            accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.capitalSpending = $0.capitalSpending + cost }
        } else {
            acquireAsset(.souvenirShop, owner: id.rawValue, cost: cost)
        }
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
