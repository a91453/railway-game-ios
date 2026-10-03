import GameCore
import GamePresentation
import SwiftUI
import UniformTypeIdentifiers

/// The start screen (Stage C4), after the `Ci/` reference's home screen and
/// its saved-game card (`screen-save-load-ui`: go on with the saved game,
/// or start fresh): continue the autosave, start a new game, open the demo
/// map, load one of the saves or import a save file.
///
/// Every action calls a ``GameLauncher`` method; the screen keeps nothing
/// of the games but what it shows.
struct StartView: View {
    let launcher: GameLauncher
    @State private var showsSaves = false
    @State private var importsSave = false
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
                            isPrimary: true
                        ) {
                            launcher.continueGame()
                        }
                        .accessibilityIdentifier("start.continue")
                    }
                    StartButton(
                        title: String(localized: "New Game"),
                        detail: String(localized: "An empty map and \(GameWorld.newGame().economy.balance.moneyText) to build with"),
                        systemImage: "plus",
                        isPrimary: launcher.autosave == nil
                    ) {
                        launcher.startNewGame()
                    }
                    // Stable across localizations for the UI smoke tests.
                    .accessibilityIdentifier("start.newGame")
                    StartButton(
                        title: String(localized: "Demo Map"),
                        detail: String(localized: "Two lines already running, with passengers"),
                        systemImage: "tram.fill"
                    ) {
                        launcher.openDemo()
                    }
                    .accessibilityIdentifier("start.demoMap")
                    if !launcher.otherSaves.isEmpty {
                        StartButton(
                            title: String(localized: "Saved Games"),
                            detail: String(localized: "\(launcher.otherSaves.count) saves"),
                            systemImage: "tray.full"
                        ) {
                            showsSaves = true
                        }
                        .accessibilityIdentifier("start.savedGames")
                    }
                    StartButton(
                        title: String(localized: "Import a Save"),
                        detail: String(localized: "A save file from Files or another device"),
                        systemImage: "square.and.arrow.down"
                    ) {
                        importsSave = true
                    }
                }
                if let message = launcher.message {
                    Label(message.text, systemImage: message.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(message.kind == .success ? Color.green : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // iOS keeps each app's language in Settings (the reference's
                // home screen has a language menu instead).
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                        .font(.footnote)
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
        VStack(spacing: 10) {
            Image(systemName: "tram.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Palette.station)
                .accessibilityHidden(true)
            Text(verbatim: "Railway Game")
                .font(.largeTitle.weight(.bold))
            Text("Build a railway, run its trains and carry the city's passengers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.footnote)
                        .opacity(0.8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        }
        .buttonStyle(SelectableButtonStyle(isActive: isPrimary))
        .accessibilityElement(children: .combine)
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
        .padding(.vertical, 2)
    }

    private func title(of entry: SaveLibrary.Entry) -> String {
        if entry.kind == .autosave {
            return String(localized: "Autosave")
        }
        return entry.savedAt?.formatted(date: .abbreviated, time: .shortened) ?? entry.id
    }
}
