import GameCore
import GamePresentation
import SwiftUI
import UniformTypeIdentifiers

/// Cash (which opens the economy panel), game time, speed controls and the
/// game menu (Stage C4: save, export, back to the start screen), in the
/// status pill at the top of the screen (``ContentView``, decision 106);
/// the lines are in the dock. Everything shown is read from the world, so
/// it updates as soon as a command or a tick changes it. Its controls have
/// no backgrounds of their own: the pill it sits in is glass.
struct HUDView: View {
    let session: GameSession
    let launcher: GameLauncher
    @Environment(GameScreenState.self) private var screen
    /// Whether the forecast of the next days is open (decision 175).
    @State private var showsForecast = false
    /// Decision 184: whether Save As's name is being asked, and the name.
    @State private var namingSave = false
    @State private var saveName = ""
    /// Decision 192: the autosaves to go back to, read and labelled when
    /// the player asks, so the ticks leave the question as it was asked.
    @State private var goBackChoices: [GoBackChoice] = []
    @State private var choosingGoBack = false

    var body: some View {
        // One row, as wide as what it shows, when it fits; otherwise cash
        // and time stack; with the largest text the time gets a row of its
        // own rather than being cut short ("Day 2 · 07…"), and the cash is
        // never cut short ("$ 3,0…").
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                cash
                time
                SpeedControl(session: session)
                ViewingReadout(session: session)
                newsBell
                gameMenu
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    cash
                    time
                }
                SpeedControl(session: session)
                ViewingReadout(session: session)
                newsBell
                gameMenu
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    cash
                    SpeedControl(session: session)
                    newsBell
                    gameMenu
                }
                time
                    .minimumScaleFactor(0.75)
                ViewingReadout(session: session)
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .alert(Text(verbatim: session.language.text("Save As", "另存新檔")), isPresented: $namingSave) {
            TextField(text: $saveName) {
                Text(verbatim: session.language.text("Name", "名稱"))
            }
            .accessibilityIdentifier("menu.saveGameAs.name")
            Button(role: .cancel) {} label: {
                Text(verbatim: session.language.text("Cancel", "取消"))
            }
            Button {
                launcher.saveCurrentGame(named: saveName)
            } label: {
                Text(verbatim: session.language.text("Save", "儲存"))
            }
            .accessibilityIdentifier("menu.saveGameAs.confirm")
        } message: {
            Text(verbatim: session.language.text(
                "A name for this save, to find it in Saved Games.",
                "為這個存檔取個名字，方便在「存檔」裡找到。"
            ))
        }
        .confirmationDialog(
            Text(verbatim: session.language.text("Go Back to an Autosave?", "回到之前的自動存檔？")),
            isPresented: $choosingGoBack,
            titleVisibility: .visible
        ) {
            ForEach(goBackChoices) { choice in
                Button {
                    launcher.load(choice.entry)
                } label: {
                    Text(verbatim: choice.label)
                }
                .accessibilityIdentifier("menu.goBack.\(choice.entry.id)")
            }
            Button(role: .cancel) {} label: {
                Text(verbatim: session.language.text("Cancel", "取消"))
            }
        } message: {
            Text(verbatim: session.language.text(
                "The game as it is now is kept as an autosave, so you can come back to it.",
                "現在的進度會先存成一份自動存檔，之後還能回來。"
            ))
        }
    }

    /// Reads the autosaves to go back to (decision 192) and asks which.
    private func askGoBack() {
        let language = session.language
        Task {
            let autosaves = await launcher.autosavesToGoBackTo()
            let now = Date()
            goBackChoices = autosaves.map { entry in
                let ago = entry.savedAgoText(at: now, in: language) ?? ""
                let date = entry.summary?.dateAndFundsText(in: language) ?? ""
                return GoBackChoice(entry: entry, label: date.isEmpty ? ago : "\(ago) · \(date)")
            }
            // With none, the launcher says so on the status line.
            choosingGoBack = !goBackChoices.isEmpty
        }
    }

    /// The game menu, built from what it shows rather than from the world,
    /// so the ticks of a running game leave it alone while it is open.
    private var gameMenu: some View {
        GameMenu(
            session: session,
            launcher: launcher,
            screen: screen,
            showsGoals: session.world.scenario != nil || session.world.hasCityRequests,
            showsTourism: session.world.hasTourism,
            language: session.language,
            askSaveName: {
                saveName = ""
                namingSave = true
            },
            askGoBack: askGoBack
        )
        .equatable()
    }

    /// The balance in dollars; it opens the economy panel.
    private var cash: some View {
        let text = session.world.economy.balance.moneyText
        let isNegative = session.world.economy.balance < .zero
        return Button {
            screen.panel = .economy
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "banknote.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isNegative ? Theme.error : Theme.success)
                Text(text)
                    .foregroundStyle(isNegative ? Theme.error : Theme.textPrimary)
                // Decision 175: a challenge that is lost to the red says how
                // long is left.
                if let days = session.world.insolvencyCountdown {
                    Text(verbatim: insolvencyCountdownText(days, in: session.language))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.error))
                        .accessibilityIdentifier("hud.insolvency")
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Decision 117: what just came in, under the cash.
        .overlay(alignment: .bottom) {
            IncomeFloat(pulse: session.incomePulse)
        }
        .accessibilityLabel("Cash \(text)")
        .accessibilityHint("Shows fares, running costs and the ledger.")
        // Decision 125: the tutorial's first fares come in here.
        .tutorialTarget(.cash)
    }

    /// The date and time (decision 175), today's weather and holiday; it
    /// opens the forecast of the next days.
    private var time: some View {
        let language = session.language
        let text = session.world.clock.calendarText(in: language)
        return Button {
            showsForecast = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                Text(text)
                    .foregroundStyle(Theme.textPrimary)
                if let symbol = session.world.todaySymbol() {
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .accessibilityIdentifier("hud.weather")
                }
                if let holiday = session.world.todayHoliday() {
                    Text(verbatim: holiday.title(in: language))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.warning.opacity(0.35)))
                        .accessibilityIdentifier("hud.holiday")
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsForecast) {
            ForecastView(session: session)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Game time \(text)")
        .accessibilityHint(Text(verbatim: language.text("Shows the forecast of the next seven days.", "顯示未來七天的預報。")))
        .accessibilityIdentifier("hud.time")
    }

    /// The news log's bell (decision 175), with the number of items not
    /// yet seen.
    private var newsBell: some View {
        let unread = session.news.unread
        let language = session.language
        return Button {
            screen.panel = .news
        } label: {
            Image(systemName: unread > 0 ? "bell.badge.fill" : "bell.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(unread > 0 ? Theme.warning : Theme.primary)
                .frame(width: 34, height: 32)
                .overlay(alignment: .topTrailing) {
                    if unread > 0 {
                        Text(verbatim: unread > 99 ? "99+" : "\(unread)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Theme.error))
                            .offset(x: 4, y: -2)
                    }
                }
        }
        .buttonStyle(TouchTargetButtonStyle(size: CGSize(width: 34, height: 32)))
        .accessibilityLabel(Text(verbatim: language.text("News", "新聞紀錄")))
        .accessibilityValue(Text(verbatim: unread > 0 ? language.text("\(unread) unread", "\(unread) 則未讀") : ""))
        .accessibilityIdentifier("hud.news")
    }
}

/// Saving, exporting the game as a file, going back to the start screen
/// (which autosaves first), the tutorial, the panels opened less often and
/// the settings.
///
/// The game loop replaces the world every tick, and a native menu whose
/// contents are drawn again while it is open is rebuilt: it scrolls back
/// to its top and can drop the tap (TestFlight 54.1: Back to Start could
/// not be reached). So it is an equatable view of what it shows, and never
/// reads the world: the export takes the game when it is shared.
private struct GameMenu: View, Equatable {
    let session: GameSession
    let launcher: GameLauncher
    let screen: GameScreenState
    /// Decision 86: a game with a challenge shows its goals; decision 183:
    /// and one with the city's requests.
    let showsGoals: Bool
    /// Decision 174: a game with sights shows them.
    let showsTourism: Bool
    let language: DisplayLanguage
    /// Asks the name of a save (decision 184), in the HUD's alert.
    let askSaveName: @MainActor () -> Void
    /// Asks which autosave to go back to (decision 192), in the HUD's
    /// dialog.
    let askGoBack: @MainActor () -> Void

    nonisolated static func == (lhs: GameMenu, rhs: GameMenu) -> Bool {
        lhs.session === rhs.session
            && lhs.launcher === rhs.launcher
            && lhs.screen === rhs.screen
            && lhs.showsGoals == rhs.showsGoals
            && lhs.showsTourism == rhs.showsTourism
            && lhs.language == rhs.language
    }

    var body: some View {
        Menu {
            Button {
                UITestTrace.action("menu.saveGame")
                launcher.saveCurrentGame()
            } label: {
                Label("Save Game", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("menu.saveGame")
            // Decision 184: a save with a name of the player's, beside the
            // export in one row, so the menu keeps its length: on a phone
            // on its side a longer menu put Back to Start out of reach.
            Menu {
                Button {
                    askSaveName()
                } label: {
                    Label {
                        Text(verbatim: language.text("Save As…", "另存新檔…"))
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .accessibilityIdentifier("menu.saveGameAs")
                ShareLink(item: ExportedSave(session: session), preview: SharePreview(Text("Along the Line save"))) {
                    Label("Export Save", systemImage: "square.and.arrow.up")
                }
                // Decision 192: back to the game of some minutes before,
                // in this row too, so the menu keeps its length.
                Button {
                    askGoBack()
                } label: {
                    Label {
                        Text(verbatim: language.text("Go Back to an Autosave…", "回到之前的自動存檔…"))
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                .accessibilityIdentifier("menu.goBack")
            } label: {
                Label {
                    Text(verbatim: language.text("Save, Export or Go Back", "另存、匯出或回到之前"))
                } icon: {
                    Image(systemName: "square.and.pencil")
                }
            }
            .accessibilityIdentifier("menu.saveOptions")
            // The only way out of the game, in the first section rather
            // than the last row (TestFlight 54.1): on a short phone, or
            // with larger text, the last row of six was off the screen.
            Button {
                launcher.returnToStart()
            } label: {
                Label("Back to Start", systemImage: "house")
            }
            .accessibilityIdentifier("menu.backToStart")
            Divider()
            // Decision 188, later fix (TestFlight 54.1): a skipped tutorial
            // is taken up again where it was, or started over, from one row,
            // so the menu keeps its six rows.
            if let skipped = session.skippedTutorial {
                Menu {
                    Button {
                        session.resumeTutorial()
                    } label: {
                        Label {
                            Text(verbatim: language.text(
                                "Continue Tutorial (Step \(skipped.index + 1))",
                                "繼續教學（第 \(skipped.index + 1) 步）"
                            ))
                        } icon: {
                            Image(systemName: "play")
                        }
                    }
                    .accessibilityIdentifier("menu.tutorial.resume")
                    Button {
                        session.startTutorial()
                    } label: {
                        Label {
                            Text(verbatim: language.text("Start Over", "從頭開始"))
                        } icon: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                    .accessibilityIdentifier("menu.tutorial.restart")
                } label: {
                    Label("Tutorial", systemImage: "hand.point.up.left")
                }
                .accessibilityIdentifier("menu.tutorial")
            } else {
                Button {
                    session.startTutorial()
                } label: {
                    Label("Tutorial", systemImage: "hand.point.up.left")
                }
                .accessibilityIdentifier("menu.tutorial")
            }
            // The panels opened less often, in one row whatever the game
            // has: on a phone on its side the menu shows about six rows,
            // and the goals (decisions 86 and 183) and the sights (decision
            // 174) pushed Back to Start out of reach.
            Menu {
                // Decision 86: a game with a challenge shows its goals;
                // decision 183: and one with the city's requests.
                if showsGoals {
                    Button {
                        screen.panel = .goals
                    } label: {
                        Label {
                            Text(verbatim: language.text("Goals", "目標"))
                        } icon: {
                            Image(systemName: "flag.checkered")
                        }
                    }
                    .accessibilityIdentifier("menu.goals")
                }
                // Decision 174: a game with sights shows them.
                if showsTourism {
                    Button {
                        screen.panel = .tourism
                    } label: {
                        Label {
                            Text(verbatim: language.text("Sights", "觀光景點"))
                        } icon: {
                            Image(systemName: "star")
                        }
                    }
                    .accessibilityIdentifier("menu.tourism")
                }
                Button {
                    screen.panel = .help
                } label: {
                    Label {
                        Text(verbatim: language.text("Help", "說明"))
                    } icon: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                .accessibilityIdentifier("menu.help")
            } label: {
                Label {
                    Text(verbatim: language.text("More", "更多"))
                } icon: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .accessibilityIdentifier("menu.more")
            Divider()
            Button {
                screen.panel = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("menu.settings")
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 32)
                // Touched over 44 by 44 points: a menu is touched over its
                // label's own frame, not a larger content shape (run
                // 38335812150), so the label is that large and the
                // negative padding below keeps the 38 by 32 the pill lays
                // out (``touchTarget(around:)``).
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.horizontal, -3)
        .padding(.vertical, -6)
        .accessibilityLabel("Game menu")
        .accessibilityHint("Saves the game, exports it as a file, opens the tutorial or the settings, or goes back to the start screen.")
        .accessibilityIdentifier("hud.menu")
        .tutorialTarget(.gameMenu)
    }
}

/// The next days' holidays, weather, typhoons and energy prices (decision
/// 175), from GameCore's own queries.
private struct ForecastView: View {
    let session: GameSession

    var body: some View {
        let language = session.language
        let days = session.world.forecast()
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: language.text("Next 7 days", "未來 7 天"))
                .font(.headline)
            if days.isEmpty {
                Text(verbatim: language.text(
                    "This game has no holidays or weather. Turn on Holidays and events in the settings.",
                    "這一局沒有連假和天氣。在設定裡打開「連假與事件」。"
                ))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: 260, alignment: .leading)
            } else {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    HStack(spacing: 8) {
                        Text(verbatim: index == 0 ? language.text("Today", "今天") : day.date.shortText(in: language))
                            .font(.footnote.weight(.semibold))
                            .frame(width: 84, alignment: .leading)
                        Image(systemName: day.typhoonBlowing ? "tropicalstorm" : day.weather.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 22)
                        Text(verbatim: day.text(in: language))
                            .font(.footnote)
                            .foregroundStyle(day.holiday != nil || day.typhoonBlowing ? Theme.textPrimary : Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .accessibilityIdentifier("hud.forecast")
    }
}

/// Pause or play, and a menu of the speeds from real time up (Stage W2a),
/// labelled with the speed the game runs at. Everything is read from the
/// world's clock.
private struct SpeedControl: View {
    let session: GameSession

    var body: some View {
        let clock = session.world.clock
        let language = session.language
        HStack(spacing: 4) {
            Button {
                session.togglePause()
            } label: {
                Image(systemName: clock.isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 38, height: 32)
            }
            .buttonStyle(PauseButtonStyle(isActive: clock.isPaused))
            .accessibilityLabel(clock.isPaused ? "Resume" : "Pause")
            SpeedMenu(session: session, speed: clock.speed, runningSpeed: clock.runningSpeed, isPaused: clock.isPaused, language: language)
                .equatable()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game speed")
        .tutorialTarget(.speedControl)
    }
}

/// Decision 195: beside the speed, the followed train's speed and how fast
/// the game really runs ("actual ×600", or "actual ×290 (falling behind)"
/// when the device cannot keep up), read from the session's measure; the
/// speed menu's label says the speed the game is set to. Nothing while
/// paused and following no train.
private struct ViewingReadout: View {
    let session: GameSession

    var body: some View {
        let viewing = session.viewingSpeed
        let language = session.language
        let actual = viewing.actualText(in: language)
        let train = viewing.trainSpeedText
        if actual != nil || train != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let train {
                    Text(verbatim: train)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                if let actual {
                    Text(verbatim: actual)
                        .font(viewing.isBehind ? Font.caption2.weight(.bold) : Font.caption2)
                        .foregroundStyle(viewing.isBehind ? Theme.warning : Theme.textSecondary)
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: viewing.accessibilityText(in: language)))
            .accessibilityIdentifier("hud.viewing")
        }
    }
}

/// A plain icon button, dimmed while pressed, touched over at least 44
/// by 44 points while drawn at `size`. The touch area belongs to the
/// style's body: one set inside a button's label was not used (run
/// 38333522943: a tap 4 points under the drawn bell missed it).
private struct TouchTargetButtonStyle: ButtonStyle {
    let size: CGSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .touchTarget(around: size)
    }
}

/// The pause button's look (``ThemeSelectableButtonStyle``: 38 by 40
/// points with its padding), touched over at least 44 by 44.
private struct PauseButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        ThemeSelectableButtonStyle(isActive: isActive)
            .makeBody(configuration: configuration)
            .touchTarget(around: CGSize(width: 38, height: 40))
    }
}

private extension View {
    /// Touched over at least 44 by 44 points (Apple's smallest target)
    /// while drawn and laid out at `size`, so the status pill keeps its
    /// size: the touch area reaches into the pill's margins and the spaces
    /// between its controls, and two neighbours' areas never meet (the
    /// bell's 5 and the menu's 3 points in at least 10 between them, the
    /// pause button's 3 in the 4 before the speed menu).
    func touchTarget(around size: CGSize) -> some View {
        let dx = max(0, (44 - size.width) / 2)
        let dy = max(0, (44 - size.height) / 2)
        return padding(.horizontal, dx)
            .padding(.vertical, dy)
            .contentShape(Rectangle())
            .padding(.horizontal, -dx)
            .padding(.vertical, -dy)
    }
}

/// The menu of the speeds, labelled with the one the game runs at. An
/// equatable view of the speed alone: the clock moves every tick, and an
/// open native menu drawn again is rebuilt (TestFlight 54.1).
private struct SpeedMenu: View, Equatable {
    let session: GameSession
    let speed: GameSpeed
    let runningSpeed: GameSpeed
    let isPaused: Bool
    let language: DisplayLanguage

    nonisolated static func == (lhs: SpeedMenu, rhs: SpeedMenu) -> Bool {
        lhs.session === rhs.session
            && lhs.speed == rhs.speed
            && lhs.runningSpeed == rhs.runningSpeed
            && lhs.isPaused == rhs.isPaused
            && lhs.language == rhs.language
    }

    var body: some View {
        Menu {
            ForEach(GameSpeed.allCases.filter { $0 != .paused }, id: \.self) { candidate in
                Button {
                    session.setSpeed(candidate)
                } label: {
                    if candidate == speed {
                        Label(candidate.label(in: language), systemImage: "checkmark")
                    } else {
                        Text(candidate.label(in: language))
                    }
                }
                .accessibilityLabel(candidate.accessibilityName(in: language))
            }
        } label: {
            HStack(spacing: 4) {
                if isPaused {
                    Circle()
                        .fill(Theme.warning)
                        .frame(width: 6, height: 6)
                }
                Text(runningSpeed.label(in: language))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.primary)
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 48, minHeight: 32)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Speed: \(runningSpeed.accessibilityName(in: language))")
        .accessibilityHint("Chooses how fast game time runs.")
    }
}

/// The game as a save file to share (Stage C4, the reference's "导出本地存档"),
/// written when the player shares it, from the game as it is then: the menu
/// that offers it does not build the world to save every tick.
private struct ExportedSave: Transferable {
    let session: GameSession

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { save in
            let world = await save.session.worldToSave
            return SentTransferredFile(try SaveLibrary.exportFile(for: world, at: Date()))
        }
    }
}

/// An autosave the game menu offers to go back to (decision 192), with
/// its label as it was when asked: how long ago, the game date and funds.
private struct GoBackChoice: Identifiable {
    let entry: SaveLibrary.Entry
    let label: String
    var id: String { entry.id }
}
