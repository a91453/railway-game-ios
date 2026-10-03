import Foundation
import GameCore
import XCTest

/// Service lines (Stage Q2a, decision 22) under generated command sequences:
/// the Stage I–N operations of ``KernelDifferentialTests`` (track built and
/// removed under the lines, trains, time) mixed with line commands, mostly
/// sensible and sometimes invalid on purpose (too few stops, a station twice
/// in a row, unknown stations and lines, rates below 1, windows and days
/// that do not fit, negative counts), and lines made rings and lines again
/// (decision 49).
///
/// - **Against the reference.** Every sequence runs on GameCore and on
///   ``ReferenceWorld``; outcomes, all state (lines and the service day
///   included) and, after every step, every line's service level at three
///   times, journey, maximum, trains and headway at each level must match.
///   A refused command changes nothing.
/// - **Invariants.** Every world reached keeps them
///   (``WorldInvariants/violations(in:)``, lines included). The world each
///   case ends in loads back equal and saves to the same bytes.
///
/// A failing sequence is shrunk before it is reported, with its seed and
/// case; `PROPERTY_REPLAY=line.differential@<seed>@<case>` runs one case.
final class ServiceLinePropertyTests: XCTestCase {
    typealias Operation = KernelDifferentialTests.Operation

    static func generate(_ c: inout PropertyCase, operations count: Int) throws -> (KernelDifferentialTests.Setup, [Operation]) {
        // On the track network (Stage F3b).
        let setup = KernelDifferentialTests.makeNetworkSetup(shapes: [.balloons, .balloons, .balloons, .loopWithTails, .loopWithTails, .crossings, .ladder, .line, .line, .twoLines], using: &c.random)
        var (world, _) = try setup.build()
        var operations: [Operation] = []
        for _ in 0..<count {
            let operation = c.random.chance(3, in: 5)
                ? nextLineOperation(in: world, using: &c.random)
                : KernelDifferentialTests.nextOperation(in: world, using: &c.random)
            operations.append(operation)
            _ = KernelDifferentialTests.apply(operation, to: &world)
        }
        return (setup, operations)
    }

    /// A line operation, drawn with the world in view: mostly a line over
    /// the world's stations and values a line can have, sometimes not.
    static func nextLineOperation(in world: GameWorld, using random: inout SplitMix64) -> Operation {
        let stations = world.stations.map(\.id)
        let lines = world.lines
        let unknown = LineID(rawValue: random.element(of: [0, -1, (lines.last?.id.rawValue ?? 0) + 1, Int.max]))
        func anyLine() -> LineID {
            lines.isEmpty || random.chance(1, in: 10) ? unknown : random.element(of: lines).id
        }
        func stops() -> [StationID] {
            guard !stations.isEmpty else { return [] }
            var stops: [StationID] = []
            for _ in 0..<(2 + random.below(4)) {
                var next = random.element(of: stations)
                if next == stops.last, stations.count > 1 {
                    next = stations.first { $0 != next }!
                }
                stops.append(next)
            }
            if random.chance(1, in: 8) {
                switch random.below(4) {
                case 0: stops = Array(stops.prefix(random.below(2)))
                case 1: stops.append(stops[stops.count - 1])
                case 2: stops[random.below(stops.count)] = StationID(rawValue: random.element(of: [0, -1, 999, Int.max]))
                default: stops = [stops[0], stops[0]]
                }
            }
            return stops
        }
        switch random.below(22) {
        case 0..<4:
            // At most three lines at a time: the reference drives every line
            // after every step, and its routes are slow on purpose.
            guard lines.count < 3 else { return .setLineStops(anyLine(), stops()) }
            let name = random.chance(1, in: 12) ? random.element(of: ["", " ", "\n"]) : "L\(lines.count + 1)"
            return .createLine(name, stops())
        case 4, 5:
            return .removeLine(anyLine())
        case 6..<8:
            return .setLineStops(anyLine(), stops())
        case 8..<11:
            return .setLinePerformance(anyLine(), random.element(of: PerformanceSamples.valid + PerformanceSamples.invalid))
        case 11..<13:
            let window: ServiceWindow = switch random.below(6) {
            case 0: .allDay
            case 1: .hours(open: random.below(1440), close: 1441 + random.below(360))
            case 2: .hours(open: random.element(of: [-1, 1440, 600]), close: random.element(of: [600, 1801, 0]))
            default:
                // Mostly within the day.
                ServiceWindow.hours(open: random.below(720), close: 721 + random.below(720))
            }
            return .setLineWindow(anyLine(), window)
        case 13..<16:
            let counts = (0..<3).map { _ in random.chance(1, in: 15) ? -1 - random.below(3) : random.below(13) }
            return .setLineTrains(anyLine(), TrainsInService(peak: counts[0], offPeak: counts[1], low: counts[2]))
        case 16:
            if random.chance(1, in: 4) {
                return .setServiceDay(ServiceDay(bands: [ServiceDay.Band(start: random.element(of: [5, 0]), level: .low), ServiceDay.Band(start: random.element(of: [0, 1440, 600]), level: .peak)]))
            }
            var start = 0
            var bands: [ServiceDay.Band] = []
            while start < 1440, bands.count < 6 {
                bands.append(ServiceDay.Band(start: start, level: random.element(of: ServiceLevel.allCases)))
                start += 1 + random.below(500)
            }
            return .setServiceDay(ServiceDay(bands: bands))
        case 17, 18:
            if world.clock.isPaused, random.chance(1, in: 2) {
                return .setSpeed(.normal)
            }
            return .advance(random.below(900))
        case 19, 20:
            return .setLineRing(anyLine(), random.chance(4, in: 5))
        default:
            return .saveAndLoad
        }
    }

    func testLinesMatchTheReference() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("line.differential", cases: 30) { c in
            let (setup, operations) = try Self.generate(&c, operations: 100)
            c.note("setup: \(setup.summary), second \(setup.seconds)")

            if let failure = KernelDifferentialTests.firstProblem(setup, operations) {
                let minimal = KernelDifferentialTests.minimalFailure(setup, operations)
                c.fail("step \(failure.step): \(failure.problem)\n  minimal (\(minimal.count) of \(operations.count)): [\(minimal.map(\.description).joined(separator: ", "))]")
                return
            }

            var world = try setup.build().0
            for (index, operation) in operations.enumerated() {
                let error = KernelDifferentialTests.apply(operation, to: &world)
                switch operation {
                case .createLine, .removeLine, .setLineStops, .setLinePerformance, .setLineWindow, .setLineTrains, .setServiceDay, .setLineRing:
                    let name = "\(operation)".dropFirst().prefix { $0 != "(" }
                    counts[error.map { String("\($0)".prefix { $0 != "(" }) } ?? "ok \(name)", default: 0] += 1
                default:
                    break
                }
                for line in world.lines {
                    guard let journey = world.lineJourney(line.id) else {
                        counts["not drivable", default: 0] += 1
                        continue
                    }
                    counts["drivable", default: 0] += 1
                    if journey.isRing { counts["drivable ring", default: 0] += 1 }
                    if journey.legs.contains(where: { $0.path.distance == 0 }) { counts["a leg with no travel", default: 0] += 1 }
                    if let maximum = world.lineMaximumTrains(line.id), line.trainsInService.peak > maximum {
                        counts["capped", default: 0] += 1
                    }
                }
                let problems = WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "step \(index) \(operation): \(problems)")
            }

            let data = try encoder.encode(world)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            c.expect(loaded == world, "the world with lines did not load back equal")
            let reloaded = try encoder.encode(loaded)
            c.expect(reloaded == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] line.differential \(digest.hex) (\(summary))")
        assertVolume(ran == 30 * PropertySeeds.active.count, "every case should run")
        // Stage F3b: no floor for "a leg with no travel". On the track
        // network two stations never share a berth (on the grid they could
        // share a platform tile), so a leg between two stops always travels.
        for (event, least) in [
            ("ok createLine", 300), ("ok setLineStops", 200), ("ok setLinePerformance", 200), ("ok setLineWindow", 100),
            ("ok setLineTrains", 200), ("ok setServiceDay", 50), ("ok removeLine", 30), ("unknownLine", 50), ("invalidLineStops", 50),
            ("unknownStation", 20), ("invalidTrainPerformance", 50), ("invalidServiceWindow", 30), ("invalidTrainsInService", 30),
            ("invalidServiceDay", 20), ("drivable", 2_500), ("not drivable", 3_000), ("capped", 300),
            ("ok setLineRing", 100), ("drivable ring", 300),
        ] {
            assertVolume((counts[event] ?? 0) >= least, "too few \(event): \(summary)")
        }
    }
}
