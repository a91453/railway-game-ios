// Goals and scenarios (decision 86): what a game asks the player to reach,
// by when, and how well they did. None of the owner's references has a
// railway goal to port: the `Ci/` game has no objectives, and the Taipei
// pack's missions (`Railway/taipei_gta_reference/`) are an action game's
// errands. So the goals are native, and read only what the game already
// keeps: the network's lines and stations, the day accounts, the city's land
// and buildings, the closed years and the balance sheet (decision 85). They
// are judged at every managed midnight, after the year's closing, so a goal
// met is met on a day, the same however the time was advanced.

/// One thing a scenario asks for.
public enum Goal: Hashable, Sendable {
    /// Every point has a station within `radius` world units that a line
    /// calls at, and those stations are one network: lines that share a
    /// station, or stop at stations of one transfer group (decision 81),
    /// are joined.
    case connect(points: [PlanPoint], radius: Int64)
    /// At least this many passengers paid a fare in the day that ended.
    case dailyRiders(Int64)
    /// At least this many people live on the map's land (Phase 6a).
    case population(Int64)
    /// At least this many of the city's buildings are of the tallest
    /// density, D4 (Phase 6c).
    case tallBuildings(Int)
    /// A closed year made at least this net profit (decision 85).
    case annualNetProfit(Money)
    /// The company is worth at least this much (decision 85).
    case equity(Money)
}

/// How well a scenario was completed: by its gold, its silver or its last
/// day.
public enum ScenarioRating: String, CaseIterable, Codable, Sendable {
    case gold, silver, bronze
}

/// Why a scenario was lost.
public enum ScenarioFailure: String, Codable, Sendable {
    /// Its last day passed before every goal was met.
    case deadline
    /// The balance was below zero at too many midnights in a row.
    case insolvency
}

/// How a scenario ended. The game goes on either way.
public enum ScenarioOutcome: Hashable, Sendable {
    /// Every goal met by the end of day `day`.
    case completed(day: Int64, rating: ScenarioRating)
    case failed(day: Int64, reason: ScenarioFailure)
}

/// A festival a scenario holds every year (decision 90): station
/// `station`'s demand raised by `boost` thousandths for `days` days from
/// day `dayOfYear` of each 360-day year (day 0 the game's first), announced
/// `notice` days before (a demand event of kind
/// ``DemandEventKind/festival``).
public struct ScenarioEvent: Hashable, Codable, Sendable {
    public let station: StationID
    public let dayOfYear: Int64
    public let days: Int64
    public let boost: Int64
    public let notice: Int64

    public init(station: StationID, dayOfYear: Int64, days: Int64, boost: Int64, notice: Int64) {
        self.station = station
        self.dayOfYear = dayOfYear
        self.days = days
        self.boost = boost
        self.notice = notice
    }

    var isValid: Bool {
        (0..<FinancePeriod.year.days).contains(dayOfYear) && (1...30).contains(days) && (1...2_000).contains(boost) && (0...30).contains(notice)
    }
}

/// A scenario's rules (decision 86): its goals, the days from its start
/// by which meeting them all earns gold, silver and bronze (the last its
/// deadline), how many midnights in a row in the red lose it, and the train
/// types its era has.
public struct Scenario: Hashable, Sendable {
    /// What GamePresentation names and describes it by, such as
    /// `"sandbox.threeTowns"`.
    public let id: String
    public let goals: [Goal]
    public let goldDays: Int64
    public let silverDays: Int64
    public let deadlineDays: Int64
    /// `nil`: the balance may stay below zero.
    public let insolvencyDays: Int64?
    /// The train types the player may give a train (the era's), or `nil`
    /// for all of them. A train without a type is always allowed.
    public let trainTypes: [TrainType]?
    /// The festivals it holds every year (decision 90).
    public let events: [ScenarioEvent]

    public init(
        id: String, goals: [Goal], goldDays: Int64, silverDays: Int64, deadlineDays: Int64,
        insolvencyDays: Int64? = nil, trainTypes: [TrainType]? = nil, events: [ScenarioEvent] = []
    ) {
        self.id = id
        self.goals = goals
        self.goldDays = goldDays
        self.silverDays = silverDays
        self.deadlineDays = deadlineDays
        self.insolvencyDays = insolvencyDays
        self.trainTypes = trainTypes
        self.events = events
    }

    /// The most goals a scenario has, and points a connection goal names.
    public static let maximumGoals = 16
    public static let maximumPoints = 16
    /// The longest a scenario may run: 50 of the report's 360-day years.
    public static let maximumDays: Int64 = 50 * FinancePeriod.year.days

    /// Whether the scenario could be played in `bounds`.
    func isValid(in bounds: WorldBounds) -> Bool {
        guard (1...Self.maximumGoals).contains(goals.count), !id.isEmpty, id.count <= 64,
              1 <= goldDays, goldDays <= silverDays, silverDays <= deadlineDays, deadlineDays <= Self.maximumDays,
              insolvencyDays.map({ (1...Self.maximumDays).contains($0) }) ?? true,
              trainTypes.map({ !$0.isEmpty && Set($0).count == $0.count }) ?? true,
              events.count <= Self.maximumGoals, events.allSatisfy(\.isValid)
        else { return false }
        return goals.allSatisfy { goal in
            switch goal {
            case .connect(let points, let radius):
                (2...Self.maximumPoints).contains(points.count) && points.allSatisfy(bounds.contains)
                    && (1...WorldBounds.maximumSide).contains(radius)
            case .dailyRiders(let count), .population(let count):
                (1...GameWorld.maximumAccrued).contains(count)
            case .tallBuildings(let count):
                count >= 1 && count <= 1 << 20
            case .annualNetProfit(let amount), .equity(let amount):
                (1...GameWorld.maximumAccrued).contains(amount.amount)
            }
        }
    }

    /// The rating for completing on `elapsed` days after the start, or
    /// `nil` after the deadline.
    public func rating(afterDays elapsed: Int64) -> ScenarioRating? {
        if elapsed <= goldDays { return .gold }
        if elapsed <= silverDays { return .silver }
        if elapsed <= deadlineDays { return .bronze }
        return nil
    }
}

/// A scenario being played: its rules, the day it started, the day each
/// goal was first met, the midnights in a row the balance has been below
/// zero, and how it ended.
public struct ScenarioState: Hashable, Sendable {
    public let scenario: Scenario
    /// The day it started: its days count from the end of this one.
    public let startDay: Int64
    /// The day each goal was first met, in the scenario's order; a goal met
    /// stays met.
    public internal(set) var achieved: [Int64?]
    public internal(set) var insolventDays: Int64
    public internal(set) var outcome: ScenarioOutcome?

    init(scenario: Scenario, startDay: Int64) {
        self.scenario = scenario
        self.startDay = startDay
        achieved = Array(repeating: nil, count: scenario.goals.count)
        insolventDays = 0
        outcome = nil
    }

    /// Days since the start, counting day `day` itself as the first.
    public func elapsedDays(through day: Int64) -> Int64 {
        day - startDay + 1
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Starts `scenario` now: its days count from today, and its goals are
    /// judged from tonight's midnight on. A scenario already being played is
    /// replaced. Only a managed company plays one: the goals read its
    /// accounts. Free.
    ///
    /// - Throws: ``GameError/invalidScenario`` in free play, or for one with
    ///   no goals or too many, days out of order, a connection outside the
    ///   world, a target that is not positive, or a festival at a station
    ///   that does not exist (decision 90).
    public mutating func startScenario(_ scenario: Scenario) throws(GameError) {
        guard accounts.mode == .management, scenario.isValid(in: bounds),
              scenario.events.allSatisfy({ station(id: $0.station) != nil }) else { throw .invalidScenario }
        self.scenario = ScenarioState(scenario: scenario, startDay: dayIndex(of: clock.now))
    }

    // MARK: - Queries

    /// Whether goal `goal` is met now: what tonight's judgement would find.
    public func isMet(_ goal: Goal) -> Bool {
        switch goal {
        case .connect(let points, let radius):
            connectedStations(near: points, radius: radius) != nil
        case .dailyRiders(let count):
            lastDayTrips() >= count
        case .population(let count):
            totalResidents() >= count
        case .tallBuildings(let count):
            tallBuildingCount() >= count
        case .annualNetProfit(let amount):
            accounts.years.contains { $0.income.netProfit >= amount }
        case .equity(let amount):
            balanceSheet().equity >= amount
        }
    }

    /// The scenario's day now, 1 on the day it started, or `nil` without one.
    public func scenarioDay() -> Int64? {
        scenario.map { $0.elapsedDays(through: dayIndex(of: clock.now)) }
    }

    /// The passengers who paid a fare in the last day that ended.
    public func lastDayTrips() -> Int64 {
        let yesterday = dayIndex(of: clock.now) - 1
        return accounts.days.first { $0.day == yesterday }?.fareTrips ?? 0
    }

    /// Everyone living on the map's land.
    public func totalResidents() -> Int64 {
        land.cells.reduce(0) { $0 + $1.residents }
    }

    /// The city's buildings of density D4.
    public func tallBuildingCount() -> Int {
        buildings.all.count { $0.density == .d4 }
    }

    /// For each of `points`, a station within `radius` that a line calls
    /// at, all of them one network, or `nil` when there are none such (see
    /// ``Goal/connect(points:radius:)``). Each point takes the lowest
    /// numbered such station of the network that serves them all.
    public func connectedStations(near points: [PlanPoint], radius: Int64) -> [StationID]? {
        // Union-find over the stations lines call at.
        var parent: [StationID: StationID] = [:]
        func root(_ id: StationID) -> StationID {
            var id = id
            while let up = parent[id], up != id { id = up }
            return id
        }
        func join(_ a: StationID, _ b: StationID) {
            let (ra, rb) = (root(a), root(b))
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }
        for line in lines {
            for stop in line.stops where parent[stop] == nil { parent[stop] = stop }
            for stop in line.stops.dropFirst() { join(line.stops[0], stop) }
        }
        for group in transferGroups {
            let served = group.stations.filter { parent[$0] != nil }
            for station in served.dropFirst() { join(served[0], station) }
        }
        let squared = radius * radius
        func near(_ point: PlanPoint) -> [StationID] {
            stations.filter { station in
                guard parent[station.id] != nil else { return false }
                let dx = station.point.x - point.x, dy = station.point.y - point.y
                return dx * dx + dy * dy <= squared
            }.map(\.id).sorted()
        }
        let candidates = points.map(near)
        let networks = Set(candidates.flatMap { $0.map(root) }).sorted()
        for network in networks {
            let chosen = candidates.compactMap { $0.first { root($0) == network } }
            if chosen.count == points.count { return chosen }
        }
        return nil
    }

    // MARK: - Judgement

    /// Judges the scenario at the midnight that ended day `day`: each goal
    /// not yet met that is met now is met on `day`; then all of them met
    /// completes it, rated by the days it took, while a deadline passed or
    /// too many midnights in the red lose it. Once it has ended nothing
    /// changes.
    mutating func judgeScenario(endingWith day: Int64) {
        guard var state = scenario, state.outcome == nil else { return }
        for index in state.achieved.indices where state.achieved[index] == nil && isMet(state.scenario.goals[index]) {
            state.achieved[index] = day
        }
        let elapsed = state.elapsedDays(through: day)
        state.insolventDays = economy.balance < .zero ? state.insolventDays + 1 : 0
        if state.achieved.allSatisfy({ $0 != nil }), let rating = state.scenario.rating(afterDays: elapsed) {
            state.outcome = .completed(day: day, rating: rating)
        } else if let limit = state.scenario.insolvencyDays, state.insolventDays >= limit {
            state.outcome = .failed(day: day, reason: .insolvency)
        } else if elapsed >= state.scenario.deadlineDays {
            state.outcome = .failed(day: day, reason: .deadline)
        }
        scenario = state
    }

    // MARK: - Validation

    /// Why the scenario breaks a decision 86 rule, or `nil`.
    func scenarioProblem() -> String? {
        guard let state = scenario else { return nil }
        let today = dayIndex(of: clock.now)
        guard state.scenario.isValid(in: bounds), state.achieved.count == state.scenario.goals.count,
              (0...today).contains(state.startDay),
              state.achieved.allSatisfy({ $0.map { (state.startDay..<today).contains($0) } ?? true }),
              (0...Scenario.maximumDays).contains(state.insolventDays)
        else { return "The scenario's rules, start, goals met or days in the red are out of range." }
        switch state.outcome {
        case nil:
            return nil
        case .completed(let day, let rating)?:
            guard state.achieved.allSatisfy({ $0.map { $0 <= day } ?? false }), state.achieved.contains(day),
                  state.scenario.rating(afterDays: state.elapsedDays(through: day)) == rating
            else { return "A completed scenario must have met every goal by its day, rated by the days it took." }
            return nil
        case .failed(let day, _)?:
            guard (state.startDay..<today).contains(day) else { return "A lost scenario must end on a day it was played." }
            return nil
        }
    }
}

// MARK: - Codable

extension Goal: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, points, radius, count, amount
    }

    private enum Kind: String, Codable {
        case connect, dailyRiders, population, tallBuildings, annualNetProfit, equity
    }

    /// `{"kind": "connect", "points": [...], "radius": r}`, or a kind with
    /// its `"count"` or `"amount"`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .connect:
            self = .connect(points: try container.decode([PlanPoint].self, forKey: .points), radius: try container.decode(Int64.self, forKey: .radius))
        case .dailyRiders: self = .dailyRiders(try container.decode(Int64.self, forKey: .count))
        case .population: self = .population(try container.decode(Int64.self, forKey: .count))
        case .tallBuildings: self = .tallBuildings(try container.decode(Int.self, forKey: .count))
        case .annualNetProfit: self = .annualNetProfit(try container.decode(Money.self, forKey: .amount))
        case .equity: self = .equity(try container.decode(Money.self, forKey: .amount))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .connect(let points, let radius):
            try container.encode(Kind.connect, forKey: .kind)
            try container.encode(points, forKey: .points)
            try container.encode(radius, forKey: .radius)
        case .dailyRiders(let count):
            try container.encode(Kind.dailyRiders, forKey: .kind)
            try container.encode(count, forKey: .count)
        case .population(let count):
            try container.encode(Kind.population, forKey: .kind)
            try container.encode(count, forKey: .count)
        case .tallBuildings(let count):
            try container.encode(Kind.tallBuildings, forKey: .kind)
            try container.encode(count, forKey: .count)
        case .annualNetProfit(let amount):
            try container.encode(Kind.annualNetProfit, forKey: .kind)
            try container.encode(amount, forKey: .amount)
        case .equity(let amount):
            try container.encode(Kind.equity, forKey: .kind)
            try container.encode(amount, forKey: .amount)
        }
    }
}

extension Scenario: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, goals, goldDays, silverDays, deadlineDays, insolvencyDays, trainTypes, events
    }

    /// Decodes the rules; one without an insolvency limit or an era has no
    /// `"insolvencyDays"` or `"trainTypes"`. That they are valid is checked
    /// by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id), goals: try container.decode([Goal].self, forKey: .goals),
            goldDays: try container.decode(Int64.self, forKey: .goldDays), silverDays: try container.decode(Int64.self, forKey: .silverDays),
            deadlineDays: try container.decode(Int64.self, forKey: .deadlineDays),
            insolvencyDays: try container.decodeIfPresent(Int64.self, forKey: .insolvencyDays),
            trainTypes: try container.decodeIfPresent([TrainType].self, forKey: .trainTypes),
            events: try container.decodeIfPresent([ScenarioEvent].self, forKey: .events) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(goals, forKey: .goals)
        try container.encode(goldDays, forKey: .goldDays)
        try container.encode(silverDays, forKey: .silverDays)
        try container.encode(deadlineDays, forKey: .deadlineDays)
        try container.encodeIfPresent(insolvencyDays, forKey: .insolvencyDays)
        try container.encodeIfPresent(trainTypes, forKey: .trainTypes)
        if !events.isEmpty {
            try container.encode(events, forKey: .events)
        }
    }
}

extension ScenarioOutcome: Codable {
    private enum CodingKeys: String, CodingKey {
        case day, rating, failure
    }

    /// `{"day": d, "rating": "gold"}` or `{"day": d, "failure": "deadline"}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let day = try container.decode(Int64.self, forKey: .day)
        if let rating = try container.decodeIfPresent(ScenarioRating.self, forKey: .rating) {
            guard !container.contains(.failure) else {
                throw DecodingError.dataCorruptedError(forKey: .failure, in: container, debugDescription: "An outcome is a rating or a failure, not both.")
            }
            self = .completed(day: day, rating: rating)
        } else {
            self = .failed(day: day, reason: try container.decode(ScenarioFailure.self, forKey: .failure))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .completed(let day, let rating):
            try container.encode(day, forKey: .day)
            try container.encode(rating, forKey: .rating)
        case .failed(let day, let reason):
            try container.encode(day, forKey: .day)
            try container.encode(reason, forKey: .failure)
        }
    }
}

extension ScenarioState: Codable {
    private enum CodingKeys: String, CodingKey {
        case scenario, startDay, achieved, insolventDays, outcome
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scenario = try container.decode(Scenario.self, forKey: .scenario)
        startDay = try container.decode(Int64.self, forKey: .startDay)
        achieved = try container.decode([Int64?].self, forKey: .achieved)
        insolventDays = container.contains(.insolventDays) ? try container.decode(Int64.self, forKey: .insolventDays) : 0
        outcome = try container.decodeIfPresent(ScenarioOutcome.self, forKey: .outcome)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scenario, forKey: .scenario)
        try container.encode(startDay, forKey: .startDay)
        try container.encode(achieved, forKey: .achieved)
        if insolventDays != 0 {
            try container.encode(insolventDays, forKey: .insolventDays)
        }
        try container.encodeIfPresent(outcome, forKey: .outcome)
    }
}
