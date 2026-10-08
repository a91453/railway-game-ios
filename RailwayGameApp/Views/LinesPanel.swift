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
    @Environment(\.dismiss) private var dismiss
    @State private var patternFirst = 0
    @State private var patternLast = 1
    @State private var patternExpress = false
    /// The name being typed for the selected line, while its rename alert
    /// is up.
    @State private var renamingLine: String?
    /// How often a train should come, for the selected line's trains
    /// (decision 101).
    @State private var staffHeadway: Int64 = 10

    /// Target headways offered in the menu, in minutes.
    private static let targets: [Int64] = [5, 10, 15, 20, 30, 60]

    var body: some View {
        NavigationStack {
            Form {
                // Decision 100: a new line first, where the sheet at half
                // height shows it while stations are picked on the map.
                draftSection
                // Decision 101: a line without trains offers them next.
                if let line = session.selectedLine, line.trains.isEmpty, !line.isRing {
                    staffSection(line)
                }
                trafficSection
                serviceDaySection
                linesSection
                if let line = session.selectedLine {
                    lineSection(line)
                    stopsSection(line)
                    ForEach(session.world.lineServiceSummaries(line.id, in: session.language), id: \.pattern) { summary in
                        serviceSection(summary, of: line)
                    }
                    // A ring has no patterns.
                    if !line.isRing {
                        addPatternSection(line)
                    }
                }
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
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                StatusBanner(session: session)
            }
            // Taps on the map select again once the panel is closed.
            .onDisappear {
                session.stopPickingLineStops()
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
                    Picker(selection: Binding(get: { band.level }, set: { session.setServiceDayBand(index, to: $0) })) {
                        ForEach(ServiceLevel.allCases, id: \.self) { level in
                            Text(level.title(in: language)).tag(level)
                        }
                    } label: {
                        Text(verbatim: day.bandText(index, in: language))
                            .monospacedDigit()
                    }
                    .pickerStyle(.menu)
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
                ForEach(session.world.lines) { line in
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
                Text(line.name)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: "\(line.stops.map { name(of: $0) }.joined(separator: " – ")) · \(status)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
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
                Menu {
                    Button {
                        session.setSelectedLineColor(nil)
                    } label: {
                        Text(verbatim: session.language.text("Automatic", "自動"))
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
                        Text(verbatim: session.language.text("Colour", "顏色"))
                    } icon: {
                        Circle()
                            .fill(Palette.lineColor(line.id, custom: line.color))
                            .frame(width: 16, height: 16)
                    }
                }
                .accessibilityIdentifier("line.color")
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
            // Stage C3: the performance its journeys are planned with
            // (Stage W2c), and the journey that gives.
            PerformanceMenu(performance: line.performance, language: session.language) { performance in
                session.setSelectedLinePerformance(performance)
            }
            if let journey = session.world.lineJourneyText(line.id, in: session.language) {
                Text(journey)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            // Stage C2: single or double track between its stops (Stage S1).
            ForEach(Array(session.world.lineTrackCountTexts(line.id, in: session.language).enumerated()), id: \.offset) { _, text in
                Label(text, systemImage: "road.lanes")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(ServiceLevel.allCases, id: \.self) { level in
                if let gap = session.world.lineCoverageText(line.id, at: level, in: session.language) {
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
        Section {
            ForEach(Array(line.stops.enumerated()), id: \.offset) { index, station in
                HStack {
                    Text(verbatim: "\(index + 1). \(name(of: station))")
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Menu {
                        Button("Move Up") {
                            session.moveStopOfSelectedLine(at: index, by: -1)
                        }
                        .disabled(index == 0)
                        Button("Move Down") {
                            session.moveStopOfSelectedLine(at: index, by: 1)
                        }
                        .disabled(index == line.stops.count - 1)
                        Menu("Insert Before") {
                            stationButtons { session.insertStopIntoSelectedLine($0, at: index) }
                        }
                        Button("Remove Stop", role: .destructive) {
                            session.removeStopFromSelectedLine(at: index)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 32)
                    }
                    .accessibilityLabel("Edit stop \(index + 1), \(name(of: station))")
                }
            }
            Menu {
                stationButtons { session.insertStopIntoSelectedLine($0, at: line.stops.count) }
            } label: {
                Label("Add Stop at the End", systemImage: "plus.circle")
            }
            // Decision 80: MapBuilder's add to line, where the station fits.
            Menu {
                stationButtons { session.addStationToSelectedLine($0) }
            } label: {
                Label("Add Stop Where It Fits", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .accessibilityIdentifier("line.addStopWhereItFits")
            Button {
                session.reverseSelectedLine()
            } label: {
                Label("Reverse Stop Order", systemImage: "arrow.left.arrow.right")
            }
            .accessibilityIdentifier("line.reverse")
        } header: {
            Text("Stops")
        } footer: {
            if line.isRing {
                Text("The last stop runs on to the first. Passengers waiting for a trip the line no longer takes leave.")
            } else {
                Text("Patterns keep calling at the same positions in the list. Passengers waiting for a trip the line no longer takes leave.")
            }
        }
    }

    /// A button for every station, calling `choose` with its ID.
    private func stationButtons(_ choose: @escaping @MainActor (StationID) -> Void) -> some View {
        ForEach(session.world.stations) { station in
            Button(station.name) {
                choose(station.id)
            }
        }
    }

    private func serviceSection(_ summary: LineServiceSummary, of line: ServiceLine) -> some View {
        Section {
            routeMenus(line, pattern: summary.pattern)
            Text(summary.callsText)
                .font(.footnote)
            ForEach(summary.levels, id: \.level) { level in
                levelRow(level, pattern: summary.pattern, of: line)
            }
            Text("\(summary.assigned) assigned · \(summary.running) on a trip")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if let train = session.selectedTrain {
                Button("Assign \(train.name) Here") {
                    session.assignSelectedTrainToSelectedLine(pattern: summary.pattern)
                }
            }
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
            let choices = session.world.lineRouteChoices(line.id, from: pair.0, to: pair.1, pattern: pattern)
            Menu {
                Button("Automatic physical path") {
                    session.setSelectedLineRoute(from: pair.0, to: pair.1, preference: nil, pattern: pattern)
                }
                ForEach(choices.indices, id: \.self) { choice in
                    Button(routeChoiceText(choices[choice])) {
                        session.setSelectedLineRoute(from: pair.0, to: pair.1, preference: choices[choice], pattern: pattern)
                    }
                    .accessibilityIdentifier("line.route.choice.\(pattern ?? -1).\(pair.0).\(pair.1).\(choice)")
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(name(of: line.stops[pair.0])) → \(name(of: line.stops[pair.1]))")
                    if let selected { Text(routeChoiceText(selected)).font(.caption) }
                    else { Text("Automatic physical path").font(.caption) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("line.route.\(pattern ?? -1).\(pair.0).\(pair.1)")
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
            Menu {
                Button("By train count") {
                    session.setSelectedLineTargetHeadway(nil, at: level.level, pattern: pattern)
                }
                ForEach(Self.targets, id: \.self) { minutes in
                    Button(headwayText(minutes: minutes, in: session.language)) {
                        session.setSelectedLineTargetHeadway(minutes, at: level.level, pattern: pattern)
                    }
                }
            } label: {
                Label(targetHeadwayText(target, in: session.language), systemImage: "clock.arrow.circlepath")
                    .font(.caption)
            }
        }
    }

    private func addPatternSection(_ line: ServiceLine) -> some View {
        Section {
            Picker("From", selection: $patternFirst) {
                ForEach(line.stops.indices, id: \.self) { index in
                    Text(name(of: line.stops[index])).tag(index)
                }
            }
            Picker("To", selection: $patternLast) {
                ForEach(line.stops.indices, id: \.self) { index in
                    Text(name(of: line.stops[index])).tag(index)
                }
            }
            Toggle("Express: call at the two ends only", isOn: $patternExpress)
            Button("Add Pattern") {
                session.addPatternToSelectedLine(from: patternFirst, to: patternLast, express: patternExpress)
            }
        } header: {
            Text("Add a short working or express")
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
        let plan = session.world.lineStaffingPlan(line.id, headway: staffHeadway)
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
            if let plan {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: language.text(
                        "Round trip \(plan.roundTripMinutes) min: \(plan.trains) \(plan.trains == 1 ? "train" : "trains"), \(headwayText(minutes: plan.actualHeadway, in: language).lowercased())",
                        "來回 \(plan.roundTripMinutes) 分鐘：需要 \(plan.trains) 列，\(headwayText(minutes: plan.actualHeadway, in: language))"
                    ))
                    .font(.subheadline)
                    Text(verbatim: language.text("Cost \(plan.cost.moneyText)", "費用 \(plan.cost.moneyText)"))
                        .font(.caption)
                        .foregroundStyle(session.world.economy.balance < plan.cost ? Theme.error : Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("line.staff.plan")
                Button {
                    session.staffSelectedLine(headway: staffHeadway)
                } label: {
                    Label {
                        Text(verbatim: language.text(
                            "Buy \(plan.trains) and Start Service",
                            "購買 \(plan.trains) 列並開始營運"
                        ))
                    } icon: {
                        Image(systemName: "tram.fill")
                    }
                }
                .disabled(session.world.economy.balance < plan.cost)
                .accessibilityIdentifier("line.staff.start")
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
            Button("Create Line") {
                session.createLineFromDraft()
            }
            .disabled(stops.count < 2)
            .accessibilityIdentifier("line.draft.create")
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
