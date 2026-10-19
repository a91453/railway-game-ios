import GameCore
import GamePresentation
import XCTest

/// The new line's draft in one line (City Transport Manager study 4.2,
/// step M0): its stops, length, time end to end and, under simple rules,
/// price; what to tap next; or why no track joins the stations picked
/// (decision 284). On a blank map and on a real map of Taiwan.
@MainActor
final class LineDraftSummaryTests: XCTestCase {
    private static let middle = Int64(524_288)
    private static let metre = WorldCoordinate.unitsPerMetre

    /// A straight track 6 km long through the middle of the map, west to
    /// east, with three stations on it 2.5 km apart; a second track 1 km
    /// to the south joining none of it, with one station; and a station
    /// with no platform.
    private struct Layout {
        var world: GameWorld
        let west: StationID, centre: StationID, east: StationID
        let apart: StationID
        let bare: StationID
    }

    private func layout(_ world: GameWorld, names: [String]) throws -> Layout {
        var world = world
        world.setTourism(nil)
        let platform = 4 * world.platformCarLength
        func point(_ east: Int64, _ south: Int64) -> WorldCoordinate {
            WorldCoordinate(x: Self.middle + east * Self.metre, y: Self.middle + south * Self.metre)
        }
        let start = try world.buildTrackNode(at: point(-3_000, 0))
        let end = try world.buildTrackNode(at: point(3_000, 0))
        let main = try world.buildTrackEdge(from: start, to: end)
        var stations: [StationID] = []
        for (index, east) in [Int64(-2_500), 0, 2_500].enumerated() {
            let id = try world.buildStation(named: names[index], at: PlanPoint(x: Self.middle + east * Self.metre, y: Self.middle - 64 * Self.metre)).id
            let from = (east + 3_000) * Self.metre - platform / 2
            try world.addTrackPlatform(id, on: main, from: from, to: from + platform)
            stations.append(id)
        }
        let southWest = try world.buildTrackNode(at: point(-1_000, 1_000))
        let southEast = try world.buildTrackNode(at: point(1_000, 1_000))
        let south = try world.buildTrackEdge(from: southWest, to: southEast)
        let apart = try world.buildStation(named: names[3], at: PlanPoint(x: Self.middle, y: Self.middle + 1_064 * Self.metre)).id
        try world.addTrackPlatform(apart, on: south, from: 1_000 * Self.metre - platform / 2, to: 1_000 * Self.metre + platform / 2)
        let bare = try world.buildStation(named: names[4], at: PlanPoint(x: Self.middle + 2_000 * Self.metre, y: Self.middle + 2_000 * Self.metre)).id
        return Layout(world: world, west: stations[0], centre: stations[1], east: stations[2], apart: apart, bare: bare)
    }

    private func pick(_ stations: [StationID], in session: GameSession) {
        session.startPickingLineStops(announces: false)
        for station in stations {
            session.selectStation(station)
            session.addSelectedStationToLineDraft()
        }
    }

    // MARK: - Blank map

    private func blank(rules: NewGameRules = .simple) throws -> Layout {
        try layout(GameWorld.newGame(rules: rules), names: ["West", "Centre", "East", "Apart", "Bare"])
    }

    func testNothingIsSaidUntilALineIsPicked() throws {
        let map = try blank()
        let session = GameSession(world: map.world, language: .english)
        XCTAssertNil(session.lineDraftSummary)
    }

    func testNoStationAndOneStationSayWhatToTapNext() throws {
        let map = try blank()
        let session = GameSession(world: map.world, language: .english)
        session.startPickingLineStops(announces: false)
        XCTAssertEqual(session.lineDraftSummary, LineDraftSummary(text: "Tap the line's first station", isProblem: false))
        pick([map.west], in: session)
        XCTAssertEqual(session.lineDraftSummary, LineDraftSummary(text: "1 stop · tap the line's next station", isProblem: false))

        let chinese = GameSession(world: map.world, language: .traditionalChinese)
        chinese.startPickingLineStops(announces: false)
        XCTAssertEqual(chinese.lineDraftSummary?.text, "點路線的第一站")
        pick([map.west], in: chinese)
        XCTAssertEqual(chinese.lineDraftSummary?.text, "1 站 · 點路線的下一站")
    }

    /// West to East passes Centre: three stops, 5 km between the
    /// platforms' berths, and the price the line opens for.
    func testOneWayGivesItsStopsLengthTimeAndPrice() throws {
        let map = try blank()
        let session = GameSession(world: map.world, language: .english)
        pick([map.west, map.east], in: session)
        let price = try XCTUnwrap(session.lineOpeningPreview).cost
        XCTAssertGreaterThan(price.amount, 0)
        let summary = try XCTUnwrap(session.lineDraftSummary)
        XCTAssertFalse(summary.isProblem)
        XCTAssertEqual(summary.text, "3 stops · 5.0 km · about 6 min · \(price.moneyText)")
        // The map's ✓ says the same, and what the price brings.
        XCTAssertEqual(session.mapLineDraft?.caption, summary.text + "\nWith a train")

        let chinese = GameSession(world: map.world, language: .traditionalChinese)
        pick([map.west, map.east], in: chinese)
        XCTAssertEqual(chinese.lineDraftSummary?.text, "3 站 · 5.0 km · 約 6 分 · \(price.moneyText)")
        XCTAssertEqual(chinese.mapLineDraft?.caption, "3 站 · 5.0 km · 約 6 分 · \(price.moneyText)\n含一列車")
    }

    /// The time is the trains' own: every leg, and a minute at each call
    /// between the ends.
    func testTheTimeIsTheJourneysOneWay() throws {
        let map = try blank()
        var trial = map.world
        let line = try trial.createLine(named: "Trial", stops: [map.west, map.centre, map.east]).id
        let journey = try XCTUnwrap(trial.lineJourney(line))
        let seconds = journey.legs[0].seconds + journey.legs[1].seconds + journey.dwellSeconds
        let minutes = max(1, (seconds + 30) / 60)
        let session = GameSession(world: map.world, language: .english)
        pick([map.west, map.east], in: session)
        XCTAssertTrue(try XCTUnwrap(session.lineDraftSummary?.text).contains("about \(minutes) min"))
    }

    /// Calling only at the stations picked leaves Centre out of the count,
    /// not out of the way.
    func testStopsLeftOutAreNotCounted() throws {
        let map = try blank()
        let session = GameSession(world: map.world, language: .english)
        pick([map.west, map.east], in: session)
        session.lineDraftStopping = .pickedStations
        XCTAssertTrue(try XCTUnwrap(session.lineDraftSummary?.text).hasPrefix("2 stops · 5.0 km · "))
    }

    /// Out to East and back to West: three stations, the way out and back.
    func testALineBackToItsStartSaysSo() throws {
        let map = try blank()
        let session = GameSession(world: map.world, language: .english)
        pick([map.west, map.east, map.west], in: session)
        XCTAssertEqual(session.lineDraftStops, [map.west, map.centre, map.east, map.centre, map.west])
        let back = try XCTUnwrap(session.lineDraftSummary?.text); XCTAssertTrue(back.hasPrefix("3 stops, back to the start · 10.1 km · "), back)

        let chinese = GameSession(world: map.world, language: .traditionalChinese)
        pick([map.west, map.east, map.west], in: chinese)
        XCTAssertTrue(try XCTUnwrap(chinese.lineDraftSummary?.text).hasPrefix("3 站（回到起點） · 10.1 km · "))
    }

    /// The demo map's ring of track (decision 49): a new line round it,
    /// West, North, East, South and back to West.
    func testARingOfTrackGoesRound() throws {
        let world = DemoWorld.make(in: .english)
        let ring = try XCTUnwrap(world.lines.first(where: \.isRing))
        let session = GameSession(world: world, language: .english)
        pick(ring.stops + [ring.stops[0]], in: session)
        XCTAssertEqual(session.lineDraftStops, ring.stops + [ring.stops[0]])
        // Four legs of 49 s and a minute at each of the three stops
        // between: 376 s, about 6 minutes.
        let price = try XCTUnwrap(session.lineOpeningPreview).cost
        XCTAssertEqual(session.lineDraftSummary?.text, "4 stops, back to the start · 1.2 km · about 6 min · \(price.moneyText)")

        let chinese = DemoWorld.make(in: .traditionalChinese)
        let zh = GameSession(world: chinese, language: .traditionalChinese)
        pick(ring.stops + [ring.stops[0]], in: zh)
        XCTAssertEqual(zh.lineDraftSummary?.text, "4 站（回到起點） · 1.2 km · 約 6 分 · \(price.moneyText)")
    }

    /// Under realistic rules nothing is bought with the line: no price.
    func testNoPriceWhenTheLineOpensForNothing() throws {
        let map = try blank(rules: .realistic)
        let session = GameSession(world: map.world, language: .english)
        pick([map.west, map.east], in: session)
        XCTAssertNil(session.lineOpeningPreview)
        XCTAssertEqual(session.lineDraftSummary?.text, "3 stops · 5.0 km · about 6 min")
        XCTAssertEqual(session.mapLineDraft?.caption, "3 stops · 5.0 km · about 6 min")
    }

    /// Decision 284: the platforms are on tracks that do not meet; and a
    /// station with no platform. The line says which.
    func testTheMainProblemTakesTheLinesPlace() throws {
        let map = try blank()
        let apart = GameSession(world: map.world, language: .traditionalChinese)
        pick([map.west, map.apart], in: apart)
        XCTAssertEqual(apart.lineDraftSummary, LineDraftSummary(text: "West 和 Apart 的月台不在相連的軌道上", isProblem: true))
        XCTAssertTrue(try XCTUnwrap(apart.mapLineDraft?.caption).hasPrefix("West 和 Apart 的月台不在相連的軌道上"))

        let english = GameSession(world: map.world, language: .english)
        pick([map.west, map.apart], in: english)
        XCTAssertEqual(english.lineDraftSummary?.text, "The platforms of West and Apart are not on joined track")

        let bare = GameSession(world: map.world, language: .english)
        pick([map.west, map.bare], in: bare)
        XCTAssertEqual(bare.lineDraftSummary, LineDraftSummary(text: "Bare has no platform yet", isProblem: true))
        bare.removeLastLineDraftStop()
        XCTAssertEqual(bare.lineDraftSummary?.isProblem, false, "undoing the pick takes the problem away")
    }

    /// The figures are worked out once for a draft, not at every tick:
    /// they change when the draft or the world does.
    func testTheLineFollowsTheDraftAndTheTrack() throws {
        let map = try blank()
        let session = GameSession(world: map.world, language: .english)
        pick([map.west, map.centre], in: session)
        XCTAssertTrue(try XCTUnwrap(session.lineDraftSummary?.text).hasPrefix("2 stops · 2.5 km · "))
        session.selectStation(map.east)
        session.addSelectedStationToLineDraft()
        XCTAssertTrue(try XCTUnwrap(session.lineDraftSummary?.text).hasPrefix("3 stops · 5.0 km · "))
        session.clearLineDraft()
        XCTAssertNil(session.lineDraftSummary)
    }

    // MARK: - Taiwan

    /// The same layout on a real map of Taiwan, round Taipei.
    func testOnARealMapOfTaiwan() throws {
        let world = GameWorld.newGame(anchor: RealWorldPlace.standard.anchor, rules: .simple)
        XCTAssertNotNil(RealWorldFrame(world: world))
        let map = try layout(world, names: ["萬華", "台北", "松山", "中正紀念堂", "大安"])
        let session = GameSession(world: map.world, language: .traditionalChinese)
        session.startPickingLineStops(announces: false)
        XCTAssertEqual(session.lineDraftSummary?.text, "點路線的第一站")
        pick([map.west], in: session)
        XCTAssertEqual(session.lineDraftSummary?.text, "1 站 · 點路線的下一站")
        session.selectStation(map.east)
        session.addSelectedStationToLineDraft()
        let price = try XCTUnwrap(session.lineOpeningPreview).cost
        XCTAssertEqual(session.lineDraftSummary?.text, "3 站 · 5.0 km · 約 6 分 · \(price.moneyText)")
        session.selectStation(map.west)
        session.addSelectedStationToLineDraft()
        XCTAssertTrue(try XCTUnwrap(session.lineDraftSummary?.text).hasPrefix("3 站（回到起點） · 10.1 km · 約 "))

        let apart = GameSession(world: map.world, language: .traditionalChinese)
        pick([map.centre, map.apart], in: apart)
        XCTAssertEqual(apart.lineDraftSummary, LineDraftSummary(text: "台北 和 中正紀念堂 的月台不在相連的軌道上", isProblem: true))
        let bare = GameSession(world: map.world, language: .traditionalChinese)
        pick([map.bare, map.centre], in: bare)
        XCTAssertEqual(bare.lineDraftSummary?.text, "大安 還沒有月台")
    }
}
