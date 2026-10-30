import GameCore

// Decision 510 (a player's report, 2026-10-30: "too much UI, sights and
// warnings, easy to tap by mistake"): what floats over the 2D map is held
// to what the player needs at that zoom, and a tap reaches what the player
// meant. Three rules, worked out here for Linux tests; the app only draws.
//
// - Sights: none from far, a star from the middle zoom, a star and its
//   rating close up; a sight's mark over a station or a track shows faint
//   and takes no touch, so the tap goes through to the station or track.
// - Warnings: one bubble per station (the most urgent, "+1" for more), a
//   few on the map at once by urgency, and the rest behind one badge that
//   opens their list. A sight's "no station" warning is not repeated over
//   a sight whose own mark already shows.
// - Taps: a station's or a track's area wins over a sight's mark, and a
//   warning bubble over a sight (the bubbles are drawn over the marks).
//
// The references float no marks on a map to port (decision 250); SimCity
// BuildIt's bubbles and Unciv's notices folded to an edge are where the
// badge comes from (decision 109's sources).

public enum MapClutter {
    // MARK: - Sights

    /// How a sight's mark is drawn at a zoom.
    public enum SightStyle: Hashable, Sendable {
        /// Not at all: too far out, where the stations crowd together.
        case none
        /// A star alone.
        case star
        /// A star and its rating ("3.75★").
        case rated
    }

    /// The style at ``MapCamera/referenceSize`` `referenceSize`: the zooms
    /// of the map's problems (``MapProblems/level(referenceSize:)``).
    public static func sightStyle(referenceSize: Double) -> SightStyle {
        switch MapProblems.level(referenceSize: referenceSize) {
        case .hidden: .none
        case .medium: .star
        case .full: .rated
        }
    }

    /// About a star-alone mark's size, with a little room round it.
    public static let starWidth: Double = 30
    public static let starHeight: Double = 26

    /// How near, in screen points, a station's middle keeps a sight's mark
    /// from taking a touch: a tap's reach on the map
    /// (``NetworkBuilding/touchRadius``).
    public static let stationGuard = NetworkBuilding.touchRadius

    /// Whether a sight's mark at `point` takes touches: not within
    /// ``stationGuard`` of a station's middle in `stations`, not on a
    /// track (`onTrack`), and not where a warning bubble's touch area in
    /// `bubbles` is. Otherwise it shows faint and a tap goes through.
    public static func sightTakesTouch(at point: ScreenPoint, stations: [ScreenPoint], bubbles: [MapLabelPlacement.Box],
                                       onTrack: Bool) -> Bool {
        guard !onTrack else { return false }
        if stations.contains(where: { ($0.x - point.x) * ($0.x - point.x) + ($0.y - point.y) * ($0.y - point.y) < stationGuard * stationGuard }) { return false }
        let mark = MapLabelPlacement.Box(x: point.x - starWidth / 2, y: point.y - starHeight / 2, width: starWidth, height: starHeight)
        return !bubbles.contains { $0.overlaps(mark, gap: 0) }
    }

    // MARK: - Warnings

    /// How urgent an alert is, the most urgent first: a challenge about to
    /// be lost, a train that cannot move, passengers turned away, a line
    /// nobody rides, a crowded station, money lost, a town short of
    /// materials, a sight with no station.
    public static func urgency(_ kind: MapAlert.Kind) -> Int {
        switch kind {
        case .insolvency: 0
        case .trainStuck: 1
        case .full: 2
        case .lineWithoutTrains: 3
        case .crowded: 4
        case .lineLosingMoney: 5
        case .materialsShort: 6
        case .sightWithoutStation: 7
        }
    }

    /// The most bubbles on the map at once at a zoom; the rest are behind
    /// the badge.
    public static func bubbleLimit(_ level: MapProblems.Level) -> Int {
        switch level {
        case .hidden: 2
        case .medium: 3
        case .full: 5
        }
    }

    /// One place's bubble: the most urgent of the alerts over it, and how
    /// many more there are.
    public struct Group: Equatable, Sendable {
        /// The alerts over one place, the most urgent first.
        public let bubbles: [MapMarks.Bubble]

        public var top: MapMarks.Bubble { bubbles[0] }
        /// The alerts the bubble does not name.
        public var more: Int { bubbles.count - 1 }
    }

    /// What the map shows of `bubbles`: the groups whose bubbles go on the
    /// map (at most `limit`, the most urgent first, then in the world's
    /// order), and every alert behind the badge (those of the groups left
    /// off, and each group's others), the most urgent first. A sight's
    /// warning is dropped where `markedSights` already marks the sight.
    public static func arrange(_ bubbles: [MapMarks.Bubble], markedSights: Set<AttractionID>, limit: Int)
        -> (onMap: [Group], folded: [MapMarks.Bubble]) {
        var order: [Place] = []
        var byPlace: [Place: [MapMarks.Bubble]] = [:]
        for bubble in bubbles {
            if case .sightWithoutStation(let sight) = bubble.alert.kind, markedSights.contains(sight) { continue }
            let place = Place(bubble.alert)
            if byPlace[place] == nil { order.append(place) }
            byPlace[place, default: []].append(bubble)
        }
        let groups = order.enumerated().map { index, place in
            (index, Group(bubbles: byPlace[place]!.enumerated()
                .sorted { (urgency($0.element.alert.kind), $0.offset) < (urgency($1.element.alert.kind), $1.offset) }
                .map(\.element)))
        }
        .sorted { (urgency($0.1.top.alert.kind), $0.0) < (urgency($1.1.top.alert.kind), $1.0) }
        .map(\.1)
        let onMap = Array(groups.prefix(max(0, limit)))
        let folded = (onMap.flatMap { $0.bubbles.dropFirst() } + groups.dropFirst(onMap.count).flatMap(\.bubbles))
            .enumerated()
            .sorted { (urgency($0.element.alert.kind), $0.offset) < (urgency($1.element.alert.kind), $1.offset) }
            .map(\.element)
        return (onMap, folded)
    }

    /// Where an alert stands: its station's, or a train's or a sight's own
    /// point.
    private struct Place: Hashable {
        let station: StationID?
        let x: Int64?
        let y: Int64?

        init(_ alert: MapAlert) {
            station = alert.station
            x = alert.station == nil ? alert.location.x : nil
            y = alert.station == nil ? alert.location.y : nil
        }
    }

    /// The badge's words, "3 alerts", for VoiceOver and the list's title.
    public static func badgeText(_ count: Int, in language: DisplayLanguage) -> String {
        language.text(count == 1 ? "1 alert" : "\(count) alerts", "\(count) 則提醒")
    }

    /// What a bubble that names one of several alerts adds: "+2".
    public static func moreText(_ more: Int) -> String {
        "+\(more)"
    }
}
