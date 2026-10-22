import Foundation
import GameCore

// Today's weather on the map (ARCHITECTURE decision 182): rain falling over
// the map on a day of rain, harder with lightning on a day of
// thunderstorms, the map darkened and the stations it blows over marked
// while a typhoon blows. Read from GameCore's own weather and typhoons
// (decision 162); only drawing.
//
// The reference has no weather on its maps (decision 162's gap), so the
// drawing is this project's own. The streaks' scatter uses the `Railway/`
// reference's noise (`rail-3d/integration/train-halo-style.js`
// `variation`: the fraction of `sin((n + 1) × 12.9898 + 7.2) × 43758.5453`),
// which it uses to vary its trains' halos without a random generator.

/// The weather the map shows today (decision 182).
public struct MapWeather: Hashable, Sendable {
    /// What the sky does.
    public enum Sky: Hashable, Sendable {
        case clear
        case rain
        case thunderstorm
        /// A typhoon blows over the map, whatever the day's weather.
        case typhoon
    }

    public let sky: Sky
    /// The stations a typhoon blows over today.
    public let typhoonStations: Set<StationID>

    public init(sky: Sky, typhoonStations: Set<StationID> = []) {
        self.sky = sky
        self.typhoonStations = typhoonStations
    }

    /// Clear, with no typhoon: what a world without weather shows.
    public static let clear = MapWeather(sky: .clear)

    /// Today's weather of `world`: a typhoon blowing today first, else the
    /// day's weather; clear for a world without weather.
    public init(world: GameWorld) {
        guard world.disruptions != nil else {
            self = .clear
            return
        }
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        let blowing = world.typhoons(onDay: today).filter { $0.isActive(onDay: today) }
        if !blowing.isEmpty {
            let stations = world.stations.filter { station in blowing.contains { $0.covers(station.point) } }
            self.init(sky: .typhoon, typhoonStations: Set(stations.map(\.id)))
            return
        }
        switch world.weather(onDay: today) {
        case .clear: self = .clear
        case .rain: self.init(sky: .rain)
        case .thunderstorm: self.init(sky: .thunderstorm)
        }
    }

    /// How many streaks of rain fall across the screen: a fixed number for
    /// the weather, whatever the size of the map or the zoom, so that a
    /// whole-Taiwan map draws no more than a town's.
    public var streakCount: Int {
        switch sky {
        case .clear: 0
        case .rain: 90
        case .thunderstorm: 140
        case .typhoon: 200
        }
    }

    /// How dark the map is laid over, from 0 to 1: a little under rain, more
    /// in a storm, most in a typhoon. With `reduceMotion` the rain does not
    /// fall and nothing flashes; the map is darkened a little more instead,
    /// so the weather still shows.
    public func dimming(reduceMotion: Bool) -> Double {
        switch sky {
        case .clear: 0
        case .rain: reduceMotion ? 0.12 : 0.06
        case .thunderstorm: reduceMotion ? 0.18 : 0.10
        case .typhoon: reduceMotion ? 0.30 : 0.22
        }
    }

    /// How far a streak leans sideways for each point it falls: the
    /// typhoon's wind blows the rain across.
    public var slant: Double {
        switch sky {
        case .typhoon: 0.55
        default: 0.15
        }
    }

    /// How fast the rain falls, in points a second.
    public var fallSpeed: Double {
        switch sky {
        case .typhoon: 1_100
        case .thunderstorm: 900
        default: 700
        }
    }

    /// How long a streak is, in points.
    public var streakLength: Double {
        switch sky {
        case .typhoon: 26
        case .thunderstorm: 20
        default: 16
        }
    }

    /// Whether lightning flashes.
    public var flashes: Bool {
        sky == .thunderstorm || sky == .typhoon
    }

    /// One streak of rain on the screen, from its top to its bottom, in
    /// points.
    public struct Streak: Hashable, Sendable {
        public let x0: Double
        public let y0: Double
        public let x1: Double
        public let y1: Double
    }

    /// The streaks at `time` seconds on a screen `width` by `height`
    /// points: ``streakCount`` of them, each falling at its own steady pace
    /// (from 0.8 to 1.2 times ``fallSpeed``) from a place of its own, and
    /// coming back in at the top once it has left at the bottom. The same
    /// time always gives the same streaks.
    public func streaks(at time: Double, width: Double, height: Double) -> [Streak] {
        let count = streakCount
        guard count > 0, width > 0, height > 0 else { return [] }
        let length = streakLength, lean = slant
        // The streaks fall through the screen and a streak's length above
        // it; leaning, they start as far left of it as they drift.
        let fall = height + length
        let drift = lean * fall
        let across = width + drift
        return (0..<count).map { index in
            let place = Self.noise(index), phase = Self.noise(index + 17), pace = 0.8 + 0.4 * Self.noise(index + 31)
            let travelled = (phase * fall + time * fallSpeed * pace).truncatingRemainder(dividingBy: fall)
            let bottom = (travelled < 0 ? travelled + fall : travelled)
            let top = bottom - length
            let x = place * across - drift + lean * bottom
            return Streak(x0: x - lean * length, y0: top, x1: x, y1: bottom)
        }
    }

    /// How bright the lightning is at `time` seconds, from 0 to 1: one
    /// flash in every ``flashPeriod`` seconds, at its own moment in each,
    /// that flickers twice in about a third of a second. 0 when the weather
    /// has no lightning. Rare and short, so it never strobes.
    public func flash(at time: Double) -> Double {
        guard flashes, time >= 0 else { return 0 }
        let cycle = (time / Self.flashPeriod).rounded(.down)
        let t = time - Self.flashStart(inCycle: Int(cycle))
        switch t {
        case ..<0: return 0
        case ..<0.08: return 1
        case ..<0.16: return 0.2
        case ..<0.34: return 0.7 * (1 - (t - 0.16) / 0.18)
        default: return 0
        }
    }

    /// The seconds between two flashes of lightning.
    public static let flashPeriod = 9.0

    /// When the flash of `cycle` (the ``flashPeriod`` that starts at
    /// `cycle` × the period) begins, in the same seconds as
    /// ``flash(at:)``: at its own moment, at least a second before the
    /// next cycle.
    static func flashStart(inCycle cycle: Int) -> Double {
        Double(cycle) * flashPeriod + noise(cycle % 10_000 + 53) * (flashPeriod - 1)
    }

    /// The reference's noise: a number from 0 up to 1 that looks random but
    /// is always the same for `n`.
    static func noise(_ n: Int) -> Double {
        let x = sin((Double(n) + 1) * 12.9898 + 7.2) * 43_758.5453
        return x - x.rounded(.down)
    }
}
