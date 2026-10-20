import GameCore
import GamePresentation
import SwiftUI

/// The real stations offered while choosing where a platform goes on a
/// real-world map (decision 295): a dashed ring where the real station is,
/// like a station not built yet, and its name, faint beside the player's
/// own stations and under the build's flags. A tap picks the nearest track
/// and the real name (``GameSession/pickRealStation(_:)``); the ✓ builds it.
/// Not animated.
struct MapRealStationPins: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets

    /// The ring's diameter, about a station badge's.
    private static let ring: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topLeading) {
            let pins = session.realStationSuggestions.compactMap { suggestion -> (suggestion: RealStationSuggestion, x: Double, y: Double)? in
                let at = camera.screenPoint(of: suggestion.point)
                guard at.x > Double(insets.leading), at.x < viewport.width - Double(insets.trailing),
                      at.y > Double(insets.top) + 40, at.y < viewport.height - Double(insets.bottom) else { return nil }
                return (suggestion, at.x, at.y)
            }
            let shown = RealStationSuggestion.shown(pins)
            ForEach(pins.filter { shown.contains($0.suggestion.id) }.map { $0.suggestion }, id: \.id) { suggestion in
                let at = camera.screenPoint(of: suggestion.point)
                pin(suggestion)
                    .fixedSize()
                    .frame(width: 0, height: 0, alignment: .leading)
                    .offset(x: -Self.ring / 2)
                    .position(x: at.x, y: at.y)
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
    }

    private func pin(_ suggestion: RealStationSuggestion) -> some View {
        let name = suggestion.name(in: session.language)
        let dash = StrokeStyle(lineWidth: 1.5, dash: [3, 2])
        return Button {
            session.pickRealStation(suggestion)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Theme.panel)
                    .overlay(Circle().strokeBorder(Theme.textSecondary, style: dash))
                    .frame(width: Self.ring, height: Self.ring)
                Text(verbatim: name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(minHeight: 20)
                    .background(Theme.panel.opacity(0.9), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.textSecondary, style: dash))
            }
            // A finger's room round a small mark.
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Real station \(name)", "真實車站 \(name)")))
        .accessibilityHint(Text(verbatim: session.language.text(
            "Puts the platform on the nearest track, named \(name).",
            "把月台放到最近的軌道上，站名用 \(name)。"
        )))
        .accessibilityIdentifier("map.realStation.\(suggestion.id)")
    }
}
