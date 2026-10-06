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

    /// Target headways offered in the menu, in minutes.
    private static let targets: [Int64] = [5, 10, 15, 20, 30, 60]

    var body: some View {
        NavigationStack {
            Form {
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
                draftSection
            }
            .navigationTitle("Lines")
            .navigationBarTitleDisplayMode(.inline)
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
        } footer: {
            Text("When on, a train takes its whole route before it leaves, and other trains wait until it has cleared it.")
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
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.world.lines) { line in
                    Button {
                        session.selectLine(line.id)
                    } label: {
                        lineRow(line)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(line.id == session.selectedLineID ? .isSelected : [])
                }
            }
        } header: {
            Text("Lines")
        }
    }

    private func lineRow(_ line: ServiceLine) -> some View {
        let status = session.world.lineStatusText(line.id, at: session.world.clock.now, in: session.language)
        let color = Palette.lineColor(line.id)
        return HStack(spacing: 10) {
            ZStack {
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
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if line.id == session.selectedLineID {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - The selected line

    private func lineSection(_ line: ServiceLine) -> some View {
        Section {
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
                    .foregroundStyle(.secondary)
            }
            // Stage C3: the performance its journeys are planned with
            // (Stage W2c), and the journey that gives.
            PerformanceMenu(performance: line.performance, language: session.language) { performance in
                session.setSelectedLinePerformance(performance)
            }
            if let journey = session.world.lineJourneyText(line.id, in: session.language) {
                Text(journey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            // Stage C2: single or double track between its stops (Stage S1).
            ForEach(Array(session.world.lineTrackCountTexts(line.id, in: session.language).enumerated()), id: \.offset) { _, text in
                Label(text, systemImage: "road.lanes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(ServiceLevel.allCases, id: \.self) { level in
                if let gap = session.world.lineCoverageText(line.id, at: level, in: session.language) {
                    Label("\(level.title(in: session.language)): \(gap)", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
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
                .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
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

    // MARK: - New line

    private var draftSection: some View {
        Section {
            if session.lineDraft.isEmpty {
                Text("Select a station on the map, then add it here. Add two or more, in order.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(session.lineDraft.map { name(of: $0) }.joined(separator: " → "))
                    .font(.subheadline)
            }
            Button("Add Selected Station") {
                session.addSelectedStationToLineDraft()
            }
            Button("Remove Last Stop") {
                session.removeLastLineDraftStop()
            }
            .disabled(session.lineDraft.isEmpty)
            Button("Create Line") {
                session.createLineFromDraft()
            }
            .disabled(session.lineDraft.count < 2)
        } header: {
            Text("New line")
        }
    }
}
