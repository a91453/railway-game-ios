import GameCore
import GamePresentation
import os
import SwiftUI
import UIKit
#if DEBUG
import UIKit.UIGestureRecognizerSubclass
#endif

@main
struct RailwayGameApp: App {
    /// Starts, continues and saves games for the app's lifetime (Stage C4).
    ///
    /// The game being played is its `GameSession`, the single authority over
    /// that game's world. Views get the session and change the world only
    /// through its methods, which apply `GameWorld` commands; nothing else
    /// keeps a copy of the world.
    @State private var launcher: GameLauncher
    /// The music and sounds, for the app's lifetime: the launcher hands
    /// its player to every game.
    @State private var audio: GameAudio
    /// The combined phase of all the app's scenes.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        // Each UI test starts from the same settings, as from the same empty
        // save folder: the map's layers and style (`@AppStorage`) and the
        // sound switches stay on the device across launches, so a test that
        // leaves the land value layer on, or stops between turning a switch
        // off and on, changed how every later test began. Before anything
        // reads them.
        if DebugLaunch.isSet("-ui-testing"), let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        // And silently: the music and sounds only take the runner's CPU
        // (``GameAudio/init(defaults:plays:)``); no test listens to them.
        let plays = !DebugLaunch.isSet("-ui-testing")
        #else
        let plays = true
        #endif
        let audio = GameAudio(plays: plays)
        let launcher = RailwayGameApp.makeLauncher()
        launcher.playSound = { audio.play($0) }
        _audio = State(initialValue: audio)
        _launcher = State(initialValue: launcher)
    }

    var body: some Scene {
        WindowGroup {
            RootView(launcher: launcher)
                .environment(audio)
                // Decision 184: the taps the sounds' cues ask for.
                .sensoryFeedback(trigger: audio.haptic) { _, pulse in pulse?.feedback }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // One game loop for the whole app, however many windows are
            // open. It runs only while the app is active; leaving the
            // foreground autosaves, and time spent in the background is not
            // replayed when the app returns. The music plays only then too.
            launcher.setActive(phase == .active)
            audio.setActive(phase == .active)
        }
    }

    private static func makeLauncher() -> GameLauncher {
        let launcher = GameLauncher(library: makeSaveLibrary(), language: .app)
        // About 2.4 MB of JSON: decoded off the main thread, so the
        // start screen shows at once; its real-world maps wait for it.
        launcher.loadRealWorldData { RailwayGameApp.bundledRealWorldData() }
        #if DEBUG
        // Decision 177: UI tests start from an empty save folder, where the
        // start screen's first-time card would push the buttons they tap
        // below the fold; they start with it closed unless a test asks for
        // it with -show-first-game-card.
        if DebugLaunch.isSet("-ui-testing"), !DebugLaunch.isSet("-show-first-game-card") {
            launcher.dismissFirstGameCard()
        }
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
        // A data layer left on, as a player's last game can leave it
        // (TutorialUITests: the tutorial starts without it).
        if let layer = DebugLaunch.value(of: "-map-layer") {
            UserDefaults.standard.set(layer, forKey: "mapPopTravelMode")
        }
        // The tutorial at a later step, over what the steps before it
        // build (TutorialUITests: the line step's screen on a phone).
        if let step = DebugLaunch.value(of: "-tutorial-step") {
            launcher.startTutorial(atStep: step)
        }
        // Decision 165: the website screenshot test opens a scene set up
        // for it, paused at the moment it shows.
        if let name = DebugLaunch.value(of: "-screenshot-scene"), let scene = ScreenshotScene(rawValue: name) {
            launcher.openScreenshotScene(scene)
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
                // A save that cannot be read, which the list must still let
                // the player delete.
                if DebugLaunch.isSet("-broken-save") {
                    try Data("not a save".utf8).write(to: directory.appendingPathComponent("save-broken.json"))
                }
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

    /// The argument after `argument`, or `nil` without both.
    static func value(of argument: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1) else { return nil }
        print("\(marker): \(argument) \(arguments[index + 1])")
        return arguments[index + 1]
    }
}
#endif

/// K4 (#366): a tap a UI test saw pressed whose action never ran. Under
/// `-ui-testing`, in a Debug build, the app writes each touch its window
/// receives (where, on which view of which window) and the actions of the
/// buttons those failures named, to the unified log: the app's subsystem,
/// category `ui-test`. `ios-build.yml` saves that log when a UI test fails,
/// so the next failure says whether the touch arrived, where it landed and
/// whether the action ran. A Release build writes nothing.
enum UITestTrace {
    #if DEBUG
    static let isOn = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RailwayGame", category: "ui-test")
    #endif

    /// Writes that button `name`'s action ran.
    static func action(_ name: String) {
        #if DEBUG
        guard isOn else { return }
        log.notice("action \(name, privacy: .public)")
        #endif
    }

    #if DEBUG
    /// Writes a touch's phase, its point in the window, the view it was
    /// delivered to (with the nearest accessibility identifier above it)
    /// and its window.
    @MainActor
    static func touch(_ touch: UITouch, _ phase: String) {
        let point = touch.location(in: nil)
        var identified = touch.view
        while let view = identified, (view.accessibilityIdentifier ?? "").isEmpty { identified = view.superview }
        let view = touch.view.map { String(describing: type(of: $0)) } ?? "none"
        let window = touch.window.map { "\(type(of: $0)) level \($0.windowLevel.rawValue)\($0.isKeyWindow ? " key" : "")" } ?? "none"
        log.notice(
            "touch \(phase, privacy: .public) at (\(Int(point.x)), \(Int(point.y))) view \(view, privacy: .public) id \(identified?.accessibilityIdentifier ?? "-", privacy: .public) window \(window, privacy: .public)"
        )
    }
    #endif
}

#if DEBUG
/// Watches every touch of its window for ``UITestTrace`` without taking
/// part: it never recognizes, and never delays or cancels a touch.
private final class TouchTraceRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    static func make() -> TouchTraceRecognizer {
        let recognizer = TouchTraceRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = recognizer
        return recognizer
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { UITestTrace.touch(touch, "began") }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { UITestTrace.touch(touch, "ended") }
        failOnceAllTouchesEnd(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { UITestTrace.touch(touch, "cancelled") }
        failOnceAllTouchesEnd(event)
    }

    private func failOnceAllTouchesEnd(_ event: UIEvent) {
        if event.allTouches?.allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) ?? true {
            state = .failed
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Puts a ``TouchTraceRecognizer`` on the window it is shown in, once.
private struct TouchTraceInstaller: UIViewRepresentable {
    final class Anchor: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchTraceRecognizer }) else { return }
            window.addGestureRecognizer(TouchTraceRecognizer.make())
        }
    }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIView(_ uiView: Anchor, context: Context) {}
}
#endif

/// The game being played, or the start screen when there is none.
private struct RootView: View {
    let launcher: GameLauncher

    var body: some View {
        Group {
            if let session = launcher.session {
                ContentView(session: session, launcher: launcher)
            } else {
                StartView(launcher: launcher)
            }
        }
        #if DEBUG
        .background {
            if UITestTrace.isOn {
                TouchTraceInstaller()
                    .accessibilityHidden(true)
            }
        }
        #endif
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
