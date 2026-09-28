import GameCore
import Observation

/// Owns the app's single authoritative ``GameWorld`` for as long as the app
/// runs, and applies every gameplay change to it through `GameWorld` commands.
///
/// SwiftUI observes the session rather than GameCore: `GameWorld` stays a
/// plain `Sendable` value type, and this class is the one place that holds it.
/// Views read ``world`` and call the session's methods; they never keep their
/// own copy of game state.
///
/// Besides the world, the session keeps only transient UI state: the selected
/// tile, the active tool, the track piece being placed, the draft station name
/// and the last action's message. Anything shown about the game is derived
/// from ``world`` on demand.
///
/// The session also hosts the game loop: it measures real time, turns it into
/// whole ticks with a ``TickAccumulator`` and calls `GameWorld.advance(ticks:)`.
/// Wall-clock time never reaches GameCore.
///
/// Main-actor isolated because both SwiftUI and the game loop run on the main
/// actor, so no locks or `@unchecked Sendable` are needed.
@MainActor
@Observable
public final class GameSession {
    /// The authoritative game state. Only the session mutates it.
    public private(set) var world: GameWorld

    /// The tile the player last selected. Always inside the map when set.
    public private(set) var selection: GridPosition?

    /// What the action button does to the selected tile.
    public private(set) var tool: ConstructionTool = .select

    /// The directions the next track piece connects. May be empty while the
    /// player edits it; GameCore rejects building an empty piece.
    public private(set) var trackConnections: TrackConnections = TrackPiece.straight.connections

    /// Name for the next station. Pre-filled with a suggestion the player can
    /// edit; GameCore decides whether it is valid.
    public var stationName: String

    /// The outcome of the last action, for the status line. Cleared when the
    /// player selects another tile or tool.
    public private(set) var message: StatusMessage?

    /// Real time per simulation tick. At 1× a tick is one game minute, so a
    /// game day lasts 144 real seconds.
    public nonisolated static let tickInterval: Duration = .milliseconds(100)
    /// The most real time one loop step turns into ticks (five ticks).
    public nonisolated static let maximumStepDuration: Duration = .milliseconds(500)

    @ObservationIgnored private var tickAccumulator = TickAccumulator(
        tickInterval: GameSession.tickInterval,
        maximumElapsed: GameSession.maximumStepDuration
    )
    @ObservationIgnored private var gameLoop: Task<Void, Never>?

    public init(world: GameWorld) {
        self.world = world
        self.stationName = Self.suggestedStationName(for: world)
    }

    // MARK: - Selection

    /// The current contents of the selected tile, read from the world.
    public var selectedTile: MapTile? {
        selection.flatMap { world.map.tile(at: $0) }
    }

    /// Selects the tile at `position`; positions outside the map are ignored.
    public func select(_ position: GridPosition) {
        guard world.map.contains(position), position != selection else { return }
        selection = position
        message = nil
    }

    public func clearSelection() {
        selection = nil
        message = nil
    }

    /// Moves the selection one tile toward `direction`, staying inside the map.
    /// Selects the north-west corner if nothing is selected yet.
    public func moveSelection(_ direction: TrackDirection) {
        guard let current = selection else {
            select(GridPosition(x: 0, y: 0))
            return
        }
        var next = current
        switch direction {
        case .north: next.y -= 1
        case .east: next.x += 1
        case .south: next.y += 1
        case .west: next.x -= 1
        }
        select(next)
    }

    // MARK: - Tools

    /// Switches tools. Never changes the world.
    public func selectTool(_ newTool: ConstructionTool) {
        guard newTool != tool else { return }
        tool = newTool
        message = nil
    }

    /// Adds or removes one direction of the next track piece.
    public func toggleTrackDirection(_ direction: TrackDirection) {
        trackConnections.formSymmetricDifference(TrackConnections(direction))
    }

    public func selectTrackPiece(_ piece: TrackPiece) {
        trackConnections = piece.connections
    }

    /// Turns the next track piece a quarter turn clockwise.
    public func rotateTrackPiece() {
        trackConnections = trackConnections.rotatedClockwise
    }

    // MARK: - Speed

    /// Changes the game speed through the world's clock, the only record of it.
    public func setSpeed(_ speed: GameSpeed) {
        world.setSpeed(speed)
    }

    // MARK: - Game loop

    /// Whether the real-time loop is currently advancing the world.
    public var isGameLoopRunning: Bool {
        gameLoop != nil
    }

    /// Turns `elapsed` real time into whole ticks and advances the world by
    /// them. While paused, elapsed time is discarded rather than saved up.
    /// If GameCore refuses to advance (game time is at its limit), the world
    /// is unchanged and the refusal is shown as the status message.
    public func advance(realElapsed elapsed: Duration) {
        guard !world.clock.isPaused else {
            tickAccumulator.reset()
            return
        }
        let ticks = tickAccumulator.ticks(for: elapsed)
        if ticks > 0 {
            do throws(GameError) {
                try world.advance(ticks: ticks)
            } catch {
                message = StatusMessage(kind: .failure, text: error.playerMessage)
            }
        }
    }

    /// Starts advancing the world in real time. Calling it while the loop is
    /// already running does nothing, so the world is never ticked twice.
    public func startGameLoop() {
        guard gameLoop == nil else { return }
        tickAccumulator.reset()
        gameLoop = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while true {
                // Sleeping only paces the loop; the ticks come from measured time.
                do {
                    try await Task.sleep(for: GameSession.tickInterval, clock: clock)
                } catch {
                    return
                }
                // A stop that arrives while this task waits to resume must
                // not let one more step through.
                guard !Task.isCancelled, let self else { return }
                let now = clock.now
                self.advance(realElapsed: now - last)
                last = now
            }
        }
    }

    /// Stops the loop and drops any partial tick. The host calls this when the
    /// app leaves the foreground; restarting later does not replay the time
    /// spent away.
    public func stopGameLoop() {
        gameLoop?.cancel()
        gameLoop = nil
        tickAccumulator.reset()
    }

    // MARK: - Actions

    /// Applies the current tool to the selected tile through the matching
    /// `GameWorld` command, and reports the outcome in ``message``.
    ///
    /// The session does not pre-check game rules: GameCore decides whether an
    /// action is allowed, and a rejected action leaves the world unchanged.
    /// Does nothing without a selection or in ``ConstructionTool/select`` mode.
    public func applyTool() {
        guard let position = selection else { return }
        switch tool {
        case .select:
            return
        case .buildTrack:
            perform { world throws(GameError) in
                let track = try world.buildTrack(at: position, connections: trackConnections)
                return "Built \(track.connections.shapeName.lowercased()) track at \(position)."
            }
        case .buildStation:
            let built = perform { world throws(GameError) in
                // The world allocates the station's ID.
                let station = try world.buildStation(named: stationName, at: position)
                return "Built station “\(station.name)” at \(position)."
            }
            if built {
                stationName = Self.suggestedStationName(for: world)
            }
        case .removeTrack:
            perform { world throws(GameError) in
                try world.removeTrack(at: position)
                return "Removed track at \(position)."
            }
        }
    }

    public func dismissMessage() {
        message = nil
    }

    /// Runs one command against the world and records its outcome. Returns
    /// whether the command succeeded.
    @discardableResult
    private func perform(_ command: (inout GameWorld) throws(GameError) -> String) -> Bool {
        do throws(GameError) {
            message = StatusMessage(kind: .success, text: try command(&world))
            return true
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage)
            return false
        }
    }

    /// "Station N" with the lowest N from the next station number upward
    /// that no existing station uses.
    private static func suggestedStationName(for world: GameWorld) -> String {
        let names = Set(world.stations.map(\.name))
        var number = world.stations.count + 1
        while names.contains("Station \(number)") {
            number += 1
        }
        return "Station \(number)"
    }
}

/// A one-line report of what the last action did.
public struct StatusMessage: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case success
        case failure
    }

    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}
