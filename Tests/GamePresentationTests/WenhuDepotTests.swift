import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 535 (PR W): the Wenhu Line is bought with its two real
/// depots, Muzha past Taipei Zoo and Neihu past Nangang Exhibition
/// Center, and its 44 four-car people movers, half standing in each depot
/// overnight. Its ends are laid with five tracks; the trains they cannot
/// hold go into the depots.
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
}

/// Decision 535 (PR W): the Wenhu Line, two real days under simple rules;
/// a class for each rule so CI can put them in two shards.
@MainActor
final class WenhuSimpleDayTests: XCTestCase {
    func testTheWenhuLineRunsTwoRealDays() throws {
        try DanhaiDepotTests.buyAndRun(["trtc:BR"], round: "trtc:BR", rules: .simple)
    }
}

/// Decision 535 (PR W): the same under realistic rules.
@MainActor
final class WenhuRealisticDayTests: XCTestCase {
    func testTheWenhuLineRunsTwoRealDays() throws {
        try DanhaiDepotTests.buyAndRun(["trtc:BR"], round: "trtc:BR", rules: .realistic)
    }
}
