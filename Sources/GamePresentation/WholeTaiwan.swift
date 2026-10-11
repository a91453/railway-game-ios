import Foundation
import GameCore

/// A real-world map of the whole of Taiwan (decision 88): the main island
/// and Penghu, with Green Island, Orchid Island and the islets off the
/// coast in the same box; Kinmen and Matsu, off the coast of the mainland,
/// would make the map much wider, mostly sea, and are left out.
///
/// The map is the box's middle (``anchor``) and as much world round it as
/// the box reaches (``bounds``), laid over the Earth as any real-world map
/// (``RealWorldFrame``, Web Mercator at the anchor's latitude: a
/// kilometre on the ground counts as some 1.012 km at Keelung and 0.988 km
/// at Eluanbi, which the game does not correct yet).
///
/// Its land is read in as it is needed: some 5 million 64 m cells of people
/// are too many to spread out when the game starts, so it starts with none,
/// and the land within ``landReach`` of each station comes in as the
/// station is built (``GameSession/readLandRoundStations()``).
public enum WholeTaiwan {
    /// The box, in degrees: west of Penghu's Huayu to east of Sandiao Cape,
    /// north of Fugui Cape and Keelung Islet to south of Eluanbi.
    public static let west = 119.25
    public static let east = 122.05
    public static let north = 25.35
    public static let south = 21.85

    /// The middle of the box: halfway in longitude, and at the latitude
    /// halfway between its edges in Web Mercator, so the box lies evenly
    /// round it.
    public static let anchor: GeoAnchor = {
        let y = (RealWorldFrame.mercatorY(north) + RealWorldFrame.mercatorY(south)) / 2
        let latitude = asin(tanh((0.5 - y / RealWorldFrame.worldPoints) * 2 * Double.pi)) * 180 / .pi
        guard let anchor = GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: (west + east) / 2) else {
            preconditionFailure("The middle of Taiwan is not on the Earth.")
        }
        return anchor
    }()

    /// The world round ``anchor`` that holds the box, in whole world units:
    /// twice the farther of each pair of edges, rounded up.
    public static let bounds: WorldBounds = {
        let frame = RealWorldFrame(anchor: anchor, bounds: .standard)
        let corners = [(north, west), (south, east)].map { frame.worldPosition(latitude: $0.0, longitude: $0.1) }
        let halfWidth = corners.map { abs($0.x - frame.middleX) }.max() ?? 0
        let halfHeight = corners.map { abs($0.y - frame.middleY) }.max() ?? 0
        do {
            return try WorldBounds(width: Int64((2 * halfWidth).rounded(.up)), height: Int64((2 * halfHeight).rounded(.up)))
        } catch {
            preconditionFailure("Taiwan does not fit in a world: \(error)")
        }
    }()

    /// How far round a station its land is read in: 2 km, the farthest a
    /// town round it is likely to reach, two and a half times its 800 m
    /// catchment.
    public static let landReach: Int64 = 2_000 * WorldCoordinate.unitsPerMetre
}

extension GameWorld {
    /// A new game on the whole of Taiwan (decision 88): ``newGame(anchor:bounds:balance:eventSeed:land:)``
    /// on ``WholeTaiwan/bounds`` round ``WholeTaiwan/anchor``, with its
    /// land read in as it is needed, none yet.
    public static func newWholeTaiwanGame(eventSeed: UInt32 = 1) -> GameWorld {
        var world = newGame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds, eventSeed: eventSeed, land: [])
        world.setLandOnDemand()
        return world
    }
}

extension GameSession {
    /// Reads in the land within ``WholeTaiwan/landReach`` of every station
    /// of `world` whose blocks are not read yet, on a map whose land is
    /// read in as it is needed (decision 88), from `population` and
    /// `places` (``LandImport/cells(in:population:places:water:frame:bounds:)``)
    /// and, since decision 105, the blocks' `water`
    /// (``WaterGrid/cells(frame:bounds:in:)``) and, since decision 115,
    /// their steep slopes, and since decision 147 the cells' `coverage`;
    /// nothing for any other map, or without the population.
    ///
    /// Since decision 167 also the whole of every tile the company owns of a
    /// map it buys tile by tile (``GameWorld/mapExpansion``): the first as
    /// the game begins, each next as it is bought (the same edit, so Undo
    /// takes both back).
    static func readLand(
        roundStationsOf world: inout GameWorld, population: PopulationGrid?, places: PlaceGrid?, water: WaterGrid? = nil, coverage: CoverageGrid? = nil
    ) {
        var wanted = blocks(within: WholeTaiwan.landReach, of: world.stations.map(\.location), in: world.bounds)
        if let expansion = world.mapExpansion {
            for tile in expansion.owned {
                wanted.formUnion(tile.landBlocks(in: world.bounds))
            }
        }
        readLand(blocks: wanted, in: &world, population: population, places: places, water: water, coverage: coverage)
    }

    /// Reads in the land within `reach` of each of `points` whose blocks
    /// are not read yet, as ``readLand(roundStationsOf:population:places:water:)``
    /// does round stations: also under a building about to be placed
    /// (decision 95), so it buys out the city's buildings there.
    static func readLand(
        within reach: Int64, of points: [PlanPoint], in world: inout GameWorld, population: PopulationGrid?, places: PlaceGrid?, water: WaterGrid? = nil,
        coverage: CoverageGrid? = nil
    ) {
        readLand(
            blocks: blocks(within: reach, of: points, in: world.bounds), in: &world, population: population, places: places, water: water,
            coverage: coverage
        )
    }

    /// The blocks of a world of `bounds` some part of which lies within
    /// `reach` of one of `points`.
    private static func blocks(within reach: Int64, of points: [PlanPoint], in bounds: WorldBounds) -> Set<LandBlock> {
        var found = Set<LandBlock>()
        for point in points {
            found.formUnion(Land.blocks(within: reach, of: point, in: bounds))
        }
        return found
    }

    /// Reads in whichever of `blocks` the map has not read yet.
    private static func readLand(
        blocks candidates: Set<LandBlock>, in world: inout GameWorld, population: PopulationGrid?, places: PlaceGrid?, water: WaterGrid?,
        coverage: CoverageGrid?
    ) {
        guard let read = world.landBlocks, !candidates.isEmpty, let population, let frame = RealWorldFrame(world: world) else { return }
        let wanted = candidates.subtracting(read)
        guard !wanted.isEmpty else { return }
        var cells = LandImport.cells(in: wanted, population: population, places: places, water: water, frame: frame, bounds: world.bounds)
        // Decision 147: each cell's real coverage, when the app has it.
        if let coverage {
            cells = coverage.covering(cells, frame: frame)
        }
        let wet = water?.cells(frame: frame, bounds: world.bounds, in: wanted) ?? []
        // Decision 115: the steep slopes come from the same file.
        let steep = water?.steepCells(frame: frame, bounds: world.bounds, in: wanted) ?? []
        do throws(GameError) {
            try world.expandLand(wanted.sorted(), cells: cells, water: wet, steep: steep)
        } catch {
            // The blocks are in the world and not read yet, and the cells
            // and the water lie in them, the cells off the water, so
            // failing here is a programming error.
            preconditionFailure("Could not read in the land: \(error)")
        }
    }
}
