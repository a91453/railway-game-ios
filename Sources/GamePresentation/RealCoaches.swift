import Foundation
import GameCore

// Taiwan's real intercity coaches (decision 706, first step): the freeway
// coaches and the long highway buses that cross a county line, each route
// direction's stops in order, its shape, every departure of the week, the
// minutes to each stop and the full fare, as
// `tools/real-coaches/build_real_coaches.py` writes them into the app
// (`Resources/RealCoaches/real_coaches.json`) from TDX's highway bus data.
//
// Read-only and never saved. Nothing runs on it yet: the rule that lets the
// coaches carry intercity passengers reads it in the decision's second
// step.

/// The real coach routes (`real_coaches.json`).
public struct RealCoaches: Sendable, Equatable {
    public static let file = "real_coaches.json"
    /// The file's version this reader knows.
    public static let schema = 1

    public let routes: [RealCoachRoute]
    /// The day the data was fetched from TDX, `yyyy-mm-dd`.
    public let fetched: String
    /// The corners of the box round every route's shape.
    public let southWest: RealRailways.Coordinate
    public let northEast: RealRailways.Coordinate

    /// Reads the file. Throws for another schema or a route out of shape:
    /// fewer than two points or two stops, a list as long as the stops
    /// missing, stops out of order in metres or minutes or past the shape's
    /// end, no departures, a departure outside the day or on no day, a fare
    /// below 1.
    public init(data: Data) throws {
        struct File: Decodable {
            struct Origin: Decodable {
                let fetched: String
            }
            struct Route: Decodable {
                let key: String
                let route: String
                let name: String
                let subRoute: String
                let direction: Int
                let kind: RealCoachRoute.Kind
                let operators: [String]
                let headsign: String
                let headsignEn: String
                let metres: Int
                let shape: [Int]
                let stopNames: [String]
                let stopMetres: [Int]
                let stopCities: [String]
                let stopBoarding: [Int]?
                let stopMinutes: [Int]
                let minutesEstimated: Bool?
                let tripMinutes: [Int]
                let tripDays: [Int]
                let tripsFromHeadways: Int?
                let fare: Int?
            }
            let schema: Int
            let scale: Int
            let origin: Origin
            let bounds: [Int]
            let routes: [Route]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schema == Self.schema else { throw RealBusError.schema(file.schema) }
        guard file.scale > 0 else { throw RealBusError.malformed("the scale is \(file.scale)") }
        guard file.bounds.count == 4, file.bounds[0] <= file.bounds[2], file.bounds[1] <= file.bounds[3] else {
            throw RealBusError.malformed("the bounds")
        }
        let scale = 1 / Double(file.scale)
        fetched = file.origin.fetched
        southWest = RealRailways.Coordinate(latitude: Double(file.bounds[1]) * scale, longitude: Double(file.bounds[0]) * scale)
        northEast = RealRailways.Coordinate(latitude: Double(file.bounds[3]) * scale, longitude: Double(file.bounds[2]) * scale)
        routes = try file.routes.map { route in
            let id = route.key
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
            let count = route.stopNames.count
            guard count >= 2, route.stopMetres.count == count, route.stopCities.count == count, route.stopMinutes.count == count,
                  route.stopBoarding.map({ $0.count == count }) ?? true else {
                throw RealBusError.malformed("\(id): the stops' lists differ in length, or fewer than two stops")
            }
            guard zip(route.stopMetres, route.stopMetres.dropFirst()).allSatisfy({ $0 <= $1 }),
                  route.stopMetres[0] >= 0, route.stopMetres[count - 1] <= route.metres else {
                throw RealBusError.malformed("\(id): stops out of order or off the shape")
            }
            guard zip(route.stopMinutes, route.stopMinutes.dropFirst()).allSatisfy({ $0 <= $1 }),
                  route.stopMinutes[0] >= 0, route.stopMinutes[count - 1] > 0 else {
                throw RealBusError.malformed("\(id): the stops' minutes")
            }
            guard !route.tripMinutes.isEmpty, route.tripMinutes.count == route.tripDays.count,
                  route.tripMinutes.allSatisfy({ (0 ..< 24 * 60).contains($0) }),
                  zip(route.tripMinutes, route.tripMinutes.dropFirst()).allSatisfy({ $0 < $1 }),
                  route.tripDays.allSatisfy({ (1 ... 127).contains($0) }) else {
                throw RealBusError.malformed("\(id): the departures")
            }
            if let fare = route.fare, fare < 1 { throw RealBusError.malformed("\(id): a fare of \(fare)") }
            guard (0 ... 1).contains(route.direction) || route.direction == 2 else {
                throw RealBusError.malformed("\(id): direction \(route.direction)")
            }
            // The stops' points, walking the shape once.
            var stops: [RealCoachRoute.Stop] = []
            stops.reserveCapacity(count)
            var segment = 0
            var run = 0.0
            for index in 0 ..< count {
                let target = Double(route.stopMetres[index])
                while segment < shape.count - 2, run + shape[segment].distance(to: shape[segment + 1]) < target {
                    run += shape[segment].distance(to: shape[segment + 1])
                    segment += 1
                }
                let point = RealBusRoute.point(along: [shape[segment], shape[segment + 1]], metres: target - run)
                let boarding: RealCoachRoute.Boarding
                switch route.stopBoarding?[index] ?? 0 {
                case 0: boarding = .both
                case 1: boarding = .boardingOnly
                case -1: boarding = .alightingOnly
                default: throw RealBusError.malformed("\(id): stop \(index)'s boarding")
                }
                stops.append(RealCoachRoute.Stop(
                    name: route.stopNames[index], metres: route.stopMetres[index], coordinate: point,
                    city: route.stopCities[index], boarding: boarding, minutes: route.stopMinutes[index]
                ))
            }
            return RealCoachRoute(
                id: id, route: route.route, name: route.name, subRoute: route.subRoute, direction: route.direction,
                kind: route.kind, operators: route.operators, headsign: route.headsign, englishHeadsign: route.headsignEn,
                metres: route.metres, shape: shape, stops: stops, minutesEstimated: route.minutesEstimated ?? false,
                departures: zip(route.tripMinutes, route.tripDays).map { RealCoachRoute.Departure(minute: $0, days: UInt8($1)) },
                departuresFromHeadways: route.tripsFromHeadways ?? 0, fare: route.fare
            )
        }
    }

    /// The routes with a stop within `metres` of `coordinate`.
    public func routes(near coordinate: RealRailways.Coordinate, within metres: Double) -> [RealCoachRoute] {
        routes.filter { route in route.stops.contains { $0.coordinate.distance(to: coordinate) <= metres } }
    }
}

/// One direction of one real coach route.
public struct RealCoachRoute: Sendable, Hashable, Identifiable {
    /// What TDX calls the route's kind.
    public enum Kind: String, Sendable, Hashable, Decodable {
        /// A freeway coach (國道客運).
        case freeway
        /// A highway bus (一般公路客運) long enough, and across a county
        /// line, to count as intercity.
        case highway
    }

    /// Whether passengers get on, off or both at a stop.
    public enum Boarding: Sendable, Hashable {
        case both
        case boardingOnly
        case alightingOnly
    }

    public struct Stop: Sendable, Hashable {
        public let name: String
        /// How far along the shape it is, never before the stop ahead of it.
        public let metres: Int
        /// The point of the shape `metres` along it.
        public let coordinate: RealRailways.Coordinate
        /// TDX's code of the city or county it stands in (`TPE`, `CYI`),
        /// empty when TDX gives none.
        public let city: String
        public let boarding: Boarding
        /// Minutes from the first stop.
        public let minutes: Int
    }

    /// One departure of the week.
    public struct Departure: Sendable, Hashable {
        /// Minutes after midnight, at the first stop the timetable times.
        public let minute: Int
        /// The days it runs: bit 0 Monday, bit 6 Sunday.
        public let days: UInt8

        /// Whether it runs on `weekday`, 0 Monday to 6 Sunday.
        public func runs(on weekday: Int) -> Bool {
            (0 ..< 7).contains(weekday) && days & (1 << UInt8(weekday)) != 0
        }
    }

    /// TDX's sub-route id and direction, unique in the file:
    /// `THB161801_0`.
    public let id: String
    /// TDX's route id (`THB1618`).
    public let route: String
    /// The route's number as the coach shows it (`1618`).
    public let name: String
    /// The sub-route's name (`1618A`).
    public let subRoute: String
    /// 0 outbound, 1 back, 2 a loop (TDX's `Direction`).
    public let direction: Int
    public let kind: Kind
    /// The companies that run it, by their Chinese names, in order.
    public let operators: [String]
    /// Where it goes, as TDX words it (`台北→嘉義`); may be empty.
    public let headsign: String
    public let englishHeadsign: String
    /// The shape's length, metres.
    public let metres: Int
    /// The road the coach takes, from its first stop to its last.
    public let shape: [RealRailways.Coordinate]
    public let stops: [Stop]
    /// Whether the stops' minutes are estimated from the route's length
    /// (no trip times two stops, or its times give no believable speed).
    public let minutesEstimated: Bool
    /// Every departure of the week, earliest first.
    public let departures: [Departure]
    /// How many of ``departures`` come from a "every 15 to 20 minutes" row
    /// of the schedule rather than a timetabled trip.
    public let departuresFromHeadways: Int
    /// The adult single fare over the whole route, NT$; nil when TDX has
    /// none.
    public let fare: Int?

    /// Minutes from the first stop to the last.
    public var runMinutes: Int { stops[stops.count - 1].minutes }

    /// The departures on `weekday` (0 Monday to 6 Sunday), minutes after
    /// midnight, earliest first.
    public func departures(on weekday: Int) -> [Int] {
        departures.filter { $0.runs(on: weekday) }.map(\.minute)
    }

    /// The point `metres` along the shape.
    public func coordinate(atMetres metres: Double) -> RealRailways.Coordinate {
        RealBusRoute.point(along: shape, metres: metres)
    }
}
