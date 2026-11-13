import GameCore
import GamePresentation
import SwiftUI

/// The sights tourists come to (decision 174): each with its stars, the
/// tourists it draws today, yesterday and this year and last, what keeps it
/// from drawing any, and a button for the next level of its souvenir shop
/// with what that does. Opened from the game menu, and by a tap on a
/// sight's stars on the map, which opens it at that sight's row, marked
/// for a moment (decision 250). Everything shown is read from
/// `session.world`; the words come from GamePresentation.
struct TourismPanel: View {
    let session: GameSession
    /// The sight tapped on the map (``SightFocus``), or `nil` from the menu.
    var focus: AttractionID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var marked: AttractionID?
    /// Whether the sights off the company's map are shown (decision 663):
    /// folded away at first, unless the map's tap is on one of them.
    @State private var showsOffMap = false
    /// Decision 695: the airports' day, worked out once when the panel
    /// opens (it asks the network who can ride to each terminal).
    @State private var airportDays: [AirportDay] = []

    var body: some View {
        let language = session.language
        let world = session.world
        // CRASH-SIGHTS: kept by the session for the day, not worked out
        // at every tick.
        let rows = session.sightsPanelRows
        // Decision 663: the sights on the company's map, then those off it,
        // nearest first, folded away.
        let onMap = rows.filter { $0.offMapMetres == nil }
        let offMap = rows.filter { $0.offMapMetres != nil }
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Text(verbatim: language.text(
                            "\(world.touristsThisYear.groupedText) tourists this year",
                            "今年觀光客 \(world.touristsThisYear.groupedText) 人次"
                        ))
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("tourism.year")
                    } footer: {
                        Text(verbatim: world.tourismHelp(in: language))
                    }
                    if !airportDays.isEmpty {
                        Section {
                            ForEach(airportDays, id: \.airport.id) { day in
                                airportRow(day)
                            }
                        } header: {
                            Text(verbatim: language.text("Airports", "機場"))
                        } footer: {
                            Text(verbatim: language.text(
                                "Flights come and go by themselves. A station of yours by a terminal brings its passengers onto your trains, and tourists set out from it to the sights.",
                                "航班自己起降，不用你經營。航廈旁有你的車站時，旅客會搭你的車，觀光客也從那裡出發去景點。"
                            ))
                        }
                    }
                    ForEach(onMap) { row in
                        Section {
                            header(row)
                            Label {
                                Text(verbatim: row.statusText)
                            } icon: {
                                Image(systemName: row.status == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(row.status == .ok ? Theme.success : Theme.warning)
                            }
                            .font(.footnote)
                            if row.hotels > 0 {
                                Text(verbatim: language.text(
                                    "\(row.hotels) hotel\(row.hotels == 1 ? "" : "s") within 800 m",
                                    "800 公尺內有 \(row.hotels) 家飯店"
                                ))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                            }
                            if let text = row.sightseeingTrainText {
                                Text(verbatim: text)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let station = row.stationName {
                                Text(verbatim: language.text("Station: \(station)", "車站：\(station)"))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let visitors = row.officialVisitorsText {
                                // Decision 724: the official count of a year.
                                Text(verbatim: visitors)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                    .accessibilityIdentifier("tourism.officialVisitors")
                            }
                            if let exhibits = row.exhibitsText {
                                // Decision 684: the company's railway museum
                                // has its exhibits, not a souvenir shop.
                                Text(verbatim: language.text(
                                    "Today \(row.today) · yesterday \(row.yesterday)",
                                    "今天 \(row.today)・昨天 \(row.yesterday)"
                                ))
                                .font(.footnote)
                                .monospacedDigit()
                                Text(verbatim: exhibits)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                    .accessibilityIdentifier("tourism.exhibits")
                                // Decision 696: and its exhibits, one by one.
                                NavigationLink {
                                    RailwayMuseumPage(session: session, closes: false)
                                } label: {
                                    Text(verbatim: language.text("See the exhibits", "參觀館藏"))
                                        .font(.footnote.weight(.semibold))
                                }
                                .accessibilityIdentifier("tourism.museum.open")
                            } else {
                                Text(verbatim: language.text(
                                    "Today \(row.today) · yesterday \(row.yesterday) · this year \(row.thisYear.groupedText) · last year \(row.lastYear.groupedText)",
                                    "今天 \(row.today)・昨天 \(row.yesterday)・今年 \(row.thisYear.groupedText)・去年 \(row.lastYear.groupedText)"
                                ))
                                .font(.footnote)
                                .monospacedDigit()
                                shop(row)
                            }
                        }
                        .listRowBackground(marked == row.id ? Theme.accent.opacity(0.18) : nil)
                    }
                    if !offMap.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: $showsOffMap) {
                                ForEach(offMap) { row in
                                    offMapRow(row)
                                        .listRowBackground(marked == row.id ? Theme.accent.opacity(0.18) : nil)
                                }
                            } label: {
                                Text(verbatim: language.text("Off your map (\(offMap.count))", "地圖外的景點（\(offMap.count)）"))
                            }
                            .accessibilityIdentifier("tourism.offMap")
                        }
                    }
                }
                // Review L19, P3-13: the airports' day, not on the main actor.
                .task { airportDays = await AirCollection.airportDays(of: world) }
                .task {
                    guard let target = SightFocus.row(for: focus, in: rows) else { return }
                    if offMap.contains(where: { $0.id == target }) { showsOffMap = true }
                    marked = target
                    // Once the sheet has laid its rows out.
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) { proxy.scrollTo(target, anchor: .top) }
                    try? await Task.sleep(for: .seconds(SightFocus.highlightSeconds))
                    withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) { marked = nil }
                }
            }
            .navigationTitle(Text(verbatim: language.text("Sights", "觀光景點")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Done", "完成"))
                    }
                    .accessibilityIdentifier("tourism.done")
                }
            }
        }
    }

    /// One airport: its name, today's flights and passengers, who rides
    /// the company's trains, yesterday's count and what would bring more.
    private func airportRow(_ day: AirportDay) -> some View {
        let language = session.language
        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: day.airport.title(in: language))
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: day.summary(in: language))
                    .font(.footnote)
                    .monospacedDigit()
                if let destinations = day.destinationsText(in: language) {
                    Text(verbatim: destinations)
                        .font(.footnote)
                        .monospacedDigit()
                }
                if let yesterday = day.yesterdayText(in: language) {
                    Text(verbatim: yesterday)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                // Decision 712: how far its flights are from opening a
                // city's map.
                if let route = day.airRouteText(in: language, routes: session.airRoutes) {
                    Text(verbatim: route)
                        .font(.footnote)
                        .monospacedDigit()
                }
                if let station = day.station, let name = session.world.station(id: station)?.name {
                    Text(verbatim: language.text("Station: \(name)", "車站：\(name)"))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let more = day.growthText(in: language) {
                    Text(verbatim: more)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } icon: {
            Image(systemName: "airplane")
                .foregroundStyle(day.station == nil || day.isClosed ? Theme.textSecondary : Theme.primary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tourism.airport.\(day.airport.id)")
    }

    private func header(_ row: AttractionRow) -> some View {
        HStack {
            // Decision 696: the museum's own mark, a star for the rest.
            (row.exhibitsText == nil ? MapGlyph.star : MapGlyph.railwayMuseum).image
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(verbatim: row.name)
                .fontWeight(.semibold)
            Spacer()
            Text(verbatim: "\(row.starsText) · \(row.kind)")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        // Where the panel scrolls to for a sight tapped on the map.
        .id(row.id)
        .accessibilityIdentifier("tourism.row.\(row.id.rawValue)")
    }

    /// A sight off the company's map (decision 663): its name, stars and
    /// how far off; nothing to build there yet.
    private func offMapRow(_ row: AttractionRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            header(row)
            if let text = row.offMapText(in: session.language) {
                Text(verbatim: text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func shop(_ row: AttractionRow) -> some View {
        let language = session.language
        if let offer = row.nextShop {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: offer.preview)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    session.investInSouvenirShop(of: row.id)
                } label: {
                    Text(verbatim: language.text(
                        "Souvenir shop level \(row.souvenir + 1) · \(offer.cost.moneyText)",
                        "名產店升到 \(row.souvenir + 1) 級・\(offer.cost.moneyText)"
                    ))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!offer.canAfford)
                .accessibilityIdentifier("tourism.shop.\(row.id.rawValue)")
            }
        } else {
            Text(verbatim: language.text("Souvenir shop at its top level (2).", "名產店已是最高等級（2 級）。"))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Decision 696: the railway museum's exhibits, one type of train at a
/// time (``RailwayMuseumGuide``): each with the catalog's picture and
/// figures, where it stands in the yard and, when the train garage has it,
/// a button that opens it there in 3D; then the types never owned, as
/// silhouettes. Opened from the museum's row of the sights panel (pushed,
/// `closes` false) and from the museum tapped on the map (a sheet of its
/// own, with a Done button).
struct RailwayMuseumPage: View {
    let session: GameSession
    let closes: Bool
    @Environment(\.dismiss) private var dismiss
    /// The exhibit open in the train garage.
    @State private var inGarage: GarageKey?

    private struct GarageKey: Identifiable {
        let id: String
    }

    var body: some View {
        let language = session.language
        let row = session.sightsPanelRows.first { $0.exhibitsText != nil }
        let guide = RailwayMuseumGuide(world: session.world, row: row, in: language)
        List {
            if let guide {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(PlacedBuildingKind.railwayMuseum.cardArt)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: guide.summary)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .accessibilityIdentifier("museum.summary")
                            Text(verbatim: guide.hint)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                let exhibits = guide.items.filter(\.isShown), waiting = guide.items.filter { !$0.isShown }
                if !exhibits.isEmpty {
                    Section {
                        ForEach(exhibits) { item in exhibit(item, language: language) }
                    } header: {
                        Text(verbatim: language.text("On show", "展出中"))
                    }
                }
                if !waiting.isEmpty {
                    Section {
                        ForEach(waiting) { item in exhibit(item, language: language) }
                    } header: {
                        Text(verbatim: language.text("Not on show yet", "還沒展出"))
                    }
                }
            } else {
                Text(verbatim: language.text("Your company has no railway museum now.", "公司現在沒有鐵道博物館。"))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .navigationTitle(Text(verbatim: language.text("Railway museum", "鐵道博物館")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if closes {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Done", "完成"))
                    }
                    .accessibilityIdentifier("museum.done")
                }
            }
        }
        .fullScreenCover(item: $inGarage) { key in
            TrainShowcaseScreen(keys: [key.id], close: { inGarage = nil })
        }
        .accessibilityIdentifier("museum.page")
    }

    private func stripe(of type: TrainType) -> Color {
        switch RollingStockCatalog.Family(type) {
        case .metro: Theme.primary
        case .railway: Theme.accent
        case .highSpeed: Palette.ink
        case .special: Theme.warning
        }
    }

    private func exhibit(_ item: RailwayMuseumGuide.Item, language: DisplayLanguage) -> some View {
        HStack(spacing: 12) {
            CatalogTrain(stripe: stripe(of: item.type), cars: 2, silhouette: !item.isShown)
                .frame(width: 84, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.isShown ? Theme.textPrimary : Theme.textSecondary)
                Text(verbatim: language.text(
                    "\(item.family) · \(item.capacityPerCar) riders a car · \(item.topSpeed) km/h",
                    "\(item.family)・每節 \(item.capacityPerCar) 人・最高 \(item.topSpeed) km/h"
                ))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                if let place = item.place {
                    Text(verbatim: place)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if let key = item.showcaseKey {
                Button {
                    inGarage = GarageKey(id: key)
                } label: {
                    Label {
                        Text(verbatim: language.text("3D", "3D"))
                    } icon: {
                        Image(systemName: "cube.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(verbatim: language.text("See \(item.name) in 3D", "看 \(item.name) 的 3D")))
                .accessibilityIdentifier("museum.3d.\(item.type.spec.code)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("museum.exhibit.\(item.type.spec.code)")
    }
}
