import GameCore
import GamePresentation
import SwiftUI

/// Cash (which opens the economy panel), game time, speed controls and the
/// button that opens the lines panel. Everything shown is read from the world, so it updates as soon as
/// a command or a tick changes it.
struct HUDView: View {
    let session: GameSession
    @State private var showsLines = false
    @State private var showsEconomy = false

    var body: some View {
        // One row when it fits (iPad, sidebar), otherwise cash and time stack.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                cash
                time
                Spacer(minLength: 12)
                linesButton
                SpeedControl(session: session)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    cash
                    time
                }
                Spacer(minLength: 8)
                linesButton
                SpeedControl(session: session)
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .sheet(isPresented: $showsEconomy) {
            EconomyPanel(session: session)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showsLines) {
            LinesPanel(session: session)
                .presentationDetents([.medium, .large])
                // The map stays usable behind the half-height sheet, so
                // stations can be selected for a new line.
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    private var linesButton: some View {
        Button {
            showsLines = true
        } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.bold))
                .frame(width: 44, height: 32)
        }
        .buttonStyle(SelectableButtonStyle(isActive: showsLines))
        .accessibilityLabel("Lines")
        .accessibilityHint("Shows the service lines and their timetables.")
    }

    /// The balance in dollars; it opens the economy panel.
    private var cash: some View {
        let text = session.world.economy.balance.moneyText
        return Button {
            showsEconomy = true
        } label: {
            Label(text, systemImage: "banknote")
                .foregroundStyle(session.world.economy.balance < .zero ? Color.red : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cash \(text)")
        .accessibilityHint("Shows fares, running costs and the ledger.")
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
