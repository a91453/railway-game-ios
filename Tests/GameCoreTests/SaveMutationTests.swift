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
            // Half the mutations avoid the (many) map tiles.
            let outsideTiles = all.filter { !$0.map(\.description).joined().hasPrefix(".map.tiles") }
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
                for station in loaded.stations {
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
            let outsideTiles = all.filter { !$0.map(\.description).joined().hasPrefix(".map.tiles") }
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
}
