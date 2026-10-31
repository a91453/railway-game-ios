import GameCore

// Decision 508 (98.1, a player: "I opened Lines and there was nothing to
// press"; another could not find Build): a player who skipped the
// tutorial is shown, before the first line, what is missing and the one
// control that makes it. Three parts, worked out here and drawn by the
// app:
//
// - the lines panel, with no line, says at its top what is missing (two
//   stations, or a line through them) with a button that takes the player
//   there (``FirstLineNeed``);
// - the station master's first word in a game with no line offers the
//   five-minute tutorial or "I'll do it myself" (``FirstLineGuide/offers``);
// - after "I'll do it myself", each of the station master's first-line
//   steps names the control on screen, its icon and its name, and the
//   tutorial's ring lights it (``FirstLineGuide/hint``).
//
// The reference has none of it: its tour (`Simulator/` and
// `city_world_reference`'s objective line) is the tutorial, which this
// game already has.

/// What a game with no line still needs for its first one, said at the
/// top of the lines panel (decision 508).
public enum FirstLineNeed: Equatable, Sendable {
    /// Fewer than two stations: `stations` of them (0 or 1).
    case stations(Int)
    /// Two stations or more, and no line.
    case line

    /// What `world` needs, or `nil` once it has a line.
    public init?(world: GameWorld) {
        guard world.lines.isEmpty else { return nil }
        self = world.stations.count < 2 ? .stations(world.stations.count) : .line
    }

    /// Where the card's button takes the player.
    public enum Action: Equatable, Sendable {
        /// Closes the panel and opens Build, its track tools chosen.
        case build
        /// Starts picking the new line's stations on the map.
        case pickStations
    }

    public var action: Action {
        switch self {
        case .stations: .build
        case .line: .pickStations
        }
    }

    /// The card's one sentence: what is missing.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .stations(0): language.text("First, build two stations", "先蓋兩座車站")
        case .stations: language.text("Build one more station", "再蓋一座車站")
        case .line: language.text("Join your stations into a line", "把車站連成路線")
        }
    }

    /// How, under the title.
    public func detail(in language: DisplayLanguage) -> String {
        switch self {
        case .stations(0):
            language.text(
                "A line runs between stations. Lay track under Build, then put a station at each end.",
                "路線要在車站之間跑。在「建設」裡鋪軌道，兩端各蓋一座車站。"
            )
        case .stations:
            language.text(
                "A line needs two stations. Add another along your track under Build.",
                "一條路線要兩座車站。在「建設」裡沿著軌道再蓋一座。"
            )
        case .line:
            language.text(
                "Tap one station on the map, then the other. The stations between are added for you.",
                "在地圖上點一座車站，再點另一座，中間的車站會自動加入。"
            )
        }
    }

    /// The button's name.
    public func buttonTitle(in language: DisplayLanguage) -> String {
        switch action {
        case .build: language.text("Go to Build", "到「建設」")
        case .pickStations: language.text("Pick on Map", "在地圖上選站")
        }
    }

    /// The button's icon: the control it stands for.
    public var buttonSymbol: String {
        switch action {
        case .build: FirstLineGuide.buildSymbol
        case .pickStations: "hand.tap"
        }
    }
}

/// How a player who skipped the tutorial is led to the first line
/// (decision 508): what they chose, and the step the station master names.
public enum FirstLineGuide {
    /// What the player chose when the station master offered the tutorial,
    /// kept on the device (``LauncherPreferences/firstLineGuide``).
    public enum Choice: String, Codable, Equatable, Sendable {
        /// The five-minute tutorial (lesson 1).
        case tutorial
        /// "I'll do it myself": each step names its control.
        case selfGuided
    }

    /// The dock's Build, as drawn (``BuildEntry`` in the app).
    public static let buildSymbol = "hammer.fill"
    /// The dock's Lines, as drawn.
    public static let linesSymbol = "point.3.connected.trianglepath.dotted"

    /// Whether the station master offers the tutorial: a free game, not
    /// the tutorial or a lesson or a challenge, with no line yet, for a
    /// player who has not finished the tutorial or answered before.
    @MainActor public static func offers(in session: GameSession, tutorialCompleted: Bool, choice: Choice?) -> Bool {
        choice == nil && !tutorialCompleted && isFreeFirstLine(in: session)
    }

    /// The step the station master names after "I'll do it myself", or
    /// `nil`: not chosen, or a line made.
    @MainActor public static func hint(in session: GameSession, choice: Choice?) -> Hint? {
        guard choice == .selfGuided, isFreeFirstLine(in: session) else { return nil }
        return hint(world: session.world, tool: session.tool, networkMode: session.networkMode,
                    linesPanelShown: session.isLinesPanelShown, picking: session.isPickingLineStops)
    }

    /// No line yet in a game of the player's own: not the tutorial, a
    /// lesson or a challenge, which say their own steps.
    @MainActor private static func isFreeFirstLine(in session: GameSession) -> Bool {
        session.world.lines.isEmpty && session.tutorial == nil && session.world.lesson == nil
            && session.world.scenario == nil
    }

    /// One step: what to do, and the control to do it with.
    public struct Hint: Equatable, Sendable {
        /// The control the ring lights, or `nil` when the step is done on
        /// the map.
        public let target: TutorialTarget?
        /// The control's icon, shown before the words, or `nil`.
        public let symbol: String?
        let english: String
        let chinese: String

        public func text(in language: DisplayLanguage) -> String {
            language.text(english, chinese)
        }
    }

    /// The next step of the first line, from what is built and what is on
    /// screen: Build (or the track tools) for the track and the stations,
    /// Done and Lines for the line.
    static func hint(world: GameWorld, tool: ConstructionTool, networkMode: NetworkToolMode,
                     linesPanelShown: Bool, picking: Bool) -> Hint {
        let building = tool != .select
        if world.network.edges.isEmpty || world.stations.count < 2 {
            let track = world.network.edges.isEmpty
            if !building {
                return track
                    ? Hint(target: .buildEntry, symbol: buildSymbol,
                           english: "Tap the hammer, Build, at the bottom left to lay track.",
                           chinese: "點左下的鐵鎚「建設」，開始鋪軌道。")
                    : Hint(target: .buildEntry, symbol: buildSymbol,
                           english: "Tap the hammer, Build, at the bottom left to add a station.",
                           chinese: "點左下的鐵鎚「建設」，在軌道上蓋車站。")
            }
            if tool != .network {
                return Hint(target: .networkTool, symbol: nil,
                            english: "Tap Network in the tools on the left.",
                            chinese: "點左邊工具裡的「路網」。")
            }
            if track {
                if networkMode != .build {
                    return Hint(target: .networkModes, symbol: nil,
                                english: "Tap Lay, then tap the track's start and its end on the map.",
                                chinese: "點「鋪設」，再在地圖上點軌道的起點和終點。")
                }
                return Hint(target: nil, symbol: nil,
                            english: "Tap the track's start on the map, then its end, then tap ✓.",
                            chinese: "在地圖上點軌道的起點，再點終點，然後按 ✓。")
            }
            if networkMode != .platform {
                return Hint(target: .networkModes, symbol: nil,
                            english: "Tap Station, then tap your track where the station goes.",
                            chinese: "點「車站」，再點軌道上要蓋車站的地方。")
            }
            return world.stations.isEmpty
                ? Hint(target: nil, symbol: nil,
                       english: "Tap your track near one end, then tap ✓ to build the station.",
                       chinese: "點軌道靠近一端的地方，再按 ✓ 蓋車站。")
                : Hint(target: nil, symbol: nil,
                       english: "Tap the track near the other end, then tap ✓ for the second station.",
                       chinese: "點軌道另一端的地方，再按 ✓ 蓋第二座車站。")
        }
        if building {
            return Hint(target: .selectTool, symbol: "xmark",
                        english: "Two stations. Tap Done at the bottom left to stop building.",
                        chinese: "兩座車站好了。點左下的「完成」結束建造。")
        }
        if !linesPanelShown {
            return Hint(target: .linesButton, symbol: linesSymbol,
                        english: "Tap Lines at the bottom left to make a line.",
                        chinese: "點左下的「路線」，開一條路線。")
        }
        if !picking {
            return Hint(target: .pickLineStops, symbol: "hand.tap",
                        english: "Tap Pick on Map, then tap your two stations.",
                        chinese: "按「在地圖上選站」，再點你的兩座車站。")
        }
        return Hint(target: nil, symbol: nil,
                    english: "Tap one station on the map, then the other, then tap ✓.",
                    chinese: "在地圖上點一座車站，再點另一座，然後按 ✓。")
    }

    /// The station master's offer, in a sentence.
    public static func offerText(in language: DisplayLanguage) -> String {
        language.text(
            "Your first railway? I can show you how in five minutes, or you can find your own way.",
            "第一次蓋鐵路嗎？我可以帶你做 5 分鐘教學，你也可以自己來。"
        )
    }

    public static func tutorialButtonTitle(in language: DisplayLanguage) -> String {
        language.text("Show Me (5 min)", "跟我做 5 分鐘教學")
    }

    public static func selfGuidedButtonTitle(in language: DisplayLanguage) -> String {
        language.text("I'll Do It Myself", "我自己來")
    }
}

extension GameSession {
    /// Decision 508: what the lines panel says is missing at its top, or
    /// `nil`: a line made, or one being picked, or the tutorial leading.
    public var linesPanelFirstLineNeed: FirstLineNeed? {
        guard tutorial == nil, lineDraft.isEmpty, !isPickingLineStops else { return nil }
        return FirstLineNeed(world: world)
    }
}

extension StationMasterAdvice {
    /// Whether it is a step of the first line, the ones a named step
    /// replaces after "I'll do it myself" (decision 508).
    public var isFirstLineStep: Bool {
        switch self {
        case .buildTrack, .buildStation, .buildSecondStation, .createLine: true
        default: false
        }
    }
}
