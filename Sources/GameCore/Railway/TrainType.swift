// Train types: how many passengers a car carries and how many doors it has
// (Phase 7 groundwork, ported from the owner's `Ci/` reference's
// `TRAIN_TYPES`). A train rates `round(ppc × cars)` (`getTrainCap`) and takes
// `round(rated × 1.1)` (`getMetroTrainOperationalCap`,
// `METRO_TRAIN_OPERATIONAL_LOAD_FACTOR`), but for a type that never
// overloads.
//
// Since decision 225 each type's numbers are a row of the built-in catalog
// (`TrainTypeCatalog.swift`, which says where each number comes from); a
// type is its row, known by its code.

/// A type of train car (the reference's `TRAIN_TYPES`): what a car is rated
/// to carry and how many doors it has, one row of ``TrainTypeCatalog``. A
/// train without a type has the standard car of G1b: 320 passengers and four
/// doors.
public struct TrainType: RawRepresentable, Hashable, Codable, CaseIterable, Sendable {
    /// Its row in ``TrainTypeCatalog/builtIn``.
    let row: Int

    /// The type with code `rawValue`, or `nil` for a code no type has.
    public init?(rawValue: String) {
        guard let row = TrainTypeCatalog.rowByCode[rawValue] else { return nil }
        self.row = row
    }

    private init(row: Int) {
        self.row = row
    }

    /// A type the catalog lists; traps on a code it does not.
    private init(listed code: String) {
        guard let type = Self(rawValue: code) else { preconditionFailure("No train type has the code \(code).") }
        self = type
    }

    /// Its code: what saves, golden scenarios and replays store.
    public var rawValue: String { TrainTypeCatalog.builtIn[row].code }

    /// Its row of the catalog.
    public var spec: TrainTypeSpec { TrainTypeCatalog.builtIn[row] }

    /// Every type, in the catalog's order.
    public static let allCases: [TrainType] = TrainTypeCatalog.builtIn.indices.map(TrainType.init(row:))

    public static let a = TrainType(listed: "A")
    public static let b = TrainType(listed: "B")
    public static let c = TrainType(listed: "C")
    public static let l = TrainType(listed: "L")
    public static let d = TrainType(listed: "D")
    public static let apm = TrainType(listed: "APM")
    public static let maglev = TrainType(listed: "MAGLEV")
    public static let skyRail = TrainType(listed: "SKYRAIL")
    public static let monorail = TrainType(listed: "MONORAIL")
    /// A steam train of the 1890s (decision 153): small four-wheeled
    /// coaches behind a tank engine, slow on its way. Not one of the
    /// reference's types.
    public static let steam = TrainType(listed: "STEAM")
    /// A high-speed train set (decision 168): long cars with two doors a
    /// side, rated 80 persons, which never takes more than it is rated for.
    /// Not one of the reference's `TRAIN_TYPES`: its `HSR_TRAIN_*` options.
    public static let highSpeed = TrainType(listed: "HSR")
    /// The Taiwan Railway's EMU3000 express (decision 169): twelve cars of
    /// 45 seats, two doors a side. Not one of the reference's types: neither
    /// reference has a Taiwanese train but its high-speed options.
    public static let emu3000 = TrainType(listed: "EMU3000")

    /// The reference's main types, offered everywhere
    /// (`LINE_TRAIN_TYPE_MAIN`); the others are its extras
    /// (`LINE_TRAIN_TYPE_EXTRA`).
    public static let main: [TrainType] = allCases.filter { $0.spec.offer == .referenceMain }

    /// The reference's types (`TRAIN_TYPES`), main and extra: every type
    /// but this project's own (the steam train of decision 153, the
    /// high-speed set of decision 168 and the EMU3000 of decision 169).
    public static let reference: [TrainType] = allCases.filter { [.referenceMain, .referenceExtra].contains($0.spec.offer) }

    /// The types a world without an era offers: every type but those only
    /// an era offers (decisions 153, 168 and 169).
    public static let offered: [TrainType] = allCases.filter { $0.spec.offer != .eraOnly }

    /// The type the reference gives a new line (`_lineFormState.type`, and
    /// `normalizeLineTrainTypeForCityKey`'s fallback).
    public static let referenceDefault: TrainType = .b

    /// Passengers a car is rated for (`TRAIN_TYPES[type].ppc`).
    public var ratedCapacityPerCar: Int64 { TrainTypeCatalog.builtIn[row].ratedCapacityPerCar }

    /// Whether a train of this type takes up to 1.1 times what it is rated
    /// for (`METRO_TRAIN_OPERATIONAL_LOAD_FACTOR`): every type but the
    /// high-speed set, which never overloads (decision 168).
    public var overloads: Bool { TrainTypeCatalog.builtIn[row].overloads }

    /// Doors on a car's platform side (gap: the reference has no doors).
    public var doorsPerCar: Int64 { TrainTypeCatalog.builtIn[row].doorsPerCar }

    /// How a train of this type runs, when the type has its own way
    /// (decision 153): the steam train's ``TrainPerformance/steam``, the
    /// high-speed set's ``TrainPerformance/highSpeed`` (`PERF_HSR`) and the
    /// EMU3000's ``TrainPerformance/emu3000``. Every other type runs as the
    /// train is set to.
    public var performance: TrainPerformance? { TrainTypeCatalog.builtIn[row].performance }

    /// Its family in the catalogue (decision 224).
    public var family: TrainFamily { TrainTypeCatalog.builtIn[row].family }

    /// Whether it is a high-speed set (decision 168): its family is high
    /// speed.
    public var isHighSpeed: Bool { TrainTypeCatalog.builtIn[row].family == .highSpeed }

    /// Reads a code; a code no type has does not read, as the type's codes
    /// did when they were an enum's raw values.
    public init(from decoder: any Decoder) throws {
        let code = try decoder.singleValueContainer().decode(String.self)
        guard let type = Self(rawValue: code) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Cannot initialize TrainType from invalid String value \(code)"
            ))
        }
        self = type
    }

    /// Writes its code.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension Train {
    /// Passengers each car is rated for: its type's, or the standard 320.
    public var ratedCapacityPerCar: Int64 {
        type?.ratedCapacityPerCar ?? Self.ratedCapacityPerCar
    }

    /// Doors on each car's platform side: its type's, or the standard four.
    public var doorsPerCar: Int64 {
        type?.doorsPerCar ?? ServiceDwell.doorsPerCar
    }

    /// How many passengers the train is rated for: its cars × its car's
    /// rated capacity (the reference's `round(ppc × cars)`, exact here).
    public var ratedCapacity: Int64 {
        Int64(cars) * ratedCapacityPerCar
    }

    /// How many passengers the train takes at most (G1b): its rated capacity
    /// × 1.1, rounded half up (the reference's
    /// `round(rated × METRO_TRAIN_OPERATIONAL_LOAD_FACTOR)`). For a train
    /// without a type, its cars × 352, as before types. A high-speed set
    /// takes no more than it is rated for (decision 168).
    public var capacity: Int64 {
        guard type?.overloads ?? true else { return ratedCapacity }
        return (ratedCapacity * 11 + 5) / 10
    }

    /// How many passengers get off, or on, in a second: through every door
    /// of every car (see ``ServiceDwell/passengersPerDoorPerSecond``).
    public var passengersPerSecond: Int64 {
        ServiceDwell.passengersPerDoorPerSecond * doorsPerCar * Int64(cars)
    }

    /// The whole seconds `count` passengers take to get off or on, rounded
    /// up (see ``ServiceDwell/exchangeSeconds(_:cars:)``), in a crowd of
    /// `crowd` thousandths of the train's rating at its doors (decision 169,
    /// see ``DoorCrowding``); none, as before it.
    func exchangeSeconds(_ count: Int64, crowd: Int64 = 0) -> Int64 {
        DoorCrowding.exchangeSeconds(count, rate: passengersPerSecond, crowd: crowd)
    }
}
