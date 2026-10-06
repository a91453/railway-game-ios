import Foundation
import GameCore

/// Station along an operating railway line.
public struct RealOperationStation: Hashable, Sendable, Codable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let distanceKm: Double?
    public let dwellSec: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case latitude = "lat"
        case longitude = "lon"
        case distanceKm = "d"
        case dwellSec = "dwell"
    }

    public init(name: String, latitude: Double, longitude: Double, distanceKm: Double? = nil, dwellSec: Int? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.distanceKm = distanceKm
        self.dwellSec = dwellSec
    }
}

/// Operational parameters of an operating line (headways, stations, dwell times).
public struct RealOperationLine: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let color: String?
    public let peakHeadwaySec: Int?
    public let offpeakHeadwaySec: Int?
    public let isHeadwayEstimated: Bool
    public let stations: [RealOperationStation]
    public let dwellSec: [Int]?
    public let segmentRunSec: [Int]?

    public init(
        id: String,
        name: String,
        color: String? = nil,
        peakHeadwaySec: Int? = nil,
        offpeakHeadwaySec: Int? = nil,
        isHeadwayEstimated: Bool = false,
        stations: [RealOperationStation] = [],
        dwellSec: [Int]? = nil,
        segmentRunSec: [Int]? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.peakHeadwaySec = peakHeadwaySec
        self.offpeakHeadwaySec = offpeakHeadwaySec
        self.isHeadwayEstimated = isHeadwayEstimated
        self.stations = stations
        self.dwellSec = dwellSec
        self.segmentRunSec = segmentRunSec
    }
}

/// An operating railway system (TRA, TRTC, KRTC, etc.) with its operational lines.
public struct RealOperationSystem: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let lines: [RealOperationLine]

    public init(id: String, name: String, lines: [RealOperationLine]) {
        self.id = id
        self.name = name
        self.lines = lines
    }

    public func line(id: String) -> RealOperationLine? {
        lines.first { $0.id == id }
    }
}

/// Operational railway data across Taiwan: station sequences, peak/off-peak headways,
/// dwell times, run times, and timetables.
public struct RealRailwayOperations: Sendable {
    public let systems: [String: RealOperationSystem]
    public let timetableData: [String: Data]

    public init(systems systemsData: [String: Data], timetables: [String: Data] = [:]) throws {
        let decoder = JSONDecoder()

        struct RawStation: Decodable {
            let name: String
            let lat: Double
            let lon: Double
            let d: Double?
            let dwell: Int?
        }

        struct RawSeg: Decodable {
            let run: Int?
        }

        struct RawLine: Decodable {
            let id: String
            let name: String
            let color: String?
            let peakHeadwaySec: Int?
            let offpeakHeadwaySec: Int?
            let headway_estimated: Bool?
            let stations: [RawStation]
            let dwellSec: [Int]?
            let segs: [RawSeg]?
        }

        struct RawSystem: Decodable {
            let system: String?
            let lines: [RawLine]
        }

        var parsedSystems: [String: RealOperationSystem] = [:]
        for (sysKey, data) in systemsData {
            guard let rawSys = try? decoder.decode(RawSystem.self, from: data) else { continue }
            let lines = rawSys.lines.map { rawLine in
                RealOperationLine(
                    id: rawLine.id,
                    name: rawLine.name,
                    color: rawLine.color,
                    peakHeadwaySec: rawLine.peakHeadwaySec,
                    offpeakHeadwaySec: rawLine.offpeakHeadwaySec,
                    isHeadwayEstimated: rawLine.headway_estimated ?? false,
                    stations: rawLine.stations.map {
                        RealOperationStation(name: $0.name, latitude: $0.lat, longitude: $0.lon, distanceKm: $0.d, dwellSec: $0.dwell)
                    },
                    dwellSec: rawLine.dwellSec,
                    segmentRunSec: rawLine.segs?.compactMap(\.run)
                )
            }
            let systemName = rawSys.system ?? sysKey.uppercased()
            parsedSystems[sysKey] = RealOperationSystem(id: sysKey, name: systemName, lines: lines)
        }
        self.systems = parsedSystems
        self.timetableData = timetables
    }

    public func system(id: String) -> RealOperationSystem? {
        systems[id]
    }

    public func line(id: String, inSystem systemId: String) -> RealOperationLine? {
        systems[systemId]?.line(id: id)
    }

    public func lines(inSystem systemId: String) -> [RealOperationLine] {
        systems[systemId]?.lines ?? []
    }

    public var allLines: [RealOperationLine] {
        systems.values.flatMap(\.lines)
    }

    public func headway(forLine id: String, inSystem systemId: String, peak: Bool) -> Int? {
        guard let line = line(id: id, inSystem: systemId) else { return nil }
        return peak ? line.peakHeadwaySec : line.offpeakHeadwaySec
    }
}
