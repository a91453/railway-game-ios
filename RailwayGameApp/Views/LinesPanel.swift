import GameCore
import GamePresentation
import SwiftUI

/// Service lines (Phase 4 Stage R): every line and whether it runs now; for
/// the selected line, each of its services (its own and its patterns) with
/// the trains it is set to run at each level, what it can run and how far
/// apart, its trains, and stretches no service covers; adding patterns and
/// assigning the selected train; and picking stations for a new line. At the
/// top, the traffic control switch (Phase 4.6 Stage T).
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
                linesSection
                if let line = session.selectedLine {
                    lineSection(line)
                    ForEach(session.world.lineServiceSummaries(line.id, in: session.language), id: \.pattern) { summary in
                        serviceSection(summary, of: line)
                    }
                    addPatternSection(line)
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
        return HStack(spacing: 8) {
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
            Text("Peak runs 07:00–10:00 and 16:00–20:00, low from 21:00 to 07:00, off-peak otherwise.")
        }
    }

    private func serviceSection(_ summary: LineServiceSummary, of line: ServiceLine) -> some View {
        Section {
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

    /// The trains a service is set to run at one level, with a stepper to
    /// change it, what it can run and how far apart, and a menu for a
    /// target headway.
    private func levelRow(_ level: LevelServiceSummary, pattern: Int?, of line: ServiceLine) -> some View {
        let counts = pattern.map { line.patterns[$0].trainsInService } ?? line.trainsInService
        let targets = pattern.map { line.patterns[$0].targetHeadways } ?? line.targetHeadways
        let wanted = counts[level.level]
        let target = targets[level.level]
        return VStack(alignment: .leading, spacing: 4) {
            Stepper(
                onIncrement: {
                    session.setSelectedLineTrains(wanted + 1, at: level.level, pattern: pattern)
                },
                onDecrement: {
                    session.setSelectedLineTrains(max(0, wanted - 1), at: level.level, pattern: pattern)
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
