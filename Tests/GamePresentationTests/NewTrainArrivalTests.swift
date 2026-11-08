import GameCore
@testable import GamePresentation
import XCTest

/// Decision 566: the new-train arrival card.
final class NewTrainArrivalTests: XCTestCase {
    /// Every model with a card is a set the 3D map draws, and none is the
    /// pack's N700S-G or a light rail built in Taiwan.
    func testEveryCardIsADrawnImportedModel() {
        for entry in NewTrainArrivals.entries {
            XCTAssertNotNil(Map3DTrainSet.byKey[entry.key], "\(entry.key) is a 3D set")
        }
        for key in ["n700sG", "danhaiLRT", "ankengLRT"] {
            XCTAssertNil(NewTrainArrivals.catalog[key], "\(key) has no card")
        }
    }

    /// A model the fleet did not have shows its card once, with a news
    /// item; a second train of it, none.
    @MainActor
    func testFirstTrainOfAModelShowsItsCardOnce() throws {
        let session = GameSession(world: try makeWorld(balance: 100_000_000))
        XCTAssertTrue(session.trainArrivals.isEmpty)
        session.purchaseTrain()
        XCTAssertTrue(session.trainArrivals.isEmpty, "a standard car is no model")
        session.setSelectedTrainType(.emu3000)
        XCTAssertEqual(session.trainArrivals.map(\.key), ["emu3000"])
        let item = try XCTUnwrap(session.news.items.first { $0.category == .newTrain })
        XCTAssertEqual(item.text(in: .traditionalChinese), "新車抵台：EMU3000 城際列車加入車隊")
        XCTAssertEqual(session.news.items.count { $0.category == .newTrain }, 1)
        session.purchaseTrain()
        session.setSelectedTrainType(.emu3000)
        XCTAssertEqual(session.trainArrivals.map(\.key), ["emu3000"], "a second one has no card")
        XCTAssertEqual(session.news.items.count { $0.category == .newTrain }, 1, "nor a second news item")
        session.dismissTrainArrival()
        XCTAssertTrue(session.trainArrivals.isEmpty)
        session.purchaseTrain()
        session.setSelectedTrainType(.highSpeed)
        XCTAssertEqual(session.trainArrivals.map(\.key), ["highSpeed"], "the pack counts as locked: the 700T")
        session.dismissTrainArrival(all: true)
        XCTAssertTrue(session.trainArrivals.isEmpty)
    }

    /// Decision 635 (Mac playtest A11): buying the Wenhu Line brings its
    /// two models on one card, and no card about which track its trains
    /// take: its double track and its routes are the real line's.
    @MainActor
    func testABoughtLinesModelsComeOnOneCard() throws {
        let session = try RealLineAcquisitionTests.game(round: "trtc:BR", side: 1 << 21)
        session.watchRouteHint()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" }, "on sale")
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        session.watchRouteHint()
        XCTAssertEqual(session.trainArrivals.count, 1, session.trainArrivals.map(\.key).description)
        let card = try XCTUnwrap(session.trainArrivals.first)
        XCTAssertEqual(card.title(in: .traditionalChinese), "新車抵台：文湖線 VAL256、文湖線 370 型")
        XCTAssertEqual(card.story(in: .traditionalChinese), "首批抵台。")
        XCTAssertEqual(session.news.items.count { $0.category == .newTrain }, 2, "each model in the news log")
        XCTAssertNil(session.routeHint)
        session.dismissTrainArrival()
        XCTAssertTrue(session.trainArrivals.isEmpty)
    }

    /// The trains a game starts or is opened with have no card, and the
    /// demo shows none.
    @MainActor
    func testStartingFleetAndDemoShowNone() throws {
        var world = try makeWorld(balance: 100_000_000)
        let train = try world.purchaseTrain(named: "T1")
        try world.setTrainType(train.id, to: .emu3000)
        XCTAssertTrue(NewTrainArrivals.models(in: world).contains("emu3000"))
        let opened = GameSession(world: world)
        opened.purchaseTrain()
        opened.setSelectedTrainType(.emu3000)
        XCTAssertTrue(opened.trainArrivals.isEmpty, "the fleet had it")

        let demo = GameSession(world: try makeWorld(balance: 100_000_000))
        demo.news.isDemo = true
        demo.purchaseTrain()
        demo.setSelectedTrainType(.emu3000)
        XCTAssertTrue(demo.trainArrivals.isEmpty, "the demo shows none")
    }

    /// The sentence: the port and date where a source has them, else only
    /// that the first ones arrived.
    func testStory() throws {
        let emu3000 = try XCTUnwrap(NewTrainArrivals.catalog["emu3000"])
        XCTAssertEqual(emu3000.story(in: .traditionalChinese), "首批列車在 2021 年 7 月 30 日於花蓮港上岸。")
        XCTAssertEqual(emu3000.story(in: .english), "The first one came ashore at Hualien Port on 30 July 2021.")
        let puyuma = try XCTUnwrap(NewTrainArrivals.catalog["puyuma"])
        XCTAssertEqual(puyuma.story(in: .traditionalChinese), "首批列車在 2012 年 10 月於基隆港上岸。")
        let taroko = try XCTUnwrap(NewTrainArrivals.catalog["taroko"])
        XCTAssertEqual(taroko.story(in: .traditionalChinese), "首批抵台。")
        XCTAssertEqual(taroko.title(in: .traditionalChinese), "新車抵台：太魯閣號（TEMU1000）")
    }

    /// The picture uses only the icon's colours and the model's, the
    /// SVG only what Xcode's catalog takes, and the car moves down only.
    func testPicture() throws {
        let arrival = try XCTUnwrap(NewTrainArrivals.catalog["puyuma"])
        let allowed: Set<Int> = [0x262C57, 0x12A08F, 0x45D3C0, 0xFFC86B, 0xECEEF6, 0xFFFFFF, arrival.body, arrival.stripe, arrival.cab]
        for shape in NewTrainArrivalArt.shapes(for: arrival) {
            for colour in [shape.fill, shape.stroke].compactMap({ $0 }) {
                XCTAssertTrue(allowed.contains(colour), String(colour, radix: 16))
            }
        }
        let svg = NewTrainArrivalArt.svg(for: arrival)
        for banned in ["transform", "opacity", "<g", "<text", "gradient"] {
            XCTAssertFalse(svg.contains(banned), banned)
        }
        XCTAssertTrue(svg.contains("#D7282F"), "the Puyuma's red")
        let high = NewTrainArrivalArt.shapes(for: arrival, drop: 0)
        let set = NewTrainArrivalArt.shapes(for: arrival, drop: 1)
        XCTAssertEqual(high.count, set.count)
        XCTAssertNotEqual(high, set)
        if let path = ProcessInfo.processInfo.environment["NEW_TRAIN_ART_DIR"] {
            for entry in NewTrainArrivals.entries {
                try NewTrainArrivalArt.svg(for: entry).write(toFile: "\(path)/\(entry.key).svg", atomically: true, encoding: .utf8)
            }
        }
    }
}
