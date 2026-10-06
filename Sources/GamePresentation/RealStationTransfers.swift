import Foundation

// The transfers between Taiwan's railways, from the `Railway/` site's
// `data/station_transfers.json` (schema version 1, built from TDX), read as
// the site reads it in `index.html`: `initStationTransfers`,
// `transferStationName`, `transferAnchorNear`, `transferAnchorForStop` and
// `transferRoutesAt`, ported as they are.

/// Which stations of different railways are one place to change at, and
/// the routes that call at each.
public struct RealStationTransfers: Sendable {
    /// A route (a line of one system): `routes[key]`.
    public struct Route: Hashable, Sendable {
        /// `SYSTEM:lineId`, as `TRA:WL`.
        public let key: String
        /// TDX's system code (`TRA`, `THSR`, `TRTC`, …).
        public let system: String
        public let lineId: String
        public let name: String?

        /// What the site calls it (`transferRoutesAt`): its name, or the
        /// site's fallback (`TRANSFER_ROUTE_FALLBACK`), or its line ID.
        public var label: String {
            if let name, !name.isEmpty { return name }
            return RealStationTransfers.routeFallbackLabels[key] ?? lineId
        }
    }

    /// A station of one system: `stations[key]`.
    public struct Station: Hashable, Sendable {
        /// `SYSTEM:stationId`, as `TRA:1000`.
        public let key: String
        public let system: String
        /// The operator's station code (TRA `1000`, Taipei Metro `BL12`).
        public let stationId: String
        public let name: String
        /// The name as ``RealStationTransfers/transferStationName(_:)``
        /// has it.
        public let normalizedName: String
        public let coordinate: RealRailways.Coordinate
        public let routes: [String]
        /// The transfer station it belongs to, if any.
        public let transferId: String?
    }

    /// Stations of different systems close enough, with the same name, to
    /// be one place: `transferStations[]`.
    public struct Group: Hashable, Sendable {
        public let id: String
        public let normalizedName: String
        public let members: [String]
        public let routes: [String]
    }

    /// The site's `TRANSFER_ROUTE_FALLBACK`.
    public static let routeFallbackLabels = ["THSR:THSR": "高鐵", "SANYING:LB": "三鶯線"]

    /// The site's `TRANSFER_SCHED_SYSTEM`: the scheduled systems' TDX codes.
    public static let scheduledSystemCodes = ["tra_sched": "TRA", "thsr_sched": "THSR", "afr_sched": "AFR"]

    /// The site's `TRANSFER_ROUTE_I18N_SYSTEM`: each TDX system code's site
    /// system (``RealRailways/System``).
    public static let siteSystems = [
        "AFR": "afr_sched", "KLRT": "krtc", "KRTC": "krtc", "NTALRT": "ntalrt", "NTDLRT": "ntdlrt",
        "NTMC": "mrt", "SANYING": "sanying", "THSR": "thsr_sched", "TMRT": "tmrt", "TRA": "tra_sched",
        "TRTC": "mrt", "TYMC": "tymc",
    ]

    /// How far apart two stations may be to be one place, in metres
    /// (`criteria.maxDistanceM`: 450).
    public let maximumDistanceMetres: Double
    public let routes: [String: Route]
    /// Every station, in key order.
    public let stations: [Station]
    public let groups: [String: Group]
    private let stationsBySystemName: [String: [Int]]
    private let stationsByName: [String: [Int]]
    private let stationsByKey: [String: Int]

    public enum FormatError: Error, Hashable {
        /// The site reads only schema version 1.
        case unsupportedSchema(Int)
    }

    public init(data: Data) throws {
        struct RawRoute: Decodable {
            let system: String
            let lineId: String
            let name: String?
        }
        struct RawStation: Decodable {
            let system: String
            let stationId: String
            let name: String
            let normalizedName: String
            let position: [Double]
            let routes: [String]?
            let transferId: String?
        }
        struct RawGroup: Decodable {
            let id: String
            let normalizedName: String
            let members: [String]
            let routes: [String]
        }
        struct Criteria: Decodable {
            let maxDistanceM: Double
        }
        struct RawFile: Decodable {
            let schemaVersion: Int
            let criteria: Criteria
            let routes: [String: RawRoute]
            let stations: [String: RawStation]
            let transferStations: [RawGroup]
        }
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        guard raw.schemaVersion == 1 else { throw FormatError.unsupportedSchema(raw.schemaVersion) }
        maximumDistanceMetres = raw.criteria.maxDistanceM
        routes = Dictionary(uniqueKeysWithValues: raw.routes.map { key, route in
            (key, Route(key: key, system: route.system, lineId: route.lineId, name: route.name))
        })
        // The site skips a station without a two-number position.
        stations = raw.stations.keys.sorted().compactMap { key in
            let station = raw.stations[key]!
            guard station.position.count == 2 else { return nil }
            return Station(
                key: key,
                system: station.system,
                stationId: station.stationId,
                name: station.name,
                normalizedName: station.normalizedName,
                coordinate: RealRailways.Coordinate(latitude: station.position[0], longitude: station.position[1]),
                routes: station.routes ?? [],
                transferId: station.transferId
            )
        }
        groups = Dictionary(raw.transferStations.map { ($0.id, Group(id: $0.id, normalizedName: $0.normalizedName, members: $0.members, routes: $0.routes)) }, uniquingKeysWith: { first, _ in first })
        var bySystemName: [String: [Int]] = [:], byName: [String: [Int]] = [:]
        for (index, station) in stations.enumerated() {
            bySystemName["\(station.system)|\(station.normalizedName)", default: []].append(index)
            byName[station.normalizedName, default: []].append(index)
        }
        stationsBySystemName = bySystemName
        stationsByName = byName
        stationsByKey = Dictionary(stations.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The site's `transferStationName(name)`: NFKC, 臺 as 台, without a
    /// leading 高鐵 or 台鐵 or a trailing 火車站, 車站 or 站, trimmed.
    public static func transferStationName(_ name: String) -> String {
        var key = name.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "臺", with: "台")
        for prefix in ["高鐵", "台鐵"] where key.hasPrefix(prefix) {
            key.removeFirst(prefix.count)
            break
        }
        // Each replace runs once, in turn, as the site's chain does.
        for suffix in ["火車站", "車站", "站"] where key.hasSuffix(suffix) {
            key.removeLast(suffix.count)
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The site's `haversineKm`, in metres (a 6,371 km Earth): the
    /// distance its 450 m rule is measured with.
    public static func distanceMetres(_ a: RealRailways.Coordinate, _ b: RealRailways.Coordinate) -> Double {
        let r = 6_371.0, toRadians = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * toRadians, dLon = (b.longitude - a.longitude) * toRadians
        let x = pow(sin(dLat / 2), 2) + cos(a.latitude * toRadians) * cos(b.latitude * toRadians) * pow(sin(dLon / 2), 2)
        return 2 * r * asin(sqrt(x)) * 1_000
    }

    /// The site's `transferAnchorNear(stop)`: the nearest station of any
    /// system with the same name (``transferStationName(_:)``) closer than
    /// ``maximumDistanceMetres``.
    public func station(named name: String, near coordinate: RealRailways.Coordinate) -> Station? {
        let key = Self.transferStationName(name)
        guard !key.isEmpty else { return nil }
        return nearest(stationsByName[key] ?? [], to: coordinate)
    }

    /// The site's `transferAnchorForStop(system, stop)`: the same, among
    /// the stations of TDX system `system` only.
    public func station(inSystem system: String, named name: String, near coordinate: RealRailways.Coordinate) -> Station? {
        nearest(stationsBySystemName["\(system)|\(Self.transferStationName(name))"] ?? [], to: coordinate)
    }

    private func nearest(_ candidates: [Int], to coordinate: RealRailways.Coordinate) -> Station? {
        var best: (station: Station, metres: Double)?
        for index in candidates {
            let station = stations[index]
            let metres = Self.distanceMetres(coordinate, station.coordinate)
            if metres < maximumDistanceMetres, best == nil || metres < best!.metres {
                best = (station, metres)
            }
        }
        return best?.station
    }

    /// The transfer station `station` belongs to.
    public func group(of station: Station) -> Group? {
        station.transferId.flatMap { groups[$0] }
    }

    /// The site's `transferRoutesAt(anchor, skip)` as
    /// `transferRoutesAtStation` calls it: the routes of the transfer
    /// station `station` belongs to (or its own), without those of its own
    /// system, once each.
    public func transferRoutes(at station: Station) -> [Route] {
        var result: [Route] = []
        for key in group(of: station)?.routes ?? station.routes {
            guard let route = routes[key], route.system != station.system, !result.contains(where: { $0.key == key }) else { continue }
            result.append(route)
        }
        return result
    }

    /// The other stations of the transfer station `station` belongs to:
    /// their systems' codes for the same place.
    public func partners(of station: Station) -> [Station] {
        guard let group = group(of: station) else { return [] }
        return group.members.filter { $0 != station.key }.compactMap { stationsByKey[$0].map { stations[$0] } }
    }
}
