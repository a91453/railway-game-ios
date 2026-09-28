import GameCore
import GamePresentation
import SwiftUI

/// Phase 2A smoke-test screen: shows that GameCore links into the app and that
/// the presentation layer can read its state.
struct ContentView: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        NavigationStack {
            List {
                Section("GameCore") {
                    LabeledContent("Map", value: "\(world.map.width) × \(world.map.height)")
                    LabeledContent("Cash", value: world.economy.balance.amount.formatted())
                    LabeledContent("Game time", value: "\(world.clock.now.minutes) min")
                    LabeledContent("Speed", value: world.clock.speed.label)
                }
            }
            .navigationTitle("Railway Game")
        }
    }
}

private extension GameSpeed {
    var label: String {
        switch self {
        case .paused: "Paused"
        case .normal: "1×"
        case .double: "2×"
        }
    }
}
