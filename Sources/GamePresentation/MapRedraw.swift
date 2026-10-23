import GameCore

// Decision 371: what of the world each of the flat map's canvases draws,
// so that a tick redraws only the canvases whose part changed. On a map of
// 44 stations with traffic control on, the one canvas of the track, the
// stations and traffic control was drawn again on nearly every tick
// because a train had reserved track further on, and the stations' names
// whenever one more passenger waited.

/// Which parts of the world the flat map's canvases compare (decision 371).
public enum MapRedraw {
    /// The railway canvas: the map's edge, the track, the lines over it
    /// and the catchment rings round the stations.
    public static func sameRailway(_ lhs: GameWorld, _ rhs: GameWorld) -> Bool {
        lhs.bounds == rhs.bounds && lhs.stations == rhs.stations && lhs.network == rhs.network
    }

    /// The canvas over it: traffic control's reserved track and waits, the
    /// city's buildings and the stations (the land too while the building
    /// tool shows its sites, `comparesLand`).
    public static func sameStations(_ lhs: GameWorld, _ rhs: GameWorld, comparesLand: Bool) -> Bool {
        lhs.bounds == rhs.bounds && lhs.stations == rhs.stations && lhs.network == rhs.network
            && lhs.placedBuildings == rhs.placedBuildings && (!comparesLand || lhs.land == rhs.land)
    }

    /// The stations' names, their lines' badges under them, and the
    /// network tool's marks over them; not the waiting counts, which have
    /// a canvas of their own.
    public static func sameNames(_ lhs: GameWorld, _ rhs: GameWorld) -> Bool {
        lhs.stations == rhs.stations
            && lhs.lines.elementsEqual(rhs.lines) { $0.id == $1.id && $0.stops == $1.stops && $0.color == $1.color }
            && lhs.geoAnchor == rhs.geoAnchor
            && lhs.network == rhs.network
    }
}

/// Decision 371: how often the flat map draws its trains between two ticks.
/// A tick moves them every tenth of a second and the map glides them from
/// where they were; drawn at the screen's own rate (60 or 120 times a
/// second) a large map drew every train that often for as long as the game
/// ran, the player not even touching it, and the phone grew hot. A camera
/// following a train glides at the screen's rate up to ``followFramesPerSecond``.
public enum MapGlide {
    /// The trains' (and the real trains') glide and the waits' pulse.
    public static let framesPerSecond = 30.0
    /// The camera following a train, which redraws the whole map.
    public static let followFramesPerSecond = 60.0

    /// The least time between two of the trains' frames, in seconds.
    public static var minimumInterval: Double { 1 / framesPerSecond }
    /// The least time between two frames of a camera following a train.
    public static var followMinimumInterval: Double { 1 / followFramesPerSecond }
}
