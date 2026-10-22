import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 346: the sound of the weather the map shows (``WeatherSound``),
/// which the session tells the app when it changes, and the thunder after
/// each flash of lightning. Never part of the world.
final class WeatherSoundTests: XCTestCase {
    /// A small world with Taiwan's weather drawn from seed 7, on `day`.
    private func world(day: Int64) throws -> GameWorld {
        var world = GameWorld(
            bounds: try WorldBounds(width: 32_768, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(now: GameTime(seconds: day * GameTime.secondsPerDay))
        )
        world.setDisruptions(Disruptions(level: .standard, country: "TW", seed: 7))
        return world
    }

    /// The first day from `day` whose sky is `sky`.
    private func firstDay(from day: Int64, with sky: MapWeather.Sky) throws -> Int64 {
        let found = try (day..<(day + 720)).first { try MapWeather(world: world(day: $0)).sky == sky }
        return try XCTUnwrap(found, "no \(sky) in two years")
    }

    /// Rain lighter than a storm's; a storm's and a typhoon's at full and
    /// with thunder; nothing under a clear sky.
    func testEachSkyHasItsSound() {
        XCTAssertNil(WeatherSound(weather: .clear))
        let rain = WeatherSound(weather: MapWeather(sky: .rain))
        XCTAssertEqual(rain?.loop, .rain)
        XCTAssertEqual(rain?.volume ?? 0, pow(10, -6.0 / 20), accuracy: 1e-9)
        XCTAssertEqual(rain?.thunders, false)
        XCTAssertEqual(WeatherSound(weather: MapWeather(sky: .thunderstorm)), WeatherSound(loop: .rain, volume: 1, thunders: true))
        XCTAssertEqual(WeatherSound(weather: MapWeather(sky: .typhoon)), WeatherSound(loop: .typhoon, volume: 1, thunders: true))
    }

    /// Each flash is followed by its own clap, 1 to 4 s later; the farther,
    /// the quieter and lower. Walking from one clap to the next hears every
    /// one, in order, once.
    func testThunderFollowsEachFlash() throws {
        let storm = MapWeather(sky: .thunderstorm)
        let start = 782_000_000.0 // a day in 2025, as the views' clock reads
        let firstCycle = Int(start / MapWeather.flashPeriod)
        var claps: [WeatherSound.Thunder] = []
        for cycle in firstCycle..<(firstCycle + 400) {
            let flash = MapWeather.flashStart(inCycle: cycle)
            XCTAssertEqual(storm.flash(at: flash + 0.01), 1, "the flash of cycle \(cycle) lights then")
            XCTAssertEqual(storm.flash(at: flash - 0.01), 0)
            let clap = WeatherSound.thunder(inCycle: cycle)
            XCTAssertGreaterThanOrEqual(clap.time - flash, 1)
            XCTAssertLessThanOrEqual(clap.time - flash, 4)
            XCTAssertLessThanOrEqual(clap.volume, 1)
            XCTAssertGreaterThanOrEqual(clap.volume, pow(10, -9.0 / 20) - 1e-9)
            XCTAssertEqual(clap.rate, 1 - 0.15 * (clap.time - flash - 1) / 3, accuracy: 1e-6, "farther is lower")
            claps.append(clap)
        }
        claps.sort { $0.time < $1.time }

        var heard: [WeatherSound.Thunder] = []
        var time = claps[10].time - 0.001
        while heard.count < 300 {
            let clap = WeatherSound.thunder(after: time)
            XCTAssertGreaterThan(clap.time, time)
            heard.append(clap)
            time = clap.time
        }
        XCTAssertEqual(heard, Array(claps[10..<310]))
    }

    /// The session tells the app the weather's sound when its player is
    /// set, and again only when the day's sky changes it.
    func testTheSessionTellsTheSoundOfEachDaysWeather() async throws {
        let rainDay = try firstDay(from: 100, with: .rain)
        var start = try world(day: rainDay)
        start.setSpeed(.fast)
        await MainActor.run {
            let session = GameSession(world: start)
            var told: [WeatherSound?] = []
            session.weatherSound = { told.append($0) }
            XCTAssertEqual(told, [WeatherSound(weather: MapWeather(sky: .rain))], "told at once")

            var skies: [MapWeather.Sky] = []
            // Ten game minutes a tick: 144 ticks a day, for 30 days.
            for _ in 0..<(144 * 30) {
                session.advance(realElapsed: GameSession.tickInterval)
                let sky = MapWeather(world: session.world).sky
                if skies.last != sky { skies.append(sky) }
            }
            XCTAssertEqual(told, [WeatherSound(weather: MapWeather(sky: .rain))] + skies.dropFirst().map { WeatherSound(weather: MapWeather(sky: $0)) })
            XCTAssertGreaterThan(told.count, 2, "the weather changed in a month")
            for (earlier, later) in zip(told, told.dropFirst()) {
                XCTAssertNotEqual(earlier, later, "told only on a change")
            }
        }
    }

    /// Turning the weather off silences it at once.
    func testTurningTheWeatherOffSilencesIt() async throws {
        let stormDay = try firstDay(from: 100, with: .thunderstorm)
        let start = try world(day: stormDay)
        await MainActor.run {
            let session = GameSession(world: start)
            var told: [WeatherSound?] = []
            session.weatherSound = { told.append($0) }
            XCTAssertEqual(told.last??.thunders, true)
            session.setDisruptionLevel(nil)
            XCTAssertEqual(told.count, 2)
            XCTAssertNil(told.last ?? nil)
        }
    }

    /// The loops and the clap are made by the audio tool, listed in its
    /// manifest as the weather's (the loops with their seam) and bundled
    /// with the app.
    func testEverySoundIsABundledFileInTheManifest() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("tools/audio/manifest.json"))) as? [String: Any]
        let entries = manifest?["files"] as? [[String: Any]] ?? []
        let files = WeatherSound.Loop.allCases.map { ($0.resource, true) } + [(WeatherSound.thunderResource, false)]
        for (resource, loops) in files {
            let file = "\(resource.name).\(resource.extension)"
            let entry = try XCTUnwrap(entries.first { $0["file"] as? String == file }, file)
            XCTAssertEqual(entry["kind"] as? String, "weather", file)
            XCTAssertEqual(entry["loopSeam"] != nil, loops, file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RailwayGameApp/Resources/Audio/\(file)").path), "\(file) is bundled")
        }
    }

    func testTheLauncherHandsItsPlayerToEachGameAndSilencesItOnLeaving() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WeatherSoundTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        await MainActor.run {
            let launcher = GameLauncher(library: library, language: .english)
            var told: [WeatherSound?] = []
            launcher.weatherSound = { told.append($0) }
            launcher.startNewGame()
            let weather = launcher.session.map { WeatherSound(weather: MapWeather(world: $0.world)) } ?? nil
            // Silenced, then told the new game's weather unless clear.
            XCTAssertEqual(told, weather == nil ? [nil] : [nil, weather])
            XCTAssertNotNil(launcher.session?.weatherSound)
            launcher.returnToStart()
            XCTAssertNil(told.last ?? nil)
        }
    }
}
