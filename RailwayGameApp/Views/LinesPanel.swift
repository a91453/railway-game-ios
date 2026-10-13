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
    /// Closes it (decision 106: shown beside the map, not presented, so
    /// the environment's dismiss would do nothing).
    @Environment(GameScreenState.self) private var screen
    @State private var patternFirst = 0
    @State private var patternLast = 1
    @State private var patternExpress = false
    /// The name being typed for the selected line, while its rename alert
    /// is up.
    @State private var renamingLine: String?
    /// How often a train should come, for the selected line's trains
    /// (decision 101).
    @State private var staffHeadway: Int64 = 10
    /// The type and the cars of the trains a line is staffed with or re-formed
    /// into (decision 180); `nil`: the line's own pick.
    @State private var staffType: TrainType?
    @State private var staffCars = 1
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
    /// Decision 184: the name typed to find a line, and which lines show.
    @State private var lineSearch = ListSearch()
    @State private var lineFilter: LineFilter = .all
    /// Decision 196: whether the new line's form shows while the lines
    /// come first.
    @State private var showsNewLine = false
    /// Decision 196, later: the player's choice for the "Advanced" switch,
    /// or `nil` for the device's default (folded on a phone).
    @AppStorage("linesPanel.showsAdvanced") private var storedShowsAdvanced: Bool?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Target headways offered in the menu, in minutes.
    private static let targets: [Int64] = [5, 10, 15, 20, 30, 60]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    if listsLinesFirst {
                        // Decision 196 (TestFlight 54.1): with lines made and
                        // none being picked, the lines and the selected
                        // line's stops come first, a new line is one row,
                        // and the switches for every line go last.
                        linesSection
                        advancedSection
                        newLineRow
                        if let line = session.selectedLine {
                            if line.trains.isEmpty, !line.isRing {
                                staffSection(line)
                            }
                            stopsSection(line)
                            lineSection(line)
                            operatingSection(line)
                            servicesSections(line)
                        }
                        if showsAdvanced {
                            trafficSection
                            serviceDaySection
                        }
                    } else {
                        // Decision 100: a new line first, where the panel beside
                        // the map (decision 106) shows it while stations are
                        // picked on the map.
                        draftSection
                        // Decision 101: a line without trains offers them next.
                        if let line = session.selectedLine, line.trains.isEmpty, !line.isRing {
                            staffSection(line)
                        }
                        if showsAdvanced {
                            trafficSection
                            serviceDaySection
                        }
                        linesSection
                        advancedSection
                        if let line = session.selectedLine {
                            lineSection(line)
                            operatingSection(line)
                            stopsSection(line)
                            servicesSections(line)
                        }
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
                        withAnimation { proxy.scrollTo(target, anchor: .center) }
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
            .renameAlert(
                title: session.language.text("Rename Line", "路線更名"),
                name: $renamingLine,
                language: session.language
            ) { name in
                session.renameSelectedLine(to: name)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        screen.panel = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                StatusBanner(session: session, announces: false)
            }
            // Decision 196: a line made from the unfolded form folds it again.
            .onChange(of: session.world.lines.count) { showsNewLine = false }
            .onAppear { sortLinesNow() }
            .onChange(of: lineSort) { sortLinesNow() }
            // Taps on the map select again once the panel is closed.
            .onDisappear {
                session.stopPickingLineStops()
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
        !session.world.lines.isEmpty && !session.isPickingLineStops && session.lineDraft.isEmpty && session.tutorial == nil
    }

    /// The new line's form folded into one row while the lines come first
    /// (decision 196); picking a station puts it back at the top.
    @ViewBuilder
    private var newLineRow: some View {
        Section {
            Button {
                withAnimation { showsNewLine.toggle() }
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
        if showsNewLine {
            draftSection
        }
    }

    /// Decision 196, later (TestFlight 54.1 #6): whether the panel shows
    /// the service day, stopping patterns, the tracks each leg takes,
    /// target headways and the network's switches. Folded, their rules run
    /// as they were set; only the panel leaves them out.
    private var showsAdvanced: Bool {
        AdvancedDetails.isShown(
            stored: storedShowsAdvanced,
            roomy: horizontalSizeClass == .regular && verticalSizeClass == .regular
        )
    }

    /// The "Advanced" switch, under the lines where it is seen at once;
    /// folded, what the network has set there in one line.
    private var advancedSection: some View {
        Section {
            Toggle(isOn: Binding(get: { showsAdvanced }, set: { storedShowsAdvanced = $0 })) {
                Label {
                    Text(verbatim: session.language.text("Advanced", "進階"))
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
            .accessibilityIdentifier("lines.advanced")
            .accessibilityHint(Text(verbatim: session.language.text(
                "Shows the service day, stopping patterns, the tracks each leg takes, target headways and traffic control. Hidden, they keep working as set.",
                "顯示時段、停靠模式、各段股道、目標班距與行車控制。收起時，這些設定照常運作。"
            )))
            if !showsAdvanced {
                Text(verbatim: AdvancedDetails.networkSummary(of: session.world, in: session.language))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("lines.advanced.summary")
            }
        }
    }

    private func servicesSections(_ line: ServiceLine) -> some View {
        Group {
            ForEach(memo.serviceSummaries(line.id, of: session), id: \.pattern) { summary in
                // Decision 196, later: a stopping pattern is an advanced detail.
                if summary.pattern == nil || showsAdvanced {
                    serviceSection(summary, of: line)
                }
            }
            // A ring has no patterns.
            if !line.isRing, showsAdvanced {
                addPatternSection(line)
            }
        }
    }

    private func name(of station: StationID) -> String {
        session.world.station(id: station)?.name ?? "#\(station.rawValue)"
    }

    // MARK: - Traffic control

    /// Traffic control, read from the world. Turning it on is refused while
    /// two trains need the same track: the status banner says which, and
    /// the switch stays off.
    private var trafficSection: some View {
        Section {
            Toggle("Traffic control", isOn: Binding(
                get: { session.world.isTrafficControlEnabled },
                set: { session.setTrafficControl($0) }
            ))
            Toggle("Network passenger routes", isOn: Binding(
                get: { session.world.passengerRoutingMode == .network },
                set: { session.setPassengerRoutingMode($0 ? .network : .direct) }
            ))
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
                session.resetServiceDay()
            } label: {
                Label("Standard Day", systemImage: "arrow.counterclockwise")
            }
            .disabled(day == .standard)
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
                Text("No lines yet. Pick stations under New Line to create one.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                if session.world.lineAccounts != nil, session.world.lines.count > 1 {
                    lineSortMenu
                }
                // Decision 184: a long list can be searched and filtered.
                if session.world.lines.count >= ListSearchField.minimumRows {
                    ListSearchField(
                        search: $lineSearch,
                        prompt: session.language.text("Search lines or stations", "搜尋路線或車站"),
                        identifier: "lines.search",
                        language: session.language
                    )
                }
                if session.world.lines.count > 1, session.world.lineFilters.count > 1 {
                    lineFilterPicker
                }
                let shown = shownLines
                if shown.isEmpty {
                    ListSearchEmpty(text: session.language.text("No line matches.", "沒有符合的路線。"))
                }
                ForEach(shown) { line in
                    Button {
                        session.selectLine(line.id)
                    } label: {
                        lineRow(line)
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(line.id == session.selectedLineID ? .isSelected : [])
                }
            }
        } header: {
            Text("Lines")
        }
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
        let search = session.world.lines.count >= ListSearchField.minimumRows ? lineSearch : ListSearch()
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

    private var lineSortMenu: some View {
        let language = session.language
        // Decision 184, later: a menu the ticks leave alone.
        return TickStable(StableKey(lineSort, language)) {
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
                    Text(verbatim: language.text("Sort: \(lineSort?.displayName(in: language) ?? language.text("Made order", "建立順序"))", "排序：\(lineSort?.displayName(in: language) ?? language.text("Made order", "建立順序"))"))
                } icon: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            .accessibilityIdentifier("lines.sort")
        }
    }

    private func lineRow(_ line: ServiceLine) -> some View {
        let status = session.world.lineStatusText(line.id, at: session.world.clock.now, in: session.language)
        let color = Palette.lineColor(line.id, custom: line.color)
        return HStack(spacing: 10) {
            ZStack {
                // Theme: kept for good. The badge is the line's own colour
                // (the player's or the default), with white on it.
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)
                if line.isRing {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text(verbatim: "\(line.id.rawValue)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                // Decision 168: a high-speed line's name carries a bolt.
                HStack(spacing: 4) {
                    Text(line.name)
                        .font(.subheadline.weight(.semibold))
                    if line.isHighSpeed {
                        Image(systemName: "bolt.fill")
                            .font(.caption2.weight(.bold))
                            .accessibilityLabel(Text(verbatim: session.language.text("High-speed", "高鐵")))
                    }
                }
                Text(verbatim: "\(line.stops.map { name(of: $0) }.joined(separator: " – ")) · \(status)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                // Decision 179: yesterday's riders, fares, profit and peak.
                if let report = session.world.lineReport(line.id), !line.isFreight {
                    Text(verbatim: report.rowText(in: session.language))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(report.yesterday.map { $0.profit < .zero } == true ? Theme.error : Theme.textSecondary)
                        .accessibilityIdentifier("line.report.\(line.id.rawValue)")
                }
            }
            Spacer(minLength: 8)
            if line.id == session.selectedLineID {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - The selected line

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
            } header: {
                Text(verbatim: session.language.text("Operations", "營運"))
            } footer: {
                Text(verbatim: session.language.text(
                    "Profit is fares less this line's own running costs: no interest, buildings or tax. A transfer's fare is shared among the lines it rides by distance.",
                    "損益是票收減去這條線自己的營運成本，不含利息、建物與稅。轉乘旅客的票價依各段距離分給所搭的路線。"
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
                Spacer()
                // Decision 184, later: a menu the ticks leave alone.
                let language = session.language
                TickStable(StableKey(line.id, line.color, language)) {
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
                                    Text(verbatim: color.hexText)
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
                    Text(verbatim: session.world.freightLineText(line.id, in: session.language)
                        ?? session.world.freightLineHelp(in: session.language))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
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
                session.removeSelectedLine()
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
                trains: session.world.lineTrainDots(line.id)
            )
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
                    session.removePatternFromSelectedLine(pattern)
                }
            }
        } header: {
            Text(summary.title)
        }
    }

    /// Each ordered leg can keep its platform flexible, or bind the whole
    /// displayed directed walk. IDs are the map's physical track numbers.
    private func routeMenus(_ line: ServiceLine, pattern: Int?) -> some View {
        let calls = pattern.map { line.patterns[$0].calls } ?? Array(line.stops.indices)
        let outward = line.isRing ? calls + [0] : calls
        let order = line.isRing ? outward + outward.dropLast().reversed() : calls + calls.dropLast().reversed()
        let pairs = Array(zip(order, order.dropFirst()))
        let preferences = pattern.map { line.patterns[$0].routePreferences } ?? line.routePreferences
        return ForEach(pairs.indices, id: \.self) { index in
            let pair = pairs[index]
            let selected = preferences.first { $0.from == pair.0 && $0.to == pair.1 }
            let choices = memo.routeChoices(line.id, from: pair.0, to: pair.1, pattern: pattern, of: session)
            // Decision 184, later: drawn from these values alone, so a
            // running game's ticks leave the open menu alone.
            let choiceTexts = choices.map(routeChoiceText)
            let selectedText = selected.map(routeChoiceText)
            let leg = "\(name(of: line.stops[pair.0])) → \(name(of: line.stops[pair.1]))"
            TickStable(StableKey(line.id, pattern, pair.0, pair.1, choices, choiceTexts, selectedText, leg)) {
                Menu {
                    Button("Automatic physical path") {
                        session.setSelectedLineRoute(from: pair.0, to: pair.1, preference: nil, pattern: pattern)
                    }
                    ForEach(choices.indices, id: \.self) { choice in
                        Button(choiceTexts[choice]) {
                            session.setSelectedLineRoute(from: pair.0, to: pair.1, preference: choices[choice], pattern: pattern)
                        }
                        .accessibilityIdentifier("line.route.choice.\(pattern ?? -1).\(pair.0).\(pair.1).\(choice)")
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: leg)
                        if let selectedText { Text(selectedText).font(.caption) }
                        else { Text("Automatic physical path").font(.caption) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("line.route.\(pattern ?? -1).\(pair.0).\(pair.1)")
            }
        }
    }

    private func trackNumber(_ edge: TrackEdgeID) -> Int {
        switch edge { case .edge(let number): number }
    }

    private func routeChoiceText(_ route: LineRoutePreference) -> String {
        let platform = trackNumber(route.platform.edge)
        if route.tracks.isEmpty {
            return session.language == .traditionalChinese ? "月台股道 #\(platform)・自動選路" : "Platform track #\(platform) · automatic route"
        }
        let walk = route.tracks.map { "\(trackNumber($0.edge))\($0.direction == .forward ? "→" : "←")" }.joined(separator: " · ")
        return session.language == .traditionalChinese ? "股道 \(walk)・月台股道 #\(platform)" : "Tracks \(walk) · platform #\(platform)"
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
        } header: {
            Text("Add a stopping pattern")
        } footer: {
            Text("Services share every stretch of the line: at most one train every 2 minutes each way, the line's own service first.")
        }
    }

    // MARK: - Trains for a line (decision 101)

    /// How often a train should come on `line`, and what that takes: the
    /// trains its round trip needs, their price, and one button that buys,
    /// places and assigns them.
    private func staffSection(_ line: ServiceLine) -> some View {
        let language = session.language
        let plan = memo.staffingPlan(line.id, headway: staffHeadway, type: staffType, cars: staffCars, of: session)
        return Section {
            Picker(selection: $staffHeadway) {
                ForEach(GameWorld.staffingHeadways, id: \.self) { minutes in
                    Text(verbatim: language.text("\(minutes) min", "\(minutes) 分")).tag(minutes)
                }
            } label: {
                Text(verbatim: language.text("A train every", "班距"))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("line.staff.headway")
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
            if draft.isEmpty {
                Text(verbatim: language.text(
                    "Pick the line's first and last stations. The stations the track passes between them are found for you.",
                    "選路線的起點和終點，沿途經過的車站會依軌道自動找出。"
                ))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            } else {
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
                } else {
                    Text(verbatim: language.text(
                        "No track joins these stations yet. The line calls at the stations picked; its trains run once track joins them.",
                        "這些車站之間還沒有軌道相連。路線只停點選的車站，軌道接通後列車才能行駛。"
                    ))
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
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
            }
            Button {
                session.createLineFromDraft()
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

/// Decision 194: a line's fares and four running costs over its report's
/// days, as bars, and for a line that lost money why: at most two reasons,
/// each with the figure that shows it. An equatable view of the diagnosis,
/// which only a command or a new game day changes: the game's ticks leave
/// it alone.
///
/// Decision 194, later: beside each reason the change that answers it
/// (``LineLossFix``), asked before it is made; one the balance does not
/// pay for is off, and says so.
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
                session.removeStopFromSelectedLine(at: index)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 32)
        }
        .accessibilityLabel("Edit stop \(index + 1), \(stationName)")
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
/// rename button calls `rename` with what was typed.
private struct RenameAlert: ViewModifier {
    let title: String
    @Binding var name: String?
    let language: DisplayLanguage
    let rename: (String) -> Void

    func body(content: Content) -> some View {
        content.alert(
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

extension View {
    /// A rename alert (see `RenameAlert`).
    func renameAlert(title: String, name: Binding<String?>, language: DisplayLanguage,
                     rename: @escaping (String) -> Void) -> some View {
        modifier(RenameAlert(title: title, name: name, language: language, rename: rename))
    }
}
