import Foundation
import GameCore

// Taiwan's real city and county bus routes (decision 400, 10i-3): each
// route's stops in order, its shape and how often it runs, as
// `tools/real-buses/build_real_buses.py` writes them into the app
// (`Resources/RealBuses/`): one file of each city or county's routes and an
// index of them, so a map reads only the places it reaches. Twenty places
// are the owner's reference's (geo-scene, made from TDX); Taipei City and
// Pingtung County, which it lacks, are TDX's own.
//
// Read-only and never saved: a route a player buys becomes GameCore's
// `BusRoute` (10i-4), which keeps only its stops' cells and leg lengths.

/// The index of the real bus files (`real_buses_index.json`).
public struct RealBuses: Sendable, Equatable {
    /// Where a place's routes come from.
    public enum Source: String, Sendable, Hashable, Decodable {
        /// The owner's reference (`Railway/geo-scene-reference-clean`).
        case reference
        /// TDX, fetched with `tdx-check.yml`.
        case tdx
    }

    /// One city or county.
    public struct Place: Sendable, Hashable {
        /// TDX's name of it (`Taipei`, `HsinchuCounty`).
        public let city: String
        /// Its Chinese name (`臺北市`).
        public let name: String
        /// Its file in the bundle.
        public let file: String
        public let source: Source
        public let routes: Int
        /// How many of its routes run every estimated headway.
        public let estimatedHeadways: Int
        /// The corners of the box round its routes' shapes.
        public let southWest: RealRailways.Coordinate
        public let northEast: RealRailways.Coordinate

        /// Whether a box `margin` metres larger than the place's holds
        /// `coordinate`.
        public func reaches(_ coordinate: RealRailways.Coordinate, margin: Double = 0) -> Bool {
            let latitudeMargin = margin / 111_320
            let longitudeMargin = margin / (111_320 * max(0.1, cos(coordinate.latitude * .pi / 180)))
            return coordinate.latitude >= southWest.latitude - latitudeMargin
                && coordinate.latitude <= northEast.latitude + latitudeMargin
                && coordinate.longitude >= southWest.longitude - longitudeMargin
                && coordinate.longitude <= northEast.longitude + longitudeMargin
        }
    }

    public static let indexFile = "real_buses_index.json"
    /// The files' version this reader knows.
    public static let schema = 1

    public let places: [Place]
    /// Degrees per stored unit (the files keep 1e-5 degree integers).
    let scale: Double

    /// Reads the index. Throws for another schema or a place out of shape.
    public init(index data: Data) throws {
        struct File: Decodable {
            struct Place: Decodable {
                let city: String
                let name: String
                let file: String
                let source: Source
                let routes: Int
                let estimatedHeadways: Int
                let bounds: [Int]
            }
            let schema: Int
            let scale: Int
            let places: [Place]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schema == Self.schema else { throw RealBusError.schema(file.schema) }
        guard file.scale > 0 else { throw RealBusError.malformed("the index's scale is \(file.scale)") }
        let scale = 1 / Double(file.scale)
        self.scale = scale
        places = try file.places.map { place in
            guard place.bounds.count == 4, place.bounds[0] <= place.bounds[2], place.bounds[1] <= place.bounds[3] else {
                throw RealBusError.malformed("\(place.city)'s bounds")
            }
            return Place(
                city: place.city, name: place.name, file: place.file, source: place.source,
                routes: place.routes, estimatedHeadways: place.estimatedHeadways,
                southWest: RealRailways.Coordinate(latitude: Double(place.bounds[1]) * scale, longitude: Double(place.bounds[0]) * scale),
                northEast: RealRailways.Coordinate(latitude: Double(place.bounds[3]) * scale, longitude: Double(place.bounds[2]) * scale)
            )
        }
    }

    /// The places whose routes may pass within `metres` of `coordinate`.
    public func places(near coordinate: RealRailways.Coordinate, within metres: Double) -> [Place] {
        places.filter { $0.reaches(coordinate, margin: metres) }
    }

    /// Reads `place`'s file, `data`.
    public func routes(of place: Place, data: Data) throws -> [RealBusRoute] {
        try RealBusRoute.routes(in: data, city: place.city, scale: scale)
    }
}

/// Why a real bus file could not be read.
public enum RealBusError: Error, Equatable {
    case schema(Int)
    case malformed(String)
}

/// One direction of one real bus route.
public struct RealBusRoute: Sendable, Hashable, Identifiable {
    public struct Stop: Sendable, Hashable {
        public let name: String
        /// How far along the shape it is, never before the stop ahead of it.
        public let metres: Int
        /// The point of the shape `metres` along it.
        public let coordinate: RealRailways.Coordinate
    }

    /// The place and the file's key, unique in Taiwan:
    /// `Hsinchu/HSZ0007_81_0`.
    public let id: String
    /// TDX's route id (`HSZ0007`).
    public let route: String
    /// The route's name as the bus shows it (`81`).
    public let name: String
    /// The sub-route's name, empty when the file has none.
    public let subRoute: String
    /// 0 outbound, 1 back (TDX's `Direction`).
    public let direction: Int
    /// Minutes between buses, whole: TDX's schedule, or an estimate.
    public let headwayMinutes: Int
    /// Whether ``headwayMinutes`` is estimated (no schedule for the
    /// route): 30 minutes in a city, 60 in a county. The game says so.
    public let headwayEstimated: Bool
    /// The shape's length, metres.
    public let metres: Int
    /// The road the bus takes, from its first stop to its last.
    public let shape: [RealRailways.Coordinate]
    public let stops: [Stop]

    /// The point `metres` along the shape.
    public func coordinate(atMetres metres: Double) -> RealRailways.Coordinate {
        Self.point(along: shape, metres: metres)
    }

    static func point(along shape: [RealRailways.Coordinate], metres: Double) -> RealRailways.Coordinate {
        var run = 0.0
        for (a, b) in zip(shape, shape.dropFirst()) {
            let length = a.distance(to: b)
            if run + length >= metres, length > 0 {
                let t = max(0, (metres - run) / length)
                return RealRailways.Coordinate(latitude: a.latitude + t * (b.latitude - a.latitude),
                                               longitude: a.longitude + t * (b.longitude - a.longitude))
            }
            run += length
        }
        return shape[shape.count - 1]
    }

    /// The routes of one place's file. Throws for another schema, another
    /// place, or a route out of shape: fewer than two points, no stops, a
    /// name for each stop missing, stops out of order or past the shape's
    /// end, a headway outside 1 minute to ``BusService/longestHeadway``.
    static func routes(in data: Data, city: String, scale: Double) throws -> [RealBusRoute] {
        struct File: Decodable {
            struct Route: Decodable {
                let key: String
                let route: String
                let name: String
                let subRoute: String
                let direction: Int
                let headway: Int
                let headwayEstimated: Bool
                let metres: Int
                let shape: [Int]
                let stopNames: [String]
                let stopMetres: [Int]
            }
            let schema: Int
            let city: String
            let routes: [Route]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schema == RealBuses.schema else { throw RealBusError.schema(file.schema) }
        guard file.city == city else { throw RealBusError.malformed("the file is \(file.city)'s, not \(city)'s") }
        return try file.routes.map { route in
            let id = "\(city)/\(route.key)"
            guard route.shape.count >= 4, route.shape.count.isMultiple(of: 2) else {
                throw RealBusError.malformed("\(id): a shape of fewer than two points")
            }
            var shape: [RealRailways.Coordinate] = []
            shape.reserveCapacity(route.shape.count / 2)
            var longitude = 0, latitude = 0
            for index in stride(from: 0, to: route.shape.count, by: 2) {
                longitude += route.shape[index]
                latitude += route.shape[index + 1]
                shape.append(RealRailways.Coordinate(latitude: Double(latitude) * scale, longitude: Double(longitude) * scale))
            }
            guard !route.stopNames.isEmpty, route.stopNames.count == route.stopMetres.count else {
                throw RealBusError.malformed("\(id): \(route.stopNames.count) stop names for \(route.stopMetres.count) stops")
            }
            guard zip(route.stopMetres, route.stopMetres.dropFirst()).allSatisfy({ $0 <= $1 }),
                  let first = route.stopMetres.first, first >= 0, let last = route.stopMetres.last, last <= route.metres else {
                throw RealBusError.malformed("\(id): stops out of order or off the shape")
            }
            guard (1 ... Int(BusService.longestHeadway)).contains(route.headway) else {
                throw RealBusError.malformed("\(id): a headway of \(route.headway) minutes")
            }
            // The stops' points, walking the shape once.
            var stops: [Stop] = []
            stops.reserveCapacity(route.stopMetres.count)
            var segment = 0
            var run = 0.0
            for (name, metres) in zip(route.stopNames, route.stopMetres) {
                let target = Double(metres)
                while segment < shape.count - 2, run + shape[segment].distance(to: shape[segment + 1]) < target {
                    run += shape[segment].distance(to: shape[segment + 1])
                    segment += 1
                }
                let point = Self.point(along: [shape[segment], shape[segment + 1]], metres: target - run)
                stops.append(Stop(name: name, metres: metres, coordinate: point))
            }
            return RealBusRoute(
                id: id, route: route.route, name: route.name, subRoute: route.subRoute, direction: route.direction,
                headwayMinutes: route.headway, headwayEstimated: route.headwayEstimated, metres: route.metres,
                shape: shape, stops: stops
            )
        }
    }
}
