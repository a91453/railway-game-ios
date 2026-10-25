import GameCore
import GamePresentation
import SwiftUI
import UIKit
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
    /// Decision 184: whether Save As's name is being asked, and the name.
    @State private var namingSave = false
    @State private var saveName = ""
    /// Decision 192: the autosaves to go back to, read and labelled when
    /// the player asks, so the ticks leave the question as it was asked.
    @State private var goBackChoices: [GoBackChoice] = []
    @State private var choosingGoBack = false
    /// Whether the problem report is open from the game menu (decisions
    /// 127 and 193; TestFlight 54.1).
    @State private var reportingProblem = false

    // Decision 379: timed for the frame readout.
    var body: some View { timed(.hudBody) { timedBody } }

    @ViewBuilder private var timedBody: some View {
        // One row in one glass pill, as wide as what it shows; then one row
        // with the shorter date ("2 年 5/12（六）08:40", decision 226); only
        // then do cash and time stack. With the largest text the time gets
        // a row of its own rather than being cut short ("Day 2 · 07…"), and
        // the cash is never cut short ("$ 3,0…"). Decision 251: each part
        // keeps the room of the widest text it can show (``StatusBarWidths``),
        // so the bar keeps one width, and one of these layouts, while the
        // game runs.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                HUDCash(session: session)
                HUDTime(session: session, short: false)
                speed
                HUDRequestsButton(session: session)
                HUDSightsButton(session: session)
                HUDNewsBell(session: session)
                gameMenu
            }
            HStack(spacing: 16) {
                HUDCash(session: session)
                HUDTime(session: session, short: true)
                speed
                HUDRequestsButton(session: session)
                HUDSightsButton(session: session)
                HUDNewsBell(session: session)
                gameMenu
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HUDCash(session: session)
                    HUDTime(session: session, short: false)
                }
                speed
                HUDRequestsButton(session: session)
                HUDSightsButton(session: session)
                HUDNewsBell(session: session)
                gameMenu
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    HUDCash(session: session)
                    speed
                    HUDRequestsButton(session: session)
                    HUDSightsButton(session: session)
                    HUDNewsBell(session: session)
                    gameMenu
                }
                HUDTime(session: session, short: false)
                    .minimumScaleFactor(0.75)
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .sheet(isPresented: $reportingProblem) {
            ProblemReportSheet(game: session.problemReportGame, session: session, lessons: launcher.lessonReport(in: .app))
        }
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
                "A name for this save, to find it in Saves.",
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

    /// Pause, the speed and, beside it, the dot or the followed train's speed.
    private var speed: some View {
        HStack(spacing: 6) {
            SpeedControl(session: session)
            ViewingReadout(session: session)
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
            // Decision 377: as the session keeps them, not read from the
            // world, so a tick leaves the bar as it was.
            showsGoals: session.screenFacts.showsGoals,
            showsTourism: session.screenFacts.showsTourism,
            language: session.language,
            askSaveName: {
                saveName = ""
                namingSave = true
            },
            askGoBack: askGoBack,
            reportProblem: { reportingProblem = true }
        )
        .equatable()
    }
}

// Decision 377: each part of the bar that a tick can change is a view of
// its own, which reads the world in its own body, so a tick rebuilds that
// part, not the bar's four layouts round it.

private struct HUDCash: View {
    let session: GameSession
    @Environment(GameScreenState.self) private var screen

    /// The balance in dollars; it opens the economy panel. Decision 200:
    /// with unlimited funds an "∞" capsule instead, in the text colour (not
    /// the green of money coming in), without the income float.
    @ViewBuilder
    // Decision 379: timed for the frame readout.
    var body: some View { timed(.hudBody) { timedBody } }

    @ViewBuilder private var timedBody: some View {
        if session.world.economy.unlimitedFunds {
            Button {
                screen.panel = .economy
            } label: {
                Text(verbatim: "∞")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(Capsule().stroke(Theme.textSecondary, lineWidth: 1))
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: session.language.text("Unlimited funds", "資金無限")))
            .accessibilityHint(Text(verbatim: session.language.text("Shows fares, running costs and the ledger.", "顯示票收、營運成本與帳本。")))
            .accessibilityIdentifier("hud.unlimitedFunds")
            .tutorialTarget(.cash)
        } else {
            balance
        }
    }

    /// The balance in dollars, as before decision 200.
    private var balance: some View {
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
                    // Decision 251: until the amount gains an eighth digit.
                    .modifier(WidestTextRoom(StatusBarWidths.moneyText(session.world.economy.balance)))
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
}

private struct HUDTime: View {
    let session: GameSession
    /// The shorter date (decision 226).
    let short: Bool
    /// Whether the forecast of the next days is open (decision 175).
    @State private var showsForecast = false

    /// The date and time (decision 175), today's weather and holiday; it
    /// opens the forecast of the next days. `short`: the board's shorter
    /// date (decision 226), which keeps it to one row.
    // Decision 379: timed for the frame readout.
    var body: some View { timed(.hudBody) { timedBody } }

    private var timedBody: some View {
        let language = session.language
        let clock = session.world.clock
        let text = short ? clock.shortCalendarText(in: language) : clock.calendarText(in: language)
        let holiday = session.world.todayHoliday()?.title(in: language)
        return Button {
            showsForecast = true
        } label: {
            HStack(spacing: 6) {
                // Decision 251: a holiday turns the clock into a flag rather
                // than adding its name, which widened the bar for the day;
                // the forecast and VoiceOver say which holiday.
                Image(systemName: holiday == nil ? "clock.fill" : "flag.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(holiday == nil ? Theme.primary : Theme.warning)
                    .frame(width: StatusBarIcon.width)
                    .accessibilityIdentifier(holiday == nil ? "hud.clock" : "hud.holiday")
                Text(text)
                    .foregroundStyle(Theme.textPrimary)
                    // Decision 251: any day of the year, with the seconds'
                    // room while they can show.
                    .modifier(WidestTextRoom(key: "date \(clock.now.date.year) \(short) \(StatusBarWidths.showsSeconds(clock)) \(language)") {
                        StatusBarWidths.dateTexts(of: clock, short: short, in: language)
                    })
                if let symbol = session.world.todaySymbol() {
                    // One width for every kind of weather.
                    Image(systemName: symbol)
                        .font(.caption.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: StatusBarIcon.width)
                        .accessibilityIdentifier("hud.weather")
                }
                // 2026-10-16: says that a tap opens more, the forecast.
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
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
        // Decision 251: the holiday the flag stands for.
        .accessibilityValue(Text(verbatim: holiday ?? ""))
        .accessibilityHint(Text(verbatim: language.text("Shows the forecast of the next seven days.", "顯示未來七天的預報。")))
        .accessibilityIdentifier("hud.time")
    }
}

private struct HUDRequestsButton: View {
    let session: GameSession
    @Environment(GameScreenState.self) private var screen

    /// Decision 246: the city's requests, one tap from the status bar,
    /// with the number in hand; tinted while offers wait that the company
    /// has room for. Only in a game with them.
    @ViewBuilder
    var body: some View {
        if let held = session.cityRequestsInHand {
            let offers = session.hasCityRequestOffers
            Button {
                screen.panel = .goals
            } label: {
                MapGlyph.request.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(offers ? Theme.warning : Theme.primary)
                    .frame(width: 34, height: 32)
                    .overlay(alignment: .topTrailing) {
                        if held > 0 {
                            Text(verbatim: "\(held)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.onPrimary)
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(Theme.primary))
                                .offset(x: 4, y: -2)
                        }
                    }
            }
            .buttonStyle(TouchTargetButtonStyle(size: CGSize(width: 34, height: 32)))
            .accessibilityLabel(Text(verbatim: session.language.text("City requests", "委託案")))
            .accessibilityValue(Text(verbatim: session.cityRequestsButtonValue))
            .accessibilityIdentifier("hud.requests")
            // Decision 376: lesson 10's step points at it.
            .tutorialTarget(.requestsButton)
        }
    }
}

private struct HUDSightsButton: View {
    let session: GameSession
    @Environment(GameScreenState.self) private var screen

    /// The sights (decision 174), one tap from the status bar in a game
    /// with them (decision 336, later); also under the game menu's More.
    @ViewBuilder
    var body: some View {
        if session.showsSightsButton {
            Button {
                screen.sightFocus = nil
                screen.panel = .tourism
            } label: {
                Image(systemName: "star.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 34, height: 32)
            }
            .buttonStyle(TouchTargetButtonStyle(size: CGSize(width: 34, height: 32)))
            .accessibilityLabel(Text(verbatim: session.language.text("Sights", "觀光景點")))
            .accessibilityIdentifier("hud.sights")
        }
    }
}

private struct HUDNewsBell: View {
    let session: GameSession
    @Environment(GameScreenState.self) private var screen

    /// The news log's bell (decision 175), with the number of items not
    /// yet seen.
    var body: some View {
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
    /// Opens the problem report (TestFlight 54.1: a player found it only in
    /// the settings), in the HUD's sheet.
    let reportProblem: @MainActor () -> Void

    nonisolated static func == (lhs: GameMenu, rhs: GameMenu) -> Bool {
        lhs.session === rhs.session
            && lhs.launcher === rhs.launcher
            && lhs.screen === rhs.screen
            && lhs.showsGoals == rhs.showsGoals
            && lhs.showsTourism == rhs.showsTourism
            && lhs.language == rhs.language
    }

    var body: some View {
        let layout = GameMenuLayout(showsGoals: showsGoals, showsTourism: showsTourism)
        Menu {
            // Decision 226, later (2026-10-16): the rows and their order
            // come from GamePresentation (``GameMenuLayout``).
            ForEach(Array(layout.sections.enumerated()), id: \.offset) { index, section in
                if index > 0 {
                    Divider()
                }
                ForEach(section, id: \.self) { row in
                    self.row(row, in: layout)
                }
            }
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

    /// One row of the menu's first level.
    @ViewBuilder
    private func row(_ row: GameMenuLayout.Row, in layout: GameMenuLayout) -> some View {
        switch row {
        case .saveGame:
            Button {
                UITestTrace.action("menu.saveGame")
                launcher.saveCurrentGame()
            } label: {
                Label("Save Game", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("menu.saveGame")
        case .saveOptions:
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
                ShareLink(item: ExportedSave(session: session, launcher: launcher), preview: SharePreview(Text("Along the Line save"))) {
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
        case .backToStart:
            // The only way out of the game, in the first section rather
            // than the last row (TestFlight 54.1): on a short phone, or
            // with larger text, the last row of six was off the screen.
            Button {
                launcher.returnToStart()
            } label: {
                Label("Back to Start", systemImage: "house")
            }
            .accessibilityIdentifier("menu.backToStart")
        case .shortcuts:
            // Decision 226, later (2026-10-16): side by side in one row,
            // so the first level keeps to six rows (``GameMenuLayout``).
            ControlGroup {
                ForEach(layout.shortcuts, id: \.self) { shortcut in
                    self.shortcut(shortcut)
                }
            }
            .controlGroupStyle(.compactMenu)
        case .help:
            // Decision 383: Help and Report a Problem side by side where
            // More stood, with what More held when it is one row.
            ControlGroup {
                ForEach(layout.helpRow, id: \.self) { item in
                    self.helpItem(item, in: layout)
                }
            }
            .controlGroupStyle(.compactMenu)
        case .settings:
            Button {
                screen.panel = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("menu.settings")
        }
    }

    /// One of the shortcuts side by side in the first level.
    @ViewBuilder
    private func shortcut(_ shortcut: GameMenuLayout.Shortcut) -> some View {
        switch shortcut {
        case .tutorial:
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
        case .postcard:
            // Decision 215: the network as a picture to share.
            Button {
                screen.panel = .postcard
            } label: {
                Label {
                    Text(verbatim: language.text("Make a Postcard", "做明信片"))
                } icon: {
                    Image(systemName: "photo.on.rectangle")
                }
            }
            .accessibilityIdentifier("menu.postcard")
        case .achievements:
            // Decision 181: the achievements (decision 226, later).
            Button {
                screen.panel = .achievements
            } label: {
                Label {
                    Text(verbatim: language.text("Achievements", "成就"))
                } icon: {
                    Image(systemName: "rosette")
                }
            }
            .accessibilityIdentifier("menu.achievements")
        }
    }

    /// One item of the help row (decision 383).
    @ViewBuilder
    private func helpItem(_ item: GameMenuLayout.HelpItem, in layout: GameMenuLayout) -> some View {
        switch item {
        case .help: helpButton
        case .report: reportButton
        case .goals: goalsButton
        case .tourism: tourismButton
        case .more:
            // The panels opened less often, when the game has both.
            Menu {
                ForEach(layout.moreRows, id: \.self) { row in
                    switch row {
                    case .goals: goalsButton
                    case .tourism: tourismButton
                    }
                }
            } label: {
                Label {
                    Text(verbatim: language.text("More", "更多"))
                } icon: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .accessibilityIdentifier("menu.more")
        }
    }

    /// Decision 86: a game with a challenge shows its goals; decision 183:
    /// and one with the city's requests.
    private var goalsButton: some View {
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

    /// Decision 174: a game with sights shows them.
    private var tourismButton: some View {
        Button {
            screen.sightFocus = nil
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

    private var helpButton: some View {
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
    }

    /// TestFlight 54.1: where to send a note, from the game.
    private var reportButton: some View {
        Button {
            reportProblem()
        } label: {
            Label {
                Text(verbatim: language.text("Report a Problem", "回報問題"))
            } icon: {
                Image(systemName: "exclamationmark.bubble")
            }
        }
        .accessibilityIdentifier("menu.report")
    }
}

/// The next days' holidays, weather, typhoons and energy prices (decision
/// 175), from GameCore's own queries.
private struct ForecastView: View {
    let session: GameSession

    // Decision 379: timed for the frame readout.
    var body: some View { timed(.hudBody) { timedBody } }

    @ViewBuilder private var timedBody: some View {
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
/// world's clock. Also on the 3D map (``Map3DPreviewScreen``), which covers
/// the status pill.
struct SpeedControl: View {
    let session: GameSession
    /// What the tutorial points at; `nil` on the 3D map, which it never
    /// shows.
    var tutorialTarget: TutorialTarget? = .speedControl

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
            SpeedMenu(session: session, speed: clock.speed, runningSpeed: clock.runningSpeed, isPaused: clock.isPaused,
                      capped: session.isSpeedCappedIn3D, language: language)
                .equatable()
        }
        // Review E's E2: waits while the demo lays the real lines.
        .disabled(session.isLayingDemoRealLines)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game speed")
        .tutorialTarget(tutorialTarget)
    }
}

/// Decision 195: beside the speed, the followed train's speed, read from
/// the session's measure; the speed menu's label says the speed the game
/// is set to. Decision 226: how fast the game really runs is no longer
/// written out, which made the board two rows on a phone; a `warning` dot
/// says the device is falling behind, and tapped says by how much
/// (``ViewingSpeed/lagText(in:)``). While the game keeps up, the dot's
/// place stays empty (#631); nothing else while following no train.
private struct ViewingReadout: View {
    let session: GameSession
    @State private var showsLag = false

    // Decision 379: timed for the frame readout.
    var body: some View { timed(.hudBody) { timedBody } }

    @ViewBuilder private var timedBody: some View {
        let viewing = session.viewingSpeed
        let language = session.language
        let lag = viewing.lagText(in: language)
        let train = viewing.trainSpeedText
        // Decision 217: the curve limit it keeps to, or brakes for.
        let curve = session.followedTrainID.flatMap { session.world.curveLimit(of: $0) }?.text(in: language)
        HStack(spacing: 6) {
            if lag != nil {
                Button {
                    showsLag = true
                } label: {
                    Circle()
                        .fill(Theme.warning)
                        .frame(width: 8, height: 8)
                        .frame(width: 16, height: 32)
                }
                .buttonStyle(TouchTargetButtonStyle(size: CGSize(width: 16, height: 32)))
                .popover(isPresented: $showsLag) {
                    Text(verbatim: viewing.lagText(in: language) ?? viewing.actualText(in: language) ?? "")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .padding()
                        .presentationCompactAdaptation(.popover)
                }
                .accessibilityLabel(Text(verbatim: viewing.accessibilityText(in: language)))
                .accessibilityIdentifier("hud.lag")
            } else {
                // The dot's place, kept while the game keeps up: a device
                // that falls behind and catches up again in turn would
                // otherwise widen and narrow the board, and the board then
                // changes its layout (the shorter date) and moves the pause
                // button under the finger (main 8c604e8's full lane, run
                // 38625196256: the board's two layouts at 00:11 and 00:17).
                Color.clear
                    .frame(width: 16, height: 32)
                    .accessibilityHidden(true)
            }
            if let train {
                // Decision 251: the speed and the curve limit keep the room
                // of their widest while the train is followed.
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: train)
                        .foregroundStyle(Theme.textPrimary)
                        .modifier(WidestTextRoom(StatusBarWidths.trainSpeedText))
                        .font(.caption.weight(.semibold))
                    if let curve {
                        Text(verbatim: curve)
                            .foregroundStyle(Theme.textSecondary)
                            .modifier(WidestTextRoom(key: "curve \(language)") { StatusBarWidths.curveTexts(in: language) })
                            .font(.caption2)
                    }
                }
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: [viewing.accessibilityText(in: language), curve].compactMap { $0 }.joined(separator: language.text(". ", "，"))))
                .accessibilityIdentifier("hud.viewing")
            }
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
    /// Decision 360: following a train on the 3D map, up to 10× only.
    let capped: Bool
    let language: DisplayLanguage

    nonisolated static func == (lhs: SpeedMenu, rhs: SpeedMenu) -> Bool {
        lhs.session === rhs.session
            && lhs.speed == rhs.speed
            && lhs.runningSpeed == rhs.runningSpeed
            && lhs.isPaused == rhs.isPaused
            && lhs.capped == rhs.capped
            && lhs.language == rhs.language
    }

    var body: some View {
        Menu {
            if capped {
                Text(verbatim: Map3DFollowSpeed.limitText(in: language))
            }
            ForEach(Map3DFollowSpeed.choices(capped: capped), id: \.self) { candidate in
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
                // Decision 251: the dot's place is kept while the game runs,
                // and the label has the room of the widest speed, so pausing
                // or changing the speed moves nothing beside it.
                Circle()
                    .fill(isPaused ? Theme.warning : Color.clear)
                    .frame(width: 6, height: 6)
                Text(runningSpeed.label(in: language))
                    .foregroundStyle(Theme.primary)
                    .modifier(WidestTextRoom(key: "speed \(language)") {
                        StatusBarWidths.speedLabels(in: language).filter { $0 != GameSpeed.paused.label(in: language) }
                    })
                    .font(.subheadline.weight(.bold))
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 48, minHeight: 32)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Speed: \(runningSpeed.accessibilityName(in: language))")
        .accessibilityHint("Chooses how fast game time runs.")
    }
}

/// An autosave the game menu offers to go back to (decision 192), with
/// its label as it was when asked: how long ago, the game date and funds.
private struct GoBackChoice: Identifiable {
    let entry: SaveLibrary.Entry
    let label: String
    var id: String { entry.id }
}

/// Decision 251: the room of a status bar icon, whichever symbol it shows
/// (the weather's are of different widths).
private enum StatusBarIcon {
    static let width: CGFloat = 20
}

/// Decision 251: lays a text out as wide as the widest of some texts in
/// the same font, so it keeps one width while what it says changes. The
/// widest is the one hidden behind it, in the font around both (set the
/// text's font after this); it is picked by measuring the texts at the
/// text size the player chose, once for each `key`.
private struct WidestTextRoom: ViewModifier {
    let key: String
    let texts: () -> [String]
    /// Measured again when the player changes the text size.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The room of `texts`, which `key` names.
    init(key: String, texts: @escaping () -> [String]) {
        self.key = key
        self.texts = texts
    }

    /// The room of `text`.
    init(_ text: String) {
        self.init(key: text) { [text] }
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            Text(verbatim: WidestText.widest(key: key, at: dynamicTypeSize, of: texts))
                .hidden()
                .accessibilityHidden(true)
            content
        }
    }
}

/// Picks and remembers the widest of a list of texts in the status bar's
/// font, ``WidestTextRoom``.
@MainActor
private enum WidestText {
    private static var picked: [String: String] = [:]

    static func widest(key: String, at size: DynamicTypeSize, of texts: () -> [String]) -> String {
        let key = "\(size) \(key)"
        if let text = picked[key] { return text }
        let candidates = texts()
        let pointSize = UIFont.preferredFont(forTextStyle: .subheadline).pointSize
        let font = UIFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .bold)
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let text = candidates.count > 1 ? candidates.max { width($0) < width($1) } ?? "" : candidates.first ?? ""
        if picked.count > 64 { picked.removeAll() }
        picked[key] = text
        return text
    }
}
