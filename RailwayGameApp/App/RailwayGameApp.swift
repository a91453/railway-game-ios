import GameCore
import GamePresentation
import SwiftUI

@main
struct RailwayGameApp: App {
    /// Holds the app's single authoritative `GameWorld` for the app's lifetime.
    ///
    /// Views get the session and change the world only through its methods,
    /// which apply `GameWorld` commands; nothing else keeps a copy of the world.
    @State private var session = RailwayGameApp.makeSession()
    /// The combined phase of all the app's scenes.
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // One loop for the whole app, however many windows are open. It
            // runs only while the app is active; time spent in the
            // background is not replayed when the app returns.
            if phase == .active {
                session.startGameLoop()
            } else {
                session.stopGameLoop()
            }
        }
    }

    private static func makeSession() -> GameSession {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(DemoLayout.launchArgument) {
            return DemoLayout.makeSession()
        }
        #endif
        return GameSession(world: .newGame(), language: .app)
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

extension GameWorld {
    /// The world a new game starts with, running at 600× (`normal`), with
    /// traffic control on (Phase 4.6 Stage T): trains take their whole
    /// route before they leave, and a managed company (G1c). GameCore's own
    /// new worlds start with both off.
    static func newGame() -> GameWorld {
        do {
            var world = try GameWorld(
                width: 32,
                height: 24,
                economy: GameEconomy(balance: 1_000_000),
                clock: GameClock(speed: .normal)
            )
            try world.setTrafficControl(true)
            // G1c: a new game is a managed company, so fares are charged
            // and running costs settled.
            world.setEconomyMode(.management)
            return world
        } catch {
            // The size is a constant within GridMap's limits and an empty
            // world has no trains to share track, so failing here is a
            // programming error.
            preconditionFailure("Could not create the new-game world: \(error)")
        }
    }
}
