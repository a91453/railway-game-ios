import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 313, later: on every kind of game the launcher starts, the 3D
/// map opened from the 2D map's camera has its middle where the 2D map
/// looked (kept within the map). A new kind of start must be added to
/// ``Start`` or to ``notAStart``, or `testEveryStartIsListed` fails.
@MainActor
final class Map3DOpenEveryStartTests: XCTestCase {
    /// A kind of game the launcher starts; one case for each of its public
    /// `start…` and `open…` calls (``startsCalled``), each challenge and each
    /// lesson.
    enum Start: CustomStringConvertible {
        case newGame
        case realWorldGameInTaiwan
        case realWorldGameAbroad
        case wholeTaiwan
        case challenge(Challenge)
        case weeklyChallenge
        case demo
        case realWorldDemo
        case highSpeedDemo
        case traDemo
        case frameTimeBench
        case tutorial
        case lesson(Lesson)

        static var all: [Start] {
            [.newGame, .realWorldGameInTaiwan, .realWorldGameAbroad, .wholeTaiwan]
                + (Challenge.sandbox + Challenge.history).map(Start.challenge)
                + [.weeklyChallenge, .demo, .realWorldDemo, .highSpeedDemo, .traDemo, .frameTimeBench, .tutorial]
                + Lesson.all.map(Start.lesson)
        }

        /// The launcher's call that starts it.
        var call: String {
            switch self {
            case .newGame, .realWorldGameInTaiwan: "startNewGame"
            case .realWorldGameAbroad: "openRealWorldGame"
            case .wholeTaiwan: "startWholeTaiwan"
            case .challenge: "startChallenge"
            case .weeklyChallenge: "startWeeklyChallenge"
            case .demo: "openDemo"
            case .realWorldDemo: "openRealWorldDemo"
            case .highSpeedDemo: "openHighSpeedDemo"
            case .traDemo: "openTRADemo"
            case .frameTimeBench: "openFrameTimeBench"
            case .tutorial: "startTutorial"
            case .lesson: "startLesson"
            }
        }

        var description: String {
            switch self {
            case .challenge(let challenge): "challenge \(challenge.id)"
            case .lesson(let lesson): "lesson \(lesson.id)"
            default: call
            }
        }
    }

    /// The launcher's `start…` and `open…` calls that start no kind of
    /// game of their own, and why.
    static let notAStart: [String: String] = [
        // The Debug app's website screenshots (decision 165), on the demo's
        // and the other starts' maps.
        "openScreenshotScene": "a Debug scene on a map listed above",
    ]

    /// The public `start…` and `open…` calls of `GameLauncher.swift`.
    static func startsCalled() throws -> Set<String> {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/GamePresentation/GameLauncher.swift"), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"public func ((?:start|open)[A-Za-z]*)\("#)
        let range = NSRange(source.startIndex..., in: source)
        return Set(pattern.matches(in: source, range: range).compactMap { Range($0.range(at: 1), in: source).map { String(source[$0]) } })
    }

    func testEveryStartIsListed() throws {
        let called = try Self.startsCalled()
        XCTAssertFalse(called.isEmpty)
        let listed = Set(Start.all.map(\.call)).union(Self.notAStart.keys)
        XCTAssertEqual(called.subtracting(listed), [], "a new kind of start: add it to Start, and check where its 3D map opens")
        XCTAssertEqual(listed.subtracting(called), [], "a start the launcher no longer has")
    }

    nonisolated static let data = RealWorldData.load(file: RealWorldDataLoadTests.file)

    static let taipei = GeoAnchor(latitudeDegrees: 25.047882, longitudeDegrees: 121.517219)!
    static let tokyo = GeoAnchor(latitudeDegrees: 35.681236, longitudeDegrees: 139.767125)!

    /// The world `start` begins.
    func world(of start: Start) async throws -> GameWorld {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Map3DOpenEveryStartTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        await launcher.loadRealWorldData { Self.data }.value
        let railways = try XCTUnwrap(launcher.railways, "the real railways")
        switch start {
        case .newGame: launcher.startNewGame()
        case .realWorldGameInTaiwan: launcher.startNewGame(at: Self.taipei)
        case .realWorldGameAbroad: await launcher.openRealWorldGame(at: Self.tokyo)?.value
        case .wholeTaiwan: launcher.startWholeTaiwan()
        case .challenge(let challenge): await launcher.startChallenge(challenge)?.value
        case .weeklyChallenge: launcher.startWeeklyChallenge(at: Date(timeIntervalSince1970: 1_792_000_000))
        case .demo: launcher.openDemo()
        case .realWorldDemo: await launcher.openRealWorldDemo(railways: railways)?.value
        case .highSpeedDemo: await launcher.openHighSpeedDemo(railways: railways)?.value
        case .traDemo: await launcher.openTRADemo(railways: railways)?.value
        case .frameTimeBench: _ = await launcher.openFrameTimeBench(lines: 1)
        case .tutorial: launcher.startTutorial()
        case .lesson(let lesson): launcher.startLesson(lesson)
        }
        return try XCTUnwrap(launcher.session?.world, "\(start) opens a game")
    }

    /// The demos built in their own classes, which open them through the
    /// launcher already (some 130, 35 and 20 seconds) and check them with
    /// ``assertOpensWhereThe2DMapLooks(_:_:file:line:)``.
    static func isCheckedElsewhere(_ start: Start) -> Bool {
        switch start {
        case .highSpeedDemo, .traDemo, .frameTimeBench: true // HighSpeedDemoTests, TRADemoTests, FrameTimeBenchTests
        default: false
        }
    }

    func testEveryStartOpensThe3DMapWhereThe2DMapLooks() async throws {
        for start in Start.all where !Self.isCheckedElsewhere(start) {
            Self.assertOpensWhereThe2DMapLooks(try await world(of: start), "\(start)")
        }
    }

    /// The 3D map of `world` opened where the 2D map looks, off the middle
    /// of the map and of what is built, and off the map (kept within it),
    /// has its middle there.
    nonisolated static func assertOpensWhereThe2DMapLooks(_ world: GameWorld, _ start: String, file: StaticString = #filePath, line: UInt = #line) {
        let map = WorldRegion(bounds: world.bounds)
        let width = map.maxX - map.minX, height = map.maxY - map.minY
        let inside = (x: map.minX + width * 0.3, y: map.minY + height * 0.7)
        let looks = [(focus: inside, middle: inside), (focus: (x: map.maxX + width, y: map.minY - height), middle: (x: map.maxX, y: map.minY))]
        for look in looks {
            let frame = Map3DScene.frame(world: world, focus: look.focus)
            XCTAssertEqual(frame.originX, look.middle.x.rounded(), start, file: file, line: line)
            XCTAssertEqual(frame.originY, look.middle.y.rounded(), start, file: file, line: line)
            XCTAssertTrue(frame.region.minX <= frame.originX && frame.originX <= frame.region.maxX, start, file: file, line: line)
            XCTAssertTrue(frame.region.minY <= frame.originY && frame.originY <= frame.region.maxY, start, file: file, line: line)
        }
    }
}
