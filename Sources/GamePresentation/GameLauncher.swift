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

    /// Who lives where on real-world maps in Taiwan, handed to every game
    /// it starts (``GameSession/population``); `nil` without the app's
    /// bundled grid, or while it is read (``isLoadingRealWorldData``).
    public var population: PopulationGrid?

    /// What there is around places on real-world maps in Taiwan, handed to
    /// every game it starts (``GameSession/places``).
    public var places: PlaceGrid?

    /// Taiwan's water, the sea, rivers and lakes, on real-world maps
    /// (decision 105), handed to every game it starts
    /// (``GameSession/water``).
    public var water: WaterGrid?
    /// Taiwan's ground height (decision 124), from the app's heights file;
    /// `nil` until it is read, or without it.
    public var heights: HeightGrid?

    /// Taiwan's real railways (stations and lines) for real-world maps, handed
    /// to every game it starts (``GameSession/railways``).
    public var railways: RealRailways?

    /// Whether the app's real-world data is being read
    /// (``loadRealWorldData(reading:)``). Until it has been, ``population``,
    /// ``places`` and ``railways`` are `nil`, and the start screen's
    /// real-world maps wait for them.
    public private(set) var isLoadingRealWorldData = false

    /// The real-world files that could not be read, and why
    /// (``RealWorldData/issues``); empty until they have been read.
    public private(set) var realWorldIssues: [RealDataLoadIssue] = []

    /// The app's sound player, handed to every game it starts
    /// (``GameSession/playSound``); `nil` plays nothing. Going into or out
    /// of a game whooshes (``SoundCue/transition``).
    @ObservationIgnored public var playSound: (@MainActor (SoundCue) -> Void)? {
        didSet { session?.playSound = playSound }
    }

    @ObservationIgnored let library: SaveLibrary
    /// The player's best result in each challenge (decision 87), kept in
    /// the saves' folder in a file that is not a save.
    public private(set) var records: ChallengeRecords
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var autosaveLoop: Task<Void, Never>?
    @ObservationIgnored private var realWorldLoad: Task<Void, Never>?

    public init(library: SaveLibrary, language: DisplayLanguage) {
        self.library = library
        self.language = language
        records = ChallengeRecords(file: library.directory.appendingPathComponent("challenge-records.data"))
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
        let world = GameWorld.newGame(
            anchor: anchor, eventSeed: .random(in: .min ... .max), land: anchor.flatMap(land(at:)), water: anchor.map(water(at:)) ?? [],
            steep: anchor.map(steep(at:)) ?? []
        )
        begin(anchor == nil ? world : grounded(world), keepingAutosave: true)
    }

    /// Starts a new game on the whole of Taiwan (decision 88), its land
    /// read in round each station as it is built.
    public func startWholeTaiwan() {
        begin(grounded(.newWholeTaiwanGame(eventSeed: .random(in: .min ... .max))), keepingAutosave: true)
    }

    /// `world`, a new real-world game, with ground (decision 124) when the
    /// app has its heights file: the network tool reads the ground in as
    /// track comes to it. Without the file the map stays flat, as before.
    private func grounded(_ world: GameWorld) -> GameWorld {
        guard heights != nil else { return world }
        var world = world
        try? world.mapGround()
        return world
    }

    /// Starts a new game on a blank map with `challenge`'s goals (decision
    /// 86), its towns drawn from a new seed.
    public func startChallenge(_ challenge: Challenge) {
        switch challenge.map {
        case .blank:
            begin(.newGame(challenge: challenge, eventSeed: .random(in: .min ... .max)), keepingAutosave: true)
        case .pingxi:
            // Decision 90: on the real-world demo's map, which waits for the
            // real railways, read at launch.
            guard let railways else {
                message = StatusMessage(kind: .failure, text: language.text(
                    "The real-world data is not ready yet.", "實景資料還沒準備好。"
                ))
                return
            }
            begin(
                PingxiChallenge.make(
                    in: language, railways: railways, land: land(at: RealWorldDemo.anchor), water: water(at: RealWorldDemo.anchor),
                    steep: steep(at: RealWorldDemo.anchor)
                ),
                keepingAutosave: true
            )
        }
    }

    /// Starts the week's challenge (decision 87): the map every player gets
    /// in the week containing `date`, Taiwan time.
    public func startWeeklyChallenge(at date: Date = Date()) {
        begin(.newGame(weekly: WeeklyChallenge(containing: date)), keepingAutosave: true)
    }

    /// Keeps the game's challenge result if it is the player's best
    /// (decision 87), and says so on the status line.
    public func recordChallengeResult(at date: Date = Date()) {
        guard let session, records.record(session.world, at: date),
              let record = session.world.scenario.flatMap({ records.best[$0.scenario.id] }) else { return }
        session.message = StatusMessage(kind: .success, text: language.text("New best! \(record.text(in: language))", "刷新紀錄！\(record.text(in: language))"))
    }

    /// Opens ``DemoWorld``: three lines already running.
    public func openDemo() {
        begin(DemoWorld.make(in: language), keepingAutosave: true)
    }

    /// Opens ``RealWorldDemo``: Taiwan's Pingxi, Yilan and Shenao Lines
    /// built on `railways` and running over Apple's map.
    public func openRealWorldDemo(railways: RealRailways) {
        begin(
            RealWorldDemo.make(
                in: language, railways: railways, land: land(at: RealWorldDemo.anchor), water: water(at: RealWorldDemo.anchor),
                steep: steep(at: RealWorldDemo.anchor)
            ),
            keepingAutosave: true
        )
    }

    /// The people and jobs of a new game's map with its middle at `anchor`
    /// (Phase 6a–6b, ``LandImport``), off its water (decision 105), or
    /// `nil` without the app's population or where no one in it lives or
    /// works.
    func land(at anchor: GeoAnchor) -> [LandCell]? {
        population.flatMap {
            LandImport.cells(
                population: $0, places: places, water: water,
                frame: RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds), bounds: GameWorld.newGameBounds
            )
        }
    }

    /// The water of a new game's map with its middle at `anchor` (decision
    /// 105, ``WaterGrid``): none without the app's water.
    func water(at anchor: GeoAnchor) -> [CellPosition] {
        water?.cells(frame: RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds), bounds: GameWorld.newGameBounds) ?? []
    }

    /// The steep slopes of a new game's map with its middle at `anchor`
    /// (decision 115, from the same file as the water): none without it.
    func steep(at anchor: GeoAnchor) -> [CellPosition] {
        water?.steepCells(frame: RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds), bounds: GameWorld.newGameBounds) ?? []
    }

    /// Starts a new game with the tutorial on its first step (the start
    /// screen's tutorial entry, Stage C5).
    public func startTutorial() {
        guard begin(.newGame(eventSeed: .random(in: .min ... .max)), keepingAutosave: true) else { return }
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
        started.population = population
        started.places = places
        started.water = water
        started.heights = heights
        started.railways = railways
        // Decision 88: land not read round a station built while the app
        // had no population.
        started.readLandRoundStations()
        started.playSound = playSound
        session = started
        message = nil
        playSound?(.transition)
        if isActive {
            started.startGameLoop()
        }
        refresh()
        return true
    }

    // MARK: - Real-world data

    /// Reads the real-world data with `read` off the main actor, so the
    /// start screen shows at once, then hands it to this launcher and to
    /// the game being played, if any (one continued or started while it was
    /// read). ``isLoadingRealWorldData`` is `true` until then, and nothing
    /// sees part of the data: it arrives all at once. Reads once; a second
    /// call returns the first one's task.
    @discardableResult
    public func loadRealWorldData(reading read: @escaping @Sendable () -> RealWorldData) -> Task<Void, Never> {
        if let realWorldLoad { return realWorldLoad }
        isLoadingRealWorldData = true
        let load = Task {
            let data = await Task.detached(priority: .userInitiated, operation: read).value
            self.install(data)
        }
        realWorldLoad = load
        return load
    }

    private func install(_ data: RealWorldData) {
        population = data.population
        places = data.places
        water = data.water
        heights = data.heights
        railways = data.railways
        realWorldIssues = data.issues
        if let session {
            session.population = population
            session.places = places
            session.water = water
            session.heights = heights
            session.railways = railways
        }
        isLoadingRealWorldData = false
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
        recordChallengeResult(at: date)
        do throws(SaveError) {
            try library.save(session.world, as: .autosave, at: date)
            refresh()
            return true
        } catch {
            session.message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
            return false
        }
    }

    /// Autosaves and goes back to the start screen. If the autosave fails
    /// the game stays, with the failure on its status line, rather than
    /// being thrown away unsaved.
    public func returnToStart() {
        guard session == nil || autosaveCurrentGame() else { return }
        let left = session != nil
        session?.stopGameLoop()
        session = nil
        message = nil
        refresh()
        if left {
            playSound?(.transition)
        }
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

/// The real-world data the app bundles: who lives where in Taiwan, what
/// there is around places there, its water (decision 105), and its real
/// railways. Each is `nil` when its files cannot be read, and listed in
/// ``issues``.
public struct RealWorldData: Sendable {
    public let population: PopulationGrid?
    public let places: PlaceGrid?
    public let water: WaterGrid?
    /// Taiwan's ground height (decision 124).
    public let heights: HeightGrid?
    public let railways: RealRailways?
    /// The files that could not be read, and why: the grids' and the
    /// railways' (``RealRailways/Loaded/issues``).
    public let issues: [RealDataLoadIssue]

    public init(
        population: PopulationGrid?, places: PlaceGrid?, water: WaterGrid? = nil, heights: HeightGrid? = nil, railways: RealRailways?,
        issues: [RealDataLoadIssue]
    ) {
        self.population = population
        self.places = places
        self.water = water
        self.heights = heights
        self.railways = railways
        self.issues = issues
    }

    /// Reads `taiwan_population.json`, `taiwan_places.json`,
    /// `taiwan_water.json`, `taiwan_heights.dat` and the railways' files
    /// (``RealRailways/load(file:)``) through `file` (a name and extension
    /// to its contents). About 5.3 MB of JSON is decoded, and 12 MB of heights
    /// read (their rows decoded only when asked): call it off the
    /// main actor.
    public static func load(file: @escaping @Sendable (_ name: String, _ ext: String) throws -> Data) -> RealWorldData {
        var issues: [RealDataLoadIssue] = []
        func grid<Grid>(_ name: String, ext: String = "json", _ make: (Data) throws -> Grid) -> Grid? {
            do {
                return try make(file(name, ext))
            } catch {
                issues.append(RealDataLoadIssue(file: "\(name).\(ext)", error: error))
                return nil
            }
        }
        let population = grid("taiwan_population", PopulationGrid.init(data:))
        let places = grid("taiwan_places", PlaceGrid.init(data:))
        let water = grid("taiwan_water", WaterGrid.init(data:))
        let heights = grid("taiwan_heights", ext: "dat", HeightGrid.init(data:))
        let railways = RealRailways.load(file: file)
        return RealWorldData(
            population: population, places: places, water: water, heights: heights, railways: railways.railways, issues: issues + railways.issues
        )
    }
}
