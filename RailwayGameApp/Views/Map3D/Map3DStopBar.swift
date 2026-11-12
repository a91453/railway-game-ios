import GamePresentation
import SwiftUI

/// Decision 710: over the last 200 m of a run driven by hand, one thin
/// bar under the strip at the top (over the sky, not the track ahead):
/// short of the stopping point, the target, past it, with a marker where
/// the train's head is and how far it still has to go. What it shows is
/// ``ManualDrive/StopBar``'s; here only its drawing.
struct Map3DStopBar: View {
    let bar: ManualDrive.StopBar
    let language: DisplayLanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The track's and the marker's sizes, with the type.
    @ScaledMetric(relativeTo: .caption) private var trackHeight: CGFloat = 6
    @ScaledMetric(relativeTo: .caption) private var markerHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(verbatim: ManualDrive.StopBar.text(of: bar.state, in: language))
            } icon: {
                Image(systemName: symbol)
            }
            .font(.caption.weight(.heavy))
            .foregroundStyle(ink)
            .fixedSize()
            track
            Text(verbatim: bar.text(in: language))
                .font(.subheadline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 260, maxWidth: 400, minHeight: 32)
        .glassBackground(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ManualDrive.StopBar.title(in: language)))
        .accessibilityValue(Text(verbatim: bar.value(in: language)))
        .accessibilityIdentifier("map3D.drive.stopBar")
        .hudFrameMark("map3D.drive.stopBar")
    }

    /// The state is said with a sign and a word, not by colour alone.
    private var symbol: String {
        switch bar.state {
        case .short: "arrow.right.to.line"
        case .onTarget: "checkmark.circle.fill"
        case .past: "exclamationmark.triangle.fill"
        }
    }

    private var ink: Color {
        switch bar.state {
        case .short: Theme.textSecondary
        case .onTarget: Theme.success
        case .past: Theme.error
        }
    }

    /// The bar itself: plain short of the target, the target a taller
    /// solid block, the stretch past it in the error colour, and the
    /// marker over where the head is.
    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width, target = ManualDrive.StopBar.target
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.chip)
                    .frame(width: width, height: trackHeight)
                Capsule()
                    .fill(Theme.error)
                    .opacity(0.45)
                    .frame(width: width * CGFloat(1 - target.upperBound), height: trackHeight)
                    .offset(x: width * CGFloat(target.upperBound))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.success)
                    .frame(width: width * CGFloat(target.upperBound - target.lowerBound), height: trackHeight * 2)
                    .offset(x: width * CGFloat(target.lowerBound))
                Capsule()
                    .fill(Theme.textPrimary)
                    .frame(width: 4, height: markerHeight)
                    .offset(x: width * CGFloat(bar.marker) - 2)
                    .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: bar.marker)
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
        .frame(minWidth: 90, minHeight: markerHeight)
    }
}
