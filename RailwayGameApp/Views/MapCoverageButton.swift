import GamePresentation
import SwiftUI

/// Decision 292: while a station or a line is being built, one tap shows
/// the catchment coverage layer, another (or leaving the tool) puts back
/// the layer there was (``CoverageShortcut``). Round glass beside the 3D
/// and zoom buttons, framed in teal while on, as the quick layers are.
struct MapCoverageButton: View {
    let isOn: Bool
    let language: DisplayLanguage
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "circle.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isOn ? Theme.primary : Theme.textPrimary)
                .frame(width: 44, height: 44)
                .glassBackground(in: Circle(), interactive: true)
                .overlay {
                    if isOn {
                        Circle().strokeBorder(Theme.primary, lineWidth: 1.5)
                    }
                }
        }
        .accessibilityLabel(Text(verbatim: language.text("Station coverage", "車站涵蓋")))
        .accessibilityHint(Text(verbatim: language.text(
            "Shows where people live and work within 800 m of a station, and where no station reaches.",
            "顯示車站 800 公尺內有人住、有人工作的地方，以及還沒有車站的地方。"
        )))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("map.coverageShortcut")
        .padding(.vertical, 12)
    }
}
