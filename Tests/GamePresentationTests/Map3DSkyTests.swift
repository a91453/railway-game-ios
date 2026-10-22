import XCTest
@testable import GamePresentation

/// Decision 347: the sky drawn behind the native 3D map.
final class Map3DSkyTests: XCTestCase {
    private func lighting(_ hour: Double, _ weather: Map3DWeather = .clear) -> Map3DLighting {
        var lighting = Map3DLighting(minute: hour * 60)
        lighting.weather = weather
        return lighting
    }

    private func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ within: Float = 0.002) -> Bool {
        abs(a.x - b.x) <= within && abs(a.y - b.y) <= within && abs(a.z - b.z) <= within
    }

    func testTheHorizonIsTheFogsColourAndStraightUpTheZenith() {
        for hour in [3.0, 9, 12, 18.5, 22] {
            let lit = lighting(hour), sky = Map3DSky(lit)
            XCTAssertEqual(sky.horizon, lit.fogColour)
            // Away from the sun and the moon, low on the horizon and below
            // it the sky is the fog's colour, so the far ground fades into it.
            let light = sky.sunShown > 0 ? sky.sun : sky.moon
            let away = Map3DPoint(-light.x, 0, -light.z + 0.01)
            XCTAssertTrue(close(sky.colour(toward: away), lit.fogColour), "hour \(hour)")
            XCTAssertTrue(close(sky.colour(toward: Map3DPoint(0, -1, 0.3)), lit.fogColour), "hour \(hour)")
            if sky.stars == 0 && sky.sun.y < 0.5 {
                XCTAssertTrue(close(sky.colour(toward: .up), sky.zenith, 0.01), "hour \(hour)")
            }
        }
    }

    func testTheZenithIsBrightBlueAtNoonAndDarkAtMidnight() {
        let noon = Map3DSky(lighting(12)).zenith, midnight = Map3DSky(lighting(0)).zenith
        XCTAssertGreaterThan(noon.z, noon.x, "blue by day")
        XCTAssertGreaterThan(noon.sum(), midnight.sum() * 3)
    }

    func testTheSunShowsByDayAndTheMoonAndStarsOnAClearNight() {
        let noon = Map3DSky(lighting(12))
        XCTAssertEqual(noon.sunShown, 1)
        XCTAssertEqual(noon.moonShown, 0)
        XCTAssertEqual(noon.stars, 0)
        XCTAssertGreaterThan(noon.sun.y, 0.8)
        // Its disc is near white, brighter than the sky beside it.
        XCTAssertGreaterThan(noon.colour(toward: noon.sun).sum(), 2.8)

        let midnight = Map3DSky(lighting(0))
        XCTAssertEqual(midnight.sunShown, 0)
        XCTAssertGreaterThan(midnight.moonShown, 0.9)
        XCTAssertGreaterThan(midnight.moon.y, 0.8, "high at midnight")
        XCTAssertGreaterThan(midnight.stars, 0.9)
        XCTAssertGreaterThan(midnight.colour(toward: midnight.moon).sum(), 2.5)

        // The moon is up in the east in the evening and low in the west
        // before dawn.
        let evening = Map3DSky(lighting(20)), dawn = Map3DSky(lighting(5))
        XCTAssertGreaterThan(evening.moon.x, 0)
        XCTAssertLessThan(dawn.moon.x, 0)
    }

    func testRainHidesTheSunTheMoonAndTheStars() {
        let rainyNoon = Map3DSky(lighting(12, .rain)), rainyNight = Map3DSky(lighting(0, .rain))
        XCTAssertEqual(rainyNoon.sunShown, 0)
        XCTAssertEqual(rainyNight.moonShown, 0)
        XCTAssertEqual(rainyNight.stars, 0)
        XCTAssertLessThan(rainyNoon.colour(toward: rainyNoon.sun).sum(), 2.5)
        // The rain's grey reaches the zenith.
        XCTAssertNotEqual(rainyNoon.zenith, Map3DSky(lighting(12)).zenith)
    }

    func testStarsAreScatteredAndNoneLowDown() {
        var high = 0, low = 0, total = 0
        for i in 0..<200 {
            for j in 0..<200 {
                let x = Float(i) / 100 - 1, z = Float(j) / 100 - 1
                total += 1
                high += Map3DSky.star(Map3DPoint(x, 0.8, z).normalized!) > 0 ? 1 : 0
                // Within some 5° of the horizon.
                let around = Float(i * 200 + j) * 0.0001, up = Float(j) / 2_300
                low += Map3DSky.star(Map3DPoint(cosf(around), up, sinf(around))) > 0 ? 1 : 0
            }
        }
        XCTAssertGreaterThan(high, 0)
        XCTAssertLessThan(Double(high) / Double(total), 0.02)
        XCTAssertEqual(low, 0)
        for value in [Map3DSky.hash(3, 7), Map3DSky.hash(-120, 45), Map3DSky.hash(0, 0)] {
            XCTAssertTrue((0..<1).contains(value))
        }
    }

    func testTheShaderGetsNineRowsOfFour() {
        let camera = Map3DCamera(target: .zero, distance: 300, heading: 0.4)
        let floats = Map3DSky(lighting(21)).floats(camera: camera)
        XCTAssertEqual(floats.count, 36)
        // The camera's way is a unit vector looking down at the target.
        let look = Map3DPoint(floats[0], floats[1], floats[2])
        XCTAssertEqual(look.length, 1, accuracy: 0.001)
        XCTAssertLessThan(look.y, 0)
        let toTarget = (camera.target - camera.eye).normalized!
        XCTAssertEqual(look.dot(toTarget), 1, accuracy: 0.001)
    }

    /// The way the shader turns a point of the screen into a way into the
    /// sky lands on that point through the camera's own projection.
    func testTheScreensPointsLookWhereTheCameraDraws() {
        var camera = Map3DCamera(target: Map3DPoint(200, 0, -50), distance: 260, heading: 2.1, viewport: (1_024, 768))
        camera.lens = 50 * .pi / 180
        let f = Map3DSky(lighting(21)).floats(camera: camera)
        let look = Map3DPoint(f[0], f[1], f[2]), side = Map3DPoint(f[4], f[5], f[6]), up = Map3DPoint(f[8], f[9], f[10])
        for (x, y) in [(Float(0.5), Float(0.3)), (-0.9, 0.95), (0.2, -0.7)] {
            let way = look + side * (x * f[12]) + up * (y * f[13])
            let seen = camera.viewProjection.project(camera.eye + way * 500)!
            XCTAssertEqual(seen.x, x, accuracy: 0.001)
            XCTAssertEqual(seen.y, y, accuracy: 0.001)
        }
    }
}
