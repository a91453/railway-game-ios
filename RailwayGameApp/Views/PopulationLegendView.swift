import GamePresentation
import SwiftUI

/// A compact floating legend for the WorldPop ~1km population density heatmap.
///
/// Faithfully reproduces the `Ci/` reference's `poptravel-pop-legend` and
/// `syncPopTravelPopulationLegendUi` visual style and color scale.
struct PopulationLegendView: View {
    let language: DisplayLanguage
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label {
                    Text(verbatim: titleText)
                        .font(.caption2.weight(.bold))
                } icon: {
                    Image(systemName: "person.3.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }

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

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(PopulationColorRamp.tiers, id: \.min) { tier in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tier.color)
                            .frame(height: 10)
                            .overlay {
                                RoundedRectangle(cornerRadius: 2)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            }
                        Text(verbatim: tier.label)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: titleText))
        .accessibilityValue(Text(verbatim: PopulationColorRamp.tiers.map(\.label).joined(separator: ", ")))
        .accessibilityIdentifier("map.populationLegend")
    }

    private var titleText: String {
        language.text("Population (/1km²)", "人口（人/約 1km 方格）")
    }
}
