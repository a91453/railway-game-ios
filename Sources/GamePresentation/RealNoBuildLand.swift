import Foundation

// Decision 385: the land a real-world map's 3D city builds no town on
// (airports, military land, cemeteries, golf courses, railway land and
// ports) and the buildings standing in its airports, from OpenStreetMap
// (ODbL 1.0), read once by `tools/no-build-land/build_no_build.py` into
// the app's `Resources/BaseMap/taiwan_no_build.json`.

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

    public init(areas: [Area], buildings: [Building] = []) {
        self.areas = areas
        self.buildings = buildings
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
        areas = try file.areas.map { numbers in
            guard let first = numbers.first, let kind = Kind(rawValue: first) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "An area's kind is one of the kinds."))
            }
            return Area(kind: kind, ring: try Self.ring(numbers.dropFirst()))
        }
        buildings = try file.buildings.map { numbers in
            guard numbers.count > 2, let use = Building.Use(rawValue: numbers[1]) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A building has a height and a use."))
            }
            return Building(height: Float(numbers[0]), use: use, ring: try Self.ring(numbers.dropFirst(2)))
        }
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
