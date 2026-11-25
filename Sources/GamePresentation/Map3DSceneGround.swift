import GameCore

/// The ground of a 3D scene and the shadows on it (decisions 232, 720).
/// Moved as it was out of `Map3DScene.swift` (MAP3D-SCENE-SPLIT).
extension Map3DScene.Builder {
    // MARK: Shadows (decision 232)

    /// The height of the ground as the scene draws it at scene point
    /// (`x`, `z`): the 64 m grid's corners, each square split from its
    /// north-west corner to its south-east one as ``addGround()``'s
    /// quads are.
    mutating func drawnGround(x: Float, z: Float) -> Float {
        let cell = Double(Land.cellLength)
        let worldX = originX + Double(x) * Self.metre, worldY = originY + Double(z) * Self.metre
        let column = Int((worldX / cell).rounded(.down)), row = Int((worldY / cell).rounded(.down))
        let fx = Float(worldX / cell - Double(column)), fy = Float(worldY / cell - Double(row))
        let a = groundCorner(row: row, column: column), b = groundCorner(row: row + 1, column: column)
        let c = groundCorner(row: row + 1, column: column + 1), d = groundCorner(row: row, column: column + 1)
        // a (0, 0), b (0, 1), c (1, 1), d (1, 0) in (fx, fy): the
        // triangles a b c and a c d.
        return fy >= fx ? a + fx * (c - b) + fy * (b - a) : a + fx * (d - a) + fy * (c - d)
    }

    /// The ground's height at the 64 m grid's corner (`row`,
    /// `column`), in metres, as ``addGround(water:)`` lays it, worked
    /// out once.
    mutating func groundCorner(row: Int, column: Int) -> Float {
        if let known = corners[row, column] { return known }
        let cell = Double(Land.cellLength)
        let own = worldGround(x: Double(column) * cell, y: Double(row) * cell)
        // Decision 737: the levelled ground on a real-world map.
        let height = levelling?.corner(row: row, column: column, own: own) ?? own
        corners[row, column] = height
        return height
    }

    /// Decision 965: the ground's smoothed way up at the 64 m grid's
    /// corner (`row`, `column`), from the heights of the corners each
    /// side of it (``groundCorner(row:column:)``): a slope lit as one
    /// surface, not as each square's own face.
    mutating func groundCornerNormal(row: Int, column: Int) -> Map3DPoint {
        let across = Float(2 * Double(Land.cellLength) / Self.metre)
        let east = groundCorner(row: row, column: column + 1) - groundCorner(row: row, column: column - 1)
        let south = groundCorner(row: row + 1, column: column) - groundCorner(row: row - 1, column: column)
        return Map3DPoint(-east / across, 1, -south / across).normalized ?? .up
    }

    /// Decision 965: the ground's smoothed way up at scene point (`x`,
    /// `z`): its square's corners' (``groundCornerNormal(row:column:)``)
    /// run together over the same two triangles ``drawnGround(x:z:)``
    /// reads the heights from, so what lies on the ground is lit as the
    /// ground under it.
    mutating func groundNormal(x: Float, z: Float) -> Map3DPoint {
        let cell = Double(Land.cellLength)
        let worldX = originX + Double(x) * Self.metre, worldY = originY + Double(z) * Self.metre
        let column = Int((worldX / cell).rounded(.down)), row = Int((worldY / cell).rounded(.down))
        let fx = Float(worldX / cell - Double(column)), fy = Float(worldY / cell - Double(row))
        let a = groundCornerNormal(row: row, column: column), b = groundCornerNormal(row: row + 1, column: column)
        let c = groundCornerNormal(row: row + 1, column: column + 1), d = groundCornerNormal(row: row, column: column + 1)
        let blended = fy >= fx ? a + (c - b) * fx + (b - a) * fy : a + (d - a) * fx + (c - d) * fy
        return blended.normalized ?? .up
    }

    /// Decision 876 (later, PERF-3D-BLOCK-FIXED): the corners worked
    /// out (``groundCorner(row:column:)``), those of the region and
    /// ``reach`` cells round it in an array, the rest by key. The
    /// drawn ground is asked for hundreds of thousands of times in a
    /// block (every road's bed, wall and bridge), and hashing each
    /// corner's key was a tenth of a Hong Kong block's time; what is
    /// kept is the same either way.
    struct CornerHeights {
        /// Cells round the region kept in the array: past the road
        /// beds (``Map3DRoadBed/reach``) and the base map's bridges,
        /// read from the tiles round the region
        /// (``Map3DBaseMap/bridgeReach``), each kept to its tile
        /// (some 2.3 km across in Hong Kong).
        static let reach = 48
        /// The most corners kept in the array (20 MB of heights and flags).
        static let most = 4_000_000
        private var firstRow = 0, firstColumn = 0, rows = 0, columns = 0
        private var heights: [Float] = []
        private var known: [Bool] = []
        private var others: [ChunkKey: Float] = [:]

        init() {}

        init(region: WorldRegion) {
            let cell = Double(Land.cellLength)
            let first = (row: Int((region.minY / cell).rounded(.down)) - Self.reach, column: Int((region.minX / cell).rounded(.down)) - Self.reach)
            let last = (row: Int((region.maxY / cell).rounded(.up)) + Self.reach, column: Int((region.maxX / cell).rounded(.up)) + Self.reach)
            guard first.row <= last.row, first.column <= last.column else { return }
            let rows = last.row - first.row + 1, columns = last.column - first.column + 1
            guard rows.multipliedReportingOverflow(by: columns).partialValue <= Self.most, rows <= Self.most, columns <= Self.most else { return }
            (firstRow, firstColumn, self.rows, self.columns) = (first.row, first.column, rows, columns)
            heights = Array(repeating: 0, count: rows * columns)
            known = Array(repeating: false, count: rows * columns)
        }

        private func index(_ row: Int, _ column: Int) -> Int? {
            let r = row &- firstRow, c = column &- firstColumn
            guard r >= 0, r < rows, c >= 0, c < columns else { return nil }
            return r * columns + c
        }

        subscript(row: Int, column: Int) -> Float? {
            get {
                if let at = index(row, column) { return known[at] ? heights[at] : nil }
                return others[ChunkKey(column: column, row: row)]
            }
            set {
                if let at = index(row, column) {
                    known[at] = newValue != nil
                    heights[at] = newValue ?? 0
                } else {
                    others[ChunkKey(column: column, row: row)] = newValue
                }
            }
        }

        /// The corner at `key` (its column and row).
        subscript(key: ChunkKey) -> Float? {
            get { self[key.row, key.column] }
            set { self[key.row, key.column] = newValue }
        }

        /// The corners worked out.
        var keys: [ChunkKey] {
            var keys = Array(others.keys)
            for at in known.indices where known[at] {
                keys.append(ChunkKey(column: firstColumn + at % columns, row: firstRow + at / columns))
            }
            return keys
        }
    }

    /// Decision 517 續 (BUILD3D-3): the corners ``addGround(water:)``
    /// lays over the region, for taps (``Map3DScene/drawnGround``).
    mutating func groundGrid() -> Map3DGroundGrid {
        let cell = Double(Land.cellLength)
        let firstColumn = Int((region.minX / cell).rounded(.down)), lastColumn = Int((region.maxX / cell).rounded(.up)) - 1
        let firstRow = Int((region.minY / cell).rounded(.down)), lastRow = Int((region.maxY / cell).rounded(.up)) - 1
        guard firstColumn <= lastColumn, firstRow <= lastRow else {
            return Map3DGroundGrid(originX: originX, originY: originY, firstRow: 0, firstColumn: 0, rows: 0, columns: 0, heights: [],
                                   file: fileGround)
        }
        var heights: [Float] = []
        heights.reserveCapacity((lastRow - firstRow + 2) * (lastColumn - firstColumn + 2))
        for row in firstRow...(lastRow + 1) {
            for column in firstColumn...(lastColumn + 1) { heights.append(groundCorner(row: row, column: column)) }
        }
        return Map3DGroundGrid(originX: originX, originY: originY, firstRow: firstRow, firstColumn: firstColumn,
                               rows: lastRow - firstRow + 2, columns: lastColumn - firstColumn + 2, heights: heights, file: fileGround)
    }

    /// `points` laid on the drawn ground, ``Map3DShadow/lift`` over it.
    mutating func onGround(_ points: [Map3DPoint]) -> [Map3DPoint] {
        points.map { Map3DPoint($0.x, drawnGround(x: $0.x, z: $0.z) + Map3DShadow.lift, $0.z) }
    }

    /// A soft shadow under a footprint `length` along `forward` and
    /// `width` across, standing on `centre`, fading out over `spread`
    /// metres round it.
    mutating func addShadow(centre: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), length: Float, width: Float,
                            spread: Float, darkness: Float) {
        guard !isFar else { return }
        let inner = onGround(Map3DMesh.footprint(centre: centre, forward: forward, length: length, width: width))
        let outer = onGround(Map3DMesh.footprint(centre: centre, forward: forward, length: length + 2 * spread, width: width + 2 * spread))
        shadow(at: key(of: centre), size: max(length, width)) { $0.addShadow(inner: inner, outer: outer, darkness: darkness) }
    }

    // MARK: Ground

    /// The ground: a grid of 64 m squares at the map's heights, the
    /// water on it unless `water` is false (the base map's water lies
    /// on it instead, decision 234).
    ///
    /// Decision 720: a square under one of `lots` in its ground's
    /// colour (``Map3DPalette/GroundKind``), run into its neighbours'
    /// at the corners they share; plain where it is `clearOf`.
    /// Decision 733: plain on the no-build land too.
    mutating func addGround(water drawsWater: Bool = true, lots: CitySkyline? = nil, clearOf track: Set<ChunkKey> = []) {
        let cell = Double(Land.cellLength)
        let firstColumn = Int((region.minX / cell).rounded(.down)), lastColumn = Int((region.maxX / cell).rounded(.up)) - 1
        let firstRow = Int((region.minY / cell).rounded(.down)), lastRow = Int((region.maxY / cell).rounded(.up)) - 1
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return }
        var kinds: [ChunkKey: Map3DPalette.GroundKind] = [:]
        if let lots {
            let around = WorldRegion(minX: region.minX - cell, minY: region.minY - cell, maxX: region.maxX + cell, maxY: region.maxY + cell)
            for lot in lots.lots(in: around) {
                let key = ChunkKey(column: lot.column, row: lot.row)
                state.land.lotCells.insert(key)
                guard let kind = Map3DPalette.GroundKind(lot), !track.contains(key) else { continue }
                // Decision 733: none on the no-build land, where no
                // lot's building stands either (``addCity``): the
                // people an older Hong Kong game put on its airport.
                guard !onNoBuildLand(point(x: (Double(lot.column) + 0.5) * cell, y: (Double(lot.row) + 0.5) * cell, height: 0))
                else { continue }
                kinds[key] = kind
            }
        }
        // Decision 811: the land cover's ground where no lot is, but
        // plain where the player's track runs.
        for (key, cover) in state.land.landCover where kinds[key] == nil && !track.contains(key) {
            if let kind = Map3DPalette.GroundKind(cover) { kinds[key] = kind }
        }
        // A corner's colour: its four squares' run together.
        func tint(_ row: Int, _ column: Int) -> UInt32 {
            guard !kinds.isEmpty else { return Map3DPalette.ground }
            return Map3DPalette.ground(mixing: [(row - 1, column - 1), (row - 1, column), (row, column - 1), (row, column)].map {
                kinds[ChunkKey(column: $0.1, row: $0.0)] ?? .plain
            })
        }
        func corner(_ row: Int, _ column: Int) -> Map3DPoint {
            let x = Double(column) * cell, y = Double(row) * cell
            return Map3DPoint(Float((x - originX) / Self.metre), groundCorner(row: row, column: column), Float((y - originY) / Self.metre))
        }
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let a = corner(row, column), b = corner(row + 1, column), c = corner(row + 1, column + 1), d = corner(row, column + 1)
                let water = drawsWater && world.isWater(row: row, column: column)
                let lift = Map3DPoint(0, water ? 0.05 : 0, 0)
                let middle = (a + c) * 0.5
                let colour = water ? Map3DPalette.water : Map3DPalette.ground
                let tints = water ? [] : [tint(row, column), tint(row + 1, column), tint(row + 1, column + 1), tint(row, column + 1)]
                // Decision 375: less the trenches, each triangle's
                // pieces at its own heights, lit as the whole square.
                let flat = { (p: Map3DPoint) in Map3DBaseMap.Point(x: Double(p.x), z: Double(p.z)) }
                let halves = [[a, b, c], [a, c, d]].map { outsideTrenches($0.map(flat)) }
                if halves.allSatisfy({ $0 == nil }) {
                    // Decision 965: land lit at each corner by the
                    // slope round it; water flat, as it lies.
                    let normals = water ? [] : [groundCornerNormal(row: row, column: column), groundCornerNormal(row: row + 1, column: column),
                                                groundCornerNormal(row: row + 1, column: column + 1), groundCornerNormal(row: row, column: column + 1)]
                    mesh(at: middle) {
                        // Decision 241: the ground plain, as the 2D map's land.
                        let start = $0.vertices.count
                        if water {
                            $0.addQuad(a + lift, b + lift, c + lift, d + lift, color: colour)
                            $0.makeWater(from: start)
                        } else {
                            $0.addGroundQuad(a, b, c, d, normals: normals, color: colour)
                            $0.recolour(from: start) { index, _ in tints[index] }
                        }
                    }
                    continue
                }
                guard let normal = Map3DMesh.normal(of: [a, b, c, d]) else { continue }
                var pieces: [[Map3DPoint]] = []
                var pieceNormals: [[Map3DPoint]] = []
                for (corners, half) in zip([[a, b, c], [a, c, d]], halves) {
                    for piece in half ?? [corners.map(flat)] {
                        pieces.append(piece.map { p in
                            let x = Float(p.x), z = Float(p.z)
                            return Map3DPoint(x, drawnGround(x: x, z: z), z) + lift
                        })
                        // Decision 965: as the whole squares' corners.
                        pieceNormals.append(piece.map { p in water ? normal : groundNormal(x: Float(p.x), z: Float(p.z)) })
                    }
                }
                mesh(at: middle) {
                    let start = $0.vertices.count
                    for (piece, normals) in zip(pieces, pieceNormals) { $0.addFan(piece, normals: normals, color: colour) }
                    if water { $0.makeWater(from: start) } else if tints.contains(where: { $0 != colour }) {
                        // A cut square's pieces: each vertex its nearest corner's colour.
                        let corners = [a, b, c, d]
                        $0.recolour(from: start) { _, at in
                            tints[corners.indices.min { (corners[$0] - at).length < (corners[$1] - at).length } ?? 0]
                        }
                    }
                }
            }
        }
    }
}
