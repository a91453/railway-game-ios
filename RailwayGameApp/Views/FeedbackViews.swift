import GameCore
import GamePresentation
import SwiftUI

/// Over the map where something was just put up (decision 117): a ring
/// that spreads and fades, and a check that pops in and goes. With Reduce
/// Motion on, the check only fades out. Only pulses that come while it is
/// shown: one from before (the map rebuilt by a turn of the device) is
/// not played again. Takes no touches.
struct BuildPulseMark: View {
    let pulse: BuildPulse?
    let camera: PlanCamera
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: BuildPulse?
    @State private var phase = 0.0

    var body: some View {
        ZStack {
            if let shown {
                let at = camera.screenPoint(of: shown.location)
                ZStack {
                    if !reduceMotion {
                        Circle()
                            .stroke(Theme.success, lineWidth: 3)
                            .frame(width: 24 + 72 * phase, height: 24 + 72 * phase)
                            .opacity(1 - phase)
                    }
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.onPrimary, Theme.success)
                        .scaleEffect(reduceMotion ? 1 : 0.6 + 0.4 * min(1, phase * 3))
                        .opacity(phase < 0.75 ? 1 : (1 - phase) * 4)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }
                .position(x: at.x, y: at.y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: pulse) { _, pulse in
            guard let pulse else { return }
            shown = pulse
            phase = 0
            Task { @MainActor in
                // A frame at the start first, so the change animates.
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(.easeOut(duration: 0.9)) { phase = 1 }
            }
        }
    }
}

/// Shows what just came in (decision 117) under the cash in the status
/// pill, "+$ 1,234" in the success colour, drifting down and fading; with
/// Reduce Motion on it fades where it is. Only pulses that come while it
/// is shown. Takes no touches; VoiceOver hears the cash itself.
struct IncomeFloat: View {
    let pulse: IncomePulse?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: IncomePulse?
    @State private var rise = 0.0

    var body: some View {
        ZStack {
            if let shown {
                Text(verbatim: "+\(shown.amount.moneyText)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.success)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .offset(y: reduceMotion ? 18 : 18 + 16 * rise)
                    .opacity(1 - rise)
                    .fixedSize()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: pulse) { _, pulse in
            guard let pulse else { return }
            shown = pulse
            rise = 0
            Task { @MainActor in
                // A frame at the start first, so the change animates.
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(.easeOut(duration: 1.6)) { rise = 1 }
            }
        }
    }
}
