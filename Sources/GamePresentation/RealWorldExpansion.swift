import Foundation
import GameCore

// A real place of Taiwan bought tile by tile (ARCHITECTURE decision 167, the
// second step of decision 160): the world is the whole island, as for
// ``WholeTaiwan``, but the company starts with part of it and buys the
// others as its railway grows. Since decision 992 the part is four tiles,
// two by two, about 32 km square round where the player pointed (one tile,
// the 16 km square, before). The tiles' land is read in whole as it starts
// and as each next tile is bought, so the city is there to build to; where
// the player points does not decide how far the map reaches.
//
// GameCore splits any world into tiles from its north-west corner
// (``MapExpansion``), so the world is laid over the island so that the
// four tiles the company starts with are centred on the pick: the corner
// they share is where the player pointed, and every tile is a whole one.
//
// The owner's references have nothing to port (gap), as for decision 160:
// `Ci/`'s "扩建" is a capacity quota. The layout, the step and the rest are
// this project's own.

/// Where a real-world game that buys its map lies (decision 167): the world
/// over the Earth, and the tile the company starts with.
public struct RealWorldExpansion: Hashable, Sendable {
    /// The world's middle on the Earth: not ``WholeTaiwan/anchor``, but the
    /// point that puts the pick at a corner of four tiles.
    public let anchor: GeoAnchor
    /// The world: whole tiles (``MapExpansion/tileLength``), enough to hold
    /// the island's box (``WholeTaiwan``) and the four tiles.
    public let bounds: WorldBounds
    /// Decision 992: the tiles the company starts with, two by two, by row
    /// and then column: the four round the corner at ``pick``.
    public let startTiles: [MapTile]
    /// Where the player pointed.
    public let pick: GeoAnchor

    /// The layout with the corner of the first four tiles at `pick`, or `nil` for
    /// a place outside the box of Taiwan (``WholeTaiwan/contains(latitude:longitude:)``),
    /// which has no people of the app's to fill more than its own square.
    public init?(around pick: GeoAnchor) {
        guard WholeTaiwan.contains(latitude: pick.latitudeDegrees, longitude: pick.longitudeDegrees) else { return nil }
        // Web Mercator map points (the frame's, ``RealWorldFrame``): the
        // pick's, and how far the box's edges lie from it.
        let pickX = RealWorldFrame.mercatorX(pick.longitudeDegrees), pickY = RealWorldFrame.mercatorY(pick.latitudeDegrees)
        let reach = Reach(
            west: pickX - RealWorldFrame.mercatorX(WholeTaiwan.west), east: RealWorldFrame.mercatorX(WholeTaiwan.east) - pickX,
            north: pickY - RealWorldFrame.mercatorY(WholeTaiwan.north), south: RealWorldFrame.mercatorY(WholeTaiwan.south) - pickY
        )
        guard reach.west >= 0, reach.east >= 0, reach.north >= 0, reach.south >= 0 else { return nil }

        // The tiles needed depend on the scale, which depends on where the
        // anchor is, which depends on the tiles. First go round to find
        // where the anchor settles, then make sure the tiles it needs are
        // the ones it was solved for, growing them if not.
        var latitude = WholeTaiwan.anchor.latitudeDegrees
        for _ in 0..<4 {
            guard let solved = Solution(Grid(reach, atLatitude: latitude), pickX: pickX, pickY: pickY, latitude: latitude) else { return nil }
            if abs(solved.latitude - latitude) < 1e-9 { break }
            latitude = solved.latitude
        }
        var grid = Grid(reach, atLatitude: latitude)
        var settled: Solution?
        for _ in 0..<8 {
            guard let solved = Solution(grid, pickX: pickX, pickY: pickY, latitude: latitude) else { return nil }
            let needed = Grid(reach, atLatitude: solved.latitude)
            if needed.fits(in: grid) {
                settled = solved
                break
            }
            latitude = solved.latitude
            grid = grid.union(needed)
        }
        guard let settled else { return nil }
        anchor = settled.anchor
        bounds = settled.bounds
        startTiles = [
            MapTile(row: grid.north - 1, column: grid.west - 1), MapTile(row: grid.north - 1, column: grid.west),
            MapTile(row: grid.north, column: grid.west - 1), MapTile(row: grid.north, column: grid.west),
        ]
        self.pick = pick
        // The layout must do what it says: the pick at the corner of the
        // four tiles, within a centimetre or so (an anchor is whole
        // ten-millionths of a degree), and the box inside the world.
        let tile = Double(MapExpansion.tileLength)
        let frame = RealWorldFrame(anchor: anchor, bounds: bounds)
        let middle = frame.worldPosition(latitude: pick.latitudeDegrees, longitude: pick.longitudeDegrees)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        guard abs(middle.x - Double(grid.west) * tile) < metre, abs(middle.y - Double(grid.north) * tile) < metre else { return nil }
        let northWest = frame.worldPosition(latitude: WholeTaiwan.north, longitude: WholeTaiwan.west)
        let southEast = frame.worldPosition(latitude: WholeTaiwan.south, longitude: WholeTaiwan.east)
        guard northWest.x >= 0, northWest.y >= 0, southEast.x <= Double(bounds.width), southEast.y <= Double(bounds.height) else { return nil }
    }

    /// The world as a real-world frame (``RealWorldFrame``).
    public var frame: RealWorldFrame {
        RealWorldFrame(anchor: anchor, bounds: bounds)
    }

    // MARK: - The layout

    /// How far the box of Taiwan reaches from the pick, in map points.
    private struct Reach {
        let west: Double
        let east: Double
        let north: Double
        let south: Double
    }

    /// The tiles round the pick's corner: how many lie to its west, east,
    /// north and south, so that the world holds the box; at least one each,
    /// the four the company starts with.
    private struct Grid: Equatable {
        var west: Int
        var east: Int
        var north: Int
        var south: Int

        /// The tiles the box needs where the anchor lies at `latitude`°: the
        /// pick is at a corner of tiles, so a side needs the tiles that
        /// reach its distance, and at least one, a start tile.
        init(_ reach: Reach, atLatitude latitude: Double) {
            let pointsPerTile = Double(MapExpansion.tileLength) * RealWorldExpansion.pointsPerUnit(atLatitude: latitude)
            func tiles(_ distance: Double) -> Int {
                max(1, Int((distance / pointsPerTile).rounded(.up)))
            }
            west = tiles(reach.west)
            east = tiles(reach.east)
            north = tiles(reach.north)
            south = tiles(reach.south)
        }

        func fits(in other: Grid) -> Bool {
            west <= other.west && east <= other.east && north <= other.north && south <= other.south
        }

        func union(_ other: Grid) -> Grid {
            var grid = self
            grid.west = max(west, other.west)
            grid.east = max(east, other.east)
            grid.north = max(north, other.north)
            grid.south = max(south, other.south)
            return grid
        }

        var columns: Int { west + east }
        var rows: Int { north + south }
    }

    /// The anchor that puts the pick at the corner of tiles `grid` gives
    /// it, and the world of its tiles.
    private struct Solution {
        let anchor: GeoAnchor
        let bounds: WorldBounds
        let latitude: Double

        /// `start` is the latitude the scale is first taken at: the
        /// anchor's latitude settles it by going round.
        init?(_ grid: Grid, pickX: Double, pickY: Double, latitude start: Double) {
            let tile = Double(MapExpansion.tileLength)
            guard let bounds = try? WorldBounds(width: Int64(grid.columns) * MapExpansion.tileLength, height: Int64(grid.rows) * MapExpansion.tileLength)
            else { return nil }
            // How far the pick lies east and south of the world's middle,
            // in world units.
            let eastOfMiddle = Double(grid.west) * tile - Double(bounds.width) / 2
            let southOfMiddle = Double(grid.north) * tile - Double(bounds.height) / 2
            var latitude = start
            var anchorX = pickX
            for _ in 0..<32 {
                let scale = RealWorldExpansion.pointsPerUnit(atLatitude: latitude)
                anchorX = pickX - eastOfMiddle * scale
                let next = RealWorldExpansion.latitude(atMercatorY: pickY - southOfMiddle * scale)
                let moved = abs(next - latitude)
                latitude = next
                if moved < 1e-12 { break }
            }
            guard let anchor = GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: RealWorldExpansion.longitude(atMercatorX: anchorX)) else { return nil }
            self.anchor = anchor
            self.bounds = bounds
            self.latitude = latitude
        }
    }

    // MARK: - Web Mercator

    /// Map points (``RealWorldFrame/worldPoints``) in a world unit where the
    /// anchor lies at `latitude`°: a metre of the world is a metre of the
    /// Earth there (``RealWorldFrame/worldPosition(latitude:longitude:)``).
    private static func pointsPerUnit(atLatitude latitude: Double) -> Double {
        RealWorldFrame.worldPoints / (2 * Double.pi * RealWorldFrame.earthRadius * cos(latitude * .pi / 180))
            / Double(WorldCoordinate.unitsPerMetre)
    }

    /// The latitude of the map point row `y` (the inverse of
    /// ``RealWorldFrame/mercatorY(_:)``).
    private static func latitude(atMercatorY y: Double) -> Double {
        asin(tanh((0.5 - y / RealWorldFrame.worldPoints) * 2 * Double.pi)) * 180 / .pi
    }

    /// The longitude of the map point column `x`.
    private static func longitude(atMercatorX x: Double) -> Double {
        x / RealWorldFrame.worldPoints * 360 - 180
    }

    // MARK: - The first tiles' people

    /// What the first tiles' people ask of the map's milestone (decision
    /// 167): ``ridersPerRootTrip`` riders for every whole number of the
    /// square root of the trips a day they make (40 for every 100 residents,
    /// ``StationDemand/tripsPerHundredResidents``), a thousand riders at a
    /// time, from ``minimumRidersStep`` up to the standard 100,000
    /// (``MapExpansion/standardRidersStep``). A tile of Taipei's has some
    /// 4.8 million people and asks the standard; one round Taitung has some
    /// 114,000, whose trips a day are 46,000 at most, and could never carry
    /// the standard 100,000: it asks 21,000.
    ///
    /// The square root because a first line reaches the same few towns
    /// whatever the place: measured on eleven places
    /// (`RealWorldExpansionReportTests.testBuyingARealMap`), a line between
    /// a tile's two densest towns carries 58 to 86 riders a day for every
    /// whole number of that root on its first day, and about twice that by
    /// the days of the year that bring the most riders.
    public static func ridersStep(forResidents residents: Int64) -> Int64 {
        // (Capped so that the sum cannot overflow: no map holds that many.)
        let trips = min(max(0, residents), 1 << 40) * StationDemand.tripsPerHundredResidents / 100
        let carried = ridersPerRootTrip * Int64(Double(trips).squareRoot())
        return min(max(carried / 1_000 * 1_000, minimumRidersStep), MapExpansion.standardRidersStep)
    }

    /// What the first tiles' people ask of the map's milestone, from the
    /// land `population` and `places` give it on this layout's world
    /// (``LandImport``): the residents of the one tile's worth of land
    /// round the pick (``middleBlocks``), through
    /// ``ridersStep(forResidents:)``.
    ///
    /// Decision 992: the same land as when a game started with that one
    /// tile, not the four it starts with now, so a first line unlocks the
    /// next tile as soon as it did (measured with the four: Taichung's,
    /// Tainan's, Kaohsiung's, Taoyuan's and Chiayi's first lines had not
    /// in 30 days).
    public func ridersStep(population: PopulationGrid, places: PlaceGrid?, water: WaterGrid?) -> Int64 {
        let cells = LandImport.cells(in: middleBlocks, population: population, places: places, water: water, frame: frame, bounds: bounds)
        return Self.ridersStep(forResidents: cells.reduce(0) { $0 + $1.residents })
    }

    /// The land blocks of one tile's side centred on the pick, the
    /// corner the four start tiles share: a quarter of each.
    public var middleBlocks: Set<LandBlock> {
        let side = Int(MapExpansion.tileLength / Land.blockLength), corner = startTiles[startTiles.count - 1]
        let row = corner.row * side, column = corner.column * side
        var blocks: Set<LandBlock> = []
        for r in (row - side / 2)..<(row + side / 2) {
            for c in (column - side / 2)..<(column + side / 2) { blocks.insert(LandBlock(row: r, column: c)) }
        }
        return blocks
    }

    /// The fewest riders a tile may ask: the smallest place still has a
    /// railway worth the next tile's price.
    public static let minimumRidersStep: Int64 = 5_000
    /// The riders a day asked for each whole number of the square root of
    /// the first tile's trips a day: 1.3 times a first line's on its first
    /// day, so the first of the busy days unlocks the second tile
    /// (`RealWorldExpansionReportTests.testBuyingARealMap`).
    public static let ridersPerRootTrip: Int64 = 100
}

extension MapTile {
    /// The blocks of land (decision 88) of the tile (decision 160) in a
    /// world of `bounds`: the 16 × 16 of a whole tile, fewer where the world
    /// cuts it, none for a tile outside it.
    func landBlocks(in bounds: WorldBounds) -> [LandBlock] {
        guard row >= 0, column >= 0 else { return [] }
        let length = MapExpansion.tileLength, size = Land.blockLength
        let minX = Int64(column) * length, minY = Int64(row) * length
        let maxX = min(bounds.width, minX + length), maxY = min(bounds.height, minY + length)
        guard minX < maxX, minY < maxY else { return [] }
        let rows = Int(minY / size)..<Int((maxY + size - 1) / size)
        let columns = Int(minX / size)..<Int((maxX + size - 1) / size)
        return rows.flatMap { row in columns.map { LandBlock(row: row, column: $0) } }
    }
}

extension WholeTaiwan {
    /// Whether the point `latitude`°, `longitude`° lies in the box of the
    /// map: the island and Penghu, with the sea round them.
    public static func contains(latitude: Double, longitude: Double) -> Bool {
        (south...north).contains(latitude) && (west...east).contains(longitude)
    }
}

extension GameWorld {
    /// A new game on a real place of Taiwan bought tile by tile (decision
    /// 167): the world of `expansion`, whose company owns its first four
    /// tiles (decision 992), each tile bought beyond them asking `ridersStep`
    /// riders more of its best day.
    /// Its land is read in as it is needed (``WholeTaiwan``): the tiles' as
    /// the game begins (``GameSession/readLandRoundStations()``) and each
    /// tile's as it is bought.
    ///
    /// The stations by the edge of the land owned are outside connections
    /// (decisions 137 and 160), as on a blank map or a 16 km real-world map:
    /// the towns beyond stand in for the tiles not bought yet, and a tile
    /// bought makes the station an ordinary one.
    public static func newRealWorldExpansionGame(
        _ expansion: RealWorldExpansion, ridersStep: Int64, balance: Money = startingBalance, eventSeed: UInt32 = 1
    ) -> GameWorld {
        var world = newGame(anchor: expansion.anchor, bounds: expansion.bounds, balance: balance, eventSeed: eventSeed, land: [])
        world.setLandOnDemand()
        do throws(GameError) {
            try world.enableMapExpansion(owning: expansion.startTiles, townSeed: nil, ridersStep: ridersStep)
        } catch {
            // A tile of the world, nothing built, a step in range.
            preconditionFailure("Could not buy the map of a real place: \(error)")
        }
        return world
    }
}
