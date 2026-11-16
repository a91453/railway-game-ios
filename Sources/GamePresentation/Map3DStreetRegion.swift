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
    /// Decision 802: Finland's (Rovaniemi's map, decision 789): traffic on
    /// the right as Taiwan's, white lines between its two ways (yellow
    /// until the Road Traffic Act of 2020), no paint on its kerbs, no
    /// scooters, and signals that show red and amber before green.
    case finland

    /// The region of `world`'s map: Hong Kong for a map anchored in Hong
    /// Kong (the map pack's, ``OverseasMap/hongKong``), Finland for one
    /// anchored there, else Taiwan (a map with no anchor, the generated
    /// ones, too). Decision 802: ``Map3DRegionLook``'s.
    public init(world: GameWorld) {
        self = Map3DRegionLook(world: world).streets
    }

    /// The region round `anchor` (``Map3DRegionLook/init(anchor:)``).
    init(anchor: GeoAnchor) {
        self = Map3DRegionLook(anchor: anchor).streets
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
    /// Decision 802: Finland's too.
    public var hasRedAmber: Bool { self != .taiwan }

    /// Decision 802: whether its kerbs are painted where no stopping or
    /// waiting is allowed (decision 447): Taiwan's red and yellow, Hong
    /// Kong's yellow. Finland's are bare.
    var hasKerbLines: Bool { self != .finland }

    /// Decision 802: whether scooters ride its streets (decision 259):
    /// not Finland's, under snow.
    var hasScooters: Bool { self != .finland }

    /// Decision 802: whether its taxis are Taiwan's yellow (the last of
    /// ``Map3DStreetLife/carPaints``).
    var hasYellowTaxis: Bool { self == .taiwan }

    /// Decision 802: the pavement beside its roads. Taiwan's and Hong
    /// Kong's the palette's white; Finland's the lots' pale grey paving,
    /// which stands off the snow as the white would not.
    var sidewalk: UInt32 { self == .finland ? Map3DPalette.paved : Map3DPalette.sidewalk }

    /// Decision 743: whether its garbage trucks come round in the evening
    /// playing music (decision 437): Taiwan's.
    public var hasEveningGarbageTrucks: Bool { self == .taiwan }

    /// Decision 743: whether its bus stops have Taiwan's red and green
    /// post boxes beside them (decision 467): Taiwan's.
    var hasTaiwanPostBoxes: Bool { self == .taiwan }
}
