// Decision 608, second continuation (MAP3D-MEM-2): the buffers the 3D map
// fills anew every frame (the trains drawn as boxes, their shadows, the
// cars' instances, the street life's instances, the sorted glass) are not
// made every frame. There are three sets, a frame's each in turn, as the
// street life's three buffers were (decision 259); a frame waits for the
// GPU to be done with the set it fills (the view's semaphore of three).
// A buffer too small for this frame's bytes is made again, larger, and
// kept, so after the first frames of a view no buffer is made at all.
// Decision 661 (review L13-4): it does not keep growing for good. A buffer
// a set's turns have not asked for, or have asked for no more than a
// quarter of, for ``shrinkAfter`` turns in a row (some 6 seconds) is let
// go and made again at what is asked next; a memory warning lets go of
// every set (``release()``). A frame in flight keeps the buffers it reads
// (the graphics API's command buffer holds them), so letting go is safe
// at any time. What a frame draws reads only its own bytes (the index
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
        /// Decision 617: the glows round the trains' lamps (``Map3DGlow/trainSpots(of:pack:)``).
        case glows
        /// Decision 672: the cars seen through the ground (``Map3DXRay/addCars(_:to:)``),
        /// filled only while seeing underground is on.
        case xrayVertices, xrayIndices
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

    /// Decision 661: how many of a set's turns in a row a buffer may go
    /// unasked for, or asked for at most a quarter of its bytes, before it
    /// is let go: 120 turns, some 6 seconds at 60 frames a second.
    public static var shrinkAfter: Int { 120 }

    private var made: [[(buffer: Buffer, bytes: Int)?]]
    /// Decision 661: whether this turn of the set asked for the buffer at
    /// more than a quarter of its bytes, and how many turns in a row did
    /// not.
    private var fitted: [[Bool]]
    private var slack: [[Int]]
    /// The set this frame fills; `nil` before the first frame took one.
    public private(set) var current: Int?
    /// How many buffers have been made in all.
    public private(set) var madeCount = 0

    public init() {
        made = Array(repeating: Array(repeating: nil, count: Use.allCases.count), count: Self.sets)
        fitted = Array(repeating: Array(repeating: false, count: Use.allCases.count), count: Self.sets)
        slack = Array(repeating: Array(repeating: 0, count: Use.allCases.count), count: Self.sets)
    }

    /// Moves to the next set; the caller has waited for the GPU to be done
    /// with it.
    public mutating func advance() {
        let set = ((current ?? -1) + 1) % Self.sets
        current = set
        // Decision 661: the set's last turn told how much of each buffer
        // it used; one too large for long enough is let go.
        for use in made[set].indices where made[set][use] != nil {
            slack[set][use] = fitted[set][use] ? 0 : slack[set][use] + 1
            if slack[set][use] >= Self.shrinkAfter {
                made[set][use] = nil
                slack[set][use] = 0
            }
            fitted[set][use] = false
        }
    }

    /// Decision 661: lets go of every set's buffers (a memory warning).
    public mutating func release() {
        for set in made.indices {
            for use in made[set].indices {
                made[set][use] = nil
                fitted[set][use] = false
                slack[set][use] = 0
            }
        }
    }

    /// How many buffers are kept in all, and their bytes.
    public var kept: (count: Int, bytes: Int) {
        made.joined().reduce((0, 0)) { sum, slot in slot.map { (sum.0 + 1, sum.1 + $0.bytes) } ?? sum }
    }

    /// The current set's buffer for `use`, holding at least `bytes`: the
    /// one kept when it is large enough, else a new one from `make` (given
    /// the capacity), kept in its place. `nil` when no set is current,
    /// `bytes` is not positive or `make` fails (the old buffer is kept).
    public mutating func buffer(_ use: Use, bytes: Int, make: (Int) -> Buffer?) -> Buffer? {
        guard let current, bytes > 0 else { return nil }
        if let kept = made[current][use.rawValue], kept.bytes >= bytes {
            if kept.bytes < 4 * Self.capacity(for: bytes) { fitted[current][use.rawValue] = true }
            return kept.buffer
        }
        let capacity = Self.capacity(for: bytes)
        guard let buffer = make(capacity) else { return nil }
        madeCount += 1
        made[current][use.rawValue] = (buffer, capacity)
        fitted[current][use.rawValue] = true
        slack[current][use.rawValue] = 0
        return buffer
    }

    /// The bytes the current set's buffer for `use` holds (0 when none).
    public func bytes(_ use: Use) -> Int {
        guard let current else { return 0 }
        return made[current][use.rawValue]?.bytes ?? 0
    }
}
