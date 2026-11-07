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
                for way in ["plus", "hand"] {
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
                    let day = try Self.runDay(session.world, days: 2)
                    print("[SL628] \(layout) \(rules) tc=\(controlled) \(way): trains \(session.world.trains.count) legs \(day.legs) deadlock \(day.deadlockMinutes) longest \(day.longest) advice \(advice) \(notes.prefix(2))")
                }
            }
        }
    }
}
