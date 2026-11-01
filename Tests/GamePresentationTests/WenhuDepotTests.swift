import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 535 (PR W): the Wenhu Line is bought with its two real
/// depots, Muzha past Taipei Zoo and Neihu past Nangang Exhibition
/// Center, and its 44 four-car people movers, half standing in each depot
/// overnight. Its ends are laid with five tracks; the trains they cannot
/// hold go into the depots. It is sold only with traffic control on:
/// without it the line stood still from its first morning (the
/// decision's next step).
@MainActor
final class WenhuDepotTests: XCTestCase {
    func testTheLineIsBoughtWithItsTwoRealDepots() throws {
        let session = try RealLineAcquisitionTests.game(round: "trtc:BR", side: 1 << 21, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" }, "the Wenhu Line on sale")
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
        // Each where the real one is: within 300 m of its yard's middle.
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        func standing(at id: StationID) -> Int { world.trains.count { world.stationsStoppedAt(by: $0.id).contains(id) } }
        for site in [RealLineDepotSite.muzha, .neihu] {
            let station = try XCTUnwrap(stations.first { $0.name == site.chinese })
            let real = WorldVector(frame.worldPosition(
                latitude: (site.yard.start.latitude + site.yard.end.latitude) / 2, longitude: (site.yard.start.longitude + site.yard.end.longitude) / 2
            ))
            let away = (WorldVector(station.location) - real).length / RealLineAcquisition.metre
            FileHandle.standardError.write(Data("\(site.english) \(Int(away)) m from the real yard's middle\n".utf8))
            XCTAssertLessThan(away, 300, site.english)
            // Overnight: the 22 the real timetable leaves at its end.
            XCTAssertEqual(standing(at: station.id), 22, site.english)
        }
        XCTAssertEqual(RealLineStock.setKey(ofRealLine: "trtc:BR"), "wenhu")
    }

    /// Without traffic control the card says to turn it on, and buys
    /// nothing; an offer laid out before it was turned off is refused too.
    func testItIsSoldOnlyWithTrafficControlOn() throws {
        let session = try RealLineAcquisitionTests.game(round: "trtc:BR", side: 1 << 21, heights: true, rules: .simple)
        XCTAssertFalse(session.world.isTrafficControlEnabled)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" }, "the Wenhu Line listed")
        let refused = session.realLineOffer(for: line)
        XCTAssertNil(refused.acquisition)
        XCTAssertEqual(refused.problem, "打開「行車控制」後才能收購這條線。")
        XCTAssertFalse(session.acquireRealLine(refused))
        XCTAssertTrue(session.world.lines.isEmpty)
        // Another line is sold as before.
        if let other = session.buyableRealLines.first(where: { $0.id != "trtc:BR" }) {
            XCTAssertNotEqual(session.realLineOffer(for: other).problem, refused.problem)
        }

        session.setTrafficControl(true)
        XCTAssertTrue(session.world.isTrafficControlEnabled, session.message?.text ?? "")
        let offer = session.realLineOffer(for: line)
        XCTAssertNotNil(offer.acquisition, offer.problem ?? "")
        session.setTrafficControl(false)
        XCTAssertFalse(session.acquireRealLine(offer))
        XCTAssertEqual(session.message?.text, "打開「行車控制」後才能收購這條線。")
        XCTAssertTrue(session.world.lines.isEmpty)

        let english = GameSession(world: session.world, language: .english)
        english.railways = session.railways
        english.heights = session.heights
        XCTAssertEqual(english.realLineOffer(for: line).problem, "Turn on Traffic control to buy this line.")
    }
}

/// Decision 535 (PR W): the Wenhu Line bought under realistic rules and
/// played minute by minute, as the app plays, to nine in the morning of
/// its first day: every run due by then sent out and no train in a
/// deadlock. Two whole days (some 12 minutes in a release build) are
/// `DepotReturnReportTests`' (`DEPOT_RETURN_ONLY=wenhu`).
@MainActor
final class WenhuMorningTests: XCTestCase {
    func testTheFirstMorningPeakRuns() throws {
        let world0 = try DepotReturnReportTests.bought("trtc:BR")
        var world = world0
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
        XCTAssertGreaterThan(due.count, 100)
        XCTAssertEqual(missed.count, 0, "runs not sent out by nine: \(missed.count) of \(due.count)")
        XCTAssertEqual(deadlocked, 0)
        FileHandle.standardError.write(Data("Wenhu first morning: \(due.count) runs due, \(missed.count) missed, most deadlocked \(deadlocked)\n".utf8))
    }
}
