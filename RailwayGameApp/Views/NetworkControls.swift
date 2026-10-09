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
    /// Whether the track options are unfolded (decision 107): view state,
    /// folded again each time the tool is chosen.
    @State private var showsAdvanced = false
    /// The map's population and travel layer (``MapView``'s preference of
    /// the same key), which the platform mode can turn to population.
    @AppStorage("mapPopTravelMode") private var popTravelModeName = ""

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
                // Decision 107: how the track is built is chosen for the
                // player (ground, smooth, easy grade, snapping); changing
                // it is one tap further away, folded until wanted.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsAdvanced.toggle() }
                } label: {
                    Label {
                        Text(verbatim: session.language.text("Track options", "進階選項"))
                    } icon: {
                        Image(systemName: showsAdvanced ? "chevron.down" : "chevron.right")
                    }
                }
                .accessibilityValue(Text(verbatim: advancedSummary))
                .accessibilityIdentifier("network.advanced")
                Spacer(minLength: 0)
                Button("Clear") {
                    session.clearNetworkDraft()
                }
                .disabled(session.networkStart == nil)
            }
            .buttonStyle(.bordered)
            .font(.footnote)
            if showsAdvanced {
                advancedOptions
            } else {
                Text(verbatim: advancedSummary)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // Two places on two tracks make a crossover: one diagonal, or
            // an X with the mirrored one crossing it.
            if session.networkPicksCrossover {
                Toggle("X crossover", isOn: $session.networkBuildsScissors)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .font(.footnote)
                    .accessibilityIdentifier("network.scissors")
            }
            if let preview = session.networkPreview {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "ruler")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.primary)
                        Text(preview.text(in: session.language))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                    }
                    if let problem = preview.problem {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.warning)
                            Text(problem)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    // Decision 124, H3: the stretch over the ground, and
                    // what it costs part by part.
                    if let section = preview.longSection {
                        LongSectionView(chart: LongSectionChart(section), length: section.length, language: session.language)
                    }
                    if let parts = preview.costParts {
                        CostPartsView(parts: parts, language: session.language)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    /// The structure, the height of new nodes, and how the track follows
    /// other track and the ground (decision 107: folded by default).
    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("Structure", selection: $session.networkStructure) {
                    ForEach(TrackStructure.offered, id: \.self) { structure in
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
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .font(.footnote)
            // Off: every tap is a new point, for a parallel track a few
            // metres beside another (closer than a tap reaches).
            Toggle("Snap to track", isOn: $session.networkSnapsToTrack)
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .font(.footnote)
                .accessibilityIdentifier("network.snap")
        }
        .transition(.opacity)
    }

    /// The options folded away, in a line: the structure, and those of the
    /// three switches that are off.
    private var advancedSummary: String {
        let language = session.language
        var parts = [session.networkStructure.name(in: language)]
        if !session.networkFollowsTrack { parts.append(language.text("sharp curves", "不平順曲線")) }
        if !session.networkEasesGrade { parts.append(language.text("steep grade", "不緩和坡度")) }
        if !session.networkSnapsToTrack { parts.append(language.text("no snapping", "不吸附軌道")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Platforms

    private var platformOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Decision 108: where people live, while choosing where a
            // station goes; the map's layers button turns it off again.
            if popTravelModeName != PopTravelMode.population.rawValue {
                Button {
                    popTravelModeName = PopTravelMode.population.rawValue
                } label: {
                    Label {
                        Text(verbatim: session.language.text("Show where people live", "顯示人口分布"))
                    } icon: {
                        Image(systemName: "person.3.fill")
                    }
                }
                .buttonStyle(.bordered)
                .font(.footnote)
                .accessibilityIdentifier("network.showPopulation")
            }
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

// MARK: - The stretch over the ground (decision 124, H3)

/// The build card's long section of the stretch the network tool would
/// build (``LongSectionChart``): chainage across, height up; water shaded,
/// each stretch between the rail and the ground in the colour of what
/// carries it, the ground's line and the rail's over them; the heights at
/// the top and bottom, the length, and a key of the kinds it shows.
private struct LongSectionView: View {
    let chart: LongSectionChart
    let length: Int64
    let language: DisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Canvas { context, size in
                func point(_ p: LongSectionChart.Point) -> CGPoint {
                    CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
                }
                func line(_ points: [LongSectionChart.Point]) -> Path {
                    var path = Path()
                    path.addLines(points.map(point))
                    return path
                }
                for range in chart.water {
                    let rect = CGRect(x: range.lowerBound * size.width, y: 0, width: (range.upperBound - range.lowerBound) * size.width, height: size.height)
                    context.fill(Path(rect), with: .color(Palette.water.opacity(0.35)))
                }
                for band in chart.bands {
                    var outline = line(band.outline)
                    outline.closeSubpath()
                    context.fill(outline, with: .color(Palette.section(band.kind).opacity(band.kind == .surface ? 0.35 : 0.6)))
                }
                context.stroke(line(chart.ground), with: .color(Palette.groundLine), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                // A tunnel's rail dashed, as on the map: drawn band by band.
                for band in chart.bands {
                    let rail = Array(band.outline.prefix(band.outline.count / 2))
                    let dash: [CGFloat] = band.kind == .tunnel ? [4, 3] : []
                    context.stroke(line(rail), with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: dash))
                }
            }
            .frame(height: 72)
            .background(Theme.panel.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .topLeading) { axisLabel(chart.top) }
            .overlay(alignment: .bottomLeading) { axisLabel(chart.bottom) }
            .overlay(alignment: .bottomTrailing) {
                Text(verbatim: NetworkBuilding.lengthText(length, in: language))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: language.text("Long section", "縱斷面")))
            .accessibilityValue(Text(verbatim: chart.kinds.map { $0.name(in: language) }.joined(separator: ", ")))
            .accessibilityIdentifier("network.longSection")
            HStack(spacing: 8) {
                ForEach(chart.kinds, id: \.self) { kind in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.section(kind)).frame(width: 10, height: 8)
                        Text(verbatim: kind.name(in: language))
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    /// A height on the chart's edge, to the metre.
    private func axisLabel(_ height: Int64) -> some View {
        Text(verbatim: NetworkBuilding.lengthText(height, in: language))
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .padding(2)
    }
}

/// What the stretch costs, part by part (``NetworkCostParts``): the
/// track, earthwork, viaducts and bridges, tunnels and demolition where
/// they cost anything, and the total GameCore charged on the preview's
/// copy of the world.
private struct CostPartsView: View {
    let parts: NetworkCostParts
    let language: DisplayLanguage

    var body: some View {
        let lines = parts.lines(in: language)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack {
                    Text(verbatim: line.name)
                    Spacer(minLength: 8)
                    Text(verbatim: line.cost.moneyText)
                        .monospacedDigit()
                }
                .font(index == lines.count - 1 ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(index == lines.count - 1 ? Theme.textPrimary : Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("network.costParts")
    }
}
