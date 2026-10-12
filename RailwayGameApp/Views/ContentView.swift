import GameCore
import GamePresentation
import SwiftUI

/// The game screen (ARCHITECTURE decision 106): the map fills it, and
/// the controls float over its edges, so it is never pushed aside. The
/// status pill (cash, time, speed, menu) at the top leading corner, the
/// dock (Build, the lines and the company's figures, Undo) at the bottom
/// leading corner, the tools down the leading edge while building
/// (decision 114), and the details card (the selection and the
/// tool's options) at the trailing side, only while there is something to
/// show; the lines, a station and the company's figures slide in at that
/// side too, rather than as sheets over the map. The same on every device:
/// a phone is held on its side (decision 106), an iPad either way.
struct ContentView: View {
    let session: GameSession
    /// Saves the game and goes back to the start screen (Stage C4).
    let launcher: GameLauncher
    @Environment(GameAudio.self) private var audio
    /// Decision 175: the secretary room's settings, kept on the device.
    @AppStorage(SecretarySettings.pauseKey) private var pausesForImportantEvents = true
    @AppStorage(SecretarySettings.monthlyKey) private var monthlyReportMode = MonthlyReportMode.openAndPause.rawValue
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
    /// Compact height: a phone, held on its side.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        gameLayout
            // Inside the text size limit below: the tutorial's card shares the
            // screen with the controls it must not cover.
            .tutorialOverlay(session: session, panelTargets: screen.tutorialPanelTargets, mapSites: screen.tutorialMapSites)
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
            .onAppear(perform: syncSecretarySettings)
            .onChange(of: pausesForImportantEvents) { _, _ in syncSecretarySettings() }
            .onChange(of: monthlyReportMode) { _, _ in syncSecretarySettings() }
            // Decision 175: a month that closes opens its report.
            .onChange(of: session.monthEndReport) { _, report in
                if report != nil, screen.panel == nil {
                    screen.panel = .monthEnd
                }
            }
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
                if old == .monthEnd { session.dismissMonthEnd() }
                guard new == nil, pendingReport != nil else { return }
                // After the closing sheet has gone.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    if screen.panel == nil, let report = pendingReport {
                        screen.panel = report
                    }
                }
            }
            // Decision 188: the panel a tutorial step needs opens for it (the
            // reference's `openUI`), and one beside the map closes for a step
            // about the map's own controls.
            .onChange(of: session.tutorial?.index, initial: true) { _, _ in
                switch session.tutorial?.step.panel {
                case .lines:
                    if screen.panel != .lines { screen.panel = .lines }
                case .closed:
                    if screen.panel?.isBesideMap == true { screen.panel = nil }
                case nil:
                    break
                }
            }
            .onChange(of: ControlDetails.Subject(session, foldsWhileDrawing: verticalSizeClass == .compact)) { _, _ in
                detailsChoice = nil
            }
            .onChange(of: screen.detailsRequests) { _, _ in
                detailsChoice = true
            }
            .onChange(of: ObjectIdentifier(session)) { _, _ in
                syncSecretarySettings()
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
        if session.monthEndReport != nil { return .monthEnd }
        return nil
    }

    /// Hands the device's secretary settings to the session.
    private func syncSecretarySettings() {
        session.pausesForImportantEvents = pausesForImportantEvents
        session.monthlyReportMode = MonthlyReportMode(rawValue: monthlyReportMode) ?? .openAndPause
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
            // Decision 127: a problem report from a game says what is in it.
            SettingsView(audio: audio, game: session.problemReportGame, session: session)
        case .yearEnd:
            YearEndSheet(session: session)
                .presentationDetents([.medium, .large])
        case .goals:
            GoalsPanel(session: session, achievements: launcher.achievements)
                .presentationDetents([.medium, .large])
        case .tourism:
            TourismPanel(session: session)
                .presentationDetents([.medium, .large])
        case .news:
            NewsLogView(session: session)
                .presentationDetents([.medium, .large])
        case .monthEnd:
            MonthlyReportSheet(session: session)
                .presentationDetents([.medium, .large])
        case .help:
            HelpView(language: session.language)
        }
    }

    /// The map with the controls floating over its edges (decision 106),
    /// the map to the screen's edges and the controls inside the safe area
    /// (decision 120). Nothing floats over a real-world map's bottom strip,
    /// whose Apple logo and legal link nothing may cover
    /// (``AppleMapBackground``).
    private var gameLayout: some View {
        GeometryReader { proxy in
            let strip = RealWorldFrame(world: session.world) == nil ? 0 : AppleMapBackground.attributionHeight
            let margin = Self.margin
            let cardWidth = min(Self.cardWidth, (proxy.size.width * Self.cardMaxShare).rounded())
            let sidePanel = screen.panel.flatMap { $0.isBesideMap ? $0 : nil }
            let sideWidth = min(Self.sidePanelWidth, (proxy.size.width * Self.sidePanelMaxShare).rounded())
            // The details card gives way to a panel beside the map.
            let isOpen = sidePanel == nil && ControlDetails.isOpen(
                session, choice: detailsChoice, foldsWhileDrawing: verticalSizeClass == .compact
            )
            // The card runs down to the screen's bottom edge, or stops above
            // the dock where both would not fit side by side.
            let besideDock = dockSize.width + cardWidth + margin <= proxy.size.width
            let cardBottom = strip + (besideDock ? 0 : dockSize.height)
            let cardHeight = max(120, proxy.size.height - pillDepth - cardBottom - 2 * margin)
            // Decision 114: the tools down the leading edge while building,
            // between the pill and the dock.
            let showsRail = BuildToolRail.isShown(session)
            let railHeight = max(60, proxy.size.height - pillDepth - strip - dockSize.height - 2 * margin)
            // Decision 120: the map runs to the screen's edges, under the
            // camera housing and the home indicator, as Apple's Maps does;
            // the controls stay inside the safe area.
            Color.clear
                .background {
                    map
                        .environment(\.mapInsets, EdgeInsets(
                            top: pillDepth, leading: showsRail ? BuildToolRail.width + margin : 0, bottom: dockSize.height,
                            trailing: sidePanel != nil ? sideWidth + margin : isOpen ? cardWidth + margin : 0
                        ))
                        // A panel beside the map runs down its whole side.
                        .environment(\.mapTrailingInsetDepth, sidePanel != nil ? .infinity : isOpen ? cardDepth : 0)
                        .environment(\.mapDetailsOpen, isOpen)
                        .environment(\.mapSafeArea, proxy.safeAreaInsets)
                        .ignoresSafeArea(.container)
                }
                .overlay(alignment: .topLeading) {
                    StatusPill(session: session, launcher: launcher)
                        .padding([.top, .leading, .trailing], margin)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pillDepth = $0 }
                }
                .overlay(alignment: .topTrailing) {
                    if isOpen {
                        DetailsCard(session: session, maxHeight: cardHeight)
                            .frame(width: cardWidth)
                            // The tutorial's card keeps clear of it.
                            .tutorialTarget(.detailsCard)
                            .padding(.top, pillDepth)
                            .padding([.top, .trailing], margin)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardDepth = $0 }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if showsRail {
                        BuildToolRail(session: session, maxHeight: railHeight)
                            .padding(.top, pillDepth)
                            .padding([.top, .leading], margin)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    // The card gives way to a panel beside the map: while
                    // one is open the toggle could only set what shows after
                    // it closes, with nothing to see now.
                    ControlDock(session: session, isOpen: isOpen, canToggle: sidePanel == nil) {
                        detailsChoice = !isOpen
                    }
                    .padding([.leading, .bottom], margin)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { dockSize = $0 }
                    .padding(.bottom, strip)
                }
                // Decision 118: the station master beside the dock, not in
                // the tutorial, whose card has the station master. Only once
                // the dock is measured: before, it would stand on the Build
                // button and then slide across the dock to its place.
                .overlay(alignment: .bottomLeading) {
                    // Short of the map's bottom-trailing column too
                    // (#366): beside a phone's dock the bubble reached
                    // the zoom buttons, and a tap there only closed it.
                    let corner = screen.mapCornerFrame.isEmpty ? 0 : proxy.frame(in: .global).maxX - screen.mapCornerFrame.minX
                    let trailing = max(sidePanel != nil ? sideWidth + margin : isOpen && besideDock ? cardWidth + margin : 0, corner)
                    // Nothing where a panel beside the map would cover it:
                    // on a landscape phone the panel's edge (x 365 of 750)
                    // lies over the station master beside the dock (x
                    // 350-394), leaving a sliver to tap. Kept, not removed,
                    // so it remembers what it has said.
                    let isCovered = dockSize.width + margin + StationMasterCorner.avatarSize + margin > proxy.size.width - trailing
                    if session.tutorial == nil, dockSize != .zero {
                        StationMasterCorner(
                            session: session,
                            maxBubbleWidth: proxy.size.width - dockSize.width - trailing - 3 * margin - 52,
                            isCovered: isCovered
                        )
                        .padding(.leading, dockSize.width + margin)
                        .padding(.bottom, strip + margin)
                    }
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
                            // The tutorial's card keeps clear of it.
                            .tutorialTarget(.sidePanel)
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
                .animation(.easeInOut(duration: 0.2), value: showsRail)
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
                MapTutorialTarget(
                    attributionHeight: RealWorldFrame(world: session.world) == nil ? 0 : AppleMapBackground.attributionHeight
                )
            }
            // The status banner is at the top of the map view, above its
            // construction HUD and traffic key.
    }
}

/// The part of the map the screen's own controls do not float over
/// (``EnvironmentValues/mapInsets``), nor the screen's edges hide
/// (``EnvironmentValues/mapSafeArea``), nor a real-world map's credits
/// take (`attributionHeight`, the strip the dock stands on), marked as the
/// tutorial's map.
private struct MapTutorialTarget: View {
    /// The real-world map's strip along the bottom
    /// (``AppleMapBackground/attributionHeight``), 0 on a blank map: the map
    /// view leaves it clear too. Without it the outline reached into the
    /// dock's Lines and Data buttons (TestFlight 54.1).
    let attributionHeight: CGFloat
    @Environment(\.mapInsets) private var insets
    @Environment(\.mapSafeArea) private var safeArea

    var body: some View {
        // The target inside the padding: marked outside it, it would be the
        // whole map, controls and all, and the tutorial's card would count
        // the map under the details card as free (decision 106).
        Color.clear
            .tutorialTarget(.map)
            .padding(insets.adding(safeArea).adding(EdgeInsets(top: 0, leading: 0, bottom: attributionHeight, trailing: 0)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// When the details card (``ControlPanel``'s details: the selection, the
/// tool's options and the action button) shows: by itself when there is
/// something to show (a tool other than Select, a selection) and not
/// otherwise, so the map gets the screen; or as the player chose, until
/// what it would show changes. During the tutorial (decision 188), which
/// has no toggle, when its step points into it, or for a selection, and
/// else as for a tool, so a phone's map steps keep the whole map. A
/// station selected while looking at the map shows its tag over it
/// instead (decision 119), which opens the card.
/// On a phone, track being drawn folds it (decision 136): the map's
/// construction HUD and the ✕ and ✓ beside the track say and do what it
/// would, and the map gets the room to draw in.
private enum ControlDetails {
    /// What the details would be about; a change drops the player's choice.
    struct Subject: Equatable {
        let tool: ConstructionTool
        let station: StationID?
        let train: TrainID?
        let hasSelection: Bool
        /// Starting to draw, and clearing what was drawn, drop it too,
        /// where drawing folds the card: on an iPad, which does not fold
        /// it, a card the player folded stays folded (decision 136).
        let drawsTrack: Bool

        @MainActor
        init(_ session: GameSession, foldsWhileDrawing: Bool) {
            tool = session.tool
            station = session.selectedStationID
            train = session.tappedTrainID
            hasSelection = session.selectionText() != nil
            drawsTrack = foldsWhileDrawing && ControlDetails.drawsTrack(session)
        }
    }

    /// Whether track is being drawn: the network tool building, from a
    /// start already picked (and, once a stretch is built, its end, which
    /// starts the next).
    @MainActor
    static func drawsTrack(_ session: GameSession) -> Bool {
        session.tool == .network && session.networkMode == .build && session.networkStart != nil
    }

    /// `choice` is the player's: open or folded, `nil` to follow what
    /// there is to show. `foldsWhileDrawing` on a phone, which has no room
    /// beside the card to draw in (decision 136).
    @MainActor
    static func isOpen(_ session: GameSession, choice: Bool?, foldsWhileDrawing: Bool) -> Bool {
        if let step = session.tutorial?.step {
            if step.usesDetailsCard { return true }
            // The station's tag is hidden in the tutorial.
            if session.tool == .select { return session.selectionText() != nil }
            return !foldsWhileDrawing
        }
        if let choice { return choice }
        if session.tool != .select { return !(foldsWhileDrawing && drawsTrack(session)) }
        // Decision 119: a station's tag stands in for the card.
        return session.selectedStationID == nil && session.selectionText() != nil
    }
}

/// Shows or hides the details card, from the dock. Hidden during the
/// tutorial, whose steps open the card when they need it.
private struct ControlDetailsToggle: View {
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The card's own shape, open or not: the map's ⓘ is MapLibre's
            // attribution, a different thing (decision 123).
            Image(systemName: "sidebar.trailing")
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

/// Build, the lines and the company's figures, and Undo
/// (``ControlPanel``'s tools), in a glass dock at the bottom of the screen
/// (decision 106), with the button that shows or hides the details card.
private struct ControlDock: View {
    let session: GameSession
    let isOpen: Bool
    var canToggle = true
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ControlPanel(session: session, arrangement: .tools)
            if session.tutorial == nil {
                ControlDetailsToggle(isOpen: isOpen, action: toggle)
                    .disabled(!canToggle)
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
/// under them. As tall as what it shows, up to `maxHeight`; then only the
/// options in its middle scroll, between the inspector at its head and the
/// action button at its foot, which stay put: with the whole card
/// scrolling, reaching the button took the status away (TestFlight 54.1).
/// Where those two leave the middle too little room, the whole card
/// scrolls as before. It floats over the map, so its height changing as
/// the game runs moves nothing else.
private struct DetailsCard: View {
    let session: GameSession
    let maxHeight: CGFloat
    /// Regular height: an iPad, not a phone.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var headHeight: CGFloat = 0
    @State private var middleHeight: CGFloat = 0
    @State private var footHeight: CGFloat = 0

    /// The card's inner margin, and the gap between its parts.
    private static let padding: CGFloat = 14
    private static let spacing: CGFloat = 12
    /// The least the middle keeps of its own while the head and foot stay
    /// put: about two rows of options.
    private static let leastMiddle: CGFloat = 88
    /// How far the middle fades into the head and foot when it scrolls.
    private static let fade: CGFloat = 8

    private var hasHead: Bool {
        selectedStation != nil || ControlPanel.showsInspector(session)
    }

    private var hasFoot: Bool {
        ControlPanel.showsAction(session)
    }

    private var selectedStation: Station? {
        session.tool == .select ? session.selectedStation : nil
    }

    /// The heights of the parts the card shows: a part it stopped showing
    /// keeps the last height it reported.
    private var ends: CGFloat {
        (hasHead ? headHeight : 0) + (hasFoot ? footHeight : 0)
    }

    /// Whether the head and foot stay put, the middle scrolling between.
    private var pinsEnds: Bool {
        ends + Self.leastMiddle <= maxHeight
    }

    var body: some View {
        Group {
            if pinsEnds {
                VStack(spacing: 0) {
                    if hasHead { head }
                    ScrollView {
                        middle
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicatorsFlash(onAppear: true)
                    .scrollIndicatorsFlash(trigger: session.tool)
                    .mask {
                        // Scrolled options fade into the head and foot
                        // instead of being cut off at a hard edge.
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                .frame(height: hasHead ? Self.fade : 0)
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: hasFoot ? Self.fade : 0)
                        }
                    }
                    .tutorialClip()
                    if hasFoot { foot }
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if hasHead { head }
                        middle
                        if hasFoot { foot }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicatorsFlash(onAppear: true)
                .tutorialClip()
            }
        }
        .frame(height: min(max(ends + middleHeight, 1), maxHeight), alignment: .top)
        .glassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("details.card")
    }

    /// The selection, or what the network tool's taps picked.
    private var head: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            if let station = selectedStation {
                VStack(alignment: .leading, spacing: 8) {
                    StationNameboard(name: station.name)
                    StationLineChips(session: session, station: station)
                }
            }
            ControlPanel(session: session, arrangement: .inspector)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.top, .horizontal], Self.padding)
        .padding(.bottom, Self.spacing - Self.fade)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headHeight = $0 }
    }

    /// The tool's options, and on an iPad the network's overview.
    private var middle: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ControlPanel(session: session, arrangement: .options)
            if verticalSizeClass == .regular {
                Divider()
                NetworkOverview(session: session)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.padding)
        .padding(.top, hasHead ? Self.fade : Self.padding)
        .padding(.bottom, hasFoot ? Self.fade : Self.padding)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { middleHeight = $0 }
    }

    /// The action button.
    private var foot: some View {
        ControlPanel(session: session, arrangement: .action)
            .padding([.bottom, .horizontal], Self.padding)
            .padding(.top, Self.spacing - Self.fade)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footHeight = $0 }
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
        /// The news log (decision 175), opened by the HUD's bell or the
        /// station master.
        case news
        /// A closed month's report (decision 175).
        case monthEnd
        /// The sights and their souvenir shops (decision 174).
        case tourism
        /// The help guide (decision 177), from the game menu.
        case help

        var id: Self { self }

        /// Shown beside the map rather than presented over it (decision
        /// 106, ``ContentView``): the panels the map is used with.
        var isBesideMap: Bool {
            switch self {
            case .lines, .station, .economy: true
            case .timetable, .fleet, .mapLayers, .dataSources, .settings, .yearEnd, .goals, .tourism, .news, .monthEnd, .help: false
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
    /// Where the map's bottom-trailing column (the small map, the zoom
    /// buttons, a layer's key) stands on the screen, as the map measured
    /// it: the station master's bubble stops short of it.
    var mapCornerFrame: CGRect = .zero
    /// Where the tutorial's targets inside a panel beside the map stand on
    /// the screen (global coordinates): the panel's NavigationStack keeps
    /// their marks (``TutorialTargetBounds``) from the overlay, so they
    /// report here (`tutorialPanelTarget(_:)`).
    var tutorialPanelTargets: [TutorialTarget: CGRect] = [:]
    /// Where the places the tutorial's step has the player tap on the map
    /// stand on the screen (global coordinates), as the map measured them
    /// (``GameSession/tutorialPlacesToTap``): the card keeps clear of
    /// them (decision 188, later fix).
    var tutorialMapSites: [CGRect] = []
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

/// The keys of the secretary room's settings (decision 175), shared by the
/// game screen and the settings: kept on the device with `@AppStorage`.
enum SecretarySettings {
    static let pauseKey = "secretary.pausesForImportantEvents"
    static let monthlyKey = "secretary.monthlyReport"
}
