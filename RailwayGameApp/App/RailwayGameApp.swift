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
        return GameSession(world: .newGame())
    }
}

extension GameWorld {
    /// The world a new game starts with, running at 1×.
    static func newGame() -> GameWorld {
        do {
            return try GameWorld(
                width: 32,
                height: 24,
                economy: GameEconomy(balance: 1_000_000),
                clock: GameClock(speed: .normal)
            )
        } catch {
            // The size is a constant within GridMap's limits, so failing here is a programming error.
            preconditionFailure("Could not create the new-game world: \(error)")
        }
    }
}
