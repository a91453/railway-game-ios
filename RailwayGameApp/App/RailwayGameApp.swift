import GameCore
import GamePresentation
import SwiftUI

@main
struct RailwayGameApp: App {
    /// Holds the app's single authoritative `GameWorld` for the app's lifetime.
    ///
    /// Views get the session and change the world only through its methods,
    /// which apply `GameWorld` commands; nothing else keeps a copy of the world.
    @State private var session = GameSession(world: .newGame())

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
    }
}

extension GameWorld {
    /// The world a new game starts with.
    static func newGame() -> GameWorld {
        do {
            return try GameWorld(width: 32, height: 24, economy: GameEconomy(balance: 1_000_000))
        } catch {
            // The size is a constant within GridMap's limits, so failing here is a programming error.
            preconditionFailure("Could not create the new-game world: \(error)")
        }
    }
}
