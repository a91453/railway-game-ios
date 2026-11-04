/// How strongly each end of a row that scrolls sideways fades out (the
/// network tool's mode row, decision 574's next step): a fade shows the
/// player there is more past that end, and goes once the row is scrolled
/// to it. Each follows the scroll position itself, growing over the first
/// ``width`` points of what is hidden past that end, so nothing is
/// animated and Reduce Motion has nothing to change.
public struct ScrollEdgeFade: Equatable, Sendable {
    /// How wide each fade is, in points; over the same distance of hidden
    /// row it comes in fully.
    public static let width = 24.0

    /// The fade at the start (left) end, 0 (none) to 1 (full).
    public var leading: Double
    /// The fade at the end (right) end, 0 (none) to 1 (full).
    public var trailing: Double

    public init(leading: Double, trailing: Double) {
        self.leading = leading
        self.trailing = trailing
    }

    /// The fades of a row `contentWidth` wide, seen through `viewportWidth`
    /// points, scrolled `offset` points past its start.
    public init(offset: Double, contentWidth: Double, viewportWidth: Double) {
        let hiddenBefore = offset
        let hiddenAfter = contentWidth - viewportWidth - offset
        leading = Self.strength(hidden: hiddenBefore)
        trailing = Self.strength(hidden: hiddenAfter)
    }

    /// No fade: the row fits, or nothing is known yet.
    public static let none = ScrollEdgeFade(leading: 0, trailing: 0)

    private static func strength(hidden: Double) -> Double {
        // Less than half a point is rounding, not more of the row.
        guard hidden.isFinite, hidden > 0.5 else { return 0 }
        return min(1, hidden / width)
    }
}
