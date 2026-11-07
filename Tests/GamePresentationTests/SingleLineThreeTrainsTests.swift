import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 628 (exploration).
@MainActor
final class SingleLineThreeTrainsTests: XCTestCase {
    static let y: Int64 = 40_000
    static let west: Int64 = 20_000
    static let km: Int64 = 1_000 * 64

    struct Layout: CustomStringConvertible {
        var stations: Int          // 2 or 3 along a single track
        var loopAt: Int?           // index of a station given a passing loop beside it (double platform) via passing-loop tool mid-leg
        var lines: [[Int]]         // stops by station index
        var description: String { "st\(stations) loop\(loopAt.map(String.init) ?? "-") lines\(lines)" }
    }

    func build(_ layout: Layout, rules: NewGameRules, controlled: Bool) throws -> GameSession {
        var world = GameWorld.newGame(rules: rules)
        if !controlled { try world.setTrafficControl(false) }
        world.setSpeed(.normal)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.network)
        session.networkBuildsDouble = false
        let length = Int64(layout.stations - 1) * 4 * Self.km
        session.tapNetwork(at: PlanPoint(x: Self.west, y: Self.y), reach: 16)
        session.tapNetwork(at: PlanPoint(x: Self.west + length, y: Self.y), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        for index in 0..<layout.stations {
            let x = Self.west + min(max(Int64(index) * 4 * Self.km, 2_000), length - 2_000)
            session.platformStationID = nil
            session.tapNetwork(at: PlanPoint(x: x, y: Self.y), reach: 64)
            session.addNetworkPlatform()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        if let loop = layout.loopAt {
            session.setNetworkMode(.passingLoop)
            let x = Self.west + Int64(loop) * 4 * Self.km + 2 * Self.km
            session.tapNetwork(at: PlanPoint(x: x, y: Self.y), reach: 64)
            session.addPassingLoop()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        session.selectTool(.select)
        let stations = session.world.stations.filter { $0.operationMode != .closed }.sorted { $0.point.x < $1.point.x }.map(\.id)
        let signal = session.world.stations.first { $0.operationMode == .closed }?.id
        for stops in layout.lines {
            for index in stops {
                session.selectStation(stations[index])
                session.addSelectedStationToLineDraft()
            }
            _ = signal
            session.createLineFromDraft()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        return session
    }

    static func runDay(_ start: GameWorld, days: Int = 1) throws -> (legs: [Int], deadlockMinutes: Int, longest: Int) {
        var world = start
        world.setSpeed(.normal)
        var legs: [TrainID: Int] = [:]
        var last: [TrainID: Int] = [:]
        var minutes = 0, run = 0, longest = 0
        for _ in 0..<(Int(GameTime.minutesPerDay) * days) {
            try world.advance(ticks: 1)
            if world.deadlockedTrains().isEmpty { run = 0 } else { minutes += 1; run += 1 }
            longest = max(longest, run)
            for train in world.trains {
                let stop: Int? = switch train.execution {
                case .waitingAtStop(let stop, _)?, .travellingToStop(let stop, _)?: stop
                default: nil
                }
                guard let stop, last[train.id] != stop else { continue }
                if last[train.id] != nil { legs[train.id, default: 0] += 1 }
                last[train.id] = stop
            }
        }
        return (world.trains.map { legs[$0.id, default: 0] }, minutes, longest)
    }

    func testExplore() throws {
        guard ProcessInfo.processInfo.environment["SINGLELINE_EXPLORE"] != nil else { throw XCTSkip("set SINGLELINE_EXPLORE") }
        let layouts: [Layout] = [
            Layout(stations: 2, loopAt: nil, lines: [[0, 1]]),
            Layout(stations: 3, loopAt: nil, lines: [[0, 1, 2]]),
            Layout(stations: 3, loopAt: 0, lines: [[0, 1, 2]]),
            Layout(stations: 3, loopAt: nil, lines: [[0, 1], [1, 2]]),
            Layout(stations: 3, loopAt: nil, lines: [[0, 1, 2], [0, 1]]),
            Layout(stations: 3, loopAt: nil, lines: [[0, 1, 2], [1, 2]]),
        ]
        for layout in layouts {
            for (rules, controlled) in [(NewGameRules.simple, true), (.simple, false), (.realistic, true)] {
                for way in ["plus", "hand", "fix"] {
                    let session = try build(layout, rules: rules, controlled: controlled)
                    var notes: [String] = []
                    let lines = session.world.lines.map(\.id)
                    if way == "plus" {
                        // Three trains overall: + on each line in turn.
                        var i = 0
                        while session.world.trains.count < 3 && i < 6 {
                            session.selectLine(lines[i % lines.count])
                            session.addTrainToSelectedLine()
                            if session.message?.kind != .success { notes.append(session.message?.text ?? "") }
                            i += 1
                        }
                    } else {
                        let stations = session.world.stations.filter { $0.operationMode != .closed }.map(\.id)
                        for index in session.world.trains.count..<3 {
                            session.purchaseTrain()
                            let train = try XCTUnwrap(session.world.trains.last).id
                            session.selectStation(stations[index % stations.count])
                            session.selectTrain(train)
                            session.placeSelectedTrain()
                            if session.message?.kind != .success { notes.append("place: " + (session.message?.text ?? "")) }
                            session.assignTrain(train, toLine: lines[index % lines.count])
                            if session.message?.kind != .success { notes.append("assign: " + (session.message?.text ?? "")) }
                        }
                        for line in lines {
                            session.selectLine(line)
                            let count = session.world.line(id: line)?.trains.count ?? 0
                            for level in ServiceLevel.allCases { session.setSelectedLineTrains(count, at: level) }
                        }
                    }
                    let advice = session.world.firstLineWithoutPlaceToPass()?.name ?? "-"
                    notes.append("assignMsg: " + String((session.message?.text ?? "").suffix(160)))
                    if way == "fix" {
                        for line in lines where session.world.singleTrackShortfall(of: line) != nil {
                            session.selectLine(line)
                            session.addPassingLoopToSelectedLine()
                            notes.append("fix: " + (session.message?.text ?? ""))
                        }
                    }
                    let day = try Self.runDay(session.world, days: 2)
                    print("[SL628] \(layout) \(rules) tc=\(controlled) \(way): trains \(session.world.trains.count) legs \(day.legs) deadlock \(day.deadlockMinutes) longest \(day.longest) advice \(advice) \(notes)")
                }
            }
        }
    }

    func testProbe() throws {
        guard ProcessInfo.processInfo.environment["SINGLELINE_EXPLORE"] != nil else { throw XCTSkip("set SINGLELINE_EXPLORE") }
        for (rules, st) in [(NewGameRules.simple, 3), (.realistic, 2)] {
            let session = try build(Layout(stations: st, loopAt: nil, lines: [Array(0..<st)]), rules: rules, controlled: true)
            let line = try XCTUnwrap(session.world.lines.first).id
            let stations = session.world.stations.map(\.id)
            for index in session.world.trains.count..<3 {
                session.purchaseTrain()
                let train = try XCTUnwrap(session.world.trains.last).id
                session.selectStation(stations[index % stations.count])
                session.selectTrain(train)
                session.placeSelectedTrain()
                print("[SL628P] place \(index): \(session.message?.text ?? "")")
                session.assignTrain(train, toLine: line)
                print("[SL628P] assign \(index): \(session.message?.text ?? "")")
            }
            session.selectLine(line)
            for level in ServiceLevel.allCases { session.setSelectedLineTrains(3, at: level) }
            print("[SL628P] \(rules) st\(st) inService \(session.world.lineTrainsInService(line, at: .peak) ?? -1) line.trains \(session.world.line(id: line)!.trains)")
            var world = session.world
            for minute in [420, 5, 30] {
                try world.advance(ticks: minute)
                for train in world.trains {
                    print("[SL628P]  t\(minute) \(train.name) pos \(String(describing: train.position)) exec \(String(describing: train.execution))")
                }
                print("[SL628P]  waits \(world.routeWaits())")
            }
        }
    }

    func testDemoOwnShortfalls() throws {
        guard ProcessInfo.processInfo.environment["SINGLELINE_EXPLORE"] != nil else { throw XCTSkip("set SINGLELINE_EXPLORE") }
        for (name, world) in [("hsr", try HighSpeedDemoTests.opened.get()), ("tra", try TRADemoTests.opened.get())] {
            for line in world.lines where !line.assignedTrains.isEmpty {
                if let s = world.passingPlaceShortfall(of: line.id, trains: line.assignedTrains.count) {
                    print("[SL628D] \(name) \(line.name) trains \(line.assignedTrains.count) others \(s.others.count) legs \(s.legs.count)")
                }
            }
            print("[SL628D] \(name) done lines \(world.lines.count)")
        }
    }

    func testProbeFix() throws {
        guard ProcessInfo.processInfo.environment["SINGLELINE_EXPLORE"] != nil else { throw XCTSkip("set SINGLELINE_EXPLORE") }
        let session = try build(Layout(stations: 3, loopAt: nil, lines: [[0, 1, 2]]), rules: .simple, controlled: true)
        let line = try XCTUnwrap(session.world.lines.first).id
        let stations = session.world.stations.map(\.id)
        for index in session.world.trains.count..<3 {
            session.purchaseTrain()
            let train = try XCTUnwrap(session.world.trains.last).id
            session.selectStation(stations[index % stations.count])
            session.selectTrain(train)
            session.placeSelectedTrain()
            session.assignTrain(train, toLine: line)
            print("[SL628F] assign: \(session.message?.text ?? "")")
        }
        session.selectLine(line)
        session.addPassingLoopToSelectedLine()
        print("[SL628F] fix: \(session.message?.text ?? "")")
        let w = session.world
        print("[SL628F] stops \(w.line(id: line)!.stops.map { w.station(id: $0)!.name }) inService \(w.lineTrainsInService(line, at: .peak) ?? -1)")
        for p in w.network.platforms { print("[SL628F] platform \(w.station(id: p.station)!.name) \(p.edge) \(p.start)-\(p.end)") }
        var world = w
        for minute in [400, 30, 30, 30] {
            try world.advance(ticks: minute)
            for train in world.trains {
                print("[SL628F]  \(train.name) pos \(String(describing: train.position)) exec \(String(describing: train.execution).prefix(80))")
            }
            print("[SL628F]  waits \(world.routeWaits().map { "\($0.train)->\($0.holder) \($0.isDeadlocked)" })")
        }
    }
}
