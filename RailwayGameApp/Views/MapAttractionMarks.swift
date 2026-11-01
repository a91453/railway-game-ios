import GameCore
import GamePresentation
import SwiftUI

/// The sights, as a star and their rating over their place on the map
/// (decision 174), the star in the sky of a sight tourists can reach and
/// grey beside one they cannot. A tap opens the tourism panel. Shown while
/// the player is looking at the map (the Select tool), as the alert bubbles
/// are. Decision 174, later (a player's report): while building too, as
/// ``isPassive`` marks, faint and taking no touches, under the build's
/// flags, so a player can build by a sight. Decision 510 (a player's
/// report: taps meant for the map hit the marks): none from far, a star
/// alone from the middle zoom, the rating close up; a mark over a station,
/// a track or a warning bubble shows faint and lets the tap through.
struct MapAttractionMarks: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets
    /// The marks shown while a building tool is chosen: faint, taking no
    /// touches. Otherwise the marks of the Select tool.
    var isPassive = false
    /// Decision 477: where the map's clear part starts under the top bar
    /// and its column, for the tiles' prices of the map's expansion.
    var clearTop: CGFloat?
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Decision 377: the sights as the session keeps them, not read
            // from the world, so a tick that leaves them as they were
            // rebuilds nothing here.
            // Decision 477: while the map's tiles are for sale, none over
            // a tile's price.
            let marks = session.sightMarksTakeTouches != isPassive
                ? Self.drawn(session: session, camera: camera, viewport: viewport, insets: insets,
                             prices: Self.tilePrices(session: session, camera: camera, viewport: viewport, insets: insets, clearTop: clearTop))
                : []
            if !marks.isEmpty {
                // Decision 510: the stations, tracks and bubbles whose taps
                // a mark leaves to them.
                let guarded = isPassive ? nil : touchGuards
                ForEach(marks, id: \.sight.attraction.id) { item in
                    let takes = guarded.map { takesTouch(item, guards: $0) } ?? false
                    mark(item.sight, rated: item.rated)
                        .opacity(takes ? 1 : 0.5)
                        .allowsHitTesting(takes)
                        .accessibilityHidden(isPassive)
                        .fixedSize()
                        .frame(width: 0, height: 0, alignment: .center)
                        .position(x: item.at.x, y: item.at.y)
                }
            }
        }
        // Not on this view, which covers the whole map: hidden from
        // VoiceOver it hid the map and its zoom buttons from UI tests' taps.
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
    }

    /// The sights marked on screen and where, at the map's zoom
    /// (decision 510's ``MapClutter/sightStyle(referenceSize:)``). Decision
    /// 250: a mark that would lie on a better-rated one waits until the map
    /// is brought closer. The alert bubbles ask it too, so a sight's
    /// warning is not repeated over its mark.
    static func marks(session: GameSession, camera: PlanCamera, viewport: ScreenSize, insets: EdgeInsets)
        -> [(sight: MapMarks.Sight, at: ScreenPoint, rated: Bool)] {
        let style = MapClutter.sightStyle(referenceSize: camera.referenceSize)
        guard style != .none else { return [] }
        let rated = style == .rated
        // Decision 377: the sights as the session keeps them, not read
        // from the world.
        let onScreen: [(sight: MapMarks.Sight, at: ScreenPoint)] = session.mapSights.compactMap { sight in
            let at = camera.screenPoint(of: sight.attraction.point)
            guard at.x > Double(insets.leading), at.x < viewport.width - Double(insets.trailing),
                  at.y > Double(insets.top) + 40, at.y < viewport.height - Double(insets.bottom) else { return nil }
            return (sight, at)
        }
        let shown = SightMarks.shown(
            onScreen.map { SightMarks.Mark(id: $0.sight.attraction.id, stars: $0.sight.stars, x: $0.at.x, y: $0.at.y) },
            width: rated ? SightMarks.width : MapClutter.starWidth, height: rated ? SightMarks.height : MapClutter.starHeight
        )
        // Only the marks shown, not every sight: the whole of Taiwan has
        // 214, and this is worked out again as the world moves.
        return onScreen.filter { shown.contains($0.sight.attraction.id) }.map { ($0.sight, $0.at, rated) }
    }

    /// ``marks(session:camera:viewport:insets:)`` the map draws: none
    /// over a tile's price (decision 477). The alert bubbles ask it too
    /// (L3-9).
    static func drawn(session: GameSession, camera: PlanCamera, viewport: ScreenSize, insets: EdgeInsets,
                      prices: [MapLabelPlacement.Box]) -> [(sight: MapMarks.Sight, at: ScreenPoint, rated: Bool)] {
        let all = Self.marks(session: session, camera: camera, viewport: viewport, insets: insets)
        guard !prices.isEmpty else { return all }
        return all.filter { !MapLabelPlacement.coversPrice(x: $0.at.x, y: $0.at.y, stars: $0.sight.starsText, prices: prices) }
    }

    /// What a mark keeps off (decision 510): the stations' middles on
    /// screen, the warning bubbles' touch areas, and the track within a
    /// tap's reach, in world units.
    private var touchGuards: (stations: [ScreenPoint], bubbles: [MapLabelPlacement.Box], reach: Int64) {
        let stations = MapAlertBubbles.stationsOnScreen(session: session, camera: camera, viewport: viewport).map { ScreenPoint(x: $0.x, y: $0.y) }
        let bubbles = MapAlertBubbles.placements(session: session, camera: camera, viewport: viewport, insets: insets,
                                                  clearTop: clearTop).map(\.touchBox)
        return (stations, bubbles, Int64(camera.worldDistance(MapClutter.stationGuard)))
    }

    private func takesTouch(_ item: (sight: MapMarks.Sight, at: ScreenPoint, rated: Bool),
                            guards: (stations: [ScreenPoint], bubbles: [MapLabelPlacement.Box], reach: Int64)) -> Bool {
        let onTrack = session.sightIsOnTrack(item.sight.attraction.point, within: guards.reach)
        return MapClutter.sightTakesTouch(at: item.at, stations: guards.stations, bubbles: guards.bubbles, onTrack: onTrack)
    }

    /// Where the map draws the prices of the tiles for sale (``MapArt``'s
    /// `drawMapExpansion`), about; `clearTop` where the map's clear part
    /// starts, `insets.top` when `nil`.
    static func tilePrices(session: GameSession, camera: PlanCamera, viewport: ScreenSize, insets: EdgeInsets,
                           clearTop: CGFloat?) -> [MapLabelPlacement.Box] {
        guard let expansion = session.mapExpansionOverlay, !expansion.forSale.isEmpty else { return [] }
        let top = Double(clearTop ?? insets.top)
        let clear = MapLabelPlacement.Box(
            x: Double(insets.leading), y: top,
            width: viewport.width - Double(insets.leading + insets.trailing), height: viewport.height - top - Double(insets.bottom)
        )
        return expansion.forSale.compactMap { tile in
            let corner = camera.screenPoint(worldX: Double(tile.area.minX), worldY: Double(tile.area.minY))
            let far = camera.screenPoint(worldX: Double(tile.area.maxX), worldY: Double(tile.area.maxY))
            let area = MapLabelPlacement.Box(x: min(corner.x, far.x), y: min(corner.y, far.y), width: abs(far.x - corner.x), height: abs(far.y - corner.y))
            let width = MapLabelPlacement.priceWidth(tile.price.moneyText, locked: !tile.isUnlocked)
            return MapLabelPlacement.tileLabel(tile: area, clear: clear, width: width, height: 18)
        }
    }

    private func mark(_ fact: MapMarks.Sight, rated: Bool) -> some View {
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
                // Decision 510: the rating close up only.
                if rated {
                    Text(verbatim: fact.starsText)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
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
