@testable import GamePresentation
import XCTest

/// Decision 277: the 3D map's light under the day's weather, with
/// `Railway/town-scene-reference-clean/`'s `PRESETS.rain` and `applyLighting`.
final class Map3DWeatherTests: XCTestCase {
    func luminance(_ light: SIMD3<Float>) -> Float { 0.2126 * light.x + 0.7152 * light.y + 0.0722 * light.z }
    func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { ((a - b) * (a - b)).sum().squareRoot() }

    func testAClearDayIsLitAsBefore() {
        for minute in stride(from: 0.0, to: 1_440, by: 90) {
            let light = Map3DLighting(minute: minute)
            XCTAssertEqual(light.weather, .clear)
            let sky = Map3DLighting.rgb(light.sky)
            XCTAssertEqual(light.background, sky, "the sky behind the map is the hour's")
            XCTAssertEqual(light.fogColour, sky, "and so is the fog")
            XCTAssertEqual(light.fogScale.near, 1)
            XCTAssertEqual(light.fogScale.far, 1)
            XCTAssertEqual(light.sunLight, Map3DLighting.rgb(light.sun) * (light.sunStrength * 0.16 * light.dayBoost))
        }
    }

    func testTheRainsNumbersAreTheReferences() {
        let rain = Map3DWeather.rain
        XCTAssertEqual([rain.daySunScale, rain.nightSunScale, rain.dayHemiScale, rain.nightHemiScale], [0.56, 0.94, 0.92, 1])
        XCTAssertEqual([rain.skyTint, rain.hemiTint, rain.groundTint, rain.fogTint], [0x66778A, 0x8392A3, 0x68737F, 0x586777])
        XCTAssertEqual([rain.skyMix, rain.hemiMix, rain.groundMix, rain.fogMix, rain.fogNear, rain.fogFar], [0.24, 0.1, 0.12, 0.24, 0.84, 0.76])
    }

    func testRainDimsTheNoonAndGreysTheSkyAndBringsTheFogNearer() {
        let clear = Map3DLighting(minute: 12 * 60)
        var rain = clear
        rain.weather = .rain
        XCTAssertEqual(luminance(rain.sunLight) / luminance(clear.sunLight), 0.56, accuracy: 0.03, "the sun a little over half")
        XCTAssertEqual(luminance(rain.skyLight) / luminance(clear.skyLight), 0.92, accuracy: 0.03)
        XCTAssertEqual(luminance(rain.groundLight) / luminance(clear.groundLight), 0.92, accuracy: 0.04)
        let tint = Map3DLighting.rgb(Map3DWeather.rain.skyTint)
        XCTAssertLessThan(distance(rain.background, tint), distance(clear.background, tint), "the sky greyer, toward the rain's")
        XCTAssertLessThan(luminance(rain.fogColour), luminance(clear.fogColour))
        XCTAssertEqual(rain.fogScale.near, 0.84, accuracy: 1e-5)
        XCTAssertEqual(rain.fogScale.far, 0.76, accuracy: 1e-5)
    }

    func testAtNightTheRainShowsLess() {
        let clear = Map3DLighting(minute: 0)
        var rain = clear
        rain.weather = .rain
        XCTAssertEqual(luminance(rain.sunLight) / luminance(clear.sunLight), 0.94, accuracy: 0.02, "the moon nearly as it was")
        XCTAssertEqual(luminance(rain.skyLight), luminance(clear.skyLight), accuracy: 0.01)
        XCTAssertEqual(rain.fogScale.near, 1 - 0.16 * 0.45, accuracy: 1e-5, "under half the day's change")
        XCTAssertEqual(rain.fogScale.far, 1 - 0.24 * 0.45, accuracy: 1e-5)
    }

    func testRainThunderAndTyphoonDarkenTheMapAlike() {
        XCTAssertEqual(Map3DWeather(.clear), .clear)
        for sky: MapWeather.Sky in [.rain, .thunderstorm, .typhoon] {
            XCTAssertEqual(Map3DWeather(MapWeather(sky: sky)), .rain, "\(sky)")
        }
    }

    func testANewWeatherTurnsOverTwoSeconds() {
        let change = Map3DWeather.Change(from: .clear, to: .rain, began: 100)
        XCTAssertEqual(change.weather(at: 99), .clear)
        XCTAssertEqual(change.weather(at: 100), .clear)
        let half = change.weather(at: 101)
        XCTAssertEqual(half.daySunScale, 0.78, accuracy: 1e-5)
        XCTAssertEqual(half.fogFar, 0.88, accuracy: 1e-5)
        XCTAssertEqual(half.skyTint, 0xB3BBC5, "each channel halfway, rounded")
        XCTAssertEqual(change.weather(at: 102), .rain)
        XCTAssertEqual(change.weather(at: 500), .rain)
    }
}
