import GameCore
import GamePresentation
import SwiftUI

@main
struct RailwayGameApp: App {
    /// Starts, continues and saves games for the app's lifetime (Stage C4).
    ///
    /// The game being played is its `GameSession`, the single authority over
    /// that game's world. Views get the session and change the world only
    /// through its methods, which apply `GameWorld` commands; nothing else
    /// keeps a copy of the world.
    @State private var launcher = RailwayGameApp.makeLauncher()
    /// The combined phase of all the app's scenes.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(launcher: launcher)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // One game loop for the whole app, however many windows are
            // open. It runs only while the app is active; leaving the
            // foreground autosaves, and time spent in the background is not
            // replayed when the app returns.
            launcher.setActive(phase == .active)
        }
    }

    private static func makeLauncher() -> GameLauncher {
        let launcher = GameLauncher(library: makeSaveLibrary(), language: .app)
        #if DEBUG
        // A Debug build launched with -demo-layout opens the demo map at
        // once (Release builds open it from the start screen).
        if ProcessInfo.processInfo.arguments.contains("-demo-layout") {
            launcher.openDemo()
        }
        #endif
        return launcher
    }

    private static func makeSaveLibrary() -> SaveLibrary {
        #if DEBUG
        // UI tests use only this temporary folder. Clear it on every launch,
        // including relaunches on a Simulator that already has player saves.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let manager = FileManager.default
            let directory = manager.temporaryDirectory.appendingPathComponent("UITestingSaves", isDirectory: true)
            do {
                if manager.fileExists(atPath: directory.path) {
                    try manager.removeItem(at: directory)
                }
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                return SaveLibrary(directory: directory)
            } catch {
                // Never fall back to the player's library if isolation fails.
                fatalError("Could not prepare UI test saves: \(error)")
            }
        }
        #endif
        return (try? SaveLibrary.standard())
            ?? SaveLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("Saves", isDirectory: true))
    }
}

/// The game being played, or the start screen when there is none.
private struct RootView: View {
    let launcher: GameLauncher

    var body: some View {
        if let session = launcher.session {
            ContentView(session: session, launcher: launcher)
        } else {
            StartView(launcher: launcher)
        }
    }
}

extension DisplayLanguage {
    /// The language of the localization iOS chose for the app at launch:
    /// the one its String Catalog shows, so the text GamePresentation
    /// writes matches the rest of the screen.
    static var app: DisplayLanguage {
        DisplayLanguage(localization: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
