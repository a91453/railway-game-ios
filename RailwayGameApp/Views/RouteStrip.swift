import SwiftUI

/// A line drawn as its stops in a row on its colour, the way a station's
/// route map hangs over a platform (ARCHITECTURE decision 110): a dot for
/// each stop, the ends larger, the names under them. Scrolls sideways when
/// the line is long. The reference's line panel draws the same strip
/// upright (`Ci/` `renderLineInfoPanel`, `#line-info-pipeline-bar`).
struct RouteStrip: View {
    let names: [String]
    let color: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    stop(name, isEnd: index == 0 || index == names.count - 1, isFirst: index == 0, isLast: index == names.count - 1)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: names.joined(separator: ", ")))
    }

    private func stop(_ name: String, isEnd: Bool, isFirst: Bool, isLast: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // The line, run through the stop to the next one.
                HStack(spacing: 0) {
                    Rectangle().fill(isFirst ? Color.clear : color)
                    Rectangle().fill(isLast ? Color.clear : color)
                }
                .frame(height: 6)
                Circle()
                    .fill(Theme.panel)
                    .overlay(Circle().strokeBorder(color, lineWidth: isEnd ? 4 : 3))
                    .frame(width: isEnd ? 18 : 14, height: isEnd ? 18 : 14)
            }
            .frame(height: 18)
            Text(verbatim: name)
                .font(.caption2.weight(isEnd ? .bold : .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(width: 64)
        }
        .frame(width: 64)
    }
}
