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
@MainActor
final class AnkengLineTests: XCTestCase {
    /// Every positioning run of the light rails and metros on sale that
    /// ends at a station between comes in from beyond it: from the end
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

    /// Bought on a game round it, laid with its second track, and run two
    /// real days under each rule: every run of the second day sent out.
    func testTheAnkengLRTIsBoughtAndRunsTwoRealDays() throws {
        for rules in [NewGameRules.simple, .realistic] {
            try RealLineAcquisitionTests.buyAndRunRealDay("ntalrt:K", type: .c, tier: .lightRail, rules: rules)
        }
    }
}
