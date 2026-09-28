import GameCore
import GamePresentation
import XCTest

/// Stage M, differentially: generated sequences of UI actions (tiles, tools,
/// trains, headings, rates, sends, reversing, taking off, building, time
/// passing) drive a `GameSession`, while a shadow `GameWorld` receives the
/// GameCore commands each action stands for. After every action the two
/// worlds must be identical, and everything the train tool shows must be read
/// from the session's world. The session can therefore neither add, drop,
/// reorder nor alter a command, nor move a train by itself.
///
/// Cases are generated from fixed seeds (the same canonical seeds as the
/// GameCore property suites); a failure names the seed and case.
final class TrainSessionPropertyTests: XCTestCase {
    private static let seeds: [UInt64] = [0x5EED_A001, 0x5EED_A002, 0x5EED_A003, 0x5EED_A004]

    /// SplitMix64, as in the GameCore property support (test targets cannot
    /// share code without a shared target).
    private struct Random {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
        mutating func element<T>(of array: [T]) -> T { array[below(array.count)] }
    }

    /// An 8 x 6 network: mostly track, neighbours joined both ways at random,
    /// and a station.
    private static func makeNetwork(_ random: inout Random) throws -> GameWorld {
        var world = try makeWorld(balance: 10_000_000, speed: .normal)
        var exits: [[TrackConnections]] = Array(repeating: Array(repeating: [], count: 8), count: 6)
        for y in 0..<6 {
            for x in 0..<8 {
                if x < 7, random.below(10) < 7 {
                    exits[y][x].insert(.east)
                    exits[y][x + 1].insert(.west)
                }
                if y < 5, random.below(10) < 5 {
                    exits[y][x].insert(.south)
                    exits[y + 1][x].insert(.north)
                }
            }
        }
        let station = GridPosition(x: random.below(8), y: random.below(6))
        for y in 0..<6 {
            for x in 0..<8 where !exits[y][x].isEmpty && GridPosition(x: x, y: y) != station && random.below(10) < 9 {
                try world.buildTrack(at: GridPosition(x: x, y: y), connections: exits[y][x])
            }
        }
        try world.buildStation(named: "Yard", at: station)
        return world
    }

    private enum Action: CustomStringConvertible {
        case select(GridPosition)
        case clearSelection
        case selectTool(ConstructionTool)
        case purchase
        case selectTrain(TrainID)
        case heading(TrackDirection)
        case place
        case rate(Int64)
        case boundRate(Int64)
        case send
        case applyTool
        case reverse
        case unplace
        case advance(Int)
        case speed(GameSpeed)

        var description: String {
            switch self {
            case .select(let tile): "select \(tile)"
            case .clearSelection: "clear selection"
            case .selectTool(let tool): "tool \(tool)"
            case .purchase: "buy"
            case .selectTrain(let id): "select train \(id.rawValue)"
            case .heading(let heading): "heading \(heading)"
            case .place: "place"
            case .rate(let rate): "rate \(rate)"
            case .boundRate(let rate): "bound rate \(rate)"
            case .send: "send"
            case .applyTool: "apply tool"
            case .reverse: "reverse"
            case .unplace: "take off"
            case .advance(let ticks): "\(ticks) x 100 ms"
            case .speed(let speed): "speed \(speed)"
            }
        }
    }

    private static func nextAction(_ random: inout Random, trains: Int) -> Action {
        switch random.below(100) {
        case 0..<14: return .select(GridPosition(x: random.below(10) - 1, y: random.below(8) - 1))
        case 14..<16: return .clearSelection
        case 16..<22: return .selectTool(random.element(of: ConstructionTool.allCases))
        case 22..<27: return .purchase
        case 27..<30: return .selectTrain(TrainID(rawValue: 1 + random.below(trains + 2)))
        case 30..<33: return .heading(random.element(of: TrackDirection.allCases))
        case 33..<41: return .place
        case 41..<47: return .rate(random.element(of: [0, 32, 256, 1_024, 3_000, -1]))
        case 47..<50: return .boundRate(Int64(random.below(40)) * 32)
        case 50..<62: return .send
        case 62..<70: return .applyTool
        case 70..<73: return .reverse
        case 73..<75: return .unplace
        case 75..<96: return .advance(random.below(6))
        default: return .speed(random.element(of: GameSpeed.allCases))
        }
    }

    /// The GameCore commands `action` stands for, applied to `shadow`, given
    /// the session's UI state just before the action. Refused commands leave
    /// the shadow as it was, as GameCore guarantees.
    @MainActor
    private static func applyToShadow(_ action: Action, _ shadow: inout GameWorld, session: GameSession) {
        let id = session.selectedTrainID
        let tile = session.selection
        func place() {
            guard let id, let tile else { return }
            try? shadow.placeTrain(id, at: .atNode(tile, heading: session.placementHeading))
        }
        func send() {
            guard let id, let tile, let position = shadow.train(id: id)?.position,
                  let route = shadow.route(from: position, to: tile)
            else { return }
            try? shadow.setTrainContinuation(id, to: route)
        }
        switch action {
        case .select, .clearSelection, .selectTool, .selectTrain, .heading:
            return
        case .purchase:
            _ = try? shadow.purchaseTrain(named: "Train \(shadow.trains.count + 1)")
        case .place:
            place()
        case .rate(let rate), .boundRate(let rate):
            if let id { try? shadow.setTrainMovementRate(id, to: rate) }
        case .send:
            send()
        case .applyTool:
            guard let tile else { return }
            switch session.tool {
            case .select: return
            case .buildTrack: _ = try? shadow.buildTrack(at: tile, connections: session.trackConnections)
            case .buildStation: _ = try? shadow.buildStation(named: session.stationName, at: tile)
            case .removeTrack: try? shadow.removeTrack(at: tile)
            case .train:
                if let id, shadow.train(id: id)?.position != nil { send() } else { place() }
            }
        case .reverse:
            if let id { try? shadow.reverseTrain(id) }
        case .unplace:
            if let id { try? shadow.unplaceTrain(id) }
        case .advance(let ticks):
            try? shadow.advance(ticks: ticks)
        case .speed(let speed):
            shadow.setSpeed(speed)
        }
    }

    @MainActor
    private static func perform(_ action: Action, on session: GameSession) {
        switch action {
        case .select(let tile): session.select(tile)
        case .clearSelection: session.clearSelection()
        case .selectTool(let tool): session.selectTool(tool)
        case .purchase: session.purchaseTrain()
        case .selectTrain(let id): session.selectTrain(id)
        case .heading(let heading): session.setPlacementHeading(heading)
        case .place: session.placeSelectedTrain()
        case .rate(let rate): session.setSelectedTrainRate(rate)
        case .boundRate(let rate): session.selectedTrainRate = rate
        case .send: session.sendSelectedTrain()
        case .applyTool: session.applyTool()
        case .reverse: session.reverseSelectedTrain()
        case .unplace: session.unplaceSelectedTrain()
        case .advance(let ticks): session.advance(realElapsed: .milliseconds(100 * ticks))
        case .speed(let speed): session.setSpeed(speed)
        }
    }

    /// Runs one generated case; returns the worlds it passed through, or a
    /// failure description.
    @MainActor
    private static func runCase(seed: UInt64, index: Int, actions: Int) -> (worlds: [GameWorld], failure: String?) {
        var random = Random(state: seed ^ (UInt64(index) &* 0xD1B5_4A32_D192_ED03))
        guard let start = try? makeNetwork(&random) else { return ([], "the network did not build") }
        let session = GameSession(world: start)
        var shadow = start
        var worlds = [start]
        var log: [String] = []
        for step in 0..<actions {
            let action = nextAction(&random, trains: session.world.trains.count)
            log.append("\(step): \(action)")
            let trainsBefore = session.world.trains.count
            applyToShadow(action, &shadow, session: session)
            perform(action, on: session)
            worlds.append(session.world)
            var problems: [String] = []
            if session.world.trains.count > trainsBefore, session.selectedTrainID != session.world.trains.last?.id {
                problems.append("a newly bought train was not selected")
            }
            if session.world != shadow { problems.append("the session's world differs from GameCore run directly") }
            if session.selectedTrain != session.selectedTrainID.flatMap({ session.world.train(id: $0) }) {
                problems.append("selectedTrain is not the world's train")
            }
            if session.selectedTrainRate != (session.selectedTrain?.movement.rate ?? 0) { problems.append("the bound rate is not GameCore's") }
            if let tile = session.selection, !session.world.map.contains(tile) { problems.append("selection \(tile) left the map") }
            for train in session.world.trains {
                if let position = train.position {
                    let onTrack: Bool = switch position {
                    case .atNode(let tile, _): session.world.track(at: tile) != nil
                    case .onLink(let from, let to, let offset): (1...1023).contains(offset) && session.world.isConnected(from, to: to)
                    }
                    if !onTrack { problems.append("train \(train.id.rawValue) is off the track at \(position)") }
                    if train.positionText != position.displayText { problems.append("position text is not derived") }
                } else if train.movement != .idle || train.positionText != "Not on the track" {
                    problems.append("unplaced train \(train.id.rawValue) is not idle")
                }
            }
            if !problems.isEmpty {
                let report = "seed 0x\(String(seed, radix: 16, uppercase: true)) case \(index) step \(step): \(problems)\n" + log.suffix(12).joined(separator: "\n")
                return (worlds, report)
            }
        }
        return (worlds, nil)
    }

    func testTheSessionIsExactlyTheGameCoreCommandsItStandsFor() async throws {
        let (actions, failures) = await MainActor.run {
            var actions = 0
            var failures: [String] = []
            for seed in Self.seeds {
                for index in 0..<40 where failures.count < 3 {
                    let result = Self.runCase(seed: seed, index: index, actions: 80)
                    actions += result.worlds.count - 1
                    if let failure = result.failure { failures.append(failure) }
                }
            }
            return (actions, failures)
        }
        XCTAssertEqual(failures, [])
        XCTAssertEqual(actions, Self.seeds.count * 40 * 80)
    }

    func testReplayingTheSameActionsGivesTheSameWorlds() async throws {
        let mismatches = await MainActor.run {
            var mismatches: [String] = []
            for seed in Self.seeds {
                for index in 0..<10 {
                    let first = Self.runCase(seed: seed, index: index, actions: 60)
                    let second = Self.runCase(seed: seed, index: index, actions: 60)
                    if first.worlds != second.worlds {
                        mismatches.append("seed 0x\(String(seed, radix: 16, uppercase: true)) case \(index)")
                    }
                }
            }
            return mismatches
        }
        XCTAssertEqual(mismatches, [])
    }
}
