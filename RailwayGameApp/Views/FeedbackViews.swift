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
                // Decision 253: with Reduce Motion the check only fades,
                // in half the time.
                withAnimation(MotionRule.builtRing.running(reduceMotion: reduceMotion)?.animation) { phase = 1 }
            }
        }
    }
}

/// Shows what just came in (decision 117) under the cash in the status
/// pill, "+$ 1,234" in the success colour (decision 177: a day's loss,
/// "−$40k", in red), drifting down and fading; with
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
                Text(verbatim: shown.text)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(shown.isLoss ? Theme.error : Theme.success)
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

/// Decision 256: the fares a train took, floated over the station as
/// "+$12" in the warm yellow on navy, one a station (``FareFloatBoard``).
/// Each pops in, holds and goes up and out within 1.2 s; with Reduce Motion
/// it only fades. At 600× and faster only the followed train's and the
/// three stations nearest the middle of the map. Takes no touches;
/// VoiceOver hears the cash itself.
struct FareFloatMarks: View {
    let session: GameSession
    let camera: PlanCamera
    @State private var board = FareFloatBoard()

    var body: some View {
        let middle = (x: camera.viewport.width / 2, y: camera.viewport.height / 2)
        let floats = board.shown(
            fast: FareFloatBoard.isFast(session.world.clock.speed), followed: session.followedTrainID
        ) { location in
            let at = camera.screenPoint(of: location)
            return (at.x - middle.x) * (at.x - middle.x) + (at.y - middle.y) * (at.y - middle.y)
        }
        ZStack(alignment: .topLeading) {
            ForEach(floats) { float in
                let at = camera.screenPoint(of: float.location)
                FareFloatLabel(text: float.text)
                    .position(x: at.x, y: at.y - 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: session.farePulse) { _, pulse in
            guard let pulse else { return }
            board.add(pulse.fares, at: Self.now)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(FareFloatBoard.lifetime))
                board.expire(at: Self.now)
            }
        }
    }

    private static var now: Double {
        Date().timeIntervalSinceReferenceDate
    }
}

/// One "+$12": decision 253's `pop` in, a hold, `cardOut` up and out.
private struct FareFloatLabel: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var gone = false

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.onAccent, in: Capsule())
            .fixedSize()
            .scaleEffect(reduceMotion || shown ? 1 : 0.6)
            .offset(y: reduceMotion || !gone ? 0 : -12)
            .opacity(shown && !gone ? 1 : 0)
            .task {
                // A frame at the start first, so the change animates.
                try? await Task.sleep(for: .milliseconds(16))
                withAnimation(MotionRule.pop.running(reduceMotion: reduceMotion)?.animation) { shown = true }
                try? await Task.sleep(for: .seconds(MotionRule.pop.seconds + FareFloatBoard.hold))
                withAnimation(MotionRule.cardOut.running(reduceMotion: reduceMotion)?.animation) { gone = true }
            }
    }
}

/// Decision 256: a goal met, checked off in the middle of the map: a
/// check and the goal's title that pop in, bump once (`confirm`) and go
/// after a few seconds. With Reduce Motion it only fades. VoiceOver hears
/// it. Takes no touches.
struct GoalMetCheck: View {
    let pulse: GoalPulse?
    let language: DisplayLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: GoalPulse?

    var body: some View {
        // Read here: the animator's closure runs off the main actor.
        let reduceMotion = self.reduceMotion
        ZStack {
            if let shown {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.onPrimary, Theme.success)
                    Text(verbatim: shown.text(in: language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.panel, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.success, lineWidth: 2))
                .phaseAnimator([false, true], trigger: shown.serial) { chip, isBumped in
                    chip.scaleEffect(isBumped && !reduceMotion ? 1.04 : 1)
                } animation: { _ in MotionRule.confirm.animation }
                .padding(.horizontal, 24)
                .transition(.pop(reduceMotion: reduceMotion))
                .id(shown.serial)
                .accessibilityIdentifier("feedback.goalMet")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: pulse) { _, pulse in
            guard let pulse else { return }
            shown = pulse
            AccessibilityNotification.Announcement(pulse.text(in: language)).post()
        }
        .task(id: shown?.serial) {
            guard let serial = shown?.serial else { return }
            try? await Task.sleep(for: .seconds(GoalPulse.shownSeconds))
            guard !Task.isCancelled, shown?.serial == serial else { return }
            shown = nil
        }
    }
}

/// Decision 256: the towns that grew a step at midnight, each a warm
/// yellow ring with a navy edge that spreads and fades over its station
/// (`builtRing`); with Reduce Motion the ring only fades where it is.
/// Silent: towns grow too often for a sound. Takes no touches.
struct TownGrowthRings: View {
    let pulse: TownGrowthPulse?
    let camera: PlanCamera
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: TownGrowthPulse?
    @State private var phase = 0.0

    var body: some View {
        ZStack {
            if let shown {
                ForEach(Array(shown.locations.enumerated()), id: \.offset) { _, location in
                    let at = camera.screenPoint(of: location)
                    let size = reduceMotion ? 64 : 24 + 72 * phase
                    ZStack {
                        Circle().stroke(Theme.onAccent, lineWidth: 6)
                        Circle().stroke(Theme.accent, lineWidth: 3)
                    }
                    .frame(width: size, height: size)
                    .opacity(1 - phase)
                    .position(x: at.x, y: at.y)
                }
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
                withAnimation(MotionRule.builtRing.running(reduceMotion: reduceMotion)?.animation) { phase = 1 }
            }
        }
    }
}
