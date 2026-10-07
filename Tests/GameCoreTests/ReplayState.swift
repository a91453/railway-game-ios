import Foundation
import GameCore

/// What a replay fixture's checksums are taken over (Stage F3b): the game's
/// state written out line by line from its public values. Time, money and
/// the accounts; the track network and its platforms; stations and their
/// passengers; every train's place, body, path, service and timetable;
/// lines and their patterns; riders.
///
/// Positions and paths are written as the network's numbers. Other values
/// are written with GameCore's own coding of a world's values (sorted keys,
/// whole numbers), never with Swift's descriptions of types, which may
/// differ between compiler versions. So the checksums are the same on every
/// Swift CI runs, and a change to a type that keeps every value (such as
/// the grid's cases leaving it in Stage F3c) leaves them alone.
enum ReplayState {
    static func checksum(of world: GameWorld) -> String {
        var digest = Digest()
        digest.add(describe(world))
        return digest.hex
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static func json<Value: Encodable>(_ value: Value) -> String {
        guard let data = try? encoder.encode(value) else { return "unencodable" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func traversal(_ traversal: TrackTraversal) -> String {
        "\(traversal.edge.number)\(traversal.direction == .forward ? "+" : "-")"
    }

    private static func position(_ position: TrainPosition?) -> String {
        guard let position else { return "unplaced" }
        guard case .onEdge(let on, let offset) = position else { return "off the network" }
        return "\(traversal(on))@\(offset)"
    }

    private static func time(_ time: GameTime?) -> String {
        time.map { "\($0.seconds)" } ?? "-"
    }

    static func describe(_ world: GameWorld) -> String {
        var lines: [String] = []
        func line(_ text: String) { lines.append(text) }

        line("clock \(world.clock.now.seconds) \(world.clock.pendingTenths) \(world.clock.speed.rawValue)")
        line("balance \(world.economy.balance.amount) baseline \(world.accounts.fareBaseline.amount)")
        line("accounts \(json(AccountsSummary(world.accounts)))")
        for period in FinancePeriod.allCases {
            line("report \(json(ReportSummary(world.financeReport(period))))")
        }
        for node in world.network.nodes {
            line("node \(node.id.number) \(node.position.x) \(node.position.y) \(node.position.z)")
        }
        for edge in world.network.edges {
            let curve = switch edge.curve {
            case .straight: "straight"
            case .cubic(let a, let b): "cubic \(a.x) \(a.y) \(b.x) \(b.y)"
            }
            line("edge \(edge.id.number) \(edge.from.number) \(edge.to.number) \(edge.length) \(curve) \(edge.structure.rawValue)")
        }
        for platform in world.network.platforms {
            line("platform \(platform.station.rawValue) \(platform.edge.number) \(platform.start) \(platform.end)")
        }
        for station in world.stations {
            let ledger = world.passengerLedger(of: station.id)
            line("station \(station.id.rawValue) \(station.name) \(station.point.x) \(station.point.y)")
            line("  ledger \(ledger.released) \(ledger.waiting) \(ledger.riding) \(ledger.arrived) \(ledger.overflowed) \(ledger.abandoned) \(ledger.refused)")
        }
        for train in world.trains {
            let movement = train.movement
            line("train \(train.id.rawValue) \(train.name) cars \(train.cars) at \(position(train.position))")
            line("  body \(train.trailEdges.map(\.number)) rate \(movement.rate) path \(movement.edges.map(\.number)) cursor \(movement.cursor) end \(movement.end.map(String.init) ?? "-")")
            line("  performance \(json(train.performance))")
            line("  timetable \(json(train.timetable)) every \(train.timetablePeriod.map(String.init) ?? "-")")
            line("  service \(train.execution.map(json) ?? "-") times \(train.times.map(json) ?? "-")")
            line("  stopped at \(world.stationsStoppedAt(by: train.id).map(\.rawValue))")
        }
        for entry in world.lines {
            line("line \(entry.id.rawValue) \(entry.name) stops \(entry.stops.map(\.rawValue)) ring \(entry.isRing) window \(json(entry.window))")
            line("  performance \(json(entry.performance)) trains \(json(entry.trainsInService)) targets \(json(entry.targetHeadways))")
            line("  roster \(entry.trains.map(\.rawValue)) last \(time(entry.lastDispatch)) outer \(time(entry.outerLastDispatch))")
            if !entry.routePreferences.isEmpty { line(" routes \(json(entry.routePreferences))") }
            for pattern in entry.patterns {
                line("  pattern \(pattern.calls) trains \(json(pattern.trainsInService)) targets \(json(pattern.targetHeadways)) roster \(pattern.trains.map(\.rawValue)) last \(time(pattern.lastDispatch))")
                if !pattern.routePreferences.isEmpty { line("  routes \(json(pattern.routePreferences))") }
            }
        }
        line("day \(json(world.serviceDay))")
        for passengers in world.passengers {
            line("passengers \(json(PassengerSummary(passengers)))")
        }
        for riders in world.riders {
            line("riders \(riders.train.rawValue) \(json(riders.groups.map(RidingGroupSummary.init)))")
        }
        // Phase 6a: only a world with land writes it, so the recordings
        // made before it keep their checksums.
        if world.landDemand {
            line("landDemand")
        }
        for cell in world.land.cells {
            line("land \(cell.row) \(cell.column) \(cell.use.rawValue) \(cell.residents) \(cell.jobs)")
        }
        // Phase 6c-1: likewise only a world with the city's buildings on.
        if world.cityBuildings {
            line("cityBuildings")
        }
        for building in world.buildings.all {
            let cells = building.cells.map { "\($0.row),\($0.column)" }.joined(separator: " ")
            line("building \(building.id.rawValue) \(building.kind.rawValue) \(building.use.rawValue) \(building.density.rawValue) \(cells)")
        }
        return lines.joined(separator: "\n")
    }
}
