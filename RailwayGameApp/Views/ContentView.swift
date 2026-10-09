import GameCore
import GamePresentation
import SwiftUI

/// The game screen (ARCHITECTURE decision 106): the map fills it, and
/// the controls float over its edges, so it is never pushed aside. The
/// status pill (cash, time, speed, menu) at the top leading corner, the
/// dock (the tools, the lines and the company's figures, Undo) at the
/// bottom leading corner, and the details card (the selection and the
/// tool's options) at the trailing side, only while there is something to
/// show; the lines, a station and the company's figures slide in at that
/// side too, rather than as sheets over the map. The same on every device:
/// a phone is held on its side (decision 106), an iPad either way.
struct ContentView: View {
    let session: GameSession
    /// Saves the game and goes back to the start screen (Stage C4).
    let launcher: GameLauncher
    @Environment(GameAudio.self) private var audio
    /// Lives above the layout: rebuilding it must not discard the camera.
    @State private var mapCamera: PlanCamera?
    /// The open panel and the map's layer settings, above the layout for
    /// the same reason: turning the device rebuilds every view under it.
    @State private var screen = GameScreenState()
    /// How far down the status pill reaches, with its margin.
    @State private var pillDepth: CGFloat = 0
    /// The dock's size, with its margin.
    @State private var dockSize = CGSize.zero
    /// How far down the details card reaches, with its margins.
    @State private var cardDepth = CGFloat.infinity
    /// The player's choice for the details card: open or folded, `nil` to
    /// follow what there is to show (``ControlDetails``).
    @State private var detailsChoice: Bool?

    var body: some View {
        gameLayout
            // Inside the text size limit below: the tutorial's card shares the
            // screen with the controls it must not cover.
            .tutorialOverlay(session: session)
            // The map and controls share one screen, so text stops growing at the
            // largest standard size instead of pushing the map off screen.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            // Presented from here, above the layout, so rebuilding it
            // neither closes the panel nor loses what is typed in it. The
            // panels shown beside the map are not presented (decision 106).
            .sheet(item: presentedPanel) { panel in
                panelSheet(panel)
            }
            .environment(screen)
            // Phase 7a: a year that closes while playing opens its year-end
            // report, at once if no panel is open, else once the panel closes.
            .onChange(of: session.yearEndYear) { _, year in
                if year != nil, screen.panel == nil {
                    screen.panel = .yearEnd
                }
            }
            // Decision 86: a scenario that ends while playing opens its goals,
            // as a closed year opens its report.
            .onChange(of: session.scenarioJustEnded) { _, ended in
                // Decision 87: a best result is kept as soon as it is made.
                if ended {
                    launcher.recordChallengeResult()
                }
                if ended, screen.panel == nil {
                    screen.panel = .goals
                }
            }
            .onChange(of: screen.panel) { old, new in
                // The report or the goals that were shown have been seen.
                if old == .yearEnd { session.dismissYearEnd() }
                if old == .goals { session.dismissScenarioEnd() }
                guard new == nil, pendingReport != nil else { return }
                // After the closing sheet has gone.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    if screen.panel == nil, let report = pendingReport {
                        screen.panel = report
                    }
                }
            }
            .onChange(of: ControlDetails.Subject(session)) { _, _ in
                detailsChoice = nil
            }
            .onChange(of: screen.detailsRequests) { _, _ in
                detailsChoice = true
            }
            .onChange(of: ObjectIdentifier(session)) { _, _ in
                mapCamera = nil
                detailsChoice = nil
                screen.stopPopTravelPlay()
                screen = GameScreenState()
            }
            .onDisappear {
                screen.stopPopTravelPlay()
            }
    }

    /// What a closing left to show: how the scenario ended first, then the
    /// year's report (decision 86, Phase 7a).
    private var pendingReport: GameScreenState.Panel? {
        if session.scenarioJustEnded { return .goals }
        if session.yearEndYear != nil { return .yearEnd }
        return nil
    }

    /// The open panel when it is one presented as a sheet; the panels
    /// beside the map are not (``GameScreenState/Panel/isBesideMap``).
    /// Turning to one of those drops the sheet without closing the panel.
    private var presentedPanel: Binding<GameScreenState.Panel?> {
        Binding {
            screen.panel.flatMap { $0.isBesideMap ? nil : $0 }
        } set: { panel in
            if panel != nil || screen.panel?.isBesideMap != true {
                screen.panel = panel
            }
        }
    }

    /// The panels beside the map (decision 106): the lines, a station and
    /// the company's figures. A phone on its side shows every sheet over
    /// the whole screen, so these, which the map is used with (picking a
    /// line's stations, choosing another station), slide in at the
    /// trailing side instead, and the map stays in sight and in reach.
    @ViewBuilder
    private func sidePanel(_ panel: GameScreenState.Panel) -> some View {
        switch panel {
        case .lines: LinesPanel(session: session)
        case .station: StationPanel(session: session)
        case .economy: EconomyPanel(session: session)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func panelSheet(_ panel: GameScreenState.Panel) -> some View {
        switch panel {
        case .lines, .station, .economy:
            // Shown beside the map instead (``sidePanel(_:)``).
            EmptyView()
        case .timetable:
            TimetableEditor(session: session)
                .presentationDetents([.medium, .large])
        case .fleet:
            FleetOverviewSheet(session: session)
        case .mapLayers:
            StoredMapLayerSheet()
        case .dataSources:
            DataSourcesView(launcher: launcher)
        case .settings:
            SettingsView(audio: audio)
        case .yearEnd:
            YearEndSheet(session: session)
                .presentationDetents([.medium, .large])
        case .goals:
            GoalsPanel(session: session)
                .presentationDetents([.medium, .large])
        }
    }

    /// The map with the controls floating over its edges (decision 106).
    /// Nothing floats over a real-world map's bottom strip, whose Apple
    /// logo and legal link nothing may cover (``AppleMapBackground``).
    private var gameLayout: some View {
        GeometryReader { proxy in
            let strip = RealWorldFrame(world: session.world) == nil ? 0 : AppleMapBackground.attributionHeight
            let margin = Self.margin
            let cardWidth = min(Self.cardWidth, (proxy.size.width * Self.cardMaxShare).rounded())
            let sidePanel = screen.panel.flatMap { $0.isBesideMap ? $0 : nil }
            let sideWidth = min(Self.sidePanelWidth, (proxy.size.width * Self.sidePanelMaxShare).rounded())
            // The details card gives way to a panel beside the map.
            let isOpen = sidePanel == nil && ControlDetails.isOpen(session, choice: detailsChoice)
            // The card runs down to the screen's bottom edge, or stops above
            // the dock where both would not fit side by side.
            let besideDock = dockSize.width + cardWidth + margin <= proxy.size.width
            let cardBottom = strip + (besideDock ? 0 : dockSize.height)
            let cardHeight = max(120, proxy.size.height - pillDepth - cardBottom - 2 * margin)
            map
                .environment(\.mapInsets, EdgeInsets(
                    top: pillDepth, leading: 0, bottom: dockSize.height,
                    trailing: sidePanel != nil ? sideWidth + margin : isOpen ? cardWidth + margin : 0
                ))
                // A panel beside the map runs down its whole side.
                .environment(\.mapTrailingInsetDepth, sidePanel != nil ? .infinity : isOpen ? cardDepth : 0)
                .environment(\.mapDetailsOpen, isOpen)
                .overlay(alignment: .topLeading) {
                    StatusPill(session: session, launcher: launcher)
                        .padding([.top, .leading, .trailing], margin)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pillDepth = $0 }
                }
                .overlay(alignment: .topTrailing) {
                    if isOpen {
                        DetailsCard(session: session, maxHeight: cardHeight)
                            .frame(width: cardWidth)
                            .padding(.top, pillDepth)
                            .padding([.top, .trailing], margin)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardDepth = $0 }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    ControlDock(session: session, isOpen: isOpen) {
                        detailsChoice = !isOpen
                    }
                    .padding([.leading, .bottom], margin)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { dockSize = $0 }
                    .padding(.bottom, strip)
                }
                .overlay(alignment: .trailing) {
                    if let sidePanel {
                        self.sidePanel(sidePanel)
                            .frame(width: sideWidth)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(Theme.panelBorder, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                            // Under the status pill, which it would cover
                            // on a phone.
                            .padding(.top, pillDepth)
                            .padding([.top, .trailing], margin)
                            .padding(.bottom, strip + margin)
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isOpen)
                .animation(.easeInOut(duration: 0.25), value: sidePanel)
        }
    }

    /// The details card's width, as the sidebar it replaces, and the most
    /// of the screen's width it takes on a phone.
    private static let cardWidth: CGFloat = 340
    private static let cardMaxShare: CGFloat = 0.4
    /// A panel beside the map's width, and the most of the screen's width
    /// it takes on a phone.
    private static let sidePanelWidth: CGFloat = 420
    private static let sidePanelMaxShare: CGFloat = 0.5
    private static let margin: CGFloat = 10

    private var map: some View {
        MapView(session: session, camera: $mapCamera)
            // A new game is a new map view: its cached track geometry
            // belongs to the world it was drawn from.
            .id(ObjectIdentifier(session))
            // The tutorial outlines, and keeps free, the part of the map that
            // shows: not what the pill, the dock or the card float over.
            .overlay {
                MapTutorialTarget()
            }
            // The status banner is at the top of the map view, above its
            // construction HUD and traffic key.
    }
}

/// The part of the map the screen's own controls do not float over
/// (``EnvironmentValues/mapInsets``), marked as the tutorial's map.
private struct MapTutorialTarget: View {
    @Environment(\.mapInsets) private var insets

    var body: some View {
        // The target inside the padding: marked outside it, it would be the
        // whole map, controls and all, and the tutorial's card would count
        // the map under the details card as free (decision 106).
        Color.clear
            .tutorialTarget(.map)
            .padding(insets)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// When the details card (``ControlPanel``'s details: the selection, the
/// tool's options and the action button) shows: by itself when there is
/// something to show (a tool other than Select, a selection) and not
/// otherwise, so the map gets the screen; or as the player chose, until
/// what it would show changes; and always during the tutorial, which
/// points at controls in it. A station selected while looking at the map
/// shows its tag over it instead (decision 119), which opens the card.
private enum ControlDetails {
    /// What the details would be about; a change drops the player's choice.
    struct Subject: Equatable {
        let tool: ConstructionTool
        let station: StationID?
        let train: TrainID?
        let hasSelection: Bool

        @MainActor
        init(_ session: GameSession) {
            tool = session.tool
            station = session.selectedStationID
            train = session.tappedTrainID
            hasSelection = session.selectionText() != nil
        }
    }

    /// `choice` is the player's: open or folded, `nil` to follow what
    /// there is to show.
    @MainActor
    static func isOpen(_ session: GameSession, choice: Bool?) -> Bool {
        if session.tutorial != nil { return true }
        if let choice { return choice }
        if session.tool != .select { return true }
        // Decision 119: a station's tag stands in for the card.
        return session.selectedStationID == nil && session.selectionText() != nil
    }
}

/// Shows or hides the details card, from the dock. Hidden during the
/// tutorial, when the card stays open.
private struct ControlDetailsToggle: View {
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOpen ? "sidebar.trailing" : "info.circle")
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: isOpen))
        .accessibilityLabel(isOpen ? "Hide Controls" : "Show Controls")
        .accessibilityIdentifier("controls.toggle")
    }
}

/// Cash, time, speed and the game menu (``HUDView``) in one glass pill at
/// the top of the screen (decision 106), as wide as what it shows.
private struct StatusPill: View {
    let session: GameSession
    let launcher: GameLauncher

    var body: some View {
        HUDView(session: session, launcher: launcher)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .glassBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// The tools, the lines and the company's figures, and Undo
/// (``ControlPanel``'s tools), in a glass dock at the bottom of the screen
/// (decision 106), with the button that shows or hides the details card.
private struct ControlDock: View {
    let session: GameSession
    let isOpen: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ControlPanel(session: session, arrangement: .tools)
            if session.tutorial == nil {
                ControlDetailsToggle(isOpen: isOpen, action: toggle)
            }
        }
        .fixedSize()
        .padding(8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// The selection and the active tool's options (``ControlPanel``'s
/// details) in a glass card at the trailing side (decision 106): a
/// station's nameboard and its lines (decision 112) over them when one is
/// selected, and on an iPad, which has the room, the network's overview
/// under them. As tall as what it shows, up to `maxHeight`, then it
/// scrolls. It floats over the map, so its height changing as the game
/// runs moves nothing else.
private struct DetailsCard: View {
    let session: GameSession
    let maxHeight: CGFloat
    /// Regular height: an iPad, not a phone.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if session.tool == .select, let station = session.selectedStation {
                    VStack(alignment: .leading, spacing: 8) {
                        StationNameboard(name: station.name)
                        StationLineChips(session: session, station: station)
                    }
                }
                ControlPanel(session: session, arrangement: .details)
                if verticalSizeClass == .regular {
                    Divider()
                    NetworkOverview(session: session)
                }
            }
            .padding(14)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .tutorialClip()
        .frame(height: min(max(contentHeight, 1), maxHeight))
        .glassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// What the game screen shows besides the world: the panel that is open and
/// the population and travel layer's opacity, hour and playback. View state
/// only, never game state; it lives above the layout (``ContentView``), so
/// turning the device closes no panel and resets no layer setting.
@MainActor
@Observable
final class GameScreenState {
    /// The sheets the game screen presents, one at a time.
    enum Panel: String, Identifiable {
        // Settings is a panel too, presented above both layouts: a sheet of
        // the HUD's own would close when turning the device rebuilt the HUD
        // (from the code; not checked on a device). Opening it with Lines
        // open was thought to fail too, but the iOS 26.5 Simulator shows
        // either way (run 37730023961).
        case lines, economy, station, timetable, fleet, mapLayers, dataSources, settings
        /// A closed year's report (Phase 7a), opened by the year's closing.
        case yearEnd
        /// The scenario's goals (decision 86), opened also when it ends.
        case goals

        var id: Self { self }

        /// Shown beside the map rather than presented over it (decision
        /// 106, ``ContentView``): the panels the map is used with.
        var isBesideMap: Bool {
            switch self {
            case .lines, .station, .economy: true
            case .timetable, .fleet, .mapLayers, .dataSources, .settings, .yearEnd, .goals: false
            }
        }
    }

    var panel: Panel?
    /// Counts the requests to open the details card from the map (the
    /// station's tag, decision 119); the screen opens it on each.
    var detailsRequests = 0
    /// The layer's opacity once the player has moved its slider (the
    /// reference's `_popTravelOpacityUserSet`); until then each layer's own
    /// (``PopTravel/baseOpacity(for:compactWidth:)``).
    var popTravelOpacity: Double?
    /// The timeline's hour, and whether it plays (the reference's
    /// `G.popTravelHour` and `G.popTravelPlaying`).
    var popTravelHour = PopTravel.defaultHour
    private(set) var isPlayingPopTravel = false
    @ObservationIgnored private var popTravelPlay: Task<Void, Never>?

    /// Play: the next hour every 1.2 s, back to 0 after 23
    /// (`startPopTravelPlay`).
    func startPopTravelPlay() {
        guard popTravelPlay == nil else { return }
        isPlayingPopTravel = true
        popTravelPlay = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: PopTravel.playInterval)
                guard !Task.isCancelled, let self else { return }
                self.popTravelHour = PopTravel.nextHour(after: self.popTravelHour)
            }
        }
    }

    func stopPopTravelPlay() {
        popTravelPlay?.cancel()
        popTravelPlay = nil
        isPlayingPopTravel = false
    }
}
