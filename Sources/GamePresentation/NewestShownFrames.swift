/// Review L14-8: the frames of views of which a screen shows one, measured
/// by each while it shows. When one is shown anew (the station master as
/// building begins), the new view is measured before the old one goes, so
/// for a moment both are here; ``newest`` is the one that came last, whose
/// frame is the one staying, not whichever a dictionary happens to list
/// first.
public struct NewestShownFrames<Key: Hashable, Frame> {
    private var frames: [Key: Frame] = [:]
    /// The keys in the order their views were first measured.
    private var order: [Key] = []

    public init() {}

    /// The frame view `key` measured, `nil` once it goes; a view measured
    /// again keeps its place in the order.
    public subscript(key: Key) -> Frame? {
        get { frames[key] }
        set {
            if let newValue {
                if frames.updateValue(newValue, forKey: key) == nil { order.append(key) }
            } else if frames.removeValue(forKey: key) != nil {
                order.removeAll { $0 == key }
            }
        }
    }

    /// The frame of the view shown last that `counts` (one measured with
    /// no size does not), `nil` with none.
    public func newest(where counts: (Frame) -> Bool = { _ in true }) -> Frame? {
        order.reversed().lazy.compactMap { frames[$0] }.first(where: counts)
    }
}

extension NewestShownFrames: Sendable where Key: Sendable, Frame: Sendable {}
