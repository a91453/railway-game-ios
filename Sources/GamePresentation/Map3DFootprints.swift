import Foundation
import GameCore

// Decision 389: Overture's building footprints of Taiwan (decision 386's
// tiles, `tools/overture-footprint-tiles/`) in the 3D map of a real-world
// game: every building where it stands, raised to its storeys in decision
// 239's look, and the game's own houses only where there are none.

/// The app's footprint tiles (`taiwan_buildings.pmtiles`, decision 386):
/// one z16 tile per 553–568 m square of Taiwan, Penghu, Kinmen and Matsu.
public struct FootprintTiles: Sendable {
    let archive: PMTilesArchive

    /// The footprints in `data`, the file's bytes (best mapped, not read).
    public init(data: Data) throws {
        archive = try PMTilesArchive(data: data)
    }

    static let zoom = 16
    /// A tile's units a side, as a vector tile's extent.
    static let extent = 4096
}

/// The buildings of the footprint tiles over a part of a real-world map.
struct Map3DFootprints: Sendable {
    /// Where a building's storeys came from (the tool's `STOREYS_FROM`),
    /// the order decision 386's point 6 takes them in.
    enum StoreysFrom: Int, Sendable {
        /// The density of people round it, its size and use, GHSL picking
        /// high or low.
        case guess
        /// OpenStreetMap's tags.
        case tags
        /// A city's building map (Taichung's of 2022).
        case cityMap
        /// Taipei's building permit map.
        case permits
        /// The national 3D buildings (NLSC), kept for later.
        case nlsc
    }

    struct Building: Sendable {
        /// 0 when unknown.
        let storeys: Int
        let storeysFrom: StoreysFrom
        /// Overture's use (the tool's `USES`, from 1); 0 when unknown.
        let use: Int
        /// The outline then its holes, in world units.
        let rings: [[(x: Double, y: Double)]]
    }

    enum Failure: Error, Equatable {
        case malformed
    }

    let buildings: [Building]

    init(buildings: [Building]) {
        self.buildings = buildings
    }

    /// The buildings of the tiles that reach `region` (world units) of the
    /// world laid on the Earth by `frame`. A building belongs to the tile
    /// its middle is in, so every building whose middle is in `region` is
    /// among them. Tiles that fail to read are left out.
    init(tiles: FootprintTiles, frame: RealWorldFrame, region: WorldRegion) {
        let zoom = FootprintTiles.zoom, extent = Double(FootprintTiles.extent)
        let anchorLatitude = frame.anchor.latitudeDegrees
        let pointsPerMetre = RealWorldFrame.worldPoints / (2 * Double.pi * RealWorldFrame.earthRadius * cos(anchorLatitude * .pi / 180))
        let anchorX = RealWorldFrame.mercatorX(frame.anchor.longitudeDegrees), anchorY = RealWorldFrame.mercatorY(anchorLatitude)
        let tilePoints = RealWorldFrame.worldPoints / Double(1 << zoom)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        // A world unit to a map point, and back: Mercator is linear about
        // the anchor (`worldPosition(latitude:longitude:)`).
        func tile(_ world: Double, middle: Double, anchor: Double) -> Int {
            Int((((world - middle) / metre * pointsPerMetre + anchor) / tilePoints).rounded(.down))
        }
        let columns = tile(region.minX, middle: frame.middleX, anchor: anchorX)...tile(region.maxX, middle: frame.middleX, anchor: anchorX)
        let rows = tile(region.minY, middle: frame.middleY, anchor: anchorY)...tile(region.maxY, middle: frame.middleY, anchor: anchorY)
        var buildings: [Building] = []
        for row in rows {
            for column in columns {
                guard let bytes = try? tiles.archive.tile(zoom: zoom, x: column, y: row),
                      let decoded = try? Self.decode(bytes) else { continue }
                let scale = tilePoints / extent / pointsPerMetre * metre
                let west = frame.middleX + (Double(column) * tilePoints - anchorX) / pointsPerMetre * metre
                let north = frame.middleY + (Double(row) * tilePoints - anchorY) / pointsPerMetre * metre
                for building in decoded {
                    buildings.append(Building(storeys: building.storeys, storeysFrom: building.storeysFrom, use: building.use,
                                              rings: building.rings.map { $0.map { (west + Double($0.x) * scale, north + Double($0.y) * scale) } }))
                }
            }
        }
        self.buildings = buildings
    }

    /// A tile's buildings, in its own units (`footprints/2`, the tool's
    /// `encode_tile`).
    static func decode(_ bytes: [UInt8]) throws(Failure) -> [(storeys: Int, storeysFrom: StoreysFrom, use: Int, rings: [[(x: Int, y: Int)]])] {
        var at = 0
        func varint() throws(Failure) -> Int {
            var value = 0, shift = 0
            while true {
                guard at < bytes.count, shift < 63 else { throw .malformed }
                let byte = bytes[at]
                at += 1
                value |= Int(byte & 0x7F) << shift
                if byte < 0x80 { return value }
                shift += 7
            }
        }
        func signed() throws(Failure) -> Int {
            let value = try varint()
            return (value >> 1) ^ -(value & 1)
        }
        guard try varint() == 2 else { throw .malformed }
        let count = try varint()
        guard count <= bytes.count else { throw .malformed }
        var cursor = (x: 0, y: 0)
        var out: [(storeys: Int, storeysFrom: StoreysFrom, use: Int, rings: [[(x: Int, y: Int)]])] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            let attributes = try varint()
            let ringCount = try varint()
            guard ringCount <= bytes.count else { throw .malformed }
            var rings: [[(x: Int, y: Int)]] = []
            for _ in 0..<ringCount {
                let points = try varint()
                guard points <= bytes.count else { throw .malformed }
                var ring: [(x: Int, y: Int)] = []
                ring.reserveCapacity(points)
                for _ in 0..<points {
                    cursor.x += try signed()
                    cursor.y += try signed()
                    ring.append(cursor)
                }
                rings.append(ring)
            }
            out.append((attributes >> 8, StoreysFrom(rawValue: attributes >> 5 & 7) ?? .guess, attributes >> 1 & 15, rings))
        }
        guard at == bytes.count else { throw .malformed }
        return out
    }
}

extension Map3DFootprints.Building {
    /// Its storeys, 2 when unknown (the tool gives every building some).
    var drawnStoreys: Int { storeys > 0 ? storeys : 2 }

    /// What it is drawn as, by its use (the tool's `USES`) and storeys.
    var kind: Map3DScene.Builder.RealKind {
        switch use {
        case 1, 6, 9: .industry                       // agricultural, industrial, outbuilding
        case 2, 4, 7, 8, 12: .civic                   // civic, education, medical, military, service
        case 3, 5: drawnStoreys > 5 ? .office : .shophouse  // commercial, entertainment
        case 10: .temple                              // religious
        case 13: .transport                           // transportation
        default: drawnStoreys > 5 ? .flats : .house   // residential, unknown
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 389: `footprints`' buildings whose middles are in the
    /// scene, but those reaching cells in `cleared` (the track's and the
    /// stations') or with their middles on cells in `taken` (the real
    /// buildings, temples and kits' scenes before them). Returns the 64 m
    /// cells under them, which keep no city lot.
    @discardableResult
    mutating func addFootprints(_ footprints: Map3DFootprints, clearOf cleared: Set<Map3DScene.ChunkKey>,
                                takenBy taken: Set<Map3DScene.ChunkKey>) -> Set<Map3DScene.ChunkKey> {
        var standing = Set<Map3DScene.ChunkKey>()
        let cell = Double(Land.cellLength)
        func key(_ x: Double, _ y: Double) -> Map3DScene.ChunkKey {
            Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((y / cell).rounded(.down)))
        }
        for building in footprints.buildings {
            guard let outline = building.rings.first, outline.count >= 3 else { continue }
            let middle = (x: outline.reduce(0) { $0 + $1.x } / Double(outline.count), y: outline.reduce(0) { $0 + $1.y } / Double(outline.count))
            guard contains(x: middle.x, y: middle.y), !taken.contains(key(middle.x, middle.y)) else { continue }
            guard !outline.contains(where: { cleared.contains(key($0.x, $0.y)) }) else { continue }
            let low = (x: outline.map(\.x).min() ?? 0, y: outline.map(\.y).min() ?? 0)
            let high = (x: outline.map(\.x).max() ?? 0, y: outline.map(\.y).max() ?? 0)
            for row in key(low.x, low.y).row...key(high.x, high.y).row {
                for column in key(low.x, low.y).column...key(high.x, high.y).column {
                    standing.insert(Map3DScene.ChunkKey(column: column, row: row))
                }
            }
            let rings = building.rings.map { $0.map { point(x: $0.x, y: $0.y, height: 0) } }
            // Cleared for a building of the player's: its cells still keep
            // no city lot.
            guard !onPlacedGround(rings[0]) else { continue }
            let storeys = building.drawnStoreys
            addRealBuilding([rings], ground: ground(x: middle.x, y: middle.y), height: Float(storeys) * Self.storeyHeight,
                            storeys: storeys, kind: building.kind)
        }
        return standing
    }

    /// Decision 386: a storey's height, the tool's `LEVEL_HEIGHT`.
    static let storeyHeight: Float = 3.2
}
