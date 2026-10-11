// Train types: how many passengers a car carries and how many doors it has
// (Phase 7 groundwork), ported from the owner's `Ci/` reference
// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
//
// - `TRAIN_TYPES` rates each type's car in persons (`ppc`): A 310, B 260,
//   C 200, L 243, D 230, APM 138, maglev 240, sky rail 140, monorail 224;
//   `LINE_TRAIN_TYPE_MAIN` is A, B and C, `LINE_TRAIN_TYPE_EXTRA` the rest;
// - `getTrainCap` rates a train `round(ppc × cars)`, and
//   `getMetroTrainOperationalCap` lets it take `round(rated × 1.1)`
//   (`METRO_TRAIN_OPERATIONAL_LOAD_FACTOR`).
//
// The reference has no doors: its boarding is instant and its dwell fixed.
// The door count of each type is this project's (gap), as the four doors of
// the standard car already were (``ServiceDwell/doorsPerCar``).
//
// The steam train (decision 153) is this project's too: the references have
// no steam train or 19th-century car. It is the era type of the Liu
// Mingchuan Railway challenge.
//
// The high-speed set (decision 168) comes from the reference's HSR options
// (`HSR_TRAIN_CARS_CAPACITY` 650, 1,200 and 1,283 persons for 8, 16 and 17
// cars: set totals, where this model rates each car, so a car is rated 80,
// 640 and 1,280 for 8 and 16 cars) and its rule that a high-speed train
// never overloads (`metroTrainUsesOperationalOverload` is false for
// `lineKind === "hsr"`): it takes what it is rated for, not 1.1 times.
//
// The Taiwan Railway's EMU3000 (decision 169), the express the 3D city view
// draws, is in neither reference. A car is rated 45 persons: the set's
// rated 538 (the Wikipedia page of the type, which gives the cars' seats and
// their total as the set's `編組定員`; Taiwan News repeats the 538) over its 12
// cars, 44.8 rounded. Two doors a side, as the owner's fleet catalogue counts
// them from photographs (`fleet/catalog.json`, `emu3000-mid`: 「每節每側 2 門
// 在客室兩端」, marked inferred) and as the city view draws them. It takes
// 1.1 times what it is rated for, as every type but the high-speed set does,
// and runs as the owner's `PERF_RULES` have the EMU3000 express run
// (``TrainPerformance/emu3000``: 135 km/h, which the performance menu has
// offered since the performance presets).

/// A type of train car (the reference's `TRAIN_TYPES`): what a car is rated
/// to carry and how many doors it has on the platform side. A train without
/// a type has the standard car of G1b: 320 passengers and four doors.
public enum TrainType: String, CaseIterable, Codable, Sendable {
    case a = "A"
    case b = "B"
    case c = "C"
    case l = "L"
    case d = "D"
    case apm = "APM"
    case maglev = "MAGLEV"
    case skyRail = "SKYRAIL"
    case monorail = "MONORAIL"
    /// A steam train of the 1890s (decision 153): small four-wheeled
    /// coaches behind a tank engine, slow on its way. Not one of the
    /// reference's types.
    case steam = "STEAM"
    /// A high-speed train set (decision 168): long cars with two doors a
    /// side, rated 80 persons, which never takes more than it is rated for.
    /// Not one of the reference's `TRAIN_TYPES`: its `HSR_TRAIN_*` options.
    case highSpeed = "HSR"
    /// The Taiwan Railway's EMU3000 express (decision 169): twelve cars of
    /// 45 seats, two doors a side. Not one of the reference's types: neither
    /// reference has a Taiwanese train but its high-speed options.
    case emu3000 = "EMU3000"

    /// The reference's main types, offered everywhere
    /// (`LINE_TRAIN_TYPE_MAIN`); the others are its extras
    /// (`LINE_TRAIN_TYPE_EXTRA`).
    public static let main: [TrainType] = [.a, .b, .c]

    /// The reference's types (`TRAIN_TYPES`), main and extra: every type
    /// but the steam train of decision 153, which only an era offers, the
    /// high-speed set of decision 168, which is the reference's HSR
    /// option rather than a `TRAIN_TYPES` entry, and the EMU3000 of
    /// decision 169, which is in neither.
    public static let reference: [TrainType] = [.a, .b, .c, .l, .d, .apm, .maglev, .skyRail, .monorail]

    /// The types a world without an era offers (decisions 168 and 169): the
    /// reference's, the high-speed set and the EMU3000.
    public static let offered: [TrainType] = reference + [.highSpeed, .emu3000]

    /// The type the reference gives a new line (`_lineFormState.type`, and
    /// `normalizeLineTrainTypeForCityKey`'s fallback).
    public static let referenceDefault: TrainType = .b

    /// Passengers a car is rated for (`TRAIN_TYPES[type].ppc`).
    public var ratedCapacityPerCar: Int64 {
        switch self {
        case .a: 310
        case .b: 260
        case .c: 200
        case .l: 243
        case .d: 230
        case .apm: 138
        case .maglev: 240
        case .skyRail: 140
        case .monorail: 224
        case .steam: 50
        case .highSpeed: 80
        case .emu3000: 45
        }
    }

    /// Whether a train of this type takes up to 1.1 times what it is rated
    /// for (`METRO_TRAIN_OPERATIONAL_LOAD_FACTOR`): every type but the
    /// high-speed set, which never overloads (decision 168).
    public var overloads: Bool {
        self != .highSpeed
    }

    /// Doors on a car's platform side (gap: the reference has no doors).
    /// Wide-body metro cars five, standard and light ones four, linear-motor
    /// and maglev cars three, people movers, sky rail, monorail and the
    /// long-distance types (the high-speed set, the EMU3000) two.
    public var doorsPerCar: Int64 {
        switch self {
        case .a, .d: 5
        case .b, .c: 4
        case .l, .maglev: 3
        case .apm, .skyRail, .monorail, .steam, .highSpeed, .emu3000: 2
        }
    }

    /// How a train of this type runs, when the type has its own way
    /// (decision 153): the steam train's ``TrainPerformance/steam``, since
    /// decision 168 the high-speed set's ``TrainPerformance/highSpeed``
    /// (`PERF_HSR`) and since decision 169 the EMU3000's
    /// ``TrainPerformance/emu3000`` (`PERF_RULES`' EMU3000 expresses, already
    /// a performance preset). Every other type runs as the train is set to.
    public var performance: TrainPerformance? {
        switch self {
        case .steam: .steam
        case .highSpeed: .highSpeed
        case .emu3000: .emu3000
        default: nil
        }
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
