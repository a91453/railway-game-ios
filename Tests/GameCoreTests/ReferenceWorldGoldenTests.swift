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
                model.stations.map {
                    WorldSummary.StationSummary(
                        id: $0.id, name: $0.name, x: $0.position.x, y: $0.position.y, annexes: $0.annexes.map(PositionSummary.init)
                    )
                },
                final.stations, name
            )
            let tracks = model.tiles.compactMap { position, tile -> WorldSummary.TrackSummary? in
                let layout: TrackLayout
                switch tile {
                case .track: layout = .open
                case .turnout(_, let stem): layout = .turnout(stem: stem)
                case .crossing: layout = .crossing
                case .station: return nil
                }
                let mask = model.mask(at: position)!
                return WorldSummary.TrackSummary(
                    x: position.x, y: position.y, connections: Directions(TrackConnections(rawValue: mask)), layout: LayoutSummary(layout)
                )
            }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            XCTAssertEqual(tracks, final.tracks, name)
            XCTAssertEqual(
                model.trains.map {
                    WorldSummary.TrainSummary(
                        id: $0.id, name: $0.name, position: TrainPositionSummary($0.position),
                        movement: TrainMovementSummary(rate: $0.rate, continuation: $0.continuation, cursor: $0.cursor, edges: $0.edges, end: $0.end),
                        timetable: $0.timetable.map(StopSummary.init), repeat: RepeatSummary($0.period),
                        execution: ExecutionSummary($0.service?.execution), cars: $0.cars, trail: $0.trail.map(PositionSummary.init),
                        trailEdges: $0.trailEdges
                    )
                },
                final.trains, name
            )
            XCTAssertEqual(
                WorldSummary.NetworkSummary(
                    nodes: model.networkNodes.keys.sorted().map { WorldSummary.NetworkSummary.NodeSummary(id: $0, x: model.networkNodes[$0]!.x, y: model.networkNodes[$0]!.y, z: model.networkNodes[$0]!.z) },
                    edges: model.networkEdges.keys.sorted().map {
                        let edge = model.networkEdges[$0]!
                        return WorldSummary.NetworkSummary.EdgeSummary(
                            id: $0, from: edge.from, to: edge.to, curve: CurveSummary(edge.curve), length: edge.length,
                            profile: ProfileSummary(TrackProfile(startTransition: edge.startTransition, endTransition: edge.endTransition)),
                            structure: StructureName(edge.structure)
                        )
                    },
                    platforms: model.allTrackPlatforms.map(PlatformSummary.init)
                ),
                final.network, name
            )
            XCTAssertEqual(model.lines.map(Self.summary), final.lines, name)
            XCTAssertEqual(model.serviceDay.map { BandSummary(ServiceDay.Band(start: $0.start, level: $0.level)) }, final.serviceDay, name)
        }
        XCTAssertGreaterThan(steps, 300, "the fixtures should exercise the model")
    }

    private static func apply(_ command: ScenarioCommand, to model: inout ReferenceWorld) -> StepOutcome {
        var error: GameError?
        switch command {
        case .buildTrack(let p, let connections): error = model.buildTrack(at: p, mask: connections.rawValue)
        case .buildTurnout(let p, let connections, let stem): error = model.buildTurnout(at: p, mask: connections.rawValue, stem: stem)
        case .buildCrossing(let p): error = model.buildCrossing(at: p)
        case .removeTrack(let p): error = model.removeTrack(at: p)
        case .buildStation(let name, let p): error = model.buildStation(named: name, at: p)
        case .extendStation(let id, let p): error = model.extendStation(id, to: p)
        case .purchaseTrain(let name): error = model.purchaseTrain(named: name)
        case .setTrainCars(let id, let cars): error = model.setCars(id, cars)
        case .placeTrain(let id, let position): error = model.placeTrain(id, at: position)
        case .unplaceTrain(let id): error = model.unplaceTrain(id)
        case .reverseTrain(let id): error = model.reverseTrain(id)
        case .setTrainMovementRate(let id, let rate): error = model.setRate(id, rate)
        case .setTrainContinuation(let id, let nodes): error = model.setContinuation(id, nodes)
        case .setTrainTimetable(let id, let stops, let period): error = model.setTimetable(id, stops, period: period)
        case .startTrainService(let id): error = model.startService(id)
        case .stopTrainService(let id): error = model.stopService(id)
        case .createLine(let name, let stops): error = model.createLine(named: name, stops: stops)
        case .removeLine(let id): error = model.removeLine(id)
        case .setLineStops(let id, let stops): error = model.setLineStops(id, stops)
        case .setLineRate(let id, let rate): error = model.setLineRate(id, rate)
        case .setLineServiceWindow(let id, let window): error = model.setLineWindow(id, window)
        case .setLineTrainsInService(let id, let trains, let pattern): error = model.setLineTrains(id, trains, pattern: pattern)
        case .setServiceDay(let day): error = model.setServiceDay(day)
        case .setLineTargetHeadways(let id, let headways, let pattern): error = model.setLineTargets(id, headways, pattern: pattern)
        case .assignTrain(let id, let line, let pattern): error = model.assign(id, to: line, pattern: pattern)
        case .unassignTrain(let id): error = model.unassign(id)
        case .addLinePattern(let id, let calls): error = model.addPattern(id, calls)
        case .removeLinePattern(let id, let pattern): error = model.removePattern(id, pattern)
        case .setSpeed(let speed): model.setSpeed(speed)
        case .pause: model.pause()
        case .resume: model.resume()
        case .advance(let ticks): error = model.advance(ticks: ticks)
        case .buildTrackNode(let position): error = model.buildNetworkNode(at: position)
        case .buildTrackEdge(let from, let to, let curve, let profile, let structure):
            error = model.buildNetworkEdge(from: from, to: to, curve: curve, profile: profile, structure: structure)
        case .removeTrackEdge(let edge): error = model.removeNetworkEdge(edge)
        case .removeTrackNode(let node): error = model.removeNetworkNode(node)
        case .setTrainPath(let id, let path, let end): error = model.setContinuation(id, along: path, stoppingAt: end)
        case .addTrackPlatform(let station, let edge, let start, let end): error = model.addTrackPlatform(station, on: edge, from: start, to: end)
        case .removeTrackPlatform(let station, let edge, let start): error = model.removeTrackPlatform(station, on: edge, from: start)
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
                    movement: TrainMovementSummary(rate: $0.rate, continuation: $0.continuation, cursor: $0.cursor, edges: $0.edges, end: $0.end)
                )
            })
        case .route(let start, let destination):
            return .route(model.route(from: start, to: destination))
        case .platforms(let station):
            return .platforms(model.platforms(of: station))
        case .routeToStation(let start, let station, let cars):
            return .route(model.route(from: start, toStation: station, length: ReferenceWorld.length(cars: cars)))
        case .stationStops(let train):
            return .stations(model.stationsStoppedAt(by: train))
        case .wholeTrainStops(let train):
            return .stations(model.stationsBesideWholeTrain(train))
        case .platformTracks(let station):
            return .platformTracks(model.platformTracks(of: station))
        case .timetable(let id):
            return .timetable(model.trains.first { $0.id == id.rawValue }?.timetable)
        case .execution(let id):
            return .execution(model.trains.first { $0.id == id.rawValue }.map { ExecutionSummary($0.service?.execution) })
        case .serviceLevel(let id, let time):
            return .level(model.serviceLevel(of: id, at: time))
        case .lineJourney(let id, let pattern):
            return .journey(model.lineJourney(id, pattern: pattern).map(JourneySummary.init))
        case .lineMaximumTrains(let id, let pattern):
            return .trains(model.lineMaximumTrains(id, pattern: pattern))
        case .lineTrainsInService(let id, let level, let pattern):
            return .trains(model.lineTrainsInService(id, at: level, pattern: pattern))
        case .lineHeadway(let id, let level, let pattern):
            return .minutes(model.lineHeadway(id, at: level, pattern: pattern))
        case .lineSegmentLoads(let id, let level):
            return .loads(model.lineSegmentLoads(id, at: level))
        case .exits(let p, let heading):
            return .exits(model.neighbors(of: p).filter { model.mayTurn(at: p, facing: heading, to: stepDirection(from: p, to: $0)!) })
        case .occupancy(let id):
            return .resources(model.occupiedResources(of: id))
        case .conflicts:
            return .conflicts(model.occupancyConflicts())
        case .trackSections:
            return .sections(model.trackSections())
        case .parallelTracks(let a, let b):
            return .tracks(model.parallelTracks(between: a, and: b))
        case .trackEdge(let id):
            guard case .edge(let number) = id, let edge = model.networkEdges[number] else { return .edge(nil) }
            return .edge(EdgeInfoSummary(from: edge.from, to: edge.to, length: edge.length))
        case .edgeLocation(let traversal, let distance):
            return .location(model.networkLocation(traversal, offset: distance).map(LocationSummary.init))
        case .transitions(let traversal):
            return .transitions(model.networkTransitions(after: traversal))
        case .pathToNode(let start, let node):
            return .path(model.networkRoute(from: start, to: node))
        case .bodyPath(let id):
            return .points(model.trains.first { $0.id == id.rawValue }.map(model.networkBodyPath) ?? [])
        case .edgePose(let traversal, let distance):
            return .pose(model.networkLocation(traversal, offset: distance).map(PoseSummary.init))
        case .edgeAlignment(let id):
            guard case .edge(let number) = id, let edge = model.networkEdges[number] else { return .alignment(nil) }
            return .alignment(AlignmentSummary(model.alignment(of: edge)))
        case .tunnelPortals:
            return .nodes(model.tunnelPortals)
        case .trackPlatformsAlongTrain(let id):
            return .trackPlatforms(model.trackPlatformsAlong(id).map(PlatformSummary.init))
        case .platformLevels(let id):
            return .levels(model.platformLevels(of: id).map { PlatformLevelSummary(platform: $0.0, height: $0.1, structure: $0.2) })
        case .pathToStation(let start, let station, let cars):
            return .trainPath(model.pathToStation(from: start, station: station, length: ReferenceWorld.length(cars: cars)).map(PathSummary.init))
        }
    }

    private static func summary(_ line: ReferenceWorld.Line) -> LineSummary {
        LineSummary(
            id: line.id, name: line.name, stops: line.stops.map(\.rawValue), rate: line.rate,
            window: WindowSummary(line.window), trainsInService: TrainsSummary(line.trainsInService),
            targetHeadways: TargetHeadwaysSummary(line.targetHeadways), trains: line.roster, lastDispatch: line.lastDispatch,
            patterns: line.patterns.map {
                PatternSummary(
                    calls: $0.calls, trainsInService: TrainsSummary($0.trainsInService),
                    targetHeadways: TargetHeadwaysSummary($0.targetHeadways), trains: $0.roster, lastDispatch: $0.lastDispatch
                )
            }
        )
    }
}
