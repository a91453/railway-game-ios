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
/// tile and station, the active tool, the track piece being placed, the draft station name,
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

    /// The tile the player last selected. Always inside the map when set.
    public private(set) var selection: GridPosition?

    /// The station the player last picked (Stage F1): an ID only, never a
    /// copy of the station. Read the selected station through
    /// ``selectedStation``. A station at a point takes no tile, so it is
    /// picked by where it stands (``tapMap(at:reach:)``) or by name
    /// (``selectStation(_:)``), not by the tile alone.
    public private(set) var selectedStationID: StationID?

    /// What the action button does to the selected tile.
    public private(set) var tool: ConstructionTool = .select

    /// The directions the next track piece connects. May be empty while the
    /// player edits it; GameCore rejects building an empty piece.
    public private(set) var trackConnections: TrackConnections = TrackPiece.straight.connections

    /// Whether the next track piece is plain, a turnout or a level crossing
    /// (Stage C2).
    public private(set) var trackPieceKind: TrackPieceKind = .plain

    /// The exit of the next turnout that joins every other one. Always one
    /// of ``trackConnections`` while the kind is a turnout and it has any.
    public private(set) var turnoutStem: TrackDirection = .west

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

    public init(world: GameWorld, language: DisplayLanguage = .english) {
        self.world = world
        self.language = language
        self.stationName = Self.suggestedStationName(for: world, in: language)
        self.selectedTrainID = world.trains.first?.id
        self.selectedLineID = world.lines.first?.id
    }

    // MARK: - Selection

    /// The land of the selected tile, read from the world.
    public var selectedTile: MapTile? {
        selection.flatMap { world.map.tile(at: $0) }
    }

    /// The grid track on the selected tile, read from the world's railway
    /// network (Stage S3A: track is not on the map).
    public var selectedTrack: Track? {
        selection.flatMap { world.track(at: $0) }
    }

    /// Selects the tile at `position` and the station on it (see
    /// ``station(onTile:)``); positions outside the map are ignored.
    public func select(_ position: GridPosition) {
        guard world.map.contains(position) else { return }
        let station = station(onTile: position)?.id
        guard position != selection || station != selectedStationID else { return }
        selection = position
        selectedStationID = station
        message = nil
    }

    /// A tap on the map at `point` with the select or train tool (Stage
    /// F1), reaching `reach` world units to a station: selects the station
    /// that takes the tile under the point, or else the nearest station
    /// within reach (`GameWorld.station(near:within:)`), or else one at a
    /// point inside that tile (see ``station(onTile:)``), and the tile.
    /// Taps off the map are ignored. Never changes the world.
    public func tapMap(at point: PlanPoint, reach: Int64) {
        let size = WorldCoordinate.tileSize
        guard point.x >= 0, point.y >= 0, point.x < Int64(world.map.width) * size, point.y < Int64(world.map.height) * size else { return }
        let tile = GridPosition(x: Int(point.x / size), y: Int(point.y / size))
        let station = (world.station(at: tile) ?? world.station(near: point, within: reach) ?? station(onTile: tile))?.id
        guard tile != selection || station != selectedStationID else { return }
        selection = tile
        selectedStationID = station
        message = nil
    }

    /// Selects station `id` and the tile it stands on: its first tile, or
    /// the tile under its point. Never changes the world; an ID the world
    /// does not have is ignored.
    public func selectStation(_ id: StationID) {
        guard let station = world.station(id: id), id != selectedStationID || station.position != selection else { return }
        selection = station.position
        selectedStationID = id
        message = nil
    }

    public func clearSelection() {
        selection = nil
        selectedStationID = nil
        message = nil
    }

    /// The station on the tile at `position`: the station that takes the
    /// tile, or else the first, in ID order, of the stations at a point
    /// inside it.
    func station(onTile position: GridPosition) -> Station? {
        world.station(at: position) ?? world.stations.first { $0.tiles.isEmpty && $0.position == position }
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

    /// Adds or removes one direction of the next track piece. A crossing
    /// has all four, so changing one makes the piece plain.
    public func toggleTrackDirection(_ direction: TrackDirection) {
        trackConnections.formSymmetricDifference(TrackConnections(direction))
        if trackPieceKind == .crossing {
            trackPieceKind = .plain
        }
        keepTurnoutStem()
    }

    /// Starts the next piece from `piece`. Only the four-way piece can be a
    /// crossing, and a turnout needs three exits or more, so otherwise the
    /// piece becomes plain.
    public func selectTrackPiece(_ piece: TrackPiece) {
        trackConnections = piece.connections
        if (trackPieceKind == .crossing && piece != .fourWay) || (trackPieceKind == .turnout && piece.connections.directions.count < 3) {
            trackPieceKind = .plain
        }
        keepTurnoutStem()
    }

    /// Turns the next track piece, and a turnout's stem, a quarter turn
    /// clockwise.
    public func rotateTrackPiece() {
        trackConnections = trackConnections.rotatedClockwise
        turnoutStem = turnoutStem.clockwise
    }

    /// Makes the next piece plain, a turnout or a level crossing (Stage
    /// C2). A turnout of fewer than three exits starts as a T-junction, and
    /// a crossing has all four.
    public func setTrackPieceKind(_ kind: TrackPieceKind) {
        trackPieceKind = kind
        switch kind {
        case .plain: break
        case .turnout:
            if trackConnections.directions.count < 3 {
                trackConnections = TrackPiece.junction.connections
            }
            keepTurnoutStem()
        case .crossing:
            trackConnections = TrackPiece.fourWay.connections
        }
    }

    /// The next piece's kind as the track tool's menu shows it: "Plain",
    /// "Turnout · stem W" or "Crossing"; "道岔 · 共用端 西".
    public var trackPieceKindText: String {
        switch trackPieceKind {
        case .plain, .crossing:
            return trackPieceKind.title(in: language)
        case .turnout:
            let stem = turnoutStem.abbreviation(in: language)
            return language.text("Turnout · stem \(stem)", "道岔 · 共用端 \(stem)")
        }
    }

    /// The layout the next piece gets: what the preview draws.
    public var trackPieceLayout: TrackLayout {
        switch trackPieceKind {
        case .plain: .open
        case .turnout: .turnout(stem: turnoutStem)
        case .crossing: .crossing
        }
    }

    /// Makes `stem` the next turnout's stem, if the piece has that exit.
    public func setTurnoutStem(_ stem: TrackDirection) {
        guard trackConnections.contains(TrackConnections(stem)) else { return }
        turnoutStem = stem
    }

    /// Keeps the turnout's stem among the piece's exits: the first exit,
    /// west, north, east then south, that a straight track runs through,
    /// or else the first exit.
    private func keepTurnoutStem() {
        guard !trackConnections.contains(TrackConnections(turnoutStem)) else { return }
        let order: [TrackDirection] = [.west, .north, .east, .south]
        let exits = order.filter { trackConnections.contains(TrackConnections($0)) }
        turnoutStem = exits.first { trackConnections.contains(TrackConnections($0.opposite)) } ?? exits.first ?? turnoutStem
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

    /// Switches the company between free play and management through
    /// `GameWorld.setEconomyMode(_:)`. Managed, fares are charged and the
    /// running costs settled every hour and day.
    public func setEconomyMode(_ mode: EconomyMode) {
        guard mode != world.accounts.mode else { return }
        world.setEconomyMode(mode)
        message = StatusMessage(
            kind: .success,
            text: mode == .management
                ? language.text(
                    "The company is managed: fares are charged and running costs settled from the next hour.",
                    "公司進入經營模式：從下一個小時起收取票價、結算營運成本。"
                )
                : language.text("Free play: no fares or running costs.", "自由模式：不收票價，也沒有營運成本。")
        )
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
    public func setPlacementHeading(_ heading: TrackDirection) {
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
    ///
    /// Without such a station, on the grid (the compatibility layer, Stage
    /// F1), it goes at the centre of the selected tile, facing
    /// ``placementHeading``, through `GameWorld.placeTrain(_:at:)`. GameCore
    /// decides whether the tile can take it.
    public func placeSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        guard let tile = selection else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station to place \(train.name) at.", "請選擇要放置 \(train.name) 的車站。"))
            return
        }
        // Stage C1: a station with platforms on the track network takes
        // the train at one of them.
        if let station = selectedStation {
            if !world.trackPlatforms(of: station.id).isEmpty {
                place(train, atPlatformOf: station)
                return
            }
            // Stage F1: a station at a point has no tile to stand on.
            if station.tiles.isEmpty {
                message = StatusMessage(kind: .failure, text: language.text(
                    "\(station.name) has no platform yet. Add one with the network tool.",
                    "\(station.name) 還沒有月台。請用路網工具加上月台。"
                ))
                return
            }
        }
        let heading = placementHeading
        perform { world throws(GameError) in
            try world.placeTrain(train.id, at: .atNode(tile, heading: heading))
            return language.text(
                "Placed \(train.name) at \(tile), facing \(heading.name(in: language).lowercased()).",
                "已將 \(train.name) 放在 \(tile)，面向\(heading.name(in: language))。"
            )
        }
    }

    /// Sets how many cars the selected train has through
    /// `GameWorld.setTrainCars(_:to:)`: only while it is off the track.
    public func setSelectedTrainCars(_ cars: Int) {
        guard let train = requireSelectedTrain() else { return }
        perform { world throws(GameError) in
            try world.setTrainCars(train.id, to: cars)
            let count = Train.carsText(cars, in: language)
            return language.text("\(train.name) now has \(count).", "\(train.name) 現在有 \(count)。")
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

    /// Sends the selected train to the selected station, or to the
    /// selected tile.
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
    /// A train on the track network (Stage S5) goes only to a station: to
    /// where it stops at one of the station's platforms on the network that
    /// it fits, along `GameWorld.path(from:toStation:length:)`, committed
    /// unchanged with `GameWorld.setTrainContinuation(_:along:stoppingAt:)`.
    ///
    /// Without a route (the tile is neither track nor a station with track
    /// beside it, or the train cannot get there without turning straight
    /// back) nothing changes, and the train keeps the continuation it had.
    public func sendSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        guard let destination = selection else {
            message = StatusMessage(kind: .failure, text: language.text("Select the station to send \(train.name) to.", "請選擇 \(train.name) 要前往的車站。"))
            return
        }
        guard let position = train.position else {
            message = StatusMessage(kind: .failure, text: GameError.trainNotPlaced(train.id).playerMessage(in: language))
            return
        }
        // A station is not track: the train goes to one of its platforms.
        let station = selectedStation
        if case .onEdge = position {
            send(train, from: position, to: station, at: destination)
            return
        }
        let found: [GridPosition]?
        if let station {
            found = world.route(from: position, toStation: station.id, length: train.length)
        } else {
            found = world.route(from: position, to: destination)
        }
        guard let route = found else {
            let target = station?.name ?? "\(destination)"
            let text = station == nil
                ? language.text(
                    "No route for \(train.name) to \(target): it must be track the train can reach without turning back. Its path is unchanged.",
                    "\(train.name) 沒有路可以到 \(target)：目的地必須是列車不折返就能到達的軌道。路徑沒有改變。"
                )
                : language.text(
                    "No route for \(train.name) to \(target): it needs track beside the station that the train can reach without turning back. Its path is unchanged.",
                    "\(train.name) 沒有路可以到 \(target)：車站旁要有列車不折返就能到達的軌道。路徑沒有改變。"
                )
            message = StatusMessage(kind: .failure, text: text)
            return
        }
        // The route starts after this node: the one the train stands on, or
        // the far end of its link.
        let start: GridPosition
        switch position {
        case .atNode(let tile, _): start = tile
        case .onLink(_, let to, _): start = to
        // A train on the track network was sent above.
        case .onEdge: return
        }
        // For a station, name it and the platform the route ends at.
        let target = station.map { language.text("\($0.name), platform \(route.last ?? start)", "\($0.name) 的月台 \(route.last ?? start)") }
            ?? "\(destination)"
        perform { world throws(GameError) in
            try world.setTrainContinuation(train.id, to: route)
            let sent: String
            switch language {
            case .english:
                let links = route.count == 1 ? "1 link" : "\(route.count) links"
                sent = route.isEmpty ? "\(train.name) stops at \(target)." : "Sent \(train.name) to \(target), \(links) from \(start)."
            case .traditionalChinese:
                sent = route.isEmpty ? "\(train.name) 停在 \(target)。" : "已派 \(train.name) 前往 \(target)，從 \(start) 起 \(route.count) 段連結。"
            }
            return train.movement.rate == 0 ? sent + language.text(" Set a rate to start.", "設定速率後出發。") : sent
        }
    }

    /// ``sendSelectedTrain()`` for `train` at `position` on the track
    /// network: to `station`, the station at `destination` if there is one.
    private func send(_ train: Train, from position: TrainPosition, to station: Station?, at destination: GridPosition) {
        guard let station else {
            message = StatusMessage(
                kind: .failure,
                text: language.text(
                    "No route for \(train.name) to \(destination): a train on the track network goes only to a station. Its path is unchanged.",
                    "\(train.name) 沒有路可以到 \(destination)：路網上的列車只能前往車站。路徑沒有改變。"
                )
            )
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
                switch trackPieceKind {
                case .plain:
                    let track = try world.buildTrack(at: position, connections: trackConnections)
                    let shape = track.connections.shapeName(in: language)
                    return language.text("Built \(shape.lowercased()) track at \(position).", "已在 \(position) 鋪設\(shape)軌道。")
                case .turnout:
                    let track = try world.buildTurnout(at: position, connections: trackConnections, stem: turnoutStem)
                    let exits = track.connections.abbreviation(in: language)
                    let stem = turnoutStem.abbreviation(in: language)
                    return language.text(
                        "Built a turnout at \(position): \(exits), stem \(stem).",
                        "已在 \(position) 鋪設道岔：\(exits)，共用端 \(stem)。"
                    )
                case .crossing:
                    try world.buildCrossing(at: position)
                    return language.text("Built a level crossing at \(position).", "已在 \(position) 鋪設平面交叉。")
                }
            }
        case .buildStation where growsStation:
            growStation(onto: position)
        case .buildStation:
            let built = perform { world throws(GameError) in
                // The world allocates the station's ID.
                let station = try world.buildStation(named: stationName, at: position)
                return language.text("Built station “\(station.name)” at \(position).", "已在 \(position) 建造車站「\(station.name)」。")
            }
            if built {
                stationName = Self.suggestedStationName(for: world, in: language)
            }
        case .removeTrack:
            perform { world throws(GameError) in
                try world.removeTrack(at: position)
                return language.text("Removed track at \(position).", "已拆除 \(position) 的軌道。")
            }
        case .network:
            // The network tool acts on what its taps picked, not on the tile.
            return
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
            message = StatusMessage(kind: .failure, text: language.text("There is no station beside \(position) to grow.", "\(position) 旁邊沒有可擴建的車站。"))
            return
        }
        perform { world throws(GameError) in
            try world.extendStation(station.id, to: position)
            return language.text("“\(station.name)” now covers \(station.tiles.count + 1) tiles.", "「\(station.name)」現在佔 \(station.tiles.count + 1) 格。")
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
