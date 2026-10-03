import GameCore
import GamePresentation
import SwiftUI

/// The network tool's options (Stage C1): build track at any angle by
/// tapping where it starts and where it ends, give a station a platform on
/// it, or remove it. The action button builds, adds or removes, and the
/// inspector says what the taps picked.
///
/// Everything shown is read from the session when the view is drawn: the
/// picked ends and place are drafts in the session, and what the stretch
/// would cost comes from GameCore through ``GameSession/networkPreview``.
struct NetworkControls: View {
    @Bindable var session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Network mode", selection: Binding(get: { session.networkMode }, set: { session.setNetworkMode($0) })) {
                ForEach(NetworkToolMode.allCases, id: \.self) { mode in
                    Text(mode.title(in: session.language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tutorialTarget(.networkModes)
            switch session.networkMode {
            case .build:
                buildOptions
            case .platform:
                platformOptions
            case .remove:
                EmptyView()
            }
        }
    }

    // MARK: - Build

    private var buildOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("Structure", selection: $session.networkStructure) {
                    ForEach(TrackStructure.allCases, id: \.self) { structure in
                        Text(structure.name(in: session.language)).tag(structure)
                    }
                }
                .pickerStyle(.menu)
                Stepper(
                    value: $session.networkHeight,
                    in: NetworkBuilding.heightRange,
                    // An `Int`: `Int64`'s stride.
                    step: Int(NetworkBuilding.heightStep)
                ) {
                    Text(session.networkHeightText())
                        .font(.footnote)
                        .monospacedDigit()
                }
            }
            HStack(spacing: 8) {
                Toggle("Smooth curves", isOn: $session.networkFollowsTrack)
                Toggle("Ease the grade", isOn: $session.networkEasesGrade)
                Spacer(minLength: 0)
                Button("Clear") {
                    session.clearNetworkDraft()
                }
                .disabled(session.networkStart == nil)
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .font(.footnote)
            if let preview = session.networkPreview {
                Text(preview.text(in: session.language))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                if let problem = preview.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Platforms

    private var platformOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $session.platformCars, in: Train.minimumCars...Train.maximumCars) {
                Text(session.platformLengthText())
                    .font(.footnote)
                    .monospacedDigit()
            }
            Picker("Platform station", selection: $session.platformStationID) {
                Text("New station").tag(StationID?.none)
                ForEach(session.world.stations) { station in
                    Text(verbatim: station.name).tag(StationID?.some(station.id))
                }
            }
            .pickerStyle(.menu)
            if session.platformStationID == nil {
                TextField("Station name", text: $session.stationName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            ForEach(session.platformsOnPickedEdge, id: \.self) { platform in
                HStack(spacing: 8) {
                    Text(session.platformText(platform))
                        .font(.footnote)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        session.removeNetworkPlatform(platform)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Remove this platform")
                }
            }
        }
    }
}
