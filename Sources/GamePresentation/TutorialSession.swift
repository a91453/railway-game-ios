import GameCore

// The tutorial's controls (Stage C5; see Tutorial.swift): start it, or
// start it again from the first step, from the start screen or the game
// menu; Back, Next (Finish on the last step), Skip and "Skip this step" on
// its card, and the step moving on by itself once done (decision 188).
// None of them changes the world.

extension GameSession {
    /// Shows the tutorial from its first step: the reference's
    /// `startTutorial`, and starting it again from the game menu.
    public func startTutorial() {
        tutorial = Tutorial(steps: Tutorial.steps(over: world), over: world)
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
    /// action step, done, that was not reached by Back.
    public var tutorialAdvancesByItself: Bool {
        guard let tutorial else { return false }
        return tutorial.step.goal != .read && !tutorial.reachedByBack && isTutorialStepDone
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
    /// `dismissTutorial`).
    public func skipTutorial() {
        tutorial = nil
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
            // with it.
            let built = newTrackLength(since: before)
            if built >= Tutorial.minimumTrackLength { return true }
            guard tool == .network, let preview = networkPreview else { return false }
            return preview.problem == nil && preview.cost != nil && built + preview.length >= Tutorial.minimumTrackLength
        case .buildTrack:
            return newTrackLength(since: before) >= Tutorial.minimumTrackLength
        case .chooseNetworkMode(let mode):
            if tool == .network, networkMode == mode { return true }
            return mode == .platform && newStationCount(since: before) >= 1
        case .pickPlatformSite(let count):
            if newStationCount(since: before) >= count { return true }
            return platformSitePlanPoint != nil && networkPlatformStretch != nil && platformStationID == nil && networkPlatformGrade == nil
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
        }
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

    /// What the card says under the step on screen while it is not done
    /// (decision 188): what is wrong, or what to do next; `nil` when the
    /// step is done, or there is nothing to add to its title.
    public var tutorialHint: TutorialHint? {
        guard let tutorial, !isTutorialStepDone else { return nil }
        let before = tutorial.snapshot(forChapterOf: tutorial.index) ?? Tutorial.Snapshot(of: world)
        let goal = tutorial.step.goal
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
            if built > 0 {
                return TutorialHint(language.text(
                    "Too short for two stations. Tap farther on from its end, then ✓.",
                    "太短，放不下兩座車站。從尾端再點遠一點，然後按 ✓。"
                ))
            }
            if networkStart != nil, networkEnd == nil {
                return TutorialHint(language.text("Now tap where it ends.", "再點終點。"))
            }
            if goal == .buildTrack, networkStart == nil {
                return TutorialHint(language.text("Tap the start and the end again.", "再點一次起點和終點。"))
            }
        case .pickPlatformSite, .buildStation:
            if case .buildStation = goal, let message, message.kind == .failure {
                return TutorialHint(message.text, isProblem: true)
            }
            if networkEdgePoint != nil, let id = platformStationID, let station = world.station(id: id) {
                return TutorialHint(language.text(
                    "That spot joins “\(station.name)”. Tap farther along the track.",
                    "這裡會併入「\(station.name)」，請點軌道上更遠的地方。"
                ), isProblem: true)
            }
            if let grade = networkPlatformGrade {
                return TutorialHint(platformGradeText(grade), isProblem: true)
            }
            if !world.land.isEmpty, let catchment = platformSiteCatchment, catchment.residents + catchment.jobs == 0 {
                return TutorialHint(language.text(
                    "No one lives in the ring, so few would ride. Try nearer the houses.",
                    "圓圈裡沒有人住，搭車的人會很少。往房子近一點試試。"
                ), isProblem: true)
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
        case .read, .chooseTool, .moveMap, .chooseNetworkMode, .startPickingStops, .timeRuns:
            break
        }
        return nil
    }
}
