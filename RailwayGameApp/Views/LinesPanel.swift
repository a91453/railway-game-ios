import Charts
import GameCore
import GamePresentation
import SwiftUI

/// Service lines (Phase 4 Stage R): every line and whether it runs now; for
/// the selected line, each of its services (its own and its patterns) with
/// the trains it is set to run at each level, what it can run and how far
/// apart, its trains, and stretches no service covers; whether it is a
/// ring (decision 49); its stops (Stage C2); adding patterns and assigning
/// the selected train; and picking stations for a new line. At the top, the traffic control switch (Phase
/// 4.6 Stage T) and the service day's bands (Stage C2).
///
/// Shown in a sheet that leaves the map usable at half height, so stations
/// can be selected for a new line while it is open. Everything shown is
/// read from `session.world` when the view is drawn, and every control
/// calls a `GameSession` method that applies one `GameWorld` command.
struct LinesPanel: View {
    let session: GameSession

    init(session: GameSession) {
        self.session = session
        // Decision 481: opened on the line's page when a line is opened,
        // with no slide as the panel comes in.
        _path = State(initialValue: LinesPanelPage.path([], opened: session.openedLine != nil))
    }
    /// Closes it (decision 106: shown beside the map, not presented, so
    /// the environment's dismiss would do nothing).
    @Environment(GameScreenState.self) private var screen
    @State private var patternFirst = 0
    @State private var patternLast = 1
    @State private var patternExpress = false
    /// The name being typed for the selected line, while its rename alert
    /// is up.
    @State private var renamingLine: String?
    /// Whether the selected line's removal is being confirmed (decision 327).
    @State private var confirmsRemoval = false
    /// The panel removal asking first (UI review 2026-10-28, A): Undo is
    /// emptied by the next tick, and the panel leaves the game running.
    @State private var confirmingPanelRemoval: RemovalConfirmation?
    /// Decision 216: the code being typed for the selected line, while its
    /// alert is up.
    @State private var editingCode: String?
    /// Decision 216: redraws the badges and colours when the line palette
    /// changes.
    @AppStorage(LinePalette.key) private var linePalette: LinePalette = .standard
    /// How often a train should come, for the selected line's trains
    /// (decision 101).
    @State private var staffHeadway: Int64 = 10
    /// The type and the cars of the trains a line is staffed with or re-formed
    /// into (decision 180); `nil`: the line's own pick.
    @State private var staffType: TrainType?
    @State private var staffCars = 1
    /// Decision 224 (2A): whether the train types' showroom is open.
    @State private var showsCatalog = false
    /// Decision 179: how the lines are ordered, or `nil` for the order
    /// they were made in.
    @State private var lineSort: LineReportSort?
    /// The order the lines were sorted in when the panel opened, the sort
    /// changed or the player asked (decision 184, later): kept while the
    /// game runs, so a list by profit, riders or load does not move under
    /// the finger at midnight.
    @State private var lineOrder: [LineID]?
    /// What the selected line shows that only a command changes, kept
    /// while the game runs (decision 184, later).
    @State private var memo = LinePanelMemo()
    /// Its fares, costs and why it loses money, kept for a command and a
    /// game day (decision 194).
    @State private var lossMemo = LineLossMemo()
    @State private var satisfactionMemo = LineSatisfactionMemo()
    /// Decision 332: who rides or drives instead of taking the selected
    /// line, worked out off the main actor as the station panel's
    /// ridership is, from every station's day.
    @State private var modeShift: (key: LineModeShiftKey, value: ModeShiftSummary?)?
    /// Decision 184: the name typed to find a line, and which lines show.
    @State private var lineSearch = ListSearch()
    @State private var lineFilter: LineFilter = .all
    /// Decision 486: whether the search field is open over a short panel,
    /// where it waits behind a button.
    @State private var searchOpened = false
    @FocusState private var searchFocused: Bool
    /// Decision 196: whether the new line's form shows while the lines
    /// come first.
    @State private var showsNewLine = false
    /// Decision 481: the pages over the list of lines; the line page
    /// follows ``GameSession/openedLine``.
    @State private var path: [LinesPanelPage] = []
    /// Decision 481, later: the line whose page was left, for the list to
    /// scroll back to it.
    @State private var returningTo: LineID?
    /// Decision 481, later: the groups of a long list folded away
    /// (``LineGroup/stored(_:)``); all open at first.
    @AppStorage("linesPanel.foldedGroups") private var storedFoldedGroups = ""
    /// Decision 206: whether the selected line's train diagram is open.
    @State private var showsDiagram = false
    /// Decision 512: whether the selected line's train roster is open.
    @State private var showsRoster = false
    /// Decision 196, later: the player's choice for the "Advanced" switch,
    /// or `nil` for the device's default (folded on a phone).
    @AppStorage("linesPanel.showsAdvanced") private var storedShowsAdvanced: Bool?
    /// Decision 201, later: whether the card about track numbers and
    /// routes has been seen.
    @AppStorage(RouteHint.seenKey) private var routeHintSeen = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Target headways offered in the menu, in minutes.
    private static let targets: [Int64] = [5, 10, 15, 20, 30, 60]
    /// Where the panel scrolls once the new line's form comes first
    /// (decision 299): its Pick on Map button, under the draft's summary.
    private static let draftAnchor = "line.draft.anchor"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                Form {
                    if listsLinesFirst {
                        // Decision 196 (TestFlight 54.1): with lines made and
                        // none being picked, the lines come first. Decision
                        // 481: a short list, its search, filter and sort
                        // pinned above it, the network's switches, Advanced,
                        // a new line and the lines for sale as rows over
                        // it; a line's own settings on its own page.
                        // Decision 486: on a short panel, the controls in
                        // one row over the lines that scrolls away with
                        // them; decision 498: the lines there before the
                        // other rows, so opening the panel shows some.
                        ForEach(controlsStyle.parts, id: \.self) { part in
                            listPart(part)
                        }
                    } else {
                        // Decision 100: a new line first, where the panel beside
                        // the map (decision 106) shows it while stations are
                        // picked on the map. Decision 508: in its place, while
                        // there are not two stations to pick, what is missing
                        // and the button to Build.
                        if let need = session.linesPanelFirstLineNeed, need.action == .build {
                            firstLineSection(need)
                        } else {
                            draftSection
                        }
                        // Decision 101: a line without trains offers them next.
                        if let line = session.selectedLine {
                            trainsSection(line)
                        }
                        // Decision 336: with no line made too.
                        buyableLinesSection
                        networkSection
                        if showsAdvanced {
                            serviceDaySection
                        }
                        linesSection
                        advancedSection
                        if let line = session.selectedLine {
                            depotSection(line)
                            lineSection(line)
                            operatingSection(line)
                            loadSection(line)
                            stopsSection(line)
                            servicesSections(line)
                        }
                    }
                }
                .hardTopScrollEdge()
                // Decision 486: a short panel's rows take more of its width.
                .contentMargins(.horizontal, listsLinesFirst && controlsStyle == .inline ? 8 : nil, for: .scrollContent)
                // Decision 498: and less room between its sections, so the
                // first lines show under the controls' row.
                .listSectionSpacing(listsLinesFirst && controlsStyle == .inline ? .compact : .default)
                // Decision 481: what finds and orders the lines stays at the
                // top while the list scrolls under it; decision 486: not on
                // a short panel, where it left one line in view.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if listsLinesFirst, controlsStyle == .pinned {
                        listControls
                    }
                }
                .onChange(of: searchOpened) { _, opened in
                    guard opened else { return }
                    Task { @MainActor in
                        await Task.yield()
                        searchFocused = true
                    }
                }
                // The tutorial's targets in the form report their place on the
                // screen themselves (`tutorialPanelTarget(_:)`); the overlay
                // counts them only inside the panel.
                // Decision 188: the button a tutorial step asks for is scrolled
                // into view, below the fold on a phone once stations are picked.
                .onChange(of: RevealKey(session), initial: true) { _, key in
                    guard let target = key.target else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(target, anchor: .center) }
                    }
                }
                // Decision 481, later: Back from a line's page leaves the
                // list where that line is, its group unfolded.
                .onChange(of: returningTo) { _, line in
                    guard let line else { return }
                    returningTo = nil
                    if let group = session.world.line(id: line).map({ session.world.lineGroup(of: $0) }), foldedGroups.contains(group) {
                        var folded = foldedGroups
                        folded.remove(group)
                        storedFoldedGroups = LineGroup.stored(folded)
                    }
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo(Self.rowAnchor(line), anchor: .center)
                    }
                }
                // Decision 299: the first station added (or picking begun)
                // moves the new line's form from under the lines to the top;
                // the panel follows it there rather than staying where the
                // button was, among the selected line's stops.
                .onChange(of: listsLinesFirst) { was, now in
                    guard was, !now else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(Self.draftAnchor, anchor: .center) }
                    }
                }
            }
            // On the tutorial's line steps picking starts by itself (the
            // reference's `openUI`), without the status line's how-to, which
            // would shrink the form: the card says it.
            .onChange(of: session.tutorial?.index, initial: true) { _, _ in
                guard let step = session.tutorial?.step, step.picksLineStops,
                      !session.isPickingLineStops, session.lineDraft.count < 2
                else { return }
                session.startPickingLineStops(announces: false)
            }
            .navigationTitle("Lines")
            .navigationBarTitleDisplayMode(.inline)
            // Decision 481: the selected line's alerts and diagram belong to
            // the page that shows its sections.
            .lineModals(of: self, active: !listsLinesFirst)
            .navigationDestination(for: LinesPanelPage.self) { page in
                switch page {
                case .line: lineDetailPage
                case .network: networkPage
                case .forSale: forSalePage
                }
            }
            .toolbar {
                // Decision 416: the network's flow report, at the top of
                // the panel where the lines are.
                if session.showsNetworkFlowReport {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            screen.panel = .networkFlow
                        } label: {
                            Label {
                                Text(verbatim: NetworkFlowReport.title(in: session.language))
                            } icon: {
                                Image(systemName: "chart.bar.xaxis")
                            }
                            .labelStyle(.titleAndIcon)
                        }
                        .accessibilityIdentifier("lines.networkFlow")
                    }
                }
                doneItem
            }
            .safeAreaInset(edge: .bottom) {
                StatusBanner(session: session, announces: false)
            }
        }
        // Decision 481: a line opened anywhere (a row, the map, a report)
        // shows on its own page; Back to the list closes it.
        .onChange(of: session.openedLine?.id) { _, opened in
            let wanted = LinesPanelPage.path(path, opened: opened != nil)
            guard wanted != path else { return }
            // Reduce Motion: the page is there at once, with no slide
            // (motion skill §3).
            var transaction = Transaction()
            transaction.disablesAnimations = reduceMotion
            withTransaction(transaction) { path = wanted }
        }
        .onChange(of: path) { was, now in
            let left = was.contains(.line) && !now.contains(.line) ? session.openedLineID : nil
            session.linesPanelPathChanged(to: now)
            if let left {
                returningTo = left
            }
        }
        // Decision 481: on the panel, not its first page, which disappears
        // under a line's page.
        .task(id: modeShiftKey) {
            await workOutModeShift(modeShiftKey)
        }
        // Decision 196: a line made from the unfolded form folds it again.
        .onChange(of: session.world.lines.count) { showsNewLine = false }
        .onAppear { sortLinesNow() }
        .onChange(of: lineSort) { sortLinesNow() }
        // The pattern's stops are indices into the selected line's:
        // another line starts from its own first two.
        .onChange(of: session.selectedLineID) {
            patternFirst = 0
            patternLast = 1
            patternExpress = false
        }
        // A stop removed from the line can leave either index past its
        // last stop: the picker would show none, and adding the pattern
        // would be refused.
        .onChange(of: session.selectedLine?.stops.count) { _, count in
            guard let count, patternFirst >= count || patternLast >= count else { return }
            patternFirst = 0
            patternLast = min(1, max(0, count - 1))
        }
        // Decision 201: folding the route menus away ends their preview.
        .onChange(of: showsAdvanced) { _, shown in
            if !shown { session.endRoutePreviews() }
        }
        // Decision 376: lesson 6's guide waits for the switch.
        .onChange(of: showsAdvanced, initial: true) { _, shown in
            session.linesAdvancedDidChange(isShown: shown)
        }
        // Taps on the map select again once the panel is closed.
        .onDisappear {
            session.stopPickingLineStops()
            // Decision 201: the map stops showing a leg once the
            // menu it came from is closed.
            session.endRoutePreviews()
        }
    }

    /// The panel's Done, on every page of its stack.
    private var doneItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                screen.panel = nil
            }
        }
    }

    /// What decides whether the tutorial's step asks for a button the
    /// panel scrolls to: the step, and what moves the button.
    private struct RevealKey: Equatable {
        let step: String?
        let target: TutorialTarget?
        let picked: Int
        let line: LineID?

        @MainActor
        init(_ session: GameSession) {
            step = session.tutorial?.step.id
            target = session.tutorial?.step.revealsInPanel
            picked = session.lineDraft.count
            line = session.selectedLineID
        }
    }

    /// Decision 196: the lines come first once there are some, unless a
    /// new line is being picked or the tutorial leads (its steps point at
    /// the form for a new line at the top).
    private var listsLinesFirst: Bool {
        session.linesPanelListsLinesFirst
    }

    /// Decision 498: one part of the list while the lines come first.
    @ViewBuilder
    private func listPart(_ part: LinesListPart) -> some View {
        switch part {
        case .controls: inlineControlsSection
        case .lines: listedLines
        case .entries: entriesSection
        case .newLine:
            if showsNewLine {
                draftSection
            }
        }
    }

    /// The new line's form folded into one row while the lines come first
    /// (decision 196); picking a station puts it back at the top.
    private var newLineButton: some View {
        Button {
            withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) { showsNewLine.toggle() }
        } label: {
            Label {
                Text(verbatim: session.language.text("New Line…", "新路線…"))
            } icon: {
                Image(systemName: showsNewLine ? "chevron.down" : "plus.circle")
            }
        }
        .accessibilityIdentifier("line.new")
        .accessibilityAddTraits(showsNewLine ? .isSelected : [])
    }

    /// Decision 481: the rows over the short list (under it on a short
    /// panel, decision 498), one each for what is not a line: the
    /// network's switches and service day (their own page), Advanced, a
    /// new line, and the real lines for sale (their own page).
    private var entriesSection: some View {
        Section {
            if session.allows(UnlockableTool.lineDetails) {
                NavigationLink(value: LinesPanelPage.network) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: NetworkSwitches.title(in: session.language))
                            Text(verbatim: NetworkSwitches.summary(of: session.world, in: session.language))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                    }
                }
                .accessibilityIdentifier("lines.network")
                // The network's row above says what the summary would.
                advancedRows(summary: false)
            }
            newLineButton
            if !session.buyableRealLines.isEmpty || session.realLinesForSaleNote != nil {
                NavigationLink(value: LinesPanelPage.forSale) {
                    Label {
                        Text(verbatim: NetworkSwitches.forSaleTitle(count: session.buyableRealLines.count, in: session.language))
                    } icon: {
                        Image(systemName: "signature")
                    }
                }
                .accessibilityIdentifier("lines.forSale")
            }
        }
    }

    // MARK: - Pages over the list (decision 481)

    /// The switches for every line and the service day, on a page of their
    /// own: the service day shows here with Advanced folded too, since the
    /// page is opened for it.
    private var networkPage: some View {
        Form {
            // The page's title already names it (IPHLAND: on a phone on
            // its side the two stood one under the other).
            trafficSection(titled: false)
            serviceDaySection
        }
        .panelTitle(NetworkSwitches.title(in: session.language))
        .toolbar { doneItem }
        .safeAreaInset(edge: .bottom) {
            StatusBanner(session: session, announces: false)
        }
    }

    private var forSalePage: some View {
        Form {
            buyableLinesSection
        }
        .panelTitle(NetworkSwitches.forSaleTitle(count: 0, in: session.language))
        .toolbar { doneItem }
        .safeAreaInset(edge: .bottom) {
            StatusBanner(session: session, announces: false)
        }
    }

    /// The opened line's own page: what its row in the list leaves out,
    /// the lines before and after it, then its trains, depots, stops,
    /// settings, operations and services, in the order the one form had
    /// them (decision 196).
    @ViewBuilder
    private var lineDetailPage: some View {
        if let line = session.openedLine {
            Form {
                lineSummarySection(line)
                trainsSection(line)
                depotSection(line)
                stopsSection(line)
                lineSection(line)
                operatingSection(line)
                loadSection(line)
                servicesSections(line)
            }
            // Another line (the arrows, the map) starts at the top.
            .id(line.id)
            .accessibilityIdentifier("line.detail")
            .hardTopScrollEdge()
            .panelTitle(line.name)
            .toolbar { doneItem }
            .safeAreaInset(edge: .bottom) {
                StatusBanner(session: session, announces: false)
            }
            .lineModals(of: self, active: true)
        }
    }

    /// The top of a line's page: its stops in full, whether it runs now,
    /// yesterday's figures with its trend, and the lines before and after
    /// it in the list.
    private func lineSummarySection(_ line: ServiceLine) -> some View {
        let status = session.world.lineStatusText(line.id, at: session.world.clock.now, in: session.language)
        let all = sortedLines.map(\.id)
        let shown = shownLines.map(\.id)
        let neighbours = LineNeighbours.around(line.id, shown: shown, all: all)
        return Section {
            Text(verbatim: "\(line.stops.map { name(of: $0) }.joined(separator: " – ")) · \(status)")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("line.summary.stops")
            if let report = session.world.lineReport(line.id), !line.isFreight {
                Text(verbatim: report.rowText(in: session.language))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(report.lostMoneyYesterday ? Theme.error : Theme.textSecondary)
                    .accessibilityIdentifier("line.summary.report")
                LineTrendStrip(report: report, language: session.language)
            }
            if neighbours.previous != nil || neighbours.next != nil {
                HStack {
                    neighbourButton(neighbours.previous, title: LineNeighbours.previousTitle(in: session.language),
                                    symbol: "chevron.up", identifier: "line.previous")
                    Spacer(minLength: 8)
                    if let position = LineNeighbours.positionText(line.id, shown: shown, all: all, in: session.language) {
                        Text(verbatim: position)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    neighbourButton(neighbours.next, title: LineNeighbours.nextTitle(in: session.language),
                                    symbol: "chevron.down", identifier: "line.next")
                }
                // Two buttons in one row: each answers its own touch.
                .buttonStyle(.borderless)
            }
        }
    }

    /// Goes to the line before or after on the same page: what the page
    /// shows changes in place, as a tap on another line's row would, with
    /// no slide (decision 481; the stack keeps its one page).
    private func neighbourButton(_ id: LineID?, title: String, symbol: String, identifier: String) -> some View {
        Button {
            if let id { session.openLine(id) }
        } label: {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: symbol)
            }
            .font(.subheadline)
        }
        .disabled(id == nil)
        .accessibilityIdentifier(identifier)
    }

    /// Decision 508: what the first line still needs, in a sentence, over
    /// how.
    private func firstLineHeading(_ need: FirstLineNeed) -> some View {
        let language = session.language
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: need.title(in: language))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(verbatim: need.detail(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lines.firstLine")
    }

    /// Decision 508: at the top of a panel with fewer than two stations,
    /// in the new line's place, what is missing and the one button that
    /// goes there: Build, its track tools chosen.
    private func firstLineSection(_ need: FirstLineNeed) -> some View {
        let language = session.language
        return Section {
            firstLineHeading(need)
            Button {
                screen.panel = nil
                session.selectTool(.network)
            } label: {
                Label {
                    Text(verbatim: need.buttonTitle(in: language))
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: need.buttonSymbol)
                }
            }
            .accessibilityIdentifier("lines.firstLine.go")
        }
    }

    /// Decision 315: the real branch lines this map sells; decision 336:
    /// listed whether or not lines are made, and on a map that sells none,
    /// a line saying why.
    @ViewBuilder
    private var buyableLinesSection: some View {
        let lines = session.buyableRealLines
        if !lines.isEmpty || session.realLinesForSaleNote != nil {
            Section {
                if lines.isEmpty, let note = session.realLinesForSaleNote {
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("line.acquire.none")
                }
                ForEach(lines, id: \.id) { line in
                    Button {
                        session.offerRealLine(line)
                    } label: {
                        Label {
                            Text(verbatim: session.language.text("Buy \(line.name(in: session.language))…", "收購\(line.name(in: session.language))…"))
                        } icon: {
                            Image(systemName: "signature")
                        }
                    }
                    .accessibilityIdentifier("line.acquire.\(line.network)")
                }
            } header: {
                Text(verbatim: session.language.text("Real lines for sale", "可收購的真實路線"))
            }
        }
    }

    /// Decision 196, later (TestFlight 54.1 #6): whether the panel shows
    /// the service day, stopping patterns, the tracks each leg takes,
    /// target headways and the network's switches. Folded, their rules run
    /// as they were set; only the panel leaves them out.
    private var showsAdvanced: Bool {
        AdvancedDetails.isShown(
            stored: storedShowsAdvanced,
            roomy: horizontalSizeClass == .regular && verticalSizeClass == .regular,
            unlocked: session.allows(UnlockableTool.lineDetails)
        )
    }

    /// The "Advanced" switch, under the lines where it is seen at once;
    /// folded, what the network has set there in one line. Decision 266:
    /// none in a lesson before the details are unlocked.
    @ViewBuilder
    private var advancedSection: some View {
        if session.allows(UnlockableTool.lineDetails) {
            Section {
                advancedRows(summary: true)
            }
        }
    }

    /// The switch and, folded, its summary.
    @ViewBuilder
    private func advancedRows(summary: Bool) -> some View {
        Toggle(isOn: Binding(get: { showsAdvanced }, set: { storedShowsAdvanced = $0 })) {
            Label {
                // Decision 336, later: what it holds, in words, not
                // only for VoiceOver; under the switch's own name, so
                // the summary below stays the row after the switch.
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: session.language.text("Advanced", "進階"))
                    Text(verbatim: AdvancedDetails.contentsText(in: session.language))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("lines.advanced.contents")
                }
            } icon: {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .accessibilityIdentifier("lines.advanced")
        .tutorialPanelTarget(.advancedSwitch)
        .id(TutorialTarget.advancedSwitch)
        .accessibilityHint(Text(verbatim: session.language.text(
            "Hidden, they keep working as set.",
            "收起時，這些設定照常運作。"
        )))
        if summary, !showsAdvanced {
            Text(verbatim: AdvancedDetails.networkSummary(of: session.world, in: session.language))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("lines.advanced.summary")
        }
    }

    private func servicesSections(_ line: ServiceLine) -> some View {
        Group {
            ForEach(memo.serviceSummaries(line.id, of: session), id: \.pattern) { summary in
                // Decision 383: a stopping pattern shows with Advanced
                // folded too, as the button that adds it does.
                serviceSection(summary, of: line)
            }
            // A ring has no patterns. Decision 383: not behind Advanced,
            // so an express is found on the line's own page; a lesson
            // before the details are taught still leaves it out.
            if !line.isRing, session.allows(UnlockableTool.lineDetails) {
                addPatternSection(line)
            }
        }
    }

    private func name(of station: StationID) -> String {
        session.world.station(id: station)?.name ?? "#\(station.rawValue)"
    }

    // MARK: - Traffic control

    /// Traffic control and how passengers route, read from the world: the
    /// switches for every line (decision 383: their own block at the top
    /// of the panel, not at the bottom of Advanced). Turning traffic
    /// control on is refused while two trains need the same track: the
    /// status banner says which, and the switch stays off. Decision 266:
    /// none in a lesson before the details are taught.
    @ViewBuilder
    private var networkSection: some View {
        if session.allows(UnlockableTool.lineDetails) {
            trafficSection(titled: true)
        }
    }

    /// `titled`: with the block's name as its header, where no page title
    /// above names it.
    private func trafficSection(titled: Bool) -> some View {
        Section {
            Toggle("Traffic control", isOn: Binding(
                get: { session.world.isTrafficControlEnabled },
                set: { session.setTrafficControl($0) }
            ))
            Toggle("Network passenger routes", isOn: Binding(
                get: { session.world.passengerRoutingMode == .network },
                set: { session.setPassengerRoutingMode($0 ? .network : .direct) }
            ))
        } header: {
            if titled {
                Text(verbatim: NetworkSwitches.title(in: session.language))
            }
        } footer: {
            Text("When on, a train takes its whole route before it leaves, and other trains wait until it has cleared it.")
            Text("With network routes, passengers change lines and walk to stations nearby; otherwise they ride only a line serving both stations.")
        }
    }

    // MARK: - Service day (Stage C2)

    /// The bands of the day, for every line: each with its level and, after
    /// the first, a stepper for when it starts; adding splits the longest
    /// band, and the standard day can be restored.
    private var serviceDaySection: some View {
        let day = session.world.serviceDay
        let language = session.language
        return Section {
            ForEach(Array(day.bands.enumerated()), id: \.offset) { index, band in
                VStack(alignment: .leading, spacing: 4) {
                    // Decision 184, later: a menu the ticks leave alone.
                    let bandText = day.bandText(index, in: language)
                    TickStable(StableKey(index, band.level, bandText, language)) {
                        Picker(selection: Binding(get: { band.level }, set: { session.setServiceDayBand(index, to: $0) })) {
                            ForEach(ServiceLevel.allCases, id: \.self) { level in
                                Text(level.title(in: language)).tag(level)
                            }
                        } label: {
                            Text(verbatim: bandText)
                                .monospacedDigit()
                        }
                        .pickerStyle(.menu)
                    }
                    if index > 0 {
                        Stepper(
                            onIncrement: ServiceDayEditing.canMove(index, later: true, in: day)
                                ? { session.moveServiceDayBand(index, by: ServiceDayEditing.step) } : nil,
                            onDecrement: ServiceDayEditing.canMove(index, later: false, in: day)
                                ? { session.moveServiceDayBand(index, by: -ServiceDayEditing.step) } : nil
                        ) {
                            Text("Starts")
                                .font(.footnote)
                        }
                        .accessibilityHint("Half an hour later or earlier, between the bands around it.")
                    }
                }
                .deleteDisabled(index == 0)
            }
            .onDelete { offsets in
                for index in offsets.sorted(by: >) where index > 0 {
                    session.removeServiceDayBand(index)
                }
            }
            Button {
                session.addServiceDayBand()
            } label: {
                Label("Split the Longest Band", systemImage: "plus.circle")
            }
            Button {
                confirmingPanelRemoval = .standardDay
            } label: {
                Label("Standard Day", systemImage: "arrow.counterclockwise")
            }
            .disabled(day == .standard)
            .removalConfirmation(.standardDay, isPresented: confirming(.standardDay), language: session.language) {
                session.resetServiceDay()
            }
        } header: {
            Text("Service day")
        } footer: {
            Text("Every line runs its peak, off-peak and low trains in these bands. Swipe a band to remove it; the band before it runs on.")
        }
    }

    // MARK: - Lines

    private var linesSection: some View {
        Section {
            if session.world.lines.isEmpty {
                // Decision 122, later: the empty state's picture over its words.
                VStack(spacing: 8) {
                    Image("EmptyLines")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text("No lines yet. Pick stations under New Line to create one.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            } else {
                // Decision 481: pinned above the list while the lines come
                // first (``listControls``); on the one form, in it.
                if !listsLinesFirst {
                    if showsSort {
                        lineSortMenu(short: false)
                    }
                    if showsSearch {
                        lineSearchField
                    }
                    if showsFilter {
                        lineFilterPicker
                    }
                }
                let shown = shownLines
                if shown.isEmpty {
                    ListSearchEmpty(text: session.language.text("No line matches.", "沒有符合的路線。"))
                }
                ForEach(shown) { line in
                    lineButton(line)
                }
            }
        } header: {
            // Decision 498: not on a short panel, under its own "Lines".
            if !listsLinesFirst || controlsStyle.showsLinesHeading {
                Text("Lines")
            }
        }
    }

    /// A line's row as a button. Decision 481: it opens the line's own
    /// page; on the one form it selects the line below.
    private func lineButton(_ line: ServiceLine) -> some View {
        Button {
            if listsLinesFirst {
                session.openLine(line.id)
            } else {
                session.selectLine(line.id)
            }
        } label: {
            lineRow(line)
        }
        .foregroundStyle(Theme.textPrimary)
        .accessibilityAddTraits(line.id == session.selectedLineID ? .isSelected : [])
        // Decision 486: a short panel's rows closer together and wider,
        // so three or four show.
        .listRowInsets(listsLinesFirst && controlsStyle == .inline ? EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12) : nil)
        .id(Self.rowAnchor(line.id))
    }

    /// Where the list scrolls to show line `id`'s row.
    private static func rowAnchor(_ id: LineID) -> String {
        "line.row.\(id.rawValue)"
    }

    /// Decision 481, later: the short list, in groups by kind (the
    /// player's own, bought, high-speed, freight) once it is long enough
    /// to search and holds more than one kind; else one section.
    @ViewBuilder
    private var listedLines: some View {
        let groups = showsSearch ? session.world.lineGroups(shownLines) : []
        if groups.count > 1 {
            ForEach(groups) { rows in
                lineGroupSection(rows)
            }
        } else {
            linesSection
        }
    }

    private var foldedGroups: Set<LineGroup> {
        LineGroup.folded(from: storedFoldedGroups)
    }

    /// One group of the list, its heading a button that folds it away.
    private func lineGroupSection(_ rows: LineGroupRows) -> some View {
        let folded = foldedGroups.contains(rows.group)
        let language = session.language
        return Section {
            if !folded {
                ForEach(rows.lines) { line in
                    lineButton(line)
                }
            }
        } header: {
            Button {
                var groups = foldedGroups
                if folded {
                    groups.remove(rows.group)
                } else {
                    groups.insert(rows.group)
                }
                withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) {
                    storedFoldedGroups = LineGroup.stored(groups)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: rows.group.title(in: language))
                    Text(verbatim: "\(rows.lines.count)")
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(folded ? -90 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(verbatim: folded ? language.text("Folded", "已收合") : language.text("Shown", "已展開")))
            .accessibilityHint(Text(verbatim: language.text("Shows or hides this group's lines.", "顯示或收合這一組的路線。")))
            .accessibilityIdentifier("lines.group.\(rows.group.rawValue)")
        }
    }

    // Decision 184: a long list can be searched and filtered.
    private var showsSearch: Bool { session.world.lines.count >= ListSearchField.minimumRows }
    private var showsSort: Bool { session.world.lineAccounts != nil && session.world.lines.count > 1 }
    private var showsFilter: Bool { session.world.lines.count > 1 && session.world.lineFilters.count > 1 }

    private var lineSearchField: some View {
        ListSearchField(
            search: $lineSearch,
            prompt: session.language.text("Search lines or stations", "搜尋路線或車站"),
            identifier: "lines.search",
            language: session.language
        )
    }

    /// Decision 481: the search, the filter and the sort, pinned over the
    /// short list; the filter and the sort side by side where they fit.
    @ViewBuilder
    private var listControls: some View {
        if showsSearch || showsSort || showsFilter {
            VStack(alignment: .leading, spacing: 8) {
                if showsSearch {
                    lineSearchField
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        if showsFilter { lineFilterPicker }
                        if showsSort { lineSortMenu(short: false).fixedSize() }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if showsFilter { lineFilterPicker }
                        if showsSort { lineSortMenu(short: false) }
                    }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
            // Where the UI tests find the rows' top (decision 486).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("lines.controls.pinned")
        }
    }

    /// Decision 486: pinned over the list, or one row in it on a panel of
    /// compact height (a phone held sideways).
    private var controlsStyle: LinesListControls {
        .style(compactHeight: verticalSizeClass == .compact)
    }

    /// Decision 486: the search, the filter and the sort in one row at the
    /// top of the list on a short panel, scrolling away with the lines;
    /// the search field opens from its button, over that row.
    @ViewBuilder
    private var inlineControlsSection: some View {
        if showsSearch || showsSort || showsFilter {
            let language = session.language
            let showsField = showsSearch && LinesListControls.inline.showsSearchField(opened: searchOpened, search: lineSearch)
            Section {
                if showsField {
                    HStack(spacing: 8) {
                        lineSearchField
                            .focused($searchFocused)
                        Button {
                            lineSearch = ListSearch()
                            searchFocused = false
                            searchOpened = false
                        } label: {
                            Text(verbatim: LinesListControls.closeSearchTitle(in: language))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("lines.search.close")
                    }
                }
                if showsFilter || showsSort || !showsField {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            inlineControls(showsField: showsField)
                        }
                        // Large text: the sort under the rest.
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 12) {
                                inlineSearchButton(showsField: showsField)
                                if showsFilter { lineFilterMenu }
                            }
                            if showsSort { lineSortMenu(short: true) }
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private func inlineControls(showsField: Bool) -> some View {
        inlineSearchButton(showsField: showsField)
        if showsFilter { lineFilterMenu }
        Spacer(minLength: 0)
        if showsSort { lineSortMenu(short: true) }
    }

    @ViewBuilder
    private func inlineSearchButton(showsField: Bool) -> some View {
        if showsSearch, !showsField {
            Button {
                searchOpened = true
            } label: {
                Label {
                    Text(verbatim: LinesListControls.searchTitle(in: session.language))
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("lines.search.open")
        }
    }

    /// Decision 486: the filter as a menu, its choice on its label (filled
    /// once it hides some lines).
    private var lineFilterMenu: some View {
        let language = session.language
        let filter = session.world.lineFilters.contains(lineFilter) ? lineFilter : .all
        return Menu {
            Picker(selection: $lineFilter) {
                ForEach(session.world.lineFilters, id: \.self) { filter in
                    Text(verbatim: filter.displayName(in: language)).tag(filter)
                }
            } label: {
                Text(verbatim: language.text("Show", "顯示"))
            }
            .pickerStyle(.inline)
        } label: {
            Label {
                Text(verbatim: filter.displayName(in: language))
                    .lineLimit(1)
            } icon: {
                Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: LinesListControls.filterLabel(filter, in: language)))
        .accessibilityIdentifier("lines.filter")
    }

    /// The lines in the order chosen (decision 179), as they were sorted
    /// last (``lineOrder``); a line made since goes last.
    private var sortedLines: [ServiceLine] {
        guard let lineSort, session.world.lineAccounts != nil else { return session.world.lines }
        if let lineOrder { return session.world.lines(keeping: lineOrder) }
        return session.world.lineReports(sortedBy: lineSort).compactMap { session.world.line(id: $0.line) }
    }

    /// Sorts the lines by ``lineSort`` as their reports are now, and keeps
    /// that order.
    private func sortLinesNow() {
        lineOrder = lineSort.map { session.world.lineReports(sortedBy: $0).map(\.line) }
    }

    /// The sorted lines the search and the filter keep (decision 184). A
    /// filter this world no longer offers counts as all lines.
    private var shownLines: [ServiceLine] {
        let filter = session.world.lineFilters.contains(lineFilter) ? lineFilter : .all
        let search = showsSearch ? lineSearch : ListSearch()
        return session.world.lines(sortedLines, matching: search, filter: filter)
    }

    private var lineFilterPicker: some View {
        Picker(selection: $lineFilter) {
            ForEach(session.world.lineFilters, id: \.self) { filter in
                Text(verbatim: filter.displayName(in: session.language)).tag(filter)
            }
        } label: {
            Text(verbatim: session.language.text("Show", "顯示"))
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("lines.filter")
    }

    /// The sort's menu; `short`: its label only the order (decision 486).
    private func lineSortMenu(short: Bool) -> some View {
        let language = session.language
        // Decision 184, later: a menu the ticks leave alone.
        return TickStable(StableKey(lineSort, language, short)) {
            Menu {
                Button {
                    lineSort = nil
                } label: {
                    Label {
                        Text(verbatim: language.text("Made order", "建立順序"))
                    } icon: {
                        Image(systemName: lineSort == nil ? "checkmark" : "")
                    }
                }
                ForEach(LineReportSort.allCases, id: \.self) { order in
                    Button {
                        lineSort = order
                    } label: {
                        Label {
                            Text(verbatim: order.displayName(in: language))
                        } icon: {
                            Image(systemName: lineSort == order ? "checkmark" : "")
                        }
                    }
                }
                if lineSort != nil {
                    Button {
                        sortLinesNow()
                    } label: {
                        Label {
                            Text(verbatim: language.text("Sort Again Now", "立即重新排序"))
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityIdentifier("lines.sortAgain")
                }
            } label: {
                Label {
                    Text(verbatim: LinesListControls.sortTitle(lineSort, short: short, in: language))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .frame(minHeight: short ? 44 : nil)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(verbatim: LinesListControls.sortLabel(lineSort, in: language)))
            .accessibilityIdentifier("lines.sort")
        }
    }

    /// Decision 481: a line's row in two lines. Its badge, name and
    /// trains; then yesterday's riders and profit (red for a loss) beside
    /// its riders' trend line. Its stops in full, fares, peak and trend in
    /// words are on its own page.
    private func lineRow(_ line: ServiceLine) -> some View {
        let color = Palette.lineColor(line.id, custom: line.color)
        let report = line.isFreight ? nil : session.world.lineReport(line.id)
        return HStack(spacing: 10) {
            // Decision 216: the line's code on its badge, where a disc of
            // its colour with its number in white was (white did not read
            // on the pale colours); a ring has its arrows by its name.
            LineCodeBadge(code: LineBadge.codes(for: session.world.lines)[line.id] ?? "", color: color)
                .frame(minWidth: 44, alignment: .leading)

            // Decision 486: two lines where they fit; on a narrow panel
            // the trains go under the name, beside the trend, and the
            // profit under the riders, rather than cut each short.
            ViewThatFits(in: .horizontal) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        lineName(line, report: report)
                        Spacer(minLength: 6)
                        trainsText(line)
                    }
                    if let report {
                        HStack(spacing: 8) {
                            reportText(report, report.compactRowText(in: session.language), id: line.id)
                            Spacer(minLength: 4)
                            sparkline(report, id: line.id)
                        }
                    } else {
                        statusText(line)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        lineName(line, report: report)
                    }
                    if let report {
                        // The trend left out before the trains are cut.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                trainsText(line)
                                Spacer(minLength: 4)
                                sparkline(report, id: line.id)
                            }
                            trainsText(line)
                        }
                    } else {
                        trainsText(line)
                    }
                    if let report {
                        ViewThatFits(in: .horizontal) {
                            reportText(report, report.compactRowText(in: session.language), id: line.id)
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(report.compactRowParts(in: session.language), id: \.self) { part in
                                    Text(verbatim: part)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(report.lostMoneyYesterday ? Theme.error : Theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("line.report.\(line.id.rawValue)")
                        }
                    } else {
                        statusText(line)
                    }
                }
            }
            if listsLinesFirst {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            } else if line.id == session.selectedLineID {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A row's name and its marks: ring, high-speed, needs a look.
    @ViewBuilder
    private func lineName(_ line: ServiceLine, report: LineReport?) -> some View {
        // Decision 168: a high-speed line's name carries a bolt.
        Text(line.name)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        if line.isRing {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2.weight(.bold))
                .accessibilityLabel(Text(verbatim: session.language.text("Ring", "環狀")))
        }
        if line.isHighSpeed {
            Image(systemName: "bolt.fill")
                .font(.caption2.weight(.bold))
                .accessibilityLabel(Text(verbatim: session.language.text("High-speed", "高鐵")))
        }
        // Decision 481, later: a line that needs a look, by a
        // mark and its words, not by colour alone.
        if let attention = LineAttention.label(session.world.lineAttention(line, report: report), in: session.language) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.warning)
                .accessibilityLabel(Text(verbatim: attention))
                .accessibilityIdentifier("line.attention.\(line.id.rawValue)")
        }
    }

    /// TestFlight 56.1: how many trains run it, and how often.
    private func trainsText(_ line: ServiceLine) -> some View {
        Text(verbatim: memo.trainsRowText(line.id, of: session))
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .accessibilityIdentifier("line.trainsRow.\(line.id.rawValue)")
    }

    /// Decision 179: yesterday's riders and profit, red for a loss.
    private func reportText(_ report: LineReport, _ text: String, id: LineID) -> some View {
        Text(verbatim: text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(report.lostMoneyYesterday ? Theme.error : Theme.textSecondary)
            .lineLimit(1)
            .accessibilityIdentifier("line.report.\(id.rawValue)")
    }

    /// Decision 472: its riders over the last days.
    private func sparkline(_ report: LineReport, id: LineID) -> some View {
        LineSparkline(values: report.sparkline)
            .accessibilityIdentifier("line.trend.\(id.rawValue)")
    }

    private func statusText(_ line: ServiceLine) -> some View {
        Text(verbatim: session.world.lineStatusText(line.id, at: session.world.clock.now, in: session.language))
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
    }

    // MARK: - The selected line

    /// Decision 214: the depots the line keeps its trains at (decision
    /// 209), a checklist since a line may have several (decision 221), with
    /// how many stand in them now; shown once there is a depot to choose,
    /// or with Advanced unfolded to say how to get one.
    @ViewBuilder
    private func depotSection(_ line: ServiceLine) -> some View {
        if let row = session.selectedLineDepotRow, !row.chosen.isEmpty || !row.choices.isEmpty || showsAdvanced {
            let language = session.language
            Section {
                if row.choices.isEmpty {
                    Text(verbatim: row.problem ?? "")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(row.choices) { choice in
                        Button {
                            session.toggleSelectedLineDepot(choice.station)
                        } label: {
                            HStack(spacing: 10) {
                                MapGlyph.depot.image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .accessibilityHidden(true)
                                Text(verbatim: choice.name)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer(minLength: 8)
                                if choice.isChosen {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.primary)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(choice.isChosen ? .isSelected : [])
                        .accessibilityIdentifier("line.depot.\(choice.station.rawValue)")
                        // Decision 376: lesson 7's step points at the first.
                        .tutorialPanelTarget(choice.id == row.choices.first?.id ? .lineDepot : nil)
                        .id(choice.id == row.choices.first?.id ? AnyHashable(TutorialTarget.lineDepot) : AnyHashable(choice.id))
                    }
                }
                if row.inDepot > 0 {
                    DepotBadge(text: language.text("\(row.inDepot) in depot", "在庫 \(row.inDepot) 列"))
                        .accessibilityIdentifier("line.inDepot")
                }
            } header: {
                Text(verbatim: language.text("Depots", "所屬機廠"))
            } footer: {
                if !row.choices.isEmpty {
                    Text(verbatim: language.text(
                        "Tick the depots this line's trains go back to at night; standing there they pay only upkeep. With none ticked they stay at the line's ends.",
                        "勾選這條線的列車晚上回哪些機廠，停在機廠只付保養費。都不勾時，列車停在路線兩端。"
                    ))
                }
            }
        }
    }

    /// The selected line's last days (decision 179), and its fares, costs
    /// and why it loses money (decision 194).
    @ViewBuilder
    private func operatingSection(_ line: ServiceLine) -> some View {
        if let report = session.world.lineReport(line.id), !line.isFreight {
            Section {
                LineOperatingCharts(report: report, language: session.language)
                if let diagnosis = lossMemo.diagnosis(line.id, of: session) {
                    // Decision 194, later: a fix beside each reason.
                    let fixes = lossMemo.fixes(line.id, of: session)
                    // Decision 200: unlimited funds are never short.
                    let economy = session.world.economy
                    LineLossCard(
                        diagnosis: diagnosis, language: session.language, session: session, lineName: line.name, fixes: fixes,
                        shortOfMoney: Set(fixes.filter { !economy.canAfford($0.value.cost) }.keys)
                    )
                        .equatable()
                        .tutorialPanelTarget(.lineLoss)
                        .id(TutorialTarget.lineLoss)
                }
                // Decision 301: how riders find the line, and the fix
                // beside its weakest score.
                if let satisfaction = satisfactionMemo.satisfaction(line.id, of: session) {
                    let fix = satisfactionMemo.fix(line.id, of: session)
                    LineSatisfactionCard(
                        satisfaction: satisfaction, language: session.language, session: session, lineName: line.name, fix: fix,
                        shortOfMoney: fix.map { !session.world.economy.canAfford($0.cost) } ?? false
                    )
                        .equatable()
                }
            } header: {
                Text(verbatim: session.language.text("Operations", "營運"))
            } footer: {
                Text(verbatim: session.language.text(
                    "Profit is this line's fares less its own running costs, before interest, buildings and tax.",
                    "損益是這條線的票收減去它自己的營運成本，不含利息、建物與稅。"
                ))
            }
        }
    }

    /// Decision 478: the selected line's riders between each pair of its
    /// stops, both ways.
    @ViewBuilder
    private func loadSection(_ line: ServiceLine) -> some View {
        if !line.isFreight {
            Section {
                LineLoadProfileChart(session: session, line: line)
            } header: {
                Text(verbatim: session.language.text("Riders between stops", "各站間載客"))
            } footer: {
                Text(verbatim: session.language.text(
                    "Riders a day on each stretch, both ways. Tap a row for its fullest hour.",
                    "每一段一天的乘客，兩個方向。點一列看它最擠的時段。"
                ))
            }
        }
    }

    private func lineSection(_ line: ServiceLine) -> some View {
        Section {
            // The reference's line name and colour (`PRESET_COLORS`).
            HStack {
                Button {
                    renamingLine = line.name
                } label: {
                    Label {
                        Text(verbatim: session.language.text("Rename", "更名"))
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
                .accessibilityIdentifier("line.rename")
                // Decision 216: the line's code, typed in an alert.
                let code = LineBadge.codes(for: session.world.lines)[line.id] ?? ""
                Button {
                    editingCode = line.code?.text ?? ""
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: session.language.text("Code", "線號"))
                        LineCodeBadge(code: code, color: Palette.lineColor(line.id, custom: line.color), size: .small)
                    }
                }
                .accessibilityLabel(Text(verbatim: session.language.text("Line code \(code)", "線號 \(code)")))
                .accessibilityIdentifier("line.code")
                Spacer()
                // Decision 184, later: a menu the ticks leave alone.
                let language = session.language
                TickStable(StableKey(line.id, line.color, language, linePalette)) {
                    Menu {
                        Button {
                            session.setSelectedLineColor(nil)
                        } label: {
                            Text(verbatim: language.text("Automatic", "自動"))
                        }
                        ForEach(LineColor.presets, id: \.self) { color in
                            Button {
                                session.setSelectedLineColor(color)
                            } label: {
                                Label {
                                    Text(verbatim: color.nameText(in: language))
                                } icon: {
                                    Image(systemName: line.color == color ? "checkmark.circle.fill" : "circle.fill")
                                }
                                .tint(Palette.color(color))
                            }
                        }
                    } label: {
                        Label {
                            Text(verbatim: language.text("Colour", "顏色"))
                        } icon: {
                            Circle()
                                .fill(Palette.lineColor(line.id, custom: line.color))
                                .frame(width: 16, height: 16)
                        }
                    }
                    .accessibilityIdentifier("line.color")
                }
            }
            .buttonStyle(.borderless)
            Button(line.window == .allDay ? "Run 06:00–24:00 Instead" : "Run All Day") {
                session.setSelectedLineAllDay(line.window != .allDay)
            }
            .accessibilityIdentifier("line.window")
            // Decision 376: lesson 6's guide.
            .tutorialPanelTarget(.serviceHours)
            .id(TutorialTarget.serviceHours)
            // Decision 49: a ring's trains go on from its last stop to the
            // first, half each way round.
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Ring line", isOn: Binding(
                    get: { session.selectedLine?.isRing ?? false },
                    set: { session.setSelectedLineRing($0) }
                ))
                Text("Trains go on from the last stop back to the first: half in the order of the stops, half the other way. They run in pairs.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            // Decision 155: a line that carries freight, offered once the
            // game has a freight yard (or the line already carries freight).
            if line.isFreight || session.world.freight?.facilities.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { session.selectedLine?.isFreight ?? false },
                        set: { session.setSelectedLineFreight($0) }
                    )) {
                        Text(verbatim: session.language.text("Freight line", "貨運路線"))
                    }
                    .disabled(!line.assignedTrains.isEmpty)
                    .accessibilityIdentifier("line.freight")
                    Text(verbatim: session.world.freightLineFooter(line.id, in: session.language))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if session.showsFreight, let hint = session.world.freightYardFirstText(in: session.language) {
                Text(verbatim: hint)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            // Stage C3: the performance its journeys are planned with
            // (Stage W2c), and the journey that gives.
            PerformanceMenu(performance: line.performance, language: session.language, identifier: "line.performance") { performance in
                session.setSelectedLinePerformance(performance)
            }
            .equatable()
            // Decision 168: planned at high speed, a line is a high-speed
            // line: what that pays and fills it with. There is no switch; a
            // high-speed set put on a line that runs nothing else does the
            // same.
            if line.isHighSpeed {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: session.world.highSpeedLineHelp(in: session.language))
                    if let people = session.world.highSpeedLineText(line.id, in: session.language) {
                        Text(verbatim: people)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("line.highSpeedText")
            }
            if let journey = memo.journeyText(line.id, of: session) {
                Text(journey)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            // Stage C2: single or double track between its stops (Stage S1),
            // an advanced detail (decision 196, later); folded, what the
            // line has set among them in one line.
            if showsAdvanced {
                ForEach(Array(memo.trackCountTexts(line.id, of: session).enumerated()), id: \.offset) { _, text in
                    Label(text, systemImage: "road.lanes")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if let summary = AdvancedDetails.lineSummary(line, in: session.language) {
                Label {
                    Text(verbatim: summary)
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("line.advanced.summary")
            }
            capacityWarning(line)
            ForEach(ServiceLevel.allCases, id: \.self) { level in
                if let gap = memo.coverageText(line.id, at: level, of: session) {
                    Label("\(level.title(in: session.language)): \(gap)", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            }
            // Decision 80: MapBuilder's fork, without the trains.
            Button {
                session.duplicateSelectedLine()
            } label: {
                Label("Duplicate Line", systemImage: "plus.square.on.square")
            }
            .accessibilityHint("Copies the line's stops and settings as a new line, without its trains.")
            .accessibilityIdentifier("line.duplicate")
            Button("Remove \(line.name)", role: .destructive) {
                confirmsRemoval = true
            }
            // Decision 327: the line's trains are sold with it.
            .confirmationDialog(
                Text(verbatim: session.language.text("Remove \(line.name)?", "刪除 \(line.name)？")),
                isPresented: $confirmsRemoval,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    session.removeSelectedLine()
                } label: {
                    Text(verbatim: session.language.text("Remove Line", "刪除路線"))
                }
            } message: {
                Text(verbatim: session.lineRemovalText(line.id))
            }
        } header: {
            Text(verbatim: "\(line.name) · \(line.window.displayText(in: session.language))")
        } footer: {
            Text(verbatim: session.world.serviceDay.summaryText(in: session.language))
        }
    }

    // MARK: - The selected line's stops (Stage C2)

    /// The line's stops in order, each with a menu to move it, insert a
    /// station before it or remove it, and a menu to add a stop at the end.
    private func stopsSection(_ line: ServiceLine) -> some View {
        let stations = session.stationMenuChoices
        return Section {
            // Decision 110: the line drawn as its stops, on its colour,
            // with its trains on it (decision 113).
            RouteStrip(
                names: line.stops.map { name(of: $0) },
                color: Palette.lineColor(line.id, custom: line.color),
                mark: Palette.lineMark(line.id, custom: line.color),
                trains: session.world.lineTrainDots(line.id)
            )
            // Decision 206: the line's train diagram, view only.
            Button {
                showsDiagram = true
            } label: {
                Label {
                    Text(verbatim: session.language.text("Train diagram", "運行圖"))
                } icon: {
                    Image(systemName: "chart.xyaxis.line")
                }
            }
            .accessibilityIdentifier("line.trainDiagram")
            // Decision 512: the line's trains on the roster, where they
            // can be moved.
            Button {
                showsRoster = true
            } label: {
                Label {
                    Text(verbatim: session.language.text("Train roster", "列車運用表"))
                } icon: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
            }
            .accessibilityIdentifier("line.trainRoster")
            ForEach(Array(line.stops.enumerated()), id: \.offset) { index, station in
                HStack {
                    Text(verbatim: "\(index + 1). \(name(of: station))")
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    // TestFlight 54.1: menus of every station, built from
                    // their names alone, so a running game's ticks leave an
                    // open one alone.
                    StopMenu(session: session, index: index, count: line.stops.count, stationName: name(of: station), choices: stations)
                        .equatable()
                }
            }
            // Decision 196: the station selected on the map, where it fits.
            if let station = session.selectedStation, !line.stops.contains(station.id) {
                Button {
                    session.addStationToSelectedLine(station.id)
                } label: {
                    Label {
                        Text(verbatim: session.language.text("Add \(station.name) to \(line.name)", "把 \(station.name) 加入 \(line.name)"))
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                }
                .accessibilityIdentifier("line.addSelectedStation")
                // Decision 390: lesson 2's guide.
                .tutorialPanelTarget(.addSelectedStation)
                .id(TutorialTarget.addSelectedStation)
            }
            AddStopMenu(session: session, place: .end(line.stops.count), choices: stations)
                .equatable()
            // Decision 80: MapBuilder's add to line, where the station fits.
            AddStopMenu(session: session, place: .whereItFits, choices: stations)
                .equatable()
            Button {
                session.reverseSelectedLine()
            } label: {
                Label("Reverse Stop Order", systemImage: "arrow.left.arrow.right")
            }
            // Decision 134: without flexible dispatch its trains would stop
            // at the new last stop. Decision 172: with it only a ring with
            // a train running cannot go the other way round.
            .disabled(session.world.flexDispatch ? ringHasRunningTrain(line) : !line.assignedTrains.isEmpty)
            .accessibilityIdentifier("line.reverse")
        } header: {
            Text("Stops")
        } footer: {
            if line.isRing {
                Text("The last stop runs on to the first. Passengers waiting for a trip the line no longer takes leave.")
            } else {
                Text("Patterns keep calling at the same positions in the list. Passengers waiting for a trip the line no longer takes leave.")
            }
            if session.world.flexDispatch {
                if ringHasRunningTrain(line) {
                    Text("A ring cannot be reversed while one of its trains is running.")
                }
            } else if !line.assignedTrains.isEmpty {
                Text("Take the line's trains off it to reverse its stops.")
            }
        }
    }

    /// Decision 196: single track that holds the line to fewer trains
    /// under traffic control, and what to build.
    @ViewBuilder
    private func capacityWarning(_ line: ServiceLine) -> some View {
        if let warning = memo.capacityWarning(line.id, of: session) {
            Label {
                Text(verbatim: warning)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.footnote)
            .foregroundStyle(Theme.warning)
            .accessibilityIdentifier("line.capacityWarning")
        }
    }

    /// Whether `line` is a ring with a train running a service (decision
    /// 172), which `GameWorld.reverseLineStops(_:)` refuses.
    private func ringHasRunningTrain(_ line: ServiceLine) -> Bool {
        line.isRing && line.trains.contains { session.world.train(id: $0)?.execution != nil }
    }

    private func serviceSection(_ summary: LineServiceSummary, of line: ServiceLine) -> some View {
        Section {
            if showsAdvanced {
                routeMenus(line, pattern: summary.pattern)
            }
            Text(summary.callsText)
                .font(.footnote)
            ForEach(summary.levels, id: \.level) { level in
                levelRow(level, pattern: summary.pattern, of: line)
            }
            Text("\(summary.assigned) assigned · \(summary.running) on a trip")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            // Decision 196: the trains on the track without a line, not
            // only the one selected last (which may run for another line).
            AssignTrainMenu(session: session, line: line.id, pattern: summary.pattern, choices: session.unassignedTrainMenuChoices, language: session.language)
                .equatable()
            if let pattern = summary.pattern {
                Button("Remove This Pattern", role: .destructive) {
                    confirmingPanelRemoval = .removePattern(title: summary.title)
                }
                .removalConfirmation(
                    .removePattern(title: summary.title), isPresented: confirming(.removePattern(title: summary.title)),
                    language: session.language
                ) {
                    session.removePatternFromSelectedLine(pattern)
                }
            }
        } header: {
            Text(summary.title)
        }
    }

    /// Each ordered leg can keep its platform flexible, or bind the whole
    /// displayed directed walk. IDs are the map's physical track numbers;
    /// decision 201: the map button beside a leg shows its path on the map
    /// (arrows the way the trains go, the numbers along it), and the
    /// menu's Show on Map First shows a choice before it is picked.
    private func routeMenus(_ line: ServiceLine, pattern: Int?) -> some View {
        let calls = pattern.map { line.patterns[$0].calls } ?? Array(line.stops.indices)
        let outward = line.isRing ? calls + [0] : calls
        let order = line.isRing ? outward + outward.dropLast().reversed() : calls + calls.dropLast().reversed()
        let pairs = Array(zip(order, order.dropFirst()))
        let preferences = pattern.map { line.patterns[$0].routePreferences } ?? line.routePreferences
        let preview = session.routePreview
        return ForEach(pairs.indices, id: \.self) { index in
            let pair = pairs[index]
            let selected = preferences.first { $0.from == pair.0 && $0.to == pair.1 }
            let choices = memo.routeChoices(line.id, from: pair.0, to: pair.1, pattern: pattern, of: session)
            // Decision 184, later: drawn from these values alone, so a
            // running game's ticks leave the open menu alone.
            let choiceTexts = RoutePreview.choiceTexts(choices, in: session.language)
            let selectedText = selected.map { RoutePreview.choiceText($0, in: session.language) }
            let leg = "\(name(of: line.stops[pair.0])) → \(name(of: line.stops[pair.1]))"
            let previewing = session.isPreviewingRoute(from: pair.0, to: pair.1, pattern: pattern)
            let previewText = previewing ? preview?.text(in: session.language) : nil
            TickStable(StableKey(line.id, pattern, pair.0, pair.1, choices, choiceTexts, selectedText, leg, previewing, previewText)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Menu {
                            Button("Automatic route") {
                                session.setSelectedLineRoute(from: pair.0, to: pair.1, preference: nil, pattern: pattern)
                            }
                            ForEach(choices.indices, id: \.self) { choice in
                                Button(choiceTexts[choice]) {
                                    session.setSelectedLineRoute(from: pair.0, to: pair.1, preference: choices[choice], pattern: pattern)
                                }
                                .accessibilityIdentifier("line.route.choice.\(pattern ?? -1).\(pair.0).\(pair.1).\(choice)")
                            }
                            Menu {
                                Button("Automatic route") {
                                    session.previewRoute(from: pair.0, to: pair.1, pattern: pattern, choice: .automatic)
                                }
                                ForEach(choices.indices, id: \.self) { choice in
                                    Button(choiceTexts[choice]) {
                                        session.previewRoute(from: pair.0, to: pair.1, pattern: pattern, choice: .preference(choices[choice]))
                                    }
                                }
                            } label: {
                                Label("Show on Map First", systemImage: "map")
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: leg)
                                if let selectedText { Text(selectedText).font(.caption) }
                                else { Text("Automatic route").font(.caption) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("line.route.\(pattern ?? -1).\(pair.0).\(pair.1)")
                        Button {
                            if previewing {
                                session.endRoutePreview(from: pair.0, to: pair.1, pattern: pattern)
                            } else {
                                session.previewRoute(from: pair.0, to: pair.1, pattern: pattern)
                            }
                        } label: {
                            Image(systemName: previewing ? "map.fill" : "map")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(previewing ? Text("Hide from Map") : Text("Show on Map"))
                        .accessibilityIdentifier("line.route.preview.\(pattern ?? -1).\(pair.0).\(pair.1)")
                    }
                    if let previewText {
                        Text(verbatim: previewText)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("line.route.preview.text")
                    }
                }
            }
            .onAppear {
                // Decision 201, later: the first route menus seen bring up
                // the card about track numbers and routes, once.
                if !routeHintSeen { session.routeMenusDidAppear() }
            }
        }
    }

    /// The trains a service is set to run at one level, with a stepper to
    /// change it (two at a time on a ring, one each way), what it can run
    /// and how far apart, and a menu for a target headway.
    private func levelRow(_ level: LevelServiceSummary, pattern: Int?, of line: ServiceLine) -> some View {
        let counts = pattern.map { line.patterns[$0].trainsInService } ?? line.trainsInService
        let targets = pattern.map { line.patterns[$0].targetHeadways } ?? line.targetHeadways
        let wanted = counts[level.level]
        let target = targets[level.level]
        let step = line.isRing ? 2 : 1
        return VStack(alignment: .leading, spacing: 4) {
            Stepper(
                onIncrement: {
                    session.setSelectedLineTrains(wanted + step, at: level.level, pattern: pattern)
                },
                onDecrement: {
                    session.setSelectedLineTrains(max(0, wanted - step), at: level.level, pattern: pattern)
                }
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(levelSettingText(level.level, trains: wanted, target: target, in: session.language))
                        .font(.subheadline)
                    Text(level.text(in: session.language))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
            // Decision 184, later: a menu the ticks leave alone. Decision
            // 196, later: a target headway is an advanced detail.
            let language = session.language
            if showsAdvanced {
                TickStable(StableKey(level.level, pattern, target, language)) {
                    Menu {
                        Button("By train count") {
                            session.setSelectedLineTargetHeadway(nil, at: level.level, pattern: pattern)
                        }
                        ForEach(Self.targets, id: \.self) { minutes in
                            Button(headwayText(minutes: minutes, in: language)) {
                                session.setSelectedLineTargetHeadway(minutes, at: level.level, pattern: pattern)
                            }
                        }
                    } label: {
                        Label(targetHeadwayText(target, in: language), systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func addPatternSection(_ line: ServiceLine) -> some View {
        // Decision 184, later: menus drawn from the stops' names alone, so
        // a running game's ticks leave an open one alone.
        let names = line.stops.map { name(of: $0) }
        return Section {
            TickStable(StableKey(names, patternFirst)) {
                Picker("From", selection: $patternFirst) {
                    ForEach(names.indices, id: \.self) { index in
                        Text(names[index]).tag(index)
                    }
                }
            }
            TickStable(StableKey(names, patternLast)) {
                Picker("To", selection: $patternLast) {
                    ForEach(names.indices, id: \.self) { index in
                        Text(names[index]).tag(index)
                    }
                }
            }
            Toggle("Non-stop: call at the two ends only", isOn: $patternExpress)
            Button("Add") {
                session.addPatternToSelectedLine(from: patternFirst, to: patternLast, express: patternExpress)
            }
            .accessibilityIdentifier("line.pattern.add")
            // Decision 376: lesson 6's guide.
            .tutorialPanelTarget(.addPattern)
            .id(TutorialTarget.addPattern)
        } header: {
            Text(verbatim: StoppingPatternEntry.title(in: session.language))
        } footer: {
            Text("Services share every stretch of the line: at most one train every 2 minutes each way, the line's own service first.")
        }
    }

    // MARK: - Trains for a line (decision 101)

    /// A line's trains: decision 101's staffing while it has none, then its
    /// headway and trains (TestFlight 56.1). A ring runs each way's trains
    /// and has neither.
    @ViewBuilder
    private func trainsSection(_ line: ServiceLine) -> some View {
        if !line.isRing {
            // Decision 264: trains that cannot pass on single track shared
            // with another line, and the one tap that mends it.
            // Decision 266: in a lesson, once passing loops are unlocked.
            if session.allows(UnlockableTool.passingLoop), let shortfall = session.selectedLinePassingShortfall {
                passingShortfallSection(shortfall)
            }
            if line.trains.isEmpty {
                staffSection(line)
            } else if session.allows(UnlockableTool.addTrain) {
                // Decision 266: a lesson's lines run the train they open
                // with until more trains are taught.
                headwaySection(line)
            }
            // Decision 274: how well its trains fit, and who waits at its ends.
            if let feedback = session.world.lineFeedback(line.id) {
                feedbackSection(feedback)
            }
        }
        modeShiftSection(line)
    }

    /// Decision 332: how many of the line's riders take a scooter or a car
    /// instead, between which stations most do, and what brings most of
    /// them back; nothing without riders switching. A tap opens the card
    /// of the station most of them switch from.
    @ViewBuilder
    private func modeShiftSection(_ line: ServiceLine) -> some View {
        if let modeShift, modeShift.key.line == line.id, let summary = modeShift.value {
            Section {
                let row = ModeShiftRow(summary: summary, text: summary.lineText(in: session.world, language: session.language),
                                       language: session.language)
                if let from = summary.top?.from, let station = session.world.station(id: from) {
                    Button {
                        session.selectStation(from)
                        session.lookAt(station.point)
                        screen.panel = .station
                    } label: {
                        row.foregroundStyle(Theme.textPrimary)
                    }
                    .accessibilityHint(Text(verbatim: session.language.text("Shows the station's details.", "顯示車站的詳細資料。")))
                    .accessibilityIdentifier("line.modeShift")
                } else {
                    row.accessibilityIdentifier("line.modeShift")
                }
            }
        }
    }

    /// What ``modeShift`` is worked out from for the selected line.
    private var modeShiftKey: LineModeShiftKey? {
        session.selectedLineID.map { LineModeShiftKey(world: session.world, line: $0) }
    }

    /// Works out ``modeShift`` for the line as `key` reads it, off the
    /// main actor; kept until what it depends on changes.
    private func workOutModeShift(_ key: LineModeShiftKey?) async {
        guard let key else { return }
        let world = session.world
        let id = key.line
        let value = await Task.detached(priority: .utility) {
            world.lineModeShift(id)
        }.value
        guard !Task.isCancelled else { return }
        modeShift = (key, value)
    }

    /// Decision 274: yesterday's fit of the line's trains, and the people
    /// waiting at each end now as one, two or three people (art style).
    private func feedbackSection(_ feedback: LineFeedback) -> some View {
        let language = session.language
        return Section {
            if let fit = feedback.fit {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: fit.title(in: language))
                            .font(.footnote.weight(.semibold))
                        Text(verbatim: fit.advice(peakPercent: feedback.peakPercent, in: language))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } icon: {
                    Image(systemName: fit == .justRight ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(fit == .justRight ? Theme.success : Theme.warning)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("line.trainFit")
            }
            ForEach(feedback.ends, id: \.station) { end in
                Label {
                    Text(verbatim: language.text(
                        "\(end.name): \(end.waiting) waiting · \(end.demand.title(in: language))",
                        "\(end.name)：\(end.waiting) 人在等・\(end.demand.title(in: language))"
                    ))
                    .font(.footnote)
                } icon: {
                    Image(systemName: Self.peopleSymbol(end.demand))
                        .foregroundStyle(Self.demandColor(end.demand))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("line.endDemand")
            }
        } header: {
            Text(verbatim: language.text("How It Runs", "營運狀況"))
        }
    }

    /// One, two or three people, as the map's crowding marks count them.
    private static func peopleSymbol(_ demand: EndDemand) -> String {
        switch demand {
        case .calm: "person.fill"
        case .busy: "person.2.fill"
        case .crowded: "person.3.fill"
        }
    }

    private static func demandColor(_ demand: EndDemand) -> Color {
        switch demand {
        case .calm: Theme.success
        case .busy: Theme.warning
        case .crowded: Theme.error
        }
    }

    /// Decision 264: the line shares single track with another line's
    /// trains and has no place for them to pass.
    private func passingShortfallSection(_ shortfall: PassingPlaceShortfall) -> some View {
        let language = session.language
        return Section {
            Label {
                Text(verbatim: session.passingShortfallText(shortfall))
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.footnote)
            .foregroundStyle(Theme.warning)
            .accessibilityIdentifier("line.passingShortfall")
            Button {
                session.addPassingLoopToSelectedLine()
            } label: {
                Label {
                    Text(verbatim: language.text("Add a Passing Loop Here", "在這裡加待避線"))
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("line.addPassingLoop")
        }
    }

    /// The headway of a line that runs and its trains (TestFlight 54.1 and
    /// 56.1): choose how often a train comes and tap once; the trains it
    /// lacks are bought and placed where its trips start, those it no
    /// longer needs go to no line (those waiting back to the depot, the
    /// others after their trip), and its targets keep them evenly apart. Shown with Advanced folded too: it is the main
    /// way to run more trains, not a detail.
    private func headwaySection(_ line: ServiceLine) -> some View {
        let language = session.language
        let change = memo.headwayChange(line.id, headway: staffHeadway, of: session)
        let shortfall = memo.trainShortfall(line.id, of: session)
        return Section {
            Text(verbatim: language.text("Now: ", "目前：") + memo.trainsRowText(line.id, of: session))
                .font(.subheadline.monospacedDigit())
                .accessibilityIdentifier("line.headway.now")
            // Decision 264: under simple rules, one more train in one tap,
            // with the passing loop it needs.
            if session.runsLinesForThePlayer {
                Button {
                    session.addTrainToSelectedLine()
                } label: {
                    Label {
                        Text(verbatim: language.text("Add a Train", "加開一列車"))
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ThemeProminentButtonStyle())
                .accessibilityIdentifier("line.addTrain")
                // Decision 376: lesson 3's guide.
                .tutorialPanelTarget(.addTrain)
                .id(TutorialTarget.addTrain)
            }
            if let shortfall {
                Label {
                    Text(verbatim: shortfall.warning(in: language))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.footnote)
                .foregroundStyle(Theme.warning)
                .accessibilityIdentifier("line.trains.shortfall")
                Button {
                    session.fillSelectedLineTrains(shortfall)
                } label: {
                    Label {
                        Text(verbatim: shortfall.title(in: language))
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!session.world.economy.canAfford(shortfall.cost))
                .accessibilityIdentifier("line.trains.fill")
            }
            headwayPicker
            // Decision 309: how two trains or more leave (TestFlight 77.1).
            if line.trains.count >= 2 {
                dispatchPatternMenu(line)
            }
            capacityWarning(line)
            if let change {
                if let limit = change.limitText(in: language) {
                    Text(verbatim: limit)
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .accessibilityIdentifier("line.headway.limit")
                }
                Button {
                    session.changeSelectedLineHeadway(change)
                } label: {
                    Label {
                        Text(verbatim: change.title(in: language))
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ThemeProminentButtonStyle())
                .disabled(change.isUnchanged || !session.world.economy.canAfford(change.cost))
                .accessibilityIdentifier("line.headway.change")
                // Decision 376: lesson 6's guide.
                .tutorialPanelTarget(.headwayChange)
                .id(TutorialTarget.headwayChange)
            }
        } header: {
            Text(verbatim: language.text("Headway and trains", "班距與列車數"))
        } footer: {
            Text(verbatim: language.text(
                "Pick how often a train comes and tap once: missing trains are bought and wait at the first station, extra ones leave the line after their trip, and the rest keep evenly apart.",
                "選班距後按一下：不夠的車會買好在第一站等候，多的車跑完這一趟後離開路線，其餘的保持等間隔。"
            ))
        }
        // The line's own headway, nearest of the choices, when it is
        // selected.
        .task(id: line.id) {
            guard let now = memo.runningHeadway(line.id, of: session) else { return }
            staffHeadway = GameWorld.staffingHeadways.min { abs($0 - now) < abs($1 - now) } ?? staffHeadway
        }
    }

    /// Decision 309: how the line's trains leave, evenly apart, from both
    /// ends at once or in pairs, and a line on what that does. A menu the
    /// ticks leave alone (decision 184, later).
    @ViewBuilder
    private func dispatchPatternMenu(_ line: ServiceLine) -> some View {
        let language = session.language
        let choices = session.selectedLineDispatchChoices
        if !choices.isEmpty {
            let current = LineDispatchPatternChoice(pattern: line.dispatchPattern)
            VStack(alignment: .leading, spacing: 4) {
                TickStable(StableKey(choices, current, language)) {
                    Menu {
                        ForEach(choices) { choice in
                            Button {
                                session.setSelectedLineDispatchPattern(choice.pattern)
                            } label: {
                                if choice == current {
                                    Label(choice.title(in: language), systemImage: "checkmark")
                                } else {
                                    Text(verbatim: choice.title(in: language))
                                }
                            }
                        }
                    } label: {
                        Label {
                            Text(verbatim: language.text("How trains leave: ", "發車方式：") + current.title(in: language))
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("line.dispatchPattern")
                }
                Text(verbatim: session.dispatchPatternFooter(line.dispatchPattern))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// How often a train should come, for ``headwaySection(_:)`` and
    /// ``staffSection(_:)``. Author's report, 2026-10-14: six segments of
    /// "10 min" were cut to "1…" beside the map on a phone held on its
    /// side, so the segments hold the minutes alone and the unit is said
    /// once above them (and to VoiceOver on each).
    private var headwayPicker: some View {
        let language = session.language
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: language.text("Minutes between trains", "班距（分鐘）"))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Picker(selection: $staffHeadway) {
                ForEach(GameWorld.staffingHeadways, id: \.self) { minutes in
                    Text(verbatim: "\(minutes)")
                        .accessibilityLabel(Text(verbatim: language.text("\(minutes) min", "\(minutes) 分")))
                        .tag(minutes)
                }
            } label: {
                Text(verbatim: language.text("A train every", "班距"))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("line.staff.headway")
            .tutorialPanelTarget(.headwayPicker)
        }
    }

    /// How often a train should come on `line`, and what that takes: the
    /// trains its round trip needs, their price, and one button that buys,
    /// places and assigns them.
    private func staffSection(_ line: ServiceLine) -> some View {
        let language = session.language
        let plan = memo.staffingPlan(line.id, headway: staffHeadway, type: staffType, cars: staffCars, of: session)
        return Section {
            headwayPicker
            // Decision 180: the type and the cars of the trains it buys.
            // Decision 184, later: a menu the ticks leave alone.
            let types = session.trainTypeCardChoices
            TickStable(StableKey(types, staffType, language)) {
                Menu {
                    Button {
                        staffType = nil
                    } label: {
                        Text(verbatim: language.text("Line's default", "依路線預設"))
                    }
                    ForEach(types) { candidate in
                        Button {
                            staffType = candidate.id
                        } label: {
                            Text(verbatim: candidate.title)
                            Text(verbatim: candidate.detail ?? "")
                        }
                    }
                } label: {
                    Label {
                        Text(verbatim: staffType.map { Train.typeText($0, in: language) } ?? language.text("Line's default", "依路線預設"))
                    } icon: {
                        Image(systemName: "tram")
                    }
                    .font(.footnote)
                }
                .accessibilityIdentifier("line.staff.type")
            }
            // Decision 224 (2A): the same choice in the showroom, with the
            // train drawn and its price.
            Button {
                showsCatalog = true
            } label: {
                Label {
                    Text(verbatim: language.text("See the train types", "看車種型錄"))
                } icon: {
                    Image(systemName: "tram.circle")
                }
                .font(.footnote)
            }
            .accessibilityIdentifier("line.staff.catalog")
            .sheet(isPresented: $showsCatalog) {
                RollingStockCatalogView(session: session, type: $staffType, cars: $staffCars)
            }
            capacityWarning(line)
            Stepper(value: $staffCars, in: Train.minimumCars...Train.maximumCars) {
                Text(verbatim: language.text("Cars a train: \(staffCars)", "每列節數：\(staffCars)"))
                    .monospacedDigit()
            }
            .accessibilityIdentifier("line.staff.cars")
            if let plan {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: language.text(
                        "Round trip \(plan.roundTripMinutes) min: \(plan.trains) \(plan.trains == 1 ? "train" : "trains"), \(headwayText(minutes: plan.actualHeadway, in: language).lowercased())",
                        "來回 \(plan.roundTripMinutes) 分鐘：需要 \(plan.trains) 列，\(headwayText(minutes: plan.actualHeadway, in: language))"
                    ))
                    .font(.subheadline)
                    Text(verbatim: language.text("Cost \(plan.cost.moneyText)", "費用 \(plan.cost.moneyText)"))
                        .font(.caption)
                        .foregroundStyle(session.world.economy.canAfford(plan.cost) ? Theme.textSecondary : Theme.error)
                    Text(verbatim: language.text(
                        "\(plan.pricePerTrain.moneyText) a train, \(plan.dailyCostPerTrain.moneyText) a day to keep on the line",
                        "每列 \(plan.pricePerTrain.moneyText)，在線上每列每日 \(plan.dailyCostPerTrain.moneyText)"
                    ))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("line.staff.plan")
                Button {
                    session.staffSelectedLine(headway: staffHeadway, type: staffType, cars: staffCars)
                } label: {
                    Label {
                        Text(verbatim: language.text(
                            "Buy \(plan.trains) and Start Service",
                            "購買 \(plan.trains) 列並開始營運"
                        ))
                    } icon: {
                        Image(systemName: "tram.fill")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                // Decision 110: the section's main action, as the theme draws one.
                .buttonStyle(ThemeProminentButtonStyle())
                .disabled(!session.world.economy.canAfford(plan.cost))
                .accessibilityIdentifier("line.staff.start")
                // Decision 125: the tutorial's first line starts here.
                .tutorialPanelTarget(.staffLine)
                .id(TutorialTarget.staffLine)
                // Decision 180: the trains already on the line, into this type and cars.
                if !line.assignedTrains.isEmpty {
                    Button {
                        session.reformSelectedLine(type: staffType ?? plan.type, cars: staffCars)
                    } label: {
                        Label {
                            Text(verbatim: language.text("Re-form the line's trains", "整線改編組"))
                        } icon: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("line.staff.reform")
                    .accessibilityHint(Text(verbatim: language.text(
                        "Trains waiting for their next trip are given the chosen type and cars; trains on a trip are left as they are.",
                        "正在等下一趟的列車換成選擇的車種與節數；正在行駛的列車維持原樣。"
                    )))
                }
            } else {
                Text(verbatim: language.text(
                    "Build track joining the line's stations, with a platform at each, and its trains can run.",
                    "鋪設連接各站的軌道並在每站設置月台後，列車就能行駛。"
                ))
                .font(.footnote)
                .foregroundStyle(Theme.warning)
            }
        } header: {
            Text(verbatim: language.text("Trains for \(line.name)", "\(line.name) 的列車"))
        } footer: {
            Text(verbatim: language.text(
                "The trains wait at the first station and leave one by one. Change counts per time of day below.",
                "列車在第一站等候，依班距逐一發車。各時段的列車數可在下方調整。"
            ))
        }
    }

    // MARK: - New line

    private func names(_ stations: [StationID]) -> String {
        stations.map { name(of: $0) }.joined(separator: " → ")
    }

    /// A new line from its ends (decision 100): the player picks the first
    /// and last stations on the map (and any on the way, to choose where
    /// the line goes), the stations the track passes between are found,
    /// and the player chooses which of them it calls at.
    private var draftSection: some View {
        let language = session.language
        let draft = session.lineDraft
        let stops = session.lineDraftStops
        return Section {
            if draft.isEmpty, let need = session.linesPanelFirstLineNeed {
                // Decision 508: with no line yet, what this form is for, its
                // Pick on Map the button that does it.
                firstLineHeading(need)
            } else if draft.isEmpty {
                Text(verbatim: language.text(
                    "Pick the line's first and last stations. The stations the track passes between them are found for you.",
                    "選路線的起點和終點，沿途經過的車站會依軌道自動找出。"
                ))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            } else {
                // CTM study 4.2 (M0): stops, length, time and price, or
                // why no track joins them.
                LineDraftSummaryRow(session: session)
                LabeledContent {
                    Text(verbatim: names(draft))
                } label: {
                    Text(verbatim: language.text("Picked", "已點選"))
                }
            }
            Button {
                if session.isPickingLineStops {
                    session.stopPickingLineStops()
                } else {
                    session.startPickingLineStops()
                }
            } label: {
                Label {
                    Text(verbatim: session.isPickingLineStops
                         ? language.text("Stop Picking", "停止選站")
                         : language.text("Pick on Map", "在地圖上選站"))
                } icon: {
                    Image(systemName: session.isPickingLineStops ? "hand.tap.fill" : "hand.tap")
                }
            }
            .accessibilityIdentifier("line.draft.pick")
            .tutorialPanelTarget(.pickLineStops)
            .id(Self.draftAnchor)
            Button("Add Selected Station") {
                session.addSelectedStationToLineDraft()
            }
            Button("Remove Last Stop") {
                session.removeLastLineDraftStop()
            }
            .disabled(draft.isEmpty)
            if draft.count >= 2 {
                if let route = session.lineDraftRoute {
                    if route.count > draft.count {
                        stoppingControls(route)
                    }
                } else if let gap = session.lineDraftGap {
                    // Decision 284: why, and what joins them.
                    Text(verbatim: session.world.lineDraftGapText(gap, in: language))
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .accessibilityIdentifier("line.draft.gap")
                }
                // Decision 110: the new line drawn as its stops.
                RouteStrip(names: stops.map { name(of: $0) }, color: Theme.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: names(stops))
                        .font(.subheadline)
                    Text(verbatim: language.text("\(stops.count) stops", "共 \(stops.count) 站"))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("line.draft.stops")
                // Decision 264: under simple rules, the train and the
                // passing loop the line opens with, and their price.
                if let opening = session.lineOpeningPreview {
                    Text(verbatim: opening.contentsText(in: language))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("line.draft.opening")
                }
            }
            Button {
                // Decision 303: the card with its hours and trains first,
                // where the game runs the line's trains.
                session.confirmLineDraft()
            } label: {
                Text("Create Line")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            // Decision 110: the section's main action, as the theme draws one.
            .buttonStyle(ThemeProminentButtonStyle())
            .disabled(stops.count < 2)
            .accessibilityIdentifier("line.draft.create")
            .tutorialPanelTarget(.createLine)
            .id(TutorialTarget.createLine)
            if !draft.isEmpty {
                Button(role: .destructive) {
                    session.clearLineDraft()
                } label: {
                    Text(verbatim: language.text("Clear", "清除"))
                }
            }
        } header: {
            Text("New line")
        }
    }

    /// Which stations along `route` the new line calls at: every one, only
    /// those picked, or the player's own choice, one switch a station (the
    /// ends always on).
    @ViewBuilder
    private func stoppingControls(_ route: [StationID]) -> some View {
        let language = session.language
        Picker(selection: Binding(get: { session.lineDraftStopping }, set: { session.lineDraftStopping = $0 })) {
            ForEach(LineDraftStopping.allCases, id: \.self) { stopping in
                Text(verbatim: stopping.title(in: language)).tag(stopping)
            }
        } label: {
            Text(verbatim: language.text("Calls at", "停靠方式"))
        }
        .pickerStyle(.inline)
        .accessibilityIdentifier("line.draft.stopping")
        if session.lineDraftStopping == .custom {
            ForEach(Array(route.enumerated()), id: \.offset) { index, station in
                let isEnd = index == 0 || index == route.count - 1
                Toggle(isOn: Binding(
                    get: { isEnd || !session.lineDraftSkipped.contains(station) },
                    set: { _ in session.toggleLineDraftStop(station) }
                )) {
                    Text(verbatim: name(of: station))
                }
                .disabled(isEnd)
            }
        }
    }
}

private extension View {
    func lineModals(of panel: LinesPanel, active: Bool) -> some View {
        panel.modals(self, active: active)
    }
}

/// Decision 194: a line's fares and four running costs over its report's
/// days, as bars, and for a line that lost money why: at most two reasons,
/// each with the figure that shows it. An equatable view of the diagnosis,
/// which only a command or a new game day changes: the game's ticks leave
/// it alone.
///
/// Decision 194, later: beside each reason the change that answers it
/// (``LineLossFix``), asked before it is made; one the balance does not
/// pay for is off, and says so.
extension LinesPanel {
    /// The selected line's rename and code alerts and its train diagram,
    /// on the page that shows its sections (decision 481); `active` false
    /// leaves them to the other page.
    fileprivate func modals(_ content: some View, active: Bool) -> some View {
        content
            .renameAlert(
                title: session.language.text("Rename Line", "路線更名"),
                name: active ? $renamingLine : .constant(nil),
                language: session.language
            ) { name in
                session.renameSelectedLine(to: name)
            }
            .lineCodeAlert(code: active ? $editingCode : .constant(nil), language: session.language) { code in
                session.setSelectedLineCode(code)
            }
            // Decision 206: the train diagram over the whole screen.
            .fullScreenCover(isPresented: active ? $showsDiagram : .constant(false)) {
                if let id = session.selectedLineID {
                    TrainDiagramView(session: session, line: id)
                }
            }
            .fullScreenCover(isPresented: active ? $showsRoster : .constant(false)) {
                if let id = session.selectedLineID {
                    TrainRosterView(session: session, line: id)
                }
            }
    }

    /// Whether the panel removal `removal` is the one asking first.
    fileprivate func confirming(_ removal: RemovalConfirmation) -> Binding<Bool> {
        Binding(
            get: { confirmingPanelRemoval == removal },
            set: { if !$0, confirmingPanelRemoval == removal { confirmingPanelRemoval = nil } }
        )
    }
}

private struct LineLossCard: View, Equatable {
    let diagnosis: LineLossDiagnosis
    let language: DisplayLanguage
    let session: GameSession
    let lineName: String
    let fixes: [LineLossReason.Kind: LineLossFix]
    /// The reasons whose fix the balance does not pay for.
    let shortOfMoney: Set<LineLossReason.Kind>
    /// The fix whose confirmation is open.
    @State private var asking: LineLossFix?

    nonisolated static func == (lhs: LineLossCard, rhs: LineLossCard) -> Bool {
        lhs.diagnosis == rhs.diagnosis && lhs.language == rhs.language && lhs.session === rhs.session
            && lhs.lineName == rhs.lineName && lhs.fixes == rhs.fixes && lhs.shortOfMoney == rhs.shortOfMoney
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: diagnosis.spanText(in: language))
                .font(.caption.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(diagnosis.bars(in: language)) { bar in
                    barRow(bar)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("line.costs")
            // NEXT_PRIORITIES §22.17: the last seven days' punctuality,
            // with Taiwan Railway's real year beside it.
            if let weekly = diagnosis.weeklyPunctuality {
                Text(verbatim: weekly.text(in: language))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("line.weeklyPunctuality")
            }
            // Decision 207: with realistic operation, how many trips were
            // on time.
            if let punctuality = diagnosis.punctualityText(in: language) {
                Text(verbatim: punctuality)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("line.punctuality")
            }
            if diagnosis.isLosing {
                Text(verbatim: language.text("Why it loses money", "為什麼虧錢"))
                    .font(.caption.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(diagnosis.reasons, id: \.self) { reason in
                    reasonRow(reason)
                }
                if let text = diagnosis.noReasonText(in: language) {
                    Text(verbatim: text)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("line.loss")
        .confirmationDialog(
            Text(verbatim: asking.map { $0.kind.title(in: language) } ?? ""),
            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
            titleVisibility: .visible,
            presenting: asking
        ) { fix in
            Button {
                session.applyLineLossFix(fix, to: diagnosis.line)
            } label: {
                Text(verbatim: fix.title(in: language))
            }
            Button(role: .cancel) {
            } label: {
                Text(verbatim: language.text("Cancel", "取消"))
            }
        } message: { fix in
            Text(verbatim: fix.question(on: lineName, in: language))
        }
    }

    /// The item and its amount, over a bar as long as the amount next to
    /// the largest of the five: green for the fares, red for a cost.
    private func barRow(_ bar: LineLossDiagnosis.Bar) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: bar.title)
                    .font(bar.isFares ? Font.footnote.weight(.semibold) : Font.footnote)
                Spacer(minLength: 8)
                Text(verbatim: bar.amount.moneyText)
                    .font(.footnote.monospacedDigit())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.chip)
                    Capsule()
                        .fill(bar.isFares ? Theme.success : Theme.error)
                        .frame(width: max(CGFloat(bar.permille > 0 ? 3 : 0), proxy.size.width * CGFloat(bar.permille) / 1_000))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: bar.text))
        .accessibilityIdentifier("line.cost.\(bar.id)")
    }

    private func reasonRow(_ reason: LineLossReason) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            reasonLabel(reason)
            if let fix = fixes[reason.kind] {
                // The tutorial points at the first fix shown (decision 188).
                if reason.kind == diagnosis.reasons.first(where: { fixes[$0.kind] != nil })?.kind {
                    fixButton(fix)
                        .tutorialPanelTarget(.lineLossFix)
                } else {
                    fixButton(fix)
                }
            }
        }
    }

    /// The fix's button, at least 44 points each way; off, with the
    /// reason under it, when the money does not reach.
    private func fixButton(_ fix: LineLossFix) -> some View {
        let short = shortOfMoney.contains(fix.kind)
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                asking = fix
            } label: {
                Text(verbatim: fix.title(in: language))
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(short)
            .accessibilityHint(Text(verbatim: short ? fix.shortOfMoneyText(in: language) : ""))
            .accessibilityIdentifier("line.loss.fix.\(fix.kind.rawValue)")
            if short {
                Text(verbatim: fix.shortOfMoneyText(in: language))
                    .font(.caption)
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 28)
    }

    private func reasonLabel(_ reason: LineLossReason) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: reason.title(in: language))
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: reason.detail(in: language))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: Self.symbol(of: reason.kind))
                .foregroundStyle(Theme.warning)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("line.loss.reason.\(reason.kind.rawValue)")
    }

    private static func symbol(of kind: LineLossReason.Kind) -> String {
        switch kind {
        case .tooManyTrains: "tram.fill"
        case .longHeadway: "clock"
        case .emptyRuns: "arrow.uturn.left"
        case .lowLoad: "person.2"
        }
    }
}

/// Decision 301: how riders find a line, three scores out of 100 each
/// with a face, the figure it comes from, and for the weakest one below good
/// what helps; beside it decision 194's one-tap fix, asked before it is made.
/// An equatable view, which only a command or a new game day changes.
private struct LineSatisfactionCard: View, Equatable {
    let satisfaction: LineSatisfaction
    let language: DisplayLanguage
    let session: GameSession
    let lineName: String
    let fix: LineLossFix?
    let shortOfMoney: Bool
    @State private var asking: LineLossFix?

    nonisolated static func == (lhs: LineSatisfactionCard, rhs: LineSatisfactionCard) -> Bool {
        lhs.satisfaction == rhs.satisfaction && lhs.language == rhs.language && lhs.session === rhs.session
            && lhs.lineName == rhs.lineName && lhs.fix == rhs.fix && lhs.shortOfMoney == rhs.shortOfMoney
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: satisfaction.spanText(in: language))
                .font(.caption.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let text = satisfaction.waitingText(in: language) {
                Text(verbatim: text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(satisfaction.items) { item in
                itemRow(item, weakest: item.aspect == satisfaction.weakest?.aspect)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("line.satisfaction")
        .confirmationDialog(
            Text(verbatim: asking.map { $0.title(in: language) } ?? ""),
            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
            titleVisibility: .visible,
            presenting: asking
        ) { fix in
            Button {
                session.applyLineLossFix(fix, to: satisfaction.line)
            } label: {
                Text(verbatim: fix.title(in: language))
            }
            Button(role: .cancel) {
            } label: {
                Text(verbatim: language.text("Cancel", "取消"))
            }
        } message: { fix in
            Text(verbatim: fix.question(on: lineName, in: language))
        }
    }

    private func itemRow(_ item: LineSatisfaction.Item, weakest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                face(item.grade)
                Text(verbatim: item.title(in: language))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(verbatim: item.scoreText(in: language))
                    .font(item.score == nil ? Font.footnote : Font.footnote.monospacedDigit().weight(.semibold))
                    .foregroundStyle(item.score == nil ? Theme.textSecondary : Theme.textPrimary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: item.spokenText(in: language)))
            if let score = item.score {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.chip)
                        Capsule()
                            .fill(Self.colour(of: item.grade))
                            .frame(width: max(CGFloat(score > 0 ? 3 : 0), proxy.size.width * CGFloat(score) / 100))
                    }
                }
                .frame(height: 6)
                .padding(.leading, 28)
                .accessibilityHidden(true)
            }
            Text(verbatim: item.detail(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 28)
                .accessibilityHidden(true)
            if weakest, let advice = item.advice(in: language) {
                Text(verbatim: advice)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 28)
                if let fix, item.aspect.fixKind != nil {
                    fixButton(fix)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("line.satisfaction.\(item.aspect.rawValue)")
    }

    /// The face of `grade` (our own drawings, decision 301), or a dash's
    /// circle before there is a score.
    @ViewBuilder
    private func face(_ grade: LineSatisfaction.Grade?) -> some View {
        Group {
            switch grade {
            case .good: Image("RatingGood").renderingMode(.template).resizable()
            case .fair: Image("RatingFair").renderingMode(.template).resizable()
            case .poor: Image("RatingPoor").renderingMode(.template).resizable()
            case nil: Image(systemName: "circle.dashed").resizable()
            }
        }
        .scaledToFit()
        .frame(width: 20, height: 20)
        .foregroundStyle(Self.colour(of: grade))
        .accessibilityHidden(true)
    }

    private static func colour(of grade: LineSatisfaction.Grade?) -> Color {
        switch grade {
        case .good: Theme.success
        case .fair: Theme.warning
        case .poor: Theme.error
        case nil: Theme.textSecondary
        }
    }

    /// The fix's button, at least 44 points each way; off, with the
    /// reason under it, when the money does not reach.
    private func fixButton(_ fix: LineLossFix) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                asking = fix
            } label: {
                Text(verbatim: fix.title(in: language))
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(shortOfMoney)
            .accessibilityHint(Text(verbatim: shortOfMoney ? fix.shortOfMoneyText(in: language) : ""))
            .accessibilityIdentifier("line.satisfaction.fix")
            if shortOfMoney {
                Text(verbatim: fix.shortOfMoneyText(in: language))
                    .font(.caption)
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 28)
    }
}

/// A stop's menu on the selected line: move it, insert a station before
/// it, or remove it. An equatable view of the stop and the stations' names:
/// the game loop replaces the world every tick, and an open native menu
/// drawn again is rebuilt, back to its top (TestFlight 54.1).
private struct StopMenu: View, Equatable {
    let session: GameSession
    let index: Int
    let count: Int
    let stationName: String
    let choices: [MenuChoice<StationID>]
    /// Whether Remove Stop is asking first (UI review 2026-10-28, A).
    @State private var confirmsRemoval = false

    nonisolated static func == (lhs: StopMenu, rhs: StopMenu) -> Bool {
        lhs.session === rhs.session && lhs.index == rhs.index && lhs.count == rhs.count
            && lhs.stationName == rhs.stationName && lhs.choices == rhs.choices
    }

    var body: some View {
        Menu {
            Button("Move Up") {
                session.moveStopOfSelectedLine(at: index, by: -1)
            }
            .disabled(index == 0)
            Button("Move Down") {
                session.moveStopOfSelectedLine(at: index, by: 1)
            }
            .disabled(index == count - 1)
            Menu("Insert Before") {
                ForEach(choices) { station in
                    Button(station.title) {
                        session.insertStopIntoSelectedLine(station.id, at: index)
                    }
                }
            }
            Button("Remove Stop", role: .destructive) {
                confirmsRemoval = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 32)
        }
        .accessibilityLabel("Edit stop \(index + 1), \(stationName)")
        .removalConfirmation(.removeStop(station: stationName), isPresented: $confirmsRemoval, language: session.language) {
            session.removeStopFromSelectedLine(at: index)
        }
    }
}

/// The trains on the track without a line, to give one to a service of
/// line `line` (decision 196). Equatable, as ``StopMenu``; with none, it
/// says how to get one.
private struct AssignTrainMenu: View, Equatable {
    let session: GameSession
    let line: LineID
    let pattern: Int?
    let choices: [MenuChoice<TrainID>]
    let language: DisplayLanguage

    nonisolated static func == (lhs: AssignTrainMenu, rhs: AssignTrainMenu) -> Bool {
        lhs.session === rhs.session && lhs.line == rhs.line && lhs.pattern == rhs.pattern
            && lhs.choices == rhs.choices && lhs.language == rhs.language
    }

    var body: some View {
        if choices.isEmpty {
            Text(verbatim: language.text(
                "Every train on the track has a line. Buy one and place it at a station, or take one off its line, to assign it here.",
                "軌道上的列車都已有路線。買一列放到車站，或把一列移出原路線，就能配屬到這裡。"
            ))
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        } else {
            Menu {
                ForEach(choices) { train in
                    Button(train.title) {
                        session.assignTrain(train.id, toLine: line, pattern: pattern)
                    }
                }
            } label: {
                Label {
                    Text(verbatim: language.text("Assign a Train…", "配屬列車…"))
                } icon: {
                    Image(systemName: "tram.fill")
                }
            }
            .accessibilityIdentifier("line.assignTrain.\(pattern ?? -1)")
        }
    }
}

/// A menu of every station to add to the selected line, at the end or
/// where it fits (decision 80, MapBuilder's add to line). Equatable, as
/// ``StopMenu``.
private struct AddStopMenu: View, Equatable {
    enum Place: Equatable {
        /// After the last of the line's `count` stops.
        case end(Int)
        case whereItFits
    }

    let session: GameSession
    let place: Place
    let choices: [MenuChoice<StationID>]

    nonisolated static func == (lhs: AddStopMenu, rhs: AddStopMenu) -> Bool {
        lhs.session === rhs.session && lhs.place == rhs.place && lhs.choices == rhs.choices
    }

    var body: some View {
        switch place {
        case let .end(count):
            Menu {
                buttons { session.insertStopIntoSelectedLine($0, at: count) }
            } label: {
                Label("Add Stop at the End", systemImage: "plus.circle")
            }
        case .whereItFits:
            Menu {
                buttons { session.addStationToSelectedLine($0) }
            } label: {
                Label("Add Stop Where It Fits", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .accessibilityIdentifier("line.addStopWhereItFits")
        }
    }

    /// A button for every station, calling `choose` with its ID.
    private func buttons(_ choose: @escaping @MainActor (StationID) -> Void) -> some View {
        ForEach(choices) { station in
            Button(station.title) {
                choose(station.id)
            }
        }
    }
}

/// An alert to type a new name in, shown while `name` is not `nil`: the
/// rename button calls `rename` with what was typed. Kept out of the
/// panel's redraw on every tick (``TickStable``), so the field is not
/// rebuilt under the player's finger and keeps its keyboard (TestFlight
/// 60.1). So `rename` must depend on nothing but the key: both panels'
/// rename whichever line or station is selected when it is pressed.
private struct RenameAlert: ViewModifier {
    let title: String
    @Binding var name: String?
    let language: DisplayLanguage
    let rename: (String) -> Void

    func body(content: Content) -> some View {
        content.background {
            TickStable(StableKey(title, name, language)) {
                alert
            }
        }
    }

    private var alert: some View {
        Color.clear.alert(
            Text(verbatim: title),
            isPresented: Binding(get: { name != nil }, set: { if !$0 { name = nil } })
        ) {
            TextField(text: Binding(get: { name ?? "" }, set: { name = $0 })) {
                Text(verbatim: language.text("Name", "名稱"))
            }
            .accessibilityIdentifier("rename.field")
            Button {
                if let typed = name { rename(typed) }
                name = nil
            } label: {
                Text(verbatim: language.text("Rename", "更名"))
            }
            Button(role: .cancel) {
                name = nil
            } label: {
                Text(verbatim: language.text("Cancel", "取消"))
            }
        }
    }
}

/// Decision 216: an alert to type a line's code in, shown while `code` is
/// not `nil`; blank asks for the app's own code again. Kept out of the
/// panel's redraw on every tick as ``RenameAlert`` is, so the field keeps
/// its keyboard; `save` sets whichever line is selected when it is pressed.
private struct LineCodeAlert: ViewModifier {
    @Binding var code: String?
    let language: DisplayLanguage
    let save: (String) -> Void

    func body(content: Content) -> some View {
        content.background {
            TickStable(StableKey(code, language)) {
                alert
            }
        }
    }

    private var alert: some View {
        Color.clear.alert(
            Text(verbatim: language.text("Line Code", "線號")),
            isPresented: Binding(get: { code != nil }, set: { if !$0 { code = nil } })
        ) {
            TextField(text: Binding(get: { code ?? "" }, set: { code = $0 })) {
                Text(verbatim: language.text("Automatic", "自動"))
            }
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .accessibilityIdentifier("lineCode.field")
            Button {
                if let typed = code { save(typed) }
                code = nil
            } label: {
                Text(verbatim: language.text("Save", "儲存"))
            }
            Button(role: .cancel) {
                code = nil
            } label: {
                Text(verbatim: language.text("Cancel", "取消"))
            }
        } message: {
            Text(verbatim: language.text(
                "One to three letters A–Z or digits, such as BL or R2. Leave it empty for a code from the line's colour.",
                "一到三個英文字母或數字，例如 BL、R2。留空就依路線顏色自動給。"
            ))
        }
    }
}

extension View {
    /// Decision 216: a line code alert (see `LineCodeAlert`).
    func lineCodeAlert(code: Binding<String?>, language: DisplayLanguage, save: @escaping (String) -> Void) -> some View {
        modifier(LineCodeAlert(code: code, language: language, save: save))
    }

    /// A rename alert (see `RenameAlert`).
    func renameAlert(title: String, name: Binding<String?>, language: DisplayLanguage,
                     rename: @escaping (String) -> Void) -> some View {
        modifier(RenameAlert(title: title, name: name, language: language, rename: rename))
    }
}

/// What a line's ``GameWorld/lineModeShift(_:)`` is worked out from: the
/// line and what every station's day reads (``RidershipInputs``).
struct LineModeShiftKey: Equatable {
    let line: LineID
    let inputs: RidershipInputs

    init(world: GameWorld, line: LineID) {
        self.line = line
        inputs = RidershipInputs(world: world)
    }
}

/// Decision 472: a line's row's small trend line of riders over its last
/// days, beside a bar of how full its fullest train was (the trains' load
/// bar: ink, red only over 100%), and the week's change in words. The
/// trend line is a picture of the words beside it, so VoiceOver reads the
/// words; the selected line's charts below have the audio graph.
private struct LineTrendStrip: View {
    let report: LineReport
    let language: DisplayLanguage

    var body: some View {
        let sparkline = report.sparkline
        let gauge = report.loadGauge
        if !sparkline.isEmpty || gauge != nil {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    if !sparkline.isEmpty {
                        LineSparkline(values: sparkline)
                    }
                    if let gauge {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Theme.panelBorder)
                                Capsule()
                                    .fill(gauge.isOverload ? Theme.error : Theme.textPrimary)
                                    .frame(width: proxy.size.width * gauge.fraction)
                            }
                        }
                        .frame(height: 5)
                        .frame(maxWidth: 120)
                        .accessibilityHidden(true)
                    }
                }
                let words = [report.trendText(in: language), gauge?.text(in: language)].compactMap { $0 }
                if !words.isEmpty {
                    Text(verbatim: words.joined(separator: " · "))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Decision 472: a line's riders over its last days as a small trend line,
/// a picture of words said beside it (VoiceOver reads those); nothing with
/// fewer than two days. Decision 481: alone on a row of the short list.
private struct LineSparkline: View {
    let values: [Int64]

    /// Not literals: a literal here would be a string to translate.
    private static let dayAxis = "Day"
    private static let ridersAxis = "Riders"

    var body: some View {
        if !values.isEmpty {
            Chart(Array(values.enumerated()), id: \.offset) { day in
                LineMark(x: .value(Self.dayAxis, day.offset), y: .value(Self.ridersAxis, day.element))
                    .foregroundStyle(Theme.chartBlue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...Double(max(values.max() ?? 0, 1)))
            .frame(width: 64, height: 18)
            .accessibilityHidden(true)
        }
    }
}
