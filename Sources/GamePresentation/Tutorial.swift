import GameCore

// The tutorial (Stage C5), after the `Ci/` reference's guided tour of the
// metro game (`TUTORIAL_STEPS`, `startTutorial`, `showTutorialStep`,
// `_tutorialOnAction`, `dismissTutorial`): a card with each step's title
// and text over the game, the controls the step is about outlined, Back,
// Next (Done on the last step) and Skip. The interface is set ahead of C5
// so the app's tutorial screens can be built alongside it; for now it has
// only ``Tutorial/demoSteps``, which C5 replaces with the reference's
// steps rewritten for touch and this app's tools.
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

    /// The tool picker's button for `tool`; `nil` for the grid's tools,
    /// which the app does not offer (``ConstructionTool/networkTools``).
    public init?(tool: ConstructionTool) {
        switch tool {
        case .select: self = .selectTool
        case .network: self = .networkTool
        case .train: self = .trainTool
        case .buildTrack, .buildStation, .removeTrack: return nil
        }
    }
}

/// What a step asks the player to do before Next is available (the
/// reference's `_tutorialStepDoneAction`). Read from the world and the
/// session, never recorded: a goal is met while what it asks for is so.
public enum TutorialGoal: Hashable, Sendable {
    /// Nothing: reading the step is enough.
    case read
    /// Choose `tool` in the tool picker.
    case chooseTool(ConstructionTool)
    /// Build a stretch of track on the network: an edge that was not there
    /// when the step was shown.
    case buildTrack
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
    /// The network's edges when each step was first shown, by step, for
    /// ``TutorialGoal/buildTrack``. Going back to a step keeps its first
    /// snapshot: a new one would hide the track already built for it, and
    /// Next would wait for a second stretch.
    private var edgesWhenFirstShown: [Int: Set<TrackEdgeID>]

    /// The first of `steps`, shown over `world`.
    ///
    /// - Precondition: `steps` is not empty.
    init(steps: [TutorialStep], over world: GameWorld) {
        precondition(!steps.isEmpty, "a tutorial needs a step")
        self.steps = steps
        index = 0
        edgesWhenFirstShown = [:]
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
        if edgesWhenFirstShown[index] == nil {
            edgesWhenFirstShown[index] = Set(world.network.edges.map(\.id))
        }
    }

    /// Whether the player has done what the step on screen asks, in
    /// `world` with `tool` active.
    func isStepDone(in world: GameWorld, tool: ConstructionTool) -> Bool {
        switch step.goal {
        case .read:
            return true
        case .chooseTool(let wanted):
            return tool == wanted
        case .buildTrack:
            let before = edgesWhenFirstShown[index] ?? []
            return world.network.edges.contains { !before.contains($0.id) }
        }
    }
}

extension Tutorial {
    /// Three steps to build the tutorial's screens against until C5 brings
    /// the real ones: one about a control, one about the map and a button,
    /// and one with nothing to outline; the first two wait for the player.
    public static let demoSteps: [TutorialStep] = [
        TutorialStep(
            id: "demo.networkTool",
            targets: [.networkTool],
            goal: .chooseTool(.network),
            title: ("Open the network tool", "打開路網工具"),
            body: (
                "Tap Network: it builds track, platforms and stations.",
                "點「路網」：軌道、月台與車站都用它建造。"
            )
        ),
        TutorialStep(
            id: "demo.buildTrack",
            targets: [.map, .actionButton],
            goal: .buildTrack,
            title: ("Lay a stretch of track", "鋪一段軌道"),
            body: (
                "Tap the map where the track starts, then where it ends, and tap Build Track.",
                "在地圖上點軌道的起點，再點終點，然後按「鋪設軌道」。"
            )
        ),
        TutorialStep(
            id: "demo.end",
            targets: [],
            goal: .read,
            title: ("That's all for now", "示範到此結束"),
            body: (
                "The full tutorial is on its way. Open it again any time from the game menu.",
                "完整的教學之後加入。隨時可以從遊戲選單重新開始。"
            )
        ),
    ]
}
