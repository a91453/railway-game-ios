import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 543: the Wenhu Line, laid as it would be bought (it is not on
/// sale yet: with signals off it sends too few of its runs), with its two
/// real depots, Muzha past Taipei Zoo and Neihu past Nangang Exhibition
/// Center (decision 535 continued), and its 44 four-car people movers,
/// half standing in each depot overnight. Its trains stood still from 07:14 on
/// their first morning while the second track's ramps were laid with
/// handles of another length than the first track's (#1668): at the
/// switch the two left along the same way but with tangents of different
/// lengths, and a train keeping left (decision 202) chose by their
/// rounding, so trains toward the zoo took the other way's track.
@MainActor
final class WenhuLineTests: XCTestCase {
    func testTheLineIsBoughtWithItsTwoRealDepots() throws {
        let session = try RealLineAcquisitionTests.game(round: "trtc:BR", side: 1 << 21, heights: true)
        XCTAssertFalse(session.buyableRealLines.contains { $0.id == "trtc:BR" }, "not on sale yet")
        let line = try XCTUnwrap(DepotReturnReportTests.wenhu("trtc:BR", in: session))
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        let depots = [acquisition.depot].compactMap(\.self) + (acquisition.moreDepots ?? [])
        XCTAssertEqual(depots.map(\.platforms.count), [RealLineDepotSite.muzha.sidings, RealLineDepotSite.neihu.sidings])
        XCTAssertEqual(acquisition.trains.count, 44)
        XCTAssertEqual(acquisition.trainType, .apm)
        XCTAssertEqual(acquisition.cars, 4)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let bought = try XCTUnwrap(world.lines.first)
        let stations = world.stations.filter(\.isDepot)
        XCTAssertEqual(Set(stations.map(\.name)), ["木柵機廠", "內湖機廠"])
        XCTAssertEqual(Set(bought.depots), Set(stations.map(\.id)))
        for site in [RealLineDepotSite.muzha, .neihu] {
            let station = try XCTUnwrap(stations.first { $0.name == site.chinese })
            // Overnight: the 22 the real timetable leaves at its end.
            XCTAssertEqual(world.trains.count { world.stationsStoppedAt(by: $0.id).contains(station.id) }, 22, site.english)
        }
        XCTAssertEqual(RealLineStock.setKey(ofRealLine: "trtc:BR"), "wenhu")
    }

    /// Where the second track's ramp leaves the first (two ways on from a
    /// switch along the same way, to within 1 in 1,000, with tangents
    /// within 1% of the same length, as the two edges' handles are), a
    /// train keeping left takes the one that leads to the left: the side
    /// decides, not how the tangents round. Before decision 543 the Wenhu
    /// Line's ramp at Nangang Exhibition Center left at (135, -2129) and
    /// (135, -2132), and trains toward the zoo took the first track.
    func testTheSecondTracksRampsKeepLeftByTheSideTheyLeadTo() throws {
        for id in ["trtc:BR", "ntalrt:K"] {
            let world = try DepotReturnReportTests.bought(id)
            var checked = 0
            for node in world.network.nodes {
                for arrival in node.ends where arrival.exits.count == 2 {
                    func leaving(_ edge: TrackEdgeID) -> TrackTraversal {
                        TrackTraversal(edge: edge, direction: world.network.edge(edge)?.from == node.id ? .forward : .backward)
                    }
                    let ways = arrival.exits.compactMap { exit -> (edge: TrackEdgeID, tangent: PlanVector, chord: PlanVector)? in
                        guard let end = node.end(of: exit), let edge = world.network.edge(exit),
                              let far = world.network.node(edge.end(of: leaving(exit).direction)) else { return nil }
                        return (exit, end.direction, far.position.plan.vector(from: node.position.plan))
                    }
                    guard ways.count == 2 else { continue }
                    let (a, b) = (ways[0], ways[1])
                    let (lengthA, lengthB) = (Self.length(a.tangent), Self.length(b.tangent))
                    guard abs(Double(a.tangent.cross(b.tangent))) < 0.001 * lengthA * lengthB,
                          abs(lengthA - lengthB) < 0.01 * max(lengthA, lengthB), a.chord.cross(b.chord) != 0 else { continue }
                    let arrived = TrackTraversal(edge: arrival.edge, direction: world.network.edge(arrival.edge)?.from == node.id ? .backward : .forward)
                    let right = world.rightOfLeftmost(after: arrived, among: [leaving(a.edge), leaving(b.edge)])
                    // b leads left of a when the cross product from a's chord to b's is negative.
                    let rightByChord = a.chord.cross(b.chord) < 0 ? a.edge : b.edge
                    XCTAssertEqual(right.map(\.edge), [rightByChord], "\(id): the switch at \(node.id)")
                    checked += 1
                }
            }
            XCTAssertGreaterThanOrEqual(checked, 2, "\(id): both ramps")
        }
    }

    private static func length(_ vector: PlanVector) -> Double {
        (Double(vector.dx) * Double(vector.dx) + Double(vector.dy) * Double(vector.dy)).squareRoot()
    }

    /// Bought under realistic rules and played minute by minute, as the
    /// app plays, to nine in the morning of its first day: every run due
    /// by then sent out and no train in a deadlock (before decision 543,
    /// 42 of the 98 not sent out and all 44 trains in a deadlock). Run
    /// only when asked (`WENHU_MORNING=1`): some 2 minutes in a release
    /// build, 26 in a debug one; CI keeps the ramps' test above, which
    /// fails on the cause.
    func testTheFirstMorningPeakRuns() throws {
        guard ProcessInfo.processInfo.environment["WENHU_MORNING"] != nil else {
            throw XCTSkip("Set WENHU_MORNING=1 to play the Wenhu Line's first morning (decision 543).")
        }
        var world = try DepotReturnReportTests.bought("trtc:BR")
        let line = try XCTUnwrap(world.lines.first)
        let day = world.clock.now.seconds / GameTime.secondsPerDay
        let until = day * GameTime.secondsPerDay + 9 * GameTime.secondsPerHour
        var deadlocked = 0
        while world.clock.now.seconds < until {
            try world.advance(ticks: 1)
            if world.clock.now.seconds % (10 * GameTime.secondsPerMinute) == 0 {
                deadlocked = max(deadlocked, world.deadlockedTrains().count)
            }
        }
        let ran = try XCTUnwrap(world.line(id: line.id))
        let due = zip(ran.runs, ran.runDays).filter { run, _ in
            run.runs(onDay: day) && run.start(onDay: day) + LineRun.latestDispatch < world.clock.now.seconds
        }
        let missed = due.filter { _, sent in (sent ?? -1) < day }
        XCTAssertGreaterThan(due.count, 90)
        XCTAssertEqual(missed.count, 0, "runs not sent out by nine: \(missed.count) of \(due.count)")
        XCTAssertEqual(deadlocked, 0)
    }
}
