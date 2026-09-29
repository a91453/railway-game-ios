import Foundation
import GameCore
import XCTest

/// The reference model used by ``KernelDifferentialTests`` must itself be
/// right: every golden scenario (expectations written by hand from the
/// rules) is replayed on ``ReferenceWorld`` instead of GameCore, and every
/// outcome, observation and final state must match the fixture.
final class ReferenceWorldGoldenTests: XCTestCase {
    func testTheReferenceModelPassesEveryGoldenScenario() throws {
        var steps = 0
        for url in try GoldenScenarioFixtures.urls() {
            let scenario = try GoldenScenario.decode(Data(contentsOf: url))
            let name = url.lastPathComponent
            let initial = scenario.initialState
            var model = ReferenceWorld(
                width: initial.mapWidth, height: initial.mapHeight, balance: initial.balance,
                costs: initial.costs.constructionCosts, minutes: initial.gameMinutes, speed: initial.speed.speed
            )
            for (index, step) in scenario.steps.enumerated() {
                steps += 1
                switch step {
                case .command(let command, let expect):
                    let before = model
                    let outcome = Self.apply(command, to: &model)
                    XCTAssertEqual(outcome, expect, "\(name) steps[\(index)]")
                    if case .rejected = outcome {
                        XCTAssertEqual(model, before, "\(name) steps[\(index)] refused but changed the model")
                    }
                case .observe(let observation, let expect):
                    XCTAssertEqual(Self.answer(observation, in: model), expect, "\(name) steps[\(index)]")
                }
            }
            let final = scenario.expectedFinalState
            XCTAssertEqual(model.minutes, final.gameMinutes, name)
            XCTAssertEqual(model.speed, final.speed.speed, name)
            XCTAssertEqual(model.balance, final.balance, name)
            XCTAssertEqual(
                model.stations.map { WorldSummary.StationSummary(id: $0.id, name: $0.name, x: $0.position.x, y: $0.position.y) },
                final.stations, name
            )
            let tracks = model.tiles.compactMap { position, tile -> WorldSummary.TrackSummary? in
                guard case .track(let mask) = tile else { return nil }
                return WorldSummary.TrackSummary(x: position.x, y: position.y, connections: Directions(TrackConnections(rawValue: mask)))
            }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            XCTAssertEqual(tracks, final.tracks, name)
            XCTAssertEqual(
                model.trains.map {
                    WorldSummary.TrainSummary(
                        id: $0.id, name: $0.name, position: TrainPositionSummary($0.position),
                        movement: TrainMovementSummary(rate: $0.rate, continuation: $0.continuation, cursor: $0.cursor),
                        timetable: $0.timetable.map(StopSummary.init), repeat: RepeatSummary($0.period),
                        execution: ExecutionSummary($0.service?.execution)
                    )
                },
                final.trains, name
            )
        }
        XCTAssertGreaterThan(steps, 300, "the fixtures should exercise the model")
    }

    private static func apply(_ command: ScenarioCommand, to model: inout ReferenceWorld) -> StepOutcome {
        var error: GameError?
        switch command {
        case .buildTrack(let p, let connections): error = model.buildTrack(at: p, mask: connections.rawValue)
        case .removeTrack(let p): error = model.removeTrack(at: p)
        case .buildStation(let name, let p): error = model.buildStation(named: name, at: p)
        case .purchaseTrain(let name): error = model.purchaseTrain(named: name)
        case .placeTrain(let id, let position): error = model.placeTrain(id, at: position)
        case .unplaceTrain(let id): error = model.unplaceTrain(id)
        case .reverseTrain(let id): error = model.reverseTrain(id)
        case .setTrainMovementRate(let id, let rate): error = model.setRate(id, rate)
        case .setTrainContinuation(let id, let nodes): error = model.setContinuation(id, nodes)
        case .setTrainTimetable(let id, let stops, let period): error = model.setTimetable(id, stops, period: period)
        case .startTrainService(let id): error = model.startService(id)
        case .stopTrainService(let id): error = model.stopService(id)
        case .setSpeed(let speed): model.setSpeed(speed)
        case .pause: model.pause()
        case .resume: model.resume()
        case .advance(let ticks): error = model.advance(ticks: ticks)
        }
        return error.map { .rejected($0) } ?? .ok
    }

    private static func answer(_ observation: ScenarioObservation, in model: ReferenceWorld) -> ObservationAnswer {
        switch observation {
        case .connectedNeighbors(let p):
            return .neighbors(model.neighbors(of: p))
        case .isConnected(let p, let q):
            return .connected(model.joined(p, q))
        case .train(let id):
            return .train(model.trains.first { $0.id == id.rawValue }.map {
                TrainState(
                    position: TrainPositionSummary($0.position),
                    movement: TrainMovementSummary(rate: $0.rate, continuation: $0.continuation, cursor: $0.cursor)
                )
            })
        case .route(let start, let destination):
            return .route(model.route(from: start, to: destination))
        case .platforms(let station):
            return .platforms(model.platforms(of: station))
        case .routeToStation(let start, let station):
            return .route(model.route(from: start, toStation: station))
        case .stationStops(let train):
            return .stations(model.stationsStoppedAt(by: train))
        case .timetable(let id):
            return .timetable(model.trains.first { $0.id == id.rawValue }?.timetable)
        case .execution(let id):
            return .execution(model.trains.first { $0.id == id.rawValue }.map { ExecutionSummary($0.service?.execution) })
        }
    }
}
