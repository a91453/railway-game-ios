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

    var body: some View {
        let language = session.language
        let info = session.world.followBarInfo(of: train.id, in: language)
        HStack(spacing: 9) {
            Circle()
                .fill(info?.line.map { Palette.lineColor($0, custom: session.world.line(id: $0)?.color) } ?? Palette.train)
                .frame(width: 9, height: 9)

            Text(verbatim: train.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()

            if let detail = info?.detail(in: language), !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 4)

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
