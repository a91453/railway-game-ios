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

    /// Name for the next station. Pre-filled with a suggestion the player can
    /// edit; GameCore decides whether it is valid.
    public var stationName: String

    /// The train the train tool acts on: an ID only, never a copy of the
    /// train. Read the train itself through ``selectedTrain``.
    public private(set) var selectedTrainID: TrainID?

    /// The train the last tap on the map picked (see ``tapMap(at:reach:)``),
    /// which the select tool's inspector shows; `nil` once a tap or a
    /// command selects a station or a point instead.
    public private(set) var tappedTrainID: TrainID?

    /// The way the selected train faces when it is placed: along its
    /// platform, the way nearer this compass point. Only used by
    /// ``placeSelectedTrain()``; it never turns a train that is on the track.
    public private(set) var placementHeading: CompassHeading = .east

    /// The outcome of the last action, for the status line. Cleared when the
    /// player selects another point or tool.
    public internal(set) var message: StatusMessage?

    /// The line the line panel shows: an ID only, never a copy of the line.
    /// Read the line itself through ``selectedLine``.
    public private(set) var selectedLineID: LineID?

    /// The stations picked, in order, for the next line. Only a draft:
    /// GameCore checks them when ``createLineFromDraft()`` creates the line.
    public private(set) var lineDraft: [StationID] = []

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
    /// What carries the next stretch of track.
    public var networkStructure: TrackStructure = .surface
    /// How high a new node goes, in world units (64 to a metre).
    public var networkHeight: Int64 = 0
    /// Whether the next stretch continues the track at its ends smoothly
    /// (the default), or runs straight.
    public var networkFollowsTrack = true
    /// Whether a stretch that climbs or falls eases into and out of its
    /// grade with vertical curves at both ends.
    public var networkEasesGrade = false
    /// The place on an edge the platform and remove modes picked.
    public internal(set) var networkEdgePoint: NetworkEdgePoint?
    /// How many cars the next platform is long enough for.
    public var platformCars = 4
    /// The station the next platform serves; `nil` builds a new station
    /// named ``stationName`` beside it.
    public var platformStationID: StationID?

    /// Who lives where on real-world maps in Taiwan, which sets the
    /// ridership of a managed company's new stations there (see
    /// PopulationGrid.swift); `nil` gives them the city's. The app's
    /// bundled grid, set by the launcher; never saved.
    @ObservationIgnored public var population: PopulationGrid?

    /// The tutorial on screen (Stage C5), or `nil`. Moved through the
    /// tutorial methods (see TutorialSession.swift); never saved.
    public internal(set) var tutorial: Tutorial?

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
        self.stationName = Self.suggestedStationName(for: world, in: language)
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

    public func clearSelection() {
        selectedPoint = nil
        selectedStationID = nil
        tappedTrainID = nil
        message = nil
    }

    // MARK: - Tools

    /// Switches tools. Never changes the world.
    public func selectTool(_ newTool: ConstructionTool) {
        guard newTool != tool else { return }
        tool = newTool
        message = nil
    }

    // MARK: - Speed

    /// Changes the game speed through the world's clock, the only record of it.
    public func setSpeed(_ speed: GameSpeed) {
        world.setSpeed(speed)
    }

    /// Pauses a running game, or resumes a paused one at the speed it ran
    /// at (see `GameClock.runningSpeed`).
    public func togglePause() {
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
    /// built out of and the switch cannot be undone.
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
        world.setEconomyMode(mode)
        message = StatusMessage(kind: .success, text: language.text(
            "Free play: no fares or running costs, and you set each station's ridership.",
            "自由模式：不收票價，也沒有營運成本；各站的客流由你設定。"
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
            do throws(GameError) {
                try world.advance(ticks: ticks)
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
    /// bound to it never holds a rate of its own.
    public var selectedTrainRate: Int64 {
        get { selectedTrain?.movement.rate ?? 0 }
        set { setSelectedTrainRate(newValue) }
    }

    /// Chooses the train the train tool acts on. Never changes the world;
    /// an ID the world does not have is ignored.
    public func selectTrain(_ id: TrainID) {
        guard id != selectedTrainID, world.train(id: id) != nil else { return }
        selectedTrainID = id
        message = nil
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

    /// Sets the selected train's rate through
    /// `GameWorld.setTrainMovementRate(_:to:)`. Like a speed change, a new
    /// rate is shown by the control itself rather than announced; a rejected
    /// one is reported.
    public func setSelectedTrainRate(_ rate: Int64) {
        guard let train = requireSelectedTrain() else { return }
        do throws(GameError) {
            try world.setTrainMovementRate(train.id, to: rate)
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
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
            try world.setTrainContinuation(train.id, along: path.traversals, stoppingAt: path.end)
            let sent = path.distance == 0
                ? language.text("\(train.name) stops at \(station.name).", "\(train.name) 停在 \(station.name)。")
                : language.text(
                    "Sent \(train.name) to \(station.name), \(path.distance) units along the track.",
                    "已派 \(train.name) 前往 \(station.name)，沿軌道 \(path.distance) 單位。"
                )
            return train.movement.rate == 0 ? sent + language.text(" Set a rate to start.", "設定速率後出發。") : sent
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
        message = nil
    }

    /// Drops the last stop picked for the new line.
    public func removeLastLineDraftStop() {
        guard !lineDraft.isEmpty else { return }
        lineDraft.removeLast()
    }

    public func clearLineDraft() {
        lineDraft = []
    }

    /// Creates a line calling at the picked stops, in order, through
    /// `GameWorld.createLine(named:stops:)`, and selects it. The draft is
    /// kept when GameCore refuses the stops.
    public func createLineFromDraft() {
        var created: LineID?
        let stops = lineDraft
        perform { world throws(GameError) in
            let line = try world.createLine(named: Self.suggestedLineName(for: world, in: language), stops: stops)
            created = line.id
            return language.text(
                "Created \(line.name) with \(stops.count) stops. Set how many trains it runs.",
                "已建立 \(line.name)，共 \(stops.count) 站。請設定上線列車數。"
            )
        }
        if let created {
            selectedLineID = created
            lineDraft = []
        }
    }

    /// Removes the selected line through `GameWorld.removeLine(_:)`; its
    /// trains finish the trip they are on.
    public func removeSelectedLine() {
        guard let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.removeLine(line.id)
            return language.text("Removed \(line.name). Its trains finish the trip they are on.", "已刪除 \(line.name)。它的列車會跑完目前這一趟。")
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
            return language.text("Updated the service's physical path.", "已更新交路的股道與月台。")
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
                "已在 \(line.name) 加入\(title)（交路 \(index + 1)）。"
            )
        }
    }

    /// Removes the selected line's pattern at `index`; its trains finish
    /// the trip they are on.
    public func removePatternFromSelectedLine(_ index: Int) {
        guard let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.removeLinePattern(line.id, at: index)
            return language.text("Removed pattern \(index + 1) from \(line.name).", "已從 \(line.name) 刪除交路 \(index + 1)。")
        }
    }

    /// Assigns the selected train to a service of the selected line (its
    /// own for `pattern` `nil`), which sends it out from the service's first
    /// stop once it waits there.
    public func assignSelectedTrainToSelectedLine(pattern: Int? = nil) {
        guard let train = requireSelectedTrain(), let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.assignTrain(train.id, to: line.id, pattern: pattern)
            let service = world.assignedServiceName(of: train.id, in: language) ?? line.name
            return language.text(
                "\(train.name) now runs for \(service). It leaves once it waits at the first stop.",
                "\(train.name) 現在為 \(service) 服務。它在第一站等候後就會出發。"
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
            try world.startTrainService(train.id)
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
        case .select, .network:
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

    /// Runs one command against the world and records its outcome. Returns
    /// whether the command succeeded.
    @discardableResult
    func perform(_ command: (inout GameWorld) throws(GameError) -> String) -> Bool {
        do throws(GameError) {
            message = StatusMessage(kind: .success, text: try command(&world))
            return true
        } catch {
            message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
            return false
        }
    }

    /// "Station N" (or "車站 N") with the lowest N from the next station
    /// number upward that no existing station uses.
    static func suggestedStationName(for world: GameWorld, in language: DisplayLanguage) -> String {
        suggestedName(language.text("Station", "車站"), from: world.stations.count + 1, taken: Set(world.stations.map(\.name)))
    }

    /// "Line N" (or "路線 N") with the lowest N from the next line number
    /// upward that no existing line uses.
    private static func suggestedLineName(for world: GameWorld, in language: DisplayLanguage) -> String {
        suggestedName(language.text("Line", "路線"), from: world.lines.count + 1, taken: Set(world.lines.map(\.name)))
    }

    /// "Train N" (or "列車 N") with the lowest N from the next train number
    /// upward that no existing train uses.
    private static func suggestedTrainName(for world: GameWorld, in language: DisplayLanguage) -> String {
        suggestedName(language.text("Train", "列車"), from: world.trains.count + 1, taken: Set(world.trains.map(\.name)))
    }

    /// "`prefix` N" with the lowest N from `first` upward that is not in
    /// `taken`.
    private static func suggestedName(_ prefix: String, from first: Int, taken: Set<String>) -> String {
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
}
