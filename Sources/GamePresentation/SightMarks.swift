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
