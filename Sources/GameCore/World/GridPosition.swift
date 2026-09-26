/// A cell coordinate on the game map.
///
/// `x` grows eastward and `y` grows southward, with `(0, 0)` at the
/// north-west corner. A position carries no knowledge of any particular map;
/// use ``GridMap/contains(_:)`` to check whether it lies inside one.
public struct GridPosition: Hashable, Codable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

extension GridPosition: CustomStringConvertible {
    public var description: String { "(\(x), \(y))" }
}
