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

    var body: some View {
        NavigationStack {
            Form {
                if let station = session.selectedStation {
                    demandSection(station)
                    if let flow = session.world.stationFlow(of: station.id) {
                        flowSection(flow)
                    }
                    pairsSection(station)
                    passengersSection(station)
                } else {
                    Section {
                        Text("Select a station on the map, or choose one above.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(session.selectedStation.map { Text(verbatim: $0.name) } ?? Text("Station"))
            .navigationBarTitleDisplayMode(.inline)
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

    /// Chooses another station by selecting its tile.
    private var stationMenu: some View {
        Menu {
            ForEach(session.world.stations) { station in
                Button(station.name) {
                    session.select(station.position)
                }
            }
        } label: {
            Image(systemName: "tram.fill")
        }
        .accessibilityLabel("Choose a station")
        .disabled(session.world.stations.isEmpty)
    }

    // MARK: - Demand

    private func demandSection(_ station: Station) -> some View {
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
                    .buttonStyle(SelectableButtonStyle(isActive: isActive))
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                        .fill(hour == shown ? Color.accentColor : Color.secondary.opacity(0.5))
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
                .fill(Color.secondary.opacity(0.4))
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
                                .foregroundStyle(.secondary)
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
