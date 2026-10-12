import GameCore

// The map's time of day (ARCHITECTURE decision 182): a tint laid over the
// ground by the game clock's minute, warm at dawn, warm turning blue at
// dusk and deep blue at night, and how strongly the night's lights (the
// stations', the trains' and the town's windows) shine. Only drawing: the
// clock is GameCore's, nothing here is saved or read back.
//
// The `Railway/` reference's 3D view (`rail-3d/integration/train-lighting.js`
// `nightAmount`, `train-halo-style.js` `haloNight`) turns the sun's
// elevation into a night amount with a smoothstep from 6° below the horizon
// to 8° above it; the 2D map has no sun, so the same smoothstep runs over
// the clock's minutes instead (``lights(atMinute:)``). The tint's colours and
// strengths are this project's own (the reference lights a 3D scene; it has
// no 2D tint).

/// The map's tint and lights at a minute of the day (decision 182).
public enum DayNight {
    /// A colour of the tint, as red, green and blue from 0 to 1.
    public struct Colour: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(hex: UInt32) {
            self.init(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255
            )
        }

        func mixed(with other: Colour, _ share: Double) -> Colour {
            Colour(
                red: red + (other.red - red) * share,
                green: green + (other.green - green) * share,
                blue: blue + (other.blue - blue) * share
            )
        }
    }

    /// What is laid over the map: ``colour`` at ``strength`` (its opacity,
    /// 0 for none), and how strongly the lights shine (``lights``, 0 by
    /// day, 1 at night).
    public struct Tint: Hashable, Sendable {
        public let colour: Colour
        public let strength: Double
        public let lights: Double

        /// No tint and no lights: the map as it was before decision 182,
        /// and the map with the day and night turned off.
        public static let day = Tint(colour: DayNight.dawn, strength: 0, lights: 0)

        /// Whether anything is laid over the map or lit.
        public var isVisible: Bool { strength > 0 || lights > 0 }
    }

    /// Dawn's warm orange.
    public static let dawn = Colour(hex: 0xFF9F55)
    /// Dusk's orange, before it turns to the night's blue.
    public static let dusk = Colour(hex: 0xF07A3C)
    /// The night's deep blue.
    public static let night = Colour(hex: 0x0E1640)

    /// The tint's turning points through the day, by minute: the night's
    /// blue at 25% until 05:00, dawn's orange at 15% by 05:30 fading out by
    /// 06:30, nothing through the day, dusk's orange rising to 25% from
    /// 17:30 to 18:15 and turning to the night's blue by 19:00. Between two
    /// points the colour and the strength run straight from one to the
    /// other. The map multiplies by it; 25% is the most that keeps the
    /// light map's track 3:1 on its ground and its names 4.5:1
    /// (`docs/UI_THEME.md`).
    static let keys: [(minute: Int, colour: Colour, strength: Double)] = [
        (0, night, 0.25),
        (300, night, 0.25),
        (330, dawn, 0.15),
        (390, dawn, 0),
        (1050, dusk, 0),
        (1095, dusk, 0.25),
        (1140, night, 0.25),
        (1440, night, 0.25),
    ]

    /// When the lights go out in the morning (from 05:00 to 06:15) and come
    /// on in the evening (from 17:30 to 18:45), in minutes of the day.
    static let lightsOut = (start: 300, end: 375)
    static let lightsOn = (start: 1050, end: 1125)

    /// The tint at minute of the day `minute` (wrapped into `0..<1440`).
    public static func tint(atMinute minute: Double) -> Tint {
        let m = wrapped(minute)
        var index = 1
        while index < keys.count - 1, keys[index].minute <= Int(m) { index += 1 }
        let from = keys[index - 1], to = keys[index]
        let share = to.minute == from.minute ? 0 : (m - Double(from.minute)) / Double(to.minute - from.minute)
        let clamped = min(max(share, 0), 1)
        return Tint(
            colour: from.colour.mixed(with: to.colour, clamped),
            strength: from.strength + (to.strength - from.strength) * clamped,
            lights: lights(atMinute: m)
        )
    }

    /// The tint at game time `time`, to the second.
    public static func tint(at time: GameTime) -> Tint {
        let seconds = time.seconds % GameTime.secondsPerDay
        return tint(atMinute: Double(seconds < 0 ? seconds + GameTime.secondsPerDay : seconds) / 60)
    }

    /// How strongly the lights shine at minute `minute`: 1 through the
    /// night, 0 through the day, and between, the reference's smoothstep
    /// (`3t² − 2t³`) as the lights go out in the morning and come on in
    /// the evening.
    public static func lights(atMinute minute: Double) -> Double {
        let m = wrapped(minute)
        if m < Double(lightsOut.start) || m >= Double(lightsOn.end) { return 1 }
        if m < Double(lightsOut.end) { return 1 - smoothstep(m, from: Double(lightsOut.start), to: Double(lightsOut.end)) }
        if m < Double(lightsOn.start) { return 0 }
        return smoothstep(m, from: Double(lightsOn.start), to: Double(lightsOn.end))
    }

    /// `value` rounded down to a twentieth (the reference's `haloSprite`
    /// buckets its night amount the same way), so that what is drawn by
    /// it is redrawn twenty times as the lights come on, not on every tick.
    public static func step(_ value: Double) -> Double {
        (min(max(value, 0), 1) * 20).rounded(.down) / 20
    }

    private static func smoothstep(_ value: Double, from low: Double, to high: Double) -> Double {
        let t = min(max((value - low) / (high - low), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func wrapped(_ minute: Double) -> Double {
        let m = minute.truncatingRemainder(dividingBy: 1440)
        return m < 0 ? m + 1440 : m
    }
}
