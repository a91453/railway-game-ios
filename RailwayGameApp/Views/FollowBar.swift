import GameCore
import GamePresentation
import SwiftUI

/// Floating bar shown when camera is dynamically following a train.
///
/// Faithfully reproduces the `Railway/` reference's `.followbar` and
/// `Ci/` reference's `metro.train.follow` control.
struct FollowBar: View {
    let train: Train
    let session: GameSession
    let onUnfollow: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Palette.metroBlue)
                .frame(width: 8, height: 8)

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
                    .background(loadBadgeColor(load.level).opacity(0.15))
                    .foregroundStyle(loadBadgeColor(load.level))
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

    private func loadBadgeColor(_ level: TrainLoadInfo.Level) -> Color {
        switch level {
        case .normal: return Color.green
        case .busy: return Palette.metroAmber
        case .crowded: return Color.red
        }
    }
}
