import GameCore

/// How the plain map shows a night's growth (ARCHITECTURE decision 140):
/// after the city grows (decisions 73, 75, 139) the map's next
/// ``CitySkyline`` has new buildings and taller ones. Instead of all of
/// them changing in one frame, a new building rises out of the ground and a
/// raised one from its old height to its new, each with its roof lit in the
/// station's yellow that fades as it rises; they start one after another,
/// a little apart, and all are done in ``duration`` seconds.
///
/// A real-world map draws no city of its own (its base map shows the real
/// one, decision 126), so there only the buildings that grew are drawn,
/// over the real map: they rise the same way, stay a moment and fade out by
/// ``fadedDuration``.
///
/// Derived from two skylines and never saved: GameCore's growth is the
/// same with or without it. The map plays it only for growth the clock
/// moved forward to over a midnight, when the city grows, a few days at
/// most, so loading a save, undoing, buying out a lot or the whole of
/// Taiwan reading in land as the map moves changes the map at once.
///
/// The references animate no city growth to port (gap): the timing and the
/// look are this project's.
public struct SkylineGrowth: Sendable {
    /// One lot that grew.
    public struct Rise: Hashable, Sendable {
        /// The density it rises from: 0 for a new building.
        public let fromDensity: Int
        /// Whether the building is new on its cell (on open ground, a new
        /// cell or a cell whose use changed) rather than raised.
        public let isNew: Bool
        /// When it starts, in seconds after the growth begins.
        public let delay: Double
    }

    /// What a growing lot looks like at one moment.
    public struct Frame: Hashable, Sendable {
        /// How tall it is drawn, as ``CitySkyline/heightShare(density:)``.
        public let heightShare: Double
        /// The share of its footprint's side drawn: a new building swells
        /// to its full size as it rises.
        public let sideShare: Double
        /// How strongly its roof is lit, 0 to 1.
        public let light: Double

        public init(heightShare: Double, sideShare: Double, light: Double) {
            self.heightShare = heightShare
            self.sideShare = sideShare
            self.light = light
        }

        /// Whether it is drawn at all: a new building not yet started is
        /// not.
        public var isShown: Bool {
            sideShare > 0
        }
    }

    private struct Cell: Hashable {
        let row: Int
        let column: Int
    }

    private let rises: [Cell: Rise]

    /// How many lots grew.
    public var count: Int {
        rises.count
    }

    /// How long one building takes to rise, in seconds.
    public static let riseDuration = 0.9
    /// The latest a building starts, in seconds.
    public static let longestDelay = 0.7
    /// How long the whole growth takes, in seconds.
    public static let duration = longestDelay + riseDuration
    /// On a real-world map, how long the buildings stay once all have
    /// risen, and how long they then take to fade out, in seconds.
    public static let lingerDuration = 1.2
    public static let fadeDuration = 0.8
    /// How long a real-world map's growth takes, faded out, in seconds.
    public static let fadedDuration = duration + lingerDuration + fadeDuration

    /// How much of a real-world map's growth is still shown `elapsed`
    /// seconds after it began: whole until it has risen and stayed, then
    /// fading to nothing at ``fadedDuration``.
    public static func shown(elapsed: Double) -> Double {
        guard elapsed < fadedDuration else { return 0 }
        let fading = elapsed - duration - lingerDuration
        return max(0, min(1, 1 - fading / fadeDuration))
    }

    /// The most game days between two skylines whose difference is played:
    /// further apart, the map was loaded or jumped, not grown.
    public static let longestGapDays: Int64 = 3

    /// The growth from `old` to `new`, or `nil` when there is none to play:
    /// nothing grew, no midnight passed between them (the clock went back,
    /// did not move or moved within a day), or more than
    /// ``longestGapDays`` did.
    public init?(from old: CitySkyline, to new: CitySkyline) {
        let day = GameTime.secondsPerDay
        guard Self.day(of: old.time) < Self.day(of: new.time),
              new.time.seconds - old.time.seconds <= Self.longestGapDays * day
        else { return nil }
        var before: [Cell: CitySkyline.Lot] = [:]
        before.reserveCapacity(old.lots.count)
        for lot in old.lots {
            before[Cell(row: lot.row, column: lot.column)] = lot
        }
        var rises: [Cell: Rise] = [:]
        for lot in new.lots where !lot.isOpenGround {
            let cell = Cell(row: lot.row, column: lot.column)
            let delay = Self.delay(row: lot.row, column: lot.column)
            guard let earlier = before[cell], !earlier.isOpenGround, earlier.use == lot.use else {
                rises[cell] = Rise(fromDensity: 0, isNew: true, delay: delay)
                continue
            }
            if lot.density > earlier.density {
                rises[cell] = Rise(fromDensity: earlier.density, isNew: false, delay: delay)
            }
        }
        guard !rises.isEmpty else { return nil }
        self.rises = rises
    }

    /// The rise of the lot on a cell, if it grew.
    public func rise(row: Int, column: Int) -> Rise? {
        rises[Cell(row: row, column: column)]
    }

    /// How `lot` is drawn `elapsed` seconds after the growth began, if it
    /// grew; `nil` when it did not, and it is drawn as it is.
    public func frame(of lot: CitySkyline.Lot, elapsed: Double) -> Frame? {
        guard let rise = rise(row: lot.row, column: lot.column) else { return nil }
        let target = CitySkyline.heightShare(density: lot.density)
        let local = elapsed - rise.delay
        guard local > 0 else {
            return rise.isNew
                ? Frame(heightShare: 0, sideShare: 0, light: 0)
                : Frame(heightShare: CitySkyline.heightShare(density: rise.fromDensity), sideShare: 1, light: 0)
        }
        let progress = min(1, local / Self.riseDuration)
        // Fast at first, settling into place.
        let eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
        let start = CitySkyline.heightShare(density: rise.fromDensity)
        return Frame(
            heightShare: start + (target - start) * eased,
            sideShare: rise.isNew ? 0.4 + 0.6 * eased : 1,
            light: 1 - progress
        )
    }

    /// The day `time` falls on, counted from 0.
    private static func day(of time: GameTime) -> Int64 {
        time.seconds / GameTime.secondsPerDay
    }

    /// When the lot on a cell starts: spread from 0 to ``longestDelay`` by
    /// its place, the same every time, so neighbours rise one after
    /// another rather than together.
    static func delay(row: Int, column: Int) -> Double {
        var hash = UInt64(bitPattern: Int64(row)) &* 0x9E37_79B9_7F4A_7C15
        hash ^= UInt64(bitPattern: Int64(column)) &* 0xC2B2_AE3D_27D4_EB4F
        hash ^= hash >> 31
        hash &*= 0x94D0_49BB_1331_11EB
        hash ^= hash >> 29
        return Double(hash % 1_024) / 1_023 * longestDelay
    }
}
