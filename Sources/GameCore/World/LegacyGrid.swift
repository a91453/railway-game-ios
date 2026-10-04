/// What GameCore still reads of the grid it once had (Stages I to F3c,
/// ARCHITECTURE decisions 51 and 54), and only reads: nothing in the game
/// uses it.
///
/// - A save before version 6 gives the world's size as a map of tiles
///   (`"map": {"width", "height", ...}`), read as bounds of
///   ``tileLength`` units a tile (see ``GameWorld/init(from:)``).
/// - Grid track, stations on tiles, and trains, bodies, paths and
///   reservations on the grid only a save made by hand could hold; they are
///   refused with that reason, and a tile's coordinates there are read only
///   to be refused.
enum LegacyGrid {
    /// A tile's width in world units, as a save before version 6 gives the
    /// map's size in tiles.
    static let tileLength: Int64 = 1_024

    /// The most tiles a side of a map could have: a new game's 16 km
    /// (Stage E1).
    static let maximumTiles = 1_024

    /// A tile's coordinates, `{"x", "y"}`, as an old save wrote them.
    struct Cell: Decodable {
        let x: Int
        let y: Int
    }
}
