import Foundation
import GameCore
import Observation

/// Starts, continues, loads and saves games (Stage C4): what the start
/// screen and the game menu do, after the `Ci/` reference's start screen
/// (`screen-save-load-ui`: enter the saved game, or restart fresh) and its
/// local saves.
///
/// It holds the game being played, if any, as its ``GameSession``, the only
/// authority over that game's world; with none, the app shows the start
/// screen. Saving reads the session's world and never changes it.
///
/// The autosave is written when the app leaves the foreground, when the
/// player returns to the start screen, and every ``autosaveInterval`` of
/// play (the reference's `AUTOSAVE_INTERVAL_MS`). Before another game
/// starts, the autosave is kept as a save of the player's own, so starting
/// a new game never loses the last one (the reference archives the current
/// draft before a fresh start).
@MainActor
@Observable
public final class GameLauncher {
    /// The game being played; `nil` on the start screen.
    public private(set) var session: GameSession?
    /// The saves, as ``SaveLibrary/entries()`` lists them, read again
    /// after every change.
    public private(set) var entries: [SaveLibrary.Entry] = []
    /// The outcome of the last start-screen action, such as a save that
    /// would not load.
    public internal(set) var message: StatusMessage?
    public let language: DisplayLanguage

    /// The reference's `AUTOSAVE_INTERVAL_MS`: 15 minutes.
    public nonisolated static let autosaveInterval: Duration = .seconds(900)

    @ObservationIgnored let library: SaveLibrary
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var autosaveLoop: Task<Void, Never>?

    public init(library: SaveLibrary, language: DisplayLanguage) {
        self.library = library
        self.language = language
        refresh()
    }

    /// The autosave, if there is one that can be loaded.
    public var autosave: SaveLibrary.Entry? {
        entries.first { $0.kind == .autosave && $0.problem == nil }
    }

    /// The player's own saves, and an autosave that cannot be loaded.
    public var otherSaves: [SaveLibrary.Entry] {
        entries.filter { $0 != autosave }
    }

    public func refresh() {
        entries = library.entries()
    }

    // MARK: - Starting a game

    /// Starts a new game: on a blank map, or with `anchor` on a real-world
    /// map with its middle there (Stage E2).
    public func startNewGame(at anchor: GeoAnchor? = nil) {
        begin(.newGame(anchor: anchor), keepingAutosave: true)
    }

    /// Opens ``DemoWorld``: two lines already running.
    public func openDemo() {
        begin(DemoWorld.make(in: language), keepingAutosave: true)
    }

    /// Starts a new game with the tutorial on its first step (the start
    /// screen's tutorial entry, Stage C5).
    public func startTutorial() {
        guard begin(.newGame(), keepingAutosave: true) else { return }
        session?.startTutorial()
    }

    /// Goes on with the autosave.
    public func continueGame() {
        guard let autosave else {
            message = StatusMessage(kind: .failure, text: language.text("There is no game to continue.", "沒有可以繼續的遊戲。"))
            return
        }
        load(autosave)
    }

    /// Loads `entry`. The autosave is kept first, unless `entry` is the
    /// autosave.
    public func load(_ entry: SaveLibrary.Entry) {
        do throws(SaveError) {
            begin(try library.load(entry), keepingAutosave: entry.kind != .autosave)
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
    }

    /// Loads a save file the player picked, read by `read` (the
    /// reference's "导入存档并加载"); a file that cannot be read is reported.
    public func importSave(reading read: () throws -> Data) {
        let data: Data
        do {
            data = try read()
        } catch {
            message = StatusMessage(kind: .failure, text: SaveError.fileSystem.playerMessage(in: language))
            return
        }
        importSave(data)
    }

    /// Loads the save file `data`.
    public func importSave(_ data: Data) {
        do throws(SaveError) {
            begin(try SaveLibrary.decode(data), keepingAutosave: true)
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
    }

    /// Plays `world`. Returns whether it started.
    @discardableResult
    private func begin(_ world: GameWorld, keepingAutosave: Bool) -> Bool {
        if keepingAutosave {
            do throws(SaveError) {
                try library.archiveAutosave()
            } catch {
                // Starting anyway would write over the last game.
                message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
                return false
            }
        }
        session?.stopGameLoop()
        let started = GameSession(world: world, language: language)
        session = started
        message = nil
        if isActive {
            started.startGameLoop()
        }
        refresh()
        return true
    }

    // MARK: - Saving

    /// Saves the game being played as a new save of the player's own,
    /// reported in the game's status line.
    public func saveCurrentGame(at date: Date = Date()) {
        guard let session else { return }
        do throws(SaveError) {
            try library.save(session.world, as: .manual, at: date)
            session.message = StatusMessage(kind: .success, text: language.text("Saved the game.", "已儲存遊戲。"))
        } catch {
            session.message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
        refresh()
    }

    /// Writes the game being played over the autosave. A failure is
    /// reported in the game's status line. Returns whether it was saved;
    /// `false` without a game.
    @discardableResult
    public func autosaveCurrentGame(at date: Date = Date()) -> Bool {
        guard let session else { return false }
        do throws(SaveError) {
            try library.save(session.world, as: .autosave, at: date)
            refresh()
            return true
        } catch {
            session.message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
            return false
        }
    }

    /// Autosaves and goes back to the start screen.
    public func returnToStart() {
        autosaveCurrentGame()
        session?.stopGameLoop()
        session = nil
        message = nil
        refresh()
    }

    public func delete(_ entry: SaveLibrary.Entry) {
        do throws(SaveError) {
            try library.delete(entry)
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
        refresh()
    }

    // MARK: - Foreground and background

    /// Whether the app is in the foreground. The game loop and the
    /// periodic autosave run only then; leaving the foreground stops them
    /// and autosaves, and time spent away is not replayed.
    public func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            session?.startGameLoop()
            autosaveLoop = Task { [weak self] in
                while true {
                    do {
                        try await Task.sleep(for: GameLauncher.autosaveInterval)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, let self else { return }
                    self.autosaveCurrentGame()
                }
            }
        } else {
            autosaveLoop?.cancel()
            autosaveLoop = nil
            session?.stopGameLoop()
            autosaveCurrentGame()
        }
    }
}
