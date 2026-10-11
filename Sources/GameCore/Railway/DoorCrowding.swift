// Door crowding (ARCHITECTURE decision 169): the crowd at a train's doors
// slows the passengers going through them.
//
// The reference pack's dwell is
//
//     dwellTicks = doorOpen + serviceTicks + doorClose + platformCongestionPenalty
//
// (`Railway/railway_game_reference_clean/01_MIGRATION_MAP.md`, "Suggested
// dwell calculation"). It names the congestion term and gives it no formula
// and no unit, and the metro game (`Ci/`) has no rule that makes a dwell
// depend on passengers at all (see `StationDwell.swift`). So this rule is
// this project's (gap), in the family the project already uses for crowding
// (`PassengerCrowding`: the Bureau of Public Roads link cost function,
// `1 + 0.15 x⁴`), with a stronger coefficient because a door is a narrower
// way than a line:
//
//     time = ceil(count ÷ rate × (1 + 1.5 × crowd⁴))
//
// where `rate` is what the train's doors pass a second uncrowded
// (``Train/passengersPerSecond``) and `crowd` is the larger of two ratios
// taken when the doors have opened: the riders on board over what the train
// is rated for, and the passengers waiting at the station over what the
// station holds (``StationPassengers/capacity``), at most the 1.1 a train
// takes (``DoorCrowding/limit``).
//
//     crowd   0.3    0.5    0.8    1.0    1.1
//     time    ×1.01  ×1.09  ×1.61  ×2.50  ×3.20
//
// So a train that is half full or less passes its passengers as it did,
// and one that is full takes two and a half times as long: where the doors
// are few for the people (a monorail car has 112 a door, a wide-body metro
// car 62) the dwell is longer than the metro game's 36 s, and the train
// leaves late.
//
// Everything is integer arithmetic in thousandths, so every platform makes
// the same dwell. The rule is off in a new world and in saves from before it
// (``GameWorld/doorCrowding``): with it off, every exchange takes what it
// took.

/// The crowd at a train's doors and what it does to the time passengers
/// take to get off and on (decision 169).
public enum DoorCrowding {
    /// The most crowd counted, in thousandths of what a train is rated for:
    /// the 1.1 it takes at most (the reference's
    /// `METRO_TRAIN_OPERATIONAL_LOAD_FACTOR`).
    public static let limit: Int64 = 1_100
    /// How much the fourth power of the crowd lengthens an exchange, in
    /// thousandths: 1.5 (this project's, gap).
    public static let coefficient: Int64 = 1_500

    /// The crowd at the doors of a train rated for `rated` passengers with
    /// `riders` on board, at a station where `waiting` wait, in thousandths:
    /// the larger of the train's and the station's, at most ``limit``.
    public static func crowd(riders: Int64, rated: Int64, waiting: Int64) -> Int64 {
        let train = rated > 0 ? max(0, riders) * 1_000 / rated : 0
        let platform = max(0, waiting) * 1_000 / StationPassengers.capacity
        return min(max(train, platform), limit)
    }

    /// How many thousandths of its uncrowded time an exchange takes in
    /// `crowd` (thousandths of the rating): 1,000 for none,
    /// `1,000 + 1,500 × crowd⁴ ÷ 1,000³` otherwise, with the crowd at most
    /// ``limit``. Each power is rounded down to a thousandth, as
    /// ``PassengerCrowding`` does.
    public static func multiplier(crowd: Int64) -> Int64 {
        let x = min(max(0, crowd), limit)
        let square = x * x / 1_000
        let fourth = square * square / 1_000
        return 1_000 + coefficient * fourth / 1_000
    }

    /// The whole seconds `count` passengers take to get off, or on, at
    /// `rate` a second in `crowd` (thousandths of the rating), rounded up.
    /// With no crowd this is `count ÷ rate` rounded up, as it always was.
    ///
    /// - Precondition: `rate >= 1`.
    public static func exchangeSeconds(_ count: Int64, rate: Int64, crowd: Int64) -> Int64 {
        precondition(rate >= 1, "A train's doors pass someone a second")
        let count = max(0, count)
        let uncrowded = count / rate + (count % rate == 0 ? 0 : 1)
        guard crowd > 0 else { return uncrowded }
        // No count a train or a save can hold gets near this; if one did,
        // the exchange takes what it would uncrowded.
        let (scaled, overflow) = count.multipliedReportingOverflow(by: multiplier(crowd: crowd))
        guard !overflow else { return uncrowded }
        let per = rate * 1_000
        return scaled / per + (scaled % per == 0 ? 0 : 1)
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns door crowding on or off (decision 169): on, the passengers of a
    /// crowded train or station take longer to get off and on (see
    /// ``DoorCrowding``). An exchange already under way keeps the time it was
    /// given.
    public mutating func setDoorCrowding(_ enabled: Bool) {
        guard enabled != doorCrowding else { return }
        doorCrowding = enabled
    }

    // MARK: - Queries

    /// The crowd at the doors of train `id` at `station` now, in thousandths
    /// of what it is rated for (see ``DoorCrowding/crowd(riders:rated:waiting:)``).
    /// 0 while door crowding is off, for a freight line's train (its cargo is
    /// not passengers) and for an unknown train.
    public func doorCrowd(of id: TrainID, at station: StationID) -> Int64 {
        guard doorCrowding, let train = train(id: id) else { return 0 }
        if let line = assignedLine(of: id), self.line(id: line)?.isFreight ?? false { return 0 }
        let waiting = passengers.first { $0.station == station }?.waitingCount ?? 0
        return DoorCrowding.crowd(riders: riderCount(of: id), rated: train.ratedCapacity, waiting: waiting)
    }
}
