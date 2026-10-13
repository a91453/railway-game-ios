// The details card's two layouts (decision 106): its head and foot pinned
// with the options scrolling between, or, when the head and foot leave the
// options too little room, the whole card scrolling. Choosing between them
// on each layout pass switched the card back and forth when its head took a
// line more or less: a train's summary does as it stops and starts, several
// times a minute at the demo's speed. Each switch put the options back at
// their top and closed a menu open among them (TestFlight 56.1). So the
// choice keeps to the layout the card has until the other is needed.

/// Whether the details card pins its head and foot, the options scrolling
/// between: from the heights the card shows, in points, and the layout it
/// has now. Pinned, it stays so while the options keep ``leastKept``; the
/// whole card scrolling, it pins once they would have ``leastMiddle``.
public enum DetailsCardLayout {
    /// The room the options need for the card to pin its head and foot:
    /// about two rows of options.
    public static let leastMiddle: Double = 88
    /// The least the options keep before a pinned card scrolls as a whole:
    /// about one row. The gap to ``leastMiddle`` is more than a head's line
    /// or two of text.
    public static let leastKept: Double = 44

    /// `ends` is the height of the head and foot together, `maxHeight` the
    /// card's, and `pinned` the layout it has now (`nil` before it has one).
    public static func pinsEnds(ends: Double, maxHeight: Double, pinned: Bool?) -> Bool {
        ends + (pinned == true ? leastKept : leastMiddle) <= maxHeight
    }
}
