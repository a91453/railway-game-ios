// The city's demand for homes, shops and workplaces (ARCHITECTURE decision
// 139): SimCity's RCI valves, on the city of Phase 6.
//
// A city keeps the mix it started with: so many shop jobs and so many jobs
// in offices, factories and farms for every resident (its ``CityMix``,
// taken from its land when the valves are turned on, or at the first
// midnight with residents). When it drifts from that mix, the use it is
// short of is in demand and the one it has too much of is not:
//
// - work (offices, factories and farms) is in demand when there are fewer
//   of those jobs a resident than at the start, shops likewise;
// - homes are in demand when there are more jobs a resident (of both) than
//   at the start;
// - each is the drift relative to the larger of the two mixes, ten times
//   (``CityDemand/gain``), from −1000 to 1000 thousandths: a tenth too few
//   is full demand.
//
// Schools, public offices and sights, and parks, are no part of it: their
// people grow and are raised as before.
//
// What demand does (in ``GameWorld/growLand(reached:)``), steering the
// city's growth without stopping it:
//
// - a growing station grows as many people as before, shared among
//   residents, shop jobs and work by the mix kept, each weighted by
//   `1 + ` its demand; what a kind has no room for goes to the others, so
//   a city whose offices cannot grow keeps growing homes;
// - its full buildings are raised the most wanted use first;
// - its new cell is the use most in demand (homes, shops or offices) when
//   that is above 0, and a home otherwise; a zoned cell is built on only if
//   its zone's use is not in negative demand.
//
// The owner's references have no city demand (decision 98's reference
// check; this one's searched again): the rule and its numbers are this
// project's (gap). Micropolis (GPL-3.0) has RCI valves fed by its census;
// only the idea is taken, none of its code or numbers.

/// A city's mix: its shop jobs and its jobs in work for every million
/// residents (decision 139).
public struct CityMix: Hashable, Codable, Sendable {
    public let shopJobs: Int64
    public let workJobs: Int64

    public init(shopJobs: Int64, workJobs: Int64) {
        self.shopJobs = shopJobs
        self.workJobs = workJobs
    }

    private enum CodingKeys: String, CodingKey {
        case shopJobs, workJobs
    }

    /// Decodes a mix, refusing a negative count or one past
    /// ``CityDemand/maximumMix``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let shopJobs = try container.decode(Int64.self, forKey: .shopJobs)
        let workJobs = try container.decode(Int64.self, forKey: .workJobs)
        guard (0...CityDemand.maximumMix).contains(shopJobs), (0...CityDemand.maximumMix).contains(workJobs) else {
            throw DecodingError.dataCorruptedError(forKey: .shopJobs, in: container, debugDescription: "A city's mix is out of range.")
        }
        self.init(shopJobs: shopJobs, workJobs: workJobs)
    }

    /// `land`'s mix: its shop jobs (the jobs of homes, shops and parks) and
    /// its jobs in work (offices, factories and farms), each times a
    /// million over its residents; `nil` for land with no one living on it.
    public init?(of land: Land) {
        var residents: Int64 = 0, shops: Int64 = 0, work: Int64 = 0
        for cell in land.cells {
            residents += cell.residents
            switch CityDemand.Kind(of: cell.use) {
            case .shops?: shops += cell.jobs
            case .work?: work += cell.jobs
            case .homes?, nil: break
            }
        }
        guard residents > 0 else { return nil }
        self.init(shopJobs: min(CityDemand.maximumMix, shops * CityDemand.perResidents / residents),
                  workJobs: min(CityDemand.maximumMix, work * CityDemand.perResidents / residents))
    }
}

/// The city's demand (decision 139): the mix it keeps, once it has one.
public struct CityDemand: Hashable, Codable, Sendable {
    /// The three kinds the valves are for.
    public enum Kind: Hashable, Sendable {
        case homes
        case shops
        case work

        /// The kind of a cell of `use`, for its jobs: homes, shops and
        /// parks hold shop jobs; offices, factories and farms work.
        /// Schools, public offices and sights have none.
        init?(of use: LandUse) {
            switch use {
            case .residential, .commercial, .park: self = .shops
            case .office, .industrial, .agricultural: self = .work
            case .civic, .leisure: return nil
            }
        }
    }

    /// The demand for each kind, in thousandths from −1000 to 1000.
    public struct Levels: Hashable, Sendable {
        public let homes: Int64
        public let shops: Int64
        public let work: Int64

        public init(homes: Int64, shops: Int64, work: Int64) {
            self.homes = homes
            self.shops = shops
            self.work = work
        }

        public static let none = Levels(homes: 0, shops: 0, work: 0)

        /// The demand for `kind`.
        public subscript(kind: Kind) -> Int64 {
            switch kind {
            case .homes: homes
            case .shops: shops
            case .work: work
            }
        }

        /// The demand for what a cell of `use` is built for: homes for
        /// homes, shops for shops and offices and factories for work; `nil`
        /// for the uses the valves leave alone.
        public func level(of use: LandUse) -> Int64? {
            switch use {
            case .residential: homes
            case .commercial: shops
            case .office, .industrial: work
            case .agricultural, .civic, .leisure, .park: nil
            }
        }
    }

    /// The mixes are per this many residents.
    static let perResidents: Int64 = 1_000_000
    /// The largest mix: a million jobs of each kind a resident, far past
    /// any city; ``CityMix/init(of:)`` stops there, and a save holds no
    /// more.
    static let maximumMix: Int64 = 1_000_000 * perResidents
    /// How many times its drift a demand is: a tenth too few is full demand.
    public static let gain: Int64 = 10

    /// The mix the city keeps, or `nil` until its land had residents.
    public internal(set) var baseline: CityMix?

    public init(baseline: CityMix? = nil) {
        self.baseline = baseline
    }

    /// The demand of a city whose mix is `now`: none without a baseline or
    /// residents.
    public func levels(now: CityMix?) -> Levels {
        guard let baseline, let now else { return .none }
        func drift(_ wanted: Int64, _ actual: Int64) -> Int64 {
            let larger = max(wanted, actual)
            guard larger > 0 else { return 0 }
            return max(-1_000, min(1_000, Self.gain * 1_000 * (wanted - actual) / larger))
        }
        return Levels(
            homes: drift(now.shopJobs + now.workJobs, baseline.shopJobs + baseline.workJobs),
            shops: drift(baseline.shopJobs, now.shopJobs),
            work: drift(baseline.workJobs, now.workJobs)
        )
    }

    /// `amount` as a demand of `level` scales it: times `1000 + level`
    /// thousandths, rounded half up.
    static func scaled(_ amount: Int64, by level: Int64) -> Int64 {
        (amount * (1_000 + level) + 500) / 1_000
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns the city's demand on or off (decision 139). On, the city keeps
    /// the mix its land has now, or, with no one living on it yet, the mix
    /// it has at the first midnight with residents; off, it grows as
    /// before. Free.
    public mutating func setCityDemand(_ enabled: Bool) {
        guard enabled != (cityDemand != nil) else { return }
        cityDemand = enabled ? CityDemand(baseline: CityMix(of: land)) : nil
    }

    // MARK: - Queries

    /// The city's demand for homes, shops and work now: none with the
    /// valves off or before the city has a mix.
    public var cityDemandLevels: CityDemand.Levels {
        guard let cityDemand else { return .none }
        return cityDemand.levels(now: CityMix(of: land))
    }

    // MARK: - Deriving

    /// Takes the land's mix as the city's when it has none yet and the land
    /// has residents (decision 139), or, with `replacing`, whenever the land
    /// was replaced.
    mutating func settleCityMix(replacing: Bool = false) {
        guard var demand = cityDemand, replacing || demand.baseline == nil else { return }
        demand.baseline = CityMix(of: land)
        cityDemand = demand
    }
}
