import Foundation
import GameCore

// Taiwan's place names, which a new station on a real-world map is named
// after when no real station is right there (decision 159).
//
// MapBuilder (`MapBuilder/reference_snapshot/_next/static/chunks/
// 611-2cd22d6d6f5c40f4.js`, `el`, the naming of its rail modes,
// `useAdminName`) asks Overpass for the most local administrative area
// round a new station. The game asks no server while the player builds:
// `tools/place-names/build_place_names.py` reads the names once from the
// same OpenStreetMap extract as the app's other data (ODbL 1.0), and the
// app bundles them as `Resources/RealWorld/taiwan_place_names.json`:
// settlements (hamlets, villages, neighbourhoods: 聚落), villages and wards
// (村里) and the townships' outlines (鄉鎮市區). Only the presentation
// reads them: a name is only a suggestion the player can change.

/// Taiwan's settlements, villages and wards, and townships, from
/// OpenStreetMap.
public struct PlaceNames: Sendable {
    /// A place's names: Chinese, and English where OpenStreetMap has it.
    public struct Name: Hashable, Sendable {
        public let chinese: String
        public let english: String?

        public init(chinese: String, english: String?) {
            self.chinese = chinese
            self.english = english
        }

        /// Its name in `language`: the Chinese one where it has no English
        /// one (MapBuilder's `name:en`, else `name`).
        public func name(in language: DisplayLanguage) -> String {
            language.text(english ?? chinese, chinese)
        }
    }

    /// A named point.
    struct Place: Sendable {
        let name: Name
        let coordinate: RealRailways.Coordinate
    }

    /// A township or district: its names and outline (rings, even-odd).
    struct Township: Sendable {
        let name: Name
        let rings: [[RealRailways.Coordinate]]
        let south, north, west, east: Double

        func contains(_ point: RealRailways.Coordinate) -> Bool {
            guard point.latitude >= south, point.latitude <= north, point.longitude >= west, point.longitude <= east else { return false }
            var inside = false
            for ring in rings {
                var j = ring.count - 1
                for i in ring.indices {
                    let a = ring[i], b = ring[j]
                    if (a.latitude > point.latitude) != (b.latitude > point.latitude),
                       point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                        inside.toggle()
                    }
                    j = i
                }
            }
            return inside
        }
    }

    /// How far a settlement's name reaches.
    public static let settlementReachMetres = 2_000.0
    /// How far a village's or ward's name reaches. They are many and small
    /// and their names more often alike (中山、中正), so one counts as twice
    /// as far as a settlement (``nearby(_:)``).
    public static let wardReachMetres = 1_500.0
    static let wardWeight = 2.0

    /// By latitude, so ``nearby(_:)`` looks only at a band.
    let settlements: [Place]
    let wards: [Place]
    let townships: [Township]

    /// Reads the app's place names file (`build_place_names.py`). Throws for
    /// a file out of shape.
    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.scale > 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Place names need a positive scale."))
        }
        let scale = Double(file.scale)
        func places(_ entries: [File.Entry]) -> [Place] {
            entries.map {
                Place(
                    name: Name(chinese: $0.chinese, english: $0.english),
                    coordinate: RealRailways.Coordinate(latitude: Double($0.latitude) / scale, longitude: Double($0.longitude) / scale)
                )
            }
            .sorted { $0.coordinate.latitude < $1.coordinate.latitude }
        }
        settlements = places(file.places)
        wards = places(file.wards)
        townships = try file.townships.map { township in
            let rings = try township.rings.map { deltas in
                guard deltas.count >= 6, deltas.count.isMultiple(of: 2) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A ring is at least three points, each two numbers."))
                }
                var latitude = 0, longitude = 0
                return stride(from: 0, to: deltas.count, by: 2).map { i in
                    latitude += deltas[i]
                    longitude += deltas[i + 1]
                    return RealRailways.Coordinate(latitude: Double(latitude) / scale, longitude: Double(longitude) / scale)
                }
            }
            let points = rings.joined()
            return Township(
                name: Name(chinese: township.name, english: township.en),
                rings: rings,
                south: points.map(\.latitude).min() ?? 0, north: points.map(\.latitude).max() ?? 0,
                west: points.map(\.longitude).min() ?? 0, east: points.map(\.longitude).max() ?? 0
            )
        }
    }

    /// The settlements within ``settlementReachMetres`` and the villages and
    /// wards within ``wardReachMetres`` of `coordinate`, nearest first (a
    /// ward at twice its distance), each name once.
    public func nearby(_ coordinate: RealRailways.Coordinate) -> [Name] {
        var found: [(name: Name, rank: Double)] = []
        func look(in places: [Place], within reach: Double, weight: Double) {
            // A degree of latitude is at least 110.5 km.
            let band = reach / 110_500
            var low = 0, high = places.count
            while low < high {
                let middle = (low + high) / 2
                if places[middle].coordinate.latitude < coordinate.latitude - band { low = middle + 1 } else { high = middle }
            }
            for place in places[low...] {
                if place.coordinate.latitude > coordinate.latitude + band { break }
                let distance = RealStationTransfers.distanceMetres(coordinate, place.coordinate)
                if distance <= reach {
                    found.append((place.name, distance * weight))
                }
            }
        }
        look(in: settlements, within: Self.settlementReachMetres, weight: 1)
        look(in: wards, within: Self.wardReachMetres, weight: Self.wardWeight)
        found.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.name.chinese < $1.name.chinese }
        var seen = Set<String>()
        return found.map(\.name).filter { seen.insert($0.chinese).inserted }
    }

    /// The township or district `coordinate` is in (MapBuilder's most local
    /// administrative area), or `nil` at sea, abroad, or where
    /// OpenStreetMap's outline could not be read.
    public func township(containing coordinate: RealRailways.Coordinate) -> Name? {
        townships.first { $0.contains(coordinate) }?.name
    }

    private struct File: Decodable {
        struct Entry: Decodable {
            let latitude: Int
            let longitude: Int
            let chinese: String
            let english: String?

            init(from decoder: Decoder) throws {
                var row = try decoder.unkeyedContainer()
                latitude = try row.decode(Int.self)
                longitude = try row.decode(Int.self)
                chinese = try row.decode(String.self)
                english = try row.decodeIfPresent(String.self)
            }
        }

        struct TownshipEntry: Decodable {
            let name: String
            let en: String?
            let rings: [[Int]]
        }

        let scale: Int
        let places: [Entry]
        let wards: [Entry]
        let townships: [TownshipEntry]
    }
}
