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

    /// The bundled data, read once and only when a report needs it.
    static let population = Result { try PopulationGrid(data: bundled("taiwan_population.json")) }
    static let places = Result { try PlaceGrid(data: bundled("taiwan_places.json")) }
    static let water = Result { try WaterGrid(data: bundled("taiwan_water.json")) }
    static let heights = Result { try HeightGrid(data: bundled("taiwan_heights.dat")) }
    static let coverage = Result { try CoverageGrid(data: bundled("taiwan_coverage.dat")) }

    /// Replays `report`, at most `limit` entries.
    init(_ report: CommandLogReport, limit: Int? = nil) throws {
        session = GameSession(world: report.start.world)
        try install(report.startData)
        for (file, digest) in report.data.sorted(by: { $0.key < $1.key }) {
            guard let ours = try? Self.bundled(file) else {
                warnings.append("\(file): not in this checkout")
                continue
            }
            if CommandLogReport.digest(of: ours) != digest {
                warnings.append("\(file): the report's app read another version (\(digest), here \(CommandLogReport.digest(of: ours)))")
            }
        }
        for (index, entry) in report.entries.enumerated().prefix(limit ?? .max) {
            if let reason = try step(entry) {
                stopped = (index, reason)
                return
            }
            replayed += 1
        }
    }

    /// Gives the session the data `data` says the device's had.
    private func install(_ data: RealWorldDataSet) throws {
        if data.population, session.population == nil { session.population = try Self.population.get() }
        if data.places, session.places == nil { session.places = try Self.places.get() }
        if data.water, session.water == nil { session.water = try Self.water.get() }
        if data.heights, session.heights == nil { session.heights = try Self.heights.get() }
        if data.coverage, session.coverage == nil { session.coverage = try Self.coverage.get() }
    }

    /// Replays `entry`; why it cannot, if it cannot.
    private func step(_ entry: CommandLog.Entry) throws -> String? {
        guard session.world.clock.now.seconds == entry.time else {
            return "the game time is \(session.world.clock.now.seconds) s, the device's was \(entry.time) s"
        }
        switch entry.action {
        case .command(let command):
            let outcome = session.perform(command) { _, _, _ in "" }
            if (outcome == nil) != entry.refused {
                return "\(command.name) was \(entry.refused ? "refused" : "made") on the device, not here: \(session.message?.text ?? "")"
            }
        case .advance(let ticks):
            session.advance(ticks: ticks)
        case .setSpeed(let speed):
            session.setSpeed(speed)
        case .pause:
            guard !session.world.clock.isPaused else { return "already paused" }
            session.togglePause()
        case .resume:
            guard session.world.clock.isPaused else { return "not paused" }
            session.togglePause()
        case .undo:
            guard session.canUndo else { return "nothing to undo" }
            session.undo()
        case .redo:
            guard session.canRedo else { return "nothing to redo" }
            session.redo()
        case .readLandRoundStations(let data):
            try install(data)
            session.readLandRoundStations()
        case .readLand(let reach, let point):
            session.readLand(within: reach, of: point)
        case .unrecorded(let caller):
            return "\(caller) changed the world with no recorded command"
        }
        return nil
    }
}
