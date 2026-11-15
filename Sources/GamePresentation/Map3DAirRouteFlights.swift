import Foundation
import GameCore

// Decision 771 (AIR-A4): the company's air routes (decision 758) on the 3D
// map. Each route's aircraft land and leave at the minutes its day's plan
// gives (``GameWorld/airRouteDepartureMinutes(_:)``), of the size the
// player chose and in the company's livery; they are taken out of the
// airport's own flights of that hour (they were among them: a route keeps
// real flights), so an airport is no busier for being flown by the company.
// A route's aircraft climbs on to its cruise's start, 3,000 m up, turning
// on the way towards where it flies; the camera follows it there, and then
// the flight window (``AirFlightWindow``) shows the rest of its flight.
//
// Both ends of a route fly at the same minutes: each departure has a
// flight out from its airport and one back from the other end, which lands
// its flight's minutes later (``GameCore/AirRoute/flightMinutes``, stand to
// stand: ``taxiMinutes`` of it on the ground at each end). A day the route
// is grounded by a typhoon (either end closed) none flies.
//
// Presentation only, as decision 699's aircraft are: nothing here changes
// the world, the save or a golden value, and nothing random decides it.

extension Map3DAircraft {
    /// Decision 771: one leg of a company's route: the route, the game
    /// minute its aircraft leaves its stand (minutes since the game
    /// began), whether it flies out from the route's airport or back to
    /// it, and the airport of the map (its place in ``GameWorld/airports``)
    /// it lands at or leaves, the one its ``FlightID`` is seen at.
    public struct Leg: Hashable, Sendable {
        public let route: AirRouteID
        public let departure: Int64
        public let outbound: Bool
        public let airport: Int

        public init(route: AirRouteID, departure: Int64, outbound: Bool, airport: Int) {
            self.route = route
            self.departure = departure
            self.outbound = outbound
            self.airport = airport
        }
    }

    /// The type a route's aircraft of `size` is drawn as.
    public static func kind(of size: AircraftSize) -> Kind {
        switch size {
        case .commuter: .commuter19
        case .regional: .regional70
        case .narrowBody: .narrowJet
        case .wideBody: .wideJet
        }
    }

    /// The company's livery: the navy of ``liveries``, the same on each of
    /// its aircraft.
    public static let companyLivery = 3

    /// Decision 771: how high a route's aircraft climbs while it is drawn
    /// (and followed), metres: about where a short flight levels off, low
    /// enough that the ground drawn round the camera still fills the view.
    /// Past it the flight window shows the flight.
    public static let cruiseHeight = 3_000.0

    /// The minutes of each leg spent on the ground at either end, between
    /// leaving the stand and the take-off roll and between touchdown and
    /// the stand (``GameCore/AirRoute/groundMinutes`` is both, and the
    /// climb and the approach).
    public static let taxiMinutes: Int64 = 10

    /// How far a route's aircraft climbs straight ahead before it turns
    /// towards where it flies, and the radius of its turn, metres (a turn
    /// of some 2° a second at its climbing speed).
    static let straightOut = 1_500.0
    static let turnRadius = 2_500.0

    /// Decision 771: a company route as the 3D map flies it.
    public struct Route: Hashable, Sendable {
        public let id: AirRouteID
        /// The airports of the map at its ends (their places in
        /// ``GameWorld/airports``): the far one `nil` for a destination
        /// past the map's edge.
        public let airport: Int
        public let far: Int?
        public let kind: Kind
        /// The minutes of the day its aircraft leave their stands, at
        /// either end.
        public let minutes: [Int64]
        /// Stand to stand (``GameCore/AirRoute/flightMinutes``).
        public let flightMinutes: Int64
        /// Whether a typhoon keeps it on the ground today.
        public let grounded: Bool
        /// Where its far end is, in world units (off the map for a place
        /// abroad), which its aircraft turn towards after taking off.
        public let farX: Double
        public let farY: Double
        public let homeX: Double
        public let homeY: Double

        public init(id: AirRouteID, airport: Int, far: Int?, kind: Kind, minutes: [Int64], flightMinutes: Int64, grounded: Bool,
                    farX: Double, farY: Double, homeX: Double, homeY: Double) {
            self.id = id
            self.airport = airport
            self.far = far
            self.kind = kind
            self.minutes = minutes
            self.flightMinutes = flightMinutes
            self.grounded = grounded
            self.farX = farX
            self.farY = farY
            self.homeX = homeX
            self.homeY = homeY
        }

        /// The game second leg `leg`'s aircraft starts its take-off roll
        /// (not landing) or touches down (landing).
        func runwaySecond(of leg: Leg, landing: Bool) -> Double {
            let minute = landing ? leg.departure + flightMinutes - Map3DAircraft.taxiMinutes : leg.departure + Map3DAircraft.taxiMinutes
            return Double(minute * 60)
        }

        /// The legs that land at or leave airport `airport` (a place in
        /// ``GameWorld/airports``) with their runway time in
        /// `start..<end` game seconds, and whether each lands there.
        func legs(at airport: Int, from start: Double, to end: Double) -> [(leg: Leg, landing: Bool, time: Double)] {
            guard !grounded, airport == self.airport || airport == far else { return [] }
            let firstDay = GameDate.floorDivide(Int64(start.rounded(.down)) / 60 - flightMinutes, GameTime.minutesPerDay)
            let lastDay = GameDate.floorDivide(Int64(end.rounded(.up)) / 60, GameTime.minutesPerDay)
            var found: [(leg: Leg, landing: Bool, time: Double)] = []
            for day in firstDay...max(firstDay, lastDay) {
                for minute in minutes {
                    let departure = day * GameTime.minutesPerDay + minute
                    // Out from the route's airport and back from its far
                    // end, both leaving at `departure`.
                    for outbound in [true, false] {
                        let leaves = outbound ? self.airport : far, lands = outbound ? far : self.airport
                        for (at, landing) in [(leaves, false), (lands, true)] where at == airport {
                            let leg = Leg(route: id, departure: departure, outbound: outbound, airport: airport)
                            let time = runwaySecond(of: leg, landing: landing)
                            if time >= start, time < end { found.append((leg, landing, time)) }
                        }
                    }
                }
            }
            return found.sorted { $0.time < $1.time }
        }
    }
}

extension Map3DAircraft.Traffic {
    /// Decision 771: the company's routes in `world`, as the 3D map flies
    /// them today; `days` the airports' days (for the typhoons).
    static func routes(of world: GameWorld, days: [AirportDay]) -> [Map3DAircraft.Route] {
        guard !world.airRoutes.isEmpty else { return [] }
        let frame = RealWorldFrame(world: world)
        return world.airRoutes.compactMap { route in
            guard let airport = world.airports.firstIndex(where: { $0.id == route.airport }) else { return nil }
            let far = route.farAirport.flatMap { id in world.airports.firstIndex { $0.id == id } }
            let home = world.airports[airport].point
            var target: (x: Double, y: Double)
            if let far {
                target = (Double(world.airports[far].point.x), Double(world.airports[far].point.y))
            } else if let frame, let place = AirportCatalog.coordinate(ofDestination: route.destination) {
                target = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
            } else {
                target = (Double(home.x), Double(home.y))
            }
            let closed = { (index: Int?) in index.map { days.indices.contains($0) && days[$0].isClosed } ?? false }
            return Map3DAircraft.Route(id: route.id, airport: airport, far: far, kind: Map3DAircraft.kind(of: route.size),
                                       minutes: world.airRouteDepartureMinutes(route.id), flightMinutes: route.flightMinutes,
                                       grounded: closed(airport) || closed(far), farX: target.x, farY: target.y,
                                       homeX: Double(home.x), homeY: Double(home.y))
        }
    }

    /// What of `world`'s air routes the 3D map flies by (each one's number,
    /// flights and size), as a number that changes when they do: the
    /// flights are counted again then (0 for none).
    public static func routesAsked(by world: GameWorld) -> Int {
        guard !world.airRoutes.isEmpty else { return 0 }
        var hasher = Hasher()
        for route in world.airRoutes {
            hasher.combine(route.id)
            hasher.combine(route.frequency)
            hasher.combine(route.size)
        }
        return hasher.finalize()
    }

    /// What the routes are, as a number that changes when they do: the
    /// flights laid of an hour are laid again with it.
    var routesKey: Int {
        var hasher = Hasher()
        hasher.combine(routes)
        return routes.isEmpty ? 0 : hasher.finalize()
    }

    /// Route `id`.
    func route(_ id: AirRouteID) -> Map3DAircraft.Route? {
        routes.first { $0.id == id }
    }
}

extension Map3DAircraft.Laid {
    /// Decision 771: where in a scene whose world origin is `origin` the
    /// other end of `route` lies from the airport `leg` leaves, level (the
    /// way its aircraft turns after taking off).
    static func target(of route: Map3DAircraft.Route, leg: Map3DAircraft.Leg, origin: (x: Double, y: Double)) -> Map3DPoint {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let (x, y) = leg.outbound ? (route.farX, route.farY) : (route.homeX, route.homeY)
        return Map3DPoint(Float((x - origin.x) / metre), 0, Float((y - origin.y) / metre))
    }

    /// Decision 771: where a climbing aircraft is `up` metres past its
    /// lift-off at `liftOff` (the runway's way `forward`): straight on for
    /// ``Map3DAircraft/straightOut``, then turning at
    /// ``Map3DAircraft/turnRadius`` until it heads `toward`, then straight
    /// on that way. Its level place and the way it heads.
    static func climbed(_ up: Double, from liftOff: Map3DPoint, forward: Map3DPoint, toward: Map3DPoint?) -> (ground: Map3DPoint, forward: Map3DPoint) {
        let straight = Map3DAircraft.straightOut
        guard let toward, up > straight else { return (liftOff + forward * Float(up), forward) }
        let left = Map3DPoint(forward.z, 0, -forward.x)
        let turn = atan2(Double(toward.dot(left)), Double(toward.dot(forward)))
        let radius = Map3DAircraft.turnRadius, arc = radius * abs(turn), sign: Double = turn < 0 ? -1 : 1
        let start = liftOff + forward * Float(straight)
        func on(_ angle: Double) -> (Map3DPoint, Map3DPoint) {
            let place = start + forward * Float(radius * sin(angle)) + left * Float(sign * radius * (1 - cos(angle)))
            let way = forward * Float(cos(angle)) + left * Float(sign * sin(angle))
            return (place, way.normalized ?? forward)
        }
        let s = up - straight
        if s < arc { return on(s / radius) }
        let (end, way) = on(abs(turn))
        return (end + way * Float(s - arc), way)
    }
}
