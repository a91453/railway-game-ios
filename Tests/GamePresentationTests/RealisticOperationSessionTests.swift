import Foundation
import GameCore
import GamePresentation
import XCTest

/// Realistic operation where the app meets it (ARCHITECTURE decision 207): a
/// new game plans realistically and counts punctuality, the worlds whose
/// timetables were measured without it (the demos, the challenges, the
/// tutorial) keep it off, as an old save does, and the line card says how
/// punctual a line was.
@MainActor
final class RealisticOperationSessionTests: XCTestCase {
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RealisticOperationSessionTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testANewGameOperatesRealistically() {
        XCTAssertTrue(GameWorld.newGame().realisticOperation)
        XCTAssertTrue(GameWorld.newGame(eventSeed: 7).realisticOperation)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        // Decision 256: under the realistic rules; the default simple ones
        // keep it off.
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.realisticOperation, false)
        launcher.returnToStart()
        launcher.newGameOptions.rules = .realistic
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.realisticOperation, true)
    }

    func testTheMeasuredWorldsKeepItOff() {
        XCTAssertFalse(DemoWorld.make(in: .english).realisticOperation)
        for challenge in Challenge.sandbox {
            XCTAssertFalse(GameWorld.newGame(challenge: challenge, eventSeed: 7).realisticOperation, challenge.id)
        }
        XCTAssertFalse(LiuMingchuanChallenge.make().realisticOperation)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startTutorial()
        XCTAssertEqual(launcher.session?.world.realisticOperation, false)
    }

    func testTheLineCardSaysHowPunctualTheLineWas() {
        func diagnosis(trips: Int64, late: Int64) -> LineLossDiagnosis {
            let measures = LineLossMeasures(
                days: 3, fareRevenue: Money(1_000_000), boardings: 100, departures: 60, trainDistance: 1_000, deadheadDistance: 0,
                peakLoadSum: 0, trains: 1, seatsPerTrain: 100, trainKeepPerDay: .zero, legsPerTrip: 2, serviceMinutes: 1_440,
                trips: trips, lateTrips: late
            )
            return LineLossDiagnosis(line: LineID(rawValue: 1), days: 3, fareRevenue: Money(1_000_000), operatingCost: .zero,
                                     maintenanceCost: .zero, energyCost: .zero, staffCost: .zero, measures: measures)
        }
        XCTAssertNil(diagnosis(trips: 0, late: 0).punctualityText(in: .english), "no trips counted: off, or none run")
        XCTAssertEqual(diagnosis(trips: 240, late: 10).punctualityText(in: .english), "On time 95%: 10 of 240 trips over 5 min late")
        XCTAssertEqual(diagnosis(trips: 240, late: 10).punctualityText(in: .traditionalChinese), "準點率 95%：240 趟有 10 趟誤點超過 5 分鐘")
    }
}
