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
/// the two hourly layers the hour (`08:00`), a 0–23 slider and play. The
/// city's layers (Phase 6d, ``CityMap``) have keys of their own: the three
/// uses' shades D1 to D4, the land value steps in $ a m², and the
/// catchment coverage's colours.
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
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 4)
                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: language.text("Close population legend", "關閉人口圖例")))
                }
            }

            scale

            if mode != .coverage {
                HStack {
                    Text(verbatim: lowText)
                    Spacer()
                    Text(verbatim: highText)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            }

            if mode == .movement {
                Text(verbatim: language.text("Darker means a bigger change", "顏色越深表示變化越大"))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            if mode == .landValue {
                Text(verbatim: language.text("Dollars a square metre; tap a cell for its parts", "單位：每平方公尺美元；點一格看分項"))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack {
                Text(verbatim: language.text("Opacity", "透明度"))
                Spacer()
                Text(verbatim: "\(Int((opacity * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary)
            Slider(value: $opacity, in: PopTravel.opacityRange, step: 0.01)
                .accessibilityLabel(Text(verbatim: language.text("\(title) opacity", "\(title)透明度")))
                .accessibilityIdentifier("map.popTravel.opacity")

            if mode.usesHour {
                timeline
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
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
        case .landUse, .landValue, .coverage: mode.title(in: language)
        }
    }

    private var lowText: String {
        switch mode {
        case .population: "0"
        case .travel: language.text("Few", "少")
        case .movement: language.text("Decrease", "減少")
        case .landUse: language.text("Low-rise (D1)", "低層（D1）")
        case .landValue: "$ 0"
        case .coverage: ""
        }
    }

    private var highText: String {
        switch mode {
        case .population: "10000+"
        case .travel: language.text("Many", "多")
        case .movement: language.text("Increase", "增加")
        case .landUse: language.text("Towers (D4)", "超高層（D4）")
        case .landValue: "$ \(CityMap.valueSteps.last ?? 0)+ / m²"
        case .coverage: ""
        }
    }

    // Theme: kept for Phase 8. The scale's colours are the map layer's own
    // (PopTravel, CityMap) and must match what the map draws; they move
    // with the map's colours when its renderer is replaced.
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
        case .landUse:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array([(1, "Homes", "住宅"), (2, "Shops", "商業"), (3, "Offices", "辦公")].enumerated()), id: \.offset) { _, use in
                    HStack(spacing: 6) {
                        Text(verbatim: language.text(use.1, use.2))
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 48, alignment: .leading)
                        HStack(spacing: 0) {
                            ForEach(1...4, id: \.self) { density in
                                Color(CityMap.useColor(use: use.0, density: density))
                            }
                        }
                        .frame(height: 10)
                        .clipShape(Capsule())
                    }
                }
            }
            .accessibilityIdentifier("map.landUseLegend")
        case .landValue:
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    ForEach(Array(CityMap.valueColors.enumerated()), id: \.offset) { _, color in
                        Color(color)
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                HStack(spacing: 0) {
                    ForEach(CityMap.valueSteps, id: \.self) { step in
                        Text(verbatim: "\(step)")
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: language.text("Land value, dollars a square metre", "地價，每平方公尺美元")))
            .accessibilityIdentifier("map.landValueLegend")
        case .coverage:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array([
                    (CityMap.coveredColor, "Within 800 m of a station", "車站 800 公尺內"),
                    (CityMap.coveredEmptyColor, "Within 800 m, no one there", "800 公尺內、沒有人"),
                    (CityMap.uncoveredColor, "People no station reaches", "有人但沒有車站涵蓋"),
                ].enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(entry.0)).frame(width: 14, height: 10)
                        Text(verbatim: language.text(entry.1, entry.2))
                            .font(.caption2)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .accessibilityIdentifier("map.coverageLegend")
        }
    }

    /// The timeline: the hour, a 0–23 slider and play (`poptravel-hour-range`,
    /// `poptravel-play-btn`).
    private var timeline: some View {
        HStack(spacing: 8) {
            Text(verbatim: PopTravel.hourLabel(hour))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
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
