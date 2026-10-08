import GameCore
import GamePresentation
import SwiftUI

/// The selected station's ridership (Stage C2), after the `Ci/`
/// reference's custom ridership panel: what kind of place it serves (the
/// four presets) and the trips it starts a day, its trips by hour as they
/// enter and leave it, copying its demand to another station or to every
/// station of its lines, and, read-only, the trips to and from each other
/// station and its passenger ledger.
///
/// Shown in a sheet that leaves the map usable at half height, so another
/// station can be selected while it is open. Everything shown is read from
/// `session.world` when the view is drawn, and every control calls a
/// `GameSession` method that applies `GameWorld` commands.
struct StationPanel: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    /// The name being typed for the station, while its rename alert is up.
    @State private var renaming: String?
    /// Whether the demolish confirmation is up.
    @State private var confirmingRemoval = false

    var body: some View {
        NavigationStack {
            Form {
                if let station = session.selectedStation {
                    Section {
                        Button {
                            renaming = station.name
                        } label: {
                            Label {
                                Text(verbatim: session.language.text("Rename Station", "車站更名"))
                            } icon: {
                                Image(systemName: "pencil")
                            }
                        }
                        .accessibilityIdentifier("station.rename")
                    }
                    operationSection(station)
                    transferSection(station)
                    platformsSection(station)
                    realStationSection(station)
                    catchmentPopulationSection(station)
                    landSection(station)
                    demandSection(station)
                    eventsSection(station)
                    if let flow = session.world.stationFlow(of: station.id) {
                        flowSection(flow)
                    }
                    pairsSection(station)
                    passengersSection(station)
                    removalSection(station)
                } else {
                    Section {
                        Text("Select a station on the map, or choose one above.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .navigationTitle(session.selectedStation.map { Text(verbatim: $0.name) } ?? Text("Station"))
            .navigationBarTitleDisplayMode(.inline)
            .renameAlert(
                title: session.language.text("Rename Station", "車站更名"),
                name: $renaming,
                language: session.language
            ) { name in
                session.renameSelectedStation(to: name)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    stationMenu
                }
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

    /// How the station is run (Phase 5F, the reference's `operationMode`):
    /// normal, flow control or closed, through
    /// `GameSession.setSelectedStationOperationMode(_:)`.
    private func operationSection(_ station: Station) -> some View {
        let mode = session.world.station(id: station.id)?.operationMode ?? .normalFlow
        return Section {
            Picker(selection: Binding(
                get: { mode },
                set: { session.setSelectedStationOperationMode($0) }
            )) {
                ForEach(StationOperationMode.allCases, id: \.self) { mode in
                    Text(verbatim: mode.title(in: session.language)).tag(mode)
                }
            } label: {
                Text(verbatim: session.language.text("Operation", "營運狀態"))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("station.operation")
        } footer: {
            Text(verbatim: mode.detail(in: session.language))
        }
    }

    /// The station's transfer group (decision 81, MapBuilder's
    /// interchanges): the stations passengers walk to from here however far
    /// apart, a menu of the nearest stations to link it with, and leaving
    /// the group.
    private func transferSection(_ station: Station) -> some View {
        let language = session.language
        let group = session.world.transferGroupText(of: station.id)
        return Section {
            if let group {
                Label {
                    Text(verbatim: group)
                } icon: {
                    Image(systemName: "arrow.triangle.swap")
                }
                .accessibilityIdentifier("station.transferGroup")
            }
            Menu {
                ForEach(session.world.transferCandidates(for: station.id)) { candidate in
                    Button {
                        session.linkSelectedStationForTransfer(with: candidate.id)
                    } label: {
                        Text(verbatim: "\(candidate.name) · \(NetworkBuilding.lengthText(session.world.distanceUnits(between: station.id, and: candidate.id) ?? 0, in: language))")
                    }
                }
            } label: {
                Label {
                    Text(verbatim: language.text("Link for Transfers", "設為轉乘"))
                } icon: {
                    Image(systemName: "link")
                }
            }
            .accessibilityIdentifier("station.linkTransfer")
            if group != nil {
                Button(role: .destructive) {
                    session.unlinkSelectedStationTransfer()
                } label: {
                    Text(verbatim: language.text("Leave Transfer Group", "離開轉乘群組"))
                }
                .accessibilityIdentifier("station.unlinkTransfer")
            }
        } header: {
            Text(verbatim: language.text("Transfers", "轉乘"))
        } footer: {
            Text(verbatim: language.text(
                "Passengers walk between the stations of a group to change trains, however far apart, at 5 km/h. Without one they walk only to stations under 450 m away.",
                "同一轉乘群組的車站之間，乘客不論距離都會以時速 5 公里步行轉乘；沒有群組時只會走到 450 公尺內的車站。"
            ))
        }
    }

    /// The station's platforms, each with a menu that adds a platform track
    /// beside it in one step (`GameSession.addPlatformTrack(beside:layout:side:)`):
    /// island or side, on either side of its track.
    private func platformsSection(_ station: Station) -> some View {
        let language = session.language
        let platforms = session.world.trackPlatforms(of: station.id)
        return Section {
            if platforms.isEmpty {
                Text(verbatim: language.text("No platform yet. Add one with the network tool.", "還沒有月台。請用路網工具加上月台。"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(Array(platforms.enumerated()), id: \.offset) { index, platform in
                Menu {
                    ForEach(PlatformTrackLayout.allCases, id: \.self) { layout in
                        ForEach(PlatformTrackSide.allCases, id: \.self) { side in
                            Button {
                                session.addPlatformTrack(beside: platform, layout: layout, side: side)
                            } label: {
                                Text(verbatim: "\(layout.title(in: language)) · \(session.platformTrackSideText(side, of: platform))")
                            }
                        }
                    }
                } label: {
                    Label {
                        Text(verbatim: language.text("Platform \(index + 1): add a platform track", "第 \(index + 1) 月台：加月台軌道"))
                    } icon: {
                        Image(systemName: "plus.rectangle.on.rectangle")
                    }
                }
                .accessibilityIdentifier("station.platformTrack.\(index)")
            }
        } header: {
            Text(verbatim: language.text("Platforms", "月台"))
        } footer: {
            Text(verbatim: language.text(
                "A platform track runs beside the platform with a turnout at each end. Island: one platform between the tracks, 11 m apart. Side: a platform outside each track, 5 m apart.",
                "月台軌道會建在月台旁，兩端各有一組轉轍器。島式：兩軌之間共用一座月台，軌距 11 公尺。岸式：兩軌外側各有月台，軌距 5 公尺。"
            ))
        }
    }

    /// Demolishing the station (decision 83), after a confirmation that
    /// says what goes with it, through `GameSession.removeSelectedStation()`;
    /// Undo puts it back.
    private func removalSection(_ station: Station) -> some View {
        let language = session.language
        return Section {
            Button(role: .destructive) {
                confirmingRemoval = true
            } label: {
                Label {
                    Text(verbatim: language.text("Demolish Station", "拆除車站"))
                } icon: {
                    Image(systemName: "trash")
                }
            }
            .accessibilityIdentifier("station.remove")
            .confirmationDialog(
                Text(verbatim: language.text("Demolish \(station.name)?", "要拆除 \(station.name) 嗎？")),
                isPresented: $confirmingRemoval,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    session.removeSelectedStation()
                } label: {
                    Text(verbatim: language.text("Demolish", "拆除"))
                }
                .accessibilityIdentifier("station.remove.confirm")
            } message: {
                Text(verbatim: language.text(
                    "Its platforms go, and its lines no longer call there; a line left with too few stops goes too. Passengers waiting there leave. Nothing is refunded.",
                    "它的月台會拆除，路線不再停靠這站；剩下的車站不足的路線也會刪除。在站裡等車的乘客會離開。不退還費用。"
                ))
            }
        } footer: {
            Text(verbatim: language.text(
                "Stop the service of every train that calls here or carries its passengers first; take a line's train off its line to stop it.",
                "請先停止停靠這站或載著這站乘客的列車的服務；路線的列車要先離開路線才能停止。"
            ))
        }
    }

    /// Chooses another station.
    private var stationMenu: some View {
        Menu {
            ForEach(session.world.stations) { station in
                Button(station.name) {
                    session.selectStation(station.id)
                }
            }
        } label: {
            Image(systemName: "tram.fill")
        }
        .accessibilityLabel("Choose a station")
        .disabled(session.world.stations.isEmpty)
    }

    // MARK: - Real station

    /// What the real data knows of the station, where it is a real one:
    /// codes, grade, address, transfers (`GameSession.realStationDetails(of:)`).
    @ViewBuilder
    private func realStationSection(_ station: Station) -> some View {
        let details = session.realStationDetails(of: station.id)
        if !details.isEmpty {
            Section {
                ForEach(details, id: \.self) { line in
                    Text(verbatim: line)
                        .font(.footnote)
                }
            } header: {
                Text("Real Station")
            }
        }
    }

    // MARK: - Catchment & Demographics

    @ViewBuilder
    private func catchmentPopulationSection(_ station: Station) -> some View {
        if let residents = session.stationCatchmentPopulation(of: station.id) {
            let estimatedTrips = StationDemand.realWorld(residents: residents).dailyTrips
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label {
                            Text(verbatim: session.language.text("800m Catchment Population", "800m 車站腹地人口"))
                                .font(.subheadline.weight(.semibold))
                        } icon: {
                            Image(systemName: "person.3.sequence.fill")
                                .foregroundStyle(Theme.primary)
                        }

                        Spacer()

                        Text(verbatim: "\(residents.formatted()) \(session.language.text("people", "人"))")
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.primary)
                    }

                    Text(verbatim: session.language.text(
                        "~10 min walking radius · Generates ~\(estimatedTrips.formatted()) trips/day (40 trips / 100 residents)",
                        "約 10 分鐘步行服務範圍 · 衍生約 \(estimatedTrips.formatted()) 旅次/日（每百人約 40 旅次）"
                    ))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 2)
            } header: {
                Text(verbatim: session.language.text("Catchment & Demographics", "站區腹地與人口"))
            }
        }
    }

    /// Who lives and works within 800 m (Phase 6a): the world's land, and
    /// the buildings standing there (Phase 6c-1).
    @ViewBuilder
    private func landSection(_ station: Station) -> some View {
        if let text = session.world.landCatchmentText(of: station.id, in: session.language) {
            Section {
                Text(verbatim: text)
                    .font(.footnote)
                    .monospacedDigit()
                    .accessibilityIdentifier("station.land")
                // Phase 6c-1: the cells there by their buildings' density.
                if let buildings = session.world.catchmentBuildingsText(of: station.id, in: session.language) {
                    Text(verbatim: buildings)
                        .font(.footnote)
                        .monospacedDigit()
                        .accessibilityIdentifier("station.buildings")
                }
                // Phase 6c-2: what town growth measured, and whether full
                // buildings rise.
                if let growth = session.world.cityGrowthText(of: station.id, in: session.language) {
                    Text(verbatim: growth)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("station.cityGrowth")
                }
                // Phase 6c-3: what the land within 800 m is worth.
                if let value = session.world.catchmentLandValueText(of: station.id, in: session.language) {
                    Text(verbatim: value)
                        .font(.footnote)
                        .monospacedDigit()
                        .accessibilityIdentifier("station.landValue")
                }
            } header: {
                Text(verbatim: session.language.text("Land", "土地"))
            }
        }
    }

    // MARK: - Demand

    @ViewBuilder
    private func demandSection(_ station: Station) -> some View {
        if session.canEditStationDemand {
            editableDemandSection(station)
        } else {
            // A managed company's city sets the ridership (decision 46).
            Section {
                Text(verbatim: session.world.stationDemand(of: station.id)?.displayText(in: session.language) ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                // Item 5: how the town round it has grown.
                if let growth = session.world.townGrowthText(of: station.id, in: session.language) {
                    Text(verbatim: growth)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .accessibilityIdentifier("station.growth")
                }
            } header: {
                Text("Ridership")
            } footer: {
                Text("A managed company's city sets each station's ridership. Free play can change it.")
            }
        }
    }

    /// Item 4: the demand events announced or running at the station.
    @ViewBuilder
    private func eventsSection(_ station: Station) -> some View {
        let lines = session.world.demandEventTexts(at: station.id, in: session.language)
        if !lines.isEmpty {
            Section {
                ForEach(lines, id: \.self) { line in
                    Label {
                        Text(verbatim: line)
                    } icon: {
                        Image(systemName: "person.3.fill")
                    }
                    .font(.footnote)
                }
            } header: {
                Text(verbatim: session.language.text("Events", "活動"))
            }
            .accessibilityIdentifier("station.events")
        }
    }

    private func editableDemandSection(_ station: Station) -> some View {
        let demand = session.world.stationDemand(of: station.id)
        let language = session.language
        return Section {
            HStack(spacing: 6) {
                ForEach(StationDemandKind.allCases, id: \.self) { kind in
                    let isActive = demand?.kind == kind
                    Button {
                        session.setSelectedStationDemandKind(kind)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: kind.systemImage)
                                .font(.body.weight(.semibold))
                            Text(kind.title(in: language))
                                .font(.caption2.weight(isActive ? .bold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
                    .accessibilityLabel(kind.title(in: language))
                    .accessibilityHint("Sets when its trips start and end over the day.")
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            if let demand {
                tripsStepper(demand)
            }
            Button {
                session.copySelectedStationDemand()
            } label: {
                Label("Copy Ridership", systemImage: "doc.on.doc")
            }
            .disabled(demand == nil)
            Button {
                session.pasteDemandToSelectedStation()
            } label: {
                if let copied = session.demandClipboard {
                    Label("Paste \(copied.kind.title(in: language))", systemImage: "doc.on.clipboard")
                } else {
                    Label("Paste Ridership", systemImage: "doc.on.clipboard")
                }
            }
            .disabled(session.demandClipboard == nil)
            Button {
                session.applySelectedStationDemandToItsLines()
            } label: {
                Label("Apply to Its Lines", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .disabled(demand == nil)
            if demand != nil {
                Button(role: .destructive) {
                    session.removeSelectedStationDemand()
                } label: {
                    Label("Remove Ridership", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("Ridership")
        } footer: {
            Text(demand == nil
                ? "Choose what kind of place the station serves. A station without ridership starts no trips and draws none."
                : "A preset keeps the station's daily trips. They go to the stations its lines reach that have ridership, shared by their own daily trips.")
        }
    }

    /// Steps the daily trips through ``StationDemand/dailyTripSteps``; the
    /// end that has no further step is disabled.
    private func tripsStepper(_ demand: StationDemand) -> some View {
        let above = StationDemand.dailyTrips(above: demand.dailyTrips)
        let below = StationDemand.dailyTrips(below: demand.dailyTrips)
        var increment: (() -> Void)?
        var decrement: (() -> Void)?
        if let above {
            increment = { session.setSelectedStationDailyTrips(above) }
        }
        if let below {
            decrement = { session.setSelectedStationDailyTrips(below) }
        }
        return Stepper(onIncrement: increment, onDecrement: decrement) {
            Text(StationDemand.tripsText(demand.dailyTrips, in: session.language))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityHint("Steps through 100, 200, 500, 1,000 and so on, up to 1,000,000 a day.")
    }

    // MARK: - Trips by hour

    private func flowSection(_ flow: StationFlow) -> some View {
        let now = session.world.clock.now.minuteOfDay / 60
        return Section {
            HourlyBarChart(title: "Entries", hours: flow.entries, now: now, language: session.language)
            HourlyBarChart(title: "Exits", hours: flow.exits, now: now, language: session.language)
        } header: {
            Text("Trips by hour")
        } footer: {
            Text(flow.isShape
                ? "No line links it to another station with ridership yet: the bars show how its own trips would spread over the day."
                : "Entries start their trip here and exits end it here. Tap a bar to read its hour.")
        }
    }

    // MARK: - Read-only

    private func pairsSection(_ station: Station) -> some View {
        let pairs = session.world.stationDemandPairs(of: station.id)
        return Section {
            if pairs.isEmpty {
                Text("No trips to or from other stations yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(pairs, id: \.station) { pair in
                Text(session.world.demandPairText(pair, in: session.language))
                    .font(.footnote)
                    .monospacedDigit()
            }
        } header: {
            Text("Trips a day by station")
        }
    }

    private func passengersSection(_ station: Station) -> some View {
        Section {
            ForEach(session.world.waitingText(at: station.id, in: session.language), id: \.self) { group in
                Label(group, systemImage: "person.2")
                    .font(.footnote)
                    .monospacedDigit()
            }
            ForEach(session.world.passengerLedgerRows(of: station.id, in: session.language), id: \.title) { row in
                LabeledContent(row.title, value: row.countText)
                    .font(.footnote)
                    .monospacedDigit()
            }
        } header: {
            Text("Passengers")
        } footer: {
            Text("Everyone released here is waiting, riding, arrived, left a full station or gave up. Left behind counts the times a full train left people waiting.")
        }
    }
}

/// One single-series chart of trips by hour of the day, after the
/// reference's canvas (`drawStationFlowAdjustCanvas`): a bar an hour from
/// one baseline, the current hour in the accent colour and the rest muted.
/// Tapping a bar, or swiping up and down with VoiceOver, reads that hour
/// instead; the text below always says the day's total, the busiest hour
/// and the hour shown, so nothing depends on colour alone.
private struct HourlyBarChart: View {
    let title: LocalizedStringKey
    let hours: [Int64]
    let now: Int
    let language: DisplayLanguage
    @State private var picked: Int?

    private static let height: CGFloat = 64

    var body: some View {
        let shown = picked ?? now
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            bars(highlighting: shown)
            axis
            Text(verbatim: StationFlow.summaryText(of: hours, in: language))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: StationFlow.hourText(shown, of: hours, in: language))
                .font(.caption.weight(.semibold))
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(verbatim: "\(StationFlow.hourText(shown, of: hours, in: language)). \(StationFlow.summaryText(of: hours, in: language))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: picked = (shown + 1) % 24
            case .decrement: picked = (shown + 23) % 24
            @unknown default: break
            }
        }
    }

    private func bars(highlighting shown: Int) -> some View {
        let top = CGFloat(max(hours.max() ?? 0, 1))
        return GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                        .fill(hour == shown ? Theme.primary : Theme.primary.opacity(0.25))
                        .frame(height: max(1, Self.height * CGFloat(hours[hour]) / top))
                        .frame(maxWidth: 24, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                let width = max(proxy.size.width, 1)
                picked = min(23, max(0, Int(tap.location.x / width * 24)))
            })
        }
        .frame(height: Self.height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.textSecondary.opacity(0.4))
                .frame(height: 1)
        }
    }

    /// Hours 0, 6, 12 and 18 under their bars.
    private var axis: some View {
        HStack(spacing: 2) {
            ForEach(0..<24, id: \.self) { hour in
                Color.clear
                    .frame(maxWidth: 24, minHeight: 12, maxHeight: 12)
                    .overlay(alignment: .leading) {
                        if hour % 6 == 0 {
                            Text(verbatim: "\(hour)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize()
                        }
                    }
            }
        }
    }
}

extension StationDemandKind {
    /// The reference's preset icons (`station-icon-residential`, the
    /// office building, `station-icon-shopping`'s cart and
    /// `station-icon-scenic`'s mountains) as SF Symbols, which follow the
    /// text size and dark mode.
    var systemImage: String {
        switch self {
        case .residential: "house.fill"
        case .office: "building.2.fill"
        case .shopping: "cart.fill"
        case .scenic: "mountain.2.fill"
        }
    }
}
