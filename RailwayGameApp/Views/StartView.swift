import GameCore
import GamePresentation
import SwiftUI
import UniformTypeIdentifiers

/// The start screen (Stage C4), after the `Ci/` reference's home screen and
/// its saved-game card (`screen-save-load-ui`: go on with the saved game,
/// or start fresh): continue the autosave, start a new game on a blank or a
/// real-world map (Stage E2), open the demo map, load one of the saves or
/// import a save file, or open the real-world demo (Taiwan's real lines
/// built and running).
///
/// Every action calls a ``GameLauncher`` method; the screen keeps nothing
/// of the games but what it shows.
struct StartView: View {
    let launcher: GameLauncher
    @State private var showsSaves = false
    @State private var importsSave = false
    @State private var choosesPlace = false
    @State private var showsDataSources = false
    @State private var showsSettings = false
    @Environment(\.openURL) private var openURL
    @Environment(GameAudio.self) private var audio

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                VStack(spacing: 12) {
                    if let autosave = launcher.autosave {
                        StartButton(
                            title: String(localized: "Continue"),
                            detail: detail(of: autosave),
                            systemImage: "play.fill",
                            isPrimary: true,
                            tone: .primary
                        ) {
                            launcher.continueGame()
                        }
                        .accessibilityIdentifier("start.continue")
                    }
                    StartButton(
                        title: String(localized: "New Game"),
                        detail: String(localized: "An empty map and \(GameWorld.newGame().economy.balance.moneyText) to build with"),
                        systemImage: "plus",
                        isPrimary: launcher.autosave == nil,
                        tone: .primary
                    ) {
                        launcher.startNewGame()
                    }
                    // Stable across localizations for the UI smoke tests.
                    .accessibilityIdentifier("start.newGame")
                    // The real-world maps wait for the real-world data,
                    // read in the background at launch: a game started
                    // before it is would have no people on its map.
                    StartButton(
                        title: String(localized: "Real-World Map"),
                        detail: launcher.isLoadingRealWorldData ? loadingDetail : String(localized: "Build on a map of a real place"),
                        systemImage: "globe.asia.australia",
                        tone: .plain
                    ) {
                        choosesPlace = true
                    }
                    .disabled(launcher.isLoadingRealWorldData)
                    .accessibilityIdentifier("start.realWorld")
                    StartButton(
                        title: String(localized: "Tutorial"),
                        detail: String(localized: "Learn to build and run a railway step by step"),
                        systemImage: "hand.point.up.left",
                        tone: .accent
                    ) {
                        launcher.startTutorial()
                    }
                    .accessibilityIdentifier("start.tutorial")
                    StartButton(
                        title: String(localized: "Demo Map"),
                        detail: String(localized: "Three lines already running, in a city that grows"),
                        systemImage: "tram.fill",
                        tone: .accent
                    ) {
                        launcher.openDemo()
                    }
                    .accessibilityIdentifier("start.demoMap")
                    if !launcher.otherSaves.isEmpty {
                        StartButton(
                            title: String(localized: "Saved Games"),
                            detail: String(localized: "\(launcher.otherSaves.count) saves"),
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
                    // Last, so the buttons the UI tests reach stay where
                    // they were.
                    StartButton(
                        title: String(localized: "Real-World Demo"),
                        detail: launcher.isLoadingRealWorldData ? loadingDetail : String(localized: "Taiwan’s Pingxi, Yilan and Shenao Lines, built on their real track and running"),
                        systemImage: "map.fill",
                        tone: .accent
                    ) {
                        if let railways = launcher.railways {
                            launcher.openRealWorldDemo(railways: railways)
                        }
                    }
                    // Without the railways' files (listed on the data
                    // sources screen) there is no demo to open.
                    .disabled(launcher.railways == nil)
                    .accessibilityIdentifier("start.realWorldDemo")
                }
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
            .frame(maxWidth: 420)
            .padding(.horizontal)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .sheet(isPresented: $showsSettings) {
            SettingsView(audio: audio)
        }
        .sheet(isPresented: $showsSaves) {
            SaveListView(launcher: launcher)
        }
        .sheet(isPresented: $choosesPlace) {
            RealWorldPicker(launcher: launcher)
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
        // iOS keeps each app's language in Settings (the
        // reference's home screen has a language menu instead).
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            chip(Label("Language", systemImage: "globe"))
        }
        .accessibilityHint("Opens Settings, where the game's language is chosen.")
        // Where the real-world data comes from (the `Railway/`
        // site's data sources page).
        Button {
            showsDataSources = true
        } label: {
            chip(Label("Data Sources", systemImage: "info.circle"))
        }
        .accessibilityIdentifier("start.dataSources")
        // The music and sound effects on or off; the game
        // menu opens the same settings.
        Button {
            showsSettings = true
        } label: {
            chip(Label("Settings", systemImage: "gearshape"))
        }
        .accessibilityIdentifier("start.settings")
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

    /// The save's game time, cash and size, and when it was saved.
    private func detail(of entry: SaveLibrary.Entry) -> String {
        let summary = entry.summary?.text(in: launcher.language) ?? ""
        guard let savedAt = entry.savedAt else { return summary }
        return "\(summary)\n\(String(localized: "Saved \(savedAt.formatted(date: .abbreviated, time: .shortened))"))"
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1.0) : 0.5)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The player's saves, and an autosave that cannot be loaded: tap one to
/// load it, swipe to delete it. A save that cannot be loaded says why.
struct SaveListView: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let message = launcher.message {
                    Section {
                        Label(message.text, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
                Section {
                    ForEach(launcher.otherSaves) { entry in
                        Button {
                            launcher.load(entry)
                            if launcher.session != nil {
                                dismiss()
                            }
                        } label: {
                            row(entry)
                        }
                        .disabled(entry.problem != nil)
                    }
                    .onDelete { offsets in
                        let entries = offsets.map { launcher.otherSaves[$0] }
                        for entry in entries {
                            launcher.delete(entry)
                        }
                    }
                }
            }
            .overlay {
                if launcher.otherSaves.isEmpty {
                    ContentUnavailableView("No Saved Games", systemImage: "tray")
                }
            }
            .navigationTitle("Saved Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
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
                if let problem = entry.problem {
                    Text(problem.playerMessage(in: launcher.language))
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                } else if let summary = entry.summary {
                    Text(summary.text(in: launcher.language))
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
        return entry.savedAt?.formatted(date: .abbreviated, time: .shortened) ?? entry.id
    }
}
