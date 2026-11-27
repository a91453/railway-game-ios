import Foundation
import GameCore

/// STATION-ALIGN-APPLY (decision 1022, the station rules of 2026-11-27,
/// part (c)): where OpenStreetMap has the platforms of each station a
/// player can buy, so the game lays its platform along the real one
/// rather than round the station's point (decision 1021 measured the
/// game's 8.5 m off at the median and up to 134 m, nearly all of it
/// along the line).
///
/// Each entry is the two ends of the real platforms the station's
/// trains stand at: the first and the last of their vertices along the
/// game's platform, as `tools/station-alignment` matched them
/// (`StationAlignmentReportTests`, `STATION_ALIGN_PLATFORMS`). A line's
/// station is keyed by the line and the station's name
/// (``key(line:station:)``); one bought by itself by its system and name
/// (``key(system:station:)``), since one name can stand for platforms of
/// different lines at different levels (Taipei Metro's Da'an). From the
/// app's `real_platforms.json`, OpenStreetMap contributors, ODbL 1.0.
public struct RealPlatformEnds: Sendable, Hashable {
    /// A station's real platforms, from end to end.
    public struct Ends: Sendable, Hashable {
        public let first: RealRailways.Coordinate
        public let last: RealRailways.Coordinate

        public init(first: RealRailways.Coordinate, last: RealRailways.Coordinate) {
            self.first = first
            self.last = last
        }

        /// The point halfway between the two ends.
        public var middle: RealRailways.Coordinate {
            RealRailways.Coordinate(latitude: (first.latitude + last.latitude) / 2, longitude: (first.longitude + last.longitude) / 2)
        }
    }

    public let ends: [String: Ends]

    public init(ends: [String: Ends]) {
        self.ends = ends
    }

    private struct File: Decodable {
        let platforms: [String: [Double]]
    }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        var ends: [String: Ends] = [:]
        for (key, values) in file.platforms where values.count == 4 {
            ends[key] = Ends(
                first: RealRailways.Coordinate(latitude: values[0], longitude: values[1]),
                last: RealRailways.Coordinate(latitude: values[2], longitude: values[3])
            )
        }
        self.ends = ends
    }

    /// The key of the station `station` (its name in the railway's data)
    /// of the line `line` on sale (``RealBranchLine/id``).
    public static func key(line: String, station: String) -> String { "\(line)|\(station)" }

    /// The key of the station `station` of the system `system` bought by
    /// itself (decision 400 A.8).
    public static func key(system: String, station: String) -> String { "\(system)|\(station)" }

    /// How far, in metres, the real platforms' middle may lie beside the
    /// game's for the match to be kept: farther, they are another line's
    /// (Nangang's, the Fukuoka subway's Hakata, which found JR's), and
    /// the station is laid as before.
    public static let acrossTrusted = 15.0

    /// How far, in metres, a platform is moved along its line at most.
    /// Decision 1021's farthest off with OSM's platforms drawn was Hexing,
    /// 135 to 198 m.
    public static let farthest = 250.0

    public func ends(line: String, station: String) -> Ends? { ends[Self.key(line: line, station: station)] }
    public func ends(system: String, station: String) -> Ends? { ends[Self.key(system: system, station: station)] }
}
