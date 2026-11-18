import GameCore

// Decision 862 (the owner, 2026-11-18): the real lines for sale that share
// a station are sold together, in one purchase. Bought one at a time, the
// one bought later was laid round whatever the first had left at the
// station they share, in whichever order the player happened to buy them:
// platforms on two levels (decisions 809, 848, 863), runs not sent and
// trains locked at the shared platforms (the checkup's worlds of decision
// 844). Sold together, a map's lines that meet are always laid in one
// order, the one the nightly checkup plays.
//
// Which lines go together is worked out from the lines' own stops, not
// from a list: two lines of one railway system with a stop of the same
// name, or joined by a third (``RealLineBundle/groups(of:)``, the rule
// `TimetableCheckupAllBoughtTests` grouped its worlds by). On the maps the
// game has: the two Danhai light rails, the Liujia and Neiwan lines,
// Hong Kong's three lines to the airport, Rovaniemi's two and Fukuoka's
// three. They are laid in the order the game lists them
// (``RealBranchLine/urbanLines``, ``RealBranchLine/overseasLines``), each
// on the world with those before it bought, exactly as buying them one
// after another in that order laid them.
//
// A save that already holds one line of a group is sold the rest of it
// together; nothing it has is changed.
//
// Neither reference sells lines (decision 315's reference table): native.

/// The real lines for sale that are bought together (decision 862): one
/// line that shares no station with another, or every line of a group that
/// does, in the order they are laid.
public struct RealLineBundle: Hashable, Sendable {
    /// Its lines, in the order they are laid; never empty.
    public let lines: [RealBranchLine]

    public init(_ lines: [RealBranchLine]) {
        precondition(!lines.isEmpty, "A bundle of real lines has a line.")
        self.lines = lines
    }

    /// Its lines' ids, joined: `hkmtr:AEL+hkmtr:TCL+hkmtr:DRL`.
    public var id: String { lines.map(\.id).joined(separator: "+") }

    /// The line laid first, which names the bundle.
    public var first: RealBranchLine { lines[0] }

    /// Whether it is one line, sold as before decision 862.
    public var isSingle: Bool { lines.count == 1 }

    /// The line's name, or "Airport Express and 2 more".
    public func title(in language: DisplayLanguage) -> String {
        let name = first.name(in: language)
        guard !isSingle else { return name }
        return language.text("\(name) and \(lines.count - 1) more", "\(name)等 \(lines.count) 條路線")
    }

    /// Its lines' names in a row.
    public func names(in language: DisplayLanguage) -> String {
        lines.map { $0.name(in: language) }.joined(separator: language.text(", ", "、"))
    }

    /// What the list and the card say of lines sold together; `nil` for
    /// one line.
    public func togetherText(in language: DisplayLanguage) -> String? {
        guard !isSingle else { return nil }
        return language.text(
            "These lines share stations and are bought together: \(names(in: language)).",
            "這幾條線共用車站，一起收購：\(names(in: language))。"
        )
    }

    /// Which of `lines` go together: the index of each line's group, the
    /// groups numbered as their first line comes. Two lines are in one
    /// group when they are of the same railway system and a stop of one
    /// has the name of a stop of the other, or a third line joins them.
    static func groups(of lines: [(system: String, stops: [String])]) -> [Int] {
        var parent = Array(lines.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { index = parent[index] }
            return index
        }
        for a in lines.indices {
            let stops = Set(lines[a].stops)
            for b in lines.indices.dropFirst(a + 1) where lines[a].system == lines[b].system && !stops.isDisjoint(with: lines[b].stops) {
                // The earlier line stays the group's root.
                let (low, high) = (min(root(a), root(b)), max(root(a), root(b)))
                parent[high] = low
            }
        }
        return lines.indices.map(root)
    }
}

/// The offer of a bundle (decision 862): each of its lines laid out and
/// priced on the world with those before it bought, or why the bundle
/// cannot be bought here.
public struct RealLineBundleOffer: Sendable {
    public let bundle: RealLineBundle
    /// Its lines' offers in the order they are laid, each line as it is
    /// sold once those before it are bought (a line sharing its first
    /// stations with one of them, from where they part: decision 400).
    /// Where a line cannot be bought, its offer is the last and holds the
    /// reason.
    public let offers: [RealLineOffer]

    /// Every line's purchase, in the order they are built; `nil` where one
    /// cannot be bought.
    public var acquisitions: [RealLineAcquisition]? {
        let laid = offers.compactMap(\.acquisition)
        return laid.count == bundle.lines.count ? laid : nil
    }

    /// What the whole bundle costs; `nil` where a line cannot be bought.
    public var price: RealLineAcquisitionPrice? {
        let prices = offers.compactMap(\.price)
        guard prices.count == bundle.lines.count else { return nil }
        return RealLineAcquisitionPrice(
            land: prices.reduce(.zero) { $0 + $1.land }, building: prices.reduce(.zero) { $0 + $1.building },
            trains: prices.reduce(.zero) { $0 + $1.trains }, riders: prices.reduce(.zero) { $0 + $1.riders }
        )
    }

    /// Why it cannot be bought: the reason of the line that cannot be.
    public var problem: String? { offers.last?.problem }

    /// ``problem`` as the card says it: of lines sold together, with the
    /// name of the line that cannot be bought.
    public func problemText(in language: DisplayLanguage) -> String? {
        guard let refused = offers.last, let problem = refused.problem else { return nil }
        guard !bundle.isSingle else { return problem }
        return refused.line.name(in: language) + language.text(": ", "：") + problem
    }

    /// The card's first section: each line, what its purchase brings and,
    /// where the bundle has more than one, its own price.
    public func lineRows(in language: DisplayLanguage) -> [(name: String, summary: String, price: Money?)] {
        offers.map { offer in
            (offer.line.name(in: language), offer.summaryText(in: language), bundle.isSingle ? nil : offer.price?.total)
        }
    }

    /// The card's price rows, the bundle's as a whole, and the total last
    /// (``RealLineOffer/priceRows(in:)``).
    public func priceRows(in language: DisplayLanguage) -> [(label: String, amount: Money)] {
        if bundle.isSingle, let offer = offers.first { return offer.priceRows(in: language) }
        guard let price, let acquisitions else { return [] }
        let tiles = acquisitions.reduce(0) { $0 + ($1.tiles?.count ?? 0) }
        let trains = acquisitions.reduce(0) { $0 + $1.trains.count }
        let land = tiles == 0 ? [] : [
            (label: language.text("\(tiles) \(tiles == 1 ? "tile" : "tiles") of land along them", "沿線的 \(tiles) 塊地"), amount: price.land),
        ]
        return land + [
            (language.text("Track, stations and platforms", "軌道、車站與月台"), price.building),
            (language.text("\(trains) trains", "\(trains) 列車"), price.trains),
            (language.text("Their regulars along the lines", "沿線的常客"), price.riders),
            (language.text("Total", "合計"), price.total),
        ]
    }

    /// What the card's foot says of lines sold together, above Buy: the
    /// price of them all, whose rows are further down the card than a
    /// phone on its side shows at once. `nil` for one line (its card is
    /// as it was), or where a line cannot be bought.
    public func totalText(in language: DisplayLanguage) -> String? {
        guard !bundle.isSingle, let total = price?.total else { return nil }
        return language.text("\(bundle.lines.count) lines, \(total.moneyText) in all", "\(bundle.lines.count) 條路線合計 \(total.moneyText)")
    }

    /// What the company still lacks to buy it with `balance`, or `nil`
    /// when it has enough (or there is nothing to buy).
    public func shortfallText(balance: Money, in language: DisplayLanguage) -> String? {
        guard let total = price?.total, balance < total else { return nil }
        let short = (total - balance).moneyText
        return language.text("\(short) short of the price.", "還差 \(short)。")
    }
}

extension RealBranchLine {
    /// The light rail or metro of ``urbanLines`` or ``overseasLines`` as
    /// it is sold in `world` (decision 400): from where it parts from the
    /// line it shares its first stations with when that is bought, the
    /// whole line otherwise; `nil` where the railways have no runs for it.
    static func onSale(
        _ rail: (system: String, network: String, english: String, chinese: String, shares: String?, tier: LineAcquisition.Tier, leavesALine: Bool),
        in world: GameWorld, railways: RealRailways
    ) -> RealBranchLine? {
        let id = "\(dataSystem(of: rail.system)):\(rail.network)"
        let after = rail.shares.flatMap { world.acquisition(of: $0) == nil ? nil : $0 }
        guard let runs = metroRuns(of: id, after: after, in: railways) else { return nil }
        return RealBranchLine(
            network: rail.network, english: rail.english, chinese: rail.chinese, stops: runs.stops, system: rail.system, after: after,
            tier: rail.tier, leavesALine: rail.leavesALine, ring: runs.ring
        )
    }

    /// This line as it is sold in `world`: itself, but a light rail or
    /// metro once more from the list (``onSale(_:in:railways:)``), so one
    /// sharing its first stations with a line `world` has bought since is
    /// sold from where they part.
    func sold(in world: GameWorld, railways: RealRailways) -> RealBranchLine {
        guard isUrban, let rail = (Self.urbanLines + Self.overseasLines).first(where: { $0.system == system && $0.network == network }) else {
            return self
        }
        return Self.onSale(rail, in: world, railways: railways) ?? self
    }
}

extension RealLineLaying {
    /// The same laying on `world`.
    func on(_ world: GameWorld) -> RealLineLaying {
        RealLineLaying(
            world: world, railways: railways, traces: traces, language: language, population: population, places: places, water: water,
            coverage: coverage, heights: heights
        )
    }

    /// Lays out and prices `bundle` (decision 862): its lines one after
    /// another, each on a copy of the world with those before it built,
    /// as buying them one at a time in that order laid them. The first
    /// laid is the first of the bundle the company's land reaches (on a
    /// map bought tile by tile; the others' land then touches it). A line
    /// that cannot be laid ends the offer with its reason.
    func offer(for bundle: RealLineBundle) -> RealLineBundleOffer {
        guard !bundle.isSingle, let railways else {
            return RealLineBundleOffer(bundle: bundle, offers: [offer(for: bundle.first)])
        }
        let landProblem = GameSession.landProblem(in: language)
        var built = world.pricingCopy()
        var left = bundle.lines
        var offers: [RealLineOffer] = []
        while !left.isEmpty {
            let laying = on(built)
            var next: (index: Int, offer: RealLineOffer)?
            var outOfReach: RealLineOffer?
            for (index, listed) in left.enumerated() {
                let offer = laying.offer(for: listed.sold(in: built, railways: railways))
                if offer.acquisition == nil, offer.problem == landProblem {
                    outOfReach = outOfReach ?? offer
                    continue
                }
                next = (index, offer)
                break
            }
            guard let next, let acquisition = next.offer.acquisition else {
                return RealLineBundleOffer(bundle: bundle, offers: offers + [next?.offer ?? outOfReach].compactMap { $0 })
            }
            offers.append(next.offer)
            left.remove(at: next.index)
            guard !left.isEmpty else { break }
            do throws(GameError) {
                _ = try build(acquisition, in: &built)
            } catch {
                // Its offer built it on the same world.
                let refused = RealLineOffer(line: next.offer.line, acquisition: nil, price: nil, problem: error.playerMessage(in: language))
                return RealLineBundleOffer(bundle: bundle, offers: offers.dropLast() + [refused])
            }
            // As a purchase of its own is followed by its stations' land
            // (decision 88) before the next line is laid out.
            GameSession.readLand(roundStationsOf: &built, population: population, places: places, water: water, coverage: coverage)
        }
        return RealLineBundleOffer(bundle: bundle, offers: offers)
    }
}

extension GameSession {
    // MARK: - Sold together

    /// The real lines for sale as they are sold (decision 862): each line
    /// with those it shares a station with, in the order the lines are
    /// listed (``buyableRealLines``).
    public var realLineBundles: [RealLineBundle] { realLineSale.bundles }

    /// The bundle `line` is sold in; `line` alone where it is not for sale.
    public func realLineBundle(of line: RealBranchLine) -> RealLineBundle {
        realLineBundles.first { $0.lines.contains { $0.id == line.id } } ?? RealLineBundle([line])
    }

    /// ``RealLineLaying/offer(for:)-(RealLineBundle)`` on the world as it
    /// is now, on the main actor.
    public func realLineBundleOffer(for bundle: RealLineBundle) -> RealLineBundleOffer {
        realLineLaying.offer(for: bundle)
    }

    /// Buys the bundle `offer` laid out (decision 862), as one command:
    /// every line's track, stations, trains and real timetable, or none of
    /// them. One line is bought as before (``acquireRealLine(_:)``). The
    /// card it opens (``lastLineAcquired``) says what was bought; a
    /// refusal says why.
    @discardableResult
    public func acquireRealLines(_ offer: RealLineBundleOffer) -> Bool {
        guard let acquisitions = offer.acquisitions, let first = offer.offers.first else {
            message = StatusMessage(kind: .failure, text: offer.problemText(in: language) ?? "")
            return false
        }
        guard acquisitions.count > 1 else { return acquireRealLine(first) }
        let names = acquisitions.map(\.lineName).joined(separator: language.text(", ", "、"))
        let stations = Set(acquisitions.flatMap { $0.stops.map(\.name) }).count
        let trains = acquisitions.reduce(0) { $0 + $1.trains.count }
        let today = RealLineAcquired.startsToday(at: world.clock.now)
        let handover = RealLineAcquired.handoverText(today: today, in: language)
        let made = perform(.acquireRealLines(acquisitions)) { _, _, _ in
            language.text(
                "Bought \(names): their track, \(stations) stations, \(trains) trains and their real timetables. \(handover).",
                "已收購\(names)：軌道、\(stations) 座車站、\(trains) 列車與真實班次。\(handover)。"
            )
        }
        guard let line = made?.line else { return false }
        var card = RealLineAcquired(acquisitions[0], line: line.id, today: today)
        card.with = acquisitions.dropFirst().compactMap { acquisition in
            world.acquisition(of: acquisition.realLine)?.line.map { RealLineAcquired(acquisition, line: $0, today: today) }
        }
        lastLineAcquired = card
        shownRealLineOffer = nil
        selectLine(line.id)
        playSound?(.lineAcquired)
        return true
    }
}
