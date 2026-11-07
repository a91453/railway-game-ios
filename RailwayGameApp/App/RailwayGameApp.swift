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
        // The 3D map's train models made at launch, for a UI test that
        // opens the 3D map (``Map3DModelsWarmUp``).
        if DebugLaunch.isSet("-ui-test-3d-models-first") {
            Map3DModelsWarmUp.shared.start()
        }
        // And silently: the music and sounds only take the runner's CPU
        // (``GameAudio/init(defaults:plays:)``); no test listens to them.
        let plays = !DebugLaunch.isSet("-ui-testing")
        #else
        let plays = true
        #endif
        // Decision 418: what the system records of freezes and exits, kept
        // on the device for a problem report.
        DeviceDiagnosticsRecorder.shared.start()
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
        // The window's content reads nothing that changes (CRASHSWEEP): a
        // closure here is main-actor code, which SwiftUI may run again on
        // its asynchronous render thread when what it reads changes, and
        // that stops the app (CRASH101's kind). So the haptic it follows is
        // read in ``AppRoot``'s body.
        WindowGroup {
            AppRoot(launcher: launcher, audio: audio, gameCenter: gameCenter)
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
        // Decision 590: previews that try a command on copies of the world
        // are worked out after the view update that asks for them, off its
        // deep stack.
        launcher.worksOutPreviewsOnTheNextTurn = true
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
        // Decision 508: likewise the station master's offer of the tutorial
        // in a game with no line, which stays until answered, unless a test
        // asks for it with -show-first-line-offer.
        if DebugLaunch.isSet("-ui-testing"), !DebugLaunch.isSet("-show-first-line-offer") {
            launcher.showsFirstLineOffer = false
        }
        // Decision 464: a slow Simulator would open the speed hint's popover
        // by itself in the middle of a test and the next tap would close it;
        // UI tests start with it off unless a test asks with
        // -show-speed-lag-hint. Tapping the dot still opens its popover.
        if DebugLaunch.isSet("-ui-testing") {
            GameSession.showsSpeedLagHint = DebugLaunch.isSet("-show-speed-lag-hint")
        }
        // A new game's seed, so a test that needs what the towns and
        // sights of a blank map put on screen gets the same map each run.
        if DebugLaunch.isSet("-ui-testing"), let seed = DebugLaunch.value(of: "-ui-test-seed").flatMap(UInt32.init) {
            launcher.newGameOptions.seed = seed
        }
        if DebugLaunch.isSet("-ui-testing"), let name = DebugLaunch.value(of: "-ui-test-world") {
            // Read at once (decision 419): the game is set up below,
            // before the first frame.
            launcher.readsSavesAtOnce = true
            launcher.continueGame()
            launcher.readsSavesAtOnce = false
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
        // Freeze the demo before its first frame so camera UI tests select
        // known train positions without racing the simulation's first tick.
        // After the tutorial's step: a lesson built from it starts at
        // midnight too, however slow the runner (LessonUITests).
        if DebugLaunch.isSet("-ui-testing-paused") {
            launcher.session?.setSpeed(.paused)
        }
        // Decision 409: the demo's network as if a friend had sent it, for
        // the UI test of the sheet that offers it.
        if DebugLaunch.isSet("-ui-test-shared-network"), let data = try? SaveLibrary.encode(DemoWorld.make(in: launcher.language), at: Date()) {
            launcher.receiveNetwork(data)
        }
        // Decision 165: the website screenshot test opens a scene set up
        // for it, paused at the moment it shows.
        if let name = DebugLaunch.value(of: "-screenshot-scene"), let scene = ScreenshotScene(rawValue: name) {
            let opening = launcher.openScreenshotScene(scene)
            // Decision 522: the zoning drag held down, its far cells grey.
            if scene == .zoning, DebugLaunch.isSet("-screenshot-zone-drag") {
                Task {
                    await opening.value
                    launcher.session?.holdScreenshotZoningDrag()
                }
            }
            // Decision 535 (continued, KLRT): a real line's purchase card
            // opened, once the app's real data is read, for its screenshot.
            if let real = DebugLaunch.value(of: "-screenshot-offer-real") {
                Task {
                    await opening.value
                    guard let session = launcher.session else { return }
                    for _ in 0..<240 {
                        if let line = session.buyableRealLines.first(where: { $0.id == real }) {
                            session.offerRealLine(line)
                            break
                        }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
            // Decision 536: a train of a bought real line picked and
            // followed, for its card and the 3D map.
            if let real = DebugLaunch.value(of: "-screenshot-follow-bought") {
                Task {
                    await opening.value
                    // Decision 564: the real line bought first, once the
                    // app's real data is read, and run on to 07:40; its
                    // train nearest the middle followed.
                    if DebugLaunch.value(of: "-screenshot-buy-real") == real, let session = launcher.session {
                        for _ in 0..<240 {
                            if session.buyForScreenshot(real) { break }
                            try? await Task.sleep(for: .milliseconds(500))
                        }
                        await session.runForScreenshot(until: 7 * 3_600 + 40 * 60)
                        if let train = session.screenshotTrainMidway(on: real) {
                            session.selectTrain(train)
                            session.toggleFollowTrain(train)
                        }
                        return
                    }
                    if let session = launcher.session, let line = session.world.acquisition(of: real)?.line,
                       let train = session.world.line(id: line)?.assignedTrains.first(where: { session.world.train(id: $0)?.position != nil }) {
                        session.selectTrain(train)
                        session.toggleFollowTrain(train)
                    }
                }
            }
            // Decision 625: the demo's real lines laid round the scene's
            // station once the app's real data is read, and run on half an
            // hour, for the 3D map over the real stations' exteriors.
            if let view = DebugLaunch.value(of: "-screenshot-lay-demo") {
                Task {
                    await opening.value
                    guard let session = launcher.session else { return }
                    for _ in 0..<240 {
                        if await session.layDemoForScreenshot(view) { break }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
            // Decision 602: the real line bought and left at the scene's
            // hour, its trains in their depots, for the 3D map over them.
            if let real = DebugLaunch.value(of: "-screenshot-buy-real"), DebugLaunch.value(of: "-screenshot-follow-bought") == nil {
                Task {
                    await opening.value
                    guard let session = launcher.session else { return }
                    for _ in 0..<240 {
                        if session.buyForScreenshot(real) { break }
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
            // Decision 565: the first train on the track picked and
            // followed, standing at its platform.
            if DebugLaunch.isSet("-screenshot-follow-train") {
                Task {
                    await opening.value
                    if let session = launcher.session, let train = session.world.trains.first(where: { $0.position != nil })?.id {
                        session.selectTrain(train)
                        session.toggleFollowTrain(train)
                    }
                }
            }
            // Decision 580: the scene's feeder bus route's newest bus
            // followed, for the 3D map's follow views.
            if DebugLaunch.isSet("-screenshot-follow-bus") {
                Task {
                    await opening.value
                    if let session = launcher.session, let route = session.world.busRoutes.last {
                        session.followBus(onRoute: route.id)
                    }
                }
            }
            // Decision 583 (CABLEFOLLOW): a cabin of the scene's cable car
            // followed, for the 3D map's cabin views: one out over the
            // longest span, so the window looks down on the city.
            if DebugLaunch.isSet("-screenshot-follow-cabin") {
                Task {
                    await opening.value
                    if let session = launcher.session, let cableway = session.world.cableways.first,
                       let cabin = session.world.cabinOverLongestSpan(on: cableway.id) ?? session.world.cabinToFollow(on: cableway.id) {
                        session.followCabin(cabin)
                    }
                }
            }
            // Decision 585 PR-4 (FERRYFOLLOW): a boat of the scene's first
            // ferry followed, for the 3D map's boat views: one out on the
            // crossing, so the water is round it.
            if DebugLaunch.isSet("-screenshot-follow-ferry") {
                Task {
                    await opening.value
                    if let session = launcher.session, let route = session.world.ferryRoutes.first,
                       let boat = session.world.ferryBoatMidCrossing(on: route.id) {
                        session.followFerryBoat(boat)
                    }
                }
            }
            // Decision 539: the first freight train on the track picked and
            // followed, for the 3D map's R200 and container wagons.
            if DebugLaunch.isSet("-screenshot-follow-freight") {
                Task {
                    await opening.value
                    if let session = launcher.session,
                       let train = session.world.trains.first(where: { $0.position != nil && session.world.isFreightTrain($0.id) })?.id {
                        session.selectTrain(train)
                        session.toggleFollowTrain(train)
                    }
                }
            }
            // Decision 568: a new line being picked on the map, five
            // stations of the longest line, its ✓ pill beside the last.
            if DebugLaunch.isSet("-screenshot-line-draft") {
                Task {
                    await opening.value
                    if let session = launcher.session,
                       let stops = session.world.lines.max(by: { $0.stops.count < $1.stops.count })?.stops.prefix(5),
                       let first = stops.first {
                        session.selectStation(first)
                        session.startLineFromSelectedStation()
                        for station in stops.dropFirst() {
                            session.selectStation(station)
                            session.addSelectedStationToLineDraft()
                        }
                    }
                }
            }
            // Decision 566: new-train cards, for their screenshot review.
            if let keys = DebugLaunch.value(of: "-screenshot-new-train") {
                Task {
                    await opening.value
                    launcher.session?.showTrainArrivals(keys.split(separator: ",").map(String.init))
                }
            }
            // Decision 517 續: a station picked, for the 3D map's tag.
            if DebugLaunch.isSet("-screenshot-select-station") {
                Task {
                    await opening.value
                    if let session = launcher.session, let station = session.world.stations.first {
                        session.selectStation(station.id)
                    }
                }
            }
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
        // maps' land is read in with, mapped rather than read (the file
        // `BaseMapFiles.tiles` names, found here off the main actor).
        data.baseMap = Bundle.main.url(forResource: "taiwan", withExtension: "pmtiles", subdirectory: "BaseMap").flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }.flatMap { try? BaseMapTiles(data: $0) }
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
                    // Not a first launch: the news would cover the lessons.
                    preferences.whatsNewSeen = WhatsNew.edition
                    try JSONEncoder().encode(preferences).write(
                        to: directory.appendingPathComponent(GameLauncher.preferencesFileName), options: .atomic
                    )
                }
                // Decision 415: an app updated from one before the "What's
                // New" card, which shows the card once.
                if DebugLaunch.isSet("-ui-test-updated") {
                    var preferences = LauncherPreferences()
                    preferences.hasLaunched = true
                    try JSONEncoder().encode(preferences).write(
                        to: directory.appendingPathComponent(GameLauncher.preferencesFileName), options: .atomic
                    )
                }
                // A save that cannot be read, which the list must still let
                // the player delete.
                if DebugLaunch.isSet("-broken-save") {
                    try Data("not a save".utf8).write(to: directory.appendingPathComponent("save-broken.json"))
                }
                // Decision 502: three games of the player's, one saved three
                // times (two earlier versions), and the last game's
                // autosave, for the saves list's screenshots.
                if DebugLaunch.isSet("-sample-saves") {
                    let library = SaveLibrary(directory: directory)
                    let now = Date()
                    var world = DemoWorld.make(in: .traditionalChinese)
                    let row = try library.save(world, as: .manual, at: now.addingTimeInterval(-7_200), named: "台北環線")
                    for minutes in [90.0, 20] {
                        try world.advance(ticks: 3_600)
                        try library.save(world, as: .manual, at: now.addingTimeInterval(-minutes * 60), row: row.id)
                    }
                    try library.save(GameWorld.newGame(), as: .manual, at: now.addingTimeInterval(-86_400), named: "空白地圖練習")
                    try library.save(DemoWorld.make(in: .traditionalChinese), as: .manual, at: now.addingTimeInterval(-3 * 86_400))
                    try library.save(world, as: .autosave, at: now.addingTimeInterval(-300), row: row.id)
                }
                // Decision 497 (P2-6): a folder no save can be written
                // to, as on a full phone, for the screenshot of Back to
                // Start's question to leave without saving.
                if DebugLaunch.isSet("-unwritable-saves") {
                    let blocked = directory.appendingPathComponent("unwritable")
                    try Data("x".utf8).write(to: blocked)
                    return SaveLibrary(directory: blocked)
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
    /// Writes one line of ``StallSampler``'s report.
    static func stall(_ text: String) {
        guard isOn else { return }
        log.notice("stall \(text, privacy: .public)")
    }

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
        StallSampler.shared.beat(at: now)
        guard now - windowStart >= 2 else { return }
        UITestTrace.action("frames \(frames) in \(Int((now - windowStart) * 1_000)) ms, longest gap \(Int(longest * 1_000)) ms")
        frames = 0
        longest = 0
        windowStart = now
    }
}

/// MENUSTALL: with `-ui-test-stall-stacks` under `-ui-testing`, what the
/// main thread is doing while ``FrameMeter`` sees it draw nothing. A
/// thread of its own looks five times a second; once the main thread has
/// drawn no frame for over a second, each look stops it for an instant,
/// copies its return addresses (frame pointers, always kept on arm64) and
/// lets it go. When frames come again, the trace gets the stall's length,
/// the functions the looks most often found running, and the call stack
/// most of the looks shared, each frame with how many looks it was in.
/// Debug and the Simulator's arm64 only; nothing else runs it.
final class StallSampler: @unchecked Sendable {
    static let shared = StallSampler()
    private let lock = NSLock()
    private var lastBeat: CFTimeInterval = 0
    private var started = false
    /// Symbol names by address; used by the sampler's thread alone.
    private var names: [UInt: String] = [:]

    /// The main thread drew a frame at `time` (``CACurrentMediaTime()``).
    func beat(at time: CFTimeInterval) {
        lock.withLock { lastBeat = time }
    }

    @MainActor
    func start() {
        #if arch(arm64)
        guard !started else { return }
        started = true
        let main = pthread_self()
        let target = Target(
            thread: pthread_mach_thread_np(main),
            stackTop: UInt(bitPattern: pthread_get_stackaddr_np(main)),
            stackSize: UInt(pthread_get_stacksize_np(main))
        )
        beat(at: CACurrentMediaTime())
        let thread = Thread { [self] in run(target) }
        thread.name = "StallSampler"
        thread.qualityOfService = .userInteractive
        thread.start()
        #endif
    }

    #if arch(arm64)
    private struct Target: Sendable {
        let thread: thread_act_t
        let stackTop: UInt
        let stackSize: UInt
    }

    private func run(_ target: Target) {
        // Allocated once: nothing may allocate while the main thread is
        // stopped (it can hold the allocator's lock).
        let state = UnsafeMutablePointer<UInt64>.allocate(capacity: 34)
        let frames = UnsafeMutablePointer<UInt>.allocate(capacity: 128)
        var samples: [[UInt]] = []
        var stallStart: CFTimeInterval = 0
        while true {
            Thread.sleep(forTimeInterval: 0.2)
            let now = CACurrentMediaTime()
            let last = lock.withLock { lastBeat }
            if now - last > 1 {
                if stallStart == 0 { stallStart = last }
                if samples.count < 300 {
                    let count = Self.sample(target, state: state, frames: frames)
                    if count > 0 { samples.append(Array(UnsafeBufferPointer(start: frames, count: count))) }
                }
            } else if stallStart > 0 {
                report(samples, milliseconds: Int((last - stallStart) * 1_000))
                samples = []
                stallStart = 0
            }
        }
    }

    /// Stops the main thread, copies its program counter, link register
    /// and the return addresses of its frame records into `frames`, and
    /// lets it go; returns how many it copied.
    private static func sample(_ target: Target, state: UnsafeMutablePointer<UInt64>, frames: UnsafeMutablePointer<UInt>) -> Int {
        let mask: UInt = 0x0000_FFFF_FFFF_FFFF
        let bottom = target.stackTop - target.stackSize
        let top = target.stackTop
        guard thread_suspend(target.thread) == KERN_SUCCESS else { return 0 }
        // ARM_THREAD_STATE64 (6): x0–x28, fp, lr, sp, pc, cpsr and a pad,
        // 68 words of 32 bits.
        var stateCount = mach_msg_type_number_t(68)
        let got = state.withMemoryRebound(to: natural_t.self, capacity: 68) {
            thread_get_state(target.thread, thread_state_flavor_t(6), $0, &stateCount)
        }
        var count = 0
        if got == KERN_SUCCESS {
            frames[0] = UInt(state[32]) & mask
            frames[1] = UInt(state[30]) & mask
            count = 2
            var fp = UInt(state[29])
            while count < 128, fp >= bottom, fp + 16 <= top, fp & 7 == 0 {
                let record = UnsafePointer<UInt>(bitPattern: fp)!
                let next = record[0]
                let returnAddress = record[1] & mask
                guard returnAddress != 0 else { break }
                frames[count] = returnAddress
                count += 1
                guard next > fp else { break }
                fp = next
            }
        }
        thread_resume(target.thread)
        return count
    }

    /// The function at `address`: its image and symbol.
    private func name(_ address: UInt) -> String {
        if let known = names[address] { return known }
        var info = Dl_info()
        var text = "0x" + String(address, radix: 16)
        if dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0 {
            let image = info.dli_fname.map { String(cString: $0) }.flatMap { $0.split(separator: "/").last.map(String.init) } ?? "?"
            if let symbol = info.dli_sname {
                text = "\(image) \(String(cString: symbol))"
            } else {
                text = "\(image) +0x\(String(address - UInt(bitPattern: info.dli_fbase), radix: 16))"
            }
        }
        names[address] = text
        return text
    }

    private func report(_ samples: [[UInt]], milliseconds: Int) {
        guard !samples.isEmpty else { return }
        let total = samples.count
        // A return address is just after its call: look up the byte
        // before it, so a call at a function's end names that function.
        let named = samples.map { stack in stack.enumerated().map { index, address in name(index == 0 ? address : address - 1) } }
        var inclusive: [String: Int] = [:]
        var leaves: [String: Int] = [:]
        for stack in named {
            for function in Set(stack) { inclusive[function, default: 0] += 1 }
            if let leaf = stack.first { leaves[leaf, default: 0] += 1 }
        }
        UITestTrace.stall("\(milliseconds) ms, \(total) looks")
        for (leaf, count) in leaves.sorted(by: { $0.value > $1.value }).prefix(milliseconds >= 2_000 ? 8 : 3) {
            UITestTrace.stall("running \(count)/\(total) \(leaf)")
        }
        guard milliseconds >= 2_000 else { return }
        let typical = named.max { lhs, rhs in
            lhs.reduce(0) { $0 + inclusive[$1, default: 0] } < rhs.reduce(0) { $0 + inclusive[$1, default: 0] }
        } ?? []
        for (index, function) in typical.prefix(90).enumerated() {
            UITestTrace.stall("#\(index) \(inclusive[function, default: 0])/\(total) \(function)")
        }
        let shown = Set(typical)
        let others = inclusive.filter { !shown.contains($0.key) && $0.value * 4 >= total }
        for (function, count) in others.sorted(by: { $0.value > $1.value }).prefix(30) {
            UITestTrace.stall("also \(count)/\(total) \(function)")
        }
    }
    #endif
}

/// Puts a ``TouchTraceRecognizer`` on the window it is shown in, once.
private struct TouchTraceInstaller: UIViewRepresentable {
    final class Anchor: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: { $0 is TouchTraceRecognizer }) else { return }
            window.addGestureRecognizer(TouchTraceRecognizer.make())
            FrameMeter.shared.start()
            if DebugLaunch.isSet("-ui-test-stall-stacks") {
                StallSampler.shared.start()
            }
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

/// The window's content: the root view with the app's audio and Game
/// Center, and the taps the sounds' cues ask for (decision 184).
private struct AppRoot: View {
    let launcher: GameLauncher
    let audio: GameAudio
    let gameCenter: GameCenterLink

    var body: some View {
        RootView(launcher: launcher)
            .environment(audio)
            .environment(gameCenter)
            // Sendable: SwiftUI keeps it and calls it when a tap comes.
            .sensoryFeedback(trigger: audio.haptic) { @Sendable _, pulse in pulse?.feedback }
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
        // Decision 419: no taps while a save is read, before its loading
        // screen comes up.
        .allowsHitTesting(!launcher.isLoadingSave)
        // Decision 307: the loading screen of a real-world map, over the
        // start screen while the map is built, fading away over the game;
        // since decision 419 also of a save slow to read.
        .overlay {
            if let loading = launcher.realWorldLoading {
                RealWorldLoadingView(loading: loading, language: launcher.language) { launcher.cancelLoading() }
                    .transition(.opacity)
            }
        }
        .animation(
            (launcher.realWorldLoading == nil ? MotionRule.loadingOut : .loadingIn).running(reduceMotion: reduceMotion)?.animation,
            value: launcher.realWorldLoading == nil
        )
        // Decision 409: a save a friend sent, tapped in another app.
        .modifier(ReceivesSharedNetworks(launcher: launcher))
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
        .overlay(alignment: .topLeading) { Map3DModelsWarmUpMarker() }
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
