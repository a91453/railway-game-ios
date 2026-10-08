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
    /// Put a train on the track: one that was not on it when the step was
    /// shown.
    case placeTrain
    /// Start a line's service: assign a train that was not assigned when
    /// the step was shown to a line that is set to run trains.
    case startService
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
        case .placeTrain:
            return world.trains.contains { $0.position != nil && !before.placedTrains.contains($0.id) }
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
        case .moveMap:
            return movedMapOn.contains(index)
        }
    }

    /// What a goal that asks for something new compares the world with.
    private struct Snapshot: Hashable, Sendable {
        let edges: Set<TrackEdgeID>
        let stations: Set<StationID>
        let lines: Set<LineID>
        let placedTrains: Set<TrainID>
        let assignedTrains: Set<TrainID>
        let speed: GameSpeed

        init(of world: GameWorld) {
            edges = Set(world.network.edges.map(\.id))
            stations = Set(world.stations.map(\.id))
            lines = Set(world.lines.map(\.id))
            placedTrains = Set(world.trains.filter { $0.position != nil }.map(\.id))
            assignedTrains = Set(world.trains.map(\.id).filter { world.assignedLine(of: $0) != nil })
            speed = world.clock.speed
        }
    }
}

extension Tutorial {
    /// The tutorial's steps: the reference's content steps (`Ci/`
    /// `TUTORIAL_STEPS` 0–1, 4, 7, 10 and 11) rewritten for touch and this
    /// app's tools, in the order a first line is built and run. Its mouse
    /// and keyboard shortcut steps (2, 3, 5, 6, 8 and 9) have no touch
    /// counterpart.
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
                "Tap Lines. Select a station on the map and tap Add Selected Station, then the other one, then Create Line. "
                    + "The first stop is where trains start.",
                "點「路線」。在地圖上選取一座車站，按「加入選取的車站」，再加入另一座，然後按「建立路線」。第一站是列車出發的地方。"
            )
        ),
        // No reference step: the reference's lines come with their trains.
        TutorialStep(
            id: "train.place",
            targets: [.trainTool, .buyTrain, .actionButton],
            goal: .placeTrain,
            title: ("Buy a train and place it", "購買並放置列車"),
            body: (
                "Tap Train, then Buy. Select the line's first station on the map and tap Place … Here: "
                    + "the train waits there until the line sends it out.",
                "點「列車」，再按「購買」。在地圖上選取路線的第一站，按「把…放在這裡」，列車會在那裡等路線派它出發。"
            )
        ),
        // Reference step 7, "开始列车运营": the trains in service per period.
        TutorialStep(
            id: "line.service",
            targets: [.linesButton],
            goal: .startService,
            title: ("Start service", "開始營運"),
            body: (
                "Open Lines, pick your line and tap Assign … Here to give it your train. A line that runs no trains yet "
                    + "then runs it at every time of day; change how many it runs for peak, off-peak or low there. "
                    + "It leaves once it has waited at the first stop.",
                "打開「路線」，選你的路線，按「把…指派到這裡」把列車交給它。還沒有上線列車的路線，"
                    + "會在各時段都讓這列車上線；尖峰、離峰、低峰的上線列數可以在那裡調整。它在第一站等候後就會出發。"
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
                    + "and the passengers waiting. The fares they pay are your income; the cash in the top bar follows.",
                "在地圖上選一座車站，點人形圖示（客源），可以看它每小時的進出站人次和候車的乘客。乘客付的票價是你的收入，上方的現金會跟著變。"
            )
        ),
        // Reference step 10, "控制模拟".
        TutorialStep(
            id: "time.speed",
            targets: [.speedControl],
            goal: .changeSpeed,
            title: ("Control time", "控制時間"),
            body: (
                "Pause or resume, and pick a speed from the menu. Trains and passengers move only while time passes. Try changing it.",
                "用暫停／繼續，並從選單選倍速。時間流動，列車和乘客才會動。試著改變一下。"
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
