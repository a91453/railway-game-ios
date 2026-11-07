// Decision 608, second continuation (MAP3D-MEM-2): the buffers the 3D map
// fills anew every frame (the trains drawn as boxes, their shadows, the
// cars' instances, the street life's instances, the sorted glass) are not
// made every frame. There are three sets, a frame's each in turn, as the
// street life's three buffers were (decision 259); a frame waits for the
// GPU to be done with the set it fills (the view's semaphore of three).
// A buffer too small for this frame's bytes is made again, larger, and
// kept; it never shrinks, so after the first frames of a view no buffer
// is made at all. What a frame draws reads only its own bytes (the index
// and vertex counts and instance offsets are this frame's), so the larger
// buffer draws the same pixels.
//
// Generic over the buffer so Linux tests count what is made; the app
// gives it `MTLBuffer`.

/// Three sets of reusable per-frame buffers, one set a frame in turn.
public struct Map3DFrameBuffers<Buffer> {
    /// What each buffer of a set holds.
    public enum Use: Int, CaseIterable, Sendable {
        case boxVertices, boxIndices, shadowVertices, shadowIndices, cars, life, glass
    }

    /// How many sets there are: as many frames as the GPU may have in
    /// flight.
    public static var sets: Int { 3 }

    /// The smallest buffer made: a page.
    public static var smallest: Int { 4096 }

    /// The bytes a buffer is made with to hold `bytes`: the next power of
    /// two, at least ``smallest``, so a slowly growing need makes few
    /// buffers.
    public static func capacity(for bytes: Int) -> Int {
        var capacity = smallest
        while capacity < bytes { capacity *= 2 }
        return capacity
    }

    private var made: [[(buffer: Buffer, bytes: Int)?]]
    /// The set this frame fills; `nil` before the first frame took one.
    public private(set) var current: Int?
    /// How many buffers have been made in all.
    public private(set) var madeCount = 0

    public init() {
        made = Array(repeating: Array(repeating: nil, count: Use.allCases.count), count: Self.sets)
    }

    /// Moves to the next set; the caller has waited for the GPU to be done
    /// with it.
    public mutating func advance() {
        current = ((current ?? -1) + 1) % Self.sets
    }

    /// The current set's buffer for `use`, holding at least `bytes`: the
    /// one kept when it is large enough, else a new one from `make` (given
    /// the capacity), kept in its place. `nil` when no set is current,
    /// `bytes` is not positive or `make` fails (the old buffer is kept).
    public mutating func buffer(_ use: Use, bytes: Int, make: (Int) -> Buffer?) -> Buffer? {
        guard let current, bytes > 0 else { return nil }
        if let kept = made[current][use.rawValue], kept.bytes >= bytes { return kept.buffer }
        let capacity = Self.capacity(for: bytes)
        guard let buffer = make(capacity) else { return nil }
        madeCount += 1
        made[current][use.rawValue] = (buffer, capacity)
        return buffer
    }

    /// The bytes the current set's buffer for `use` holds (0 when none).
    public func bytes(_ use: Use) -> Int {
        guard let current else { return 0 }
        return made[current][use.rawValue]?.bytes ?? 0
    }
}
