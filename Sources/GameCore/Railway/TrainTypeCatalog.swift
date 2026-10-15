// The built-in catalog of train types (decision 225): each type's numbers as
// one row of data, where they were a `switch` for each number before. A type
// is known by its code, the string saves, golden scenarios and replays store
// (`"A"`, `"HSR"`); a row is never removed and a code never changes, since a
// save may hold any of them. Adding a type is adding a row (and its name in
// GamePresentation): the save format does not change.
//
// Where the numbers come from:
//
// - The reference's nine types are the owner's `Ci/` reference
//   (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`): `TRAIN_TYPES`
//   rates each type's car in persons (`ppc`): A 310, B 260, C 200, L 243,
//   D 230, APM 138, maglev 240, sky rail 140, monorail 224;
//   `LINE_TRAIN_TYPE_MAIN` is A, B and C, `LINE_TRAIN_TYPE_EXTRA` the rest.
// - The reference has no doors: its boarding is instant and its dwell fixed.
//   The door count of each type is this project's (gap), as the four doors
//   of the standard car already were (``ServiceDwell/doorsPerCar``): wide-body
//   metro cars five, standard and light ones four, linear-motor and maglev
//   cars three, people movers, sky rail, monorail and the long-distance types
//   two.
// - The steam train (decision 153) is this project's: the references have no
//   steam train or 19th-century car. It is the era type of the Liu Mingchuan
//   Railway challenge, which only an era offers.
// - The high-speed set (decision 168) comes from the reference's HSR options
//   (`HSR_TRAIN_CARS_CAPACITY` 650, 1,200 and 1,283 persons for 8, 16 and 17
//   cars: set totals, where this model rates each car, so a car is rated 80,
//   640 and 1,280 for 8 and 16 cars) and its rule that a high-speed train
//   never overloads (`metroTrainUsesOperationalOverload` is false for
//   `lineKind === "hsr"`): it takes what it is rated for, not 1.1 times.
// - The Taiwan Railway's EMU3000 (decision 169), the express the 3D city
//   view draws, is in neither reference. A car is rated 45 persons: the set's
//   rated 538 (the Wikipedia page of the type, which gives the cars' seats
//   and their total as the set's `編組定員`; Taiwan News repeats the 538) over
//   its 12 cars, 44.8 rounded. Two doors a side, as the owner's fleet
//   catalogue counts them from photographs (`fleet/catalog.json`,
//   `emu3000-mid`: 「每節每側 2 門在客室兩端」, marked inferred) and as the
//   city view draws them. It runs as the owner's `PERF_RULES` have the
//   EMU3000 express run (``TrainPerformance/emu3000``: 135 km/h).
// - The prices and running-cost weights (decision 180) are this project's
//   (gap): the references have no price list for rolling stock.
// - The car lengths (decision 227) are coupler pitches, a middle car's: the
//   EMU3000's 20.3 m is the owner's fleet catalogue (`fleet/catalog.json`,
//   `emu3000-mid` `pitchM`); the high-speed set's 25 m the 700T's middle
//   car; A 22 m, B 19.5 m and C 19 m China's standard metro car types
//   (GB 50157) the reference's types are named after; L 16.5 m the
//   linear-motor metros (Osaka, Guangzhou); D 20 m, the APM's 12.5 m, sky
//   rail's 12 m, maglev and monorail 15 m and the steam train's four-wheeled
//   coach 8 m are estimates from cars of their kind.
// - The families (metro, railway, high speed, special) are decision 224's
//   catalogue of types; a high-speed set is the type whose family is high
//   speed.

/// A family of train types: the catalogue's tabs (decision 224). A type is a
/// high-speed set when its family is ``highSpeed`` (decision 168).
public enum TrainFamily: CaseIterable, Hashable, Sendable {
    case metro, railway, highSpeed, special
}

/// Where a type is offered (decisions 153, 168 and 169).
public enum TrainTypeOffer: Hashable, Sendable {
    /// One of the reference's main types (`LINE_TRAIN_TYPE_MAIN`).
    case referenceMain
    /// One of the reference's other types (`LINE_TRAIN_TYPE_EXTRA`).
    case referenceExtra
    /// One of this project's, offered with the reference's in a world
    /// without an era.
    case added
    /// Offered only by an era that names it.
    case eraOnly
}

/// One type of train car, as the catalog lists it (decision 225).
public struct TrainTypeSpec: Hashable, Sendable {
    /// The type's code: what saves store.
    public let code: String
    public let family: TrainFamily
    public let offer: TrainTypeOffer
    /// Passengers a car is rated for.
    public let ratedCapacityPerCar: Int64
    /// Doors on a car's platform side.
    public let doorsPerCar: Int64
    /// Whether a train of the type takes up to 1.1 times what it is rated
    /// for (`METRO_TRAIN_OPERATIONAL_LOAD_FACTOR`).
    public let overloads: Bool
    /// How a train of the type runs, when the type has its own way.
    public let performance: TrainPerformance?
    /// What it costs to buy and to run (decision 180).
    public let pricing: RollingStockPricing
    /// How far apart its cars stand, centre to centre, in world units, in a
    /// world with real car lengths (decision 227): the type's real coupler
    /// pitch, a middle car's.
    public let carLength: Int64

    init(
        code: String, family: TrainFamily, offer: TrainTypeOffer, capacity: Int64, doors: Int64, overloads: Bool,
        performance: TrainPerformance?, firstDollars: Int64, carDollars: Int64, operatingPermille: Int64, carMetres: (Int64, Int64)
    ) {
        self.code = code
        self.family = family
        self.offer = offer
        ratedCapacityPerCar = capacity
        doorsPerCar = doors
        self.overloads = overloads
        self.performance = performance
        pricing = RollingStockPricing(firstDollars: firstDollars, carDollars: carDollars, operatingPermille: operatingPermille)
        carLength = Self.worldUnits(metres: carMetres.0, tenths: carMetres.1)
    }

    /// `metres.tenths` metres in world units (64 a metre), to the nearest.
    static func worldUnits(metres: Int64, tenths: Int64) -> Int64 {
        ((metres * 10 + tenths) * WorldCoordinate.unitsPerMetre + 5) / 10
    }
}

/// The built-in train types (decision 225).
public enum TrainTypeCatalog {
    /// Every type, in the order ``TrainType/allCases`` and the menus list
    /// them.
    public static let builtIn: [TrainTypeSpec] = [
        .init(code: "A", family: .metro, offer: .referenceMain, capacity: 310, doors: 5, overloads: true,
              performance: nil, firstDollars: 150_000, carDollars: 40_000, operatingPermille: 1_000, carMetres: (22, 0)),
        .init(code: "B", family: .metro, offer: .referenceMain, capacity: 260, doors: 4, overloads: true,
              performance: nil, firstDollars: 150_000, carDollars: 40_000, operatingPermille: 1_000, carMetres: (19, 5)),
        .init(code: "C", family: .metro, offer: .referenceMain, capacity: 200, doors: 4, overloads: true,
              performance: nil, firstDollars: 150_000, carDollars: 40_000, operatingPermille: 1_000, carMetres: (19, 0)),
        .init(code: "L", family: .metro, offer: .referenceExtra, capacity: 243, doors: 3, overloads: true,
              performance: nil, firstDollars: 90_000, carDollars: 25_000, operatingPermille: 700, carMetres: (16, 5)),
        .init(code: "D", family: .metro, offer: .referenceExtra, capacity: 230, doors: 5, overloads: true,
              performance: nil, firstDollars: 120_000, carDollars: 35_000, operatingPermille: 1_300, carMetres: (20, 0)),
        .init(code: "APM", family: .metro, offer: .referenceExtra, capacity: 138, doors: 2, overloads: true,
              performance: nil, firstDollars: 110_000, carDollars: 30_000, operatingPermille: 800, carMetres: (12, 5)),
        .init(code: "MAGLEV", family: .special, offer: .referenceExtra, capacity: 240, doors: 3, overloads: true,
              performance: nil, firstDollars: 600_000, carDollars: 150_000, operatingPermille: 1_800, carMetres: (15, 0)),
        .init(code: "SKYRAIL", family: .special, offer: .referenceExtra, capacity: 140, doors: 2, overloads: true,
              performance: nil, firstDollars: 170_000, carDollars: 50_000, operatingPermille: 1_000, carMetres: (12, 0)),
        .init(code: "MONORAIL", family: .special, offer: .referenceExtra, capacity: 224, doors: 2, overloads: true,
              performance: nil, firstDollars: 160_000, carDollars: 45_000, operatingPermille: 1_000, carMetres: (15, 0)),
        .init(code: "STEAM", family: .railway, offer: .eraOnly, capacity: 50, doors: 2, overloads: true,
              performance: .steam, firstDollars: 80_000, carDollars: 20_000, operatingPermille: 1_400, carMetres: (8, 0)),
        .init(code: "HSR", family: .highSpeed, offer: .added, capacity: 80, doors: 2, overloads: false,
              performance: .highSpeed, firstDollars: 900_000, carDollars: 120_000, operatingPermille: 2_000, carMetres: (25, 0)),
        .init(code: "EMU3000", family: .railway, offer: .added, capacity: 45, doors: 2, overloads: true,
              performance: .emu3000, firstDollars: 260_000, carDollars: 55_000, operatingPermille: 1_200, carMetres: (20, 3)),
    ]

    /// Each code's row. Building it traps on a code listed twice.
    static let rowByCode: [String: Int] = Dictionary(uniqueKeysWithValues: builtIn.enumerated().map { ($1.code, $0) })
}
