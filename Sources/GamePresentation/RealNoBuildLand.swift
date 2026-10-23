import Foundation

// Decision 385: the land a real-world map's 3D city builds no town on
// (airports, military land, cemeteries, golf courses, railway land and
// ports) and the buildings standing in its airports, from OpenStreetMap
// (ODbL 1.0), read once by `tools/no-build-land/build_no_build.py` into
// the app's `Resources/RealWorld/taiwan_no_build.json`. Decision 385
// (續): no one lives on it either (`LandImport`).

/// Land of Taiwan the 3D map builds no town on, and its airports' buildings.
public struct RealNoBuildLand: Sendable {
    /// What a piece of land is, in the file's order (its `kinds`).
    public enum Kind: Int, CaseIterable, Sendable {
        case airport, military, cemetery, golf, railway, port
    }

    /// A latitude and longitude, degrees.
    public struct Point: Equatable, Sendable {
        public let latitude: Double
        public let longitude: Double
    }

    public struct Area: Sendable {
        public let kind: Kind
        /// Its outline, not closed.
        public let ring: [Point]
    }

    /// A terminal, hangar or other building in an airport.
    public struct Building: Sendable {
        public enum Use: Int, Sendable {
            case other, hangar, terminal
        }

        /// Metres.
        public let height: Float
        public let use: Use
        public let ring: [Point]
    }

    public let areas: [Area]
    public let buildings: [Building]
    /// The areas whose bounds reach each square of ``bucket`` degrees, by
    /// ``key(_:_:)``, so ``kind(atLatitude:longitude:)`` tries a few.
    private let index: [Int: [Int]]
    private static let bucket = 0.01

    public init(areas: [Area], buildings: [Building] = []) {
        self.areas = areas
        self.buildings = buildings
        var index: [Int: [Int]] = [:]
        for (number, area) in areas.enumerated() {
            let latitudes = area.ring.map(\.latitude), longitudes = area.ring.map(\.longitude)
            guard let south = latitudes.min(), let north = latitudes.max(), let west = longitudes.min(), let east = longitudes.max() else {
                continue
            }
            for row in Self.square(south)...Self.square(north) {
                for column in Self.square(west)...Self.square(east) {
                    index[Self.key(row, column), default: []].append(number)
                }
            }
        }
        self.index = index
    }

    private static func square(_ degrees: Double) -> Int {
        Int((degrees / bucket).rounded(.down))
    }

    private static func key(_ row: Int, _ column: Int) -> Int {
        row &* 100_000 &+ column
    }

    /// The kind of area `latitude`° north, `longitude`° east lies on (the
    /// even-odd rule), or `nil` on none.
    public func kind(atLatitude latitude: Double, longitude: Double) -> Kind? {
        for number in index[Self.key(Self.square(latitude), Self.square(longitude))] ?? [] {
            let ring = areas[number].ring
            var inside = false
            var last = ring[ring.count - 1]
            for point in ring {
                if (point.latitude > latitude) != (last.latitude > latitude),
                   longitude < point.longitude + (latitude - point.latitude) * (last.longitude - point.longitude) / (last.latitude - point.latitude) {
                    inside.toggle()
                }
                last = point
            }
            if inside { return areas[number].kind }
        }
        return nil
    }

    private struct File: Decodable {
        let kinds: [String]
        /// Each area's kind, then its ring (``ring(_:from:)``).
        let areas: [[Int]]
        /// Each building's height in metres, its use, then its ring.
        let buildings: [[Int]]
    }

    /// Reads the app's file (`build_no_build.py`). Throws for a file out
    /// of shape.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.kinds == Kind.allCases.map({ "\($0)" }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The kinds are \(file.kinds)."))
        }
        let areas = try file.areas.map { numbers in
            guard let first = numbers.first, let kind = Kind(rawValue: first) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "An area's kind is one of the kinds."))
            }
            return Area(kind: kind, ring: try Self.ring(numbers.dropFirst()))
        }
        let buildings = try file.buildings.map { numbers in
            guard numbers.count > 2, let use = Building.Use(rawValue: numbers[1]) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A building has a height and a use."))
            }
            return Building(height: Float(numbers[0]), use: use, ring: try Self.ring(numbers.dropFirst(2)))
        }
        self.init(areas: areas, buildings: buildings)
    }

    /// A ring of 1e-5 degrees: the first point whole, each after it the
    /// change from the one before; at least three points.
    static func ring(_ numbers: ArraySlice<Int>) throws -> [Point] {
        guard numbers.count >= 6, numbers.count.isMultiple(of: 2) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A ring is three points or more."))
        }
        var latitude = 0, longitude = 0
        var points: [Point] = []
        points.reserveCapacity(numbers.count / 2)
        var index = numbers.startIndex
        while index < numbers.endIndex {
            latitude += numbers[index]
            longitude += numbers[index + 1]
            points.append(Point(latitude: Double(latitude) / 1e5, longitude: Double(longitude) / 1e5))
            index += 2
        }
        return points
    }
}
