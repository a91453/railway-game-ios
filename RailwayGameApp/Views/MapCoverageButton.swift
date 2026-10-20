import GamePresentation
import SwiftUI

/// Decision 292: while a station or a line is being built, one tap shows
/// the catchment coverage layer, another (or leaving the tool) puts back
/// the layer there was (``CoverageShortcut``). Round glass beside the 3D
/// and zoom buttons, framed in teal while on, as the quick layers are.
struct MapCoverageButton: View {
    let isOn: Bool
    let language: DisplayLanguage
    /// Decision 300: under a phone's panel, as tall as the credit button,
    /// a finger's target reaching this far below it (``MapCornerButtonFace``).
    var compactReach: CGFloat? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Decision 300: a station's dot and the dashed ring of its
            // reach (it was a bull's-eye, which reads as "find me").
            Image("GlyphCoverage")
                .resizable()
                .renderingMode(.template)
                .frame(width: compactReach == nil ? 24 : 18, height: compactReach == nil ? 24 : 18)
                .foregroundStyle(isOn ? Theme.primary : Theme.textPrimary)
                .modifier(MapCornerButtonFace(compactReach: compactReach, isOn: isOn))
        }
        .accessibilityLabel(Text(verbatim: language.text("Station coverage", "車站涵蓋")))
        .accessibilityHint(Text(verbatim: language.text(
            "Shows where people live and work within 800 m of a station, and where no station reaches.",
            "顯示車站 800 公尺內有人住、有人工作的地方，以及還沒有車站的地方。"
        )))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("map.coverageShortcut")
        .padding(.vertical, compactReach == nil ? 12 : 0)
    }
}

/// The face of a round button in the map's bottom-trailing corner: a
/// 44-point glass circle, framed in teal while `isOn`. Decision 300: under
/// a phone's panel a capsule as tall as the credit button
/// (``MapCornerRow/height``), a finger's target reaching `compactReach`
/// points below it.
struct MapCornerButtonFace: ViewModifier {
    let compactReach: CGFloat?
    var isOn = false

    func body(content: Content) -> some View {
        if let reach = compactReach {
            content
                .frame(width: 44, height: CGFloat(MapCornerRow.height))
                .glassBackground(in: Capsule(), interactive: true)
                .overlay {
                    if isOn {
                        Capsule().strokeBorder(Theme.primary, lineWidth: 1.5)
                    }
                }
                .frame(height: CGFloat(MapCornerRow.height) + reach, alignment: .top)
                .contentShape(Rectangle())
        } else {
            content
                .frame(width: 44, height: 44)
                .glassBackground(in: Circle(), interactive: true)
                .overlay {
                    if isOn {
                        Circle().strokeBorder(Theme.primary, lineWidth: 1.5)
                    }
                }
        }
    }
}
