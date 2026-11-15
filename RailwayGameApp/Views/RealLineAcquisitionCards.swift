import GameCore
import GamePresentation
import SwiftUI

/// Decision 315 §2: the card that offers a real branch line, opened from a
/// station beside it or the new-line menu. What it brings, its price in
/// three parts and the total, and what is in the way, if anything; Buy
/// only when nothing is and the cash is there. The offer is the
/// session's (``GameSession/shownRealLineOffer``); this view only draws it.
/// Decision 497: without an offer yet, it says the line is being prepared
/// (``GameSession/preparingRealLine``), Buy off.
struct RealLineOfferCard: View {
    let session: GameSession
    let line: RealBranchLine
    let offer: RealLineOffer?
    /// Called after Buy bought the line.
    var bought: () -> Void = {}

    var body: some View {
        let language = session.language
        let shortfall = offer?.shortfallText(balance: session.world.economy.balance, in: language)
        NavigationStack {
            Form {
                if let offer {
                    Section {
                        Text(verbatim: offer.summaryText(in: language))
                            .font(.subheadline)
                        Text(verbatim: RealLineAcquired.handoverText(today: RealLineAcquired.startsToday(at: session.world.clock.now), in: language)
                            + language.text(".", "。"))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(verbatim: language.text("Planning the line and its price…", "正在規劃路線與估價…"))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("acquire.preparing")
                    }
                }
                if let offer, offer.price != nil {
                    Section {
                        let rows = offer.priceRows(in: language)
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            // BUGHUNT_BUILD P3-1: the total is the last row
                            // (a line bought with its land has one more).
                            let total = index == rows.count - 1
                            HStack {
                                Text(verbatim: row.label)
                                    .font(total ? .subheadline.weight(.semibold) : .subheadline)
                                Spacer()
                                Text(verbatim: row.amount.moneyText)
                                    .font((total ? Font.subheadline.weight(.semibold) : .subheadline).monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("acquire.price.\(index)")
                        }
                    } header: {
                        Text(verbatim: language.text("Price", "價格"))
                    }
                }
                if !session.world.realTransfers {
                    Text(verbatim: RealLineOffer.transfersOffText(in: language))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let problem = offer?.problem {
                    Label {
                        Text(verbatim: problem)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .accessibilityIdentifier("acquire.problem")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if let shortfall, offer?.problem == nil {
                        Text(verbatim: shortfall)
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                            .accessibilityIdentifier("acquire.shortfall")
                    }
                    Button {
                        if let offer, session.acquireRealLine(offer) { bought() }
                    } label: {
                        Text(verbatim: language.text("Buy \(line.name(in: language))", "收購\(line.name(in: language))"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    // Decision 110: the card's main action, as the theme draws one.
                    .buttonStyle(ThemeProminentButtonStyle())
                    .disabled(offer?.acquisition == nil || shortfall != nil)
                    .accessibilityIdentifier("acquire.buy")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.panel)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.panelBorder).frame(height: 1)
                }
            }
            .navigationTitle(Text(verbatim: line.name(in: language)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        session.closeRealLineOffer()
                    } label: {
                        Text(verbatim: language.text("Cancel", "取消"))
                    }
                    .accessibilityIdentifier("acquire.cancel")
                }
            }
        }
    }
}

/// Decision 315 §8: the card a purchase ends on, laid out as a lesson's
/// result card. The line's colour band with its name, a navy round seal
/// "Bought" holding the junction's and the terminal's names, and what the
/// company now runs. The seal comes down once (`MotionRule.pop`); with
/// Reduce Motion it is simply there.
struct AcquisitionCompleteCard: View {
    let acquired: RealLineAcquired
    let language: DisplayLanguage
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false

    var body: some View {
        VStack(spacing: 16) {
            band
            seal
                .scaleEffect(stamped || reduceMotion ? 1 : 1.25)
                .opacity(stamped || reduceMotion ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: acquired.sealText(in: language)))
                .accessibilityIdentifier("acquired.seal")
            VStack(spacing: 4) {
                Text(verbatim: acquired.sizeText(in: language))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(verbatim: acquired.handoverText(in: language))
                Text(verbatim: acquired.timetableText(in: language))
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            Button(action: done) {
                Text(verbatim: language.text("OK", "好"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ThemeProminentButtonStyle())
            .accessibilityIdentifier("acquired.done")
        }
        .padding(24)
        .frame(maxWidth: 360)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(MotionRule.pop.animation) { stamped = true }
        }
    }

    /// The line's colour, its name on a panel-coloured capsule so it reads
    /// on any line colour.
    private var band: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(acquired.color.map { Palette.color($0) } ?? Theme.primary)
            .frame(height: 40)
            .overlay {
                Text(verbatim: acquired.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(Theme.panel, in: Capsule())
            }
            .accessibilityIdentifier("acquired.title")
    }

    /// Flat, a thick navy ring and a thin one inside it, as the app icon
    /// draws its outlines (art-style skill); no new colour.
    private var seal: some View {
        ZStack {
            Circle().strokeBorder(Theme.textPrimary, lineWidth: 4)
            Circle().strokeBorder(Theme.textPrimary, lineWidth: 1.5).padding(9)
            VStack(spacing: 2) {
                Text(verbatim: language.text("Bought", "收購"))
                    .font(.title2.weight(.heavy))
                Text(verbatim: acquired.endsText(in: language))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(18)
        }
        .frame(width: 124, height: 124)
        .rotationEffect(.degrees(-8))
    }
}

/// Decision 400 A.8: the card that offers a real station, opened from its
/// pin on the map where no track is within 400 m. What it brings, the line
/// the track follows where several stop there, its price, and what is in
/// the way, if anything; Buy only when nothing is and the cash is there.
/// The offer is the session's (``GameSession/shownRealStationOffer``); this
/// view only draws it.
struct RealStationOfferCard: View {
    let session: GameSession
    let offer: RealStationOffer

    var body: some View {
        let language = session.language
        let name = offer.suggestion.name(in: language)
        let systems = session.realStationSystems(of: offer.suggestion)
        let shortfall = offer.shortfallText(balance: session.world.economy.balance, in: language)
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: offer.summaryText(in: language))
                        .font(.subheadline)
                }
                if systems.count > 1 {
                    Section {
                        Picker(selection: Binding(
                            get: { offer.system.id },
                            set: { session.chooseRealStationSystem($0) }
                        )) {
                            ForEach(systems) { system in
                                Text(verbatim: system.name(in: language)).tag(system.id)
                            }
                        } label: {
                            Text(verbatim: language.text("Along", "沿著"))
                        }
                        .accessibilityIdentifier("buyStation.system")
                    } header: {
                        Text(verbatim: language.text("Which line the track follows", "軌道沿哪一條線"))
                    }
                }
                if let price = offer.price {
                    Section {
                        HStack {
                            Text(verbatim: language.text("Track, station and platform", "軌道、車站與月台"))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(verbatim: price.moneyText)
                                .font(Font.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("buyStation.price")
                    } header: {
                        Text(verbatim: language.text("Price", "價格"))
                    }
                }
                if let problem = offer.problem {
                    Label {
                        Text(verbatim: problem)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
                    .accessibilityIdentifier("buyStation.problem")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if let shortfall, offer.problem == nil {
                        Text(verbatim: shortfall)
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                            .accessibilityIdentifier("buyStation.shortfall")
                    }
                    Button {
                        session.buyRealStation(offer)
                    } label: {
                        Label {
                            Text(verbatim: language.text("Buy \(name) station", "收購\(name)站"))
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    // Decision 110: the card's main action, as the theme draws one.
                    .buttonStyle(ThemeProminentButtonStyle())
                    .disabled(offer.purchase == nil || shortfall != nil)
                    .accessibilityIdentifier("buyStation.buy")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.panel)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.panelBorder).frame(height: 1)
                }
            }
            .navigationTitle(Text(verbatim: language.text("Buy \(name) station", "收購\(name)站")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        session.shownRealStationOffer = nil
                    } label: {
                        Text(verbatim: language.text("Cancel", "取消"))
                    }
                    .accessibilityIdentifier("buyStation.cancel")
                }
            }
        }
    }
}

// MARK: - Air routes (decision 759)

/// The lines panel's air routes page (decision 759): the routes the
/// company flies, each with its card, then the routes for sale by airport.
/// A route for sale opens its offer, where the aircraft size is chosen.
struct AirRoutesPage: View {
    let session: GameSession
    @State private var offering: AirRouteListing?
    @State private var selling: AirRouteID?
    @State private var resizing: (id: AirRouteID, size: AircraftSize)?

    var body: some View {
        let language = session.language
        let listings = session.airRouteListings
        Form {
            if !session.world.airRoutes.isEmpty {
                Section {
                    ForEach(session.world.airRoutes.map(\.id), id: \.self) { id in
                        if let card = session.airRouteCard(id) { routeCard(card) }
                    }
                } header: {
                    Text(verbatim: language.text("Your air routes", "我的航線"))
                }
            }
            ForEach(session.world.airports, id: \.id) { airport in
                let routes = listings.filter { $0.airport == airport.id }
                if !routes.isEmpty {
                    Section {
                        ForEach(routes) { listing in listingRow(listing) }
                    } header: {
                        Text(verbatim: airport.title(in: language))
                    }
                }
            }
            Section {
                Text(verbatim: language.text(
                    "A route flies its real flights; you choose how many and how big the aircraft are. Airports stay the city's: each landing pays the airport a fee.",
                    "航線照真實的班數飛，你只調班數和飛機大小。機場不能收購，每次降落付起降費給機場。"
                ))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $offering) { listing in
            AirRouteOfferSheet(session: session, listing: listing)
        }
        .confirmationDialog(
            Text(verbatim: language.text("Sell this air route?", "要賣掉這條航線嗎？")),
            isPresented: Binding(get: { selling != nil }, set: { if !$0 { selling = nil } }),
            titleVisibility: .visible,
            presenting: selling
        ) { id in
            Button(role: .destructive) {
                session.sellAirRoute(id)
            } label: {
                Text(verbatim: language.text("Sell Route", "賣掉航線"))
            }
        } message: { _ in
            Text(verbatim: language.text("Its aircraft and passengers are not paid back.", "飛機與旅客的錢都不退還。"))
        }
        .confirmationDialog(
            Text(verbatim: language.text("Change the aircraft?", "要換飛機嗎？")),
            isPresented: Binding(get: { resizing != nil }, set: { if !$0 { resizing = nil } }),
            titleVisibility: .visible,
            presenting: resizing
        ) { change in
            let id = change.id, size = change.size
            Button {
                session.setAirRouteSize(id, to: size)
            } label: {
                Text(verbatim: language.text("Fly \(size.name(in: .english))", "改用\(size.name(in: .traditionalChinese))"))
            }
        } message: { change in
            let id = change.id, size = change.size
            if let price = session.airRouteChangePrice(id, size: size) {
                Text(verbatim: language.text(
                    "A new fleet costs \(price.moneyText); the old aircraft are not paid back.",
                    "新的飛機要 \(price.moneyText)；舊飛機不退錢。"
                ))
            } else {
                Text(verbatim: language.text("This size cannot fly the route.", "這個大小飛不了這條航線。"))
            }
        }
    }

    private func listingRow(_ listing: AirRouteListing) -> some View {
        let language = session.language
        return Button {
            offering = listing
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(verbatim: language.text("To \(listing.destination.englishName)", "飛往\(listing.destination.name)"))
                } icon: {
                    Image(systemName: listing.destination.isDomestic ? "airplane" : "globe.asia.australia")
                }
                Text(verbatim: listing.bought != nil
                    ? language.text("You fly it", "已收購")
                    : language.text(
                        "\((listing.destination.yearlyPassengers / 365).groupedText) passengers a day",
                        "每天約 \((listing.destination.yearlyPassengers / 365).groupedText) 位旅客"
                    ))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .disabled(listing.bought != nil)
        .accessibilityIdentifier("air.listing.\(listing.airport).\(listing.destination.englishName)")
    }

    private func routeCard(_ card: AirRouteCard) -> some View {
        let language = session.language
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: card.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(role: .destructive) {
                    selling = card.id
                } label: {
                    Text(verbatim: language.text("Sell", "賣掉"))
                }
                .buttonStyle(.borderless)
                .font(.footnote)
                .accessibilityIdentifier("air.sell")
            }
            ForEach(Array(card.rows.enumerated()), id: \.offset) { index, row in
                Text(verbatim: row)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(index == 2 && !card.flies ? Theme.warning : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker(selection: Binding(get: { card.frequency }, set: { session.setAirRouteFrequency(card.id, to: $0) })) {
                ForEach(AirRouteFrequency.allCases, id: \.self) { frequency in
                    Text(verbatim: frequency.name(in: language)).tag(frequency)
                }
            } label: {
                Text(verbatim: language.text("Flights", "班數"))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("air.frequency")
            Picker(selection: Binding(get: { card.size }, set: { if $0 != card.size { resizing = (card.id, $0) } })) {
                ForEach(AircraftSize.allCases, id: \.self) { size in
                    Text(verbatim: size.name(in: language)).tag(size)
                }
            } label: {
                Text(verbatim: language.text("Aircraft", "飛機"))
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("air.size")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("air.card")
    }
}

/// A route for sale's offer (decision 759): its real flights and
/// passengers, each aircraft size's average day, and the price in two
/// parts, the aircraft and the passengers.
struct AirRouteOfferSheet: View {
    let session: GameSession
    let listing: AirRouteListing
    @Environment(\.dismiss) private var dismiss
    @State private var frequency: AirRouteFrequency = .real
    @State private var size: AircraftSize?

    var body: some View {
        let language = session.language
        let estimates = session.airRouteEstimates(listing, frequency: frequency)
        let chosen = size ?? AirRouteMarket.suggestedSize(estimates)
        let estimate = estimates.first { $0.size == chosen }
        NavigationStack {
            Form {
                Section {
                    if let route = estimates.compactMap(\.offer).first?.route {
                        let km = max(1, (route.metres + 500) / 1_000)
                        row(language.text("Flight", "航程"), language.text("\(km.groupedText) km", "\(km.groupedText) 公里"))
                        row(language.text("Real flights", "真實班數"), language.text("\(route.realDepartures) each way a day", "每天來回各 \(route.realDepartures) 班"))
                        row(language.text("Fare", "票價"), language.text("\(route.fare.moneyText) a passenger", "每人 \(route.fare.moneyText)"))
                    }
                    row(language.text("Passengers", "旅客"), language.text(
                        "about \((listing.destination.yearlyPassengers / 365).groupedText) a day, both ways",
                        "來回每天約 \((listing.destination.yearlyPassengers / 365).groupedText) 人"
                    ))
                }
                Section {
                    Picker(selection: $frequency) {
                        ForEach(AirRouteFrequency.allCases, id: \.self) { frequency in
                            Text(verbatim: frequency.name(in: language)).tag(frequency)
                        }
                    } label: {
                        Text(verbatim: language.text("Flights", "班數"))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("air.offer.frequency")
                } header: {
                    Text(verbatim: language.text("Flights", "班數"))
                }
                Section {
                    ForEach(estimates, id: \.size) { estimate in
                        sizeRow(estimate, chosen: estimate.size == chosen)
                    }
                } header: {
                    Text(verbatim: language.text("Aircraft", "飛機"))
                } footer: {
                    Text(verbatim: language.text(
                        "An average day: fares less the aircraft's upkeep, fuel and landing fees.",
                        "平均一天：票收減掉飛機的維持費、油錢與起降費。"
                    ))
                }
                if let offer = estimate?.offer {
                    Section {
                        row(language.text("Aircraft (\(offer.route.aircraft))", "飛機（\(offer.route.aircraft) 架）"), offer.aircraftPrice.moneyText)
                        row(language.text("Passengers", "旅客"), offer.value.moneyText)
                        row(language.text("Total", "合計"), offer.price.moneyText)
                            .fontWeight(.semibold)
                        Button {
                            if session.buyAirRoute(listing, size: chosen, frequency: frequency) { dismiss() }
                        } label: {
                            Text(verbatim: language.text("Buy for \(offer.price.moneyText)", "以 \(offer.price.moneyText) 收購"))
                                .fontWeight(.semibold)
                        }
                        .disabled(offer.price > session.world.economy.balance)
                        .accessibilityIdentifier("air.offer.buy")
                    } header: {
                        Text(verbatim: language.text("Price", "價錢"))
                    }
                }
            }
            .navigationTitle(Text(verbatim: listing.title(in: language)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Cancel", "取消"))
                    }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
        } label: {
            Text(verbatim: title)
        }
    }

    private func sizeRow(_ estimate: AirRouteEstimate, chosen: Bool) -> some View {
        let language = session.language
        return Button {
            size = estimate.size
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosen ? Theme.success : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: estimate.size.name(in: language))
                        .foregroundStyle(Theme.textPrimary)
                    if let offer = estimate.offer {
                        let net = estimate.dailyNet
                        Text(verbatim: language.text(
                            "\(offer.route.aircraft) aircraft · \(estimate.passengers.groupedText) passengers · \(net > .zero ? "+" : "")\(net.moneyText) a day",
                            "\(offer.route.aircraft) 架 · 旅客 \(estimate.passengers.groupedText) 人 · 一天 \(net > .zero ? "+" : "")\(net.moneyText)"
                        ))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(net > .zero ? Theme.textSecondary : Theme.error)
                        if let days = estimate.paybackDays {
                            Text(verbatim: language.text("Pays back in about \(days.groupedText) days", "約 \(days.groupedText) 天回本"))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        Text(verbatim: language.text("Too small to fly so many flights.", "太小，飛不了這麼多班。"))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .disabled(estimate.offer == nil)
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("air.offer.size.\(estimate.size.rawValue)")
    }
}
