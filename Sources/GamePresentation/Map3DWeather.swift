import Foundation
import GameCore

/// ARCHITECTURE decision 277: how the day's weather changes the native 3D
/// map's light. The values are `Railway/town-scene-reference-clean/`'s
/// (`source/weather.js` `PRESETS`, `applyLighting`): under rain the sun is
/// weaker by day, the light and the sky greyer and bluer, the fog nearer
/// and greyer. What day it rains is GameCore's own weather
/// (``MapWeather``, decision 162), not the reference's dice; the
/// reference's cloudy and snowy days are not GameCore weathers.
public struct Map3DWeather: Hashable, Sendable {
    /// The sun's strength by day and at night, as a share.
    public var daySunScale: Float
    public var nightSunScale: Float
    /// The sky's and the ground's ambient light by day and at night.
    public var dayHemiScale: Float
    public var nightHemiScale: Float
    /// What the sky behind the map (and a little the sun) turns toward.
    public var skyTint: UInt32
    public var skyMix: Float
    /// What the ambient light from the sky turns toward.
    public var hemiTint: UInt32
    public var hemiMix: Float
    /// What the ambient light from the ground turns toward.
    public var groundTint: UInt32
    public var groundMix: Float
    /// The fog's colour, and where it starts and ends, as shares.
    public var fogTint: UInt32
    public var fogMix: Float
    public var fogNear: Float
    public var fogFar: Float

    /// A clear day: the light as it is (`PRESETS.sunny`).
    public static let clear = Map3DWeather(daySunScale: 1, nightSunScale: 1, dayHemiScale: 1, nightHemiScale: 1,
                                           skyTint: 0xFFFFFF, skyMix: 0, hemiTint: 0xFFFFFF, hemiMix: 0,
                                           groundTint: 0xFFFFFF, groundMix: 0, fogTint: 0xFFFFFF, fogMix: 0,
                                           fogNear: 1, fogFar: 1)

    /// A day of rain (`PRESETS.rain`).
    public static let rain = Map3DWeather(daySunScale: 0.56, nightSunScale: 0.94, dayHemiScale: 0.92, nightHemiScale: 1,
                                          skyTint: 0x66778A, skyMix: 0.24, hemiTint: 0x8392A3, hemiMix: 0.1,
                                          groundTint: 0x68737F, groundMix: 0.12, fogTint: 0x586777, fogMix: 0.24,
                                          fogNear: 0.84, fogFar: 0.76)

    /// The light of the day's weather on the map: rain for rain, a
    /// thunderstorm and a typhoon (their lightning and heavier rain are the
    /// rain streaks' to show, decision 277's next step).
    public init(_ weather: MapWeather) {
        switch weather.sky {
        case .clear: self = .clear
        case .rain, .thunderstorm, .typhoon: self = .rain
        }
    }

    init(daySunScale: Float, nightSunScale: Float, dayHemiScale: Float, nightHemiScale: Float,
         skyTint: UInt32, skyMix: Float, hemiTint: UInt32, hemiMix: Float,
         groundTint: UInt32, groundMix: Float, fogTint: UInt32, fogMix: Float, fogNear: Float, fogFar: Float) {
        self.daySunScale = daySunScale
        self.nightSunScale = nightSunScale
        self.dayHemiScale = dayHemiScale
        self.nightHemiScale = nightHemiScale
        self.skyTint = skyTint
        self.skyMix = skyMix
        self.hemiTint = hemiTint
        self.hemiMix = hemiMix
        self.groundTint = groundTint
        self.groundMix = groundMix
        self.fogTint = fogTint
        self.fogMix = fogMix
        self.fogNear = fogNear
        self.fogFar = fogFar
    }

    /// How long one weather takes to turn into the next on screen, in
    /// seconds (`TRANSITION_SECONDS`).
    public static let changeSeconds: Double = 2

    /// `share` of the way from this weather to `other` (`blendProfile`):
    /// each number and each colour's channels in a straight line.
    public func blended(to other: Map3DWeather, share: Float) -> Map3DWeather {
        let t = min(max(share, 0), 1)
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
        func mix(_ a: UInt32, _ b: UInt32) -> UInt32 {
            (0..<3).reduce(UInt32(0)) { colour, channel in
                let shift = UInt32(channel * 8)
                let p = Float((a >> shift) & 0xFF), q = Float((b >> shift) & 0xFF)
                return colour | UInt32((p + (q - p) * t).rounded()) << shift
            }
        }
        return Map3DWeather(daySunScale: mix(daySunScale, other.daySunScale), nightSunScale: mix(nightSunScale, other.nightSunScale),
                            dayHemiScale: mix(dayHemiScale, other.dayHemiScale), nightHemiScale: mix(nightHemiScale, other.nightHemiScale),
                            skyTint: mix(skyTint, other.skyTint), skyMix: mix(skyMix, other.skyMix),
                            hemiTint: mix(hemiTint, other.hemiTint), hemiMix: mix(hemiMix, other.hemiMix),
                            groundTint: mix(groundTint, other.groundTint), groundMix: mix(groundMix, other.groundMix),
                            fogTint: mix(fogTint, other.fogTint), fogMix: mix(fogMix, other.fogMix),
                            fogNear: mix(fogNear, other.fogNear), fogFar: mix(fogFar, other.fogFar))
    }

    /// One weather turning into the next over ``changeSeconds``: what the
    /// 3D map shows `seconds` (any clock) after the change began.
    public struct Change: Hashable, Sendable {
        public let from: Map3DWeather
        public let to: Map3DWeather
        public let began: Double

        public init(from: Map3DWeather, to: Map3DWeather, began: Double) {
            self.from = from
            self.to = to
            self.began = began
        }

        public func weather(at seconds: Double) -> Map3DWeather {
            from.blended(to: to, share: Float((seconds - began) / Map3DWeather.changeSeconds))
        }
    }
}
