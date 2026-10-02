import GameCore
import GamePresentation
import SwiftUI

/// The selected train's own timetable (Stage C2): its stops with when it
/// arrives and leaves, turning round, repeating, and starting or stopping
/// its service. A line's train gets its timetables from the line, and a
/// running service keeps its timetable until it is stopped: GameCore
/// refuses both, so the controls are disabled and say why.
///
/// Everything shown is read from `session.world` when the view is drawn,
/// and every control calls a `GameSession` method that applies one
/// `GameWorld` command.
struct TimetableEditor: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let train = session.selectedTrain {
                    overviewSection(train)
                    stopsSection(train)
                    addSection(train)
                } else {
                    Text("No train yet. Buy one with the train tool.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .safeAreaInset(edge: .bottom) {
                StatusBanner(session: session)
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

    // MARK: - Sections

    private func overviewSection(_ train: Train) -> some View {
        let language = session.language
        let isLocked = lock(of: train) != nil
        return Section {
            if let lock = lock(of: train) {
                Label(lock, systemImage: "lock")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
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
            if session.world.assignedLine(of: train.id) == nil {
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
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Stepper(
                onIncrement: { session.moveSelectedTrainArrival(at: row.index, by: TimetableEditing.step) },
                onDecrement: TimetableEditing.canArriveEarlier(row.index, in: stops)
                    ? { session.moveSelectedTrainArrival(at: row.index, by: -TimetableEditing.step) } : nil
            ) {
                Text(row.index == 0 ? "Start" : "Arrive")
                    .font(.footnote)
            }
            .accessibilityHint("A minute later or earlier; the stops after it move with it.")
            Stepper(
                onIncrement: { session.moveSelectedTrainDeparture(at: row.index, by: TimetableEditing.step) },
                onDecrement: TimetableEditing.canLeaveEarlier(row.index, in: stops)
                    ? { session.moveSelectedTrainDeparture(at: row.index, by: -TimetableEditing.step) } : nil
            ) {
                Text("Leave")
                    .font(.footnote)
            }
            .accessibilityHint("A minute later or earlier; the stops after it move with it.")
            Toggle("Turn round here", isOn: Binding(
                get: { row.reverses },
                set: { _ in session.toggleSelectedTrainReverse(at: row.index) }
            ))
            .font(.footnote)
        }
        .padding(.vertical, 2)
    }

    private func addSection(_ train: Train) -> some View {
        Section {
            Menu {
                ForEach(session.world.stations) { station in
                    Button(station.name) {
                        session.addStopToSelectedTrainTimetable(station.id)
                    }
                }
            } label: {
                Label("Add Stop", systemImage: "plus.circle")
            }
            .disabled(lock(of: train) != nil || session.world.stations.isEmpty)
        } footer: {
            Text("A new stop comes 3 minutes after the last one and waits a minute; move its times with the steppers. Swipe a stop to remove it.")
        }
    }
}
