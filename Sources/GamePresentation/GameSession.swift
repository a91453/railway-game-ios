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
/// tile, the active tool, the track piece being placed, the draft station name,
/// the selected train, the heading for placing it, the selected line, the
/// stops picked for a new line, and the last action's message. Anything shown about the game, including where each train is and
/// where it is going, is derived from ``world`` on demand.
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

    /// Whether the station tool grows the station beside the selected tile
    /// onto it, rather than building a new station there.
    public var growsStation = false

    /// The train the train tool acts on: an ID only, never a copy of the
    /// train. Read the train itself through ``selectedTrain``.
    public private(set) var selectedTrainID: TrainID?

    /// The heading the selected train gets when it is placed. Only used by
    /// ``placeSelectedTrain()``; it never turns a train that is on the track.
    public private(set) var placementHeading: TrackDirection = .east

    /// The outcome of the last action, for the status line. Cleared when the
    /// player selects another tile or tool.
    public private(set) var message: StatusMessage?

    /// The line the line panel shows: an ID only, never a copy of the line.
    /// Read the line itself through ``selectedLine``.
    public private(set) var selectedLineID: LineID?

    /// The stations picked, in order, for the next line. Only a draft:
    /// GameCore checks them when ``createLineFromDraft()`` creates the line.
    public private(set) var lineDraft: [StationID] = []

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
        self.selectedTrainID = world.trains.first?.id
        self.selectedLineID = world.lines.first?.id
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
    public func setPlacementHeading(_ heading: TrackDirection) {
        placementHeading = heading
    }

    /// Buys a train through `GameWorld.purchaseTrain(named:)`, which charges
    /// its cost and allocates its ID, and selects it. It is not on the track
    /// until it is placed.
    public func purchaseTrain() {
        var purchased: TrainID?
        perform { world throws(GameError) in
            let train = try world.purchaseTrain(named: Self.suggestedTrainName(for: world))
            purchased = train.id
            return "Bought \(train.name). Select a track tile to place it."
        }
        if let purchased {
            selectedTrainID = purchased
        }
    }

    /// Puts the selected train at the centre of the selected tile, facing
    /// ``placementHeading``, through `GameWorld.placeTrain(_:at:)`. GameCore
    /// decides whether the tile can take it.
    public func placeSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        guard let tile = selection else {
            message = StatusMessage(kind: .failure, text: "Select a track tile to place \(train.name) on.")
            return
        }
        let heading = placementHeading
        perform { world throws(GameError) in
            try world.placeTrain(train.id, at: .atNode(tile, heading: heading))
            return "Placed \(train.name) at \(tile), facing \(heading.name.lowercased())."
        }
    }

    /// Sets how many cars the selected train has through
    /// `GameWorld.setTrainCars(_:to:)`: only while it is off the track.
    public func setSelectedTrainCars(_ cars: Int) {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.setTrainCars(train.id, to: cars)
            return "\(train.name) now has \(cars == 1 ? "1 car" : "\(cars) cars")."
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
            message = StatusMessage(kind: .failure, text: error.playerMessage)
        }
    }

    /// Sends the selected train to the selected tile, or to the selected
    /// station.
    ///
    /// Asks GameCore for the route from where the train is now
    /// (`GameWorld.route(from:to:)` for a track tile, or
    /// `GameWorld.route(from:toStation:length:)` for a station tile, which
    /// reaches the nearest of the station's platforms and pulls a train of
    /// several cars along them) and commits exactly that route
    /// with `GameWorld.setTrainContinuation(_:to:)`. Both run against the same
    /// world within this one call, with nothing in between, so the route can
    /// never be stale or reach another train. The session never finds or
    /// edits a path itself.
    ///
    /// Without a route (the tile is neither track nor a station with track
    /// beside it, or the train cannot get there without turning straight
    /// back) nothing changes, and the train keeps the continuation it had.
    public func sendSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        guard let destination = selection else {
            message = StatusMessage(kind: .failure, text: "Select the track tile to send \(train.name) to.")
            return
        }
        guard let position = train.position else {
            message = StatusMessage(kind: .failure, text: GameError.trainNotPlaced(train.id).playerMessage)
            return
        }
        // A station is not track: the train goes to one of its platforms.
        let station = world.station(at: destination)
        let found: [GridPosition]?
        if let station {
            found = world.route(from: position, toStation: station.id, length: train.length)
        } else {
            found = world.route(from: position, to: destination)
        }
        guard let route = found else {
            let reason = station == nil
                ? "it must be track the train can reach without turning back"
                : "it needs track beside the station that the train can reach without turning back"
            message = StatusMessage(
                kind: .failure,
                text: "No route for \(train.name) to \(station?.name ?? "\(destination)"): \(reason). Its path is unchanged."
            )
            return
        }
        // The route starts after this node: the one the train stands on, or
        // the far end of its link.
        let start: GridPosition
        switch position {
        case .atNode(let tile, _): start = tile
        case .onLink(_, let to, _): start = to
        }
        // For a station, name it and the platform the route ends at.
        let target = station.map { "\($0.name), platform \(route.last ?? start)" } ?? "\(destination)"
        perform { world throws(GameError) in
            try world.setTrainContinuation(train.id, to: route)
            let links = route.count == 1 ? "1 link" : "\(route.count) links"
            let sent = route.isEmpty
                ? "\(train.name) stops at \(target)."
                : "Sent \(train.name) to \(target), \(links) from \(start)."
            return train.movement.rate == 0 ? "\(sent) Set a rate to start." : sent
        }
    }

    /// Turns the selected train around where it stands through
    /// `GameWorld.reverseTrain(_:)`, which also clears its continuation.
    public func reverseSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.reverseTrain(train.id)
            return "Reversed \(train.name); its path was cleared."
        }
    }

    /// Takes the selected train off the track through
    /// `GameWorld.unplaceTrain(_:)`, which also clears its rate and path.
    public func unplaceSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.unplaceTrain(train.id)
            return "Took \(train.name) off the track."
        }
    }

    /// The selected train, or `nil` after reporting that there is none.
    private func requireSelectedTrain() -> Train? {
        guard let id = selectedTrainID else {
            message = StatusMessage(kind: .failure, text: "Buy a train first.")
            return nil
        }
        guard let train = world.train(id: id) else {
            message = StatusMessage(kind: .failure, text: GameError.unknownTrain(id).playerMessage)
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

    /// Adds the station on the selected tile to the end of the new line's
    /// stops. Never changes the world.
    public func addSelectedStationToLineDraft() {
        guard let position = selection, let station = world.station(at: position) else {
            message = StatusMessage(kind: .failure, text: "Select a station on the map to add it to the new line.")
            return
        }
        guard lineDraft.last != station.id else {
            message = StatusMessage(kind: .failure, text: "\(station.name) is already the last stop. A line cannot call at the same station twice in a row.")
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
            let line = try world.createLine(named: Self.suggestedLineName(for: world), stops: stops)
            created = line.id
            return "Created \(line.name) with \(stops.count) stops. Set how many trains it runs."
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
            return "Removed \(line.name). Its trains finish the trip they are on."
        }
        selectedLineID = world.lines.first?.id
    }

    /// Runs the selected line all day, or from 06:00 to midnight.
    public func setSelectedLineAllDay(_ allDay: Bool) {
        guard let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.setLineServiceWindow(line.id, to: allDay ? .allDay : .standard)
            return "\(line.name) runs \(allDay ? "all day" : "from 06:00 to midnight")."
        }
    }

    /// Sets how many trains a service of the selected line runs at `level`
    /// (its own for `pattern` `nil`), keeping the other levels. How many it
    /// can run is derived; see ``GameWorld/lineServiceSummaries(_:)``.
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
            return "\(line.name): \(count) \(count == 1 ? "train" : "trains") at \(level.title.lowercased())."
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
            let what = minutes.map { headwayText(minutes: $0).lowercased() } ?? "the train count"
            return "\(line.name) at \(level.title.lowercased()): \(what)."
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
            let title = world.serviceTitle(of: world.line(id: line.id)!, calls: calls)
            return "Added \(title) to \(line.name) as pattern \(index + 1)."
        }
    }

    /// Removes the selected line's pattern at `index`; its trains finish
    /// the trip they are on.
    public func removePatternFromSelectedLine(_ index: Int) {
        guard let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.removeLinePattern(line.id, at: index)
            return "Removed pattern \(index + 1) from \(line.name)."
        }
    }

    /// Assigns the selected train to a service of the selected line (its
    /// own for `pattern` `nil`), which sends it out from the service's first
    /// stop once it waits there.
    public func assignSelectedTrainToSelectedLine(pattern: Int? = nil) {
        guard let train = requireSelectedTrain(), let line = requireSelectedLine() else { return }
        perform { world throws(GameError) in
            try world.assignTrain(train.id, to: line.id, pattern: pattern)
            let service = world.assignedServiceName(of: train.id) ?? line.name
            return "\(train.name) now runs for \(service). It leaves once it waits at the first stop."
        }
    }

    /// Takes the selected train off its line; a trip under way is finished.
    public func unassignSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.unassignTrain(train.id)
            return "Took \(train.name) off its line. A trip under way is finished."
        }
    }

    /// Starts the selected train's own timetable through
    /// `GameWorld.startTrainService(_:)`.
    public func startSelectedTrainService() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.startTrainService(train.id)
            return "\(train.name) is running its timetable."
        }
    }

    /// Stops the selected train's service through
    /// `GameWorld.stopTrainService(_:)`; it keeps its timetable.
    public func stopSelectedTrainService() {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.stopTrainService(train.id)
            return "Stopped \(train.name)'s service. It stays where it is."
        }
    }

    /// The selected line, or `nil` after reporting that there is none.
    private func requireSelectedLine() -> ServiceLine? {
        guard let line = selectedLine else {
            message = StatusMessage(kind: .failure, text: "Create or choose a line first.")
            return nil
        }
        return line
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
        case .buildStation where growsStation:
            growStation(onto: position)
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
        case .train:
            // The selected tile is where an unplaced train goes, or where a
            // placed one is sent.
            if selectedTrain?.position == nil {
                placeSelectedTrain()
            } else {
                sendSelectedTrain()
            }
        }
    }

    /// Grows the first station, in ID order, with a tile beside `position`
    /// onto it through `GameWorld.extendStation(_:to:)`.
    private func growStation(onto position: GridPosition) {
        let beside = world.stations.filter { station in
            station.tiles.contains { abs($0.x - position.x) + abs($0.y - position.y) == 1 }
        }
        guard let station = beside.min(by: { $0.id < $1.id }) else {
            message = StatusMessage(kind: .failure, text: "There is no station beside \(position) to grow.")
            return
        }
        perform { world throws(GameError) in
            try world.extendStation(station.id, to: position)
            return "“\(station.name)” now covers \(station.tiles.count + 1) tiles."
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

    /// "Line N" with the lowest N from the next line number upward that no
    /// existing line uses.
    private static func suggestedLineName(for world: GameWorld) -> String {
        let names = Set(world.lines.map(\.name))
        var number = world.lines.count + 1
        while names.contains("Line \(number)") {
            number += 1
        }
        return "Line \(number)"
    }

    /// "Train N" with the lowest N from the next train number upward that no
    /// existing train uses.
    private static func suggestedTrainName(for world: GameWorld) -> String {
        let names = Set(world.trains.map(\.name))
        var number = world.trains.count + 1
        while names.contains("Train \(number)") {
            number += 1
        }
        return "Train \(number)"
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
