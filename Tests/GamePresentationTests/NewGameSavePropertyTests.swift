import Foundation
import GameCore
import GamePresentation
import XCTest

/// A new game as the player starts one (``GameWorld/newGame``: a managed
/// company with every switch the app turns on: tourism, the city's requests,
/// rolling-stock economics, line accounts, buildings, freight and building
/// materials), driven by generated commands of the economy and the city:
/// requests taken and declined, souvenir shops, the company's buildings
/// placed, sold and pulled down, trains bought, refitted, lengthened and
/// sold, stations and lines removed, loans, the economy switched, zones and
/// freight yards, and time passing over midnights and months.
///
/// - **Saves.** After every command the world saves as the app saves it
///   (``SavedGame``) and loads back equal: a command that leaves a record
///   the loader rejects makes the player's save unloadable.
/// - **Determinism.** Partway, the world is saved and loaded, and the rest
///   of the commands run on both: the two must end equal, so a game
///   continued from a save plays as the one never saved.
///
/// Cases are generated from fixed seeds (the GameCore campaigns' canonical
/// seeds); a failure names the seed, the case and the step.
final class NewGameSavePropertyTests: XCTestCase {
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
        mutating func chance(_ numerator: Int, in denominator: Int) -> Bool { below(denominator) < numerator }
    }

    /// One generated command, applied to a world; the text names it for a
    /// failure. Refused commands are part of the game too and leave the
    /// world as it was.
    private enum Command: CustomStringConvertible {
        case advance(Int)
        case accept(Int), decline(Int)
        case invest(AttractionID)
        case place(PlacedBuildingKind, PlanPoint), sell(PlacedBuildingID), demolish(PlacedBuildingID)
        case buyTrain(LineID?), sellTrain(TrainID), retype(TrainID, TrainType?), cars(TrainID, Int)
        case removeStation(StationID), removeLine(LineID)
        case borrow(Int64), repay(Int64)
        case economy(EconomyMode)
        case zone(Zone?, ClosedRange<Int>, ClosedRange<Int>)
        case freightYard(StationID), freightProduct(StationID, CargoKind)

        var description: String {
            switch self {
            case .advance(let ticks): "advance(\(ticks))"
            case .accept(let id): "acceptRequest(\(id))"
            case .decline(let id): "declineRequest(\(id))"
            case .invest(let id): "investInSouvenirShop(\(id.rawValue))"
            case .place(let kind, let point): "placeBuilding(\(kind), \(point.x), \(point.y))"
            case .sell(let id): "sellPlacedBuilding(\(id.rawValue))"
            case .demolish(let id): "removePlacedBuilding(\(id.rawValue))"
            case .buyTrain(let line): "purchaseTrain, assign to \(line.map { "\($0.rawValue)" } ?? "none")"
            case .sellTrain(let id): "sellTrain(\(id.rawValue))"
            case .retype(let id, let type): "setTrainType(\(id.rawValue), \(type.map { "\($0)" } ?? "nil"))"
            case .cars(let id, let cars): "setTrainCars(\(id.rawValue), \(cars))"
            case .removeStation(let id): "removeStation(\(id.rawValue))"
            case .removeLine(let id): "removeLine(\(id.rawValue))"
            case .borrow(let cents): "borrow(\(cents))"
            case .repay(let cents): "repayLoan(\(cents))"
            case .economy(let mode): "setEconomyMode(\(mode))"
            case .zone(let zone, let rows, let columns): "setZone(\(zone.map(\.rawValue) ?? "nil"), \(rows), \(columns))"
            case .freightYard(let id): "buildFreightFacility(\(id.rawValue))"
            case .freightProduct(let id, let kind): "setFreightProduct(\(id.rawValue), \(kind))"
            }
        }

        func apply(to world: inout GameWorld) {
            switch self {
            case .advance(let ticks): try? world.advance(ticks: ticks)
            case .accept(let id): try? world.acceptRequest(id)
            case .decline(let id): try? world.declineRequest(id)
            case .invest(let id): try? world.investInSouvenirShop(of: id)
            case .place(let kind, let point): _ = try? world.placeBuilding(kind, at: point)
            case .sell(let id): _ = try? world.sellPlacedBuilding(id)
            case .demolish(let id): try? world.removePlacedBuilding(id)
            case .buyTrain(let line):
                guard let train = try? world.purchaseTrain(named: "Train \(world.trains.count + 1)").id, let line else { return }
                try? world.assignTrain(train, to: line)
            case .sellTrain(let id): try? world.sellTrain(id)
            case .retype(let id, let type): try? world.setTrainType(id, to: type)
            case .cars(let id, let cars): try? world.setTrainCars(id, to: cars)
            case .removeStation(let id): try? world.removeStation(id)
            case .removeLine(let id): try? world.removeLine(id)
            case .borrow(let cents): try? world.borrow(Money(cents))
            case .repay(let cents): try? world.repayLoan(Money(cents))
            case .economy(let mode): world.setEconomyMode(mode)
            case .zone(let zone, let rows, let columns): _ = try? world.setZone(zone, rows: rows, columns: columns)
            case .freightYard(let id): try? world.buildFreightFacility(at: id)
            case .freightProduct(let id, let kind): try? world.setFreightProduct(at: id, to: kind)
            }
        }
    }

    /// A new game with two lines from the first town: one to the second
    /// town, one to the first sight (or a third town).
    private static func start() throws -> GameWorld {
        let bounds = GameWorld.newGameBounds
        let towns = Land.townCentres(seed: 1, in: bounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        let sight = world.tourism?.attractions.first?.point ?? towns[2]
        let from = PlanPoint(x: towns[0].x, y: towns[0].y + 6_144)
        let to = PlanPoint(x: sight.x, y: sight.y + 2_048)
        world = try newGameLine(through: [from, to], in: world)
        return world
    }

    /// A command drawn with the world in view.
    private static func command(in world: GameWorld, using random: inout Random) -> Command {
        let stations = world.stations.map(\.id)
        let trains = world.trains.map(\.id)
        switch random.below(40) {
        case 0..<8:
            // Minutes to hours, now and then to just past midnight, so the
            // day's settlement, requests judged and buildings' books come.
            // A game day takes seconds to run, so a case stays within about
            // two days (the month's draw and payment are unit tests').
            let minute = Int(world.clock.now.seconds / 60 % 1_440)
            if random.chance(1, in: 6) { return .advance(1_440 - minute + 1) }
            return .advance(1 + random.below(180))
        case 8..<11:
            guard let offer = world.cityRequests?.offers, !offer.isEmpty else { return .advance(60) }
            return .accept(random.element(of: offer).id)
        case 11:
            let all = (world.cityRequests?.offers ?? []) + (world.cityRequests?.active ?? [])
            guard !all.isEmpty else { return .advance(60) }
            return .decline(random.element(of: all).id)
        case 12, 13:
            guard let sights = world.tourism?.attractions, !sights.isEmpty else { return .advance(60) }
            return .invest(random.element(of: sights).id)
        case 14..<19:
            // Near a station or a sight, within about 800 m.
            var anchors = world.stations.map(\.point)
            anchors += world.tourism?.attractions.map(\.point) ?? []
            guard !anchors.isEmpty else { return .advance(60) }
            let anchor = random.element(of: anchors)
            let point = PlanPoint(x: anchor.x + Int64(random.below(96) - 48) * 1_024, y: anchor.y + Int64(random.below(96) - 48) * 1_024)
            let kind = random.chance(1, in: 2) ? .hotel : random.element(of: PlacedBuildingKind.allCases)
            return .place(kind, point)
        case 19, 20:
            guard !world.placedBuildings.isEmpty else { return .advance(60) }
            let id = random.element(of: world.placedBuildings).id
            return random.chance(2, in: 3) ? .sell(id) : .demolish(id)
        case 21, 22:
            return .buyTrain(world.lines.isEmpty ? nil : random.element(of: world.lines).id)
        case 23:
            guard !trains.isEmpty else { return .advance(60) }
            return .sellTrain(random.element(of: trains))
        case 24, 25:
            guard !trains.isEmpty else { return .advance(60) }
            let types: [TrainType?] = [nil] + TrainType.allCases.map(Optional.some)
            return .retype(random.element(of: trains), random.element(of: types))
        case 26, 27:
            guard !trains.isEmpty else { return .advance(60) }
            return .cars(random.element(of: trains), 1 + random.below(8))
        case 28:
            guard !stations.isEmpty, random.chance(1, in: 2) else { return .advance(60) }
            return .removeStation(random.element(of: stations))
        case 29:
            guard !world.lines.isEmpty, random.chance(1, in: 2) else { return .advance(60) }
            return .removeLine(random.element(of: world.lines).id)
        case 30, 31:
            let cents = Int64(1 + random.below(50)) * 10_000_000
            return random.chance(1, in: 2) ? .borrow(cents) : .repay(cents)
        case 32:
            guard random.chance(1, in: 3) else { return .advance(60) }
            return .economy(world.accounts.mode == .management ? .free : .management)
        case 33, 34:
            let row = random.below(Land.rows(in: world.bounds)), column = random.below(Land.columns(in: world.bounds))
            let zones: [Zone?] = [nil] + Zone.allCases.map(Optional.some)
            return .zone(random.element(of: zones), row...min(Land.rows(in: world.bounds) - 1, row + random.below(4)),
                         column...min(Land.columns(in: world.bounds) - 1, column + random.below(4)))
        case 35, 36:
            guard !stations.isEmpty else { return .advance(60) }
            return .freightYard(random.element(of: stations))
        case 37:
            guard !stations.isEmpty else { return .advance(60) }
            return .freightProduct(random.element(of: stations), random.element(of: CargoKind.allCases))
        default:
            return .advance(1 + random.below(120))
        }
    }

    /// The world saved as the app saves it, and loaded back.
    private static func saveAndLoad(_ world: GameWorld) throws -> (GameWorld, Data) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(SavedGame(world: world))
        return (try JSONDecoder().decode(SavedGame.self, from: data).world, data)
    }

    func testEveryCommandOfANewGameLeavesItSavableAndASaveContinuesTheSame() throws {
        let initial = try Self.start()
        let steps = 50
        for seed in Self.seeds {
            for index in 0..<2 {
                var random = Random(state: seed &+ UInt64(index) &* 0x1_0000)
                var world = initial
                var commands: [Command] = []
                let fork = 10 + random.below(steps - 20)
                var continued: GameWorld?
                for step in 0..<steps {
                    let command = Self.command(in: world, using: &random)
                    commands.append(command)
                    command.apply(to: &world)
                    if var other = continued {
                        command.apply(to: &other)
                        continued = other
                    }
                    let label = "seed \(String(seed, radix: 16)) case \(index) step \(step) \(command)"
                    let loaded: GameWorld
                    do {
                        loaded = try Self.saveAndLoad(world).0
                    } catch {
                        XCTFail("\(label): the saved world did not load: \(error)\n" + commands.map(\.description).joined(separator: "\n"))
                        return
                    }
                    XCTAssertEqual(loaded, world, "\(label): did not load back equal")
                    if step == fork { continued = loaded }
                }
                let continuedWorld = try XCTUnwrap(continued)
                if continuedWorld != world {
                    XCTFail("seed \(String(seed, radix: 16)) case \(index): the game continued from the save at step \(fork) ended differently\n"
                        + commands.map(\.description).joined(separator: "\n"))
                } else {
                    XCTAssertEqual(try Self.saveAndLoad(continuedWorld).1, try Self.saveAndLoad(world).1,
                                   "seed \(String(seed, radix: 16)) case \(index): the two saves differ")
                }
            }
        }
    }
}
