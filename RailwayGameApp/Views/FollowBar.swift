import GameCore
import GamePresentation
import SwiftUI

/// The bar over the map while the camera follows a train
/// (``GameSession/followedTrain``), ported from the `Railway/` site's
/// `.followbar` (`renderFollowBar`): a 9-point dot in the train's colour
/// (its line's, ``Palette/lineColor(_:)``), the train's name in bold, its
/// service, first → last stop and first departure – last arrival, the
/// follow status ("Not departed", "Arrived"), and the stop-following button
/// (`取消跟隨`, "Stop following") at the end. Its content is what the
/// session keeps of the world for it (``GameSession/followBar``, decision
/// 471), so a tick that changes nothing it shows does not rebuild it.
struct FollowBar: View {
    let facts: FollowBarFacts
    let session: GameSession
    /// Decision 333: opens the 3D map following this train from behind;
    /// `nil` hides the button.
    var open3D: (() -> Void)? = nil
    let onUnfollow: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let language = session.language
        // Decision 226 (2026-10-15): beside the layer strip, the room left
        // before the details card, which says the trip in full: the widest
        // of these that fits, the name never broken over lines, down to the
        // badge and the stop (decision 251).
        ViewThatFits(in: .horizontal) {
            row {
                badge
                name
                if let detail = facts.detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                if let trip = facts.trip {
                    if horizontalSizeClass == .regular {
                        FollowBarProgress(session: session)
                            .frame(width: 72)
                    }
                    times(trip)
                    status(trip)
                }
                speeds(language)
                threeD
                unfollow(short: false)
            }
            row {
                badge
                name
                if let trip = facts.trip {
                    times(trip)
                    status(trip)
                }
                speeds(language)
                threeD
                unfollow(short: true)
            }
            row {
                badge
                name
                speeds(language)
                threeD
                unfollow(short: true)
            }
            row {
                badge
                speeds(language)
                threeD
                unfollow(short: true)
            }
            // Decision 251: the last of them always fits, down to the badge
            // and the stop (the bar beside a narrow layer strip on a small
            // phone went past the screen's edge); the speeds are in the
            // status bar too.
            row {
                badge
                unfollow(short: true)
            }
        }
        .accessibilityElement(children: .contain)
        .hudFrameMark("follow.bar")
    }

    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 9) {
            content()
        }
        .fixedSize()
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
        )
    }

    /// Decision 216: the train's line by its badge; a dot when it runs on
    /// none.
    @ViewBuilder
    private var badge: some View {
        if let line = facts.line {
            LineCodeBadge(
                code: facts.lineCode,
                color: Palette.lineColor(line, custom: facts.lineColor),
                size: .small
            )
        } else {
            Circle()
                .fill(Palette.train)
                .frame(width: 9, height: 9)
        }
    }

    private var name: some View {
        Text(verbatim: facts.name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
    }

    /// Decision 223: the trip's times, the arrival struck through when late.
    private func times(_ trip: FollowBarFacts.Trip) -> some View {
        HStack(spacing: 3) {
            Text(verbatim: trip.departure + "–")
                .foregroundStyle(Theme.textPrimary)
            LateTimeText(scheduled: trip.arrival, expected: trip.expectedArrival)
                .foregroundStyle(Theme.textPrimary)
        }
        .font(.footnote.monospacedDigit())
        .lineLimit(1)
    }

    /// Decision 223: on time, late or the follow status, as the train
    /// card's capsule (``TrainStatusCapsule/init(card:language:)``).
    private func status(_ trip: FollowBarFacts.Trip) -> some View {
        TrainStatusCapsule(text: trip.statusText, kind: trip.showsPunctuality ? (trip.isLate ? .late : .onTime) : .neutral)
    }

    /// Decision 195: real time or ten times it, one tap each, through the
    /// speed the speed menu sets; following stops without changing it back.
    private func speeds(_ language: DisplayLanguage) -> some View {
        let session = session
        let running = facts.runningSpeed
        // A sendable closure, not main-actor code (CRASH101, CRASHSWEEP):
        // the bar's rows stand in a ViewThatFits, whose layouts SwiftUI's
        // asynchronous renderer may measure, and build, off the main thread.
        return ForEach(FollowBarInfo.speedShortcuts, id: \.self) { @Sendable speed in
            FollowSpeedButton(session: session, speed: speed, isCurrent: running == speed, language: language)
        }
    }

    /// Decision 333: the 3D map's button, following this train there.
    @ViewBuilder
    private var threeD: some View {
        if let open3D {
            Button(action: open3D) {
                Image("Glyph3DMap")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: session.language.text("Follow in 3D", "在 3D 跟車")))
            .accessibilityIdentifier("follow.map3D")
        }
    }

    /// The stop, in words where there is room, else a cross.
    private func unfollow(short: Bool) -> some View {
        Button {
            onUnfollow()
        } label: {
            Group {
                if short {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.heavy))
                        .frame(width: 26, height: 26)
                        .background(Theme.chip, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.panelBorder, lineWidth: 1))
                } else {
                    Text(verbatim: unfollowText)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.panelBorder, lineWidth: 1))
                }
            }
            // Stopping following loses nothing, so it is not red (UI health check O).
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: unfollowText))
        .accessibilityIdentifier("train.unfollow")
    }

    /// The site's `取消跟隨` ("Stop following" in its translations).
    private var unfollowText: String {
        session.language.text("Stop following", "取消跟隨")
    }
}

/// Decision 471: the follow bar's trip progress, its own view, so the
/// progress, which moves at most ticks, rebuilds only itself.
private struct FollowBarProgress: View {
    let session: GameSession

    var body: some View {
        TrainTripProgressBar(progress: session.followProgress, height: 6, marker: 16)
    }
}

/// A follow bar speed shortcut (decision 195): a chip of at least 38 by 26 points,
/// filled while the game runs at its speed, touched over at least 44 by 44 points.
/// The touch area belongs to the style's body, as the status pill's
/// buttons have it (a touch area set inside a button's label is not used).
/// One of ``FollowBar``'s speed shortcuts (decision 195).
private struct FollowSpeedButton: View {
    let session: GameSession
    let speed: GameSpeed
    let isCurrent: Bool
    let language: DisplayLanguage

    var body: some View {
        Button {
            session.setSpeed(speed)
        } label: {
            Text(verbatim: speed.label(in: language))
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .buttonStyle(FollowSpeedButtonStyle(isCurrent: isCurrent))
        .disabled(session.isLayingDemoRealLines)
        .accessibilityLabel(Text(verbatim: speed.accessibilityName(in: language)))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("follow.speed.\(speed.rawValue)")
    }
}

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
