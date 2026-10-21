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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Decision 175: the secretary room's settings, kept on the device.
    @AppStorage(SecretarySettings.pauseKey) private var pausesForImportantEvents = true
    @AppStorage(SecretarySettings.nightSkipKey) private var skipsQuietNights = false
    @AppStorage(SecretarySettings.monthlyKey) private var monthlyReportMode = MonthlyReportMode.openAndPause.rawValue
    /// Lives above the layout: rebuilding it must not discard the camera.
    @State private var mapCamera: PlanCamera?
    /// The open panel and the map's layer settings, above the layout for
    /// the same reason: turning the device rebuilds every view under it.
    @State private var screen = GameScreenState()
    /// How far down the status pill reaches, with its margin.
    @State private var pillDepth: CGFloat = 0
    /// The height of the row under the status pill (the layer strip, the
    /// follow bar), without its margin.
    @State private var stripHeight: CGFloat = 0
    /// How far Undo and Redo reach from the leading edge beside the tools
    /// column, with the column (decision 226).
    @State private var editsWidth: CGFloat = 0
    /// The dock's size, with its margin.
    @State private var dockSize = CGSize.zero
    /// How far down the details card reaches, with its margins.
    @State private var cardDepth = CGFloat.infinity
    /// The player's choice for the details card: open or folded, `nil` to
    /// follow what there is to show (``ControlDetails``).
    @State private var detailsChoice: Bool?
    /// Decision 266: how the lesson just played ended, on its card.
    @State private var lessonResult: LessonResult?
    /// Compact height: a phone, held on its side.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Decision 269: the 3D map closes at once onto the 2D map at `plan`.
    private func back(to plan: Map3DHandoff.Plan) {
        screen.map2DReturn = plan
        var cut = Transaction()
        cut.disablesAnimations = true
        withTransaction(cut) { screen.showsMap3D = false }
    }

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
            // Decision 229, later: this game's 3D map, from the map's own
            // button (``Map3DShortcut``).
            .fullScreenCover(isPresented: $screen.showsMap3D) {
                // Decision 269: a 3D map a pinch handed over hands the 2D
                // map back as it is pinched out, at once (the 2D map takes
                // up `plan`); one the button opened never does (later fix,
                // 71.1).
                // Decision 313: its "2D" button goes back to the 2D map
                // where it looks, whichever way it opened, and Build there
                // with the building tools out, as the dock's Build does.
                Map3DPreviewScreen(session: session, handedOver: screen.map3DHandoff, openedAt: screen.map3DOpenedAt,
                                   close: { screen.showsMap3D = false },
                                   handBack: screen.map3DHandoff == nil ? nil : { plan in back(to: plan) },
                                   toMap2D: { plan in back(to: plan) },
                                   build: { plan in
                    back(to: plan)
                    session.selectTool(.network)
                })
            }
            .environment(screen)
            .onAppear(perform: syncSecretarySettings)
            .onChange(of: pausesForImportantEvents) { _, _ in syncSecretarySettings() }
            .onChange(of: skipsQuietNights) { _, _ in syncSecretarySettings() }
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
                // Decision 266: a lesson ends on its result card.
                if ended, let result = LessonResult(world: session.world) {
                    session.dismissScenarioEnd()
                    lessonResult = result
                    return
                }
                if ended, screen.panel == nil {
                    screen.panel = .goals
                }
            }
            .sheet(isPresented: Binding(get: { lessonResult != nil }, set: { if !$0 { lessonResult = nil } })) {
                if let result = lessonResult {
                    LessonResultCard(
                        result: result, language: session.language,
                        next: {
                            lessonResult = nil
                            if let next = result.next { launcher.startLesson(next) }
                        },
                        again: {
                            lessonResult = nil
                            launcher.startLesson(Lesson.all[result.lesson - 1])
                        },
                        keepPlaying: {
                            lessonResult = nil
                            session.keepPlaying()
                        }
                    )
                    .presentationDetents([.medium, .large])
                }
            }
            // Decision 315: a real branch line offered, and in the same
            // sheet the card its purchase ends on.
            .sheet(isPresented: Binding(
                get: { session.shownRealLineOffer != nil || session.lastLineAcquired != nil },
                set: { if !$0 { session.shownRealLineOffer = nil; session.lastLineAcquired = nil } }
            )) {
                if let acquired = session.lastLineAcquired {
                    AcquisitionCompleteCard(acquired: acquired, language: session.language) {
                        session.lastLineAcquired = nil
                        screen.panel = .lines
                    }
                    .presentationDetents([.medium, .large])
                } else if let offer = session.shownRealLineOffer {
                    RealLineOfferCard(session: session, offer: offer)
                        .presentationDetents([.medium, .large])
                }
            }
            // Decision 303: a new line's hours and trains, before they are
            // bought; the lines panel shows the line once it is open.
            .sheet(isPresented: Binding(
                get: { session.lineConfirmation != nil },
                set: { if !$0 { session.cancelLineConfirmation() } }
            )) {
                LineConfirmationCard(session: session) {
                    screen.panel = .lines
                }
                .presentationDetents([.medium, .large])
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
            // The tutorial's step that asks for the lines panel reads it
            // from the session.
            .onChange(of: screen.panel == .lines, initial: true) { _, shown in
                session.linesPanelDidChange(isShown: shown)
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
            // Decision 201, later: the one-time card about track numbers
            // and routes.
            .modifier(RouteHintCard(session: session, screen: screen))
            .modifier(PassingLoopCards(session: session, screen: screen))
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
    /// Decision 226: un-fades the tools; written only when they are faded.
    private func endDrawingUnderTools() {
        if screen.isDrawingUnderTools { screen.isDrawingUnderTools = false }
    }

    private func syncSecretarySettings() {
        session.pausesForImportantEvents = pausesForImportantEvents
        session.skipsQuietNights = skipsQuietNights
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
            // Its line button opens the lines panel through the screen.
            TimetableEditor(session: session)
                .environment(screen)
                .presentationDetents([.medium, .large])
        case .fleet:
            FleetOverviewSheet(session: session)
        case .mapLayers:
            StoredMapLayerSheet(session: session) {
                screen.panel = .dataSources
            }
        case .dataSources:
            DataSourcesView(launcher: launcher)
        case .settings:
            // Decision 127: a problem report from a game says what is in it.
            SettingsView(audio: audio, game: session.problemReportGame, lessons: launcher.lessonReport(in: .app), session: session)
        case .yearEnd:
            YearEndSheet(session: session)
                .presentationDetents([.medium, .large])
        case .goals:
            GoalsPanel(session: session, achievements: launcher.achievements)
                .presentationDetents([.medium, .large])
        case .tourism:
            TourismPanel(session: session, focus: screen.sightFocus)
                .presentationDetents([.medium, .large])
        case .news:
            NewsLogView(session: session)
                .presentationDetents([.medium, .large])
        case .monthEnd:
            MonthlyReportSheet(session: session)
                .presentationDetents([.medium, .large])
        case .help:
            HelpView(language: session.language)
        case .postcard:
            PostcardSheet(session: session)
        case .achievements:
            AchievementsSheet(session: session, records: launcher.achievements)
                .presentationDetents([.medium, .large])
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
            // Decision 106, later: narrower on a phone on its side, so the
            // map keeps about two thirds of the screen.
            let compactHeight = verticalSizeClass == .compact
            let cardWidth: CGFloat = SidePanelWidth.card(screenWidth: proxy.size.width, compactHeight: compactHeight)
            let sidePanel = screen.panel.flatMap { $0.isBesideMap ? $0 : nil }
            let sideWidth: CGFloat = SidePanelWidth.panel(screenWidth: proxy.size.width, compactHeight: compactHeight)
            // Decision 300: on a phone on its side the map's zoom buttons
            // stand under the panel rather than beside it in the middle of
            // the map; the panel ends above them where the credits' band
            // has no room for them.
            let buttonsUnderPanel = MapCornerRow.standsUnderPanel(compactHeight: compactHeight, panelBesideMap: sidePanel != nil)
            let panelBottom = strip + margin
                + CGFloat(MapCornerRow.panelRaise(underPanel: buttonsUnderPanel, inBand: screen.mapRowInBand))
            // The details card gives way to a panel beside the map.
            let isOpen = sidePanel == nil && ControlDetails.isOpen(
                session, choice: detailsChoice, foldsWhileDrawing: verticalSizeClass == .compact
            )
            // Decision 226: on a phone held sideways the tools are a column
            // down the leading edge, not a dock along the bottom; the map
            // keeps its height. `dockSize` measures either. In the tutorial
            // too (decision 226, later: its steps point at the game's own
            // controls, not a dock it alone had).
            let toolsColumn = compactHeight
            // With the column, the bottom row is the column's foot, the
            // map's own buttons (layers, map style, expansion) and the
            // station master with its title, side by side
            // (``EnvironmentValues/mapLeadingRowFoot``); what floats over
            // the map (the build's ✓, banners) keeps above that row.
            let dockBottom = toolsColumn ? StationMasterCorner.standingHeight + margin : dockSize.height
            // The card runs down to the screen's bottom edge, or stops above
            // the dock where both would not fit side by side.
            let besideDock = toolsColumn || dockSize.width + cardWidth + margin <= proxy.size.width
            let cardBottom = strip + (besideDock ? 0 : dockSize.height)
            let cardHeight = max(120, proxy.size.height - pillDepth - cardBottom - 2 * margin)
            // Decision 114: the tools down the leading edge while building,
            // between the pill and the dock.
            let showsRail = BuildToolRail.isShown(session)
            let railHeight = max(60, proxy.size.height - pillDepth - strip - dockSize.height - 2 * margin)
            // Decision 224 (5B): the layer strip under the pill, while not
            // building and not in the tutorial; on a phone the building
            // tools need the height it takes (the column held Done below
            // its fold with it, PR #644's gate). The map's round layers
            // button, which opens the same list, shows only while the strip
            // does not (decision 226, 2026-10-15).
            let showsLayerStrip = !showsRail && session.tutorial == nil
            // Decision 226 (2026-10-15, the owner): the follow bar beside
            // the strip, in the row under the pill, rather than squeezed
            // between the tools and the card lower down.
            let followed = session.followedTrain
            let showsTopRow = showsLayerStrip || followed != nil
            // The map's top column (its banner, the construction readout)
            // starts under that row, not behind it.
            let mapTop = pillDepth + (showsTopRow ? margin + stripHeight : 0)
            // Decision 120: the map runs to the screen's edges, under the
            // camera housing and the home indicator, as Apple's Maps does;
            // the controls stay inside the safe area.
            Color.clear
                .background {
                    map
                        .environment(\.mapInsets, EdgeInsets(
                            top: mapTop,
                            // Past Undo and Redo too when they show.
                            leading: toolsColumn ? max(dockSize.width, ControlPanel.showsEdits(session) ? editsWidth : 0)
                                : showsRail ? BuildToolRail.width + margin : 0,
                            bottom: dockBottom,
                            trailing: sidePanel != nil ? sideWidth + margin : isOpen ? cardWidth + margin : 0
                        ))
                        // A panel beside the map runs down its whole side.
                        .environment(\.mapTrailingInsetDepth, sidePanel != nil ? .infinity : isOpen ? cardDepth : 0)
                        .environment(\.mapButtonsUnderPanel, buttonsUnderPanel)
                        .environment(\.mapDetailsOpen, isOpen)
                        .environment(\.mapSafeArea, proxy.safeAreaInsets)
                        .environment(\.mapShowsLayerStrip, showsLayerStrip)
                        // Decision 226 (2026-10-15, the owner): on a phone
                        // the map's layers and expansion buttons stand on
                        // the bottom row, beside the column's foot, not
                        // above the station master.
                        .environment(\.mapLeadingRowFoot, toolsColumn ? margin : nil)
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
                            // Decision 253: in from its edge, out faster.
                            .transition(.card(from: .trailing, reduceMotion: reduceMotion))
                    }
                }
                // Decision 224 (5B): the layers used most, under the pill,
                // while not building (the tool rail has that edge then) and
                // not in the tutorial, whose card points at the map.
                .overlay(alignment: .topLeading) {
                    if showsTopRow {
                        // As far as the card or a panel beside the map, and
                        // beside the building tools while they are out: they
                        // reach up to the pill (the follow bar alone then).
                        let trailing = sidePanel != nil ? sideWidth + margin : isOpen ? cardWidth + margin : 0
                        let leading = showsRail ? (toolsColumn ? dockSize.width : BuildToolRail.width + margin) : 0
                        HStack(alignment: .center, spacing: margin) {
                            if showsLayerStrip {
                                // Decision 305: under the speed, a night with
                                // no train to skip.
                                NightSkipChip(session: session)
                                MapQuickLayerStrip(language: session.language) {
                                    screen.panel = .mapLayers
                                }
                                // CTM study M2: a free game's next step.
                                if let steps = session.nextSteps {
                                    NextStepChip(steps: steps, language: session.language) {
                                        screen.panel = .goals
                                    }
                                }
                            }
                            if let followed {
                                FollowBar(train: followed, session: session) {
                                    session.stopFollowingTrain()
                                }
                                .transition(.card(from: .top, reduceMotion: reduceMotion))
                            }
                        }
                        .frame(maxWidth: max(0, proxy.size.width - leading - trailing - 2 * margin), alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stripHeight = $0 }
                        .padding(.top, pillDepth)
                        .padding([.top, .leading], margin)
                        .padding(.leading, leading)
                        .transition(.opacity)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if showsRail, !toolsColumn {
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
                    Group {
                        if toolsColumn {
                            // Up to the screen's gap below the layer strip
                            // (TestFlight, 2026-10-16: on a short phone the
                            // column's top all but touched it), or below the
                            // board while the strip is not there; the follow
                            // bar alone stands beside the column.
                            ToolsColumn(
                                session: session, isOpen: isOpen, canToggle: sidePanel == nil,
                                maxHeight: CGFloat(ToolColumn.maxHeight(
                                    screenHeight: proxy.size.height,
                                    top: showsLayerStrip ? pillDepth + margin + stripHeight : pillDepth,
                                    gap: margin, bottom: strip + margin
                                ))
                            ) {
                                detailsChoice = !isOpen
                            }
                            .transition(.opacity)
                        } else {
                            ControlDock(session: session, isOpen: isOpen, canToggle: sidePanel == nil) {
                                detailsChoice = !isOpen
                            }
                        }
                    }
                    // Decision 226: faded while a finger draws under them.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { screen.toolsFrame = $0 }
                    .opacity(screen.isDrawingUnderTools ? 0.4 : 1)
                    .animation(.easeInOut(duration: 0.15), value: screen.isDrawingUnderTools)
                    // A drag whose end the map never sees (the tool or the
                    // panel changed under the finger) must not leave them faded.
                    .onChange(of: session.tool) { _, _ in endDrawingUnderTools() }
                    .onChange(of: screen.panel) { _, _ in endDrawingUnderTools() }
                    .padding([.leading, .bottom], margin)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { dockSize = $0 }
                    .padding(.bottom, strip)
                }
                // Decision 226: Undo and Redo beside the tools column's
                // foot, when there is an edit to take back or make again.
                .overlay(alignment: .bottomLeading) {
                    if toolsColumn {
                        ControlPanel(session: session, arrangement: .editsRow)
                            .padding(.leading, dockSize.width + ControlPanel.tileGap)
                            .padding(.bottom, strip + margin)
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { editsWidth = $0 }
                    }
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
                    // Beside the tools column, past Undo and Redo when they
                    // show (decision 226).
                    // On a phone past the map's buttons too, which share the
                    // bottom row (decision 226): its bubble opens over the
                    // map, not over them.
                    let rowEnd = toolsColumn && screen.mapLeadingRowFrame.width > 0
                        ? screen.mapLeadingRowFrame.maxX - proxy.frame(in: .global).minX : 0
                    let beside = max(dockSize.width + (toolsColumn && ControlPanel.showsEdits(session) ? editsWidth - dockSize.width : 0), rowEnd)
                    let isCovered = beside + margin + StationMasterCorner.avatarSize + margin > proxy.size.width - trailing
                    if session.tutorial == nil, dockSize != .zero {
                        StationMasterCorner(
                            session: session,
                            maxBubbleWidth: proxy.size.width - beside - trailing - 3 * margin - 52,
                            isCovered: isCovered
                        )
                        .padding(.leading, beside + margin)
                        .padding(.bottom, strip + margin)
                    }
                }
                // Decision 224 (3B): the last two stations picked for a new
                // line, compared, above the dock and clear of a panel
                // beside the map; not in the tutorial, whose card leads.
                .overlay(alignment: .bottom) {
                    let draft = session.lineDraft
                    if session.tutorial == nil, draft.count >= 2 {
                        StationPairDrawer(session: session, from: draft[draft.count - 2], to: draft[draft.count - 1])
                            .padding(.horizontal, margin)
                            .padding(.leading, toolsColumn ? dockSize.width : 0)
                            .padding(.trailing, sidePanel != nil ? sideWidth + margin : 0)
                            // Beside the tools column, above the station
                            // master, who stands at its foot.
                            .padding(.bottom, strip + dockBottom + 2 * margin)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                            .padding(.bottom, panelBottom)
                            .transition(.card(from: .trailing, fades: false, reduceMotion: reduceMotion))
                    }
                }
                // Decision 253: the rest of the screen makes room as one
                // change; with Reduce Motion at once, the cards and panels
                // only fading.
                .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: isOpen)
                .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: showsRail)
                .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: toolsColumn)
                .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: sidePanel)
                .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: session.lineDraft.count >= 2)
                .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: session.followedTrain?.id)
        }
    }

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
/// what it would show changes. During the tutorial (decision 188), always
/// when its step points into it (the toggle is hidden then); otherwise as
/// the player chose, else for a selection, and else as for a tool, so a
/// phone's map steps keep the whole map. A
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
            if let choice { return choice }
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

/// Shows or hides the details card, from the dock. Hidden on the
/// tutorial's steps that point into the card, which keep it open.
private struct ControlDetailsToggle: View {
    let isOpen: Bool
    let action: () -> Void
    @Environment(\.toolColumnStyle) private var column

    var body: some View {
        Button(action: action) {
            // The card's own shape, open or not: the map's ⓘ is MapLibre's
            // attribution, a different thing (decision 123).
            let icon = Image(systemName: "sidebar.trailing")
                .font(.subheadline.weight(.bold))
            if column != nil {
                // In the phone's column, the size of the tools under it,
                // labelled or not (TestFlight, 2026-10-16: the toggle was
                // as wide as its icon and shorter than a named button): a
                // name's room kept, unseen, round the icon.
                TabLabel(systemImage: "sidebar.trailing", title: " ")
                    .hidden()
                    .overlay { icon }
            } else {
                // 40 in the dock, which offers it no more.
                icon.frame(minWidth: 40, minHeight: 40)
            }
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: isOpen))
        .accessibilityLabel(isOpen ? "Hide Controls" : "Show Controls")
        .accessibilityIdentifier("controls.toggle")
    }
}

/// Cash, time, speed and the game menu (``HUDView``) in one glass pill at
/// the top of the screen (decision 106), as wide as what it shows.
/// Decision 226 made it a row of solid tiles for a day; on a device the
/// row was twice as tall and heavier than the pill (2026-10-15).
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
/// (``ControlPanel``'s tools), in a dock at the bottom of the screen
/// (decision 106; a regular height: an iPad, the tutorial too since
/// decision 226's later change), with the button that shows or hides the
/// details card.
private struct ControlDock: View {
    let session: GameSession
    let isOpen: Bool
    var canToggle = true
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ControlPanel(session: session, arrangement: .tools)
            // In the tutorial, only on the steps that do not point into the
            // card: on a phone on its side it covered a third of the map,
            // with no way to hide it (a player's report on 59.1).
            if session.tutorial?.step.usesDetailsCard != true {
                ControlDetailsToggle(isOpen: isOpen, action: toggle)
                    .disabled(!canToggle)
            }
        }
        .fixedSize()
        .padding(8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Decision 226: on a phone held sideways, the tools in a column down the
/// leading edge, anchored at the bottom where the thumb rests, so the map
/// keeps its height: the details card's toggle on top, then the tools
/// (``ControlPanel/Arrangement/toolsColumn``, Build at the bottom). While
/// building, the building tools (``BuildToolRail``, decision 114) take the
/// tools' place, over Build. Undo and Redo, when they show, stand beside the
/// column's foot (``ContentView``), not in it: a phone held sideways has
/// not the height for all of them.
private struct ToolsColumn: View {
    let session: GameSession
    let isOpen: Bool
    var canToggle = true
    /// The most height the column may take: from the screen's foot up to
    /// the layer strip, less the gap kept below it (``ToolColumn``).
    let maxHeight: CGFloat
    let toggle: () -> Void

    /// The groups with names under the icons where they fit, else the icons
    /// alone, else the icons scrolling, all of them alike (as the building
    /// tools beside the map, ``BuildToolRail``): each button one size,
    /// chosen or not, each group one width (TestFlight, 2026-10-16).
    var body: some View {
        ViewThatFits(in: .vertical) {
            groups(compact: false)
            groups(compact: true)
            ScrollView {
                groups(compact: true)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .tutorialClip()
        }
        .frame(width: ToolColumnStyle.width)
        // Offered no more than that, and as tall as what it shows: a frame
        // would stand as tall as the room, and the column faded for a
        // finger drawing over the map above it (``GameScreenState/toolsFrame``).
        .modifier(HeightCap(maxHeight: maxHeight))
    }

    private func groups(compact: Bool) -> some View {
        VStack(alignment: .center, spacing: ControlPanel.tileGap) {
            // The card's toggle stays on top while building too: a chosen
            // tool keeps the card open, and folding it shows the map. Not
            // on the tutorial's steps that point into the card, which keep
            // it open, as in the dock.
            if session.tutorial?.step.usesDetailsCard != true {
                ControlDetailsToggle(isOpen: isOpen, action: toggle)
                    .disabled(!canToggle)
                    .controlTile()
            }
            if BuildToolRail.isShown(session) {
                BuildToolButtons(session: session)
                    .controlTile()
                // Build where it was, lit: a second tap closes the tools.
                ControlPanel(session: session, arrangement: .buildEntry)
            } else {
                ControlPanel(session: session, arrangement: .toolsColumn)
            }
        }
        .environment(\.toolColumnStyle, ToolColumnStyle(compact: compact))
    }
}

/// Offers a view at most `maxHeight` and takes the height it takes, at the
/// foot of the room.
private struct HeightCap: ViewModifier {
    let maxHeight: CGFloat

    func body(content: Content) -> some View {
        CapLayout(maxHeight: maxHeight) { content }
    }

    private struct CapLayout: Layout {
        let maxHeight: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            guard let view = subviews.first else { return .zero }
            return view.sizeThatFits(ProposedViewSize(width: proposal.width, height: min(proposal.height ?? maxHeight, maxHeight)))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading,
                                  proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        }
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
    /// The layout the card keeps for what it shows (``pinsEnds``); `nil`
    /// until its heights have changed since it began to show it.
    @State private var pinned: Bool?

    /// The card's inner margin, and the gap between its parts.
    private static let padding: CGFloat = 14
    private static let spacing: CGFloat = 12
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
    /// Something new to show decides afresh; the same thing keeps its
    /// layout until the other is needed (``DetailsCardLayout``), so a head
    /// a line longer or shorter, as a train's when it stops and starts,
    /// does not rebuild the middle, putting it back at its top and closing
    /// a menu open in it (TestFlight 56.1).
    private var pinsEnds: Bool {
        pinned ?? DetailsCardLayout.pinsEnds(ends: ends, maxHeight: maxHeight, pinned: nil)
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
                    // Which of the two layouts shows, for the UI tests.
                    .accessibilityIdentifier("details.scroll.middle")
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
                .accessibilityIdentifier("details.scroll.whole")
            }
        }
        .frame(height: min(max(ends + middleHeight, 1), maxHeight), alignment: .top)
        .onChange(of: [ends, maxHeight]) {
            pinned = DetailsCardLayout.pinsEnds(ends: ends, maxHeight: maxHeight, pinned: pinned)
        }
        .onChange(of: ControlDetails.Subject(session, foldsWhileDrawing: verticalSizeClass == .compact)) {
            pinned = nil
        }
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

    /// The action button. Under a scrolling middle it keeps a whole gap
    /// clear of the fade: the author saw a train's load bar half under it
    /// (report of 2026-10-14).
    private var foot: some View {
        ControlPanel(session: session, arrangement: .action)
            .padding([.bottom, .horizontal], Self.padding)
            .padding(.top, pinsEnds ? Self.spacing : Self.spacing - Self.fade)
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
        /// The network postcard (decision 215), from the game menu.
        case postcard
        /// The achievements (decision 181), from the game menu's first
        /// level (decision 226, later).
        case achievements

        var id: Self { self }

        /// Shown beside the map rather than presented over it (decision
        /// 106, ``ContentView``): the panels the map is used with.
        var isBesideMap: Bool {
            switch self {
            case .lines, .station, .economy: true
            case .timetable, .fleet, .mapLayers, .dataSources, .settings, .yearEnd, .goals, .tourism, .news, .monthEnd, .help, .postcard, .achievements: false
            }
        }
    }

    var panel: Panel?
    /// Decision 250 (a player's report): the sight whose mark or bubble on
    /// the map opened the sights panel, which scrolls to it; `nil` from the
    /// menu.
    var sightFocus: AttractionID?
    /// Decision 229, later: whether this game's 3D map is open, from the
    /// map's 3D button.
    var showsMap3D = false
    /// Decision 269: the 2D map's view when a pinch handed it over to the
    /// 3D map (`nil` when the 3D button opened it), and the 3D map's when
    /// it handed it back, for the 2D map to take up.
    var map3DHandoff: Map3DHandoff.Plan?
    var map2DReturn: Map3DHandoff.Plan?
    /// Decision 313, later: the 2D map's view when the 3D button opened the
    /// 3D map, which opens over the same place.
    var map3DOpenedAt: Map3DHandoff.Plan?
    /// Whether the station panel, as it opens, puts up its rename alert
    /// at once: the station tag's pencil (TestFlight 60.1, renaming took
    /// three taps before a letter could be typed).
    var renamesStationOnOpen = false
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
    /// Decision 300: whether the map's buttons under a phone's panel found
    /// room in the credits' band, as the map measured it: where they did
    /// not, the panel ends above them.
    var mapRowInBand = false
    /// Where the map's bottom-leading buttons stand on the screen, as the
    /// map measured them: on a phone's bottom row the station master
    /// stands past them (decision 226).
    var mapLeadingRowFrame: CGRect = .zero
    /// Decision 226: where the tools stand on the screen (global
    /// coordinates; the column down a phone's leading edge, or the dock),
    /// as the screen measured them; a finger drawing on the map compares
    /// against it (``isDrawingUnderTools``).
    var toolsFrame: CGRect = .zero
    /// Decision 226: whether a finger drawing on the map (track, a
    /// building, zones) is under the tools: they fade to 40% so the map
    /// shows through, and come back when it lifts. The map sets it, only
    /// when it changes.
    var isDrawingUnderTools = false
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
    /// Decision 305: skip a quiet night without the shortcut; off.
    static let nightSkipKey = "secretary.skipsQuietNights"
}

/// The one-time card about track numbers and routes (decision 201, later;
/// ``RouteHint``): when a line first gets double track, or the line panel's
/// route menus first come into view. Shown over the map or the lines
/// panel only, never over another sheet; seen once, kept on the device.
private struct RouteHintCard: ViewModifier {
    let session: GameSession
    let screen: GameScreenState
    @AppStorage(RouteHint.seenKey) private var seen = false
    /// The lines panel's Advanced switch (decision 196, later), opened by
    /// the card's button.
    @AppStorage("linesPanel.showsAdvanced") private var storedShowsAdvanced: Bool?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        content
            .onChange(of: seen ? nil : RouteHintWatch(world: session.world), initial: true) { _, watch in
                if watch != nil { session.watchRouteHint() }
            }
            .alert(
                Text(verbatim: RouteHint.title(in: session.language)),
                isPresented: shown,
                presenting: session.routeHint
            ) { trigger in
                if let show = RouteHint.showButton(trigger, in: session.language) {
                    Button {
                        showRoutes(trigger)
                    } label: {
                        Text(verbatim: show)
                    }
                }
                Button(role: .cancel) {
                    finish()
                } label: {
                    Text(verbatim: RouteHint.dismissButton(in: session.language))
                }
            } message: { trigger in
                Text(verbatim: RouteHint.message(trigger, in: session.world, language: session.language, advancedShown: advancedShown))
            }
    }

    private var shown: Binding<Bool> {
        Binding {
            !seen && session.routeHint != nil && (screen.panel == nil || screen.panel == .lines)
        } set: { shown in
            if !shown { finish() }
        }
    }

    private var advancedShown: Bool {
        AdvancedDetails.isShown(
            stored: storedShowsAdvanced,
            roomy: horizontalSizeClass == .regular && verticalSizeClass == .regular
        )
    }

    /// The line with the new double track, in the lines panel with its
    /// route menus unfolded.
    private func showRoutes(_ trigger: RouteHint.Trigger) {
        if case .parallelTrack(let line) = trigger {
            storedShowsAdvanced = true
            session.selectLine(line)
            screen.panel = .lines
        }
        finish()
    }

    private func finish() {
        seen = true
        session.dismissRouteHint()
    }
}

/// Decision 204, later: after a passing loop is built, the offer to add its
/// signal station to the lines it lies on (``PassingLoopOffer``); and the
/// one-time card the first time a line's train waits on single track
/// (``PassingLoopHint``), seen once per device.
private struct PassingLoopCards: ViewModifier {
    let session: GameSession
    let screen: GameScreenState
    @AppStorage(PassingLoopHint.seenKey) private var seen = false

    func body(content: Content) -> some View {
        content
            // The waiting trains, read with each tick (the map reads them
            // too); looked at only until the card has been seen.
            .onChange(of: seen ? nil : session.trafficOverlay.waits.map(\.train)) { _, waiting in
                if let waiting, !waiting.isEmpty { session.watchPassingLoopHint() }
            }
            .alert(
                Text(verbatim: PassingLoopOffer.title(in: session.language)),
                isPresented: offerShown,
                presenting: session.passingLoopOffer
            ) { _ in
                Button {
                    session.acceptPassingLoopOffer()
                } label: {
                    Text(verbatim: PassingLoopOffer.addButton(in: session.language))
                }
                Button(role: .cancel) {
                    session.dismissPassingLoopOffer()
                } label: {
                    Text(verbatim: PassingLoopOffer.skipButton(in: session.language))
                }
            } message: { offer in
                Text(verbatim: offer.message(in: session.world, language: session.language))
            }
            .alert(
                Text(verbatim: PassingLoopHint.title(in: session.language)),
                isPresented: hintShown,
                presenting: session.passingLoopHint
            ) { _ in
                Button {
                    seen = true
                    screen.panel = nil
                    session.showPassingLoopTool()
                } label: {
                    Text(verbatim: PassingLoopHint.showButton(in: session.language))
                }
                Button(role: .cancel) {
                    finishHint()
                } label: {
                    Text(verbatim: PassingLoopHint.dismissButton(in: session.language))
                }
            } message: { line in
                Text(verbatim: PassingLoopHint.message(line: line, in: session.world, language: session.language))
            }
    }

    private var offerShown: Binding<Bool> {
        Binding {
            session.passingLoopOffer != nil && screen.panel == nil
        } set: { shown in
            if !shown { session.dismissPassingLoopOffer() }
        }
    }

    private var hintShown: Binding<Bool> {
        Binding {
            !seen && session.passingLoopHint != nil && screen.panel == nil
        } set: { shown in
            if !shown { finishHint() }
        }
    }

    private func finishHint() {
        seen = true
        session.dismissPassingLoopHint()
    }
}
