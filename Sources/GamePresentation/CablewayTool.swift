import GameCore

// Decision 574 (PR-2): the cable car, a mode of the network tool. A tap
// puts down the next stop on the land cell under it (a station, or an
// angle station where the rope turns), a tap on the last stop takes it
// back, and the action button builds the lot through one GameWorld
// command; the rope runs straight between the stops, over anything.
// GameCore decides whether it can be built and what it costs: the
// preview runs the same command on a copy of the world that is thrown
// away.
//
// The references: the owner's transit map site draws a gondola as a line
// of its own colour (MapBuilder's `GONDOLA`), and OpenWorld's Sun Moon
// Lake ropeway is a polyline with cabins along it (`sunmoon-ropeway.js`);
// neither has a tool for drawing one (gap: the taps are the bus tool's
// stops, decision 438).

/// What the cable car mode's stops would build, as GameCore would.
public struct CablewayPreview: Hashable, Sendable {
    /// The stops that board riders.
    public let stations: Int
    public let metres: Int64
    public let price: Money
    /// End to end, in minutes.
    public let rideMinutes: Int64
    /// Why it cannot be built, or `nil`.
    public let problem: String?
}

/// The company's cable cars and the one the mode is drawing, for the
/// map (docs/MAP_LAYERS.md, 24.9).
public struct CablewayMapOverlay: Hashable, Sendable {
    public struct Rope: Hashable, Sendable {
        /// `nil` for the draft.
        public let id: CablewayID?
        /// The stops' middles, in order: the rope's straight spans.
        public let points: [PlanPoint]
        /// Whether each stop boards riders (a station) or not (an angle
        /// station).
        public let boards: [Bool]
        /// Whether it runs today: faint on a day it stands still.
        public let runs: Bool
    }

    public var ropes: [Rope] = []
    public var draft: Rope?
    public var draftIsBuildable = false
}

/// A real cable car the mode can lay as it is (decision 574's demo): its
/// stops on the Earth and its spans' real metres.
public struct RealCableway: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public let name: String
        public let englishName: String
        public let latitude: Double
        public let longitude: Double
        public let boards: Bool
    }

    public let name: String
    public let englishName: String
    public let stops: [Stop]
    public let legMetres: [Int64]

    /// The Maokong Gondola: four stations and two angle stations, 4,033 m
    /// (gondola.taipei). Where the stops are: along the line of
    /// `Railway/geo-scene-reference-clean/source/public/rail/routes_static.geojson`
    /// (`MK`, from OpenStreetMap), the stations where the nearest station
    /// points of `Railway/tw3d-reference-clean`'s OSM tiles (`貓纜…站`) fall
    /// on it, the angle stations at its two bends; each span the line's
    /// metres between them, scaled to the official length (the line
    /// measures 4,021 m).
    public static let maokong = RealCableway(
        name: "貓空纜車", englishName: "Maokong Gondola",
        stops: [
            Stop(name: "動物園", englishName: "Taipei Zoo", latitude: 24.995998, longitude: 121.576217, boards: true),
            Stop(name: "轉角一", englishName: "Angle station 1", latitude: 24.991920, longitude: 121.583053, boards: false),
            Stop(name: "動物園南", englishName: "Taipei Zoo South", latitude: 24.990340, longitude: 121.587045, boards: true),
            Stop(name: "轉角二", englishName: "Angle station 2", latitude: 24.988280, longitude: 121.592165, boards: false),
            Stop(name: "指南宮", englishName: "Zhinan Temple", latitude: 24.978591, longitude: 121.589612, boards: true),
            Stop(name: "貓空", englishName: "Maokong", latitude: 24.968944, longitude: 121.588142, boards: true)
        ],
        legMetres: [827, 440, 568, 1_111, 1_087]
    )

    /// Its stops on `world`'s map, or `nil` on a map not on the Earth or
    /// one any stop is off.
    public func stops(in world: GameWorld) -> [CablewayStop]? {
        guard let frame = RealWorldFrame(world: world) else { return nil }
        let rows = Land.rows(in: world.bounds), columns = Land.columns(in: world.bounds)
        var placed: [CablewayStop] = []
        for stop in stops {
            let (x, y) = frame.worldPosition(latitude: stop.latitude, longitude: stop.longitude)
            guard x.isFinite, y.isFinite, x >= 0, y >= 0 else { return nil }
            let cell = CellPosition(containing: PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded())))
            guard (0..<rows).contains(cell.row), (0..<columns).contains(cell.column) else { return nil }
            placed.append(CablewayStop(cell: cell, boards: stop.boards))
        }
        return placed
    }
}

extension GameSession {
    // MARK: - Taps

    /// A tap at `point` in the cable car mode: the next stop on the cell
    /// under it (an angle station with ``cablewayPlacesAngle``, never the
    /// first); a tap on the last stop takes it back. A real cable car's
    /// spans are forgotten once a stop changes. Never changes the world.
    func tapCableway(at point: PlanPoint) {
        let cell = CellPosition(containing: point)
        cablewayDraftLegs = nil
        if cablewayDraft.last?.cell == cell {
            cablewayDraft.removeLast()
            return
        }
        guard cablewayDraft.count < Cableway.maximumStops else {
            message = StatusMessage(kind: .failure, text: language.text(
                "A cable car has at most \(Cableway.maximumStops) stops.", "一條纜車最多 \(Cableway.maximumStops) 個站。"
            ))
            return
        }
        cablewayDraft.append(CablewayStop(cell: cell, boards: cablewayDraft.isEmpty || !cablewayPlacesAngle))
    }

    /// Takes the last stop picked back.
    public func undoCablewayStop() {
        guard !cablewayDraft.isEmpty else { return }
        cablewayDraft.removeLast()
        cablewayDraftLegs = nil
    }

    /// The real cable car on this map the mode offers to lay as it is
    /// (decision 574's demo), while nothing is drawn and none is built
    /// from its first stop; `nil` otherwise.
    public var realCablewayOffer: RealCableway? {
        guard cablewayDraft.isEmpty, let stops = RealCableway.maokong.stops(in: world),
              !world.cableways.contains(where: { $0.stops.first?.cell == stops.first?.cell }) else { return nil }
        return RealCableway.maokong
    }

    /// Draws `real` (``realCablewayOffer``) as the mode's stops, with its
    /// real spans, for the action button to build.
    public func traceRealCableway(_ real: RealCableway) {
        guard let stops = real.stops(in: world) else { return }
        cablewayDraft = stops
        cablewayDraftLegs = real.legMetres
        lookAt(stops[stops.count / 2].cell.middle)
    }

    // MARK: - Building

    /// What the stops picked would build; `nil` until there are two.
    public var cablewayPreview: CablewayPreview? {
        guard cablewayDraft.count >= 2 else { return nil }
        let key = CablewayPreviewKey(stops: cablewayDraft, legs: cablewayDraftLegs, balance: world.economy.balance, cableways: world.cableways.count)
        if let memo = cablewayPreviewMemo, memo.key == key { return memo.preview }
        var copy = world
        let preview: CablewayPreview
        do throws(GameError) {
            let built = try copy.createCableway(stops: cablewayDraft, legMetres: cablewayDraftLegs)
            preview = CablewayPreview(
                stations: built.stops.filter(\.boards).count, metres: built.metres, price: world.economy.balance - copy.economy.balance,
                rideMinutes: (built.rideSeconds(from: 0, to: built.stops.count - 1) + 30) / 60, problem: nil
            )
        } catch {
            let legs = cablewayDraftLegs ?? Self.straightLegs(cablewayDraft)
            let metres = legs.reduce(0, +)
            let problem: String = switch error {
            case .invalidCableway: cablewayProblem(legs: legs)
            default: error.playerMessage(in: language)
            }
            preview = CablewayPreview(
                stations: cablewayDraft.filter(\.boards).count, metres: metres, price: Cableway.price(of: cablewayDraft, metres: metres),
                rideMinutes: 0, problem: problem
            )
        }
        cablewayPreviewMemo = (key, preview)
        return preview
    }

    /// Builds the cable car drawn, and pays for it. Returns whether it did.
    @discardableResult
    public func buildCableway() -> Bool {
        guard cablewayPreview?.problem == nil, cablewayDraft.count >= 2 else { return false }
        let done = perform(.createCableway(stops: cablewayDraft, legMetres: cablewayDraftLegs)) { _, before, after in
            let price = before.economy.balance - after.economy.balance
            let name = after.cableways.last.map { CablewayText.name($0.id, in: language) } ?? ""
            return language.text("\(name) now runs, for \(price.moneyText).", "\(name)開通了，花費 \(price.moneyText)。")
        }
        guard done != nil else { return false }
        cablewayDraft = []
        cablewayDraftLegs = nil
        return true
    }

    /// Takes cable car `id` down: nothing is sold back.
    public func removeCableway(_ id: CablewayID) {
        perform(.removeCableway(id)) { _, _, _ in
            language.text("The cable car is taken down.", "纜車拆掉了。")
        }
    }

    /// What the mode says: the next tap, or what the stops would build.
    func cablewayDraftText() -> String {
        guard !cablewayDraft.isEmpty else {
            return language.text(
                "Tap where the cable car starts, then each stop in turn. The rope runs straight over anything.",
                "請點纜車的起點，再依序點各站。纜線直線拉過去，山、河、路都能跨。"
            )
        }
        guard let preview = cablewayPreview else {
            return language.text("Tap the next stop. Tap the last stop again to take it back.", "請點下一站。再點一次最後一站可以取消它。")
        }
        if let problem = preview.problem { return problem }
        return CablewayText.summary(stations: preview.stations, metres: preview.metres, minutes: preview.rideMinutes, in: language)
    }

    /// Why GameCore refused the stops, in the player's words.
    private func cablewayProblem(legs: [Int64]) -> String {
        if cablewayDraft.last?.boards == false {
            return language.text("The last stop must be a station, not an angle station.", "最後一站要是車站，不能是轉角站。")
        }
        if legs.contains(where: { $0 > Cableway.maximumLegMetres }) {
            return language.text(
                "A span is longer than \(Cableway.maximumLegMetres / 1_000) km: add a stop between.",
                "有一段超過 \(Cableway.maximumLegMetres / 1_000) 公里，請在中間加一站。"
            )
        }
        return language.text("The cable car cannot go here.", "纜車不能蓋在這裡。")
    }

    /// The straight spans between `stops`' cells' middles, in metres, as
    /// GameCore measures them without real ones.
    static func straightLegs(_ stops: [CablewayStop]) -> [Int64] {
        zip(stops, stops.dropFirst()).map { a, b in
            let (from, to) = (a.cell.middle, b.cell.middle)
            let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
            return max(1, Int64(((dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)).rounded()))
        }
    }

    // MARK: - The map

    /// The company's cable cars and the one drawn, or `nil` when there is
    /// nothing to draw.
    public var cablewayMapOverlay: CablewayMapOverlay? {
        let drawing = tool == .network && networkMode == .cableway && !cablewayDraft.isEmpty
        guard !world.cableways.isEmpty || drawing else { return nil }
        var overlay = CablewayMapOverlay()
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        overlay.ropes = world.cableways.map { cableway in
            CablewayMapOverlay.Rope(
                id: cableway.id, points: cableway.stops.map(\.cell.middle), boards: cableway.stops.map(\.boards),
                runs: world.cablewayIsOpen(cableway.id, onDay: today)
            )
        }
        if drawing {
            overlay.draft = CablewayMapOverlay.Rope(
                id: nil, points: cablewayDraft.map(\.cell.middle), boards: cablewayDraft.map(\.boards), runs: true
            )
            overlay.draftIsBuildable = cablewayPreview?.problem == nil && cablewayDraft.count >= 2
        }
        return overlay
    }

    // MARK: - The card

    /// Cable car `id`'s card (decision 574): its rows, or `nil`.
    public func cablewayCard(_ id: CablewayID) -> CablewayCard? {
        guard let cableway = world.cableway(id: id) else { return nil }
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        let open = world.cablewayIsOpen(id, onDay: today)
        var rows: [String] = []
        let stations = cableway.stops.filter(\.boards).count
        rows.append(CablewayText.summary(
            stations: stations, metres: cableway.metres,
            minutes: (cableway.rideSeconds(from: 0, to: cableway.stops.count - 1) + 30) / 60, in: language
        ))
        rows.append(language.text(
            "\(Cableway.hourlyCapacity.groupedText) people an hour each way · \(Cableway.fare.moneyText) a ride",
            "單向每小時 \(Cableway.hourlyCapacity.groupedText) 人 · 每人 \(Cableway.fare.moneyText)"
        ))
        let hours = Cableway.operatingHours(onDay: today)
        rows.append(open
            ? language.text("Runs today, 9:00–\(9 + hours):00", "今天營運 9:00–\(9 + hours):00")
            : language.text("Stands still today: \(closedReason(cableway, onDay: today).english)", "今天停駛：\(closedReason(cableway, onDay: today).chinese)"))
        if let station = cableway.transfer.flatMap({ world.station(id: $0.station) }) {
            rows.append(language.text("Meets \(station.name) station", "接 \(station.name)站"))
        }
        if let last = cableway.days.last {
            rows.append(last.closed
                ? language.text("Yesterday: stood still · cost \(last.cost.moneyText)", "昨天：停駛 · 成本 \(last.cost.moneyText)")
                : language.text(
                    "Yesterday: \(last.riders.groupedText) riders · fares \(last.fares.moneyText) · cost \(last.cost.moneyText)",
                    "昨天：乘客 \(last.riders.groupedText) 人 · 票收 \(last.fares.moneyText) · 成本 \(last.cost.moneyText)"
                ))
        } else {
            rows.append(language.text(
                "Costs \(cableway.dailyCost.moneyText) a day to run", "每天營運成本 \(cableway.dailyCost.moneyText)"
            ))
        }
        return CablewayCard(id: id, title: CablewayText.name(id, in: language), rows: rows, runs: open)
    }

    /// Why cable car `cableway` stands still on `day`, as GameCore's
    /// ``GameWorld/cablewayIsOpen(_:onDay:)`` checks it.
    private func closedReason(_ cableway: Cableway, onDay day: Int64) -> (english: String, chinese: String) {
        if StationDemand.weekday(ofDay: day) == 1, world.holiday(onDay: day) == nil { return ("Monday maintenance", "週一例行保養") }
        if world.weather(onDay: day) == .thunderstorm { return ("thunderstorm", "雷雨") }
        return ("typhoon", "颱風")
    }
}

/// What the preview was worked out from (``GameSession/cablewayPreview``).
struct CablewayPreviewKey: Hashable {
    let stops: [CablewayStop]
    let legs: [Int64]?
    let balance: Money
    let cableways: Int
}

/// A cable car's card (decision 574): its name and rows of plain text.
public struct CablewayCard: Hashable, Sendable, Identifiable {
    public let id: CablewayID
    public let title: String
    public let rows: [String]
    public let runs: Bool
}

/// The cable car's words.
public enum CablewayText {
    /// "Cable car 1" / "纜車 1".
    public static func name(_ id: CablewayID, in language: DisplayLanguage) -> String {
        language.text("Cable car \(id.rawValue)", "纜車 \(id.rawValue)")
    }

    /// "4 stations · 4,033 m · 17 min end to end".
    public static func summary(stations: Int, metres: Int64, minutes: Int64, in language: DisplayLanguage) -> String {
        language.text(
            "\(stations) stations · \(metres.groupedText) m · \(minutes) min end to end",
            "\(stations) 站 · \(metres.groupedText) 公尺 · 全程 \(minutes) 分"
        )
    }
}
