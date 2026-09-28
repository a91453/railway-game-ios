import GameCore
import GamePresentation
import SwiftUI

/// Cash, game time and speed, read from the world on every change.
struct HUDView: View {
    let session: GameSession

    var body: some View {
        let world = session.world
        HStack(spacing: 16) {
            Label(world.economy.balance.amount.formatted(), systemImage: "banknote")
                .accessibilityLabel("Cash \(world.economy.balance.amount.formatted())")
            Label("\(world.clock.now.minutes) min", systemImage: "clock")
                .accessibilityLabel("Game time \(world.clock.now.minutes) minutes")
            Spacer(minLength: 0)
            Text(world.clock.speed == .paused ? "Paused" : world.clock.speed == .normal ? "1×" : "2×")
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
    }
}
