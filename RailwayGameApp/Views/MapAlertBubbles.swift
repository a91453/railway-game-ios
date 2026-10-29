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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if session.tool == .select {
                ForEach(placed) { item in
                    // Its bottom middle at the point: the bubble stands on a
                    // frame of no size, placed there. Alignment guides
                    // placed the bubbles only against each other, and the
                    // stack, as large as the bubbles, sat in the map's top
                    // left corner with all of them in it.
                    bubble(item.bubble)
                        .fixedSize()
                        .frame(width: 0, height: 0, alignment: .bottom)
                        .position(item.point)
                        .transition(.pop(reduceMotion: reduceMotion))
                }
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: placed.map(\.id))
    }

    /// An alert on screen, and where its bubble's bottom middle goes.
    private struct PlacedAlert: Identifiable {
        let bubble: MapMarks.Bubble
        let point: CGPoint
        // Decision 184, later: the bubble's subject, not its figures.
        var id: MapAlert.ID { bubble.alert.id }
    }

    /// The alerts on screen: each over its station (or train, or sight),
    /// or, decision 477, beside it where that covers another station's
    /// name (``MapLabelPlacement/placeBubbles(_:stations:lift:radius:)``).
    private var placed: [PlacedAlert] {
        guard session.tool == .select else { return [] }
        // Decision 210: over the waiting count's pill (and a crowded
        // station's ring) where the map draws them, not on it.
        let radius = MapArt.stationRadius(camera)
        let lift = MapProblems.level(referenceSize: camera.referenceSize) == .hidden ? 14 : radius + 30
        // Decision 377: as the session keeps them, not read from the world,
        // so a tick that leaves them as they were rebuilds nothing here.
        let shown: [(bubble: MapMarks.Bubble, at: ScreenPoint)] = session.mapBubbles.compactMap { bubble in
            let at = camera.screenPoint(of: bubble.alert.location)
            guard at.x > Double(insets.leading), at.x < viewport.width - Double(insets.trailing),
                  at.y > Double(insets.top) + 40, at.y < viewport.height - Double(insets.bottom)
            else { return nil }
            return (bubble, at)
        }
        guard !shown.isEmpty else { return [] }
        let points = MapLabelPlacement.placeBubbles(
            shown.map { item in
                MapLabelPlacement.Bubble(
                    x: item.at.x, y: item.at.y,
                    text: item.bubble.alert.text(in: session.language, lineName: item.bubble.lineName, subject: subject(of: item.bubble)),
                    hasReason: item.bubble.waitReason != nil
                )
            },
            stations: stationsOnScreen, lift: lift, radius: radius
        )
        return zip(shown, points).map { PlacedAlert(bubble: $0.bubble, point: CGPoint(x: $1.x, y: $1.y)) }
    }

    /// The stations whose names a bubble could cover.
    private var stationsOnScreen: [MapLabelPlacement.Station] {
        session.world.stations.compactMap { station in
            let at = camera.screenPoint(of: station.location)
            guard at.x > -80, at.x < viewport.width + 80, at.y > -80, at.y < viewport.height + 80 else { return nil }
            return MapLabelPlacement.Station(x: at.x, y: at.y, name: station.name)
        }
    }

    private func bubble(_ bubble: MapMarks.Bubble) -> some View {
        let alert = bubble.alert
        let text = alert.text(in: session.language, lineName: bubble.lineName, subject: subject(of: bubble))
        let why = bubble.waitReason?.text(in: session.language)
        return Button {
            if session.respond(to: alert) {
                screen.panel = .lines
            }
            // Decision 184: a sight opens the sights, a challenge in the
            // red the company's figures. A town short of materials opens
            // its station's panel, whose Freight section builds the yard.
            switch alert.kind {
            case .sightWithoutStation(let sight):
                // Decision 250: at that sight's row.
                screen.sightFocus = sight
                screen.panel = .tourism
            case .materialsShort where alert.station != nil: screen.panel = .station
            case .insolvency: screen.panel = .economy
            default: break
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
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: text)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    // Decision 210: and why, as the reference's land
                    // value gives its figure and its reasons.
                    if let why {
                        Text(verbatim: why)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
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
        // 28 high, touched over 44: bubbles over one station are 46
        // apart, so two areas never meet.
        .buttonStyle(TouchTargetButtonStyle(size: CGSize(width: 44, height: 28)))
        .accessibilityLabel(Text(verbatim: why.map { "\(text), \($0)" } ?? text))
        .accessibilityHint(Text(verbatim: session.language.text("Goes to it.", "前往處理。")))
        .accessibilityIdentifier("map.alert")
    }

    /// The train's or the sight's name (decision 184).
    private func subject(of bubble: MapMarks.Bubble) -> String? {
        bubble.trainName ?? bubble.sight.map { session.language.text($0.englishName, $0.name) }
    }

    private func glyph(_ alert: MapAlert) -> MapGlyph {
        switch alert.kind {
        case .crowded: .crowd
        case .full: .full
        case .lineWithoutTrains: .train
        // Decision 179: the warning sign, for a line in the red.
        case .lineLosingMoney: .warning
        // Decision 158: a building, for the town that could not build.
        case .materialsShort: .office
        // Decision 184.
        case .trainStuck: .train
        case .sightWithoutStation: .star
        case .insolvency: .warningSolid
        }
    }

    private func tint(_ alert: MapAlert) -> Color {
        switch alert.kind {
        case .crowded: Theme.warning
        case .full: Theme.error
        case .lineWithoutTrains: Theme.primary
        case .lineLosingMoney: Theme.error
        case .materialsShort: Theme.warning
        case .trainStuck: Theme.error
        case .sightWithoutStation: Theme.primary
        case .insolvency: Theme.error
        }
    }
}
