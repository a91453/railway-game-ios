import GameCore

// Which sights the map marks (ARCHITECTURE decision 250): with Taiwan's 214
// sights, or a dozen in the middle of Taipei, the marks of a map seen from
// afar would lie on each other. A mark gives way to a better-rated one it
// would overlap: the higher rating first, the lower number between equals.
// Every one shows again as the map is brought closer. This project's own;
// the references draw no marks to port.

public enum SightMarks {
    /// About a mark's size on the screen, in points, with a little room
    /// round it: a star and a rating in a capsule.
    public static let width: Double = 56
    public static let height: Double = 26

    /// One sight's mark: the sight, its rating now and where its middle is
    /// on the screen.
    public struct Mark: Sendable {
        public let id: AttractionID
        public let stars: Int
        public let x: Double
        public let y: Double

        public init(id: AttractionID, stars: Int, x: Double, y: Double) {
            self.id = id
            self.stars = stars
            self.x = x
            self.y = y
        }
    }

    /// The sights of `marks` to show: each that overlaps none better rated
    /// already shown.
    public static func shown(_ marks: [Mark]) -> Set<AttractionID> {
        var kept: [Mark] = []
        for mark in marks.sorted(by: { $0.stars != $1.stars ? $0.stars > $1.stars : $0.id.rawValue < $1.id.rawValue })
        where kept.allSatisfy({ abs($0.x - mark.x) >= width || abs($0.y - mark.y) >= height }) {
            kept.append(mark)
        }
        return Set(kept.map(\.id))
    }
}

/// The sight the sights panel opens on (ARCHITECTURE decision 250, a
/// player's report): the one whose mark or bubble on the map was tapped.
/// The panel scrolls to its row and marks it for a moment; opened from the
/// menu it opens at the top, as before. View state only, never game state.
public enum SightFocus {
    /// How long the row stays marked, in seconds.
    public static let highlightSeconds: Double = 2

    /// The row of `rows` the panel scrolls to for `sight`: the sight's own
    /// while the panel lists it, none for no sight (the menu) or one gone.
    public static func row(for sight: AttractionID?, in rows: [AttractionRow]) -> AttractionID? {
        guard let sight, rows.contains(where: { $0.id == sight }) else { return nil }
        return sight
    }
}

extension GameSession {
    /// Whether the map's sight marks take touches (decision 250, later):
    /// with the Select tool, but not while choosing a tile to buy, when a
    /// tap on the map chooses the tile under it, sight or not; the marks
    /// show faint then, as while building. A map bought tile by tile has
    /// sights in every tile.
    public var sightMarksTakeTouches: Bool {
        tool == .select && !isChoosingMapTile
    }
}
