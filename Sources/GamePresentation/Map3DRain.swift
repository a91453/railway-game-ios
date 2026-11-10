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
            let seed = Self.seed(index)
            let travel = seed.speed * time
            let x = Self.wrapped(seed.x + travel * slant / width) * width
            let y = Self.wrapped(seed.y + travel / height) * height
            return MapWeather.Streak(x0: x, y0: y, x1: x + slant * seed.length, y1: y + seed.length)
        }
    }

    /// Streak `index`'s own start (shares of the screen across and down),
    /// length in points and pace in points a second.
    static func seed(_ index: Int) -> (x: Double, y: Double, length: Double, speed: Double) {
        let i = Int32(index)
        return (Double(map3DRandom(i, 0, salt: salt)), Double(map3DRandom(i, 1, salt: salt)),
                5 + 6 * Double(map3DRandom(i, 2, salt: salt)), speed * (0.85 + 0.3 * Double(map3DRandom(i, 3, salt: salt))))
    }

    // MARK: - PERF_3D_RAIN (2026-10-30): drawn by the 3D map's GPU

    /// The streaks as the 3D map's GPU draws them (`map3dRainVertex` in
    /// `Map3DShaders.metal`): four floats a streak, ``seed(_:)``'s start
    /// across, start down, length and pace, made once for a rain and a
    /// street detail (``Map3DRainDrawing``). Each frame the shader moves
    /// them by the clock alone (``uniforms(seconds:width:height:night:flash:count:)``),
    /// as ``streaks(at:width:height:detail:)`` does, so the main thread
    /// works out no streak a frame.
    public func seeds(_ detail: Map3DStreetDetail) -> [Float] {
        guard amount > 0 else { return [] }
        return (0..<streakCount(detail)).flatMap { index in
            let seed = Self.seed(index)
            return [Float(seed.x), Float(seed.y), Float(seed.length), Float(seed.speed)]
        }
    }

    /// The seconds the shader's streaks fall by: `seconds` (any clock)
    /// taken over ``clockPeriod``, so a `Float` keeps them to a hundredth
    /// of a point however long the map is open; the streaks jump once a
    /// period, to other places in the same rain.
    public static func shaderSeconds(_ seconds: Double) -> Float {
        let part = seconds - (seconds / clockPeriod).rounded(.down) * clockPeriod
        return Float(part)
    }

    /// See ``shaderSeconds(_:)``.
    public static let clockPeriod = 600.0

    /// What the shader reads each frame, 16 floats: the screen's width
    /// and height in points, ``shaderSeconds(_:)`` and the slant; the
    /// streaks' colour and opacity (``look(night:)``); the lightning's
    /// white and its opacity (``flashOpacity`` times `flash`, 0 for none);
    /// half the streaks' ``lineWidth`` and how many streaks there are
    /// (`count`, the seeds' over four). The same 16 however many streaks
    /// fall.
    public func uniforms(seconds: Double, width: Double, height: Double, night: Float, flash: Double, count: Int) -> [Float] {
        let look = look(night: night)
        func channel(_ colour: UInt32, _ shift: UInt32) -> Float { Float(colour >> shift & 0xFF) / 255 }
        return [Float(width), Float(height), Self.shaderSeconds(seconds), Float(slant),
                channel(look.colour, 16), channel(look.colour, 8), channel(look.colour, 0), Float(look.opacity),
                1, 1, 1, Float(Self.flashOpacity * min(max(flash, 0), 1)),
                Float(Self.lineWidth / 2), Float(count), 0, 0]
    }

    /// Whether the 3D map draws the streaks (and the lightning): when it
    /// rains, not with Reduce Motion (then only the light of decision 277
    /// shows the rain), and not with the cab deep in a tunnel (decision
    /// 394).
    public func drawsStreaks(reduceMotion: Bool, underground: Bool) -> Bool {
        amount > 0 && !reduceMotion && !underground
    }

    /// Streak `index` of `seeds` at `seconds` on a `width` by `height`
    /// screen, worked out in `Float` as the shader does
    /// (`map3dRainVertex`): for the tests, which hold it to
    /// ``streaks(at:width:height:detail:)``.
    static func shaderStreak(_ index: Int, of seeds: [Float], uniforms: [Float]) -> MapWeather.Streak {
        let x0 = seeds[index * 4], y0 = seeds[index * 4 + 1], length = seeds[index * 4 + 2], pace = seeds[index * 4 + 3]
        let width = uniforms[0], height = uniforms[1], seconds = uniforms[2], slant = uniforms[3]
        func fract(_ v: Float) -> Float { v - v.rounded(.down) }
        let travel = pace * seconds
        let x = fract(x0 + travel * slant / width) * width
        let y = fract(y0 + travel / height) * height
        return MapWeather.Streak(x0: Double(x), y0: Double(y), x1: Double(x + slant * length), y1: Double(y + length))
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

/// PERF_3D_RAIN (2026-10-30): the streaks' seeds the 3D map hands its GPU
/// (``Map3DRain/seeds(_:)``), made again only when the rain or the street
/// detail changes, never because the clock or the camera moved: until
/// then the map draws a frame's rain from the 16 floats of
/// ``Map3DRain/uniforms(seconds:width:height:night:flash:count:)``. Before,
/// a SwiftUI `Canvas` over the map worked out and stroked every streak on
/// the main thread up to 60 times a second, whatever the map drew.
public struct Map3DRainDrawing: Sendable {
    /// The seeds now, four floats a streak (empty: no rain).
    public private(set) var seeds: [Float] = []
    /// How many times the seeds were made.
    public private(set) var builds = 0
    /// How many streaks the seeds were made for: they are
    /// ``Map3DRain/seed(_:)``'s first so many, whatever the rain.
    private var made: Int?

    public init() {}

    /// How many streaks the seeds hold.
    public var count: Int { seeds.count / 4 }

    /// Makes the seeds for `rain` at `detail` if they are not those
    /// already; whether it made them (the map then hands them over again).
    public mutating func update(_ rain: Map3DRain, detail: Map3DStreetDetail) -> Bool {
        let count = rain.streakCount(detail)
        guard count != made else { return false }
        made = count
        seeds = rain.seeds(detail)
        builds += 1
        return true
    }
}
