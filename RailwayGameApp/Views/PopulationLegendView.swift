import GamePresentation
import SwiftUI

/// The legend of the population and travel layer on the map, ported from
/// the `Ci/` reference's `map-overlay-legend--poptravel` cards and the map
/// layer panel's timeline (`map-layer-poptravel-timeline`):
///
/// - population (`legend-poptravel-population`): "人口网格", the 1 km grid's
///   gradient from 0 to 10000+ (`chinaGrid`), few → many;
/// - travel demand (`legend-poptravel-travel`): the six swatches
///   #000088 → #FF1100, few → many;
/// - demand change (`legend-poptravel-movement`): blue for a fall, red for
///   a rise, "颜色越深表示变化越大";
///
/// each with the opacity row and slider (`透明度`, 10 %–100 %), and for
/// the two hourly layers the hour (`08:00`), a 0–23 slider and play.
struct PopulationLegendView: View {
    let mode: PopTravelMode
    let language: DisplayLanguage
    @Binding var opacity: Double
    @Binding var hour: Int
    let isPlaying: Bool
    let onTogglePlay: () -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(verbatim: title)
                    .font(.caption2.weight(.bold))
                Spacer(minLength: 4)
                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: language.text("Close population legend", "關閉人口圖例")))
                }
            }

            scale

            HStack {
                Text(verbatim: lowText)
                Spacer()
                Text(verbatim: highText)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            if mode == .movement {
                Text(verbatim: language.text("Darker means a bigger change", "顏色越深表示變化越大"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(verbatim: language.text("Opacity", "透明度"))
                Spacer()
                Text(verbatim: "\(Int((opacity * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption2)
            Slider(value: $opacity, in: PopTravel.opacityRange, step: 0.01)
                .accessibilityLabel(Text(verbatim: language.text("\(title) opacity", "\(title)透明度")))
                .accessibilityIdentifier("map.popTravel.opacity")

            if mode.usesHour {
                timeline
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: 260)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: "\(lowText), \(highText)"))
        .accessibilityIdentifier("map.populationLegend")
    }

    /// The reference's `map.layers.populationGrid`, `travelDemand` and
    /// `demandChange`.
    private var title: String {
        switch mode {
        case .population: language.text("Population grid", "人口網格")
        case .travel: language.text("Travel demand", "出行需求")
        case .movement: language.text("Demand change", "需求變化")
        }
    }

    private var lowText: String {
        switch mode {
        case .population: "0"
        case .travel: language.text("Few", "少")
        case .movement: language.text("Decrease", "減少")
        }
    }

    private var highText: String {
        switch mode {
        case .population: "10000+"
        case .travel: language.text("Many", "多")
        case .movement: language.text("Increase", "增加")
        }
    }

    @ViewBuilder
    private var scale: some View {
        switch mode {
        case .population:
            LinearGradient(
                stops: PopTravel.populationGradient.map { Gradient.Stop(color: Color($0.color), location: $0.position) },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 12)
            .clipShape(Capsule())
        case .travel:
            HStack(spacing: 0) {
                ForEach(Array(PopTravel.travelLegend.enumerated()), id: \.offset) { _, color in
                    Color(color)
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
        case .movement:
            HStack(spacing: 0) {
                ForEach(Array(PopTravel.decreaseColors.reversed().enumerated()), id: \.offset) { _, color in
                    Color(color)
                }
                ForEach(Array(PopTravel.increaseColors.enumerated()), id: \.offset) { _, color in
                    Color(color)
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
        }
    }

    /// The timeline: the hour, a 0–23 slider and play (`poptravel-hour-range`,
    /// `poptravel-play-btn`).
    private var timeline: some View {
        HStack(spacing: 8) {
            Text(verbatim: PopTravel.hourLabel(hour))
                .font(.caption.weight(.semibold).monospacedDigit())
                .accessibilityIdentifier("map.popTravel.hourLabel")
            Slider(
                value: Binding(get: { Double(hour) }, set: { hour = PopTravel.clampedHour(Int($0.rounded())) }),
                in: 0 ... 23,
                step: 1
            )
            .accessibilityLabel(Text(verbatim: language.text("Hour", "時段")))
            .accessibilityValue(Text(verbatim: PopTravel.hourLabel(hour)))
            .accessibilityIdentifier("map.popTravel.hour")
            Button(action: onTogglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text(verbatim: language.text("Play or pause", "播放或暫停")))
            .accessibilityIdentifier("map.popTravel.play")
        }
    }
}
