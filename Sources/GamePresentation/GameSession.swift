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
/// point and station, the active tool, the drafts of the network tool, the draft station name,
/// the selected train, the heading for placing it, the selected line, the
/// stops picked for a new line, the copied station demand, the tutorial on
/// screen, and the last action's message, written in ``language``. Anything shown about the game,
/// including where each train is and where it is going, is derived from
/// ``world`` on demand.
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

    /// The language of the session's messages and suggested names, and of
    /// the text the app derives from the world (Stage L1). Set once: iOS
    /// restarts an app whose language changes.
    public let language: DisplayLanguage

    /// Where the selection is: the point of the player's last tap on the
    /// map, or where the station they picked stands, exactly as it is (Stage
    /// F3d: never rounded to anything coarser). Always in the world's
    /// bounds when set.
    public private(set) var selectedPoint: PlanPoint?

    /// The station the player last picked (Stage F1): an ID only, never a
    /// copy of the station. Read the selected station through
    /// ``selectedStation``. A station is picked by where it stands
    /// (``tapMap(at:reach:)``) or by name (``selectStation(_:)``).
    public private(set) var selectedStationID: StationID?

    /// What the action button does.
    public private(set) var tool: ConstructionTool = .select

    /// What the building tool places where the player taps (decision 92).
    public var buildingKind: PlacedBuildingKind = .house
    /// Whether a tap with the building tool builds or demolishes (decision
    /// 94).
    public var buildingMode: BuildingToolMode = .build {
        didSet {
            buildingSite = nil
            zoneDrag = nil
        }
    }
    /// What the zoning mode zones cells for (decision 98), or `nil` to
    /// clear their zones.
    public var zoningZone: Zone? = .residential
    /// The cells a drag with the zoning mode would zone, while the finger
    /// is down (decision 98).
    public internal(set) var zoneDrag: CellRectangle?
    /// Where the building tool would build, once the player tapped there
    /// (decision 95): the map shows the building there and what it would
    /// cost and pull down, and the action button builds it.
    public internal(set) var buildingSite: PlanPoint?
    /// Whether a tap with the building tool builds there at once rather
    /// than showing the building first (decision 103): for putting up one
    /// building after another. Undo takes each back.
    public var buildingBuildsOnTap = false
    /// While a finger drags the shown building (decision 103): where the
    /// site was when the drag began, which a cancelled drag puts back.
    @ObservationIgnored var buildingDragSiteBefore: PlanPoint?

    /// Name for the next station. Pre-filled with a suggestion the player can
    /// edit; GameCore decides whether it is valid.
    public var stationName: String

    /// The name the session last suggested for ``stationName``. A new
    /// suggestion replaces ``stationName`` only while it is still this one:
    /// a name the player typed is never overwritten.
    @ObservationIgnored var automaticStationName: String

    /// The car count the session last suggested for ``platformCars``
    /// (from a real TRA station's grade); replaced, like the name, only
    /// while the player has not changed it.
    @ObservationIgnored var automaticPlatformCars: Int = GameSession.defaultPlatformCars

    /// The car count a platform is built for where no real default applies.
    static let defaultPlatformCars = 4

    /// The train the train tool acts on: an ID only, never a copy of the
    /// train. Read the train itself through ``selectedTrain``.
    public private(set) var selectedTrainID: TrainID?

    /// The train the last tap on the map picked (see ``tapMap(at:reach:)``),
    /// which the select tool's inspector shows; `nil` once a tap or a
    /// command selects a station or a point instead.
    public private(set) var tappedTrainID: TrainID?

    /// The train the camera follows: the `Ci/` reference's
    /// `trackedTrainId`, kept apart from the selection
    /// (``selectedTrainID``, the reference's `selectedTrainId`), so picking
    /// another train or a station never moves or ends it. An ID only; read
    /// the train through ``followedTrain``, which is `nil` once the train is
    /// gone or off the track. Started with ``followTrain(_:)`` or
    /// ``toggleFollowTrain()``; ended by the player (``stopFollowingTrain()``,
    /// a drag, pinch or zoom of the map through ``mapDidMove()``, closing the
    /// train with ``clearSelection()``), or when the train leaves the track,
    /// stops existing or its line is removed.
    public private(set) var followedTrainID: TrainID?

    /// The way the selected train faces when it is placed: along its
    /// platform, the way nearer this compass point. Only used by
    /// ``placeSelectedTrain()``; it never turns a train that is on the track.
    public private(set) var placementHeading: CompassHeading = .east

    /// The outcome of the last action, for the status line. Cleared when the
    /// player selects another point or tool.
    public internal(set) var message: StatusMessage? {
        didSet { messageSerial &+= 1 }
    }

    /// Counts each time ``message`` is set, the same message again
    /// included: a second "Saved the game." is a newer message, which the
    /// banner announces and shows for its own while
    /// (``StatusMessage/autoDismissDelay``, ``dismissMessage(posted:)``).
    public private(set) var messageSerial: UInt64 = 0

    /// The year that closed while the game ran, until the player has seen
    /// its year-end report (Phase 7a, decision 85): which year it is, never
    /// a copy of the statement, which stays the world's. Read it through
    /// ``yearEndStatement``. Not set by loading a game whose years closed
    /// before.
    public private(set) var yearEndYear: Int64?

    /// The statement of ``yearEndYear``, as the world has it.
    public var yearEndStatement: AnnualStatement? {
        yearEndYear.flatMap { year in world.accounts.years.last { $0.year == year } }
    }

    /// The player has seen the year-end report.
    public func dismissYearEnd() {
        yearEndYear = nil
    }

    /// Whether the scenario ended while the game ran (decision 86), until
    /// the player has seen how: its goals panel opens. Not set by loading a
    /// game whose scenario ended before.
    public private(set) var scenarioJustEnded = false

    /// The player has seen how the scenario ended.
    public func dismissScenarioEnd() {
        scenarioJustEnded = false
    }

    /// The line the line panel shows: an ID only, never a copy of the line.
    /// Read the line itself through ``selectedLine``.
    public private(set) var selectedLineID: LineID?

    /// The stations picked, in order, for the next line. Only a draft:
    /// GameCore checks them when ``createLineFromDraft()`` creates the line.
    public private(set) var lineDraft: [StationID] = []

    /// The stations along the track through ``lineDraft``
    /// (`GameWorld.stationsAlongTrack(through:)`, decision 100), kept up to
    /// date as the draft and the track change; `nil` for fewer than two
    /// picked stations or when no track joins two picked in a row.
    public private(set) var lineDraftRoute: [StationID]?

    /// Which stations along ``lineDraftRoute`` the new line calls at.
    public var lineDraftStopping: LineDraftStopping = .everyStation

    /// The stations along the route the player left out with
    /// ``LineDraftStopping/custom``.
    public private(set) var lineDraftSkipped: Set<StationID> = []

    /// Whether a tap on a station on the map adds it to ``lineDraft``
    /// (decision 100), so the player picks a new line's ends on the map
    /// without a button for each.
    public private(set) var isPickingLineStops = false

    /// The station demand copied to paste onto other stations (Stage C2;
    /// see ``copySelectedStationDemand()``). Only a clipboard: GameCore
    /// checks it when it is pasted.
    public internal(set) var demandClipboard: StationDemand?

    // The network tool (Stage C1): drafts only, read through GameCore when
    // used (see NetworkSession.swift).

    /// What a tap does with the network tool.
    public internal(set) var networkMode: NetworkToolMode = .build
    /// The ends picked for the next stretch of track: an existing node, or
    /// a point for a new one. Nothing is built until
    /// ``buildNetworkTrack()``.
    public internal(set) var networkStart: NetworkAnchor?
    public internal(set) var networkEnd: NetworkAnchor?
    /// While a finger draws track (decision 102): the end picked before the
    /// drag began, which a cancelled drag puts back.
    @ObservationIgnored var networkDragEndBefore: NetworkAnchor??
    /// What carries the next stretch of track.
    public var networkStructure: TrackStructure = .surface
    /// How high a new node goes, in world units (64 to a metre).
    public var networkHeight: Int64 = 0
    /// Whether the next stretch continues the track at its ends smoothly
    /// (the default), or runs straight.
    public var networkFollowsTrack = true
    /// Whether a tap near the track joins it (the default): a node, or a
    /// turnout on an edge, whatever its height. Off, every tap is a new
    /// point at ``networkHeight``, so a parallel track can be laid 4 m
    /// beside another (``RailwayNetwork/trackSpacing``), closer than a tap
    /// reaches, or a viaduct's end set over a track.
    public var networkSnapsToTrack = true
    /// Whether a stretch between two tracks is built as an X (scissors)
    /// crossover, with the mirrored diagonal crossing it at a diamond in
    /// the middle (see ``networkPicksCrossover``), rather than one.
    public var networkBuildsScissors = false
    /// Whether a stretch that climbs or falls eases into and out of its
    /// grade with vertical curves at both ends.
    public var networkEasesGrade = false
    /// The place on an edge the platform and remove modes picked.
    public internal(set) var networkEdgePoint: NetworkEdgePoint?
    /// How many cars the next platform is long enough for.
    public var platformCars = GameSession.defaultPlatformCars
    /// The station the next platform serves; `nil` builds a new station
    /// named ``stationName`` beside it.
    public var platformStationID: StationID?

    /// Who lives where on real-world maps in Taiwan, which sets the
    /// ridership of a managed company's new stations there (see
    /// PopulationGrid.swift); `nil` gives them the city's. The app's
    /// bundled grid, set by the launcher; never saved.
    @ObservationIgnored public var population: PopulationGrid?

    /// What there is around places on real-world maps in Taiwan, which
    /// sets the kind of a managed company's new stations there (see
    /// PlaceGrid.swift); `nil` makes them all serve homes. The app's
    /// bundled grid, set by the launcher; never saved.
    @ObservationIgnored public var places: PlaceGrid?

    /// Taiwan's water (decision 105), read in with the land of a map whose
    /// land is read as it is needed; `nil` without the app's file.
    @ObservationIgnored public var water: WaterGrid?

    /// Taiwan's real railways (stations and lines) for real-world maps.
    /// Handed to each session by the launcher; never saved. Once they are
    /// there, a station name still as first suggested is suggested again
    /// from them, at the middle of a real-world map. Observed: they can
    /// arrive after the game starts (``GameLauncher/loadRealWorldData(reading:)``),
    /// and the map then draws them.
    public var railways: RealRailways? {
        didSet {
            let middle = RealWorldFrame(world: world).map { PlanPoint(x: Int64($0.middleX), y: Int64($0.middleY)) }
            suggestStationName(at: middle)
        }
    }

    /// The tutorial on screen (Stage C5), or `nil`. Moved through the
    /// tutorial methods (see TutorialSession.swift); never saved.
    public internal(set) var tutorial: Tutorial?

    /// The world as it was before each of the latest edits, oldest first,
    /// at most ``undoLimit`` of them (ARCHITECTURE decision 82): what
    /// ``undo()`` goes back to. Snapshots only, never played or shown; the
    /// world is ``world``. Pushed by ``performEdit(_:)``, emptied as soon as
    /// game time moves on, and never saved, so a new game, a loaded save
    /// and the start screen (each a new session) start without any.
    private(set) var undoHistory: [GameWorld] = []

    /// Whether a control is being dragged (``beginEditGesture()``), so its
    /// edits make one snapshot between them.
    @ObservationIgnored private var isEditGestureOpen = false
    /// Whether the open gesture has already kept its snapshot.
    @ObservationIgnored private var editGestureHasSnapshot = false

    /// Plays the sounds the session's changes call for (``SoundCue``): a
    /// train in service arriving at a station, track built, another tool.
    /// The app's player, set by the launcher; `nil` plays nothing. Never
    /// saved.
    @ObservationIgnored public var playSound: (@MainActor (SoundCue) -> Void)?

    /// The trains the player is looking at, whose arrivals ring at full
    /// volume (``SoundCue/arrival(watched:)``): the one the camera follows,
    /// the one last tapped on the map, and the selected one while the
    /// train tool is open.
    public var watchedTrainIDs: Set<TrainID> {
        var watched = Set([followedTrainID, tappedTrainID].compactMap { $0 })
        if tool == .train, let selectedTrainID {
            watched.insert(selectedTrainID)
        }
        return watched
    }

    /// Real time per simulation tick. At 600× (``GameSpeed/normal``) a tick
    /// is one game minute, so a game day lasts 144 real seconds; at 1× it is
    /// a tenth of a game second (Stage W2a).
    public nonisolated static let tickInterval: Duration = .milliseconds(100)
    /// The most real time one loop step turns into ticks (five ticks).
    public nonisolated static let maximumStepDuration: Duration = .milliseconds(500)

    @ObservationIgnored private var tickAccumulator = TickAccumulator(
        tickInterval: GameSession.tickInterval,
        maximumElapsed: GameSession.maximumStepDuration
    )
    @ObservationIgnored private var gameLoop: Task<Void, Never>?

    /// A managed company's stations without ridership get the city's
    /// (``StationDemand/cityDefault``), as stations built since do; saves
    /// from before ARCHITECTURE decision 46 may have such stations.
    public init(world: GameWorld, language: DisplayLanguage = .english) {
        self.world = Self.withCityRidership(world)
        self.language = language
        let suggested = Self.suggestedStationName(for: world, in: language)
        self.stationName = suggested
        self.automaticStationName = suggested
        self.selectedTrainID = world.trains.first?.id
        self.selectedLineID = world.lines.first?.id
    }

    // MARK: - Selection

    /// A tap on the map at `point` with the select or train tool (Stage
    /// F1), reaching `reach` world units: selects the station whose mark
    /// is within half the reach; or else the train drawn nearest within
    /// reach (`GameWorld.train(near:within:)`, see ``tapTrain(_:)``); or
    /// else the nearest station within reach
    /// (`GameWorld.station(near:within:)`), and the point itself. A station
    /// right under the finger wins over a train beside it, so a station's
    /// mark always selects it. Only distance decides what a tap picks; the
    /// point is kept exactly (Stage F3d). Taps outside the world's bounds
    /// are ignored. Never changes the world.
    public func tapMap(at point: PlanPoint, reach: Int64) {
        guard world.bounds.contains(point) else { return }
        var station = world.station(near: point, within: reach / 2)?.id
        if station == nil, let train = world.train(near: point, within: reach) {
            tapTrain(train)
            return
        }
        station = station ?? world.station(near: point, within: reach)?.id
        if isPickingLineStops, let station {
            appendToLineDraft(station)
        }
        guard point != selectedPoint || station != selectedStationID || tappedTrainID != nil else { return }
        selectedPoint = point
        selectedStationID = station
        tappedTrainID = nil
        message = nil
    }

    /// A tap that picked train `id`: it becomes the train the train tool
    /// acts on, and the select tool's inspector shows it. The select tool
    /// lets go of the station or point it had; the train tool keeps it, as
    /// the place it sends the train to.
    private func tapTrain(_ id: TrainID) {
        guard tappedTrainID != id || selectedTrainID != id || (tool == .select && selectedPoint != nil) else { return }
        selectedTrainID = id
        tappedTrainID = id
        if tool == .select {
            selectedPoint = nil
            selectedStationID = nil
        }
        message = nil
    }

    /// Selects station `id` and the point it stands at. Never changes the
    /// world; an ID the world does not have is ignored.
    public func selectStation(_ id: StationID) {
        guard let station = world.station(id: id), id != selectedStationID || station.point != selectedPoint || tappedTrainID != nil else { return }
        selectedPoint = station.point
        selectedStationID = id
        tappedTrainID = nil
        message = nil
    }

    /// Lets go of the selected station, point and tapped train: the
    /// inspector closes. Like the reference's `closePanelTrain`, closing
    /// the train also ends following it.
    public func clearSelection() {
        selectedPoint = nil
        selectedStationID = nil
        tappedTrainID = nil
        followedTrainID = nil
        message = nil
    }

    /// Selects train `id` (the train tool's picker, the fleet list). Never
    /// changes the world or what the camera follows, even when another
    /// train is picked (the reference keeps `trackedTrainId` apart from
    /// `selectedTrainId`); an ID the world does not have is ignored.
    public func selectTrain(_ id: TrainID) {
        guard world.train(id: id) != nil else { return }
        selectedTrainID = id
        tappedTrainID = id
        message = nil
    }

    // MARK: - Following a train

    /// The followed train (``followedTrainID``) while it exists and stands
    /// on the track; `nil` otherwise, so the follow bar and the camera never
    /// show a train that cannot be followed.
    public var followedTrain: Train? {
        guard let id = followedTrainID, let train = world.train(id: id), train.position != nil else { return nil }
        return train
    }

    /// Whether the camera follows a train now (``followedTrain``).
    public var isFollowingTrain: Bool {
        followedTrain != nil
    }

    /// Whether the camera follows train `id` now.
    public func isFollowing(_ id: TrainID) -> Bool {
        followedTrain?.id == id
    }

    /// Starts following train `id` (the reference's `toggleTrainFollow`
    /// turning on). Only a train on the track can be followed; for any
    /// other, or an unknown ID, nothing changes. Never changes the world or
    /// the selection.
    public func followTrain(_ id: TrainID) {
        guard let train = world.train(id: id), train.position != nil else { return }
        followedTrainID = id
    }

    /// Stops following (the follow bar's unfollow button).
    public func stopFollowingTrain() {
        followedTrainID = nil
    }

    /// The train panel's follow button (the reference's `toggleTrainFollow`):
    /// stops following when the selected train is the one followed,
    /// otherwise follows the selected train if it is on the track. Without
    /// a selected train nothing changes.
    public func toggleFollowTrain() {
        guard let id = selectedTrainID else { return }
        if isFollowing(id) {
            followedTrainID = nil
        } else {
            followTrain(id)
        }
    }

    /// Lets go of a followed train that no longer exists or has left the
    /// track (the reference ends `trackedTrainId` when its train is gone).
    func endFollowIfGone() {
        if followedTrainID != nil, followedTrain == nil {
            followedTrainID = nil
        }
    }

    /// Estimates the 800-metre walking catchment population of station `id`
    /// when the session runs on a real-world map with population data.
    public func stationCatchmentPopulation(of id: StationID) -> Int? {
        guard let station = world.station(id: id),
              let realWorld = RealWorldFrame(world: world),
              let population else { return nil }
        let coord = realWorld.coordinate(worldX: Double(station.location.x), worldY: Double(station.location.y))
        return population.people(within: StationDemand.catchmentRadius, ofLatitude: coord.latitude, longitude: coord.longitude)
    }

    // MARK: - Tools

    /// Switches tools. Changes nothing in the world but the clock:
    /// choosing a tool that builds (``ConstructionTool/pausesGame``) pauses
    /// a running game, and leaving those tools resumes it if the session
    /// paused it and the player has not touched the speed since
    /// (ARCHITECTURE decision 99).
    public func selectTool(_ newTool: ConstructionTool) {
        guard newTool != tool else { return }
        tool = newTool
        buildingSite = nil
        zoneDrag = nil
        message = nil
        if newTool.pausesGame {
            if !world.clock.isPaused {
                world.pause()
                isPausedForBuilding = true
                message = StatusMessage(
                    kind: .success,
                    text: language.text(
                        "Paused while you build, so every edit can be undone. Leave the tool or press play to go on.",
                        "建造時自動暫停，每一步都能復原。換回其他工具或按播放就會繼續。"
                    )
                )
            }
        } else if isPausedForBuilding {
            isPausedForBuilding = false
            if world.clock.isPaused { world.resume() }
        }
        playSound?(.transition)
    }

    /// Whether the session paused the game itself when a building tool was
    /// chosen (decision 99), so leaving the building tools resumes it.
    /// Any speed change by the player, pausing and resuming included,
    /// lets go of it: the speed is then the player's.
    public private(set) var isPausedForBuilding = false

    // MARK: - Speed

    /// Changes the game speed through the world's clock, the only record of it.
    public func setSpeed(_ speed: GameSpeed) {
        isPausedForBuilding = false
        world.setSpeed(speed)
    }

    /// Pauses a running game, or resumes a paused one at the speed it ran
    /// at (see `GameClock.runningSpeed`).
    public func togglePause() {
        isPausedForBuilding = false
        if world.clock.isPaused {
            world.resume()
        } else {
            world.pause()
        }
    }

    // MARK: - Traffic control

    /// Turns traffic control on or off through
    /// `GameWorld.setTrafficControl(_:)`. With it on, a train takes its whole
    /// route before it leaves and others wait for it; turning it on is
    /// refused while two trains need the same track.
    public func setTrafficControl(_ enabled: Bool) {
        perform { world throws(GameError) in
            try world.setTrafficControl(enabled)
            return enabled
                ? language.text(
                    "Traffic control is on. Trains take their whole route before they leave.",
                    "交通控制已開啟。列車出發前會先預約整條進路。"
                )
                : language.text("Traffic control is off. Trains no longer wait for each other.", "交通控制已關閉。列車不再互相等待。")
        }
    }

    // MARK: - Passenger routing

    /// Chooses how passengers released from now on find their way, through
    /// `GameWorld.setPassengerRoutingMode(_:)`: across the whole network,
    /// changing trains and walking between stations nearby (`network`), or
    /// only on a line that calls at both ends (`direct`). Those already
    /// waiting or riding keep their way.
    public func setPassengerRoutingMode(_ mode: PassengerRoutingMode) {
        guard mode != world.passengerRoutingMode else { return }
        perform { world throws(GameError) in
            world.setPassengerRoutingMode(mode)
            return mode == .network
                ? language.text(
                    "Passengers now plan journeys across the network and change trains.",
                    "乘客現在會規劃跨路線的旅程並轉乘。"
                )
                : language.text(
                    "Passengers now take only a line that serves both their stations.",
                    "乘客現在只搭兩站都停靠的路線。"
                )
        }
    }

    // MARK: - Economy

    /// Switches a managed company to free play through
    /// `GameWorld.setEconomyMode(_:)`: no fares or running costs, and
    /// ridership the player sets. Free play cannot become managed again,
    /// as the reference loads a free-play save only in free play
    /// (`MetroSaveModePolicy`): its ridership would be the player's, not
    /// the city's.
    ///
    /// A company in the red cannot switch: building still costs money in
    /// free play, which has no income, so a negative balance could never be
    /// built out of and the switch cannot be undone. Nor can a company with
    /// a loan: interest is paid only by a managed company (decision 67), so
    /// the loan would become money it never pays for.
    public func setEconomyMode(_ mode: EconomyMode) {
        guard mode != world.accounts.mode else { return }
        guard mode == .free else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Free play cannot become a managed company again. Start a new game to manage one.",
                "自由模式無法再改回經營模式。要經營公司，請開新遊戲。"
            ))
            return
        }
        guard world.economy.balance >= .zero else {
            message = StatusMessage(kind: .failure, text: language.text(
                "The company is in the red. Free play has no income and building still costs money, so you could not build anything. Bring the balance back above zero first, or start a new game.",
                "公司目前虧損。自由模式沒有收入，蓋東西仍要花錢，切過去就什麼都蓋不了。請先讓餘額回到零以上，或開新遊戲。"
            ))
            return
        }
        guard world.accounts.loan == .zero else {
            message = StatusMessage(kind: .failure, text: language.text(
                "The company still owes \(world.accounts.loan.moneyText). Free play pays no interest, so repay the loan before switching.",
                "公司仍有 \(world.accounts.loan.moneyText) 貸款。自由模式不付利息，請先還清貸款再切換。"
            ))
            return
        }
        performEdit { world in world.setEconomyMode(mode) }
        message = StatusMessage(kind: .success, text: language.text(
            "Free play: no fares or running costs, and you set each station's ridership.",
            "自由模式：不收票價，也沒有營運成本；各站的客源由你設定。"
        ))
    }

    /// Sets the network's fare rules through `GameWorld.setFareRules(_:)`.
    public func setFareRules(_ rules: FareRules) {
        perform { world throws(GameError) in
            try world.setFareRules(rules)
            return language.text("Fares: \(rules.displayText(in: language)).", "已更新票價規則：\(rules.displayText(in: language))。")
        }
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
            let closedBefore = world.accounts.years.last?.year
            let endedBefore = world.scenario?.outcome != nil
            defer {
                if let closed = world.accounts.years.last?.year, closed != closedBefore {
                    yearEndYear = closed
                }
                if !endedBefore, world.scenario?.outcome != nil {
                    scenarioJustEnded = true
                }
            }
            do throws(GameError) {
                if let playSound {
                    // A tick at a time, comparing only the arrival times
                    // (holding the whole world would copy what the ticks
                    // change): a step of several ticks can hold a train
                    // sent out, arriving and completing its service, and a
                    // completed service keeps no times to compare. The
                    // clock alone refuses a step, so trying it on a copy
                    // first keeps the step all or nothing.
                    var clock = world.clock
                    try clock.advance(ticks: ticks)
                    var arrived: [TrainID] = []
                    for _ in 0..<ticks {
                        let arrivals = SoundCue.arrivals(in: world)
                        try world.advance(ticks: 1)
                        arrived += SoundCue.trainsArrived(since: arrivals, in: world)
                    }
                    // Game time moved on: no edit before it can be undone.
                    undoHistory.removeAll()
                    editGestureHasSnapshot = false
                    endFollowIfGone()
                    if !arrived.isEmpty {
                        let watched = watchedTrainIDs
                        playSound(.arrival(watched: arrived.contains { watched.contains($0) }))
                    }
                } else {
                    try world.advance(ticks: ticks)
                    undoHistory.removeAll()
                    editGestureHasSnapshot = false
                    endFollowIfGone()
                }
            } catch {
                message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
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

    // MARK: - Trains

    /// The selected train as the world has it now, or `nil` if none is
    /// selected. Its position, rate and continuation are always GameCore's;
    /// the session never keeps a copy.
    public var selectedTrain: Train? {
        selectedTrainID.flatMap { world.train(id: $0) }
    }

    /// The selected train's rate as GameCore has it (0 without a selected
    /// train). Setting it calls ``setSelectedTrainRate(_:)``, so a control
    /// bound to it never holds a rate of its own. A slider bound to it
    /// brackets each drag with ``beginEditGesture()`` and
    /// ``endEditGesture()`` (its `onEditingChanged`), so one drag is one
    /// edit to undo.
    public var selectedTrainRate: Int64 {
        get { selectedTrain?.movement.rate ?? 0 }
        set { setSelectedTrainRate(newValue) }
    }

    /// Chooses the heading for the next placement. Never changes the world.
    public func setPlacementHeading(_ heading: CompassHeading) {
        placementHeading = heading
    }

    /// Buys a train through `GameWorld.purchaseTrain(named:)`, which charges
    /// its cost and allocates its ID, and selects it. It is not on the track
    /// until it is placed.
    public func purchaseTrain() {
        var purchased: TrainID?
        perform { world throws(GameError) in
            let train = try world.purchaseTrain(named: Self.suggestedTrainName(for: world, in: language))
            purchased = train.id
            return language.text("Bought \(train.name). Select a station to place it.", "已購買 \(train.name)。請選擇要放置它的車站。")
        }
        if let purchased {
            selectedTrainID = purchased
            tappedTrainID = purchased
        }
    }

    /// Puts the selected train on a platform of the selected station on
    /// the track network (Stage C1; see ``place(_:atPlatformOf:)``).
    public func placeSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station to place \(train.name) at.", "請選擇要放置 \(train.name) 的車站。"))
            return
        }
        guard !world.trackPlatforms(of: station.id).isEmpty else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(station.name) has no platform yet. Add one with the network tool.",
                "\(station.name) 還沒有月台。請用路網工具加上月台。"
            ))
            return
        }
        place(train, atPlatformOf: station)
    }

    /// Sets how many cars the selected train has through
    /// `GameWorld.setTrainCars(_:to:)`: only while it is off the track.
    public func setSelectedTrainCars(_ cars: Int) {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            let balance = world.economy.balance
            try world.setTrainCars(train.id, to: cars)
            let count = Train.carsText(cars, in: language)
            // Added cars are paid for (decision 46).
            let paid = balance - world.economy.balance
            guard paid > .zero else { return language.text("\(train.name) now has \(count).", "\(train.name) 現在有 \(count)。") }
            return language.text("\(train.name) now has \(count), for \(paid.moneyText).", "\(train.name) 現在有 \(count)，花費 \(paid.moneyText)。")
        }
    }

    /// Renames the selected station through `GameWorld.renameStation(_:to:)`.
    public func renameSelectedStation(to name: String) {
        guard let station = selectedStation else { return }
        perform { world throws(GameError) in
            try world.renameStation(station.id, to: name)
            return language.text("Renamed \(station.name) to \(name).", "已將 \(station.name) 更名為 \(name)。")
        }
    }

    /// Renames the selected line through `GameWorld.renameLine(_:to:)`.
    public func renameSelectedLine(to name: String) {
        guard let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.renameLine(line.id, to: name)
            return language.text("Renamed \(line.name) to \(name).", "已將 \(line.name) 更名為 \(name)。")
        }
    }

    /// Sets the selected line's colour through
    /// `GameWorld.setLineColor(_:to:)`; `nil` gives back the app's pick.
    public func setSelectedLineColor(_ color: LineColor?) {
        guard let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.setLineColor(line.id, to: color)
            return language.text("\(line.name) has a new colour.", "\(line.name) 換了顏色。")
        }
    }

    /// Borrows one ``CompanyAccounts/loanStep`` through
    /// `GameWorld.borrow(_:)` (decision 67).
    public func borrowLoanStep() {
        perform { world throws(GameError) in
            try world.borrow(CompanyAccounts.loanStep)
            return language.text("Borrowed \(CompanyAccounts.loanStep.moneyText).", "借入 \(CompanyAccounts.loanStep.moneyText)。")
        }
    }

    /// Repays one ``CompanyAccounts/loanStep`` through
    /// `GameWorld.repayLoan(_:)` (decision 67).
    public func repayLoanStep() {
        perform { world throws(GameError) in
            try world.repayLoan(CompanyAccounts.loanStep)
            return language.text("Repaid \(CompanyAccounts.loanStep.moneyText).", "償還 \(CompanyAccounts.loanStep.moneyText)。")
        }
    }

    /// Sets the type of the selected train's cars through
    /// `GameWorld.setTrainType(_:to:)` (`nil`: the standard car): only while
    /// it is off the track.
    public func setSelectedTrainType(_ type: TrainType?) {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.setTrainType(train.id, to: type)
            let text = Train.typeText(type, in: language)
            return language.text("\(train.name) now has \(text).", "\(train.name) 現在是 \(text)。")
        }
    }

    /// Sets the selected train's rate through
    /// `GameWorld.setTrainMovementRate(_:to:)`. Like a speed change, a new
    /// rate is shown by the control itself rather than announced; a rejected
    /// one is reported.
    public func setSelectedTrainRate(_ rate: Int64) {
        guard let train = requireSelectedTrain() else { return }
        do throws(GameError) {
            try performEdit { world throws(GameError) in try world.setTrainMovementRate(train.id, to: rate) }
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
    }

    /// An explicit operational hold, separate from the configured km/h speed.
    public func holdSelectedTrain() {
        setSelectedTrainRate(0)
    }

    public func resumeSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.useTrainPerformanceForMovement(train.id)
            return language.text("Resumed \(train.name).", "已恢復 \(train.name) 運行。")
        }
    }

    /// Sends the selected train to the selected station: to where it stops
    /// at one of the station's platforms on the track network that it
    /// fits, along `GameWorld.path(from:toStation:length:)`, committed
    /// unchanged with `GameWorld.setTrainContinuation(_:along:stoppingAt:)`
    /// (Stage S5). Both run against the same world within this one call,
    /// with nothing in between, so the path can never be stale. The session
    /// never finds or edits a path itself.
    ///
    /// Without a path (no platform as long as the train that it can reach
    /// without turning back) nothing changes, and the train keeps the path
    /// it had.
    public func sendSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select the station to send \(train.name) to.", "請選擇 \(train.name) 要前往的車站。"))
            return
        }
        guard let position = train.position else {
            message = StatusMessage(kind: .failure, text: GameError.trainNotPlaced(train.id).playerMessage(in: language))
            return
        }
        guard let path = world.path(from: position, toStation: station.id, length: train.length) else {
            message = StatusMessage(
                kind: .failure,
                text: language.text(
                    "No route for \(train.name) to \(station.name): it needs a platform on the track network as long as the train, that it can reach without turning back. Its path is unchanged.",
                    "\(train.name) 沒有路可以到 \(station.name)：路網上要有不短於列車、而且不折返就能到達的月台。路徑沒有改變。"
                )
            )
            return
        }
        perform { world throws(GameError) in
            var draft = world
            try draft.setTrainContinuation(train.id, along: path.traversals, stoppingAt: path.end)
            try draft.useTrainPerformanceForMovement(train.id)
            world = draft
            let sent = path.distance == 0
                ? language.text("\(train.name) stops at \(station.name).", "\(train.name) 停在 \(station.name)。")
                : language.text(
                    "Sent \(train.name) to \(station.name), \(path.distance) units along the track.",
                    "已派 \(train.name) 前往 \(station.name)，沿軌道 \(path.distance) 單位。"
                )
            return sent
        }
    }

    /// Turns the selected train around where it stands through
    /// `GameWorld.reverseTrain(_:)`, which also clears its continuation.
    public func reverseSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.reverseTrain(train.id)
            return language.text("Reversed \(train.name); its path was cleared.", "\(train.name) 已反向，路徑已清除。")
        }
    }

    /// Takes the selected train off the track through
    /// `GameWorld.unplaceTrain(_:)`, which also clears its rate and path.
    public func unplaceSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        // Follow ends only once the train is off the track (``perform``
        // checks): a refused command leaves it where it was, still followed.
        perform { world throws(GameError) in
            try world.unplaceTrain(train.id)
            return language.text("Took \(train.name) off the track.", "已將 \(train.name) 移出軌道。")
        }
    }

    /// The selected train, or `nil` after reporting that there is none.
    func requireSelectedTrain() -> Train? {
        guard let id = selectedTrainID else {
            message = StatusMessage(kind: .failure, text: language.text("Buy a train first.", "請先購買列車。"))
            return nil
        }
        guard let train = world.train(id: id) else {
            message = StatusMessage(kind: .failure, text: GameError.unknownTrain(id).playerMessage(in: language))
            return nil
        }
        return train
    }

    // MARK: - Lines

    /// The selected line as the world has it now, or `nil` if none is
    /// selected (or it was removed).
    public var selectedLine: ServiceLine? {
        selectedLineID.flatMap { world.line(id: $0) }
    }

    /// Chooses the line the line panel shows. Never changes the world; an
    /// ID the world does not have is ignored.
    public func selectLine(_ id: LineID) {
        guard id != selectedLineID, world.line(id: id) != nil else { return }
        selectedLineID = id
        message = nil
    }

    /// Adds the selected station to the end of the new line's stops. Never
    /// changes the world.
    public func addSelectedStationToLineDraft() {
        guard let station = selectedStation else {
            message = StatusMessage(
                kind: .failure,
                text: language.text("Select a station on the map to add it to the new line.", "請在地圖上選擇車站，加到新路線。")
            )
            return
        }
        appendToLineDraft(station.id)
    }

    /// Adds station `id` to the end of the new line's stops, unless it is
    /// already the last.
    private func appendToLineDraft(_ id: StationID) {
        guard let station = world.station(id: id) else { return }
        guard lineDraft.last != station.id else {
            message = StatusMessage(
                kind: .failure,
                text: language.text(
                    "\(station.name) is already the last stop. A line cannot call at the same station twice in a row.",
                    "\(station.name) 已經是最後一站。路線不能連續兩次停靠同一站。"
                )
            )
            return
        }
        lineDraft.append(station.id)
        refreshLineDraftRoute()
        message = nil
    }

    /// Drops the last stop picked for the new line.
    public func removeLastLineDraftStop() {
        guard !lineDraft.isEmpty else { return }
        lineDraft.removeLast()
        refreshLineDraftRoute()
    }

    public func clearLineDraft() {
        lineDraft = []
        lineDraftStopping = .everyStation
        lineDraftSkipped = []
        isPickingLineStops = false
        refreshLineDraftRoute()
    }

    /// Starts adding the stations tapped on the map (``tapMap(at:reach:)``)
    /// to the new line (decision 100). The app sends map taps there while
    /// the lines panel is open, whichever tool is chosen.
    public func startPickingLineStops() {
        isPickingLineStops = true
        message = StatusMessage(
            kind: .success,
            text: language.text(
                "Tap the line's first station on the map, then its last. Tap a station between to choose the way.",
                "在地圖上點路線的起點，再點終點。有分岔時，點中間的車站指定經過哪裡。"
            )
        )
    }

    /// Starts a new line at the selected station (decision 112): a new
    /// draft with it as the first stop, and the next station tapped on the
    /// map as the next. A draft already begun is dropped. Never changes
    /// the world.
    public func startLineFromSelectedStation() {
        guard let station = selectedStation else {
            addSelectedStationToLineDraft()
            return
        }
        clearLineDraft()
        appendToLineDraft(station.id)
        isPickingLineStops = true
        message = StatusMessage(
            kind: .success,
            text: language.text(
                "The line starts at \(station.name). Tap its last station on the map.",
                "路線從\(station.name)出發。在地圖上點它的終點站。"
            )
        )
    }

    /// Stops adding tapped stations to the new line; the draft stays.
    public func stopPickingLineStops() {
        isPickingLineStops = false
    }

    /// Leaves station `id` out of the new line, or puts it back
    /// (``LineDraftStopping/custom``). The two ends are always called at.
    public func toggleLineDraftStop(_ id: StationID) {
        guard let route = lineDraftRoute, id != route.first, id != route.last else { return }
        lineDraftStopping = .custom
        if lineDraftSkipped.contains(id) {
            lineDraftSkipped.remove(id)
        } else {
            lineDraftSkipped.insert(id)
        }
    }

    /// The stops the new line will call at, in order: the stations along
    /// the track as ``lineDraftStopping`` chooses them, or the picked
    /// stations when no track joins them (``lineDraftRoute`` is `nil`).
    public var lineDraftStops: [StationID] {
        guard let route = lineDraftRoute else { return lineDraft }
        switch lineDraftStopping {
        case .everyStation:
            return route
        case .pickedStations:
            return lineDraft
        case .custom:
            return route.enumerated().filter { index, station in
                index == 0 || index == route.count - 1 || !lineDraftSkipped.contains(station)
            }.map(\.element)
        }
    }

    /// Finds ``lineDraftRoute`` again; a station skipped that is no
    /// longer on it is forgotten.
    func refreshLineDraftRoute() {
        let route = world.stationsAlongTrack(through: lineDraft)
        if route != lineDraftRoute { lineDraftRoute = route }
        let along = Set(route ?? [])
        if !lineDraftSkipped.isSubset(of: along) { lineDraftSkipped.formIntersection(along) }
    }

    /// Creates a line calling at ``lineDraftStops``, in order, through
    /// `GameWorld.createLine(named:stops:)`, and selects it. The draft is
    /// kept when GameCore refuses the stops.
    ///
    /// Where the stops are on a real line (``realLine(calling:)``), the new
    /// line starts with that line's peak and off-peak headways as its
    /// targets (``realTargetHeadways(of:inSystem:)``), through
    /// `GameWorld.setLineTargetHeadways(_:to:pattern:)` in the same step.
    public func createLineFromDraft() {
        var created: LineID?
        refreshLineDraftRoute()
        let stops = lineDraftStops
        let real = realLine(calling: stops).flatMap { match in
            realTargetHeadways(of: match.line, inSystem: match.system).map { (name: match.line.name, targets: $0) }
        }
        perform { world throws(GameError) in
            var draft = world
            let line = try draft.createLine(named: Self.suggestedLineName(for: draft, in: language), stops: stops)
            var detail = ""
            if let real {
                try draft.setLineTargetHeadways(line.id, to: real.targets, pattern: nil)
                let levels = [(ServiceLevel.peak, real.targets.peak), (.offPeak, real.targets.offPeak)].compactMap { level, minutes in
                    minutes.map { "\(level.title(in: language)) \(headwayText(minutes: $0, in: language).lowercased())" }
                }.joined(separator: language.text(", ", "、"))
                detail = language.text(" Target headways from \(real.name): \(levels).", "目標班距依 \(real.name)：\(levels)。")
            }
            world = draft
            created = line.id
            return language.text(
                "Created \(line.name) with \(stops.count) stops. Set how many trains it runs.",
                "已建立 \(line.name)，共 \(stops.count) 站。請設定上線列車數。"
            ) + detail
        }
        if let created {
            selectedLineID = created
            clearLineDraft()
        }
    }

    /// Removes the selected line through `GameWorld.removeLine(_:)`; its
    /// trains finish the trip they are on.
    public func removeSelectedLine() {
        guard let line = requireSelectedLine() else { return }
        let followsLineTrain = followedTrainID.map { world.assignedLine(of: $0) == line.id } ?? false
        let removed = perform { world throws(GameError) in
            try world.removeLine(line.id)
            return language.text("Removed \(line.name). Its trains finish the trip they are on.", "已刪除 \(line.name)。它的列車會跑完目前這一趟。")
        }
        // The reference removes a line's trains with it, which ends
        // following one of them (`trackedTrainId` of a gone train).
        if removed && followsLineTrain {
            followedTrainID = nil
        }
        selectedLineID = world.lines.first?.id
    }

    /// One directed leg of the selected service: replace or clear its
    /// preference through the world's atomic command.
    public func setSelectedLineRoute(from: Int, to: Int, preference: LineRoutePreference?, pattern: Int? = nil) {
        guard let line = requireSelectedLine() else { return }
        var routes = pattern.flatMap { line.patterns.indices.contains($0) ? line.patterns[$0].routePreferences : nil } ?? line.routePreferences
        routes.removeAll { $0.from == from && $0.to == to }
        if let preference { routes.append(preference) }
        let chosen = routes
        perform { world throws(GameError) in
            try world.setLineRoutePreferences(line.id, to: chosen, pattern: pattern)
            return language.text("Updated the service's physical path.", "已更新停站模式的股道與月台。")
        }
    }

    /// Runs the selected line all day, or from 06:00 to midnight.
    public func setSelectedLineAllDay(_ allDay: Bool) {
        guard let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.setLineServiceWindow(line.id, to: allDay ? .allDay : .standard)
            return allDay
                ? language.text("\(line.name) runs all day.", "\(line.name) 全天營運。")
                : language.text("\(line.name) runs from 06:00 to midnight.", "\(line.name) 從 06:00 營運到午夜。")
        }
    }

    /// Makes the selected line a ring, its trains going on from its last
    /// stop back to the first, half of them each way round (decision 49),
    /// or a line that turns round at its ends again. A ring runs its trains
    /// in pairs: GameCore makes its counts even, down.
    public func setSelectedLineRing(_ isRing: Bool) {
        guard let line = requireSelectedLine(), line.isRing != isRing else { return }
        perform { world throws(GameError) in
            try world.setLineRing(line.id, to: isRing)
            return isRing
                ? language.text(
                    "\(line.name) is a ring: its trains go on from the last stop to the first, half of them each way round.",
                    "\(line.name) 改為環線：列車從最後一站接著開回第一站，一半依站序、一半反方向。"
                )
                : language.text("\(line.name) turns round at its ends again.", "\(line.name) 改回在兩端折返。")
        }
    }

    /// Sets how many trains a service of the selected line runs at `level`
    /// (its own for `pattern` `nil`), keeping the other levels. How many it
    /// can run is derived; see ``GameWorld/lineServiceSummaries(_:)``. A
    /// ring's count is made even, down (decision 49).
    public func setSelectedLineTrains(_ count: Int, at level: ServiceLevel, pattern: Int? = nil) {
        guard let line = requireSelectedLine() else { return }
        let current = pattern.flatMap { line.patterns.indices.contains($0) ? line.patterns[$0].trainsInService : nil } ?? line.trainsInService
        var counts = current
        switch level {
        case .peak: counts.peak = count
        case .offPeak: counts.offPeak = count
        case .low: counts.low = count
        }
        let changed = counts
        perform { world throws(GameError) in
            try world.setLineTrainsInService(line.id, to: changed, pattern: pattern)
            return language.text(
                "\(line.name): \(count) \(count == 1 ? "train" : "trains") at \(level.title(in: language).lowercased()).",
                "\(line.name)：\(level.title(in: language))上線 \(count) 列。"
            )
        }
    }

    /// Sets or clears a service's target headway at `level`, keeping the
    /// other levels.
    public func setSelectedLineTargetHeadway(_ minutes: Int64?, at level: ServiceLevel, pattern: Int? = nil) {
        guard let line = requireSelectedLine() else { return }
        let current = pattern.flatMap { line.patterns.indices.contains($0) ? line.patterns[$0].targetHeadways : nil } ?? line.targetHeadways
        var targets = current
        switch level {
        case .peak: targets.peak = minutes
        case .offPeak: targets.offPeak = minutes
        case .low: targets.low = minutes
        }
        let changed = targets
        perform { world throws(GameError) in
            try world.setLineTargetHeadways(line.id, to: changed, pattern: pattern)
            let levelName = level.title(in: language)
            switch language {
            case .english:
                let what = minutes.map { headwayText(minutes: $0, in: language).lowercased() } ?? "the train count"
                return "\(line.name) at \(levelName.lowercased()): \(what)."
            case .traditionalChinese:
                let what = minutes.map { headwayText(minutes: $0, in: language) } ?? "依上線列車數"
                return "\(line.name)：\(levelName)\(what)。"
            }
        }
    }

    /// Adds a pattern to the selected line from stop `first` to stop
    /// `last` (indices into its stops): calling at every stop between, a
    /// short working, or at the two ends only, an express.
    public func addPatternToSelectedLine(from first: Int, to last: Int, express: Bool) {
        guard let line = requireSelectedLine() else { return }
        let calls = express ? [first, last] : (first <= last ? Array(first...last) : [first, last])
        perform { world throws(GameError) in
            let index = try world.addLinePattern(line.id, calling: calls)
            let title = world.serviceTitle(of: world.line(id: line.id)!, calls: calls, in: language)
            return language.text(
                "Added \(title) to \(line.name) as pattern \(index + 1).",
                "已在 \(line.name) 加入\(title)（停站模式 \(index + 1)）。"
            )
        }
    }

    /// Removes the selected line's pattern at `index`; its trains finish
    /// the trip they are on.
    public func removePatternFromSelectedLine(_ index: Int) {
        guard let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.removeLinePattern(line.id, at: index)
            return language.text("Removed pattern \(index + 1) from \(line.name).", "已從 \(line.name) 刪除停站模式 \(index + 1)。")
        }
    }

    /// Assigns the selected train to a service of the selected line (its
    /// own for `pattern` `nil`), which sends it out from the service's first
    /// stop once it waits there.
    ///
    /// A new line runs no trains at any level and has no target headways,
    /// so a train assigned to it would never leave: when the service runs
    /// none, it is set to run its assigned trains at every level (a ring's
    /// count made even, up, as each way needs one).
    public func assignSelectedTrainToSelectedLine(pattern: Int? = nil) {
        guard let train = requireSelectedTrain(), let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            var draft = world
            try draft.assignTrain(train.id, to: line.id, pattern: pattern)
            if train.position != nil { try draft.useTrainPerformanceForMovement(train.id) }
            var started = 0
            if let assigned = draft.line(id: line.id) {
                let service = pattern.map { $0 + 1 } ?? 0
                let counts = service == 0 ? assigned.trainsInService : assigned.patterns[service - 1].trainsInService
                let targets = service == 0 ? assigned.targetHeadways : assigned.patterns[service - 1].targetHeadways
                if counts == .none, targets == TargetHeadways() {
                    let trains = (service == 0 ? assigned.trains : assigned.patterns[service - 1].trains).count
                    started = assigned.isRing ? max(2, trains + trains % 2) : max(1, trains)
                    try draft.setLineTrainsInService(line.id, to: TrainsInService(peak: started, offPeak: started, low: started), pattern: pattern)
                }
            }
            world = draft
            let service = world.assignedServiceName(of: train.id, in: language) ?? line.name
            let text = language.text(
                "\(train.name) now runs for \(service). It leaves once it waits at the first stop.",
                "\(train.name) 現在為 \(service) 服務。它在第一站等候後就會出發。"
            )
            // A line outside its window sends nobody out until it opens.
            let opens: String
            if let assigned = world.line(id: line.id), world.serviceLevel(of: line.id, at: world.clock.now) == nil,
               case .hours(let open, _) = assigned.window {
                let time = clockText(minuteOfDay: open % 1_440)
                opens = language.text(" \(line.name) opens at \(time).", "\(line.name) \(time) 開始營運。")
            } else {
                opens = ""
            }
            guard started > 0 else { return text + opens }
            return text + opens + language.text(
                " \(service) ran no trains, so it now runs \(started) at every level.",
                "\(service) 原本沒有上線列車，現在各時段上線 \(started) 列。"
            )
        }
    }

    /// Takes the selected train off its line; a trip under way is finished.
    public func unassignSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.unassignTrain(train.id)
            return language.text("Took \(train.name) off its line. A trip under way is finished.", "已將 \(train.name) 移出路線。進行中的這一趟會跑完。")
        }
    }

    /// Starts the selected train's own timetable through
    /// `GameWorld.startTrainService(_:)`.
    public func startSelectedTrainService() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            var draft = world
            try draft.startTrainService(train.id)
            try draft.useTrainPerformanceForMovement(train.id)
            world = draft
            return language.text("\(train.name) is running its timetable.", "\(train.name) 開始依時刻表運行。")
        }
    }

    /// Stops the selected train's service through
    /// `GameWorld.stopTrainService(_:)`; it keeps its timetable.
    public func stopSelectedTrainService() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.stopTrainService(train.id)
            return language.text("Stopped \(train.name)'s service. It stays where it is.", "已停止 \(train.name) 的服務。它會停在原地。")
        }
    }

    /// The selected line, or `nil` after reporting that there is none.
    func requireSelectedLine() -> ServiceLine? {
        guard let line = selectedLine else {
            message = StatusMessage(kind: .failure, text: language.text("Create or choose a line first.", "請先建立或選擇一條路線。"))
            return nil
        }
        return line
    }

    // MARK: - Actions

    /// Applies the current tool to the selection through the matching
    /// `GameWorld` command, and reports the outcome in ``message``.
    ///
    /// The session does not pre-check game rules: GameCore decides whether an
    /// action is allowed, and a rejected action leaves the world unchanged.
    /// Does nothing without a selection, in ``ConstructionTool/select``
    /// mode, or with the network tool, which acts on what its taps picked.
    public func applyTool() {
        guard selectedPoint != nil else { return }
        switch tool {
        case .select, .network, .building:
            return
        case .train:
            // The selected station is where an unplaced train goes, or
            // where a placed one is sent.
            if selectedTrain?.position == nil {
                placeSelectedTrain()
            } else {
                sendSelectedTrain()
            }
        }
    }

    public func dismissMessage() {
        message = nil
    }

    /// Clears the message posted as `serial` (``messageSerial``) if it is
    /// still the message (the banner's own timer,
    /// ``StatusMessage/autoDismissDelay``): a newer message stays, even
    /// one with the same text.
    public func dismissMessage(posted serial: UInt64) {
        if messageSerial == serial { message = nil }
    }

    /// Runs one command against the world through ``performEdit(_:)`` and
    /// records its outcome. Returns whether the command succeeded.
    @discardableResult
    func perform(_ command: (inout GameWorld) throws(GameError) -> String) -> Bool {
        do throws(GameError) {
            message = StatusMessage(kind: .success, text: try performEdit(command))
            endFollowIfGone()
            return true
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
            return false
        }
    }

    // MARK: - Editing and undo

    /// How many edits ``undo()`` can take back: MapBuilder's `B.I6` (25),
    /// the snapshots its `handleUndo` goes back through.
    public static let undoLimit = 25

    /// How many of those edits may have read land in (decision 88): each
    /// keeps a copy of a map's land and buildings, some 110 bytes a cell,
    /// 45 MB with a hundred stations on the whole of Taiwan and 220 MB with
    /// six hundred, so older edits are forgotten past three.
    public static let landReadingUndoLimit = 3

    /// The one way an edit changes the world (ARCHITECTURE decision 82):
    /// runs `command` on a copy of ``world`` and, only if it succeeds,
    /// keeps the world as it was for ``undo()`` and puts the copy in its
    /// place. A command that throws leaves the world and the undo history
    /// as they were, even after it changed part of its copy; one that
    /// succeeds without changing anything leaves no snapshot, so Undo never
    /// takes back nothing. Between ``beginEditGesture()`` and
    /// ``endEditGesture()`` only the first edit that changes the world keeps
    /// a snapshot: the world as it was when the drag began. The oldest
    /// snapshot goes once there are ``undoLimit``.
    ///
    /// Everything the player builds, removes or sets goes through it;
    /// pausing, the speed, the selection, the camera and the map layers do
    /// not, and are not edits. Returns what `command` returns, and throws
    /// what it throws: a `GameError` from a GameWorld command, or nothing
    /// for a command that cannot fail. It shows no message
    /// (``perform(_:)`` does).
    /// Reads in the land round every station whose land is not read yet,
    /// on a map whose land is read in as it is needed (decision 88, see
    /// ``readLand(roundStationsOf:population:places:water:)``). Every edit does
    /// it (``performEdit(_:)``), so a station's land comes with it and
    /// Undo takes both back; a game that starts does it for the stations
    /// built while the app had no population. Not an edit: nothing to undo.
    public func readLandRoundStations() {
        Self.readLand(roundStationsOf: &world, population: population, places: places, water: water)
    }

    /// Reads in the land within `reach` of `point` (decision 95: under a
    /// building's site), as ``readLandRoundStations()`` does round
    /// stations. Not an edit.
    func readLand(within reach: Int64, of point: PlanPoint) {
        Self.readLand(within: reach, of: [point], in: &world, population: population, places: places, water: water)
    }

    @discardableResult
    public func performEdit<Result, Failure: Error>(
        _ command: (inout GameWorld) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        var edited = world
        let result = try command(&edited)
        // Decision 88: a new station's land comes with it.
        Self.readLand(roundStationsOf: &edited, population: population, places: places, water: water)
        guard edited != world else { return result }
        // Decision 100: the new line's route follows the track.
        let trackChanged = lineDraft.count >= 2 && edited.network != world.network
        defer { if trackChanged { refreshLineDraftRoute() } }
        if !editGestureHasSnapshot {
            if undoHistory.count >= Self.undoLimit {
                undoHistory.removeFirst(undoHistory.count - Self.undoLimit + 1)
            }
            undoHistory.append(world)
            editGestureHasSnapshot = isEditGestureOpen
            forgetEditsPastTheLandReadingLimit(before: edited)
        }
        world = edited
        return result
    }

    /// Drops the oldest snapshots until at most ``landReadingUndoLimit``
    /// of the edits up to `latest` read land in (their land's blocks are
    /// not the next world's).
    private func forgetEditsPastTheLandReadingLimit(before latest: GameWorld) {
        guard latest.landBlocks != nil else { return }
        var reads = 0
        var next = latest
        for index in undoHistory.indices.reversed() {
            if undoHistory[index].landBlocks != next.landBlocks {
                reads += 1
                if reads > Self.landReadingUndoLimit {
                    undoHistory.removeFirst(index + 1)
                    return
                }
            }
            next = undoHistory[index]
        }
    }

    /// A drag of a control that edits as it moves (a slider's
    /// `onEditingChanged(true)`) begins: its edits until
    /// ``endEditGesture()`` are one edit to ``undo()``, which goes back to
    /// the world as it was when the drag began. A tick of game time during
    /// the drag empties the history as ever, and the drag's next change
    /// keeps a new snapshot.
    public func beginEditGesture() {
        isEditGestureOpen = true
        editGestureHasSnapshot = false
    }

    /// The drag ends (`onEditingChanged(false)`): each edit after it is
    /// one edit to undo again.
    public func endEditGesture() {
        isEditGestureOpen = false
        editGestureHasSnapshot = false
    }

    /// How many edits ``undo()`` could take back, one at a time, up to
    /// ``undoLimit``.
    public var undoCount: Int {
        undoHistory.count
    }

    /// Whether ``undo()`` has an edit to take back now: there is one since
    /// game time last moved, and no tutorial is on screen.
    public var canUndo: Bool {
        !undoHistory.isEmpty && tutorial == nil
    }

    /// Takes back the latest edit (MapBuilder's `handleUndo`): the whole
    /// world goes back to the snapshot ``performEdit(_:)`` kept before it,
    /// money included, so what was built is refunded. Only the clock's
    /// speed stays as the player has it now, since pausing and the speed
    /// are not edits; game time is the snapshot's, which it still is (any
    /// tick empties the history). The selection and the drafts let go of
    /// stations, trains, lines and track the world no longer has.
    ///
    /// Refused, with a message, when there is nothing to take back, and
    /// while the tutorial is on screen: its steps compare the world with
    /// IDs it saw, and an undone station's ID is given to the next one, so
    /// Next could wait for a second station.
    public func undo() {
        guard tutorial == nil else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Undo is off during the tutorial.",
                "教學進行中無法復原。"
            ))
            return
        }
        guard var restored = undoHistory.popLast() else {
            message = StatusMessage(kind: .failure, text: language.text("Nothing to undo.", "沒有可復原的編輯。"))
            return
        }
        // A drag still under way keeps a new snapshot at its next change.
        editGestureHasSnapshot = false
        restored.setSpeed(world.clock.runningSpeed)
        if world.clock.isPaused { restored.pause() }
        world = restored
        dropSelectionOfMissing()
        message = StatusMessage(kind: .success, text: language.text("Undid the last edit.", "已復原上一步編輯。"))
    }

    /// Lets go of what the selection and the drafts name that ``world``
    /// does not have (after ``undo()`` or a demolished station); keeps the
    /// rest.
    func dropSelectionOfMissing() {
        if let id = selectedStationID, world.station(id: id) == nil { selectedStationID = nil }
        if let id = platformStationID, world.station(id: id) == nil { platformStationID = nil }
        lineDraft.removeAll { world.station(id: $0) == nil }
        refreshLineDraftRoute()
        if let id = selectedTrainID, world.train(id: id) == nil { selectedTrainID = nil }
        if let id = tappedTrainID, world.train(id: id) == nil { tappedTrainID = nil }
        endFollowIfGone()
        if let id = selectedLineID, world.line(id: id) == nil { selectedLineID = nil }
        func exists(_ anchor: NetworkAnchor?) -> Bool {
            switch anchor {
            case nil, .point: true
            case .node(let id): world.network.node(id) != nil
            case .track(let point): world.network.edge(point.edge) != nil
            }
        }
        if !exists(networkStart) { networkStart = nil }
        if !exists(networkEnd) { networkEnd = nil }
        if let point = networkEdgePoint, world.network.edge(point.edge) == nil { networkEdgePoint = nil }
    }

    /// "Station N" (or "車站 N") with the lowest N from the next station
    /// number upward that no existing station uses. On a real-world map,
    /// suggests the nearest real railway station's name if within range
    /// and not yet taken.
    ///
    /// A real station is taken when a station of the world already is it,
    /// whatever language or system's spelling it was named in: 台北, 臺北,
    /// 台北車站, "Taipei" and "Taipei Main Station" near Taipei Main
    /// Station are one place (``RealRailways/stationKey(_:)``), so none of
    /// them is offered again once one is used.
    nonisolated public static func suggestedStationName(
        for world: GameWorld,
        at location: PlanPoint? = nil,
        in language: DisplayLanguage,
        railways: RealRailways? = nil,
        maximumDistanceMetres: Double = 5_000
    ) -> String {
        let taken = Set(world.stations.map(\.name))
        if let location,
           let railways,
           let frame = RealWorldFrame(world: world) {
            func coordinate(_ point: PlanPoint) -> RealRailways.Coordinate {
                let coord = frame.coordinate(worldX: Double(point.x), worldY: Double(point.y))
                return RealRailways.Coordinate(latitude: coord.latitude, longitude: coord.longitude)
            }
            // Every name key of the real stations the world's stations are.
            var takenKeys = Set(taken.map(RealRailways.stationKey))
            for station in world.stations {
                for real in railways.stations(named: station.name, near: coordinate(station.location)) {
                    takenKeys.insert(RealRailways.stationKey(real.chinese))
                    if let english = real.english { takenKeys.insert(RealRailways.stationKey(english)) }
                }
            }
            let candidates = railways.nearbyStations(to: coordinate(location), maximumDistanceMetres: maximumDistanceMetres)
            for candidate in candidates {
                let name = candidate.station.name(in: language)
                let keys = [candidate.station.chinese, candidate.station.english, name].compactMap { $0 }.map(RealRailways.stationKey)
                if !taken.contains(name), keys.allSatisfy({ !takenKeys.contains($0) }) {
                    return name
                }
            }
        }
        return suggestedName(language.text("Station", "車站"), from: world.stations.count + 1, taken: taken)
    }

    /// Suggests a new ``stationName`` for a station at `location` (see
    /// ``suggestedStationName(for:at:in:railways:maximumDistanceMetres:)``),
    /// replacing the current one only while it is still the last suggestion.
    func suggestStationName(at location: PlanPoint?) {
        let suggestion = Self.suggestedStationName(for: world, at: location, in: language, railways: railways)
        if stationName == automaticStationName {
            stationName = suggestion
        }
        automaticStationName = suggestion
    }

    /// "Line N" (or "路線 N") with the lowest N from the next line number
    /// upward that no existing line uses.
    private static func suggestedLineName(for world: GameWorld, in language: DisplayLanguage) -> String {
        suggestedName(language.text("Line", "路線"), from: world.lines.count + 1, taken: Set(world.lines.map(\.name)))
    }

    /// "Train N" (or "列車 N") with the lowest N from the next train number
    /// upward that no existing train uses.
    static func suggestedTrainName(for world: GameWorld, in language: DisplayLanguage) -> String {
        suggestedName(language.text("Train", "列車"), from: world.trains.count + 1, taken: Set(world.trains.map(\.name)))
    }

    /// "`prefix` N" with the lowest N from `first` upward that is not in
    /// `taken`.
    nonisolated private static func suggestedName(_ prefix: String, from first: Int, taken: Set<String>) -> String {
        var number = first
        while taken.contains("\(prefix) \(number)") {
            number += 1
        }
        return "\(prefix) \(number)"
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

    /// How long the banner shows the message before clearing it: a success
    /// goes after 4 s, so it never stays over the row just edited at the
    /// bottom of a panel; a problem, which explains itself, stays longer
    /// the longer it is: 4 s and a tenth of a second a character, from 6 s
    /// up to 10 s (ARCHITECTURE decision 106, after the reference's
    /// `notify()`, `min(9, 3.2 + length × 0.09)` s). The banner keeps a
    /// problem until dismissed while VoiceOver runs.
    public var autoDismissDelay: Duration {
        switch kind {
        case .success: .seconds(4)
        case .failure: .milliseconds(min(10_000, max(6_000, 4_000 + 100 * text.count)))
        }
    }
}
