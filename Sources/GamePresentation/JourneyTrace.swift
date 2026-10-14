import GameCore

/// Decision 220: the journey trace. Holding a station on the map draws an
/// arc from it to each of the stations it trades the most trips with, at
/// most ``limit``, each as wide as its trips (SC4's Route Query, after the
/// `Ci/` reference's station OD layer: `showStationODForStation` →
/// `renderStationODLayerFromMatrix` with a focus station). Worked out from
/// the world's daily demand (``GameWorld/stationDemandPairs(of:)``), not
/// kept in GameCore or the save: a view of the passengers the world
/// already has.
public struct JourneyTrace: Hashable, Sendable {
    /// One arc: the station at its far end and the trips each day both
    /// ways between it and the traced station.
    public struct Arc: Hashable, Sendable {
        public let station: StationID
        /// Trips from the traced station to ``station`` each day.
        public let outbound: Int64
        /// Trips from ``station`` back to the traced station each day.
        public let inbound: Int64
        /// Its stroke's width in points (``width(of:largest:)``).
        public let width: Double

        public var trips: Int64 { outbound + inbound }
    }

    /// The traced station.
    public let station: StationID
    /// The busiest first (ties to the lower station ID), at most ``limit``.
    public let arcs: [Arc]

    /// The most arcs drawn: the owner's spec (§13, sixth): more than five
    /// crowd round a busy station and stop reading as its main trips.
    public static let limit = 5
    /// The narrowest arc, in points: the reference clamps its widths to
    /// 0.8…6.5; here the floor is 2 so that the fifth arc still shows its
    /// white edge on a phone.
    public static let narrowest = 2.0

    /// The ``limit`` busiest of `pairs` (both ways added; the reference
    /// draws each way as its own line, here they would lie on one another)
    /// with any trips at all.
    public init(station: StationID, pairs: [StationDemandPair]) {
        self.station = station
        let busiest = pairs
            .filter { $0.outbound + $0.inbound > 0 }
            .sorted { lhs, rhs in
                let left = lhs.outbound + lhs.inbound, right = rhs.outbound + rhs.inbound
                return left != right ? left > right : lhs.station.rawValue < rhs.station.rawValue
            }
            .prefix(Self.limit)
        let largest = busiest.first.map { $0.outbound + $0.inbound } ?? 0
        arcs = busiest.map {
            Arc(station: $0.station, outbound: $0.outbound, inbound: $0.inbound,
                width: Self.width(of: $0.outbound + $0.inbound, largest: largest))
        }
    }

    /// The width of an arc of `trips` when the busiest has `largest`: the
    /// reference's `0.8 + 5.5 × trips / largest`, at least ``narrowest``.
    public static func width(of trips: Int64, largest: Int64) -> Double {
        guard largest > 0 else { return narrowest }
        let ratio = min(1, max(0, Double(trips) / Double(largest)))
        return max(narrowest, 0.8 + 5.5 * ratio)
    }

    /// Where the curve from `start` (the traced station) to `end` bends
    /// towards: the control point of a quadratic curve, off the middle of
    /// the chord by ``bend`` of its length, to the chord's left as it goes
    /// on the screen (whose y grows down). Every arc of a trace bends the
    /// same way round, so they fan out from the station instead of
    /// crossing, and an arc never lies along the straight track between two
    /// stations.
    public static func control(from start: ScreenPoint, to end: ScreenPoint) -> ScreenPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        return ScreenPoint(x: (start.x + end.x) / 2 + dy * bend, y: (start.y + end.y) / 2 - dx * bend)
    }

    /// How far a curve bends, as a share of its chord.
    public static let bend = 0.2

    /// The point halfway along the curve from `start` to `end`, where its
    /// trips are written (the quadratic's point at t = ½).
    public static func apex(from start: ScreenPoint, to end: ScreenPoint) -> ScreenPoint {
        let control = control(from: start, to: end)
        return ScreenPoint(x: (start.x + 2 * control.x + end.x) / 4, y: (start.y + 2 * control.y + end.y) / 4)
    }

    /// How much of each arc is drawn at `elapsed` seconds after the trace
    /// appeared: drawn out from the station over ``drawDuration`` in
    /// ``drawSteps`` steps (each a redraw of the map's canvas, so few), or
    /// whole at once when the player asks for less motion.
    public static func progress(elapsed: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion, elapsed < drawDuration else { return 1 }
        let step = (max(0, elapsed) / drawDuration * Double(drawSteps)).rounded(.down) + 1
        return min(1, step / Double(drawSteps))
    }

    public static let drawDuration = 0.4
    public static let drawSteps = 8

    /// An arc's trips, as written on it: "1,200".
    public static func tripsText(_ arc: Arc) -> String {
        Money(arc.trips).displayText
    }

    /// What the trace says to VoiceOver: "Busiest trips: Beta 2,000, Gamma
    /// 900 a day"; "最多人往返：Beta 2,000、Gamma 900（每天）". `nil`
    /// without arcs.
    public func summary(in world: GameWorld, language: DisplayLanguage) -> String? {
        guard !arcs.isEmpty else { return nil }
        let names = arcs.map { arc in
            "\(world.station(id: arc.station)?.name ?? "#\(arc.station.rawValue)") \(Self.tripsText(arc))"
        }
        return language.text(
            "Busiest trips: \(names.joined(separator: ", ")) a day",
            "最多人往返：\(names.joined(separator: "、"))（每天）"
        )
    }
}

extension GameWorld {
    /// Station `id`'s journey trace (decision 220): its busiest pairs of
    /// ``stationDemandPairs(of:)``. Searches the whole map with network
    /// routing, so the map works it out off the main actor.
    public func journeyTrace(of id: StationID) -> JourneyTrace {
        JourneyTrace(station: id, pairs: stationDemandPairs(of: id))
    }
}
