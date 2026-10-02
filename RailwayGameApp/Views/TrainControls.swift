import GameCore
import GamePresentation
import SwiftUI

/// The train tool's options: which train, where GameCore has it, the path
/// it has left and the station it is stopped at, its rate, and the train
/// commands that need no tile.
///
/// Everything shown is read from `session.world` each time the view is
/// drawn, and every control calls a `GameSession` method that applies one
/// `GameWorld` command, so the view keeps no train state of its own. Trains
/// move only when the game loop advances the world (the HUD's speed
/// controls).
struct TrainControls: View {
    /// What one press of the rate control changes, in logical units per game
    /// minute (1024 units are one tile; at 600× a game minute is 100 ms). An
    /// `Int`, because that is `Int64`'s stride.
    static let rateStep = 32
    static let maximumRate: Int64 = 1_024

    @Bindable var session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let train = session.selectedTrain {
                status(of: train)
                if train.position == nil {
                    Stepper(value: Binding(get: { train.cars }, set: { session.setSelectedTrainCars($0) }), in: Train.minimumCars...Train.maximumCars) {
                        Text(train.carsText(in: session.language))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .accessibilityHint("One car to a tile. A train of several cars needs track behind it, and platforms as long as it.")
                    headingPicker
                } else {
                    Stepper(value: $session.selectedTrainRate, in: 0...Self.maximumRate, step: Self.rateStep) {
                        Text(train.movement.rateText(in: session.language))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .accessibilityValue("\(train.movement.rate) units per game minute")
                    commands
                }
            } else {
                Text("No train yet. Buy one, then select a track tile to place it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The selected train, a menu to choose another, and the buy button.
    private var header: some View {
        HStack(spacing: 8) {
            if let train = session.selectedTrain {
                Menu {
                    ForEach(session.world.trains) { candidate in
                        Button(candidate.name) {
                            session.selectTrain(candidate.id)
                        }
                    }
                } label: {
                    Label(train.name, systemImage: "train.side.front.car")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Train: \(train.name)")
                .accessibilityHint("Chooses the train to control.")
            }
            Spacer(minLength: 8)
            Button {
                session.purchaseTrain()
            } label: {
                Label("Buy · \(session.world.economy.costs.train.moneyText)", systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Buy a train for \(session.world.economy.costs.train.moneyText)")
        }
    }

    /// Where the train is, the path it has left and the station it is
    /// stopped at, exactly as GameCore records or derives them.
    private func status(of train: Train) -> some View {
        let language = session.language
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(train.positionText(in: language)) · \(train.carsText(in: language))")
                .font(.subheadline)
                .monospacedDigit()
            if train.position != nil {
                Text(train.pathText(in: language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let stop = session.world.stationStopText(of: train.id, in: language) {
                    Text(stop)
                        .font(.footnote.weight(.semibold))
                }
                if let load = session.world.loadText(of: train.id, in: language) {
                    Label(load, systemImage: "person.2")
                        .font(.footnote)
                        .monospacedDigit()
                }
            }
            if let service = session.world.trainServiceStatus(of: train.id, in: language) {
                serviceStatus(service)
            }
            // Under traffic control: which train holds the route it waits for.
            if let wait = session.world.routeWaitText(of: train.id, in: language) {
                Label(wait, systemImage: "hourglass")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The line or timetable the train runs, where it is in it and whether
    /// it is early or late, derived from the schedule and the clock.
    private func serviceStatus(_ service: TrainServiceStatus) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let name = service.serviceName {
                Label(name, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.footnote.weight(.semibold))
            }
            HStack(spacing: 6) {
                Text(service.stopText)
                if let punctuality = service.punctuality {
                    Text(punctuality.text(in: session.language))
                        .fontWeight(.semibold)
                        .foregroundStyle(punctuality == .onTime ? Color.green : Color.orange)
                }
            }
            .font(.footnote)
            .monospacedDigit()
        }
    }

    /// The heading an unplaced train will get when it is placed.
    private var headingPicker: some View {
        HStack(spacing: 6) {
            Text("Faces")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(TrackDirection.allCases, id: \.self) { heading in
                let isActive = session.placementHeading == heading
                Button {
                    session.setPlacementHeading(heading)
                } label: {
                    Text(heading.abbreviation(in: session.language))
                        .font(.subheadline.weight(.bold))
                        .frame(width: 36, height: 28)
                }
                .buttonStyle(SelectableButtonStyle(isActive: isActive))
                .accessibilityLabel("Face \(heading.name(in: session.language))")
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
    }

    private var commands: some View {
        HStack(spacing: 8) {
            Button {
                session.reverseSelectedTrain()
            } label: {
                Label("Reverse", systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
            }
            Button {
                session.unplaceSelectedTrain()
            } label: {
                Label("Take Off", systemImage: "xmark.circle")
                    .font(.subheadline)
            }
            .accessibilityLabel("Take the train off the track")
            serviceCommand
        }
        .buttonStyle(.bordered)
    }

    /// Takes a line's train off its line, or starts or stops a train's own
    /// timetable. GameCore decides whether the command is allowed.
    @ViewBuilder
    private var serviceCommand: some View {
        if let train = session.selectedTrain {
            if session.world.assignedLine(of: train.id) != nil {
                Button {
                    session.unassignSelectedTrain()
                } label: {
                    Label("Off Line", systemImage: "minus.circle")
                        .font(.subheadline)
                }
                .accessibilityLabel("Take the train off its line")
            } else if train.execution != nil {
                Button {
                    session.stopSelectedTrainService()
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .font(.subheadline)
                }
                .accessibilityLabel("Stop the train's timetable")
            } else if !train.timetable.isEmpty {
                Button {
                    session.startSelectedTrainService()
                } label: {
                    Label("Run", systemImage: "play.circle")
                        .font(.subheadline)
                }
                .accessibilityLabel("Run the train's timetable")
            }
        }
    }
}
