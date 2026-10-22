import GameCore
import GamePresentation
import SwiftUI

/// The city's requests on the map (ARCHITECTURE decision 246): a flag where
/// each request in hand points, and for the one "Show on map" pointed out a
/// ring (a new station's 800 m) and a card at the top saying what it asks,
/// how far it has come and the days left. A flag tapped points its request
/// out; the card's list button opens the requests, its ✕ takes the ring
/// away. Everything shown is read from the session.
struct MapRequestMarks: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        let marks = session.cityRequestMarks
        ZStack(alignment: .topLeading) {
            ForEach(marks) { mark in
                let at = camera.screenPoint(of: mark.location)
                if mark.isFocused, let radius = mark.radius {
                    let size = Double(radius) * camera.pointsPerUnit * 2
                    Circle()
                        .fill(Theme.primary.opacity(0.10))
                        .overlay(Circle().strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                        .frame(width: size, height: size)
                        .position(x: at.x, y: at.y)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if at.x > Double(insets.leading), at.x < viewport.width - Double(insets.trailing),
                   at.y > Double(insets.top) + 40, at.y < viewport.height - Double(insets.bottom) {
                    flag(mark)
                        .fixedSize()
                        .frame(width: 0, height: 0, alignment: .center)
                        .position(x: at.x, y: at.y)
                }
            }
            if let request = session.focusedRequest {
                card(request)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 16)
                    .frame(width: viewport.width)
                    .offset(y: Double(insets.top) + 8)
            }
        }
        // Not on this view, which covers the whole map: hidden from
        // VoiceOver it would hide the map from UI tests' taps.
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
    }

    private func flag(_ mark: CityRequestMark) -> some View {
        let size: Double = mark.isFocused ? 40 : 30
        return Button {
            session.showRequestOnMap(mark.id)
        } label: {
            MapGlyph.request.image
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.5, height: size * 0.5)
                .foregroundStyle(mark.isFocused ? Theme.onPrimary : Theme.primary)
                .frame(width: size, height: size)
                .background(mark.isFocused ? Theme.primary : Theme.panel, in: Circle())
                .overlay(Circle().strokeBorder(Theme.primary, lineWidth: 2))
                .frame(minWidth: 44, minHeight: 44)
                // The whole finger's square, not the circle, as the locks
                // (#1040): on an iPad a tap on the circle's middle row fell
                // through to the map (MapMarkTapUITests, run 39841822269).
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("City request", "委託案")))
        .accessibilityIdentifier(mark.isFocused ? "map.request.focus" : "map.request.\(mark.id)")
    }

    private func card(_ request: CityRequestRow) -> some View {
        let language = session.language
        return HStack(alignment: .top, spacing: 10) {
            MapGlyph.request.image
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.primary)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: request.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if request.isActive {
                    ProgressView(value: Double(request.progress) / 1_000)
                        .tint(Theme.primary)
                }
                Text(verbatim: request.progressText + " · " + request.daysLeftText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                screen.panel = .goals
            } label: {
                Image(systemName: "list.bullet")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(verbatim: language.text("All requests", "全部委託")))
            .accessibilityIdentifier("map.request.card.list")
            Button {
                session.clearRequestFocus()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text(verbatim: language.text("Close", "關閉")))
            .accessibilityIdentifier("map.request.card.close")
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .glassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.request.card")
    }
}
