import GameCore
import GamePresentation
import SwiftUI

/// What needs the player, as small bubbles over its stations
/// (ARCHITECTURE decision 109, ``GameWorld/mapAlerts()``): a crowded or
/// full station, a line with no train. A tap selects the station, or opens
/// the line panel at the line, where it can be staffed in one step
/// (decision 101). Shown while the player is looking at the map (the
/// Select tool), not while building, so they never cover what is being
/// built; a bubble goes when its cause does.
struct MapAlertBubbles: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        ZStack(alignment: .topLeading) {
            if session.tool == .select {
                ForEach(placed) { item in
                    bubble(item.alert)
                        .fixedSize()
                        .alignmentGuide(HorizontalAlignment.leading) { $0[HorizontalAlignment.center] - item.point.x }
                        .alignmentGuide(VerticalAlignment.top) { $0[VerticalAlignment.bottom] - item.point.y }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .animation(.spring(duration: 0.3, bounce: 0.4), value: placed.map(\.alert))
    }

    /// An alert on screen, and where its bubble's bottom middle goes.
    private struct PlacedAlert: Identifiable {
        let alert: MapAlert
        let point: CGPoint
        var id: MapAlert { alert }
    }

    /// The alerts on screen: each over its station, the second at a
    /// station over the first.
    private var placed: [PlacedAlert] {
        var perStation: [StationID: Int] = [:]
        return session.world.mapAlerts().compactMap { alert in
            let at = camera.screenPoint(of: alert.location)
            guard at.x > Double(insets.leading), at.x < viewport.width - Double(insets.trailing),
                  at.y > Double(insets.top) + 40, at.y < viewport.height - Double(insets.bottom)
            else { return nil }
            let index = perStation[alert.station, default: 0]
            perStation[alert.station] = index + 1
            return PlacedAlert(alert: alert, point: CGPoint(x: at.x, y: at.y - 14 - Double(index) * 34))
        }
    }

    private func bubble(_ alert: MapAlert) -> some View {
        let text = alert.text(in: session.language, lineName: lineName(of: alert))
        return Button {
            if session.respond(to: alert) {
                screen.panel = .lines
            }
        } label: {
            HStack(spacing: 4) {
                // Decision 121: the map's glyph on a disc of the alert's
                // colour, as the app icon's chips (5.5:1 or more).
                glyph(alert).image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(Theme.panel)
                    .frame(width: 20, height: 20)
                    .background(tint(alert), in: Circle())
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(minHeight: 28)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(tint(alert), lineWidth: 1.5))
            // The website's tactile edge, as the station nameboard has.
            .background(Capsule().fill(Color.black.opacity(0.18)).offset(y: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityHint(Text(verbatim: session.language.text("Goes to it.", "前往處理。")))
        .accessibilityIdentifier("map.alert")
    }

    private func lineName(of alert: MapAlert) -> String? {
        guard case .lineWithoutTrains(let id) = alert.kind else { return nil }
        return session.world.line(id: id)?.name
    }

    private func glyph(_ alert: MapAlert) -> MapGlyph {
        switch alert.kind {
        case .crowded: .crowd
        case .full: .full
        case .lineWithoutTrains: .train
        }
    }

    private func tint(_ alert: MapAlert) -> Color {
        switch alert.kind {
        case .crowded: Theme.warning
        case .full: Theme.error
        case .lineWithoutTrains: Theme.primary
        }
    }
}
