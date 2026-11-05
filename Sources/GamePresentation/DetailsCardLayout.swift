// The details card's three layouts (decision 106; decision 588): its head
// and foot pinned with the options scrolling between; where the head and
// foot leave the options too little room, the foot alone pinned, the head
// scrolling away with the options; and, where even the foot leaves too
// little, the whole card scrolling. Choosing on each layout pass switched
// the card back and forth when its head took a line more or less: a
// train's summary does as it stops and starts, several times a minute at
// the demo's speed. Each switch put the options back at their top and
// closed a menu open among them (TestFlight 56.1). So the choice keeps to
// the layout the card has until another is needed.
//
// Decision 588: a phone is held on its side only, and there a pinned head
// and foot left the options some 70 pt (decision 584's screenshots): the
// options to place a train needed scrolling, and with English's longer
// words the whole card scrolled, its Place … Here button below the card's
// edge. The foot holds the action button (and, while a train is placed,
// what is chosen for it, ``placesTrain``), so it is the part kept in view.

/// The layout of the details card: from the heights the card shows, in
/// points, and the layout it has now.
public enum DetailsCardLayout: Equatable, Sendable {
    /// The head and foot stay put, the options scrolling between.
    case pinned
    /// The foot stays put; the head scrolls with the options above it.
    case footPinned
    /// The whole card scrolls.
    case whole

    /// The room the options need for the card to pin its head as well as
    /// its foot: about three rows of options (decision 588; two before,
    /// some 70 pt on a phone held on its side once the fades are taken).
    public static let roomyMiddle: Double = 132
    /// The least the options keep before a pinned head scrolls away: about
    /// two rows. The gap to ``roomyMiddle`` is more than a head's line or
    /// two of text.
    public static let leastMiddle: Double = 88
    /// The room the options need for the card to pin its foot: about one
    /// row.
    public static let leastKept: Double = 44
    /// The least the options keep before a pinned foot scrolls too: what
    /// is left of a row when the foot takes a line more (a platform's
    /// warning under the platforms).
    public static let leastFootKept: Double = 24

    /// The layout for a head and foot of these heights in a card at most
    /// `maxHeight` high, the card having `current` now (`nil` before it
    /// has one, or when it begins to show something new). Each layout is
    /// kept on less room than it takes to enter, by more than a head's or
    /// foot's line, so a line more or less keeps the layout.
    public static func layout(head: Double, foot: Double, maxHeight: Double, current: DetailsCardLayout?) -> DetailsCardLayout {
        let headRoom = current == .pinned ? leastMiddle : roomyMiddle
        if head + foot + headRoom <= maxHeight { return .pinned }
        let footRoom = current == .whole || current == nil ? leastKept : leastFootKept
        if foot + footRoom <= maxHeight { return .footPinned }
        return .whole
    }

    /// Whether the card's foot holds what is chosen for a train being
    /// placed (its cars and platform) above the Place button, rather than
    /// the options in the middle (decision 588): the train tool, with a
    /// train not on the track selected.
    public static func placesTrain(tool: ConstructionTool, trainIsSelected: Bool, trainIsOnTrack: Bool) -> Bool {
        tool == .train && trainIsSelected && !trainIsOnTrack
    }
}
