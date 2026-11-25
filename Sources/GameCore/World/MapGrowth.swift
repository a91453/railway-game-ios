// The map grows (decision 969): a world laid over a real place reaches
// farther to the south and the east than it did, so a game begun on a
// city's map goes on when the map takes in the next city. The world keeps
// its north-west corner, which everything in it is measured from (track,
// stations, the cells of the land, the blocks read, the tiles of the map),
// so nothing in it moves or is numbered again but the tiles' asset records,
// numbered row by row. Where it lies on the Earth stays too: the anchor was
// the middle of the world as it was, and the world remembers that part
// (``GameWorld/geoAnchorBounds``).
//
// The blocks of land cut by the old east and south edges were read in
// part: they are to be read again, whole (their cells keep what they have,
// as any block read after the land grew there). Their ground, if read,
// stays: track is measured from it.
//
// The owner's references have no map that grows (gap): `Ci/` and the
// `Railway/` site load one city, and OpenTTD's map has the size it was
// made with. This is the project's own.

extension GameWorld {
    // MARK: - Commands

    /// Grows the world to `larger` (decision 969), its north-west corner
    /// where it was: everything in it stays, and where it lies on the
    /// Earth, the anchor being from now on the middle of the part the
    /// world was (``geoAnchorBounds``; the first time only, so a map that
    /// grows twice keeps the anchor it began with). Free. Nothing for a
    /// world of that size already.
    ///
    /// The blocks of land the old east and south edges cut are no longer
    /// read (``landBlocks``, and the roads' ``RoadGrid/readBlocks``), and
    /// their water and steep slopes are forgotten until they are read
    /// again: ``expandLand(_:cells:water:steep:)`` then brings the cells
    /// beyond the old edge, those listed keeping what they have. A world
    /// whose land is whole has none beyond its old edges, as before. The
    /// tiles owned of a map bought tile by tile (decision 160) stay owned,
    /// and those beyond are for sale as any other. The year's typhoons
    /// (decision 162), drawn over the whole world, are drawn again.
    /// Passengers already waiting stay.
    ///
    /// - Throws: ``GameError/invalidMapSize(width:height:)`` when `larger`
    ///   is narrower or shorter than the world.
    public mutating func growMap(to larger: WorldBounds) throws(GameError) {
        guard larger.width >= bounds.width, larger.height >= bounds.height else {
            throw .invalidMapSize(width: larger.width, height: larger.height)
        }
        guard larger != bounds else { return }
        let old = bounds, oldTileColumns = mapTileColumns
        if geoAnchor != nil, geoAnchorBounds == nil {
            geoAnchorBounds = old
        }
        bounds = larger
        // A tile's record is numbered by the tiles in a row.
        let tileColumns = mapTileColumns
        if tileColumns != oldTileColumns {
            for index in accounts.assets.indices where accounts.assets[index].kind == .mapTile {
                let number = accounts.assets[index].owner
                accounts.assets[index].owner = number / oldTileColumns * tileColumns + number % oldTileColumns
            }
        }
        let cut = Self.blocksCut(at: old, in: larger)
        if let read = landBlocks, !cut.isEmpty {
            landBlocks = read.filter { !cut.contains($0) }
            terrain.forget(in: cut)
        }
        roads?.readBlocks.subtract(cut)
        passengerPlan = PassengerPlanCache()
        refreshLandDemand()
    }

    // MARK: - Queries

    /// The blocks of land a world of `old` bounds held in part and one of
    /// `larger` bounds holds more of: those its east edge cut, where the
    /// world grew wider, and its south edge, where it grew longer.
    static func blocksCut(at old: WorldBounds, in larger: WorldBounds) -> Set<LandBlock> {
        let side = Land.blockLength
        let rows = Land.blockRows(in: old), columns = Land.blockColumns(in: old)
        var cut = Set<LandBlock>()
        if larger.width > old.width, old.width % side != 0 {
            for row in 0..<rows { cut.insert(LandBlock(row: row, column: columns - 1)) }
        }
        if larger.height > old.height, old.height % side != 0 {
            for column in 0..<columns { cut.insert(LandBlock(row: rows - 1, column: column)) }
        }
        return cut
    }

    // MARK: - Validation

    /// Why the part of the world its anchor is the middle of breaks a rule
    /// (decision 969), or `nil`: only a world with an anchor has one, it
    /// lies in the world, and it is not the whole world (which `nil` says).
    func mapGrowthProblem() -> String? {
        guard let part = geoAnchorBounds else { return nil }
        guard geoAnchor != nil else { return "Only a map laid over the Earth says which part of it its anchor is the middle of." }
        guard part.width <= bounds.width, part.height <= bounds.height, part != bounds else {
            return "The part of the world its anchor is the middle of must lie in the world, and not be the whole of it."
        }
        return nil
    }
}
