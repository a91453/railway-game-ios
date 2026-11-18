// A real line the company bought (ARCHITECTURE decision 315): the app lays
// its track, stations, trains and real timetable with the commands it
// already has, then records the purchase here, paying for the line's
// riders. GameCore reads no real data: the app gives the line's name and
// its riders as numbers, as it gives a station's transfer points
// (decision 298).

/// A real line the company bought (decision 315), or a real bus route
/// (decision 400, 10i-2).
public struct LineAcquisition: Hashable, Sendable {
    /// What was bought.
    public enum Kind: String, Hashable, Codable, Sendable {
        case railway, bus
    }

    public let kind: Kind
    /// The real line's or route's name in the app's data
    /// (`"tra:PINGXI"`): bought once while the company has it.
    public let realLine: String
    /// The line its trains run as, a railway's. Removing the line drops
    /// the purchase with it, and the real line is on sale again (decision
    /// 528; before it, the purchase was kept and the line never sold
    /// again).
    public let line: LineID?
    /// The bus route it runs as, a bus route's; dropped likewise.
    public let busRoute: BusRouteID?
    /// The game day it was bought.
    public let day: Int64
    /// What its riders cost (``LineAcquisition/value(ofDailyRiders:tier:)``).
    public let value: Money
    /// Decision 528: the track a railway's purchase laid, by edge, which
    /// stays as the line's ``LeftTrack`` when the line is removed; `nil`
    /// for a bus route's and a purchase saved before version 79.
    public private(set) var track: [TrackEdgeID]?
    /// Decision 828: whether the line runs on the state's track, as a
    /// Finnish line runs on the track the state keeps: the company did not
    /// pay for the track it laid (``GameWorld/handOverTrack(_:)``), pays
    /// only ``stateTrackAccessPermille`` of the track's upkeep and route
    /// energy, and its riders pay the kilometre fare
    /// (``stateTrackFare(squaredDistance:)``). `false` for a bus route's
    /// and a purchase saved before version 108.
    public private(set) var stateTrack = false

    /// What kind of railway a line bought is, which sets what each of its
    /// riders costs (decision 400, 10j-3).
    public enum Tier: String, Hashable, Codable, Sendable {
        /// A TRA branch line (decision 315); a purchase recorded without a
        /// tier.
        case branch
        /// A light rail: $70 a rider.
        case lightRail
        /// A metro line: $100 a rider.
        case metro

        /// What a line of this kind costs for each rider a day its
        /// stations carry in real life, on top of building it and its
        /// trains (measured by `AcquisitionReportTests`). An urban
        /// line's riders are many and their trips short, so each is worth
        /// far less than a branch line's; at these values Taipei's, New
        /// Taipei's and Taoyuan's real-place openings can each buy a line
        /// with cash and loan (decision 400, 10j-3).
        public var valuePerDailyRider: Money {
            switch self {
            case .branch: LineAcquisition.valuePerDailyRider
            case .lightRail: Money(21_000)
            case .metro: Money(30_000)
            }
        }
    }

    /// The most riders a day a bought line is paid for: more than the
    /// busiest metro line's (decision 400).
    public static let maximumDailyRiders: Int64 = 2_000_000
    /// What a bought branch line costs for each rider a day its stations
    /// carry in real life, on top of building it and its trains:
    /// NT$30,000 (decision 315, measured by `AcquisitionReportTests`;
    /// decision 499 multiplied it by 3).
    public static let valuePerDailyRider = Money(3_000_000)
    /// The longest real line name kept.
    public static let maximumNameLength = 64
    /// Bought before this second of a day, the line runs that day's
    /// timetable; from it on, the next day's: 04:00, before any branch
    /// line's first train.
    public static let sameDayCutoff: Int64 = 4 * 3_600

    /// Decision 828: the share of its track's upkeep and route energy a
    /// line on the state's track pays as its access charge, in
    /// thousandths: 1 %, about what Finland's basic infrastructure charge
    /// asks of the Kemijärvi line's trains.
    public static let stateTrackAccessPermille: Int64 = 10
    /// Decision 828: what a trip riding a line on the state's track pays a
    /// kilometre of the straight line between its stations, in cents:
    /// NT$5, about what VR's regional trains in Lapland charge.
    public static let stateTrackCentsPerKilometre: Int64 = 500

    /// Decision 828: the kilometre fare of a trip `squaredDistance` (world
    /// units squared) long riding a line on the state's track, in whole
    /// dollars rounded half up. A trip pays this or the network's fare,
    /// whichever is more (``GameWorld/tripFare(from:to:highSpeed:stateTrack:)``).
    public static func stateTrackFare(squaredDistance: Int64) -> Money {
        let units = FixedPoint.squareRoot(max(0, squaredDistance))
        // units / 64,000 kilometres × 500 / 100 dollars.
        let dollars = (units * stateTrackCentsPerKilometre + 3_200_000) / 6_400_000
        return Money(dollars * 100)
    }

    /// What a line of `tier` whose stations carry `riders` a day costs
    /// for them.
    public static func value(ofDailyRiders riders: Int64, tier: Tier = .branch) -> Money {
        Money(riders * tier.valuePerDailyRider.amount)
    }

    /// The first day whose runs a line bought at `time` runs: the same day
    /// before ``sameDayCutoff``, the next one after.
    public static func firstServiceDay(at time: GameTime) -> Int64 {
        let day = GameTime.floorDivide(time.seconds, GameTime.secondsPerDay)
        return time.seconds - day * GameTime.secondsPerDay < sameDayCutoff ? day : day + 1
    }

    /// Railway `realLine`, bought as `line`, laying `track`, on the
    /// state's track if `stateTrack` (decision 828).
    public init(realLine: String, line: LineID, day: Int64, value: Money, track: [TrackEdgeID]? = nil, stateTrack: Bool = false) {
        kind = .railway
        self.realLine = realLine
        self.line = line
        busRoute = nil
        self.day = day
        self.value = value
        self.track = track
        self.stateTrack = stateTrack
    }

    /// Bus route `realLine`, bought as `busRoute`.
    public init(realLine: String, busRoute: BusRouteID, day: Int64, value: Money) {
        kind = .bus
        self.realLine = realLine
        line = nil
        self.busRoute = busRoute
        self.day = day
        self.value = value
        track = nil
    }

    /// It with its track changed by `change` (decision 528: an edge
    /// of it split).
    func splitting(track change: ([TrackEdgeID]) -> [TrackEdgeID]) -> LineAcquisition {
        var changed = self
        changed.track = track.map(change)
        return changed
    }

    var isValid: Bool {
        !realLine.isEmpty && realLine.count <= Self.maximumNameLength && day >= 0 && value >= .zero
            && (kind == .railway) == (line != nil) && (kind == .bus) == (busRoute != nil)
            && (kind == .railway || (track == nil && !stateTrack)) && track.map { !$0.isEmpty && Set($0).count == $0.count } ?? true
    }
}

extension LineAcquisition: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, realLine, line, busRoute, day, value, track, stateTrack
    }

    /// A railway's without `"kind"` (saves before version 73), a bus
    /// route's with `"kind": "bus"` and its `"busRoute"`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .railway
        realLine = try container.decode(String.self, forKey: .realLine)
        line = kind == .railway ? try container.decode(LineID.self, forKey: .line) : nil
        busRoute = kind == .bus ? try container.decode(BusRouteID.self, forKey: .busRoute) : nil
        day = try container.decode(Int64.self, forKey: .day)
        value = try container.decode(Money.self, forKey: .value)
        track = try container.decodeIfPresent([Int].self, forKey: .track)?.map(TrackEdgeID.edge)
        stateTrack = try container.decodeIfPresent(Bool.self, forKey: .stateTrack) ?? false
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .realLine, in: container, debugDescription: "A line bought has a name, a day and a value of at least 0.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if kind != .railway {
            try container.encode(kind, forKey: .kind)
        }
        try container.encode(realLine, forKey: .realLine)
        try container.encodeIfPresent(line, forKey: .line)
        try container.encodeIfPresent(busRoute, forKey: .busRoute)
        try container.encode(day, forKey: .day)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(track?.compactMap(\.networkNumber), forKey: .track)
        if stateTrack {
            try container.encode(true, forKey: .stateTrack)
        }
    }
}

/// Decision 528: the track a real line bought laid, left where it was when
/// the line was removed: what buying that line (or the one sharing its
/// first stations) again takes up first, and only that.
public struct LeftTrack: Hashable, Sendable {
    /// The real line's name in the app's data (``LineAcquisition/realLine``).
    public let realLine: String
    /// Its edges still standing when the line was removed. Some may have
    /// been taken up since.
    public let edges: [TrackEdgeID]

    public init(realLine: String, edges: [TrackEdgeID]) {
        self.realLine = realLine
        self.edges = edges
    }

    var isValid: Bool {
        !realLine.isEmpty && realLine.count <= LineAcquisition.maximumNameLength && !edges.isEmpty && Set(edges).count == edges.count
    }
}

extension LeftTrack: Codable {
    private enum CodingKeys: String, CodingKey {
        case realLine, edges
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        realLine = try container.decode(String.self, forKey: .realLine)
        edges = try container.decode([Int].self, forKey: .edges).map(TrackEdgeID.edge)
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .edges, in: container, debugDescription: "Track left has a line's name and its edges, each once.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(realLine, forKey: .realLine)
        try container.encode(edges.compactMap(\.networkNumber), forKey: .edges)
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Records that line `id` is real line `realLine`, bought (decision
    /// 315): pays ``LineAcquisition/value(ofDailyRiders:tier:)`` for its
    /// `dailyRiders` at `tier`'s value (decision 400), on the books as an asset written down as track is,
    /// and sets its runs to start on ``LineAcquisition/firstServiceDay(at:)``,
    /// so its trains, standing where its timetable has them at night, run
    /// from that day's first train.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``;
    ///   ``GameError/lineAlreadyAcquired`` if the company has `realLine`
    ///   or the line bought (one removed since is not, decision 528);
    ///   ``GameError/invalidAcquisition`` for an empty
    ///   or too long name, riders outside 0 to
    ///   ``LineAcquisition/maximumDailyRiders``, or a line without runs or
    ///   one that has run one, or `track` naming an edge twice or one
    ///   not standing; ``GameError/insufficientFunds(required:available:)``.
    ///   The world is then unchanged.
    ///
    /// Decision 528: `track` is the track the purchase laid, kept with it
    /// and left as its ``LeftTrack`` when the line is removed; the track
    /// `realLine` left before, and what of any track left is gone, is then
    /// forgotten.
    ///
    /// Decision 828: with `stateTrack` the line runs on the state's track
    /// (``LineAcquisition/stateTrack``).
    public mutating func recordLineAcquisition(
        line id: LineID, realLine: String, dailyRiders: Int64, tier: LineAcquisition.Tier = .branch, track: [TrackEdgeID]? = nil,
        stateTrack: Bool = false
    ) throws(GameError) {
        let index = try lineIndex(of: id)
        guard !acquisitions.contains(where: { $0.realLine == realLine || $0.line == id }) else { throw .lineAlreadyAcquired }
        let line = lines[index]
        guard !realLine.isEmpty, realLine.count <= LineAcquisition.maximumNameLength,
              (0...LineAcquisition.maximumDailyRiders).contains(dailyRiders),
              !line.runs.isEmpty, line.runDays.allSatisfy({ $0 == nil }),
              track.map({ !$0.isEmpty && Set($0).count == $0.count && $0.allSatisfy { network.edge($0) != nil } }) ?? true else {
            throw .invalidAcquisition
        }
        let value = LineAcquisition.value(ofDailyRiders: dailyRiders, tier: tier)
        try economy.spend(value)
        let lastDayDone = LineAcquisition.firstServiceDay(at: clock.now) - 1
        setRunsDone(ofLine: index, through: lastDayDone >= 0 ? lastDayDone : nil)
        acquisitions.append(LineAcquisition(realLine: realLine, line: id, day: dayIndex(of: clock.now), value: value, track: track, stateTrack: stateTrack))
        acquireAsset(.acquiredLine, owner: id.rawValue, cost: value)
        leftTrack = leftTrack.compactMap { left in
            let standing = left.edges.filter { network.edge($0) != nil }
            return left.realLine == realLine || standing.isEmpty ? nil : LeftTrack(realLine: left.realLine, edges: standing)
        }
    }

    /// Decision 828: runs `body`, which lays the track of a line the
    /// company buys on the state's track, at the state's cost: what it
    /// builds costs the company nothing, and a managed company keeps no
    /// record of it and books no capital spending for it, so `body` lays
    /// that track and nothing else. The track stays the company's to use
    /// and take up; taking it up refunds nothing, as for any track. A
    /// company building in its way still comes down at the company's cost
    /// (decision 95): its fee is paid from the cash, as the ledger books
    /// it. If `body` throws, so does this, and what it built stays built
    /// (at no cost): call it on a copy of the world to keep the world
    /// unchanged.
    public mutating func layStateTrack(_ body: (inout GameWorld) throws(GameError) -> Void) throws(GameError) {
        let unlimited = economy.unlimitedFunds
        // Edge numbers are never handed out again: the edges `body` lays
        // are numbered from here on.
        let firstEdge = network.nextEdgeNumber
        let standing = placedBuildings
        economy.unlimitedFunds = true
        defer {
            economy.unlimitedFunds = unlimited
            // Its records, at their cost, leave the books and the day's
            // capital spending. Found by their edges, not by where they
            // stand in the list: a company building the track cleared
            // takes its own record out from among the earlier ones
            // (REVIEW-L28).
            var laid = Money.zero
            accounts.assets.removeAll { record in
                guard record.kind == .track, record.owner >= firstEdge else { return false }
                laid = laid + record.cost
                return true
            }
            if laid > .zero {
                accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.capitalSpending = $0.capitalSpending - laid }
            }
            // The company's buildings it cleared: the ledger booked their
            // fees, and the cash pays them (``clear(_:)`` settled nothing
            // while the funds were unlimited).
            let left = Set(placedBuildings.map(\.id))
            let fees = standing.filter { !left.contains($0.id) }.reduce(Money.zero) { $0 + demolitionCost(of: $1) }
            if fees > .zero {
                economy.settle(.zero - fees)
            }
        }
        try body(&self)
    }

    /// Whether line `id` was bought on the state's track (decision 828).
    func runsOnStateTrack(_ id: LineID) -> Bool {
        acquisitions.contains { $0.stateTrack && $0.line == id }
    }

    /// Decision 528: drops the purchase line `id` runs, as the line is
    /// removed, so its real line is on sale again. What it cost was
    /// written off with the line's asset.
    /// What of the track it laid still stands is left as its
    /// ``LeftTrack``, in place of what it left before.
    mutating func forgetAcquisition(ofLine id: LineID) {
        guard let index = acquisitions.firstIndex(where: { $0.line == id }) else { return }
        let bought = acquisitions.remove(at: index)
        let standing = (bought.track ?? []).filter { network.edge($0) != nil }
        leftTrack.removeAll { $0.realLine == bought.realLine }
        if !standing.isEmpty {
            leftTrack.append(LeftTrack(realLine: bought.realLine, edges: standing))
        }
    }

    /// Decision 528: edge `id` split into `first` and `second`
    /// (``splitTrackEdge(_:at:)``), each purchase's track and each track
    /// left holding it holds both parts in its place, so what a line laid
    /// is still what buying it again takes up.
    mutating func splitAcquiredTrack(_ id: TrackEdgeID, into first: TrackEdgeID, _ second: TrackEdgeID) {
        func split(_ edges: [TrackEdgeID]) -> [TrackEdgeID] {
            edges.flatMap { $0 == id ? [first, second] : [$0] }
        }
        for index in acquisitions.indices where acquisitions[index].track?.contains(id) == true {
            acquisitions[index] = acquisitions[index].splitting(track: split)
        }
        for index in leftTrack.indices where leftTrack[index].edges.contains(id) {
            leftTrack[index] = LeftTrack(realLine: leftTrack[index].realLine, edges: split(leftTrack[index].edges))
        }
    }

    /// Decision 528: the track real line `realLine` left when it was
    /// removed, still standing; none if it left none.
    public func trackLeft(by realLine: String) -> [TrackEdgeID] {
        (leftTrack.first { $0.realLine == realLine }?.edges ?? []).filter { network.edge($0) != nil }
    }

    // MARK: - Queries

    /// The purchase of real line `realLine`, or `nil` if it was not bought.
    public func acquisition(of realLine: String) -> LineAcquisition? {
        acquisitions.first { $0.realLine == realLine }
    }

    // MARK: - Validation

    func acquisitionsProblem() -> String? {
        guard acquisitions.allSatisfy({ $0.isValid && ($0.line?.rawValue ?? 0) < lineIDsHandedOut
                  && ($0.busRoute?.rawValue ?? 0) < nextBusRouteID }),
              Set(acquisitions.map(\.realLine)).count == acquisitions.count,
              Set(acquisitions.compactMap(\.line)).count == acquisitions.filter({ $0.kind == .railway }).count,
              Set(acquisitions.compactMap(\.busRoute)).count == acquisitions.filter({ $0.kind == .bus }).count else {
            return "Each line or bus route bought is well formed, a number handed out, and bought once."
        }
        let edgesHandedOut = network.nextEdgeNumber
        func handedOut(_ edges: [TrackEdgeID]) -> Bool { edges.allSatisfy { (1..<edgesHandedOut).contains($0.networkNumber ?? 0) } }
        guard acquisitions.allSatisfy({ handedOut($0.track ?? []) }),
              leftTrack.allSatisfy({ left in left.isValid && handedOut(left.edges) && !acquisitions.contains(where: { $0.realLine == left.realLine }) }),
              Set(leftTrack.map(\.realLine)).count == leftTrack.count else {
            return "Each track left or laid by a purchase is edges handed out, of a line not bought now, once."
        }
        return nil
    }
}
