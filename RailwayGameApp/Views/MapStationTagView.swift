import GameCore
import GamePresentation
import SwiftUI

extension EnvironmentValues {
    /// Whether the details card is open (decision 119): the station's tag
    /// stands over the map only while it is not.
    @Entry var mapDetailsOpen = false
}

/// The tag by the station selected while looking at the map (decision
/// 119), under it: its name, who waits there and its lines' colours (``StationTag``).
/// A tap on it opens the details card; its pencil opens the station's
/// panel, as holding the station does, with the rename alert up and its
/// field ready to type in (TestFlight 60.1), so VoiceOver and Switch
/// Control have a way to it that is not a long press. Shown only while
/// neither is open.
struct MapStationTagView: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets
    /// Where the map's clear part starts under the top bar and its column
    /// (decision 477), for the bubbles' tile prices.
    var clearTop: CGFloat?
    @Environment(\.mapDetailsOpen) private var detailsOpen
    @Environment(GameScreenState.self) private var screen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size = CGSize(width: 160, height: 44)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let tag {
                content(tag)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .offset(placement(under: camera.screenPoint(of: tag.location)))
                    .transition(.pop(anchor: .top, reduceMotion: reduceMotion))
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        // Decision 253: it pops up under the station tapped, and moves to
        // the next one tapped (at once with Reduce Motion).
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: tag?.station)
    }

    private var tag: StationTag? {
        // Decision 100, later: a new line being picked has its own ✓
        // under the station.
        guard session.tool == .select, session.tutorial == nil, !detailsOpen, screen.panel == nil,
              session.mapLineDraft == nil,
              let id = session.selectedStationID
        else { return nil }
        return StationTag(world: session.world, station: id)
    }

    private func content(_ tag: StationTag) -> some View {
        StationTagCard(tag: tag, session: session, details: { screen.detailsRequests &+= 1 }, rename: {
            screen.renamesStationOnOpen = true
            screen.panel = .station
        })
    }

    /// Under `point`, clear of the station's mark (its bubbles, decision
    /// 109, stand over it) and of its name under the mark (decision 123:
    /// the tag covered the name's lower half), or over it when there is no
    /// room below; kept clear of the controls along the map's edges.
    /// Decision 501: and off the bubbles, which it is drawn over: a bubble
    /// under the station's name (decision 477) lay under the tag, and after
    /// the first tap every tap on it went to the tag.
    private func placement(under point: ScreenPoint) -> CGSize {
        let margin = 8.0
        let clear = MapLabelPlacement.Box(
            x: Double(insets.leading) + margin, y: Double(insets.top) + margin,
            width: viewport.width - Double(insets.leading) - Double(insets.trailing) - 2 * margin,
            height: viewport.height - Double(insets.top) - Double(insets.bottom) - 2 * margin
        )
        let bubbles = MapAlertBubbles.placements(session: session, camera: camera, viewport: viewport, insets: insets, clearTop: clearTop).map(\.touchBox)
            // Decision 510: and the badge of the alerts not on the map.
            + [MapAlertBubbles.badgeTouchBox(session: session, camera: camera, viewport: viewport, insets: insets, clearTop: clearTop)].compactMap { $0 }
        // Decision 501: and, moved, off the other stations where it can.
        let stations = MapLabelPlacement.obstacles(MapAlertBubbles.stationsOnScreen(session: session, camera: camera, viewport: viewport),
                                                   radius: MapArt.stationRadius(camera), own: (point.x, point.y))
        let box = MapLabelPlacement.stationTag(at: point, width: Double(size.width), height: Double(size.height), clear: clear, avoiding: bubbles,
                                               keepingOff: stations, stationRadius: MapArt.stationRadius(camera))
        return CGSize(width: box.minX, height: box.minY)
    }
}

/// The station tag's card (decision 119): the lines' badges, the name, who
/// waits there; a tap opens the details, the pencil the station's panel
/// with the rename field up. Decision 517 續: the 2D map's tag and the 3D
/// map's (``Map3DStationTagView``) are this one card.
struct StationTagCard: View {
    let tag: StationTag
    let session: GameSession
    let details: () -> Void
    let rename: () -> Void
    var identifier = "map.stationTag"

    var body: some View {
        HStack(spacing: 0) {
            Button(action: details) {
                HStack(spacing: 8) {
                    if !tag.lines.isEmpty {
                        // Decision 216: the lines' badges, stacked.
                        let codes = LineBadge.codes(for: session.world.lines)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(tag.lines.prefix(3), id: \.id) { line in
                                LineCodeBadge(code: codes[line.id] ?? "", color: Palette.lineColor(line.id, custom: line.color), size: .small)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: tag.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let waiting = tag.waitingText(in: session.language) {
                            Text(verbatim: waiting)
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: [tag.name, tag.waitingText(in: session.language)].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityHint(Text(verbatim: session.language.text("Shows the station's details.", "顯示車站的詳細資料。")))
            .accessibilityIdentifier(identifier)
            Divider()
                .frame(height: 24)
            Button(action: rename) {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: session.language.text("Rename the station", "車站更名")))
            .accessibilityIdentifier(identifier + ".edit")
        }
        .fixedSize()
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

}
