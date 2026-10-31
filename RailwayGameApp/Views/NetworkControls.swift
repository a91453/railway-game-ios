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
    /// Whether the long section and the cost in parts are unfolded on a
    /// phone (decision 124, H3): folded there, so the card's action button
    /// stays in view without scrolling; an iPad has the room and shows them.
    @State private var showsSection = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The map's population and travel layer (``MapView``'s preference of
    /// the same key), which the platform mode can turn to population.
    @AppStorage("mapPopTravelMode") private var popTravelModeName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Network mode", selection: Binding(get: { session.networkMode }, set: { session.setNetworkMode($0) })) {
                // Decision 266: in a lesson, only the modes it has unlocked.
                ForEach(NetworkToolMode.allCases.filter { session.allows($0) }, id: \.self) { mode in
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
                platformRemovals(showsPlace: false)
            case .passingLoop:
                passingLoopOptions
            case .depot:
                depotOptions
            }
        }
    }

    // MARK: - Build

    private var buildOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Four buttons in a row did not fit a phone held sideways (the
            // side panel is narrow there): SwiftUI squeezed their words one
            // character to a line. In rows, each button as wide as its
            // words: one row where they fit, else two, else more.
            ChipFlow(spacing: 8) {
                advancedButton
                doubleToggle
                snapToggle
                traceToggle
                clearButton
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
                    .toggleStyle(OnOffButtonToggleStyle())
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
                    // Decision 204: the double track's crossovers where it
                    // joins the track there, or why there are none.
                    // Decision 213: where a traced stretch stops, and why.
                    if let note = preview.traceNote {
                        Text(verbatim: note)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("network.traceNote")
                    }
                    if let note = preview.crossoverNote {
                        Text(verbatim: note)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("network.crossoverNote")
                    }
                    // Decision 468, later: a trace along a real line for
                    // sale, which can be bought as it is instead.
                    if let sale = session.tracedSaleHint {
                        TracedSaleRow(sale: sale, language: session.language) {
                            session.offerTracedSaleLine()
                        }
                    }
                    // Decision 124, H3: the stretch over the ground, and
                    // what it costs part by part. Only where the world has
                    // ground: without it the ground is flat at 0 m and the
                    // cost is the track's, which the line above says.
                    if session.world.ground.isMapped, preview.longSection != nil || preview.costParts != nil {
                        let roomy = horizontalSizeClass == .regular && verticalSizeClass == .regular
                        if !roomy {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showsSection.toggle() }
                            } label: {
                                Label {
                                    Text(verbatim: session.language.text("Long section and costs", "縱斷面與費用"))
                                } icon: {
                                    Image(systemName: showsSection ? "chevron.down" : "chevron.right")
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.footnote)
                            .accessibilityIdentifier("network.section")
                        }
                        if roomy || showsSection {
                            if let section = preview.longSection {
                                LongSectionView(chart: LongSectionChart(section), length: section.length, language: session.language)
                            }
                            if let parts = preview.costParts {
                                CostPartsView(parts: parts, language: session.language)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // Decision 107: how the track is built is chosen for the player
    // (ground, smooth, easy grade; decision 383: snapping is beside
    // Double); changing it is one tap
    // further away, folded until wanted.
    private var advancedButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showsAdvanced.toggle() }
        } label: {
            Label {
                Text(verbatim: NetworkOptionsEntry.title(in: session.language))
            } icon: {
                Image(systemName: showsAdvanced ? "chevron.down" : "chevron.right")
            }
        }
        .accessibilityValue(Text(verbatim: advancedSummary))
        .accessibilityIdentifier("network.advanced")
    }

    /// Decision 204: a second track 5 m beside each stretch, in one step;
    /// which side is among the folded options. Decision 247, later: on
    /// while a traced stretch is double because the real line is.
    private var doubleToggle: some View {
        Toggle(isOn: $session.networkDoubleShown) {
            Text(verbatim: session.language.text("Double", "複線"))
        }
        .toggleStyle(OnOffButtonToggleStyle())
        .accessibilityIdentifier("network.double")
    }

    /// Off: every tap is a new point, for a parallel track a few metres
    /// beside another (closer than a tap reaches). Decision 383: beside
    /// Double, not among the folded options.
    private var snapToggle: some View {
        Toggle("Snap to track", isOn: $session.networkSnapsToTrack)
            .toggleStyle(OnOffButtonToggleStyle())
            .accessibilityIdentifier("network.snap")
    }

    /// Decision 213: on a real-world map, follow the real railway drawn
    /// under it.
    @ViewBuilder
    private var traceToggle: some View {
        if session.canTraceRealRailway {
            Toggle(isOn: $session.networkTracesRealRailway) {
                Text(verbatim: session.language.text("Trace real", "沿真實鐵路"))
            }
            .toggleStyle(OnOffButtonToggleStyle())
            .accessibilityIdentifier("network.trace")
        }
    }

    private var clearButton: some View {
        Button("Clear") {
            session.clearNetworkDraft()
        }
        .disabled(session.networkStart == nil)
    }

    /// The structure, the height of new nodes, and how the track follows
    /// other track and the ground (decision 107: folded by default).
    private var advancedOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Decision 184, later: a menu the ticks leave alone.
                let language = session.language
                TickStable(StableKey(session.networkStructure, language)) {
                    Picker("Structure", selection: $session.networkStructure) {
                        ForEach(TrackStructure.offered, id: \.self) { structure in
                            Text(structure.name(in: language)).tag(structure)
                        }
                    }
                    .pickerStyle(.menu)
                }
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
            // The second under the first where the two do not fit side
            // by side.
            ChipFlow(spacing: 8) {
                Toggle("Smooth curves", isOn: $session.networkFollowsTrack)
                Toggle("Ease the grade", isOn: $session.networkEasesGrade)
            }
            .toggleStyle(OnOffButtonToggleStyle())
            .font(.footnote)
            if session.networkDoubleShown {
                Picker(selection: $session.networkDoubleSide) {
                    Text(verbatim: session.language.text("Second track on the left", "第二條在左側")).tag(PlatformTrackSide.left)
                    Text(verbatim: session.language.text("Second track on the right", "第二條在右側")).tag(PlatformTrackSide.right)
                } label: {
                    Text(verbatim: session.language.text("Second track", "第二條軌道"))
                }
                .pickerStyle(.segmented)
                .font(.footnote)
                .accessibilityIdentifier("network.doubleSide")
            }
            // Decision 107, later: a player did not know how to lay a
            // second track beside the first.
            Text(verbatim: session.language.text(
                "Turn off Snap to track to lay a parallel track 4 m or more beside another by hand; \"Double\" lays both at once.",
                "關掉「吸附軌道」可以自己鋪相距 4 m 以上的平行軌；「複線」會一次鋪好兩條。"
            ))
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .transition(.opacity)
    }

    /// The options folded away, in a line: the structure, and those of the
    /// two switches that are off.
    private var advancedSummary: String {
        let language = session.language
        var parts = [session.networkStructure.name(in: language)]
        if !session.networkFollowsTrack { parts.append(language.text("sharp curves", "不平順曲線")) }
        if !session.networkEasesGrade { parts.append(language.text("steep grade", "不緩和坡度")) }
        if session.networkDoubleShown {
            parts.append(session.networkDoubleSide == .left
                ? language.text("second track left", "第二條在左") : language.text("second track right", "第二條在右"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Passing loop

    /// Decision 204: which side of the picked single track the loop goes,
    /// by compass, and why it cannot go there (the inspector says what the
    /// tap picked).
    private var passingLoopOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let point = session.networkEdgePoint {
                Picker(selection: $session.networkLoopSide) {
                    ForEach(PlatformTrackSide.allCases, id: \.self) { side in
                        Text(verbatim: session.edgeSideText(side, at: point)).tag(side)
                    }
                } label: {
                    Text(verbatim: session.language.text("Side", "側"))
                }
                .pickerStyle(.segmented)
                .font(.footnote)
                .accessibilityIdentifier("network.loopSide")
            }
        }
    }

    // MARK: - Depot

    /// Decision 214: how many sidings, and which side of the picked end
    /// they fan out to, by compass (the inspector says what the tap picked
    /// and why it cannot go there).
    private var depotOptions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $session.networkDepotSidings, in: DepotYard.sidings) {
                Text(verbatim: session.language.text("\(session.networkDepotSidings) sidings", "\(session.networkDepotSidings) 股停車線"))
                    .font(.footnote)
                    .monospacedDigit()
            }
            .accessibilityIdentifier("network.depotSidings")
            if session.networkDepotSidings > 1, session.networkDepotEnd != nil {
                Picker(selection: $session.networkDepotSide) {
                    ForEach(PlatformTrackSide.allCases, id: \.self) { side in
                        Text(verbatim: session.depotSideText(side) ?? "").tag(side)
                    }
                } label: {
                    Text(verbatim: session.language.text("Side", "側"))
                }
                .pickerStyle(.segmented)
                .font(.footnote)
                .accessibilityIdentifier("network.depotSide")
            }
        }
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
            // Decision 507: how the station's platforms and tracks stand,
            // picked before ✓ builds them all; a layout for the other kind
            // of track than the one tapped is greyed with why.
            let layouts = session.stationLayoutChoices
            TickStable(StableKey(layouts, session.networkStationLayout)) {
                // A Menu, not a menu Picker: a Picker shows only the
                // chosen value without its label, and does not grey the
                // rows that do not fit.
                HStack {
                    Text(verbatim: session.language.text("Platform layout", "月台排法"))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Menu {
                        ForEach(layouts) { choice in
                            Button {
                                session.stationLayout = choice.layout
                            } label: {
                                if choice.layout == session.networkStationLayout {
                                    Label(choice.title, systemImage: "checkmark")
                                } else {
                                    Text(verbatim: choice.title)
                                }
                            }
                            .disabled(!choice.fits)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: session.networkStationLayout.title(in: session.language))
                            Image(systemName: "chevron.up.chevron.down")
                                .imageScale(.small)
                        }
                        .font(.footnote)
                    }
                    .accessibilityIdentifier("network.stationLayout")
                }
            }
            Text(verbatim: session.networkStationLayout.summary(in: session.language))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Stepper(value: $session.platformCars, in: Train.minimumCars...Train.maximumCars) {
                Text(session.platformLengthText())
                    .font(.footnote)
                    .monospacedDigit()
            }
            .accessibilityIdentifier("network.platformCars")
            // Decision 184, later: drawn from the stations' names alone, so
            // a running game's ticks leave the open menu alone. Decision
            // 519: the nearest the picked track first, with how far.
            let stations = session.platformStationMenuChoices
            TickStable(StableKey(stations, session.platformStationID)) {
                Picker("Platform station", selection: $session.platformStationID) {
                    Text("New station").tag(StationID?.none)
                    ForEach(stations) { station in
                        Text(verbatim: station.title).tag(StationID?.some(station.id))
                    }
                }
                .pickerStyle(.menu)
            }
            if session.platformStationID == nil {
                TextField("Station name", text: $session.stationName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            platformRemovals(showsPlace: true)
        }
    }

    // MARK: - Removing platforms

    /// A button for each platform on the picked track, which removes it
    /// (56.1: track with a platform on it cannot be removed, and players
    /// found no way to remove the platform). The platform mode also says
    /// where along the track each lies.
    private func platformRemovals(showsPlace: Bool) -> some View {
        ForEach(Array(session.platformsOnPickedEdge.enumerated()), id: \.element) { index, platform in
            // The button beside the place where they fit, else under it:
            // squeezed beside it, the words stood one character to a line.
            ChipFlow(spacing: 8) {
                if showsPlace {
                    Text(verbatim: session.platformText(platform))
                        .font(.footnote)
                        .monospacedDigit()
                }
                removePlatformButton(platform, index: index)
            }
        }
    }

    private func removePlatformButton(_ platform: TrackPlatform, index: Int) -> some View {
        Button(role: .destructive) {
            session.removeNetworkPlatform(platform)
        } label: {
            Label {
                Text(verbatim: session.removePlatformTitle(platform))
            } icon: {
                Image(systemName: "trash")
            }
        }
        .buttonStyle(.bordered)
        .font(.footnote)
        .accessibilityIdentifier("network.removePlatform.\(index)")
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

/// A switch drawn as a button that shows whether it is on (decision 107,
/// later; a player's report): on, filled with the accent colour and a tick,
/// so it does not rest on the colour alone; off, the bordered button the
/// other buttons beside it are.
private struct OnOffButtonToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let button = Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 4) {
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                configuration.label
            }
        }
        return Group {
            if configuration.isOn {
                button.buttonStyle(.borderedProminent).tint(Theme.primary)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
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

/// Decision 468, later: the real line for sale a trace runs along, what it
/// costs as it is, what the company lacks for it, and a button to its
/// purchase card.
private struct TracedSaleRow: View {
    let sale: TracedSaleHint
    let language: DisplayLanguage
    let buy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "signature")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.primary)
                Text(verbatim: sale.text)
                    .font(.footnote)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("network.forSale")
            }
            if let shortfall = sale.shortfall {
                Text(verbatim: shortfall)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.warning)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("network.forSale.short")
            }
            Button(action: buy) {
                Label {
                    Text(verbatim: TracedSaleHint.buttonTitle(in: language))
                } icon: {
                    Image(systemName: "signature")
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .font(.footnote)
            .accessibilityIdentifier("network.forSale.buy")
        }
        .padding(.top, 2)
    }
}
