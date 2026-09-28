import GameCore
import SwiftUI

@main
struct RailwayGameApp: App {
    /// The app's single authoritative game state.
    ///
    /// Views receive it read-only. Future gameplay changes must be applied here
    /// through `GameWorld` commands, never to a separate copy.
    @State private var world = GameWorld.smokeTest()

    var body: some Scene {
        WindowGroup {
            ContentView(world: world)
        }
    }
}

extension GameWorld {
    /// A small empty world for the Phase 2A smoke test.
    static func smokeTest() -> GameWorld {
        do {
            return try GameWorld(width: 32, height: 24, economy: GameEconomy(balance: 1_000_000))
        } catch {
            // The size is a constant within GridMap's limits, so failing here is a programming error.
            preconditionFailure("Could not create the smoke-test world: \(error)")
        }
    }
}
