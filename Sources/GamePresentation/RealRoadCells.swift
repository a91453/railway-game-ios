import Foundation
import GameCore

/// Decision 400 B.1 and its sequel: which 64 m cells of a real-world map's
/// land have a road, read from the base map's `transportation` layer (the
/// file the 2D map and the 3D map draw, ``BaseMapTiles``) as the land is
/// read in. GameCore keeps only the result (``GameWorld/setRoads(_:in:)``).
///
/// A cell has a road when one of the base map's roads crosses it: the
/// OpenMapTiles classes the 3D map draws (``Map3DBaseMap/roadKind(_:)``),
/// service roads too, a road in a tunnel not (no stop or station road can
/// reach it from the cell above). The national freeways and expressways
/// (`motorway` and `trunk`, their links too) are not the roads a town's
/// buses or a station road use (the author's choice B, 2026-10-24): they
/// are kept apart as ``Cells/highways``, tunnels and all, for the
/// intercity buses to come, and never saved. Whether a road is on a bridge
/// counts only in 3D (decision 391).
///
/// The references have no road grid read from vector tiles (gap): the
/// island city's roads are laid by the player cell by cell, and the
/// location modeler only draws its tiles' roads (`RKFAR.build`, the class
/// list and tunnels left out, which ``Map3DBaseMap`` ported). The cells a
/// line crosses are the project's own: points along it every
/// ``sampleMetres``.
enum RealRoadCells {
    /// The road cells and the highway cells of some blocks.
    struct Cells: Hashable, Sendable {
        var roads: Set<CellPosition> = []
        var highways: Set<CellPosition> = []
    }

    /// How far apart a line's points are looked at, in metres: an eighth
    /// of a cell, so a road clips a cell's corner by less than this before
    /// it is missed.
    static let sampleMetres = 8.0

    /// Whether a road of `kind` is a freeway or an expressway, which buses
    /// in town do not take.
    static func isHighway(_ kind: Map3DBaseMap.RoadKind) -> Bool {
        kind == .motorway || kind == .trunk
    }

    /// The base map's tile grid laid over a world, in metres from the
    /// world's north-west corner (x east, z south), as ``Map3DBaseMap``
    /// lays it for a scene whose origin is that corner.
    struct Projection: Sendable {
        let pointsPerMetre: Double
        let anchorX: Double, anchorY: Double
        let shiftX: Double, shiftZ: Double
        let tilePoints: Double

        init(frame: RealWorldFrame) {
            let metre = Double(WorldCoordinate.unitsPerMetre)
            let latitude = frame.anchor.latitudeDegrees
            pointsPerMetre = RealWorldFrame.worldPoints / (2 * Double.pi * RealWorldFrame.earthRadius * cos(latitude * .pi / 180))
            anchorX = RealWorldFrame.mercatorX(frame.anchor.longitudeDegrees)
            anchorY = RealWorldFrame.mercatorY(latitude)
            shiftX = frame.middleX / metre
            shiftZ = frame.middleY / metre
            tilePoints = RealWorldFrame.worldPoints / Double(1 << BaseMapTiles.zoom)
        }

        /// The tile column holding `x` metres east of the world's corner.
        func column(_ x: Double) -> Int { Int((((x - shiftX) * pointsPerMetre + anchorX) / tilePoints).rounded(.down)) }
        /// The tile row holding `z` metres south of it.
        func row(_ z: Double) -> Int { Int((((z - shiftZ) * pointsPerMetre + anchorY) / tilePoints).rounded(.down)) }

        /// Where tile `column`, `row` lies: its west edge and north edge, in
        /// metres, and a tile unit of a layer of `extent` in metres.
        func place(column: Int, row: Int, extent: Int) -> (west: Double, north: Double, scale: Double) {
            ((Double(column) * tilePoints - anchorX) / pointsPerMetre + shiftX,
             (Double(row) * tilePoints - anchorY) / pointsPerMetre + shiftZ,
             tilePoints / Double(extent) / pointsPerMetre)
        }
    }

    /// The roads of `blocks` of a world of `bounds` laid on the Earth by
    /// `frame`, from `tiles`. A tile that fails to read is left out, as
    /// the 3D map leaves it out.
    static func read(blocks: Set<LandBlock>, tiles: BaseMapTiles, frame: RealWorldFrame, bounds: WorldBounds) -> Cells {
        var cells = Cells()
        guard !blocks.isEmpty else { return cells }
        if Thread.isMainThread { readsOnTheMainThread.add() }
        let projection = Projection(frame: frame)
        let length = Double(Land.blockLength) / Double(WorldCoordinate.unitsPerMetre)
        var wanted = Set<TilePosition>()
        for block in blocks {
            let west = Double(block.column) * length, north = Double(block.row) * length
            for row in projection.row(north)...projection.row(north + length) {
                for column in projection.column(west)...projection.column(west + length) {
                    wanted.insert(TilePosition(column: column, row: row))
                }
            }
        }
        for tile in wanted.sorted() {
            guard let bytes = try? tiles.archive.tile(zoom: BaseMapTiles.zoom, x: tile.column, y: tile.row),
                  let decoded = try? VectorTile(bytes, layers: ["transportation"]),
                  let layer = decoded.layers["transportation"]
            else { continue }
            add(layer, column: tile.column, row: tile.row, projection: projection, blocks: blocks, bounds: bounds, to: &cells)
        }
        return cells
    }

    /// How many reads of some blocks ran on the main thread, for the
    /// tests that keep the slow ones off it.
    static let readsOnTheMainThread = ReadCount()

    final class ReadCount: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int { lock.withLock { count } }

        func add() { lock.withLock { count += 1 } }
    }

    struct TilePosition: Hashable, Comparable, Sendable {
        let column: Int, row: Int
        static func < (a: Self, b: Self) -> Bool { (a.row, a.column) < (b.row, b.column) }
    }

    /// Adds the cells of `blocks` the roads of `layer`, tile `column`,
    /// `row`'s `transportation`, cross.
    static func add(
        _ layer: VectorTile.Layer, column: Int, row: Int, projection: Projection, blocks: Set<LandBlock>, bounds: WorldBounds, to cells: inout Cells
    ) {
        let rows = Land.rows(in: bounds), columns = Land.columns(in: bounds)
        let cellMetres = Double(Land.cellLength) / Double(WorldCoordinate.unitsPerMetre)
        let (west, north, scale) = projection.place(column: column, row: row, extent: layer.extent)
        for feature in layer.features where feature.kind == .line {
            guard let kind = Map3DBaseMap.roadKind(feature.string("class")) else { continue }
            let highway = isHighway(kind)
            if !highway, feature.string("brunnel") == "tunnel" { continue }
            for part in feature.parts where part.count >= 2 {
                var last: (x: Double, z: Double)?
                for point in part {
                    let here = (x: west + Double(point.x) * scale, z: north + Double(point.y) * scale)
                    defer { last = here }
                    guard let from = last else { continue }
                    let steps = max(1, Int((hypot(here.x - from.x, here.z - from.z) / sampleMetres).rounded(.up)))
                    for step in 0...steps {
                        let t = Double(step) / Double(steps)
                        let x = from.x + (here.x - from.x) * t, z = from.z + (here.z - from.z) * t
                        guard x >= 0, z >= 0 else { continue }
                        let cell = CellPosition(row: Int(z / cellMetres), column: Int(x / cellMetres))
                        guard cell.row < rows, cell.column < columns, blocks.contains(LandBlock(cellRow: cell.row, column: cell.column)) else { continue }
                        if highway {
                            cells.highways.insert(cell)
                        } else {
                            cells.roads.insert(cell)
                        }
                    }
                }
            }
        }
    }
}

extension GameSession {
    /// Decision 400's sequel: gives `world`'s roads the base map's in every
    /// block whose land is read but whose roads are not, from `baseMap`;
    /// nothing on a map without roads or a frame, or without the base map.
    ///
    /// The blocks `ahead` read already (``roadsReadAhead(of:population:places:water:coverage:baseMap:)``)
    /// are taken from it rather than read again: a block's road cells are
    /// the base map's in that block alone, so the world gets the same
    /// roads either way.
    nonisolated static func readRoads(in world: inout GameWorld, baseMap: BaseMapTiles?, ahead: RoadsReadAhead? = nil) {
        guard let baseMap, let roads = world.roads, let land = world.landBlocks, let frame = RealWorldFrame(world: world) else { return }
        let wanted = Set(land).subtracting(roads.readBlocks)
        guard !wanted.isEmpty else { return }
        var cells: Set<CellPosition>
        if let ahead, ahead.frame == frame, ahead.bounds == world.bounds {
            cells = ahead.roads.filter { wanted.contains(LandBlock(cellRow: $0.row, column: $0.column)) }
            cells.formUnion(RealRoadCells.read(blocks: wanted.subtracting(ahead.blocks), tiles: baseMap, frame: frame, bounds: world.bounds).roads)
        } else {
            cells = RealRoadCells.read(blocks: wanted, tiles: baseMap, frame: frame, bounds: world.bounds).roads
        }
        do throws(GameError) {
            try world.setRoads(cells.sorted(), in: wanted.sorted())
        } catch {
            // The blocks are the world's own, read already, and the cells
            // lie in them, so failing here is a programming error.
            preconditionFailure("Could not read in the roads: \(error)")
        }
    }
}

/// Decision 400's sequel (#1260's rest): the road cells of some blocks of
/// a real-world map, read off the main actor before the world is handed
/// them on it (``GameSession/readRoads(in:baseMap:ahead:)``).
struct RoadsReadAhead: Sendable {
    let frame: RealWorldFrame
    let bounds: WorldBounds
    let blocks: Set<LandBlock>
    let roads: Set<CellPosition>
}

extension GameSession {
    /// The roads ``readLandRoundStations()`` would read from `baseMap`
    /// for `world` with this data: those of the land it has read and the
    /// land it would read. Slow (some 2,500 blocks round the High Speed
    /// Rail's stations take seconds), so read off the main actor; `nil`
    /// when it would read none.
    nonisolated static func roadsReadAhead(
        of world: GameWorld, population: PopulationGrid?, places: PlaceGrid?, water: WaterGrid?, coverage: CoverageGrid?, baseMap: BaseMapTiles?
    ) -> RoadsReadAhead? {
        guard let baseMap, world.roads != nil, let frame = RealWorldFrame(world: world) else { return nil }
        var read = world
        readLand(roundStationsOf: &read, population: population, places: places, water: water, coverage: coverage)
        guard let land = read.landBlocks, let roads = read.roads else { return nil }
        let wanted = Set(land).subtracting(roads.readBlocks)
        guard !wanted.isEmpty else { return nil }
        return RoadsReadAhead(
            frame: frame, bounds: world.bounds, blocks: wanted,
            roads: RealRoadCells.read(blocks: wanted, tiles: baseMap, frame: frame, bounds: world.bounds).roads
        )
    }
}
