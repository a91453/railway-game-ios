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

    /// Decision 1040: a point of a funicular's track on the Earth.
    public struct TrackPoint: Hashable, Sendable {
        public let latitude: Double
        public let longitude: Double
    }

    public let name: String
    public let englishName: String
    public let stops: [Stop]
    public let legMetres: [Int64]
    /// Decision 586: the station it meets, by name and place (its first
    /// stop's real transfer), or `nil` to meet the nearest.
    public var meets: Stop?
    /// Decision 1040: what runs on it: a gondola lift, or a funicular
    /// laid only as it is (the player draws no funicular stop by stop).
    public var kind: Cableway.Kind = .aerial
    /// Decision 1040: a funicular's track from its first stop to its last,
    /// each stop one of its points (``trackStops``); empty for a gondola,
    /// whose rope runs straight from stop to stop.
    public var track: [TrackPoint] = []
    /// Decision 1040: the point of ``track`` each stop stands at, in order.
    public var trackStops: [Int] = []
    /// Decision 1040: the points of ``track`` its passing loop runs
    /// between, where the car going up meets the one coming down.
    public var passingLoop: ClosedRange<Int>?

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
        legMetres: [827, 440, 568, 1_111, 1_087],
        // Decision 586: MRT Taipei Zoo, whose exit 2 is by the gondola
        // (the app's `track_stations.geojson`): 413 m from the gondola's
        // Taipei Zoo stop, Muzha 404 m, so the nearest is not the one
        // riders change at.
        meets: Stop(name: "動物園", englishName: "Taipei Zoo", latitude: 24.998333, longitude: 121.579402, boards: true)
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

    /// Where ``meets`` stands on `world`'s map, or `nil` without one or on
    /// a map not on the Earth.
    public func meetsNear(in world: GameWorld) -> PlanPoint? {
        guard let meets, let frame = RealWorldFrame(world: world) else { return nil }
        let (x, y) = frame.worldPosition(latitude: meets.latitude, longitude: meets.longitude)
        guard x.isFinite, y.isFinite else { return nil }
        return PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded()))
    }

    /// Decision 615: the Sun Moon Lake Ropeway, Sun Moon Lake to the
    /// Formosan Aboriginal Culture Village: its two stations, OpenStreetMap
    /// nodes 800331755 (日月潭端車站) and 800332213 (九族端車站), its span
    /// the length of OpenStreetMap way 65630200 (`aerialway=gondola`,
    /// osmtoday.com's Taiwan extract of 2026-11-06, ODbL), 1,860 m. Used to
    /// tell which cable cars run its cabins (``Map3DCableways/look(of:in:)``)
    /// and to name its stops; since decision 870 the mode offers it to lay
    /// as it is too.
    public static let sunMoonLake = RealCableway(
        name: "日月潭纜車", englishName: "Sun Moon Lake Ropeway",
        stops: [
            Stop(name: "日月潭", englishName: "Sun Moon Lake", latitude: 23.852257, longitude: 120.9348179, boards: true),
            Stop(name: "九族文化村", englishName: "Formosan Aboriginal Culture Village", latitude: 23.8601457, longitude: 120.950941, boards: true)
        ],
        legMetres: [1_860]
    )

    /// Decision 870: the Wulai cable car, from Wulai Waterfall up to Yun
    /// Hsien Resort: the two ends of OpenStreetMap way 188552077
    /// (`aerialway=cable_car`, 烏來空中纜車; nodes 1991814130, the lower,
    /// and 1991814131; osmtoday.com's Taiwan extract of 2026-11-18, ODbL),
    /// its span the way's length, 381 m (the operator gives 382 m). The
    /// real one is an aerial tramway of two large cabins; in the game it
    /// runs as every cable car does (gap, decision 870).
    public static let wulai = RealCableway(
        name: "烏來空中纜車", englishName: "Wulai Cable Car",
        stops: [
            Stop(name: "烏來瀑布", englishName: "Wulai Waterfall", latitude: 24.8489501, longitude: 121.5512864, boards: true),
            Stop(name: "雲仙樂園", englishName: "Yun Hsien Resort", latitude: 24.845975, longitude: 121.5531608, boards: true)
        ],
        legMetres: [381]
    )

    /// Decision 872: Hong Kong's Ngong Ping cable car (Ngong Ping 360),
    /// from Tung Chung over the bay and Lantau's hills to Ngong Ping: two
    /// stations and two angle stations along OpenStreetMap way 26351045
    /// (`aerialway=gondola`, 昂坪纜車; osmtoday.com's Hong Kong extract of
    /// 2026-11-18, ODbL). The stations are the way's ends (nodes
    /// 4402125187 東涌 and 4402125186 昂坪), the angle stations its two
    /// `aerialway=deflection_roller` nodes where the rope turns (288710867
    /// 機場島, 288709227 彌勒山); each span is the way's metres between
    /// them, 5,767 m in all (the operator says 5.7 km). It meets MTR Tung
    /// Chung (the Tung Chung Line's end in `hongkong/track_stations.geojson`),
    /// 323 m from the cable car's terminal.
    public static let ngongPing = RealCableway(
        name: "昂坪纜車", englishName: "Ngong Ping Cable Car",
        stops: [
            Stop(name: "東涌", englishName: "Tung Chung", latitude: 22.2902758, longitude: 113.9385089, boards: true),
            Stop(name: "機場島", englishName: "Airport Island", latitude: 22.2917448, longitude: 113.9327026, boards: false),
            Stop(name: "彌勒山", englishName: "Nei Lak Shan", latitude: 22.2691908, longitude: 113.9079404, boards: false),
            Stop(name: "昂坪", englishName: "Ngong Ping", latitude: 22.2563956, longitude: 113.9014311, boards: true)
        ],
        legMetres: [619, 3_575, 1_573],
        meets: Stop(name: "東涌", englishName: "Tung Chung", latitude: 22.289158, longitude: 113.941405, boards: true)
    )

    /// Decision 1040: Hong Kong's Peak Tram, a funicular from Garden Road
    /// up to the Peak: its track the line of OpenStreetMap's
    /// `railway=funicular` ways of the Peak Tram (4338940, 85404052,
    /// 85404150, 265943512, 265943515, 622565242, 1046739316, 1046739317,
    /// 1117280223, 1165024097, 1308940440, 1308940441; osmtoday.com's Hong
    /// Kong extract of 2026-11-27, ODbL) from the Garden Road stop
    /// (node 2525250101) to the Peak (node 26412045), the passing loop's
    /// west track (265943512, the east one is 265943513); its six stations
    /// its nodes 2525250101 花園道, 526904599 堅尼地道, 988059698 麥當勞道,
    /// 988059498 梅道, 988059821 白加道 and 26412045 山頂, each a point of
    /// the line; each span the line's metres between them, 1,247 m in all
    /// (the operator says about 1.4 km with the stations' tracks, and
    /// 4.5–6 minutes end to end: 1,247 m at 6 m/s and four stops of 20 s
    /// make 4.8). Every one boards: the operator lists all six. It meets
    /// no railway: MTR Central is some 600 m from Garden Road.
    public static let peakTram = RealCableway(
        name: "山頂纜車", englishName: "Peak Tram",
        stops: [
            Stop(name: "花園道", englishName: "Garden Road", latitude: 22.2771695, longitude: 114.158577, boards: true),
            Stop(name: "堅尼地道", englishName: "Kennedy Road", latitude: 22.276545, longitude: 114.1580862, boards: true),
            Stop(name: "麥當勞道", englishName: "MacDonnell Road", latitude: 22.2751722, longitude: 114.1571206, boards: true),
            Stop(name: "梅道", englishName: "May Road", latitude: 22.2733633, longitude: 114.155887, boards: true),
            Stop(name: "白加道", englishName: "Barker Road", latitude: 22.2709577, longitude: 114.1517471, boards: true),
            Stop(name: "山頂", englishName: "The Peak", latitude: 22.271123, longitude: 114.1501414, boards: true)
        ],
        legMetres: [86, 182, 238, 575, 166],
        kind: .funicular,
        track: [
            (22.2771695, 114.1585770), (22.2769392, 114.1583785), (22.2768893, 114.1583380), (22.2768355, 114.1582941),
            (22.2767649, 114.1582439), (22.2765450, 114.1580862), (22.2764321, 114.1580080), (22.2762955, 114.1579122),
            (22.2756926, 114.1574881), (22.2751722, 114.1571206), (22.2747827, 114.1568307), (22.2742035, 114.1564041),
            (22.2733633, 114.1558870), (22.2730611, 114.1556754), (22.2729948, 114.1556136), (22.2729253, 114.1555332),
            (22.2728732, 114.1554799), (22.2721453, 114.1549689), (22.2712816, 114.1543629), (22.2710967, 114.1542349),
            (22.2710300, 114.1541816), (22.2709637, 114.1541117), (22.2709084, 114.1540389), (22.2708634, 114.1539661),
            (22.2708224, 114.1538857), (22.2707940, 114.1538063), (22.2707709, 114.1537159), (22.2707542, 114.1536219),
            (22.2707494, 114.1535337), (22.2707533, 114.1534625), (22.2708793, 114.1524047), (22.2709577, 114.1517471),
            (22.2709780, 114.1515542), (22.2709886, 114.1514534), (22.2711097, 114.1503039), (22.2711230, 114.1501414),
        ].map { TrackPoint(latitude: $0.0, longitude: $0.1) },
        trackStops: [0, 5, 9, 12, 31, 35],
        passingLoop: 13...30
    )

    /// The real cable cars the mode knows by their stops.
    public static let all: [RealCableway] = [.maokong, .sunMoonLake, .wulai, .ngongPing, .peakTram]

    /// The real cable car `cableway` was laid as (decision 583: its stops'
    /// names for the follow bar): the same stops on the same cells, the
    /// same spans; `nil` for one the player laid stop by stop.
    public static func matching(_ cableway: Cableway, in world: GameWorld) -> RealCableway? {
        all.first { $0.kind == cableway.kind && $0.legMetres == cableway.legMetres && $0.stops(in: world) == cableway.stops }
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
        cablewayDraftMeets = nil
        cablewayDraftKind = nil
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
        cablewayDraftMeets = nil
        cablewayDraftKind = nil
    }

    /// The real cable cars on this map the mode offers to lay as they are
    /// (decision 574's demo; decision 870: every one of
    /// ``RealCableway/all``, not Maokong alone), while nothing is drawn:
    /// those whose stops are all on the map and none is built from their
    /// first stop, nearest ``realLineFocus`` first.
    public var realCablewayOffers: [RealCableway] {
        guard cablewayDraft.isEmpty else { return [] }
        let focus = realLineFocus
        return RealCableway.all.enumerated().compactMap { index, real -> (distance: Double, index: Int, real: RealCableway)? in
            guard let first = real.stops(in: world)?.first,
                  !world.cableways.contains(where: { $0.stops.first?.cell == first.cell }) else { return nil }
            let middle = first.cell.middle
            let dx = Double(middle.x - focus.x), dy = Double(middle.y - focus.y)
            return (dx * dx + dy * dy, index, real)
        }.sorted { ($0.distance, $0.index) < ($1.distance, $1.index) }.map(\.real)
    }

    /// The nearest of ``realCablewayOffers``, or `nil`.
    public var realCablewayOffer: RealCableway? {
        realCablewayOffers.first
    }

    /// Draws `real` (one of ``realCablewayOffers``) as the mode's stops, with its
    /// real spans, for the action button to build.
    public func traceRealCableway(_ real: RealCableway) {
        guard let stops = real.stops(in: world) else { return }
        cablewayDraft = stops
        cablewayDraftLegs = real.legMetres
        cablewayDraftMeets = real.meetsNear(in: world)
        cablewayDraftKind = real.kind == .aerial ? nil : real.kind
        lookAt(stops[stops.count / 2].cell.middle)
    }

    // MARK: - Building

    /// What the stops picked would build; `nil` until there are two.
    public var cablewayPreview: CablewayPreview? {
        guard cablewayDraft.count >= 2 else { return nil }
        let key = CablewayPreviewKey(stops: cablewayDraft, legs: cablewayDraftLegs, meets: cablewayDraftMeets, kind: cablewayDraftKind,
                                     balance: world.economy.balance, cableways: world.cableways.count)
        if let memo = cablewayPreviewMemo, memo.key == key { return memo.preview }
        var copy = world
        let preview: CablewayPreview
        do throws(GameError) {
            let built = try copy.createCableway(stops: cablewayDraft, legMetres: cablewayDraftLegs, meetsNear: cablewayDraftMeets,
                                                kind: cablewayDraftKind ?? .aerial)
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
        let command = PlayerCommand.Edit.createCableway(stops: cablewayDraft, legMetres: cablewayDraftLegs, meetsNear: cablewayDraftMeets,
                                                        kind: cablewayDraftKind)
        let done = perform(command) { _, before, after in
            let price = before.economy.balance - after.economy.balance
            let name = after.cableways.last.map { CablewayText.name($0, in: language) } ?? ""
            return language.text("\(name) now runs, for \(price.moneyText).", "\(name)開通了，花費 \(price.moneyText)。")
        }
        guard done != nil else { return false }
        cablewayDraft = []
        cablewayDraftLegs = nil
        cablewayDraftMeets = nil
        cablewayDraftKind = nil
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
        let hourly = cableway.kind.hourlyCapacity
        rows.append(language.text(
            "\(hourly.groupedText) people an hour each way · \(Cableway.fare.moneyText) a ride",
            "單向每小時 \(hourly.groupedText) 人 · 每人 \(Cableway.fare.moneyText)"
        ))
        let hours = "\(CablewayText.clock(cableway.kind.opens(onDay: today)))–\(CablewayText.clock(cableway.kind.closes(onDay: today)))"
        rows.append(open
            ? language.text("Runs today, \(hours)", "今天營運 \(hours)")
            : language.text("Stands still today: \(closedReason(cableway, onDay: today).english)", "今天停駛：\(closedReason(cableway, onDay: today).chinese)"))
        if let station = cableway.transfer.flatMap({ world.station(id: $0.station) }) {
            rows.append(language.text("Meets \(station.name) station", "接 \(station.name)站"))
        }
        // Decision 880: whose visitors come for the ride, or that no one
        // has a reason to.
        let sights = world.sights(ofCableway: id)
        if !sights.isEmpty {
            let shown = sights.prefix(3)
            let more = sights.count - shown.count
            rows.append(language.text(
                "Visitors of \(shown.map(\.englishName).joined(separator: ", "))\(more > 0 ? " and \(more) more" : "") ride it",
                "\(shown.map(\.name).joined(separator: "、"))\(more > 0 ? "等 \(sights.count) 個景點" : "")的遊客會來搭"
            ))
        } else if cableway.transfer == nil, cableway.localTrips == 0 {
            rows.append(language.text(
                "No station or sight nearby: few will ride it", "附近沒有車站，也沒有景點：搭的人會很少"
            ))
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
        return CablewayCard(id: id, title: CablewayText.name(cableway, in: language), rows: rows, runs: open)
    }

    /// Why cable car `cableway` stands still on `day`, as GameCore's
    /// ``GameWorld/cablewayIsOpen(_:onDay:)`` checks it.
    private func closedReason(_ cableway: Cableway, onDay day: Int64) -> (english: String, chinese: String) {
        if cableway.kind.restsOnMonday, StationDemand.weekday(ofDay: day) == 1, world.holiday(onDay: day) == nil {
            return ("Monday maintenance", "週一例行保養")
        }
        if cableway.kind.stopsInThunderstorms, world.weather(onDay: day, atCableway: cableway.id) == .thunderstorm { return ("thunderstorm", "雷雨") }
        return ("typhoon", "颱風")
    }
}

/// What the preview was worked out from (``GameSession/cablewayPreview``).
struct CablewayPreviewKey: Hashable {
    let stops: [CablewayStop]
    let legs: [Int64]?
    let meets: PlanPoint?
    let kind: Cableway.Kind?
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

    /// Decision 1040: `cableway`'s name: a gondola's ``name(_:in:)``, a
    /// funicular's "Funicular 1" / "纜索鐵路 1".
    public static func name(_ cableway: Cableway, in language: DisplayLanguage) -> String {
        guard cableway.kind == .funicular else { return name(cableway.id, in: language) }
        return language.text("Funicular \(cableway.id.rawValue)", "纜索鐵路 \(cableway.id.rawValue)")
    }

    /// Decision 1040: second `second` of a day as "7:30" or "23:00".
    static func clock(_ second: Int64) -> String {
        let minutes = second / 60
        return "\(minutes / 60):\(minutes % 60 < 10 ? "0" : "")\(minutes % 60)"
    }

    /// "4 stations · 4,033 m · 17 min end to end".
    public static func summary(stations: Int, metres: Int64, minutes: Int64, in language: DisplayLanguage) -> String {
        language.text(
            "\(stations) stations · \(metres.groupedText) m · \(minutes) min end to end",
            "\(stations) 站 · \(metres.groupedText) 公尺 · 全程 \(minutes) 分"
        )
    }
}
