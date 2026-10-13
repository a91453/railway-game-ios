/// How a real-world game's base map keeps to the game's camera
/// (ARCHITECTURE decision 50, TestFlight 56.1's "the route runs off when
/// the map changes to satellite"). The base map (Apple's `MKMapView`) is
/// told which piece of the Earth to show whenever the camera moves, but it
/// may also move on its own: when it has loaded, when a new style is
/// applied, or when it cannot show the piece asked for (its imagery does
/// not reach that close, so it keeps the middle and shows more). Then the
/// railway drawn over it no longer lines up.
///
/// This decides, each time the base map moved or the camera did, whether
/// to ask again: always for a new piece; for the same piece only when the
/// base map left where it went in answer to it, and at most
/// ``maximumRetries`` times, so a base map that keeps refusing is not asked
/// for ever. It also says how much closer the camera went than the base
/// map could follow (``refusal``), so the map can stop zooming there.
///
/// The pieces are rectangles in the base map's own units (MapKit's map
/// points), any units that grow east and south alike. The project's own.
public struct BaseMapFollowing: Sendable {
    /// A piece of the base map: its top left corner and its size.
    public struct Piece: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var middle: (x: Double, y: Double) { (x + width / 2, y + height / 2) }
    }

    /// How many times the same piece is asked for again after the base map
    /// moved away from its answer.
    public static let maximumRetries = 3

    /// The piece asked for last, and where the base map went in answer.
    private var asked: Piece?
    private var answer: Piece?
    private var retries = 0

    public init() {}

    /// Whether to ask the base map, now showing `shown`, for `target`.
    /// After asking, tell it where the base map went with ``answered(_:)``.
    public mutating func shouldAsk(for target: Piece, shown: Piece) -> Bool {
        if Self.isClose(shown, to: target) {
            asked = target
            answer = shown
            retries = 0
            return false
        }
        if let asked, Self.isClose(asked, to: target) {
            // The base map's own answer to this piece: as far as it goes.
            if let answer, Self.isClose(shown, to: answer) { return false }
            guard retries < Self.maximumRetries else { return false }
            retries += 1
        } else {
            retries = 0
        }
        asked = target
        answer = nil
        return true
    }

    /// Where the base map went when asked for the last piece.
    public mutating func answered(_ shown: Piece) {
        answer = shown
    }

    /// How many times wider than the piece asked for the base map showed
    /// round the same middle, when it would not come as close (more than
    /// 2 % wider); `nil` when it showed the piece, or went somewhere else.
    public var refusal: Double? {
        guard let asked, let answer, asked.width > 0, answer.width > asked.width * 1.02 else { return nil }
        let a = asked.middle, b = answer.middle
        // Round the same middle, within a hundredth of what it showed.
        guard abs(a.x - b.x) <= answer.width / 100, abs(a.y - b.y) <= answer.width / 100 else { return nil }
        return answer.width / asked.width
    }

    /// Within a thousandth of `b`'s width: asking for the same piece again
    /// would only make the base map redraw.
    static func isClose(_ a: Piece, to b: Piece) -> Bool {
        let tolerance = b.width / 1_000
        return abs(a.x - b.x) <= tolerance
            && abs(a.y - b.y) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}

extension PlanCamera {
    /// This camera, but no closer than `size` (points per
    /// ``MapScale/referenceLength``) about the middle of the view: as close
    /// as a base map that refused to come closer can follow
    /// (``BaseMapFollowing/refusal``). Unchanged with no size, or one no
    /// closer than this.
    public func limited(toReferenceSize size: Double?) -> PlanCamera {
        guard let size, size.isFinite, size > 0, referenceSize > size else { return self }
        return zoomed(by: size / referenceSize, around: ScreenPoint(x: viewport.width / 2, y: viewport.height / 2))
    }
}
