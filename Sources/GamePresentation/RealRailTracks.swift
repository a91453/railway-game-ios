import Foundation

// Every running track of Taiwan's real railways (decision 402), so the 3D
// map of a real-world game lays a real line as the single, double or
// quadruple track it is, each track where the real one runs and at the
// height the owner's site shows it: up on its viaducts, down in its tunnels,
// a line crossing over another above it.
//
// The owner's `Railway/` site's OpenStreetMap ways (`rail-3d/physical/
// network.json`, `metro-network.json`) and the height it draws each at over
// the ground (`level-profiles.json`'s `flatOffsets`);
// `tools/real-railways/extract_tracks.py` keeps the running tracks of the
// TRA, the High Speed Rail, the Alishan Forest Railway and the metros and
// light rails (`rail_tracks.json`).

/// The running tracks of Taiwan's real railways (decision 402), as
/// `rail_tracks.json` lists them.
public struct RealRailTracks: Sendable, Equatable {
    public enum Kind: String, Sendable, Hashable, Decodable {
        case surface = "s"
        /// On a bridge or a viaduct.
        case bridge = "b"
        case tunnel = "t"
    }

    public struct Track: Sendable, Equatable {
        /// The system it is a track of, as ``RealRailways/System/id`` names
        /// it (`tra_sched`).
        public let system: String
        public let kind: Kind
        /// Along the track, at least two.
        public let points: [RealRailways.Coordinate]
        /// How far over the ground each point is, metres; under it in a
        /// tunnel.
        public let heights: [Double]
    }

    public let tracks: [Track]

    init(tracks: [Track]) {
        self.tracks = tracks
    }

    /// Reads the file. Throws for one out of shape: a track of fewer than
    /// two points, its points not in threes, a system it does not list, or
    /// a point off the Earth.
    public init(data: Data) throws {
        struct File: Decodable {
            struct Way: Decodable {
                let system: Int
                let kind: Kind
                let points: [Int]
            }

            let systems: [String]
            let ways: [Way]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        func corrupt(_ what: String) -> DecodingError { DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: what)) }
        tracks = try file.ways.map { way in
            guard file.systems.indices.contains(way.system) else { throw corrupt("A track's system is not listed") }
            guard way.points.count % 3 == 0, way.points.count >= 6 else { throw corrupt("A track's points are not in threes, or fewer than two") }
            var points: [RealRailways.Coordinate] = [], heights: [Double] = []
            points.reserveCapacity(way.points.count / 3)
            heights.reserveCapacity(way.points.count / 3)
            var longitude = 0, latitude = 0, height = 0
            for index in stride(from: 0, to: way.points.count, by: 3) {
                longitude += way.points[index]
                latitude += way.points[index + 1]
                height += way.points[index + 2]
                guard abs(longitude) <= 180_000_000, abs(latitude) <= 90_000_000 else { throw corrupt("A track's point is off the Earth") }
                points.append(RealRailways.Coordinate(latitude: Double(latitude) / 1e6, longitude: Double(longitude) / 1e6))
                heights.append(Double(height) / 10)
            }
            return Track(system: file.systems[way.system], kind: way.kind, points: points, heights: heights)
        }
    }

    /// The systems it has tracks of.
    public var systems: Set<String> { Set(tracks.map(\.system)) }
}
