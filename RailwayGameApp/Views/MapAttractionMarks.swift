import GameCore
import GamePresentation
import SwiftUI

/// The sights, as a star and their rating over their place on the map
/// (decision 174), the star in the sky of a sight tourists can reach and
/// grey beside one they cannot. A tap opens the tourism panel. Shown while
/// the player is looking at the map (the Select tool), as the alert bubbles
/// are, and not over what is being built.
struct MapAttractionMarks: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        ZStack(alignment: .topLeading) {
            if session.tool == .select, let sights = session.world.tourism?.attractions {
                ForEach(sights, id: \.id) { sight in
                    let at = camera.screenPoint(of: sight.point)
                    if at.x > Double(insets.leading), at.x < viewport.width - Double(insets.trailing),
                       at.y > Double(insets.top) + 40, at.y < viewport.height - Double(insets.bottom) {
                        mark(sight)
                            .fixedSize()
                            .frame(width: 0, height: 0, alignment: .center)
                            .position(x: at.x, y: at.y)
                    }
                }
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
    }

    private func mark(_ sight: Attraction) -> some View {
        // Whether a station serves it (the panel says more): asked at every
        // redraw, so nothing that builds the route graph.
        let open = session.world.attractionStation(of: sight.id) != nil
        let text = "\(sight.name(in: session.language)) \(sight.starsText)"
        return Button {
            screen.panel = .tourism
        } label: {
            HStack(spacing: 3) {
                MapGlyph.star.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(open ? Theme.accent : Theme.textSecondary)
                    .accessibilityHidden(true)
                Text(verbatim: sight.starsText)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 6)
            .frame(minHeight: 22)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(open ? Theme.accent : Theme.textSecondary, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityHint(Text(verbatim: session.language.text("Opens the sights.", "打開觀光景點。")))
        .accessibilityIdentifier("map.sight.\(sight.id.rawValue)")
    }
}
