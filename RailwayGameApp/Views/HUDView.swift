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
                newsBell
                gameMenu
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    cash
                    time
                }
                SpeedControl(session: session)
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
    }

    /// Saving, exporting the game as a file, the tutorial, the settings
    /// (music and sound effects), and going back to the start screen,
    /// which autosaves first.
    private var gameMenu: some View {
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
                    saveName = ""
                    namingSave = true
                } label: {
                    Label {
                        Text(verbatim: session.language.text("Save As…", "另存新檔…"))
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .accessibilityIdentifier("menu.saveGameAs")
                ShareLink(item: ExportedSave(world: session.world), preview: SharePreview(Text("Along the Line save"))) {
                    Label("Export Save", systemImage: "square.and.arrow.up")
                }
            } label: {
                Label {
                    Text(verbatim: session.language.text("Save As or Export", "另存或匯出"))
                } icon: {
                    Image(systemName: "square.and.pencil")
                }
            }
            .accessibilityIdentifier("menu.saveOptions")
            Divider()
            Button {
                session.startTutorial()
            } label: {
                Label("Tutorial", systemImage: "hand.point.up.left")
            }
            .accessibilityIdentifier("menu.tutorial")
            // Decision 86: a game with a challenge shows its goals;
            // decision 183: and one with the city's requests.
            if session.world.scenario != nil || session.world.hasCityRequests {
                Button {
                    screen.panel = .goals
                } label: {
                    Label {
                        Text(verbatim: session.language.text("Goals", "目標"))
                    } icon: {
                        Image(systemName: "flag.checkered")
                    }
                }
                .accessibilityIdentifier("menu.goals")
            }
            // Decision 174: a game with sights shows them.
            if session.world.hasTourism {
                Button {
                    screen.panel = .tourism
                } label: {
                    Label {
                        Text(verbatim: session.language.text("Sights", "觀光景點"))
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
                    Text(verbatim: session.language.text("Help", "說明"))
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
            }
            .accessibilityIdentifier("menu.help")
            Divider()
            Button {
                screen.panel = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("menu.settings")
            Divider()
            Button {
                launcher.returnToStart()
            } label: {
                Label("Back to Start", systemImage: "house")
            }
            .accessibilityIdentifier("menu.backToStart")
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Game menu")
        .accessibilityHint("Saves the game, exports it as a file, opens the tutorial or the settings, or goes back to the start screen.")
        .accessibilityIdentifier("hud.menu")
        .tutorialTarget(.gameMenu)
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
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: language.text("News", "新聞紀錄")))
        .accessibilityValue(Text(verbatim: unread > 0 ? language.text("\(unread) unread", "\(unread) 則未讀") : ""))
        .accessibilityIdentifier("hud.news")
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
            .buttonStyle(ThemeSelectableButtonStyle(isActive: clock.isPaused))
            .accessibilityLabel(clock.isPaused ? "Resume" : "Pause")
            Menu {
                ForEach(GameSpeed.allCases.filter { $0 != .paused }, id: \.self) { speed in
                    Button {
                        session.setSpeed(speed)
                    } label: {
                        if speed == clock.speed {
                            Label(speed.label(in: language), systemImage: "checkmark")
                        } else {
                            Text(speed.label(in: language))
                        }
                    }
                    .accessibilityLabel(speed.accessibilityName(in: language))
                }
            } label: {
                HStack(spacing: 4) {
                    if clock.isPaused {
                        Circle()
                            .fill(Theme.warning)
                            .frame(width: 6, height: 6)
                    }
                    Text(clock.runningSpeed.label(in: language))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 48, minHeight: 32)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Speed: \(clock.runningSpeed.accessibilityName(in: language))")
            .accessibilityHint("Chooses how fast game time runs.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game speed")
        .tutorialTarget(.speedControl)
    }
}

/// The game as a save file to share (Stage C4, the reference's "导出本地存档"),
/// written when the player shares it.
private struct ExportedSave: Transferable {
    let world: GameWorld

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { save in
            SentTransferredFile(try SaveLibrary.exportFile(for: save.world, at: Date()))
        }
    }
}
