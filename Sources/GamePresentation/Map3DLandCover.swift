import Foundation
import GameCore

// Decision 811: the countryside of a real-world map in Taiwan no longer a
// blank plain. ESA WorldCover's land cover (``LandCoverGrid``) tints the
// 64 m squares of ground where the city has no lot (forest, fields,
// grassland, bare ground and wetland, ``Map3DPalette/GroundKind``), under
// OpenStreetMap's own land cover, which still lies on top where it is
// mapped; and trees stand in its forests, broadleaf low down and more
// conifers higher up, as they do in the base map's woods.

extension Map3DScene.Builder {
    /// Decision 811: the land cover of each 64 m cell round the region (one
    /// cell more each way, for the corners the region's edge shares), read
    /// from `grid` at each cell's middle.
    mutating func readLandCover(_ grid: LandCoverGrid, frame: RealWorldFrame) {
        let cell = Double(Land.cellLength)
        let firstColumn = Int((region.minX / cell).rounded(.down)) - 1, lastColumn = Int((region.maxX / cell).rounded(.up))
        let firstRow = Int((region.minY / cell).rounded(.down)) - 1, lastRow = Int((region.maxY / cell).rounded(.up))
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return }
        var reader = LandCoverGrid.Reader(grid)
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                let place = frame.coordinate(worldX: (Double(column) + 0.5) * cell, worldY: (Double(row) + 0.5) * cell)
                if let found = reader.cover(latitude: place.latitude, longitude: place.longitude) {
                    landCover[Map3DScene.ChunkKey(column: column, row: row)] = found
                }
            }
        }
    }

    /// Decision 811: how many of a wood's spots have a tree, at full
    /// cover: the base map's woods' (decision 458's most conifers).
    static let woodShare: Float = 0.85

    /// Decision 811: the broadleaf trees' greens: the street trees' a
    /// little deeper, as the foothills' evergreen broadleaf woods are, and
    /// warmer than the conifers' (``Map3DSceneryProp/coniferGreens``).
    public static let broadleafGreens: [UInt32] = [0x4F9A45, 0x5AA34A, 0x468F40, 0x63AA50].map { Map3DLook.colour(Map3DColor.rgb($0)) }

    /// Decision 458 and 811: a wood's tree on the spot `seed` hashes, at
    /// (`x`, `z`) on ground `height`: a conifer for
    /// ``coniferShare(atHeight:)`` of the spots, a broadleaf tree (the
    /// street tree's model, larger) for the rest of ``woodShare``; `nil`
    /// for a spot left open.
    func woodTree(seed: (Int32, Int32), x: Float, z: Float, height: Float, conifers: [Int], broadleaf: Int?) -> Map3DInstance? {
        func r(_ salt: Int32) -> Float { map3DRandom(seed.0, seed.1, salt: salt) }
        let draw = r(82), angle = r(84) * 2 * Float.pi
        let foot = Map3DPoint(x, height, z), forward = Map3DPoint(cosf(angle), 0, sinf(angle))
        if draw < Self.coniferShare(atHeight: height) {
            // Most of them tall, the young ones fewest.
            let pick = r(83), model = conifers[pick < 0.45 ? 0 : pick < 0.8 ? 1 : 2]
            return .prop(model, at: foot, forward: forward, scale: 0.8 + 0.45 * r(85), tint: Self.pick(Map3DSceneryProp.coniferGreens, r(86)))
        }
        guard draw < Self.woodShare, let broadleaf else { return nil }
        // A crown some 6 to 10 m up, wider than a street tree's.
        return .prop(broadleaf, at: foot, forward: forward, scale: 1.25 + 0.55 * r(85), tint: Self.pick(Self.broadleafGreens, r(86)))
    }

    /// Decision 811: trees in the land cover's forests that the base map
    /// has no wood on, two by two on each 64 m cell as ``addConifers(clearOf:)``
    /// plants them in the base map's woods; none on a cell of
    /// `cleared` (the track, stations, landmarks, real buildings, the
    /// city's lots, the base map's water and parks), on a chunk built
    /// without its city in full, on water, or within 4 m of a road. Laid
    /// after the buildings, so none stands in one.
    mutating func addWildTrees(clearOf cleared: Set<Map3DScene.ChunkKey>) {
        guard !landCover.isEmpty else { return }
        let conifers = Map3DSceneryProp.conifers.compactMap { Self.sceneryModels[$0] }
        guard conifers.count == Map3DSceneryProp.conifers.count, let broadleaf = Self.propModels[.tree] else { return }
        let side = Float(Double(Land.cellLength) / Self.metre), quarter = side / 2
        let cells = Set(landCover.compactMap { key, cover in cover == .forest ? key : nil }).subtracting(cleared).subtracting(woodCells.keys).subtracting(lotCells).filter { key in
            let west = Float(gridLine(key.column, origin: originX)), north = Float(gridLine(key.row, origin: originY))
            let middle = Map3DPoint(west + quarter, 0, north + quarter)
            return regionHolds(middle) && !isCoarse(self.key(of: middle))
        }
        guard !cells.isEmpty else { return }
        let pieces = roadPieces(near: cells)
        for key in cells.sorted() {
            let west = Float(gridLine(key.column, origin: originX)), north = Float(gridLine(key.row, origin: originY))
            for i in 0..<2 {
                for j in 0..<2 {
                    let seed = (Int32(truncatingIfNeeded: key.column &* 2 &+ i), Int32(truncatingIfNeeded: key.row &* 2 &+ j))
                    func r(_ salt: Int32) -> Float { map3DRandom(seed.0, seed.1, salt: salt) }
                    let x = west + quarter * (Float(i) + 0.1 + 0.8 * r(80)), z = north + quarter * (Float(j) + 0.1 + 0.8 * r(81))
                    let spot = Map3DPoint(x, 0, z)
                    guard !isOverWater(spot), !Self.isNearRoad(x: x, z: z, pieces[key] ?? [], margin: 4) else { continue }
                    let height = drawnGround(x: x, z: z)
                    guard let tree = woodTree(seed: seed, x: x, z: z, height: height, conifers: conifers,
                                              broadleaf: broadleaf) else { continue }
                    props[self.key(of: Map3DPoint(x, height, z)), default: []].append(tree)
                }
            }
        }
    }

    /// Whether scene point `p` lies in the region the scene is built for.
    func regionHolds(_ p: Map3DPoint) -> Bool {
        let x = originX + Double(p.x) * Self.metre, y = originY + Double(p.z) * Self.metre
        return x >= region.minX && x < region.maxX && y >= region.minY && y < region.maxY
    }
}
