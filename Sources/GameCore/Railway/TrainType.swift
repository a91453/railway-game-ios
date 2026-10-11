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

    /// The reference's main types, offered everywhere
    /// (`LINE_TRAIN_TYPE_MAIN`); the others are its extras
    /// (`LINE_TRAIN_TYPE_EXTRA`).
    public static let main: [TrainType] = [.a, .b, .c]

    /// The reference's types (`TRAIN_TYPES`), main and extra: every type
    /// but the steam train of decision 153, which only an era offers.
    public static let reference: [TrainType] = [.a, .b, .c, .l, .d, .apm, .maglev, .skyRail, .monorail]

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
        }
    }

    /// Doors on a car's platform side (gap: the reference has no doors).
    /// Wide-body metro cars five, standard and light ones four, linear-motor
    /// and maglev cars three, people movers, sky rail and monorail two.
    public var doorsPerCar: Int64 {
        switch self {
        case .a, .d: 5
        case .b, .c: 4
        case .l, .maglev: 3
        case .apm, .skyRail, .monorail, .steam: 2
        }
    }

    /// How a train of this type runs, when the type has its own way
    /// (decision 153): the steam train's ``TrainPerformance/steam``. Every
    /// other type runs as the train is set to.
    public var performance: TrainPerformance? {
        switch self {
        case .steam: .steam
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
    /// without a type, its cars × 352, as before types.
    public var capacity: Int64 {
        (ratedCapacity * 11 + 5) / 10
    }

    /// How many passengers get off, or on, in a second: through every door
    /// of every car (see ``ServiceDwell/passengersPerDoorPerSecond``).
    public var passengersPerSecond: Int64 {
        ServiceDwell.passengersPerDoorPerSecond * doorsPerCar * Int64(cars)
    }

    /// The whole seconds `count` passengers take to get off or on, rounded
    /// up (see ``ServiceDwell/exchangeSeconds(_:cars:)``).
    func exchangeSeconds(_ count: Int64) -> Int64 {
        let rate = passengersPerSecond
        return count / rate + (count % rate == 0 ? 0 : 1)
    }
}
