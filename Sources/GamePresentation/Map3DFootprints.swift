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
    /// Decision 712: the buildings of the cities outside Taiwan (their
    /// map packs' `buildings.pmtiles`), each asked where the one before
    /// has no tile.
    let cities: [PMTilesArchive]

    /// The footprints in `data`, the file's bytes (best mapped, not read),
    /// with those of `cities`; a city's file that cannot be read is left
    /// out.
    public init(data: Data, cities: [Data] = []) throws {
        archive = try PMTilesArchive(data: data)
        self.cities = cities.compactMap { try? PMTilesArchive(data: $0) }
    }

    /// The tile's bytes: Taiwan's, or the first city's that has it.
    func tile(x: Int, y: Int) -> [UInt8]? {
        for archive in [archive] + cities {
            if let bytes = try? archive.tile(zoom: Self.zoom, x: x, y: y) { return bytes }
        }
        return nil
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
        /// Decision 729: the Lands Department's measured heights (Hong
        /// Kong's map).
        case landsd
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
                guard let bytes = tiles.tile(x: column, y: row),
                      let decoded = try? Self.decode(bytes) else { continue }
                let scale = tilePoints / extent / pointsPerMetre * metre
                let west = frame.middleX + (Double(column) * tilePoints - anchorX) / pointsPerMetre * metre
                let north = frame.middleY + (Double(row) * tilePoints - anchorY) / pointsPerMetre * metre
                for building in Self.withoutDuplicates(decoded) {
                    buildings.append(Building(storeys: building.storeys, storeysFrom: building.storeysFrom, use: building.use,
                                              rings: building.rings.map { $0.map { (west + Double($0.x) * scale, north + Double($0.y) * scale) } }))
                }
            }
        }
        self.buildings = buildings
    }

    /// The owner's report on 133 (an iPad, a corner tower whose walls
    /// showed two window grids at once and a shopfront's ghost): a tile's
    /// buildings without the second of two outlines of the same building.
    /// OpenStreetMap maps some buildings twice (an outline and a part of
    /// the same shape, or two ways), and Overture keeps both: 2,328 pairs
    /// in the app's tiles of 2026-11 overlap by more than half the smaller,
    /// 194 of them over 100 m² and of much the same size. Drawn twice, each
    /// with its own storeys and use, their walls lie in one plane and
    /// flicker between the two. Two outlines are one building when each
    /// one's box covers at least ``duplicateShare`` of the other's and
    /// their areas differ by less than ``duplicateSizes``; the one with
    /// more storeys is kept (the first of equals). A smaller part inside a
    /// larger building, a tower on its podium, is not of the same size and
    /// stays.
    static func withoutDuplicates(_ decoded: [(storeys: Int, storeysFrom: StoreysFrom, use: Int, rings: [[(x: Int, y: Int)]])])
        -> [(storeys: Int, storeysFrom: StoreysFrom, use: Int, rings: [[(x: Int, y: Int)]])] {
        guard decoded.count > 1 else { return decoded }
        struct Box { var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min, area = 0.0 }
        let boxes: [Box] = decoded.map { building in
            var box = Box()
            guard let outline = building.rings.first, outline.count >= 3 else { return box }
            var twice = 0
            for (index, point) in outline.enumerated() {
                box.minX = min(box.minX, point.x); box.maxX = max(box.maxX, point.x)
                box.minY = min(box.minY, point.y); box.maxY = max(box.maxY, point.y)
                let next = outline[(index + 1) % outline.count]
                twice += point.x * next.y - next.x * point.y
            }
            box.area = Double(abs(twice)) / 2
            return box
        }
        func boxArea(_ box: Box) -> Double { Double(box.maxX - box.minX) * Double(box.maxY - box.minY) }
        // Swept by the boxes' west edges, so only neighbours are compared.
        let order = decoded.indices.filter { boxes[$0].area > 0 }.sorted { (boxes[$0].minX, $0) < (boxes[$1].minX, $1) }
        var dropped = Set<Int>()
        for (place, a) in order.enumerated() where !dropped.contains(a) {
            for b in order[(place + 1)...] {
                guard boxes[b].minX <= boxes[a].maxX else { break }
                guard !dropped.contains(b) else { continue }
                let (one, other) = (boxes[a], boxes[b])
                let width = min(one.maxX, other.maxX) - max(one.minX, other.minX)
                let height = min(one.maxY, other.maxY) - max(one.minY, other.minY)
                guard width > 0, height > 0 else { continue }
                let shared = Double(width) * Double(height)
                guard shared >= duplicateShare * boxArea(one), shared >= duplicateShare * boxArea(other),
                      max(one.area, other.area) < duplicateSizes * min(one.area, other.area) else { continue }
                // Keep the taller; of equals, the first in the tile.
                if decoded[b].storeys > decoded[a].storeys || (decoded[b].storeys == decoded[a].storeys && b < a) {
                    dropped.insert(a)
                    break
                }
                dropped.insert(b)
            }
        }
        guard !dropped.isEmpty else { return decoded }
        return decoded.indices.filter { !dropped.contains($0) }.map { decoded[$0] }
    }

    /// How much of each other's box two outlines of one building share,
    /// and how much larger the one may be than the other.
    static let duplicateShare = 0.8
    static let duplicateSizes = 1.4

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
        case 2, 4, 7, 8: .civic                       // civic, education, medical, military
        case 3: drawnStoreys > 5 ? .office : .shophouse  // commercial
        case 5: drawnStoreys > 6 ? .office : .hall    // entertainment: stadiums, sports halls (decision 765)
        case 12: .hall                                // service: substations (decision 765)
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
    /// cells under them, which keep no city lot (decision 723: but the
    /// houses along the roads of those they cover little of,
    /// ``thinlyBuilt(but:)``).
    @discardableResult
    mutating func addFootprints(_ footprints: Map3DFootprints, clearOf cleared: Set<Map3DScene.ChunkKey>,
                                takenBy taken: Set<Map3DScene.ChunkKey>) -> Set<Map3DScene.ChunkKey> {
        var standing = Set<Map3DScene.ChunkKey>()
        // Decision 723: how much of each cell the footprints drawn cover.
        var cover = RealCover()
        let cell = Double(Land.cellLength)
        func key(_ x: Double, _ y: Double) -> Map3DScene.ChunkKey {
            Map3DScene.ChunkKey(column: Int((x / cell).rounded(.down)), row: Int((y / cell).rounded(.down)))
        }
        // Decision 610: built in full, the street fronts by the streets;
        // decision 610 續: none where they are never drawn.
        facadeStreets = isFar || !buildsFacades ? nil : facadeStreetCells()
        defer { facadeStreets = nil }
        // Decision 699: the halls behind the airports' piers, found once.
        if !terminalSpots.isEmpty, !terminalsJoined {
            terminalsJoined = true
            let reach = Double(700 * Self.metre)
            let spots = terminalSpots.map { (x: originX + Double($0.at.x) * Self.metre, y: originY + Double($0.at.z) * Self.metre) }
            let low = (x: (spots.map(\.x).min() ?? 0) - reach, y: (spots.map(\.y).min() ?? 0) - reach)
            let high = (x: (spots.map(\.x).max() ?? 0) + reach, y: (spots.map(\.y).max() ?? 0) + reach)
            joinTerminals(footprints.buildings.compactMap { building in
                guard let ring = building.rings.first, ring.count >= 3, ring[0].x > low.x, ring[0].x < high.x, ring[0].y > low.y, ring[0].y < high.y
                else { return nil }
                return ring.map { point(x: $0.x, y: $0.y, height: 0) }
            })
        }
        for building in footprints.buildings {
            guard let outline = building.rings.first, outline.count >= 3 else { continue }
            let middle = (x: outline.reduce(0) { $0 + $1.x } / Double(outline.count), y: outline.reduce(0) { $0 + $1.y } / Double(outline.count))
            guard contains(x: middle.x, y: middle.y), !taken.contains(key(middle.x, middle.y)) else { continue }
            guard !outline.contains(where: { cleared.contains(key($0.x, $0.y)) }) else { continue }
            let rings = building.rings.map { $0.map { point(x: $0.x, y: $0.y, height: 0) } }
            // Cleared for a building of the player's: its cells still keep
            // no city lot.
            // Decision 791: nor on a landmark's ground (it draws the building).
            let drawn = !onPlacedGround(rings[0]) && !underLandmark(point(x: middle.x, y: middle.y, height: 0)) && !underLandmark(outline: rings[0])
            // Decision 879: nor where a model stands in its place, though
            // it counts as built.
            let spot = point(x: middle.x, y: middle.y, height: 0)
            let replaced = replacedPlots.contains { $0.minX <= spot.x && spot.x <= $0.maxX && $0.minZ <= spot.z && spot.z <= $0.maxZ }
            standing.formUnion(count(building.rings, drawn: drawn, into: &cover))
            guard drawn, !replaced else { continue }
            var storeys = building.drawnStoreys, kind = building.kind
            // Decision 699: an airport's terminal, at least four storeys.
            if isTerminal(rings[0]) { (storeys, kind) = (max(storeys, 4), .terminal) }
            addRealBuilding([rings], ground: ground(x: middle.x, y: middle.y), height: Float(storeys) * Self.storeyHeight,
                            storeys: storeys, kind: kind)
        }
        footprintCover = cover
        return standing
    }

    /// Decision 386: a storey's height, the tool's `LEVEL_HEIGHT`.
    static let storeyHeight: Float = 3.2
}
