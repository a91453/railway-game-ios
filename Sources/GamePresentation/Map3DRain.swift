import GameCore

/// Decision 277, next step: rain falling over the 3D map on a day of rain,
/// harder in a thunderstorm and a typhoon, with the 2D map's lightning
/// (``MapWeather/flash(at:)``). Ported from `Railway/town-scene-reference-clean/`'s
/// `source/weather.js`: a layer over the screen of fine parallel streaks
/// (`updateRain`), as many as the device's quality draws (`QUALITY.*.rain`),
/// falling at `RAIN_SPEED` points a second, each at its own pace, leaning
/// `RAIN_SLANT` sideways, 0.7 points wide, in `rgba(198, 215, 228, 0.24 ×
/// amount)`. Where the reference keeps each drop's place and pace from
/// `Math.random()` and moves it a frame at a time, here they come from
/// ``map3DRandom(_:_:salt:)`` and the time, so the same moment always draws
/// the same rain.
public struct Map3DRain: Hashable, Sendable {
    /// How hard it rains: 0 for none, 1 for the reference's rain.
    public let amount: Double
    /// Whether lightning flashes.
    public let flashes: Bool
    private let weather: MapWeather

    public init(_ weather: MapWeather) {
        self.weather = weather
        flashes = weather.flashes
        switch weather.sky {
        case .clear: amount = 0
        case .rain: amount = 1
        case .thunderstorm: amount = 1.3
        case .typhoon: amount = 1.6
        }
    }

    /// The reference's streaks at its three qualities, by how much street
    /// life the device draws (the same budget, ``Map3DStreetDetail``).
    public static func baseCount(for detail: Map3DStreetDetail) -> Int {
        switch detail {
        case .full: 480
        case .reduced: 260
        case .off: 140
        }
    }

    /// How many streaks fall: the base count times ``amount``.
    public func count(for detail: Map3DStreetDetail) -> Int {
        Int((Double(Self.baseCount(for: detail)) * amount).rounded())
    }

    /// The reference's `RAIN_SPEED`, points a second, and `RAIN_SLANT`,
    /// points sideways for each point down.
    public static let speed = 220.0
    public static let slant = 0.12
    /// The streaks' width in points and their colour, 0xRRGGBB.
    public static let lineWidth = 0.7
    public static let rgb = 0xC6D7E4

    /// The streaks' opacity: the reference's 0.24 times ``amount``.
    public var opacity: Double { 0.24 * amount }

    /// The streaks at `time` seconds on a screen `width` by `height` points
    /// with `detail`'s budget: each from a place of its own, 5 to 11 points
    /// long, falling at 0.85 to 1.15 times ``speed`` and drifting as it
    /// leans, coming back in at the top and the left as it leaves.
    public func streaks(at time: Double, width: Double, height: Double, detail: Map3DStreetDetail) -> [MapWeather.Streak] {
        guard amount > 0, width > 0, height > 0 else { return [] }
        return (0..<count(for: detail)).map { index in
            let drop = Int32(truncatingIfNeeded: index)
            func random(_ salt: Int32) -> Double { Double(map3DRandom(drop, 277, salt: salt)) }
            let length = 5 + random(2) * 6
            let travel = Self.speed * (0.85 + random(3) * 0.3) * time
            let x = Self.wrapped(random(0) + travel * Self.slant / width) * width
            let y = Self.wrapped(random(1) + travel / height) * height
            return MapWeather.Streak(x0: x, y0: y, x1: x + Self.slant * length, y1: y + length)
        }
    }

    /// How bright the lightning is at `time` seconds: the 2D map's.
    public func flash(at time: Double) -> Double {
        weather.flash(at: time)
    }

    private static func wrapped(_ value: Double) -> Double {
        let fraction = value - value.rounded(.down)
        return fraction < 1 ? fraction : 0
    }
}
