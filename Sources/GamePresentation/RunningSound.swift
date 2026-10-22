import Foundation
import GameCore

/// Decision 343: the sound of the followed train running (decision 219's
/// next item, the research note `JAPAN_RAIL_DATA_2026-10-21.md` §7.3). A
/// loop the app plays while the player follows a train at 60× or slower,
/// louder and higher the faster it runs: a high-speed train's or an
/// ordinary train's with its rail joints, each made to the spectrum of
/// recordings of real trains (`tools/audio/README.md`). Worked out after
/// each step; never part of the world, never saved.
public struct RunningSound: Hashable, Sendable {
    /// Which loop plays.
    public enum Loop: String, CaseIterable, Hashable, Sendable {
        case electric
        case highSpeed

        /// The loop's file in the app's `Resources/Audio/` (made by
        /// `tools/audio/make_game_audio.py`).
        public var resource: (name: String, extension: String) {
            switch self {
            case .electric: ("run-electric", "caf")
            case .highSpeed: ("run-highspeed", "caf")
            }
        }

        /// The speed at which the loop plays at full volume and its
        /// highest rate, in km/h: about the top speed of the trains it
        /// stands for.
        var fullSpeedKMH: Double {
            switch self {
            case .electric: 120
            case .highSpeed: 300
            }
        }
    }

    /// The loop that plays.
    public let loop: Loop
    /// The factor on the loop's own volume, `1` at full speed.
    public let volume: Double
    /// The rate the loop plays at, `1` as made: slower and lower at low
    /// speed, faster and higher at full speed.
    public let rate: Double

    /// Below this the train is about to stand: nothing plays.
    static let quietBelowKMH = 5.0
    /// How far down the loop is just above ``quietBelowKMH``, in decibels.
    static let quietestDecibels = -12.0
    /// The steps the volume moves in, in decibels: the app is told only
    /// when the sound moves a step, and fades between them.
    static let volumeStepDecibels = 1.0
    /// The rate's range, and the steps it moves in.
    static let slowestRate = 0.8
    static let fastestRate = 1.2
    static let rateStep = 0.02

    /// The sound `loop` makes at `kmh`, or `nil` below 5 km/h. The share
    /// of the loop's full speed sets both: the volume rises evenly in
    /// decibels from 12 dB down to full, in 1 dB steps; the rate from 0.8
    /// to 1.2, in steps of 0.02.
    public static func of(_ loop: Loop, atKMH kmh: Double) -> RunningSound? {
        guard kmh >= quietBelowKMH else { return nil }
        let share = min(kmh / loop.fullSpeedKMH, 1)
        let decibels = ((1 - share) * quietestDecibels / volumeStepDecibels).rounded() * volumeStepDecibels
        let steps = (share * (fastestRate - slowestRate) / rateStep).rounded()
        return RunningSound(
            loop: loop,
            volume: decibels == 0 ? 1 : pow(10, decibels / 20),
            rate: slowestRate + steps * rateStep
        )
    }

    /// The sound while `train` is followed in `world`: `nil` unless the
    /// game runs (not paused) at 60× or slower, where the player can hear
    /// one train, and the train moves at 5 km/h or more. A train that
    /// runs as a high-speed train (``TrainPerformance/isHighSpeed``) plays
    /// the high-speed loop; any other the electric one.
    static func of(following train: Train?, in world: GameWorld) -> RunningSound? {
        guard let train, !world.clock.isPaused,
              world.clock.speed.tenthsPerTick <= GameSpeed.x60.tenthsPerTick
        else { return nil }
        return of(train.performance.isHighSpeed ? .highSpeed : .electric, atKMH: world.trainSpeedKMH(of: train.id))
    }
}
