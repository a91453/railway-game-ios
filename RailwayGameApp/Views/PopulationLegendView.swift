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

            VStack(spacing: 3) {
                LinearGradient(
                    colors: PopulationColorRamp.gradientColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 10)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )

                HStack {
                    Text(verbatim: "\(PopulationColorRamp.tiers.first?.min ?? 0)")
                    Spacer()
                    Text(verbatim: "1k")
                    Spacer()
                    Text(verbatim: "4k")
                    Spacer()
                    Text(verbatim: "\(PopulationColorRamp.tiers.last?.min ?? 10000)+")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: 240)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: titleText))
    }

    private var titleText: String {
        language.text("Population (/1km²)", "人口（人/約 1km 方格）")
    }
}
