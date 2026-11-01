import GameCore

// Buying a real branch line (ARCHITECTURE decision 315): on a real-world
// map, a TRA branch line with its track, stations, trains and real
// timetable, in one command (``PlayerCommand/acquireRealLine(_:)``). The
// session lays it out on a copy of the world as the ground demo lays the
// Pingxi Line (decision 132, ``RealWorldDemo/GroundLayout``): the real
// line's centre line from its junction to its terminal, level at each
// station, a passing loop where the real trains meet or stand side by
// side, the trains where the real ones stand at midnight, and the line
// running TRA's own trains (decision 133, `tra_branch_runs.json`). GameCore
// then records the purchase and its riders' price
// (``GameWorld/recordLineAcquisition(line:realLine:dailyRiders:tier:)``).
//
// The reference has no purchase of a line (decision 315's reference
// table): its data (the timetable, the stations' riders) and the ground
// demo's layout are what is reused.

/// A TRA branch line a company can buy (decision 315), a light rail
/// (decision 400, 10j-2) or a metro line (10j-3).
public struct RealBranchLine: Hashable, Sendable {
    /// Its `tra.json` id (`PINGXI`), or its line's id in its system's
    /// `<system>.json` (`VB`).
    public let network: String
    public let english: String
    public let chinese: String
    /// Its stations by their Chinese names, the junction first.
    public let stops: [String]
    /// The site's system of its stations and track: `tra_sched`, `ntdlrt`,
    /// `mrt` (Taipei's metro).
    public let system: String
    /// Decision 400: the line already bought that it shares its first
    /// stations with (`ntdlrt:V`), when it is laid only from where they
    /// part; `nil` for the whole line.
    public let after: String?
    /// Decision 400 (10j-3): what kind of railway it is, which sets what
    /// its riders cost.
    public let tier: LineAcquisition.Tier
    /// Decision 400 (10j-3): whether its first station is another line's
    /// it leaves, as a branch line's junction (Beitou, the Xinbeitou
    /// Branch's), whose riders that line has.
    let leavesALine: Bool

    public init(
        network: String, english: String, chinese: String, stops: [String], system: String = RealBranchLine.tra, after: String? = nil,
        tier: LineAcquisition.Tier? = nil, leavesALine: Bool = false
    ) {
        self.network = network
        self.english = english
        self.chinese = chinese
        self.stops = stops
        self.system = system
        self.after = after
        self.tier = tier ?? (system == Self.tra ? .branch : .lightRail)
        self.leavesALine = leavesALine
    }

    /// The name GameCore records it by (``LineAcquisition/realLine``):
    /// `tra:PINGXI`, `ntdlrt:VB`, `trtc:R_XBT`.
    public var id: String { system == Self.tra ? "tra:\(network)" : "\(Self.dataSystem(of: system)):\(network)" }

    public static let tra = "tra_sched"

    /// The app's files a site system's lines are in (`trtc.json` for
    /// `mrt`).
    static func dataSystem(of system: String) -> String { system == "mrt" ? "trtc" : system }

    /// Whether it is a light rail or a metro rather than a TRA branch line.
    var isUrban: Bool { system != Self.tra }

    /// Whether it is laid with a second track beside the first.
    var isDoubleTrack: Bool { isUrban || Self.doubleTrack.contains(network) }

    /// Cars of its trains: the DR1000's three on the branch lines
    /// (decision 315's reference row), as the demo's on the light rails
    /// and metros (``DemoRealLines/cars(ofSystem:)``).
    /// Decision 535: the Wenhu Line's four, as its real trains have.
    var cars: Int {
        guard isUrban else { return RealLineAcquisition.carsPerTrain }
        return isWenhu ? 4 : DemoRealLines.cars(ofSystem: system)
    }

    /// Whether it is the Wenhu Line (decision 535), whose rubber-tyred
    /// medium-capacity trains are the game's APM.
    var isWenhu: Bool { system == "mrt" && network == "BR" }

    /// Whether its price pays for the riders of its first station: not at a
    /// branch line's junction, which is the main line's, nor where a light
    /// rail joins the one bought before, whose riders that paid for.
    var paysForFirstStop: Bool { isUrban && after == nil && !leavesALine }

    /// The type of its trains: the game's light metro on a light rail, its
    /// heavy metro on Taipei's, its medium one on the Sanying Line, its
    /// APM on the Wenhu Line (decision 535); `nil` (the game's first) on a
    /// branch line.
    var trainType: TrainType? {
        switch tier {
        case .branch: nil
        case .lightRail: .c
        case .metro: isWenhu ? .apm : system == "mrt" ? .a : .b
        }
    }

    /// The light rails and metro lines on sale (decision 400, 10j-2 and
    /// 10j-3): their system, line, names, the line whose first stations
    /// they share, their tier and whether they leave another line at their
    /// first station. A line is on sale where `metro_runs.json` has its
    /// runs (`tools/real-timetables/extract_metro_runs.py` says why the
    /// others are not). Kaohsiung's Circular Light Rail is not listed:
    /// the game's runs do not go round a ring yet (decision 535). The
    /// Wenhu Line is bought with its two depots (decision 535).
    static let urbanLines: [(system: String, network: String, english: String, chinese: String, shares: String?, tier: LineAcquisition.Tier, leavesALine: Bool)] = [
        ("ntdlrt", "V", "Danhai LRT Green Mountain Line", "淡海輕軌綠山線", "ntdlrt:VB", .lightRail, false),
        ("ntdlrt", "VB", "Danhai LRT Blue Coast Line", "淡海輕軌藍海線", "ntdlrt:V", .lightRail, false),
        ("ntalrt", "K", "Ankeng LRT", "安坑輕軌", nil, .lightRail, false),
        ("mrt", "R_XBT", "Xinbeitou Branch Line", "新北投支線", nil, .metro, true),
        ("mrt", "G_XBT", "Xiaobitan Branch Line", "小碧潭支線", nil, .metro, true),
        ("mrt", "BR", "Wenhu Line", "文湖線", nil, .metro, false),
        ("sanying", "LB", "Sanying Line", "三鶯線", nil, .metro, false),
    ]

    public func name(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    /// Decision 400: the runs of the light rail or metro `id`, from where
    /// it parts from `after` when that is already bought; decision 493,
    /// the whole line's where `extract_metro_runs.py` lists none from there
    /// (the Green Mountain Line after the Blue Coast Line, laid beside it).
    static func metroRuns(of id: String, after: String?, in railways: RealRailways) -> RealLineRuns? {
        after.flatMap { railways.metroRuns["\(id) after \($0)"] } ?? railways.metroRuns[id]
    }

    /// The lines on sale (decision 315).
    static let names: [String: (english: String, chinese: String)] = [
        "PINGXI": ("Pingxi Line", "平溪線"),
        "JIJI": ("Jiji Line", "集集線"),
        "NEIWAN": ("Neiwan Line", "內灣線"),
        "SHENAO": ("Shenao Line", "深澳線"),
        "LIUJIA": ("Liujia Line", "六家線"),
        "SHALUN": ("Shalun Line", "沙崙線"),
    ]

    /// The lines on sale that are double track, laid with a second track
    /// beside the first (decision 315's later note); the others run on a
    /// single track with passing loops.
    static let doubleTrack: Set<String> = ["LIUJIA", "SHALUN"]
}

/// How a line's stations are laid (decision 315; decision 400 for the
/// light rails): how far each loop reaches from its station, how long it
/// takes to move out, how far it stands off the track it leaves, and how
/// many deep the loops of an end station may lie either side.
struct RealLineLayout {
    let loopReach: Double
    let loopRamp: Double
    let loopOffset: Double
    let endLevels: Int

    /// A branch line's: the ground demo's loops, one either side.
    static let branch = RealLineLayout(
        loopReach: RealWorldDemo.loopReach, loopRamp: RealWorldDemo.loopRamp, loopOffset: RealWorldDemo.groundLoopOffset, endLevels: 1
    )
    /// A light rail's: its stations 500 m to 1.4 km apart and its trains
    /// short, a loop reaches 100 m and moves out over 50 m; the trains an
    /// end stands at once on loops two deep either side, the outer one its
    /// ramp further out and longer, so neither crosses the other; three
    /// deep where an end stands six or seven (decision 489, the Green
    /// Mountain Line bought with its depot: its trains stand there by day,
    /// not overnight).
    static let lightRail = RealLineLayout(
        loopReach: 100 * RealLineAcquisition.metre, loopRamp: 50 * RealLineAcquisition.metre, loopOffset: RealWorldDemo.groundLoopOffset, endLevels: 3
    )
    /// The most cars a train laid with ``lightRail``'s loops has: their
    /// straight 100 m holds its platform.
    static let lightRailCars = 3
    /// A metro's of longer trains (decision 400, 10j-3): as a light rail's,
    /// its loops reaching 150 m, so their straight holds a platform of six
    /// cars and more.
    static let metro = RealLineLayout(
        loopReach: 150 * RealLineAcquisition.metre, loopRamp: 50 * RealLineAcquisition.metre, loopOffset: RealWorldDemo.groundLoopOffset, endLevels: 2
    )

    /// The `level`th loop out (from 1): its reach and its ramp.
    func reach(level: Int) -> Double { loopReach + Double(level - 1) * loopRamp }
    func ramp(level: Int) -> Double { Double(level) * loopRamp }
}

/// A real line bought, as the session laid it out: every node, edge,
/// station, platform and train, so the command log replays it without the
/// real data (decision 193).
public struct RealLineAcquisition: Hashable, Sendable, Codable {
    /// A node of a piece built before.
    public struct NodeAt: Hashable, Sendable, Codable {
        public let piece: Int
        public let node: Int
    }

    /// A stretch of track: its nodes, the first and last perhaps nodes of
    /// pieces built before, and its edges between them, each `distances`
    /// along the plan's path; `together`, built as one (a passing loop,
    /// ``GameWorld/buildTrackEdges(_:)``). `ground` is read in first.
    public struct Piece: Hashable, Sendable, Codable {
        public let nodes: [WorldCoordinate]
        public let start: NodeAt?
        public let end: NodeAt?
        public let curves: [TrackCurve]
        public let distances: [Double]
        public let structure: TrackStructure
        public let together: Bool
        public let ground: [PlanPoint]
    }

    /// A place on a piece: `distance` along its path.
    public struct PieceAt: Hashable, Sendable, Codable {
        public let piece: Int
        public let distance: Double
    }

    /// A station: one the company has (the junction's, decision 315 §4),
    /// or a new one by its real name at `at`, with `demand` where a managed
    /// company sets ridership rather than the land.
    public struct Stop: Hashable, Sendable, Codable {
        public let name: String
        public let at: PlanPoint
        public let existing: StationID?
        public let demand: StationDemand
    }

    /// A platform of stop `stop`, from `at` on for `length`.
    public struct Platform: Hashable, Sendable, Codable {
        public let stop: Int
        public let at: PieceAt
        public let length: Int64
    }

    /// A train standing at a platform beginning at `at` overnight, facing
    /// along its piece or back.
    public struct Start: Hashable, Sendable, Codable {
        public let name: String
        public let at: PieceAt
        public let forward: Bool
    }

    public let realLine: String
    public let pieces: [Piece]
    public let stops: [Stop]
    public let platforms: [Platform]
    public let lineName: String
    public let color: LineColor?
    public let runs: [LineRun]
    public let trains: [Start]
    public let cars: Int
    /// Decision 400: the type of its trains, the game's light metro on a
    /// light rail; `nil` for the game's first (and in the logs of before).
    public let trainType: TrainType?
    /// The real riders a day of its stations past the junction (decision
    /// 298), which its price pays for.
    public let dailyRiders: Int64
    /// Decision 400 (10j-3): what kind of railway it is, which sets what
    /// each of its riders costs; `nil` for a branch line (and in the logs
    /// of before, a light rail's then priced as one).
    public let tier: LineAcquisition.Tier?
    /// Decision 401: the tiles under it the company does not own yet, on a
    /// map bought tile by tile, in the order they are bought, each beside
    /// one owned by then; `nil` for none (and in the logs of before).
    public let tiles: [MapTile]?
    /// Decision 479: the real depot bought with it, the line's; `nil` for
    /// none (and in the logs of before).
    public let depot: Depot?
    /// Decision 535: the line's other real depots (the Wenhu Line's second,
    /// past its other end); `nil` for none (and in the logs of before).
    public let moreDepots: [Depot]?
    /// Decision 528: the track the same line left when it was bought and
    /// removed before, taken up first; `nil` for none (and in the logs of
    /// before).
    public let clearing: RealLineClearing?

    public init(
        realLine: String, pieces: [Piece], stops: [Stop], platforms: [Platform], lineName: String, color: LineColor?, runs: [LineRun],
        trains: [Start], cars: Int, trainType: TrainType? = nil, dailyRiders: Int64, tiles: [MapTile]?, tier: LineAcquisition.Tier? = nil,
        depot: Depot? = nil, moreDepots: [Depot]? = nil, clearing: RealLineClearing? = nil
    ) {
        self.realLine = realLine
        self.pieces = pieces
        self.stops = stops
        self.platforms = platforms
        self.lineName = lineName
        self.color = color
        self.runs = runs
        self.trains = trains
        self.cars = cars
        self.trainType = trainType
        self.dailyRiders = dailyRiders
        self.tiles = tiles
        self.tier = tier
        self.depot = depot
        self.moreDepots = moreDepots
        self.clearing = clearing
    }

    /// It, taking `clearing` up first (decision 528).
    func clearing(_ clearing: RealLineClearing?) -> RealLineAcquisition {
        RealLineAcquisition(
            realLine: realLine, pieces: pieces, stops: stops, platforms: platforms, lineName: lineName, color: color, runs: runs, trains: trains,
            cars: cars, trainType: trainType, dailyRiders: dailyRiders, tiles: tiles, tier: tier, depot: depot, moreDepots: moreDepots,
            clearing: clearing
        )
    }

    /// Cars per train: the DR1000's three (decision 315's reference row).
    static let carsPerTrain = 3
    static let metre = Double(WorldCoordinate.unitsPerMetre)
    /// How far past each end the track runs on, so a loop at a terminal
    /// has room: a loop's reach and a little.
    static let runOn = RealWorldDemo.loopReach + 60 * metre
    /// How near the real junction a station of the company's is the one
    /// the line joins (decision 295's 450 m).
    static let junctionReach = 450 * metre
    /// How far a real station may be from its line's centre line.
    static let stationReach = 150 * metre
    /// Decision 489: how far beside the other line's track a line bought
    /// after it is laid where they part: clear of its double track, with
    /// the end's loops two deep (12 m) and the 4 m between tracks.
    static let besideOffset = 30 * metre

    /// Decision 462: how far over the ground a station on a viaduct stands
    /// at least: as high as a station on the ground beside it may, and
    /// the clearance of track crossing over track (``TrackStructure/clearance``)
    /// above that.
    static let raisedStation = RealWorldDemo.stationReach + Double(TrackStructure.clearance)

    /// Decision 462: whether a station `at` along a line's path, its
    /// neighbours `before` and `after` (`nil` at an end), stands on the
    /// real line's viaduct: a bridge at least ``TrackRise/shortestCarried``
    /// long under it carries the line on at least that far toward each
    /// neighbour. A station beside another line's viaduct, which its path
    /// runs along only a little way (the Neiwan Line's at Zhuzhong, beside
    /// the Liujia Line's), stays on the ground.
    static func isRaised(at: Double, before: Double?, after: Double?, carried: [TrackRise.Carried]) -> Bool {
        let reach = TrackRise.shortestCarried
        return carried.contains { stretch in
            stretch.kind == .bridge && stretch.range.contains(at)
                && before.map { stretch.range.lowerBound <= at - min(reach, at - $0) } ?? true
                && after.map { stretch.range.upperBound >= at + min(reach, $0 - at) } ?? true
        }
    }

    /// Decision 401: `tiles` in an order the company can buy them, each
    /// beside one owned or bought before it (``GameWorld/buyMapTile(_:passingMilestone:)``),
    /// by row and then column among those it could buy next; `nil` when
    /// some never touch the land owned.
    static func buyingOrder(of tiles: Set<MapTile>, owned: [MapTile]) -> [MapTile]? {
        var reached = Set(owned), left = tiles.subtracting(reached), order: [MapTile] = []
        while !left.isEmpty {
            guard let next = left.sorted().first(where: { $0.neighbours.contains(where: reached.contains) }) else { return nil }
            order.append(next)
            reached.insert(next)
            left.remove(next)
        }
        return order
    }
}

/// What buying a line costs, item by item (decision 315 §2).
public struct RealLineAcquisitionPrice: Hashable, Sendable {
    /// The tiles under it not owned yet (decision 401).
    public let land: Money
    /// Its track, stations and platforms, at the game's prices.
    public let building: Money
    public let trains: Money
    /// Its riders (``LineAcquisition/value(ofDailyRiders:tier:)``).
    public let riders: Money

    public var total: Money { land + building + trains + riders }
}

/// The offer of a line: what the purchase lays and costs, or why it
/// cannot be bought here.
public struct RealLineOffer: Sendable {
    public let line: RealBranchLine
    public let acquisition: RealLineAcquisition?
    public let price: RealLineAcquisitionPrice?
    /// Why it cannot be bought, as the player reads it.
    public let problem: String?

    /// The card's price rows (decision 315 §2), and the total last.
    public func priceRows(in language: DisplayLanguage) -> [(label: String, amount: Money)] {
        guard let price, let acquisition else { return [] }
        let tiles = acquisition.tiles?.count ?? 0
        let land = tiles == 0 ? [] : [
            (label: language.text("\(tiles) \(tiles == 1 ? "tile" : "tiles") of land along it", "沿線的 \(tiles) 塊地"), amount: price.land),
        ]
        return land + [
            (language.text("Track, stations and platforms", "軌道、車站與月台"), price.building),
            (language.text("\(acquisition.trains.count) trains", "\(acquisition.trains.count) 列車"), price.trains),
            (language.text("Its regulars along the line", "沿線的常客"), price.riders),
            (language.text("Total", "合計"), price.total),
        ]
    }

    /// What the purchase brings, in a line.
    public func summaryText(in language: DisplayLanguage) -> String {
        let stops = line.stops.count
        guard let acquisition else { return language.text("\(stops) stations", "\(stops) 站") }
        let summary = language.text(
            "\(line.stops.first ?? "") to \(line.stops.last ?? ""): \(stops) stations, \(acquisition.trains.count) trains and the real timetable",
            "\(line.stops.first ?? "")—\(line.stops.last ?? "")：\(stops) 站、\(acquisition.trains.count) 列車與真實班次"
        )
        // Decision 528: what it takes up first.
        guard let clearing = acquisition.clearing else { return summary }
        return summary + language.text(". ", "。") + clearing.text(in: language)
    }

    /// What the company still lacks to buy it with `balance`, or `nil`
    /// when it has enough (or there is nothing to buy).
    public func shortfallText(balance: Money, in language: DisplayLanguage) -> String? {
        guard let total = price?.total, balance < total else { return nil }
        let short = (total - balance).moneyText
        return language.text("\(short) short of the price.", "還差 \(short)。")
    }

    /// What the card says when the game has real transfers off.
    public static func transfersOffText(in language: DisplayLanguage) -> String {
        language.text(
            "Real transfers are off: the line has only the riders of the towns along it.",
            "關掉了真實轉乘，這條線只有沿線城鎮的旅客。"
        )
    }
}

extension GameSession {
    // MARK: - On sale

    /// The branch lines this map sells (decision 315 §1): on a real-world
    /// map with the real trains loaded, each whose stations all lie in the
    /// world and that the company has not bought.
    public var buyableRealLines: [RealBranchLine] {
        // Decision 328: worked out again only when the map, the lines
        // bought or the railways change, not at every tick while a panel
        // asks (some 2 ms each time).
        realLineSale.lines
    }

    /// The lines on sale and those the map holds only part of, worked out
    /// again only when what they come from changes.
    private var realLineSale: RealLineSale {
        let key = BuyableRealLinesKey(bounds: world.bounds, anchor: world.geoAnchor, bought: world.acquisitions, railways: railwaysRevision)
        if let memo = buyableRealLinesMemo, memo.key == key { return memo.sale }
        let sale = workOutRealLineSale()
        buyableRealLinesMemo = (key, sale)
        return sale
    }

    private func workOutRealLineSale() -> RealLineSale {
        guard let railways, let frame = RealWorldFrame(world: world) else { return RealLineSale(lines: [], partlyOnTheMap: [], bought: false) }
        var sale = RealLineSale(lines: [], partlyOnTheMap: [], bought: false)
        var lines = RealBranchLine.names.keys.sorted().compactMap { network -> RealBranchLine? in
            guard let runs = railways.branchRuns[network], let names = RealBranchLine.names[network] else { return nil }
            return RealBranchLine(network: network, english: names.english, chinese: names.chinese, stops: runs.stops)
        }
        // Decision 400: the light rails; one sharing its first stations
        // with a line bought, from where they part, or not at all where its
        // trips from there do not fit.
        for rail in RealBranchLine.urbanLines {
            let id = "\(RealBranchLine.dataSystem(of: rail.system)):\(rail.network)"
            let after = rail.shares.flatMap { world.acquisition(of: $0) == nil ? nil : $0 }
            guard let runs = RealBranchLine.metroRuns(of: id, after: after, in: railways) else {
                if world.acquisition(of: id) != nil { sale.bought = true }
                continue
            }
            lines.append(RealBranchLine(
                network: rail.network, english: rail.english, chinese: rail.chinese, stops: runs.stops, system: rail.system, after: after,
                tier: rail.tier, leavesALine: rail.leavesALine
            ))
        }
        for line in lines {
            guard world.acquisition(of: line.id) == nil else {
                sale.bought = true
                continue
            }
            let onTheMap = line.stops.count { name in
                realPoint(of: name, system: line.system, railways: railways, frame: frame).map { world.bounds.contains($0.plan) } ?? false
            }
            if onTheMap == line.stops.count {
                sale.lines.append(line)
            } else if onTheMap > 0 {
                sale.partlyOnTheMap.append(line)
            }
        }
        return sale
    }

    /// Decision 336: why the lines panel lists no real line for sale, in a
    /// line; `nil` while it lists some, and in the tutorial or a lesson.
    public var realLinesForSaleNote: String? {
        guard tutorial == nil, lesson == nil else { return nil }
        guard world.geoAnchor != nil else {
            return language.text(
                "Real branch lines are for sale on real-world maps.",
                "真實支線只在實景地圖上可以收購。"
            )
        }
        guard railways != nil else {
            return language.text("The real railways are still loading.", "真實鐵路還在載入。")
        }
        let sale = realLineSale
        guard sale.lines.isEmpty else { return nil }
        if !sale.partlyOnTheMap.isEmpty {
            let names = sale.partlyOnTheMap.map { $0.name(in: language) }.joined(separator: language.text(" and ", "、"))
            return language.text(
                "This map holds only part of the \(names). A line is for sale when all its stations are on the map.",
                "這張地圖只框到\(names)的一部分。整條線的車站都在地圖上，才可以收購。"
            )
        }
        if sale.bought {
            return language.text("You own every real branch line on this map.", "這張地圖上的真實支線都是你的了。")
        }
        return language.text("No real branch line runs through this map.", "這張地圖上沒有可以收購的真實支線。")
    }

    /// The branch line on sale that real station `name` (its Chinese name)
    /// is on past its junction, if any; or, of `system`, the line on sale
    /// of that system (a light rail's first station is its own).
    public func buyableRealLine(through name: String, system: String = RealBranchLine.tra) -> RealBranchLine? {
        buyableRealLines.first { $0.system == system && ($0.paysForFirstStop ? $0.stops[...] : $0.stops.dropFirst()).contains(name) }
    }

    /// The branch line on sale that station `id` stands on past its
    /// junction, by the real station beside it (decision 315 §1), if any.
    public func buyableRealLine(at id: StationID) -> RealBranchLine? {
        guard let station = world.station(id: id), !station.isDepot,
              let place = nearestRealStation(to: station.point) else { return nil }
        return place.stations.lazy.compactMap { self.buyableRealLine(through: $0.chinese, system: $0.system.id) }.first
    }

    /// Opens the purchase card for `line`, laid out and priced now.
    /// Opens the purchase card for `line` (decision 497): at once, saying
    /// it is being prepared (``preparingRealLine``), while the line is laid
    /// out and priced off the main actor (``realLineLaying``; up to 2 s on
    /// a real map of 64 stations, all of it a frozen screen before). The
    /// offer shows only if it was laid out on the world as it still is
    /// (``commandRevision`` and the railways unchanged); otherwise it is
    /// laid out again on the world as it is now. Closing the card drops it.
    public func offerRealLine(_ line: RealBranchLine) {
        shownRealLineOffer = nil
        preparingRealLine = line
        layRealLineOffer(line)
    }

    private func layRealLineOffer(_ line: RealBranchLine) {
        realLineOfferTask?.cancel()
        let laying = realLineLaying, revision = commandRevision, railways = railwaysRevision
        realLineOfferTask = Task {
            let offer = await Task.detached(priority: .userInitiated) { laying.offer(for: line) }.value
            guard !Task.isCancelled, preparingRealLine == line else { return }
            guard commandRevision == revision, railwaysRevision == railways else {
                layRealLineOffer(line)
                return
            }
            realLineOfferTask = nil
            preparingRealLine = nil
            shownRealLineOffer = offer
        }
    }

    /// Closes the purchase card, or stops preparing it.
    public func closeRealLineOffer() {
        realLineOfferTask?.cancel()
        realLineOfferTask = nil
        preparingRealLine = nil
        shownRealLineOffer = nil
    }

    /// Waits for the offer being prepared, if any (for the tests).
    func realLineOfferPrepared() async {
        while let task = realLineOfferTask {
            await task.value
            if realLineOfferTask == task { break }
        }
    }

    private func realPoint(of name: String, system: String, railways: RealRailways, frame: RealWorldFrame) -> WorldVector? {
        RealLineLaying.realPoint(of: name, system: system, railways: railways, frame: frame)
    }

    /// What laying out and pricing a real line reads of the session, taken
    /// as it is now (decision 497).
    var realLineLaying: RealLineLaying {
        RealLineLaying(
            world: world, railways: railways, traces: realRailwayTraces, language: language, population: population, places: places,
            water: water, coverage: coverage, heights: heights
        )
    }

    /// ``RealLineLaying/offer(for:)`` on the world as it is now, on the
    /// main actor.
    public func realLineOffer(for line: RealBranchLine) -> RealLineOffer {
        realLineLaying.offer(for: line)
    }

    func realLineOffer(for line: RealBranchLine, raising: RealLineLaying.StationRaising, depot: Bool = true) -> (offer: RealLineOffer, crossesTrack: Bool) {
        let laid = realLineLaying.offer(for: line, raising: raising, depot: depot)
        return (laid.offer, laid.crossesTrack)
    }

    func build(_ acquisition: RealLineAcquisition, in world: inout GameWorld, recording: Bool = true) throws(GameError) -> RealLineAcquisitionPrice {
        try realLineLaying.build(acquisition, in: &world, recording: recording)
    }

    func buildStepByStep(_ acquisition: RealLineAcquisition, in world: inout GameWorld, recording: Bool = true) throws(GameError) -> RealLineAcquisitionPrice {
        try realLineLaying.buildStepByStep(acquisition, in: &world, recording: recording)
    }
}

/// Decision 497: what laying out, pricing and building a real line reads
/// of the session (``GameSession/realLineLaying``), as values, so a line's
/// offer can be laid out off the main actor.
struct RealLineLaying: Sendable {
    let world: GameWorld
    let railways: RealRailways?
    /// ``GameSession/realRailwayTraces``.
    let traces: RealRailwayTraces?
    let language: DisplayLanguage
    let population: PopulationGrid?
    let places: PlaceGrid?
    let water: WaterGrid?
    let coverage: CoverageGrid?
    let heights: HeightGrid?

    static func realPoint(of name: String, system: String, railways: RealRailways, frame: RealWorldFrame) -> WorldVector? {
        railways.stations.first { $0.id == "\(system)|\(name)" }.map {
            WorldVector(frame.worldPosition(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
        }
    }

    private func realPoint(of name: String, system: String, railways: RealRailways, frame: RealWorldFrame) -> WorldVector? {
        Self.realPoint(of: name, system: system, railways: railways, frame: frame)
    }

    /// ``GameSession/newStationDemand(at:)``.
    private func newStationDemand(at point: PlanPoint) -> StationDemand {
        GameSession.newStationDemand(at: point, in: world, population: population, places: places)
    }
}

extension RealLineLaying {
    // MARK: - The offer

    /// Lays `line` out on a copy of the world and prices it (decision 315):
    /// the purchase, or why it cannot be made here (track in the way, land
    /// not bought, a grade too steep). Want of cash is not a problem here:
    /// the card weighs the price against the balance.
    ///
    /// Decision 462: a station on its line's real viaduct stands up on it
    /// (``RealLineAcquisition/isRaised(at:before:after:carried:)``). Where
    /// the track still meets another's at one level, the line is laid once
    /// more with the stations it shares with the company's raised too: a
    /// line bought before decision 462 lies on the ground at Zhuzhong
    /// whichever it was.
    func offer(for line: RealBranchLine) -> RealLineOffer {
        let laid = laidOffer(for: line)
        // Decision 528: refused where the same line, bought and removed
        // before, left its track, laid again on the world without that
        // track, which is taken up first. A first purchase, or one nothing
        // is in the way of, takes nothing up.
        guard laid.offer.acquisition == nil, let left = RealLineClearing.left(in: world, for: line),
              var clearing = RealLineClearing.clearing(in: world, taking: left.own + left.shared, shared: !left.shared.isEmpty)
        else { return laid.offer }
        func refusal(_ error: GameError) -> RealLineOffer {
            RealLineOffer(line: line, acquisition: nil, price: nil, problem: language.text(
                "The track the line left cannot be taken up: ", "這條線之前留下的軌道拆不掉："
            ) + error.playerMessage(in: language))
        }
        func laying(taking clearing: RealLineClearing) -> (offer: RealLineOffer, cleared: GameWorld?) {
            var cleared = world.pricingCopy()
            do throws(GameError) {
                try clearing.apply(to: &cleared)
            } catch {
                return (refusal(error), nil)
            }
            let again = RealLineLaying(
                world: cleared, railways: railways, traces: traces, language: language, population: population, places: places, water: water,
                coverage: coverage, heights: heights
            ).laidOffer(for: line)
            return (again.offer, cleared)
        }
        let again = laying(taking: clearing)
        guard var acquisition = again.offer.acquisition, let cleared = again.cleared else { return again.offer }
        // #1636 second review, P2: the track the line sharing its first
        // stations left is taken up only where the line laid without it
        // comes onto it (or close beside it); the rest (the Green
        // Mountain Line's way to Kanding, for the Blue Coast Line) stays.
        // A piece missed, the purchase built on the world without the
        // rest names it, and it is taken up too.
        if !left.shared.isEmpty {
            var built = cleared
            let before = Set(built.network.edges.map(\.id))
            var taking: [TrackEdgeID] = []
            if (try? build(acquisition, in: &built, recording: false)) != nil {
                taking = RealLineClearing.overlapping(left.shared, in: world, laid: built, besides: before)
            } else {
                taking = left.shared
            }
            // The least that lets the purchase be built; the whole of it
            // where something else refuses the purchase.
            var narrowed = clearing
            narrowing: for _ in 0...left.shared.count {
                let tried = RealLineClearing.clearing(in: world, taking: left.own + taking, shared: !taking.isEmpty)
                var probe = world.pricingCopy()
                do throws(GameError) {
                    try tried?.apply(to: &probe)
                    _ = try build(acquisition, in: &probe, recording: false)
                    if let tried { narrowed = tried }
                    break narrowing
                } catch {
                    let blocking: TrackEdgeID? = switch error {
                    case .trackConflict(let edge), .trackTooClose(let edge): edge
                    default: nil
                    }
                    guard let blocking, left.shared.contains(blocking), !taking.contains(blocking) else { break narrowing }
                    taking.append(blocking)
                }
            }
            // Laid again on the world keeping the rest; refused there
            // after all, the whole is taken up as before.
            if narrowed != clearing, let narrowedAcquisition = laying(taking: narrowed).offer.acquisition {
                acquisition = narrowedAcquisition
                clearing = narrowed
            }
        }
        let bought = acquisition.clearing(clearing)
        var probe = world.pricingCopy()
        do throws(GameError) {
            let price = try build(bought, in: &probe)
            return RealLineOffer(line: line, acquisition: bought, price: price, problem: nil)
        } catch {
            return refusal(error)
        }
    }

    /// ``offer(for:)`` without taking up what the line left before, and
    /// the line as laid where GameCore refused it.
    private func laidOffer(for line: RealBranchLine) -> (offer: RealLineOffer, laid: RealLineAcquisition?) {
        func offer(depot: Bool) -> (offer: RealLineOffer, laid: RealLineAcquisition?) {
            let laid = self.offer(for: line, raising: .viaducts, depot: depot)
            guard laid.crossesTrack else { return (laid.offer, laid.laid) }
            let raised = self.offer(for: line, raising: .viaductsAndShared, depot: depot)
            return raised.offer.problem == nil ? (raised.offer, raised.laid) : (laid.offer, laid.laid)
        }
        // Decision 479: without its depot where that cannot be laid; not
        // a line whose end has no room for its trains without it
        // (decision 489).
        let laid = offer(depot: true)
        let sites = RealLineDepotSite.sites(of: line.id)
        guard laid.offer.acquisition == nil, !sites.isEmpty, sites.allSatisfy({ $0.beyond == nil }) else { return laid }
        let without = offer(depot: false)
        return without.offer.acquisition == nil ? laid : without
    }

    /// Which of a line's stations stand raised (decision 462).
    enum StationRaising {
        /// None, as before decision 462 (the layout old saves hold).
        case none
        /// Those on the real line's viaduct.
        case viaducts
        /// Those, and those whose station the company already has.
        case viaductsAndShared
    }

    /// The offer of `line` with its stations raised as `raising` says,
    /// whether GameCore refused it for its track meeting another's at one
    /// level (``GameError/trackConflict(_:)``), and the line as laid where
    /// GameCore refused it (decision 528).
    func offer(for line: RealBranchLine, raising: StationRaising, depot: Bool = true) -> (offer: RealLineOffer, crossesTrack: Bool, laid: RealLineAcquisition?) {
        func refused(_ english: String, _ chinese: String) -> (offer: RealLineOffer, crossesTrack: Bool, laid: RealLineAcquisition?) {
            (RealLineOffer(line: line, acquisition: nil, price: nil, problem: language.text(english, chinese)), false, nil)
        }
        func refusedForLand() -> (offer: RealLineOffer, crossesTrack: Bool, laid: RealLineAcquisition?) {
            refused(
                "The land this line crosses does not touch yours. Use Expand Map to buy up to the line first, then buy it.",
                "這條線經過的地和你的地不相連。先用「擴建地圖」買到這條線旁邊，再收購。"
            )
        }
        guard let railways, let frame = RealWorldFrame(world: world),
              let runs = line.isUrban ? RealBranchLine.metroRuns(of: line.id, after: line.after, in: railways) : railways.branchRuns[line.network],
              let traces else {
            return refused("This map has no real railway to buy.", "這張地圖沒有可以收購的真實鐵路。")
        }
        guard world.acquisition(of: line.id) == nil else {
            return refused("This line is already yours.", "這條線已經是你的了。")
        }
        let points = runs.stops.compactMap { realPoint(of: $0, system: line.system, railways: railways, frame: frame) }
        guard points.count == runs.stops.count, points.allSatisfy({ world.bounds.contains($0.plan) }) else {
            return refused("The whole line is not on this map.", "這張地圖框不住整條線。")
        }
        // The real line's way from the junction to the terminal, run on
        // straight past each end (Checheng stands 81 m past the end of
        // the Jiji Line's drawing).
        // A light rail's own track, not the metro's beside it.
        let reach = RealLineAcquisition.stationReach, ownSystem = line.isUrban ? line.system : nil
        // Decision 489: a line bought after the one it shares its first
        // stations with (decision 400) starts where they part, on the
        // drawn line its last station is on, not the other's: from the
        // other's, the way to its end runs back to where they meet.
        let parting = line.after == nil ? nil : traces.snap(points[points.count - 1], within: reach, system: ownSystem).flatMap {
            traces.snap(points[0], within: reach, only: $0.place.line)
        }
        guard let first = parting ?? traces.snap(points[0], within: reach, system: ownSystem),
              let last = traces.snap(points[points.count - 1], within: reach, group: traces.groups[first.place.line]),
              let way = traces.path(from: first.place, to: last.place) else {
            return refused("The real line's track could not be followed here.", "這裡沒辦法沿著真實鐵路鋪軌。")
        }
        let traced = WorldPath(way).smoothed()
        guard traced.length > 2 * RealLineAcquisition.runOn else {
            return refused("The real line's track could not be followed here.", "這裡沒辦法沿著真實鐵路鋪軌。")
        }
        let startDirection = traced.tangent(at: 0), endDirection = traced.tangent(at: traced.length)
        // Decision 479: its real depot's leads and yard, where it has one.
        // Decision 535: the Wenhu Line has two, one past each end.
        let depotSites = RealLineDepotSite.sites(of: line.id)
        func worldPoints(_ site: RealLineDepotSite) -> [WorldVector] {
            [site.junction, site.yard.start, site.yard.end].map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
        }
        let depotSite = depotSites.first { $0.beyond == nil }
        let depotPoints = depotSite.map(worldPoints)
        // Decision 489: past the end its depot stands beyond, the line
        // runs on as the real one does, straight to where its leads leave
        // it and round into the yard's way, not straight on.
        let depotEnds: [(stop: Int, site: RealLineDepotSite, points: [WorldVector])] = depot ? depotSites.compactMap { site in
            site.beyond.flatMap { runs.stops.firstIndex(of: $0) }.map { ($0, site, worldPoints(site)) }
        } : []
        func runOn(from end: WorldVector, leaving way: WorldVector, at stop: Int) -> [WorldVector] {
            guard let points = depotEnds.first(where: { $0.stop == stop })?.points else { return [end + way * RealLineAcquisition.runOn] }
            // In the yard's way 50 m short of its sidings' near ends, so
            // the game's ladder, longer than the real one, stays within
            // the real depot.
            let yard = (points[2] - points[1]).unit, into = points[1] - yard * (50 * RealLineAcquisition.metre)
            let junction = end + way * max(0, (points[0] - end).dot(way))
            let handle = 0.4 * (into - junction).length
            let curve = (1...16).map { step -> WorldVector in
                let t = Double(step) / 16, u = 1 - t
                let b = junction + way * handle, c = into - yard * handle
                return junction * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + into * (t * t * t)
            }
            return [junction] + curve
        }
        let laid = WorldPath(
            runOn(from: traced.point(at: 0), leaving: startDirection.reversed, at: 0).reversed() + traced.points
                + runOn(from: traced.point(at: traced.length), leaving: endDirection, at: runs.stops.count - 1)
        )
        // Decision 489: a line bought after the one it shares its first
        // stations with (decision 400) has its own end where they part,
        // whose loops and run-on lie along the other's track: it is laid
        // beside it there, on the side away from where the other turns
        // off, and back onto its own line past its first stop's loops.
        // Decision 493: one bought whole after it (the Green Mountain Line
        // after the Blue Coast Line) is laid beside it from its first stop
        // to where they part.
        let other = line.after.flatMap { RealBranchLine.metroRuns(of: $0, after: nil, in: railways)?.stops } ?? []
        let parts = runs.stops.indices.dropLast().first { !other.contains(runs.stops[$0 + 1]) } ?? 0
        func beside(_ laid: WorldPath, to stop: WorldVector) -> WorldPath {
            let first = laid.nearest(stop).along, full = first + RealLineAcquisition.runOn, blend = 150 * RealLineAcquisition.metre
            func vote(_ points: [PlanPoint]) -> Double {
                points.reduce(0.0) { votes, plan in
                    let point = WorldVector(plan)
                    guard (point - stop).length < (parts == 0 ? full : RealLineAcquisition.runOn + RealLineAcquisition.stationReach) + blend else { return votes }
                    let near = laid.nearest(point)
                    guard parts == 0 || near.along > first - RealLineAcquisition.runOn, near.along < full + blend,
                          near.away > 10 * RealLineAcquisition.metre, near.away < RealLineAcquisition.stationReach else { return votes }
                    return votes + (point - laid.point(at: near.along)).dot(laid.tangent(at: near.along).normal)
                }
            }
            var votes = vote(world.network.nodes.map(\.position.plan))
            // Decision 493: where no node is near enough (the Blue Coast
            // Line's lie far apart round Binhai Shalun), points along the
            // track between them.
            if votes == 0 {
                votes = vote(world.network.edges.flatMap { edge -> [PlanPoint] in
                    guard let from = world.network.node(edge.from), let to = world.network.node(edge.to),
                          let geometry = TrackGeometry(from: from.position, to: to.position, curve: edge.curve) else { return [] }
                    return NetworkBuilding.surveyedPoints(of: geometry)
                })
            }
            let side = votes > 0 ? -1.0 : 1.0
            // Decision 493: along a whole shared stretch, each point moved
            // square to the way over 50 m either side of it, so a tight bend
            // (Binhai Shalun's) does not fold the track laid 30 m inside it.
            let across = 50 * RealLineAcquisition.metre
            func normal(at distance: Double) -> WorldVector {
                guard parts > 0 else { return laid.tangent(at: distance).normal }
                return (laid.point(at: min(distance + across, laid.length)) - laid.point(at: max(distance - across, 0))).unit.normal
            }
            let moved = WorldPath(zip(laid.points, laid.distances).map { point, distance in
                let t = min(max((distance - full) / blend, 0), 1), share = 1 - t * t * (3 - 2 * t)
                return point + normal(at: distance) * (side * RealLineAcquisition.besideOffset * share)
            })
            return parts > 0 ? moved.smoothed() : moved
        }
        let path = line.after == nil ? laid : beside(laid, to: points[parts])
        let along = points.map { path.nearest($0) }
        guard along.allSatisfy({ $0.away <= RealLineAcquisition.stationReach }), zip(along, along.dropFirst()).allSatisfy({ $0.along < $1.along }) else {
            return refused("The real line's stations are not along its track here.", "真實車站不在這段鐵路上。")
        }

        // The ground under the way, read in on a copy, and under the depot's.
        var draft = world.pricingCopy()
        let step = 32 * RealLineAcquisition.metre, side = 16 * RealLineAcquisition.metre
        let depotWays = depotSites.map { WorldPath(worldPoints($0)) }
        let samples = ([path] + depotWays).flatMap { way in
            (0...Int(way.length / step)).flatMap { index -> [PlanPoint] in
                let point = way.point(at: Double(index) * step)
                return [(-side, -side), (-side, side), (side, -side), (side, side)].map { dx, dy in WorldVector(x: point.x + dx, y: point.y + dy).plan }
            }
        }
        // Decision 401: on a map bought tile by tile, the tiles under the
        // way not owned yet are bought with the line, their land and water
        // read in before the track is laid over them.
        var tiles: [MapTile] = []
        if let expansion = world.mapExpansion {
            let wanted = Set(samples.map { MapExpansion.tile(at: $0) }).filter { world.isOnMap($0) && !expansion.owns($0) }
            guard let order = RealLineAcquisition.buyingOrder(of: wanted, owned: expansion.owned) else { return refusedForLand() }
            tiles = order
            for tile in tiles {
                try? draft.buyMapTile(tile, passingMilestone: true)
            }
            if !tiles.isEmpty {
                GameSession.readLand(roundStationsOf: &draft, population: population, places: places, water: self.water, coverage: coverage)
            }
        }
        try? draft.readGround(under: samples, from: heights)
        let mapped = draft.ground.isMapped
        let planning = draft
        func ground(_ point: WorldVector) -> Double {
            Double(planning.groundHeight(at: point.plan) ?? 0)
        }
        func water(_ point: WorldVector) -> Bool {
            guard mapped else { return false }
            let plan = point.plan
            return planning.terrain.isWater(row: Int(plan.y / Land.cellLength), column: Int(plan.x / Land.cellLength))
        }

        // Each station level, its loops' stretch with it. On a double track
        // a station between the ends has the second track's platform too,
        // and a loop only on the other side.
        let cars = line.cars
        let half = Double(Int64(cars + 1) * Train.carLength) / 2
        let platformLength = Int64(cars + 1) * Train.carLength
        let double = line.isDoubleTrack
        let layout = !line.isUrban ? RealLineLayout.branch : cars > RealLineLayout.lightRailCars ? .metro : .lightRail
        var forced = [0, path.length]
        var levels: [TrackRise.Level] = []
        var zones: [ClosedRange<Double>] = []
        var spans: [ClosedRange<Double>] = []
        var loopSpans: [(stop: Int, a: Double, b: Double, offset: Double, ramp: Double)] = []
        // The stations: the company's own by the junction, if it has one;
        // and, decision 400, any other by its real name within 450 m (a
        // transfer to the company's line, or the line bought before): the
        // line's platforms join it.
        // Review BUGHUNT_BUILD P3-3: never a depot, which no line calls at.
        let junctionStation = world.stations
            .filter { !$0.isDepot && (WorldVector($0.location) - points[0]).length <= RealLineAcquisition.junctionReach }
            .min { (WorldVector($0.location) - points[0]).length < (WorldVector($1.location) - points[0]).length }
        func sameName(_ index: Int) -> StationID? {
            let real = railways.stations.first { $0.id == "\(line.system)|\(runs.stops[index])" }
            let names = Set([runs.stops[index], real?.name(in: language)].compactMap { $0 })
            return world.stations
                .filter { !$0.isDepot && names.contains($0.name) && (WorldVector($0.location) - points[index]).length <= RealLineAcquisition.junctionReach }
                .min { (WorldVector($0.location) - points[index]).length < (WorldVector($1.location) - points[index]).length }?.id
        }
        let carried = railways.structures?.stretches(along: path, frame: frame, system: line.system) ?? []
        for (index, name) in runs.stops.enumerated() {
            let at = along[index].along
            let zone = (at - half)...(at + half)
            zones.append(zone)
            let between = double && index > 0 && index < runs.stops.count - 1
            let loops = (runs.tracks[name] ?? 1) - (between ? 2 : 1)
            // A positive offset is on the right going up the line; on a
            // double track the second track is on the left, so a loop
            // between the ends is on the right. An end station's loops lie
            // either side, the deeper ones (decision 400) further out.
            let offset = layout.loopOffset
            let sides = between
                ? [(offset, 1)]
                : (1...layout.endLevels).flatMap { level in [(Double(level) * offset, level), (-Double(level) * offset, level)] }
            guard loops <= sides.count else {
                return refused("A station of the line has no room for its tracks here.", "這條線有一站放不下它要的股道。")
            }
            let span: ClosedRange<Double>
            if loops > 0 {
                let deepest = sides.prefix(loops).map(\.1).max() ?? 1
                span = (at - layout.reach(level: deepest))...(at + layout.reach(level: deepest))
                for (side, level) in sides.prefix(loops) {
                    let reach = layout.reach(level: level)
                    loopSpans.append((index, at - reach, at + reach, side, layout.ramp(level: level)))
                    forced += [at - reach, at + reach]
                }
            } else {
                span = (zone.lowerBound - RealWorldDemo.platformMargin)...(zone.upperBound + RealWorldDemo.platformMargin)
            }
            spans.append(span)
            forced += [span.lowerBound, span.upperBound]
            let height = ground(path.point(at: at))
            // Decision 462: a station on its line's real viaduct stands up
            // on it, clear over a station on the ground beside it (the
            // Liujia Line's platforms at Zhuzhong over the Neiwan Line's).
            let shared = (index == 0 ? junctionStation?.id : sameName(index)) != nil
            let raised = switch raising {
            case .none: false
            case .viaducts, .viaductsAndShared:
                (raising == .viaductsAndShared && shared) || RealLineAcquisition.isRaised(
                    at: at, before: index > 0 ? along[index - 1].along : nil, after: index < along.count - 1 ? along[index + 1].along : nil, carried: carried
                )
            }
            let low = raised ? height + RealLineAcquisition.raisedStation : height - RealWorldDemo.stationReach
            levels.append(TrackRise.Level(span, from: low, to: low + 2 * RealWorldDemo.stationReach))
        }
        // A double track's second track, for the trains toward the
        // terminal, on their left (Taiwan's trains keep left, and the
        // game's choose that track by keeping left, decision 202): beside the
        // first from past the junction's station to short of the
        // terminal's, as the high-speed demo's up track (decision 281); the
        // trains toward the junction keep to the first. Each end station is
        // on the first alone, with its loops.
        let ramp = HighSpeedDemo.rampLength, gap = RealWorldDemo.shortestEdge
        var second: (a: Double, b: Double)?
        if double, let first = spans.first, let last = spans.last {
            let a = first.upperBound + gap, b = last.lowerBound - gap
            guard b - a > 2 * ramp + gap else {
                return refused("The line is too short for its second track here.", "這條線太短，放不下第二條正線。")
            }
            forced += [a, a + ramp, b - ramp, b]
            second = (a, b)
        }
        // Decision 479: the depot's wye and crossovers, on the second
        // track's side of the line, clear of the stations and the second
        // track's ramps.
        var depotAt: Double?
        if depot, depotSite?.beyond == nil, let points = depotPoints, let second {
            let j = path.nearest(points[0]).along
            let marks = RealLineDepotLayout.marks(at: j)
            let reach = marks[0]...marks[marks.count - 1]
            let side = (points[1] - path.point(at: j)).dot(path.tangent(at: j).normal)
            if side < 0, reach.lowerBound > second.a + ramp + gap, reach.upperBound < second.b - ramp - gap,
               !spans.contains(where: { $0.overlaps(reach) }) {
                forced += marks
                depotAt = j
            }
        }
        guard let rise = TrackRise(path: path, ground: ground, water: water, levels: levels, carried: carried) else {
            return refused(
                "The track cannot climb along this line within the steepest grade.",
                "沿這條線的高低差超過遊戲的坡度上限，鋪不上去。"
            )
        }
        // Not cut close over the second track's ramps: an edge of the
        // first cut short in one would meet the second's whole ramp at the
        // joint with tangents of different lengths, and a train keeping
        // left (decision 202) would tell the two ways apart by their
        // rounding, not by the side they lead to (Danhai's Blue Coast Line
        // sent its trains back on the wrong track).
        let main = RealWorldDemo.TrackPlan(
            path, forced: forced, avoiding: zones, close: loopSpans.map { $0.a...$0.b }, rise: rise, structure: .automatic
        )
        var plans: [(plan: RealWorldDemo.TrackPlan, start: RealLineAcquisition.NodeAt?, end: RealLineAcquisition.NodeAt?, together: Bool)] = [
            (main, nil, nil, false),
        ]
        var platformsAt: [(stop: Int, piece: Int, zone: ClosedRange<Double>)] = zones.enumerated().map { ($0.offset, 0, $0.element) }
        var besideNodes: [Int] = []
        if let second {
            let node = { (distance: Double) in main.distances.firstIndex { abs($0 - distance) < 1 } }
            guard let a = node(second.a), let inner = node(second.a + ramp), let outer = node(second.b - ramp), let b = node(second.b),
                  a < inner, inner <= outer, outer < b
            else {
                return refused("The line is too short for its second track here.", "這條線太短，放不下第二條正線。")
            }
            let beside = [a] + Array(inner...outer) + [b]
            besideNodes = beside
            plans.append((
                RealWorldDemo.TrackPlan(beside: main, at: beside, offsets: beside.map { $0 == a || $0 == b ? 0 : -HighSpeedDemo.trackOffset }),
                RealLineAcquisition.NodeAt(piece: 0, node: a), RealLineAcquisition.NodeAt(piece: 0, node: b), true
            ))
            platformsAt += zones.indices.dropFirst().dropLast().map { ($0, plans.count - 1, zones[$0]) }
        }
        for loop in loopSpans {
            for offset in [loop.offset] {
                let loopPath = path.offset(from: loop.a, to: loop.b, by: offset, ramp: loop.ramp)
                guard let loopRise = TrackRise(
                    path: loopPath, ground: ground, water: water, levels: [TrackRise.Level(0...loopPath.length, at: Double(rise.node(at: loop.a)))]
                ), let startNode = main.node(at: loop.a), let endNode = main.node(at: loop.b),
                    let a = main.distances.firstIndex(where: { abs($0 - loop.a) < 1 }), let b = main.distances.firstIndex(where: { abs($0 - loop.b) < 1 })
                else {
                    return refused("A passing loop does not fit here.", "這裡放不下待避線。")
                }
                // The middle of the loop, flat for a platform as long as
                // the line's: a metro's trains are longer than the demo's.
                let middle = loopPath.length / 2, loopHalf = max(half, Double(RealWorldDemo.platformLength) / 2)
                let zone = (middle - loopHalf)...(middle + loopHalf)
                plans.append((
                    RealWorldDemo.TrackPlan(
                        loopPath, forced: [0, loopPath.length], avoiding: [zone], close: [0...loopPath.length],
                        start: startNode, end: endNode, rise: loopRise, structure: .automatic
                    ),
                    RealLineAcquisition.NodeAt(piece: 0, node: a), RealLineAcquisition.NodeAt(piece: 0, node: b), true
                ))
                platformsAt.append((loop.stop, plans.count - 1, zone))
            }
        }
        // Decision 479: the crossovers either side of the depot's wye, the
        // first before it to the first track, the second after it from
        // the first track, as the second track's ramps are laid.
        let mainNode = { (distance: Double) in main.distances.firstIndex { abs($0 - distance) < 1 } }
        var depotMarks: [(main: Int, second: Int)] = []
        if let j = depotAt {
            depotMarks = RealLineDepotLayout.marks(at: j).compactMap { mark in
                mainNode(mark).flatMap { node in besideNodes.firstIndex(of: node).map { (node, $0) } }
            }
            if depotMarks.count == 6 {
                let offset = -HighSpeedDemo.trackOffset
                plans.append((
                    RealWorldDemo.TrackPlan(beside: main, at: [depotMarks[0].main, depotMarks[1].main], offsets: [0, offset]),
                    RealLineAcquisition.NodeAt(piece: 0, node: depotMarks[0].main), RealLineAcquisition.NodeAt(piece: 1, node: depotMarks[1].second), true
                ))
                plans.append((
                    RealWorldDemo.TrackPlan(beside: main, at: [depotMarks[4].main, depotMarks[5].main], offsets: [offset, 0]),
                    RealLineAcquisition.NodeAt(piece: 1, node: depotMarks[4].second), RealLineAcquisition.NodeAt(piece: 0, node: depotMarks[5].main), true
                ))
            }
        }
        var pieces = plans.map { entry in
            let plan = entry.plan
            let nodes = plan.nodes.indices.map { WorldCoordinate(x: plan.nodes[$0].point.x, y: plan.nodes[$0].point.y, z: plan.heights[$0]) }
            let ground = plan.curves.indices.flatMap { index -> [PlanPoint] in
                let surveyed = TrackGeometry(from: nodes[index], to: nodes[index + 1], curve: plan.curves[index]).map(NetworkBuilding.surveyedPoints(of:)) ?? []
                return [nodes[index].plan, nodes[index + 1].plan] + surveyed
            }
            return RealLineAcquisition.Piece(
                nodes: nodes, start: entry.start, end: entry.end, curves: plan.curves, distances: plan.distances, structure: plan.structure,
                together: entry.together, ground: ground
            )
        }
        var depotsLaid: [(stop: Int?, depot: RealLineAcquisition.Depot)] = []
        if let site = depotSite, let points = depotPoints, let j = depotAt, let laid = RealLineDepotLayout.lay(
            site, points: points, along: path, at: j, second: plans[1].plan, marks: depotMarks, first: pieces.count, length: platformLength,
            ground: ground, in: language
        ) {
            pieces += laid.pieces
            depotsLaid.append((nil, laid.depot))
        }
        // Decision 489: a depot past an end, its lead on from the main
        // track's end there; decision 535, one past each end.
        for (end, site, _) in depotEnds where end == 0 || end == runs.stops.count - 1 {
            let last = end == 0 ? 0 : main.nodes.count - 1
            let way = end == 0 ? path.tangent(at: 0).reversed : path.tangent(at: path.length)
            guard let laid = RealLineDepotLayout.lay(
                site, beyond: (RealLineAcquisition.NodeAt(piece: 0, node: last), WorldVector(main.nodes[last].point), main.heights[last], way),
                first: pieces.count, length: platformLength, ground: ground, in: language
            ) else {
                return refused("The line's depot does not fit here.", "這條線的機廠放不下。")
            }
            pieces += laid.pieces
            depotsLaid.append((end, laid.depot))
        }

        let stops = runs.stops.enumerated().map { index, name in
            let at = path.point(at: along[index].along).plan
            let real = railways.stations.first { $0.id == "\(line.system)|\(name)" }
            return RealLineAcquisition.Stop(
                name: real?.name(in: language) ?? name, at: at, existing: index == 0 ? junctionStation?.id : sameName(index), demand: newStationDemand(at: at)
            )
        }
        let platforms = platformsAt.map {
            RealLineAcquisition.Platform(stop: $0.stop, at: RealLineAcquisition.PieceAt(piece: $0.piece, distance: $0.zone.lowerBound), length: platformLength)
        }

        // The trains where the real ones stand at midnight, one to a track,
        // each facing up the line but at the terminal. Decision 400: a light
        // rail's train an end has no track for stands at a station between,
        // on the track toward the end nearer it, facing it.
        // Decision 479: those the real timetable leaves at a station
        // between the ends stand in the depot, while it has room; decision
        // 489, those it leaves at the end the depot stands past.
        var starts: [RealLineAcquisition.Start] = []
        var depotRooms = depotsLaid.map(\.depot.platforms)
        let lastStop = runs.stops.count - 1
        for (name, overnight) in runs.overnight.sorted(by: { $0.key < $1.key }) {
            guard let stop = runs.stops.firstIndex(of: name) else { continue }
            var count = overnight
            // The depot past this end, or, on a line with none past an
            // end, the one beside the line for a station between.
            let room = depotEnds.isEmpty
                ? (stop > 0 && stop < lastStop ? depotsLaid.firstIndex { $0.stop == nil } : nil)
                : depotsLaid.firstIndex { $0.stop == stop }
            if let room {
                while count > 0, !depotRooms[room].isEmpty {
                    starts.append(RealLineAcquisition.Start(name: "", at: depotRooms[room].removeFirst(), forward: true))
                    count -= 1
                }
                if count == 0 { continue }
            }
            var tracks = platformsAt.filter { $0.stop == stop }
            var forward = stop < lastStop
            if double, stop > 0, stop < lastStop {
                forward = 2 * stop > lastStop
                tracks = forward ? tracks.filter { $0.piece != 0 } + tracks.filter { $0.piece == 0 } : tracks
            }
            guard count <= tracks.count else {
                return refused("The line's trains have no room to stand overnight.", "這條線的列車晚上沒有地方停。")
            }
            for track in tracks.prefix(count) {
                starts.append(RealLineAcquisition.Start(
                    name: "", at: RealLineAcquisition.PieceAt(piece: track.piece, distance: track.zone.lowerBound), forward: forward
                ))
            }
        }
        let lineName = line.name(in: language)
        starts = starts.enumerated().map { number, start in
            RealLineAcquisition.Start(name: RealWorldDemo.trainName(line: lineName, number: number + 1, in: language), at: start.at, forward: start.forward)
        }
        // Decision 479: with the depot, its own empty runs take the
        // trains in and out, not the real timetable's positioning runs.
        // Decision 489: a depot past an end takes in and sends out only
        // that end's; the runs taking the other end's trains back there
        // for the night stay.
        let lineRuns = runs.runs.filter { depotsLaid.isEmpty || !depotEnds.isEmpty || !($0.positioning || $0.train == "回送") }.map { run in
            LineRun(
                from: runs.stops.firstIndex(of: run.calls[0].station) ?? 0,
                to: runs.stops.firstIndex(of: run.calls[run.calls.count - 1].station) ?? 0,
                times: run.calls.map { LineRunTime(arrival: $0.arrival, departure: $0.departure) },
                days: run.days.reduce(0) { $0 | 1 << $1 }
            )
        }
        let riders = (line.paysForFirstStop ? runs.stops[...] : runs.stops.dropFirst()).reduce(Int64(0)) { total, name in
            guard let real = railways.stations.first(where: { $0.id == "\(line.system)|\(name)" }) else { return total }
            return total + Int64(railways.ridership?.riders(of: real, data: railways.stationData) ?? 0)
        }
        let color = railways.lines.first { line.isUrban ? $0.lineKey == "\(line.system)|\(line.network)" : $0.system.id == RealBranchLine.tra && $0.name.hasPrefix(line.chinese) }
            .flatMap { LineColor(rgb: Int($0.palette.color.red) << 16 | Int($0.palette.color.green) << 8 | Int($0.palette.color.blue)) }
        func acquisition(buying tiles: [MapTile]) -> RealLineAcquisition {
            RealLineAcquisition(
                realLine: line.id, pieces: pieces, stops: stops, platforms: platforms, lineName: lineName, color: color, runs: lineRuns,
                trains: starts, cars: cars, trainType: line.trainType, dailyRiders: min(riders, LineAcquisition.maximumDailyRiders),
                tiles: tiles.isEmpty ? nil : tiles, tier: line.tier == .branch ? nil : line.tier, depot: depotsLaid.first?.depot,
                moreDepots: depotsLaid.count > 1 ? depotsLaid.dropFirst().map(\.depot) : nil
            )
        }

        // GameCore's answer and the price, on a funded copy. A tile the
        // track reaches between the samples is bought with the others.
        while true {
            let bought = acquisition(buying: tiles)
            var probe = world.pricingCopy()
            do throws(GameError) {
                let price = try build(bought, in: &probe)
                return (RealLineOffer(line: line, acquisition: bought, price: price, problem: nil), false, nil)
            } catch {
                if case .mapTileNotOwned(let tile) = error, let owned = world.mapExpansion?.owned, !tiles.contains(tile) {
                    guard let order = RealLineAcquisition.buyingOrder(of: Set(tiles + [tile]), owned: owned) else { return refusedForLand() }
                    tiles = order
                    continue
                }
                let crosses = if case .trackConflict = error { true } else { false }
                return (RealLineOffer(line: line, acquisition: nil, price: nil, problem: error.playerMessage(in: language)), crosses, bought)
            }
        }
    }

    // MARK: - Building it

    /// Builds `acquisition` in `world` and records it (decision 315 §5):
    /// all of it or, throwing, none, the caller's copy dropped. What each
    /// part cost. Not `recording`, the same line built by the company
    /// itself, its runs from now on (what `AcquisitionReportTests`
    /// compares a purchase with).
    @discardableResult
    /// Where the trains of a line bought stop at a station of more than one
    /// track, by the line's stops (the terminal first, the junction last):
    /// coming from the terminal's side on the main track, from the
    /// junction's on the loop, and into either end on the main track.
    /// Under simple rules (decision 258) a train may take another track of
    /// a station only where no train is planned the other way along it
    /// (decision 57). At an end every track a train is planned along is run
    /// both ways (decision 278), and a line's plan sets off from every
    /// track of its first stop, so a train coming in to the junction, where
    /// the real trains stand two and three at night, to a train standing
    /// on the track its route names waited for it all day. With the
    /// junction last and each way's track named, its other tracks are
    /// planned by nobody and are free to take; the terminals have one.
    static func routePreferences(_ platformsOf: [Int: [TrackPlatform]], stops: Int) -> [LineRoutePreference] {
        var routes: [LineRoutePreference] = []
        for (stop, platforms) in platformsOf.sorted(by: { $0.key < $1.key }) where platforms.count > 1 {
            if stop > 0 { routes.append(LineRoutePreference(from: stop - 1, to: stop, platform: platforms[0])) }
            if stop < stops - 1 { routes.append(LineRoutePreference(from: stop + 1, to: stop, platform: platforms[stop == 0 ? 0 : 1])) }
        }
        return routes
    }

    func build(_ acquisition: RealLineAcquisition, in world: inout GameWorld, recording: Bool = true) throws(GameError) -> RealLineAcquisitionPrice {
        // One edit for the passengers (decision 275): every track, platform,
        // line and train step below otherwise looked again at every group
        // waiting on the map (``GameWorld/abandonUnservedPassengers()``,
        // each line's journey worked out afresh), some hundred times for
        // one line; on the player's real map of 64 stations and 15 lines
        // (96.1) that was 24 s to buy the Danhai light rail and as long
        // again to lay its offer, all on the main actor. Nothing in a
        // purchase takes a service away, so the groups the finished
        // purchase leaves are those the steps one at a time left
        // (`PassengerCheckOnceTests`).
        try world.editTrackAsOne { (world: inout GameWorld) throws(GameError) in
            try buildStepByStep(acquisition, in: &world, recording: recording)
        }
    }

    /// ``build(_:in:recording:)``'s steps, each its own command for the
    /// passengers, as purchases were built before 0.5.0 (96.1)'s report:
    /// what the tests compare the one edit with.
    func buildStepByStep(_ acquisition: RealLineAcquisition, in world: inout GameWorld, recording: Bool = true) throws(GameError) -> RealLineAcquisitionPrice {
        let opening = world.economy.balance
        // Decision 401: the tiles under it first, their land and water read
        // in before the track is laid over them.
        if let tiles = acquisition.tiles {
            for tile in tiles {
                try world.buyMapTile(tile, passingMilestone: true)
            }
            GameSession.readLand(roundStationsOf: &world, population: population, places: places, water: water, coverage: coverage)
        }
        let landed = world.economy.balance
        // Decision 528: what the same line left when it was removed.
        try acquisition.clearing?.apply(to: &world)
        let standing = Set(world.network.edges.map(\.id))
        var nodes: [[TrackNodeID]] = []
        var edges: [[TrackEdgeID]] = []
        for piece in acquisition.pieces {
            try world.readGround(under: piece.ground, from: heights)
            var ids: [TrackNodeID] = []
            for (index, position) in piece.nodes.enumerated() {
                if index == 0, let start = piece.start {
                    ids.append(nodes[start.piece][start.node])
                } else if index == piece.nodes.count - 1, let end = piece.end {
                    ids.append(nodes[end.piece][end.node])
                } else {
                    ids.append(try world.buildTrackNode(at: position))
                }
            }
            if piece.together {
                edges.append(try world.buildTrackEdges(piece.curves.enumerated().map { index, curve in
                    TrackEdgePlan(from: ids[index], to: ids[index + 1], curve: curve, structure: piece.structure)
                }))
            } else {
                var built: [TrackEdgeID] = []
                for (index, curve) in piece.curves.enumerated() {
                    built.append(try world.buildTrackEdge(from: ids[index], to: ids[index + 1], curve: curve, structure: piece.structure))
                }
                edges.append(built)
            }
            nodes.append(ids)
        }
        /// The edge `at` is on and how far along it.
        func edge(_ at: RealLineAcquisition.PieceAt) throws(GameError) -> (TrackEdgeID, Int64) {
            guard acquisition.pieces.indices.contains(at.piece) else { throw .invalidTrackGeometry }
            let distances = acquisition.pieces[at.piece].distances, built = edges[at.piece]
            guard !built.isEmpty, distances.count == built.count + 1 else { throw .invalidTrackGeometry }
            let index = max(0, min(built.count - 1, distances.lastIndex { $0 <= at.distance } ?? 0))
            let a = distances[index], b = distances[index + 1]
            let length = Double(world.network.edge(built[index])?.length ?? 0)
            return (built[index], Int64(((at.distance - a) / max(b - a, 1) * length).rounded()))
        }
        // Where a platform (and a train standing at it) `length` long from
        // `at` starts: moved back to end a metre short of its edge's end
        // when it would run past it, as the edge on the inside of a curve
        // can be a little shorter than the plan's stretch it was fitted to.
        func berth(_ at: RealLineAcquisition.PieceAt, length: Int64) throws(GameError) -> (TrackEdgeID, Int64) {
            let (on, offset) = try edge(at)
            let edgeLength = world.network.edge(on)?.length ?? 0
            guard offset + length > edgeLength else { return (on, offset) }
            return (on, max(0, edgeLength - length - Int64(RealLineAcquisition.metre)))
        }

        var stations: [StationID] = []
        for stop in acquisition.stops {
            if let existing = stop.existing {
                guard world.station(id: existing) != nil else { throw .unknownStation(existing) }
                stations.append(existing)
            } else {
                let station = try world.buildStation(named: stop.name, at: stop.at)
                if world.accounts.mode == .management, !world.landDemand {
                    try world.setStationDemand(station.id, to: stop.demand)
                }
                stations.append(station.id)
            }
        }
        // Each stop's platforms, the main track's first.
        var platformsOf: [Int: [TrackPlatform]] = [:]
        for platform in acquisition.platforms {
            guard stations.indices.contains(platform.stop) else { throw .invalidTrackGeometry }
            let (on, offset) = try berth(platform.at, length: platform.length)
            try world.addTrackPlatform(stations[platform.stop], on: on, from: offset, to: offset + platform.length)
            platformsOf[stations.count - 1 - platform.stop, default: []].append(TrackPlatform(station: stations[platform.stop], edge: on, start: offset, end: offset + platform.length))
        }
        GameSession.readLand(roundStationsOf: &world, population: population, places: places, water: water, coverage: coverage)

        // The line runs from its terminal to its junction: see
        // ``routePreferences(_:stops:)``.
        let last = stations.count - 1
        let line = try world.createLine(named: acquisition.lineName, stops: stations.reversed())
        if let color = acquisition.color { try world.setLineColor(line.id, to: color) }
        try world.setLineServiceWindow(line.id, to: .allDay)
        try world.setLineRuns(line.id, to: acquisition.runs.map { run in
            LineRun(from: last - run.from, to: last - run.to, times: run.times, days: run.days)
        })
        try world.setLineRoutePreferences(line.id, to: Self.routePreferences(platformsOf, stops: stations.count))
        // Decision 479: the depot, a platform along each siding, the line's.
        // Decision 535: and its others, the Wenhu Line's two.
        var depots: [StationID] = []
        for depot in [acquisition.depot].compactMap(\.self) + (acquisition.moreDepots ?? []) {
            let station = try world.buildStation(named: depot.name, at: depot.at)
            for at in depot.platforms {
                let (on, offset) = try berth(at, length: depot.length)
                try world.addTrackPlatform(station.id, on: on, from: offset, to: offset + depot.length)
            }
            try world.setStationDepot(station.id, to: true)
            depots.append(station.id)
        }
        if !depots.isEmpty { try world.setLineDepots(line.id, to: depots) }
        // Review BUGHUNT_BUILD P3-4: after the depot, whose station and
        // platforms are building, not trains.
        let built = world.economy.balance
        let count = acquisition.trains.count
        try world.setLineTrainsInService(line.id, to: TrainsInService(peak: count, offPeak: count, low: count))
        let length = Int64(acquisition.cars + 1) * Train.carLength
        for start in acquisition.trains {
            let train: TrainID
            if let type = acquisition.trainType {
                train = try world.purchaseTrain(named: start.name, as: type).id
            } else {
                train = try world.purchaseTrain(named: start.name).id
            }
            try world.setTrainCars(train, to: acquisition.cars)
            let (on, at) = try berth(start.at, length: length)
            let edgeLength = world.network.edge(on)?.length ?? 0
            let offset = start.forward ? at + length : edgeLength - at
            try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: on, direction: start.forward ? .forward : .backward), offset: offset))
            try world.setTrainContinuation(train, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(train, to: 512)
            try world.assignTrain(train, to: line.id)
        }
        let bought = world.economy.balance
        if recording {
            // Decision 528: the track it laid, standing, left behind if
            // the line is removed.
            let laid = world.network.edges.map(\.id).filter { !standing.contains($0) }
            try world.recordLineAcquisition(
                line: line.id, realLine: acquisition.realLine, dailyRiders: acquisition.dailyRiders, tier: acquisition.tier ?? .branch,
                track: laid.isEmpty ? nil : laid
            )
        }
        return RealLineAcquisitionPrice(
            land: opening - landed, building: landed - built, trains: built - bought, riders: bought - world.economy.balance
        )
    }
}

/// What the "line bought" card says (decision 315 §8): the line, its
/// stations at each end, and what the company now runs.
public struct RealLineAcquired: Hashable, Sendable {
    public let line: LineID
    public let name: String
    public let color: LineColor?
    /// The junction's and the terminal's names.
    public let ends: (from: String, to: String)
    public let stations: Int
    /// Its length in metres, along the main track.
    public let metres: Int64
    public let trains: Int
    /// The real trains of a weekday (Wednesday) it runs.
    public let weekdayTrains: Int
    /// BUGHUNT_BUILD P3-2: whether it runs from that day's first train
    /// (bought before ``LineAcquisition/sameDayCutoff``), not the next day's.
    public var startsToday = false

    public static func == (a: RealLineAcquired, b: RealLineAcquired) -> Bool {
        a.line == b.line && a.name == b.name && a.color == b.color && a.ends == b.ends && a.stations == b.stations && a.metres == b.metres
            && a.trains == b.trains && a.weekdayTrains == b.weekdayTrains && a.startsToday == b.startsToday
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(line)
    }

    /// "7 stations, 13.0 km, 3 trains".
    public func sizeText(in language: DisplayLanguage) -> String {
        let km = String(format: "%.1f", Double(metres) / 1_000)
        return language.text(
            "\(stations) stations, \(km) km, \(trains) \(trains == 1 ? "train" : "trains")",
            "\(stations) 站、\(km) 公里、\(trains) 列車"
        )
    }

    public func handoverText(in language: DisplayLanguage) -> String {
        RealLineAcquired.handoverText(today: startsToday, in: language)
    }

    /// BUGHUNT_BUILD P3-2: from which day's first train a line bought at
    /// `time` is the company's (``LineAcquisition/firstServiceDay(at:)``):
    /// that day's before four in the morning, the next day's after.
    public static func startsToday(at time: GameTime) -> Bool {
        let day = time.seconds >= 0 ? time.seconds / GameTime.secondsPerDay : (time.seconds + 1) / GameTime.secondsPerDay - 1
        return LineAcquisition.firstServiceDay(at: time) == day
    }

    /// "Yours to run from today's (or tomorrow's) first train", without a
    /// full stop.
    public static func handoverText(today: Bool, in language: DisplayLanguage) -> String {
        today
            ? language.text("Yours to run from today's first train", "今天首班車起由你經營")
            : language.text("Yours to run from tomorrow's first train", "明天首班車起由你經營")
    }

    public func timetableText(in language: DisplayLanguage) -> String {
        language.text("Real timetable: \(weekdayTrains) trains a weekday", "真實班次：平日 \(weekdayTrains) 班")
    }
}

extension GameSession {
    /// Buys the line `offer` laid out (decision 315), as one command: its
    /// track, stations, trains and real timetable. The card it opens
    /// (``lastLineAcquired``) says what was bought; a refusal says why.
    @discardableResult
    public func acquireRealLine(_ offer: RealLineOffer) -> Bool {
        guard let acquisition = offer.acquisition else {
            message = StatusMessage(kind: .failure, text: offer.problem ?? "")
            return false
        }
        let name = acquisition.lineName
        let today = RealLineAcquired.startsToday(at: world.clock.now)
        let handover = RealLineAcquired.handoverText(today: today, in: language)
        let made = perform(.acquireRealLine(acquisition)) { _, _, _ in
            language.text(
                "Bought \(name): its track, \(acquisition.stops.count) stations, \(acquisition.trains.count) trains and its real timetable. \(handover).",
                "已收購\(name)：軌道、\(acquisition.stops.count) 座車站、\(acquisition.trains.count) 列車與真實班次。\(handover)。"
            )
        }
        guard let line = made?.line else { return false }
        let main = acquisition.pieces.first
        let metres = main.map { piece in
            Int64(((piece.distances.last ?? 0) - 2 * RealLineAcquisition.runOn) / RealLineAcquisition.metre)
        } ?? 0
        // Wednesday: 1 << 3.
        let weekday = acquisition.runs.count { $0.days & (1 << 3) != 0 }
        lastLineAcquired = RealLineAcquired(
            line: line.id, name: name, color: acquisition.color,
            ends: (acquisition.stops.first?.name ?? "", acquisition.stops.last?.name ?? ""),
            stations: acquisition.stops.count, metres: max(0, metres), trains: acquisition.trains.count, weekdayTrains: weekday,
            startsToday: today
        )
        shownRealLineOffer = nil
        selectLine(line.id)
        playSound?(.lineAcquired)
        return true
    }
}

/// What ``GameSession/buyableRealLines`` is worked out from (decision 328).
struct BuyableRealLinesKey: Equatable {
    let bounds: WorldBounds
    let anchor: GeoAnchor?
    let bought: [LineAcquisition]
    /// ``GameSession/railwaysRevision``.
    let railways: Int
}

/// The real lines of a map (decision 336): on sale, held only in part,
/// and whether the company has bought one.
struct RealLineSale {
    var lines: [RealBranchLine]
    var partlyOnTheMap: [RealBranchLine]
    var bought: Bool
}
