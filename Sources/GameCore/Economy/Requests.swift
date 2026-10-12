// The city's requests and subsidies (ARCHITECTURE decision 183): errands
// with a deadline, a clear reward and no fine, for the middle of a free
// game, after A-Train's administrative measures and OpenTTD's subsidies
// (read for the idea only).
//
// The shape is the owner's references': a mission has a kind, a target, a
// reward and a time limit (`Railway/city_world_reference/source/assets/
// missions-*.js`: `reward`, `steps[].timeLimit`, `objective`), and a
// director offers it, judges it, and on success adds the reward and the
// giver's regard (`OpenWorld/.../game/mission-director.js`: `_advance(
// message, reward, rep)`, `snapshot`/`restore` clamping what a save holds).
// The railway conditions have no source and are this project's own.
//
// On the first of every month (30 days) up to three offers of different
// kinds are drawn from the world's seed and the month (decision 162's
// keyed hash: nothing is stored day by day for the draw); one not taken
// lapses when the next month's are drawn. The city trusts the company with
// 0 to 5 stars, 1 at first, and with 1 + ⌊trust / 2⌋ requests in hand at a
// time. Every managed midnight judges them: one met is paid on the first of
// the next month (a `monthlySubsidy` row, taxable) and earns a star; one
// past its deadline costs a star and nothing else.
//
// Everything is whole numbers.

/// What the city asks for.
public enum CityRequestKind: String, CaseIterable, Codable, Sendable {
    /// A station within 800 m of a settlement that has none, called at ten
    /// times a day.
    case newStation
    /// A station's planned daily trips up by two fifths.
    case stationRiders
    /// The network's best day of paying passengers up by a quarter.
    case networkRiders
    /// Tons of building materials brought by rail to a station short of
    /// them (with freight and building materials on).
    case materials
    /// The residents round a station up by a fifth.
    case population
    /// Tourists to a sight (with tourism on).
    case tourism
}

/// One request: offered, in hand, or done.
public struct CityRequest: Hashable, Sendable {
    public let id: Int
    public let kind: CityRequestKind
    /// The settlement's middle, for ``CityRequestKind/newStation``.
    public let point: PlanPoint?
    /// The station, for riders, materials and population.
    public let station: StationID?
    /// The sight, for ``CityRequestKind/tourism``.
    public let attraction: AttractionID?
    /// What it measured when offered: the settlement's residents and jobs,
    /// the station's trips or residents, the network's best day; 0 for the
    /// counted kinds (materials, tourism).
    public let baseline: Int64
    /// What ``progress`` must reach.
    public let target: Int64
    public let reward: Money
    /// The days it allows from the day it is accepted.
    public let days: Int64
    public let offeredDay: Int64
    /// The day it was accepted, or `nil` for an offer.
    public internal(set) var acceptedDay: Int64?
    /// How far it has come, as last judged: the most calls a day at a
    /// station within reach of the settlement, the station's trips or
    /// residents, the best day since it was accepted, or the tons or
    /// tourists counted since.
    public internal(set) var progress: Int64
    /// For ``CityRequestKind/newStation``, the calls of the day so far at
    /// each station within reach: a midnight reads and clears them.
    var callsToday: [StationID: Int64]

    init(id: Int, kind: CityRequestKind, point: PlanPoint? = nil, station: StationID? = nil, attraction: AttractionID? = nil,
         baseline: Int64, target: Int64, reward: Money, days: Int64, offeredDay: Int64) {
        self.id = id
        self.kind = kind
        self.point = point
        self.station = station
        self.attraction = attraction
        self.baseline = baseline
        self.target = target
        self.reward = reward
        self.days = days
        self.offeredDay = offeredDay
        acceptedDay = nil
        progress = 0
        callsToday = [:]
    }

    /// The last day it can be met on, once accepted.
    public var deadline: Int64? {
        acceptedDay.map { $0 + days - 1 }
    }
}

/// How a request ended.
public struct CityRequestResult: Hashable, Sendable {
    public let request: CityRequest
    public let succeeded: Bool
    /// The day it was met or lapsed, or was given up.
    public let day: Int64
}

/// The city's requests of the company (decision 183).
public struct CityRequests: Hashable, Sendable {
    public let seed: UInt32
    /// 0 to ``maximumTrust`` stars.
    public internal(set) var trust: Int
    /// This month's offers, at most ``maximumOffers``, of different kinds.
    public internal(set) var offers: [CityRequest]
    /// The requests in hand, at most ``capacity(trust:)``, by ID.
    public internal(set) var active: [CityRequest]
    /// The last ``keptResults`` results, oldest first.
    public internal(set) var results: [CityRequestResult]
    /// The subsidies met and not yet paid: paid on the first of the month.
    public internal(set) var owed: Money
    /// Every subsidy paid so far.
    public internal(set) var paid: Money
    /// The most paying passengers of any day so far: what a network riders
    /// request is measured against.
    public internal(set) var bestDayTrips: Int64
    public internal(set) var nextID: Int

    public static let startingTrust = 1
    public static let maximumTrust = 5
    public static let maximumOffers = 3
    public static let keptResults = 20
    /// A month: offers are drawn on its first day and lapse at the next.
    public static let monthDays: Int64 = 30

    /// How far a station counts as serving a place: 800 m.
    public static let reach = Land.catchmentRadius
    // The kinds' rules: this project's own (gap), after the dispatch's
    // numbers (decision 183).
    public static let settlementPeople: Int64 = 3_000
    public static let settlementCalls: Int64 = 10
    public static let stationTripsFloor: Int64 = 500
    public static let networkTripsFloor: Int64 = 200
    public static let populationFloor: Int64 = 1_000
    /// The most a request pays: $10 million.
    public static let maximumReward = Money(1_000_000_000)

    public init(seed: UInt32) {
        self.seed = seed
        trust = Self.startingTrust
        offers = []
        active = []
        results = []
        owed = .zero
        paid = .zero
        bestDayTrips = 0
        nextID = 1
    }

    /// The requests the company may hold at once at `trust`.
    public static func capacity(trust: Int) -> Int {
        1 + trust / 2
    }

    public var capacity: Int { Self.capacity(trust: trust) }

    /// The days a request of `kind` allows.
    public static func days(of kind: CityRequestKind) -> Int64 {
        switch kind {
        case .newStation, .networkRiders, .tourism: 90
        case .stationRiders: 60
        case .materials: 45
        case .population: 120
        }
    }

    /// `value × numerator / denominator`, rounded up.
    static func ceiling(_ value: Int64, _ numerator: Int64, _ denominator: Int64) -> Int64 {
        (value * numerator + denominator - 1) / denominator
    }

    /// `dollars` dollars, at least `floor` dollars and at most ``maximumReward``.
    static func reward(dollars: Int64, floor: Int64 = 0) -> Money {
        min(Money(max(dollars, floor) * 100), maximumReward)
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns the city's requests on, drawn from `seed`, or off with `nil`
    /// (decision 183). Free. Turning them on starts at one star of trust
    /// and draws this month's offers at once; turning them off forgets
    /// them, and what was owed.
    public mutating func setCityRequests(seed: UInt32?) {
        guard let seed else {
            cityRequests = nil
            return
        }
        var requests = CityRequests(seed: seed)
        requests.bestDayTrips = accounts.days.map(\.fareTrips).max() ?? 0
        cityRequests = requests
        let today = dayIndex(of: clock.now)
        drawCityRequests(month: CompanyAccounts.floorDivide(today, CityRequests.monthDays), day: today)
    }

    /// Takes on offer `id`: its days run from today.
    ///
    /// - Throws: ``GameError/cityRequestsNotEnabled``,
    ///   ``GameError/unknownCityRequest(_:)`` for no such offer, or
    ///   ``GameError/cityRequestLimitReached(limit:)``.
    public mutating func acceptRequest(_ id: Int) throws(GameError) {
        guard var requests = cityRequests else { throw .cityRequestsNotEnabled }
        guard let index = requests.offers.firstIndex(where: { $0.id == id }) else { throw .unknownCityRequest(id) }
        guard requests.active.count < requests.capacity else { throw .cityRequestLimitReached(limit: requests.capacity) }
        var request = requests.offers.remove(at: index)
        request.acceptedDay = dayIndex(of: clock.now)
        request.progress = measure(request)
        requests.active.append(request)
        requests.active.sort { $0.id < $1.id }
        cityRequests = requests
    }

    /// Turns down offer `id`, which goes; or gives up request `id` in hand,
    /// which fails now and costs a star.
    ///
    /// - Throws: ``GameError/cityRequestsNotEnabled`` or
    ///   ``GameError/unknownCityRequest(_:)``.
    public mutating func declineRequest(_ id: Int) throws(GameError) {
        guard var requests = cityRequests else { throw .cityRequestsNotEnabled }
        if let index = requests.offers.firstIndex(where: { $0.id == id }) {
            requests.offers.remove(at: index)
        } else if let index = requests.active.firstIndex(where: { $0.id == id }) {
            let request = requests.active.remove(at: index)
            requests.record(CityRequestResult(request: request, succeeded: false, day: dayIndex(of: clock.now)))
        } else {
            throw .unknownCityRequest(id)
        }
        cityRequests = requests
    }

    // MARK: - Queries

    /// The request with `id`, offered or in hand.
    public func cityRequest(id: Int) -> CityRequest? {
        cityRequests.flatMap { requests in (requests.offers + requests.active).first { $0.id == id } }
    }

    /// Where request `request` is on the map: its settlement, station or
    /// sight, or `nil` for the whole network (or a station or sight gone).
    public func location(of request: CityRequest) -> PlanPoint? {
        if let point = request.point { return point }
        if let id = request.station { return station(id: id)?.point }
        if let id = request.attraction { return attraction(id: id)?.point }
        return nil
    }

    /// Whether a passenger line with trains calls at station `id` and it
    /// takes passengers.
    func isServedStation(_ id: StationID) -> Bool {
        allowsService(at: id) && lines.contains { !$0.isFreight && !$0.trains.isEmpty && $0.stops.contains(id) }
    }

    /// What `request` measures now; for the counted kinds, what it has
    /// counted.
    public func measure(_ request: CityRequest) -> Int64 {
        switch request.kind {
        case .newStation, .materials, .tourism, .networkRiders: request.progress
        case .stationRiders: request.station.flatMap { stationDemand(of: $0)?.dailyTrips } ?? 0
        case .population: request.station.flatMap { landCatchment(of: $0)?.residents } ?? 0
        }
    }

    // MARK: - Counting

    /// A passenger line's train calls at `station` (it leaves it for its
    /// next stop): it counts for each settlement request in hand within
    /// reach.
    mutating func countRequestCall(at station: StationID) {
        guard let requests = cityRequests, requests.active.contains(where: { $0.kind == .newStation }),
              let point = self.station(id: station)?.point else { return }
        let reach = CityRequests.reach * CityRequests.reach
        for index in requests.active.indices where requests.active[index].kind == .newStation {
            guard let middle = requests.active[index].point else { continue }
            let dx = point.x - middle.x, dy = point.y - middle.y
            guard dx * dx + dy * dy <= reach else { continue }
            cityRequests!.active[index].callsToday[station, default: 0] += 1
        }
    }

    /// `tons` of building materials were brought by rail to `station`.
    mutating func countRequestMaterials(_ tons: Int64, at station: StationID) {
        guard tons > 0, let requests = cityRequests else { return }
        for index in requests.active.indices where requests.active[index].kind == .materials && requests.active[index].station == station {
            cityRequests!.active[index].progress = min(requests.active[index].progress + tons, Self.maximumAccrued)
        }
    }

    // MARK: - Midnight

    /// Judges the requests in hand at the end of day `day`, then, as the
    /// next day begins a month, pays what is owed (a row at `time`) and
    /// draws the month's offers. Managed midnights only.
    mutating func judgeCityRequests(endingWith day: Int64, time: GameTime) {
        guard var requests = cityRequests else { return }
        let trips = accounts.days.first { $0.day == day }?.fareTrips ?? 0
        var kept: [CityRequest] = []
        for var request in requests.active {
            switch request.kind {
            case .newStation:
                request.progress = request.callsToday.values.max() ?? 0
                request.callsToday = [:]
            case .networkRiders:
                request.progress = max(request.progress, trips)
            case .tourism:
                if let sight = request.attraction.flatMap(attraction(id:)) {
                    request.progress = min(request.progress + sight.yesterday, Self.maximumAccrued)
                }
            case .materials:
                break
            case .stationRiders, .population:
                request.progress = measure(request)
            }
            if request.progress >= request.target {
                requests.owed = requests.owed + request.reward
                requests.record(CityRequestResult(request: request, succeeded: true, day: day))
            } else if let deadline = request.deadline, day >= deadline {
                requests.record(CityRequestResult(request: request, succeeded: false, day: day))
            } else {
                kept.append(request)
            }
        }
        requests.active = kept
        requests.bestDayTrips = max(requests.bestDayTrips, trips)
        let next = day + 1
        let opensMonth = CompanyAccounts.floorDivide(next, CityRequests.monthDays) * CityRequests.monthDays == next
        if opensMonth, requests.owed > .zero {
            let owed = requests.owed
            requests.paid = requests.paid + owed
            requests.owed = .zero
            cityRequests = requests
            write(LedgerEntry(kind: .monthlySubsidy, time: time, amount: owed, breakdown: [LedgerLine(item: .subsidy, amount: owed)]), day: day)
        } else {
            cityRequests = requests
        }
        if opensMonth {
            drawCityRequests(month: next / CityRequests.monthDays, day: next)
        }
    }

    /// Draws month `month`'s offers on day `day`, replacing any left: the
    /// kinds in an order hashed from the seed and the month, and of each
    /// the first whose conditions hold, up to three.
    mutating func drawCityRequests(month: Int64, day: Int64) {
        guard var requests = cityRequests else { return }
        let draw = SeedDraw(seed: requests.seed)
        let kinds = CityRequestKind.allCases.enumerated().sorted {
            let a = draw.hash("requests.\(month).order.\($0.element.rawValue)"), b = draw.hash("requests.\(month).order.\($1.element.rawValue)")
            return (a, $0.offset) < (b, $1.offset)
        }.map(\.element)
        var offers: [CityRequest] = []
        for kind in kinds where offers.count < CityRequests.maximumOffers {
            guard var offer = makeRequest(kind, month: month, day: day, draw: draw, id: requests.nextID, active: requests.active) else { continue }
            offer.progress = 0
            offers.append(offer)
            requests.nextID += 1
        }
        requests.offers = offers
        cityRequests = requests
    }

    /// An offer of `kind`, if its conditions hold, not for what a request
    /// in hand of the same kind already asks.
    private func makeRequest(_ kind: CityRequestKind, month: Int64, day: Int64, draw: SeedDraw, id: Int,
                             active: [CityRequest]) -> CityRequest? {
        let days = CityRequests.days(of: kind)
        let taken = Set(active.filter { $0.kind == kind }.compactMap(\.station))
        func pick(_ candidates: [StationID]) -> StationID? {
            let free = candidates.filter { !taken.contains($0) }
            guard !free.isEmpty else { return nil }
            return free[Int(draw.roll("requests.\(month).\(kind.rawValue)", in: 0...Int64(free.count - 1)))]
        }
        let served = stations.map(\.id).filter(isServedStation)
        switch kind {
        case .newStation:
            let near = active.filter { $0.kind == .newStation }.compactMap(\.point)
            guard let place = largestUnservedSettlement(avoiding: near) else { return nil }
            return CityRequest(id: id, kind: kind, point: place.point, baseline: place.people, target: CityRequests.settlementCalls,
                               reward: CityRequests.reward(dollars: 300_000 + 50 * place.people), days: days, offeredDay: day)
        case .stationRiders:
            let candidates = served.filter { (stationDemand(of: $0)?.dailyTrips ?? 0) >= CityRequests.stationTripsFloor }
            guard let station = pick(candidates), let trips = stationDemand(of: station)?.dailyTrips else { return nil }
            let target = CityRequests.ceiling(trips, 14, 10)
            return CityRequest(id: id, kind: kind, station: station, baseline: trips, target: target,
                               reward: CityRequests.reward(dollars: 40 * (target - trips), floor: 200_000), days: days, offeredDay: day)
        case .networkRiders:
            guard !active.contains(where: { $0.kind == .networkRiders }), let best = cityRequests?.bestDayTrips,
                  best >= CityRequests.networkTripsFloor else { return nil }
            let target = CityRequests.ceiling(best, 125, 100)
            return CityRequest(id: id, kind: kind, baseline: best, target: target,
                               reward: CityRequests.reward(dollars: 20 * (target - best), floor: 200_000), days: days, offeredDay: day)
        case .materials:
            guard let state = freight, state.buildingMaterials, let station = pick(state.lastShort.filter { self.station(id: $0) != nil }) else {
                return nil
            }
            let tons = 7 * Self.dailyMaterialsNeed
            return CityRequest(id: id, kind: kind, station: station, baseline: 0, target: tons,
                               reward: CityRequests.reward(dollars: 30 * tons, floor: 200_000), days: days, offeredDay: day)
        case .population:
            let candidates = served.filter { (landCatchment(of: $0)?.residents ?? 0) >= CityRequests.populationFloor }
            guard let station = pick(candidates), let residents = landCatchment(of: station)?.residents else { return nil }
            let target = CityRequests.ceiling(residents, 12, 10)
            return CityRequest(id: id, kind: kind, station: station, baseline: residents, target: target,
                               reward: CityRequests.reward(dollars: 100 * (target - residents), floor: 1_000_000), days: days, offeredDay: day)
        case .tourism:
            guard let sights = tourism?.attractions else { return nil }
            let busy = Set(active.filter { $0.kind == .tourism }.compactMap(\.attraction))
            // A sight served asks for a fifth more than it draws (a better
            // shop); one not yet served, three fifths of it (a station soon).
            let candidates = sights.filter { sight in
                !busy.contains(sight.id) && (servingStation(at: sight.point) == nil || sight.souvenir < Tourism.maximumSouvenirLevel)
            }
            guard !candidates.isEmpty else { return nil }
            let sight = candidates[Int(draw.roll("requests.\(month).\(kind.rawValue)", in: 0...Int64(candidates.count - 1)))]
            let expected = (day..<day + days).reduce(Int64(0)) { $0 + touristsExpected(for: sight, onDay: $1) }
            let share: Int64 = servingStation(at: sight.point) == nil ? 600 : 1_200
            let target = max(1, CityRequests.ceiling(expected, share, 1_000))
            return CityRequest(id: id, kind: kind, attraction: sight.id, baseline: 0, target: target,
                               reward: CityRequests.reward(dollars: 10 * target, floor: 500_000), days: days, offeredDay: day)
        }
    }

    /// The building materials a growing station uses in a day at most: a
    /// new cell and its raises (decision 157).
    static var dailyMaterialsNeed: Int64 {
        Freight.newCellMaterials + Int64(LandDemand.upgradesPerStation) * Freight.materials(toRaise: .d1)
    }

    /// The settlement with the most residents and jobs within 800 m of its
    /// middle, at least 3,000, with no station within 800 m and not within
    /// 800 m of a point in `avoiding`. The land is summed in squares of 12
    /// cells (768 m); the twelve fullest are measured round their weighted
    /// middles.
    func largestUnservedSettlement(avoiding: [PlanPoint]) -> (point: PlanPoint, people: Int64)? {
        let side = 12
        struct Square { var people: Int64 = 0, x: Int64 = 0, y: Int64 = 0 }
        var squares: [Int64: Square] = [:]
        let columns = Int64(Land.columns(in: bounds) / side + 1)
        for cell in land.cells {
            let people = cell.residents + cell.jobs
            guard people > 0 else { continue }
            let key = Int64(cell.row / side) * columns + Int64(cell.column / side)
            let centreX = Int64(cell.column) * Land.cellLength + Land.cellLength / 2
            let centreY = Int64(cell.row) * Land.cellLength + Land.cellLength / 2
            var square = squares[key] ?? Square()
            square.people += people
            square.x += people * centreX
            square.y += people * centreY
            squares[key] = square
        }
        let fullest = squares.sorted { ($1.value.people, $0.key) < ($0.value.people, $1.key) }.prefix(12)
        let reach = CityRequests.reach * CityRequests.reach
        func near(_ a: PlanPoint, _ b: PlanPoint) -> Bool {
            let dx = a.x - b.x, dy = a.y - b.y
            return dx * dx + dy * dy <= reach
        }
        var best: (point: PlanPoint, people: Int64)?
        for (_, square) in fullest {
            let point = PlanPoint(x: square.x / square.people, y: square.y / square.people)
            guard !stations.contains(where: { near($0.point, point) }), !avoiding.contains(where: { near($0, point) }) else { continue }
            let totals = land.totals(within: CityRequests.reach, of: point)
            let people = totals.residents + totals.jobs
            if people >= CityRequests.settlementPeople, people > best?.people ?? 0 { best = (point, people) }
        }
        return best
    }

    // MARK: - Validation

    func cityRequestsProblem() -> String? {
        guard let requests = cityRequests else { return nil }
        guard (0...CityRequests.maximumTrust).contains(requests.trust) else { return "The city's trust is 0 to 5 stars." }
        guard requests.offers.count <= CityRequests.maximumOffers, Set(requests.offers.map(\.kind)).count == requests.offers.count,
              requests.active.count <= CityRequests.capacity(trust: CityRequests.maximumTrust),
              requests.results.count <= CityRequests.keptResults
        else { return "The city offers at most three requests of different kinds, and keeps twenty results." }
        let ids = requests.offers.map(\.id) + requests.active.map(\.id)
        guard Set(ids).count == ids.count, ids.allSatisfy({ (1..<requests.nextID).contains($0) }),
              zip(requests.active, requests.active.dropFirst()).allSatisfy({ $0.id < $1.id })
        else { return "City requests are numbered once each, below the next ID." }
        let today = dayIndex(of: clock.now)
        for request in requests.offers + requests.active + requests.results.map(\.request) {
            guard request.target >= 1, request.days >= 1, request.days <= 360, request.offeredDay <= today,
                  (.zero...CityRequests.maximumReward).contains(request.reward), request.reward.amount % 100 == 0,
                  (0...Self.maximumAccrued).contains(request.progress), (0...Self.maximumAccrued).contains(request.baseline),
                  request.callsToday.values.allSatisfy({ $0 >= 0 }), request.acceptedDay.map({ $0 >= request.offeredDay && $0 <= today }) ?? true
            else { return "A city request's target, reward, days or progress are out of range." }
            let subject = switch request.kind {
            case .newStation: request.point != nil && request.station == nil && request.attraction == nil
            case .networkRiders: request.point == nil && request.station == nil && request.attraction == nil
            case .tourism: request.point == nil && request.station == nil && request.attraction != nil
            case .stationRiders, .materials, .population: request.point == nil && request.station != nil && request.attraction == nil
            }
            guard subject else { return "A city request names what its kind asks about, and nothing else." }
        }
        guard requests.offers.allSatisfy({ $0.acceptedDay == nil }), requests.active.allSatisfy({ $0.acceptedDay != nil }) else {
            return "An offer is not accepted yet, and a request in hand is."
        }
        guard requests.owed >= .zero, requests.paid >= .zero, requests.owed.amount % 100 == 0, requests.paid.amount % 100 == 0,
              requests.owed.amount <= Self.maximumAccrued, requests.paid.amount <= Self.maximumAccrued,
              (0...Self.maximumAccrued).contains(requests.bestDayTrips)
        else { return "The city's subsidies owed and paid are whole dollars, none negative." }
        return nil
    }
}

extension CityRequests {
    /// Keeps `result`, the last ``keptResults``, and moves the trust a star.
    mutating func record(_ result: CityRequestResult) {
        results.append(result)
        if results.count > Self.keptResults { results.removeFirst(results.count - Self.keptResults) }
        trust = max(0, min(Self.maximumTrust, trust + (result.succeeded ? 1 : -1)))
    }
}

// MARK: - Codable

extension CityRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, kind, x, y, station, attraction, baseline, target, reward, days, offeredDay, acceptedDay, progress, callsToday
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        kind = try container.decode(CityRequestKind.self, forKey: .kind)
        if container.contains(.x) || container.contains(.y) {
            point = PlanPoint(x: try container.decode(Int64.self, forKey: .x), y: try container.decode(Int64.self, forKey: .y))
        } else {
            point = nil
        }
        station = try container.decodeIfPresent(StationID.self, forKey: .station)
        attraction = try container.decodeIfPresent(AttractionID.self, forKey: .attraction)
        baseline = try container.decodeIfPresent(Int64.self, forKey: .baseline) ?? 0
        target = try container.decode(Int64.self, forKey: .target)
        reward = try container.decode(Money.self, forKey: .reward)
        days = try container.decode(Int64.self, forKey: .days)
        offeredDay = try container.decode(Int64.self, forKey: .offeredDay)
        acceptedDay = try container.decodeIfPresent(Int64.self, forKey: .acceptedDay)
        progress = try container.decodeIfPresent(Int64.self, forKey: .progress) ?? 0
        // `[[station, calls], …]`, by ascending station.
        let calls = try container.decodeIfPresent([[Int64]].self, forKey: .callsToday) ?? []
        var today: [StationID: Int64] = [:]
        for pair in calls {
            guard pair.count == 2, let raw = Int(exactly: pair[0]), today[StationID(rawValue: raw)] == nil else {
                throw DecodingError.dataCorruptedError(forKey: .callsToday, in: container, debugDescription: "Each call count is a station and a number, once each.")
            }
            today[StationID(rawValue: raw)] = pair[1]
        }
        callsToday = today
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        if let point {
            try container.encode(point.x, forKey: .x)
            try container.encode(point.y, forKey: .y)
        }
        try container.encodeIfPresent(station, forKey: .station)
        try container.encodeIfPresent(attraction, forKey: .attraction)
        if baseline != 0 { try container.encode(baseline, forKey: .baseline) }
        try container.encode(target, forKey: .target)
        try container.encode(reward, forKey: .reward)
        try container.encode(days, forKey: .days)
        try container.encode(offeredDay, forKey: .offeredDay)
        try container.encodeIfPresent(acceptedDay, forKey: .acceptedDay)
        if progress != 0 { try container.encode(progress, forKey: .progress) }
        if !callsToday.isEmpty {
            try container.encode(callsToday.keys.sorted().map { [Int64($0.rawValue), callsToday[$0]!] }, forKey: .callsToday)
        }
    }
}

extension CityRequestResult: Codable {
    private enum CodingKeys: String, CodingKey {
        case request, succeeded, day
    }
}

extension CityRequests: Codable {
    private enum CodingKeys: String, CodingKey {
        case seed, trust, offers, active, results, owed, paid, bestDayTrips, nextID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seed = try container.decode(UInt32.self, forKey: .seed)
        trust = try container.decode(Int.self, forKey: .trust)
        offers = try container.decodeIfPresent([CityRequest].self, forKey: .offers) ?? []
        active = try container.decodeIfPresent([CityRequest].self, forKey: .active) ?? []
        results = try container.decodeIfPresent([CityRequestResult].self, forKey: .results) ?? []
        owed = try container.decodeIfPresent(Money.self, forKey: .owed) ?? .zero
        paid = try container.decodeIfPresent(Money.self, forKey: .paid) ?? .zero
        bestDayTrips = try container.decodeIfPresent(Int64.self, forKey: .bestDayTrips) ?? 0
        nextID = try container.decode(Int.self, forKey: .nextID)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seed, forKey: .seed)
        try container.encode(trust, forKey: .trust)
        if !offers.isEmpty { try container.encode(offers, forKey: .offers) }
        if !active.isEmpty { try container.encode(active, forKey: .active) }
        if !results.isEmpty { try container.encode(results, forKey: .results) }
        if owed != .zero { try container.encode(owed, forKey: .owed) }
        if paid != .zero { try container.encode(paid, forKey: .paid) }
        if bestDayTrips != 0 { try container.encode(bestDayTrips, forKey: .bestDayTrips) }
        try container.encode(nextID, forKey: .nextID)
    }
}
