import Foundation

// Decision 699: the airfields of Taiwan's airports with scheduled flights,
// as OpenStreetMap (ODbL 1.0) maps them: runways, taxiways, aprons, parking
// positions, jet bridges and control towers, read once by
// `tools/airfields/build_airfields.py` into the app's
// `Resources/BaseMap/taiwan_airfields.json`. The 3D map lays them on the
// ground and parks and flies its aircraft on them (``Map3DAirfields``);
// nothing of the game's rules reads them.

/// Taiwan's airfields, as the 3D map draws them.
public struct RealAirfields: Sendable {
    /// A latitude and longitude, degrees.
    public struct Point: Equatable, Sendable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public struct Runway: Sendable {
        /// The numbers painted at its ends, as "05L/23R": the first at the
        /// line's first point.
        public let ref: String
        /// Metres.
        public let width: Float
        public let line: [Point]

        public init(ref: String, width: Float, line: [Point]) {
            self.ref = ref
            self.width = width
            self.line = line
        }
    }

    public struct Taxiway: Sendable {
        public let width: Float
        public let line: [Point]
    }

    /// Where an aircraft parks: where its nose stops, and the way it
    /// points, degrees clockwise from north (`nil` when the map does not
    /// say).
    public struct Stand: Sendable {
        public let nose: Point
        public let heading: Double?
    }

    public struct Tower: Sendable {
        public let at: Point
        /// Metres.
        public let height: Float
    }

    public struct Field: Sendable {
        public let iata: String
        public let icao: String
        /// The middle of its outline.
        public let at: Point
        public let runways: [Runway]
        public let taxiways: [Taxiway]
        /// Each apron's outline, not closed.
        public let aprons: [[Point]]
        public let stands: [Stand]
        /// Each jet bridge, from the terminal to the aircraft's door.
        public let bridges: [(from: Point, to: Point)]
        public let towers: [Tower]

        public init(iata: String, icao: String = "", at: Point, runways: [Runway], taxiways: [Taxiway] = [], aprons: [[Point]] = [],
                    stands: [Stand] = [], bridges: [(from: Point, to: Point)] = [], towers: [Tower] = []) {
            self.iata = iata
            self.icao = icao
            self.at = at
            self.runways = runways
            self.taxiways = taxiways
            self.aprons = aprons
            self.stands = stands
            self.bridges = bridges
            self.towers = towers
        }
    }

    public let fields: [Field]

    public init(fields: [Field]) {
        self.fields = fields
    }

    private struct File: Decodable {
        struct Line: Decodable {
            let ref: String?
            let width: Int
            let line: [Int]
        }

        struct Airport: Decodable {
            let iata: String
            let icao: String
            let at: [Int]
            let runways: [Line]
            let taxiways: [Line]
            let aprons: [[Int]]
            let stands: [[Int]]
            let bridges: [[Int]]
            let towers: [[Int]]
        }

        let airports: [Airport]
    }

    /// Reads the app's file (`build_airfields.py`). Throws for a file out
    /// of shape.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        func broken(_ what: String) -> DecodingError { .dataCorrupted(.init(codingPath: [], debugDescription: what)) }
        fields = try file.airports.map { airport in
            guard airport.at.count == 2 else { throw broken("An airport has a middle.") }
            return Field(
                iata: airport.iata, icao: airport.icao, at: Self.point(airport.at[0], airport.at[1]),
                runways: try airport.runways.map { Runway(ref: $0.ref ?? "", width: Float($0.width), line: try Self.line($0.line)) },
                taxiways: try airport.taxiways.map { Taxiway(width: Float($0.width), line: try Self.line($0.line)) },
                aprons: try airport.aprons.map { try Self.line($0, atLeast: 3) },
                stands: try airport.stands.map { numbers in
                    guard numbers.count == 3 else { throw broken("A stand is a place and a heading.") }
                    return Stand(nose: Self.point(numbers[0], numbers[1]), heading: numbers[2] < 0 ? nil : Double(numbers[2]))
                },
                bridges: try airport.bridges.map { numbers in
                    let ends = try Self.line(numbers)
                    return (ends[0], ends[ends.count - 1])
                },
                towers: try airport.towers.map { numbers in
                    guard numbers.count == 3 else { throw broken("A tower is a place and a height.") }
                    return Tower(at: Self.point(numbers[0], numbers[1]), height: Float(numbers[2]))
                }
            )
        }
    }

    private static func point(_ latitude: Int, _ longitude: Int) -> Point {
        Point(latitude: Double(latitude) / 1e6, longitude: Double(longitude) / 1e6)
    }

    /// A line of 1e-6 degrees: the first point whole, each after it the
    /// change from the one before.
    static func line(_ numbers: [Int], atLeast least: Int = 2) throws -> [Point] {
        guard numbers.count >= 2 * least, numbers.count.isMultiple(of: 2) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A line is \(least) points or more."))
        }
        var latitude = 0, longitude = 0
        var points: [Point] = []
        points.reserveCapacity(numbers.count / 2)
        for index in stride(from: 0, to: numbers.count, by: 2) {
            latitude += numbers[index]
            longitude += numbers[index + 1]
            points.append(point(latitude, longitude))
        }
        return points
    }
}
