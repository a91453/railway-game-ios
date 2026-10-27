import Foundation

/// Decision 351: the demo mode, for showing the game to others without
/// playing up to what is shown. Only a test build (Xcode or TestFlight)
/// has it, and there it is hidden: its switch shows in the settings once
/// the version row has been tapped ``tapsToReveal`` times in a row. The
/// App Store's build has none: the app passes `testBuild` false.
///
/// While on (``GameLauncher/isDemoMode``) every lesson is open, a new game
/// has unlimited funds and the whole map, and every game it starts counts
/// nothing, as a demo: no achievements, station stamps, lesson stars or
/// challenge records. It changes no rule of the game and nothing in a save
/// but what a demo or unlimited funds already write.
public enum DemoMode {
    /// The settings switch, kept on the device; off unless turned on.
    public static let switchKey = "demoMode.on"

    /// How many taps on the version row in a row show the switch.
    public static let tapsToReveal = 5

    /// The longest gap between two taps that still counts them in a row.
    public static let tapGap: TimeInterval = 1.5

    /// Whether the demo mode is on: only in a test build, and only with
    /// its switch on.
    public static func isOn(testBuild: Bool, switchOn: Bool) -> Bool {
        testBuild && switchOn
    }

    /// The taps on the version row, counting towards showing the switch.
    public struct Reveal: Equatable, Sendable {
        public private(set) var taps = 0
        private var last: Date?

        public init() {}

        /// Whether the switch shows: after ``DemoMode/tapsToReveal`` taps in
        /// a row, until the settings close.
        public var isRevealed: Bool { taps >= DemoMode.tapsToReveal }

        /// Counts a tap at `date`, starting again after a pause longer than
        /// `gap` (``DemoMode/tapGap`` unless a UI test, whose taps take over
        /// a second each on a busy Simulator, gives a longer one). Returns
        /// whether this tap showed the switch.
        @discardableResult
        public mutating func tap(at date: Date = Date(), gap: TimeInterval = DemoMode.tapGap) -> Bool {
            guard !isRevealed else { return false }
            if let last, date.timeIntervalSince(last) > gap { taps = 0 }
            last = date
            taps += 1
            return isRevealed
        }
    }
}
