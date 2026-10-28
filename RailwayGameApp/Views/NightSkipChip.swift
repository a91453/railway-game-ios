import GameCore
import GamePresentation
import SwiftUI

/// Decision 305: "Skip to Morning" under the speed, while no train runs
/// until the morning; while the skip runs, the same chip stops it. Where
/// it stops and whether there is a night to skip are the session's
/// (``GameSession/nightSkipOffer``, ``GameSession/nightSkipRun``); this
/// view only draws them, and does not follow the world every tick.
struct NightSkipChip: View {
    let session: GameSession
    /// Decision 469: the icon alone where the row under the status pill has
    /// no room for the name (the time is in the status pill above).
    var iconOnly = false
    /// The chip's full width, measured whether or not it shows in full, so
    /// the row knows when the name fits again.
    var onFullWidth: (CGFloat) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let language = session.language
        let run = session.nightSkipRun
        let skip = run == nil ? session.nightSkipOffer : nil
        // A group, not a stack: with nothing to show it adds no gap to the
        // row it stands in.
        Group {
            if let run {
                chip(
                    title: NightSkip.stopTitle(at: run.stop, in: language), symbol: "stop.fill", id: "hud.nightSkip.stop"
                ) {
                    session.stopNightSkip()
                }
                .transition(.pop(reduceMotion: reduceMotion))
            } else if let skip {
                chip(title: skip.buttonTitle(in: language), symbol: "forward.end.fill", id: "hud.nightSkip") {
                    session.skipToMorning()
                }
                .accessibilityHint(Text(verbatim: NightSkip.hint(in: language)))
                .transition(.pop(reduceMotion: reduceMotion))
            }
        }
        // Decision 253: a small thing that appears by the speed; the row
        // beside it makes room as a change in place.
        .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: run != nil)
        .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: skip != nil)
    }

    private func chip(title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if iconOnly {
                    icon(symbol)
                        .frame(width: CGFloat(MapTopRow.nightSkipIconWidth), height: 44)
                } else {
                    label(title: title, symbol: symbol)
                }
            }
            .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            label(title: title, symbol: symbol)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onFullWidth($0) }
                .accessibilityHidden(true)
        }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityIdentifier(id)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.primary)
    }

    private func label(title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            icon(symbol)
            Text(verbatim: title)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(minHeight: 44)
    }
}
