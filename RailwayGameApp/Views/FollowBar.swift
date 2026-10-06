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
                .fill(info?.line.map(Palette.lineColor) ?? Palette.train)
                .frame(width: 9, height: 9)

            Text(verbatim: train.name)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()

            if let detail = info?.detail(in: language), !detail.isEmpty {
                Text(verbatim: detail)
                    .font(.footnote.monospacedDigit())
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
                    .background(Palette.metroRed, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .foregroundStyle(Color(red: 1, green: 0.973, blue: 0.925))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: unfollowText))
            .accessibilityIdentifier("train.unfollow")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 1.5)
        )
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }

    /// The site's `取消跟隨` ("Stop following" in its translations).
    private var unfollowText: String {
        session.language.text("Stop following", "取消跟隨")
    }
}
