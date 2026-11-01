// Decision 533: the company's schools bring students and its hospitals
// patients (decision 361's sequel, its next step 3). A school or hospital a
// station serves draws riders from the other stations within its reach,
// shared by their residents, who ride there and back on the day's own
// hours: students on a school day, in the morning and home in the
// afternoon; patients and visitors through the day, fewer at the weekend.
// They join the passenger plan as the tourists do (`TouristFlows`), so they
// board, pay their fares and fill trains like every other passenger.

/// The numbers of decision 533.
public enum CivicRiderRules {
    /// The students a school draws on a school day, at most, each riding
    /// there in the morning and home in the afternoon: a Taiwanese senior
    /// high school's 1,500 or so pupils, of whom about one in three comes
    /// by train.
    public static let schoolStudents: Int64 = 500
    /// The patients and visitors a hospital draws on a weekday, at most:
    /// a regional hospital's outpatients who come by train.
    public static let hospitalVisitors: Int64 = 300
    /// One student a day for every this many residents of the stations
    /// within reach (and one patient for twice as many): a small town
    /// fills no school.
    public static let residentsPerStudent: Int64 = 40
    /// How far students come: the stations within 12 km of the school
    /// (64 world units to the metre).
    public static let schoolReach: Int64 = 768_000
    /// How far patients come: 25 km.
    public static let hospitalReach: Int64 = 1_600_000
    /// A hospital's patients on a Saturday, a Sunday and a holiday, in
    /// thousandths of a weekday's: clinics open on Saturday mornings,
    /// and only emergencies and visitors come on a day off.
    public static let hospitalSaturday: Int64 = 500
    public static let hospitalDayOff: Int64 = 200
    /// The months of the summer holiday, when no school opens (the game's
    /// months of 30 days, 1 for the first).
    public static let summerMonths: ClosedRange<Int> = 7...8

    /// Each hour's share of the students' rides to school and home, hour 0
    /// first: most set out at seven for an eight o'clock bell; most go home
    /// at four, some after evening classes.
    static let schoolOutbound: [Int64] = [0, 0, 0, 0, 0, 0, 2, 7, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    static let schoolBack: [Int64] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 4, 3, 1, 0, 0, 1, 0, 0]
    /// The patients': to the morning clinics from seven and the afternoon
    /// ones after lunch, home from late morning.
    static let hospitalOutbound: [Int64] = [0, 0, 0, 0, 0, 0, 0, 2, 4, 4, 2, 0, 0, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    static let hospitalBack: [Int64] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 3, 0, 0, 2, 2, 1, 0, 0, 0, 0, 0, 0]
}

/// The riders a school or a hospital of the company's brings to the
/// station that serves it today (``GameWorld/civicRiders(at:)``).
public struct CivicRiders: Hashable, Sendable {
    /// ``PlacedBuildingKind/school`` or ``PlacedBuildingKind/hospital``.
    public let kind: PlacedBuildingKind
    /// The riders who come today, each riding there and back.
    public let riders: Int64

    public init(kind: PlacedBuildingKind, riders: Int64) {
        self.kind = kind
        self.riders = riders
    }
}

extension PlacedBuildingKind {
    /// Whether it brings riders of its own (decision 533): a school or a
    /// hospital.
    public var bringsRiders: Bool {
        self == .school || self == .hospital
    }
}

extension GameWorld {
    /// The company's schools and hospitals (decision 533), by placing:
    /// one built or sold changes the day's passenger plan.
    var civicRiderBuildings: [PlacedBuildingID] {
        placedBuildings.filter(\.kind.bringsRiders).map(\.id)
    }

    /// The most riders a building of `kind` draws on game day `day` at
    /// `point`, before the stations within reach cap it: none on a day
    /// its kind is shut or a typhoon blows there.
    func civicRidersExpected(_ kind: PlacedBuildingKind, at point: PlanPoint, onDay day: Int64) -> Int64 {
        let blowing = typhoons(onDay: day).contains { $0.isActive(onDay: day) && $0.covers(point) }
        guard !blowing else { return 0 }
        let weekday = StationDemand.weekday(ofDay: day)
        let dayOff = holiday(onDay: day) != nil
        switch kind {
        case .school:
            let year = FinancePeriod.year.days
            let month = Int((day - CompanyAccounts.floorDivide(day, year) * year) / 30) + 1
            guard !dayOff, !StationDemand.isWeekend(day: day), !CivicRiderRules.summerMonths.contains(month) else { return 0 }
            return CivicRiderRules.schoolStudents
        case .hospital:
            let share = dayOff || weekday == 0 ? CivicRiderRules.hospitalDayOff
                : weekday == 6 ? CivicRiderRules.hospitalSaturday : 1_000
            return CivicRiderRules.hospitalVisitors * share / 1_000
        default:
            return 0
        }
    }

    /// Adds the riders of the company's schools and hospitals on game day
    /// `day` to `flows`, `reaches` saying which pairs can ride (decision
    /// 533), and returns how many come to each, by building. A building
    /// draws from the stations within its reach that can ride to the
    /// station serving it, never that station itself (its own catchment
    /// walks), shared by their residents (or, on a map without a city, their
    /// daily trips); at most one rider for ``CivicRiderRules/residentsPerStudent``
    /// of those residents (twice as many a patient). Buildings of a kind
    /// within ``Tourism/reach`` of one another share their riders, as
    /// temples do. Each rides back on its kind's hours when the way back
    /// is open too.
    @discardableResult
    func addCivicFlows(onDay day: Int64, to flows: inout TouristFlows,
                       reaches: (StationID, StationID) -> Bool) -> [PlacedBuildingID: Int64] {
        let buildings = placedBuildings.filter(\.kind.bringsRiders)
        guard !buildings.isEmpty else { return [:] }
        let candidates = touristCandidates()
        let cityless = candidates.allSatisfy { $0.residents == 0 }
        let points = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0.point) })
        let near = Tourism.reach * Tourism.reach
        var arrivals: [PlacedBuildingID: Int64] = [:]
        for building in buildings {
            let expected = civicRidersExpected(building.kind, at: building.centre, onDay: day)
            guard expected > 0, let station = servingStation(at: building.centre) else { continue }
            let school = building.kind == .school
            let reach = school ? CivicRiderRules.schoolReach : CivicRiderRules.hospitalReach
            let sources: [(station: StationID, weight: Int64)] = candidates.compactMap { candidate in
                guard candidate.station != station, let point = points[candidate.station] else { return nil }
                let dx = point.x - building.centre.x, dy = point.y - building.centre.y
                guard dx * dx + dy * dy <= reach * reach else { return nil }
                let weight = cityless ? stationDemand(of: candidate.station)?.dailyTrips ?? 0 : candidate.residents
                guard weight > 0, reaches(candidate.station, station) else { return nil }
                return (candidate.station, weight)
            }
            guard !sources.isEmpty else { continue }
            let sharing = Int64(max(1, buildings.count { other in
                let dx = other.centre.x - building.centre.x, dy = other.centre.y - building.centre.y
                return other.kind == building.kind && dx * dx + dy * dy <= near
            }))
            let perRider = CivicRiderRules.residentsPerStudent * (school ? 1 : 2)
            let potential = sources.reduce(Int64(0)) { $0 + $1.weight } / perRider
            let riders = min(expected, potential) / sharing
            guard riders > 0 else { continue }
            let outbound = school ? CivicRiderRules.schoolOutbound : CivicRiderRules.hospitalOutbound
            let back = school ? CivicRiderRules.schoolBack : CivicRiderRules.hospitalBack
            for (source, share) in zip(sources, Self.apportion(riders, by: sources.map(\.weight))) where share > 0 {
                flows.add(hours: Self.apportion(share, by: outbound), from: source.station, to: station)
                if reaches(station, source.station) {
                    flows.add(hours: Self.apportion(share, by: back), from: station, to: source.station)
                }
            }
            arrivals[building.id] = riders
        }
        return arrivals
    }

    /// The riders the company's schools and hospitals served by station
    /// `id` bring today, a kind at a time (school first), as the passenger
    /// model reaches them now; empty when none comes (decision 533).
    public func civicRiders(at id: StationID) -> [CivicRiders] {
        let served = placedBuildings.filter { $0.kind.bringsRiders && servingStation(at: $0.centre) == id }
        guard !served.isEmpty else { return [] }
        let world = self
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        var flows = TouristFlows()
        let arrivals = addCivicFlows(onDay: dayIndex(of: clock.now), to: &flows) { world.reaches(from: $0, to: $1, graph: graph) }
        return [PlacedBuildingKind.school, .hospital].compactMap { kind in
            let riders = served.filter { $0.kind == kind }.reduce(Int64(0)) { $0 + (arrivals[$1.id] ?? 0) }
            return riders > 0 ? CivicRiders(kind: kind, riders: riders) : nil
        }
    }
}
