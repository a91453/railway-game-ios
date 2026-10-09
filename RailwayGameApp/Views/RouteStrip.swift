import GamePresentation
import SwiftUI

/// A line drawn as its stops in a row on its colour, the way a station's
/// route map hangs over a platform (ARCHITECTURE decision 110): a dot for
/// each stop, the ends larger, the names under them. Scrolls sideways when
/// the line is long. The reference's line panel draws the same strip
/// upright (`Ci/` `renderLineInfoPanel`, `#line-info-pipeline-bar`), and
/// on it a dot for each train (`updateLineInfoTrainDots`): here a train
/// on its way out runs above the line and one coming back below it
/// (decision 113).
struct RouteStrip: View {
    let names: [String]
    let color: Color
    var trains: [LineTrainDot] = []

    /// The width each stop takes; the line runs through their middles.
    private static let stopWidth = 64.0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    stop(name, isEnd: index == 0 || index == names.count - 1, isFirst: index == 0, isLast: index == names.count - 1)
                }
            }
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(trains, id: \.train) { dot in
                        train(dot)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.top, trains.isEmpty ? 0 : 10)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: names.joined(separator: ", ")))
    }

    /// A train: a small tram on the line's colour, centred over its place
    /// along the stops, above the line going out and below it coming back.
    private func train(_ dot: LineTrainDot) -> some View {
        let size = 16.0
        let x = Self.stopWidth / 2 + Self.stopWidth * dot.position - size / 2
        // The line runs 9 points down the stop's top row.
        let y = dot.isOutbound ? 9 - size - 2 : 9 + 2
        return MapGlyph.train.image
            .resizable()
            .scaledToFit()
            .frame(width: 10, height: 10)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .overlay(Circle().strokeBorder(Theme.panel, lineWidth: 1.5))
            .offset(x: x, y: y)
            .animation(.linear(duration: 0.5), value: dot.position)
            .accessibilityHidden(true)
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
                .frame(width: Self.stopWidth)
        }
        .frame(width: Self.stopWidth)
    }
}
