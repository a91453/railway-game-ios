import GameCore

// Decision 210 (NEXT_PRIORITIES §0 item 12, §4 item 7): problems seen on
// the map at a middle zoom too, not only close up. The waiting count's
// pill, a ring round a crowded station that fills as it does, and a tag
// beside a waiting train's ring with why it waits: each held to a number
// so the map is not covered. And a crowded station's bubble says why in a
// line under its figure, as the reference's land value
// (`Railway/island_city_reference_clean/source/js/g23.js` `landValueAt`)
// gives its figure, a zone and the largest reasons.
// Worked out here, for Linux tests; the app only draws.

/// What the map shows of the problems of the stations and the trains.
public enum MapProblems {
    /// How much of the problems the map shows at a zoom.
    public enum Level: Hashable, Sendable {
        /// Too far out: only the rings round waiting trains, as before.
        case hidden
        /// Zoomed out (``MapDetail/overview``) near enough to tell the
        /// stations apart: the pills, rings and tags, fewer of them.
        case medium
        /// Close up (``MapDetail/full``).
        case full
    }

    /// From this ``MapCamera/referenceSize`` (16 m on the screen, in
    /// points) up the map shows the problems: half a point, a kilometre
    /// some 31 points, where a city's network fills an iPhone.
    public static let mediumFrom = 0.5

    public static func level(referenceSize: Double) -> Level {
        if MapScale.detail(forReferenceSize: referenceSize) == .full { return .full }
        return referenceSize >= mediumFrom ? .medium : .hidden
    }

    /// The most waiting counts drawn at once at `level`.
    public static func pillLimit(_ level: Level) -> Int {
        switch level {
        case .hidden: 0
        case .medium: 12
        case .full: 30
        }
    }

    /// The most rings round waiting trains drawn at once, and of them the
    /// most with a tag saying why.
    public static let waitMarkLimit = 12
    public static let waitTagLimit = 6

    // MARK: - Stations

    /// How full a station's room for waiting passengers is, by the
    /// thresholds of the map's bubbles (``GameCore/GameWorld/mapAlerts()``):
    /// the same people glyph with more people (art-style §2).
    public enum Crowding: Int, Comparable, Hashable, Sendable {
        case normal, crowded, full

        public static func < (lhs: Crowding, rhs: Crowding) -> Bool { lhs.rawValue < rhs.rawValue }

        public init(waiting: Int64) {
            if waiting >= StationPassengers.capacity {
                self = .full
            } else if waiting * 2 >= StationPassengers.capacity {
                self = .crowded
            } else {
                self = .normal
            }
        }
    }

    /// How much of the room is taken, 0 to 1: how far round the crowded
    /// ring goes.
    public static func fill(waiting: Int64) -> Double {
        min(1, max(0, Double(waiting) / Double(StationPassengers.capacity)))
    }

    /// The stations with passengers waiting, in the order their pills are
    /// placed: full first, then crowded, then the most waiting, then by ID.
    public static func stationOrder(_ counts: [StationID: Int64]) -> [(station: StationID, waiting: Int64)] {
        counts.filter { $0.value > 0 }
            .map { (station: $0.key, waiting: $0.value) }
            .sorted {
                let a = Crowding(waiting: $0.waiting), b = Crowding(waiting: $1.waiting)
                if a != b { return a > b }
                if $0.waiting != $1.waiting { return $0.waiting > $1.waiting }
                return $0.station < $1.station
            }
    }

    /// Marks placed on the screen one by one, in order: one that would
    /// cover one already placed is left out, and so is every one after
    /// the limit (the overview names' rule, decision 89).
    public struct Placement: Sendable {
        public struct Box: Hashable, Sendable {
            public let minX, minY, maxX, maxY: Double

            public init(x: Double, y: Double, width: Double, height: Double) {
                minX = x
                minY = y
                maxX = x + width
                maxY = y + height
            }

            func overlaps(_ other: Box, gap: Double) -> Bool {
                minX - gap < other.maxX && other.minX - gap < maxX && minY - gap < other.maxY && other.minY - gap < maxY
            }
        }

        public let limit: Int
        /// The space kept between two marks, in points.
        public let gap: Double
        public private(set) var placed: [Box] = []

        public init(limit: Int, gap: Double = 2) {
            self.limit = limit
            self.gap = gap
        }

        public var isFull: Bool { placed.count >= limit }

        /// Places `box` and says so, or leaves it out.
        public mutating func place(_ box: Box) -> Bool {
            guard !isFull, !placed.contains(where: { $0.overlaps(box, gap: gap) }) else { return false }
            placed.append(box)
            return true
        }
    }

    // MARK: - Trains

    /// The waiting trains whose rings are drawn, of those `inView`: the
    /// deadlocked first, then by train ID, at most ``waitMarkLimit``. The
    /// first ``waitTagLimit`` of them carry a tag.
    public static func shownWaits(_ waits: [TrafficOverlay.Wait], inView: (TrafficOverlay.Wait) -> Bool) -> [TrafficOverlay.Wait] {
        let seen = waits.filter(inView).sorted {
            if $0.isDeadlocked != $1.isDeadlocked { return $0.isDeadlocked }
            return $0.train < $1.train
        }
        return Array(seen.prefix(waitMarkLimit))
    }

    /// How large a waiting train's ring pulses at `time` seconds, 0 to 1:
    /// once every ``pulseBeat`` seconds a second ring grows out of it and
    /// fades. None when the player reduces motion or the game is paused.
    public static func pulse(at time: Double, reduceMotion: Bool, running: Bool) -> Double? {
        guard !reduceMotion, running else { return nil }
        let phase = time.truncatingRemainder(dividingBy: pulseBeat) / pulseBeat
        return phase < 0 ? phase + 1 : phase
    }

    /// Seconds between two pulses of a waiting train's ring.
    public static let pulseBeat = 1.6
}

// MARK: - Why a station is crowded

/// Why a station's passengers wait (decision 210): the line and way most
/// of them wait for, and how long the first of those has waited, or that
/// the line has no train. The reference's land value says its figure and
/// the largest of its reasons ("近捷運、學校"); this says one.
public struct StationWaitReason: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The line most wait for has no train.
        case noTrains
        /// Most wait for the line, toward `terminus`.
        case waitingFor
    }

    public let kind: Kind
    public let line: LineID
    public let lineName: String
    /// The station the line's way ends at.
    public let terminus: String?
    /// How many of them wait for it.
    public let waiting: Int64
    /// How long the first of them has waited, in whole minutes.
    public let longestMinutes: Int64

    public init(kind: Kind, line: LineID, lineName: String, terminus: String?, waiting: Int64, longestMinutes: Int64) {
        self.kind = kind
        self.line = line
        self.lineName = lineName
        self.terminus = terminus
        self.waiting = waiting
        self.longestMinutes = longestMinutes
    }

    /// "No trains on Red", "紅線沒有列車"; "Most for Red to Taipei · up
    /// to 25 min", "多數等紅線往台北 · 最久 25 分".
    public func text(in language: DisplayLanguage) -> String {
        switch kind {
        case .noTrains:
            return language.text("No trains on \(lineName)", "\(lineName)沒有列車")
        case .waitingFor:
            var text = terminus.map { language.text("Most for \(lineName) to \($0)", "多數等\(lineName)往\($0)") }
                ?? language.text("Most for \(lineName)", "多數等\(lineName)")
            if longestMinutes >= 1 {
                text += language.text(" · up to \(longestMinutes) min", " · 最久 \(longestMinutes) 分")
            }
            return text
        }
    }
}

extension GameWorld {
    /// Why passengers wait at station `id` (decision 210), or `nil` when
    /// none do: of its waiting groups, the line and way most wait for
    /// (the lower line ID, then outbound, on a tie). The first record of
    /// the station, as ``MapLayers/waitingPassengerCounts(in:)`` reads.
    public func stationWaitReason(of id: StationID) -> StationWaitReason? {
        guard let record = passengers.first(where: { $0.station == id }) else { return nil }
        struct Way: Hashable { let line: LineID; let direction: LineDirection }
        var counts: [Way: Int64] = [:]
        var since: [Way: GameTime] = [:]
        for group in record.waiting {
            let way = Way(line: group.line, direction: group.direction)
            counts[way, default: 0] += group.count
            since[way] = min(since[way] ?? group.since, group.since)
        }
        guard let most = counts.max(by: { a, b in
            if a.value != b.value { return a.value < b.value }
            if a.key.line != b.key.line { return a.key.line > b.key.line }
            // The larger is the one named: outbound on a tie.
            return a.key.direction == .inbound && b.key.direction == .outbound
        }), let line = line(id: most.key.line) else { return nil }
        let hasTrains = !line.trains.isEmpty || line.patterns.contains { !$0.trains.isEmpty }
        let end = most.key.direction == .outbound ? line.stops.last : line.stops.first
        let waited = since[most.key].map { max(0, clock.now.seconds - $0.seconds) / 60 } ?? 0
        return StationWaitReason(
            kind: hasTrains ? .waitingFor : .noTrains, line: line.id, lineName: line.name,
            terminus: end.flatMap { station(id: $0)?.name }, waiting: most.value, longestMinutes: waited
        )
    }
}
