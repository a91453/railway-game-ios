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

    /// The tool picker's button for `tool`. Optional because the grid's
    /// tools had none until Stage F3c removed them; every tool has one now.
    public init?(tool: ConstructionTool) {
        switch tool {
        case .select: self = .selectTool
        case .network: self = .networkTool
        case .train: self = .trainTool
        case .building: self = .buildingTool
        }
    }
}

/// What a step asks the player to do before Next is available (the
/// reference's `_tutorialStepDoneAction`). Read from the world and the
/// session, never recorded: a goal is met while what it asks for is so.
///
/// The goals that ask for something to be built are about what is new
/// since the step was first shown, so a game that already has track,
/// stations or lines still has the player do each step.
public enum TutorialGoal: Hashable, Sendable {
    /// Nothing: reading the step is enough.
    case read
    /// Choose `tool` in the tool picker.
    case chooseTool(ConstructionTool)
    /// Build a stretch of track on the network: an edge that was not there
    /// when the step was shown.
    case buildTrack
    /// Build a station: one that was not there when the step was shown.
    case buildStation
    /// Create a service line: one that was not there when the step was
    /// shown.
    case createLine
    /// Start a line's service: assign a train that was not assigned when
    /// the step was shown to a line that is set to run trains.
    case startService
    /// Earn a fare (decision 125): a settlement written since the step was
    /// shown took fares in. A free game, which charges none, has nothing
    /// to wait for.
    case earnFare
    /// Change the game's speed, by pausing, resuming or choosing another
    /// (the reference's `speedOrPause`): it differs from what it was when
    /// the step was shown.
    case changeSpeed
    /// Move the map, by pinching, dragging or a zoom button, while the step
    /// is shown (Stage E1). The camera is the map view's, so the view tells
    /// the session (``GameSession/mapDidMove()``); a turned device or a
    /// station centred for the player does not count.
    case moveMap
}

/// One step of the tutorial: its card's title and text in both languages,
/// the controls it is about and what it asks the player to do.
public struct TutorialStep: Hashable, Sendable, Identifiable {
    /// A stable name for the step, never shown.
    public let id: String
    /// The controls to outline; the card goes beside the first. With none,
    /// the card is in the middle of the screen.
    public let targets: [TutorialTarget]
    public let goal: TutorialGoal
    private let englishTitle: String
    private let chineseTitle: String
    private let englishBody: String
    private let chineseBody: String

    init(
        id: String,
        targets: [TutorialTarget],
        goal: TutorialGoal,
        title: (english: String, chinese: String),
        body: (english: String, chinese: String)
    ) {
        self.id = id
        self.targets = targets
        self.goal = goal
        englishTitle = title.english
        chineseTitle = title.chinese
        englishBody = body.english
        chineseBody = body.chinese
    }

    public func title(in language: DisplayLanguage) -> String {
        language.text(englishTitle, chineseTitle)
    }

    public func body(in language: DisplayLanguage) -> String {
        language.text(englishBody, chineseBody)
    }
}

/// The tutorial being shown: its steps and which one is on screen. Moved
/// through ``GameSession``'s tutorial methods.
public struct Tutorial: Hashable, Sendable {
    public let steps: [TutorialStep]
    /// The step on screen, from 0.
    public private(set) var index: Int
    /// What the world had when each step was first shown, by step, for the
    /// goals that ask for something new. Going back to a step keeps its
    /// first snapshot: a new one would hide what was built for it, and
    /// Next would wait for a second one.
    private var whenFirstShown: [Int: Snapshot]
    /// The steps the player moved the map on (``TutorialGoal/moveMap``).
    /// Kept when going back, as the snapshots are.
    private var movedMapOn: Set<Int> = []

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

    /// The step on screen.
    public var step: TutorialStep {
        steps[index]
    }

    /// Whether Back is hidden: the first step has none (the reference's
    /// `tutorial-prev`).
    public var isFirstStep: Bool {
        index == 0
    }

    /// Whether Next reads Done and ends the tutorial (the reference's
    /// `common.done`).
    public var isLastStep: Bool {
        index == steps.count - 1
    }

    /// Shows step `index` over `world`.
    mutating func show(_ index: Int, over world: GameWorld) {
        precondition(steps.indices.contains(index), "show(_:over:) needs one of the steps")
        self.index = index
        if whenFirstShown[index] == nil {
            whenFirstShown[index] = Snapshot(of: world)
        }
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

    /// Whether the player has done what the step on screen asks, in
    /// `world` with `tool` active.
    func isStepDone(in world: GameWorld, tool: ConstructionTool) -> Bool {
        let before = whenFirstShown[index] ?? Snapshot(of: world)
        switch step.goal {
        case .read:
            return true
        case .chooseTool(let wanted):
            return tool == wanted
        case .buildTrack:
            return world.network.edges.contains { !before.edges.contains($0.id) }
        case .buildStation:
            return world.stations.contains { !before.stations.contains($0.id) }
        case .createLine:
            return world.lines.contains { !before.lines.contains($0.id) }
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
        case .changeSpeed:
            return world.clock.speed != before.speed
        case .earnFare:
            return world.accounts.mode == .free
                || CompanyAccounts.income(writtenAfter: before.lastEntry, in: world.accounts.entries, of: [.fareRevenue]) > .zero
        case .moveMap:
            return movedMapOn.contains(index)
        }
    }

    /// What a goal that asks for something new compares the world with.
    private struct Snapshot: Hashable, Sendable {
        let edges: Set<TrackEdgeID>
        let stations: Set<StationID>
        let lines: Set<LineID>
        let assignedTrains: Set<TrainID>
        let speed: GameSpeed
        /// The newest ledger row, which the fares are counted after.
        let lastEntry: LedgerEntry?

        init(of world: GameWorld) {
            edges = Set(world.network.edges.map(\.id))
            stations = Set(world.stations.map(\.id))
            lines = Set(world.lines.map(\.id))
            assignedTrains = Set(world.trains.map(\.id).filter { world.assignedLine(of: $0) != nil })
            speed = world.clock.speed
            lastEntry = world.accounts.entries.last
        }
    }
}

extension Tutorial {
    /// The tutorial's steps: the reference's content steps (`Ci/`
    /// `TUTORIAL_STEPS` 0–1, 4, 7, 10 and 11) rewritten for touch and this
    /// app's tools, in the order a first line is built and run, until its
    /// first fares come in (decision 125). Its mouse and keyboard shortcut
    /// steps (2, 3, 5, 6, 8 and 9) have no touch counterpart.
    ///
    /// The first two steps keep the order the app's UI tests rely on (the
    /// network tool, then a stretch of track). Moving the map follows them
    /// (Stage E1): the reference has no step for it, only its guide's
    /// shortcuts (`guide.metro.shortcut.1`, the mouse wheel zooms), and on
    /// the 16 km map the second station and longer lines need it.
    public static let standardSteps: [TutorialStep] = [
        // Reference step 0, "开始建线": the reference opens its line builder.
        TutorialStep(
            id: "build.network",
            targets: [.networkTool],
            goal: .chooseTool(.network),
            title: ("Start building a line", "開始建線"),
            body: (
                "Tap Network. Track, platforms and stations are all built with it.",
                "點「路網」。軌道、月台和車站都用它來建造。"
            )
        ),
        // Reference steps 0–1, placing stops and nodes so the line bends.
        TutorialStep(
            id: "build.track",
            targets: [.map, .actionButton],
            goal: .buildTrack,
            title: ("Lay the track", "鋪設軌道"),
            body: (
                "In Build mode, tap the map where the track starts, then where it ends, and tap Build Track. "
                    + "The end becomes the next start, so keep tapping to extend the track or bend it. "
                    + "Turns over 90° and stretches under 22 m are refused.",
                "在「鋪設」模式下，點地圖上軌道的起點，再點終點，然後按「鋪設軌道」。"
                    + "終點會變成下一段的起點，可以接著點下去延伸或轉彎。轉彎超過 90 度或短於 22 公尺會被拒絕。"
            )
        ),
        // No reference step: the guide's "缩放地图" (the mouse wheel zooms)
        // and the flight mode's "移动地图" (W/A/S/D pans), for touch.
        TutorialStep(
            id: "map.move",
            targets: [.map, .zoomControls],
            goal: .moveMap,
            title: ("Move around the map", "移動與縮放地圖"),
            body: (
                "The map is about 16 km across. Pinch to zoom in or out and drag with one finger to move it, "
                    + "or use the magnifying glass buttons. Try moving it.",
                "地圖大約 16 公里見方。用兩指開合放大或縮小，用一指拖曳移動地圖，也可以用放大鏡按鈕。試著移動一下。"
            )
        ),
        // Reference step 1, placing a station.
        TutorialStep(
            id: "build.firstStation",
            targets: [.networkModes, .map, .actionButton],
            goal: .buildStation,
            title: ("Build a station", "建造車站"),
            body: (
                "Switch to Platform mode, tap the track where the station goes, and tap Add Platform. "
                    + "A platform away from every other station opens a new one.",
                "切到「月台」模式，點選要設車站的軌道，再按「設置月台」。離其他車站有一段距離的月台會開出一座新車站。"
            )
        ),
        // Reference step 4, "确认建设线路": a line needs at least two stops.
        TutorialStep(
            id: "build.secondStation",
            targets: [.networkModes, .map, .actionButton],
            goal: .buildStation,
            title: ("A line needs two stations", "路線至少要兩座車站"),
            body: (
                "Switch back to Build, extend the track at least 32 m past the first station, then add a platform there too. "
                    + "Passengers travel between stations, so keep them well apart.",
                "切回「鋪設」模式，把軌道延伸到離第一座車站至少 32 公尺以外，再設置一座月台。乘客在車站之間往來，所以兩站要離遠一點。"
            )
        ),
        // Reference step 4, ending the line's construction.
        TutorialStep(
            id: "line.create",
            targets: [.linesButton],
            goal: .createLine,
            title: ("Create the line", "建立路線"),
            body: (
                "Tap Lines, then Pick on Map. Tap the first station on the map, then the other one: the stations the track passes "
                    + "between are found for you. Then tap Create Line. The first stop is where trains start.",
                "點「路線」，再按「在地圖上選站」。在地圖上點第一座車站，再點另一座：軌道沿途經過的車站會自動找出。然後按「建立路線」。第一站是列車出發的地方。"
            )
        ),
        // Reference step 7, "开始列车运营": the reference's lines come with
        // their trains. Decision 125: the lines panel's one step (decision
        // 101) buys, places and assigns them, so the first line runs from
        // the panel the line was made in.
        TutorialStep(
            id: "line.staff",
            targets: [.staffLine, .linesButton],
            goal: .startService,
            title: ("Start service", "開始營運"),
            body: (
                "Your new line is selected in Lines. Choose how often a train should come, then tap Buy … and Start Service: "
                    + "the trains are bought, placed at the first stop and sent out one after another.",
                "新路線已在「路線」裡選好。選擇多久來一班車，再按「購買…列並開始營運」：列車會自動購買、放到第一站，依班距陸續出發。"
            )
        ),
        // Reference step 10, "控制模拟". Decision 125: it follows the line's
        // trains, while building has the game paused (decision 99).
        TutorialStep(
            id: "time.speed",
            targets: [.speedControl],
            goal: .changeSpeed,
            title: ("Control time", "控制時間"),
            body: (
                "Time stops while you build. Press play, or pick a speed from the menu: trains and passengers move only while time passes.",
                "建造時時間會暫停。按繼續，或從選單選倍速：時間流動，列車和乘客才會動。"
            )
        ),
        // No reference step: decision 125 waits for the line's first fares,
        // which the hour's settlement pays into the cash.
        TutorialStep(
            id: "first.fare",
            targets: [.cash, .speedControl],
            goal: .earnFare,
            title: ("Your first fares", "第一筆車資"),
            body: (
                "Let time run. Passengers board at your stations, and at the end of each hour the fares they paid "
                    + "come into the cash at the top. Wait for your first; a faster speed gets there sooner. "
                    + "No one coming? Stations need people living or working within 800 m.",
                "讓時間繼續走。乘客會在你的車站上車，每小時結束時，他們付的車資會進到上方的現金。等第一筆車資進帳吧，倍速調快會更快看到。"
                    + "一直沒有人搭車？車站 800 公尺內要有人住或工作。"
            )
        ),
        // No reference step: its stations carry their ridership in the line
        // builder. Read-only because a managed company's city sets it.
        TutorialStep(
            id: "station.ridership",
            targets: [.map],
            goal: .read,
            title: ("Passengers", "乘客"),
            body: (
                "Select a station on the map, then tap the people icon (Ridership) to see the trips it starts by the hour "
                    + "and the passengers waiting. The more people live and work near your stations, the more ride.",
                "在地圖上選一座車站，點人形圖示（客源），可以看它每小時的進出站人次和候車的乘客。車站附近住和工作的人越多，搭車的人就越多。"
            )
        ),
        // Reference step 11, "导览结束".
        TutorialStep(
            id: "end",
            targets: [.gameMenu],
            goal: .read,
            title: ("That's the tour", "導覽結束"),
            body: (
                "Open the tutorial again any time from the game menu. Happy building!",
                "隨時可以從遊戲選單重新開啟教學。祝建造順利！"
            )
        ),
    ]
}
