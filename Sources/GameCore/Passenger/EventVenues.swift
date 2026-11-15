// Event venues (decision 768, EVENT-VENUES; the owner, 2026-11-15: a
// stadium should be a kind of its own, "since the concerts' boost is all
// there"). A venue is a real stadium, arena, concert hall or exhibition
// hall on the map, put there by the presentation from its catalogue, as the
// festivals' places are (decision 576). Once a passenger line calls at a
// station near one, the demand events of its kind are held there: a crowd
// surge (a concert or a match) at a stadium or an arena, an exhibition at
// an exhibition hall, drawn by the venue's seats. A map with no venue a
// line reaches draws its events by the stations' traffic as before.

/// What a venue holds.
public enum EventVenueKind: String, CaseIterable, Codable, Sendable {
    /// An open stadium or a ballpark, or a domed one (體育場、棒球場、巨蛋):
    /// matches and the largest concerts.
    case stadium
    /// An indoor arena or a concert hall (體育館、小巨蛋、流行音樂中心):
    /// concerts and indoor matches.
    case arena
    /// An exhibition hall (展覽館): exhibitions.
    case exhibitionHall

    /// Whether demand events of `kind` are held at a venue of this kind.
    public func holds(_ kind: DemandEventKind) -> Bool {
        switch (self, kind) {
        case (.stadium, .crowdSurge), (.arena, .crowdSurge), (.exhibitionHall, .exhibition): true
        default: false
        }
    }
}

/// A real venue on the map.
public struct EventVenue: Hashable, Codable, Sendable {
    /// Its key in the presentation's catalogue, which names it.
    public let id: String
    public let kind: EventVenueKind
    public let point: PlanPoint
    /// The people it holds, which weighs how often its events come.
    public let seats: Int64

    public init(id: String, kind: EventVenueKind, point: PlanPoint, seats: Int64) {
        self.id = id
        self.kind = kind
        self.point = point
        self.seats = seats
    }

    /// The most venues a save holds.
    static let maximumCount = 64
    /// The most seats a venue holds.
    static let maximumSeats: Int64 = 200_000
    /// How near a station is to a venue for its crowd to come there: a
    /// festival's reach (1.6 km).
    static var reach: Int64 { FestivalKind.reach }

    var isValid: Bool {
        !id.isEmpty && id.utf8.count <= 64 && (1...Self.maximumSeats).contains(seats)
    }
}

extension GameWorld {
    /// Sets the venues demand events are held at (decision 768). Needs
    /// demand events (``setDemandEvents(seed:)``): without them it does
    /// nothing. Venues outside the map, of no seats or of a key given twice
    /// (the first is kept) are left out, and at most 64 are kept.
    public mutating func setEventVenues(_ venues: [EventVenue]) {
        guard demandEvents != nil else { return }
        var kept: [EventVenue] = []
        var keys: Set<String> = []
        for venue in venues where venue.isValid && (0..<bounds.width).contains(venue.point.x) && (0..<bounds.height).contains(venue.point.y) {
            guard kept.count < EventVenue.maximumCount, keys.insert(venue.id).inserted else { continue }
            kept.append(venue)
        }
        demandEvents?.venues = kept
    }

    /// The station nearest `venue`, within ``EventVenue/reach``, that a
    /// passenger line calls at and that takes passengers, or `nil`.
    func eventVenueStation(_ venue: EventVenue) -> StationID? {
        festivalStations(near: venue.point).first
    }

    /// The venue and station an event of `kind` of draw `draw` is held at:
    /// one of the venues of its kind a line reaches, drawn by their seats,
    /// or `nil` with none.
    func drawEventVenue(_ schedule: DemandEventSchedule, kind: DemandEventKind, draw: Int64) -> (venue: EventVenue, station: StationID)? {
        let reached = schedule.venues.compactMap { venue -> (EventVenue, StationID)? in
            guard venue.kind.holds(kind), let station = eventVenueStation(venue) else { return nil }
            return (venue, station)
        }
        guard !reached.isEmpty else { return nil }
        var pick = schedule.roll("event.\(draw).venue", in: 0...(reached.reduce(0) { $0 + $1.0.seats } - 1))
        for entry in reached {
            if pick < entry.0.seats { return (entry.0, entry.1) }
            pick -= entry.0.seats
        }
        return (reached[0].0, reached[0].1)
    }
}
