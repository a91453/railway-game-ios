import Foundation
@testable import GameCore
@testable import GamePresentation

/// Replays a problem report's command log (ARCHITECTURE decision 193)
/// through a session with no screen, as the device ran it: a session from
/// the save it starts from, given the app's bundled data when the device's
/// session had it, then every entry through the path the session logged it
/// from. So land read in round a new station (decision 88) and the ground
/// under new track (decision 124) come from the same files, and Undo and
/// Redo go back through the same snapshots.
@MainActor
struct CommandLogReplay {
    let session: GameSession
    /// How many entries were replayed.
    private(set) var replayed = 0
    /// Why the replay stopped before the end: the entry's index and the
    /// reason.
    private(set) var stopped: (index: Int, reason: String)?
    /// What may make it part from the device's game: data files or a
    /// build other than the report's.
    private(set) var warnings: [String] = []

    /// The repository's root, found from this file.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The app's bundled file `name`, as the app reads it.
    static func bundled(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/\(name)"))
    }

    /// The bundled data, read once and only when a report needs it
    /// (decision 260: through the headless game's reader).
    static let realWorld = RealWorldFiles(folder: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld"))

    /// Replays `report`, at most `limit` entries.
    init(_ report: CommandLogReport, limit: Int? = nil) throws {
        let game = HeadlessGame(world: report.start.world)
        session = game.session
        // The device's session paused for events and logged it: replay as
        // it ran.
        session.pausesForImportantEvents = true
        try game.install(report.startData, from: Self.realWorld)
        for (file, digest) in report.data.sorted(by: { $0.key < $1.key }) {
            guard let ours = try? Self.bundled(file) else {
                warnings.append("\(file): not in this checkout")
                continue
            }
            if CommandLogReport.digest(of: ours) != digest {
                warnings.append("\(file): the report's app read another version (\(digest), here \(CommandLogReport.digest(of: ours)))")
            }
        }
        // Decision 260: each entry as the headless game replays it.
        for (index, entry) in report.entries.enumerated().prefix(limit ?? .max) {
            if let reason = try game.step(entry, realWorld: Self.realWorld) {
                stopped = (index, reason)
                return
            }
            replayed += 1
        }
    }
}
