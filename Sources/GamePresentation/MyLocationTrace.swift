import Foundation
import GameCore

// TestFlight 86.1 (the owner's video): after the first press of "Use my
// location" the map only moved further to the north-east, and nothing on
// the screen said whether the press reached the button, whether a fix
// came, or how old it was. A test build (TestFlight or Debug) shows one
// line beside the button, kept until the next press: when it was pressed,
// then what the ask came to. The App Store build shows nothing.

/// What one press of "Use my location" came to, for a test build's line.
public struct MyLocationTrace: Hashable, Sendable {
    /// Where the ask stands.
    public enum Outcome: Hashable, Sendable {
        case locating
        /// A fix `accuracyMetres` across (the location's horizontal
        /// accuracy), taken `ageSeconds` before it reached the app.
        case located(accuracyMetres: Double, ageSeconds: Double)
        /// Location is off for the app or not allowed on the device.
        case denied
        /// The system's error, by its code and description.
        case failed(code: Int, description: String)
        /// No answer within `seconds`.
        case timedOut(seconds: Int)
    }

    /// When the button was pressed, on the device's clock.
    public var hour: Int
    public var minute: Int
    public var second: Int
    public var outcome: Outcome

    public init(hour: Int, minute: Int, second: Int, outcome: Outcome = .locating) {
        self.hour = hour
        self.minute = minute
        self.second = second
        self.outcome = outcome
    }

    /// The line: the press's time, then the outcome.
    public func text(in language: DisplayLanguage) -> String {
        let time = [hour, minute, second].map { $0 < 10 ? "0\($0)" : "\($0)" }.joined(separator: ":")
        let result: String
        switch outcome {
        case .locating:
            result = language.text("Locating…", "定位中…")
        case let .located(accuracy, age):
            let metres = Int(accuracy.rounded()), seconds = Int(max(0, age).rounded())
            result = language.text("Found ±\(metres) m, \(seconds) s old", "成功 ±\(metres) m，\(seconds) 秒前的位置")
        case .denied:
            result = language.text("Location not allowed", "定位未允許")
        case let .failed(code, description):
            result = language.text("Failed: \(code) \(description)", "失敗：\(code) \(description)")
        case let .timedOut(seconds):
            result = language.text("Timed out after \(seconds) s", "逾時 \(seconds) 秒")
        }
        return "\(time) \(result)"
    }
}
