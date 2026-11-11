import GameCore

// The city's size and kind (decision 683): a title for how many people live
// on the map's land, and a word for what its jobs are mostly in. Both are
// read from the world's land each time they are wanted and kept nowhere:
// nothing here is game state, and GameCore is untouched.
//
// The idea is the reference study's (docs/research/
// FEATURE_GAP_SCORING_2026-11-08.md §1.5: a size in steps from a village to
// the largest city, a kind by the strongest sector, none while the city is
// very small). Its numbers are in units of its own and are not taken; the
// steps here are Taiwan's own, where the law has them (Local Government
// Act, article 4: 100,000 people for a county-administered city, 500,000
// for a city, 1,250,000 for a special municipality), and the game's below
// and above those (gap), set so the app's maps read as people know the
// places (``CityTitleReportTests``).

/// What the city on the map is: its size by its residents, and its kind by
/// its jobs (decision 683).
public struct CityTitle: Hashable, Sendable {
    /// The city's size, smallest first.
    public enum Rank: Int, CaseIterable, Comparable, Hashable, Sendable {
        case hamlet, village, smallTown, town, smallCity, city, largeCity, metropolis, megalopolis

        /// The residents it starts at.
        public var residents: Int64 {
            switch self {
            case .hamlet: 0
            case .village: 1_000
            case .smallTown: 5_000
            case .town: 20_000
            // The Local Government Act's three: a county-administered
            // city, a city, a special municipality.
            case .smallCity: 100_000
            case .city: 500_000
            case .largeCity: 1_250_000
            case .metropolis: 3_000_000
            case .megalopolis: 10_000_000
            }
        }

        /// The size of a city of `residents`.
        public init(residents: Int64) {
            self = Rank.allCases.last { residents >= $0.residents } ?? .hamlet
        }

        /// The next size up, or `nil` at the largest.
        public var next: Rank? {
            Rank(rawValue: rawValue + 1)
        }

        public static func < (a: Rank, b: Rank) -> Bool {
            a.rawValue < b.rawValue
        }

        public func name(in language: DisplayLanguage) -> String {
            switch self {
            case .hamlet: language.text("Hamlet", "聚落")
            case .village: language.text("Village", "村莊")
            case .smallTown: language.text("Small town", "小鎮")
            case .town: language.text("Town", "城鎮")
            case .smallCity: language.text("Small city", "小城市")
            case .city: language.text("City", "城市")
            case .largeCity: language.text("Large city", "大城市")
            case .metropolis: language.text("Metropolis", "都會")
            case .megalopolis: language.text("Megalopolis", "大都會")
            }
        }
    }

    /// What the city's jobs are mostly in.
    public enum Kind: CaseIterable, Hashable, Sendable {
        /// Few jobs for its people: they work elsewhere.
        case residential
        /// Shops and services (the jobs among homes, shops and parks).
        case commercial
        /// Offices.
        case business
        /// Factories and warehouses.
        case industrial
        /// Schools, hospitals and public offices.
        case civic
        /// Sights, resorts and amusements.
        case tourist
        /// Farms.
        case farming
        /// No kind of job stands out.
        case mixed

        /// "mostly homes", "以住宅為主".
        public func name(in language: DisplayLanguage) -> String {
            switch self {
            case .residential: language.text("mostly homes", "以住宅為主")
            case .commercial: language.text("mostly shops", "以商業為主")
            case .business: language.text("mostly offices", "以辦公為主")
            case .industrial: language.text("mostly industry", "以工業為主")
            case .civic: language.text("mostly schools and public services", "以文教為主")
            case .tourist: language.text("mostly tourism", "以觀光為主")
            case .farming: language.text("mostly farming", "以農業為主")
            case .mixed: language.text("a mix of work", "各業均衡")
            }
        }

        /// The kind `use`'s jobs count towards: the shop jobs among homes
        /// and in parks are commerce, as ``CityDemand/Kind`` counts them.
        static func sector(of use: LandUse) -> Kind {
            switch use {
            case .residential, .commercial, .park: .commercial
            case .office: .business
            case .industrial: .industrial
            case .civic: .civic
            case .leisure: .tourist
            case .agricultural: .farming
            }
        }

        /// Each sector's usual share of the jobs, in thousandths: the whole
        /// of Taiwan's land as the app reads it in (``LandImport``, 12.0
        /// million jobs; ``CityTitleReportTests`` prints them).
        static let usualShare: [Kind: Int64] = [
            .commercial: 537, .business: 119, .industrial: 252, .civic: 21, .tourist: 12, .farming: 57,
        ]
        /// The sectors, in the order a tie goes to the first.
        static let sectors: [Kind] = [.commercial, .business, .industrial, .civic, .tourist, .farming]
    }

    /// Below this a city has no kind: a few houses' jobs say nothing.
    public static let kindMinimumResidents: Int64 = Rank.smallTown.residents
    /// A city with fewer jobs than this for every thousand residents is
    /// residential: a third, where Taiwan as a whole has about a half.
    public static let residentialJobsPerThousand: Int64 = 333
    /// How far above its usual share of the jobs, in thousandths of them,
    /// a sector must stand for the city to be named after it.
    public static let leadingMargin: Int64 = 80

    /// Everyone living on the map's land.
    public let residents: Int64
    public let rank: Rank
    /// `nil` for a city too small to have one, or with no jobs.
    public let kind: Kind?
    /// Whether the map's land is read in as the railway reaches it
    /// (``GameWorld/landBlocks``): its residents are those read in so far.
    public let countsAlongTheLines: Bool

    /// The title of the city on `world`'s land, or `nil` with no one on it.
    public init?(world: GameWorld) {
        self.init(cells: world.land.cells, countsAlongTheLines: world.landBlocks != nil)
    }

    /// The title of a city of `cells`, or `nil` with no one living in them.
    public init?(cells: some Sequence<LandCell>, countsAlongTheLines: Bool = false) {
        var residents: Int64 = 0
        // By use, not by sector's name: a map has tens of thousands of
        // cells, and this is read while a panel is open.
        var byUse = [Int64](repeating: 0, count: LandUse.allCases.count)
        let index = Dictionary(uniqueKeysWithValues: LandUse.allCases.enumerated().map { ($1, $0) })
        var last: (use: LandUse, index: Int)?
        for cell in cells {
            residents += cell.residents
            guard cell.jobs > 0 else { continue }
            if last?.use != cell.use { last = (cell.use, index[cell.use] ?? 0) }
            byUse[last?.index ?? 0] += cell.jobs
        }
        var jobs: [Kind: Int64] = [:]
        for (use, count) in zip(LandUse.allCases, byUse) where count > 0 {
            jobs[Kind.sector(of: use), default: 0] += count
        }
        guard residents > 0 else { return nil }
        self.residents = residents
        rank = Rank(residents: residents)
        kind = Self.kind(residents: residents, jobs: jobs)
        self.countsAlongTheLines = countsAlongTheLines
    }

    /// The kind of a city of `residents` with `jobs` in each sector.
    static func kind(residents: Int64, jobs: [Kind: Int64]) -> Kind? {
        let total = jobs.values.reduce(0, +)
        guard residents >= kindMinimumResidents, total > 0 else { return nil }
        // Counts are far below 2⁵³ (``Land/maximumPerCell`` a cell), so
        // the products below do not overflow.
        if total * 1_000 < residents * residentialJobsPerThousand { return .residential }
        var best: (kind: Kind, margin: Int64)?
        for sector in Kind.sectors {
            let margin = (jobs[sector] ?? 0) * 1_000 / total - (Kind.usualShare[sector] ?? 0)
            if margin >= leadingMargin, margin > (best?.margin ?? Int64.min) { best = (sector, margin) }
        }
        return best?.kind ?? .mixed
    }

    // MARK: - Words

    /// "Metropolis · mostly shops", "都會 · 以商業為主"; the size alone for
    /// a city with no kind.
    public func headline(in language: DisplayLanguage) -> String {
        guard let kind else { return rank.name(in: language) }
        return "\(rank.name(in: language)) · \(kind.name(in: language))"
    }

    /// How many more residents the next size needs, or `nil` at the largest.
    public var residentsToNext: Int64? {
        rank.next.map { $0.residents - residents }
    }

    /// "4,682,180 residents. 5,317,820 more make it a megalopolis."
    public func detail(in language: DisplayLanguage) -> String {
        let count = residents.groupedText
        // The same words on a map whose land is read in as it is needed:
        // a new game in a real city has millions there before any line.
        let people = language.text(residents == 1 ? "1 resident." : "\(count) residents.", "居民 \(count) 人。")
        guard let next = rank.next, let more = residentsToNext else {
            return people + language.text(" The largest size there is.", "已經是最大的規模。")
        }
        return people + language.text(
            " \(more.groupedText) more make it a \(next.name(in: language).lowercased()).",
            "再 \(more.groupedText) 人成為\(next.name(in: language))。"
        )
    }

    /// What the panel says of a map with no one on its land yet.
    public static func emptyText(in language: DisplayLanguage) -> String {
        language.text("No one lives along your lines yet.", "沿線還沒有居民。")
    }

    /// What the size and the kind go by, under the panel's row.
    public static func helpText(in language: DisplayLanguage) -> String {
        language.text(
            "More residents make a larger city. Its kind is the work it has more of than most cities.",
            "居民越多，城市的規模越大。類型看城裡哪一種工作比一般城市多。"
        )
    }

    /// The news of the map reaching `rank`: "This place has grown into a
    /// metropolis." Not "the city": one of the ranks is "city" (review
    /// L17-10: "The city has grown into a city.").
    public static func promotionText(_ rank: Rank, in language: DisplayLanguage) -> String {
        language.text("This place has grown into a \(rank.name(in: language).lowercased()).", "這裡成長為\(rank.name(in: language))了。")
    }
}
