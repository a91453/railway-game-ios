import GameCore

// ARCHITECTURE decision 201, later: a one-time card about track numbers and
// routes. The owner chose (NEXT_PRIORITIES Q21, 2026-10-13) to add no
// advanced tutorial chapter; the card comes when the player first needs it:
// when a line first gets double track between two of its stops (two
// separate tracks, ``GameWorld/parallelTracks(between:and:)``: its trains
// can take one or the other), or when the player first sees the line
// panel's route menus. A passing loop between stations joins them by one
// track at its ends, so it does not count; the route menus bring the card
// up for it. Seen once, it never comes
// again: the device keeps that, not the save.

/// The one-time card about track numbers and routes (decision 201, later).
public enum RouteHint {
    /// The device's setting that says the card has been seen
    /// (`@AppStorage`).
    public static let seenKey = "hints.routesAndTrackNumbers.seen"

    /// What brought the card up.
    public enum Trigger: Hashable, Sendable {
        /// Line `line` now runs a leg where its stops are joined by two
        /// tracks or more: its trains can take one or the other.
        case parallelTrack(LineID)
        /// The line panel's route menus came into view.
        case routeMenus
    }

    /// One leg between consecutive stops of a line: stop `stop` to stop
    /// `stop + 1`.
    public struct Leg: Hashable, Sendable {
        public let line: LineID
        public let stop: Int
    }

    /// The legs of `world`'s lines whose stops are joined by two separate
    /// tracks or more (``GameWorld/lineTrackCounts(_:)``): where a route
    /// choice decides which track the trains take.
    ///
    /// Costs a maximum flow a leg of every line.
    public static func parallelLegs(in world: GameWorld) -> Set<Leg> {
        var legs = Set<Leg>()
        for line in world.lines {
            for (stop, count) in (world.lineTrackCounts(line.id) ?? []).enumerated() where count >= 2 {
                legs.insert(Leg(line: line.id, stop: stop))
            }
        }
        return legs
    }

    public static func title(in language: DisplayLanguage) -> String {
        language.text("Which track does a train take?", "列車會走哪一條軌道？")
    }

    /// What the card says. With a second track, the line it has to look at,
    /// named; the way there through the lines panel's Advanced switch
    /// when it is folded.
    public static func message(_ trigger: Trigger, in world: GameWorld, language: DisplayLanguage, advancedShown: Bool) -> String {
        let numbers = language.text(
            "Every stretch of track has a number (Track #7): tap a track with Select to see it, or zoom in close.",
            "每一段軌道都有編號（軌段 #7）：用「選取」點軌道就看得到，拉近地圖也會標出來。"
        )
        let menus = language.text(
            "In Lines, each leg of a line has a route menu; the map button beside it outlines the path on the map, with arrows the way the trains go and the numbers of the tracks.",
            "在「路線」裡，路線的每一段都有進路選單；按旁邊的地圖按鈕，地圖會框出路徑，箭頭是列車行進的方向，並標出經過的軌段編號。"
        )
        let arrows = language.text(
            "On the map, arrows on a line's colour show a track its trains take one way only.",
            "地圖上路線顏色裡的箭頭，表示那條軌道列車只走一個方向。"
        )
        let advanced = advancedShown ? nil : language.text(
            "The route menus are under Advanced in Lines.",
            "進路選單在「路線」的「進階」裡。"
        )
        switch trigger {
        case .parallelTrack(let id):
            let name = world.line(id: id)?.name ?? ""
            let lead = language.text(
                "\(name) now has two tracks between some stops, so its trains can take one or the other.",
                "\(name) 有幾段現在有兩條軌道，列車可以走其中一條。"
            )
            return ([lead, numbers, menus, arrows] + [advanced].compactMap { $0 }).joined(separator: "\n\n")
        case .routeMenus:
            return [numbers, menus, arrows].joined(separator: "\n\n")
        }
    }

    /// The button that takes the player to the routes: "Show Me", or
    /// `nil` for a card already beside them.
    public static func showButton(_ trigger: Trigger, in language: DisplayLanguage) -> String? {
        switch trigger {
        case .parallelTrack: language.text("Show the Routes", "看進路設定")
        case .routeMenus: nil
        }
    }

    public static func dismissButton(in language: DisplayLanguage) -> String {
        language.text("Got It", "知道了")
    }
}

/// What the card is watched for: the track and the lines' stops, so it is
/// looked for again only after they change (``GameSession/watchRouteHint()``).
public struct RouteHintWatch: Equatable, Sendable {
    let network: RailwayNetwork
    let stops: [[StationID]]

    public init(world: GameWorld) {
        network = world.network
        stops = world.lines.map(\.stops)
    }
}

extension GameSession {
    /// Looks for a leg that has just gained a second track (decision 201,
    /// later): the first time, it only notes the legs there are, so a game
    /// opened with double track already does not bring the card up; after
    /// that, a leg that was not there before does. Not during the tutorial.
    public func watchRouteHint() {
        let legs = RouteHint.parallelLegs(in: world)
        defer { routeHintLegs = legs }
        guard let known = routeHintLegs, tutorial == nil, routeHint == nil else { return }
        if let new = legs.subtracting(known).min(by: { ($0.line, $0.stop) < ($1.line, $1.stop) }) {
            routeHint = .parallelTrack(new.line)
        }
    }

    /// The line panel's route menus came into view: the card, unless the
    /// tutorial is on or another card is waiting.
    public func routeMenusDidAppear() {
        guard tutorial == nil, routeHint == nil else { return }
        routeHint = .routeMenus
    }

    /// The card was answered.
    public func dismissRouteHint() {
        routeHint = nil
    }
}
