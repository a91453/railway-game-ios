import GameCore
import GamePresentation
import SwiftUI

/// Floating HUD displaying dimensions, costs, and feedback for the current track preview.
///
/// Ported from the owner's `Ci/` build mode HUD (`.place-distance-hud` and `.metro-cost-preview-pill`).
/// Only reads fields directly provided by `NetworkPreview`: length, start/end height, cost, and problem.
struct MapConstructionHUD: View {
    let preview: NetworkPreview
    let language: DisplayLanguage
    /// Decision 646: the end's height as the build card holds it; the
    /// height cell is slid up and down (held first, so the map still
    /// pans) while it is not `nil`.
    var heights: NetworkHeightCard?
    /// Raises the end by whole metres once the finger lets go.
    var onRaise: (Int) -> Void = { _ in }

    /// The metres the finger has slid while held, not yet applied, and
    /// whether it holds the cell: gesture state, so a cancelled hold
    /// (which never ends) goes back to nothing (review L14-2).
    @GestureState private var hold = TrackHeightDrag.Hold.idle
    @State private var showsStepper = false

    var body: some View {
        VStack(spacing: 6) {
            // Decision 469 (UI review 2-22): one line where it fits, the
            // figures one under another where it does not (a small phone
            // at the largest text).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    lengthFigure
                    Divider()
                        .frame(height: 14)
                    heightFigure
                    if let cost = preview.cost {
                        Divider()
                            .frame(height: 14)
                        costFigure(cost)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    lengthFigure
                    heightFigure
                    if let cost = preview.cost {
                        costFigure(cost)
                    }
                }
            }

            // Refusal reason (problem) or track continuity status
            if let problem = preview.problem {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.warning)
                    Text(problem)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(text("Problem: \(problem)", "問題：\(problem)"))
            } else if preview.joinsStart || preview.joinsEnd {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(continuityText)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(Theme.textPrimary)
        .background {
            // The panel itself lets touches through to the map.
            Color.clear
                .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.constructionHUD")
    }

    private var lengthFigure: some View {
        lengthFigureContent.allowsHitTesting(false)
    }

    private var lengthFigureContent: some View {
        HStack(spacing: 4) {
            Image(systemName: "ruler")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.primary)
            Text(NetworkBuilding.lengthText(preview.length, in: language))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text("Length: \(NetworkBuilding.lengthText(preview.length, in: language))", "長度：\(NetworkBuilding.lengthText(preview.length, in: language))"))
    }

    @ViewBuilder private var heightFigure: some View {
        if let heights, !heights.label.isEmpty {
            slidingHeightFigure(heights)
        } else {
            plainHeightFigure.allowsHitTesting(false)
        }
    }

    /// Decision 646: how high the end stands over the ground; held and
    /// slid up or down a metre at a time (a tap opens − and +, for a
    /// finger that cannot slide; VoiceOver adjusts it).
    private func slidingHeightFigure(_ card: NetworkHeightCard) -> some View {
        let reading = card.readout(steps: hold.steps, in: language)
        let holdAndSlide = LongPressGesture(minimumDuration: TrackHeightDrag.holdSeconds)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($hold) { value, state, _ in
                guard case .second(true, let drag) = value else { return }
                state.hold(at: drag.map { Double($0.translation.height) }, card: card)
            }
            .onEnded { value in
                guard case .second(true, let drag) = value else { return }
                let steps = TrackHeightDrag.stepsApplied(endingAt: drag.map { Double($0.translation.height) }, card: card)
                if steps != 0 { onRaise(steps) }
            }
        return HStack(spacing: 6) {
            if showsStepper {
                stepButton(systemName: "minus", enabled: card.canLower, steps: -1,
                           label: text("Lower 1 m", "降低 1 公尺"), identifier: "map.build.lower")
            }
            VStack(spacing: 0) {
                Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.primary)
            Text(verbatim: reading)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            if showsStepper {
                stepButton(systemName: "plus", enabled: card.canRaise, steps: 1,
                           label: text("Raise 1 m", "架高 1 公尺"), identifier: "map.build.raise")
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 44)
        .background(hold.isHeld ? Theme.primary.opacity(0.18) : Color.clear, in: Capsule())
        .contentShape(Rectangle())
        .onTapGesture { showsStepper.toggle() }
        .gesture(holdAndSlide)
        .sensoryFeedback(.selection, trigger: hold.steps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text("Height above ground", "離地高度"))
        .accessibilityValue(reading)
        .accessibilityHint(text("Hold and slide up or down, or swipe up or down to adjust by 1 m.", "按住上下滑動，或用上下滑調整，每次 1 公尺。"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if card.canRaise { onRaise(1) }
            case .decrement: if card.canLower { onRaise(-1) }
            @unknown default: break
            }
        }
        .accessibilityIdentifier("map.constructionHUD.height")
    }

    private func stepButton(systemName: String, enabled: Bool, steps: Int, label: String, identifier: String) -> some View {
        Button {
            onRaise(steps)
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityIdentifier(identifier)
    }

    private var plainHeightFigure: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.and.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.primary)
            if preview.startHeight == preview.endHeight {
                Text(NetworkBuilding.lengthText(preview.startHeight, in: language))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            } else {
                Text(verbatim: "\(NetworkBuilding.lengthText(preview.startHeight, in: language)) → \(NetworkBuilding.lengthText(preview.endHeight, in: language))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heightAccessibilityLabel)
    }

    private func costFigure(_ cost: Money) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "banknote")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.success)
            // Decision 523, continued: in 萬 or 億 in Chinese.
            Text(verbatim: cost.compactText(in: language))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            // Decision 523: a rough US dollar figure, English only.
            if let reference = cost.usDollarReferenceText(in: language) {
                Text(verbatim: reference)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text("Cost: \(cost.moneyText)", "費用：\(cost.compactText(in: language))"))
    }

    /// `english` or `chinese` for the session's language. GamePresentation's
    /// own `DisplayLanguage.text` is internal to that module, so the app
    /// picks by the public enum, as the line panel does.
    private func text(_ english: String, _ chinese: String) -> String {
        language == .traditionalChinese ? chinese : english
    }

    private var continuityText: String {
        switch (preview.joinsStart, preview.joinsEnd) {
        case (true, true): return text("Joins track at both ends", "兩端均與軌道相接")
        case (true, false): return text("Continues existing track", "延續既有軌道")
        case (false, true): return text("Joins track at end", "終點與軌道相接")
        case (false, false): return ""
        }
    }

    private var heightAccessibilityLabel: String {
        if preview.startHeight == preview.endHeight {
            return text("Height: \(NetworkBuilding.lengthText(preview.startHeight, in: language))", "高度：\(NetworkBuilding.lengthText(preview.startHeight, in: language))")
        } else {
            return text("Height: \(NetworkBuilding.lengthText(preview.startHeight, in: language)) to \(NetworkBuilding.lengthText(preview.endHeight, in: language))", "高度：\(NetworkBuilding.lengthText(preview.startHeight, in: language)) 至 \(NetworkBuilding.lengthText(preview.endHeight, in: language))")
        }
    }
}
