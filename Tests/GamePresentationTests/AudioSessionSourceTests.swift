import Foundation
import XCTest

/// MENUSTALL (run 41409109160): setting the audio session's category and
/// making it active wait for the system's audio server, and on CI's
/// Simulator that held the main thread 3.2 s each time the app became
/// active. `GameAudio` sets it on a queue of its own.
///
/// This reads the app's sources as text: every use of the shared audio
/// session stands inside a block given to `sessionQueue.async`, with no
/// function begun between the two.
final class AudioSessionSourceTests: XCTestCase {
    private static let app = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp")

    func testTheAudioSessionIsSetOffTheMainThread() throws {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: Self.app.path))
        let files = enumerator.compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") && !$0.hasPrefix("UITests/") }
            .sorted()
        var uses = 0
        var problems: [String] = []
        for file in files {
            let source = try String(contentsOf: Self.app.appendingPathComponent(file), encoding: .utf8)
            let found = Self.uses(in: source)
            uses += found.uses
            problems += found.problems.map { "\(file): \($0)" }
        }
        XCTAssertGreaterThan(uses, 0, "the scan finds GameAudio's session")
        XCTAssertEqual(problems, [], "set the audio session on GameAudio's sessionQueue, not the main thread")
    }

    /// The scan itself: a use inside the queue's block passes, one in a
    /// function of its own does not.
    func testTheScanFindsWhatItLooksFor() {
        let good = Self.uses(in: """
            func setActive() {
                Self.sessionQueue.async {
                    let session = AVAudioSession.sharedInstance()
                    _ = try? session.setCategory(.ambient)
                }
            }
            """)
        XCTAssertEqual(good.uses, 1)
        XCTAssertEqual(good.problems, [])
        let bad = Self.uses(in: """
            func setActive() {
                Self.sessionQueue.async { warmUp() }
            }
            func other() {
                _ = try? AVAudioSession.sharedInstance().setActive(true)
            }
            """)
        XCTAssertEqual(bad.uses, 1)
        XCTAssertEqual(bad.problems.count, 1)
    }

    /// Each `AVAudioSession.sharedInstance()` in `source`, and those not
    /// inside a `sessionQueue.async` block.
    private static func uses(in source: String) -> (uses: Int, problems: [String]) {
        let lines = source.components(separatedBy: "\n")
        var uses = 0
        var problems: [String] = []
        for (index, line) in lines.enumerated() where line.contains("AVAudioSession.sharedInstance()") {
            uses += 1
            // Back to the nearest opening of the queue's block, with no
            // function and no closed block in between.
            var inside = false
            var depth = 0
            for earlier in lines[..<index].reversed() {
                depth += earlier.filter { $0 == "}" }.count - earlier.filter { $0 == "{" }.count
                if earlier.contains("func ") { break }
                if earlier.contains("sessionQueue.async") {
                    inside = depth < 0
                    break
                }
            }
            if !inside { problems.append("line \(index + 1): \(line.trimmingCharacters(in: .whitespaces))") }
        }
        return (uses, problems)
    }
}
