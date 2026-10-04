import Foundation
import GameCore
import XCTest

/// Adversarial saves: worlds reached by generated commands are saved, one
/// value in the JSON is changed (a number nudged or pushed to an extreme, a
/// name or enum case replaced, a key removed or added, an array element
/// dropped, repeated or swapped, a value made `null`), and the result is
/// loaded. Decision 6: bad data is refused with a `DecodingError`; whatever
/// loads must keep every documented invariant, survive another save, and
/// stay consistent under further commands (a refused command changes
/// nothing, and nothing traps).
final class SaveMutationTests: XCTestCase {
    private enum Step: CustomStringConvertible {
        case key(String)
        case index(Int)

        var description: String {
            switch self {
            case .key(let key): ".\(key)"
            case .index(let index): "[\(index)]"
            }
        }
    }

    /// Every value in `json` with its path, containers included.
    private static func paths(in json: Any, prefix: [Step] = []) -> [[Step]] {
        var found = [prefix]
        if let object = json as? [String: Any] {
            for key in object.keys.sorted() {
                found += paths(in: object[key]!, prefix: prefix + [.key(key)])
            }
        } else if let array = json as? [Any] {
            for index in array.indices {
                found += paths(in: array[index], prefix: prefix + [.index(index)])
            }
        }
        return found
    }

    /// `json` with the value at `path` replaced by `transform` of it; a
    /// `nil` result removes it from its object or array.
    private static func replacing(_ path: ArraySlice<Step>, in json: Any, _ transform: (Any) -> Any?) -> Any? {
        guard let first = path.first else { return transform(json) }
        switch first {
        case .key(let key):
            guard var object = json as? [String: Any], let child = object[key] else { return json }
            object[key] = replacing(path.dropFirst(), in: child, transform)
            return object
        case .index(let index):
            guard var array = json as? [Any], array.indices.contains(index) else { return json }
            if let value = replacing(path.dropFirst(), in: array[index], transform) {
                array[index] = value
            } else {
                array.remove(at: index)
            }
            return array
        }
    }

    /// A changed value of the same general kind, or something else entirely.
    /// An object may get one of `addedKeys` added.
    private static func mutation(
        of value: Any,
        addedKeys: [String] = ["onLink", "atNode", "movement", "position", "extra"],
        using random: inout SplitMix64
    ) -> (Any?, String) {
        if let number = value as? NSNumber, !(value is Bool) {
            let int = number.int64Value
            let choices: [(Any, String)] = [
                (NSNumber(value: int &+ 1), "+1"), (NSNumber(value: int &- 1), "-1"), (NSNumber(value: 0), "0"),
                (NSNumber(value: -int), "negated"), (NSNumber(value: Int64.max), "Int64.max"), (NSNumber(value: Int64.min), "Int64.min"),
                (NSNumber(value: 1024), "1024"), (NSNumber(value: 1.5), "1.5"), ("7", "a string"), (NSNull(), "null"),
            ]
            let choice = random.element(of: choices)
            return (choice.0, "number \(int) -> \(choice.1)")
        }
        if let string = value as? String {
            let choices = ["", " ", "north", "south", "paused", "normal", "double", "up", "atNode", "onLink", "\(string)x"]
            let choice = random.element(of: choices)
            return (choice, "string \"\(string)\" -> \"\(choice)\"")
        }
        if var array = value as? [Any] {
            switch array.isEmpty ? 3 : random.below(4) {
            case 0:
                let index = random.below(array.count)
                array.remove(at: index)
                return (array, "array: removed [\(index)]")
            case 1:
                let index = random.below(array.count)
                array.insert(array[index], at: index)
                return (array, "array: repeated [\(index)]")
            case 2:
                let a = random.below(array.count)
                let b = random.below(array.count)
                array.swapAt(a, b)
                return (array, "array: swapped [\(a)] and [\(b)]")
            default:
                return ([Any](), "array: emptied")
            }
        }
        if var object = value as? [String: Any] {
            let keys = object.keys.sorted()
            if !keys.isEmpty, random.chance(1, in: 2) {
                let key = random.element(of: keys)
                object[key] = nil
                return (object, "object: removed \"\(key)\"")
            }
            let key = random.element(of: addedKeys)
            object[key] = random.chance(1, in: 2) ? NSNull() : ["tile": ["x": 0, "y": 0], "heading": "north"]
            return (object, "object: set \"\(key)\"")
        }
        return (random.chance(1, in: 2) ? nil : NSNumber(value: 1), "removed or replaced \(value)")
    }

    func testMutatedSavesAreRefusedOrLoadIntoWorldsThatKeepEveryInvariant() throws {
        var accepted = 0
        var refused = 0
        var commandsOnLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.mutation", cases: 30) { c in
            let (setup, operations) = try KernelDifferentialTests.generate(&c, operations: 50)
            var world = try setup.build().0
            for operation in operations {
                _ = KernelDifferentialTests.apply(operation, to: &world)
            }
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            // Half the mutations avoid the map's tiles (the grid track of these worlds).
            let outsideTiles = all.filter { !$0.map(\.description).joined().hasPrefix(".map.occupied") }
            for _ in 0..<40 {
                let path = c.random.chance(1, in: 2) ? c.random.element(of: outsideTiles) : c.random.element(of: all)
                var described = ""
                let mutated = Self.replacing(path[...], in: json) { value in
                    let (result, text) = Self.mutation(of: value, using: &c.random)
                    described = text
                    return result
                }
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                // A station on tiles is on its tile; one at a point takes none
                // (Stage F1; the invariants check its position).
                for station in loaded.stations where station.point == nil {
                    c.expect(loaded.station(at: station.position) == station, "\(where_) \(described): station \(station.id.rawValue) is not on its tile")
                }
                var current = loaded
                for step in 0..<15 {
                    let operation = KernelDifferentialTests.nextOperation(in: current, using: &c.random)
                    let before = current
                    if KernelDifferentialTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                    for train in current.trains {
                        let stops = current.stationsStoppedAt(by: train.id)
                        c.expect(stops.allSatisfy { current.station(id: $0) != nil }, "a stop names a station that does not exist")
                    }
                    commandsOnLoaded += 1
                }
            }
        }
        print("[volume] save.mutation \(accepted) mutated saves loaded, \(refused) refused, \(commandsOnLoaded) commands on loaded worlds")
        assertVolume(refused > 1_000, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 500, "only \(accepted) mutated saves loaded")
    }

    /// The same for timetables (decision 19), with many mutations aimed
    /// inside them (worlds without stations or trains have none to aim at):
    /// a stop's station or time changed, a stop dropped, repeated or
    /// swapped with another, a key removed, a timetable emptied, nulled or
    /// added. Whatever loads keeps every stop at a station the world has,
    /// with times that never go back, and further commands (timetable
    /// replacements included) stay atomic.
    func testMutatedTimetablesAreRefusedOrLoadWithEveryStopAtAKnownStation() throws {
        var accepted = 0
        var refused = 0
        var timetableMutations = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.timetableMutation", cases: 30) { c in
            let (setup, operations) = try TimetablePropertyTests.generate(&c, operations: 50)
            var world = try setup.build().0
            for operation in operations {
                _ = KernelDifferentialTests.apply(operation, to: &world)
            }
            // Every train gets a timetable (none without stations).
            for train in world.trains {
                try world.setTrainTimetable(train.id, to: TimetableGenerator.valid(in: world, using: &c.random))
            }
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let outsideTiles = all.filter { !$0.map(\.description).joined().hasPrefix(".map.occupied") }
            let inTimetables = all.filter { $0.map(\.description).joined().contains(".timetable") }
            let trainObjects = all.filter { path in
                let text = path.map(\.description).joined()
                return text.hasPrefix(".trains[") && path.count == 2
            }
            for _ in 0..<40 {
                // Half aimed inside timetables and a quarter at whole trains
                // (to add or remove a "timetable" key), when the world has
                // them; the rest, and any aim that has no target, anywhere
                // but tiles.
                let path: [Step]
                let roll = c.random.below(4)
                if roll < 2, !inTimetables.isEmpty {
                    path = c.random.element(of: inTimetables)
                    timetableMutations += 1
                } else if roll == 2, !trainObjects.isEmpty {
                    path = c.random.element(of: trainObjects)
                } else {
                    path = c.random.element(of: outsideTiles)
                }
                var described = ""
                let mutated = Self.replacing(path[...], in: json) { value in
                    let (result, text) = Self.mutation(of: value, addedKeys: ["timetable", "extra"], using: &c.random)
                    described = text
                    return result
                }
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<10 {
                    let operation = c.random.chance(1, in: 2)
                        ? TimetablePropertyTests.nextTimetable(in: current, using: &c.random)
                        : KernelDifferentialTests.nextOperation(in: current, using: &c.random)
                    let before = current
                    if KernelDifferentialTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.timetableMutation \(accepted) mutated saves loaded, \(refused) refused, \(timetableMutations) inside timetables")
        assertVolume(refused > 1_000, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 500, "only \(accepted) mutated saves loaded")
        assertVolume(timetableMutations > 1_000, "only \(timetableMutations) mutations inside timetables")
    }

    /// The same for services (decision 20), with many mutations aimed at
    /// them: a phase or stop changed, a service removed, or one written onto
    /// a train (most of them plausible: a known phase and a small stop).
    /// Whatever loads keeps every service consistent with its timetable,
    /// train and stations, survives another save, and stays so under further
    /// commands and advances, which never trap.
    func testMutatedServicesAreRefusedOrLoadWithAConsistentService() throws {
        var accepted = 0
        var refused = 0
        var serviceMutations = 0
        var loadedServices = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.serviceMutation", cases: 30) { c in
            let (setup, operations) = try ServicePropertyTests.generate(&c, operations: 60)
            var world = try setup.build().0
            for operation in operations {
                _ = KernelDifferentialTests.apply(operation, to: &world)
            }
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let outsideTiles = all.filter { !$0.map(\.description).joined().hasPrefix(".map.occupied") }
            let inServices = all.filter { $0.map(\.description).joined().contains(".execution") }
            let trainObjects = all.filter { path in
                path.map(\.description).joined().hasPrefix(".trains[") && path.count == 2
            }
            for _ in 0..<40 {
                // Half aimed inside services and a quarter writing a service
                // onto a train (or removing its own), when the world has
                // them; the rest, and any aim without a target, anywhere but
                // tiles.
                let path: [Step]
                var written = false
                let roll = c.random.below(4)
                if roll < 2, !inServices.isEmpty {
                    path = c.random.element(of: inServices)
                    serviceMutations += 1
                } else if roll == 2, !trainObjects.isEmpty {
                    path = c.random.element(of: trainObjects)
                    written = true
                    serviceMutations += 1
                } else {
                    path = c.random.element(of: outsideTiles)
                }
                var described = ""
                let mutated = Self.replacing(path[...], in: json) { value in
                    guard written, var train = value as? [String: Any] else {
                        let (result, text) = Self.mutation(of: value, addedKeys: ["execution", "extra"], using: &c.random)
                        described = text
                        return result
                    }
                    if train["execution"] != nil, c.random.chance(1, in: 4) {
                        train["execution"] = nil
                        described = "service removed"
                    } else {
                        let phase = c.random.element(of: ["waiting", "travelling", "waiting", "travelling", "arrived"])
                        let stop = c.random.element(of: [0, 0, 1, 1, 2, 3, 4, -1])
                        train["execution"] = ["phase": phase, "stop": stop]
                        described = "service set to \(phase) \(stop)"
                    }
                    return train
                }
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                loadedServices += loaded.trains.count { $0.execution != nil }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<10 {
                    let operation = c.random.chance(1, in: 3)
                        ? .advance(c.random.below(40))
                        : c.random.chance(1, in: 2)
                            ? ServicePropertyTests.nextServiceOperation(in: current, using: &c.random)
                            : KernelDifferentialTests.nextOperation(in: current, using: &c.random)
                    let before = current
                    if KernelDifferentialTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.serviceMutation \(accepted) mutated saves loaded, \(refused) refused, \(serviceMutations) aimed at services, \(loadedServices) services loaded")
        assertVolume(refused > 1_000, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 500, "only \(accepted) mutated saves loaded")
        assertVolume(serviceMutations > 1_000, "only \(serviceMutations) mutations aimed at services")
        assertVolume(loadedServices > 500, "only \(loadedServices) services loaded")
    }

    /// The same for repeating timetables and turning round (decision 21),
    /// with many mutations aimed at a train's period, its stops' turns and
    /// its service's cycle, or writing a period or a cycle onto a train
    /// (mostly plausible: a small period or cycle). Whatever loads keeps
    /// every period and cycle consistent with its timetable, survives
    /// another save, and stays so under further commands and advances,
    /// which never trap.
    func testMutatedRepeatsAreRefusedOrLoadWithAConsistentService() throws {
        var accepted = 0
        var refused = 0
        var repeatMutations = 0
        var loadedRepeats = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.repeatMutation", cases: 30) { c in
            let (setup, operations) = try ServicePropertyTests.generate(&c, operations: 60, repeating: true)
            var world = try setup.build().0
            for operation in operations {
                _ = KernelDifferentialTests.apply(operation, to: &world)
            }
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let outsideTiles = all.filter { !$0.map(\.description).joined().hasPrefix(".map.occupied") }
            let inRepeats = all.filter { path in
                let text = path.map(\.description).joined()
                return text.contains(".period") || text.contains(".reverse") || text.contains(".execution")
            }
            let trainObjects = all.filter { path in
                path.map(\.description).joined().hasPrefix(".trains[") && path.count == 2
            }
            for _ in 0..<40 {
                let path: [Step]
                var written = false
                let roll = c.random.below(4)
                if roll < 2, !inRepeats.isEmpty {
                    path = c.random.element(of: inRepeats)
                    repeatMutations += 1
                } else if roll == 2, !trainObjects.isEmpty {
                    path = c.random.element(of: trainObjects)
                    written = true
                    repeatMutations += 1
                } else {
                    path = c.random.element(of: outsideTiles)
                }
                var described = ""
                let mutated = Self.replacing(path[...], in: json) { value in
                    guard written, var train = value as? [String: Any] else {
                        let (result, text) = Self.mutation(of: value, addedKeys: ["period", "cycle", "reverse", "extra"], using: &c.random)
                        described = text
                        return result
                    }
                    switch c.random.below(3) {
                    case 0:
                        let period = c.random.element(of: [1, 5, 12, 30, 60, 0, -1, Int64.max])
                        train["period"] = period
                        described = "period set to \(period)"
                    case 1:
                        train["period"] = nil
                        described = "period removed"
                    default:
                        let cycle = c.random.element(of: [0, 1, 2, 5, 100, -1, Int64.max])
                        if var execution = train["execution"] as? [String: Any] {
                            execution["cycle"] = cycle
                            train["execution"] = execution
                        } else {
                            train["execution"] = ["phase": c.random.element(of: ["waiting", "travelling"]), "stop": c.random.below(3), "cycle": cycle]
                        }
                        described = "cycle set to \(cycle)"
                    }
                    return train
                }
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                loadedRepeats += loaded.trains.count { $0.timetablePeriod != nil }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<10 {
                    let operation = c.random.chance(1, in: 3)
                        ? .advance(c.random.below(40))
                        : c.random.chance(1, in: 2)
                            ? ServicePropertyTests.nextServiceOperation(in: current, repeating: true, using: &c.random)
                            : KernelDifferentialTests.nextOperation(in: current, using: &c.random)
                    let before = current
                    if KernelDifferentialTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.repeatMutation \(accepted) mutated saves loaded, \(refused) refused, \(repeatMutations) aimed at repeats, \(loadedRepeats) repeating timetables loaded")
        assertVolume(refused > 1_000, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 500, "only \(accepted) mutated saves loaded")
        assertVolume(repeatMutations > 1_000, "only \(repeatMutations) mutations aimed at repeats")
        assertVolume(loadedRepeats > 500, "only \(loadedRepeats) repeating timetables loaded")
    }

    /// The same for service lines (decision 22), with many mutations aimed
    /// at the lines, the next line ID and the service day. Whatever loads
    /// keeps every line consistent with the world's stations and the rules
    /// for stops, rates, windows, counts and days, survives another save,
    /// and stays so under further commands, which never trap.
    func testMutatedLinesAreRefusedOrLoadWithConsistentLines() throws {
        var accepted = 0
        var refused = 0
        var lineMutations = 0
        var loadedLines = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.lineMutation", cases: 30) { c in
            let (setup, operations) = try ServiceLinePropertyTests.generate(&c, operations: 60)
            var world = try setup.build().0
            for operation in operations {
                _ = KernelDifferentialTests.apply(operation, to: &world)
            }
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let outsideTiles = all.filter { !$0.map(\.description).joined().hasPrefix(".map.occupied") }
            let inLines = all.filter { path in
                let text = path.map(\.description).joined()
                return text.hasPrefix(".lines") || text.hasPrefix(".serviceDay") || text.hasPrefix(".nextLineID")
            }
            for _ in 0..<40 {
                let path: [Step]
                if c.random.chance(3, in: 4), !inLines.isEmpty {
                    path = c.random.element(of: inLines)
                    lineMutations += 1
                } else {
                    path = c.random.element(of: outsideTiles)
                }
                let (mutated, described) = { () -> (Any?, String) in
                    var text = ""
                    let result = Self.replacing(path[...], in: json) { value in
                        let (changed, what) = Self.mutation(of: value, addedKeys: ["lines", "serviceDay", "nextLineID", "window", "extra"], using: &c.random)
                        text = what
                        return changed
                    }
                    return (result, text)
                }()
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                loadedLines += loaded.lines.count
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<10 {
                    let operation = c.random.chance(1, in: 2)
                        ? ServiceLinePropertyTests.nextLineOperation(in: current, using: &c.random)
                        : KernelDifferentialTests.nextOperation(in: current, using: &c.random)
                    let before = current
                    if KernelDifferentialTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    for line in current.lines {
                        _ = current.lineHeadway(line.id, at: .peak)
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.lineMutation \(accepted) mutated saves loaded, \(refused) refused, \(lineMutations) aimed at lines, \(loadedLines) lines loaded")
        assertVolume(refused > 1_000, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 500, "only \(accepted) mutated saves loaded")
        assertVolume(lineMutations > 1_000, "only \(lineMutations) mutations aimed at lines")
        assertVolume(loadedLines > 500, "only \(loadedLines) lines loaded")
    }

    /// Decision 23: saves of dispatching lines, mutated mostly in their
    /// trains, targets and last dispatch and in their trains' timetables and
    /// services, are refused or load into worlds that keep every invariant
    /// and keep dispatching without breaking one.
    func testMutatedDispatchIsRefusedOrLoadsConsistently() throws {
        var accepted = 0
        var refused = 0
        var aimed = 0
        var assignedLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.dispatchMutation", cases: 12) { c in
            let (setup, operations) = try LineDispatchPropertyTests.generate(&c, operations: 40)
            var world = try setup.build().0
            for operation in operations {
                _ = KernelDifferentialTests.apply(operation, to: &world)
            }
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let outsideTiles = all.filter { !$0.map(\.description).joined().hasPrefix(".map.occupied") }
            let targeted = all.filter { path in
                let text = path.map(\.description).joined()
                return text.hasPrefix(".lines") || text.contains("timetable") || text.contains("execution") || text.hasPrefix(".clock")
            }
            for _ in 0..<30 {
                let path: [Step]
                if c.random.chance(3, in: 4), !targeted.isEmpty {
                    path = c.random.element(of: targeted)
                    aimed += 1
                } else {
                    path = c.random.element(of: outsideTiles)
                }
                let (mutated, described) = { () -> (Any?, String) in
                    var text = ""
                    let result = Self.replacing(path[...], in: json) { value in
                        let (changed, what) = Self.mutation(
                            of: value, addedKeys: ["trains", "lastDispatch", "targetHeadways", "period", "extra"], using: &c.random
                        )
                        text = what
                        return changed
                    }
                    return (result, text)
                }()
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                assignedLoaded += loaded.lines.reduce(0) { $0 + $1.trains.count }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<8 {
                    let operation = c.random.chance(1, in: 2)
                        ? LineDispatchPropertyTests.nextDispatchOperation(in: current, using: &c.random)
                        : .advance(c.random.below(120))
                    let before = current
                    if KernelDifferentialTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.dispatchMutation \(accepted) mutated saves loaded, \(refused) refused, \(aimed) aimed at lines and services, \(assignedLoaded) assigned trains loaded")
        assertVolume(refused > 300, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 300, "only \(accepted) mutated saves loaded")
        assertVolume(aimed > 800, "only \(aimed) mutations aimed at lines and services")
        assertVolume(assignedLoaded > 300, "only \(assignedLoaded) assigned trains loaded")
    }

    /// Decision 24: saves of lines with patterns, mutated mostly in the
    /// patterns (their calls, counts, targets, trains and last dispatch),
    /// are refused or load into worlds that keep every invariant and keep
    /// dispatching without breaking one.
    func testMutatedPatternsAreRefusedOrLoadConsistently() throws {
        var accepted = 0
        var refused = 0
        var aimed = 0
        var patternsLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.patternMutation", cases: 10) { c in
            let (setup, operations) = try LinePatternPropertyTests.generate(&c, operations: 30)
            var world = try setup.build().0
            for operation in operations {
                _ = KernelDifferentialTests.apply(operation, to: &world)
            }
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let outsideTiles = all.filter { !$0.map(\.description).joined().hasPrefix(".map.occupied") }
            let targeted = all.filter { path in
                let text = path.map(\.description).joined()
                return text.contains("patterns") || (text.hasPrefix(".lines") && text.contains("stops"))
            }
            for _ in 0..<30 {
                let path: [Step]
                if c.random.chance(3, in: 4), !targeted.isEmpty {
                    path = c.random.element(of: targeted)
                    aimed += 1
                } else {
                    path = c.random.element(of: outsideTiles)
                }
                let (mutated, described) = { () -> (Any?, String) in
                    var text = ""
                    let result = Self.replacing(path[...], in: json) { value in
                        let (changed, what) = Self.mutation(
                            of: value, addedKeys: ["patterns", "calls", "trains", "lastDispatch", "extra"], using: &c.random
                        )
                        text = what
                        return changed
                    }
                    return (result, text)
                }()
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                patternsLoaded += loaded.lines.reduce(0) { $0 + $1.patterns.count }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<6 {
                    let operation = c.random.chance(1, in: 2)
                        ? LinePatternPropertyTests.nextPatternOperation(in: current, using: &c.random)
                        : .advance(c.random.below(120))
                    let before = current
                    if KernelDifferentialTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.patternMutation \(accepted) mutated saves loaded, \(refused) refused, \(aimed) aimed at patterns and stops, \(patternsLoaded) patterns loaded")
        assertVolume(refused > 150, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 150, "only \(accepted) mutated saves loaded")
        assertVolume(aimed > 400, "only \(aimed) mutations aimed at patterns and stops")
        assertVolume(patternsLoaded > 150, "only \(patternsLoaded) patterns loaded")
    }

    /// Stage S3 (decision 29): mutations aimed at the track network, the
    /// positions of trains on it and their bodies and paths.
    func testMutatedNetworksAreRefusedOrLoadConsistently() throws {
        var accepted = 0
        var refused = 0
        var aimed = 0
        var networkTrainsLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.networkMutation", cases: 10) { c in
            let world = try ContinuousTrackPropertyTests.generateWorld(&c, operations: 30)
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let targeted = all.filter { path in
                let text = path.map(\.description).joined()
                return text.contains("network") || text.contains("onEdge") || text.contains("trailEdges") || text.contains(".edges")
            }
            for _ in 0..<30 {
                let path: [Step]
                if c.random.chance(3, in: 4), !targeted.isEmpty {
                    path = c.random.element(of: targeted)
                    aimed += 1
                } else {
                    path = c.random.element(of: all)
                }
                let (mutated, described) = { () -> (Any?, String) in
                    var text = ""
                    let result = Self.replacing(path[...], in: json) { value in
                        let (changed, what) = Self.mutation(
                            of: value, addedKeys: ["network", "onEdge", "trailEdges", "edges", "trail", "extra"], using: &c.random
                        )
                        text = what
                        return changed
                    }
                    return (result, text)
                }()
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                networkTrainsLoaded += loaded.trains.count { if case .onEdge? = $0.position { true } else { false } }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<6 {
                    let operation = ContinuousTrackPropertyTests.operation(
                        in: current, using: &c.random, width: current.map.width, height: current.map.height
                    )
                    let before = current
                    if ContinuousTrackPropertyTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.networkMutation \(accepted) mutated saves loaded, \(refused) refused, \(aimed) aimed at the network and its trains, \(networkTrainsLoaded) trains on the network loaded")
        assertVolume(refused > 100, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 100, "only \(accepted) mutated saves loaded")
        assertVolume(aimed > 300, "only \(aimed) mutations aimed at the network")
        assertVolume(networkTrainsLoaded > 300, "only \(networkTrainsLoaded) trains on the network loaded")
    }

    /// Stage S4 (decision 30): saves of networks at several levels, with
    /// profiles, structures and platforms, mutated where the vertical
    /// railway lives: refused, or loaded as a world that keeps every
    /// invariant (grades, structures, clearance, platforms), survives saving
    /// and keeps them under further commands.
    func testMutatedThreeDimensionalNetworksAreRefusedOrLoadConsistently() throws {
        var accepted = 0
        var refused = 0
        var aimed = 0
        var raisedLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.verticalMutation", cases: 10) { c in
            let world = try VerticalRailwayPropertyTests.generateWorld(&c, operations: 30)
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let targeted = all.filter { path in
                let text = path.map(\.description).joined()
                return text.contains("network") || text.contains("platforms") || text.contains("onEdge")
            }
            for _ in 0..<30 {
                let path: [Step]
                if c.random.chance(3, in: 4), !targeted.isEmpty {
                    path = c.random.element(of: targeted)
                    aimed += 1
                } else {
                    path = c.random.element(of: all)
                }
                let (mutated, described) = { () -> (Any?, String) in
                    var text = ""
                    let result = Self.replacing(path[...], in: json) { value in
                        let (changed, what) = Self.mutation(
                            of: value, addedKeys: ["profile", "structure", "platforms", "station", "z", "network", "extra"], using: &c.random
                        )
                        text = what
                        return changed
                    }
                    return (result, text)
                }()
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                raisedLoaded += loaded.network.nodes.count { $0.position.z != 0 }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<6 {
                    let operation = VerticalRailwayPropertyTests.operation(
                        in: current, using: &c.random, width: current.map.width, height: current.map.height
                    )
                    let before = current
                    if VerticalRailwayPropertyTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.verticalMutation \(accepted) mutated saves loaded, \(refused) refused, \(aimed) aimed at the network and platforms, \(raisedLoaded) raised or sunk nodes loaded")
        assertVolume(refused > 100, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 100, "only \(accepted) mutated saves loaded")
        assertVolume(aimed > 300, "only \(aimed) mutations aimed at the vertical railway")
        assertVolume(raisedLoaded > 300, "only \(raisedLoaded) nodes off the ground loaded")
    }

    /// Stage S5 (decision 31): saves of services, lines and paths on the
    /// track network, mutated where they live (a path's edges, cursor and
    /// end, a service's phase, stop and cycle, a timetable, a line's
    /// patterns, platforms): refused, or loaded as a world that keeps every
    /// invariant (a travelling service's path ends where it stops for its
    /// next call, a waiting one stands at its station), survives saving
    /// and keeps them under further commands.
    func testMutatedNetworkServicesAreRefusedOrLoadConsistently() throws {
        var accepted = 0
        var refused = 0
        var aimed = 0
        var servicesLoaded = 0
        var endsLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.networkServiceMutation", cases: 10) { c in
            let world = try NetworkServicePropertyTests.generateWorld(&c, operations: 40)
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let targeted = all.filter { path in
                let text = path.map(\.description).joined()
                return ["movement", "execution", "timetable", "period", "onEdge", "trailEdges", "platforms", "lines"].contains { text.contains($0) }
            }
            for _ in 0..<30 {
                let path: [Step]
                if c.random.chance(3, in: 4), !targeted.isEmpty {
                    path = c.random.element(of: targeted)
                    aimed += 1
                } else {
                    path = c.random.element(of: all)
                }
                let (mutated, described) = { () -> (Any?, String) in
                    var text = ""
                    let result = Self.replacing(path[...], in: json) { value in
                        let (changed, what) = Self.mutation(
                            of: value, addedKeys: ["end", "edges", "execution", "movement", "cycle", "period", "extra"], using: &c.random
                        )
                        text = what
                        return changed
                    }
                    return (result, text)
                }()
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                for train in loaded.trains {
                    guard case .onEdge? = train.position else { continue }
                    if train.execution != nil { servicesLoaded += 1 }
                    if train.movement.end != nil { endsLoaded += 1 }
                }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<6 {
                    let operation = NetworkServicePropertyTests.operation(in: current, using: &c.random)
                    let before = current
                    if NetworkServicePropertyTests.apply(operation, to: &current) != nil, !operation.isCompound {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.networkServiceMutation \(accepted) mutated saves loaded, \(refused) refused, \(aimed) aimed at services, paths, lines and platforms, \(servicesLoaded) services on the network loaded, \(endsLoaded) paths ending part of the way along an edge loaded")
        assertVolume(refused > 100, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 100, "only \(accepted) mutated saves loaded")
        assertVolume(aimed > 300, "only \(aimed) mutations aimed at services on the network")
        assertVolume(servicesLoaded > 100, "only \(servicesLoaded) services on the network loaded")
        assertVolume(endsLoaded > 100, "only \(endsLoaded) paths ending part of the way along an edge loaded")
    }

    /// Decision 32: traffic control and reservations in saves. Mutations
    /// aim at the flag, the reservations, the resources in them and what a
    /// route is read from (positions, movements, bodies, services, platforms
    /// and edges); the flag is also flipped. Whatever loads must keep every
    /// invariant, traffic control's among them (no two trains hold the same
    /// track, a train on its way has a reservation, one standing has none).
    func testMutatedTrafficControlIsRefusedOrLoadsConsistently() throws {
        var accepted = 0
        var refused = 0
        var aimed = 0
        var flipped = 0
        var reservationsLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.trafficMutation", cases: 12) { c in
            let world = try TrafficControlPropertyTests.generateWorld(&c, operations: 40)
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let targeted = all.filter { path in
                let text = path.map(\.description).joined()
                return ["reservation", "trafficControl", "movement", "position", "trail", "execution", "platforms", "edges"].contains { text.contains($0) }
            }
            for _ in 0..<30 {
                let path: [Step]
                if c.random.chance(3, in: 4), !targeted.isEmpty {
                    path = c.random.element(of: targeted)
                    aimed += 1
                } else {
                    path = c.random.element(of: all)
                }
                let (mutated, described) = { () -> (Any?, String) in
                    var text = ""
                    let result = Self.replacing(path[...], in: json) { value in
                        if let flag = value as? Bool, c.random.chance(1, in: 2) {
                            text = "flag \(flag) -> \(!flag)"
                            flipped += 1
                            return !flag
                        }
                        let (changed, what) = Self.mutation(
                            of: value, addedKeys: ["reservation", "trafficControl", "tile", "node", "link", "edge", "extra"], using: &c.random
                        )
                        text = what
                        return changed
                    }
                    return (result, text)
                }()
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                if loaded.trains.contains(where: { !$0.reservation.isEmpty }) { reservationsLoaded += 1 }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<6 {
                    let operation = TrafficControlPropertyTests.operation(in: current, using: &c.random)
                    let before = current
                    if TrafficControlPropertyTests.apply(operation, to: &current) != nil, !operation.isCompound {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.trafficMutation \(accepted) mutated saves loaded, \(refused) refused, \(aimed) aimed at traffic control and routes, \(flipped) flags flipped, \(reservationsLoaded) loaded with reservations")
        assertVolume(refused > 100, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 50, "only \(accepted) mutated saves loaded")
        assertVolume(aimed > 200, "only \(aimed) mutations aimed at traffic control and routes")
        assertVolume(flipped > 5, "only \(flipped) flags flipped")
        assertVolume(reservationsLoaded > 30, "only \(reservationsLoaded) worlds with reservations loaded")
    }

    /// G1a (decision 34): a save's passengers either fail to load or load
    /// into a world where every passenger is accounted for, every group
    /// waits for a trip a line still takes, and play goes on keeping it so.
    func testMutatedPassengersAreRefusedOrLoadConsistently() throws {
        var accepted = 0
        var refused = 0
        var aimed = 0
        var passengersLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.passengerMutation", cases: 12) { c in
            let world = try PassengerPropertyTests.generateWorld(&c, operations: 30)
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let targeted = all.filter { path in
                let text = path.map(\.description).joined()
                return ["passengers", "lines", "stations", "clock"].contains { text.contains($0) }
            }
            for _ in 0..<30 {
                let path: [Step]
                if c.random.chance(3, in: 4), !targeted.isEmpty {
                    path = c.random.element(of: targeted)
                    aimed += 1
                } else {
                    path = c.random.element(of: all)
                }
                var described = ""
                let mutated = Self.replacing(path[...], in: json) { value in
                    let (changed, what) = Self.mutation(
                        of: value, addedKeys: ["passengers", "demand", "waiting", "remainders", "released", "extra"], using: &c.random
                    )
                    described = what
                    return changed
                }
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                if loaded.passengers.contains(where: { $0.waitingCount > 0 }) { passengersLoaded += 1 }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<6 {
                    let operation = PassengerPropertyTests.operation(in: current, using: &c.random)
                    let before = current
                    if PassengerPropertyTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.passengerMutation \(accepted) mutated saves loaded, \(refused) refused, \(aimed) aimed at passengers, lines, stations and the clock, \(passengersLoaded) loaded with passengers waiting")
        assertVolume(refused > 100, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 50, "only \(accepted) mutated saves loaded")
        assertVolume(aimed > 200, "only \(aimed) mutations aimed at passengers")
        assertVolume(passengersLoaded > 30, "only \(passengersLoaded) worlds with passengers waiting loaded")
    }

    /// G1b (decision 35): a save's riders either fail to load or load into
    /// a world where every passenger is accounted for, no train carries
    /// more than it takes and every rider is bound for a stop ahead, and
    /// play goes on keeping it so.
    func testMutatedRidersAreRefusedOrLoadConsistently() throws {
        var accepted = 0
        var refused = 0
        var aimed = 0
        var ridersLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.riderMutation", cases: 10) { c in
            var world = try BoardingPropertyTests.generateWorld(&c, operations: 40)
            // Played on until some train carries riders, if any will.
            var extra = 0
            while world.riders.isEmpty, extra < 40, !world.lines.isEmpty {
                try? world.advance(ticks: 3)
                extra += 1
            }
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let targeted = all.filter { path in
                let text = path.map(\.description).joined()
                return ["riders", "passengers", "execution", "timetable", "cars", "lines"].contains { text.contains($0) }
            }
            for _ in 0..<30 {
                let path: [Step]
                if c.random.chance(3, in: 4), !targeted.isEmpty {
                    path = c.random.element(of: targeted)
                    aimed += 1
                } else {
                    path = c.random.element(of: all)
                }
                var described = ""
                let mutated = Self.replacing(path[...], in: json) { value in
                    let (changed, what) = Self.mutation(
                        of: value, addedKeys: ["riders", "groups", "origin", "destination", "arrived", "refused", "extra"], using: &c.random
                    )
                    described = what
                    return changed
                }
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                if !loaded.riders.isEmpty { ridersLoaded += 1 }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<6 {
                    let operation = LineDispatchPropertyTests.nextDispatchOperation(in: current, using: &c.random)
                    let before = current
                    if KernelDifferentialTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.riderMutation \(accepted) mutated saves loaded, \(refused) refused, \(aimed) aimed at riders, passengers and services, \(ridersLoaded) loaded with riders")
        assertVolume(refused > 100, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 50, "only \(accepted) mutated saves loaded")
        assertVolume(aimed > 150, "only \(aimed) mutations aimed at riders")
        assertVolume(ridersLoaded > 20, "only \(ridersLoaded) worlds with riders loaded")
    }

    /// G1c (decision 36): saves of managed companies with fare rules, hours
    /// and days settled, mutated mostly in their accounts: refused, or
    /// loaded as a world that keeps every invariant (open accounts, whole
    /// dollars, rows shaped as written, days ascending) and keeps settling
    /// under further commands without breaking one.
    func testMutatedAccountsAreRefusedOrLoadConsistently() throws {
        var accepted = 0
        var refused = 0
        var aimed = 0
        var ledgersLoaded = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try runCampaign("save.accountsMutation", cases: 10) { c in
            let world = try EconomyPropertyTests.generateWorld(&c, operations: 30)
            let json = try JSONSerialization.jsonObject(with: try encoder.encode(world))
            let all = Self.paths(in: json)
            let targeted = all.filter { path in path.first.map { "\($0)" } == ".accounts" }
            for _ in 0..<30 {
                let path: [Step]
                if c.random.chance(3, in: 4), !targeted.isEmpty {
                    path = c.random.element(of: targeted)
                    aimed += 1
                } else {
                    path = c.random.element(of: all)
                }
                let (mutated, described) = { () -> (Any?, String) in
                    var text = ""
                    let result = Self.replacing(path[...], in: json) { value in
                        let (changed, what) = Self.mutation(
                            of: value, addedKeys: ["fareRules", "openedAt", "crowding", "toMeters", "extra"], using: &c.random
                        )
                        text = what
                        return changed
                    }
                    return (result, text)
                }()
                let where_ = path.map(\.description).joined()
                guard let mutated, JSONSerialization.isValidJSONObject(mutated),
                      let bytes = try? JSONSerialization.data(withJSONObject: mutated)
                else { continue }
                guard let loaded = try? JSONDecoder().decode(GameWorld.self, from: bytes) else {
                    refused += 1
                    continue
                }
                accepted += 1
                if !loaded.accounts.entries.isEmpty { ledgersLoaded += 1 }
                let problems = WorldInvariants.violations(in: loaded)
                c.expect(problems.isEmpty, "\(where_) \(described) loaded a world that breaks invariants: \(problems)")
                if let problem = WorldInvariants.roundTripProblem(of: loaded) {
                    c.fail("\(where_) \(described) loaded a world that does not survive saving: \(problem)")
                }
                var current = loaded
                for step in 0..<6 {
                    let operation: KernelDifferentialTests.Operation = switch c.random.below(4) {
                    case 0: .advance(c.random.element(of: [1, 59, 60, 61, 1_440]))
                    case 1: .setFareRules(EconomyPropertyTests.fareRules(using: &c.random))
                    case 2: .setEconomyMode(c.random.chance(1, in: 4) ? .free : .management)
                    default: KernelDifferentialTests.nextOperation(in: current, using: &c.random)
                    }
                    let before = current
                    if KernelDifferentialTests.apply(operation, to: &current) != nil {
                        c.expect(current == before, "\(where_) \(described): step \(step) \(operation) was refused but changed the world")
                    }
                    let after = WorldInvariants.violations(in: current)
                    c.expect(after.isEmpty, "\(where_) \(described): after step \(step) \(operation): \(after)")
                }
            }
        }
        print("[volume] save.accountsMutation \(accepted) mutated saves loaded, \(refused) refused, \(aimed) aimed at the accounts, \(ledgersLoaded) loaded with a ledger")
        assertVolume(refused > 100, "only \(refused) mutated saves were refused")
        assertVolume(accepted > 50, "only \(accepted) mutated saves loaded")
        assertVolume(aimed > 150, "only \(aimed) mutations aimed at the accounts")
        assertVolume(ledgersLoaded > 30, "only \(ledgersLoaded) worlds with a ledger loaded")
    }
}
