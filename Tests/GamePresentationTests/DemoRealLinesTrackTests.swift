import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 401's sequel: the demo's real lines (decision 351) laid as the
/// real lines are, measured as ``DemoRealLinesTrackReportTests`` does: no
/// gap where a metro or light rail turns tightly, double track where the
/// real line is double, and a line that stops short of a station going on
/// from the last one it reached.
@MainActor
final class DemoRealLinesTrackTests: XCTestCase {
    private typealias Report = DemoRealLinesTrackReportTests

    /// Lays the demo in the view `half` metres each way round `station` of
    /// `system`, and measures the routes of `lineKey` it planned.
    private func laid(at station: String, in system: String, half: Double, lineKey: String) async throws -> (measures: [Report.Measure], world: GameWorld) {
        let (session, view) = try Report.game(at: station, in: system, half: half)
        let routes = try Report.routes(in: session, view: view).filter { $0.lineKey == lineKey }
        XCTAssertFalse(routes.isEmpty, "\(lineKey) in view")
        _ = await session.layDemoRealLines(in: view)
        return (Report.measure(routes, in: session.world), session.world)
    }

    /// The Wenhu Line turns about 35 m round its corners at Da'an and
    /// Songshan Airport: 40 m, the TRA's tightest, left 650–750 m out.
    func testTheWenhuLineHasNoGapRoundItsTightCorners() async throws {
        for station in ["大安", "中山國中"] {
            let (measures, _) = try await laid(at: station, in: "mrt", half: 1_200, lineKey: "mrt|BR")
            for measure in measures {
                XCTAssertEqual(measure.gaps, [], "\(station): \(measure.gaps.map(measure.stations(at:)))")
            }
        }
    }

    /// Kaohsiung's Circular Line turns as tightly as 26 m.
    func testTheCircularLightRailHasNoGapRoundItsTightCorners() async throws {
        for station in ["旅運中心", "美術館"] {
            let (measures, _) = try await laid(at: station, in: "krtc", half: 1_500, lineKey: "krtc|C")
            for measure in measures {
                XCTAssertEqual(measure.gaps, [], "\(station): \(measure.gaps.map(measure.stations(at:)))")
            }
        }
    }

    /// The Western Trunk Line is double into Zhunan, on the north line and
    /// the coast line both, and from Xinzuoying into Kaohsiung: their
    /// second track used to join a node of track on another level, too
    /// steep to build, and the whole was laid single.
    func testTheTrunkLinesAreDoubleWhereTheRealOnesAre() async throws {
        for (station, line) in [("竹南", "tra_sched|縱貫線北段"), ("竹南", "tra_sched|海線"), ("新左營", "tra_sched|縱貫線南段")] {
            let (measures, _) = try await laid(at: station, in: "tra_sched", half: 6_000, lineKey: line)
            for measure in measures {
                XCTAssertLessThan(measure.singleShare, 0.05, "\(station) \(line): \(measure.singles.map(measure.stations(at:)))")
            }
        }
    }

    /// Between Taipei and Banqiao the second track of the trunk line was
    /// refused beside the other lines' track; laid in pieces, only what
    /// GameCore refuses stays single.
    func testTheTrunkLineIsDoubleFromTaipeiToBanqiao() async throws {
        let (measures, _) = try await laid(at: "萬華", in: "tra_sched", half: 3_000, lineKey: "tra_sched|縱貫線北段")
        for measure in measures {
            XCTAssertLessThan(measure.singleShare, 0.05, "\(measure.singles.map(measure.stations(at:)))")
            XCTAssertEqual(measure.missed, [])
        }
    }

    /// A line that stops short where it would cross another on its level
    /// goes on from the last station it reached at another level, as one
    /// line calling at all of them: the Zhonghe–Xinlu Line's two branches
    /// round Taipei Main Station, of which one used to stop at Zhongxiao
    /// Xinsheng and start again at Songjiang Nanjing, the track between
    /// never laid.
    func testALineThatStopsShortGoesOnFromTheLastStationItReached() async throws {
        let (session, view) = try Report.game(at: "台北車站", in: "mrt", half: 2_000)
        let routes = try Report.routes(in: session, view: view).filter { $0.lineKey.hasPrefix("mrt|O_") }
        XCTAssertEqual(routes.count, 2, "\(routes.map(\.lineKey))")
        _ = await session.layDemoRealLines(in: view)
        for measure in Report.measure(routes, in: session.world) {
            XCTAssertEqual(measure.missed, [], measure.route.lineKey)
            XCTAssertEqual(measure.gaps, [], "\(measure.route.lineKey): \(measure.gaps.map(measure.stations(at:)))")
        }
        let lines = session.world.lines.filter { $0.name.hasPrefix("中和新蘆線") }
        XCTAssertEqual(lines.count, 2, "one line a branch: \(session.world.lines.map(\.name))")
    }
}
