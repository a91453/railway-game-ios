import GameCore

// The tutorial (Stage C5), after the `Ci/` reference's guided tour of the
// metro game (`TUTORIAL_STEPS`, `startTutorial`, `showTutorialStep`,
// `_tutorialOnAction`, `dismissTutorial`): a card with each step's title
// and text over the game, the controls the step is about outlined, Back,
// Next (Done on the last step) and Skip. The steps are the reference's
// content steps rewritten for touch and this app's tools
// (``Tutorial/standardSteps``); its mouse and keyboard shortcut steps are
// not carried over.
//
// Only UI state: the tutorial is never saved, and GameCore knows nothing
// of it. Whether a step is done is read from the world and the session
// (see ``GameSession/isTutorialStepDone``).
//
// Decision 188 redid the steps: one action each, in five chapters, moving
// on by themselves once done (the city-world reference's tutorial mission,
// `LP` in `Railway/city_world_reference/`, and its short help card), with a
// hint that says what is wrong (the transport tutorial's
// `data-tt-confirm-prompt`) and the panel a step needs opened for it (the
// `Ci/` steps' `openUI`).

/// A control a tutorial step is about: the tutorial outlines it and puts
/// its card beside the first one (the reference's `target` and `targets`,
/// CSS selectors there).
///
/// The raw value is the control's stable name: the same in every language
/// and kept across versions. The app marks each control with its target
/// (`tutorialTarget(_:)` in the app); a control that also has an
/// accessibility identifier for the UI tests has the same name there.
public enum TutorialTarget: String, CaseIterable, Hashable, Sendable {
    /// The tool picker's buttons (their accessibility identifiers are
    /// `tool.<tool>` too).
    case selectTool = "tool.select"
    case networkTool = "tool.network"
    case trainTool = "tool.train"
    /// The building tool (city building P0-A, decision 92).
    case buildingTool = "tool.building"
    /// Build, which opens the building tools with the network tool chosen
    /// (decision 114; decision 226, later: the tutorial uses the game's own
    /// controls, so its first step points here, not at the tools).
    case buildEntry = "dock.build"
    /// The train tool's Buy button.
    case buyTrain = "train.buy"
    /// The lines panel's Buy … and Start Service, for a line without
    /// trains (decision 101); the first line's trains in the tutorial
    /// (decision 125).
    case staffLine = "line.staff.start"
    /// The network tool's modes: build, platform, remove.
    case networkModes = "network.modes"
    /// The button that applies the tool: Build Track, Add Platform, Place
    /// or Send a train.
    case actionButton = "panel.action"
    /// The map view, where the player taps.
    case map = "map"
    /// The map's zoom buttons.
    case zoomControls = "map.zoom"
    /// The button that opens the lines panel.
    case linesButton = "hud.lines"
    /// Pause, play and the speed menu (the reference's `#bottombar`).
    case speedControl = "hud.speed"
    /// The cash in the status pill, where fares come in (decision 125).
    case cash = "hud.cash"
    /// The game menu: save, export, back to the start screen.
    case gameMenu = "hud.menu"
    /// The lines panel's Pick on Map, which starts picking a new line's
    /// stations on the map (decision 100).
    case pickLineStops = "line.draft.pick"
    /// The lines panel's Create Line.
    case createLine = "line.draft.create"
    /// The details card at the trailing side (decision 106): never outlined,
    /// but the tutorial's card keeps clear of it, as of a panel beside the
    /// map, whose own controls are not all marked.
    case detailsCard = "panel.details"
    /// A panel beside the map: the lines, a station or the company's figures.
    case sidePanel = "panel.side"
    /// The ✓ of the bubble over the map that builds what the network tool
    /// picked (``GameSession/networkPreview``, a platform's site).
    case mapConfirm = "map.build.confirm"
    /// The details card's Station… button, for a selected station.
    case ridership = "inspector.ridership"
    /// The selected line's fares, costs and why it loses money in the lines
    /// panel (decision 194), there from its first full day.
    case lineLoss = "line.loss"
    /// The fix beside the first reason the line loses money (decision 194,
    /// later fix), there while it loses money for a reason with a fix.
    case lineLossFix = "line.loss.fix"
    /// The selected line's Add a Train in the lines panel (decision 264),
    /// for lesson 3 (decision 376).
    case addTrain = "line.addTrain"
    /// The details card's "Make double track", for picked single track
    /// (decision 247), for lesson 5.
    case doubleTrack = "inspector.track.double"
    /// The lines panel's minutes between trains, for a line that runs.
    case headwayPicker = "line.staff.headway"
    /// The lines panel's button that runs the line at the minutes picked.
    case headwayChange = "line.headway.change"
    /// The lines panel's Advanced switch (decision 196), for lesson 6.
    case advancedSwitch = "lines.advanced"
    /// The selected line's Run All Day, or Run 06:00–24:00 Instead.
    case serviceHours = "line.window"
    /// The Add of the lines panel's stopping pattern, under Advanced.
    case addPattern = "line.pattern.add"
    /// The first depot the selected line can keep its trains at, in the
    /// lines panel (decision 214), for lesson 7.
    case lineDepot = "line.depots"
    /// The station panel's Build Freight Yard (decision 155), for lesson 8.
    case freightYard = "station.freight.build"
    /// The building tool's Hotel, for lesson 9.
    case hotelKind = "building.kind.hotel"
    /// The status bar's city requests (decision 246), for lesson 10.
    case requestsButton = "hud.requests"
    /// The lines panel's "Add … to …", for the station selected on the
    /// map and the selected line (decision 196), for lesson 2 (decision
    /// 390).
    case addSelectedStation = "line.addSelectedStation"
    /// The bus tool (decision 400, 10i-5): no step points at it yet.
    case busTool = "tool.bus"

    /// Whether the control is in the details card, which a step pointing
    /// at it opens (``TutorialStep/usesDetailsCard``).
    public var isInDetailsCard: Bool {
        switch self {
        case .networkModes, .actionButton, .ridership, .doubleTrack, .hotelKind: true
        default: false
        }
    }

    /// The tool picker's button for `tool`. Optional because the grid's
    /// tools had none until Stage F3c removed them; every tool has one now.
    public init?(tool: ConstructionTool) {
        switch tool {
        case .select: self = .selectTool
        case .network: self = .networkTool
        case .train: self = .trainTool
        case .building: self = .buildingTool
        case .bus: self = .busTool
        }
    }
}

/// The parts of the tutorial (decision 188), each a few steps of one
/// thing: the card names the chapter, and a goal that asks for something
/// new compares the world with what it had when the chapter began
/// (``Tutorial/snapshot(forChapterOf:)``).
public enum TutorialChapter: CaseIterable, Hashable, Sendable {
    case track, stations, line, service, passengers

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .track: language.text("Track", "軌道")
        case .stations: language.text("Stations", "車站")
        case .line: language.text("Line", "路線")
        case .service: language.text("Service", "營運")
        case .passengers: language.text("Passengers", "乘客")
        }
    }
}

/// What a step asks the player to do before Next is available (the
/// reference's `_tutorialStepDoneAction`). Read from the world and the
/// session, never recorded: a goal is met while what it asks for is so.
///
/// The goals that ask for something to be built are about what is new
/// since the step's chapter began, so a game that already has track,
/// stations or lines still has the player do each step, and a step done
/// ahead (a fast player, the map's ✓) is not asked for again.
public enum TutorialGoal: Hashable, Sendable {
    /// Nothing: reading the step is enough.
    case read
    /// Choose `tool` in the tool picker.
    case chooseTool(ConstructionTool)
    /// Pick both ends of a stretch of track at least
    /// ``Tutorial/minimumTrackMetres`` long that GameCore would build, or
    /// have built that much.
    case drawTrack
    /// Build at least ``Tutorial/minimumTrackMetres`` of new track.
    case buildTrack
    /// Choose the network tool's mode `mode`; a station built counts for
    /// the platform mode.
    case chooseNetworkMode(NetworkToolMode)
    /// Pick a level place on the track for a new station's platform, or
    /// have built that many new stations.
    case pickPlatformSite(Int)
    /// Have built that many new stations.
    case buildStation(Int)
    /// Start picking a new line's stations on the map (the lines panel
    /// starts it by itself), or have picked one, or made the line.
    case startPickingStops
    /// Pick two stations that track joins, or have made the line.
    case pickLineStations
    /// Create a service line whose trains can run: a new one with a
    /// staffing plan (``GameSession/tutorialStaffingPlan(_:)``).
    case createLine
    /// Start a line's service: assign a train that was not assigned when
    /// the chapter began to a line that is set to run trains.
    case startService
    /// Have time running.
    case timeRuns
    /// Earn a fare (decision 125): a settlement written since the chapter
    /// began took fares in. A free game, which charges none, has nothing
    /// to wait for.
    case earnFare
    /// Select a station with the Select tool.
    case selectStation
    /// Move the map, by pinching, dragging or a zoom button, while the step
    /// is shown (Stage E1). The camera is the map view's, so the view tells
    /// the session (``GameSession/mapDidMove()``); a turned device or a
    /// station centred for the player does not count.
    case moveMap
    /// Open the lines panel. The panel is the app's, so the app tells the
    /// session (``GameSession/linesPanelDidChange(isShown:)``).
    case openLines
    /// Decision 376: put a train that was not on a line when the chapter
    /// began on one (the lines panel's Add a Train).
    case addTrain
    /// Select a passing loop's signal station with the Select tool.
    case selectPassingLoop
    /// Select a stretch of track with the Select tool.
    case selectTrack
    /// Start drafting double track on the picked track, or have built
    /// track since the chapter began.
    case draftDoubleTrack
    /// Build track beside the line's (any new track since the chapter
    /// began).
    case buildDoubleTrack
    /// Turn the lines panel's Advanced switch on. The switch is the
    /// app's, so the app tells the session
    /// (``GameSession/linesAdvancedDidChange(isShown:)``).
    case showAdvanced
    /// Change when a line runs, or the service day's levels.
    case changeServiceHours
    /// Change how many trains a line runs or how far apart.
    case changeHeadway
    /// Give a line one more stopping pattern.
    case addPattern
    /// Decision 376, lessons 7–10. Tap the end of a track with the
    /// network tool's Depot mode.
    case pickDepotEnd
    /// Build a depot (a station flagged as one) since the chapter began.
    case buildDepot
    /// Change the depots of a line.
    case chooseDepot
    /// Select, with the Select tool, a station without a freight yard.
    case selectStationForFreight
    /// Open the station panel. The panel is the app's, so the app tells
    /// the session (``GameSession/stationPanelDidChange(isShown:)``).
    case openStationPanel
    /// Have this many freight yards built since the chapter began.
    case buildFreightYard(Int)
    /// Open a new line that carries freight.
    case createFreightLine
    /// Choose this kind of building in the building tool.
    case chooseBuildingKind(PlacedBuildingKind)
    /// Tap the map with the building tool where it goes.
    case pickBuildingSite
    /// Put up a building of this kind since the chapter began.
    case putUpBuilding(PlacedBuildingKind)
    /// Take on one of the city's requests.
    case acceptRequest
    /// Decision 390, lesson 2: select, with the Select tool, a station no
    /// line calls at, or have added a stop to a line.
    case selectStationOffLine
    /// Decision 390, lesson 2: give a line one more stop since the chapter
    /// began.
    case addStopToLine
}

/// What the session does when a step is first shown, going forward
/// (decision 188), so the step starts from what it needs. None of them
/// changes the world or the message on screen (but `clearSelection` and
/// `selectNewestLine`).
enum TutorialSetup: Hashable, Sendable {
    /// The network tool's Lay mode, the ends picked in another mode
    /// forgotten (a start tapped while the map was moved is kept).
    case layTrack
    /// Forget the ends and the place picked with the network tool.
    case clearPicks
    /// Forget the platform's place that is the station just built.
    case clearLeftoverSite
    /// Forget the stations picked for a new line.
    case clearLineDraft
    /// Let go of the selection.
    case clearSelection
    /// Select the newest line for the lines panel when none is (the `Ci/`
    /// line steps' `openUI` picks the first line with stations).
    case selectNewestLine
    /// Select a line that can keep its trains at a depot, when the one
    /// selected cannot (decision 376, lesson 7).
    case selectDepotLine
}

/// The panel beside the map a step needs, which the app opens or closes
/// when the step is shown (the `Ci/` steps' `openUI`).
public enum TutorialPanel: Hashable, Sendable {
    case lines
    case closed
}

/// What the card says under a step that is not done yet: what is wrong
/// (a problem, which offers to skip the step at once) or what comes next.
public struct TutorialHint: Hashable, Sendable {
    public let text: String
    public let isProblem: Bool

    public init(_ text: String, isProblem: Bool = false) {
        self.text = text
        self.isProblem = isProblem
    }
}

/// One step of the tutorial: its card's title and text in both languages,
/// the controls it is about and what it asks the player to do.
public struct TutorialStep: Hashable, Sendable, Identifiable {
    /// A stable name for the step, never shown.
    public let id: String
    public let chapter: TutorialChapter
    /// The controls to outline; the card goes beside the first. With none,
    /// the card is in the middle of the screen.
    public let targets: [TutorialTarget]
    public let goal: TutorialGoal
    /// What the session does when the step is first shown going forward.
    let setup: [TutorialSetup]
    /// The panel beside the map the app opens or closes for the step;
    /// `nil` leaves it as it is.
    public let panel: TutorialPanel?
    private let englishTitle: String
    private let chineseTitle: String
    private var englishBody: String
    private var chineseBody: String
    /// What the body says of demand by distance (decision 137), left out
    /// over a world without it (``Tutorial/steps(over:)``).
    private var distanceNote: (english: String, chinese: String)?

    init(
        id: String,
        chapter: TutorialChapter,
        targets: [TutorialTarget],
        goal: TutorialGoal,
        setup: [TutorialSetup] = [],
        panel: TutorialPanel? = nil,
        title: (english: String, chinese: String),
        body: (english: String, chinese: String),
        distanceNote: (english: String, chinese: String)? = nil
    ) {
        self.id = id
        self.chapter = chapter
        self.targets = targets
        self.goal = goal
        self.setup = setup
        self.panel = panel
        englishTitle = title.english
        chineseTitle = title.chinese
        englishBody = body.english
        chineseBody = body.chinese
        self.distanceNote = distanceNote
    }

    public static func == (lhs: TutorialStep, rhs: TutorialStep) -> Bool {
        lhs.id == rhs.id && lhs.chapter == rhs.chapter && lhs.targets == rhs.targets && lhs.goal == rhs.goal
            && lhs.setup == rhs.setup && lhs.panel == rhs.panel
            && lhs.englishTitle == rhs.englishTitle && lhs.chineseTitle == rhs.chineseTitle
            && lhs.englishBody == rhs.englishBody && lhs.chineseBody == rhs.chineseBody
            && lhs.distanceNote?.english == rhs.distanceNote?.english && lhs.distanceNote?.chinese == rhs.distanceNote?.chinese
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(chapter)
        hasher.combine(setup)
        hasher.combine(panel)
        hasher.combine(englishBody)
        hasher.combine(distanceNote?.english)
    }

    /// Decision 390: the step in a lesson's own words, its goal, targets,
    /// setup and panel kept, without a distance note.
    func retold(title: (english: String, chinese: String), body: (english: String, chinese: String)) -> TutorialStep {
        TutorialStep(id: id, chapter: chapter, targets: targets, goal: goal, setup: setup, panel: panel, title: title, body: body)
    }

    /// The step without what it says of demand by distance.
    func withoutDistanceNote() -> TutorialStep {
        var step = self
        step.distanceNote = nil
        return step
    }

    public func title(in language: DisplayLanguage) -> String {
        language.text(englishTitle, chineseTitle)
    }

    public func body(in language: DisplayLanguage) -> String {
        guard let note = distanceNote else { return language.text(englishBody, chineseBody) }
        return language.text(englishBody + " " + note.english, chineseBody + note.chinese)
    }

    /// Whether the step points into the details card, which then opens
    /// (decision 188: otherwise the map gets the screen).
    public var usesDetailsCard: Bool {
        targets.contains(where: \.isInDetailsCard)
    }

    /// Whether the step picks a new line's stations on the map, which the
    /// lines panel starts by itself.
    public var picksLineStops: Bool {
        goal == .startPickingStops || goal == .pickLineStations
    }

    /// The button in the lines or the station panel the step asks for,
    /// which the panel scrolls into view.
    public var revealsInPanel: TutorialTarget? {
        targets.first { Self.panelTargets.contains($0) }
    }

    /// The panels' controls a step can ask for.
    private static let panelTargets: Set<TutorialTarget> = [
        .createLine, .staffLine, .lineLoss, .addTrain, .headwayChange, .advancedSwitch, .serviceHours, .addPattern, .lineDepot,
        .freightYard, .addSelectedStation,
    ]

    /// How long the card waits before it offers to skip a step that is not
    /// done (a problem offers it at once): longer for the first fares,
    /// which take a while.
    public var skipOfferSeconds: Int {
        goal == .earnFare ? 90 : 20
    }
}

/// The tutorial being shown: its steps and which one is on screen. Moved
/// through ``GameSession``'s tutorial methods.
public struct Tutorial: Hashable, Sendable {
    public let steps: [TutorialStep]
    /// The step on screen, from 0.
    public private(set) var index: Int
    /// Whether the step on screen was reached by Back: it waits for Next
    /// rather than moving on by itself.
    public private(set) var reachedByBack = false
    /// What the world had when each step was first shown, by step, for the
    /// goals that ask for something new. Going back to a step keeps its
    /// first snapshot: a new one would hide what was built for it, and
    /// Next would wait for a second one.
    private var whenFirstShown: [Int: Snapshot]
    /// The steps the player moved the map on (``TutorialGoal/moveMap``).
    /// Kept when going back, as the snapshots are.
    private var movedMapOn: Set<Int> = []

    /// The shortest first stretch of track (decision 188): two platforms of
    /// 64 m and the gap between two stations fit on 160 m wherever the
    /// first is placed.
    public static let minimumTrackMetres: Int64 = 160

    /// ``minimumTrackMetres`` in world units.
    static var minimumTrackLength: Int64 {
        minimumTrackMetres * WorldCoordinate.unitsPerMetre
    }

    /// How long a done step stays on screen before the next is shown.
    public static let autoAdvanceDelay: Duration = .milliseconds(800)

    /// The first of `steps`, shown over `world`.
    ///
    /// - Precondition: `steps` is not empty.
    init(steps: [TutorialStep], over world: GameWorld) {
        precondition(!steps.isEmpty, "a tutorial needs a step")
        self.steps = steps
        index = 0
        whenFirstShown = [:]
        show(0, over: world)
    }

    /// The tutorial at step `index`, taken up again over a world it has not
    /// watched being built (decision 188, later fix: TestFlight 54.1, the
    /// tutorial skipped and the app closed): the chapters up to the step's
    /// own take everything already in the world as built in them, so a goal
    /// is read from the world as it is, and nothing built before is asked
    /// for again. The chapters after it compare with the world when they
    /// begin, as ever.
    init(steps: [TutorialStep], resumingAt index: Int, over world: GameWorld) {
        precondition(steps.indices.contains(index), "resuming needs one of the steps")
        self.steps = steps
        self.index = index
        whenFirstShown = Dictionary(uniqueKeysWithValues: (0 ... index).map { ($0, Snapshot.resumed(over: world)) })
    }

    /// The step on screen.
    public var step: TutorialStep {
        steps[index]
    }

    /// Whether Back is hidden: the first step has none (the reference's
    /// `tutorial-prev`).
    public var isFirstStep: Bool {
        index == 0
    }

    /// Whether Next reads Finish and ends the tutorial (the reference's
    /// `common.done`).
    public var isLastStep: Bool {
        index == steps.count - 1
    }

    /// Shows step `index` over `world`, by Back or going forward: `true`
    /// when it is shown for the first time.
    @discardableResult
    mutating func show(_ index: Int, over world: GameWorld, byBack: Bool = false) -> Bool {
        precondition(steps.indices.contains(index), "show(_:over:) needs one of the steps")
        self.index = index
        reachedByBack = byBack
        guard whenFirstShown[index] == nil else { return false }
        whenFirstShown[index] = Snapshot(of: world)
        return true
    }

    /// What the goals of step `index` compare the world with: the snapshot
    /// of the earliest step of its chapter that was shown, else its own.
    func snapshot(forChapterOf index: Int) -> Snapshot? {
        snapshot(of: steps[index].chapter) ?? whenFirstShown[index]
    }

    /// The snapshot of the earliest step of `chapter` that was shown.
    func snapshot(of chapter: TutorialChapter) -> Snapshot? {
        steps.indices.first { steps[$0].chapter == chapter && whenFirstShown[$0] != nil }.flatMap { whenFirstShown[$0] }
    }

    /// Whether the player moved the map while step `index` was shown.
    func hasMovedMap(on index: Int) -> Bool {
        movedMapOn.contains(index)
    }

    /// Whether the step on screen asks the player to move the map and they
    /// have not yet.
    var awaitsMapMove: Bool {
        step.goal == .moveMap && !movedMapOn.contains(index)
    }

    /// The player moved the map while the step on screen was shown.
    mutating func noteMapMoved() {
        movedMapOn.insert(index)
    }

    /// What a goal that asks for something new compares the world with.
    struct Snapshot: Hashable, Sendable {
        let edges: Set<TrackEdgeID>
        let stations: Set<StationID>
        let lines: Set<LineID>
        let assignedTrains: Set<TrainID>
        /// The newest ledger row, which the fares are counted after.
        let lastEntry: LedgerEntry?
        /// What each line runs (decision 376), for the goals that ask for
        /// a change to it.
        let services: [LineID: LineService]
        let serviceDay: ServiceDay?
        /// Decision 376, lessons 8–10: the stations with a freight yard,
        /// the company's buildings and the city's requests in hand.
        let freightYards: Set<StationID>
        let buildings: Set<PlacedBuildingID>
        let requestsInHand: Set<Int>
        /// Whether the map had stations (decision 390's hold for the
        /// places to reach). Review H: taken up again, whether the lesson
        /// began with them (every lesson after the first begins with its
        /// line, ``GameWorld/newGame(lesson:)``), though ``stations`` is
        /// empty so that all of them count as new.
        let hadStations: Bool

        /// When a line runs, how many trains how far apart, its
        /// stopping patterns and (decision 390) how many stops it has.
        struct LineService: Hashable, Sendable {
            let window: ServiceWindow
            let trainsInService: TrainsInService
            let targetHeadways: TargetHeadways
            let trains: Int
            let patterns: Int
            let depots: [StationID]
            let stops: Int

            init(_ line: ServiceLine) {
                window = line.window
                trainsInService = line.trainsInService
                targetHeadways = line.targetHeadways
                trains = line.trains.count
                patterns = line.patterns.count
                depots = line.depots
                stops = line.stops.count
            }
        }

        /// A world with nothing built: everything there is counts as new.
        static let nothing = Snapshot()

        /// Taking a tutorial up again over `world` (review G): nothing
        /// built, as ``nothing``, but the lines run as they run now, so a
        /// goal asking for a change to them (the hours, the headway, a
        /// stopping pattern, a depot) is met by a change from here.
        static func resumed(over world: GameWorld) -> Snapshot {
            Snapshot(services: Dictionary(uniqueKeysWithValues: world.lines.map { ($0.id, LineService($0)) }), serviceDay: world.serviceDay,
                     hadStations: world.lesson.map { $0.number > 1 } ?? false)
        }

        private init(services: [LineID: LineService] = [:], serviceDay: ServiceDay? = nil, hadStations: Bool = false) {
            edges = []
            stations = []
            lines = []
            assignedTrains = []
            lastEntry = nil
            self.services = services
            self.serviceDay = serviceDay
            freightYards = []
            buildings = []
            requestsInHand = []
            self.hadStations = hadStations
        }

        init(of world: GameWorld) {
            edges = Set(world.network.edges.map(\.id))
            stations = Set(world.stations.map(\.id))
            lines = Set(world.lines.map(\.id))
            assignedTrains = Set(world.trains.map(\.id).filter { world.assignedLine(of: $0) != nil })
            lastEntry = world.accounts.entries.last
            services = Dictionary(uniqueKeysWithValues: world.lines.map { ($0.id, LineService($0)) })
            serviceDay = world.serviceDay
            freightYards = Set(world.freight?.facilities.map(\.station) ?? [])
            buildings = Set(world.placedBuildings.map(\.id))
            requestsInHand = Set(world.cityRequests?.active.map(\.id) ?? [])
            hadStations = !world.stations.isEmpty
        }
    }
}

extension Tutorial {
    /// ``standardSteps`` for a tutorial over `world`: without what they say
    /// of demand by distance where it is off (a demo, a save from before
    /// decision 137), where short trips do not walk.
    ///
    /// Decision 266: in a lesson, the lesson's guide; under simple rules,
    /// without "Buy … and Start Service".
    static func steps(over world: GameWorld) -> [TutorialStep] {
        var steps = world.lesson.map(\.guide).flatMap { $0.isEmpty ? nil : $0 } ?? standardSteps
        // A line opens with its trains there (decision 264).
        if NewGameRules(of: world) == .simple { steps.removeAll { $0.id == "line.staff" } }
        return world.distanceDemand ? steps : steps.map { $0.withoutDistanceNote() }
    }

    /// The tutorial's steps (decision 188): one action each, in the order a
    /// first line is built and run until its first fares come in (decision
    /// 125), in five chapters. Each title is the instruction itself, and a
    /// body says why in a line. They carry the reference's content steps
    /// (`Ci/` `TUTORIAL_STEPS` 0–1, 4, 7, 10 and 11), rewritten for touch
    /// and this app's tools; its mouse and keyboard shortcut steps (2, 3,
    /// 5, 6, 8 and 9) have no touch counterpart.
    ///
    /// The ids `build.network`, `map.move`, `line.create` and `line.staff`
    /// are kept for the app's UI tests and its `-tutorial-step`.
    public static let standardSteps: [TutorialStep] = [
        // Reference step 0, "开始建线": the reference opens its line builder.
        TutorialStep(
            id: "build.network", chapter: .track,
            // Decision 226, later: Build, as in the game; it opens the
            // building tools with Network chosen.
            targets: [.buildEntry],
            goal: .chooseTool(.network),
            // No setup: the first step changes neither the world nor the clock.
            panel: .closed,
            title: ("Tap Build", "點「建設」"),
            body: (
                "Your goal: a line that earns its first fares. Track and stations are under Build.",
                "目標：蓋一條賺到第一筆車資的路線。軌道和車站都在「建設」裡蓋。"
            )
        ),
        // No reference step: the guide's "缩放地图" (the mouse wheel zooms)
        // and the flight mode's "移动地图" (W/A/S/D pans), for touch. Before
        // the track, so a drag only moves the map.
        TutorialStep(
            id: "map.move", chapter: .track,
            targets: [.zoomControls],
            goal: .moveMap,
            title: ("Zoom out to see the town", "縮小地圖看看城鎮"),
            body: (
                "Pinch or tap − to zoom, drag to move. Blocks: green homes, blue shops, orange offices.",
                "兩指或按「−」縮放，拖曳移動。方塊是建物：綠住宅、藍商業、橘辦公。"
            )
        ),
        // Reference steps 0–1, placing stops and nodes so the line bends.
        TutorialStep(
            id: "track.draw", chapter: .track,
            targets: [.map],
            goal: .drawTrack,
            setup: [.layTrack],
            title: ("Tap the start, then the end", "點起點，再點終點"),
            body: (
                "Lay it across the town, at least \(minimumTrackMetres) m, so two stations fit.",
                "讓軌道穿過城鎮，至少 \(minimumTrackMetres) 公尺，才放得下兩座車站。"
            )
        ),
        TutorialStep(
            id: "track.build", chapter: .track,
            targets: [.mapConfirm],
            goal: .buildTrack,
            title: ("Tap ✓ to build the track", "按 ✓ 蓋好軌道"),
            body: (
                "The price is on the button. Time stays paused while you build.",
                "按鈕上就是價錢。建造時時間會先暫停。"
            )
        ),
        // Reference step 1, placing a station.
        TutorialStep(
            id: "station.mode", chapter: .stations,
            targets: [.networkModes],
            goal: .chooseNetworkMode(.platform),
            setup: [.clearPicks],
            title: ("Tap Platform", "點「月台」"),
            body: (
                "A station is a platform on your track.",
                "車站就是蓋在軌道上的月台。"
            )
        ),
        TutorialStep(
            id: "station.first.site", chapter: .stations,
            targets: [.map],
            goal: .pickPlatformSite(1),
            title: ("Tap your track near one end", "點軌道靠近一端的地方"),
            body: (
                "Pick a spot in the town. The ring shows who lives within a walk.",
                "選在城鎮裡。圓圈裡是走路就能到站的居民。"
            )
        ),
        TutorialStep(
            id: "station.first.build", chapter: .stations,
            targets: [.mapConfirm],
            goal: .buildStation(1),
            title: ("Tap ✓ to build the station", "按 ✓ 蓋車站"),
            body: (
                "The more people in the ring, the more riders.",
                "圓圈裡的人越多，搭車的人越多。"
            )
        ),
        // Reference step 4, "确认建设线路": a line needs at least two stops.
        TutorialStep(
            id: "station.second.site", chapter: .stations,
            targets: [.map],
            goal: .pickPlatformSite(2),
            setup: [.clearLeftoverSite],
            title: ("Tap the track near the other end", "點軌道另一端的地方"),
            body: (
                "A line needs two stations.",
                "一條路線至少要兩座車站。"
            ),
            distanceNote: (
                "Farther apart, up to 2 km, more people ride.",
                "兩站離得越遠（最多 2 公里），搭車的人越多。"
            )
        ),
        TutorialStep(
            id: "station.second.build", chapter: .stations,
            targets: [.mapConfirm],
            goal: .buildStation(2),
            title: ("Tap ✓ for the second station", "按 ✓ 蓋第二座車站"),
            body: (
                "Two stations: enough for a line.",
                "兩座車站，就能開一條路線。"
            )
        ),
        // Reference step 10, "控制模拟". Leaving the building tools resumes
        // the clock the network tool paused (decision 99). Decision 226,
        // later: before the line, as in the game, where Lines is beside
        // Build only once the building tools are put away (on a phone held
        // sideways they take Lines' place in the column).
        TutorialStep(
            id: "build.done", chapter: .stations,
            targets: [.selectTool],
            goal: .chooseTool(.select),
            panel: .closed,
            title: ("Tap Done to stop building", "點「完成」結束建造"),
            body: (
                "Time runs again. Next, a line joins your two stations.",
                "時間會繼續走。接著用路線把兩站連起來。"
            )
        ),
        // Reference step 4, ending the line's construction. The lines
        // panel starts picking by itself once open (its `openUI`).
        TutorialStep(
            id: "line.open", chapter: .line,
            targets: [.linesButton],
            goal: .startPickingStops,
            setup: [.clearPicks, .clearLineDraft],
            title: ("Tap Lines", "點「路線」"),
            body: (
                "A line tells trains where to stop. It opens on the right.",
                "路線決定列車停哪些站，會在右邊打開。"
            )
        ),
        TutorialStep(
            id: "line.stations", chapter: .line,
            targets: [.map],
            goal: .pickLineStations,
            panel: .lines,
            title: ("Tap one station, then the other", "點一座車站，再點另一座"),
            body: (
                "Trains start from the first. Stations the track passes are added for you.",
                "列車從先點的站出發，沿途的車站會自動加入。"
            )
        ),
        // Decision 100, later: the line is made on the map, by the ✓
        // beside its last station; the panel's Create Line does the same.
        TutorialStep(
            id: "line.create", chapter: .line,
            targets: [.mapConfirm],
            goal: .createLine,
            panel: .lines,
            // Decision 390: the title names both taps; the card's Open
            // Line makes the line, not the ✓ alone.
            title: ("Tap ✓, then Open Line", "按 ✓，再按「開通路線」"),
            // Decision 303: the ✓ raises the line's card; its Open Line
            // makes the line.
            body: (
                "The card shows the line's hours and trains.",
                "卡片會列出路線的營運時間與列車。"
            )
        ),
        // Reference step 7, "开始列车运营": the reference's lines come with
        // their trains. Decision 125: the lines panel's one step (decision
        // 101) buys, places and assigns them.
        TutorialStep(
            id: "line.staff", chapter: .service,
            targets: [.staffLine],
            goal: .startService,
            panel: .lines,
            title: ("Tap Buy … and Start Service", "按「購買…列並開始營運」"),
            body: (
                "Pick how often a train comes. The trains are bought and set off in turn.",
                "選多久來一班車，列車會自動買好、依序發車。"
            )
        ),
        // Passed while time runs, as it usually does once Done set it
        // running before the line (decision 226, later).
        TutorialStep(
            id: "time.play", chapter: .service,
            targets: [.speedControl],
            goal: .timeRuns,
            // The lines panel closes, as Done closed it when it came after
            // the line (decision 226, later), so the next steps show the map
            // and the cash and Lines is tapped again to read the line's card.
            panel: .closed,
            title: ("Tap \u{25B6}\u{FE0E} to run time", "按 \u{25B6}\u{FE0E} 讓時間走"),
            body: (
                "Trains and passengers move only while time runs.",
                "時間在走，列車和乘客才會動。"
            )
        ),
        // No reference step: decision 125 waits for the line's first fares,
        // which the hour's settlement pays into the cash.
        TutorialStep(
            id: "first.fare", chapter: .service,
            targets: [.cash, .speedControl],
            goal: .earnFare,
            // Closed here too: the time step is usually passed over.
            panel: .closed,
            title: ("Wait for your first fares", "等第一筆車資進帳"),
            body: (
                "Trains run from 06:00. Fares come in each hour; a faster speed gets there sooner.",
                "列車早上 6 點開始跑，車資每小時進帳，調快倍速更快。"
            )
        ),
        // Reference steps 7–9 open the line's panel at its first line
        // (`openUI`) and outline the panel and one row. Its panel has no
        // takings to read; decision 194's card does (decision 188, later
        // fix: the lines panel's card was not taught).
        TutorialStep(
            id: "line.card.open", chapter: .service,
            targets: [.linesButton],
            goal: .openLines,
            setup: [.selectNewestLine],
            title: ("Tap Lines to check your line", "點「路線」看營運收支"),
            body: (
                "See what your line earns and what it costs to run.",
                "看看這條線賺多少、營運要花多少。"
            )
        ),
        // The card is there from the line's first full day; before that
        // the panel is outlined, and the body says when it comes.
        TutorialStep(
            id: "line.card.read", chapter: .service,
            targets: [.lineLoss, .lineLossFix, .sidePanel],
            goal: .read,
            panel: .lines,
            title: ("Read your line's card", "看懂路線卡"),
            body: (
                "Each day: fares against costs. A losing line says why, with a fix beside each reason.",
                "每天結算車資和成本；虧錢時寫出原因，原因旁的按鈕一鍵修正。"
            )
        ),
        // No reference step: its stations carry their ridership in the line
        // builder. Read-only because a managed company's city sets it.
        TutorialStep(
            id: "station.select", chapter: .passengers,
            targets: [.map],
            goal: .selectStation,
            setup: [.clearSelection],
            panel: .closed,
            title: ("Tap one of your stations", "點你的一座車站"),
            body: (
                "See who rides from it.",
                "看看有誰從這裡搭車。"
            )
        ),
        TutorialStep(
            id: "station.ridership", chapter: .passengers,
            targets: [.ridership, .sidePanel],
            goal: .read,
            title: ("Tap Station… to see who rides", "點「車站…」看誰在搭車"),
            body: (
                "Trips by the hour and who is waiting. More homes and jobs nearby, more riders.",
                "每小時的進出站人次和候車人數。附近住的、上班的人越多，搭車越多。"
            )
        ),
        // Reference step 11, "导览结束".
        TutorialStep(
            id: "end", chapter: .passengers,
            targets: [.gameMenu],
            goal: .read,
            title: ("That's the tour", "導覽結束"),
            body: (
                "Replay it from the game menu. Next, extend your line to the next town.",
                "隨時可以從遊戲選單重看。下一步，把路線延伸到下一個城鎮吧！"
            )
        ),
    ]
}
