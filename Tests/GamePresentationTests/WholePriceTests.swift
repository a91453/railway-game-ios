import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 245 (a player's report: the warning said 「需要 $124,397，目前只有
/// $19,256」 with $128,480 in hand, and ✓ showed no price): a build of
/// several steps is tried on a copy of the world, and GameCore refuses
/// the first step the cash left after the others does not cover. The
/// preview and the refusal say the whole build's price against the cash
/// the player has, name what is being built, and leave the world as it
/// was; ✓ shows that price, and it is what building it takes.
@MainActor
final class WholePriceTests: XCTestCase {
    /// `world` with `cash` in hand and nothing else changed.
    private func world(_ world: GameWorld, cash: Money) throws -> GameWorld {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var economy = try XCTUnwrap(json["economy"] as? [String: Any])
        economy["balance"] = cash.amount
        json["economy"] = economy
        return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// With plenty of cash, what the preview prices is what the build
    /// takes (✓'s price); with a dollar less than that, the preview and
    /// the refusal say the whole price and the cash in hand, ✓ still shows
    /// the price, and the world is left as it was. `action` names the
    /// build as the refusal does.
    private func assertWholePrice(
        of base: GameWorld, action: String,
        setUp: (GameSession) -> Void,
        preview: (GameSession) -> (cost: Money?, problem: String?),
        build: (GameSession) -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let rich = GameSession(world: try world(base, cash: Money(1_000_000_000_000)))
        setUp(rich)
        let shown = preview(rich)
        XCTAssertNil(shown.problem, shown.problem ?? "", file: file, line: line)
        let price = try XCTUnwrap(shown.cost, file: file, line: line)
        XCTAssertGreaterThan(price, Money(1), file: file, line: line)
        let before = rich.world.economy.balance
        build(rich)
        XCTAssertEqual(rich.message?.kind, .success, rich.message?.text ?? "", file: file, line: line)
        XCTAssertEqual(before - rich.world.economy.balance, price, "✓'s price is what it takes", file: file, line: line)

        let cash = price - Money(1)
        let poor = GameSession(world: try world(base, cash: cash))
        setUp(poor)
        let (required, available) = Money.shortfallTexts(required: price, available: cash)
        let text = "Not enough cash to \(action): it costs \(required) and you have \(available)."
        let refused = preview(poor)
        XCTAssertEqual(refused.cost, price, "✓ shows the whole price", file: file, line: line)
        XCTAssertEqual(refused.problem, text, file: file, line: line)
        let unchanged = poor.world
        build(poor)
        XCTAssertEqual(poor.world, unchanged, "all or nothing", file: file, line: line)
        XCTAssertEqual(poor.message, StatusMessage(kind: .failure, text: text, fundsNeeded: price), file: file, line: line)
    }

    // MARK: - Track

    /// Decision 204: the track and its parallel, two stretches.
    func testADoubleTrackSaysItsWholePrice() throws {
        let base = try makeWorld(width: 40_960, height: 20_480, balance: 10_000_000, speed: .paused)
        try assertWholePrice(of: base, action: "lay this track", setUp: { session in
            session.selectTool(.network)
            session.networkBuildsDouble = true
            session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
            session.tapNetwork(at: PlanPoint(x: 18_432, y: 10_240), reach: 16)
        }, preview: { ($0.networkPreview?.cost, $0.networkPreview?.problem) }, build: { $0.buildNetworkTrack() })
    }

    /// Decision 204, later: a double track from the end of one carries a
    /// crossover where it joins, a third stretch.
    func testADoubleTracksCrossoversAreInItsPrice() throws {
        var base = try makeWorld(width: 40_960, height: 16_384, balance: 10_000_000, speed: .paused)
        let west = try base.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try base.buildTrackNode(at: WorldCoordinate(x: 5_120, y: 8_192))
        try base.buildTrackEdge(from: west, to: east)
        try assertWholePrice(of: base, action: "lay this track", setUp: { session in
            session.selectTool(.network)
            session.networkBuildsDouble = true
            session.networkDoubleSide = .left
            session.tapNetwork(at: PlanPoint(x: 5_120, y: 8_192), reach: 16)
            session.tapNetwork(at: PlanPoint(x: 18_432, y: 8_192), reach: 16)
        }, preview: { session in
            XCTAssertEqual(session.networkDraftPreview?.preview.crossovers.count, 1, "it joins with a crossover")
            return (session.networkPreview?.cost, session.networkPreview?.problem)
        }, build: { $0.buildNetworkTrack() })
    }

    /// An X crossover: four halves.
    func testAnXCrossoverSaysItsWholePrice() throws {
        var base = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        for y in [Int64(4_096), 4_416] {
            let west = try base.buildTrackNode(at: WorldCoordinate(x: 1_024, y: y))
            let east = try base.buildTrackNode(at: WorldCoordinate(x: 31_744, y: y))
            try base.buildTrackEdge(from: west, to: east)
        }
        try assertWholePrice(of: base, action: "build this crossover", setUp: { session in
            session.selectTool(.network)
            session.networkBuildsScissors = true
            session.tapNetwork(at: PlanPoint(x: 10_240, y: 4_096), reach: 256)
            session.tapNetwork(at: PlanPoint(x: 16_384, y: 4_416), reach: 256)
        }, preview: { ($0.networkPreview?.cost, $0.networkPreview?.problem) }, build: { $0.buildNetworkTrack() })
    }

    // MARK: - Beside a station's track

    /// A straight single track 480 m long with stations at its ends.
    private func singleTrack() throws -> GameWorld {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 29_696, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 4_096)
        try world.addTrackPlatform(east, on: edge, from: 26_624, to: 29_696)
        return world
    }

    /// Three stretches and a signal station.
    func testAPassingLoopSaysItsWholePrice() throws {
        try assertWholePrice(of: try singleTrack(), action: "build this passing loop", setUp: { session in
            session.selectTool(.network)
            session.setNetworkMode(.passingLoop)
            session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        }, preview: { ($0.networkLoopPreview?.cost, $0.networkLoopPreview?.problem) }, build: { $0.addPassingLoop() })
    }

    /// Sidings, the ladder joining them and the depot.
    func testADepotSaysItsWholePrice() throws {
        var base = try makeWorld(width: 65_536, height: 16_384, balance: 10_000_000, speed: .paused)
        let a = try base.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try base.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 8_192))
        try base.buildTrackEdge(from: a, to: b)
        try assertWholePrice(of: base, action: "build this depot", setUp: { session in
            session.selectTool(.network)
            session.setNetworkMode(.depot)
            session.tapNetwork(at: PlanPoint(x: 16_400, y: 8_200), reach: 64)
        }, preview: { ($0.networkDepotPreview?.cost, $0.networkDepotPreview?.problem) }, build: { $0.addDepotYard() })
    }

    /// Three stretches beside the platform.
    func testAPlatformTrackSaysItsWholePrice() throws {
        var base = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .paused)
        let west = try base.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let east = try base.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try base.buildTrackEdge(from: west, to: east)
        let station = try base.buildStation(named: "Middle", at: PlanPoint(x: 16_384, y: 8_704)).id
        try base.addTrackPlatform(station, on: edge, from: 12_288, to: 18_432)
        let platform = try XCTUnwrap(base.trackPlatforms(of: station).first)
        try assertWholePrice(of: base, action: "add this platform track", setUp: { _ in }, preview: { session in
            let preview = session.platformTrackPreview(beside: platform, layout: .side, side: .left)
            let choice = session.platformTrackMenuChoices(beside: platform).first { $0.id == PlatformTrackPlacement(layout: .side, side: .left) }
            XCTAssertEqual(choice?.detail, preview.problem ?? preview.cost.map { "Costs \($0.moneyText)" }, "the menu says why")
            return preview
        }, build: { $0.addPlatformTrack(beside: platform, layout: .side, side: .left) })
    }

    // MARK: - A new station's platform

    /// Levelling a stretch on a grade, then the station (#596's case): ✓'s
    /// price is what the two take, and short of it the refusal says it.
    func testANewStationsPlatformOnAGradeSaysItsWholePrice() throws {
        var world = GameWorld(
            bounds: try WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(100_000_000), costs: testCosts),
            clock: GameClock(speed: .paused)
        )
        let side = GroundBlock.side
        let heights = (0..<side).flatMap { _ in (0..<side).map { Int16($0 == 0 ? 10 : 15) } }
        try world.setGround([GroundBlock(block: LandBlock(row: 0, column: 0), heights: heights)!])
        let laying = GameSession(world: world)
        laying.selectTool(.network)
        laying.tapNetwork(at: PlanPoint(x: 1_024, y: 2_048), reach: 16)
        laying.tapNetwork(at: PlanPoint(x: 17_408, y: 2_048), reach: 16)
        laying.buildNetworkTrack()
        XCTAssertEqual(laying.message?.kind, .success, laying.message?.text ?? "")
        try assertWholePrice(of: laying.world, action: "build station “Dazhi” and its platform", setUp: { session in
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            session.tapNetwork(at: PlanPoint(x: 9_216, y: 2_048), reach: 16)
            session.stationName = "Dazhi"
        }, preview: { session in
            XCTAssertNotNil(session.networkPlatformLevelling?.cost, "levelled first")
            // ✓ asks and GameCore says: the problem is the refusal's.
            return (session.networkPlatformCost, session.world.economy.canAfford(session.networkPlatformCost ?? .zero) ? nil : {
                let price = session.networkPlatformCost ?? .zero
                let (required, available) = Money.shortfallTexts(required: price, available: session.world.economy.balance)
                return "Not enough cash to build station “Dazhi” and its platform: it costs \(required) and you have \(available)."
            }())
        }, build: { $0.addNetworkPlatform() })
    }

    // MARK: - Buildings and purchases

    func testABuildingSaysItsPrice() throws {
        var base = try makeWorld(width: 20_480, height: 20_480, balance: 100_000_000)
        base.setEconomyMode(.management)
        try assertWholePrice(of: base, action: "put up this building", setUp: { session in
            session.selectTool(.building)
            _ = session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 500)
        }, preview: { ($0.buildingPreview?.cost, $0.buildingPreview?.problem) }, build: { _ = $0.confirmBuilding() })
    }

    /// A purchase of one step, with the price it shows.
    func testTheStationsShopsSayTheirPrice() throws {
        var base = try makeWorld(width: 20_480, height: 20_480, balance: 100_000_000)
        let station = try base.buildStation(named: "Taipei", at: PlanPoint(x: 10_000, y: 10_000)).id
        let price = StationCommerceLevel.convenienceStore.price
        try assertWholePrice(of: base, action: "build the station's shops", setUp: { _ in }, preview: { session in
            let short = !session.world.economy.canAfford(price)
            let (required, available) = Money.shortfallTexts(required: price, available: session.world.economy.balance)
            return (price, short ? "Not enough cash to build the station's shops: it costs \(required) and you have \(available)." : nil)
        }, build: { $0.buildNextStationCommerce(at: station) })
    }
}
