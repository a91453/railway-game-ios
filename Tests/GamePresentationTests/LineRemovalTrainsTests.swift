import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 327: removing a line sells its trains, so its
/// platforms and track can be taken down after it; a train left on the
/// track on no line is named where it is in the way, and is sold where it
/// stands.
@MainActor
final class LineRemovalTrainsTests: XCTestCase {
    private static let line = LineID(rawValue: 1)

    /// Decision 137's line between the first two towns (seed 1), its one
    /// train out on a trip, under traffic control as in a new game.
    private func runningLine() throws -> GameWorld {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.economy.earn(Money(10_000_000_000))
        try world.advance(ticks: 30)
        return world
    }

    /// Every platform, then every edge, through the network tool's
    /// commands: what refused them.
    private func demolishAll(_ session: GameSession) -> [StatusMessage] {
        var refusals: [StatusMessage] = []
        for platform in session.world.network.platforms {
            session.removeNetworkPlatform(platform)
            if let message = session.message, message.kind == .failure { refusals.append(message) }
        }
        for edge in session.world.network.edges {
            session.networkEdgePoint = NetworkEdgePoint(edge: edge.id, distance: 0)
            session.removeNetworkEdge()
            if let message = session.message, message.kind == .failure { refusals.append(message) }
        }
        return refusals
    }

    /// The player's report (2026-10-21): with the line removed and its last
    /// trip over, its platforms and track could not be taken down. Now
    /// the line's train is sold with it, at its quote, and nothing is in
    /// the way.
    func testRemovingALineSellsItsTrains() throws {
        let world = try runningLine()
        let train = try XCTUnwrap(world.line(id: Self.line)?.assignedTrains.first)
        XCTAssertNotNil(world.train(id: train)?.execution, "out on a trip")
        let quote = world.trainSaleQuote(train)
        XCTAssertGreaterThan(quote, .zero)

        let session = GameSession(world: world)
        session.selectLine(Self.line)
        let sale = try XCTUnwrap(session.selectedLineRemovalSale)
        XCTAssertEqual(sale.trains, 1)
        XCTAssertEqual(sale.proceeds, quote)
        session.removeSelectedLine()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertNil(session.world.line(id: Self.line))
        XCTAssertNil(session.world.train(id: train), "sold with the line")
        XCTAssertEqual(session.world.economy.balance, world.economy.balance + quote)
        XCTAssertEqual(session.commandLog.entries.last?.refused, false)

        XCTAssertEqual(demolishAll(session).map(\.text), [])
        XCTAssertTrue(session.world.network.edges.isEmpty)
    }

    /// A line with no trains says so and removes only the line.
    func testRemovingALineWithNoTrains() throws {
        var world = try runningLine()
        let train = try XCTUnwrap(world.line(id: Self.line)?.assignedTrains.first)
        try world.unassignTrain(train)
        let session = GameSession(world: world)
        session.selectLine(Self.line)
        XCTAssertEqual(session.selectedLineRemovalSale?.trains, 0)
        session.removeSelectedLine()
        XCTAssertEqual(session.message?.text, "Removed Line 1.")
        XCTAssertNotNil(session.world.train(id: train))
    }

    /// A train left on the track on no line (a save from before decision
    /// 327, or one taken off its line) holds its track for good: the
    /// refusal names it and offers it for sale, and selling it there
    /// clears the way.
    func testATrainInTheWayIsNamedAndSoldWhereItStands() throws {
        var world = try runningLine()
        let train = try XCTUnwrap(world.line(id: Self.line)?.assignedTrains.first)
        try world.removeLine(Self.line)
        try world.advance(ticks: 1_440)
        XCTAssertNil(world.train(id: train)?.execution, "its last trip over")
        XCTAssertNotNil(world.train(id: train)?.position, "still on the track")

        let session = GameSession(world: world)
        let refusals = demolishAll(session)
        XCTAssertFalse(refusals.isEmpty, "before the sale the train is in the way")
        for refusal in refusals {
            XCTAssertEqual(refusal.sellableTrain, train)
            XCTAssertEqual(refusal.text, "Train 1 is standing here with no line and is in the way. Sell it to clear the track.")
        }

        XCTAssertFalse(session.world.canSellTrain(train), "on the track")
        XCTAssertTrue(session.world.canSellTrainWhereItStands(train))
        let balance = session.world.economy.balance
        let quote = session.world.trainSaleQuote(train)
        session.sellTrain(train)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertNil(session.world.train(id: train))
        XCTAssertEqual(session.world.economy.balance, balance + quote)
        XCTAssertEqual(demolishAll(session).map(\.text), [])
        XCTAssertTrue(session.world.network.edges.isEmpty)
    }

    /// A train on a line is not sold where it stands: removing the line, or
    /// taking it off the line, comes first. A running train's refusal
    /// names no train to sell.
    func testATrainOnALineIsNotSold() throws {
        let world = try runningLine()
        let train = try XCTUnwrap(world.line(id: Self.line)?.assignedTrains.first)
        XCTAssertFalse(world.canSellTrainWhereItStands(train))
        let session = GameSession(world: world)
        session.sellTrain(train)
        XCTAssertEqual(session.message?.kind, .failure)
        XCTAssertNil(session.message?.sellableTrain)
        XCTAssertEqual(session.world, world)

        let refusals = demolishAll(session)
        XCTAssertFalse(refusals.isEmpty)
        XCTAssertTrue(refusals.allSatisfy { $0.sellableTrain == nil })
    }
}
