/// Decision 782: a train that keeps everything of its own in its own
/// files, so two pull requests that each add a train touch no file in
/// common but ``Map3DTrainRegistry/trains``'s list (one line a train,
/// merged line by line, `.gitattributes`). Its source file (or files)
/// holds its units, its palette (an extension of ``Map3DPalette``), its
/// sets and this registration; `tools/train-models/locks/<id>.json` its
/// models' hashes and its lamps; its own test file what is particular to
/// it. ``Map3DTrainSet/all``, ``Map3DTrainSet/nearOnly``,
/// ``Map3DShowcase/catalog``, the lock, size and set tests and
/// `tools/train-models/export.swift --lock` read the registry, so none of
/// them is edited for a new train.
public struct Map3DTrainRegistration: Sendable {
    /// Its name: the stem of its lock file
    /// (`tools/train-models/locks/<id>.json`).
    public let id: String
    /// Its sets, each near one followed by its far one, in the order they
    /// join the pack after the hand-written sets (``Map3DTrainSet/all``).
    /// A set with a far set is drawn near only (``Map3DTrainSet/nearOnly``).
    let sets: [Map3DTrainSet]
    /// Its rows of the train showcase (``Map3DShowcase/catalog``), after
    /// the hand-written ones; one for each near set shown.
    let showcase: [Map3DShowcase.Entry]
    /// What `Map3DTrainSetTests` allows a car of its sets, near or far:
    /// triangles, and length in metres. Its width, height and lamps are the
    /// rules every train keeps.
    let triangles: ClosedRange<Int>
    let length: ClosedRange<Float>

    /// Whether the model `name` (a car, `set-<key>-…`, or its windows,
    /// `light-set-<key>-…`) is one of this train's.
    public func owns(_ name: String) -> Bool {
        let car = name.hasPrefix("light-") ? String(name.dropFirst("light-".count)) : name
        return sets.contains { car.hasPrefix("set-\($0.key)-") }
    }
}

enum Map3DTrainRegistry {
    /// The registered trains' sets, in the order they join the pack.
    static let sets: [Map3DTrainSet] = trains.flatMap(\.sets)

    /// The train that owns the set `key`, if it is a registered one.
    static func registration(ofSet key: String) -> Map3DTrainRegistration? {
        trains.first { train in train.sets.contains { $0.key == key } }
    }

    /// The train that owns the model `name`, if it is a registered one.
    static func registration(ofModel name: String) -> Map3DTrainRegistration? {
        trains.first { $0.owns(name) }
    }
}
