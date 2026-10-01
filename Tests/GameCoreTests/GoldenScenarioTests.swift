import Foundation
import GameCore
import XCTest

/// Runs every checked-in scenario in `GoldenScenarios/` against GameCore and
/// compares the outcome with the expectations committed in the fixture.
///
/// The fixtures are the portable behavior contract: a port of GameCore to
/// another language must reproduce the same outcomes from the same files.
final class GoldenScenarioTests: XCTestCase {
    func testGoldenScenariosMatchCommittedExpectations() throws {
        let urls = try GoldenScenarioFixtures.urls()
        XCTAssertFalse(urls.isEmpty, "No fixtures in \(GoldenScenarioFixtures.directory.path)")

        for url in urls {
            let scenario: GoldenScenario
            do {
                scenario = try GoldenScenario.decode(Data(contentsOf: url))
            } catch {
                XCTFail("\(url.lastPathComponent): \(error)")
                continue
            }
            for difference in scenario.differences() {
                XCTFail("\(url.lastPathComponent): \(difference)")
            }
        }
    }

    /// ASCII only, and numbers only as plain integers every JSON reader
    /// represents exactly.
    func testFixturesUsePortableJSON() throws {
        for url in try GoldenScenarioFixtures.urls() {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.unicodeScalars.allSatisfy(\.isASCII), "\(url.lastPathComponent) is not ASCII")
            XCTAssertEqual(GoldenScenarioFixtures.nonPortableNumbers(in: text), [], url.lastPathComponent)
        }
    }

    // MARK: - The mechanism itself

    /// A golden test that cannot fail protects nothing: changing a committed
    /// expectation in any fixture must be reported.
    func testChangedExpectationsAreReported() throws {
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            XCTAssertEqual(committed.differences(), [], name)

            var wrongOutcome = committed
            let first = try XCTUnwrap(committed.steps.firstIndex { if case .command = $0 { true } else { false } }, name)
            if case .command(let command, let expect) = committed.steps[first] {
                wrongOutcome.steps[first] = .command(command, expect: expect == .ok ? .rejected(.invalidName) : .ok)
            }
            XCTAssertEqual(wrongOutcome.differences().count, 1, name)

            var wrongBalance = committed
            wrongBalance.expectedFinalState.balance += 1
            XCTAssertEqual(wrongBalance.differences().count, 1, name)

            var wrongTime = committed
            wrongTime.expectedFinalState.gameMinutes += 1
            XCTAssertEqual(wrongTime.differences().count, 1, name)

            var extraTrain = committed
            extraTrain.expectedFinalState.trains.append(.init(id: 99, name: "Ghost", position: TrainPositionSummary(nil), movement: TrainMovementSummary(.idle), timetable: [], repeat: RepeatSummary(nil), execution: ExecutionSummary(nil), cars: 1, trail: [], trailEdges: [], reservation: []))
            XCTAssertEqual(extraTrain.differences().count, 1, name)

            var wrongTrafficControl = committed
            wrongTrafficControl.expectedFinalState.trafficControl.toggle()
            XCTAssertEqual(wrongTrafficControl.differences().count, 1, name)

            var extraPassengers = committed
            extraPassengers.expectedFinalState.passengers.append(
                PassengerSummary(station: 99, demand: nil, waiting: [], released: 1, arrived: 0, overflowed: 1, abandoned: 0, refused: 0)
            )
            XCTAssertEqual(extraPassengers.differences().count, 1, name)

            var extraRiders = committed
            extraRiders.expectedFinalState.riders.append(RiderSummary(train: 99, groups: []))
            XCTAssertEqual(extraRiders.differences().count, 1, name)

            var otherAccounts = committed
            otherAccounts.expectedFinalState.accounts.pending.fareTrips += 1
            XCTAssertEqual(otherAccounts.differences().count, 1, name)
        }
    }

    /// A station's expected annexes and a train's expected cars and body
    /// are compared exactly: one more, one fewer or another order is
    /// reported once.
    func testChangedStationFacilityExpectationsAreReported() throws {
        var annexCount = 0
        var trailCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, station) in committed.expectedFinalState.stations.enumerated() {
                if station.annexes.count > 1 { annexCount += 1 }
                var wrongAnnexes = [station.annexes + [PositionSummary(GridPosition(x: 99, y: 99))]]
                if station.annexes.count > 1 { wrongAnnexes += [Array(station.annexes.dropLast()), station.annexes.reversed()] }
                for wrong in wrongAnnexes {
                    var scenario = committed
                    scenario.expectedFinalState.stations[index].annexes = wrong
                    XCTAssertEqual(scenario.differences().count, 1, "\(name) station \(station.id) expecting \(wrong)")
                }
            }
            for (index, train) in committed.expectedFinalState.trains.enumerated() {
                if train.trail.count > 1 { trailCount += 1 }
                var scenario = committed
                scenario.expectedFinalState.trains[index].cars += 1
                XCTAssertEqual(scenario.differences().count, 1, "\(name) train \(train.id) with another car")
                var wrongTrails = [train.trail + [PositionSummary(GridPosition(x: 99, y: 99))]]
                if train.trail.count > 1 { wrongTrails += [Array(train.trail.dropLast()), train.trail.reversed()] }
                for wrong in wrongTrails {
                    scenario = committed
                    scenario.expectedFinalState.trains[index].trail = wrong
                    XCTAssertEqual(scenario.differences().count, 1, "\(name) train \(train.id) expecting \(wrong)")
                }
            }
        }
        XCTAssertGreaterThan(annexCount, 0, "No fixture expects a station of three tiles or more")
        XCTAssertGreaterThan(trailCount, 0, "No fixture expects a train body over two nodes or more")
    }

    /// A train's expected movement is compared exactly: another rate, cursor
    /// or continuation is reported once.
    func testChangedTrainMovementExpectationsAreReported() throws {
        var movingCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, train) in committed.expectedFinalState.trains.enumerated() {
                if train.movement.rate > 0 {
                    movingCount += 1
                }
                var wrongMovements: [TrainMovementSummary] = []
                var changed = train.movement
                changed.rate += 1
                wrongMovements.append(changed)
                changed = train.movement
                changed.cursor += 1
                wrongMovements.append(changed)
                changed = train.movement
                changed.continuation.append(PositionSummary(GridPosition(x: 0, y: 0)))
                wrongMovements.append(changed)
                for wrong in wrongMovements {
                    var scenario = committed
                    scenario.expectedFinalState.trains[index].movement = wrong
                    XCTAssertEqual(scenario.differences().count, 1, "\(name) train \(train.id) expecting \(wrong)")
                }
            }
        }
        XCTAssertGreaterThan(movingCount, 0, "No fixture expects a train with a rate")
    }

    /// A train's expected timetable is compared exactly, in order: an extra,
    /// missing or repeated stop, another station, a time one minute off, a
    /// stop that turns the train round or not, or the same stops in another
    /// order is reported once.
    func testChangedTrainTimetableExpectationsAreReported() throws {
        var scheduledCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, train) in committed.expectedFinalState.trains.enumerated() {
                if train.timetable.count > 1 {
                    scheduledCount += 1
                }
                for wrong in Self.wrongTimetables(for: train.timetable) {
                    var scenario = committed
                    scenario.expectedFinalState.trains[index].timetable = wrong
                    XCTAssertEqual(scenario.differences().count, 1, "\(name) train \(train.id) expecting \(wrong)")
                }
            }
        }
        XCTAssertGreaterThan(scheduledCount, 0, "No fixture expects a train with a timetable of more than one stop")
    }

    /// A train's expected service is compared exactly: inactive instead of
    /// active (or the reverse), the other phase, another stop, or another
    /// cycle is reported once.
    func testChangedTrainExecutionExpectationsAreReported() throws {
        var activeCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, train) in committed.expectedFinalState.trains.enumerated() {
                if train.execution.execution != nil {
                    activeCount += 1
                }
                for wrong in Self.wrongExecutions(for: train.execution.execution) {
                    var scenario = committed
                    scenario.expectedFinalState.trains[index].execution = ExecutionSummary(wrong)
                    XCTAssertEqual(scenario.differences().count, 1, "\(name) train \(train.id) expecting \(String(describing: wrong))")
                }
            }
        }
        XCTAssertGreaterThan(activeCount, 0, "No fixture expects a train with an active service")
    }

    /// Services that differ from `execution` in one way each.
    private static func wrongExecutions(for execution: TimetableExecution?) -> [TimetableExecution?] {
        switch execution {
        case nil:
            return [.waitingAtStop(0), .travellingToStop(1)]
        case .waitingAtStop(let stop, let cycle)?:
            return [nil, .travellingToStop(stop, cycle: cycle), .waitingAtStop(stop + 1, cycle: cycle), .waitingAtStop(stop, cycle: cycle + 1)]
        case .travellingToStop(let stop, let cycle)?:
            return [nil, .waitingAtStop(stop, cycle: cycle), .travellingToStop(stop + 1, cycle: cycle), .travellingToStop(stop, cycle: cycle + 1)]
        }
    }

    /// Timetables that differ from `stops` in one way each.
    private static func wrongTimetables(for stops: [StopSummary]) -> [[StopSummary]] {
        var wrong: [[StopSummary]] = [stops + [StopSummary(ScheduledStop(station: StationID(rawValue: 99), arrival: .zero, departure: .zero))]]
        guard let first = stops.first else { return wrong }
        wrong.append(Array(stops.dropLast()))
        wrong.append([first] + stops)
        var changed = stops
        changed[0].station += 1
        wrong.append(changed)
        changed = stops
        changed[0].arrival += 1
        wrong.append(changed)
        changed = stops
        changed[stops.count - 1].departure += 1
        wrong.append(changed)
        changed = stops
        changed[0].reverse.toggle()
        wrong.append(changed)
        if stops.count > 1 {
            wrong.append(stops.reversed())
        }
        return wrong
    }

    /// A train's expected position is compared exactly: unplaced instead of
    /// placed (or the reverse), the other heading, the other end of a link,
    /// or an offset one unit off is reported once.
    func testChangedTrainPositionExpectationsAreReported() throws {
        var placedCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, train) in committed.expectedFinalState.trains.enumerated() {
                var wrongPositions: [TrainPosition?] = []
                switch train.position.position {
                case nil:
                    wrongPositions = [.atNode(GridPosition(x: 0, y: 0), heading: .north)]
                case .atNode(let tile, let heading)?:
                    placedCount += 1
                    wrongPositions = [nil, .atNode(tile, heading: heading.opposite)]
                case .onLink(let from, let to, let offset)?:
                    placedCount += 1
                    wrongPositions = [nil, .onLink(from: to, to: from, offset: offset), .onLink(from: from, to: to, offset: offset + 1)]
                case .onEdge(let traversal, let offset)?:
                    placedCount += 1
                    wrongPositions = [nil, .onEdge(traversal.reversed, offset: offset), .onEdge(traversal, offset: offset + 1)]
                }
                for wrong in wrongPositions {
                    var changed = committed
                    changed.expectedFinalState.trains[index].position = TrainPositionSummary(wrong)
                    XCTAssertEqual(changed.differences().count, 1, "\(name) train \(train.id) expecting \(String(describing: wrong))")
                }
            }
        }
        XCTAssertGreaterThan(placedCount, 0, "No fixture expects a placed train")
    }

    /// Every observation's expectation is compared exactly: a flipped answer,
    /// a missing, extra or repeated neighbour, the same neighbours in another
    /// order, or any change to a train's position or movement is reported at
    /// that step and nowhere else.
    func testChangedObservationExpectationsAreReported() throws {
        var observationCount = 0
        var orderedAnswerCount = 0
        var trainAnswerCount = 0
        var routeAnswerCount = 0
        var platformAnswerCount = 0
        var stationRouteCount = 0
        var sharedStopCount = 0
        var timetableAnswerCount = 0
        var executionAnswerCount = 0
        var journeyAnswerCount = 0
        var headwayAnswerCount = 0
        var sharedLoadCount = 0
        var patternAnswerCount = 0
        var turnoutExitCount = 0
        var sectionAnswerCount = 0
        var conflictAnswerCount = 0
        var doubleTrackCount = 0
        var longRouteCount = 0
        var wholeTrainCount = 0
        var platformTrackCount = 0
        var gradeCount = 0
        var curveAlignmentCount = 0
        var portalCount = 0
        var wholePlatformCount = 0
        var levelCount = 0
        var reservationCount = 0
        var holderCount = 0
        var tripCount = 0
        var demandCount = 0
        var queueCount = 0
        var overflowCount = 0
        var abandonCount = 0
        var rideCount = 0
        var refusalCount = 0
        var riderCount = 0
        var hourlyRevenueCount = 0
        var dailyCount = 0
        var distanceFareCount = 0
        var reportCount = 0
        for url in try GoldenScenarioFixtures.urls() {
            let name = url.lastPathComponent
            let committed = try GoldenScenario.decode(Data(contentsOf: url))
            for (index, step) in committed.steps.enumerated() {
                guard case .observe(let observation, let expect) = step else { continue }
                observationCount += 1
                if case .neighbors(let neighbors) = expect, neighbors.count > 1 {
                    orderedAnswerCount += 1
                }
                if case .train = expect {
                    trainAnswerCount += 1
                }
                if case .route(let nodes?) = expect, nodes.count > 1 {
                    routeAnswerCount += 1
                }
                if case .platforms(let platforms) = expect, !platforms.isEmpty {
                    platformAnswerCount += 1
                }
                if case .routeToStation = observation, case .route(let nodes?) = expect, nodes.count > 1 {
                    stationRouteCount += 1
                }
                if case .stations(let stations) = expect, stations.count > 1 {
                    sharedStopCount += 1
                }
                if case .timetable(let stops?) = expect, stops.count > 1 {
                    timetableAnswerCount += 1
                }
                if case .execution(let execution?) = expect, execution.execution != nil {
                    executionAnswerCount += 1
                }
                if case .journey(let journey?) = expect, journey.legs.count > 2 {
                    journeyAnswerCount += 1
                }
                if case .minutes(let minutes?) = expect, minutes > 0 {
                    headwayAnswerCount += 1
                }
                // A segment carrying two services, and one a later service
                // was cut back on.
                if case .loads(let loads?) = expect, loads.contains(where: { $0 > 0 && $0 < ServiceLine.segmentCapacity }), loads.contains(ServiceLine.segmentCapacity) {
                    sharedLoadCount += 1
                }
                switch observation {
                case .lineJourney(_, pattern: _?), .lineTrainsInService(_, _, pattern: _?), .lineHeadway(_, _, pattern: _?):
                    patternAnswerCount += 1
                default:
                    break
                }
                if case .exits(let exits) = expect, exits.count > 1 { turnoutExitCount += 1 }
                if case .sections(let sections) = expect, sections.count > 2 { sectionAnswerCount += 1 }
                if case .conflicts(let conflicts) = expect, !conflicts.isEmpty { conflictAnswerCount += 1 }
                if case .tracks(let count) = expect, count >= 2 { doubleTrackCount += 1 }
                if case .routeToStation(_, _, let cars) = observation, cars > 2, case .route(let nodes?) = expect, !nodes.isEmpty { longRouteCount += 1 }
                if case .wholeTrainStops = observation, case .stations(let stations) = expect, !stations.isEmpty { wholeTrainCount += 1 }
                if case .platformTracks(let tracks) = expect, tracks.count > 1, tracks.contains(where: { $0.count > 1 }) { platformTrackCount += 1 }
                if case .pose(let pose?) = expect, pose.rise != 0, pose.z != 0 { gradeCount += 1 }
                if case .alignment(let alignment?) = expect, alignment.segments.contains(where: { $0.kind == "transition" }) { curveAlignmentCount += 1 }
                if case .reservation = observation, case .resources(let resources) = expect, !resources.isEmpty { reservationCount += 1 }
                if case .holder(_?) = expect { holderCount += 1 }
                if case .trip(let trip?) = expect, trip.direction.direction == .inbound { tripCount += 1 }
                if case .demand(let daily, let hourly) = expect, daily > 0, hourly.filter({ $0 > 0 }).count > 1 { demandCount += 1 }
                if case .groups(let groups) = expect, Set(groups.map(\.destination)).count > 1, Set(groups.map(\.since)).count > 1 { queueCount += 1 }
                if case .ledger(let ledger) = expect, ledger.overflowed > 0 { overflowCount += 1 }
                if case .ledger(let ledger) = expect, ledger.abandoned > 0 { abandonCount += 1 }
                if case .ledger(let ledger) = expect, ledger.riding > 0, ledger.arrived > 0 { rideCount += 1 }
                if case .ledger(let ledger) = expect, ledger.refused > 0 { refusalCount += 1 }
                if case .riders(let riders) = expect, Set(riders.map(\.destination)).count > 1 { riderCount += 1 }
                if case .accounts(let accounts) = expect, accounts.ledger.contains(where: { $0.kind == "hourlyNet" && $0.breakdown[0].amount > 0 }) { hourlyRevenueCount += 1 }
                if case .accounts(let accounts) = expect, accounts.ledger.contains(where: { $0.kind == "dailyStaff" }) { dailyCount += 1 }
                if case .fare(let fare?) = expect, fare < 500 { distanceFareCount += 1 }
                if case .report(let report) = expect, report.previous.fareRevenue > 0 { reportCount += 1 }
                if case .nodes(let nodes) = expect, !nodes.isEmpty { portalCount += 1 }
                if case .trackPlatforms(let platforms) = expect, !platforms.isEmpty { wholePlatformCount += 1 }
                if case .levels(let levels) = expect, levels.contains(where: { $0.height != 0 }) { levelCount += 1 }
                for wrong in Self.wrongAnswers(for: expect) {
                    var changed = committed
                    changed.steps[index] = .observe(observation, expect: wrong)
                    let differences = changed.differences()
                    XCTAssertEqual(differences.count, 1, "\(name) steps[\(index)] expecting \(wrong)")
                    XCTAssertTrue(differences.first?.hasPrefix("steps[\(index)]: ") == true, "\(name) steps[\(index)]")
                }
            }
        }
        XCTAssertGreaterThan(observationCount, 0, "No fixture observes track connectivity")
        XCTAssertGreaterThan(orderedAnswerCount, 0, "No fixture pins the order of connected neighbours")
        XCTAssertGreaterThan(trainAnswerCount, 0, "No fixture observes a train")
        XCTAssertGreaterThan(routeAnswerCount, 0, "No fixture pins a route of more than one node")
        XCTAssertGreaterThan(platformAnswerCount, 0, "No fixture pins a station's platforms")
        XCTAssertGreaterThan(stationRouteCount, 0, "No fixture pins a route to a station of more than one node")
        XCTAssertGreaterThan(sharedStopCount, 0, "No fixture pins a train stopped at more than one station")
        XCTAssertGreaterThan(timetableAnswerCount, 0, "No fixture pins a timetable of more than one stop")
        XCTAssertGreaterThan(executionAnswerCount, 0, "No fixture observes an active service")
        XCTAssertGreaterThan(journeyAnswerCount, 0, "No fixture pins a line journey of more than two legs")
        XCTAssertGreaterThan(headwayAnswerCount, 0, "No fixture pins a line's headway")
        XCTAssertGreaterThan(sharedLoadCount, 0, "No fixture pins a line's segments filled by several services")
        XCTAssertGreaterThan(patternAnswerCount, 0, "No fixture observes a pattern")
        XCTAssertGreaterThan(turnoutExitCount, 0, "No fixture pins exits of more than one tile")
        XCTAssertGreaterThan(sectionAnswerCount, 0, "No fixture pins three sections or more")
        XCTAssertGreaterThan(conflictAnswerCount, 0, "No fixture pins a conflict")
        XCTAssertGreaterThan(doubleTrackCount, 0, "No fixture pins double track")
        XCTAssertGreaterThan(longRouteCount, 0, "No fixture pins a route for a long train")
        XCTAssertGreaterThan(wholeTrainCount, 0, "No fixture pins a train beside a station with its whole length")
        XCTAssertGreaterThan(platformTrackCount, 0, "No fixture pins two platform tracks, one of several tiles")
        XCTAssertGreaterThan(gradeCount, 0, "No fixture pins a pose on a slope")
        XCTAssertGreaterThan(curveAlignmentCount, 0, "No fixture pins a vertical curve")
        XCTAssertGreaterThan(portalCount, 0, "No fixture pins a tunnel portal")
        XCTAssertGreaterThan(wholePlatformCount, 0, "No fixture pins a whole train along a platform on the network")
        XCTAssertGreaterThan(levelCount, 0, "No fixture pins a platform off the ground")
        XCTAssertGreaterThan(reservationCount, 0, "No fixture pins a reservation")
        XCTAssertGreaterThan(holderCount, 0, "No fixture pins the train holding a route")
        XCTAssertGreaterThan(tripCount, 0, "No fixture pins an inbound passenger trip")
        XCTAssertGreaterThan(demandCount, 0, "No fixture pins a pair's trips spread over several hours")
        XCTAssertGreaterThan(queueCount, 0, "No fixture pins a queue of several destinations and minutes")
        XCTAssertGreaterThan(overflowCount, 0, "No fixture pins passengers turned away from a full station")
        XCTAssertGreaterThan(abandonCount, 0, "No fixture pins passengers who lost their line")
        XCTAssertGreaterThan(rideCount, 0, "No fixture pins passengers riding and arrived")
        XCTAssertGreaterThan(refusalCount, 0, "No fixture pins passengers refused by a full train")
        XCTAssertGreaterThan(riderCount, 0, "No fixture pins a train's riders for several destinations")
        XCTAssertGreaterThan(hourlyRevenueCount, 0, "No fixture pins an hour settled with fares")
        XCTAssertGreaterThan(dailyCount, 0, "No fixture pins a day's energy and staff")
        XCTAssertGreaterThan(distanceFareCount, 0, "No fixture pins a distance fare")
        XCTAssertGreaterThan(reportCount, 0, "No fixture pins a finance report with revenue")
    }

    private static func wrongAnswers(for answer: ObservationAnswer) -> [ObservationAnswer] {
        switch answer {
        case .connected(let connected):
            return [.connected(!connected)]
        case .neighbors(let neighbors):
            var wrong: [ObservationAnswer] = [.neighbors(neighbors + [GridPosition(x: 99, y: 99)])]
            if let first = neighbors.first {
                wrong.append(.neighbors(Array(neighbors.dropFirst())))
                wrong.append(.neighbors(neighbors + [first]))
            }
            if neighbors.count > 1 {
                wrong.append(.neighbors(neighbors.reversed()))
            }
            return wrong
        case .route(nil):
            return [.route([])]
        case .route(let nodes?):
            var wrong: [ObservationAnswer] = [.route(nil), .route(nodes + [GridPosition(x: 99, y: 99)])]
            if !nodes.isEmpty {
                wrong.append(.route(Array(nodes.dropLast())))
            }
            if nodes.count > 1 {
                wrong.append(.route(nodes.reversed()))
            }
            return wrong
        case .train(nil):
            return []
        case .train(let state?):
            return [.train(nil)] + wrongStates(for: state).map { .train($0) }
        case .platforms(let platforms):
            var wrong: [ObservationAnswer] = [.platforms(platforms + [GridPosition(x: 99, y: 99)])]
            if let first = platforms.first {
                wrong.append(.platforms(Array(platforms.dropFirst())))
                wrong.append(.platforms(platforms + [first]))
            }
            if platforms.count > 1 {
                wrong.append(.platforms(platforms.reversed()))
            }
            return wrong
        case .stations(let stations):
            var wrong: [ObservationAnswer] = [.stations(stations + [StationID(rawValue: 99)])]
            if let first = stations.first {
                wrong.append(.stations(Array(stations.dropFirst())))
                wrong.append(.stations(stations + [first]))
            }
            if stations.count > 1 {
                wrong.append(.stations(stations.reversed()))
            }
            return wrong
        case .timetable(nil):
            return []
        case .timetable(let stops?):
            return [.timetable(nil)] + wrongTimetables(for: stops.map(StopSummary.init)).map { .timetable($0.map(\.stop)) }
        case .execution(nil):
            return []
        case .execution(let execution?):
            return [.execution(nil)] + wrongExecutions(for: execution.execution).map { .execution(ExecutionSummary($0)) }
        case .level(let level):
            return ([nil] + ServiceLevel.allCases.map(Optional.some)).filter { $0 != level }.map { .level($0) }
        case .journey(nil):
            return []
        case .journey(let journey?):
            var wrong: [ObservationAnswer] = [.journey(nil)]
            var changed = journey
            changed.roundTripMinutes += 1
            wrong.append(.journey(changed))
            changed = journey
            changed.legs = Array(journey.legs.dropLast())
            wrong.append(.journey(changed))
            if let leg = journey.legs.first {
                changed = journey
                changed.legs[0].minutes = leg.minutes + 1
                wrong.append(.journey(changed))
                if let route = leg.route {
                    changed = journey
                    changed.legs[0].route = route + [PositionSummary(GridPosition(x: 99, y: 99))]
                    wrong.append(.journey(changed))
                }
                if let path = leg.path {
                    changed = journey
                    changed.legs[0].path?.distance = path.distance + 1
                    wrong.append(.journey(changed))
                    changed = journey
                    changed.legs[0].path?.end = path.end.map { $0 + 1 } ?? 1
                    wrong.append(.journey(changed))
                }
            }
            changed = journey
            changed.start = TrainPositionSummary(.atNode(GridPosition(x: 99, y: 99), heading: .north))
            wrong.append(.journey(changed))
            return wrong
        case .trains(let trains):
            return trains.map { [.trains(nil), .trains($0 + 1)] } ?? [.trains(0)]
        case .minutes(let minutes):
            return minutes.map { [.minutes(nil), .minutes($0 + 1)] } ?? [.minutes(0)]
        case .loads(nil):
            return [.loads([])]
        case .loads(let loads?):
            var wrong: [ObservationAnswer] = [.loads(nil), .loads(loads + [0])]
            if let first = loads.first {
                wrong.append(.loads([first + 1] + loads.dropFirst()))
            }
            return wrong
        case .exits(let exits):
            var wrong: [ObservationAnswer] = [.exits(exits + [GridPosition(x: 99, y: 99)])]
            if !exits.isEmpty { wrong.append(.exits(Array(exits.dropLast()))) }
            if exits.count > 1 { wrong.append(.exits(exits.reversed())) }
            return wrong
        case .resources(let resources):
            var wrong: [ObservationAnswer] = [.resources(resources + [.tile(GridPosition(x: 99, y: 99))])]
            if !resources.isEmpty { wrong.append(.resources([])) }
            return wrong
        case .conflicts(let conflicts):
            var wrong: [ObservationAnswer] = [.conflicts(conflicts + [TrackConflict(resource: .tile(GridPosition(x: 99, y: 99)), trains: [])])]
            if let first = conflicts.first {
                wrong.append(.conflicts([TrackConflict(resource: first.resource, trains: first.trains.dropLast())] + conflicts.dropFirst()))
            }
            return wrong
        case .sections(let sections):
            var wrong: [ObservationAnswer] = [.sections(Array(sections.dropLast()))]
            if let first = sections.first {
                wrong.append(.sections([TrackSection(nodes: first.nodes.reversed(), isLoop: first.isLoop)] + sections.dropFirst()))
                wrong.append(.sections([TrackSection(nodes: first.nodes, isLoop: !first.isLoop)] + sections.dropFirst()))
            }
            return wrong
        case .tracks(let count):
            return [.tracks(count + 1)]
        case .holder(nil):
            return [.holder(TrainID(rawValue: 1))]
        case .holder(let id?):
            return [.holder(nil), .holder(TrainID(rawValue: id.rawValue + 1))]
        case .trip(nil):
            return [.trip(TripSummary(PassengerTrip(line: LineID(rawValue: 1), direction: .outbound)))]
        case .trip(let trip?):
            var otherLine = trip
            otherLine.line += 1
            var otherWay = trip
            otherWay.direction = DirectionAlongLine(trip.direction.direction == .outbound ? .inbound : .outbound)
            return [.trip(nil), .trip(otherLine), .trip(otherWay)]
        case .demand(let daily, let hourly):
            var shifted = hourly
            shifted.append(shifted.removeFirst())
            var moved = hourly
            if let peak = hourly.indices.max(by: { hourly[$0] < hourly[$1] }), hourly[peak] > 0 {
                moved[peak] -= 1
                moved[(peak + 1) % 24] += 1
            }
            return [.demand(daily: daily + 1, hourly: hourly), .demand(daily: daily, hourly: shifted), .demand(daily: daily, hourly: moved)]
                .filter { $0 != .demand(daily: daily, hourly: hourly) }
        case .groups(let groups):
            var wrong: [ObservationAnswer] = [.groups(groups + [WaitingGroupSummary(WaitingGroup(
                line: LineID(rawValue: 9), direction: .outbound, destination: StationID(rawValue: 9), since: .zero, count: 1
            ))])]
            if let first = groups.first {
                var bigger = first
                bigger.count += 1
                var later = first
                later.since += 1
                wrong += [.groups(Array(groups.dropFirst())), .groups([bigger] + groups.dropFirst()), .groups([later] + groups.dropFirst())]
            }
            if groups.count > 1, groups.reversed() != groups { wrong.append(.groups(groups.reversed())) }
            return wrong
        case .ledger(let ledger):
            var wrong: [ObservationAnswer] = []
            for key in [\LedgerSummary.released, \.waiting, \.riding, \.arrived, \.overflowed, \.abandoned, \.refused] {
                var changed = ledger
                changed[keyPath: key] += 1
                wrong.append(.ledger(changed))
            }
            return wrong
        case .fare(let fare?):
            return [.fare(nil), .fare(fare + 1)]
        case .fare(nil):
            return [.fare(500)]
        case .accounts(let accounts):
            var wrong: [ObservationAnswer] = []
            var mode = accounts
            mode.mode = accounts.mode == "free" ? "management" : "free"
            var pending = accounts
            pending.pending.departures += 1
            wrong += [.accounts(mode), .accounts(pending)]
            if let first = accounts.ledger.first {
                var amount = accounts
                amount.ledger[0].amount = first.amount + 1
                var dropped = accounts
                dropped.ledger.removeFirst()
                wrong += [.accounts(amount), .accounts(dropped)]
            }
            if !accounts.days.isEmpty {
                var day = accounts
                day.days[0].staffCost += 1
                wrong.append(.accounts(day))
            }
            return wrong
        case .report(let report):
            var revenue = report
            revenue.current.fareRevenue += 1
            var previous = report
            previous.previous.index += 1
            return [.report(revenue), .report(previous)]
        case .riders(let riders):
            var wrong: [ObservationAnswer] = [.riders(riders + [RidingGroupSummary(RidingGroup(
                origin: StationID(rawValue: 9), destination: StationID(rawValue: 8), count: 1
            ))])]
            if let first = riders.first {
                var bigger = first
                bigger.count += 1
                wrong += [.riders(Array(riders.dropFirst())), .riders([bigger] + riders.dropFirst())]
            }
            if riders.count > 1, riders.reversed() != riders { wrong.append(.riders(riders.reversed())) }
            return wrong
        case .platformTracks(let tracks):
            var wrong: [ObservationAnswer] = [.platformTracks(tracks + [[GridPosition(x: 99, y: 99)]])]
            if let first = tracks.first {
                wrong.append(.platformTracks(Array(tracks.dropFirst())))
                wrong.append(.platformTracks([first.dropLast()] + tracks.dropFirst()))
            }
            if tracks.count > 1 { wrong.append(.platformTracks(tracks.reversed())) }
            return wrong
        case .edge(nil):
            return [.edge(EdgeInfoSummary(from: 1, to: 2, length: 1))]
        case .edge(let edge?):
            return [.edge(nil), .edge(EdgeInfoSummary(from: edge.from, to: edge.to, length: edge.length + 1)), .edge(EdgeInfoSummary(from: edge.to, to: edge.from, length: edge.length))]
        case .location(nil):
            return [.location(LocationSummary(TrackLocation(position: WorldCoordinate(x: 0, y: 0), direction: PlanVector(dx: 1, dy: 0))))]
        case .location(let location?):
            var moved = location
            moved.x += 1
            var turned = location
            turned.dx = -turned.dx
            return [.location(nil), .location(moved), .location(turned)]
        case .transitions(let traversals):
            var wrong: [ObservationAnswer] = [.transitions(traversals + [TrackTraversal(edge: .edge(99), direction: .forward)])]
            if !traversals.isEmpty { wrong.append(.transitions(Array(traversals.dropLast()))) }
            if traversals.count > 1 { wrong.append(.transitions(traversals.reversed())) }
            return wrong
        case .path(nil):
            return [.path([])]
        case .path(let path?):
            var wrong: [ObservationAnswer] = [.path(nil), .path(path + [TrackTraversal(edge: .edge(99), direction: .forward)])]
            if let first = path.first { wrong.append(.path([first.reversed] + path.dropFirst())) }
            return wrong
        case .points(let points):
            var wrong: [ObservationAnswer] = [.points(points + [WorldCoordinate(x: 0, y: 0)])]
            if let first = points.first {
                wrong.append(.points([WorldCoordinate(x: first.x + 1, y: first.y, z: first.z)] + points.dropFirst()))
                wrong.append(.points([WorldCoordinate(x: first.x, y: first.y, z: first.z + 1)] + points.dropFirst()))
                wrong.append(.points(Array(points.dropFirst())))
            }
            return wrong
        case .pose(nil):
            return [.pose(PoseSummary(TrackLocation(position: WorldCoordinate(x: 0, y: 0), direction: PlanVector(dx: 1, dy: 0))))]
        case .pose(let pose?):
            var raised = pose
            raised.z += 1
            var steeper = pose
            steeper.rise += 1
            var turned = pose
            turned.dx = -turned.dx
            return [.pose(nil), .pose(raised), .pose(steeper), .pose(turned)]
        case .alignment(nil):
            return [.alignment(AlignmentSummary(structure: .surface, segments: [], steepest: .level))]
        case .alignment(let alignment?):
            var wrong: [ObservationAnswer] = [.alignment(nil)]
            var changed = alignment
            changed.structure = StructureName(alignment.structure.structure == .tunnel ? .surface : .tunnel)
            wrong.append(.alignment(changed))
            changed = alignment
            changed.steepest.rise += 1
            wrong.append(.alignment(changed))
            changed = alignment
            changed.segments = Array(alignment.segments.dropLast())
            wrong.append(.alignment(changed))
            if let first = alignment.segments.first {
                changed = alignment
                changed.segments[0].end = first.end + 1
                wrong.append(.alignment(changed))
            }
            return wrong
        case .nodes(let nodes):
            var wrong: [ObservationAnswer] = [.nodes(nodes + [99])]
            if !nodes.isEmpty { wrong.append(.nodes(Array(nodes.dropLast()))) }
            return wrong
        case .trackPlatforms(let platforms):
            var wrong: [ObservationAnswer] = [.trackPlatforms(platforms + [platforms.first ?? PlatformSummary(TrackPlatform(station: StationID(rawValue: 99), edge: .edge(1), start: 0, end: 1))])]
            if let first = platforms.first {
                var changed = first
                changed.end += 1
                wrong.append(.trackPlatforms([changed] + platforms.dropFirst()))
                wrong.append(.trackPlatforms(Array(platforms.dropFirst())))
            }
            return wrong
        case .levels(let levels):
            var wrong: [ObservationAnswer] = [.levels(levels + [PlatformLevelSummary(platform: TrackPlatform(station: StationID(rawValue: 1), edge: .edge(99), start: 0, end: 1), height: 0, structure: .surface)])]
            if let first = levels.first {
                var changed = first
                changed.height += 1
                wrong.append(.levels([changed] + levels.dropFirst()))
                changed = first
                changed.structure = StructureName(first.structure.structure == .tunnel ? .elevated : .tunnel)
                wrong.append(.levels([changed] + levels.dropFirst()))
                wrong.append(.levels(Array(levels.dropFirst())))
            }
            return wrong
        case .trainPath(nil):
            return [.trainPath(PathSummary(TrainPath(traversals: [], end: nil, distance: 0)))]
        case .trainPath(let path?):
            var wrong: [ObservationAnswer] = [.trainPath(nil)]
            var changed = path
            changed.distance += 1
            wrong.append(.trainPath(changed))
            changed = path
            changed.end = path.end.map { $0 + 1 } ?? 1
            wrong.append(.trainPath(changed))
            changed = path
            changed.traversals.append(TraversalSummary(TrackTraversal(edge: .edge(99), direction: .forward)))
            wrong.append(.trainPath(changed))
            return wrong
        }
    }

    /// Train states that differ from `state` in one field each.
    private static func wrongStates(for state: TrainState) -> [TrainState] {
        var wrong: [TrainState] = []
        var changed = state
        switch state.position.position {
        case nil:
            changed.position = TrainPositionSummary(.atNode(GridPosition(x: 0, y: 0), heading: .north))
        case .atNode(let tile, let heading)?:
            changed.position = TrainPositionSummary(.atNode(tile, heading: heading.opposite))
        case .onLink(let from, let to, let offset)?:
            changed.position = TrainPositionSummary(.onLink(from: from, to: to, offset: offset + 1))
        case .onEdge(let traversal, let offset)?:
            changed.position = TrainPositionSummary(.onEdge(traversal, offset: offset + 1))
        }
        wrong.append(changed)
        changed = state
        changed.movement.rate += 1
        wrong.append(changed)
        changed = state
        changed.movement.cursor += 1
        wrong.append(changed)
        changed = state
        changed.movement.continuation.append(PositionSummary(GridPosition(x: 99, y: 99)))
        wrong.append(changed)
        changed = state
        changed.movement.edges.append(99)
        wrong.append(changed)
        changed = state
        changed.movement.end = state.movement.end.map { $0 + 1 } ?? 1
        wrong.append(changed)
        return wrong
    }

    /// A fixture that wrongly expects a one-sided exit to be a link fails,
    /// and the message shows GameCore's actual answer.
    func testAWrongTopologyExpectationIsReported() throws {
        let json = #"""
            {
              "schemaVersion": 22,
              "description": "Deliberately wrong: expects a one-sided exit to join.",
              "initialState": {
                "mapWidth": 2, "mapHeight": 1, "balance": 2000,
                "costs": { "track": 1000, "station": 50000, "train": 200000 },
                "gameMinutes": 0, "speed": "paused"
              },
              "steps": [
                {
                  "command": { "type": "buildTrack", "x": 0, "y": 0, "connections": ["east"] },
                  "expect": { "result": "ok" }
                },
                {
                  "command": { "type": "buildTrack", "x": 1, "y": 0, "connections": ["north"] },
                  "expect": { "result": "ok" }
                },
                {
                  "observe": { "type": "isConnected", "from": { "x": 0, "y": 0 }, "to": { "x": 1, "y": 0 } },
                  "expect": { "connected": true }
                },
                {
                  "observe": { "type": "connectedNeighbors", "x": 0, "y": 0 },
                  "expect": { "neighbors": [{ "x": 1, "y": 0 }] }
                }
              ],
              "expectedFinalState": {
                "gameMinutes": 0, "speed": "paused", "balance": 0, "stations": [],
                "tracks": [
                  { "x": 0, "y": 0, "connections": ["east"], "layout": { "type": "open" } },
                  { "x": 1, "y": 0, "connections": ["north"], "layout": { "type": "open" } }
                ],
                "trains": [],
                "lines": [],
                "serviceDay": [
                  { "start": 0, "level": "low" }, { "start": 420, "level": "peak" }, { "start": 600, "level": "offPeak" },
                  { "start": 960, "level": "peak" }, { "start": 1200, "level": "offPeak" }, { "start": 1260, "level": "low" }
                ],
                "network": { "nodes": [], "edges": [], "platforms": [] },
                "trafficControl": false,
                "passengers": [],
                "riders": [],
                "accounts": {
                  "mode": "free", "fareRules": null, "openedAt": null,
                  "pending": { "fareRevenue": 0, "fareTrips": 0, "departures": 0, "trainDistance": 0, "passengers": 0, "seats": 0 },
                  "ledger": [], "days": []
                }
              }
            }
            """#

        let scenario = try GoldenScenario.decode(Data(json.utf8))

        XCTAssertEqual(scenario.differences(), [
            #"steps[2]: expected {"connected":true}, got {"connected":false}"#,
            #"steps[3]: expected {"neighbors":[{"x":1,"y":0}]}, got {"neighbors":[]}"#,
        ])
    }

    func testUnsupportedSchemaVersionIsRejected() {
        for version in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 23] {
            let data = Data(#"{"schemaVersion": \#(version)}"#.utf8)

            XCTAssertThrowsError(try GoldenScenario.decode(data)) { error in
                XCTAssertEqual(error as? GoldenScenario.FixtureError, .unsupportedSchemaVersion(version))
            }
        }
    }

    func testMalformedStepsAreRejectedRatherThanGuessed() {
        let commands = [
            #"{"type": "demolish", "x": 1, "y": 1}"#,
            #"{"type": "buildTrack", "x": 1, "y": 1, "connections": ["up"]}"#,
            #"{"type": "buildTrack", "x": 1, "y": 1, "connections": ["east", "east"]}"#,
            #"{"type": "advance", "ticks": -1}"#,
            #"{"type": "setSpeed", "speed": "triple"}"#,
            // Observations are not commands.
            #"{"type": "connectedNeighbors", "x": 1, "y": 1}"#,
            // Train commands need a train, and a placement a node or link.
            #"{"type": "reverseTrain"}"#,
            #"{"type": "unplaceTrain", "train": "1"}"#,
            #"{"type": "placeTrain", "position": {"type": "node", "x": 1, "y": 1, "heading": "east"}}"#,
            #"{"type": "placeTrain", "train": 1}"#,
            #"{"type": "placeTrain", "train": 1, "position": {"type": "unplaced"}}"#,
            // Movement commands need a train and a value of the right kind.
            #"{"type": "setTrainMovementRate", "train": 1}"#,
            #"{"type": "setTrainMovementRate", "rate": 5}"#,
            #"{"type": "setTrainMovementRate", "train": 1, "rate": "fast"}"#,
            #"{"type": "setTrainContinuation", "train": 1}"#,
            #"{"type": "setTrainContinuation", "train": 1, "continuation": [{"x": 1}]}"#,
            #"{"type": "setTrainContinuation", "train": 1, "continuation": ["east"]}"#,
            // Observations are not commands.
            #"{"type": "train", "train": 1}"#,
            #"{"type": "timetable", "train": 1}"#,
            // A timetable needs a train, stops with a station, two integer
            // times and whether the train turns round each, and how it
            // repeats.
            #"{"type": "setTrainTimetable", "train": 1, "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "timetable": [], "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 1, "arrival": 0, "reverse": false}], "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"arrival": 0, "departure": 0, "reverse": false}], "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": "Alpha", "arrival": 0, "departure": 0, "reverse": false}], "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 1, "arrival": "08:00", "departure": 0, "reverse": false}], "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 1, "arrival": 0.5, "departure": 1, "reverse": false}], "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": {"station": 1, "arrival": 0, "departure": 0, "reverse": false}, "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": null, "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 1, "arrival": 0, "departure": 0}], "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 1, "arrival": 0, "departure": 0, "reverse": "yes"}], "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 1, "arrival": 0, "departure": 0, "reverse": null}], "repeat": {"type": "once"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": []}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [], "repeat": null}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [], "repeat": 60}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [], "repeat": {"type": "every"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [], "repeat": {"type": "every", "minutes": "60"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [], "repeat": {"type": "every", "minutes": null}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [], "repeat": {"type": "once", "minutes": 60}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [], "repeat": {"type": "daily"}}"#,
            #"{"type": "setTrainTimetable", "train": 1, "timetable": [], "repeat": {"minutes": 60}}"#,
            // Starting and stopping a service needs a train, and an
            // observation is not a command.
            #"{"type": "startTrainService"}"#,
            #"{"type": "stopTrainService", "train": "1"}"#,
            #"{"type": "execution", "train": 1}"#,
            // Schema 17: a profile needs both transitions, a structure its
            // name, a platform its station, edge and ends.
            #"{"type": "buildTrackEdge", "from": 1, "to": 2, "curve": {"type": "straight"}, "profile": {"startTransition": 1}}"#,
            #"{"type": "buildTrackEdge", "from": 1, "to": 2, "curve": {"type": "straight"}, "profile": null}"#,
            #"{"type": "buildTrackEdge", "from": 1, "to": 2, "curve": {"type": "straight"}, "structure": "floating"}"#,
            #"{"type": "buildTrackEdge", "from": 1, "to": 2, "curve": {"type": "straight"}, "structure": null}"#,
            #"{"type": "addTrackPlatform", "station": 1, "edge": 1, "start": 0}"#,
            #"{"type": "addTrackPlatform", "edge": 1, "start": 0, "end": 5}"#,
            #"{"type": "removeTrackPlatform", "station": 1, "start": 0}"#,
            #"{"type": "platformLevels", "station": 1}"#,
            // Schema 18: a path's end is a number, or absent.
            #"{"type": "setTrainPath", "train": 1, "path": [], "end": null}"#,
            #"{"type": "setTrainPath", "train": 1, "path": [], "end": "berth"}"#,
            #"{"type": "pathToStation", "station": 1}"#,
        ]
        for json in commands {
            XCTAssertThrowsError(try JSONDecoder().decode(ScenarioCommand.self, from: Data(json.utf8)), json)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "maybe"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "unknownTrain"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "unknownStation"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "unknownStation", "station": "Alpha"}"#.utf8)))
        // Schema 17: a conflict and a platform on an edge name the edge.
        for result in ["trackConflict", "trackEdgeHasPlatform"] {
            XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "\#(result)"}"#.utf8)), result)
        }
        for result in ["trainServiceActive", "trainServiceNotActive", "noTimetable", "trainNotAtFirstStop"] {
            XCTAssertThrowsError(try JSONDecoder().decode(StepOutcome.self, from: Data(#"{"result": "\#(result)"}"#.utf8)), result)
        }

        let negativeCost = #"{"track": -1, "station": 0, "train": 0}"#
        XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Costs.self, from: Data(negativeCost.utf8)))
    }

    func testMalformedObservationsAreRejectedRatherThanGuessed() {
        let from = #""from": {"x": 0, "y": 0}"#
        let to = #""to": {"x": 1, "y": 0}"#
        let steps = [
            // Exactly one of command and observe.
            #"{"expect": {"result": "ok"}}"#,
            #"{"command": {"type": "pause"}, "observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"result": "ok"}}"#,
            // Unknown observation.
            #"{"observe": {"type": "shortestPath", "x": 0, "y": 0}, "expect": {"neighbors": []}}"#,
            // An answer of another observation's kind, or a command result.
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"connected": false}}"#,
            #"{"observe": {"type": "isConnected", \#(from), \#(to)}, "expect": {"neighbors": []}}"#,
            #"{"observe": {"type": "isConnected", \#(from), \#(to)}, "expect": {"result": "ok"}}"#,
            // Both answers at once: neither may be silently ignored.
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"neighbors": [], "connected": false}}"#,
            #"{"observe": {"type": "isConnected", \#(from), \#(to)}, "expect": {"connected": false, "neighbors": []}}"#,
            // Missing or ill-typed values.
            #"{"observe": {"type": "isConnected", \#(from)}, "expect": {"connected": false}}"#,
            #"{"observe": {"type": "isConnected", \#(from), \#(to)}, "expect": {"connected": "yes"}}"#,
            #"{"observe": {"type": "connectedNeighbors", "x": 0}, "expect": {"neighbors": []}}"#,
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"neighbors": [{"x": 1}]}}"#,
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"neighbors": ["east"]}}"#,
            // A train is answered by its position and movement, both required,
            // and by nothing else.
            #"{"observe": {"type": "train"}, "expect": {"position": {"type": "unplaced"}, "movement": {"rate": 0, "continuation": [], "cursor": 0, "edges": []}}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "unplaced"}}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"movement": {"rate": 0, "continuation": [], "cursor": 0, "edges": []}}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "unplaced"}, "movement": {"rate": 0, "continuation": []}}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "unplaced"}, "movement": {"rate": 0, "continuation": [], "cursor": 0}}}"#,
            // Schema 16: the track network's observations answer only in
            // their own shapes.
            #"{"observe": {"type": "trackEdge", "edge": 1}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "trackEdge", "edge": 1}, "expect": {"found": false, "edge": {"from": 1, "to": 2, "length": 5}}}"#,
            #"{"observe": {"type": "trackEdge"}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "transitions", "edge": 1, "direction": "sideways"}, "expect": {"transitions": []}}"#,
            #"{"observe": {"type": "transitions", "edge": 1, "direction": "forward"}, "expect": {"path": []}}"#,
            #"{"observe": {"type": "edgeLocation", "edge": 1, "direction": "forward"}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "pathToNode", "from": {"type": "unplaced"}, "node": 1}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "pathToNode", "from": {"type": "edge", "edge": 1, "direction": "forward", "offset": 0}}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "bodyPath", "train": 1}, "expect": {"points": [{"x": 1, "y": 2}]}}"#,
            #"{"observe": {"type": "occupancy", "train": 1}, "expect": {"resources": [{"type": "networkSpan", "edge": 1}]}}"#,
            // Schema 17: the vertical railway's observations too.
            #"{"observe": {"type": "edgePose", "edge": 1, "direction": "forward", "distance": 0}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "edgePose", "edge": 1, "direction": "forward", "distance": 0}, "expect": {"found": true, "pose": {"x": 0, "y": 0, "z": 0, "dx": 1, "dy": 0}}}"#,
            #"{"observe": {"type": "edgePose", "edge": 1, "direction": "forward", "distance": 0}, "expect": {"found": false, "location": {"x": 0, "y": 0, "z": 0, "dx": 1, "dy": 0}}}"#,
            #"{"observe": {"type": "edgeAlignment", "edge": 1}, "expect": {"found": true, "alignment": {"structure": "floating", "segments": [], "steepest": {"rise": 0, "run": 1}}}}"#,
            #"{"observe": {"type": "edgeAlignment", "edge": 1}, "expect": {"found": true, "alignment": {"structure": "surface", "segments": []}}}"#,
            #"{"observe": {"type": "tunnelPortals"}, "expect": {"nodes": [], "found": true}}"#,
            #"{"observe": {"type": "trackPlatformsAlongTrain"}, "expect": {"trackPlatforms": []}}"#,
            #"{"observe": {"type": "trackPlatformsAlongTrain", "train": 1}, "expect": {"trackPlatforms": [{"station": 1, "edge": 1, "start": 0}]}}"#,
            #"{"observe": {"type": "platformLevels", "station": 1}, "expect": {"levels": [{"edge": 1, "start": 0, "end": 1, "height": 0, "structure": null}]}}"#,
            // Schema 18: a path to a station starts on an edge and answers in
            // its own shape.
            #"{"observe": {"type": "pathToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "pathToStation", "from": {"type": "edge", "edge": 1, "direction": "forward", "offset": 0}}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "pathToStation", "from": {"type": "edge", "edge": 1, "direction": "forward", "offset": 0}, "station": 1, "cars": 17}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "pathToStation", "from": {"type": "edge", "edge": 1, "direction": "forward", "offset": 0}, "station": 1}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "pathToStation", "from": {"type": "edge", "edge": 1, "direction": "forward", "offset": 0}, "station": 1}, "expect": {"found": false, "trainPath": {"traversals": [], "distance": 0}}}"#,
            #"{"observe": {"type": "pathToStation", "from": {"type": "edge", "edge": 1, "direction": "forward", "offset": 0}, "station": 1}, "expect": {"found": true, "trainPath": {"traversals": []}}}"#,
            #"{"observe": {"type": "pathToStation", "from": {"type": "edge", "edge": 1, "direction": "forward", "offset": 0}, "station": 1}, "expect": {"found": true, "path": []}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "unplaced"}, "movement": {"rate": 0, "continuation": [], "cursor": 0, "edges": []}, "connected": true}}"#,
            #"{"observe": {"type": "connectedNeighbors", "x": 0, "y": 0}, "expect": {"neighbors": [], "position": {"type": "unplaced"}}}"#,
            // A route is answered by "found", with "route" exactly when found.
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"route": []}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": false, "route": []}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": "yes", "route": []}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": false, "connected": false}}"#,
            // A route starts from a placed position and needs a destination.
            #"{"observe": {"type": "route", "from": {"type": "unplaced"}, "to": {"x": 1, "y": 0}}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "route", "from": {"x": 0, "y": 0}, "to": {"x": 1, "y": 0}}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "route", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}}, "expect": {"found": false}}"#,
            // A route to a station answers like a route, and needs a start
            // and a station ID.
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1}, "expect": {"found": false, "route": []}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1}, "expect": {"found": false, "platforms": []}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "unplaced"}, "station": 1}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": "Central"}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "to": {"x": 1, "y": 0}}, "expect": {"found": false}}"#,
            // Platforms and station stops have answers of their own.
            #"{"observe": {"type": "platforms"}, "expect": {"platforms": []}}"#,
            #"{"observe": {"type": "platforms", "station": 1}, "expect": {"neighbors": []}}"#,
            #"{"observe": {"type": "platforms", "station": 1}, "expect": {"platforms": [], "stations": []}}"#,
            #"{"observe": {"type": "platforms", "station": 1}, "expect": {"platforms": [{"x": 1}]}}"#,
            #"{"observe": {"type": "stationStops"}, "expect": {"stations": []}}"#,
            #"{"observe": {"type": "stationStops", "train": 1}, "expect": {"platforms": []}}"#,
            #"{"observe": {"type": "stationStops", "train": 1}, "expect": {"stations": ["Central"]}}"#,
            #"{"observe": {"type": "stationStops", "train": 1}, "expect": {"stations": [], "found": false}}"#,
            // A timetable is answered by its stops, and by nothing else.
            #"{"observe": {"type": "timetable"}, "expect": {"timetable": []}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {"stations": []}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {"timetable": [], "stations": []}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {"timetable": [{"station": 1, "arrival": 0}]}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {"timetable": null}}"#,
            #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "unplaced"}, "movement": {"rate": 0, "continuation": [], "cursor": 0, "edges": []}, "timetable": []}}"#,
            // A service is answered by its type, with "stop" and "cycle"
            // exactly when active, and by nothing else.
            #"{"observe": {"type": "execution"}, "expect": {"execution": {"type": "inactive"}}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": null}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "running", "stop": 0}}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "inactive", "stop": 0}}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "waiting"}}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "waiting", "cycle": 0}}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "travelling", "stop": "1", "cycle": 0}}}"#,
            // ...and by its cycle when active, never without one.
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "waiting", "stop": 0}}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "travelling", "stop": 1, "cycle": "0"}}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "waiting", "stop": 1, "cycle": null}}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "inactive", "cycle": 0}}}"#,
            #"{"observe": {"type": "execution", "train": 1}, "expect": {"execution": {"type": "inactive"}, "timetable": []}}"#,
            #"{"observe": {"type": "timetable", "train": 1}, "expect": {"execution": {"type": "inactive"}}}"#,
        ]
        for json in steps {
            XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), json)
        }
    }

    func testObservationStepsDecode() throws {
        let neighbors = #"{"observe": {"type": "connectedNeighbors", "x": 2, "y": 1}, "expect": {"neighbors": [{"x": 2, "y": 0}, {"x": 1, "y": 1}]}}"#
        let connected = #"{"observe": {"type": "isConnected", "from": {"x": 2, "y": 1}, "to": {"x": 3, "y": 1}}, "expect": {"connected": true}}"#

        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(neighbors.utf8)),
            .observe(.connectedNeighbors(GridPosition(x: 2, y: 1)), expect: .neighbors([GridPosition(x: 2, y: 0), GridPosition(x: 1, y: 1)]))
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(connected.utf8)),
            .observe(.isConnected(GridPosition(x: 2, y: 1), to: GridPosition(x: 3, y: 1)), expect: .connected(true))
        )

        let found = #"{"observe": {"type": "route", "from": {"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}, "offset": 9}, "to": {"x": 3, "y": 2}}, "expect": {"found": true, "route": [{"x": 3, "y": 1}, {"x": 3, "y": 2}]}}"#
        let notFound = #"{"observe": {"type": "route", "from": {"type": "node", "x": 1, "y": 1, "heading": "west"}, "to": {"x": 3, "y": 2}}, "expect": {"found": false}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(found.utf8)),
            .observe(
                .route(from: .onLink(from: GridPosition(x: 1, y: 1), to: GridPosition(x: 2, y: 1), offset: 9), to: GridPosition(x: 3, y: 2)),
                expect: .route([GridPosition(x: 3, y: 1), GridPosition(x: 3, y: 2)])
            )
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(notFound.utf8)),
            .observe(.route(from: .atNode(GridPosition(x: 1, y: 1), heading: .west), to: GridPosition(x: 3, y: 2)), expect: .route(nil))
        )

        let platforms = #"{"observe": {"type": "platforms", "station": 2}, "expect": {"platforms": [{"x": 4, "y": 0}, {"x": 3, "y": 1}]}}"#
        let toStation = #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 1, "y": 1, "heading": "east"}, "station": 2}, "expect": {"found": true, "route": [{"x": 2, "y": 1}, {"x": 3, "y": 1}]}}"#
        let noStationRoute = #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 1, "y": 1, "heading": "west"}, "station": 9}, "expect": {"found": false}}"#
        let stops = #"{"observe": {"type": "stationStops", "train": 3}, "expect": {"stations": [1, 4]}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(platforms.utf8)),
            .observe(.platforms(StationID(rawValue: 2)), expect: .platforms([GridPosition(x: 4, y: 0), GridPosition(x: 3, y: 1)]))
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(toStation.utf8)),
            .observe(
                .routeToStation(from: .atNode(GridPosition(x: 1, y: 1), heading: .east), station: StationID(rawValue: 2), cars: 1),
                expect: .route([GridPosition(x: 2, y: 1), GridPosition(x: 3, y: 1)])
            )
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(noStationRoute.utf8)),
            .observe(.routeToStation(from: .atNode(GridPosition(x: 1, y: 1), heading: .west), station: StationID(rawValue: 9), cars: 1), expect: .route(nil))
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(stops.utf8)),
            .observe(.stationStops(TrainID(rawValue: 3)), expect: .stations([StationID(rawValue: 1), StationID(rawValue: 4)]))
        )

        let timetable = #"{"observe": {"type": "timetable", "train": 2}, "expect": {"timetable": [{"station": 3, "arrival": 0, "departure": 0, "reverse": false}, {"station": 1, "arrival": 1440, "departure": 1450, "reverse": true}]}}"#
        let emptyTimetable = #"{"observe": {"type": "timetable", "train": 1}, "expect": {"timetable": []}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(timetable.utf8)),
            .observe(.timetable(TrainID(rawValue: 2)), expect: .timetable([
                ScheduledStop(station: StationID(rawValue: 3), arrival: GameTime(minutes: 0), departure: GameTime(minutes: 0)),
                ScheduledStop(station: StationID(rawValue: 1), arrival: GameTime(minutes: 1440), departure: GameTime(minutes: 1450), reverses: true),
            ]))
        )
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(emptyTimetable.utf8)),
            .observe(.timetable(TrainID(rawValue: 1)), expect: .timetable([]))
        )

        let executions: [(String, TimetableExecution?)] = [
            (#"{"type": "inactive"}"#, nil),
            (#"{"type": "waiting", "stop": 0, "cycle": 0}"#, .waitingAtStop(0)),
            (#"{"type": "travelling", "stop": 3, "cycle": 0}"#, .travellingToStop(3)),
            (#"{"type": "waiting", "stop": 2, "cycle": 7}"#, .waitingAtStop(2, cycle: 7)),
            (#"{"type": "travelling", "stop": 0, "cycle": 1}"#, .travellingToStop(0, cycle: 1)),
            // Read as written: rejecting a negative cycle is GameCore's decision.
            (#"{"type": "waiting", "stop": 0, "cycle": -1}"#, .waitingAtStop(0, cycle: -1)),
        ]
        for (json, expected) in executions {
            let step = #"{"observe": {"type": "execution", "train": 2}, "expect": {"execution": \#(json)}}"#
            XCTAssertEqual(
                try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(step.utf8)),
                .observe(.execution(TrainID(rawValue: 2)), expect: .execution(ExecutionSummary(expected))),
                step
            )
        }

        let train = #"{"observe": {"type": "train", "train": 1}, "expect": {"position": {"type": "link", "from": {"x": 2, "y": 1}, "to": {"x": 3, "y": 1}, "offset": 532}, "movement": {"rate": 1300, "continuation": [{"x": 3, "y": 1}, {"x": 4, "y": 1}], "cursor": 1, "edges": []}}}"#
        XCTAssertEqual(
            try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(train.utf8)),
            .observe(.train(TrainID(rawValue: 1)), expect: .train(TrainState(
                position: TrainPositionSummary(.onLink(from: GridPosition(x: 2, y: 1), to: GridPosition(x: 3, y: 1), offset: 532)),
                movement: TrainMovementSummary(rate: 1300, continuation: [GridPosition(x: 3, y: 1), GridPosition(x: 4, y: 1)], cursor: 1)
            )))
        )
    }

    func testTrainCommandsAndResultsDecode() throws {
        let commands: [(String, ScenarioCommand)] = [
            (#"{"type": "placeTrain", "train": 2, "position": {"type": "node", "x": 3, "y": 1, "heading": "west"}}"#,
             .placeTrain(TrainID(rawValue: 2), .atNode(GridPosition(x: 3, y: 1), heading: .west))),
            (#"{"type": "placeTrain", "train": 1, "position": {"type": "link", "from": {"x": 1, "y": 2}, "to": {"x": 1, "y": 1}, "offset": 256}}"#,
             .placeTrain(TrainID(rawValue: 1), .onLink(from: GridPosition(x: 1, y: 2), to: GridPosition(x: 1, y: 1), offset: 256))),
            // Read as written: rejecting offset 0 is GameCore's decision.
            (#"{"type": "placeTrain", "train": 1, "position": {"type": "link", "from": {"x": 1, "y": 2}, "to": {"x": 1, "y": 1}, "offset": 0}}"#,
             .placeTrain(TrainID(rawValue: 1), .onLink(from: GridPosition(x: 1, y: 2), to: GridPosition(x: 1, y: 1), offset: 0))),
            (#"{"type": "unplaceTrain", "train": 3}"#, .unplaceTrain(TrainID(rawValue: 3))),
            (#"{"type": "reverseTrain", "train": 4}"#, .reverseTrain(TrainID(rawValue: 4))),
            (#"{"type": "setTrainMovementRate", "train": 2, "rate": 1300}"#, .setTrainMovementRate(TrainID(rawValue: 2), 1300)),
            // Read as written: rejecting a negative rate is GameCore's decision.
            (#"{"type": "setTrainMovementRate", "train": 2, "rate": -1}"#, .setTrainMovementRate(TrainID(rawValue: 2), -1)),
            (#"{"type": "setTrainContinuation", "train": 1, "continuation": [{"x": 3, "y": 1}, {"x": 3, "y": 2}]}"#,
             .setTrainContinuation(TrainID(rawValue: 1), [GridPosition(x: 3, y: 1), GridPosition(x: 3, y: 2)])),
            (#"{"type": "setTrainContinuation", "train": 1, "continuation": []}"#, .setTrainContinuation(TrainID(rawValue: 1), [])),
            (#"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 2, "arrival": 20, "departure": 25, "reverse": false}, {"station": 2, "arrival": 25, "departure": 25, "reverse": true}], "repeat": {"type": "once"}}"#,
             .setTrainTimetable(TrainID(rawValue: 1), [
                ScheduledStop(station: StationID(rawValue: 2), arrival: GameTime(minutes: 20), departure: GameTime(minutes: 25)),
                ScheduledStop(station: StationID(rawValue: 2), arrival: GameTime(minutes: 25), departure: GameTime(minutes: 25), reverses: true),
             ], period: nil)),
            (#"{"type": "setTrainTimetable", "train": 3, "timetable": [], "repeat": {"type": "once"}}"#, .setTrainTimetable(TrainID(rawValue: 3), [], period: nil)),
            (#"{"type": "setTrainTimetable", "train": 2, "timetable": [{"station": 1, "arrival": 0, "departure": 5, "reverse": true}], "repeat": {"type": "every", "minutes": 60}}"#,
             .setTrainTimetable(TrainID(rawValue: 2), [ScheduledStop(station: StationID(rawValue: 1), arrival: .zero, departure: GameTime(minutes: 5), reverses: true)], period: 60)),
            // Read as written: rejecting a negative time, a departure before
            // the arrival, an unknown station, or a period that is not
            // positive or repeats an empty timetable is GameCore's decision.
            (#"{"type": "setTrainTimetable", "train": 1, "timetable": [{"station": 0, "arrival": -1, "departure": -5, "reverse": false}], "repeat": {"type": "once"}}"#,
             .setTrainTimetable(TrainID(rawValue: 1), [ScheduledStop(station: StationID(rawValue: 0), arrival: GameTime(minutes: -1), departure: GameTime(minutes: -5))], period: nil)),
            (#"{"type": "setTrainTimetable", "train": 1, "timetable": [], "repeat": {"type": "every", "minutes": -3}}"#,
             .setTrainTimetable(TrainID(rawValue: 1), [], period: -3)),
            (#"{"type": "startTrainService", "train": 2}"#, .startTrainService(TrainID(rawValue: 2))),
            (#"{"type": "stopTrainService", "train": 3}"#, .stopTrainService(TrainID(rawValue: 3))),
        ]
        for (json, expected) in commands {
            XCTAssertEqual(try JSONDecoder().decode(ScenarioCommand.self, from: Data(json.utf8)), expected, json)
        }

        let results: [(String, StepOutcome)] = [
            (#"{"result": "trackInUse", "x": 1, "y": 2}"#, .rejected(.trackInUse(GridPosition(x: 1, y: 2)))),
            (#"{"result": "unknownTrain", "train": 9}"#, .rejected(.unknownTrain(TrainID(rawValue: 9)))),
            (#"{"result": "trainAlreadyPlaced", "train": 1}"#, .rejected(.trainAlreadyPlaced(TrainID(rawValue: 1)))),
            (#"{"result": "trainNotPlaced", "train": 1}"#, .rejected(.trainNotPlaced(TrainID(rawValue: 1)))),
            (#"{"result": "invalidTrainPosition"}"#, .rejected(.invalidTrainPosition)),
            (#"{"result": "invalidMovementRate"}"#, .rejected(.invalidMovementRate)),
            (#"{"result": "invalidContinuation"}"#, .rejected(.invalidContinuation)),
            (#"{"result": "clockOverflow"}"#, .rejected(.clockOverflow)),
            (#"{"result": "idsExhausted"}"#, .rejected(.idsExhausted)),
            (#"{"result": "invalidTimetable"}"#, .rejected(.invalidTimetable)),
            (#"{"result": "unknownStation", "station": 4}"#, .rejected(.unknownStation(StationID(rawValue: 4)))),
            (#"{"result": "trainServiceActive", "train": 2}"#, .rejected(.trainServiceActive(TrainID(rawValue: 2)))),
            (#"{"result": "trainServiceNotActive", "train": 2}"#, .rejected(.trainServiceNotActive(TrainID(rawValue: 2)))),
            (#"{"result": "noTimetable", "train": 2}"#, .rejected(.noTimetable(TrainID(rawValue: 2)))),
            (#"{"result": "trainNotAtFirstStop", "train": 2}"#, .rejected(.trainNotAtFirstStop(TrainID(rawValue: 2)))),
        ]
        for (json, expected) in results {
            XCTAssertEqual(try JSONDecoder().decode(StepOutcome.self, from: Data(json.utf8)), expected, json)
        }
    }

    func testLineCommandsObservationsAndResultsDecode() throws {
        let line = LineID(rawValue: 2)
        let commands: [(String, ScenarioCommand)] = [
            (#"{"type": "createLine", "name": "Main", "stops": [1, 2, 3]}"#,
             .createLine(name: "Main", stops: [1, 2, 3].map(StationID.init(rawValue:)))),
            // Read as written: rejecting too few stops or a blank name is GameCore's decision.
            (#"{"type": "createLine", "name": " ", "stops": []}"#, .createLine(name: " ", stops: [])),
            (#"{"type": "removeLine", "line": 2}"#, .removeLine(line)),
            (#"{"type": "setLineStops", "line": 2, "stops": [4, 1]}"#, .setLineStops(line, [4, 1].map(StationID.init(rawValue:)))),
            (#"{"type": "setLineRate", "line": 2, "rate": 0}"#, .setLineRate(line, 0)),
            (#"{"type": "setLineServiceWindow", "line": 2, "window": {"type": "allDay"}}"#, .setLineServiceWindow(line, .allDay)),
            (#"{"type": "setLineServiceWindow", "line": 2, "window": {"type": "hours", "open": 900, "close": 100}}"#,
             .setLineServiceWindow(line, .hours(open: 900, close: 100))),
            (#"{"type": "setLineTrainsInService", "line": 2, "trains": {"peak": 6, "offPeak": -1, "low": 0}}"#,
             .setLineTrainsInService(line, TrainsInService(peak: 6, offPeak: -1, low: 0), pattern: nil)),
            (#"{"type": "setLineTrainsInService", "line": 2, "pattern": 1, "trains": {"peak": 1, "offPeak": 0, "low": 0}}"#,
             .setLineTrainsInService(line, TrainsInService(peak: 1, offPeak: 0, low: 0), pattern: 1)),
            (#"{"type": "setLineTargetHeadways", "line": 2, "pattern": 0, "targetHeadways": {"peak": 5, "offPeak": null, "low": null}}"#,
             .setLineTargetHeadways(line, TargetHeadways(peak: 5), pattern: 0)),
            (#"{"type": "assignTrain", "train": 3, "line": 2, "pattern": -1}"#, .assignTrain(TrainID(rawValue: 3), line, pattern: -1)),
            // Read as written: whether the calls fit the line is GameCore's decision.
            (#"{"type": "addLinePattern", "line": 2, "calls": [3, 1]}"#, .addLinePattern(line, calls: [3, 1])),
            (#"{"type": "removeLinePattern", "line": 2, "pattern": 4}"#, .removeLinePattern(line, pattern: 4)),
            (#"{"type": "setServiceDay", "bands": [{"start": 0, "level": "low"}, {"start": 420, "level": "peak"}]}"#,
             .setServiceDay(ServiceDay(bands: [ServiceDay.Band(start: 0, level: .low), ServiceDay.Band(start: 420, level: .peak)]))),
            (#"{"type": "setServiceDay", "bands": []}"#, .setServiceDay(ServiceDay(bands: []))),
        ]
        for (json, expected) in commands {
            XCTAssertEqual(try JSONDecoder().decode(ScenarioCommand.self, from: Data(json.utf8)), expected, json)
        }

        let results: [(String, StepOutcome)] = [
            (#"{"result": "unknownLine", "line": 4}"#, .rejected(.unknownLine(LineID(rawValue: 4)))),
            (#"{"result": "invalidLineStops"}"#, .rejected(.invalidLineStops)),
            (#"{"result": "invalidLineRate"}"#, .rejected(.invalidLineRate)),
            (#"{"result": "invalidServiceWindow"}"#, .rejected(.invalidServiceWindow)),
            (#"{"result": "invalidTrainsInService"}"#, .rejected(.invalidTrainsInService)),
            (#"{"result": "invalidServiceDay"}"#, .rejected(.invalidServiceDay)),
            (#"{"result": "invalidLinePattern"}"#, .rejected(.invalidLinePattern)),
            (#"{"result": "unknownLinePattern", "pattern": 2}"#, .rejected(.unknownLinePattern(2))),
        ]
        for (json, expected) in results {
            XCTAssertEqual(try JSONDecoder().decode(StepOutcome.self, from: Data(json.utf8)), expected, json)
        }

        let observations: [(String, GoldenScenario.Step)] = [
            (#"{"observe": {"type": "serviceLevel", "line": 2, "gameMinutes": 420}, "expect": {"level": "peak"}}"#,
             .observe(.serviceLevel(line, at: GameTime(minutes: 420)), expect: .level(.peak))),
            (#"{"observe": {"type": "serviceLevel", "line": 2, "gameMinutes": -5}, "expect": {"level": "closed"}}"#,
             .observe(.serviceLevel(line, at: GameTime(minutes: -5)), expect: .level(nil))),
            (#"{"observe": {"type": "lineJourney", "line": 2}, "expect": {"found": false}}"#,
             .observe(.lineJourney(line, pattern: nil), expect: .journey(nil))),
            (#"{"observe": {"type": "lineJourney", "line": 2, "pattern": 0}, "expect": {"found": false}}"#,
             .observe(.lineJourney(line, pattern: 0), expect: .journey(nil))),
            (#"{"observe": {"type": "lineMaximumTrains", "line": 2}, "expect": {"found": true, "trains": 7}}"#,
             .observe(.lineMaximumTrains(line, pattern: nil), expect: .trains(7))),
            (#"{"observe": {"type": "lineTrainsInService", "line": 2, "level": "offPeak"}, "expect": {"found": false}}"#,
             .observe(.lineTrainsInService(line, .offPeak, pattern: nil), expect: .trains(nil))),
            (#"{"observe": {"type": "lineHeadway", "line": 2, "level": "low"}, "expect": {"found": true, "minutes": 14}}"#,
             .observe(.lineHeadway(line, .low, pattern: nil), expect: .minutes(14))),
            (#"{"observe": {"type": "lineHeadway", "line": 2, "pattern": 3, "level": "low"}, "expect": {"found": true, "minutes": 9}}"#,
             .observe(.lineHeadway(line, .low, pattern: 3), expect: .minutes(9))),
            (#"{"observe": {"type": "lineSegmentLoads", "line": 2, "level": "peak"}, "expect": {"found": true, "loads": [720, 360]}}"#,
             .observe(.lineSegmentLoads(line, .peak), expect: .loads([720, 360]))),
            (#"{"observe": {"type": "lineSegmentLoads", "line": 2, "level": "low"}, "expect": {"found": false}}"#,
             .observe(.lineSegmentLoads(line, .low), expect: .loads(nil))),
        ]
        for (json, expected) in observations {
            XCTAssertEqual(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), expected, json)
        }
    }

    func testTrackResourceStepsDecode() throws {
        let p = { (x: Int, y: Int) in GridPosition(x: x, y: y) }
        let steps: [(String, GoldenScenario.Step)] = [
            (#"{"command": {"type": "buildTurnout", "x": 2, "y": 1, "connections": ["east", "west"], "stem": "north"}, "expect": {"result": "ok"}}"#,
             .command(.buildTurnout(p(2, 1), [.east, .west], stem: .north), expect: .ok)),
            (#"{"command": {"type": "buildCrossing", "x": 3, "y": 1}, "expect": {"result": "outOfBounds", "x": 3, "y": 1}}"#,
             .command(.buildCrossing(p(3, 1)), expect: .rejected(.outOfBounds(p(3, 1))))),
            (#"{"observe": {"type": "exits", "x": 2, "y": 2, "heading": "south"}, "expect": {"exits": [{"x": 3, "y": 2}]}}"#,
             .observe(.exits(p(2, 2), facing: .south), expect: .exits([p(3, 2)]))),
            (#"{"observe": {"type": "occupancy", "train": 2}, "expect": {"resources": [{"type": "link", "from": {"x": 1, "y": 0}, "to": {"x": 2, "y": 0}}]}}"#,
             .observe(.occupancy(TrainID(rawValue: 2)), expect: .resources([.wholeLink(.link(p(1, 0), p(2, 0)))]))),
            (#"{"observe": {"type": "conflicts"}, "expect": {"conflicts": [{"resource": {"type": "node", "x": 4, "y": 2}, "trains": [1, 2]}]}}"#,
             .observe(.conflicts, expect: .conflicts([TrackConflict(resource: .tile(p(4, 2)), trains: [TrainID(rawValue: 1), TrainID(rawValue: 2)])]))),
            (#"{"observe": {"type": "trackSections"}, "expect": {"sections": [{"nodes": [{"x": 0, "y": 0}], "loop": false}]}}"#,
             .observe(.trackSections, expect: .sections([TrackSection(nodes: [p(0, 0)], isLoop: false)]))),
            (#"{"observe": {"type": "parallelTracks", "from": 1, "to": 2}, "expect": {"tracks": 2}}"#,
             .observe(.parallelTracks(StationID(rawValue: 1), StationID(rawValue: 2)), expect: .tracks(2))),
        ]
        for (json, expected) in steps {
            XCTAssertEqual(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), expected, json)
        }
        let layouts: [(String, TrackLayout)] = [
            (#"{"type": "open"}"#, .open), (#"{"type": "crossing"}"#, .crossing), (#"{"type": "turnout", "stem": "east"}"#, .turnout(stem: .east)),
        ]
        for (json, expected) in layouts {
            XCTAssertEqual(try JSONDecoder().decode(LayoutSummary.self, from: Data(json.utf8)).layout, expected, json)
        }
        let malformed = [
            #"{"command": {"type": "buildTurnout", "x": 2, "y": 1, "connections": ["east", "west"]}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "buildTurnout", "x": 2, "y": 1, "connections": ["east", "west"], "stem": "up"}, "expect": {"result": "ok"}}"#,
            #"{"observe": {"type": "exits", "x": 2, "y": 2}, "expect": {"exits": []}}"#,
            #"{"observe": {"type": "exits", "x": 2, "y": 2, "heading": "south"}, "expect": {"resources": []}}"#,
            #"{"observe": {"type": "occupancy", "train": 2}, "expect": {"resources": [{"type": "tile", "x": 1, "y": 0}]}}"#,
            #"{"observe": {"type": "trackSections"}, "expect": {"sections": [{"nodes": []}]}}"#,
            #"{"observe": {"type": "parallelTracks", "from": 1}, "expect": {"tracks": 2}}"#,
        ]
        for json in malformed {
            XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), json)
        }
        for json in [#"{"type": "open", "stem": "east"}"#, #"{"type": "turnout"}"#, #"{"type": "switch"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(LayoutSummary.self, from: Data(json.utf8)), json)
        }
    }

    func testStationFacilityStepsDecode() throws {
        let p = { (x: Int, y: Int) in GridPosition(x: x, y: y) }
        let steps: [(String, GoldenScenario.Step)] = [
            (#"{"command": {"type": "extendStation", "station": 1, "x": 3, "y": 1}, "expect": {"result": "ok"}}"#,
             .command(.extendStation(StationID(rawValue: 1), p(3, 1)), expect: .ok)),
            (#"{"command": {"type": "extendStation", "station": 1, "x": 5, "y": 1}, "expect": {"result": "invalidStationTile", "x": 5, "y": 1}}"#,
             .command(.extendStation(StationID(rawValue: 1), p(5, 1)), expect: .rejected(.invalidStationTile(p(5, 1))))),
            (#"{"command": {"type": "setTrainCars", "train": 2, "cars": 4}, "expect": {"result": "ok"}}"#,
             .command(.setTrainCars(TrainID(rawValue: 2), 4), expect: .ok)),
            // Read as written: rejecting 17 cars is GameCore's decision.
            (#"{"command": {"type": "setTrainCars", "train": 2, "cars": 17}, "expect": {"result": "invalidTrainLength"}}"#,
             .command(.setTrainCars(TrainID(rawValue: 2), 17), expect: .rejected(.invalidTrainLength))),
            (#"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1, "cars": 4}, "expect": {"found": true, "route": [{"x": 1, "y": 0}]}}"#,
             .observe(.routeToStation(from: .atNode(p(0, 0), heading: .east), station: StationID(rawValue: 1), cars: 4), expect: .route([p(1, 0)]))),
            (#"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1}, "expect": {"found": false}}"#,
             .observe(.routeToStation(from: .atNode(p(0, 0), heading: .east), station: StationID(rawValue: 1), cars: 1), expect: .route(nil))),
            (#"{"observe": {"type": "wholeTrainStops", "train": 1}, "expect": {"stations": [2]}}"#,
             .observe(.wholeTrainStops(TrainID(rawValue: 1)), expect: .stations([StationID(rawValue: 2)]))),
            (#"{"observe": {"type": "platformTracks", "station": 1}, "expect": {"platformTracks": [[{"x": 1, "y": 0}, {"x": 2, "y": 0}], []]}}"#,
             .observe(.platformTracks(StationID(rawValue: 1)), expect: .platformTracks([[p(1, 0), p(2, 0)], []]))),
        ]
        for (json, expected) in steps {
            XCTAssertEqual(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), expected, json)
        }
        let malformed = [
            #"{"command": {"type": "extendStation", "x": 3, "y": 1}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setTrainCars", "train": 2}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setTrainCars", "train": 2, "cars": 4}, "expect": {"result": "invalidStationTile"}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1, "cars": 17}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1, "cars": 0}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "routeToStation", "from": {"type": "node", "x": 0, "y": 0, "heading": "east"}, "station": 1, "cars": null}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "wholeTrainStops"}, "expect": {"stations": []}}"#,
            #"{"observe": {"type": "wholeTrainStops", "train": 1}, "expect": {"platforms": []}}"#,
            #"{"observe": {"type": "platformTracks", "station": 1}, "expect": {"platformTracks": [{"x": 1, "y": 0}]}}"#,
            #"{"observe": {"type": "platformTracks", "station": 1}, "expect": {"platforms": []}}"#,
        ]
        for json in malformed {
            XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), json)
        }
    }

    /// Schema 19: traffic control, its results and the reservation
    /// observations.
    func testTrafficControlStepsDecode() throws {
        let train = { (id: Int) in TrainID(rawValue: id) }
        let span = TrackResource.span(TrackSpan(edge: .edge(1), start: 0, end: 1024))
        let steps: [(String, GoldenScenario.Step)] = [
            (#"{"command": {"type": "setTrafficControl", "enabled": true}, "expect": {"result": "trainsShareTrack", "trains": [1, 2]}}"#,
             .command(.setTrafficControl(true), expect: .rejected(.trainsShareTrack(train(1), train(2))))),
            (#"{"command": {"type": "setTrafficControl", "enabled": false}, "expect": {"result": "ok"}}"#,
             .command(.setTrafficControl(false), expect: .ok)),
            (#"{"command": {"type": "setTrainPath", "train": 2, "path": []}, "expect": {"result": "trackReserved", "train": 1}}"#,
             .command(.setTrainPath(train(2), [], end: nil), expect: .rejected(.trackReserved(train(1))))),
            (#"{"observe": {"type": "reservation", "train": 1}, "expect": {"resources": [{"type": "networkNode", "node": 2}, {"type": "networkSpan", "edge": 1, "start": 0, "end": 1024}]}}"#,
             .observe(.reservation(train(1)), expect: .resources([.node(.node(2)), span]))),
            (#"{"observe": {"type": "heldResources", "train": 1}, "expect": {"resources": []}}"#,
             .observe(.heldResources(train(1)), expect: .resources([]))),
            (#"{"observe": {"type": "routeHolder", "train": 2}, "expect": {"found": true, "train": 1}}"#,
             .observe(.routeHolder(train(2)), expect: .holder(train(1)))),
            (#"{"observe": {"type": "routeHolder", "train": 1}, "expect": {"found": false}}"#,
             .observe(.routeHolder(train(1)), expect: .holder(nil))),
        ]
        for (json, expected) in steps {
            XCTAssertEqual(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), expected, json)
        }
        let malformed = [
            #"{"command": {"type": "setTrafficControl"}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setTrafficControl", "enabled": 1}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setTrafficControl", "enabled": true}, "expect": {"result": "trainsShareTrack", "trains": [1]}}"#,
            #"{"command": {"type": "setTrafficControl", "enabled": true}, "expect": {"result": "trackReserved"}}"#,
            #"{"observe": {"type": "reservation"}, "expect": {"resources": []}}"#,
            #"{"observe": {"type": "heldResources", "train": 1}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "routeHolder", "train": 2}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "routeHolder", "train": 2}, "expect": {"found": false, "train": 1}}"#,
            #"{"observe": {"type": "routeHolder", "train": 2}, "expect": {"found": true, "train": 1, "resources": []}}"#,
        ]
        for json in malformed {
            XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), json)
        }
    }

    /// Schema 20: station demand, its result, and the passenger
    /// observations.
    func testPassengerStepsDecode() throws {
        let station = { (id: Int) in StationID(rawValue: id) }
        var hourly = Array(repeating: Int64(0), count: 24)
        hourly[8] = 1
        let hourlyJSON = "[" + hourly.map(String.init).joined(separator: ", ") + "]"
        let group = WaitingGroup(line: LineID(rawValue: 1), direction: .inbound, destination: station(1), since: GameTime(minutes: 539), count: 3)
        let steps: [(String, GoldenScenario.Step)] = [
            (#"{"command": {"type": "setStationDemand", "station": 1, "demand": {"kind": "residential", "dailyTrips": 1}}, "expect": {"result": "ok"}}"#,
             .command(.setStationDemand(station(1), StationDemand(kind: .residential, dailyTrips: 1)), expect: .ok)),
            (#"{"command": {"type": "setStationDemand", "station": 2, "demand": {"kind": "scenic", "dailyTrips": -1}}, "expect": {"result": "invalidStationDemand"}}"#,
             .command(.setStationDemand(station(2), StationDemand(kind: .scenic, dailyTrips: -1)), expect: .rejected(.invalidStationDemand))),
            (#"{"command": {"type": "setStationDemand", "station": 2, "demand": null}, "expect": {"result": "ok"}}"#,
             .command(.setStationDemand(station(2), nil), expect: .ok)),
            (#"{"observe": {"type": "passengerTrip", "from": 1, "to": 2}, "expect": {"found": true, "trip": {"line": 1, "direction": "outbound"}}}"#,
             .observe(.passengerTrip(from: station(1), to: station(2)), expect: .trip(TripSummary(PassengerTrip(line: LineID(rawValue: 1), direction: .outbound))))),
            (#"{"observe": {"type": "passengerTrip", "from": 1, "to": 1}, "expect": {"found": false}}"#,
             .observe(.passengerTrip(from: station(1), to: station(1)), expect: .trip(nil))),
            (#"{"observe": {"type": "demand", "from": 1, "to": 2}, "expect": {"daily": 1, "hourly": \#(hourlyJSON)}}"#,
             .observe(.demand(from: station(1), to: station(2)), expect: .demand(daily: 1, hourly: hourly))),
            (#"{"observe": {"type": "waitingPassengers", "station": 2}, "expect": {"groups": [{"line": 1, "direction": "inbound", "destination": 1, "since": 539, "count": 3}]}}"#,
             .observe(.waitingPassengers(station(2)), expect: .groups([WaitingGroupSummary(group)]))),
            (#"{"observe": {"type": "passengerLedger", "station": 2}, "expect": {"ledger": {"released": 9, "waiting": 3, "riding": 1, "arrived": 3, "overflowed": 2, "abandoned": 0, "refused": 4}}}"#,
             .observe(.passengerLedger(station(2)), expect: .ledger(LedgerSummary(PassengerLedger(
                 released: 9, waiting: 3, riding: 1, arrived: 3, overflowed: 2, abandoned: 0, refused: 4
             ))))),
            (#"{"observe": {"type": "riders", "train": 1}, "expect": {"riders": [{"origin": 2, "destination": 1, "count": 1}]}}"#,
             .observe(.riders(TrainID(rawValue: 1)), expect: .riders([RidingGroupSummary(RidingGroup(origin: station(2), destination: station(1), count: 1))]))),
        ]
        for (json, expected) in steps {
            XCTAssertEqual(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), expected, json)
        }
        let malformed = [
            #"{"command": {"type": "setStationDemand", "station": 1}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setStationDemand", "demand": null}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setStationDemand", "station": 1, "demand": {"kind": "airport", "dailyTrips": 1}}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setStationDemand", "station": 1, "demand": {"kind": "office"}}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setStationDemand", "station": 1, "demand": {"kind": "office", "dailyTrips": 1.5}}, "expect": {"result": "ok"}}"#,
            #"{"observe": {"type": "passengerTrip", "from": 1}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "passengerTrip", "from": 1, "to": 2}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "passengerTrip", "from": 1, "to": 2}, "expect": {"found": false, "trip": {"line": 1, "direction": "outbound"}}}"#,
            #"{"observe": {"type": "passengerTrip", "from": 1, "to": 2}, "expect": {"found": true, "trip": {"line": 1, "direction": "up"}}}"#,
            #"{"observe": {"type": "demand", "from": 1, "to": 2}, "expect": {"daily": 1, "hourly": [1]}}"#,
            #"{"observe": {"type": "demand", "from": 1, "to": 2}, "expect": {"daily": 1}}"#,
            #"{"observe": {"type": "waitingPassengers", "station": 1}, "expect": {"groups": [{"line": 1, "direction": "inbound", "destination": 2, "since": 0}]}}"#,
            #"{"observe": {"type": "waitingPassengers", "station": 1}, "expect": {"ledger": {"released": 0, "waiting": 0, "overflowed": 0, "abandoned": 0}}}"#,
            #"{"observe": {"type": "passengerLedger", "station": 1}, "expect": {"ledger": {"released": 0, "waiting": 0, "overflowed": 0}}}"#,
            // Schema 21: the ledger's new counts are required.
            #"{"observe": {"type": "passengerLedger", "station": 1}, "expect": {"ledger": {"released": 0, "waiting": 0, "overflowed": 0, "abandoned": 0}}}"#,
            #"{"observe": {"type": "riders"}, "expect": {"riders": []}}"#,
            #"{"observe": {"type": "riders", "train": 1}, "expect": {"groups": []}}"#,
            #"{"observe": {"type": "riders", "train": 1}, "expect": {"riders": [{"origin": 1, "destination": 2}]}}"#,
        ]
        for json in malformed {
            XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), json)
        }
        // A station's passengers in the final state spell out "demand",
        // null for none.
        XCTAssertThrowsError(try JSONDecoder().decode(
            PassengerSummary.self, from: Data(#"{"station": 1, "waiting": [], "released": 0, "arrived": 0, "overflowed": 0, "abandoned": 0, "refused": 0}"#.utf8)
        ))
        XCTAssertEqual(
            try JSONDecoder().decode(
                PassengerSummary.self,
                from: Data(#"{"station": 1, "demand": null, "waiting": [], "released": 0, "arrived": 0, "overflowed": 0, "abandoned": 0, "refused": 0}"#.utf8)
            ),
            PassengerSummary(station: 1, demand: nil, waiting: [], released: 0, arrived: 0, overflowed: 0, abandoned: 0, refused: 0)
        )
        // Schema 21: every field is required.
        XCTAssertThrowsError(try JSONDecoder().decode(
            PassengerSummary.self, from: Data(#"{"station": 1, "demand": null, "waiting": [], "released": 0, "overflowed": 0, "abandoned": 0}"#.utf8)
        ))
    }

    func testMalformedLineStepsAreRejectedRatherThanGuessed() {
        let steps = [
            #"{"command": {"type": "createLine", "stops": [1, 2]}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "createLine", "name": "L"}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "createLine", "name": "L", "stops": ["Alpha"]}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "removeLine"}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setLineRate", "line": 1, "rate": 1.5}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setLineServiceWindow", "line": 1, "window": {"type": "allDay", "open": 0}}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setLineServiceWindow", "line": 1, "window": {"type": "hours", "open": 0}}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setLineServiceWindow", "line": 1, "window": {"type": "always"}}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setLineServiceWindow", "line": 1, "window": "allDay"}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setLineTrainsInService", "line": 1, "trains": {"peak": 1, "offPeak": 1}}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setServiceDay", "bands": [{"start": 0, "level": "rush"}]}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "setServiceDay", "bands": [{"start": 0}]}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "removeLine", "line": 1}, "expect": {"result": "unknownLine"}}"#,
            #"{"observe": {"type": "serviceLevel", "line": 1}, "expect": {"level": "peak"}}"#,
            #"{"observe": {"type": "serviceLevel", "line": 1, "gameMinutes": 0}, "expect": {"level": "rush"}}"#,
            #"{"observe": {"type": "serviceLevel", "line": 1, "gameMinutes": 0}, "expect": {"level": null}}"#,
            #"{"observe": {"type": "serviceLevel", "line": 1, "gameMinutes": 0}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "lineJourney", "line": 1}, "expect": {"found": false, "journey": {}}}"#,
            #"{"observe": {"type": "lineJourney", "line": 1}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "lineMaximumTrains", "line": 1}, "expect": {"found": true, "minutes": 3}}"#,
            #"{"observe": {"type": "lineTrainsInService", "line": 1}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "lineTrainsInService", "line": 1, "level": "rush"}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "lineHeadway", "line": 1, "level": "peak"}, "expect": {"found": false, "minutes": 3}}"#,
            #"{"observe": {"type": "lineHeadway", "line": 1, "level": "peak"}, "expect": {"found": true, "trains": 3}}"#,
            #"{"observe": {"type": "lineHeadway", "line": 1, "pattern": null, "level": "peak"}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "lineSegmentLoads", "line": 1}, "expect": {"found": false}}"#,
            #"{"observe": {"type": "lineSegmentLoads", "line": 1, "level": "peak"}, "expect": {"found": true}}"#,
            #"{"observe": {"type": "lineSegmentLoads", "line": 1, "level": "peak"}, "expect": {"found": true, "trains": 3}}"#,
            #"{"command": {"type": "assignTrain", "train": 1, "line": 1, "pattern": null}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "addLinePattern", "line": 1}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "addLinePattern", "line": 1, "calls": 2}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "removeLinePattern", "line": 1}, "expect": {"result": "ok"}}"#,
            #"{"command": {"type": "removeLine", "line": 1}, "expect": {"result": "unknownLinePattern"}}"#,
        ]
        for json in steps {
            XCTAssertThrowsError(try JSONDecoder().decode(GoldenScenario.Step.self, from: Data(json.utf8)), json)
        }
    }

    func testMalformedTrainPositionsAreRejectedRatherThanGuessed() {
        let positions = [
            #"{"type": "moving"}"#,
            #"{"x": 1, "y": 1, "heading": "east"}"#,
            // Missing, ill-typed or unknown values.
            #"{"type": "node", "x": 1, "y": 1}"#,
            #"{"type": "node", "x": 1, "y": 1, "heading": "up"}"#,
            #"{"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}}"#,
            #"{"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}, "offset": "256"}"#,
            #"{"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2}, "offset": 256}"#,
            // Fields of another type are not silently ignored.
            #"{"type": "unplaced", "x": 1, "y": 1}"#,
            #"{"type": "node", "x": 1, "y": 1, "heading": "east", "offset": 256}"#,
            #"{"type": "link", "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}, "offset": 256, "heading": "east"}"#,
            #"{"type": "link", "x": 1, "y": 1, "from": {"x": 1, "y": 1}, "to": {"x": 2, "y": 1}, "offset": 256}"#,
        ]
        for json in positions {
            XCTAssertThrowsError(try JSONDecoder().decode(TrainPositionSummary.self, from: Data(json.utf8)), json)
        }
    }

    func testDirectionOrderDoesNotMatter() throws {
        let json = #"{"type": "buildTrack", "x": 1, "y": 2, "connections": ["west", "north"]}"#

        let command = try JSONDecoder().decode(ScenarioCommand.self, from: Data(json.utf8))

        XCTAssertEqual(command, .buildTrack(GridPosition(x: 1, y: 2), [.north, .west]))
    }

    func testNonPortableNumbersAreDetected() {
        let json = #"{"a": 1.0, "b": 1e3, "c": 9007199254740992, "d": -9007199254740991, "e": 0, "f": "2.5", "g": true, "h": 012}"#

        XCTAssertEqual(
            GoldenScenarioFixtures.nonPortableNumbers(in: json),
            ["1.0", "1e3", "9007199254740992", "012"]
        )
        // A combining mark right after a quote must not hide the string's end.
        XCTAssertEqual(GoldenScenarioFixtures.nonPortableNumbers(in: #"{"s": "\#u{301}x", "n": 2.5}"#), ["2.5"])
    }
}
