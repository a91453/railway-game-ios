import Foundation
import GameCore

// What there is around a place on a real-world map in Taiwan, and the kind
// of place a managed company's new station there serves (2026-10-05, the
// author's request: a station by the shops is a shopping one, by the offices
// and schools an office one, by the sights a scenic one).
//
// The places are OpenStreetMap's (ODbL 1.0), counted on WorldPop's grid
// (the population grid's own cells) and bundled as
// `Resources/RealWorld/taiwan_places.json` by
// `tools/real-world-population/build_place_grid.py`. The `Ci/` reference's
// kinds are the player's choice (its station-flow presets); deciding one
// from what is around a station is the app's own (gap), and so are the
// thresholds below.
//
// Like the population, only the presentation reads it: the kind is given
// through `GameWorld.setStationDemand(_:to:)` with the ridership.

/// OpenStreetMap's places per cell of WorldPop's grid of Taiwan.
public struct PlaceGrid: Sendable {
    /// What is counted: shops (with restaurants, cafés and markets),
    /// offices, schools (with universities and colleges), and sights
    /// (attractions, museums, viewpoints, zoos, aquariums, galleries and
    /// theme parks).
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case shops, offices, schools, attractions
    }

    let layers: [Kind: GridCounts]

    /// Reads the app's places file: the grid's north-west corner and cell
    /// size, and runs of places per cell for every kind. Throws for a
    /// file out of shape, a missing kind or a negative count.
    public init(data: Data) throws {
        struct File: Decodable {
            let north: Double
            let west: Double
            let cellDegrees: Double
            let layers: [String: [GridCounts.Run]]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        var layers: [Kind: GridCounts] = [:]
        for kind in Kind.allCases {
            guard let runs = file.layers[kind.rawValue] else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No \(kind.rawValue) in the places file."))
            }
            layers[kind] = try GridCounts(north: file.north, west: file.west, cellDegrees: file.cellDegrees, runs: runs)
        }
        self.layers = layers
    }

    /// Every place of `kind` in the grid.
    public func total(of kind: Kind) -> Int {
        layers[kind]?.total ?? 0
    }

    /// The places of each kind within `radius` metres of `latitude`°
    /// north, `longitude`° east, each cell counting by the share of the
    /// circle in it (so not whole numbers).
    public func places(within radius: Double, ofLatitude latitude: Double, longitude: Double) -> [Kind: Double] {
        layers.mapValues { $0.count(within: radius, ofLatitude: latitude, longitude: longitude) }
    }
}

extension StationDemandKind {
    /// How many times its share of the country's places (for its
    /// residents) a station's surroundings must have of one kind to serve
    /// that kind rather than homes: tuned on Taiwan's 544 real stations
    /// (2026-10-05), where it made 335 serve homes, 130 shops, 57 sights
    /// and 22 offices; with schools a kind of their own (decision 91), 328
    /// homes, 107 shops, 57 sights, 50 offices and 2 schools.
    public static let realWorldThreshold = 1.5

    /// The fewest places of each kind a station's surroundings are
    /// measured against: a handful of shops in a village is not a
    /// shopping district, however few live there.
    static let realWorldMinimums: [PlaceGrid.Kind: Double] = [.shops: 30, .offices: 5, .schools: 3, .attractions: 1]

    /// The kind of place a station on a real-world map serves, from the
    /// places within its catchment and the people living there.
    ///
    /// For offices, shops, sights and (decision 91, counted with offices
    /// before) schools, the places nearby are compared with what the
    /// station's residents would have at the country's rate (`totals` ÷
    /// `population`), but never with fewer than a minimum (30 shops, 5
    /// offices, 1 sight, 3 schools). The kind most above its expectation
    /// wins if it reaches ``realWorldThreshold`` times it; otherwise the
    /// station serves homes. Ties go to offices, then shops, then sights,
    /// then schools.
    public static func realWorld(
        residents: Int,
        places: [PlaceGrid.Kind: Double],
        totals: [PlaceGrid.Kind: Int],
        population: Int
    ) -> StationDemandKind {
        guard population > 0 else { return .residential }
        func expected(_ kinds: [PlaceGrid.Kind]) -> Double {
            let rate = Double(kinds.map { totals[$0] ?? 0 }.reduce(0, +)) / Double(population)
            let minimum = kinds.map { realWorldMinimums[$0] ?? 0 }.reduce(0, +)
            return max(Double(max(0, residents)) * rate, minimum)
        }
        func nearby(_ kinds: [PlaceGrid.Kind]) -> Double {
            kinds.map { places[$0] ?? 0 }.reduce(0, +)
        }
        let candidates: [(StationDemandKind, [PlaceGrid.Kind])] = [
            (.office, [.offices]),
            (.shopping, [.shops]),
            (.scenic, [.attractions]),
            (.civic, [.schools]),
        ]
        var best: (kind: StationDemandKind, ratio: Double) = (.residential, 0)
        for (kind, sources) in candidates {
            let ratio = nearby(sources) / expected(sources)
            if ratio > best.ratio {
                best = (kind, ratio)
            }
        }
        return best.ratio >= realWorldThreshold ? best.kind : .residential
    }
}
