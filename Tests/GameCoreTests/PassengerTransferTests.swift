import Foundation
@testable import GameCore
import XCTest

final class PassengerTransferTests: XCTestCase {
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let c = StationID(rawValue: 3)

    private func world() throws -> GameWorld {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000)
        let track = TestLine(tiles: 7)
        try track.build(in: &world)
        for (name, x) in [("A", 1), ("B", 3), ("C", 5)] {
            try track.buildStation(named: name, beside: x, at: 1, in: &world)
        }
        let first = try world.createLine(named: "First", stops: [a, b]).id
        let second = try world.createLine(named: "Second", stops: [b, c]).id
        for line in [first, second] {
            try world.setLineServiceWindow(line, to: .allDay)
            try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        }
        let one = try world.purchaseTrain(named: "One").id
        let two = try world.purchaseTrain(named: "Two").id
        try world.placeTrain(one, at: track.at(1, facingEast: true))
        try world.placeTrain(two, at: track.at(3, facingEast: true))
        try world.setTrainMovementRate(one, to: 1024)
        try world.setTrainMovementRate(two, to: 1024)
        try world.assignTrain(one, to: first)
        try world.assignTrain(two, to: second)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 0))
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    func testPassengerChangesTrainsAndOriginLedgerStaysConserved() throws {
        var world = try world()
        let route = try XCTUnwrap(world.passengerRoutes(from: a, to: c).first)
        XCTAssertEqual(route.legs.map(\.from), [a, b])
        let journey = try XCTUnwrap(PassengerJourney(origin: a, route: route))
        let origin = try XCTUnwrap(world.passengers.firstIndex { $0.station == a })
        world.passengers[origin].release(5, along: journey, at: world.clock.now)

        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: TrainID(rawValue: 1)).map(\.count), [5])
        try world.advance(ticks: 1)
        XCTAssertEqual(world.riders(of: TrainID(rawValue: 1)), [])
        let transfer = try XCTUnwrap(world.waitingPassengers(at: b).first)
        XCTAssertEqual(transfer.journey?.origin, a)
        XCTAssertEqual(transfer.journey?.current, 1)
        XCTAssertEqual(transfer.count, 5)
        XCTAssertGreaterThan(transfer.readyAt!, world.clock.now)
        XCTAssertEqual(world.passengerLedger(of: a).waiting, 5)

        try world.advance(ticks: 15)
        let ledger = world.passengerLedger(of: a)
        XCTAssertEqual(ledger.released, 5)
        XCTAssertEqual(ledger.arrived, 5)
        XCTAssertEqual(ledger.waiting + ledger.riding + ledger.overflowed + ledger.abandoned, 0)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
    }

    func testNetworkDemandUsesRoutesAndBatchMatchesMinuteSteps() throws {
        var batched = try world()
        try batched.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try batched.setStationDemand(c, to: StationDemand(kind: .office, dailyTrips: 1_000))
        var stepped = batched

        try batched.advance(ticks: 30)
        for _ in 0..<30 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        let ledger = batched.passengerLedger(of: a)
        XCTAssertGreaterThan(ledger.released, 0)
        XCTAssertEqual(ledger.released,
            ledger.waiting + ledger.riding + ledger.arrived + ledger.overflowed + ledger.abandoned)
        XCTAssertTrue(batched.passengers.flatMap(\.waiting).allSatisfy { $0.journey != nil })
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched)), batched)
    }
}
