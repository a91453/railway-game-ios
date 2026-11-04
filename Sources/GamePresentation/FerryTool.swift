import GameCore

// Decision 585 (PR-2): the ferry, a mode of the transit tool (the bus
// tool, renamed). A tap on a land cell beside the water puts down the next
// pier, a tap on the last pier takes it back, and the action button opens
// the route through one GameWorld command with the boats and headway
// chosen; the boats cross straight between the piers. GameCore decides
// whether it can be built and what it costs: the preview runs the same
// command on a copy of the world that is thrown away. Modelled on the
// cable car mode (CablewayTool.swift, decision 574).
//
// The references: MapBuilder's `FERRY` draws a ferry as a line of its own
// and `assets/user/ferry.svg` marks its piers; neither has a tool for
// drawing one (gap: the taps are the cable car mode's).

/// What the ferry mode's piers would open, as GameCore would.
public struct FerryPreview: Hashable, Sendable {
    public let piers: Int
    public let metres: Int64
    public let price: Money
    /// First pier to last, in minutes.
    public let rideMinutes: Int64
    /// Minutes between boats, as its boats can keep; `nil` with none.
    public let headway: Int64?
    /// Riders its boats carry on a weekday, there and back.
    public let dailyCapacity: Int64
    /// The railway station its piers meet, or `nil`.
    public let station: String?
    /// Why it cannot be built, or `nil`.
    public let problem: String?
}

/// The company's ferry routes and the one the mode is drawing, for the
/// map: piers and the straight crossings between them.
public struct FerryMapOverlay: Hashable, Sendable {
    public struct Route: Hashable, Sendable {
        /// `nil` for the draft.
        public let id: FerryRouteID?
        /// The piers' middles, in order: the crossings' straight lines.
        public let piers: [PlanPoint]
        /// Whether its boats sail today: faint on a day they do not.
        public let sails: Bool
    }

    public var routes: [Route] = []
    public var draft: Route?
    public var draftIsBuildable = false
}

/// A real ferry the mode can lay as it is (decision 585's demo): its piers
/// on the Earth and its crossings' metres.
public struct RealFerry: Hashable, Sendable {
    public struct Pier: Hashable, Sendable {
        public let name: String
        public let englishName: String
        public let latitude: Double
        public let longitude: Double
    }

    public let name: String
    public let englishName: String
    public let piers: [Pier]
    public let legMetres: [Int64]

    /// Tamsui–Bali across the Tamsui River's mouth: the two ferry piers,
    /// 1,260 m apart in a straight line (the crossing takes about 10
    /// minutes, New Taipei transport department, 2026-05-18). The
    /// coordinates are the piers' as on the map, not checked against
    /// OpenStreetMap here (UNVERIFIED: the extract and Overpass could not
    /// be reached).
    public static let tamsuiBali = RealFerry(
        name: "淡水—八里", englishName: "Tamsui–Bali",
        piers: [
            Pier(name: "淡水", englishName: "Tamsui", latitude: 25.1693, longitude: 121.4395),
            Pier(name: "八里", englishName: "Bali", latitude: 25.1585, longitude: 121.4357)
        ],
        legMetres: [1_260]
    )

    /// Gushan–Cijin across Kaohsiung harbour's mouth: the two ferry
    /// piers, 715 m apart in a straight line (about 5 minutes). The
    /// coordinates as Tamsui–Bali's (UNVERIFIED).
    public static let gushanCijin = RealFerry(
        name: "鼓山—旗津", englishName: "Gushan–Cijin",
        piers: [
            Pier(name: "鼓山", englishName: "Gushan", latitude: 22.6195, longitude: 120.2690),
            Pier(name: "旗津", englishName: "Cijin", latitude: 22.6135, longitude: 120.2665)
        ],
        legMetres: [715]
    )

    public static let all = [tamsuiBali, gushanCijin]

    /// How far from a pier's point its cell may be: the nearest cell a
    /// pier can stand on within this many cells.
    static let snapCells = 4

    /// Its piers on `world`'s map, each on the nearest cell beside the
    /// water within ``snapCells``, or `nil` on a map not on the Earth, one
    /// a pier is off, or one with no shore near a pier.
    public func piers(in world: GameWorld) -> [CellPosition]? {
        guard let frame = RealWorldFrame(world: world) else { return nil }
        let rows = Land.rows(in: world.bounds), columns = Land.columns(in: world.bounds)
        var placed: [CellPosition] = []
        for pier in piers {
            let (x, y) = frame.worldPosition(latitude: pier.latitude, longitude: pier.longitude)
            guard x.isFinite, y.isFinite, x >= 0, y >= 0 else { return nil }
            let at = CellPosition(containing: PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded())))
            guard (0..<rows).contains(at.row), (0..<columns).contains(at.column) else { return nil }
            var best: (distance: Int, cell: CellPosition)?
            for row in (at.row - Self.snapCells)...(at.row + Self.snapCells) {
                for column in (at.column - Self.snapCells)...(at.column + Self.snapCells) where world.isPierCell(row: row, column: column) {
                    let distance = (row - at.row) * (row - at.row) + (column - at.column) * (column - at.column)
                    if best.map({ distance < $0.distance }) ?? true { best = (distance, CellPosition(row: row, column: column)) }
                }
            }
            guard let cell = best?.cell, placed.last != cell else { return nil }
            placed.append(cell)
        }
        return placed
    }
}

extension GameSession {
    // MARK: - Taps

    /// A tap at `point` in the ferry mode: the next pier on the cell under
    /// it, which must be land beside the water; a tap on the last pier
    /// takes it back. A real ferry's crossings are forgotten once a pier
    /// changes. Never changes the world.
    func tapFerry(at point: PlanPoint) {
        let cell = CellPosition(containing: point)
        ferryDraftLegs = nil
        if ferryDraft.last == cell {
            ferryDraft.removeLast()
            return
        }
        guard world.isPierCell(row: cell.row, column: cell.column) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "A pier stands on the shore: tap land beside the water.", "碼頭要蓋在岸邊：請點水邊的陸地。"
            ))
            return
        }
        guard ferryDraft.count < FerryRoute.maximumPiers else {
            message = StatusMessage(kind: .failure, text: language.text(
                "A ferry route has at most \(FerryRoute.maximumPiers) piers.", "一條渡輪航線最多 \(FerryRoute.maximumPiers) 個碼頭。"
            ))
            return
        }
        ferryDraft.append(cell)
    }

    /// Takes the last pier picked back.
    public func undoFerryPier() {
        guard !ferryDraft.isEmpty else { return }
        ferryDraft.removeLast()
        ferryDraftLegs = nil
    }

    /// The boats the route drawn opens with, 1 to ``FerryRoute/maximumBoats``.
    public func setFerryDraftBoats(_ boats: Int) {
        ferryDraftBoats = min(max(boats, 1), FerryRoute.maximumBoats)
    }

    /// The minutes between boats the route drawn opens with.
    public func setFerryDraftMinutesApart(_ minutes: Int64) {
        ferryDraftMinutesApart = min(max(minutes, 1), BusService.longestHeadway)
    }

    /// The real ferry on this map the mode offers to lay as it is
    /// (decision 585's demo), while nothing is drawn and none is open from
    /// its first pier; `nil` otherwise.
    public var realFerryOffer: RealFerry? {
        guard ferryDraft.isEmpty else { return nil }
        return RealFerry.all.first { real in
            guard let piers = real.piers(in: world) else { return false }
            return !world.ferryRoutes.contains { $0.piers.first == piers.first }
        }
    }

    /// Draws `real` (``realFerryOffer``) as the mode's piers, with its real
    /// crossings, for the action button to open.
    public func traceRealFerry(_ real: RealFerry) {
        guard let piers = real.piers(in: world) else { return }
        ferryDraft = piers
        ferryDraftLegs = real.legMetres
        lookAt(piers[piers.count / 2].middle)
    }

    // MARK: - Building

    /// What the piers picked would open; `nil` until there are two.
    public var ferryPreview: FerryPreview? {
        guard ferryDraft.count >= 2 else { return nil }
        let service = BusService.every(minutes: ferryDraftMinutesApart)
        let key = FerryPreviewKey(
            piers: ferryDraft, legs: ferryDraftLegs, boats: ferryDraftBoats, minutes: ferryDraftMinutesApart,
            balance: world.economy.balance, routes: world.ferryRoutes.count, stations: world.stations.count
        )
        if let memo = ferryPreviewMemo, memo.key == key { return memo.preview }
        var copy = world
        let preview: FerryPreview
        let weekday = Self.ferryWeekday(from: world.clock.now.seconds / GameTime.secondsPerDay)
        do throws(GameError) {
            let built = try copy.createFerryRoute(piers: ferryDraft, legMetres: ferryDraftLegs, service: service, boats: ferryDraftBoats)
            preview = FerryPreview(
                piers: built.piers.count, metres: built.metres, price: world.economy.balance - copy.economy.balance,
                rideMinutes: built.rideMinutes(from: 0, to: built.piers.count - 1), headway: built.headway,
                dailyCapacity: built.dailyCapacity(onDay: weekday),
                station: built.transfer.flatMap { copy.station(id: $0.station)?.name }, problem: nil
            )
        } catch {
            let legs = ferryDraftLegs ?? Self.straightFerryLegs(ferryDraft)
            let problem: String = switch error {
            case .invalidFerryRoute where legs.contains(where: { $0 > FerryRoute.maximumLegMetres }):
                language.text(
                    "A crossing is longer than \(FerryRoute.maximumLegMetres / 1_000) km: add a pier between.",
                    "有一段超過 \(FerryRoute.maximumLegMetres / 1_000) 公里，請在中間加一個碼頭。"
                )
            default: error.playerMessage(in: language)
            }
            preview = FerryPreview(
                piers: ferryDraft.count, metres: legs.reduce(0, +), price: FerryRoute.price(piers: ferryDraft.count, boats: ferryDraftBoats),
                rideMinutes: 0, headway: nil, dailyCapacity: 0, station: nil, problem: problem
            )
        }
        ferryPreviewMemo = (key, preview)
        return preview
    }

    /// Opens the route drawn, and pays for it. Returns whether it did.
    @discardableResult
    public func buildFerryRoute() -> Bool {
        guard ferryPreview?.problem == nil, ferryDraft.count >= 2 else { return false }
        let edit = PlayerCommand.Edit.createFerryRoute(
            piers: ferryDraft.map(PlayerCommand.Edit.BusStop.init), legMetres: ferryDraftLegs,
            service: .every(minutes: ferryDraftMinutesApart), boats: ferryDraftBoats
        )
        let done = perform(edit) { _, before, after in
            let price = before.economy.balance - after.economy.balance
            let name = after.ferryRoutes.last.map { FerryText.name($0.id, in: language) } ?? ""
            return language.text("\(name) now sails, for \(price.moneyText).", "\(name)開航了，花費 \(price.moneyText)。")
        }
        guard done != nil else { return false }
        ferryDraft = []
        ferryDraftLegs = nil
        return true
    }

    /// Sails `boats` boats on route `id`: more are bought, fewer are sold
    /// for nothing.
    public func setFerryBoats(_ id: FerryRouteID, to boats: Int) {
        perform(.setFerryBoats(id, boats: boats)) { _, _, _ in
            language.text("\(FerryText.boats(boats, in: .english)) now sail.", "現在有 \(boats) 艘船。")
        }
    }

    /// A boat every `minutes` minutes on route `id`.
    public func setFerryMinutesApart(_ id: FerryRouteID, to minutes: Int64) {
        perform(.setFerryRuns(id, .every(minutes: minutes))) { _, _, _ in
            language.text("A boat every \(minutes) min.", "每 \(minutes) 分一班。")
        }
    }

    /// Closes route `id`: nothing is sold back.
    public func removeFerryRoute(_ id: FerryRouteID) {
        perform(.removeFerryRoute(id)) { _, _, _ in
            language.text("The ferry route is closed.", "渡輪航線停航了。")
        }
    }

    /// What the mode says: the next tap, or what the piers would open.
    public func ferryDraftText() -> String {
        guard !ferryDraft.isEmpty else {
            return language.text(
                "Tap the shore where the ferry starts, then each pier in turn. Boats cross straight between them.",
                "請點渡輪起點的岸邊，再依序點各碼頭。船在碼頭之間直線往返。"
            )
        }
        guard let preview = ferryPreview else {
            return language.text("Tap the next pier. Tap the last pier again to take it back.", "請點下一個碼頭。再點一次最後一個碼頭可以取消它。")
        }
        if let problem = preview.problem { return problem }
        return FerryText.summary(piers: preview.piers, metres: preview.metres, minutes: preview.rideMinutes, in: language)
    }

    /// The straight crossings between `piers`' cells' middles, in metres,
    /// as GameCore measures them without real ones.
    static func straightFerryLegs(_ piers: [CellPosition]) -> [Int64] {
        zip(piers, piers.dropFirst()).map { a, b in
            let (from, to) = (a.middle, b.middle)
            let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
            return max(1, Int64(((dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)).rounded()))
        }
    }

    /// The first weekday from game day `day` on, for the capacity a
    /// preview quotes.
    static func ferryWeekday(from day: Int64) -> Int64 {
        var day = day
        while StationDemand.isWeekend(day: day) { day += 1 }
        return day
    }

    // MARK: - The map

    /// The company's ferry routes and the one drawn, or `nil` when there
    /// is nothing to draw.
    public var ferryMapOverlay: FerryMapOverlay? {
        let drawing = tool == .bus && busMode == .ferries && !ferryDraft.isEmpty
        guard !world.ferryRoutes.isEmpty || drawing else { return nil }
        var overlay = FerryMapOverlay()
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        overlay.routes = world.ferryRoutes.map { route in
            FerryMapOverlay.Route(
                id: route.id, piers: route.piers.map(\.middle),
                sails: route.boats > 0 && world.ferryRouteIsOpen(route.id, onDay: today)
            )
        }
        if drawing {
            overlay.draft = FerryMapOverlay.Route(id: nil, piers: ferryDraft.map(\.middle), sails: true)
            overlay.draftIsBuildable = ferryPreview?.problem == nil && ferryDraft.count >= 2
        }
        return overlay
    }

    // MARK: - The card

    /// Ferry route `id`'s card (decision 585): its rows, or `nil`.
    public func ferryCard(_ id: FerryRouteID) -> FerryCard? {
        guard let route = world.ferryRoute(id: id) else { return nil }
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        let open = world.ferryRouteIsOpen(id, onDay: today)
        var rows: [String] = []
        rows.append(FerryText.summary(
            piers: route.piers.count, metres: route.metres, minutes: route.rideMinutes(from: 0, to: route.piers.count - 1), in: language
        ))
        if let headway = route.headway {
            rows.append(language.text(
                "A boat every \(headway) min · \(FerryText.boats(route.boats, in: .english)) · \(route.dailyCapacity(onDay: today).groupedText) seats a day · \(FerryRoute.fare.moneyText) a ride",
                "每 \(headway) 分一班 · \(route.boats) 艘船 · 一天 \(route.dailyCapacity(onDay: today).groupedText) 個座位 · 每人 \(FerryRoute.fare.moneyText)"
            ))
        } else {
            rows.append(language.text("No boats: it does not sail.", "沒有船：航線停航中。"))
        }
        let hours = FerryRoute.operatingMinutes(onDay: today) / 60
        rows.append(open
            ? language.text("Sails today, 7:00–\(7 + hours):00", "今天開航 7:00–\(7 + hours):00")
            : language.text("No sailings today: typhoon", "今天停航：颱風"))
        if let station = route.transfer.flatMap({ world.station(id: $0.station) }) {
            rows.append(language.text("Meets \(station.name) station", "接 \(station.name)站"))
        }
        if let last = route.days.last {
            rows.append(last.closed
                ? language.text("Yesterday: no sailings · cost \(last.cost.moneyText)", "昨天：停航 · 成本 \(last.cost.moneyText)")
                : language.text(
                    "Yesterday: \(last.riders.groupedText) riders · fares \(last.fares.moneyText) · cost \(last.cost.moneyText)",
                    "昨天：乘客 \(last.riders.groupedText) 人 · 票收 \(last.fares.moneyText) · 成本 \(last.cost.moneyText)"
                ))
        } else {
            rows.append(language.text(
                "Costs \(route.dailyCost(onDay: today).moneyText) a day to run", "每天營運成本 \(route.dailyCost(onDay: today).moneyText)"
            ))
        }
        return FerryCard(id: id, title: FerryText.name(id, in: language), rows: rows, sails: open && route.boats > 0, boats: route.boats,
                         minutesApart: route.service.averageMinutes)
    }
}

/// What the preview was worked out from (``GameSession/ferryPreview``).
struct FerryPreviewKey: Hashable {
    let piers: [CellPosition]
    let legs: [Int64]?
    let boats: Int
    let minutes: Int64
    let balance: Money
    let routes: Int
    let stations: Int
}

/// A ferry route's card (decision 585): its name and rows of plain text,
/// and the boats and headway its steppers start from.
public struct FerryCard: Hashable, Sendable, Identifiable {
    public let id: FerryRouteID
    public let title: String
    public let rows: [String]
    public let sails: Bool
    public let boats: Int
    public let minutesApart: Int64
}

/// The ferry's words.
public enum FerryText {
    /// "Ferry 1" / "渡輪 1".
    public static func name(_ id: FerryRouteID, in language: DisplayLanguage) -> String {
        language.text("Ferry \(id.rawValue)", "渡輪 \(id.rawValue)")
    }

    /// "2 piers · 1,260 m · 6 min across".
    public static func summary(piers: Int, metres: Int64, minutes: Int64, in language: DisplayLanguage) -> String {
        language.text(
            "\(piers) piers · \(metres.groupedText) m · \(minutes) min across",
            "\(piers) 個碼頭 · \(metres.groupedText) 公尺 · 船程 \(minutes) 分"
        )
    }

    /// "1 boat" / "2 boats" (English only).
    static func boats(_ count: Int, in language: DisplayLanguage) -> String {
        count == 1 ? "1 boat" : "\(count) boats"
    }
}
