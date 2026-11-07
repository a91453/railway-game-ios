import XCTest
@testable import GamePresentation

/// Decision 608, second continuation: the 3D map's per-frame buffers are
/// three sets in turn, made only when a frame needs more than was kept.
final class Map3DFrameBuffersTests: XCTestCase {
    private final class Fake {
        let id: Int, bytes: Int
        init(id: Int, bytes: Int) { self.id = id; self.bytes = bytes }
    }

    private var nextID = 0
    private func make(_ bytes: Int) -> Fake? {
        nextID += 1
        return Fake(id: nextID, bytes: bytes)
    }

    func testTheSetsTakeTurns() {
        var ring = Map3DFrameBuffers<Fake>()
        XCTAssertNil(ring.current)
        var seen: [Int] = []
        for _ in 0..<7 {
            ring.advance()
            seen.append(ring.current!)
        }
        XCTAssertEqual(seen, [0, 1, 2, 0, 1, 2, 0])
    }

    func testNoSetNoBuffer() {
        var ring = Map3DFrameBuffers<Fake>()
        XCTAssertNil(ring.buffer(.cars, bytes: 100, make: make))
        ring.advance()
        XCTAssertNil(ring.buffer(.cars, bytes: 0, make: make))
        XCTAssertEqual(ring.madeCount, 0)
    }

    func testCapacityIsAPowerOfTwoFromAPage() {
        XCTAssertEqual(Map3DFrameBuffers<Fake>.capacity(for: 1), 4096)
        XCTAssertEqual(Map3DFrameBuffers<Fake>.capacity(for: 4096), 4096)
        XCTAssertEqual(Map3DFrameBuffers<Fake>.capacity(for: 4097), 8192)
        XCTAssertEqual(Map3DFrameBuffers<Fake>.capacity(for: 1_000_000), 1_048_576)
    }

    /// Each set keeps its own buffers: a frame never fills the buffer an
    /// earlier frame still in flight reads.
    func testEachSetHasItsOwnBuffers() {
        var ring = Map3DFrameBuffers<Fake>()
        var ids: [Int] = []
        for _ in 0..<Map3DFrameBuffers<Fake>.sets {
            ring.advance()
            ids.append(ring.buffer(.boxVertices, bytes: 1000, make: make)!.id)
        }
        XCTAssertEqual(Set(ids).count, 3)
        ring.advance()
        XCTAssertEqual(ring.buffer(.boxVertices, bytes: 1000, make: make)!.id, ids[0])
        // And each use its own within a set.
        XCTAssertNotEqual(ring.buffer(.boxIndices, bytes: 1000, make: make)!.id, ids[0])
    }

    /// The point of it: once the sets have grown to what the frames need,
    /// no frame makes a buffer. Before, every frame made one a use drawn
    /// (up to seven).
    func testASteadyRunMakesNoBuffers() {
        var ring = Map3DFrameBuffers<Fake>()
        // Frames whose needs wander up and down, the largest early.
        func frame(_ n: Int) {
            ring.advance()
            for use in Map3DFrameBuffers<Fake>.Use.allCases {
                let bytes = 20_000 + ((n * 7919 + use.rawValue * 104_729) % 30_000)
                let buffer = ring.buffer(use, bytes: bytes, make: make)
                XCTAssertNotNil(buffer)
                XCTAssertGreaterThanOrEqual(buffer!.bytes, bytes)
            }
        }
        for n in 0..<30 { frame(n) }
        let warmed = ring.madeCount
        // At most a few growths a buffer: 7 uses × 3 sets, each from 32 KB.
        XCTAssertLessThanOrEqual(warmed, 7 * 3 * 2)
        for n in 0..<600 { frame(n % 30) }
        XCTAssertEqual(ring.madeCount, warmed)
    }

    /// A larger need makes the buffer again, larger, and keeps it; a smaller
    /// one afterwards reuses it.
    func testGrowsAndKeeps() {
        var ring = Map3DFrameBuffers<Fake>()
        ring.advance()
        let small = ring.buffer(.glass, bytes: 5000, make: make)!
        XCTAssertEqual(small.bytes, 8192)
        let large = ring.buffer(.glass, bytes: 100_000, make: make)!
        XCTAssertEqual(large.bytes, 131_072)
        XCTAssertEqual(ring.bytes(.glass), 131_072)
        XCTAssertEqual(ring.buffer(.glass, bytes: 10, make: make)!.id, large.id)
        XCTAssertEqual(ring.madeCount, 2)
    }

    /// When making fails, the old buffer stays and nothing is counted.
    func testAFailedMakeKeepsTheOld() {
        var ring = Map3DFrameBuffers<Fake>()
        ring.advance()
        let kept = ring.buffer(.life, bytes: 100, make: make)!
        XCTAssertNil(ring.buffer(.life, bytes: 1_000_000, make: { _ in nil }))
        XCTAssertEqual(ring.buffer(.life, bytes: 100, make: make)!.id, kept.id)
        XCTAssertEqual(ring.madeCount, 1)
    }
}
