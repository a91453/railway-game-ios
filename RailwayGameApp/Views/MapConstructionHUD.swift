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
    /// Whether a tutorial runs: the line about the height cell
    /// (``HeightSlideHint``) keeps out of its way.
    var tutorialRuns = false
    /// Decision 800: whether the map's ✕ ✓ card says why the stretch is
    /// refused, beside its ✓. Decision 803: this row never says it in
    /// words; while the card is away (a finger still draws) a warning
    /// sign stands for it (``BuildConfirmLayout/hudMark(refused:pillSaysProblem:joins:)``).
    var pillSaysProblem = false

    /// The metres the finger has slid while held, not yet applied, and
    /// whether it holds the cell: gesture state, so a cancelled hold
    /// (which never ends) goes back to nothing (review L14-2).
    @GestureState private var hold = TrackHeightDrag.Hold.idle
    @State private var showsStepper = false
    /// The line about the height cell is done with (``HeightSlideHint``):
    /// kept on the device, not in the save.
    @AppStorage(HeightSlideHint.seenKey) private var heightHintSeen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsHeightHint: Bool {
        HeightSlideHint.shows(seen: heightHintSeen, card: heights, tutorialRuns: tutorialRuns)
    }

    var body: some View {
        panel
            // The panel gives way to the line about the height cell
            // (``MotionRule/change``).
            .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: showsHeightHint)
    }

    /// Raises the end, and with a real change the player has used the
    /// cell: the line about it never comes again.
    private func raise(_ steps: Int) {
        onRaise(steps)
        if HeightSlideHint.isUse(raisingBy: steps) { heightHintSeen = true }
    }

    /// The one-time line about the height cell (``HeightSlideHint``): the
    /// cell's own arrows, what holding and sliding it does, and a ✕. Only
    /// the ✕ takes touches; the rest lets them through to the map, as the
    /// HUD. Decision 803: under the row on the first stretch alone; once
    /// it has left the screen it is done with, and takes no room again.
    private var heightHint: some View {
        HStack(spacing: 6) {
            VStack(spacing: 0) {
                Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.primary)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
            Text(verbatim: HeightSlideHint.text(in: language))
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
                .accessibilityIdentifier("map.constructionHUD.heightHint")
            Button {
                heightHintSeen = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(TouchTargetButtonStyle(size: CGSize(width: 24, height: 24)))
            .accessibilityLabel(Text(verbatim: HeightSlideHint.dismissLabel(in: language)))
            .accessibilityIdentifier("map.constructionHUD.heightHint.dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background { glass(inset: 0) }
        .onDisappear { heightHintSeen = true }
    }

    /// The glass and its edge behind a row, `inset` points shorter above
    /// and below than the row's touch area; it lets touches through to
    /// the map.
    private func glass(inset: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
        return Color.clear
            .glassBackground(in: shape)
            .overlay { shape.strokeBorder(Theme.panelBorder, lineWidth: 1) }
            .padding(.vertical, inset)
            .allowsHitTesting(false)
    }

    /// Decision 803 (the owner, 2026-11-16: too cluttered): one small
    /// capsule, the length and the height, and a mark where the stretch
    /// joins track or is refused while the ✕ ✓ card is away. Why it is
    /// refused is the card's to say; the price is on its ✓ (decision 744).
    private var panel: some View {
        VStack(spacing: 6) {
            // Decision 469 (UI review 2-22): one line where it fits, the
            // figures one under another where it does not (a small phone
            // at the largest text).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    lengthFigure
                    Divider()
                        .frame(height: 14)
                    heightFigure
                    mark
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                // The capsule is drawn 34 points tall; the height cell is
                // touched over 44. With − and + out it is as tall as they.
                .background { glass(inset: showsStepper ? 0 : 5) }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        lengthFigure
                        mark
                    }
                    heightFigure
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background { glass(inset: 0) }
            }
            if showsHeightHint {
                heightHint
                    .transition(.opacity)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.constructionHUD")
    }

    /// The row's one mark (``BuildConfirmLayout/HUDMark``).
    @ViewBuilder private var mark: some View {
        switch BuildConfirmLayout.hudMark(
            refused: preview.problem != nil, pillSaysProblem: pillSaysProblem,
            joins: preview.joinsStart || preview.joinsEnd
        ) {
        case .none:
            EmptyView()
        case .joins:
            Image(systemName: "link")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .allowsHitTesting(false)
                .accessibilityLabel(Text(verbatim: continuityText))
                .accessibilityIdentifier("map.constructionHUD.joins")
        case .refused:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.warning)
                .allowsHitTesting(false)
                .accessibilityLabel(Text(verbatim: text("Problem: \(preview.problem ?? "")", "問題：\(preview.problem ?? "")")))
                .accessibilityIdentifier("map.constructionHUD.problem")
        }
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
                if steps != 0 { raise(steps) }
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
        .background {
            Capsule().fill(hold.isHeld ? Theme.primary.opacity(0.18) : Color.clear)
                .padding(.vertical, showsStepper ? 0 : 7)
        }
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
            case .increment: if card.canRaise { raise(1) }
            case .decrement: if card.canLower { raise(-1) }
            @unknown default: break
            }
        }
        .accessibilityIdentifier("map.constructionHUD.height")
    }

    private func stepButton(systemName: String, enabled: Bool, steps: Int, label: String, identifier: String) -> some View {
        Button {
            raise(steps)
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
