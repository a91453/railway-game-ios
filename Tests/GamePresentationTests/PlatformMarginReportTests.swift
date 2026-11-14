import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// PLATFORM-BOOK PB-4 (decision 757): how many lines a platform safety
/// margin would stop, run only when asked (`PLATFORM_MARGIN_REPORT=1`).
/// The owner's desktop game asks a train to be shorter than its platform
/// by a margin at both ends; this game asks only that it fit. For every
/// line on sale (bought under realistic rules, as a new game has it) and
/// the demos, it finds each train's calls where the longest platform of
/// the station fits the train now but would not with a margin of 2, 3 or
/// 5 m at each end, and prints them: how many calls, stations, lines and
/// trains a margin would leave with nowhere to stop.
@MainActor
final class PlatformMarginReportTests: XCTestCase {
    static let margins: [Int64] = [2, 3, 5]

    func testHowManyLinesAMarginStops() throws {
        guard ProcessInfo.processInfo.environment["PLATFORM_MARGIN_REPORT"] != nil else {
            throw XCTSkip("Set PLATFORM_MARGIN_REPORT=1 to measure the platform margin (decision 757).")
        }
        let railways = try BundledRealData.railways()
        var worlds: [(String, GameWorld)] = []
        let networks = Set(railways.metroRuns.keys).union(railways.branchRuns.keys).sorted()
        for network in networks {
            let round = network
            guard let session = try? RealLineAcquisitionTests.game(round: round, side: 1 << 22) else { continue }
            for line in session.buyableRealLines where line.network == network || line.id == network {
                let offer = session.realLineOffer(for: line)
                guard session.acquireRealLine(offer) else {
                    Self.print("\(line.id): not bought (\(offer.problem ?? ""))")
                    continue
                }
            }
            worlds.append((network, session.world))
        }
        if let tra = try? TRADemoTests.opened.get() { worlds.append(("tra-demo", tra)) }
        if let hsr = try? HighSpeedDemoTests.opened.get() { worlds.append(("hsr-demo", hsr)) }
        worlds.append(("demo", DemoWorld.make(in: .english)))
        var totals = Dictionary(uniqueKeysWithValues: Self.margins.map { ($0, (calls: 0, lines: Set<String>(), worlds: Set<String>())) })
        var trainsSeen = 0
        for (name, world) in worlds {
            for train in world.trains {
                // A line's train calls at the line's stops, out on a run or
                // waiting in the depot for one; any other at its timetable's.
                let line = world.assignedLine(of: train.id).flatMap { world.line(id: $0) }
                let calls = line?.stops ?? train.timetable.map(\.station)
                guard !calls.isEmpty else { continue }
                trainsSeen += 1
                let lineName = line?.name ?? "no line"
                for station in Set(calls).sorted(by: { $0.rawValue < $1.rawValue }) {
                    let longest = world.network.platforms(of: station).map(\.length).max() ?? 0
                    let slack = longest - train.length
                    guard slack >= 0 else { continue }
                    for margin in Self.margins where slack < 2 * margin * WorldCoordinate.unitsPerMetre {
                        totals[margin]?.calls += 1
                        totals[margin]?.lines.insert("\(name)/\(lineName)")
                        totals[margin]?.worlds.insert(name)
                        if margin == Self.margins.last {
                            let stationName = world.station(id: station)?.name ?? "\(station.rawValue)"
                            Self.print("\(name) \(lineName) \(train.name) at \(stationName): train \(train.length / 64) m, platform \(longest / 64) m, slack \(slack * 100 / 64) cm")
                        }
                    }
                }
            }
        }
        Self.print("worlds \(worlds.count), trains with calls \(trainsSeen)")
        for margin in Self.margins {
            let total = totals[margin]!
            Self.print("margin \(margin) m each end: \(total.calls) train calls, \(total.lines.count) lines in \(total.worlds.count) worlds: \(total.lines.sorted().joined(separator: ", "))")
        }
    }

    private static func print(_ line: String) {
        FileHandle.standardError.write(Data("PLATFORM_MARGIN \(line)\n".utf8))
    }
}
