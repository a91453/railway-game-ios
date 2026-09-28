import GameCore
import GamePresentation
import SwiftUI

/// Cash, game time and speed controls. Everything shown is read from the
/// world, so it updates as soon as a command or a tick changes it.
struct HUDView: View {
    let session: GameSession

    var body: some View {
        // One row when it fits (iPad, sidebar), otherwise cash and time stack.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                cash
                time
                Spacer(minLength: 12)
                SpeedControl(session: session)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    cash
                    time
                }
                Spacer(minLength: 8)
                SpeedControl(session: session)
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
    }

    private var cash: some View {
        let text = session.world.economy.balance.displayText
        return Label(text, systemImage: "banknote")
            .accessibilityLabel("Cash \(text)")
    }

    private var time: some View {
        let text = session.world.clock.now.displayText
        return Label(text, systemImage: "clock")
            .accessibilityLabel("Game time \(text)")
    }
}

/// Pause, 1× and 2×. The active speed is read from the world's clock.
private struct SpeedControl: View {
    let session: GameSession

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GameSpeed.allCases, id: \.self) { speed in
                let isActive = session.world.clock.speed == speed
                Button {
                    session.setSpeed(speed)
                } label: {
                    Group {
                        if speed == .paused {
                            Image(systemName: "pause.fill")
                        } else {
                            Text(speed.label)
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(width: 44, height: 32)
                }
                .buttonStyle(SelectableButtonStyle(isActive: isActive))
                .accessibilityLabel(speed.accessibilityName)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game speed")
    }
}
