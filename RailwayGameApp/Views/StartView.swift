import GameCore
import GamePresentation
import SwiftUI
import UniformTypeIdentifiers

/// The start screen (Stage C4), after the `Ci/` reference's home screen and
/// its saved-game card (`screen-save-load-ui`: go on with the saved game,
/// or start fresh): continue the autosave, start a new game on a blank or a
/// real-world map (Stage E2), open the demo map, load one of the saves or
/// import a save file.
///
/// Every action calls a ``GameLauncher`` method; the screen keeps nothing
/// of the games but what it shows.
struct StartView: View {
    let launcher: GameLauncher
    @State private var showsSaves = false
    @State private var importsSave = false
    @State private var choosesPlace = false
    @Environment(\.openURL) private var openURL

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
                            accentColor: Palette.metroGreen
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
                        accentColor: Palette.metroBlue
                    ) {
                        launcher.startNewGame()
                    }
                    // Stable across localizations for the UI smoke tests.
                    .accessibilityIdentifier("start.newGame")
                    StartButton(
                        title: String(localized: "Real-World Map"),
                        detail: String(localized: "Build on a map of a real place"),
                        systemImage: "globe.asia.australia",
                        accentColor: Palette.metroCyan
                    ) {
                        choosesPlace = true
                    }
                    .accessibilityIdentifier("start.realWorld")
                    StartButton(
                        title: String(localized: "Tutorial"),
                        detail: String(localized: "Learn to build and run a railway step by step"),
                        systemImage: "hand.point.up.left",
                        accentColor: Palette.metroAmber
                    ) {
                        launcher.startTutorial()
                    }
                    .accessibilityIdentifier("start.tutorial")
                    StartButton(
                        title: String(localized: "Demo Map"),
                        detail: String(localized: "Two lines already running, with passengers"),
                        systemImage: "tram.fill",
                        accentColor: Palette.metroPurple
                    ) {
                        launcher.openDemo()
                    }
                    .accessibilityIdentifier("start.demoMap")
                    if !launcher.otherSaves.isEmpty {
                        StartButton(
                            title: String(localized: "Saved Games"),
                            detail: String(localized: "\(launcher.otherSaves.count) saves"),
                            systemImage: "tray.full",
                            accentColor: Palette.station
                        ) {
                            showsSaves = true
                        }
                        .accessibilityIdentifier("start.savedGames")
                    }
                    StartButton(
                        title: String(localized: "Import a Save"),
                        detail: String(localized: "A save file from Files or another device"),
                        systemImage: "square.and.arrow.down",
                        accentColor: Palette.metroBlue
                    ) {
                        importsSave = true
                    }
                }
                if let message = launcher.message {
                    HStack(spacing: 8) {
                        Image(systemName: message.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.bold))
                        Text(message.text)
                            .font(.footnote.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(message.kind == .success ? Palette.metroGreen : Palette.metroAmber)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background((message.kind == .success ? Palette.metroGreen : Palette.metroAmber).opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder((message.kind == .success ? Palette.metroGreen : Palette.metroAmber).opacity(0.35), lineWidth: 1))
                }
                // iOS keeps each app's language in Settings (the reference's
                // home screen has a language menu instead).
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Palette.chipBackground, in: Capsule())
                        .overlay(Capsule().strokeBorder(Palette.cardBorder, lineWidth: 1))
                }
                .accessibilityHint("Opens Settings, where the game's language is chosen.")
            }
            .frame(maxWidth: 420)
            .padding(.horizontal)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showsSaves) {
            SaveListView(launcher: launcher)
        }
        .sheet(isPresented: $choosesPlace) {
            RealWorldPicker(launcher: launcher)
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
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Palette.station, Palette.metroAmber],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Palette.station.opacity(0.35), radius: 12, x: 0, y: 6)
                Image(systemName: "tram.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
            Text(verbatim: "Railway Game")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
            Text("Build a railway, run its trains and carry the city's passengers.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    /// The save's game time, cash and size, and when it was saved.
    private func detail(of entry: SaveLibrary.Entry) -> String {
        let summary = entry.summary?.text(in: launcher.language) ?? ""
        guard let savedAt = entry.savedAt else { return summary }
        return "\(summary)\n\(String(localized: "Saved \(savedAt.formatted(date: .abbreviated, time: .shortened))"))"
    }
}

/// One choice on the start screen: a title over what it does.
private struct StartButton: View {
    let title: String
    let detail: String
    let systemImage: String
    var isPrimary = false
    var accentColor: Color = Color.accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.body.weight(.bold))
                        .foregroundStyle(accentColor)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isPrimary ? accentColor.opacity(0.65) : Palette.cardBorder,
                        lineWidth: isPrimary ? 2 : 1
                    )
            }
            .shadow(
                color: isPrimary ? accentColor.opacity(0.16) : Color.black.opacity(0.04),
                radius: isPrimary ? 8 : 4,
                x: 0,
                y: isPrimary ? 3 : 2
            )
        }
        .buttonStyle(CardTapButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct CardTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
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
                            .foregroundStyle(Color.orange)
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
                    .fill((entry.problem != nil ? Palette.metroAmber : (entry.kind == .autosave ? Palette.metroGreen : Palette.metroBlue)).opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: entry.problem != nil ? "exclamationmark.triangle.fill" : (entry.kind == .autosave ? "clock.arrow.circlepath" : "tram.fill"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(entry.problem != nil ? Palette.metroAmber : (entry.kind == .autosave ? Palette.metroGreen : Palette.metroBlue))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title(of: entry))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(entry.problem == nil ? Color.primary : Color.secondary)
                if let problem = entry.problem {
                    Text(problem.playerMessage(in: launcher.language))
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                } else if let summary = entry.summary {
                    Text(summary.text(in: launcher.language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
