import GameCore
import GamePresentation
import SwiftUI

/// The sights, as a star and their rating over their place on the map
/// (decision 174), the star in the sky of a sight tourists can reach and
/// grey beside one they cannot. A tap opens the tourism panel. Shown while
/// the player is looking at the map (the Select tool), as the alert bubbles
/// are. Decision 174, later (a player's report): while building too, as
/// ``isPassive`` marks, faint and taking no touches, under the build's
/// flags, so a player can build by a sight.
struct MapAttractionMarks: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets
    /// The marks shown while a building tool is chosen: faint, taking no
    /// touches. Otherwise the marks of the Select tool.
    var isPassive = false
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Decision 377: the sights as the session keeps them, not read
            // from the world, so a tick that leaves them as they were
            // rebuilds nothing here.
            let sights = session.sightMarksTakeTouches != isPassive ? session.mapSights : []
            if !sights.isEmpty {
                // Decision 250: a mark that would lie on a better-rated
                // one waits until the map is brought closer.
                let shown = SightMarks.shown(sights.compactMap { sight -> SightMarks.Mark? in
                    let at = camera.screenPoint(of: sight.attraction.point)
                    guard at.x > Double(insets.leading), at.x < viewport.width - Double(insets.trailing),
                          at.y > Double(insets.top) + 40, at.y < viewport.height - Double(insets.bottom) else { return nil }
                    return SightMarks.Mark(id: sight.attraction.id, stars: sight.stars, x: at.x, y: at.y)
                })
                // Only the marks shown, not every sight: the whole of Taiwan
                // has 214, and this is worked out again as the world moves.
                ForEach(sights.filter { shown.contains($0.attraction.id) }, id: \.attraction.id) { sight in
                    let at = camera.screenPoint(of: sight.attraction.point)
                    mark(sight)
                        .opacity(isPassive ? 0.5 : 1)
                        .allowsHitTesting(!isPassive)
                        .accessibilityHidden(isPassive)
                        .fixedSize()
                        .frame(width: 0, height: 0, alignment: .center)
                        .position(x: at.x, y: at.y)
                }
            }
        }
        // Not on this view, which covers the whole map: hidden from
        // VoiceOver it hid the map and its zoom buttons from UI tests' taps.
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
    }

    private func mark(_ fact: MapMarks.Sight) -> some View {
        let sight = fact.attraction
        // Whether a station serves it (the panel says more).
        let open = fact.isServed
        let text = "\(sight.name(in: session.language)) \(fact.starsText)"
        return Button {
            // Decision 250 (a player's report): the panel opens at this
            // sight's row.
            screen.sightFocus = sight.id
            screen.panel = .tourism
        } label: {
            HStack(spacing: 3) {
                MapGlyph.star.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(open ? Theme.accent : Theme.textSecondary)
                    .accessibilityHidden(true)
                Text(verbatim: fact.starsText)
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
