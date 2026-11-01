import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 535 (continued, ANKENG): the Ankeng LRT on sale. Its second
/// track kept 5 m off the first round its tight curves (the track outside
/// a curve laid with longer handles, not bulged in to within 4 m), and its
/// trains standing overnight at stations between brought in from beyond
/// them, facing the end their first run leaves for (one from Shuangcheng
/// out to Shisizhang first): one from Shuangcheng stood on the second
/// track, and the morning's trains toward Shisizhang stood behind it from
/// 06:12 on the second day.
///
/// Continued (ANKENGDEPOT): it is bought with the real Ankeng depot past
/// Shuangcheng, as the Green Mountain Line is with the Danhai depot
/// (decision 489). Six of its seven trains stand there overnight and one at
/// Shisizhang, as the real timetable leaves them; none stands at a station
/// between, and the positioning runs out to them are gone.
@MainActor
final class AnkengLineTests: XCTestCase {
    /// Every positioning run of the light rails and metros on sale that
    /// ends at a station between (the Sanying Line's now; the Ankeng LRT's
    /// trains stand in its depot) comes in from beyond it: from the end
    /// further from it, so it stands facing the nearer end, where its
    /// first run of the morning leaves for.
    func testATrainStandingAtAStationBetweenComesInFromBeyondIt() throws {
        let railways = try BundledRealData.railways()
        XCTAssertNotNil(railways.metroRuns["ntalrt:K"], "the Ankeng LRT's runs")
        for (id, line) in railways.metroRuns {
            let stops = line.stops
            for run in line.runs where run.positioning {
                guard let last = run.calls.last?.station, let first = run.calls.first?.station,
                      let at = stops.firstIndex(of: last), let from = stops.firstIndex(of: first),
                      at > 0, at < stops.count - 1 else { continue }
                let nearFirst = 2 * at <= stops.count - 1
                XCTAssertTrue(nearFirst ? from > at : from < at, "\(id): a positioning run \(first) to \(last)")
            }
        }
    }

    /// Bought with the Ankeng depot past Shuangcheng, where the real one
    /// is: six trains stand in it overnight, one at Shisizhang, none at a
    /// station between.
    func testTheLineIsBoughtWithItsRealDepot() throws {
        let session = try RealLineAcquisitionTests.game(round: "ntalrt:K", side: 1 << 21, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "ntalrt:K" }, "the Ankeng LRT on sale")
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        XCTAssertEqual(acquisition.depot?.platforms.count, RealLineDepotSite.ankeng.sidings)
        XCTAssertEqual(acquisition.trains.count, 7)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let station = try XCTUnwrap(world.stations.first(where: \.isDepot))
        XCTAssertEqual(station.name, "安坑機廠")
        let bought = try XCTUnwrap(world.lines.first)
        XCTAssertEqual(bought.depots, [station.id])
        // Where the real one is: within 300 m of its stabling tracks'
        // middle (the game's yard runs on north of them, in the depot).
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let real = WorldVector(frame.worldPosition(latitude: 24.943973, longitude: 121.487067))
        let away = (WorldVector(station.location) - real).length / RealLineAcquisition.metre
        FileHandle.standardError.write(Data("Ankeng depot \(Int(away)) m from the real stabling tracks' middle\n".utf8))
        XCTAssertLessThan(away, 300)
        func standing(at id: StationID) -> Int { world.trains.count { world.stationsStoppedAt(by: $0.id).contains(id) } }
        XCTAssertEqual(standing(at: station.id), 6)
        let shisizhang = try XCTUnwrap(world.stations.first { $0.name == "十四張" && bought.stops.contains($0.id) })
        XCTAssertEqual(standing(at: shisizhang.id), 1)
        // None at a station between.
        for stop in bought.stops.dropFirst().dropLast() {
            XCTAssertEqual(standing(at: stop), 0, world.station(id: stop)?.name ?? "")
        }
    }

    /// Bought with its depot on a game round it, laid with its second
    /// track, and run two real days under each rule: every run of the
    /// second day sent out.
    func testTheAnkengLRTIsBoughtAndRunsTwoRealDays() throws {
        for rules in [NewGameRules.simple, .realistic] {
            try RealLineAcquisitionTests.buyAndRunRealDay("ntalrt:K", type: .c, tier: .lightRail, rules: rules)
        }
    }
}
