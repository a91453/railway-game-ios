import GameCore
import GamePresentation
import SwiftUI

/// What needs the player, as small bubbles over its stations
/// (ARCHITECTURE decision 109, ``GameWorld/mapAlerts()``): a crowded or
/// full station, a line with no train. A tap selects the station, or opens
/// the line panel at the line, where it can be staffed in one step
/// (decision 101). Shown while the player is looking at the map (the
/// Select tool), not while building, so they never cover what is being
/// built; a bubble goes when its cause does. Decision 510: one bubble
/// over a station however many alerts it has, a few on the map at once,
/// and the rest behind one badge that lists them.
struct MapAlertBubbles: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets
    /// Where the map's clear part starts under the top bar and its column
    /// (decision 477), for the tiles' prices; `insets.top` when `nil`.
    var clearTop: CGFloat?
    @Environment(GameScreenState.self) private var screen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the badge's list is open (decision 510).
    @State private var listOpen = false

    var body: some View {
        let arranged = Self.arranged(session: session, camera: camera, viewport: viewport, insets: insets, clearTop: clearTop)
        ZStack(alignment: .topLeading) {
            if session.tool == .select {
                ForEach(placed) { item in
                    // Its bottom middle at the point: the bubble stands on a
                    // frame of no size, placed there. Alignment guides
                    // placed the bubbles only against each other, and the
                    // stack, as large as the bubbles, sat in the map's top
                    // left corner with all of them in it.
                    bubble(item.bubble, more: item.more)
                        .fixedSize()
                        .frame(width: 0, height: 0, alignment: .bottom)
                        .position(item.point)
                        .transition(.pop(reduceMotion: reduceMotion))
                }
                // Decision 510: the alerts not on the map, behind one
                // badge in the map's top corner; not under a request's
                // card, which is there.
                if !arranged.folded.isEmpty, session.focusedRequest == nil {
                    folded(arranged.folded)
                        .padding(.leading, insets.leading + 8)
                        .padding(.top, insets.top + 8)
                        .transition(.pop(reduceMotion: reduceMotion))
                }
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: placed.map(\.id))
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: arranged.folded.isEmpty)
        .onChange(of: arranged.folded.isEmpty) { _, empty in
            if empty { listOpen = false }
        }
        .onChange(of: session.tool) { listOpen = false }
    }

    /// The badge, and its list while open: each alert's glyph and words,
    /// a tap going to it as its bubble would.
    private func folded(_ bubbles: [MapMarks.Bubble]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                listOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    MapGlyph.warning.image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                        .foregroundStyle(Theme.panel)
                        .frame(width: 20, height: 20)
                        .background(tint(bubbles[0].alert), in: Circle())
                        .accessibilityHidden(true)
                    Text(verbatim: "\(bubbles.count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: listOpen ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.leading, 4)
                .padding(.trailing, 8)
                .frame(minHeight: 28)
                .background(Theme.panel, in: Capsule())
                .overlay(Capsule().strokeBorder(tint(bubbles[0].alert), lineWidth: 1.5))
                .background(Capsule().fill(Color.black.opacity(0.18)).offset(y: 2))
                .contentShape(Capsule())
            }
            .buttonStyle(TouchTargetButtonStyle(size: CGSize(width: 44, height: 28)))
            .accessibilityLabel(Text(verbatim: MapClutter.badgeText(bubbles.count, in: session.language)))
            .accessibilityHint(Text(verbatim: listOpen
                ? session.language.text("Hides the list.", "收起清單。")
                : session.language.text("Lists what needs you.", "列出需要處理的事。")))
            .accessibilityIdentifier("map.alerts")
            if listOpen {
                // Five rows at most before it scrolls.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(bubbles, id: \.alert.id) { bubble in
                            row(bubble)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(width: 280, height: min(CGFloat(bubbles.count) * 44 + 8, 5 * 44 + 8))
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.textSecondary.opacity(0.4), lineWidth: 1))
                .transition(.pop(reduceMotion: reduceMotion))
            }
        }
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: listOpen)
    }

    /// One alert of the badge's list.
    private func row(_ bubble: MapMarks.Bubble) -> some View {
        let alert = bubble.alert
        let text = alert.text(in: session.language, lineName: bubble.lineName, subject: subject(of: bubble))
        return Button {
            listOpen = false
            go(to: alert)
        } label: {
            HStack(spacing: 6) {
                glyph(alert).image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(Theme.panel)
                    .frame(width: 18, height: 18)
                    .background(tint(alert), in: Circle())
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityHint(Text(verbatim: session.language.text("Goes to it.", "前往處理。")))
        .accessibilityIdentifier("map.alerts.row")
    }

    /// An alert on screen, and where its bubble's bottom middle goes.
    private struct PlacedAlert: Identifiable {
        let bubble: MapMarks.Bubble
        /// The alerts over its place it does not name (decision 510).
        let more: Int
        let point: CGPoint
        // Decision 184, later: the bubble's subject, not its figures.
        var id: MapAlert.ID { bubble.alert.id }
    }

    /// The alerts on the map: each over its station (or train, or sight),
    /// or, decision 477, beside it where that covers another station's
    /// name (``MapLabelPlacement/placeBubbles(_:stations:lift:radius:)``).
    private var placed: [PlacedAlert] {
        Self.placements(session: session, camera: camera, viewport: viewport, insets: insets, clearTop: clearTop).map {
            PlacedAlert(bubble: $0.bubble, more: $0.more, point: CGPoint(x: $0.point.x, y: $0.point.y))
        }
    }

    /// Decision 510: the alerts on screen, as a few bubbles on the map and
    /// the rest behind the badge (``MapClutter/arrange(_:markedSights:limit:)``).
    /// A sight's warning is not repeated over its own mark.
    static func arranged(session: GameSession, camera: PlanCamera, viewport: ScreenSize, insets: EdgeInsets,
                         clearTop: CGFloat? = nil)
        -> (onMap: [MapClutter.Group], folded: [MapMarks.Bubble]) {
        let inputs = PlacementInputs(session: session, camera: camera, viewport: viewport, insets: insets, clearTop: clearTop)
        if let memo = PlacementMemo.last, memo.inputs == inputs { return memo.arranged }
        let arranged = arranged(session: session, camera: camera, viewport: viewport, insets: insets, prices: inputs.prices)
        PlacementMemo.last = PlacementMemo(inputs: inputs, arranged: arranged)
        return arranged
    }

    private static func arranged(session: GameSession, camera: PlanCamera, viewport: ScreenSize, insets: EdgeInsets,
                                 prices: [MapLabelPlacement.Box]) -> (onMap: [MapClutter.Group], folded: [MapMarks.Bubble]) {
        // Decision 377: as the session keeps them, not read from the world,
        // so a tick that leaves them as they were rebuilds nothing here.
        let onScreen = session.mapBubbles.filter { bubble in
            let at = camera.screenPoint(of: bubble.alert.location)
            return at.x > Double(insets.leading) && at.x < viewport.width - Double(insets.trailing)
                && at.y > Double(insets.top) + 40 && at.y < viewport.height - Double(insets.bottom)
        }
        guard !onScreen.isEmpty else { return ([], []) }
        // L3-9 (#1583's review): the marks the map draws, not those over a
        // tile's price, so a sight whose mark is not drawn keeps its warning.
        let marked = Set(MapAttractionMarks.drawn(session: session, camera: camera, viewport: viewport, insets: insets, prices: prices)
            .map(\.sight.attraction.id))
        let level = MapProblems.level(referenceSize: camera.referenceSize)
        return MapClutter.arrange(onScreen, markedSights: marked, limit: MapClutter.bubbleLimit(level))
    }

    /// Where the badge takes a touch while it shows (closed), about: its
    /// glyph, count and chevron, touched over 44 high.
    static func badgeTouchBox(session: GameSession, camera: PlanCamera, viewport: ScreenSize, insets: EdgeInsets,
                              clearTop: CGFloat? = nil) -> MapLabelPlacement.Box? {
        guard session.tool == .select, session.focusedRequest == nil,
              !arranged(session: session, camera: camera, viewport: viewport, insets: insets, clearTop: clearTop).folded.isEmpty else { return nil }
        return MapLabelPlacement.Box(x: Double(insets.leading) + 8, y: Double(insets.top) + 8 - 8, width: 72, height: 44)
    }

    /// Where each bubble on screen goes (its bottom middle) and the box its
    /// touch takes. Decision 501: the selected station's tag keeps off them.
    static func placements(session: GameSession, camera: PlanCamera, viewport: ScreenSize, insets: EdgeInsets,
                           clearTop: CGFloat? = nil)
        -> [(bubble: MapMarks.Bubble, more: Int, point: ScreenPoint, touchBox: MapLabelPlacement.Box)] {
        guard session.tool == .select else { return [] }
        let groups = arranged(session: session, camera: camera, viewport: viewport, insets: insets, clearTop: clearTop).onMap
        // ``arranged`` just kept its memo for these inputs.
        if let placed = PlacementMemo.last?.placements { return placed }
        let placed = placements(groups, session: session, camera: camera)
        PlacementMemo.last?.placements = placed
        return placed
    }

    /// What ``arranged`` and ``placements`` are worked out from (L1-2,
    /// #1546's review): the bubbles, the selected station's tag and the
    /// sights' marks each ask for them, at every redraw, and placing them
    /// goes through every station on screen.
    private struct PlacementInputs: Equatable {
        let camera: PlanCamera
        let viewport: ScreenSize
        let insets: EdgeInsets
        let language: DisplayLanguage
        let tool: ConstructionTool
        let bubbles: [MapMarks.Bubble]
        let sights: [MapMarks.Sight]
        let stations: [MapLabelPlacement.Station]
        /// Where the tiles' prices are while the map is for sale: no sight
        /// mark is drawn over one (L3-9).
        let prices: [MapLabelPlacement.Box]

        @MainActor
        init(session: GameSession, camera: PlanCamera, viewport: ScreenSize, insets: EdgeInsets, clearTop: CGFloat?) {
            self.camera = camera
            self.viewport = viewport
            self.insets = insets
            language = session.language
            tool = session.tool
            bubbles = session.mapBubbles
            sights = session.mapSights
            stations = MapAlertBubbles.stationsOnScreen(session: session, camera: camera, viewport: camera.viewport)
            prices = MapAttractionMarks.tilePrices(session: session, camera: camera, viewport: viewport, insets: insets, clearTop: clearTop)
        }
    }

    /// The last ``arranged`` and ``placements``, for their inputs.
    @MainActor
    private struct PlacementMemo {
        static var last: PlacementMemo?

        let inputs: PlacementInputs
        let arranged: (onMap: [MapClutter.Group], folded: [MapMarks.Bubble])
        var placements: [(bubble: MapMarks.Bubble, more: Int, point: ScreenPoint, touchBox: MapLabelPlacement.Box)]?
    }

    private static func placements(_ groups: [MapClutter.Group], session: GameSession, camera: PlanCamera)
        -> [(bubble: MapMarks.Bubble, more: Int, point: ScreenPoint, touchBox: MapLabelPlacement.Box)] {
        guard !groups.isEmpty else { return [] }
        // Decision 210: over the waiting count's pill (and a crowded
        // station's ring) where the map draws them, not on it.
        let radius = MapArt.stationRadius(camera)
        let lift = MapProblems.level(referenceSize: camera.referenceSize) == .hidden ? 14 : radius + 30
        let shown = groups.map { (group: $0, at: camera.screenPoint(of: $0.top.alert.location)) }
        let plates = shown.map { item in
            MapLabelPlacement.Bubble(
                x: item.at.x, y: item.at.y,
                text: bubbleText(item.group.top, more: item.group.more, in: session.language),
                hasReason: item.group.top.waitReason != nil
            )
        }
        let points = MapLabelPlacement.placeBubbles(
            plates, stations: stationsOnScreen(session: session, camera: camera, viewport: camera.viewport), lift: lift, radius: radius
        )
        return zip(zip(shown, plates), points).map { item, point in
            (item.0.group.top, item.0.group.more, point, MapLabelPlacement.bubbleTouchBox(item.1, at: point))
        }
    }

    /// What a bubble says, with "+1" for the alerts over its place it
    /// does not name (decision 510).
    private static func bubbleText(_ bubble: MapMarks.Bubble, more: Int, in language: DisplayLanguage) -> String {
        let text = bubble.alert.text(in: language, lineName: bubble.lineName, subject: subject(of: bubble, in: language))
        return more > 0 ? "\(text) \(MapClutter.moreText(more))" : text
    }

    /// The stations whose names a bubble, or the selected station's tag
    /// (decision 501), could cover.
    static func stationsOnScreen(session: GameSession, camera: PlanCamera, viewport: ScreenSize) -> [MapLabelPlacement.Station] {
        session.world.stations.compactMap { station in
            let at = camera.screenPoint(of: station.location)
            guard at.x > -80, at.x < viewport.width + 80, at.y > -80, at.y < viewport.height + 80 else { return nil }
            return MapLabelPlacement.Station(x: at.x, y: at.y, name: station.name)
        }
    }

    /// Goes to what `alert` is about, from its bubble or the badge's list.
    private func go(to alert: MapAlert) {
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
        // Decision 477: at the freight group, where its materials are.
        case .materialsShort where alert.station != nil:
            screen.stationFocus = StationPanelGroup.answering(alert.kind)
            screen.panel = .station
        case .insolvency: screen.panel = .economy
        default: break
        }
    }

    private func bubble(_ bubble: MapMarks.Bubble, more: Int) -> some View {
        let alert = bubble.alert
        let text = Self.bubbleText(bubble, more: more, in: session.language)
        let why = bubble.waitReason?.text(in: session.language)
        return Button {
            go(to: alert)
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
        Self.subject(of: bubble, in: session.language)
    }

    private static func subject(of bubble: MapMarks.Bubble, in language: DisplayLanguage) -> String? {
        bubble.trainName ?? bubble.sight.map { language.text($0.englishName, $0.name) }
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
