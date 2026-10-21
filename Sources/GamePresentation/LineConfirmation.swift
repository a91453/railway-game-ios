import GameCore

// The new line's confirmation card (ARCHITECTURE decision 303, City
// Transport Manager study 4.4, step M4): the draft's ✓ raises a card that
// sets up the whole line in one place, the competitor's "Confirm line"
// (its pictures 18 and 19). Its name and colour, one line of figures,
// when it runs and how many trains run at each time of day, each with
// how often a train comes, how many trains are still to buy and what it
// all costs; Confirm buys it all at once. Everything starts at what
// opening the line did before (decisions 258 and 264: one train, run on
// the round trip, 06:00 to midnight), so a player can confirm without
// touching anything.
//
// It only puts the existing commands together: the line is made and run by
// simple rules' service (``PlayerCommand/autoService(_:)``), with the name,
// colour and hours set in the same command, so one Undo takes it all back.
// The day keeps the world's three levels (decision 22): the card names
// them as the player reads them, the two peak bands apart but with one
// count between them, and leaves out the times the line does not run.
//
// The reference has nothing to port: `Ci/`'s lines come with their trains
// and a plus and minus. The competitor is closed. Native.

/// The settings on the new line's confirmation card (``GameSession/lineConfirmation``).
public struct LineConfirmation: Equatable, Sendable {
    /// One of the times of day the card lists, in the player's words.
    public enum Period: String, CaseIterable, Sendable {
        case morningPeak
        case daytime
        case eveningPeak
        case night

        /// The level of the world's service day the period is part of.
        public var level: ServiceLevel {
            switch self {
            case .morningPeak, .eveningPeak: .peak
            case .daytime: .offPeak
            case .night: .low
            }
        }

        /// "Morning peak", "Daytime", "Evening peak", "Night".
        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .morningPeak: language.text("Morning peak", "早尖峰")
            case .daytime: language.text("Daytime", "白天")
            case .eveningPeak: language.text("Evening peak", "晚尖峰")
            case .night: language.text("Night", "夜間")
            }
        }
    }

    /// One time of day the line runs: when, and with how many trains.
    public struct Row: Equatable, Sendable {
        public let period: Period
        /// "07:00–10:00", or several joined: "06:00–07:00, 21:00–24:00".
        public let hours: String
        public let trains: Int
        /// Minutes between trains: the round trip shared between them.
        public let headway: Int64
    }

    public var name: String
    /// The colour chosen, or `nil` for the app's own pick (``LineBadge/automaticColor(of:)``).
    public var color: LineColor?
    /// When the line starts and stops running, minutes of the day; `close`
    /// may run into the next morning (``ServiceWindow/hours(open:close:)``).
    public var open: Int
    public var close: Int
    /// Trains at each level: the two peaks share one count.
    public var trains: TrainsInService

    public init(name: String, color: LineColor? = nil, open: Int = 360, close: Int = 1440, trains: TrainsInService = Self.automaticTrains) {
        self.name = name
        self.color = color
        self.open = open
        self.close = close
        self.trains = trains
    }

    /// One train at every level: what opening a line did before (decision 264).
    public static let automaticTrains = TrainsInService(peak: 1, offPeak: 1, low: 1)

    /// The colours to pick from: the colour-blind-safe palette (decision
    /// 216's Okabe–Ito colours), which stay apart from one another and the
    /// map whichever palette the player draws with.
    public static let colors = LinePalette.safeColors.compactMap(LineColor.init(rgb:))

    /// The most trains the card sets at a time of day.
    public static let maximumTrains = 20
    /// The shortest day a line may run: an hour.
    public static let shortestDay = 60
    /// The step the hours move by: ten minutes.
    public static let minuteStep = 10

    /// The hours, as a line has them.
    public var window: ServiceWindow { .hours(open: open, close: close) }

    /// `open` moved by `minutes`, kept in the day and an hour before `close`.
    public func movingOpen(by minutes: Int) -> LineConfirmation {
        var moved = self
        moved.open = min(max(0, open + minutes), min(1439, close - Self.shortestDay))
        return moved
    }

    /// `close` moved by `minutes`, kept an hour after `open` and no later
    /// than 06:00 the next morning (``ServiceWindow/latestClose``).
    public func movingClose(by minutes: Int) -> LineConfirmation {
        var moved = self
        moved.close = min(max(open + Self.shortestDay, close + minutes), ServiceWindow.latestClose)
        return moved
    }

    /// The trains at `level` set to `count`, kept from one to ``maximumTrains``.
    public func setting(_ level: ServiceLevel, to count: Int) -> LineConfirmation {
        var set = self
        let count = min(max(1, count), Self.maximumTrains)
        switch level {
        case .peak: set.trains.peak = count
        case .offPeak: set.trains.offPeak = count
        case .low: set.trains.low = count
        }
        return set
    }

    /// The most trains any time of day runs: the trains to buy.
    public var trainsNeeded: Int {
        max(trains.peak, trains.offPeak, trains.low)
    }

    /// Minutes between trains at a time of day that runs `trains` trains
    /// on a round trip of `roundTrip` minutes: the round trip shared
    /// between them, rounded up (decision 23), and never under the line's
    /// shortest headway.
    public static func headway(roundTrip: Int64, trains: Int) -> Int64 {
        let trains = Int64(max(1, trains))
        return max(ServiceLine.minimumHeadwayMinutes, (roundTrip + trains - 1) / trains)
    }

    /// The times of day the line runs, in the card's order, each with the
    /// hours of `day` it covers between `open` and `close`. A time of day
    /// the line never runs is left out. A peak band starting before noon
    /// is the morning's, the others the evening's.
    public static func periods(of day: ServiceDay, open: Int, close: Int, in language: DisplayLanguage) -> [(period: Period, hours: String)] {
        // The day's bands from `open` to `close`, counting minutes of the
        // next morning on from 1440.
        var runs: [(start: Int, end: Int, level: ServiceLevel)] = []
        for offset in [0, 1440] {
            for (index, band) in day.bands.enumerated() {
                let end = (index + 1 < day.bands.count ? day.bands[index + 1].start : 1440) + offset
                let start = max(band.start + offset, open), stop = min(end, close)
                guard start < stop else { continue }
                if let last = runs.last, last.end == start, last.level == band.level {
                    runs[runs.count - 1].end = stop
                } else {
                    runs.append((start, stop, band.level))
                }
            }
        }
        func period(_ run: (start: Int, end: Int, level: ServiceLevel)) -> Period {
            switch run.level {
            case .peak: run.start % 1440 < 720 ? .morningPeak : .eveningPeak
            case .offPeak: .daytime
            case .low: .night
            }
        }
        return Period.allCases.compactMap { kind in
            let hours = runs.filter { period($0) == kind }.map { run in
                "\(clockText(minuteOfDay: run.start))–\(run.end == 1440 ? "24:00" : clockText(minuteOfDay: run.end))"
            }
            return hours.isEmpty ? nil : (kind, hours.joined(separator: language.text(", ", "、")))
        }
    }
}

/// What the card shows for its settings (``GameSession/lineConfirmationPreview``).
public struct LineConfirmationPreview: Equatable, Sendable {
    /// "4.2 km · about 6 min · 3 stops".
    public let figures: String
    /// "Round trip": its trains run out to the last stop and back.
    public let direction: String
    /// "06:00" and "24:00", or "01:00 next day".
    public let firstTrain: String
    public let lastTrain: String
    public let rows: [LineConfirmation.Row]
    /// Trains to buy, and what opening the line costs in all: the trains
    /// and any passing loop the line needs.
    public let trainsToBuy: Int
    public let cost: Money
    /// Why the cash in hand does not pay ``cost``, or `nil`.
    public let shortfall: String?
    /// When the card asks for more trains than can start at once (each
    /// waits on a free berth at one of the line's ends, and the track's
    /// passing places hold only so many): says how many start, or `nil`.
    public let trackLimit: String?

    /// This preview with `shortfall` for the cash there is now.
    func with(shortfall: String?) -> LineConfirmationPreview {
        LineConfirmationPreview(
            figures: figures, direction: direction, firstTrain: firstTrain, lastTrain: lastTrain, rows: rows,
            trainsToBuy: trainsToBuy, cost: cost, shortfall: shortfall, trackLimit: trackLimit
        )
    }

    /// "Buy 2 trains · $ 3,400,000"; "還要買 2 列 · $ 3,400,000".
    public func purchaseText(in language: DisplayLanguage) -> String {
        let trains = trainsToBuy == 1
            ? language.text("Buy 1 train", "還要買 1 列")
            : language.text("Buy \(trainsToBuy) trains", "還要買 \(trainsToBuy) 列")
        return trains + " · " + cost.moneyText
    }
}

extension LineConfirmation.Row {
    /// "About every 9 min"; "約每 9 分一班".
    public func headwayText(in language: DisplayLanguage) -> String {
        guard headway >= 60 else { return language.text("About every \(headway) min", "約每 \(headway) 分一班") }
        let rest = headway % 60
        return language.text(
            "About every \(headway / 60) h" + (rest == 0 ? "" : " \(rest) min"),
            "約每 \(headway / 60) 小時" + (rest == 0 ? "" : " \(rest) 分") + "一班"
        )
    }
}

struct LineConfirmationMemo {
    struct Key: Equatable {
        let confirmation: LineConfirmation
        let stops: [StationID]
        let revision: Int
        let language: DisplayLanguage
    }

    let key: Key
    let preview: LineConfirmationPreview?
    /// The command the preview prices, for its shortfall.
    let plan: AutoService?
}

extension GameSession {
    /// Raises the new line's confirmation card (decision 303) for the
    /// drafted stops, its settings at what opening the line did before; or,
    /// where the game does not run its lines for the player (realistic
    /// rules) or nothing would run yet, makes the line at once as before
    /// (``createLineFromDraft()``).
    public func confirmLineDraft() {
        refreshLineDraftRoute()
        guard runsLinesForThePlayer, lineDraftStops.count >= 2,
              autoServicePlan(creating: Self.suggestedLineName(for: world, in: language), stops: lineDraftStops, targets: nil).flatMap({ feasible($0) }) != nil
        else {
            createLineFromDraft()
            return
        }
        lineConfirmation = LineConfirmation(name: Self.suggestedLineName(for: world, in: language))
    }

    /// Puts the card away; the draft stays, to change or confirm again.
    public func cancelLineConfirmation() {
        lineConfirmation = nil
    }

    /// The card's settings changed (its name, colour, hours or trains).
    public func updateLineConfirmation(_ change: (LineConfirmation) -> LineConfirmation) {
        guard let card = lineConfirmation else { return }
        lineConfirmation = change(card)
    }

    /// Opens the drafted line as the card sets it: its name, colour and
    /// hours, and its trains at each time of day, bought, placed and run
    /// (``PlayerCommand/autoService(_:)``, one command, so one Undo).
    public func confirmLine() {
        guard let card = lineConfirmation else { return }
        // A card that cannot be paid for or run keeps the card up and says
        // why, instead of opening a bare line in its place.
        guard let preview = lineConfirmationPreview else {
            message = StatusMessage(kind: .failure, text: language.text(
                "This line can't run as set. Change the stops or the track.",
                "這條路線照這樣開不了，請改停靠站或軌道。"))
            return
        }
        if let shortfall = preview.shortfall {
            message = StatusMessage(kind: .failure, text: shortfall)
            return
        }
        createLineFromDraft(as: card)
    }

    /// What the card shows for its settings: the line's figures, its times
    /// of day with their trains and headways, and what it costs. `nil`
    /// without a card, or when the line could not run as set (no track
    /// joins its stops any more). Worked out once for each setting, draft
    /// and command (not at every tick).
    public var lineConfirmationPreview: LineConfirmationPreview? {
        guard let card = lineConfirmation else { return nil }
        let stops = lineDraftStops
        let key = LineConfirmationMemo.Key(confirmation: card, stops: stops, revision: commandRevision, language: language)
        let memo: LineConfirmationMemo
        if let kept = lineConfirmationMemo, kept.key == key {
            memo = kept
        } else {
            let worked = workOutLineConfirmationPreview(card, stops: stops)
            memo = LineConfirmationMemo(key: key, preview: worked?.preview, plan: worked?.plan)
            lineConfirmationMemo = memo
        }
        // The cash moves with game time, which the key leaves out: the
        // shortfall is read from the cash there is now, so Confirm turns
        // on once the money is there, and off when running costs take it.
        guard let preview = memo.preview else { return nil }
        return preview.with(shortfall: shortfallText(preview.cost, doing: memo.plan.map { .autoService($0) }))
    }

    /// The plan Confirm runs: the line as `card` sets it, the passing loops
    /// its trains need, and its trains: as many as the busiest time of
    /// day runs, or as many as its track can run with those loops when
    /// that is fewer (a single track runs a train more for each place to
    /// pass). Tried on a pricing copy of the world, so that the cash in
    /// hand does not decide what is shown.
    func lineConfirmationPlan(_ card: LineConfirmation, stops: [StationID], targets: TargetHeadways?) -> (plan: AutoService, trainInTheWay: Bool)? {
        let name = LineBadge.isBlank(card.name) ? Self.suggestedLineName(for: world, in: language) : card.name
        let base = world.pricingCopy()
        var wanted = card.trainsNeeded
        var found: (plan: AutoService, trainInTheWay: Bool)?
        for _ in 0..<2 {
            guard let plan = autoServicePlan(creating: name, stops: stops, targets: targets, trains: wanted) else { return nil }
            let service = TrainsInService(peak: min(card.trains.peak, wanted), offPeak: min(card.trains.offPeak, wanted), low: min(card.trains.low, wanted))
            let set = AutoService(
                newLine: AutoService.NewLine(
                    name: name, stops: plan.newLine?.stops ?? stops, targets: targets, color: card.color, window: card.window
                ),
                line: nil, loops: plan.loops, trains: plan.trains, cars: plan.cars, language: plan.language, service: service
            )
            guard let tried = feasible(set, on: base) else { return found }
            found = tried
            var trial = base
            // The track may hold fewer trains than the card asks for (a
            // single track with one passing loop runs two), and a train
            // that finds no room is held back: plan only those that run.
            guard let line = (try? apply(tried.plan, to: &trial))?.line else { break }
            let running = min(trial.lineMaximumTrains(line.id) ?? wanted, trial.line(id: line.id)?.trains.count ?? wanted)
            guard running < wanted else { break }
            wanted = max(1, running)
        }
        return found
    }

    private func workOutLineConfirmationPreview(_ card: LineConfirmation, stops: [StationID]) -> (preview: LineConfirmationPreview, plan: AutoService)? {
        guard stops.count >= 2, let found = lineConfirmationPlan(card, stops: stops, targets: nil),
              let priced = try? priced({ world throws(GameError) in try apply(found.plan, to: &world) }),
              let line = priced.result.line, let journey = priced.draft.lineJourney(line.id) else { return nil }
        let running = max(1, found.plan.trains)
        var figures: [String] = []
        if let run = world.lineDraftRun(stops: stops), run.distance > 0 {
            let minutes = max(1, (run.seconds + 30) / GameTime.secondsPerMinute)
            figures.append(StationPairComparison.kilometres(run.distance / WorldCoordinate.unitsPerMetre))
            figures.append(language.text("about \(minutes) min", "約 \(minutes) 分"))
        }
        let count = Set(stops).count
        figures.append(language.text("\(count) stops", "\(count) 站"))
        let rows = LineConfirmation.periods(of: world.serviceDay, open: card.open, close: card.close, in: language).map { period, hours in
            let trains = min(card.trains[period.level], running)
            return LineConfirmation.Row(
                period: period, hours: hours, trains: trains,
                headway: LineConfirmation.headway(roundTrip: journey.roundTripMinutes, trains: trains)
            )
        }
        let close = clockText(minuteOfDay: card.close == 1440 ? 0 : card.close)
        let preview = LineConfirmationPreview(
            figures: figures.joined(separator: " · "),
            direction: stops.first == stops.last
                ? language.text("Round trip, back through the first stop", "來回，經過起點兩次")
                : language.text("Round trip", "來回"),
            firstTrain: clockText(minuteOfDay: card.open),
            lastTrain: card.close == 1440 ? "24:00" : card.close > 1440 ? language.text("\(close) next day", "翌日 \(close)") : close,
            rows: rows,
            trainsToBuy: found.plan.trains,
            cost: priced.cost,
            // Read from the cash at each look (``lineConfirmationPreview``).
            shortfall: nil,
            trackLimit: card.trainsNeeded > running
                ? language.text(
                    running == 1
                        ? "1 train can wait at the line's ends at once. Once it leaves, add more with Add a Train."
                        : "\(running) trains can wait at the line's ends at once. Once they leave, add more with Add a Train.",
                    running == 1
                        ? "起訖站一次只能停 1 列。等它開出後，再按「加開一列車」。"
                        : "起訖站一次只能停 \(running) 列。等它們開出後，再按「加開一列車」。")
                : nil
        )
        return (preview, found.plan)
    }
}
