import GameCore
import GamePresentation
import SwiftUI
import UniformTypeIdentifiers

/// The start screen (Stage C4), after the `Ci/` reference's home screen and
/// its saved-game card (`screen-save-load-ui`: go on with the saved game,
/// or start fresh): continue the autosave, start a new game on a blank or a
/// real-world map (Stage E2; decision 316: both behind New Game), open one
/// of the demos (decision 135: the
/// real-world demo of Taiwan's real lines, or the simple demo), load one of
/// the saves or import a save file.
///
/// Every action calls a ``GameLauncher`` method; the screen keeps nothing
/// of the games but what it shows.
struct StartView: View {
    let launcher: GameLauncher
    @State private var showsSaves = false
    @State private var importsSave = false
    /// Decision 316: the new game's page, blank or real-world.
    @State private var choosesNewGame = false
    @State private var choosesChallenge = false
    /// Decision 266: the lessons, in place of the tutorial.
    @State private var choosesLesson = false
    @State private var choosesDemo = false
    @State private var showsDataSources = false
    @State private var showsSettings = false
    @State private var showsHelp = false
    @State private var showsAchievements = false
    /// The language menu's choice, read from the app's settings.
    @State private var languageChoice = LanguageChoice.saved
    /// What the player is told after choosing a language: it takes effect
    /// the next time the game opens.
    @State private var languageNote: String?
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
            SettingsView(audio: audio, lessons: launcher.lessonReport(in: .app))
        }
        .sheet(isPresented: $showsHelp) {
            HelpView(language: launcher.language)
        }
        .sheet(isPresented: $choosesNewGame) {
            NewGamePicker(launcher: launcher, loadingDetail: loadingDetail)
        }
        .sheet(isPresented: $showsAchievements) {
            NavigationStack {
                AchievementsView(
                    language: launcher.language, records: launcher.achievements,
                    stamps: launcher.stationStamps, railways: launcher.railways
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
        .sheet(isPresented: $choosesChallenge) {
            ChallengePicker(launcher: launcher)
        }
        .sheet(isPresented: $choosesLesson) {
            LessonPicker(launcher: launcher)
        }
        .sheet(isPresented: $choosesDemo) {
            DemoPicker(launcher: launcher, loadingDetail: loadingDetail)
        }
        .sheet(isPresented: $showsDataSources) {
            DataSourcesView(launcher: launcher)
        }
        .fileImporter(isPresented: $importsSave, allowedContentTypes: [.json]) { result in
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
        .onAppear {
            launcher.refresh()
        }
    }

    /// The ways into a game.
    private var buttons: some View {
        VStack(spacing: 12) {
            if launcher.showsFirstGameCard {
                firstGameCard
            }
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
                .accessibilityIdentifier("start.continue")
            }
            // Decision 316: one way into a new game, on a blank or a
            // real-world map, with the options both start with.
            StartButton(
                title: String(localized: "New Game"),
                detail: NewGameChoice.entryDetail(in: launcher.language),
                systemImage: "plus",
                isPrimary: launcher.autosave == nil,
                tone: .primary
            ) {
                choosesNewGame = true
            }
            // Stable across localizations for the UI smoke tests.
            .accessibilityIdentifier("start.newGame")
            // Decision 266: the lessons, where the tutorial was: its steps
            // are the first lessons' guide.
            StartButton(
                title: launcher.language.text(
                    "Lessons · ★ \(launcher.lessonStarTotal)/\(3 * Lesson.all.count)",
                    "入門 · ★ \(launcher.lessonStarTotal)/\(3 * Lesson.all.count)"
                ),
                detail: launcher.language.text(
                    "Short games that teach one thing each: build, run, and earn up to 3 stars",
                    "一關教一件事的短遊戲：蓋、開、賺，最多拿 3 顆星"
                ),
                systemImage: "hand.point.up.left",
                tone: .accent
            ) {
                choosesLesson = true
            }
            .accessibilityIdentifier("start.lessons")
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
            .accessibilityIdentifier("start.demoMap")
            // Decision 192: the older autosaves are listed there too.
            if !launcher.otherSaves.isEmpty || !launcher.olderAutosaves.isEmpty {
                StartButton(
                    title: String(localized: "Saved Games"),
                    detail: String(localized: "\(launcher.otherSaves.count + launcher.olderAutosaves.count) saves"),
                    systemImage: "tray.full",
                    tone: .plain
                ) {
                    showsSaves = true
                }
                .accessibilityIdentifier("start.savedGames")
            }
            StartButton(
                title: String(localized: "Import a Save"),
                detail: String(localized: "A save file from Files or another device"),
                systemImage: "square.and.arrow.down",
                tone: .plain
            ) {
                importsSave = true
            }
            // Decision 86: a new game with goals. Last, after the
            // buttons the UI tests reach.
            StartButton(
                title: launcher.language.text("Challenges", "挑戰"),
                detail: launcher.language.text(
                    "Goals to reach by a deadline, rated gold, silver or bronze",
                    "在期限內達成目標，依完成速度拿金、銀、銅牌"
                ),
                systemImage: "flag.checkered",
                tone: .accent
            ) {
                choosesChallenge = true
            }
            .accessibilityIdentifier("start.challenges")
            // Decision 181: what the player has done across games.
            StartButton(
                title: launcher.language.text(
                    "Achievements \(launcher.achievements.count)/\(Achievement.all.count)",
                    "成就 \(launcher.achievements.count)/\(Achievement.all.count)"
                ),
                detail: launcher.language.text(
                    "Milestones of your own games, kept on this device",
                    "你自己的遊戲裡達成的里程碑，記錄在這台裝置上"
                ),
                systemImage: "rosette",
                tone: .plain
            ) {
                showsAchievements = true
            }
            .accessibilityIdentifier("start.achievements")
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

    /// The last message, and Language, Data Sources and Settings.
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

    /// Language, Data Sources and Settings, under the start screen's
    /// buttons.
    @ViewBuilder private var chips: some View {
        // Decision 257: the game's own language menu, as on the
        // reference's home screen (iOS shows an app's language in
        // Settings only on a device with two or more languages).
        Menu {
            Picker(selection: languageChoiceBinding) {
                ForEach(LanguageChoice.allCases, id: \.self) { choice in
                    Text(verbatim: choice.title(in: launcher.language)).tag(choice)
                }
            } label: {
                EmptyView()
            }
        } label: {
            chip(Label("Language", systemImage: "globe"))
        }
        .accessibilityIdentifier("start.language")
        .accessibilityHint(Text(verbatim: launcher.language.text("Chooses the game's language.", "選擇遊戲的語言。")))
        .alert(
            Text(verbatim: launcher.language.text("Language", "語言")),
            isPresented: Binding(get: { languageNote != nil }, set: { if !$0 { languageNote = nil } })
        ) {
            Button {
                languageNote = nil
            } label: {
                Text(verbatim: launcher.language.text("OK", "好"))
            }
        } message: {
            Text(verbatim: languageNote ?? "")
        }
        // Where the real-world data comes from (the `Railway/`
        // site's data sources page).
        Button {
            showsDataSources = true
        } label: {
            chip(Label("Data Sources", systemImage: "info.circle"))
        }
        .accessibilityIdentifier("start.dataSources")
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
        .accessibilityIdentifier("start.help")
        // The music and sound effects on or off; the game
        // menu opens the same settings.
        Button {
            showsSettings = true
        } label: {
            chip(Label("Settings", systemImage: "gearshape"))
        }
        .accessibilityIdentifier("start.settings")
    }

    /// The language menu's selection: saves the choice, and tells the
    /// player to reopen the game when the language may change.
    private var languageChoiceBinding: Binding<LanguageChoice> {
        Binding {
            languageChoice
        } set: { choice in
            if choice.needsRestart(from: languageChoice, showing: launcher.language) {
                languageNote = choice.restartNote(in: launcher.language)
            }
            languageChoice = choice
            choice.save()
        }
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
/// new game's options (decision 177), which both start with.
private struct NewGamePicker: View {
    let launcher: GameLauncher
    /// What the real-world map says while the real-world data is read.
    let loadingDetail: String
    @State private var choosesPlace = false
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
/// the game as it was then.
struct SaveListView: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            List {
                if let message = launcher.message {
                    Section {
                        Label(message.text, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
                if !launcher.olderAutosaves.isEmpty {
                    Section {
                        ForEach(launcher.olderAutosaves) { entry in
                            Button {
                                launcher.load(entry)
                                if launcher.session != nil {
                                    dismiss()
                                }
                            } label: {
                                row(entry)
                            }
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
                            .accessibilityIdentifier("saves.row.\(entry.id)")
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
                        Button {
                            launcher.load(entry)
                            if launcher.session != nil {
                                dismiss()
                            }
                        } label: {
                            row(entry)
                        }
                        .disabled(entry.problem != nil)
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
                        .accessibilityIdentifier("saves.row.\(entry.id)")
                    }
                }
            }
            .overlay {
                if launcher.otherSaves.isEmpty && launcher.olderAutosaves.isEmpty {
                    // Decision 122, later: the game's own picture, not the system's tray.
                    ContentUnavailableView {
                        Label {
                            Text("No Saved Games")
                        } icon: {
                            Image("EmptySaves")
                                .resizable()
                                .frame(width: 96, height: 96)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .navigationTitle("Saved Games")
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
