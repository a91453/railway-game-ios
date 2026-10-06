import Foundation
import GameCore

// How many people live around a place on a real-world map in Taiwan, and the
// ridership a managed company's new station there gets from them (2026-10-05,
// the author's request: a station should be as busy as the place it serves).
//
// The `Ci/` reference sizes demand on a population grid too: LandScan's
// 300 m grid (`landscan-grid-300m.pmtiles`, its population layer, "LandScan
// 300m 方格"); its server turns the grid into each station's ridership, and
// neither the grid nor the server is in the snapshot. Here the grid is
// WorldPop's 1 km estimates of Taiwan for 2025 (CC BY 4.0), bundled as
// `Resources/RealWorld/taiwan_population.json` by
// `tools/real-world-population/`, and the rate that turns residents into
// trips is the app's own (gap): 40 trips a day for every 100 people within
// 800 m, which gives Banqiao about 31,200 trips a day and Pingxi 200.
//
// Only the presentation reads the grid: the ridership it suggests is given
// through `GameWorld.setStationDemand(_:to:)`, and the world keeps that
// number like any other, so a save never depends on the grid.

/// Counts per cell of a grid of whole fractions of a degree, as WorldPop
/// publishes its population: rows from the north edge, columns from the
/// west edge. The population and the places on real-world maps share it.
struct GridCounts: Sendable {
    struct Cell: Hashable, Sendable {
        let row: Int
        let column: Int
    }

    /// A row's cells with something in them, from column `c` on.
    struct Run: Decodable, Sendable {
        let r: Int
        let c: Int
        let p: [Int]
    }

    let north: Double
    let west: Double
    let cellDegrees: Double
    let counts: [Cell: Int]
    let total: Int

    /// Throws for a grid without a corner or a positive cell size, or a
    /// negative row, column or count.
    init(north: Double, west: Double, cellDegrees: Double, runs: [Run]) throws {
        guard cellDegrees > 0, north.isFinite, west.isFinite else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A grid needs a corner and a positive cell size."))
        }
        var counts: [Cell: Int] = [:]
        var total = 0
        for run in runs {
            for (offset, count) in run.p.enumerated() {
                guard count >= 0, run.r >= 0, run.c >= 0 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Rows, columns and counts are never negative."))
                }
                counts[Cell(row: run.r, column: run.c + offset), default: 0] += count
                total += count
            }
        }
        self.north = north
        self.west = west
        self.cellDegrees = cellDegrees
        self.counts = counts
        self.total = total
    }

    /// How many there are within `radius` metres of `latitude`° north,
    /// `longitude`° east: each cell counts in proportion to how much of the
    /// circle lies in it, sampled every 50 m (each sample stands for an
    /// equal share of the circle's area).
    func count(within radius: Double, ofLatitude latitude: Double, longitude: Double) -> Double {
        guard radius > 0 else { return 0 }
        let step = 50.0
        let steps = Int((radius / step).rounded(.up))
        var density = 0.0
        var samples = 0
        for east in -steps ..< steps {
            for south in -steps ..< steps {
                let x = (Double(east) + 0.5) * step
                let y = (Double(south) + 0.5) * step
                guard x * x + y * y <= radius * radius else { continue }
                samples += 1
                let point = Self.offset(latitude: latitude, longitude: longitude, east: x, south: y)
                let cell = cell(latitude: point.latitude, longitude: point.longitude)
                guard let count = counts[cell], count > 0 else { continue }
                density += Double(count) / area(of: cell)
            }
        }
        guard samples > 0 else { return 0 }
        return density / Double(samples) * Double.pi * radius * radius
    }

    /// Whether a cell within `distance` metres of the place (its middle)
    /// has anything in it.
    func hasAny(within distance: Double, ofLatitude latitude: Double, longitude: Double) -> Bool {
        let centre = cell(latitude: latitude, longitude: longitude)
        let reach = Int((distance / (cellDegrees * Self.metresPerDegreeOfLatitude)).rounded(.up)) + 1
        for row in centre.row - reach ... centre.row + reach {
            for column in centre.column - reach ... centre.column + reach {
                let cell = Cell(row: row, column: column)
                guard let count = counts[cell], count > 0 else { continue }
                let middle = middle(of: cell)
                if Self.metres(fromLatitude: latitude, longitude: longitude, toLatitude: middle.latitude, longitude: middle.longitude) <= distance {
                    return true
                }
            }
        }
        return false
    }

    func cell(latitude: Double, longitude: Double) -> Cell {
        Cell(row: Int(((north - latitude) / cellDegrees).rounded(.down)), column: Int(((longitude - west) / cellDegrees).rounded(.down)))
    }

    func middle(of cell: Cell) -> (latitude: Double, longitude: Double) {
        (north - (Double(cell.row) + 0.5) * cellDegrees, west + (Double(cell.column) + 0.5) * cellDegrees)
    }

    /// A cell's area on the ground, in square metres.
    func area(of cell: Cell) -> Double {
        let latitude = middle(of: cell).latitude
        return cellDegrees * Self.metresPerDegreeOfLatitude * cellDegrees * Self.metresPerDegreeOfLongitude(at: latitude)
    }

    // A local flat Earth is enough at a few kilometres.
    static let metresPerDegreeOfLatitude = 110_574.0

    static func metresPerDegreeOfLongitude(at latitude: Double) -> Double {
        111_320.0 * cos(latitude * .pi / 180)
    }

    static func offset(latitude: Double, longitude: Double, east: Double, south: Double) -> (latitude: Double, longitude: Double) {
        (latitude - south / metresPerDegreeOfLatitude, longitude + east / metresPerDegreeOfLongitude(at: latitude))
    }

    static func metres(fromLatitude a: Double, longitude b: Double, toLatitude c: Double, longitude d: Double) -> Double {
        let south = (a - c) * metresPerDegreeOfLatitude
        let east = (d - b) * metresPerDegreeOfLongitude(at: a)
        return (south * south + east * east).squareRoot()
    }

    /// Queries non-empty population cells within the given geographic bounding box.
    func cells(inNorth northLimit: Double, south southLimit: Double, west westLimit: Double, east eastLimit: Double) -> [PopulationCell] {
        guard cellDegrees > 0 else { return [] }
        let highLat = max(northLimit, southLimit)
        let lowLat = min(northLimit, southLimit)
        let lowLon = min(westLimit, eastLimit)
        let highLon = max(westLimit, eastLimit)

        let minRow = max(0, Int(((north - highLat) / cellDegrees).rounded(.down)))
        let maxRow = max(minRow, Int(((north - lowLat) / cellDegrees).rounded(.up)))
        let minCol = max(0, Int(((lowLon - west) / cellDegrees).rounded(.down)))
        let maxCol = max(minCol, Int(((highLon - west) / cellDegrees).rounded(.up)))

        var result: [PopulationCell] = []
        for r in minRow...maxRow {
            for c in minCol...maxCol {
                let cell = Cell(row: r, column: c)
                guard let count = counts[cell], count > 0 else { continue }
                let cellNorth = north - Double(r) * cellDegrees
                let cellSouth = cellNorth - cellDegrees
                let cellWest = west + Double(c) * cellDegrees
                let cellEast = cellWest + cellDegrees
                let midLat = cellNorth - 0.5 * cellDegrees
                let midLon = cellWest + 0.5 * cellDegrees
                result.append(PopulationCell(
                    row: r,
                    column: c,
                    count: count,
                    centerLatitude: midLat,
                    centerLongitude: midLon,
                    northLatitude: cellNorth,
                    southLatitude: cellSouth,
                    westLongitude: cellWest,
                    eastLongitude: cellEast
                ))
            }
        }
        return result
    }
}

/// A single cell of the population grid for overlay visualization.
public struct PopulationCell: Equatable, Hashable, Sendable {
    public let row: Int
    public let column: Int
    public let count: Int
    public let centerLatitude: Double
    public let centerLongitude: Double
    public let northLatitude: Double
    public let southLatitude: Double
    public let westLongitude: Double
    public let eastLongitude: Double

    public init(
        row: Int,
        column: Int,
        count: Int,
        centerLatitude: Double,
        centerLongitude: Double,
        northLatitude: Double,
        southLatitude: Double,
        westLongitude: Double,
        eastLongitude: Double
    ) {
        self.row = row
        self.column = column
        self.count = count
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.northLatitude = northLatitude
        self.southLatitude = southLatitude
        self.westLongitude = westLongitude
        self.eastLongitude = eastLongitude
    }
}

/// People per cell of WorldPop's grid of Taiwan.
public struct PopulationGrid: Sendable {
    let people: GridCounts

    /// Everyone in the grid.
    public var total: Int {
        people.total
    }

    /// Reads the app's grid file: its north-west corner, cell size in
    /// degrees, and runs of people per cell along a row. Throws for a file
    /// out of shape or a negative count.
    public init(data: Data) throws {
        struct File: Decodable {
            let north: Double
            let west: Double
            let cellDegrees: Double
            let runs: [GridCounts.Run]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        people = try GridCounts(north: file.north, west: file.west, cellDegrees: file.cellDegrees, runs: file.runs)
    }

    /// How far around a place the grid must have someone living for the
    /// place to count as covered, in metres: farther than this from
    /// anyone, a place is taken to be outside the grid's country (WorldPop
    /// counts one country), not empty land in it.
    public static let coverage = 5_000.0

    /// The people living within `radius` metres of `latitude`° north,
    /// `longitude`° east, to the nearest person (see
    /// ``GridCounts/count(within:ofLatitude:longitude:)``). `nil` where the
    /// grid does not cover the place (no one lives within ``coverage`` of
    /// it).
    public func people(within radius: Double, ofLatitude latitude: Double, longitude: Double) -> Int? {
        guard radius > 0, people.hasAny(within: Self.coverage, ofLatitude: latitude, longitude: longitude) else { return nil }
        return Int(people.count(within: radius, ofLatitude: latitude, longitude: longitude).rounded())
    }

    /// Non-empty cells of the grid within the given geographic bounding box.
    public func cells(north: Double, south: Double, west: Double, east: Double) -> [PopulationCell] {
        people.cells(inNorth: north, south: south, west: west, east: east)
    }
}

extension StationDemand {
    /// How far from a station on a real-world map its residents live, in
    /// metres: about ten minutes' walk.
    public static let catchmentRadius = 800.0

    /// The trips a day a station on a real-world map gets for every 100
    /// people living within ``catchmentRadius``.
    public static let tripsPerHundredResidents: Int64 = 40

    /// The ridership a managed company's station on a real-world map gets
    /// from the people living around it: of `kind` (homes unless the
    /// places around it say otherwise, see
    /// ``StationDemandKind/realWorld(residents:places:totals:population:)``),
    /// 40 trips a day for every 100 residents, to the nearest 100 trips and
    /// at least 100 (the smallest of ``dailyTripSteps``), at most
    /// ``maximumDailyTrips``.
    public static func realWorld(residents: Int, kind: StationDemandKind = .residential) -> StationDemand {
        let trips = Int64(max(0, residents)) * tripsPerHundredResidents / 100
        let rounded = (trips + 50) / 100 * 100
        return StationDemand(kind: kind, dailyTrips: min(max(rounded, 100), maximumDailyTrips))
    }
}

extension RealWorldFrame {
    /// The place on the Earth at the world point (`x`, `y`), in degrees:
    /// the inverse of ``worldPosition(latitude:longitude:)``.
    public func coordinate(worldX x: Double, worldY y: Double) -> (latitude: Double, longitude: Double) {
        let anchorLatitude = anchor.latitudeDegrees
        let pointsPerMetre = Self.worldPoints / (2 * Double.pi * Self.earthRadius * cos(anchorLatitude * .pi / 180))
        let metres = metresFromAnchor(worldX: x, worldY: y)
        let mercatorX = Self.mercatorX(anchor.longitudeDegrees) + metres.east * pointsPerMetre
        let mercatorY = Self.mercatorY(anchorLatitude) + metres.south * pointsPerMetre
        let longitude = mercatorX / Self.worldPoints * 360 - 180
        let latitude = asin(tanh((0.5 - mercatorY / Self.worldPoints) * 2 * Double.pi)) * 180 / .pi
        return (latitude, longitude)
    }
}
