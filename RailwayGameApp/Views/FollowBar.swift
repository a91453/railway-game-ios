import GameCore
import GamePresentation
import SwiftUI

/// The bar over the map while the camera follows a train
/// (``GameSession/followedTrain``): the `Railway/` site's `.followbar`
/// (`renderFollowBar`): a dot in the train's colour (here its line's, see
/// ``Palette/lineColor(_:)``), the train's name, and the unfollow button
/// (`取消跟隨`).
struct FollowBar: View {
    let train: Train
    let session: GameSession
    let onUnfollow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 9, height: 9)

            Text(verbatim: train.name)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()

            if let service = session.world.trainServiceStatus(of: train.id, in: session.language) {
                Text(verbatim: service.serviceName ?? service.stopText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let stop = session.world.stationStopText(of: train.id, in: session.language) {
                Text(verbatim: stop)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let load = session.world.trainLoadInfo(of: train.id) {
                Text(verbatim: "\(load.percentage)%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(loadColor(load).opacity(0.15))
                    .foregroundStyle(loadColor(load))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 4)

            Button {
                onUnfollow()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                    Text(verbatim: unfollowText)
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(Color.red)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: unfollowText))
            .accessibilityIdentifier("train.unfollow")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.cardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }

    private var unfollowText: String {
        session.language.text("Unfollow", "取消跟隨")
    }

    /// The train's line colour (the site's `tr.color`); a train on no
    /// line has the map's train colour.
    private var dotColor: Color {
        session.world.assignedLine(of: train.id).map(Palette.lineColor) ?? Palette.train
    }

    /// Neutral, or red when overloaded, as the reference's load bar.
    private func loadColor(_ load: TrainLoadInfo) -> Color {
        load.isOverload ? Palette.paxBarOverload : Color.primary
    }
}
