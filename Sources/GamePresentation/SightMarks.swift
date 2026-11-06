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
    /// already shown, the marks `width` by `height` (decision 510: a star
    /// alone, ``MapClutter/starWidth``, from the middle zoom).
    public static func shown(_ marks: [Mark], width: Double = SightMarks.width, height: Double = SightMarks.height) -> Set<AttractionID> {
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

/// The sights panel's rows (``GameSession/sightsPanelRows``) and what they
/// were worked out for.
struct SightRowsMemo {
    let day: Int64
    let commandRevision: Int
    let language: DisplayLanguage
    /// Whether the balance covers a shop's price: it moves at every tick,
    /// and the rows' buy buttons say it (L11-2).
    let canAffordShop: Bool
    let rows: [AttractionRow]
}

extension GameSession {
    /// The sights panel's rows (``GameWorld/attractionRows(in:)``), worked
    /// out again only when the game's day or a command changes, not at
    /// every tick (CRASH-SIGHTS: a player's report, "it
    /// keeps jumping to the sights and crashing"). Each row asks whether
    /// tourists can ride to its sight, a route search on the whole
    /// network; the panel, which reads the world, asked it of every sight
    /// at every tick while it stayed open, and on a big network that took
    /// longer than a tick, so the game froze until the system closed it.
    /// What a row says changes with the day (its status, today's,
    /// yesterday's and this year's tourists, the day's typhoon) or a
    /// command (its shop, its station, the lines); the shop's price being
    /// affordable changes with the cash, so it is part of the key.
    public var sightsPanelRows: [AttractionRow] {
        let day = world.clock.now.seconds / GameTime.secondsPerDay
        let canAffordShop = world.economy.canAfford(Money(Tourism.souvenirCost))
        if let memo = sightRowsMemo, memo.day == day, memo.commandRevision == commandRevision, memo.language == language, memo.canAffordShop == canAffordShop {
            return memo.rows
        }
        let rows = world.attractionRows(in: language)
        sightRowsMemo = SightRowsMemo(day: day, commandRevision: commandRevision, language: language, canAffordShop: canAffordShop, rows: rows)
        sightRowsWorkedOut += 1
        return rows
    }
}
