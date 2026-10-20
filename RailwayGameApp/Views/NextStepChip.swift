import GamePresentation
import SwiftUI

/// A free game's next step on the map, beside the quick layers (City
/// Transport Manager study, step M2): "Next: Open a second line · 3/6" over
/// a thin bar of how far it has come; a tap opens the goals, where every
/// step is listed. One line, not a card, so it covers no more map than the
/// layers beside it; where there is no room, only the flag and the count.
/// Gone once every step is met. GamePresentation says it (``NextSteps``).
struct NextStepChip: View {
    let steps: NextSteps
    let language: DisplayLanguage
    let open: () -> Void

    var body: some View {
        if let current = steps.current {
            Button(action: open) {
                ViewThatFits(in: .horizontal) {
                    full(current)
                    compact
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            // One button to VoiceOver and to a finger's test, as the quick
            // layers beside it are: an `.accessibilityElement(children:
            // .ignore)` here wrapped it in a plain element that carried the
            // identifier but not the button (main 614375c's full lane).
            .accessibilityLabel(Text(verbatim: steps.chipText(in: language)))
            .accessibilityValue(Text(verbatim: current.progressText))
            .accessibilityHint(Text(verbatim: language.text("Shows every step and how to do it.", "列出每一步和怎麼做。")))
            .accessibilityIdentifier("map.nextStep")
        }
    }

    private func full(_ current: NextStepProgress) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "flag.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: steps.chipText(in: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                ProgressView(value: current.fraction)
                    .tint(Theme.primary)
                    .frame(width: 120)
            }
        }
        .fixedSize()
    }

    private var compact: some View {
        HStack(spacing: 4) {
            Image(systemName: "flag.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.primary)
            Text(verbatim: "\(steps.metCount)/\(steps.steps.count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .fixedSize()
    }
}

/// The goals panel's "Next steps" (CTM study, step M2): each step with its
/// progress and what to do, the met ones ticked. Nothing is paid for them.
struct NextStepsSection: View {
    let steps: NextSteps
    let language: DisplayLanguage

    var body: some View {
        Section {
            ForEach(steps.steps, id: \.step) { progress in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label {
                            Text(verbatim: progress.step.title(in: language))
                                .fontWeight(progress.step == steps.current?.step ? .semibold : .regular)
                        } icon: {
                            Image(systemName: progress.isMet ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(progress.isMet ? Theme.success : Theme.textSecondary)
                        }
                        Spacer()
                        Text(verbatim: progress.progressText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if !progress.isMet {
                        ProgressView(value: progress.fraction)
                            .tint(Theme.primary)
                        if progress.step == steps.current?.step {
                            Text(verbatim: progress.step.hint(in: language))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(verbatim: language.text("Next steps", "下一步"))
        } footer: {
            Text(verbatim: language.text(
                "A path through the game for your first days. Each step is ticked as soon as it is done.",
                "前幾天的玩法順序。每一步做到就會打勾。"
            ))
        }
        .accessibilityIdentifier("goals.nextSteps")
    }
}
