// A service's run from one call to the next (Phase 4.7 Stage W2c,
// ARCHITECTURE decision 40): the train no longer goes at a steady rate
// between calls, it follows the running curve its performance builds
// (Stage W1, ``RunningCurve``): accelerating, cruising, coasting when its
// performance coasts, and braking to a stand at the call.
//
// As in the Railway reference (`assignRunProfiles`, `profTimeToProg`), the
// run takes the time the timetable gives it, from the scheduled departure
// to the scheduled arrival, so a train on time arrives on time and one
// that left late arrives as late. Where the reference has nothing (it only
// samples a timetable), the rules are this project's: a train whose
// performance cannot keep that time runs as fast as it can, and one that
// was held up on the way sets off again from a stand.

/// The run of a service's train from the call it left to the next (Stage
/// W2c): it set off at ``start`` and follows the running curve its
/// performance builds for ``length`` world units in ``seconds`` (see
/// ``RunningCurve/init(length:duration:performance:)``). At every second it
/// may have come `curve.distance(at:)` that far along, and it stops at the
/// end of its path, at the call, ``seconds`` after it set off. Saved with
/// the service's times (``ServiceTimes/run``) while the train travels.
public struct ServiceRun: Hashable, Sendable {
    /// When the train set off.
    public let start: GameTime
    /// World units from where it set off to where it stops for the call:
    /// what was left of its path then. At least 1.
    public let length: Int64
    /// Whole seconds the run takes: 1 to ``RunningCurve/maximumSeconds``.
    public let seconds: Int64

    public init(start: GameTime, length: Int64, seconds: Int64) {
        self.start = start
        self.length = length
        self.seconds = seconds
    }

    /// When the run is over: the train has covered ``length`` then, unless
    /// something held it up on the way.
    public var end: GameTime {
        GameWorld.saturating(start, plus: seconds)
    }

    /// The curve `performance` builds for the run, or `nil` if it builds
    /// none (a saved run always has one; see ``Train``'s decoder).
    public func curve(for performance: TrainPerformance) -> RunningCurve? {
        RunningCurve(length: length, duration: seconds * 1000, performance: performance)
    }

    /// The world units `curve`, this run's, takes the train from `from` to
    /// `to` (seconds of the game's clock, `from <= to`): how far it has come
    /// by `to` less how far by `from`. Nothing before ``start`` or after
    /// ``end``.
    func distance(on curve: RunningCurve, from: GameTime, to: GameTime) -> Int64 {
        covered(on: curve, by: to) - covered(on: curve, by: from)
    }

    /// How far along the run `curve` has taken the train by `time`.
    private func covered(on curve: RunningCurve, by time: GameTime) -> Int64 {
        guard time > start else { return 0 }
        let (elapsed, overflow) = time.seconds.subtractingReportingOverflow(start.seconds)
        return overflow || elapsed >= seconds ? length : curve.distance(at: elapsed * 1000)
    }
}

extension ServiceRun: Codable {
    private enum CodingKeys: String, CodingKey {
        case start, length, seconds
    }

    /// Decodes `{"start": second, "length", "seconds"}`, rejecting a length
    /// below 1 or seconds outside `1...RunningCurve.maximumSeconds`. That the
    /// train's performance builds a curve for it, and that it fits the
    /// service and the clock, is checked by ``Train``'s and ``GameWorld``'s
    /// decoders.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(GameTime.self, forKey: .start)
        length = try container.decode(Int64.self, forKey: .length)
        seconds = try container.decode(Int64.self, forKey: .seconds)
        guard length >= 1 else {
            throw DecodingError.dataCorruptedError(forKey: .length, in: container, debugDescription: "A run's length must be at least 1.")
        }
        guard (1...RunningCurve.maximumSeconds).contains(seconds) else {
            throw DecodingError.dataCorruptedError(
                forKey: .seconds, in: container, debugDescription: "A run takes 1 to \(RunningCurve.maximumSeconds) seconds."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(length, forKey: .length)
        try container.encode(seconds, forKey: .seconds)
    }
}
