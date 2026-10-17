import Foundation

/// What the launcher remembers between launches (ARCHITECTURE decision
/// 177): that the app has been opened before, that the tutorial was
/// finished, that the first-time card was closed, and the options of the
/// last new game. A small JSON file beside the saves, like the challenge
/// records, and not a save: a file that cannot be read is a first launch.
public struct LauncherPreferences: Codable, Equatable, Sendable {
    public var hasLaunched = false
    public var tutorialCompleted = false
    public var firstGameCardDismissed = false
    public var newGameOptions = NewGameOptions()
    /// The tutorial's step to take it up again at in the next game
    /// (decision 188, later fix): the step it was skipped on, or on screen
    /// when the game was left; `nil` once finished or never begun.
    public var tutorialStepToResume: String?
    /// Decision 266: the most stars each lesson was passed with, by its id;
    /// `nil` in preferences written before the lessons.
    public var lessonStars: [String: Int]?

    public init() {}

    /// Reads `file`, or the defaults when it is missing or damaged.
    static func read(from file: URL) -> LauncherPreferences? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(LauncherPreferences.self, from: $0) }
    }

    func write(to file: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(self) { try? data.write(to: file, options: .atomic) }
    }
}
