// A run driven by hand, as the world counts it (decision 693; native: the
// owner's references have no driving). The player drives a train to its
// next stop in the presentation layer (decision 686), where the world's
// train runs on to its timetable; when that run ends, its result comes to
// the world as one command, ``GameWorld/settleDrivenRun(_:)``, and the
// world marks it by its own whole-number rules, pays the company for a
// good one and keeps the record. Nothing of the frames or the handle
// reaches the world: only the run's measured result, written in whole
// units so a replay settles it the same.

/// What a run driven by hand came to, as measured where it was driven:
/// whole world units and milliseconds.
public struct DrivenRun: Hashable, Sendable, Codable {
    /// How the run ended.
    public enum Outcome: String, CaseIterable, Codable, Sendable {
        /// Stood near the stopping point.
        case stopped
        /// Ran past the stop.
        case passed
        /// Not there in time.
        case timedOut
    }

    /// The marks of a run, by grade.
    public enum Grade: String, CaseIterable, Codable, Sendable {
        case s = "S", a = "A", b = "B", c = "C", d = "D"
    }

    /// What a run is marked: for where it stopped, for when, and for how
    /// it was handled; all 0 unless it stopped.
    public struct Marks: Hashable, Sendable {
        public let position: Int
        public let time: Int
        public let handling: Int

        public init(position: Int, time: Int, handling: Int) {
            self.position = position
            self.time = time
            self.handling = handling
        }

        public var total: Int { position + time + handling }

        public var grade: Grade {
            switch total {
            case 95...: .s
            case 85...: .a
            case 70...: .b
            case 50...: .c
            default: .d
            }
        }
    }

    public let train: TrainID
    public let outcome: Outcome
    /// World units (``WorldCoordinate/unitsPerMetre``) past the stopping
    /// point; negative: short of it.
    public let offset: Int64
    /// Milliseconds after the timetable's arrival; negative: early.
    public let lateness: Int64
    /// Milliseconds spent over the speed limit.
    public let overspeed: Int64
    public let usedEmergency: Bool

    public init(train: TrainID, outcome: Outcome, offset: Int64, lateness: Int64, overspeed: Int64, usedEmergency: Bool) {
        self.train = train
        self.outcome = outcome
        self.offset = offset
        self.lateness = lateness
        self.overspeed = overspeed
        self.usedEmergency = usedEmergency
    }

    // MARK: The rules' figures (decision 686's, in whole units)

    public static let positionMarks = 50
    public static let timeMarks = 30
    public static let handlingMarks = 20
    /// Within half a metre of the stopping point is on it; 25 m short or
    /// 12.5 m past earns nothing for the position.
    public static let exactOffset: Int64 = WorldCoordinate.unitsPerMetre / 2
    public static let shortOffset: Int64 = 25 * WorldCoordinate.unitsPerMetre
    public static let pastOffset: Int64 = 25 * WorldCoordinate.unitsPerMetre / 2
    /// Within 5 s of the timetable is on time; a minute off earns nothing
    /// for the time.
    public static let exactLateness: Int64 = 5_000
    public static let offLateness: Int64 = 60_000
    /// Two marks a second over the limit, ten for the emergency brake.
    public static let overspeedMarksPerSecond: Int64 = 2
    public static let emergencyMarks = 10
    /// A run that stopped did so within this of its stopping point, and
    /// no run is told of more than an hour late, early or over the limit:
    /// what ``isWellFormed`` asks.
    public static let stopWindow: Int64 = 50 * WorldCoordinate.unitsPerMetre
    public static let longest: Int64 = 3_600_000

    /// Whether the figures are ones a run can have.
    public var isWellFormed: Bool {
        (-Self.longest...Self.longest).contains(lateness) && (0...Self.longest).contains(overspeed)
            && (-Self.longest...Self.longest).contains(offset) && (outcome != .stopped || abs(offset) <= Self.stopWindow)
    }

    /// `marks` in full while `off` is within `full`, none from `none` on,
    /// evenly between, rounded half up.
    static func marks(_ marks: Int, off: Int64, full: Int64, none: Int64) -> Int {
        if off <= full { return marks }
        if off >= none { return 0 }
        let span = none - full
        return Int((2 * Int64(marks) * (none - off) + span) / (2 * span))
    }

    /// The marks of a run that ended so.
    public static func marks(outcome: Outcome, offset: Int64, lateness: Int64, overspeed: Int64, usedEmergency: Bool) -> Marks {
        guard outcome == .stopped else { return Marks(position: 0, time: 0, handling: 0) }
        let position = marks(positionMarks, off: abs(offset), full: exactOffset, none: offset < 0 ? shortOffset : pastOffset)
        let time = marks(timeMarks, off: abs(lateness), full: exactLateness, none: offLateness)
        let lost = (overspeed * overspeedMarksPerSecond + 500) / 1_000 + (usedEmergency ? Int64(emergencyMarks) : 0)
        return Marks(position: position, time: time, handling: handlingMarks - Int(min(max(lost, 0), Int64(handlingMarks))))
    }

    /// The run's marks.
    public var marks: Marks {
        Self.marks(outcome: outcome, offset: offset, lateness: lateness, overspeed: overspeed, usedEmergency: usedEmergency)
    }
}

/// The company's record of the runs driven by hand (decision 693).
public struct DrivingRecord: Hashable, Sendable, Codable {
    /// The runs settled, and those of them that stopped at their stop.
    public internal(set) var runs: Int64
    public internal(set) var arrivals: Int64
    /// The most marks any run was given.
    public internal(set) var best: Int
    /// What the runs have earned the company.
    public internal(set) var earned: Money
    /// The game second the last was settled at.
    public internal(set) var last: Int64
}

/// What settling a run driven by hand came to.
public struct DrivenRunSettlement: Hashable, Sendable {
    public let marks: DrivenRun.Marks
    /// The passengers on the train when it was settled.
    public let riders: Int64
    /// What the company was paid for it; nothing for a run that did not
    /// stop, one marked ``DrivenRun/bonusFloor`` or less, or a company
    /// that keeps no accounts.
    public let bonus: Money
    /// Whether the company keeps accounts (a managed one), so a good run
    /// is paid for.
    public let keepsAccounts: Bool
    /// Whether it is the most marks of any run so far.
    public let isBest: Bool
    /// The record with this run in it.
    public let record: DrivingRecord
}

extension DrivenRun {
    // MARK: What a good run earns

    /// A run earns from this many marks up, in proportion to the marks
    /// above it: all of ``bonus(marks:riders:)``'s amount at 100.
    public static let bonusFloor = 50
    /// For any train, and for each passenger on it, in cents.
    public static let bonusBase: Int64 = 500_00
    public static let bonusPerRider: Int64 = 5_00
    /// The game seconds between two settlements, at least: no run to a
    /// stop is shorter.
    public static let shortestSeconds: Int64 = 20

    /// What a run of `marks` with `riders` on the train earns, in whole
    /// dollars rounded down.
    public static func bonus(marks: Int, riders: Int64) -> Money {
        guard marks > bonusFloor else { return .zero }
        let full = bonusBase + bonusPerRider * max(0, riders)
        return Money(full * Int64(min(marks, 100) - bonusFloor) / Int64(100 - bonusFloor) / 100 * 100)
    }
}

extension GameWorld {
    /// Whether train `id` is one a run driven by hand is settled for: on
    /// the track, running to a timetable or for a line.
    public func settlesDrivenRuns(of id: TrainID) -> Bool {
        guard let train = train(id: id), train.position != nil else { return false }
        return train.execution != nil || assignedLine(of: id) != nil
    }

    /// Settles `run`, a run the player drove by hand (decision 693): marks
    /// it, pays a managed company ``DrivenRun/bonus(marks:riders:)`` for
    /// the passengers on the train now (a ledger row of its own), and adds
    /// it to ``driving``. The train itself is left to its timetable.
    ///
    /// - Throws: ``GameError/unknownTrain(_:)``, or
    ///   ``GameError/invalidDrivenRun`` for figures no run has, a train
    ///   off the track or without a timetable or a line, or a run settled
    ///   less than ``DrivenRun/shortestSeconds`` after the last. The world
    ///   is unchanged.
    @discardableResult
    public mutating func settleDrivenRun(_ run: DrivenRun) throws(GameError) -> DrivenRunSettlement {
        guard train(id: run.train) != nil else { throw .unknownTrain(run.train) }
        let now = clock.now.seconds
        guard run.isWellFormed, settlesDrivenRuns(of: run.train) else { throw .invalidDrivenRun }
        if let driving, now - driving.last < DrivenRun.shortestSeconds { throw .invalidDrivenRun }
        let marks = run.marks
        let riders = riderCount(of: run.train)
        let keepsAccounts = accounts.mode == .management
        let bonus = keepsAccounts ? DrivenRun.bonus(marks: marks.total, riders: riders) : .zero
        if bonus > .zero {
            write(LedgerEntry(
                kind: .drivenRun, time: clock.now, amount: bonus, breakdown: [LedgerLine(item: .drivingBonus, amount: bonus)]
            ), day: dayIndex(of: clock.now))
        }
        var record = driving ?? DrivingRecord(runs: 0, arrivals: 0, best: 0, earned: .zero, last: now)
        let isBest = run.outcome == .stopped && (record.arrivals == 0 || marks.total > record.best)
        record.runs += 1
        if run.outcome == .stopped { record.arrivals += 1 }
        record.best = max(record.best, marks.total)
        record.earned = record.earned + bonus
        record.last = now
        driving = record
        return DrivenRunSettlement(marks: marks, riders: riders, bonus: bonus, keepsAccounts: keepsAccounts, isBest: isBest, record: record)
    }

    /// Whether ``driving`` is a record settlements leave.
    func drivingProblem() -> String? {
        guard let driving else { return nil }
        guard driving.runs >= 1, (0...driving.runs).contains(driving.arrivals), (0...100).contains(driving.best),
              driving.arrivals > 0 || driving.best == 0, driving.earned >= .zero, driving.last <= clock.now.seconds
        else { return "The record of the runs driven by hand is not one settlements leave." }
        return nil
    }
}
