import Foundation
@testable import GameCore
import XCTest

/// Decision 506: whether a save's full stations are too small or its trains
/// too few. Runs the save's world as it is and with every station expanded
/// (`STATION_CAPACITY_EXPAND=1` or `2`), so the two runs can be compared:
/// if expanding lets many more arrive, the stations were too small; if the
/// trains leaving them were already full, more room only lengthens the
/// queue. The file is the player's and stays out of the repository; run on
/// request:
///
///     STATION_CAPACITY_SAVE=<file> STATION_CAPACITY_EXPAND=0 \
///       swift test --filter StationCapacityReportTests
///
/// `STATION_CAPACITY_DAYS` how many days (default 2). Prints, for each
/// day, the arrivals, those turned away by a full station, the fares; and
/// for each station that was full at some minute, its people a day, its
/// minutes full and how full the trains were that left it while it was.
final class StationCapacityReportTests: XCTestCase {
    private struct SharedFile: Decodable {
        let game: SavedGame
    }

    func testFullStationsAgainstTheirTrains() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["STATION_CAPACITY_SAVE"] else {
            throw XCTSkip("set STATION_CAPACITY_SAVE=<file> to report a save's full stations")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let saved = try (try? JSONDecoder().decode(SharedFile.self, from: data).game)
            ?? JSONDecoder().decode(SavedGame.self, from: data)
        let days = Int64(environment["STATION_CAPACITY_DAYS"] ?? "") ?? 2
        let expand = Int(environment["STATION_CAPACITY_EXPAND"] ?? "") ?? 0
        var world = saved.world
        world.setSpeed(.normal)
        if expand > 0, let step = StationExpansion(rawValue: expand) {
            for index in world.stations.indices where !world.stations[index].isDepot {
                world.setStationExpansion(step, at: index)
            }
        }
        let start = world.clock.now.seconds
        let firstDay = start / 86_400 + 1
        print("expand \(expand): stations \(world.stations.count), lines \(world.lines.count), trains \(world.trains.count), from day \(start / 86_400) \(start % 86_400 / 60) min")

        // Per station: minutes full, and, at those minutes, the riders and
        // the capacity of the trains standing at it.
        var fullMinutes: [StationID: Int64] = [:]
        var halfMinutes: [StationID: Int64] = [:]
        var standingRiders: [StationID: Int64] = [:], standingCapacity: [StationID: Int64] = [:]
        var overflowAtStart: [StationID: Int64] = [:]
        var allRiders: Int64 = 0, allCapacity: Int64 = 0, samples: Int64 = 0
        var fullTrainSamples: Int64 = 0, trainSamples: Int64 = 0
        var dayTotals: [(day: Int64, arrived: Int64, overflowed: Int64, abandoned: Int64)] = []
        func totals() -> (Int64, Int64, Int64) {
            (world.passengers.reduce(0) { $0 + $1.arrived },
             world.passengers.reduce(0) { $0 + $1.overflowed },
             world.passengers.reduce(0) { $0 + $1.abandoned })
        }
        for record in world.passengers { overflowAtStart[record.station] = record.overflowed }
        // Run to the first midnight, then whole days.
        let end = firstDay * 86_400 + days * 86_400
        var lastMinute = world.clock.now.seconds / 60
        var dayStart = (firstDay, totals())
        var reachedFirstMidnight = false
        while world.clock.now.seconds < end {
            try world.advance(ticks: 1)
            let now = world.clock.now.seconds
            if !reachedFirstMidnight, now >= firstDay * 86_400 {
                reachedFirstMidnight = true
                dayStart = (firstDay, totals())
                for record in world.passengers { overflowAtStart[record.station] = record.overflowed }
            }
            guard reachedFirstMidnight else { lastMinute = now / 60; continue }
            let day = now / 86_400
            if day > dayStart.0 {
                let t = totals()
                dayTotals.append((dayStart.0, t.0 - dayStart.1.0, t.1 - dayStart.1.1, t.2 - dayStart.1.2))
                dayStart = (day, t)
            }
            let minute = now / 60
            guard minute != lastMinute else { continue }
            lastMinute = minute
            // Every five minutes: which stations are full, and how full the
            // trains standing at them are.
            guard minute % 5 == 0 else { continue }
            for record in world.passengers {
                let holds = world.stationCapacity(of: record.station)
                if record.waitingCount * 2 >= holds { halfMinutes[record.station, default: 0] += 5 }
                guard record.waitingCount >= holds - 50 else { continue }
                fullMinutes[record.station, default: 0] += 5
            }
            for train in world.trains {
                guard let line = world.assignedLine(of: train.id), !(world.line(id: line)?.isFreight ?? true),
                      train.capacity > 0 else { continue }
                let riders = world.riderCount(of: train.id)
                allRiders += riders
                allCapacity += train.capacity
                trainSamples += 1
                if riders * 100 >= train.capacity * 95 { fullTrainSamples += 1 }
                guard case .waitingAtStop(let stop, _)? = train.execution, train.timetable.indices.contains(stop) else { continue }
                let at = train.timetable[stop].station
                if let record = world.passengers.first(where: { $0.station == at }),
                   record.waitingCount >= world.stationCapacity(of: at) - 50 {
                    standingRiders[at, default: 0] += riders
                    standingCapacity[at, default: 0] += train.capacity
                }
            }
            samples += 1
        }
        let t = totals()
        if world.clock.now.seconds / 86_400 > dayStart.0 - 1, dayTotals.count < days {
            dayTotals.append((dayStart.0, t.0 - dayStart.1.0, t.1 - dayStart.1.1, t.2 - dayStart.1.2))
        }
        print("| day | arrived | turned away (full) | went home or gave up | fares |")
        print("| --- | --: | --: | --: | --: |")
        for row in dayTotals {
            let fares = world.accounts.days.first { $0.day == row.day }?.fareRevenue.amount ?? 0
            print("| \(row.day) | \(row.arrived) | \(row.overflowed) | \(row.abandoned) | \(fares) |")
        }
        print("trains (passenger lines), sampled every 5 min: mean load \(allCapacity > 0 ? allRiders * 100 / allCapacity : 0)%, at 95%+ \(trainSamples > 0 ? fullTrainSamples * 100 / trainSamples : 0)% of samples")
        print("| station | people/day (last) | min full/day | min half/day | turned away/day | trains standing there while full: load |")
        print("| --- | --: | --: | --: | --: | --: |")
        let lastDay = firstDay + days - 1
        let rows = world.stations.filter { (halfMinutes[$0.id] ?? 0) > 0 }
            .sorted { (fullMinutes[$0.id] ?? 0, halfMinutes[$0.id] ?? 0) > (fullMinutes[$1.id] ?? 0, halfMinutes[$1.id] ?? 0) }
        for station in rows {
            let people = world.stationCommercePeople(of: station.id, onDay: lastDay)
            let overflow = (world.passengers.first { $0.station == station.id }?.overflowed ?? 0) - (overflowAtStart[station.id] ?? 0)
            let load = (standingCapacity[station.id] ?? 0) > 0 ? "\((standingRiders[station.id] ?? 0) * 100 / standingCapacity[station.id]!)%" : "–"
            print("| \(station.id.rawValue) \(station.name) | \(people) | \((fullMinutes[station.id] ?? 0) / days) | \((halfMinutes[station.id] ?? 0) / days) | \(overflow / days) | \(load) |")
        }
        // Stations by people a day, to set the thresholds against.
        let people = world.stations.filter { !$0.isDepot }.map { world.stationCommercePeople(of: $0.id, onDay: lastDay) }.sorted()
        if !people.isEmpty {
            func at(_ p: Int) -> Int64 { people[min(people.count - 1, people.count * p / 100)] }
            print("people a day across \(people.count) stations: p25 \(at(25)), median \(at(50)), p75 \(at(75)), p90 \(at(90)), max \(people.last!)")
        }
    }
}
