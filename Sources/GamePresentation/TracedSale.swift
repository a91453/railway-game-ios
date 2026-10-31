import GameCore

// Decision 468, later (its next step 3): a trace along a real line the map
// sells (``GameSession/buyableRealLines``) says the line can be bought as it
// is, for how much, and offers its purchase card, the lines panel's
// (``GameSession/offerRealLine(_:)``). The trace stays as it is: the player
// lays it or buys the line.

/// A line for sale along its real way, in the world's plan: the real
/// lines' way from each of its stations to the next (some may be missing
/// where a station is not on a real line).
struct SaleLineWay: Sendable {
    /// One stretch of its way, with its box in plan.
    struct Piece: Sendable {
        let path: WorldPath
        let minX: Double, minY: Double, maxX: Double, maxY: Double

        init(_ path: WorldPath) {
            self.path = path
            let xs = path.points.map(\.x), ys = path.points.map(\.y)
            minX = xs.min() ?? 0
            maxX = xs.max() ?? 0
            minY = ys.min() ?? 0
            maxY = ys.max() ?? 0
        }

        /// Whether `point` lies within `reach` of it.
        func reaches(_ point: WorldVector, within reach: Double) -> Bool {
            guard point.x >= minX - reach, point.x <= maxX + reach, point.y >= minY - reach, point.y <= maxY + reach else { return false }
            return path.nearest(point).away <= reach
        }
    }

    let line: RealBranchLine
    let pieces: [Piece]
}

/// What the network tool says of a trace along a line for sale.
public struct TracedSaleHint: Hashable, Sendable {
    public let line: RealBranchLine
    /// Its whole price; `nil` while it is still being worked out.
    public let price: Money?
    /// That it can be bought, and for how much.
    public let text: String
    /// What the company lacks to buy it; `nil` when it has enough, or the
    /// price is not known yet.
    public let shortfall: String?

    /// The button that opens its purchase card.
    public static func buttonTitle(in language: DisplayLanguage) -> String {
        language.text("Buy Line", "收購路線")
    }
}

/// A line's offer laid out for ``TracedSaleHint``, and on which world.
struct TracedSaleQuote: Sendable {
    let offer: RealLineOffer
    /// ``GameSession/commandRevision`` and ``GameSession/railwaysRevision``
    /// as they were.
    let revision: Int
    let railways: Int
}

enum TracedSale {
    static let metre = Double(WorldCoordinate.unitsPerMetre)
    /// How near the line's way a point of the trace lies to run along it:
    /// a traced edge keeps within 3 m of the real line (decision 213), and
    /// the bundled lines of one route lie a few metres apart.
    static let reach = 15 * metre
    /// How far apart the trace is sampled.
    static let step = 20 * metre
    /// How much of the trace runs along the line, at least, for it to be
    /// that line: a trace along the main line past a branch's junction, or
    /// across it, runs along it for a few tens of metres.
    static let minimumLength = 200 * metre
    /// How far a station may stand from the real line it is on.
    static let stationReach = 100 * metre

    /// The line of `ways` the trace `way` runs along, if any: the one it
    /// follows the longest, for 200 m or half its length (a shorter trace)
    /// at least.
    static func line(along way: WorldPath, ways: [SaleLineWay]) -> RealBranchLine? {
        guard way.points.count > 1, !ways.isEmpty else { return nil }
        let count = max(1, Int((way.length / step).rounded(.up)))
        let samples = (0...count).map { way.point(at: way.length * Double($0) / Double(count)) }
        let spacing = way.length / Double(count)
        let needed = min(minimumLength, way.length / 2)
        var best: (line: RealBranchLine, length: Double)?
        for sale in ways {
            // Each stretch between two samples both along it.
            var along = 0.0
            var previous = false
            for sample in samples {
                let near = sale.pieces.contains { $0.reaches(sample, within: reach) }
                if near, previous { along += spacing }
                previous = near
            }
            if along >= needed, along > (best?.length ?? 0) { best = (sale.line, along) }
        }
        return best?.line
    }

    /// "You can buy the Neiwan Line as it is (its price, with its trains
    /// and real timetable)."; without the price while it is worked out.
    static func text(_ line: RealBranchLine, price: Money?, in language: DisplayLanguage) -> String {
        let name = line.name(in: language)
        guard let price else {
            return language.text(
                "You can buy the \(name) as it is, with its trains and real timetable.",
                "\(name)可以直接收購，含列車與真實班表。"
            )
        }
        return language.text(
            "You can buy the \(name) as it is (\(price.moneyText), with its trains and real timetable).",
            "\(name)可以直接收購（\(price.moneyText)，含列車與真實班表）。"
        )
    }

    /// The hint for `line`: with its price and what the company lacks from
    /// `quote`'s offer when there is one; `nil` where that offer says it
    /// cannot be bought here.
    static func hint(_ line: RealBranchLine, quote: RealLineOffer?, balance: Money, in language: DisplayLanguage) -> TracedSaleHint? {
        guard let quote else { return TracedSaleHint(line: line, price: nil, text: text(line, price: nil, in: language), shortfall: nil) }
        guard quote.problem == nil, let price = quote.price?.total else { return nil }
        return TracedSaleHint(
            line: line, price: price, text: text(line, price: price, in: language),
            shortfall: quote.shortfallText(balance: balance, in: language)
        )
    }
}

extension GameSession {
    /// The real way of each line for sale, worked out again only when the
    /// lines for sale may change (``buyableRealLines``).
    var saleLineWays: [SaleLineWay] {
        let key = BuyableRealLinesKey(bounds: world.bounds, anchor: world.geoAnchor, bought: world.acquisitions, railways: railwaysRevision)
        if let memo = saleLineWaysMemo, memo.key == key { return memo.ways }
        let lines = buyableRealLines
        var ways: [SaleLineWay] = []
        if let railways, let frame = RealWorldFrame(world: world), let traces = realRailwayTraces {
            for line in lines {
                let places = line.stops.map { name in
                    RealLineLaying.realPoint(of: name, system: line.system, railways: railways, frame: frame)
                        .flatMap { traces.snap($0, within: TracedSale.stationReach, system: line.system)?.place }
                }
                let pieces = zip(places, places.dropFirst()).compactMap { from, to -> SaleLineWay.Piece? in
                    guard let from, let to, let way = traces.path(from: from, to: to), way.count > 1 else { return nil }
                    return SaleLineWay.Piece(WorldPath(way))
                }
                ways.append(SaleLineWay(line: line, pieces: pieces))
            }
        }
        saleLineWaysMemo = (key, ways)
        return ways
    }

    /// The line for sale the trace from `start` to `end` runs along
    /// (``TracedSale/line(along:ways:)``); `nil` unless the tool traces,
    /// and in the tutorial or a lesson.
    func tracedSaleLine(from start: NetworkAnchor, to end: NetworkAnchor) -> RealBranchLine? {
        guard tracesRealRailway, tutorial == nil, lesson == nil, !buyableRealLines.isEmpty,
              let from = world.position(of: start, height: networkHeight), let to = world.position(of: end, height: networkHeight),
              let way = tracedWay(from: from, to: to, reach: Self.traceReach(NetworkBuilding.minimumSpacing * 2)) else { return nil }
        return TracedSale.line(along: WorldPath(way), ways: saleLineWays)
    }

    /// What the preview says of the line for sale the trace runs along:
    /// that it can be bought, its price and what the company lacks for it.
    /// The price is laid out off the main actor, as the purchase card's is
    /// (decision 497); until then the hint has none. `nil` where the trace
    /// runs along no line for sale, or the line cannot be bought here.
    public var tracedSaleHint: TracedSaleHint? {
        guard let line = networkPreview?.forSale else { return nil }
        if let quote = currentTracedSaleQuote(of: line) {
            return TracedSale.hint(line, quote: quote.offer, balance: world.economy.balance, in: language)
        }
        quoteTracedSale(line)
        return TracedSale.hint(line, quote: nil, balance: world.economy.balance, in: language)
    }

    /// The offer of `line` laid out on the world as it is now, if any.
    private func currentTracedSaleQuote(of line: RealBranchLine) -> TracedSaleQuote? {
        guard let quote = tracedSaleQuote, quote.offer.line == line, quote.revision == commandRevision,
              quote.railways == railwaysRevision else { return nil }
        return quote
    }

    /// Lays out `line`'s offer off the main actor for ``tracedSaleQuote``,
    /// unless that is already under way; again where the world changed
    /// meanwhile, once laid out.
    private func quoteTracedSale(_ line: RealBranchLine) {
        if let running = tracedSaleQuoteTask, running.line == line { return }
        tracedSaleQuoteTask?.task.cancel()
        let laying = realLineLaying, revision = commandRevision, railways = railwaysRevision
        let task = Task {
            let offer = await Task.detached(priority: .utility) { laying.offer(for: line) }.value
            guard !Task.isCancelled else { return }
            tracedSaleQuoteTask = nil
            guard commandRevision == revision, railwaysRevision == railways else {
                // L2-5 (#1576's review): the world changed meanwhile. Laid
                // out again while the trace still runs along the line, or
                // a paused game's hint would stay without a price, as
                // nothing it shows changed.
                if networkPreview?.forSale == line { quoteTracedSale(line) }
                return
            }
            tracedSaleQuote = TracedSaleQuote(offer: offer, revision: revision, railways: railways)
        }
        tracedSaleQuoteTask = (line, task)
    }

    /// Waits for the hint's price being laid out, if any (for the tests).
    func tracedSaleQuoted() async {
        while let running = tracedSaleQuoteTask {
            await running.task.value
            if tracedSaleQuoteTask?.task == running.task { break }
        }
    }

    /// Opens the purchase card of the line for sale the trace runs along
    /// (``offerRealLine(_:)``), at once with the offer the hint priced
    /// where it is still the world's. The trace stays drawn.
    public func offerTracedSaleLine() {
        guard let line = networkPreview?.forSale else { return }
        if let quote = currentTracedSaleQuote(of: line) {
            closeRealLineOffer()
            shownRealLineOffer = quote.offer
        } else {
            offerRealLine(line)
        }
    }
}

extension GameSession {
    /// For the website screenshot test (decision 165): the network tool
    /// tracing the first line for sale between its first two stations past
    /// the junction (from the junction on a line of two), and the map
    /// looking over it; whether there was one. Through the tool's own taps, as a player draws it.
    @discardableResult
    public func traceAlongALineForSale() -> Bool {
        guard canTraceRealRailway, let line = buyableRealLines.first, line.stops.count > 1,
              let railways, let frame = RealWorldFrame(world: world) else { return false }
        let points = line.stops.prefix(3).suffix(2).compactMap {
            RealLineLaying.realPoint(of: $0, system: line.system, railways: railways, frame: frame)?.plan
        }
        guard points.count == 2 else { return false }
        selectTool(.network)
        setNetworkMode(.build)
        networkTracesRealRailway = true
        let reach = NetworkBuilding.minimumSpacing * 2
        tapNetwork(at: points[0], reach: reach)
        tapNetwork(at: points[1], reach: reach)
        lookOver(WorldRegion(
            minX: Double(min(points[0].x, points[1].x)), minY: Double(min(points[0].y, points[1].y)),
            maxX: Double(max(points[0].x, points[1].x)), maxY: Double(max(points[0].y, points[1].y))
        ))
        return networkPreview?.forSale != nil
    }
}
