import GameCore
import GamePresentation
import SwiftUI

/// The selected train's own timetable (Stage C2): its stops with when it
/// arrives and leaves, turning round, repeating, and starting or stopping
/// its service. A line's train gets its timetables from the line, so for
/// one the screen shows the line instead, with the way to its stops and the
/// way off it; a running service keeps its timetable until it is stopped,
/// so its controls are disabled. Why sits above the form, where the
/// navigation bar never covers it.
///
/// Everything shown is read from `session.world` when the view is drawn,
/// and every control calls a `GameSession` method that applies one
/// `GameWorld` command.
struct TimetableEditor: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    @Environment(GameScreenState.self) private var screen

    /// The least height of a stop's stepper or switch, in points.
    private static let controlHeight: CGFloat = 44

    var body: some View {
        NavigationStack {
            Form {
                if let train = session.selectedTrain {
                    if let line = session.world.lineTrainTimetable(of: train.id, in: session.language) {
                        lineSection(line)
                        tripSection(train)
                        lineActionsSection(line)
                    } else {
                        overviewSection(train)
                        stopsSection(train)
                        addSection(train)
                    }
                } else {
                    Text("No train yet. Buy one with the train tool.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle(session.selectedTrain.map { Text(verbatim: $0.name) } ?? Text("Timetable"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let train = session.selectedTrain, let lock = lock(of: train) {
                    lockBanner(lock)
                }
            }
            .safeAreaInset(edge: .bottom) {
                StatusBanner(session: session, announces: false)
            }
        }
    }

    /// Why the timetable cannot be changed now, or `nil`.
    private func lock(of train: Train) -> LocalizedStringKey? {
        if session.world.assignedLine(of: train.id) != nil {
            return "This train runs for a line, which writes its timetables. Take it off the line to give it its own."
        }
        if train.execution != nil {
            return "The service is running. Stop it to change the timetable."
        }
        return nil
    }

    /// Why the timetable cannot be changed, fixed above the form: in the
    /// form's first row the navigation bar covered half of it.
    private func lockBanner(_ lock: LocalizedStringKey) -> some View {
        Label(lock, systemImage: "lock")
            .font(.footnote)
            .foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
    }

    // MARK: - A line's train

    /// The line the train runs for, read only: its name, its stops and
    /// where the train stands.
    private func lineSection(_ line: LineTrainTimetable) -> some View {
        Section {
            Text(verbatim: line.serviceName)
                .font(.subheadline.weight(.semibold))
            Text(verbatim: line.stopsText)
                .font(.footnote)
            Text(verbatim: line.statusText)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        } header: {
            Text("Line")
        }
    }

    /// The trip the line sent the train out on, as plain text; nothing
    /// before it is sent out.
    @ViewBuilder
    private func tripSection(_ train: Train) -> some View {
        let rows = session.world.timetableRows(of: train.id, in: session.language)
        if train.execution != nil, !rows.isEmpty {
            Section {
                ForEach(rows, id: \.index) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "\(row.index + 1). \(row.stationName)")
                                .font(.subheadline)
                            Spacer(minLength: 8)
                            Text(verbatim: row.timesText)
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                        Text(verbatim: row.detailText)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("This Trip")
            }
        }
    }

    /// Where a line's train is changed: the line's stops in the line panel,
    /// or the train taken off the line.
    private func lineActionsSection(_ line: LineTrainTimetable) -> some View {
        Section {
            Button {
                session.selectLine(line.line)
                screen.panel = .lines
            } label: {
                Label("Edit Stops in the Lines Panel", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            Button {
                session.unassignSelectedTrain()
            } label: {
                Label("Take Off the Line for Its Own Timetable", systemImage: "arrow.uturn.left.circle")
            }
        } footer: {
            Text("A trip under way is finished first; after that the train's timetable is its own to change.")
        }
    }

    // MARK: - Sections

    private func overviewSection(_ train: Train) -> some View {
        let language = session.language
        let isLocked = lock(of: train) != nil
        return Section {
            Text(session.world.timetableSummary(of: train.id, in: language) ?? String(localized: "No timetable yet. Add its first stop below."))
                .font(.subheadline)
                .monospacedDigit()
            Toggle("Repeats", isOn: Binding(
                get: { train.timetablePeriod != nil },
                set: { session.setSelectedTrainTimetableRepeats($0) }
            ))
            .disabled(isLocked || train.timetable.isEmpty)
            if let period = session.world.timetablePeriodText(of: train.id, in: language) {
                Stepper(
                    onIncrement: { session.changeSelectedTrainTimetablePeriod(by: TimetableEditing.step) },
                    onDecrement: { session.changeSelectedTrainTimetablePeriod(by: -TimetableEditing.step) }
                ) {
                    Text(verbatim: period)
                        .monospacedDigit()
                }
                .disabled(isLocked)
                .accessibilityHint("A minute longer or shorter, never shorter than the timetable.")
            }
            if train.execution != nil {
                Button {
                    session.stopSelectedTrainService()
                } label: {
                    Label("Stop Service", systemImage: "stop.circle")
                }
            } else if !train.timetable.isEmpty {
                Button {
                    session.startSelectedTrainService()
                } label: {
                    Label("Run Service", systemImage: "play.circle")
                }
            }
            if !train.timetable.isEmpty {
                Button(role: .destructive) {
                    session.clearSelectedTrainTimetable()
                } label: {
                    Label("Clear Timetable", systemImage: "trash")
                }
                .disabled(isLocked)
            }
        } header: {
            Text("Timetable")
        } footer: {
            Text("A service starts at the first stop: put the train there and run it. An early train waits for its departure; a late one leaves once boarding is done.")
        }
    }

    private func stopsSection(_ train: Train) -> some View {
        let isLocked = lock(of: train) != nil
        let rows = session.world.timetableRows(of: train.id, in: session.language)
        return Section {
            ForEach(rows, id: \.index) { row in
                stopRow(row, of: train)
                    .disabled(isLocked)
            }
            .onDelete { offsets in
                // One stop at a time, last first, so each index still
                // names the stop it named.
                for index in offsets.sorted(by: >) {
                    session.removeSelectedTrainStop(at: index)
                }
            }
            .deleteDisabled(isLocked)
        } header: {
            Text("Stops")
        }
    }

    /// A stop's name and times, then its controls, each at least as tall as
    /// a control is drawn (44 points): sized to their small labels alone,
    /// the steppers and the switch were drawn over one another.
    private func stopRow(_ row: TimetableRow, of train: Train) -> some View {
        let stops = train.timetable
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(row.index + 1). \(row.stationName)")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(verbatim: row.timesText)
                    .font(.subheadline)
                    .monospacedDigit()
            }
            Text(verbatim: row.detailText)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            Stepper(
                onIncrement: { session.moveSelectedTrainArrival(at: row.index, by: TimetableEditing.step) },
                onDecrement: TimetableEditing.canArriveEarlier(row.index, in: stops)
                    ? { session.moveSelectedTrainArrival(at: row.index, by: -TimetableEditing.step) } : nil
            ) {
                Text(row.index == 0 ? "Start" : "Arrive")
                    .font(.footnote)
            }
            .frame(minHeight: Self.controlHeight)
            .accessibilityHint("A minute later or earlier; the stops after it move with it.")
            Stepper(
                onIncrement: { session.moveSelectedTrainDeparture(at: row.index, by: TimetableEditing.step) },
                onDecrement: TimetableEditing.canLeaveEarlier(row.index, in: stops)
                    ? { session.moveSelectedTrainDeparture(at: row.index, by: -TimetableEditing.step) } : nil
            ) {
                Text("Leave")
                    .font(.footnote)
            }
            .frame(minHeight: Self.controlHeight)
            .accessibilityHint("A minute later or earlier; the stops after it move with it.")
            Toggle("Turn round here", isOn: Binding(
                get: { row.reverses },
                set: { _ in session.toggleSelectedTrainReverse(at: row.index) }
            ))
            .font(.footnote)
            .frame(minHeight: Self.controlHeight)
        }
        .padding(.vertical, 2)
    }

    private func addSection(_ train: Train) -> some View {
        let stations = session.stationMenuChoices
        return Section {
            // Decision 184, later: drawn from the stations' names alone, so
            // a running game's ticks leave the open menu alone.
            TickStable(stations) {
                Menu {
                    ForEach(stations) { station in
                        Button(station.title) {
                            session.addStopToSelectedTrainTimetable(station.id)
                        }
                    }
                } label: {
                    Label("Add Stop", systemImage: "plus.circle")
                }
            }
            .disabled(lock(of: train) != nil || stations.isEmpty)
        } footer: {
            Text("A new stop comes 3 minutes after the last one and waits a minute; move its times with the steppers. Swipe a stop to remove it.")
        }
    }
}
