import Foundation
import GameCore

/// Decision 346: the sound of the weather the map shows (``MapWeather``,
/// decision 182 and 320's gap "雨聲、雷聲"): rain on a day of rain,
/// harder in a thunderstorm, the wind and rain of a typhoon, and thunder
/// after each flash of lightning. Loops and a clap the app plays, each
/// made to the spectrum of recordings of rain and thunder in Taiwan
/// (`tools/audio/README.md`). Worked out from the day's weather; never
/// part of the world, never saved.
public struct WeatherSound: Hashable, Sendable {
    /// Which loop plays.
    public enum Loop: String, CaseIterable, Hashable, Sendable {
        case rain
        case typhoon

        /// The loop's file in the app's `Resources/Audio/` (made by
        /// `tools/audio/make_game_audio.py`).
        public var resource: (name: String, extension: String) {
            switch self {
            case .rain: ("rain-steady", "caf")
            case .typhoon: ("rain-typhoon", "caf")
            }
        }
    }

    /// The loop that plays.
    public let loop: Loop
    /// The factor on the loop's own volume: the rain of a thunderstorm and
    /// a typhoon at full, a day of rain lighter.
    public let volume: Double
    /// Whether thunder follows the flashes (``MapWeather/flashes``).
    public let thunders: Bool

    /// How much lighter a day of rain is than a storm's, in decibels.
    static let lightRainDecibels = -6.0

    /// The sound of `weather`, `nil` under a clear sky.
    public init?(weather: MapWeather) {
        switch weather.sky {
        case .clear: return nil
        case .rain: self.init(loop: .rain, volume: pow(10, Self.lightRainDecibels / 20), thunders: false)
        case .thunderstorm: self.init(loop: .rain, volume: 1, thunders: true)
        case .typhoon: self.init(loop: .typhoon, volume: 1, thunders: true)
        }
    }

    init(loop: Loop, volume: Double, thunders: Bool) {
        self.loop = loop
        self.volume = volume
        self.thunders = thunders
    }

    /// The thunder's file in the app's `Resources/Audio/`.
    public static let thunderResource = (name: "thunder", extension: "caf")

    /// One clap of thunder: when it is heard, how loud and at what rate.
    public struct Thunder: Hashable, Sendable {
        /// When it is heard, in the seconds of ``MapWeather/flash(at:)``
        /// (the views' `timeIntervalSinceReferenceDate`).
        public let time: Double
        /// The factor on the clap's own volume, `1` for the nearest.
        public let volume: Double
        /// The rate it plays at: `1` for the nearest, lower and slower
        /// for a farther one.
        public let rate: Double
    }

    /// The nearest and farthest lightning, as the seconds its thunder
    /// takes to arrive (sound covers about a third of a kilometre a
    /// second: from about 300 m to 1.4 km).
    static let nearestDelay = 1.0
    static let farthestDelay = 4.0
    /// How much quieter and lower the farthest clap is than the nearest.
    static let farthestDecibels = -9.0
    static let farthestRate = 0.85

    /// The thunder of the flash in `cycle` (``MapWeather/flashStart(inCycle:)``):
    /// heard from 1 to 4 s after it, as far as the reference's noise puts
    /// that flash; the farther, the quieter (down to 9 dB) and the lower
    /// (down to a rate of 0.85, as distance takes the crack's highs).
    static func thunder(inCycle cycle: Int) -> Thunder {
        let far = MapWeather.noise(cycle % 10_000 + 71)
        let delay = nearestDelay + far * (farthestDelay - nearestDelay)
        return Thunder(
            time: MapWeather.flashStart(inCycle: cycle) + delay,
            volume: pow(10, far * farthestDecibels / 20),
            rate: 1 - far * (1 - farthestRate)
        )
    }

    /// The first clap of thunder heard after `time` (seconds, as
    /// ``MapWeather/flash(at:)`` takes them): the thunder of a flash that
    /// has already lit the map, or of one to come. A far flash's thunder
    /// can come after a nearer, later one's.
    public static func thunder(after time: Double) -> Thunder {
        // A cycle's thunder is heard from 1 s after it begins to 4 s
        // after its last second (12 s after it begins): from the first
        // cycle whose thunder can still come, up to the first that begins
        // too late to beat the earliest found.
        let period = MapWeather.flashPeriod
        var cycle = max(Int(((time - period - farthestDelay) / period).rounded(.down)), 0)
        var earliest: Thunder?
        while earliest.map({ Double(cycle) * period + nearestDelay < $0.time }) ?? true {
            let clap = thunder(inCycle: cycle)
            if clap.time > time, clap.time < earliest?.time ?? .infinity {
                earliest = clap
            }
            cycle += 1
        }
        return earliest!
    }
}
