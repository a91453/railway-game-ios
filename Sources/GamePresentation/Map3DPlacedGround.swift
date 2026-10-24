import GameCore

/// The ground the player's and the company's buildings take: as in the
/// A-Train, putting one up clears what stood there, so no real building,
/// footprint, temple, kit's scene or street house is drawn on it.
extension Map3DScene.Builder {
    /// One building's square in the scene, grown by
    /// ``PlacedBuildingRules/clearance`` as GameCore grows it to claim the
    /// city's buildings.
    struct PlacedSquare {
        var minX: Float, minZ: Float, maxX: Float, maxZ: Float
    }

    /// The squares of the world's placed buildings that reach the region.
    static func placedSquares(_ world: GameWorld, region: WorldRegion, originX: Double, originY: Double) -> [PlacedSquare] {
        let c = PlacedBuildingRules.clearance
        return world.placedBuildings.compactMap { building in
            let minX = Double(building.minX - c), minY = Double(building.minY - c)
            let maxX = Double(building.maxX + c), maxY = Double(building.maxY + c)
            guard maxX >= region.minX, minX <= region.maxX, maxY >= region.minY, minY <= region.maxY else { return nil }
            return PlacedSquare(minX: Float((minX - originX) / metre), minZ: Float((minY - originY) / metre),
                                maxX: Float((maxX - originX) / metre), maxZ: Float((maxY - originY) / metre))
        }
    }

    /// Whether the outline `ring` (scene points) reaches a placed
    /// building's ground: an edge of it crosses the square, or the square
    /// lies inside it.
    func onPlacedGround(_ ring: [Map3DPoint]) -> Bool {
        guard !placedGround.isEmpty, let first = ring.first else { return false }
        var low = first, high = first
        for point in ring {
            low = Map3DPoint(min(low.x, point.x), 0, min(low.z, point.z))
            high = Map3DPoint(max(high.x, point.x), 0, max(high.z, point.z))
        }
        return placedGround.contains { square in
            guard low.x <= square.maxX, high.x >= square.minX, low.z <= square.maxZ, high.z >= square.minZ else { return false }
            if ring.indices.contains(where: { Self.crosses(ring[$0], ring[($0 + 1) % ring.count], square) }) { return true }
            let middle = Map3DPoint((square.minX + square.maxX) / 2, 0, (square.minZ + square.maxZ) / 2)
            return ring.count >= 3 && Self.inside(middle, [ring])
        }
    }

    /// Whether the segment `a`–`b` reaches `square` (Liang–Barsky).
    static func crosses(_ a: Map3DPoint, _ b: Map3DPoint, _ square: PlacedSquare) -> Bool {
        var enter: Float = 0, leave: Float = 1
        let dx = b.x - a.x, dz = b.z - a.z
        for (p, q) in [(-dx, a.x - square.minX), (dx, square.maxX - a.x), (-dz, a.z - square.minZ), (dz, square.maxZ - a.z)] {
            if p == 0 {
                if q < 0 { return false }
                continue
            }
            let r = q / p
            if p < 0 {
                if r > leave { return false }
                enter = max(enter, r)
            } else {
                if r < enter { return false }
                leave = min(leave, r)
            }
        }
        return true
    }
}
