// A real line the company bought (ARCHITECTURE decision 315): the app lays
// its track, stations, trains and real timetable with the commands it
// already has, then records the purchase here, paying for the line's
// riders. GameCore reads no real data: the app gives the line's name and
// its riders as numbers, as it gives a station's transfer points
// (decision 298).

/// A real line the company bought (decision 315).
public struct LineAcquisition: Hashable, Sendable {
    /// The real line's name in the app's data (`"tra:PINGXI"`): bought
    /// once only.
    public let realLine: String
    /// The line its trains run as. Kept when the line is removed later, so
    /// the real line is still the company's.
    public let line: LineID
    /// The game day it was bought.
    public let day: Int64
    /// What its riders cost (``LineAcquisition/value(ofDailyRiders:)``).
    public let value: Money

    /// The most riders a day a bought line is paid for: more than the
    /// busiest TRA station's.
    public static let maximumDailyRiders: Int64 = 200_000
    /// What a bought line costs for each rider a day its stations carry in
    /// real life, on top of building it and its trains: $40.
    public static let valuePerDailyRider = Money(4_000)
    /// The longest real line name kept.
    public static let maximumNameLength = 64
    /// Bought before this second of a day, the line runs that day's
    /// timetable; from it on, the next day's: 04:00, before any branch
    /// line's first train.
    public static let sameDayCutoff: Int64 = 4 * 3_600

    /// What a line whose stations carry `riders` a day costs for them.
    public static func value(ofDailyRiders riders: Int64) -> Money {
        Money(riders * valuePerDailyRider.amount)
    }

    /// The first day whose runs a line bought at `time` runs: the same day
    /// before ``sameDayCutoff``, the next one after.
    public static func firstServiceDay(at time: GameTime) -> Int64 {
        let day = GameTime.floorDivide(time.seconds, GameTime.secondsPerDay)
        return time.seconds - day * GameTime.secondsPerDay < sameDayCutoff ? day : day + 1
    }

    var isValid: Bool {
        !realLine.isEmpty && realLine.count <= Self.maximumNameLength && day >= 0 && value >= .zero
    }
}

extension LineAcquisition: Codable {
    private enum CodingKeys: String, CodingKey {
        case realLine, line, day, value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        realLine = try container.decode(String.self, forKey: .realLine)
        line = try container.decode(LineID.self, forKey: .line)
        day = try container.decode(Int64.self, forKey: .day)
        value = try container.decode(Money.self, forKey: .value)
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .realLine, in: container, debugDescription: "A line bought has a name, a day and a value of at least 0.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(realLine, forKey: .realLine)
        try container.encode(line, forKey: .line)
        try container.encode(day, forKey: .day)
        try container.encode(value, forKey: .value)
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Records that line `id` is real line `realLine`, bought (decision
    /// 315): pays ``LineAcquisition/value(ofDailyRiders:)`` for its
    /// `dailyRiders`, on the books as an asset written down as track is,
    /// and sets its runs to start on ``LineAcquisition/firstServiceDay(at:)``,
    /// so its trains, standing where its timetable has them at night, run
    /// from that day's first train.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``;
    ///   ``GameError/lineAlreadyAcquired`` if `realLine` or the line was
    ///   bought before; ``GameError/invalidAcquisition`` for an empty
    ///   or too long name, riders outside 0 to
    ///   ``LineAcquisition/maximumDailyRiders``, or a line without runs or
    ///   one that has run one; ``GameError/insufficientFunds(required:available:)``.
    ///   The world is then unchanged.
    public mutating func recordLineAcquisition(line id: LineID, realLine: String, dailyRiders: Int64) throws(GameError) {
        let index = try lineIndex(of: id)
        guard !acquisitions.contains(where: { $0.realLine == realLine || $0.line == id }) else { throw .lineAlreadyAcquired }
        let line = lines[index]
        guard !realLine.isEmpty, realLine.count <= LineAcquisition.maximumNameLength,
              (0...LineAcquisition.maximumDailyRiders).contains(dailyRiders),
              !line.runs.isEmpty, line.runDays.allSatisfy({ $0 == nil }) else {
            throw .invalidAcquisition
        }
        let value = LineAcquisition.value(ofDailyRiders: dailyRiders)
        try economy.spend(value)
        let lastDayDone = LineAcquisition.firstServiceDay(at: clock.now) - 1
        setRunsDone(ofLine: index, through: lastDayDone >= 0 ? lastDayDone : nil)
        acquisitions.append(LineAcquisition(realLine: realLine, line: id, day: dayIndex(of: clock.now), value: value))
        acquireAsset(.acquiredLine, owner: id.rawValue, cost: value)
    }

    // MARK: - Queries

    /// The purchase of real line `realLine`, or `nil` if it was not bought.
    public func acquisition(of realLine: String) -> LineAcquisition? {
        acquisitions.first { $0.realLine == realLine }
    }

    // MARK: - Validation

    func acquisitionsProblem() -> String? {
        guard acquisitions.allSatisfy({ $0.isValid && $0.line.rawValue < lineIDsHandedOut }),
              Set(acquisitions.map(\.realLine)).count == acquisitions.count,
              Set(acquisitions.map(\.line)).count == acquisitions.count else {
            return "Each line bought is well formed, a line ID handed out, and bought once."
        }
        return nil
    }
}
