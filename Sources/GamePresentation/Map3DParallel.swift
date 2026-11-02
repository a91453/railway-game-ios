import Foundation

/// Decision 546: work split over the device's cores whose results come
/// back in their own order, so what is made from them is the same, to the
/// bit, as when they were made one after another (the model pack,
/// ``Map3DModelPack/standard``, `hashes.lock.json`).
enum Map3DParallel {
    /// `work(0)` to `work(count - 1)`, each worked out on whichever core is
    /// free, returned in index order.
    static func map<T: Sendable>(_ count: Int, _ work: @Sendable (Int) -> T) -> [T] {
        guard count > 1 else { return (0..<count).map(work) }
        let results = UnsafeMutableBufferPointer<T?>.allocate(capacity: count)
        results.initialize(repeating: nil)
        defer {
            _ = results.deinitialize()
            results.deallocate()
        }
        // Each index written by one iteration only.
        nonisolated(unsafe) let shared = results
        DispatchQueue.concurrentPerform(iterations: count) { index in
            shared[index] = work(index)
        }
        return results.map { $0! }
    }
}
