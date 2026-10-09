import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 113: a dot on the route strip for each of a line's
/// trains on a trip, at the stop it calls at or between the two it runs
/// between, as far as its run's time has gone.
final class LineTrainDotsTests: XCTestCase {
    func testATrainsDotFollowsItsTripThereAndBack() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .x10)
        let track = TestLine(tiles: 7, row: 1)
        try track.build(in: &world)
        let alpha = try track.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let beta = try track.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        let gamma = try track.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        let main = try world.createLine(named: "Main", stops: [alpha, beta, gamma]).id
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: track.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)
        XCTAssertEqual(world.lineTrainDots(main), [], "no trip yet")
        XCTAssertEqual(world.lineTrainDots(LineID(rawValue: 99)), [])

        var between = 0, calling = 0, outbound = 0, inbound = 0
        var last: Double?
        for _ in 0..<7_200 {
            try world.advance(ticks: 1)
            let dots = world.lineTrainDots(main)
            guard let execution = world.train(id: train.id)?.execution else {
                XCTAssertEqual(dots, [], "waiting for its next trip")
                if last != nil { break }
                continue
            }
            let dot = try XCTUnwrap(dots.first)
            XCTAssertEqual(dots.count, 1)
            XCTAssertEqual(dot.train, train.id)
            XCTAssertTrue((0...2).contains(dot.position), "\(dot.position)")
            switch execution {
            case .waitingAtStop:
                XCTAssertEqual(dot.position, dot.position.rounded(), "at a stop")
                calling += 1
            case .travellingToStop:
                if dot.position != dot.position.rounded() { between += 1 }
                if let last {
                    // Never back the way it came within a run.
                    XCTAssertTrue(dot.isOutbound ? dot.position >= last - 1e-9 : dot.position <= last + 1e-9, "\(last) → \(dot.position)")
                }
            }
            if dot.isOutbound { outbound += 1 } else { inbound += 1 }
            last = dot.position
        }
        XCTAssertGreaterThan(between, 0, "a dot between two stops")
        XCTAssertGreaterThan(calling, 0, "a dot at a stop")
        XCTAssertGreaterThan(outbound, 0)
        XCTAssertGreaterThan(inbound, 0, "and on the way back")
    }
}
