import GameCore
import GamePresentation
import SwiftUI
import UniformTypeIdentifiers

/// The start screen (Stage C4), after the `Ci/` reference's home screen and
/// its saved-game card (`screen-save-load-ui`: go on with the saved game,
/// or start fresh): continue the autosave, start a new game on a blank or a
/// real-world map or a challenge (Stage E2; decision 316: all behind New
/// Game), open one of the demos (decision 135: the
/// real-world demo of Taiwan's real lines, or the simple demo), load one of
/// the saves or import a save file (decision 381: both behind Saves).
///
/// Every action calls a ``GameLauncher`` method; the screen keeps nothing
/// of the games but what it shows.
struct StartView: View {
    let launcher: GameLauncher
    @State private var showsSaves = false
    /// Decision 316: the new game's page, blank or real-world.
    @State private var choosesNewGame = false
    /// Decision 266: the lessons, in place of the tutorial.
    @State private var choosesLesson = false
    @State private var choosesDemo = false
    @State private var showsSettings = false
    @State private var showsHelp = false
    @State private var showsAchievements = false
    /// Decision 415: the news of an update, once.
    @State private var showsWhatsNew = false
    @Environment(GameAudio.self) private var audio
    /// Compact: a phone on its side.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                // A phone on its side (decision 106): the title beside the
                // buttons, so the first ones show without scrolling.
                HStack(spacing: 0) {
                    ScrollView {
                        header
                            .padding(.vertical, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxWidth: .infinity)
                    ScrollView {
                        VStack(spacing: 20) {
                            buttons
                            footer
                        }
                        .frame(maxWidth: 420)
                        .padding(.horizontal)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(spacing: 28) {
                        header
                        buttons
                        footer
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Theme.background)
        .sheet(isPresented: $showsSettings) {
            SettingsView(audio: audio, launcher: launcher, lessons: launcher.lessonReport(in: .app))
        }
        .sheet(isPresented: $showsHelp) {
            HelpView(language: launcher.language, launcher: launcher)
        }
        .sheet(isPresented: $choosesNewGame) {
            NewGamePicker(launcher: launcher, loadingDetail: loadingDetail)
        }
        .sheet(isPresented: $showsAchievements) {
            NavigationStack {
                AchievementsView(
                    language: launcher.language, records: launcher.achievements,
                    stamps: launcher.stationStamps, railways: launcher.railways, placeNames: launcher.placeNames
                )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                showsAchievements = false
                            } label: {
                                Text(verbatim: launcher.language.text("Done", "完成"))
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showsSaves) {
            SaveListView(launcher: launcher)
        }
        .sheet(isPresented: $choosesLesson) {
            LessonPicker(launcher: launcher)
        }
        .sheet(isPresented: $choosesDemo) {
            DemoPicker(launcher: launcher, loadingDetail: loadingDetail)
        }
        .sheet(isPresented: $showsWhatsNew, onDismiss: launcher.dismissWhatsNew) {
            WhatsNewView(language: launcher.language)
        }
        .onAppear {
            launcher.refresh()
            if launcher.showsWhatsNew { showsWhatsNew = true }
        }
    }

    /// The ways into a game (decision 381: ``StartMenuEntry``).
    private var buttons: some View {
        VStack(spacing: 12) {
            if launcher.showsFirstGameCard {
                firstGameCard
            }
            ForEach(StartMenuEntry.entries(hasAutosave: launcher.autosave != nil), id: \.self) { entry in
                button(entry)
                    // Stable across localizations for the UI tests.
                    .accessibilityIdentifier(entry.identifier)
            }
            // Decision 397, later: whether the saves are in iCloud.
            CloudSaveStatusLine(launcher: launcher, identifier: "start.syncNow")
        }
    }

    /// One of the start screen's buttons.
    @ViewBuilder private func button(_ entry: StartMenuEntry) -> some View {
        let language = launcher.language
        switch entry {
        case .continueGame:
            if let autosave = launcher.autosave {
                StartButton(
                    title: String(localized: "Continue"),
                    detail: detail(of: autosave),
                    systemImage: "play.fill",
                    isPrimary: true,
                    tone: .primary
                ) {
                    UITestTrace.action("start.continue")
                    launcher.continueGame()
                }
            }
        case .newGame:
            // Decision 316: one way into a new game, on a blank or a
            // real-world map, with the options both start with; since
            // decision 381 the challenges too.
            StartButton(
                title: String(localized: "New Game"),
                detail: NewGameChoice.entryDetail(in: language),
                systemImage: "plus",
                isPrimary: launcher.autosave == nil,
                tone: .primary
            ) {
                choosesNewGame = true
            }
        case .lessons:
            // Decision 266: the lessons, where the tutorial was: its steps
            // are the first lessons' guide.
            StartButton(
                title: language.text(
                    "Lessons · ★ \(launcher.lessonStarTotal)/\(3 * Lesson.all.count)",
                    "入門 · ★ \(launcher.lessonStarTotal)/\(3 * Lesson.all.count)"
                ),
                detail: language.text(
                    "Short games that teach one thing each: build, run, and earn up to 3 stars",
                    "一關教一件事的短遊戲：蓋、開、賺，最多拿 3 顆星"
                ),
                systemImage: "hand.point.up.left",
                tone: .accent
            ) {
                choosesLesson = true
            }
        case .demoMap:
            // Decision 135: both demos behind one button, so the start
            // screen keeps to the ways into a game of one's own.
            StartButton(
                title: String(localized: "Demo Map"),
                detail: String(localized: "Railways already built and running: Taiwan’s real lines, or a simple one to try things on"),
                systemImage: "tram.fill",
                tone: .accent
            ) {
                choosesDemo = true
            }
        case .saves:
            // Decision 381: the saves and importing one, in one list;
            // decision 192: the older autosaves are listed there too.
            StartButton(
                title: StartMenuEntry.savesTitle(in: language),
                detail: StartMenuEntry.savesDetail(
                    count: launcher.otherSaves.count + launcher.olderAutosaves.count, in: language
                ),
                systemImage: "tray.full",
                tone: .plain
            ) {
                showsSaves = true
            }
        case .achievements:
            // Decision 181: what the player has done across games.
            StartButton(
                title: language.text(
                    "Achievements \(launcher.achievements.count)/\(Achievement.all.count)",
                    "成就 \(launcher.achievements.count)/\(Achievement.all.count)"
                ),
                detail: language.text(
                    "Milestones of your own games, kept on this device",
                    "你自己的遊戲裡達成的里程碑，記錄在這台裝置上"
                ),
                systemImage: "rosette",
                tone: .plain
            ) {
                showsAchievements = true
            }
        }
    }

    /// Decision 177: to a player who has not finished the tutorial or closed
    /// this card, the first line with the station master, at the top of the
    /// start screen.
    private var firstGameCard: some View {
        let language = launcher.language
        return HStack(alignment: .top, spacing: 12) {
            StationMasterAvatar(size: 56, mood: .happy)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: language.text("First time? Build your first line with the station master (about 5 minutes)", "第一次玩？跟站長蓋第一條線（約 5 分鐘）"))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    launcher.startTutorial()
                } label: {
                    Text(verbatim: language.text("Start Lesson 1", "開始第 1 關"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.onPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.primary, in: Capsule())
                }
                .accessibilityIdentifier("start.firstGame.start")
            }
            Spacer(minLength: 0)
            Button {
                launcher.dismissFirstGameCard()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(verbatim: language.text("Close", "關閉")))
            .accessibilityIdentifier("start.firstGame.dismiss")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent, lineWidth: 2))
        .accessibilityIdentifier("start.firstGame")
    }

    /// The last message, and Help and Settings.
    @ViewBuilder private var footer: some View {
        if let message = launcher.message {
            HStack(spacing: 8) {
                Image(systemName: message.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.bold))
                Text(message.text)
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(message.kind == .success ? Theme.success : Theme.warning)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder((message.kind == .success ? Theme.success : Theme.warning).opacity(0.5), lineWidth: 1))
        }
        // One row while it fits; with large text on a phone, a
        // column, rather than squeezing the labels.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { chips }
            VStack(spacing: 10) { chips }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            // The app icon, light or dark with the appearance.
            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text("Along the Line")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("start.brand")
            Text("Along the Line is a railway and city-building simulation where the railway shapes the growth of the city.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    /// What a real-world button says while the real-world data is read.
    private var loadingDetail: String {
        launcher.language.text("Reading the real-world data…", "正在讀取實景資料…")
    }

    /// Help and Settings, under the start screen's buttons (decision 381:
    /// the language is in Settings, the data sources in Help).
    @ViewBuilder private var chips: some View {
        // Decision 177: the help guide, searchable.
        Button {
            showsHelp = true
        } label: {
            chip(Label {
                Text(verbatim: launcher.language.text("Help", "說明"))
            } icon: {
                Image(systemName: "questionmark.circle")
            })
        }
        .accessibilityIdentifier(StartMenuChip.help.identifier)
        // The language, the music and sound effects; the game menu opens
        // the same settings.
        Button {
            showsSettings = true
        } label: {
            chip(Label("Settings", systemImage: "gearshape"))
        }
        .accessibilityIdentifier(StartMenuChip.settings.identifier)
    }

    /// A small capsule under the start buttons.
    private func chip(_ label: some View) -> some View {
        label
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.panelBorder, lineWidth: 1))
    }

    /// The save's game time, cash and size, and when it was saved, and
    /// how long ago (decision 192).
    private func detail(of entry: SaveLibrary.Entry) -> String {
        let summary = entry.summary?.text(in: launcher.language) ?? ""
        guard let savedAt = entry.savedAt else { return summary }
        let ago = SaveLibrary.agoText(from: savedAt, to: Date(), in: launcher.language)
        return "\(summary)\n\(String(localized: "Saved \(savedAt.formatted(date: .abbreviated, time: .shortened))")) · \(ago)"
    }
}

/// The start screen's demos (decision 135), the real-world one first: the
/// game as it looks on Taiwan's real lines, then the High Speed Rail
/// (decision 170), then the simple demo, a small network to try things on.
private struct DemoPicker: View {
    let launcher: GameLauncher
    /// What the real-world demo says while the real-world data is read.
    let loadingDetail: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    StartButton(
                        title: String(localized: "Real-World Demo"),
                        detail: launcher.isLoadingRealWorldData ? loadingDetail : String(localized: "Taiwan’s Yilan, Western Trunk, Pingxi and Shenao Lines, built on their real track over the real ground and running"),
                        systemImage: "map.fill",
                        tone: .accent
                    ) {
                        if let railways = launcher.railways {
                            dismiss()
                            launcher.openRealWorldDemo(railways: railways)
                        }
                    }
                    // Without the railways' files (listed on the data
                    // sources screen) there is no demo to open.
                    .disabled(launcher.railways == nil)
                    .accessibilityIdentifier("demo.realWorld")
                    // Decision 170: the Taiwan High Speed Rail, built on its
                    // real alignment. It takes seconds to build, so the
                    // sheet stays up, saying so, until the game begins.
                    StartButton(
                        title: String(localized: "High-Speed Rail Demo"),
                        detail: launcher.isOpeningHighSpeedDemo
                            ? String(localized: "Building the High Speed Rail…")
                            : launcher.isLoadingRealWorldData
                            ? loadingDetail
                            : String(localized: "The Taiwan High Speed Rail from Nangang to Zuoying, built on its real alignment with its three stopping patterns running"),
                        systemImage: "bolt.fill",
                        tone: .accent
                    ) {
                        if let railways = launcher.railways {
                            Task { @MainActor in
                                await launcher.openHighSpeedDemo(railways: railways)?.value
                                dismiss()
                            }
                        }
                    }
                    .disabled(launcher.railways == nil || launcher.isOpeningADemo)
                    .accessibilityIdentifier("demo.highSpeed")
                    StartButton(
                        title: String(localized: "Simple Demo"),
                        detail: String(localized: "Three lines already running, in a city that grows"),
                        systemImage: "tram.fill",
                        tone: .accent
                    ) {
                        dismiss()
                        launcher.openDemo()
                    }
                    .accessibilityIdentifier("demo.simple")
                    // Decision 240: the Yilan Line running a weekday's real
                    // trains, built as the high-speed demo is.
                    StartButton(
                        title: String(localized: "TRA Demo"),
                        detail: launcher.isOpeningTRADemo
                            ? String(localized: "Building the Yilan Line…")
                            : launcher.isLoadingRealWorldData
                            ? loadingDetail
                            : String(localized: "The Taiwan Railway’s Yilan Line from Toucheng to Su’aoxin, built on its real alignment with a weekday’s real trains running"),
                        systemImage: "tram.circle.fill",
                        tone: .accent
                    ) {
                        if let railways = launcher.railways {
                            Task { @MainActor in
                                await launcher.openTRADemo(railways: railways)?.value
                                dismiss()
                            }
                        }
                    }
                    .disabled(launcher.railways == nil || launcher.isOpeningADemo)
                    .accessibilityIdentifier("demo.tra")
                }
                .frame(maxWidth: 420)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("Demo Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Decision 316: the new game's page, the maps a new game can start on
/// (``NewGameChoice``): a blank map, which starts at once, and a real-world
/// map, which opens the place picker (decision 312). Under them, the
/// new game's options (decision 177), which both start with. Last, the
/// challenges (decision 381; decision 86: a new game with goals), which
/// were a start screen button of their own.
private struct NewGamePicker: View {
    let launcher: GameLauncher
    /// What the real-world map says while the real-world data is read.
    let loadingDetail: String
    @State private var choosesPlace = false
    @State private var choosesChallenge = false
    @State private var showsOptions = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let language = launcher.language
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(NewGameChoice.allCases, id: \.self) { choice in
                        // The real-world maps wait for the real-world data,
                        // read in the background at launch: a game started
                        // before it is would have no people on its map.
                        let waits = choice == .realWorld && launcher.isLoadingRealWorldData
                        StartButton(
                            title: choice.title(in: language),
                            detail: waits ? loadingDetail : choice.detail(in: language, options: launcher.newGameOptions),
                            systemImage: choice.systemImage,
                            isPrimary: choice == .blank,
                            tone: .primary
                        ) {
                            switch choice {
                            case .blank:
                                dismiss()
                                launcher.startNewGame()
                            case .realWorld:
                                choosesPlace = true
                            }
                        }
                        .disabled(waits)
                        .accessibilityIdentifier(choice.identifier)
                    }
                    VStack(spacing: 2) {
                        Button {
                            showsOptions = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                Text(verbatim: NewGameChoice.optionsSummary(launcher.newGameOptions, in: language))
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .accessibilityIdentifier("start.newGameOptions")
                        Text(verbatim: NewGameChoice.optionsNote(in: language))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 4)
                    // After the options, which challenges set themselves.
                    StartButton(
                        title: NewGameChoice.challengesTitle(in: language),
                        detail: NewGameChoice.challengesDetail(in: language),
                        systemImage: "flag.checkered",
                        tone: .accent
                    ) {
                        choosesChallenge = true
                    }
                    .padding(.top, 8)
                    .accessibilityIdentifier(NewGameChoice.challengesIdentifier)
                }
                .frame(maxWidth: 420)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showsOptions) {
            NewGameOptionsView(launcher: launcher)
        }
        .sheet(isPresented: $choosesPlace) {
            RealWorldPicker(launcher: launcher)
        }
        .sheet(isPresented: $choosesChallenge) {
            ChallengePicker(launcher: launcher)
        }
        // A challenge started from the picker above leaves the start
        // screen: this page closes with it.
        .onChange(of: launcher.session != nil) { _, isPlaying in
            if isPlaying { dismiss() }
        }
        // A7 of the #873–#910 review: once a real-world map is being built,
        // this page closes with the place picker on it, so the loading
        // screen (decision 307) is not drawn under it and a blank map
        // cannot be started meanwhile.
        .onChange(of: launcher.realWorldLoading != nil) { _, isBuilding in
            if isBuilding { dismiss() }
        }
    }
}

/// One choice on the start screen: a title over what it does, beside an
/// icon on a flat tile in the app icon's colours.
private struct StartButton: View {
    /// The icon's tile: teal for starting a game, the icon's warm yellow for
    /// the guided and ready-made games, a light teal for the rest.
    enum Tone {
        case primary, accent, plain
    }

    let title: String
    let detail: String
    let systemImage: String
    var isPrimary = false
    var tone = Tone.plain
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tileColor)
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.body.weight(.bold))
                        .foregroundStyle(iconColor)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isPrimary ? Theme.primary : Theme.panelBorder,
                        lineWidth: isPrimary ? 2 : 1
                    )
            }
        }
        .buttonStyle(CardTapButtonStyle())
        .accessibilityElement(children: .combine)
    }

    private var tileColor: Color {
        switch tone {
        case .primary: Theme.primary
        case .accent: Theme.accent
        case .plain: Theme.primary.opacity(0.14)
        }
    }

    private var iconColor: Color {
        switch tone {
        case .primary: Theme.onPrimary
        case .accent: Theme.onAccent
        case .plain: Theme.primary
        }
    }
}

private struct CardTapButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Decision 253: with Reduce Motion it only dims.
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1.0) : 0.5)
            .animation(MotionRule.press.running(reduceMotion: reduceMotion)?.animation, value: configuration.isPressed)
    }
}

/// The player's saves, and autosaves that cannot be loaded: tap one to
/// load it. A save that cannot be loaded says why. Since decision 184 each
/// row shows the game's date and funds, the list can be ordered by date or
/// name, a save can be named (swipe, or hold it), and deleting one asks
/// first. Since decision 192 the older autosaves come first, the newest
/// first, each saying how long ago it was saved: loading one goes back to
/// the game as it was then. Since decision 381 it is the start screen's
/// Saves, and imports a save file too (the start screen's Import a Save
/// was): a row at its top, or the empty list's button.
struct SaveListView: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss
    /// Whether Files is open to choose a save file.
    @State private var importsSave = false
    /// How the saves are ordered; kept for the next time.
    @AppStorage("saveListOrder") private var order: SaveLibrary.Order = .newest
    /// The save being named, and the name being typed.
    @State private var renaming: SaveLibrary.Entry?
    @State private var newName = ""
    /// The save the player asked to delete, while the question is up.
    @State private var deleting: SaveLibrary.Entry?

    var body: some View {
        let language = launcher.language
        let saves = SaveLibrary.sorted(launcher.otherSaves, by: order)
        let isEmpty = launcher.otherSaves.isEmpty && launcher.olderAutosaves.isEmpty
        NavigationStack {
            List {
                if let message = launcher.message {
                    Section {
                        Label(message.text, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
                // With no save, the empty list's own button imports one.
                if !isEmpty {
                    Section {
                        importButton
                    }
                }
                // Decision 397, later: whether the saves are in iCloud, and
                // Sync Now.
                if !isEmpty, launcher.cloudSaves.systemImage != nil {
                    Section {
                        CloudSaveStatusLine(launcher: launcher, identifier: "saves.syncNow")
                    }
                }
                if !launcher.olderAutosaves.isEmpty {
                    Section {
                        ForEach(launcher.olderAutosaves) { entry in
                            rowWithMenu(entry)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleting = entry
                                    } label: {
                                        Label {
                                            Text(verbatim: language.text("Delete", "刪除"))
                                        } icon: {
                                            Image(systemName: "trash")
                                        }
                                    }
                                }
                        }
                    } header: {
                        Text(verbatim: language.text("Earlier Autosaves", "之前的自動存檔"))
                    } footer: {
                        Text(verbatim: language.text(
                            "One every 15 minutes of play, the last \(SaveLibrary.autosaveSlots) kept. Going back keeps the game you leave as an autosave too.",
                            "遊戲中每 15 分鐘存一份，保留最近 \(SaveLibrary.autosaveSlots) 份。回到之前時，離開的進度也會存成一份自動存檔。"
                        ))
                    }
                }
                Section {
                    ForEach(saves) { entry in
                        rowWithMenu(entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleting = entry
                                } label: {
                                    Label {
                                        Text(verbatim: language.text("Delete", "刪除"))
                                    } icon: {
                                        Image(systemName: "trash")
                                    }
                                }
                                if entry.kind == .manual {
                                    Button {
                                        startRenaming(entry)
                                    } label: {
                                        Label {
                                            Text(verbatim: language.text("Rename", "重新命名"))
                                        } icon: {
                                            Image(systemName: "pencil")
                                        }
                                    }
                                    .tint(Theme.primary)
                                }
                            }
                            .contextMenu {
                                if entry.kind == .manual {
                                    Button {
                                        startRenaming(entry)
                                    } label: {
                                        Label {
                                            Text(verbatim: language.text("Rename", "重新命名"))
                                        } icon: {
                                            Image(systemName: "pencil")
                                        }
                                    }
                                }
                                Button(role: .destructive) {
                                    deleting = entry
                                } label: {
                                    Label {
                                        Text(verbatim: language.text("Delete", "刪除"))
                                    } icon: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                    }
                }
            }
            .overlay {
                if isEmpty {
                    // Decision 122, later: the game's own picture, not the system's tray.
                    ContentUnavailableView {
                        Label {
                            Text(verbatim: language.text("No Saves Yet", "還沒有存檔"))
                        } icon: {
                            Image("EmptySaves")
                                .resizable()
                                .frame(width: 96, height: 96)
                                .accessibilityHidden(true)
                        }
                    } description: {
                        Text(verbatim: SaveListText.importDetail(in: language))
                    } actions: {
                        Button {
                            importsSave = true
                        } label: {
                            Label {
                                Text(verbatim: SaveListText.importTitle(in: language))
                            } icon: {
                                Image(systemName: "square.and.arrow.down")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .accessibilityIdentifier(SaveListText.importIdentifier)
                    }
                }
            }
            .fileImporter(isPresented: $importsSave, allowedContentTypes: [.alongTheLineSave, .json]) { result in
                launcher.importSave {
                    let url = try result.get()
                    // A file from Files is outside the app's container.
                    let isScoped = url.startAccessingSecurityScopedResource()
                    defer {
                        if isScoped { url.stopAccessingSecurityScopedResource() }
                    }
                    return try Data(contentsOf: url)
                }
            }
            // Decision 419: a save is read off the main thread. One that
            // was read opens and closes this list; one that was not says
            // why at the top of it. One slow to read closes it as the
            // loading screen comes up, so the screen is not drawn under it.
            .onChange(of: launcher.session != nil || launcher.realWorldLoading != nil) { _, isOpening in
                if isOpening { dismiss() }
            }
            .allowsHitTesting(!launcher.isLoadingSave)
            .navigationTitle(SaveListText.title(in: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(selection: $order) {
                            ForEach(SaveLibrary.Order.allCases, id: \.self) { order in
                                Text(verbatim: order.displayName(in: language)).tag(order)
                            }
                        } label: {
                            Text(verbatim: language.text("Sort by", "排序"))
                        }
                    } label: {
                        Label {
                            Text(verbatim: language.text("Sort", "排序"))
                        } icon: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                    .accessibilityIdentifier("saves.sort")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                Text(verbatim: language.text("Name This Save", "為存檔命名")),
                isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
            ) {
                TextField(text: $newName) {
                    Text(verbatim: language.text("Name", "名稱"))
                }
                .accessibilityIdentifier("saves.rename.field")
                Button(role: .cancel) {
                    renaming = nil
                } label: {
                    Text(verbatim: language.text("Cancel", "取消"))
                }
                Button {
                    if let entry = renaming {
                        launcher.rename(entry, to: newName)
                    }
                    renaming = nil
                } label: {
                    Text(verbatim: language.text("Save", "儲存"))
                }
                .accessibilityIdentifier("saves.rename.confirm")
            } message: {
                Text(verbatim: language.text(
                    "Leave it empty to name the save by when it was saved.",
                    "留白則以儲存時間當作名稱。"
                ))
            }
            .confirmationDialog(
                Text(verbatim: language.text("Delete this save?", "要刪除這個存檔嗎？")),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { entry in
                Button(role: .destructive) {
                    launcher.delete(entry)
                    deleting = nil
                } label: {
                    Text(verbatim: language.text("Delete \"\(title(of: entry))\"", "刪除「\(title(of: entry))」"))
                }
                .accessibilityIdentifier("saves.delete.confirm")
                Button(role: .cancel) {
                    deleting = nil
                } label: {
                    Text(verbatim: language.text("Cancel", "取消"))
                }
            } message: { _ in
                Text(verbatim: language.text("A deleted save cannot be brought back.", "刪除後無法復原。"))
            }
        }
    }

    /// A save's row: tap it to load it; its "⋯" button (decision 381)
    /// holds what its swipe and long press do, so they can be seen.
    private func rowWithMenu(_ entry: SaveLibrary.Entry) -> some View {
        HStack(spacing: 8) {
            Button {
                launcher.load(entry)
            } label: {
                row(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(entry.problem != nil)
            .accessibilityIdentifier("saves.row.\(entry.id)")
            rowMenu(entry)
        }
    }

    /// The row's "⋯" menu: rename (the player's own saves), export, and
    /// delete, which asks first (``SaveListText/RowAction``).
    private func rowMenu(_ entry: SaveLibrary.Entry) -> some View {
        let language = launcher.language
        return Menu {
            ForEach(SaveListText.RowAction.available(for: entry), id: \.self) { action in
                switch action {
                case .rename:
                    Button {
                        startRenaming(entry)
                    } label: {
                        Label(action.title(in: language), systemImage: action.systemImage)
                    }
                case .export:
                    ShareLink(
                        item: ExportedListSave(library: launcher.saveLibrary, entry: entry),
                        preview: SharePreview(Text(verbatim: title(of: entry)))
                    ) {
                        Label(action.title(in: language), systemImage: action.systemImage)
                    }
                case .delete:
                    Button(role: .destructive) {
                        deleting = entry
                    } label: {
                        Label(action.title(in: language), systemImage: action.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(Theme.primary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(verbatim: SaveListText.rowMenuLabel(in: language)))
        .accessibilityIdentifier(SaveListText.rowMenuIdentifier(of: entry))
    }

    /// The row that imports a save file, at the top of a list with saves.
    private var importButton: some View {
        let language = launcher.language
        return Button {
            importsSave = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.primary.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: "square.and.arrow.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: SaveListText.importTitle(in: language))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(verbatim: SaveListText.importDetail(in: language))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SaveListText.importIdentifier)
    }

    private func startRenaming(_ entry: SaveLibrary.Entry) {
        newName = entry.name ?? ""
        renaming = entry
    }

    private func row(_ entry: SaveLibrary.Entry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(entry.problem != nil ? Theme.warning.opacity(0.14) : (entry.kind == .autosave ? Theme.accent : Theme.primary))
                    .frame(width: 36, height: 36)
                Image(systemName: entry.problem != nil ? "exclamationmark.triangle.fill" : (entry.kind == .autosave ? "clock.arrow.circlepath" : "tram.fill"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(entry.problem != nil ? Theme.warning : (entry.kind == .autosave ? Theme.onAccent : Theme.onPrimary))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title(of: entry))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(entry.problem == nil ? Theme.textPrimary : Theme.textSecondary)
                // Decision 192: an autosave says how long ago it was saved,
                // by the clock on the wall, kept current while it shows.
                if entry.kind == .autosave, let savedAt = entry.savedAt {
                    TimelineView(.everyMinute) { context in
                        Text(verbatim: "\(SaveLibrary.agoText(from: savedAt, to: context.date, in: launcher.language)) · \(savedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                // A named save says when it was saved too.
                if entry.name != nil, let savedAt = entry.savedAt {
                    Text(verbatim: savedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let problem = entry.problem {
                    Text(problem.playerMessage(in: launcher.language))
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                } else if let summary = entry.summary {
                    Text(verbatim: summary.dateAndFundsText(in: launcher.language))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                    Text(verbatim: summary.networkText(in: launcher.language))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                // Decision 397, later: whether another device gets it.
                if let mark = launcher.cloudMark(of: entry) {
                    Label {
                        Text(verbatim: mark.text(in: launcher.language))
                    } icon: {
                        Image(systemName: mark.systemImage)
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func title(of entry: SaveLibrary.Entry) -> String {
        if entry.kind == .autosave {
            return String(localized: "Autosave")
        }
        if let name = entry.name {
            return name
        }
        return entry.savedAt?.formatted(date: .abbreviated, time: .shortened) ?? entry.id
    }
}

/// A save in the list as a file to share (decision 381), written when the
/// player shares it, as the game menu's Export Save writes the game being
/// played.
private struct ExportedListSave: Transferable {
    let library: SaveLibrary
    let entry: SaveLibrary.Entry

    static var transferRepresentation: some TransferRepresentation {
        // Review I: the game's own type, as the game menu's export
        // (decision 409).
        FileRepresentation(exportedContentType: .alongTheLineSave) { save in
            SentTransferredFile(try save.library.exportFile(of: save.entry))
        }
    }
}

/// Decision 397, later: whether the saves are in the player's iCloud
/// (``CloudSaves``), with a button that syncs at once. Nothing in a build
/// without iCloud.
private struct CloudSaveStatusLine: View {
    let launcher: GameLauncher
    /// The Sync Now button's, stable across localizations.
    let identifier: String

    var body: some View {
        let language = launcher.language
        let status = launcher.cloudSaves
        if let image = status.systemImage {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: image)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(status == .incomplete || status == .iCloudOff ? Theme.warning : Theme.primary)
                    .accessibilityHidden(true)
                // A time said as "5 min ago", kept current while it shows.
                TimelineView(.everyMinute) { context in
                    Text(verbatim: status.footnote(in: language, now: context.date) ?? "")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    launcher.syncNow()
                } label: {
                    Text(verbatim: language.text("Sync Now", "立即同步"))
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 32)
                }
                .buttonStyle(.bordered)
                .tint(Theme.primary)
                .disabled(!status.canSyncNow)
                .accessibilityIdentifier(identifier)
            }
        }
    }
}
