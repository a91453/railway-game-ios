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
    /// Closes it (decision 106: shown beside the map, not presented, so
    /// the environment's dismiss would do nothing).
    @Environment(GameScreenState.self) private var screen
    /// The name being typed for the station, while its rename alert is up.
    @State private var renaming: String?
    /// Whether the demolish confirmation is up.
    @State private var confirmingRemoval = false
    /// The selected station's trips by hour and by station, worked out off
    /// the main actor (``RidershipKey``): drawn from the world on every
    /// tick, they held the main thread for seconds on a real-world map,
    /// and the panel stopped halfway as it slid in.
    @State private var ridership: (key: RidershipKey, value: StationRidership)?
    /// Whether the "arriving soon" board is open (decision 178); kept for
    /// the next station and the next launch.
    @AppStorage("stationBoardExpanded") private var boardExpanded = true
    /// Decision 184: whether the searchable list of stations is up, and
    /// what was typed in it.
    @State private var choosingStation = false
    @State private var stationSearch = ListSearch()

    var body: some View {
        NavigationStack {
            Form {
                if let station = session.selectedStation {
                    departureBoardSection(station)
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
                    depotSection
                    transferSection(station)
                    platformsSection(station)
                    realStationSection(station)
                    catchmentPopulationSection(station)
                    landSection(station)
                    demandSection(station)
                    eventsSection(station)
                    ridershipSections(station)
                    passengersSection(station)
                    freightSection(station)
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
                        screen.panel = nil
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                StatusBanner(session: session, announces: false)
            }
        }
        .task(id: RidershipKey(world: session.world, station: session.selectedStationID)) {
            await workOutRidership()
        }
    }

    /// Works out the selected station's ridership for the world as it is,
    /// off the main actor; kept until what it depends on changes.
    private func workOutRidership() async {
        let key = RidershipKey(world: session.world, station: session.selectedStationID)
        guard let id = key.station else { return }
        let world = session.world
        let value = await Task.detached(priority: .userInitiated) {
            world.stationRidership(of: id)
        }.value
        guard !Task.isCancelled else { return }
        ridership = (key, value)
    }

    /// Decision 178: the trains due at the station, a direction at a time,
    /// soonest first (``DepartureBoard``, the `Railway/` site's board):
    /// the line's colour, the train, where it goes, and in how many minutes
    /// (or "Arriving" under one, "Boarding" at the platform); a late train
    /// carries "N min late" from its lateness, a fast train that does not
    /// call "Passes", and a fixed-timetable line's runs not yet sent out
    /// are listed at their timetable's time. Read from the world on every
    /// tick; collapsible.
    private func departureBoardSection(_ station: Station) -> some View {
        let language = session.language
        let board = DepartureBoard(world: session.world, station: station.id)
        return Section {
            DisclosureGroup(isExpanded: $boardExpanded) {
                if board.isEmpty {
                    Text(verbatim: language.text("No train is due in the next three hours.", "未來三小時沒有列車進站。"))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(board.directions) { direction in
                    Text(verbatim: direction.endsHere
                        ? language.text("Ending here", "抵達本站")
                        : language.text("To \(session.world.station(id: direction.destination)?.name ?? "")", "往 \(session.world.station(id: direction.destination)?.name ?? "")"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(direction.rows) { row in
                        departureRow(row, language: language)
                    }
                }
            } label: {
                Label {
                    Text(verbatim: language.text("Arriving Soon", "即將進站"))
                } icon: {
                    Image(systemName: "clock")
                }
            }
            .accessibilityIdentifier("station.board")
        }
    }

    private func departureRow(_ row: DepartureBoard.Row, language: DisplayLanguage) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.lineColor(row.line, custom: row.color))
                .frame(width: 6, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.trainName.isEmpty ? row.lineName : row.trainName)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: departureDetail(row, language: language))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            if let late = row.lateText(in: language) {
                Text(verbatim: late)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.25)))
                    .foregroundStyle(Color.orange)
            }
            if row.passes {
                Text(verbatim: language.text("Passes", "通過"))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.textSecondary.opacity(0.2)))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(verbatim: row.awayText(in: language))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(row.isBoarding ? Color.green : Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("station.board.row")
    }

    /// "Line 1 · to East", "Line 1 · ends here" or the line alone.
    private func departureDetail(_ row: DepartureBoard.Row, language: DisplayLanguage) -> String {
        let destination = session.world.station(id: row.destination)?.name ?? ""
        if row.endsHere { return row.lineName + " · " + language.text("ends here", "終點到達") }
        return row.lineName + " · " + language.text("to \(destination)", "往 \(destination)")
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

    /// Decision 214: make the station a depot (decision 209), or an
    /// ordinary one again, through `GameSession.setSelectedStationDepot(_:)`;
    /// off limits, with why, while a line stops here or keeps its trains
    /// here.
    @ViewBuilder private var depotSection: some View {
        if let depot = session.selectedStationDepotSwitch {
            Section {
                Button {
                    session.setSelectedStationDepot(!depot.isDepot)
                } label: {
                    Label {
                        Text(verbatim: depot.title(in: session.language))
                    } icon: {
                        Image("MapGlyphDepot").renderingMode(.template)
                    }
                }
                .disabled(depot.problem != nil)
                .accessibilityIdentifier("station.depot")
            } footer: {
                Text(verbatim: depot.problem ?? StationDepotSwitch.note(in: session.language))
            }
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
            // TestFlight 54.1: built from the stations' names alone, so a
            // running game's ticks leave the open menu alone.
            TransferLinkMenu(session: session, choices: session.transferMenuChoices(for: station.id), language: language)
                .equatable()
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
    /// island or side, on either side of its track; and a button that
    /// removes it (`GameSession.removeNetworkPlatform(_:)`).
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
                // Decision 184, later: a menu the ticks leave alone.
                let choices = session.platformTrackMenuChoices(beside: platform)
                TickStable(StableKey(index, platform, choices, language)) {
                    Menu {
                        ForEach(choices) { choice in
                            Button {
                                session.addPlatformTrack(beside: platform, layout: choice.id.layout, side: choice.id.side)
                            } label: {
                                Text(verbatim: choice.title)
                                if let detail = choice.detail {
                                    Text(verbatim: detail)
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
                // 56.1: a platform can be removed here too (Undo brings it
                // back); the track under it then can be.
                Button(role: .destructive) {
                    session.removeNetworkPlatform(platform)
                } label: {
                    Label {
                        Text(verbatim: language.text("Remove platform \(index + 1)", "拆除第 \(index + 1) 月台"))
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
                .accessibilityIdentifier("station.removePlatform.\(index)")
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
    /// Freight (decision 155): the station's freight yard, what it holds and
    /// the industry round it makes, or the button that builds one. Shown
    /// only in a game with freight, last in the form.
    @ViewBuilder
    private func freightSection(_ station: Station) -> some View {
        let language = session.language
        let world = session.world
        if world.hasFreight {
            Section {
                // Decision 156: the station's building materials.
                if let materials = world.materialsText(at: station.id, in: language) {
                    Text(verbatim: materials)
                        .font(.footnote)
                        .accessibilityIdentifier("station.materials")
                }
                if let text = world.freightYardText(at: station.id, in: language) {
                    Text(verbatim: text)
                        .font(.subheadline)
                        .accessibilityIdentifier("station.freight.status")
                    // Decision 156: what the yard sends.
                    if world.hasBuildingMaterials {
                        // Decision 184, later: a menu the ticks leave alone.
                        let product = world.freightFacility(at: station.id)?.product ?? .goods
                        TickStable(StableKey(product, language)) {
                            Picker(selection: Binding(
                                get: { product },
                                set: { session.setFreightProductAtSelectedStation($0) }
                            )) {
                                ForEach(CargoKind.allCases, id: \.self) { kind in
                                    Text(verbatim: kind.title(in: language)).tag(kind)
                                }
                            } label: {
                                Text(verbatim: language.text("Sends", "出貨"))
                            }
                            .accessibilityIdentifier("station.freight.product")
                        }
                    }
                    Button(role: .destructive) {
                        session.removeFreightYardAtSelectedStation()
                    } label: {
                        Label {
                            Text(verbatim: language.text("Remove Freight Yard", "拆除貨運場"))
                        } icon: {
                            Image(systemName: "shippingbox")
                        }
                    }
                    .accessibilityIdentifier("station.freight.remove")
                } else {
                    Button {
                        session.buildFreightYardAtSelectedStation()
                    } label: {
                        Label {
                            Text(verbatim: language.text(
                                "Build Freight Yard \(Freight.facilityCost.moneyText)",
                                "蓋貨運場 \(Freight.facilityCost.moneyText)"
                            ))
                        } icon: {
                            Image(systemName: "shippingbox")
                        }
                    }
                    .accessibilityIdentifier("station.freight.build")
                }
            } header: {
                Text(verbatim: language.text("Freight", "貨運"))
            } footer: {
                Text(verbatim: world.freightYardHelp(in: language))
            }
        }
    }

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

    /// Chooses another station: a menu, or past ``ListSearchField/minimumRows``
    /// stations a list that can be searched by name (decision 184).
    @ViewBuilder
    private var stationMenu: some View {
        if session.world.stations.count < ListSearchField.minimumRows {
            // Decision 184, later: drawn from the stations' names alone, so
            // a running game's ticks leave the open menu alone.
            let stations = session.stationMenuChoices
            TickStable(stations) {
                Menu {
                    ForEach(stations) { station in
                        Button(station.title) {
                            session.selectStation(station.id)
                        }
                    }
                } label: {
                    Image(systemName: "tram.fill")
                }
                .accessibilityLabel("Choose a station")
            }
            .disabled(stations.isEmpty)
        } else {
            Button {
                stationSearch = ListSearch()
                choosingStation = true
            } label: {
                Image(systemName: "tram.fill")
            }
            .accessibilityLabel("Choose a station")
            .accessibilityIdentifier("station.choose")
            .sheet(isPresented: $choosingStation) {
                stationChooser
            }
        }
    }

    /// Every station, the ones whose name matches what was typed.
    private var stationChooser: some View {
        let language = session.language
        let shown = session.world.stations(matching: stationSearch)
        return NavigationStack {
            List {
                if shown.isEmpty {
                    ListSearchEmpty(text: language.text("No station matches.", "沒有符合的車站。"))
                }
                ForEach(shown) { station in
                    Button {
                        session.selectStation(station.id)
                        choosingStation = false
                    } label: {
                        HStack {
                            Text(verbatim: station.name)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 8)
                            if station.id == session.selectedStationID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.primary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(station.id == session.selectedStationID ? .isSelected : [])
                }
            }
            .searchable(text: $stationSearch.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(verbatim: language.text("Search stations", "搜尋車站")))
            .navigationTitle(Text(verbatim: language.text("Choose a Station", "選擇車站")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        choosingStation = false
                    } label: {
                        Text(verbatim: language.text("Cancel", "取消"))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

    /// Item 4: the demand events announced or running at the station, and
    /// (decision 154) the public holidays announced or running everywhere.
    @ViewBuilder
    private func eventsSection(_ station: Station) -> some View {
        let lines = session.world.holidayTexts(in: session.language) + session.world.weatherTexts(at: station.id, in: session.language)
            + session.world.demandEventTexts(at: station.id, in: session.language)
        if !lines.isEmpty {
            Section {
                // By position: two typhoons alike can read the same.
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
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

    /// The trips by hour and by station, once worked out for this station;
    /// the last ones while they are worked out again.
    @ViewBuilder
    private func ridershipSections(_ station: Station) -> some View {
        if let ridership, ridership.key.station == station.id {
            if let flow = ridership.value.flow {
                flowSection(flow)
            }
            pairsSection(ridership.value.pairs)
        } else {
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(verbatim: session.language.text("Working out its trips…", "正在計算客流…"))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("Trips a day by station")
            }
        }
    }

    private func pairsSection(_ pairs: [StationDemandPair]) -> some View {
        Section {
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
            // Decision 179: how many got on and off here yesterday.
            if let flow = session.world.stationFlowText(at: station.id, in: session.language) {
                Label(flow, systemImage: "arrow.left.arrow.right")
                    .font(.footnote)
                    .monospacedDigit()
                    .accessibilityIdentifier("station.flow.yesterday")
            }
            // TestFlight 59.1: who waits for which line and way, how many
            // of them change trains here, and whether the line has closed.
            ForEach(session.world.waitingBreakdown(at: station.id, in: session.language), id: \.self) { group in
                Label(group, systemImage: "person.2")
                    .font(.footnote)
                    .monospacedDigit()
            }
            .accessibilityIdentifier("station.waiting")
            if let note = session.world.crowdedStationNote(at: station.id, in: session.language) {
                Text(verbatim: note)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("station.crowdedNote")
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

/// What a station's ridership (``GameWorld/stationRidership(of:)``) is
/// worked out from, so the panel works it out again only when one of them
/// changes, not on every tick: the station and what its day reads
/// (``RidershipInputs``, shared with the map's travel layers).
private struct RidershipKey: Equatable {
    let station: StationID?
    let inputs: RidershipInputs

    init(world: GameWorld, station: StationID?) {
        self.station = station
        inputs = RidershipInputs(world: world)
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
    /// text size and dark mode; decision 91's schools and services, a
    /// mortarboard.
    var systemImage: String {
        switch self {
        case .residential: "house.fill"
        case .office: "building.2.fill"
        case .shopping: "cart.fill"
        case .scenic: "mountain.2.fill"
        case .civic: "graduationcap.fill"
        }
    }
}

/// The menu of the nearest stations to link a station with for transfers
/// (decision 81), each with how far away it is. An equatable view of what
/// it lists: the game loop replaces the world every tick, and an open
/// native menu drawn again is rebuilt, back to its top (TestFlight 54.1).
private struct TransferLinkMenu: View, Equatable {
    let session: GameSession
    let choices: [MenuChoice<StationID>]
    let language: DisplayLanguage

    nonisolated static func == (lhs: TransferLinkMenu, rhs: TransferLinkMenu) -> Bool {
        lhs.session === rhs.session && lhs.choices == rhs.choices && lhs.language == rhs.language
    }

    var body: some View {
        Menu {
            ForEach(choices) { candidate in
                Button {
                    session.linkSelectedStationForTransfer(with: candidate.id)
                } label: {
                    Text(verbatim: candidate.title)
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
    }
}
