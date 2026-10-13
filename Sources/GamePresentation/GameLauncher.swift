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
///
/// Decision 192: the periodic autosave is taken in turn into one of
/// ``SaveLibrary/autosaveSlots`` (``autosaveSlotInBackground(at:)``), and
/// the autosave on leaving the game stays the latest, so the player can go
/// back to the game of some minutes before (``load(_:at:)`` of an older
/// autosave, ``autosavesToGoBackTo()``).
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
    /// How much of the ground real buildings cover (decision 147), from
    /// the app's coverage file; `nil` until it is read, or without it.
    public var coverage: CoverageGrid?

    /// Taiwan's place names, which new stations on real-world maps are
    /// named after (decision 159), handed to every game it starts
    /// (``GameSession/placeNames``).
    public var placeNames: PlaceNames?

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
    /// Where the saves are written, one after another (decision 45,
    /// later): a save is encoded and written here, off the main thread,
    /// from a copy of the world taken on it, and whatever else reads or
    /// changes the folder waits here for the saves queued before it, so it
    /// sees the latest of them and no two writes cross.
    @ObservationIgnored private let saveQueue = DispatchQueue(label: "GameLauncher.saves", qos: .userInitiated)
    /// What the launcher keeps between launches (decision 177): the
    /// options of the next new game, whether the tutorial was done.
    public private(set) var preferences: LauncherPreferences
    /// Whether this launch is the app's first (decision 177): no
    /// preferences file was there to read.
    public let isFirstLaunch: Bool
    /// The player's best result in each challenge (decision 87), kept in
    /// the saves' folder in a file that is not a save.
    public private(set) var records: ChallengeRecords
    /// The achievements unlocked (decision 181), kept beside the challenge
    /// records in a file that is not a save.
    public private(set) var achievements: AchievementRecords
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var autosaveLoop: Task<Void, Never>?
    /// The world of the last autosave taken in turn, or of the game when
    /// it began (decision 192): a game left as it was, paused, takes no
    /// slot, so it never pushes out the ones the player may go back to.
    @ObservationIgnored private var lastSlotWorld: GameWorld?
    @ObservationIgnored private var realWorldLoad: Task<Void, Never>?

    public init(library: SaveLibrary, language: DisplayLanguage) {
        self.library = library
        self.language = language
        records = ChallengeRecords(file: library.directory.appendingPathComponent("challenge-records.data"))
        achievements = AchievementRecords(file: library.directory.appendingPathComponent(AchievementRecords.fileName))
        let read = LauncherPreferences.read(from: library.directory.appendingPathComponent(Self.preferencesFileName))
        isFirstLaunch = read == nil
        preferences = read ?? LauncherPreferences()
        refresh()
        if !preferences.hasLaunched {
            preferences.hasLaunched = true
            savePreferences()
        }
    }

    nonisolated static let preferencesFileName = "launcher-preferences.data"

    private func savePreferences() {
        preferences.write(to: library.directory.appendingPathComponent(Self.preferencesFileName))
    }

    /// The options the next new game starts with (decision 177), kept.
    public var newGameOptions: NewGameOptions {
        get { preferences.newGameOptions }
        set {
            guard newValue != preferences.newGameOptions else { return }
            preferences.newGameOptions = newValue
            savePreferences()
        }
    }

    /// Whether the start screen asks a first-time player to follow the
    /// station master (decision 177): until the tutorial is finished or
    /// the card closed, and not for a player who already has a game.
    public var showsFirstGameCard: Bool {
        !preferences.tutorialCompleted && !preferences.firstGameCardDismissed && entries.isEmpty
    }

    /// Closes the first-time card for good.
    public func dismissFirstGameCard() {
        guard !preferences.firstGameCardDismissed else { return }
        preferences.firstGameCardDismissed = true
        savePreferences()
    }

    func noteTutorialStepToResume(_ step: String?) {
        guard step != preferences.tutorialStepToResume else { return }
        preferences.tutorialStepToResume = step
        savePreferences()
    }

    func noteTutorialCompleted() {
        guard !preferences.tutorialCompleted else { return }
        preferences.tutorialCompleted = true
        savePreferences()
    }

    /// The newest autosave that can be loaded, if there is one: the game
    /// Continue goes on with.
    public var autosave: SaveLibrary.Entry? {
        entries.first { $0.kind == .autosave && $0.problem == nil }
    }

    /// The other autosaves that can be loaded (decision 192), the newest
    /// first: the game as it was some minutes before.
    public var olderAutosaves: [SaveLibrary.Entry] {
        entries.filter { $0.kind == .autosave && $0.problem == nil && $0 != autosave }
    }

    /// The player's own saves, and autosaves that cannot be loaded.
    public var otherSaves: [SaveLibrary.Entry] {
        entries.filter { $0.kind == .manual || $0.problem != nil }
    }

    /// The autosaves of the game being played that can be loaded, the
    /// newest first, read now (decision 192): what the game menu offers to
    /// go back to. Reads the autosaves alone, after the saves queued, off
    /// the main thread: six saves of the high-speed demo take some 0.4 s.
    /// With none, the game's status line says when there will be one.
    public func autosavesToGoBackTo() async -> [SaveLibrary.Entry] {
        let library = library
        let read = await withCheckedContinuation { (read: CheckedContinuation<[SaveLibrary.Entry], Never>) in
            saveQueue.async { read.resume(returning: library.autosaves()) }
        }
        let autosaves = read.filter { $0.problem == nil }
        if autosaves.isEmpty {
            session?.message = StatusMessage(kind: .failure, text: language.text(
                "There is no autosave to go back to yet: one is taken every 15 minutes of play.",
                "還沒有可以回去的自動存檔：遊戲中每 15 分鐘會存一份。"
            ))
        }
        return autosaves
    }

    public func refresh() {
        let library = library
        entries = saveQueue.sync { library.entries() }
    }

    // MARK: - Starting a game

    /// Starts a new game: on a blank map, bought tile by tile as the
    /// railway grows (decision 160), or with `anchor` on a real-world map
    /// with its middle there (Stage E2). A place of Taiwan, with the app's
    /// people, is the island bought tile by tile from the 16 km round it
    /// (decision 167, ``RealWorldExpansion``); any other place is a 16 km
    /// map.
    ///
    /// Decision 177: it starts with the player's ``newGameOptions``
    /// (standard unless changed): the cash, the disruptions, the rules
    /// the new game turns on and the seed; and on a real-world map, the
    /// ground (decision 198).
    public func startNewGame(at anchor: GeoAnchor? = nil) {
        let options = newGameOptions
        let seed = options.eventSeed()
        if let anchor, let population, let expansion = RealWorldExpansion(around: anchor) {
            let step = expansion.ridersStep(population: population, places: places, water: water)
            var world = GameWorld.newRealWorldExpansionGame(expansion, ridersStep: step, balance: options.startingBalance, eventSeed: seed)
            options.apply(to: &world)
            begin(grounded(world, options.ground), keepingAutosave: true)
            return
        }
        var world = GameWorld.newGame(
            anchor: anchor, balance: options.startingBalance, eventSeed: seed, land: anchor.flatMap(land(at:)),
            water: anchor.map(water(at:)) ?? [], steep: anchor.map(steep(at:)) ?? [], buysMap: anchor == nil && options.buysMap
        )
        options.apply(to: &world)
        begin(anchor == nil ? world : grounded(world, options.ground), keepingAutosave: true)
    }

    /// Starts a new game on the whole of Taiwan (decision 88), its land
    /// read in round each station as it is built.
    public func startWholeTaiwan() {
        let options = newGameOptions
        var world = GameWorld.newWholeTaiwanGame(balance: options.startingBalance, eventSeed: options.eventSeed())
        options.apply(to: &world)
        begin(grounded(world, options.ground), keepingAutosave: true)
    }

    /// `world`, a new real-world game, with ground (decision 124) when the
    /// app has its heights file and `ground` is real: the network tool
    /// reads the ground in as track comes to it. Without the file, or on
    /// flat ground (decision 198), the map stays flat and its track level,
    /// in the game and in its saves.
    private func grounded(_ world: GameWorld, _ ground: NewGameOptions.Ground) -> GameWorld {
        guard heights != nil, ground == .real else { return world }
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
        case .liuMingchuan:
            // Decision 153: the map from Keelung to Hsinchu, its towns read
            // in round the places the milestones name, and its ground. Its
            // towns are the real-world data's, read at launch.
            guard population != nil else {
                message = StatusMessage(kind: .failure, text: language.text(
                    "The real-world data is not ready yet.", "實景資料還沒準備好。"
                ))
                return
            }
            var world = LiuMingchuanChallenge.make(eventSeed: .random(in: .min ... .max))
            GameSession.readLand(
                within: WholeTaiwan.landReach, of: LiuMingchuanChallenge.towns.map(\.point), in: &world, population: population, places: places,
                water: water, coverage: coverage
            )
            begin(grounded(world, .real), keepingAutosave: true)
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

    /// Unlocks the achievements `session`'s world meets (decision 181),
    /// unless it is a demo, and says so in the game.
    func checkAchievements(of session: GameSession, at date: Date = Date()) {
        guard !session.news.isDemo, session.tutorial == nil else { return }
        let unlocked = achievements.unlock(meeting: AchievementFacts(world: session.world), at: date, only: Self.achievementScope(of: session.world))
        session.noteAchievements(unlocked)
    }

    /// What a world may unlock: everything, but for the Pingxi challenge,
    /// which starts on the real-world demo's running lines (the track, the
    /// trains and the hubs are not the player's work), where only the
    /// challenge's own marks count.
    static func achievementScope(of world: GameWorld) -> Set<String>? {
        world.scenario?.scenario.id == "history.pingxi" ? ["challengeGold", "pingxi"] : nil
    }

    /// Opens ``DemoWorld``: three lines already running.
    public func openDemo() {
        begin(DemoWorld.make(in: language), keepingAutosave: true, isDemo: true)
    }

    /// Opens a website screenshot scene (decision 165), paused at the
    /// moment it shows; only the Debug app's `-screenshot-scene` launch
    /// argument asks for one. The scene runs on to its moment off the main
    /// actor (some 20 seconds), with the start screen showing meanwhile.
    @discardableResult
    public func openScreenshotScene(_ scene: ScreenshotScene) -> Task<Void, Never> {
        let language = language
        return Task {
            let world = await Task.detached(priority: .userInitiated) { scene.make(in: language) }.value
            self.begin(world, keepingAutosave: true, isDemo: true)
        }
    }

    /// Opens ``RealWorldDemo``: Taiwan's Yilan, Western Trunk, Pingxi and
    /// Shenao Lines built on `railways` over the ground of the app's
    /// heights (decision 132) and running over Apple's map.
    public func openRealWorldDemo(railways: RealRailways) {
        begin(
            RealWorldDemo.make(
                in: language, railways: railways, land: land(at: RealWorldDemo.anchor), water: water(at: RealWorldDemo.anchor),
                steep: steep(at: RealWorldDemo.anchor), heights: heights
            ),
            keepingAutosave: true, isDemo: true
        )
    }

    /// Whether ``openHighSpeedDemo(railways:)`` is building its game.
    public private(set) var isOpeningHighSpeedDemo = false

    /// Opens ``HighSpeedDemo`` (decision 170): the Taiwan High Speed Rail,
    /// Nangang to Zuoying, built on its real alignment over the whole of
    /// Taiwan and running. It is the heaviest game to start (350 km of
    /// track, the land round twelve stations, the sets sent out), so it is
    /// built off the main actor, with the start screen showing meanwhile
    /// (``isOpeningHighSpeedDemo``). Returns the task, or `nil` while one
    /// is being built already. A game the player starts meanwhile stays.
    @discardableResult
    public func openHighSpeedDemo(railways: RealRailways) -> Task<Void, Never>? {
        guard !isOpeningHighSpeedDemo else { return nil }
        isOpeningHighSpeedDemo = true
        let (language, population, places, water, coverage) = (language, population, places, water, coverage)
        return Task {
            let world = await Task.detached(priority: .userInitiated) {
                try? HighSpeedDemo.make(
                    in: language, railways: railways, population: population, places: places, water: water, coverage: coverage,
                    eventSeed: .random(in: .min ... .max)
                )
            }.value
            isOpeningHighSpeedDemo = false
            guard let world else {
                message = StatusMessage(kind: .failure, text: language.text(
                    "The High Speed Rail could not be built from the real-world data.", "無法用實景資料蓋出高鐵。"
                ))
                return
            }
            // A game started meanwhile, from the start screen behind the
            // sheet, is not replaced.
            guard session == nil else { return }
            begin(world, keepingAutosave: true, isDemo: true)
        }
    }

    /// The people and jobs of a new game's map with its middle at `anchor`
    /// (Phase 6a–6b, ``LandImport``), off its water (decision 105), or
    /// `nil` without the app's population or where no one in it lives or
    /// works.
    /// Since decision 147 each cell has the coverage of the app's
    /// coverage file, when it has been read.
    func land(at anchor: GeoAnchor) -> [LandCell]? {
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        let cells = population.flatMap {
            LandImport.cells(population: $0, places: places, water: water, frame: frame, bounds: GameWorld.newGameBounds)
        }
        guard let cells, let coverage else { return cells }
        return coverage.covering(cells, frame: frame)
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
        // Decision 154: the tutorial's first line is not raised by a
        // holiday.
        var world = GameWorld.newGame(eventSeed: .random(in: .min ... .max))
        world.setDisruptions(nil)
        // Decision 157: nor slowed by building materials; decision 169: nor
        // by a crowd at the doors.
        world.setBuildingMaterials(false)
        world.setDoorCrowding(false)
        world.setRollingStockEconomics(false)
        world.setFlexDispatch(false)
        // Decision 174: nor do tourists come to its sights.
        world.setTourism(nil)
        // Decision 183: nor does the city ask it for anything.
        world.setCityRequests(seed: nil)
        guard begin(world, keepingAutosave: true) else { return }
        session?.startTutorial()
    }

    /// Starts the tutorial's game at step `id` (Debug builds'
    /// `-tutorial-step`, for the UI tests of a later step's screen): from
    /// the line chapter on, with what the steps before it have the player
    /// build near the middle of the map: a stretch of track with a station
    /// near each end (nothing left picked), and from `line.create` the two
    /// stations picked for the line, from `line.staff` the line, from
    /// `build.done` its trains. The network tool is left chosen.
    public func startTutorial(atStep id: String) {
        startTutorial()
        guard let session else { return }
        let steps = Tutorial.standardSteps.map(\.id)
        func reaches(_ step: String) -> Bool {
            guard let index = steps.firstIndex(of: id), let first = steps.firstIndex(of: step) else { return false }
            return index >= first
        }
        if reaches("line.open") {
            let tile: Int64 = 1_024
            let reach: Int64 = 512
            let bounds = session.world.bounds
            func point(_ x: Int64) -> PlanPoint {
                PlanPoint(x: bounds.width / 2 - 8 * tile + x * tile, y: bounds.height / 2)
            }
            session.selectTool(.network)
            session.tapNetwork(at: point(2), reach: reach)
            session.tapNetwork(at: point(13), reach: reach)
            session.buildNetworkTrack()
            session.setNetworkMode(.platform)
            for x: Int64 in [4, 11] {
                session.tapNetwork(at: point(x), reach: reach)
                session.addNetworkPlatform()
            }
            session.networkStart = nil
            session.networkEnd = nil
            session.networkEdgePoint = nil
            if reaches("line.create") {
                for station in session.world.stations.suffix(2) {
                    session.selectStation(station.id)
                    session.addSelectedStationToLineDraft()
                }
            }
            if reaches("line.staff") { session.createLineFromDraft() }
            if reaches("build.done") { session.staffSelectedLine(headway: 10) }
        }
        session.startTutorial(atStep: id)
    }

    /// Goes on with the autosave.
    public func continueGame() {
        guard let autosave else {
            message = StatusMessage(kind: .failure, text: language.text("There is no game to continue.", "沒有可以繼續的遊戲。"))
            return
        }
        load(autosave)
    }

    /// Loads `entry`. The autosave is kept first, unless `entry` is an
    /// autosave.
    ///
    /// Decision 192: an autosave other than the newest is going back, and
    /// can be undone. In a game, the game as it is is first kept as the
    /// next autosave taken in turn; on the start screen, the latest
    /// autosave is kept that way. The game gone back to is then the latest
    /// autosave, so Continue goes on with it.
    public func load(_ entry: SaveLibrary.Entry, at date: Date = Date()) {
        if entry.kind == .autosave {
            loadAutosave(entry, at: date)
            return
        }
        do throws(SaveError) {
            let library = library
            let (world, news) = try afterSaves { () throws(SaveError) in (try library.load(entry), library.news(for: entry)) }
            begin(world, keepingAutosave: entry.kind != .autosave, news: news)
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
    }

    private func loadAutosave(_ entry: SaveLibrary.Entry, at date: Date) {
        let playing = session
        if playing != nil { recordChallengeResult(at: date) }
        let current = playing.map { ($0.worldToSave, $0.news) }
        do throws(SaveError) {
            let library = library
            let (world, news, wentBack) = try afterSaves { () throws(SaveError) in
                // Read first: keeping a game in turn may delete the oldest.
                let (world, news) = (try library.load(entry), library.news(for: entry))
                if let (now, log) = current {
                    try library.saveAutosaveSlot(now, news: log, at: date)
                    return (world, news, true)
                }
                guard library.newestAutosave()?.id != entry.id else {
                    return (world, news, false)
                }
                try library.keepLatestAutosaveInSlot()
                return (world, news, true)
            }
            begin(world, keepingAutosave: false, news: news)
            if wentBack {
                autosaveInBackground(at: date)
            }
        } catch {
            let failure = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
            if let playing {
                playing.message = failure
            } else {
                message = failure
            }
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

    /// Plays `world`. Returns whether it started. A demo (`isDemo`)
    /// unlocks no achievements (decision 181), nor does its save later.
    @discardableResult
    private func begin(_ world: GameWorld, keepingAutosave: Bool, news: NewsLog? = nil, isDemo: Bool = false) -> Bool {
        if keepingAutosave {
            do throws(SaveError) {
                let library = library
                try afterSaves { () throws(SaveError) in try library.archiveAutosave() }
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
        started.coverage = coverage
        started.placeNames = placeNames
        started.railways = railways
        // Decision 88: land not read round a station built while the app
        // had no population.
        started.readLandRoundStations()
        started.playSound = playSound
        if let news { started.restoreNews(news) }
        if isDemo { started.news.isDemo = true }
        started.onTutorialCompleted = { [weak self] in self?.noteTutorialCompleted() }
        // Decision 188, later fix: the tutorial skipped, or left, in an
        // earlier game or launch, offered at the same step.
        if !isDemo, let step = preferences.tutorialStepToResume {
            started.keepTutorialToResume(atStep: step)
            started.notedTutorialStepToResume = step
        }
        started.onTutorialStepToResume = { [weak self] step in self?.noteTutorialStepToResume(step) }
        started.onMidnight = { [weak self, weak started] in
            guard let self, let started else { return }
            self.checkAchievements(of: started)
        }
        session = started
        lastSlotWorld = started.worldToSave
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
        coverage = data.coverage
        placeNames = data.placeNames
        railways = data.railways
        realWorldIssues = data.issues
        if let session {
            session.population = population
            session.places = places
            session.water = water
            session.heights = heights
            session.coverage = coverage
            session.placeNames = placeNames
            session.railways = railways
            // Decision 88: land not read round a station built while the
            // app had no population, as when a game begins (``begin``).
            session.readLandRoundStations()
        }
        isLoadingRealWorldData = false
    }

    // MARK: - Saving

    /// Saves the game being played as a new save of the player's own,
    /// reported in the game's status line when it is written.
    /// Named `name` (decision 184), when the player gave one.
    ///
    /// The game is saved as it is now: the world is copied here, and
    /// encoded and written off the main thread (decision 45, later). The
    /// task ends once the status line and the list of saves say so.
    @discardableResult
    public func saveCurrentGame(at date: Date = Date(), named name: String? = nil) -> Task<Void, Never> {
        guard let session else { return Task {} }
        let language = language
        return write(session.worldToSave, news: session.news, as: .manual, at: date, named: name) { [weak self, weak session] result in
            switch result {
            case .success(let entry):
                session?.message = StatusMessage(kind: .success, text: entry.name.map {
                    language.text("Saved the game as \"\($0)\".", "已儲存遊戲：「\($0)」。")
                } ?? language.text("Saved the game.", "已儲存遊戲。"))
            case .failure(let error):
                session?.message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
            }
            self?.refresh()
        }
    }

    /// Writes the game being played over the autosave, waiting for it to
    /// be written. A failure is reported in the game's status line.
    /// Returns whether it was saved; `false` without a game.
    ///
    /// `refreshing` false leaves the list of saves as it was (decision 184,
    /// later): reading the list decodes the head of every save in the
    /// folder on the main thread. The start screen reads it again
    /// (``returnToStart()``).
    ///
    /// The autosave on leaving the app and the periodic one are written in
    /// the background instead (``autosaveInBackground(at:)``,
    /// ``autosaveSlotInBackground(at:)``).
    @discardableResult
    public func autosaveCurrentGame(at date: Date = Date(), refreshing: Bool = true) -> Bool {
        guard let session else { return false }
        recordChallengeResult(at: date)
        let (library, world, news) = (library, session.worldToSave, session.news)
        do throws(SaveError) {
            try afterSaves { () throws(SaveError) in try library.save(world, news: news, as: .autosave, at: date) }
            if refreshing { refresh() }
            return true
        } catch {
            session.message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
            return false
        }
    }

    /// Writes the game being played over the latest autosave in the
    /// background (decision 45, later): the autosave on leaving the app
    /// (the periodic one is taken in turn since decision 192,
    /// ``autosaveSlotInBackground(at:)``). The world is copied now, the moment it is saved; it
    /// is encoded and written off the main thread, so the game does not
    /// stop while it is. A failure is reported in the game's status line
    /// when the task ends. The list of saves is left as it was, as
    /// ``autosaveCurrentGame(at:refreshing:)`` leaves it with `refreshing`
    /// false. `nil` without a game.
    @discardableResult
    public func autosaveInBackground(at date: Date = Date()) -> Task<Void, Never>? {
        guard let session else { return nil }
        recordChallengeResult(at: date)
        let language = language
        return write(session.worldToSave, news: session.news, as: .autosave, at: date) { [weak session] result in
            guard case .failure(let error) = result else { return }
            session?.message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
    }

    /// Takes the game being played as the next autosave in turn (decision
    /// 192), in the background as ``autosaveInBackground(at:)``: the
    /// periodic autosave. Nothing is written, and `nil` returned, when
    /// the game is as the last one taken (or as it began): a paused game
    /// left alone would otherwise push out the autosaves worth going back
    /// to. `nil` without a game.
    @discardableResult
    public func autosaveSlotInBackground(at date: Date = Date()) -> Task<Void, Never>? {
        guard let session else { return nil }
        let world = session.worldToSave
        guard world != lastSlotWorld else { return nil }
        lastSlotWorld = world
        recordChallengeResult(at: date)
        let language = language
        return write(world, news: session.news, as: .autosave, inTurn: true, at: date) { [weak session] result in
            guard case .failure(let error) = result else { return }
            session?.message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
    }

    /// Returns once every save queued so far is written: the app keeps
    /// running in the background until then after leaving the
    /// foreground.
    public func savesWritten() async {
        await withCheckedContinuation { (written: CheckedContinuation<Void, Never>) in
            saveQueue.async { written.resume() }
        }
    }

    /// Queues `world` to be written after the saves already queued, at
    /// once, and calls `done` on the main actor with how it went.
    private func write(
        _ world: GameWorld, news: NewsLog, as kind: SaveLibrary.Kind, inTurn: Bool = false, at date: Date, named name: String? = nil,
        then done: @escaping @MainActor (Result<SaveLibrary.Entry, SaveError>) -> Void
    ) -> Task<Void, Never> {
        let library = library
        let (written, report) = AsyncStream.makeStream(of: Result<SaveLibrary.Entry, SaveError>.self)
        saveQueue.async {
            report.yield(Result { () throws(SaveError) in
                inTurn
                    ? try library.saveAutosaveSlot(world, news: news, at: date).entry
                    : try library.save(world, news: news, as: kind, at: date, named: name)
            })
            report.finish()
        }
        return Task {
            for await result in written {
                done(result)
            }
        }
    }

    /// Runs `work`, which reads or changes the saves' folder, after the
    /// saves queued before it are written.
    @discardableResult
    private func afterSaves<T>(_ work: () throws(SaveError) -> T) throws(SaveError) -> T {
        try saveQueue.sync { Result(catching: work) }.get()
    }

    /// Autosaves and goes back to the start screen. If the autosave fails
    /// the game stays, with the failure on its status line, rather than
    /// being thrown away unsaved.
    public func returnToStart() {
        guard session == nil || autosaveCurrentGame(refreshing: false) else { return }
        let left = session != nil
        session?.stopGameLoop()
        session = nil
        message = nil
        refresh()
        if left {
            playSound?(.transition)
        }
    }

    /// Names the player's save `entry` `name`, or takes its name away when
    /// `name` is empty (decision 184).
    public func rename(_ entry: SaveLibrary.Entry, to name: String) {
        do throws(SaveError) {
            let library = library
            try afterSaves { () throws(SaveError) in try library.rename(entry, to: name) }
            message = nil
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
        refresh()
    }

    public func delete(_ entry: SaveLibrary.Entry) {
        do throws(SaveError) {
            let library = library
            try afterSaves { () throws(SaveError) in try library.delete(entry) }
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
        refresh()
    }

    // MARK: - Foreground and background

    /// Whether the app is in the foreground. The game loop and the
    /// periodic autosave run only then; leaving the foreground stops them
    /// and autosaves in the background (``savesWritten()`` returns once it
    /// is written), and time spent away is not replayed.
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
                    self.autosaveSlotInBackground()
                }
            }
        } else {
            autosaveLoop?.cancel()
            autosaveLoop = nil
            session?.stopGameLoop()
            autosaveInBackground()
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
    /// How much of the ground real buildings cover (decision 147).
    public let coverage: CoverageGrid?
    /// Taiwan's place names (decision 159).
    public let placeNames: PlaceNames?
    public let railways: RealRailways?
    /// The files that could not be read, and why: the grids' and the
    /// railways' (``RealRailways/Loaded/issues``).
    public let issues: [RealDataLoadIssue]

    public init(
        population: PopulationGrid?, places: PlaceGrid?, water: WaterGrid? = nil, heights: HeightGrid? = nil, coverage: CoverageGrid? = nil,
        placeNames: PlaceNames? = nil, railways: RealRailways?, issues: [RealDataLoadIssue]
    ) {
        self.population = population
        self.places = places
        self.water = water
        self.heights = heights
        self.coverage = coverage
        self.placeNames = placeNames
        self.railways = railways
        self.issues = issues
    }

    /// Reads `taiwan_population.json`, `taiwan_places.json`,
    /// `taiwan_water.json`, `taiwan_heights.dat`, `taiwan_coverage.dat`
    /// (decision 147), `taiwan_place_names.json` (decision 159) and the
    /// railways' files
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
        let coverage = grid("taiwan_coverage", ext: "dat", CoverageGrid.init(data:))
        let placeNames = grid("taiwan_place_names", PlaceNames.init(data:))
        let railways = RealRailways.load(file: file)
        return RealWorldData(
            population: population, places: places, water: water, heights: heights, coverage: coverage, placeNames: placeNames,
            railways: railways.railways,
            issues: issues + railways.issues
        )
    }
}
