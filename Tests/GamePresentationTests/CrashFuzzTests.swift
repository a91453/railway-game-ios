import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// BH8 (docs/research/BUGHUNT_CRASH_2026-10-30.md): random player commands
/// with extreme arguments against a played game, looking for traps rather
/// than wrong values. Off unless `CRASH_FUZZ=<cases>` is set, so CI skips
/// it; `CRASH_FUZZ_STEPS` (default 200) sets the commands per case. Before
/// each command it writes `[CRASH-FUZZ] case step command` to standard
/// error, so a trap's last line names the command that trapped.
@MainActor
final class CrashFuzzTests: XCTestCase {
    func testRandomCommandsDoNotTrap() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let cases = environment["CRASH_FUZZ"].flatMap({ Int($0) }), cases > 0 else {
            throw XCTSkip("set CRASH_FUZZ=<cases> to run")
        }
        let steps = environment["CRASH_FUZZ_STEPS"].flatMap { Int($0) } ?? 200
        let first = environment["CRASH_FUZZ_FIRST"].flatMap { Int($0) } ?? 0
        let policyName = environment["CRASH_FUZZ_POLICY"] ?? "third-town"
        let game = HeadlessGame.newGame(seed: 1)
        let policy = try XCTUnwrap(Policy.named(policyName, towns: game.towns, bounds: game.world.bounds))
        _ = try game.play(policy, days: Int64(environment["CRASH_FUZZ_DAYS"].flatMap { Int($0) } ?? 2))
        let start = game.world
        for index in first..<(first + cases) {
            var random = SplitMix64(seed: 0xB8_0000 + UInt64(index))
            let session = GameSession(world: start)
            session.pausesForImportantEvents = false
            for step in 0..<steps {
                if random.below(6) == 0 {
                    let ticks = [1, 10, 60, 600, 6_000, 60_000][random.below(6)]
                    note("[CRASH-FUZZ] \(index) \(step) advance \(ticks)")
                    session.advance(ticks: ticks)
                    continue
                }
                if random.below(25) == 0 {
                    note("[CRASH-FUZZ] \(index) \(step) undo/redo")
                    if random.below(2) == 0 { session.undo() } else { session.redo() }
                    continue
                }
                let edit = Self.edit(in: session.world, using: &random)
                note("[CRASH-FUZZ] \(index) \(step) \(edit)")
                _ = session.perform(edit) { _, _, _ in "" }
            }
            note("[CRASH-FUZZ] \(index) save")
            XCTAssertNil(WorldInvariantsProbe.roundTrip(session.world), "case \(index)")
        }
    }

    private func note(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    static let numbers: [Int64] = [0, 1, 2, -1, 3, 5, 30, 60, 120, 1_000, 86_400, 1 << 31, 1 << 40, 1 << 53, Int64.max, Int64.min, Int64.max - 1, -(1 << 40)]

    static func number(_ random: inout SplitMix64) -> Int64 {
        random.below(3) == 0 ? Int64(random.below(200)) - 20 : numbers[random.below(numbers.count)]
    }

    /// An `Int` argument (an ID, a count, an index, a cell) within ±2^40:
    /// `Int.min` and `Int.max` there overflow in places a tap never reaches
    /// (P3-2 and P3-3 in the report).
    static func int(_ random: inout SplitMix64) -> Int {
        Int(min(max(number(&random), -(1 << 40)), 1 << 40))
    }

    static func train(_ world: GameWorld, _ random: inout SplitMix64) -> TrainID {
        world.trains.isEmpty || random.below(8) == 0 ? TrainID(rawValue: int(&random)) : world.trains[random.below(world.trains.count)].id
    }

    static func station(_ world: GameWorld, _ random: inout SplitMix64) -> StationID {
        world.stations.isEmpty || random.below(8) == 0 ? StationID(rawValue: int(&random)) : world.stations[random.below(world.stations.count)].id
    }

    static func line(_ world: GameWorld, _ random: inout SplitMix64) -> LineID {
        world.lines.isEmpty || random.below(8) == 0 ? LineID(rawValue: int(&random)) : world.lines[random.below(world.lines.count)].id
    }

    static func bus(_ world: GameWorld, _ random: inout SplitMix64) -> BusRouteID {
        world.busRoutes.isEmpty || random.below(4) == 0 ? BusRouteID(rawValue: int(&random)) : world.busRoutes[random.below(world.busRoutes.count)].id
    }

    static func stations(_ world: GameWorld, _ random: inout SplitMix64) -> [StationID] {
        (0..<random.below(6)).map { _ in station(world, &random) }
    }

    static func type(_ random: inout SplitMix64) -> TrainType? {
        random.below(4) == 0 ? nil : TrainType.allCases[random.below(TrainType.allCases.count)]
    }

    static func targets(_ random: inout SplitMix64) -> TargetHeadways {
        func one(_ random: inout SplitMix64) -> Int64? { random.below(3) == 0 ? nil : number(&random) }
        return TargetHeadways(peak: one(&random), offPeak: one(&random), low: one(&random))
    }

    static func cell(_ world: GameWorld, _ random: inout SplitMix64) -> PlayerCommand.Edit.BusStop {
        let near = world.stations.isEmpty ? nil : world.stations[random.below(world.stations.count)].point
        let row = near.map { Int($0.y / Land.cellLength) + random.below(9) - 4 } ?? int(&random)
        let column = near.map { Int($0.x / Land.cellLength) + random.below(9) - 4 } ?? int(&random)
        return PlayerCommand.Edit.BusStop(CellPosition(row: random.below(10) == 0 ? int(&random) : row, column: column))
    }

    static func point(_ world: GameWorld, _ random: inout SplitMix64) -> PlanPoint {
        // Beyond ±2^40 a centre's square overflows (P3-1 in the report; a tap cannot get there).
        if random.below(5) == 0 { return PlanPoint(x: min(max(number(&random), -(1 << 40)), 1 << 40), y: min(max(number(&random), -(1 << 40)), 1 << 40)) }
        return PlanPoint(x: Int64(random.below(Int(world.bounds.width / 256) + 1)) * 256, y: Int64(random.below(Int(world.bounds.height / 256) + 1)) * 256)
    }

    static func span(_ random: inout SplitMix64) -> ClosedRange<Int> {
        let start = random.below(3) == 0 ? int(&random) : random.below(300) - 20
        let (end, overflow) = start.addingReportingOverflow(random.below(40))
        return overflow ? start...start : start...end
    }

    static func service(_ random: inout SplitMix64) -> BusService {
        random.below(2) == 0 ? .every(minutes: number(&random)) : .runs((0..<random.below(5)).map { _ in number(&random) })
    }

    static func edit(in world: GameWorld, using random: inout SplitMix64) -> PlayerCommand.Edit {
        let language: DisplayLanguage = .english
        switch random.below(52) {
        case 0: return .borrow(Money(number(&random)))
        case 1: return .repayLoan(Money(number(&random)))
        case 2: return .setDayPass(random.below(3) == 0 ? nil : Money(number(&random)))
        case 3: return .purchaseTrain(name: ["", "Train", String(repeating: "車", count: 300)][random.below(3)])
        case 4: return .sellTrain(train(world, &random))
        case 5: return .sellTrainWhereItStands(train(world, &random))
        case 6: return .setTrainCars(train(world, &random), cars: int(&random))
        case 7: return .setTrainType(train(world, &random), type(&random))
        case 8: return .setTrainRate(train(world, &random), rate: number(&random))
        case 9: return .reverseTrain(train(world, &random))
        case 10: return .unplaceTrain(train(world, &random))
        case 11: return .startTrainService(train(world, &random))
        case 12: return .stopTrainService(train(world, &random))
        case 13: return .assignTrain(train(world, &random), line(world, &random), pattern: random.below(2) == 0 ? nil : int(&random))
        case 14: return .unassignTrain(train(world, &random))
        case 15: return .placeTrain(train(world, &random), at: station(world, &random), heading: CompassHeading.allCases[random.below(CompassHeading.allCases.count)])
        case 16: return .staffLine(line(world, &random), headway: number(&random), type: type(&random), cars: int(&random), language: language)
        case 17: return .reformLine(line(world, &random), type: type(&random), cars: int(&random), language: language)
        case 18: return .addLineTrains(line(world, &random), count: random.below(3) == 0 ? int(&random) : random.below(6), type: type(&random), cars: random.below(3) == 0 ? int(&random) : 1 + random.below(10), targets: targets(&random), language: language)
        case 19: return .removeLineTrains(line(world, &random), count: random.below(3) == 0 ? int(&random) : random.below(6), targets: targets(&random))
        case 20: return .removeStation(station(world, &random))
        case 21: return .setStationDemand(station(world, &random), random.below(3) == 0 ? nil : StationDemand(kind: StationDemandKind.allCases[random.below(StationDemandKind.allCases.count)], dailyTrips: number(&random), hinterland: number(&random)))
        case 22: return .setStationOperationMode(station(world, &random), StationOperationMode.allCases[random.below(StationOperationMode.allCases.count)])
        case 23: return .linkTransfer(station(world, &random), station(world, &random))
        case 24: return .unlinkTransfer(station(world, &random))
        case 25: return .buildFreightYard(station(world, &random))
        case 26: return .removeFreightYard(station(world, &random))
        case 27: return .buildStationRoad(station(world, &random))
        case 28: return .setStationDepot(station(world, &random), random.below(2) == 0)
        case 29: return .createLine(name: "L", stops: stations(world, &random), targets: random.below(2) == 0 ? nil : targets(&random))
        case 30: return .duplicateLine(line(world, &random), name: "D")
        case 31: return .removeLine(line(world, &random))
        case 32: return .removeLineSellingTrains(line(world, &random))
        case 33: return .setLineStops(line(world, &random), stations(world, &random))
        case 34: return .reverseLineStops(line(world, &random))
        case 35: return .setLineWindow(line(world, &random), random.below(3) == 0 ? .allDay : .hours(open: int(&random), close: int(&random)))
        case 36: return .setLineRing(line(world, &random), random.below(2) == 0)
        case 37: return .setLineTrains(line(world, &random), TrainsInService(peak: int(&random), offPeak: int(&random), low: int(&random)), pattern: random.below(2) == 0 ? nil : int(&random))
        case 38: return .setLineTargets(line(world, &random), targets(&random), pattern: random.below(2) == 0 ? nil : int(&random))
        case 39: return .setLineDispatchPattern(line(world, &random), [DispatchPattern.even, .fromBothEnds, .staggered(minutes: number(&random))][random.below(3)])
        case 40: return .addLinePattern(line(world, &random), calls: (0..<random.below(5)).map { _ in random.below(3) == 0 ? int(&random) : random.below(8) })
        case 41: return .removeLinePattern(line(world, &random), index: random.below(3) == 0 ? int(&random) : random.below(4))
        case 42: return .setLineDepot(line(world, &random), random.below(3) == 0 ? nil : station(world, &random))
        case 43: return .placeBuilding(PlacedBuildingKind.allCases[random.below(PlacedBuildingKind.allCases.count)], at: point(world, &random), look: random.below(2) == 0 ? nil : int(&random))
        case 44: return .setZone(PlayerCommand.Edit.ZoneChoice(random.below(4) == 0 ? nil : Zone.allCases[random.below(Zone.allCases.count)]), rows: span(&random), columns: span(&random))
        case 45: return .buyMapTile(MapTile(row: random.below(3) == 0 ? int(&random) : random.below(8) - 4, column: random.below(3) == 0 ? int(&random) : random.below(8) - 4))
        case 46: return .acceptRequest(int(&random))
        case 47: return .createBusRoute(station(world, &random), stops: (0..<random.below(6)).map { _ in cell(world, &random) }, legMetres: random.below(2) == 0 ? nil : (0..<random.below(6)).map { _ in number(&random) }, service: service(&random), buses: int(&random))
        case 48: return .setBusCount(bus(world, &random), buses: int(&random))
        case 49: return .setBusRuns(bus(world, &random), service(&random))
        case 50: return .buildRoad(along: (0..<random.below(6)).map { _ in cell(world, &random) })
        default: return .createCityBusRoute(stops: (0..<random.below(6)).map { _ in cell(world, &random) }, legMetres: nil, service: service(&random), buses: random.below(3) == 0 ? int(&random) : 1 + random.below(5))
        }
    }
}

/// GameCoreTests' generator (PropertySupport.swift), repeated here: the
/// two test targets share no code.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
}

/// Encodes and decodes a world; the reason it does not come back, if not.
enum WorldInvariantsProbe {
    static func roundTrip(_ world: GameWorld) -> String? {
        do {
            let data = try JSONEncoder().encode(SavedGame(world: world))
            _ = try JSONDecoder().decode(SavedGame.self, from: data)
            return nil
        } catch {
            return "\(error)"
        }
    }
}
