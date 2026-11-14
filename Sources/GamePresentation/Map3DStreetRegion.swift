import GameCore

// Decision 732: the 3D map's streets follow the place the map is of. Until
// then every street was Taiwan's (traffic on the right, the animated
// little green man and its countdown, the scooter boxes, red kerbs), on
// Hong Kong's map (decision 697) too. Hong Kong drives on the left, its
// signals show red and amber together before green, and its pedestrian
// signals are a standing red man and a walking green one that flashes
// before red, with no countdown (the Transport Department's Road Users'
// Code, chapters 2 and 8; a countdown is only on trial at a few crossings,
// LCQ13 of 23 July 2025). Only what is drawn changes: GameCore has no road
// traffic of its own, and the region comes from the map, so no save
// records it.

/// Whose streets the 3D map draws.
public enum Map3DStreetRegion: Sendable, Equatable {
    case taiwan
    case hongKong

    /// The region of `world`'s map: Hong Kong for a map anchored in Hong
    /// Kong (the map pack's, ``OverseasMap/hongKong``), else Taiwan (a map
    /// with no anchor, the generated ones, too).
    public init(world: GameWorld) {
        self = world.geoAnchor.map(Self.init(anchor:)) ?? .taiwan
    }

    /// The region round `anchor`: Hong Kong within 22.1–22.6° N and
    /// 113.8–114.5° E, which holds the whole territory and none of
    /// Taiwan (Kinmen is at 118.3° E).
    init(anchor: GeoAnchor) {
        let hongKong = 221_000_000...226_000_000 ~= anchor.latitude && 1_138_000_000...1_145_000_000 ~= anchor.longitude
        self = hongKong ? .hongKong : .taiwan
    }

    /// Whether its road traffic keeps to the left.
    public var keepsLeft: Bool { self == .hongKong }

    /// Which way across a road its traffic keeps from the middle, as a
    /// multiple of the way to the right: 1 in Taiwan, −1 in Hong Kong.
    public var trafficSide: Float { keepsLeft ? -1 : 1 }

    /// Whether its roads have scooter boxes and two-stage turn boxes
    /// (decision 447's 機車停等區 and 機車待轉區): Taiwan's alone.
    var hasScooterBoxes: Bool { self == .taiwan }

    /// Whether its kerbs are painted red where no stopping is allowed
    /// (decision 447): Taiwan's. Hong Kong's are yellow.
    var hasRedKerbs: Bool { self == .taiwan }

    /// Whether its lanes have a painted green walkway (decision 447,
    /// continued): Taipei's, not Hong Kong's.
    var hasPaintedWalkways: Bool { self == .taiwan }

    /// Whether the lines between its two ways of traffic are yellow
    /// (decision 241): Taiwan's. Hong Kong's are white.
    var hasYellowCentreLines: Bool { self == .taiwan }

    /// Whether its pedestrian signals count down and walk the figure
    /// (decision 445): Taiwan's. Hong Kong's green man stands still and
    /// flashes, with no countdown.
    public var animatesPedestrianSignals: Bool { self == .taiwan }

    /// Whether its signals show red and amber together before green.
    public var hasRedAmber: Bool { self == .hongKong }
}
