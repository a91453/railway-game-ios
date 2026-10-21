import Foundation
import GameCore

/// ARCHITECTURE decision 320 (decision 277's next step): rain falling over
/// the native 3D map on a day of rain, harder in a thunderstorm with the
/// 2D map's lightning, hardest in a typhoon. Like
/// `Railway/town-scene-reference-clean/`'s (`source/weather.js`
/// `updateRain`), it is a curtain of fine parallel streaks over the
/// screen, so every streak stays parallel however the camera turns or
/// zooms: as many as the device draws street life for (`QUALITY.*.rain`),
/// falling at `RAIN_SPEED` and leaning `RAIN_SLANT`, each 5 to 11 points
/// long at 0.85 to 1.15 times the speed. At night they are the
/// reference's `rgba(198, 215, 228, 0.24 × amount)`; by day that pale
/// blue is lost on this map's pale ground (decisions 241 and 272), so they
/// are the 2D map's rain colour (`4A5A80`) at 0.35, the two mixed as the
/// light fades (``look(night:)``). Where each streak starts and how fast it falls is a position
/// hash (``map3DRandom``), not the reference's `Math.random()`, so the same
/// time always gives the same streaks. Only drawing; what day it rains is
/// GameCore's (``MapWeather``).
public struct Map3DRain: Hashable, Sendable {
    /// How hard it rains: 0 on a clear day, 1 under rain (the reference's
    /// one rain), more in a thunderstorm and a typhoon.
    public let amount: Double
    /// How far a streak leans sideways for each point it falls.
    public let slant: Double
    /// Whether lightning flashes (``MapWeather/flash(at:)``).
    public let flashes: Bool
    private let weather: MapWeather

    public init(_ weather: MapWeather) {
        self.weather = weather
        switch weather.sky {
        case .clear: amount = 0
        case .rain: amount = 1
        case .thunderstorm: amount = 1.25
        case .typhoon: amount = 1.5
        }
        // The typhoon's wind blows its rain across, as on the 2D map.
        slant = weather.sky == .typhoon ? 0.4 : Self.referenceSlant
        flashes = weather.flashes
    }

    /// No rain.
    public static let none = Map3DRain(.clear)

    /// `RAIN_SPEED`, in points a second.
    public static let speed = 220.0
    /// `RAIN_SLANT`.
    public static let referenceSlant = 0.12
    /// The streaks' line width, in points.
    public static let lineWidth = 0.7
    /// The streaks' colour and opacity at night (the reference's) and by
    /// day (the 2D map's rain, light on dark turned dark on light).
    public static let nightColour: UInt32 = 0xC6D7E4
    public static let nightOpacity = 0.24
    public static let dayColour: UInt32 = 0x4A5A80
    public static let dayOpacity = 0.35

    /// The streaks' colour (`0xRRGGBB`) and opacity when `night` of the
    /// day's light has gone (``Map3DLighting/night``, 0 by day, 1 at
    /// night): the day's and the night's mixed, the opacity times
    /// ``amount``.
    public func look(night: Float) -> (colour: UInt32, opacity: Double) {
        let t = Double(min(max(night, 0), 1))
        let colour = (0..<3).reduce(UInt32(0)) { colour, channel in
            let shift = UInt32(channel * 8)
            let day = Double(Self.dayColour >> shift & 0xFF), dark = Double(Self.nightColour >> shift & 0xFF)
            return colour | UInt32((day + (dark - day) * t).rounded()) << shift
        }
        return (colour, (Self.dayOpacity + (Self.nightOpacity - Self.dayOpacity) * t) * amount)
    }

    /// How many streaks fall: the reference's high, medium and low counts
    /// (480, 260, 140) for the street life the device draws, more in a
    /// thunderstorm and a typhoon (``amount``).
    public func streakCount(_ detail: Map3DStreetDetail) -> Int {
        let base: Double = switch detail {
        case .full: 480
        case .reduced: 260
        case .off: 140
        }
        return Int((base * amount).rounded())
    }

    /// The streaks at `time` seconds on a screen `width` by `height`
    /// points. Each starts at its own place, falls at its own steady pace
    /// and drifts sideways by ``slant`` as it falls, coming back in at the
    /// other edge (the reference's `% 1`).
    public func streaks(at time: Double, width: Double, height: Double, detail: Map3DStreetDetail) -> [MapWeather.Streak] {
        guard amount > 0, width > 0, height > 0 else { return [] }
        return (0..<streakCount(detail)).map { index in
            let i = Int32(index)
            let length = 5 + 6 * Double(map3DRandom(i, 2, salt: Self.salt))
            let travel = Self.speed * (0.85 + 0.3 * Double(map3DRandom(i, 3, salt: Self.salt))) * time
            let x = Self.wrapped(Double(map3DRandom(i, 0, salt: Self.salt)) + travel * slant / width) * width
            let y = Self.wrapped(Double(map3DRandom(i, 1, salt: Self.salt)) + travel / height) * height
            return MapWeather.Streak(x0: x, y0: y, x1: x + slant * length, y1: y + length)
        }
    }

    /// How bright the lightning is at `time` seconds, from 0 to 1: the 2D
    /// map's flashes (decision 182), 0 when it does not flash.
    public func flash(at time: Double) -> Double {
        flashes ? weather.flash(at: time) : 0
    }

    /// How much of the lightning's white lies over the screen at full
    /// flash, as on the 2D map.
    public static let flashOpacity = 0.35

    private static let salt: Int32 = 320

    private static func wrapped(_ share: Double) -> Double {
        let part = share - share.rounded(.down)
        return part < 0 ? part + 1 : part
    }
}
