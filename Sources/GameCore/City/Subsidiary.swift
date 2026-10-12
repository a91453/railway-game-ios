// Subsidiary businesses (ARCHITECTURE decision 173): the A-Train 9 way of
// spending a rich company's cash. A department store, a hotel or an
// amusement park does not let its floors; it trades, and each midnight takes
// in what the passengers of the stations round it spend, pays its goods and
// its staff, and books the profit or loss on its own account. Built early,
// where the district has not grown yet, and sold once it has, it makes the
// A-Train's loop of building, waiting and selling high.
//
// The reference has no property and A-Train 9's manual lists only the
// categories (docs/research/CITY_BUILDING_STUDY.md §2): every number below
// is this project's, tuned by `BalanceReportTests`.

/// The rules of a subsidiary's trade (decision 173).
public enum SubsidiaryRules {
    /// How far a station's passengers come from: 800 m, in world units.
    public static let reach: Int64 = 51_200
    /// What a department store takes of the trips of the stations in reach,
    /// in thousandths; a shopping station's trips count one and a half
    /// times.
    public static let departmentStoreCapture: Int64 = 60
    public static let departmentStoreShoppingTenths: Int64 = 15
    /// What a hotel takes, in thousandths, of the trips that start outside
    /// the city (an outside connection, or an intercity station: its daily
    /// trips and a two-hundredth of its hinterland), and of the trips of a
    /// scenic station.
    public static let hotelIntercityCapture: Int64 = 6
    public static let hotelScenicCapture: Int64 = 10
    /// The intercity trips a day of a station with a hinterland, in
    /// thousandths of it.
    public static let hinterlandTripsPermille: Int64 = 5
    /// What an amusement park takes, in thousandths, of all the trips of
    /// the stations in reach, and of the trips of the other stations on the
    /// lines that call at them.
    public static let parkCapture: Int64 = 40
    public static let parkLineCapture: Int64 = 5
    /// What a customer spends, in cents.
    public static func spend(of kind: PlacedBuildingKind) -> Int64 {
        switch kind {
        case .departmentStore: 1_800
        case .hotel: 8_500
        case .amusementPark: 3_500
        default: 0
        }
    }
    /// The goods and running costs, in hundredths of what is taken.
    public static func variableCostPercent(of kind: PlacedBuildingKind) -> Int64 {
        kind == .departmentStore ? 65 : 55
    }
    /// The staff, each day, in ten-thousandths of what the building cost,
    /// rounded up: 0.04 %.
    public static let staffBasisPoints: Int64 = 4
    /// What a sale brings at least, as a multiple of the profit of the last
    /// twelve months.
    public static let saleProfitMultiple: Int64 = 6
    /// Months kept: a month is thirty days.
    public static let monthDays: Int64 = 30
    public static let monthsKept = 12
}

extension PlacedBuildingKind {
    /// Whether it trades (decision 173) rather than lets.
    public var isSubsidiary: Bool {
        switch self {
        case .departmentStore, .hotel, .amusementPark: true
        default: false
        }
    }
}

/// One month's trade.
public struct SubsidiaryMonth: Hashable, Codable, Sendable {
    public var sales: Money = .zero
    public var cost: Money = .zero

    public init(sales: Money = .zero, cost: Money = .zero) {
        self.sales = sales
        self.cost = cost
    }

    public var profit: Money { sales - cost }
}

/// A subsidiary's books (decision 173): the month in progress, the months
/// closed before it (at most twelve, the newest last) and the totals since
/// it opened.
public struct SubsidiaryBooks: Hashable, Codable, Sendable {
    /// The month in progress: the game day ÷ 30.
    public internal(set) var month: Int64 = 0
    public internal(set) var thisMonth = SubsidiaryMonth()
    public internal(set) var closed: [SubsidiaryMonth] = []
    public internal(set) var totalSales: Money = .zero
    public internal(set) var totalCost: Money = .zero

    public init() {}

    /// Last month's trade (nothing before one has closed).
    public var lastMonth: SubsidiaryMonth { closed.last ?? SubsidiaryMonth() }

    /// Profit since it opened.
    public var totalProfit: Money { totalSales - totalCost }

    /// The profit of the last twelve months, this one included.
    public var trailingProfit: Money {
        closed.suffix(SubsidiaryRules.monthsKept - 1).reduce(thisMonth.profit) { $0 + $1.profit }
    }

    /// Whether it has traded at all.
    public var hasTraded: Bool { totalSales != .zero || totalCost != .zero }

    /// Books a day's trade on day `day`, closing the months it has passed.
    mutating func record(sales: Money, cost: Money, day: Int64) {
        let month = max(0, day) / SubsidiaryRules.monthDays
        if !hasTraded {
            self.month = month
        } else if month > self.month {
            // The month in progress closes, then any month with no trade.
            closed.append(thisMonth)
            for _ in 0..<min(month - self.month - 1, Int64(SubsidiaryRules.monthsKept)) { closed.append(SubsidiaryMonth()) }
            if closed.count > SubsidiaryRules.monthsKept { closed.removeFirst(closed.count - SubsidiaryRules.monthsKept) }
            thisMonth = SubsidiaryMonth()
            self.month = month
        }
        thisMonth.sales = thisMonth.sales + sales
        thisMonth.cost = thisMonth.cost + cost
        totalSales = totalSales + sales
        totalCost = totalCost + cost
    }

    func isValid(for kind: PlacedBuildingKind) -> Bool {
        let limit = StationDemandLimits.maximumAccrued
        let amounts = [thisMonth.sales, thisMonth.cost, totalSales, totalCost] + closed.flatMap { [$0.sales, $0.cost] }
        guard month >= 0, closed.count <= SubsidiaryRules.monthsKept,
              amounts.allSatisfy({ (0...limit).contains($0.amount) })
        else { return false }
        return kind.isSubsidiary || self == SubsidiaryBooks()
    }
}

enum StationDemandLimits {
    static let maximumAccrued: Int64 = 1 << 50
}

/// What one subsidiary took on a day (decision 173).
public struct SubsidiaryDay: Hashable, Sendable {
    public let customers: Int64
    public let sales: Money
    public let cost: Money
}

extension GameWorld {
    // MARK: - Queries

    /// Stations a train calls at: on a passenger line with a train.
    private func servedStationIDs() -> Set<StationID> {
        var served: Set<StationID> = []
        for line in lines where !line.isFreight && !line.assignedTrains.isEmpty {
            served.formUnion(line.stops)
        }
        return served
    }

    /// The customers `building` would have on day `day`, shared with the
    /// subsidiaries of its kind within reach of it (decision 173).
    public func subsidiaryCustomers(of building: PlacedBuilding, onDay day: Int64) -> Int64 {
        guard building.kind.isSubsidiary else { return 0 }
        let served = servedStationIDs()
        return customers(of: building, onDay: day, served: served)
    }

    private func customers(of building: PlacedBuilding, onDay day: Int64, served: Set<StationID>) -> Int64 {
        let reach = SubsidiaryRules.reach
        func weight(of station: Station) -> Int64 {
            let dx = station.point.x - building.centre.x, dy = station.point.y - building.centre.y
            let d2 = dx * dx + dy * dy
            guard d2 <= reach * reach else { return 0 }
            return 1_000 - 1_000 * d2 / (reach * reach)
        }
        func trips(of station: Station) -> (demand: StationDemand, trips: Int64)? {
            guard let demand = stationDemand(of: station.id) else { return nil }
            return (demand, scaledTrips(weeklyDemand ? demand.trips(onDay: day) : demand.dailyTrips, at: station.id))
        }
        // Numerators are in (trips × thousandths of capture × tenths ×
        // thousandths of weight); each rate below divides them out.
        var numerator: Int64 = 0
        var denominator: Int64 = 1_000_000
        var best: Int64 = 0
        for station in stations where served.contains(station.id) {
            let w = weight(of: station)
            guard w > 0, let (demand, t) = trips(of: station) else { continue }
            best = max(best, w)
            switch building.kind {
            case .departmentStore:
                let tenths = demand.kind == .shopping ? SubsidiaryRules.departmentStoreShoppingTenths : 10
                numerator += t * SubsidiaryRules.departmentStoreCapture * tenths * w
                denominator = 10_000_000
            case .hotel:
                if isOutsideConnection(station.id) || demand.hinterland > 0 {
                    let intercity = t + demand.hinterland * SubsidiaryRules.hinterlandTripsPermille / 1_000
                    numerator += intercity * SubsidiaryRules.hotelIntercityCapture * 10 * w
                }
                if demand.kind == .scenic {
                    numerator += t * SubsidiaryRules.hotelScenicCapture * 10 * w
                }
                denominator = 10_000_000
            case .amusementPark:
                numerator += t * SubsidiaryRules.parkCapture * 10 * w
                denominator = 10_000_000
            default:
                break
            }
        }
        if building.kind == .amusementPark, best > 0 {
            // The other stations on the lines that call at the stations in reach.
            var inReach: Set<StationID> = [], along: Set<StationID> = []
            for station in stations where served.contains(station.id) && weight(of: station) > 0 { inReach.insert(station.id) }
            for line in lines where !line.isFreight && !line.assignedTrains.isEmpty && line.stops.contains(where: inReach.contains) {
                along.formUnion(line.stops)
            }
            for id in along.sorted() where !inReach.contains(id) {
                if let station = station(id: id), let (_, t) = trips(of: station) {
                    numerator += t * SubsidiaryRules.parkLineCapture * 10 * best
                }
            }
        }
        let rivals = Int64(placedBuildings.filter { $0.kind == building.kind && Self.distanceSquared($0.centre, building.centre) <= reach * reach }.count)
        return numerator / denominator / max(1, rivals)
    }

    private static func distanceSquared(_ a: PlanPoint, _ b: PlanPoint) -> Int64 {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }

    /// What `building` takes and spends on day `day` (decision 173): its
    /// customers at their spend, less the goods and running costs and the
    /// day's staff. Nothing for a building that lets.
    public func subsidiaryDay(of building: PlacedBuilding, onDay day: Int64) -> SubsidiaryDay {
        guard building.kind.isSubsidiary else { return SubsidiaryDay(customers: 0, sales: .zero, cost: .zero) }
        let customers = subsidiaryCustomers(of: building, onDay: day)
        return subsidiaryDay(of: building, customers: customers)
    }

    private func subsidiaryDay(of building: PlacedBuilding, customers: Int64) -> SubsidiaryDay {
        let sales = customers * SubsidiaryRules.spend(of: building.kind)
        let variable = sales * SubsidiaryRules.variableCostPercent(of: building.kind) / 100
        let staff = (building.cost.amount * SubsidiaryRules.staffBasisPoints + 9_999) / 10_000
        return SubsidiaryDay(customers: customers, sales: Money(sales), cost: Money(variable + staff))
    }

    /// Settles day `day` of every subsidiary (decision 173): its books, and
    /// one ledger row of the sales taken and the costs paid.
    mutating func settleSubsidiaries(day: Int64, time: GameTime) {
        guard accounts.mode == .management else { return }
        let served = servedStationIDs()
        var sales = Money.zero, cost = Money.zero
        for index in placedBuildings.indices where placedBuildings[index].kind.isSubsidiary {
            let building = placedBuildings[index]
            let result = subsidiaryDay(of: building, customers: customers(of: building, onDay: day, served: served))
            placedBuildings[index].books.record(sales: result.sales, cost: result.cost, day: day)
            sales = sales + result.sales
            cost = cost + result.cost
        }
        guard sales > .zero || cost > .zero else { return }
        write(LedgerEntry(
            kind: .dailySubsidiary, time: time, amount: sales - cost,
            breakdown: [LedgerLine(item: .subsidiarySales, amount: sales), LedgerLine(item: .subsidiaryCost, amount: .zero - cost)]
        ), day: day)
    }
}
