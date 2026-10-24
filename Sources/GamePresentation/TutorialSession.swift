import GameCore

// The tutorial's controls (Stage C5; see Tutorial.swift): start it, or
// start it again from the first step, from the start screen or the game
// menu, or take it up again where it was skipped; Back, Next (Finish on the last step), Skip and "Skip this step" on
// its card, and the step moving on by itself once done (decision 188).
// None of them changes the world.

extension GameSession {
    /// Shows the tutorial from its first step: the reference's
    /// `startTutorial`, and starting it again from the game menu.
    ///
    /// What was picked before it began (a stretch's start and end, a line's
    /// stations, a selection) is dropped first: started from the game menu
    /// in a game being built in, a stretch already picked had the drawing
    /// step passed as done before the player drew anything.
    public func startTutorial() {
        networkStart = nil
        networkEnd = nil
        networkEdgePoint = nil
        clearLineDraft()
        clearSelection()
        tutorial = Tutorial(steps: Tutorial.steps(over: world), over: world)
        skippedTutorial = nil
        setUpTutorialStep()
    }

    /// Shows the tutorial from step `id`, its steps before it skipped, over
    /// the world as it is now; from the first step if there is no such
    /// step. For the UI tests of a later step's screen (Debug builds'
    /// `-tutorial-step`, ``GameLauncher/startTutorial(atStep:)``).
    public func startTutorial(atStep id: String) {
        var shown = Tutorial(steps: Tutorial.steps(over: world), over: world)
        if let index = shown.steps.firstIndex(where: { $0.id == id }) {
            shown.show(index, over: world)
        }
        tutorial = shown
        skippedTutorial = nil
        setUpTutorialStep()
    }

    /// Whether the player has done what the step on screen asks (the
    /// reference's `_tutorialStepActionDone`), read from the world and the
    /// session; `false` without a tutorial. Next waits for it.
    public var isTutorialStepDone: Bool {
        guard let tutorial else { return false }
        return isTutorialStepDone(tutorial.index, in: tutorial)
    }

    /// Whether the step on screen moves on by itself
    /// (``Tutorial/autoAdvanceDelay`` after it is done, decision 188): an
    /// action step, done, that was not reached by Back, and not the last.
    /// The last waits for Finish, which alone ends a tutorial (decision
    /// 177): lesson 1's guide ends on an action step, the first fares
    /// (decision 266), and moving on from it by itself had ended the guide
    /// before Finish could be tapped (the full lane on main d530311).
    public var tutorialAdvancesByItself: Bool {
        guard let tutorial else { return false }
        return tutorial.step.goal != .read && !tutorial.isLastStep && !tutorial.reachedByBack && isTutorialStepDone
    }

    /// The places on the map the step on screen has the player tap
    /// (decision 188, later fix): the ends of the stretch of track built for
    /// the stations (near one end, then the other), the line's two
    /// stations, then a station to select. The tutorial's card keeps clear
    /// of them, or folds: on a phone on its side, with the lines panel open,
    /// it stood over both of the line's stations and the player could not
    /// pick them (run 38307741519). Only what the player built in the
    /// tutorial (since the track or the stations chapter began); all of it
    /// when the tutorial began after that chapter (`-tutorial-step`). Empty
    /// for the other steps: drawing the track may start anywhere, and the
    /// map's ✓ is a control of its own.
    public var tutorialPlacesToTap: [PlanPoint] {
        guard let tutorial else { return [] }
        switch tutorial.step.goal {
        case .pickPlatformSite:
            // The stretch's outer ends: the nodes of one new edge, the
            // platforms splitting it in between.
            let before = tutorial.snapshot(of: .track)
            let edges = world.network.edges.filter { before?.edges.contains($0.id) != true }
            var ends: [TrackNodeID: Int] = [:]
            for edge in edges {
                ends[edge.from, default: 0] += 1
                ends[edge.to, default: 0] += 1
            }
            var seen: Set<TrackNodeID> = []
            return edges.flatMap { [$0.from, $0.to] }.compactMap { id in
                guard ends[id] == 1, seen.insert(id).inserted, let node = world.network.node(id) else { return nil }
                return PlanPoint(x: node.position.x, y: node.position.y)
            }
        case .pickLineStations, .selectStation:
            let before = tutorial.snapshot(of: .stations)
            return world.stations.filter { before?.stations.contains($0.id) != true }.map(\.location)
        case .selectStationOffLine:
            // Decision 390: the station lesson 2 built, on no line yet.
            return world.stations.filter { isOffEveryLine($0) }.map(\.location)
        case .drawTrack:
            // Decision 390: in a lesson, the places its goal links that
            // have no station yet, where the track is to go.
            return tutorialPlacesToReach?.places ?? []
        case .selectPassingLoop:
            // Decision 376: the line's passing loops, which the player
            // did not build in the lesson.
            return world.stations.filter { Self.isPassingPlace($0, in: world) }.map(\.location)
        case .pickDepotEnd:
            // The ends of the tracks: a node only one edge ends at.
            return world.network.nodes.filter { $0.ends.count == 1 }.map { PlanPoint(x: $0.position.x, y: $0.position.y) }
        case .selectStationForFreight:
            return world.stations.filter { Self.takesFreightYard($0, in: world) }.map(\.location)
        case .selectTrack:
            // Decision 378: the middle of the stretch to make double.
            guard let id = tutorialDoubleTrackStretch, let geometry = world.trackGeometry(of: id) else { return [] }
            return [geometry.location(at: geometry.length / 2).position.plan]
        default:
            return []
        }
    }

    /// The stretch lesson 5's guide has the player make double (decision
    /// 378): the longest single track, with none beside it, that a
    /// crossover could be cut into at its middle (no train on it or on its
    /// way along it, no platform there). Lesson 5's longest track, out to
    /// the third town, has a train at its station and costs more than the
    /// lesson's cash; the one the guide points at is built at once.
    var tutorialDoubleTrackStretch: TrackEdgeID? {
        world.network.edges
            .filter { edge in world.trackEdgeSplitRefusal(edge.id, at: edge.length / 2) == nil && !hasTrackBeside(edge.id) }
            .max { $0.length != $1.length ? $0.length < $1.length : $0.id > $1.id }?.id
    }

    /// Where ``tutorialDoubleTrackStretch`` is, as the player reads it:
    /// "by" the station with a platform on it, or the track with no train.
    private var tutorialDoubleTrackPlace: String {
        let station = tutorialDoubleTrackStretch.flatMap { id in world.network.platforms(on: id).first }
            .flatMap { platform in world.stations.first { $0.id == platform.station } }
        return station.map { language.text("Tap the track by \u{201C}\($0.name)\u{201D}, with no train on it.", "點「\($0.name)」旁沒有列車的那段軌道。") }
            ?? language.text("Tap the track with no train on it.", "點沒有列車的那段軌道。")
    }

    /// Next: the following step, or, on the last step, Finish, which ends
    /// the tutorial. Does nothing until the step on screen is done. Steps
    /// already done on the way are passed over.
    public func showNextTutorialStep() {
        guard let shown = tutorial, isTutorialStepDone else { return }
        if shown.isLastStep {
            tutorial = nil
            onTutorialCompleted?()
        } else {
            moveTutorialForward(to: shown.index + 1)
        }
    }

    /// Next, for the step that moved on by itself: only while step `index`
    /// is still on screen and moves on by itself, so a late call (the
    /// player tapped Next, or went Back) does nothing.
    public func showNextTutorialStep(from index: Int) {
        guard tutorial?.index == index, tutorialAdvancesByItself else { return }
        showNextTutorialStep()
    }

    /// "Skip this step": the following step, without the goal of the step
    /// on screen, for a step that cannot be done here (decision 188). Only
    /// for an action step before the last; never finishes the tutorial,
    /// which only Finish does (decision 177).
    public func skipTutorialStep() {
        guard let shown = tutorial, shown.step.goal != .read, !shown.isLastStep else { return }
        moveTutorialForward(to: shown.index + 1)
    }

    /// Back: the step before, which then waits for Next. Does nothing on the
    /// first step, and sets nothing up.
    public func showPreviousTutorialStep() {
        guard var shown = tutorial, !shown.isFirstStep else { return }
        shown.show(shown.index - 1, over: world, byBack: true)
        tutorial = shown
    }

    /// Skip: ends the tutorial at any step (the reference's
    /// `dismissTutorial`), keeping it, with what each chapter began with,
    /// to be taken up again at the same step (``resumeTutorial()``).
    public func skipTutorial() {
        guard let shown = tutorial else { return }
        skippedTutorial = shown
        tutorial = nil
    }

    /// Takes the skipped tutorial up again at the step it was skipped on
    /// (decision 188, later fix: TestFlight 54.1 found the game menu
    /// started it again from the first step, and, as its goals ask for
    /// what is new since their chapter began, had the player build the
    /// track and the stations again). What was built in the tutorial still
    /// counts; a step done since moves on by itself.
    public func resumeTutorial() {
        guard let skipped = skippedTutorial else { return }
        tutorial = skipped
        skippedTutorial = nil
        setUpTutorialStep()
    }

    /// Keeps the tutorial to be taken up again at step `id` over the world
    /// as it is (``Tutorial/init(steps:resumingAt:over:)``): the step the
    /// launcher kept from an earlier launch. Nothing for an unknown step,
    /// or with a tutorial on screen.
    func keepTutorialToResume(atStep id: String) {
        guard tutorial == nil else { return }
        let steps = Tutorial.steps(over: world)
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        skippedTutorial = Tutorial(steps: steps, resumingAt: index, over: world)
    }

    /// Tells the launcher the step a tutorial left now would be taken up
    /// again at, when it has changed.
    func noteTutorialStepToResume() {
        let step = (tutorial ?? skippedTutorial)?.step.id
        guard step != notedTutorialStepToResume else { return }
        notedTutorialStepToResume = step
        onTutorialStepToResume?(step)
    }

    /// The player moved the map: pinched, dragged or tapped a zoom button
    /// (Stage E1). The camera is the map view's own state, so the view
    /// calls this for the tutorial's ``TutorialGoal/moveMap``. Changes the
    /// session only the first time on such a step, so calling it on every
    /// frame of a gesture costs nothing.
    public func mapDidMove() {
        // A drag, pinch or zoom ends following a train, as the reference's
        // `dragstart`, `zoomstart` and `rotatestart` do
        // (`metroCancelCameraFollowForUserGesture`).
        if followedTrainID != nil { stopFollowingTrain() }
        guard var shown = tutorial, shown.awaitsMapMove else { return }
        shown.noteMapMoved()
        tutorial = shown
    }

    /// The app opened or closed the lines panel. Changes the session only
    /// when it is so, as the app tells it on every change of its panel.
    public func linesPanelDidChange(isShown: Bool) {
        guard isLinesPanelShown != isShown else { return }
        isLinesPanelShown = isShown
    }

    /// The lines panel's Advanced switch turned on or off (decision 376),
    /// or the panel showed it as it was kept. Changes the session only
    /// when it is so.
    public func linesAdvancedDidChange(isShown: Bool) {
        guard isLinesAdvancedShown != isShown else { return }
        isLinesAdvancedShown = isShown
    }

    /// The app opened or closed the station panel (decision 376). Changes
    /// the session only when it is so.
    public func stationPanelDidChange(isShown: Bool) {
        guard isStationPanelShown != isShown else { return }
        isStationPanelShown = isShown
    }

    /// Shows step `index` and sets it up if it is shown for the first time,
    /// then passes over the action steps after it that are already done.
    private func moveTutorialForward(to index: Int) {
        guard var shown = tutorial else { return }
        var next = index
        while true {
            let isFirst = shown.show(next, over: world)
            tutorial = shown
            if isFirst { setUpTutorialStep() }
            guard let current = tutorial, current.step.goal != .read, !current.isLastStep,
                  isTutorialStepDone(next, in: current)
            else { return }
            shown = current
            next += 1
        }
    }

    /// Does what the step on screen needs set up (``TutorialSetup``).
    private func setUpTutorialStep() {
        guard let step = tutorial?.step else { return }
        for setup in step.setup {
            switch setup {
            case .layTrack:
                // A start tapped while the map was moved is kept.
                if networkMode != .build {
                    networkMode = .build
                    networkStart = nil
                    networkEnd = nil
                    networkEdgePoint = nil
                }
            case .clearPicks:
                networkStart = nil
                networkEnd = nil
                networkEdgePoint = nil
            case .clearLeftoverSite:
                // The place of the station just built: its ✓ would add a
                // platform to it. A place picked for a new one is kept.
                if networkEdgePoint != nil, platformStationID != nil {
                    networkEdgePoint = nil
                }
            case .clearLineDraft:
                clearLineDraft()
            case .clearSelection:
                clearSelection()
            case .selectNewestLine:
                // The line the tutorial made, unless the player chose one.
                if selectedLine == nil, let newest = world.lines.last {
                    selectLine(newest.id)
                }
            case .selectDepotLine:
                func reachesDepot(_ id: LineID) -> Bool {
                    world.depotRow(of: id, in: language)?.choices.isEmpty == false
                }
                if selectedLineID.map(reachesDepot) != true, let line = world.lines.last(where: { reachesDepot($0.id) }) {
                    selectLine(line.id)
                }
            }
        }
    }

    // MARK: - Goals

    /// Whether step `index` of `tutorial` is done in the world and the
    /// session as they are now.
    private func isTutorialStepDone(_ index: Int, in tutorial: Tutorial) -> Bool {
        let before = tutorial.snapshot(forChapterOf: index) ?? Tutorial.Snapshot(of: world)
        switch tutorial.steps[index].goal {
        case .read:
            return true
        case .chooseTool(let wanted):
            return tool == wanted
        case .moveMap:
            return tutorial.hasMovedMap(on: index)
        case .drawTrack:
            // A stretch that lengthens a short one built on the step counts
            // with it. Decision 390: extending a railway, it reaches the
            // place the lesson's goal is waiting for.
            let built = newTrackLength(since: before)
            let reaches = !holdsForPlaces(before) || newTrackReachesEveryPlace(since: before)
            if built >= Tutorial.minimumTrackLength, reaches { return true }
            guard tool == .network, let preview = networkPreview else { return false }
            return preview.problem == nil && preview.cost != nil && built + preview.length >= Tutorial.minimumTrackLength && reaches
        case .buildTrack:
            // Review H: the stretch built, not one still drawn, reaches the
            // place.
            return newTrackLength(since: before) >= Tutorial.minimumTrackLength
                && (!holdsForPlaces(before) || newTrackReachesEveryPlace(since: before, drawn: false))
        case .chooseNetworkMode(let mode):
            if tool == .network, networkMode == mode { return true }
            return mode == .platform && newStationCount(since: before) >= 1
        case .pickPlatformSite(let count):
            // Decision 390: extending a railway, the station goes at the
            // place the lesson's goal is waiting for.
            let held = holdsForPlaces(before)
            if newStationCount(since: before) >= count, !held { return true }
            return platformSitePlanPoint != nil && networkPlatformStretch != nil && platformStationID == nil
                && networkPlatformLevelling?.problem == nil && (!held || platformSiteIsAtAPlace)
        case .buildStation(let count):
            return newStationCount(since: before) >= count
        case .startPickingStops:
            return isPickingLineStops || !lineDraft.isEmpty || world.lines.contains { !before.lines.contains($0.id) }
        case .pickLineStations:
            return (lineDraft.count >= 2 && lineDraftRoute != nil) || world.lines.contains { !before.lines.contains($0.id) }
        case .createLine:
            return world.lines.contains { !before.lines.contains($0.id) && tutorialStaffingPlan($0.id) != nil }
        case .startService:
            return world.trains.contains { train in
                guard !before.assignedTrains.contains(train.id),
                      let id = world.assignedLine(of: train.id),
                      let line = world.lines.first(where: { $0.id == id })
                else { return false }
                // Target headways set the count when they are set
                // (see ``ServiceLine/service(at:roundTrip:)`` in GameCore).
                return line.trainsInService != .none || line.targetHeadways != .none
                    || line.patterns.contains { $0.trainsInService != .none || $0.targetHeadways != .none }
            }
        case .timeRuns:
            return !world.clock.isPaused
        case .earnFare:
            return world.accounts.mode == .free
                || CompanyAccounts.income(writtenAfter: before.lastEntry, in: world.accounts.entries, of: [.fareRevenue]) > .zero
        case .selectStation:
            return tool == .select && selectedStationID != nil
        case .openLines:
            return isLinesPanelShown
        case .addTrain:
            return world.trains.contains { !before.assignedTrains.contains($0.id) && world.assignedLine(of: $0.id) != nil }
        case .selectPassingLoop:
            return tool == .select && selectedStation.map { Self.isPassingPlace($0, in: world) } == true
        case .selectTrack:
            return tool == .select && selectedTrackEdge != nil
        case .draftDoubleTrack:
            return (tool == .select && trackUpgrade == .doubleTrack) || newTrackLength(since: before) > 0
        case .buildDoubleTrack:
            return newTrackLength(since: before) > 0
        case .showAdvanced:
            return isLinesAdvancedShown
        case .changeServiceHours:
            return world.serviceDay != before.serviceDay && before.serviceDay != nil
                || world.lines.contains { line in before.services[line.id].map { $0.window != line.window } == true }
        case .changeHeadway:
            return world.lines.contains { line in
                guard let was = before.services[line.id] else { return false }
                let now = Tutorial.Snapshot.LineService(line)
                return now.trains != was.trains || now.trainsInService != was.trainsInService || now.targetHeadways != was.targetHeadways
            }
        case .addPattern:
            return world.lines.contains { line in before.services[line.id].map { line.patterns.count > $0.patterns } == true }
        case .pickDepotEnd:
            return (tool == .network && networkMode == .depot && networkDepotEnd != nil) || newDepot(since: before)
        case .buildDepot:
            return newDepot(since: before)
        case .chooseDepot:
            return world.lines.contains { line in before.services[line.id].map { $0.depots != line.depots } == true }
        case .selectStationForFreight:
            return tool == .select && selectedStation.map { Self.takesFreightYard($0, in: world) } == true
        case .openStationPanel:
            return isStationPanelShown
        case .buildFreightYard(let count):
            return newFreightYards(since: before) >= count
        case .createFreightLine:
            return world.lines.contains { !before.lines.contains($0.id) && $0.isFreight }
        case .chooseBuildingKind(let kind):
            return (tool == .building && buildingMode == .build && buildingKind == kind) || newBuilding(of: kind, since: before)
        case .pickBuildingSite:
            return (tool == .building && buildingMode == .build && buildingSite != nil && buildingPreview?.problem == nil)
                || world.placedBuildings.contains { !before.buildings.contains($0.id) }
        case .putUpBuilding(let kind):
            return newBuilding(of: kind, since: before)
        case .acceptRequest:
            return world.cityRequests?.active.contains { !before.requestsInHand.contains($0.id) } == true
        case .selectStationOffLine:
            return (tool == .select && selectedStation.map(isOffEveryLine) == true) || addedStop(since: before)
        case .addStopToLine:
            return addedStop(since: before)
        }
    }

    /// Whether `station` is one a player's line could take on: a station
    /// with a platform, not a depot, that no line calls at (decision 390).
    private func isOffEveryLine(_ station: Station) -> Bool {
        !station.isDepot && !Self.isPassingPlace(station, in: world) && !world.lines.contains { $0.stops.contains(station.id) }
    }

    /// Whether a line has more stops than when `before` was taken.
    private func addedStop(since before: Tutorial.Snapshot) -> Bool {
        world.lines.contains { line in before.services[line.id].map { line.stops.count > $0.stops } == true }
    }

    /// The places the lesson's goal links that no station is near yet
    /// (decision 390), with how near a station must be: the towns, or
    /// lesson 9's sight. `nil` outside a lesson or without such a goal.
    var tutorialPlacesToReach: (places: [PlanPoint], radius: Int64)? {
        guard lesson != nil, let goals = world.scenario?.scenario.goals else { return nil }
        for case .connect(let points, let radius) in goals {
            let stations = world.stations.filter { !$0.isDepot && !Self.isPassingPlace($0, in: world) }
            let places = points.filter { point in !stations.contains { Self.squaredDistance($0.point, point) <= radius * radius } }
            return (places, radius)
        }
        return nil
    }

    /// Whether the track and station steps wait for the places to reach
    /// (decision 390): when the railway is being extended to them, the map
    /// having had stations when the chapter began (lessons 2, 4 and 9).
    /// Lesson 1's first track, on a blank map, is not held: its cards say
    /// to run it from town to town (holding it is in HANDOFF, with the UI
    /// tests that lay it inside one town).
    private func holdsForPlaces(_ before: Tutorial.Snapshot) -> Bool {
        before.hadStations && tutorialPlacesToReach?.places.isEmpty == false
    }

    /// Whether the track built since `before`, with the stretch picked
    /// when `drawn`, passes near every place to reach.
    private func newTrackReachesEveryPlace(since before: Tutorial.Snapshot, drawn: Bool = true) -> Bool {
        guard let reach = tutorialPlacesToReach else { return true }
        var lines = world.network.edges.filter { !before.edges.contains($0.id) }.compactMap { world.trackGeometry(of: $0.id)?.points }
        if drawn, tool == .network, let preview = networkPreview, preview.problem == nil { lines.append(preview.points) }
        return reach.places.allSatisfy { place in lines.contains { Self.passes($0, within: reach.radius, of: place) } }
    }

    /// Whether the platform's site picked is near a place to reach.
    private var platformSiteIsAtAPlace: Bool {
        guard let site = platformSitePlanPoint, let reach = tutorialPlacesToReach else { return false }
        return reach.places.contains { Self.squaredDistance(site, $0) <= reach.radius * reach.radius }
    }

    /// Whether the line through `points` passes within `radius` of `place`.
    static func passes(_ points: [WorldCoordinate], within radius: Int64, of place: PlanPoint) -> Bool {
        let px = Double(place.x), py = Double(place.y), limit = Double(radius) * Double(radius)
        func squared(_ x: Double, _ y: Double) -> Double { (x - px) * (x - px) + (y - py) * (y - py) }
        guard let first = points.first else { return false }
        if squared(Double(first.x), Double(first.y)) <= limit { return true }
        return zip(points, points.dropFirst()).contains { a, b in
            let (ax, ay, bx, by) = (Double(a.x), Double(a.y), Double(b.x), Double(b.y))
            let (dx, dy) = (bx - ax, by - ay), span = dx * dx + dy * dy
            let t = span == 0 ? 0 : min(1, max(0, ((px - ax) * dx + (py - ay) * dy) / span))
            return squared(ax + t * dx, ay + t * dy) <= limit
        }
    }

    /// Where the place to reach is, as the hints name it: the sight, or
    /// the town.
    private var placesToReachText: (track: String, site: String)? {
        guard let reach = tutorialPlacesToReach, !reach.places.isEmpty else { return nil }
        if reach.places == [Lesson.sight(in: world.bounds)] {
            return (
                language.text("It doesn't reach the sight yet. Tap the end beside it.", "還沒到景點，終點要點在景點旁。"),
                language.text("Too far from the sight. Tap your track beside it.", "離景點太遠，點景點旁的軌道。")
            )
        }
        return (
            language.text("It doesn't reach the town yet. Tap the end among its houses.", "還沒到城鎮，終點要點在房子之間。"),
            language.text(
                "That spot is outside the town that needs a station. Tap your track there.",
                "這裡不在還沒有車站的城鎮，請點那座城鎮裡的軌道。"
            )
        )
    }

    private func newDepot(since before: Tutorial.Snapshot) -> Bool {
        world.stations.contains { $0.isDepot && !before.stations.contains($0.id) }
    }

    private func newFreightYards(since before: Tutorial.Snapshot) -> Int {
        world.freight?.facilities.count { !before.freightYards.contains($0.station) } ?? 0
    }

    private func newBuilding(of kind: PlacedBuildingKind, since before: Tutorial.Snapshot) -> Bool {
        world.placedBuildings.contains { $0.kind == kind && !before.buildings.contains($0.id) }
    }

    /// Whether `station` is one a freight yard can go at that has none
    /// yet: a station with a platform, not a depot.
    static func takesFreightYard(_ station: Station, in world: GameWorld) -> Bool {
        !station.isDepot && !isPassingPlace(station, in: world) && world.freightFacility(at: station.id) == nil
    }

    /// The length of the track built since `before`, in world units.
    private func newTrackLength(since before: Tutorial.Snapshot) -> Int64 {
        world.network.edges.reduce(0) { $0 + (before.edges.contains($1.id) ? 0 : $1.length) }
    }

    private func newStationCount(since before: Tutorial.Snapshot) -> Int {
        world.stations.count { !before.stations.contains($0.id) }
    }

    /// What running line `id` every 10 minutes would take
    /// (``GameWorld/lineStaffingPlan(_:headway:type:cars:)``): `nil` when
    /// its trains cannot run. Worked out once for each world, as the card
    /// reads it many times a frame.
    func tutorialStaffingPlan(_ id: LineID) -> LineStaffingPlan? {
        // Read so that what shows it is redrawn when the world changes.
        _ = world
        if let memo = tutorialStaffingMemo, memo.revision == worldRevision, memo.line == id { return memo.plan }
        let plan = world.lineStaffingPlan(id, headway: 10)
        tutorialStaffingMemo = (worldRevision, id, plan)
        return plan
    }

    // MARK: - Hints

    /// What a step short of cash adds (decision 376): building pauses the
    /// game, and the lines earn while it runs.
    private var faresRemedy: String {
        language.text("Tap \u{25B6}\u{FE0E} and let fares come in.", "按 \u{25B6}\u{FE0E}，讓車資進帳。")
    }

    /// What the card says under the step on screen while it is not done
    /// (decision 188): what is wrong, or what to do next; `nil` when the
    /// step is done, or there is nothing to add to its title.
    public var tutorialHint: TutorialHint? {
        guard let tutorial, !isTutorialStepDone else { return nil }
        let before = tutorial.snapshot(forChapterOf: tutorial.index) ?? Tutorial.Snapshot(of: world)
        let goal = tutorial.step.goal
        // Decision 226, later: Done stands beside the network tool, as in
        // the game; left early, the track and station steps say how back.
        switch goal {
        case .drawTrack, .buildTrack, .chooseNetworkMode, .pickPlatformSite, .buildStation:
            if tool != .network {
                return TutorialHint(language.text("Tap Build to get the network tool back.", "點「建設」拿回路網工具。"))
            }
        default:
            break
        }
        switch goal {
        case .drawTrack, .buildTrack:
            let built = newTrackLength(since: before)
            if let problem = networkPreview?.problem { return TutorialHint(problem, isProblem: true) }
            if let preview = networkPreview, built + preview.length < Tutorial.minimumTrackLength {
                return TutorialHint(language.text(
                    "Make it longer: at least \(Tutorial.minimumTrackMetres) m, so two stations fit.",
                    "再拉長一點：至少 \(Tutorial.minimumTrackMetres) 公尺，才放得下兩座車站。"
                ))
            }
            if built > 0, built < Tutorial.minimumTrackLength {
                return TutorialHint(language.text(
                    "Too short for two stations. Tap farther on from its end, then ✓.",
                    "太短，放不下兩座車站。從尾端再點遠一點，然後按 ✓。"
                ))
            }
            // Decision 390: short of the places the lesson's goal links.
            if built > 0 || networkPreview != nil, !newTrackReachesEveryPlace(since: before), let text = placesToReachText {
                return TutorialHint(text.track)
            }
            if networkStart != nil, networkEnd == nil {
                return TutorialHint(language.text("Now tap where it ends.", "再點終點。"))
            }
            if goal == .buildTrack, networkStart == nil {
                return TutorialHint(language.text("Tap the start and the end again.", "再點一次起點和終點。"))
            }
        case .pickPlatformSite, .buildStation:
            if case .buildStation = goal, let message, message.kind == .failure {
                // Decision 376: short of cash, the fares pay for it.
                let short = networkPlatformCost.map { !world.economy.canAfford($0) } == true
                return TutorialHint(short ? message.text + " " + faresRemedy : message.text, isProblem: true)
            }
            if networkEdgePoint != nil, let id = platformStationID, let station = world.station(id: id) {
                return TutorialHint(language.text(
                    "That spot joins “\(station.name)”. Tap farther along the track.",
                    "這裡會併入「\(station.name)」，請點軌道上更遠的地方。"
                ), isProblem: true)
            }
            // Decision 190: ✓ levels a grade, unless it cannot.
            if let levelling = networkPlatformLevelling, let problem = levelling.problem {
                return TutorialHint(platformGradeText(levelling.grade, problem: problem), isProblem: true)
            }
            if !world.land.isEmpty, let catchment = platformSiteCatchment, catchment.residents + catchment.jobs == 0 {
                return TutorialHint(language.text(
                    "No one lives in the ring, so few would ride. Try nearer the houses.",
                    "圓圈裡沒有人住，搭車的人會很少。往房子近一點試試。"
                ), isProblem: true)
            }
            // Decision 390: away from the places the lesson's goal links.
            if case .pickPlatformSite = goal, platformSitePlanPoint != nil, !platformSiteIsAtAPlace, let text = placesToReachText {
                return TutorialHint(text.site)
            }
            if case .buildStation = goal, networkEdgePoint == nil {
                return TutorialHint(language.text("Tap the track again to pick the spot.", "再點一次軌道，選好位置。"))
            }
        case .pickLineStations:
            if lineDraft.count >= 2, lineDraftRoute == nil {
                return TutorialHint(language.text(
                    "No track joins these stations. Tap Clear in Lines, then pick two on your track.",
                    "這兩站之間沒有軌道相連。按「路線」裡的「清除」，再選你軌道上的兩站。"
                ), isProblem: true)
            }
            if !isPickingLineStops {
                return TutorialHint(language.text("Tap Lines to pick stations again.", "點「路線」再繼續選站。"))
            }
            if lineDraft.count == 1 {
                return TutorialHint(language.text("Now tap the other station.", "再點另一座車站。"))
            }
        case .createLine, .startService:
            if goal == .createLine, lineConfirmation != nil, let shortfall = lineConfirmationPreview?.shortfall {
                return TutorialHint(shortfall + " " + faresRemedy, isProblem: true)
            }
            let line = goal == .createLine ? world.lines.last { !before.lines.contains($0.id) }?.id : selectedLineID
            if let line, tutorialStaffingPlan(line) == nil {
                return TutorialHint(language.text(
                    "Trains can't run: no track joins this line's stations.",
                    "列車開不了：這條路線的車站之間沒有軌道相連。"
                ), isProblem: true)
            }
            if goal == .createLine, lineDraftStops.count < 2 {
                return TutorialHint(language.text("Tap Pick on Map, then two stations.", "按「在地圖上選站」，再點兩座車站。"))
            }
            if goal == .startService, let line, let plan = tutorialStaffingPlan(line), plan.cost > world.economy.balance {
                return TutorialHint(language.text(
                    "Not enough cash: choose a longer time between trains.",
                    "錢不夠：選久一點的班距。"
                ), isProblem: true)
            }
        case .earnFare:
            if world.clock.isPaused {
                return TutorialHint(language.text("Time is paused. Tap \u{25B6}\u{FE0E}.", "時間暫停中，按 \u{25B6}\u{FE0E}。"))
            }
            if let line = selectedLineID ?? world.lines.last?.id, world.serviceLevel(of: line, at: world.clock.now) == nil {
                return TutorialHint(language.text(
                    "Trains start at 06:00. Tap the speed beside \u{25B6}\u{FE0E} to go faster.",
                    "列車早上 6 點才開，點 \u{25B6}\u{FE0E} 旁的倍速可以加快。"
                ))
            }
        case .selectStation:
            if tool != .select {
                return TutorialHint(language.text("Tap Done first, then a station.", "先點「完成」，再點車站。"))
            }
        case .selectPassingLoop:
            if tool != .select {
                return TutorialHint(language.text("Tap Done first, then the passing loop.", "先點「完成」，再點待避線。"))
            }
            if tutorialPlacesToTap.isEmpty {
                return TutorialHint(language.text(
                    "Your line has no passing loop yet. Tap Add a Train in Lines first.",
                    "路線還沒有待避線。先在「路線」按「加開一列車」。"
                ), isProblem: true)
            }
            if selectedStation != nil {
                return TutorialHint(language.text(
                    "That is a station. The passing loop is the one with no platform.",
                    "那是車站。待避線是沒有月台的那一處。"
                ))
            }
        case .selectTrack:
            if tool != .select {
                return TutorialHint(language.text("Tap Done first, then the track.", "先點「完成」，再點軌道。"))
            }
            if tutorialDoubleTrackStretch != nil {
                return TutorialHint(tutorialDoubleTrackPlace)
            }
            if selectedStation != nil || selectedTrainID != nil {
                return TutorialHint(language.text(
                    "Tap the track between two stations, away from the trains.",
                    "點兩站之間的軌道，避開列車。"
                ))
            }
        case .draftDoubleTrack:
            if selectedTrackEdge == nil {
                return TutorialHint(language.text("Tap a stretch of track first.", "先點一段軌道。"))
            }
            if !canDoubleSelectedTrack, trackUpgrade == nil {
                return TutorialHint(language.text(
                    "This stretch is double already. Tap another one.",
                    "這一段已經是複線，請點別段。"
                ), isProblem: true)
            }
        case .buildDoubleTrack:
            // The card's pickers: the side the second track goes on and how far.
            if let problem = trackUpgradePreview?.problem {
                // Decision 378: back to the stretch the guide points at.
                if let stretch = tutorialDoubleTrackStretch, stretch != selectedTrackEdge {
                    return TutorialHint(problem + " " + tutorialDoubleTrackPlace, isProblem: true)
                }
                return TutorialHint(problem + " " + language.text(
                    "Try the other side, This piece only, or another stretch.",
                    "試試另一側、「只有這一段」，或別段軌道。"
                ), isProblem: true)
            }
            if trackUpgrade == nil {
                return TutorialHint(language.text(
                    "Tap a stretch of track, then Make double track.",
                    "點一段軌道，再按「升級為複線」。"
                ))
            }
        case .addTrain, .changeServiceHours, .changeHeadway, .addPattern:
            if !isLinesPanelShown {
                return TutorialHint(language.text("Tap Lines to open your line.", "點「路線」打開你的路線。"))
            }
            if goal == .addTrain, let message, message.kind == .failure {
                return TutorialHint(message.text, isProblem: true)
            }
        case .pickDepotEnd, .buildDepot:
            if tool != .network {
                return TutorialHint(language.text("Tap Build to get the network tool back.", "點「建設」拿回路網工具。"))
            }
            if networkMode != .depot {
                return TutorialHint(language.text("Tap Depot first.", "先點「機廠」。"))
            }
            if let problem = networkDepotPreview?.problem {
                return TutorialHint(problem + " " + language.text("Try another end.", "試試別的盡頭。"), isProblem: true)
            }
            if networkDepotEnd == nil {
                return TutorialHint(language.text("Tap where a track ends.", "點軌道的盡頭。"))
            }
        case .chooseDepot:
            if !isLinesPanelShown {
                return TutorialHint(language.text("Tap Lines to open your line.", "點「路線」打開你的路線。"))
            }
            if let line = selectedLine, world.depotRow(of: line.id, in: language)?.choices.isEmpty != false {
                return TutorialHint(language.text(
                    "This line can't reach the depot. Pick the line that runs past it.",
                    "這條路線到不了機廠，請選經過機廠的路線。"
                ), isProblem: true)
            }
        case .selectStationForFreight:
            if tool != .select {
                return TutorialHint(language.text("Tap Done first, then a station.", "先點「完成」，再點車站。"))
            }
            if let station = selectedStation, world.freightFacility(at: station.id) != nil {
                return TutorialHint(language.text(
                    "That station has a freight yard. Tap another one.",
                    "這一站已經有貨運場，請點另一站。"
                ))
            }
        case .openStationPanel:
            if selectedStation == nil {
                return TutorialHint(language.text("Tap a station first.", "先點一座車站。"))
            }
        case .buildFreightYard:
            if let message, message.kind == .failure {
                return TutorialHint(message.text, isProblem: true)
            }
            if !isStationPanelShown {
                return TutorialHint(language.text("Tap Station… first.", "先點「車站…」。"))
            }
        case .createFreightLine:
            // Two freight yards can leave too little for the train at first.
            if lineConfirmation != nil, let shortfall = lineConfirmationPreview?.shortfall {
                return TutorialHint(shortfall + " " + faresRemedy, isProblem: true)
            }
            if let card = lineConfirmation, !card.isFreight {
                return TutorialHint(language.text("Turn on Freight line on the card.", "在卡片上打開「貨運路線」。"))
            }
            if lineConfirmation == nil, lineDraftStops.count < 2 {
                return TutorialHint(language.text("Tap Lines, then the two freight yards.", "點「路線」，再點兩座貨運場。"))
            }
        case .chooseBuildingKind:
            if tool != .building {
                return TutorialHint(language.text("Tap Build, then Buildings.", "點「建設」，再點「建物」。"))
            }
        case .pickBuildingSite, .putUpBuilding:
            if tool != .building {
                return TutorialHint(language.text("Tap Build, then Buildings.", "點「建設」，再點「建物」。"))
            }
            if case .putUpBuilding(let kind) = goal, buildingKind != kind {
                return TutorialHint(language.text(
                    "Tap \(kind.title(in: .english)) first.", "先點「\(kind.title(in: .traditionalChinese))」。"
                ))
            }
            if let preview = buildingPreview, let problem = preview.problem {
                let short = preview.cost.map { !world.economy.canAfford($0) } == true
                return TutorialHint(short ? problem + " " + faresRemedy : problem, isProblem: true)
            }
            if let message, message.kind == .failure {
                return TutorialHint(message.text, isProblem: true)
            }
        case .acceptRequest:
            if world.cityRequests?.offers.isEmpty != false {
                return TutorialHint(language.text(
                    "No requests yet. Tap \u{25B6}\u{FE0E}: the city asks before long.",
                    "還沒有委託。按 \u{25B6}\u{FE0E}，城市很快就會提出。"
                ))
            }
            if let requests = world.cityRequests, requests.active.count >= requests.capacity {
                return TutorialHint(language.text(
                    "Your hands are full. Finish or give up a request first.",
                    "手上的委託已滿，先完成或放棄一件。"
                ), isProblem: true)
            }
        case .selectStationOffLine:
            if tool != .select {
                return TutorialHint(language.text("Tap Done first, then a station.", "先點「完成」，再點車站。"))
            }
            if let station = selectedStation, !isOffEveryLine(station) {
                return TutorialHint(language.text(
                    "That station is on a line already. Tap the new one.",
                    "這一站已經在路線上，請點新蓋的那一站。"
                ))
            }
        case .addStopToLine:
            if let message, message.kind == .failure {
                return TutorialHint(message.text, isProblem: true)
            }
            if selectedStation.map(isOffEveryLine) != true {
                return TutorialHint(language.text("Tap the new station on the map first.", "先在地圖上點新車站。"))
            }
            if !isLinesPanelShown {
                return TutorialHint(language.text("Tap Lines to open your line.", "點「路線」打開你的路線。"))
            }
        case .read, .chooseTool, .moveMap, .chooseNetworkMode, .startPickingStops, .timeRuns, .openLines, .showAdvanced:
            break
        }
        return nil
    }
}
