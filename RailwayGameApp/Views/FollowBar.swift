import GameCore
import GamePresentation
import SwiftUI

/// The bar over the map while the camera follows a train
/// (``GameSession/followedTrain``), ported from the `Railway/` site's
/// `.followbar` (`renderFollowBar`): a 9-point dot in the train's colour
/// (its line's, ``Palette/lineColor(_:)``), the train's name in bold, its
/// service, first → last stop and first departure – last arrival, the
/// follow status ("Not departed", "Arrived"), and the stop-following button
/// (`取消跟隨`, "Stop following") at the end. Its content is read from the
/// world each time (``GameWorld/followBarInfo(of:in:)``).
struct FollowBar: View {
    let train: Train
    let session: GameSession
    let onUnfollow: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let language = session.language
        let info = session.world.followBarInfo(of: train.id, in: language)
        HStack(spacing: 9) {
            // Decision 216: the train's line by its badge; a dot when it
            // runs on none.
            if let line = info?.line {
                LineCodeBadge(
                    code: LineBadge.codes(for: session.world.lines)[line] ?? "",
                    color: Palette.lineColor(line, custom: session.world.line(id: line)?.color),
                    size: .small
                )
            } else {
                Circle()
                    .fill(Palette.train)
                    .frame(width: 9, height: 9)
            }

            Text(verbatim: train.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()

            // Decision 223: a train on a trip shows its times with the
            // arrival struck through when late, a status in words and, on
            // a wide screen, the trip's bar.
            let card = session.world.trainCard(of: train.id, in: language)
            if let detail = info?.detail(in: language, times: card == nil), !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            if let card {
                if horizontalSizeClass == .regular {
                    TrainTripProgressBar(progress: card.progress, height: 6, marker: 16)
                        .frame(width: 72)
                }
                HStack(spacing: 3) {
                    Text(verbatim: card.departure.clockText + "–")
                        .foregroundStyle(Theme.textPrimary)
                    LateTimeText(scheduled: card.arrival.clockText, expected: card.isLate ? card.expectedArrival.clockText : nil)
                        .foregroundStyle(Theme.textPrimary)
                }
                .font(.footnote.monospacedDigit())
                .lineLimit(1)
                .fixedSize()
                TrainStatusCapsule(card: card, language: language)
            }

            Spacer(minLength: 4)

            // Decision 195: real time or ten times it, one tap each, through
            // the speed the speed menu sets; following stops without
            // changing it back.
            let clock = session.world.clock
            ForEach(FollowBarInfo.speedShortcuts, id: \.self) { speed in
                let isCurrent = !clock.isPaused && clock.speed == speed
                Button {
                    session.setSpeed(speed)
                } label: {
                    Text(verbatim: speed.label(in: language))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
                .buttonStyle(FollowSpeedButtonStyle(isCurrent: isCurrent))
                .accessibilityLabel(Text(verbatim: speed.accessibilityName(in: language)))
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
                .accessibilityIdentifier("follow.speed.\(speed.rawValue)")
            }

            Button {
                onUnfollow()
            } label: {
                Text(verbatim: unfollowText)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.error, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(Theme.onError)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: unfollowText))
            .accessibilityIdentifier("train.unfollow")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }

    /// The site's `取消跟隨` ("Stop following" in its translations).
    private var unfollowText: String {
        session.language.text("Stop following", "取消跟隨")
    }
}

/// A follow bar speed shortcut (decision 195): a chip of at least 38 by 26 points,
/// filled while the game runs at its speed, touched over at least 44 by 44 points.
/// The touch area belongs to the style's body, as the status pill's
/// buttons have it (a touch area set inside a button's label is not used).
private struct FollowSpeedButtonStyle: ButtonStyle {
    let isCurrent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 4)
            .frame(minWidth: 38, minHeight: 26)
            .background(isCurrent ? Theme.primary : Theme.chip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(isCurrent ? Theme.onPrimary : Theme.textPrimary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            // 3 points out each side and 9 up and down: 44 by 44.
            .padding(.horizontal, 3)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .padding(.horizontal, -3)
            .padding(.vertical, -9)
    }
}
