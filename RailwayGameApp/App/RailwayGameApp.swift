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
    /// Game Center (decision 396): signed in in the background, never in
    /// the way of the start.
    @State private var gameCenter: GameCenterLink
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
            // The one-time card about track numbers and routes (decision
            // 201, later) starts seen, as the start screen's first-time
            // card starts closed: on settings emptied at every launch it came
            // up in every test whose line has double track or whose lines
            // panel shows the route menus, an alert over the switch or map
            // the test went on to touch (main's full lane, run 38404565525).
            // A test of the card itself asks for it with -show-route-hint.
            if !DebugLaunch.isSet("-show-route-hint") {
                UserDefaults.standard.set(true, forKey: RouteHint.seenKey)
            }
            // Likewise the one-time card about passing loops (decision 204,
            // later), which comes up when a line's train first waits on
            // single track.
            UserDefaults.standard.set(true, forKey: PassingLoopHint.seenKey)
            // Decision 311: the building layer starts put away, as a player
            // who hid it would have it: shown as soon as building began,
            // its legend took the corner where tests tap the map and the
            // mini map. A test of it asks for it with -show-building-layer.
            if !DebugLaunch.isSet("-show-building-layer") {
                UserDefaults.standard.set(false, forKey: BuildingLayerShortcut.autoShowsKey)
            }
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
        launcher.duckMusic = { audio.duckMusic($0) }
        launcher.runningSound = { audio.setRunning($0) }
        launcher.weatherSound = { audio.setWeather($0) }
        _audio = State(initialValue: audio)
        _launcher = State(initialValue: launcher)
        let gameCenter = GameCenterLink()
        #if DEBUG
        // UI tests play signed out: no sign-in to come up over a test.
        let signsIn = !DebugLaunch.isSet("-ui-testing")
        #else
        let signsIn = true
        #endif
        if signsIn {
            gameCenter.start(launcher: launcher)
        }
        _gameCenter = State(initialValue: gameCenter)
    }

    var body: some Scene {
        WindowGroup {
            RootView(launcher: launcher)
                .environment(audio)
                .environment(gameCenter)
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
            // The autosave is written off the main thread (decision 45,
            // later); the app asks iOS for the time to finish it.
            if phase != .active {
                BackgroundSave.finish(launcher)
            }
        }
    }

    private static func makeLauncher() -> GameLauncher {
        let launcher = GameLauncher(library: makeSaveLibrary(), language: .app)
        // Decision 397: the saves kept in the player's iCloud too, when
        // there is one; asked off the main thread before every round.
        launcher.cloudSaveFolder = { ICloudSaveFolder.current() }
        // About 2.4 MB of JSON: decoded off the main thread, so the
        // start screen shows at once; its real-world maps wait for it.
        launcher.loadRealWorldData { RailwayGameApp.bundledRealWorldData() }
        #if DEBUG
        // UI tests keep their cleared save folder on the Simulator alone.
        if DebugLaunch.isSet("-ui-testing") {
            launcher.cloudSaveFolder = nil
        }
        // Decision 177: UI tests start from an empty save folder, where the
        // start screen's first-time card would push the buttons they tap
        // below the fold; they start with it closed unless a test asks for
        // it with -show-first-game-card.
        if DebugLaunch.isSet("-ui-testing"), !DebugLaunch.isSet("-show-first-game-card") {
            launcher.dismissFirstGameCard()
        }
        // A new game's seed, so a test that needs what the towns and
        // sights of a blank map put on screen gets the same map each run.
        if DebugLaunch.isSet("-ui-testing"), let seed = DebugLaunch.value(of: "-ui-test-seed").flatMap(UInt32.init) {
            launcher.newGameOptions.seed = seed
        }
        if DebugLaunch.isSet("-ui-testing"), let name = DebugLaunch.value(of: "-ui-test-world") {
            launcher.continueGame()
            guard let session = launcher.session else { fatalError("Could not load UI test world") }
            if name == "separate-tracks" || name == "missing-platform" {
                for station in session.world.stations {
                    session.selectStation(station.id)
                    session.addSelectedStationToLineDraft()
                }
            } else if !name.hasPrefix("big-grid"), name != "story", let line = session.world.lines.first {
                session.selectLine(line.id)
            }
        }
        // A Debug build launched with -demo-layout opens the demo map at
        // once (Release builds open it from the start screen).
        if DebugLaunch.isSet("-demo-layout") {
            if let time = DebugLaunch.value(of: "-demo-at") {
                // Run on to that time ("HH:MM") off the main actor, and
                // paused there with -ui-testing-paused: a UI test that
                // needs the morning's trains opens on them instead of
                // waiting for the clock.
                launcher.openDemo(at: time, paused: DebugLaunch.isSet("-ui-testing-paused"))
            } else if DebugLaunch.isSet("-city-requests") {
                // Decision 246: with the city's requests, for their UI test.
                launcher.openDemo(cityRequestSeed: 1)
            } else {
                launcher.openDemo()
            }
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
        var data = RealWorldData.load { name, ext in
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
                throw RealRailways.ResourceError.missing("\(name).\(ext)")
            }
            return try Data(contentsOf: url)
        }
        // Decision 400's sequel: the base map, whose roads real-world
        // maps' land is read in with, mapped rather than read.
        data.baseMap = BaseMapFiles.tiles.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }.flatMap { try? BaseMapTiles(data: $0) }
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
                if let name = DebugLaunch.value(of: "-ui-test-world") {
                    let world = try FeatureUITestWorld.make(name)
                    _ = try SaveLibrary(directory: directory).save(world, as: .autosave, at: Date())
                }
                // Lesson UI tests can open later lessons without playing
                // all the earlier ones. Only this cleared testing library,
                // under -ui-testing in Debug, ever receives these stars.
                if let value = DebugLaunch.value(of: "-lesson-stars") {
                    let counts = value.split(separator: ",", omittingEmptySubsequences: false)
                    guard counts.count <= Lesson.all.count else {
                        fatalError("-lesson-stars has more entries than lessons")
                    }
                    var preferences = LauncherPreferences()
                    var stars: [String: Int] = [:]
                    for (index, text) in counts.enumerated() {
                        guard let count = Int(text), (0...3).contains(count) else {
                            fatalError("-lesson-stars expects comma-separated counts from 0 to 3")
                        }
                        stars[Lesson.all[index].id] = count
                    }
                    preferences.lessonStars = stars
                    try JSONEncoder().encode(preferences).write(
                        to: directory.appendingPathComponent(GameLauncher.preferencesFileName), options: .atomic
                    )
                }
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

/// #791's review: under `-ui-testing`, how busy the main thread is, for
/// the UI test trace. Every 2 s it writes how many frames it drew and the
/// longest time between two of them: a display link fires only when the
/// main thread is free, so a long gap is the main thread busy (drawing,
/// or answering a UI test's query) for that long.
@MainActor
final class FrameMeter: NSObject {
    static let shared = FrameMeter()
    private var link: CADisplayLink?
    private var frames = 0
    private var longest: CFTimeInterval = 0
    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        if last > 0 { longest = max(longest, now - last) } else { windowStart = now }
        last = now
        frames += 1
        guard now - windowStart >= 2 else { return }
        UITestTrace.action("frames \(frames) in \(Int((now - windowStart) * 1_000)) ms, longest gap \(Int(longest * 1_000)) ms")
        frames = 0
        longest = 0
        windowStart = now
    }
}

/// Puts a ``TouchTraceRecognizer`` on the window it is shown in, once.
private struct TouchTraceInstaller: UIViewRepresentable {
    final class Anchor: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchTraceRecognizer }) else { return }
            window.addGestureRecognizer(TouchTraceRecognizer.make())
            FrameMeter.shared.start()
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

/// Keeps the app running in the background until the launcher's saves are
/// written: an autosave queued on leaving the foreground is not cut off
/// half way by iOS suspending the app. The file is replaced whole or not
/// at all either way; this keeps the latest game.
@MainActor
private final class BackgroundSave {
    private var task = UIBackgroundTaskIdentifier.invalid

    static func finish(_ launcher: GameLauncher) {
        let save = BackgroundSave()
        save.task = UIApplication.shared.beginBackgroundTask(withName: "Save the game") {
            // Out of time: iOS ends the app if the task is not ended.
            MainActor.assumeIsolated { save.end() }
        }
        Task {
            await launcher.savesWritten()
            save.end()
        }
    }

    private func end() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

/// The game being played, or the start screen when there is none.
private struct RootView: View {
    let launcher: GameLauncher
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Decision 351: the demo mode's switch in the settings, read only in
    /// a test build.
    @AppStorage(DemoMode.switchKey) private var demoModeOn = false

    var body: some View {
        Group {
            if let session = launcher.session {
                ContentView(session: session, launcher: launcher)
            } else {
                StartView(launcher: launcher)
                    // Decision 269, later: the last game's 3D scene is not
                    // kept on the start screen.
                    .onAppear { Map3DSceneCache.shared.clear() }
            }
        }
        // Decision 307: the loading screen of a real-world map, over the
        // start screen while the map is built, fading away over the game.
        .overlay {
            if let loading = launcher.realWorldLoading {
                RealWorldLoadingView(loading: loading, language: launcher.language)
                    .transition(.opacity)
            }
        }
        .animation(
            (launcher.realWorldLoading == nil ? MotionRule.loadingOut : .loadingIn).running(reduceMotion: reduceMotion)?.animation,
            value: launcher.realWorldLoading == nil
        )
        .onChange(of: demoModeOn, initial: true) { _, on in
            launcher.isDemoMode = DemoMode.isOn(testBuild: TestBuild.isTest, switchOn: on)
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

extension LanguageChoice {
    /// The start screen's language choice, from the app's own
    /// `AppleLanguages` (decision 257). Read from the app's domain alone:
    /// the device's languages and a launch argument's are not the player's
    /// choice in the game.
    static var saved: LanguageChoice {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        return LanguageChoice(appleLanguages: domain?["AppleLanguages"] as? [String])
    }

    /// Keeps the choice in the app's `AppleLanguages`, which iOS reads at
    /// the next launch (``DisplayLanguage/app`` then follows it).
    func save() {
        if let appleLanguages {
            UserDefaults.standard.set(appleLanguages, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}
