// Freight (ARCHITECTURE decision 155): tons of cargo made by the industry
// round a freight station, carried by the trains of a freight line and paid
// for by the ton and the kilometre. `docs/research/FREIGHT_STUDY.md` is the
// study; this is its plan C, the smallest loop.
//
// The owner's references have no freight to port (the study's §2: the
// reference pack names OpenTTD's `cargopacket.cpp`, `cargotype.cpp` and
// `industry_cmd.cpp` by path only, and `Railway/` and `city_world_reference`
// have no cargo, industry, wagon or freight timetable). OpenTTD (GPL-2.0) and
// Simutrans (Artistic 1.0) were read for ideas only: cargo is made where
// there is industry, waits at the station and is paid by the distance it was
// carried. So the rules and their numbers are this project's (gap):
//
// - the world has a switch, ``GameWorld/freight``, off in a new world and in
//   saves from before it, and written to a save only while it is on, so a
//   world without freight is exactly what it was;
// - a station gets a freight facility for ``Freight/facilityCost``; it holds
//   up to ``Freight/stockLimit`` tons. Each hour it is made
//   ``Freight/milliTonsPerJobDay`` thousandths of a ton a day for every job of
//   the industrial land whose nearest facility it is, within
//   ``Freight/catchmentRadius`` (1,600 m: the study measured that only 4.5 %
//   of Taiwan's industrial land lies within a kilometre of a railway station),
//   and a facility on the map's edge, an outside connection (decision 137), is
//   a port that is made ``Freight/portTonsPerDay`` tons a day besides;
// - a line is a freight line (``ServiceLine/isFreight``): nobody rides it, and
//   its trains, ``Freight/tonsPerCar`` tons a car, let off the cargo they
//   carry at the next station with a facility but its origin, then take on what
//   waits there unless it is the last stop of their timetable;
// - a delivery pays ``Freight/centsPerTonKilometre`` cents a ton for each
//   kilometre of the straight line from where it was loaded to where it was
//   let off, in whole dollars, in the hour's `hourlyFreight` ledger row, and
//   only while the company is managed. A train's running costs are those of
//   any train's.
//
// Cargo is whole tons, counted in groups by origin as passengers are, never
// one object each, and is conserved: everything made is waiting, on board,
// delivered, spilled (made while the facility was full) or lost (its facility,
// its origin or its train gone).

/// The rules of freight (decision 155): this project's numbers (gap), the
/// study's §6.0, to be measured by `BalanceReportTests`.
public enum Freight {
    /// The tons a car carries.
    public static let tonsPerCar: Int64 = 40
    /// What a freight facility costs: $50,000, paid as capital spending.
    public static let facilityCost: Money = 5_000_000
    /// The most tons a facility holds; cargo made beyond it is spilled.
    public static let stockLimit: Int64 = 2_000
    /// How far a facility's industry lies: 1,600 m.
    public static let catchmentRadius: Int64 = 2 * Land.catchmentRadius
    /// The thousandths of a ton a day an industrial job makes.
    public static let milliTonsPerJobDay: Int64 = 500
    /// The tons a day a port is made besides.
    public static let portTonsPerDay: Int64 = 200
    /// What a ton pays for a kilometre: $5 (500 cents). A full passenger car
    /// pays $1,430 a trip at the standard $5 fare, a freight car one way only,
    /// 40 t: over 5.4 km that is $1,080 (`BalanceReportTests.testAFreightLine`).
    public static let centsPerTonKilometre: Int64 = 500
    // Building materials (decision 156): this project's numbers (gap),
    // the study's §6.2, to be measured with decision 157's growth.

    /// The most tons of building materials a station holds.
    public static let materialsLimit: Int64 = 5_000
    /// The tons of building materials every station gets a day by road,
    /// from the city's own builders' merchants.
    public static let localMaterialsPerDay: Int64 = 60
    /// The tons a station that is an outside connection (decision 137)
    /// imports a day besides.
    public static let importedMaterialsPerDay: Int64 = 600
    // The city builds with them (decision 157): this project's numbers
    // (gap), chosen by `BalanceReportTests`.

    /// The floor a ton of building materials builds, in m²: raising a
    /// building takes its new storeys' floor (``Building/floorArea`` a
    /// storey) over this, rounded up.
    public static let floorPerTon: Int64 = 200
    /// The tons a new cell (a D1 building of two storeys) takes.
    public static var newCellMaterials: Int64 {
        materials(forFloors: BuildingDensity.d1.floors)
    }
    /// How many times slower a station short of materials grows that night.
    public static let shortGrowthDivisor: Int64 = 4

    /// The tons `floors` new storeys of a cell take.
    public static func materials(forFloors floors: Int64) -> Int64 {
        let floor = floors * Building.floorArea
        return (floor + floorPerTon - 1) / floorPerTon
    }

    /// The tons raising a building of `density` one density takes; 0 at D4.
    public static func materials(toRaise density: BuildingDensity) -> Int64 {
        guard let next = BuildingDensity(rawValue: density.rawValue + 1) else { return 0 }
        return materials(forFloors: next.floors - density.floors)
    }

    /// The most tons any total, or train's load, may hold in a save: far
    /// beyond any game.
    static let maximumTons: Int64 = 1 << 40
    /// Thousandths of a ton an hour's production is counted in: a day's is
    /// thousandths over 24 hours.
    static let accrualUnit: Int64 = 24_000

    /// The cents `tons` tons pay for being carried `distance` world units
    /// (1/64 m), in whole dollars, half up.
    static func fare(tons: Int64, distance: Int64) -> Money {
        // tons ≤ 2^40 only in a damaged save; a train carries ≤ 40 × cars.
        let cents = tons * distance * centsPerTonKilometre / (WorldCoordinate.unitsPerMetre * 1_000)
        return GameWorld.wholeDollars(cents)
    }
}

/// What a freight yard sends (decision 156): goods, paid for where they
/// are let off, or building materials, paid for and kept at the station
/// they are let off at for the city round it to build with.
public enum CargoKind: String, CaseIterable, Codable, Comparable, Sendable {
    case goods
    case materials

    public static func < (lhs: CargoKind, rhs: CargoKind) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// Cargo of one origin and kind on a train.
public struct CargoGroup: Hashable, Sendable {
    /// The station it was loaded at.
    public let origin: StationID
    /// What it is (decision 156); goods for cargo loaded before then.
    public let kind: CargoKind
    /// How many tons, at least 1.
    public internal(set) var tons: Int64

    public init(origin: StationID, kind: CargoKind = .goods, tons: Int64) {
        self.origin = origin
        self.kind = kind
        self.tons = tons
    }

    /// Groups are kept by origin, then kind.
    var key: (Int, CargoKind) {
        (origin.rawValue, kind)
    }
}

/// What a freight facility holds and has made.
public struct StationFreight: Hashable, Sendable {
    public let station: StationID
    /// Tons waiting, 0 to ``Freight/stockLimit``.
    public internal(set) var stock: Int64 = 0
    /// Thousandths of a ton made but not yet a whole ton, counted over
    /// 24 hours: 0 up to (not including) 24,000.
    var accrual: Int64 = 0
    /// What it sends (decision 156): goods unless set to building
    /// materials.
    public internal(set) var product: CargoKind = .goods

    public init(station: StationID) {
        self.station = station
    }
}

/// The cargo on one train.
public struct TrainCargo: Hashable, Sendable {
    public let train: TrainID
    /// By ascending origin, then kind, each once.
    public internal(set) var groups: [CargoGroup]

    public var tons: Int64 {
        groups.reduce(0) { $0 + $1.tons }
    }
}

/// The building materials a station holds (decision 156).
public struct StationMaterials: Hashable, Sendable {
    public let station: StationID
    /// 1 to ``Freight/materialsLimit`` tons.
    public internal(set) var tons: Int64 = 0

    public init(station: StationID) {
        self.station = station
    }
}

/// The world's freight (decision 155): its facilities, the cargo on its
/// trains, the hour's fares and the totals that account for every ton.
public struct FreightState: Hashable, Sendable {
    /// By ascending station.
    public internal(set) var facilities: [StationFreight] = []
    /// By ascending train; only trains with cargo.
    public internal(set) var loads: [TrainCargo] = []
    /// The fares of the deliveries of the hour, in whole dollars, until it
    /// is settled.
    public internal(set) var pendingRevenue: Money = .zero
    /// Tons made, let off at their destinations, spilled and lost, in all.
    public internal(set) var produced: Int64 = 0
    public internal(set) var delivered: Int64 = 0
    public internal(set) var spilled: Int64 = 0
    public internal(set) var lost: Int64 = 0
    /// Building materials (decision 156): whether stations get them, how
    /// many tons each holds, and the tons received by train, supplied
    /// locally or imported, used by the city (decision 157) and lost (over a
    /// station's limit, or with the station), in all.
    public internal(set) var buildingMaterials = false
    /// By ascending station; only stations holding some.
    public internal(set) var materials: [StationMaterials] = []
    public internal(set) var materialsReceived: Int64 = 0
    public internal(set) var materialsSupplied: Int64 = 0
    public internal(set) var materialsUsed: Int64 = 0
    public internal(set) var materialsLost: Int64 = 0
    /// The stations short of building materials at the last midnight
    /// (decision 158): those whose growth went at a quarter (decision 157),
    /// by ascending ID.
    public internal(set) var lastShort: [StationID] = []

    public init() {}

    /// Tons waiting at the facilities and on the trains.
    public var waiting: Int64 {
        facilities.reduce(0) { $0 + $1.stock }
    }

    public var onBoard: Int64 {
        loads.reduce(0) { $0 + $1.tons }
    }

    func facilityIndex(of station: StationID) -> Int? {
        facilities.firstIndex { $0.station == station }
    }

    func loadIndex(of train: TrainID) -> Int? {
        loads.firstIndex { $0.train == train }
    }

    /// Whether every ton made is somewhere: waiting, on board, delivered,
    /// spilled or lost.
    var isConserved: Bool {
        produced == waiting + onBoard + delivered + spilled + lost
            && materialsReceived + materialsSupplied == materials.reduce(0) { $0 + $1.tons } + materialsUsed + materialsLost
    }

    /// The tons of building materials at `station`.
    func materialsTons(at station: StationID) -> Int64 {
        materials.first { $0.station == station }?.tons ?? 0
    }

    /// Adds `tons` of building materials to `station`'s stock, up to
    /// ``Freight/materialsLimit``; the rest is lost. Returns what it kept.
    @discardableResult
    mutating func storeMaterials(_ tons: Int64, at station: StationID) -> Int64 {
        guard tons > 0 else { return 0 }
        let index: Int
        if let known = materials.firstIndex(where: { $0.station == station }) {
            index = known
        } else {
            index = materials.firstIndex { $0.station > station } ?? materials.count
            materials.insert(StationMaterials(station: station), at: index)
        }
        let kept = min(tons, Freight.materialsLimit - materials[index].tons)
        materials[index].tons += kept
        count(tons - kept, in: \.materialsLost)
        if materials[index].tons == 0 { materials.remove(at: index) }
        return kept
    }

    /// Takes `tons` of building materials from `station`'s stock, which
    /// holds at least that many, as used by the city (decision 157).
    mutating func useMaterials(_ tons: Int64, at station: StationID) {
        guard tons > 0, let index = materials.firstIndex(where: { $0.station == station }) else { return }
        materials[index].tons -= tons
        count(tons, in: \.materialsUsed)
        if materials[index].tons == 0 { materials.remove(at: index) }
    }

    /// Adds `tons` to the total `keyPath` names, stopping at the most a save
    /// holds.
    mutating func count(_ tons: Int64, in keyPath: WritableKeyPath<FreightState, Int64>) {
        self[keyPath: keyPath] = min(self[keyPath: keyPath] + tons, Freight.maximumTons)
    }
}

// MARK: - Codable

extension CargoGroup: Codable {
    private enum CodingKeys: String, CodingKey {
        case origin, kind, tons
    }

    /// Goods have no `"kind"`, as cargo saved before decision 156 reads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        origin = try container.decode(StationID.self, forKey: .origin)
        kind = try container.decodeIfPresent(CargoKind.self, forKey: .kind) ?? .goods
        tons = try container.decode(Int64.self, forKey: .tons)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        if kind != .goods { try container.encode(kind, forKey: .kind) }
        try container.encode(tons, forKey: .tons)
    }
}

extension StationMaterials: Codable {}
extension StationFreight: Codable {
    private enum CodingKeys: String, CodingKey {
        case station, stock, accrual, product
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        station = try container.decode(StationID.self, forKey: .station)
        stock = try container.decodeIfPresent(Int64.self, forKey: .stock) ?? 0
        accrual = try container.decodeIfPresent(Int64.self, forKey: .accrual) ?? 0
        product = try container.decodeIfPresent(CargoKind.self, forKey: .product) ?? .goods
        guard (0...Freight.stockLimit).contains(stock), (0..<Freight.accrualUnit).contains(accrual) else {
            throw DecodingError.dataCorruptedError(
                forKey: .stock, in: container, debugDescription: "A freight facility holds 0 to \(Freight.stockLimit) tons."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(station, forKey: .station)
        if stock != 0 { try container.encode(stock, forKey: .stock) }
        if accrual != 0 { try container.encode(accrual, forKey: .accrual) }
        if product != .goods { try container.encode(product, forKey: .product) }
    }
}

extension TrainCargo: Codable {}

extension FreightState: Codable {
    private enum CodingKeys: String, CodingKey {
        case facilities, loads, pendingRevenue, produced, delivered, spilled, lost
        case buildingMaterials, materials, materialsReceived, materialsSupplied, materialsUsed, materialsLost
        case lastShort
    }

    /// Decodes the freight of a world that has it. A facility list or load
    /// list that is not by ascending station or train, a load with no cargo
    /// or a group of no tons, a negative or out-of-range total, a fare that
    /// is not whole dollars, and tons that are not accounted for are
    /// rejected. That the stations and trains exist is checked by the
    /// ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        facilities = try container.decodeIfPresent([StationFreight].self, forKey: .facilities) ?? []
        loads = try container.decodeIfPresent([TrainCargo].self, forKey: .loads) ?? []
        pendingRevenue = try container.decodeIfPresent(Money.self, forKey: .pendingRevenue) ?? .zero
        produced = try container.decodeIfPresent(Int64.self, forKey: .produced) ?? 0
        delivered = try container.decodeIfPresent(Int64.self, forKey: .delivered) ?? 0
        spilled = try container.decodeIfPresent(Int64.self, forKey: .spilled) ?? 0
        lost = try container.decodeIfPresent(Int64.self, forKey: .lost) ?? 0
        // Decision 156 (save version 39): building materials.
        buildingMaterials = try container.decodeIfPresent(Bool.self, forKey: .buildingMaterials) ?? false
        materials = try container.decodeIfPresent([StationMaterials].self, forKey: .materials) ?? []
        materialsReceived = try container.decodeIfPresent(Int64.self, forKey: .materialsReceived) ?? 0
        materialsSupplied = try container.decodeIfPresent(Int64.self, forKey: .materialsSupplied) ?? 0
        materialsUsed = try container.decodeIfPresent(Int64.self, forKey: .materialsUsed) ?? 0
        materialsLost = try container.decodeIfPresent(Int64.self, forKey: .materialsLost) ?? 0
        lastShort = try container.decodeIfPresent([StationID].self, forKey: .lastShort) ?? []
        func corrupt(_ why: String) -> DecodingError {
            DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath, debugDescription: why))
        }
        guard zip(facilities, facilities.dropFirst()).allSatisfy({ $0.station < $1.station }) else {
            throw corrupt("Freight facilities must be listed once each, by ascending station.")
        }
        guard zip(loads, loads.dropFirst()).allSatisfy({ $0.train < $1.train }),
              loads.allSatisfy({ load in
                  !load.groups.isEmpty && load.groups.allSatisfy { (1...Freight.maximumTons).contains($0.tons) }
                      && zip(load.groups, load.groups.dropFirst()).allSatisfy { $0.key < $1.key }
              })
        else {
            throw corrupt("Freight loads must be listed once each, by ascending train, with groups of tons by ascending origin.")
        }
        guard buildingMaterials || (materials.isEmpty && facilities.allSatisfy { $0.product == .goods }
                  && loads.allSatisfy { $0.groups.allSatisfy { $0.kind == .goods } }),
              zip(materials, materials.dropFirst()).allSatisfy({ $0.station < $1.station }),
              buildingMaterials || lastShort.isEmpty, zip(lastShort, lastShort.dropFirst()).allSatisfy({ $0 < $1 }),
              materials.allSatisfy({ (1...Freight.materialsLimit).contains($0.tons) })
        else {
            throw corrupt("Building materials must be on to be held or sent, and each station's are 1 to \(Freight.materialsLimit) tons, by ascending station.")
        }
        let totals = [produced, delivered, spilled, lost, materialsReceived, materialsSupplied, materialsUsed, materialsLost]
        guard totals.allSatisfy({ (0...Freight.maximumTons).contains($0) }),
              (.zero...Money(GameWorld.maximumHourly)).contains(pendingRevenue), pendingRevenue.amount % 100 == 0
        else {
            throw corrupt("Freight totals must be 0 or more and within bounds, and fares whole dollars.")
        }
        // The totals stop at ``Freight/maximumTons``; a save that reached it
        // counts no further, so only a total below it must add up exactly.
        guard isConserved || totals.contains(Freight.maximumTons) else {
            throw corrupt("Every ton made must be waiting, on board, delivered, spilled or lost.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !facilities.isEmpty { try container.encode(facilities, forKey: .facilities) }
        if !loads.isEmpty { try container.encode(loads, forKey: .loads) }
        if pendingRevenue != .zero { try container.encode(pendingRevenue, forKey: .pendingRevenue) }
        if produced != 0 { try container.encode(produced, forKey: .produced) }
        if delivered != 0 { try container.encode(delivered, forKey: .delivered) }
        if spilled != 0 { try container.encode(spilled, forKey: .spilled) }
        if lost != 0 { try container.encode(lost, forKey: .lost) }
        if buildingMaterials { try container.encode(true, forKey: .buildingMaterials) }
        if !materials.isEmpty { try container.encode(materials, forKey: .materials) }
        if materialsReceived != 0 { try container.encode(materialsReceived, forKey: .materialsReceived) }
        if materialsSupplied != 0 { try container.encode(materialsSupplied, forKey: .materialsSupplied) }
        if materialsUsed != 0 { try container.encode(materialsUsed, forKey: .materialsUsed) }
        if materialsLost != 0 { try container.encode(materialsLost, forKey: .materialsLost) }
        if !lastShort.isEmpty { try container.encode(lastShort, forKey: .lastShort) }
    }
}

// MARK: - Commands and queries

extension GameWorld {
    /// Turns freight on (decision 155). Free; a world with freight on keeps
    /// it on.
    public mutating func enableFreight() {
        if freight == nil { freight = FreightState() }
    }

    /// Turns building materials on (decision 156), and freight with them.
    /// Free.
    public mutating func enableBuildingMaterials() {
        setBuildingMaterials(true)
    }

    /// Turns building materials on, with freight, or off (decision 157: the
    /// tutorial and the challenges, measured without them, keep none). Off,
    /// the materials the stations hold and those on board are lost, and
    /// every yard sends goods. Free.
    public mutating func setBuildingMaterials(_ enabled: Bool) {
        if enabled { enableFreight() }
        guard var state = freight, state.buildingMaterials != enabled else { return }
        if !enabled {
            state.count(state.materials.reduce(0) { $0 + $1.tons }, in: \.materialsLost)
            state.materials = []
            state.lastShort = []
            for index in state.facilities.indices { state.facilities[index].product = .goods }
            for slot in state.loads.indices.reversed() {
                let gone = state.loads[slot].groups.filter { $0.kind == .materials }.reduce(0) { $0 + $1.tons }
                state.count(gone, in: \.lost)
                state.loads[slot].groups.removeAll { $0.kind == .materials }
                if state.loads[slot].groups.isEmpty { state.loads.remove(at: slot) }
            }
        }
        state.buildingMaterials = enabled
        freight = state
    }

    /// Whether station `id`'s town was short of building materials at the
    /// last midnight, and grew at a quarter (decisions 157, 158).
    public func isShortOfMaterials(_ id: StationID) -> Bool {
        freight?.lastShort.contains(id) ?? false
    }

    /// The tons of building materials station `id` holds (decision 156).
    public func materialsStock(at id: StationID) -> Int64 {
        freight?.materialsTons(at: id) ?? 0
    }

    /// The tons of building materials station `id` gets a day without a
    /// train (decision 156): ``Freight/localMaterialsPerDay``, and
    /// ``Freight/importedMaterialsPerDay`` more at an outside connection; 0
    /// while building materials are off.
    public func materialsSuppliedPerDay(at id: StationID) -> Int64 {
        guard freight?.buildingMaterials == true, station(id: id) != nil else { return 0 }
        return Freight.localMaterialsPerDay + (isOutsideConnection(id) ? Freight.importedMaterialsPerDay : 0)
    }

    /// Sets what station `id`'s freight yard sends (decision 156). What
    /// waits there is sent as the new kind. Free.
    ///
    /// - Throws, checked in this order: ``GameError/freightNotEnabled``,
    ///   ``GameError/noFreightFacility(_:)`` or, for building materials,
    ///   ``GameError/buildingMaterialsNotEnabled``.
    public mutating func setFreightProduct(at id: StationID, to kind: CargoKind) throws(GameError) {
        guard var state = freight else { throw .freightNotEnabled }
        guard let index = state.facilityIndex(of: id) else { throw .noFreightFacility(id) }
        if kind == .materials, !state.buildingMaterials { throw .buildingMaterialsNotEnabled }
        state.facilities[index].product = kind
        freight = state
    }

    /// Station `id`'s freight facility, or `nil` while it has none or freight
    /// is off.
    public func freightFacility(at id: StationID) -> StationFreight? {
        freight?.facilities.first { $0.station == id }
    }

    /// The tons on board train `id`.
    public func cargoOnBoard(of id: TrainID) -> Int64 {
        freight?.loads.first { $0.train == id }?.tons ?? 0
    }

    /// Whether train `id` is on a freight line, and so carries cargo rather
    /// than passengers.
    public func isFreightTrain(_ id: TrainID) -> Bool {
        guard let line = assignedLine(of: id) else { return false }
        return lines.first { $0.id == line }?.isFreight ?? false
    }

    /// The tons a freight train of `cars` cars carries.
    public static func freightCapacity(cars: Int) -> Int64 {
        Int64(cars) * Freight.tonsPerCar
    }

    /// Gives station `id` a freight facility and charges
    /// ``Freight/facilityCost``, booked as capital spending for a managed
    /// company (it is not written down: it is no asset record).
    ///
    /// - Throws, checked in this order: ``GameError/freightNotEnabled``,
    ///   ``GameError/unknownStation(_:)``, ``GameError/freightFacilityExists(_:)``
    ///   or ``GameError/insufficientFunds(required:available:)``.
    public mutating func buildFreightFacility(at id: StationID) throws(GameError) {
        guard var state = freight else { throw .freightNotEnabled }
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard state.facilityIndex(of: id) == nil else { throw .freightFacilityExists(id) }
        try economy.spend(Freight.facilityCost)
        if accounts.mode == .management {
            accounts.bookCapital(day: dayIndex(of: clock.now)) { $0.capitalSpending = $0.capitalSpending + Freight.facilityCost }
        }
        let at = state.facilities.firstIndex { $0.station > id } ?? state.facilities.count
        state.facilities.insert(StationFreight(station: id), at: at)
        freight = state
    }

    /// Takes station `id`'s freight facility away; the cargo waiting there is
    /// lost, that of its origin on board trains still goes to its destination.
    /// Nothing is refunded.
    ///
    /// - Throws: ``GameError/freightNotEnabled`` or ``GameError/noFreightFacility(_:)``.
    public mutating func removeFreightFacility(at id: StationID) throws(GameError) {
        guard var state = freight else { throw .freightNotEnabled }
        guard let index = state.facilityIndex(of: id) else { throw .noFreightFacility(id) }
        state.count(state.facilities[index].stock, in: \.lost)
        state.facilities.remove(at: index)
        freight = state
    }

    /// The tons a day the industry round station `id` and its port make:
    /// what the facility there is made, to the nearest ton below; 0 without
    /// freight.
    public func freightSupply(at id: StationID) -> Int64 {
        guard let state = freight, state.facilityIndex(of: id) != nil, let station = station(id: id) else { return 0 }
        return dailyMilliTons(of: station, facilities: state.facilities.compactMap { self.station(id: $0.station) }) / 1_000
    }

    // MARK: - Making cargo

    /// The thousandths of a ton a day the industry round `station` makes,
    /// with its port: every industrial job of the cells within
    /// ``Freight/catchmentRadius`` whose nearest facility (the lower station
    /// when they are as near) is this one.
    func dailyMilliTons(of station: Station, facilities: [Station]) -> Int64 {
        var jobs: Int64 = 0
        land.forEachCell(within: Freight.catchmentRadius, of: station.point) { index, squared in
            let cell = land.cells[index]
            guard cell.use == .industrial, cell.jobs > 0 else { return }
            for other in facilities where other.id != station.id {
                let dx = cell.middle.x - other.point.x, dy = cell.middle.y - other.point.y
                let theirs = dx * dx + dy * dy
                if theirs < squared || (theirs == squared && other.id < station.id) { return }
            }
            jobs += cell.jobs
        }
        let port = isOutsideConnection(station.id) ? Freight.portTonsPerDay * 1_000 : 0
        return jobs * Freight.milliTonsPerJobDay + port
    }

    /// The hour's work of freight, at the start of the hour `now`: the fares
    /// of the hour that ended are written, cargo of trains that left their
    /// freight lines is lost, and each facility is made an hour of cargo.
    /// Called before the accounts are settled, so the fares count in the
    /// day that ended.
    mutating func tickFreight(at now: GameTime) {
        guard var state = freight, now.seconds % GameTime.secondsPerHour == 0 else { return }
        // The fares of the hour that ended.
        if state.pendingRevenue > .zero {
            if accounts.mode == .management, let opened = accounts.openedAt, opened < now {
                let amount = state.pendingRevenue
                state.pendingRevenue = .zero
                let day = dayIndex(of: GameTime(seconds: now.seconds - GameTime.secondsPerMinute))
                write(LedgerEntry(
                    kind: .hourlyFreight, time: now, amount: amount, breakdown: [LedgerLine(item: .freightRevenue, amount: amount)]
                ), day: day)
            } else if accounts.mode != .management {
                state.pendingRevenue = .zero
            }
        }
        // Cargo of a train that is no longer on a freight line is lost.
        for index in state.loads.indices.reversed() {
            let train = state.loads[index].train
            if let line = assignedLine(of: train).flatMap({ id in lines.first { $0.id == id } }), line.isFreight { continue }
            state.count(state.loads[index].tons, in: \.lost)
            state.loads.remove(at: index)
        }
        // Decision 156: each midnight every station gets the day's building
        // materials by road, and an outside connection its imports.
        if state.buildingMaterials, now.seconds % GameTime.secondsPerDay == 0 {
            for station in stations {
                let tons = Freight.localMaterialsPerDay + (isOutsideConnection(station.id) ? Freight.importedMaterialsPerDay : 0)
                state.count(tons, in: \.materialsSupplied)
                state.storeMaterials(tons, at: station.id)
            }
        }
        // An hour of cargo for each facility.
        if !state.facilities.isEmpty {
            let made = state.facilities.compactMap { station(id: $0.station) }
            for index in state.facilities.indices {
                guard let station = station(id: state.facilities[index].station) else { continue }
                var facility = state.facilities[index]
                facility.accrual += dailyMilliTons(of: station, facilities: made)
                let tons = facility.accrual / Freight.accrualUnit
                facility.accrual %= Freight.accrualUnit
                let kept = min(tons, Freight.stockLimit - facility.stock)
                facility.stock += kept
                state.count(tons, in: \.produced)
                state.count(tons - kept, in: \.spilled)
                state.facilities[index] = facility
            }
        }
        freight = state
    }

    // MARK: - Carrying it

    /// Train `index`'s exchange of cargo at stop `stop` of its timetable, as
    /// its doors finish opening, if its line is a freight line: what it
    /// carries and did not load here is let off and paid for, then, unless it
    /// is the last stop, it takes on what waits here up to its cars' tons.
    /// `nil` for a train that is not on a freight line; else the larger of
    /// the tons let off and taken on, which sets how long the exchange takes.
    mutating func exchangeCargo(_ index: Int, at stop: Int) -> Int64? {
        guard var state = freight, let lineID = assignedLine(of: trains[index].id),
              let line = lines.first(where: { $0.id == lineID }), line.isFreight else { return nil }
        let train = trains[index]
        let here = train.timetable[stop].station
        guard let facility = state.facilityIndex(of: here), station(id: here)?.operationMode.allowsService == true else { return 0 }
        var letOff: Int64 = 0
        if let slot = state.loadIndex(of: train.id) {
            var kept: [CargoGroup] = []
            for group in state.loads[slot].groups {
                if group.origin == here {
                    kept.append(group)
                } else {
                    letOff += group.tons
                    // Decision 156: building materials stay at the station.
                    if group.kind == .materials {
                        state.count(group.tons, in: \.materialsReceived)
                        state.storeMaterials(group.tons, at: here)
                    }
                    if accounts.mode == .management, let squared = squaredDistance(from: group.origin, to: here) {
                        let fare = Freight.fare(tons: group.tons, distance: FixedPoint.squareRoot(squared))
                        state.pendingRevenue = Money(min(state.pendingRevenue.amount + fare.amount, Self.maximumHourly / 100 * 100))
                    }
                }
            }
            state.count(letOff, in: \.delivered)
            if kept.isEmpty {
                state.loads.remove(at: slot)
            } else {
                state.loads[slot].groups = kept
            }
        }
        var taken: Int64 = 0
        if stop < train.timetable.count - 1 {
            let aboard = state.loadIndex(of: train.id).map { state.loads[$0].tons } ?? 0
            taken = min(state.facilities[facility].stock, max(0, Self.freightCapacity(cars: train.cars) - aboard))
            if taken > 0 {
                state.facilities[facility].stock -= taken
                let kind = state.facilities[facility].product
                if let slot = state.loadIndex(of: train.id) {
                    if let group = state.loads[slot].groups.firstIndex(where: { $0.origin == here && $0.kind == kind }) {
                        state.loads[slot].groups[group].tons += taken
                    } else {
                        state.loads[slot].groups.append(CargoGroup(origin: here, kind: kind, tons: taken))
                        state.loads[slot].groups.sort { $0.key < $1.key }
                    }
                } else {
                    let at = state.loads.firstIndex { $0.train > train.id } ?? state.loads.count
                    state.loads.insert(TrainCargo(train: train.id, groups: [CargoGroup(origin: here, kind: kind, tons: taken)]), at: at)
                }
            }
        }
        freight = state
        return max(letOff, taken)
    }

    /// Forgets station `id` (it has been removed): its facility's cargo and
    /// the cargo on board that was loaded there are lost.
    mutating func forgetFreight(of id: StationID) {
        guard var state = freight else { return }
        if let index = state.facilityIndex(of: id) {
            state.count(state.facilities[index].stock, in: \.lost)
            state.facilities.remove(at: index)
        }
        state.lastShort.removeAll { $0 == id }
        // Decision 156: and the building materials it held.
        if let index = state.materials.firstIndex(where: { $0.station == id }) {
            state.count(state.materials[index].tons, in: \.materialsLost)
            state.materials.remove(at: index)
        }
        for slot in state.loads.indices.reversed() {
            let gone = state.loads[slot].groups.filter { $0.origin == id }.reduce(0) { $0 + $1.tons }
            state.count(gone, in: \.lost)
            state.loads[slot].groups.removeAll { $0.origin == id }
            if state.loads[slot].groups.isEmpty { state.loads.remove(at: slot) }
        }
        freight = state
    }

    // MARK: - Validation

    /// Why the world's freight breaks a rule, or `nil`: its stations and
    /// trains exist, and a freight line is one that carries no passengers.
    func freightProblem() -> String? {
        guard let state = freight else {
            return lines.contains(where: \.isFreight) ? "A freight line needs a world with freight." : nil
        }
        guard state.facilities.allSatisfy({ station(id: $0.station) != nil }) else { return "A freight facility names a station that does not exist." }
        guard state.loads.allSatisfy({ load in train(id: load.train) != nil && load.groups.allSatisfy { station(id: $0.origin) != nil } }) else {
            return "Cargo is on a train, or from a station, that does not exist."
        }
        guard state.materials.allSatisfy({ station(id: $0.station) != nil }), state.lastShort.allSatisfy({ station(id: $0) != nil }) else {
            return "Building materials are held at a station that does not exist."
        }
        return nil
    }
}
