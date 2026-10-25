import GameCore

// The network's flow report (decision 416; NEXT_PRIORITIES §22.2 rank 22),
// three lists the section flow layer (decision 178) does not give:
//
// - Lines, ported from the `Ci/` reference's flow dashboard
//   (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
//   `flowDashboardGetLineBarRows` gives each line its previous day's
//   ridership, its route length, the intensity (ridership over length,
//   none under `METRO_LINE_INTENSITY_MIN_KM`, 0.05 km) and its peak trains
//   (`flowDashboardPeakTrains`); `flowDashboardSortLineRows` sorts by one
//   of them, ties by the line.
// - Sections, the busiest stop-to-stop sections of ``SectionFlow``, each
//   at its fullest hour against what its trains carry then.
// - Unmet demand, which the reference has no list of: those waiting long
//   for a train now, those who leave the trains for a scooter, a car or
//   the fare each day (``GameWorld/modeShiftLosses(from:)``), and the
//   pairs of stations with demand that no line joins.
//
// Read from the world, never stored; it costs a line journey each and a
// section flow, so it is worked out off the main thread. Only the world's
// own stations and lines count: the real trains a map draws from
// timetables are not in it.

/// The flow report of a network: its lines, its busiest sections and the
/// demand it leaves unmet (decision 416).
public struct NetworkFlowReport: Equatable, Sendable {
    // MARK: - Lines

    /// What the lines are sorted by (`flowDashboardGetLineBarMetricConfig`).
    public enum LineMetric: String, CaseIterable, Sendable {
        case ridership, length, intensity, peakTrains

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .ridership: language.text("Riders", "客流")
            case .length: language.text("Length", "長度")
            case .intensity: language.text("Intensity", "客流強度")
            case .peakTrains: language.text("Peak trains", "尖峰列車")
            }
        }

        /// What the figures are, under the list.
        public func subtitle(in language: DisplayLanguage) -> String {
            switch self {
            case .ridership: language.text("Riders yesterday, all day", "昨天一整天的搭乘人次")
            case .length: language.text("Route length, one way", "路線單程長度")
            case .intensity: language.text("Riders yesterday per kilometre of route", "昨天每公里路線的搭乘人次")
            case .peakTrains: language.text("Trains in service at the peak", "尖峰時段上線的列車")
            }
        }
    }

    /// One line's figures (`flowDashboardGetLineBarRows`).
    public struct LineRow: Equatable, Sendable, Identifiable {
        public let line: LineID
        public let name: String
        /// Passengers who boarded it yesterday (``GameWorld/lineYesterday(_:)``).
        public let ridership: Int64
        /// Its route, one way (a ring once round), in world units.
        public let length: Int64
        /// Its peak trains, every service's together.
        public let peakTrains: Int

        public var id: LineID { line }

        /// Riders a kilometre of route; `nil` under the reference's 0.05 km.
        public var intensity: Double? {
            let kilometres = Double(length) / Double(NetworkFlowReport.unitsPerKilometre)
            return kilometres >= NetworkFlowReport.shortestIntensityKilometres ? Double(ridership) / kilometres : nil
        }

        /// The row's figure for `metric`, as the list sorts and draws it.
        public func value(_ metric: LineMetric) -> Double {
            switch metric {
            case .ridership: Double(ridership)
            case .length: Double(length)
            case .intensity: intensity ?? 0
            case .peakTrains: Double(peakTrains)
            }
        }

        /// The row's figure for `metric`: "1,234 riders", "12.3 km",
        /// "456 riders/km" or "8 trains".
        public func valueText(_ metric: LineMetric, in language: DisplayLanguage) -> String {
            switch metric {
            case .ridership:
                let count = Money(ridership).displayText
                return language.text("\(count) riders", "\(count) 人次")
            case .length:
                let km = WorldBounds.kilometresText(length)
                return language.text("\(km) km", "\(km) 公里")
            case .intensity:
                guard let intensity else { return "—" }
                let count = Money(Int64(intensity.rounded())).displayText
                return language.text("\(count) riders/km", "\(count) 人次／公里")
            case .peakTrains:
                return language.text(peakTrains == 1 ? "1 train" : "\(peakTrains) trains", "\(peakTrains) 列")
            }
        }
    }

    // MARK: - Sections

    /// One stop-to-stop section at its fullest hour.
    public struct SectionRow: Equatable, Sendable, Identifiable {
        /// Its index in the report's ``SectionFlow``.
        public let section: Int
        public let from: StationID
        public let to: StationID
        public let lines: [LineID]
        /// The hour it is fullest: of its load against its capacity, the
        /// largest load when nothing carries it; the earlier on a tie.
        public let hour: Int
        public let load: Int64
        public let capacity: Int64
        /// Load as a whole percent of capacity; `nil` with no trains.
        public let percent: Int?
        /// Its passengers all day.
        public let dailyLoad: Int64

        public var id: Int { section }
        /// Whether more ride it than its trains carry.
        public var isOverloaded: Bool { percent.map { $0 > 100 } ?? (load > 0) }
    }

    // MARK: - Unmet demand

    /// The kinds of demand the network leaves unmet.
    public enum UnmetKind: String, CaseIterable, Sendable {
        /// Waiting at least ``longWaitSeconds`` for a train now.
        case waiting
        /// Left the trains each day for a scooter, a car or the fare.
        case lost
        /// Pairs of stations with demand no line joins.
        case unconnected

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .waiting: language.text("Waiting long", "等不到車")
            case .lost: language.text("Gone elsewhere", "流失")
            case .unconnected: language.text("No line between", "沒有路線連")
            }
        }

        public func subtitle(in language: DisplayLanguage) -> String {
            switch self {
            case .waiting:
                language.text("Waiting half an hour or more now, by where they are going.", "現在等了半小時以上的人，照要去的站分。")
            case .lost:
                language.text("Trips a day that took a scooter or a car, or found the fare too high.", "每天改騎機車、開車，或嫌票價太貴的人次。")
            case .unconnected:
                language.text("Trips a day these stations could share if a line joined them.", "如果有路線連起來，兩站之間每天大約的人次。")
            }
        }

        public func emptyText(in language: DisplayLanguage) -> String {
            switch self {
            case .waiting: language.text("Nobody has waited long.", "沒有人等很久。")
            case .lost: language.text("Nobody leaves the trains.", "沒有流失的乘客。")
            case .unconnected: language.text("Every station with riders is joined.", "有乘客的車站都連起來了。")
            }
        }
    }

    /// A pair of stations whose demand goes unmet.
    public struct UnmetRow: Equatable, Sendable, Identifiable {
        public let kind: UnmetKind
        /// Where they are (waiting), or set out from; for a pair counted
        /// both ways, the lower station ID.
        public let from: StationID
        public let to: StationID
        /// How many: waiting now, or trips a day.
        public let people: Int64
        /// Whether `people` counts both ways (unconnected pairs).
        public let bothWays: Bool
        /// The longest any of them has waited, in minutes (waiting only).
        public let longestWaitMinutes: Int64?

        public var id: String { "\(kind.rawValue)-\(from.rawValue)-\(to.rawValue)" }

        /// "Alpha → Beta" (or "Alpha ↔ Beta" both ways).
        public func title(in world: GameWorld) -> String {
            let a = world.station(id: from)?.name ?? "", b = world.station(id: to)?.name ?? ""
            return bothWays ? "\(a) ↔ \(b)" : "\(a) → \(b)"
        }

        public func valueText(in language: DisplayLanguage) -> String {
            let count = Money(people).displayText
            switch kind {
            case .waiting:
                let minutes = longestWaitMinutes ?? 0
                return language.text("\(count) waiting · up to \(minutes) min", "\(count) 人等 · 最久 \(minutes) 分")
            case .lost:
                return language.text("\(count) a day", "每天 \(count) 人次")
            case .unconnected:
                return language.text("about \(count) a day", "每天約 \(count) 人次")
            }
        }
    }

    /// The report's three pages, in order.
    public enum Page: String, CaseIterable, Sendable {
        case lines, sections, unmet

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .lines: language.text("Lines", "路線")
            case .sections: language.text("Busiest", "最擠區間")
            case .unmet: language.text("Unmet", "未滿足需求")
            }
        }
    }

    // MARK: - Constants

    /// World units in a kilometre.
    public static let unitsPerKilometre: Int64 = 1_000 * WorldCoordinate.unitsPerMetre
    /// The reference's `METRO_LINE_INTENSITY_MIN_KM`.
    public static let shortestIntensityKilometres = 0.05
    /// How long a wait counts as long: half an hour.
    public static let longWaitSeconds: Int64 = 1_800
    /// How many rows each list keeps.
    public static let rowsShown = 10

    // MARK: - The report

    /// Whether the world keeps a passenger plan (the sections need one).
    public let hasPlan: Bool
    /// The lines, by ID; sort them with ``lines(sortedBy:descending:)``.
    public let lines: [LineRow]
    /// The fullest sections first, at most ``rowsShown``.
    public let sections: [SectionRow]
    /// Each kind's pairs, the most people first, at most ``rowsShown``.
    public let unmet: [UnmetKind: [UnmetRow]]

    public init(hasPlan: Bool = false, lines: [LineRow] = [], sections: [SectionRow] = [], unmet: [UnmetKind: [UnmetRow]] = [:]) {
        self.hasPlan = hasPlan
        self.lines = lines
        self.sections = sections
        self.unmet = unmet
    }

    /// The lines sorted by `metric` (`flowDashboardSortLineRows`), the
    /// largest first unless `descending` is false; ties by line ID.
    public func lines(sortedBy metric: LineMetric, descending: Bool = true) -> [LineRow] {
        lines.sorted { a, b in
            let x = a.value(metric), y = b.value(metric)
            if x != y { return descending ? x > y : x < y }
            return a.line < b.line
        }
    }

    public func unmet(_ kind: UnmetKind) -> [UnmetRow] { unmet[kind] ?? [] }

    /// Whether there is nothing at all to show: no line and no station
    /// with unmet demand.
    public var isEmpty: Bool { lines.isEmpty && sections.isEmpty && unmet.values.allSatisfy(\.isEmpty) }
}

// MARK: - From the world

extension NetworkFlowReport {
    /// The report of `world` now. Costs a journey a line, a section flow
    /// and a pass over the stations' demand: run it off the main thread.
    public init(world: GameWorld) {
        self.init(world: world, flow: SectionFlow(world: world))
    }

    /// The report with the section flow already worked out.
    public init(world: GameWorld, flow: SectionFlow) {
        self.init(
            hasPlan: flow.hasPlan,
            lines: Self.lineRows(of: world),
            sections: Self.sectionRows(of: flow),
            unmet: [
                .waiting: Self.waitingRows(of: world),
                .lost: Self.lostRows(of: world),
                .unconnected: Self.unconnectedRows(of: world),
            ]
        )
    }

    /// Every passenger line's figures (`flowDashboardGetLineBarRows`),
    /// by line ID. Its length is its journey's legs out (a ring's whole
    /// lap), as the company's fixed assets measure it.
    static func lineRows(of world: GameWorld) -> [LineRow] {
        world.lines.filter { !$0.isFreight }.map { line in
            var length: Int64 = 0
            if let journey = world.lineJourney(line.id) {
                let route = journey.isRing ? journey.legs[...] : journey.legs.prefix(journey.legs.count / 2)
                length = route.reduce(0) { $0 + $1.path.distance }
            }
            let peak = line.trainsInService.peak + line.patterns.reduce(0) { $0 + $1.trainsInService.peak }
            return LineRow(line: line.id, name: line.name, ridership: world.lineYesterday(line.id)?.boardings ?? 0,
                           length: length, peakTrains: peak)
        }.sorted { $0.line < $1.line }
    }

    /// The sections at their fullest hours, the fullest first: any load
    /// with no trains, then by percent, then by load, then by the
    /// section's order. Sections nobody rides are left out.
    static func sectionRows(of flow: SectionFlow) -> [SectionRow] {
        var rows: [(ratio: Double, row: SectionRow)] = []
        for (index, section) in flow.sections.enumerated() {
            var best: (hour: Int, ratio: Double)?
            for hour in 0..<24 where section.loads[hour] > 0 {
                let ratio = section.ratio(at: hour) ?? 0
                if best == nil || ratio > best!.ratio
                    || (ratio == best!.ratio && section.loads[hour] > section.loads[best!.hour]) {
                    best = (hour, ratio)
                }
            }
            guard let best else { continue }
            let reading = flow.reading(of: index, at: best.hour)
            rows.append((best.ratio, SectionRow(
                section: index, from: section.from, to: section.to, lines: section.lines, hour: best.hour,
                load: section.loads[best.hour], capacity: section.capacities[best.hour], percent: reading?.percent,
                dailyLoad: section.loads.reduce(0, +))))
        }
        rows.sort { a, b in
            if a.ratio != b.ratio { return a.ratio > b.ratio }
            if a.row.load != b.row.load { return a.row.load > b.row.load }
            return a.row.section < b.row.section
        }
        return rows.prefix(rowsShown).map(\.row)
    }

    /// Those waiting at least ``longWaitSeconds`` now, by the station
    /// they wait at and where they are going.
    static func waitingRows(of world: GameWorld) -> [UnmetRow] {
        let now = world.clock.now.seconds
        var rows: [UnmetRow] = []
        for station in world.stations {
            var groups: [StationID: (count: Int64, longest: Int64)] = [:]
            for group in world.waitingPassengers(at: station.id) {
                let waited = now - group.since.seconds
                guard waited >= longWaitSeconds else { continue }
                let entry = groups[group.destination] ?? (0, 0)
                groups[group.destination] = (entry.count + group.count, max(entry.longest, waited))
            }
            for (destination, entry) in groups {
                rows.append(UnmetRow(kind: .waiting, from: station.id, to: destination, people: entry.count,
                                     bothWays: false, longestWaitMinutes: entry.longest / 60))
            }
        }
        return ranked(rows)
    }

    /// The trips a day that left the trains between each pair, one way.
    static func lostRows(of world: GameWorld) -> [UnmetRow] {
        var rows: [UnmetRow] = []
        for station in world.stations {
            for loss in world.modeShiftLosses(from: station.id) where loss.switched + loss.tooExpensive > 0 {
                rows.append(UnmetRow(kind: .lost, from: station.id, to: loss.destination,
                                     people: loss.switched + loss.tooExpensive, bothWays: false, longestWaitMinutes: nil))
            }
        }
        return ranked(rows)
    }

    /// Pairs of open stations with demand that no line joins, both ways,
    /// with the trips a day they would share: each station's trips shared
    /// among every other station with demand in proportion to their own,
    /// as the world shares them among the stations it reaches
    /// (``GameWorld/dailyDemand(from:to:)``), before the distance, the
    /// fare and the events. Two stations are joined when a passenger line
    /// calls at both; in a network game also through a change of trains,
    /// at a station or by a walk (``GameWorld/walkingTransfer(from:to:)``).
    static func unconnectedRows(of world: GameWorld) -> [UnmetRow] {
        let open = world.stations.filter { $0.operationMode != .closed }
        var trips: [StationID: Int64] = [:]
        for station in open {
            if let demand = world.stationDemand(of: station.id), demand.dailyTrips > 0 {
                trips[station.id] = demand.dailyTrips
            }
        }
        let ids = trips.keys.sorted()
        guard ids.count >= 2 else { return [] }
        let total = trips.values.reduce(0, +)
        let passenger = world.lines.filter { !$0.isFreight }

        let joined: (StationID, StationID) -> Bool
        if world.passengerRoutingMode == .network {
            var parent: [StationID: StationID] = [:]
            func root(_ id: StationID) -> StationID {
                var id = id
                while let up = parent[id], up != id { id = up }
                return id
            }
            func join(_ a: StationID, _ b: StationID) {
                let x = root(a), y = root(b)
                if x != y { parent[max(x, y)] = min(x, y) }
            }
            for line in passenger {
                for stop in line.stops.dropFirst() { join(line.stops[0], stop) }
            }
            let served = Set(passenger.flatMap(\.stops)).sorted()
            for (index, a) in served.enumerated() {
                for b in served[(index + 1)...] where world.walkingTransfer(from: a, to: b) != nil { join(a, b) }
            }
            joined = { root($0) == root($1) }
        } else {
            joined = { a, b in passenger.contains { $0.stops.contains(a) && $0.stops.contains(b) } }
        }

        func share(from origin: StationID, to destination: StationID) -> Int64 {
            let others = total - trips[origin]!
            guard others > 0 else { return 0 }
            return (trips[origin]! * trips[destination]! + others / 2) / others
        }
        var rows: [UnmetRow] = []
        for (index, a) in ids.enumerated() {
            for b in ids[(index + 1)...] where !joined(a, b) {
                let people = share(from: a, to: b) + share(from: b, to: a)
                guard people > 0 else { continue }
                rows.append(UnmetRow(kind: .unconnected, from: a, to: b, people: people, bothWays: true, longestWaitMinutes: nil))
            }
        }
        return ranked(rows)
    }

    /// The most people first; ties by the station they set out from, then
    /// where they are going. At most ``rowsShown``.
    static func ranked(_ rows: [UnmetRow]) -> [UnmetRow] {
        Array(rows.sorted { a, b in
            if a.people != b.people { return a.people > b.people }
            if a.from != b.from { return a.from < b.from }
            return a.to < b.to
        }.prefix(rowsShown))
    }
}

// MARK: - On the map

extension NetworkFlowReport {
    /// The part of the map that shows stations `a` and `b` (a section or
    /// a pair), with a margin round them; `nil` when either is gone.
    public static func region(from a: StationID, to b: StationID, in world: GameWorld) -> WorldRegion? {
        guard let p = world.station(id: a)?.location, let q = world.station(id: b)?.location else { return nil }
        let minX = Double(min(p.x, q.x)), maxX = Double(max(p.x, q.x))
        let minY = Double(min(p.y, q.y)), maxY = Double(max(p.y, q.y))
        let margin = max(max(maxX - minX, maxY - minY) * 0.2, Double(500 * WorldCoordinate.unitsPerMetre))
        return WorldRegion(minX: minX - margin, minY: minY - margin, maxX: maxX + margin, maxY: maxY + margin)
    }

    /// "Alpha → Beta" for a section.
    public static func title(of row: SectionRow, in world: GameWorld) -> String {
        "\(world.station(id: row.from)?.name ?? "") → \(world.station(id: row.to)?.name ?? "")"
    }

    /// A section's figures: "08:00 · 3,240 / 2,800 (116%)", or "no trains"
    /// with no capacity.
    public static func valueText(of row: SectionRow, in language: DisplayLanguage) -> String {
        let hour = SectionFlow.hourText(row.hour)
        let load = Money(row.load).displayText
        guard let percent = row.percent else {
            return language.text("\(hour) · \(load) riders, no trains", "\(hour) · \(load) 人，沒有列車")
        }
        let capacity = Money(row.capacity).displayText
        return language.text("\(hour) · \(load) / \(capacity) seats (\(percent)%)", "\(hour) · \(load) 人／運能 \(capacity)（\(percent)%）")
    }

    public static func title(in language: DisplayLanguage) -> String {
        language.text("Network Flow", "路網分析")
    }
}

extension GameSession {
    /// Whether the lines panel offers the flow report (decision 416): once
    /// a passenger line is made, not in the tutorial or a lesson, whose
    /// steps would be left behind under it.
    public var showsNetworkFlowReport: Bool {
        world.lines.contains { !$0.isFreight } && tutorial == nil && lesson == nil
    }

    /// Shows a section or a pair of stations whole on the map (decision 416).
    public func lookOver(from a: StationID, to b: StationID) {
        guard let region = NetworkFlowReport.region(from: a, to: b, in: world) else { return }
        lookOver(region)
    }
}
