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
        // About 2.4 MB of JSON: decoded off the main thread, so the
        // start screen shows at once; its real-world maps wait for it.
        launcher.loadRealWorldData { RailwayGameApp.bundledRealWorldData() }
        #if DEBUG
        // A Debug build launched with -demo-layout opens the demo map at
        // once (Release builds open it from the start screen).
        if DebugLaunch.isSet("-demo-layout") {
            launcher.openDemo()
        }
        // Freeze the demo before its first frame so camera UI tests select
        // known train positions without racing the simulation's first tick.
        if DebugLaunch.isSet("-ui-testing-paused") {
            launcher.session?.setSpeed(.paused)
        }
        #endif
        return launcher
    }

    /// The app's real-world data (`Resources/RealWorld/` and
    /// `Resources/RealRailways/`, the timetables only when one is asked
    /// for). Each file that cannot be read is left out, printed once in
    /// debug builds and listed on the data sources screen: without the
    /// population grid new stations get the city's ridership everywhere,
    /// without the places grid they all serve homes, and without the map
    /// files there are no real railways.
    private nonisolated static func bundledRealWorldData() -> RealWorldData {
        let data = RealWorldData.load { name, ext in
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
                throw RealRailways.ResourceError.missing("\(name).\(ext)")
            }
            return try Data(contentsOf: url)
        }
        #if DEBUG
        for issue in data.issues {
            print("RealWorldData: could not read \(issue)")
        }
        #endif
        return data
    }

    private static func makeSaveLibrary() -> SaveLibrary {
        #if DEBUG
        // UI tests use only this temporary folder. Clear it on every launch,
        // including relaunches on a Simulator that already has player saves.
        if DebugLaunch.isSet("-ui-testing") {
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

#if DEBUG
/// The launch arguments that exist only in Debug builds. Their names (11 and
/// 12 bytes) cannot be searched for in a Release binary: Swift keeps a string
/// of 15 bytes or fewer in the code, not as bytes in the binary. So
/// ``marker``, which is longer and exists only here, is what
/// `release-archive.yml` looks for in the Release binary (it must not be
/// found) and `ios-build.yml` in the Debug app (it must be). Keep the text in
/// the two workflows the same.
private enum DebugLaunch {
    static let marker = "RailwayGame Debug-only launch argument"

    static func isSet(_ argument: String) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains(argument) else { return false }
        print("\(marker): \(argument)")
        return true
    }
}
#endif

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
