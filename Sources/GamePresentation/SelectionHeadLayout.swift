// The selection card's head: what is picked, in words, and its buttons
// ("Station…", "Sell"). On an iPhone held sideways the side panel's card
// is narrow, and beside the buttons the words kept a column a word or two
// wide and lost their end ("Station · Zuoying · 8 platforms, 1664…", a
// player's report). There the buttons go under the words.

/// Whether the selection card's head puts its buttons under the selection's
/// words rather than beside them, from the head's width in points.
public enum SelectionHeadLayout {
    /// The least width that keeps the buttons beside the words: the mark
    /// (30), a column of about a dozen characters for the words, and the
    /// "Station…" button.
    public static let leastBeside: Double = 300

    /// `width` is 0 before the head has been measured: beside, as before.
    public static func buttonsBelow(width: Double) -> Bool {
        width > 0 && width < leastBeside
    }
}
