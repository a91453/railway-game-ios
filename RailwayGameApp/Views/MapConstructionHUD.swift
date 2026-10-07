import GameCore
import GamePresentation
import SwiftUI

/// Floating HUD displaying dimensions, costs, and feedback for the current track preview.
///
/// Ported from the owner's `Ci/` build mode HUD (`.place-distance-hud` and `.metro-cost-preview-pill`).
/// Only reads fields directly provided by `NetworkPreview`: length, start/end height, cost, and problem.
struct MapConstructionHUD: View {
    let preview: NetworkPreview
    let language: DisplayLanguage

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                // Length
                HStack(spacing: 4) {
                    Image(systemName: "ruler")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.primary)
                    Text(NetworkBuilding.lengthText(preview.length, in: language))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(text("Length: \(NetworkBuilding.lengthText(preview.length, in: language))", "長度：\(NetworkBuilding.lengthText(preview.length, in: language))"))

                Divider()
                    .frame(height: 14)

                // Height profile
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.primary)
                    if preview.startHeight == preview.endHeight {
                        Text(NetworkBuilding.lengthText(preview.startHeight, in: language))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text(verbatim: "\(NetworkBuilding.lengthText(preview.startHeight, in: language)) → \(NetworkBuilding.lengthText(preview.endHeight, in: language))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(heightAccessibilityLabel)

                // Cost (if buildable and costed)
                if let cost = preview.cost {
                    Divider()
                        .frame(height: 14)

                    HStack(spacing: 4) {
                        Image(systemName: "banknote")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.success)
                        Text(cost.moneyText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(text("Cost: \(cost.moneyText)", "費用：\(cost.moneyText)"))
                }
            }

            // Refusal reason (problem) or track continuity status
            if let problem = preview.problem {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.warning)
                    Text(problem)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(text("Problem: \(problem)", "問題：\(problem)"))
            } else if preview.joinsStart || preview.joinsEnd {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(continuityText)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(Theme.textPrimary)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.constructionHUD")
    }

    /// `english` or `chinese` for the session's language. GamePresentation's
    /// own `DisplayLanguage.text` is internal to that module, so the app
    /// picks by the public enum, as the line panel does.
    private func text(_ english: String, _ chinese: String) -> String {
        language == .traditionalChinese ? chinese : english
    }

    private var continuityText: String {
        switch (preview.joinsStart, preview.joinsEnd) {
        case (true, true): return text("joins track at both ends", "兩端均與軌道相接")
        case (true, false): return text("continues existing track", "延續既有軌道")
        case (false, true): return text("joins track at end", "終點與軌道相接")
        case (false, false): return ""
        }
    }

    private var heightAccessibilityLabel: String {
        if preview.startHeight == preview.endHeight {
            return text("Height: \(NetworkBuilding.lengthText(preview.startHeight, in: language))", "高度：\(NetworkBuilding.lengthText(preview.startHeight, in: language))")
        } else {
            return text("Height: \(NetworkBuilding.lengthText(preview.startHeight, in: language)) to \(NetworkBuilding.lengthText(preview.endHeight, in: language))", "高度：\(NetworkBuilding.lengthText(preview.startHeight, in: language)) 至 \(NetworkBuilding.lengthText(preview.endHeight, in: language))")
        }
    }
}
