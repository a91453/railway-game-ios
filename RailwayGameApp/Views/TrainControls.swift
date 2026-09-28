import GameCore
import GamePresentation
import SwiftUI

/// The train tool's options: which train, where GameCore has it and the
/// path it has left, its rate, and the train commands that need no tile.
///
/// Everything shown is read from `session.world` each time the view is
/// drawn, and every control calls a `GameSession` method that applies one
/// `GameWorld` command, so the view keeps no train state of its own. Trains
/// move only when the game loop advances the world (Pause / 1× / 2× in the
/// HUD).
struct TrainControls: View {
    /// What one press of the rate control changes, in logical units per game
    /// minute (1024 units are one tile; at 1× a game minute is 100 ms).
    static let rateStep: Int64 = 32
    static let maximumRate: Int64 = 1_024

    @Bindable var session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let train = session.selectedTrain {
                status(of: train)
                if train.position == nil {
                    headingPicker
                } else {
                    Stepper(value: $session.selectedTrainRate, in: 0...Self.maximumRate, step: Self.rateStep) {
                        Text(train.movement.rateText)
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
                Label("Buy · \(session.world.economy.costs.train.displayText)", systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Buy a train for \(session.world.economy.costs.train.displayText)")
        }
    }

    /// Where the train is and the path it has left, exactly as GameCore
    /// records them.
    private func status(of train: Train) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(train.positionText)
                .font(.subheadline)
                .monospacedDigit()
            if train.position != nil {
                Text(train.movement.pathText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
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
                    Text(heading.abbreviation)
                        .font(.subheadline.weight(.bold))
                        .frame(width: 36, height: 28)
                }
                .buttonStyle(SelectableButtonStyle(isActive: isActive))
                .accessibilityLabel("Face \(heading.name)")
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
        }
        .buttonStyle(.bordered)
    }
}
