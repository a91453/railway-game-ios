import GameCore

// What buying trains for a line would do to its day (decision 682): the
// fares it would take, what it would cost to run and what is left, beside
// what the line makes now, shown where the trains are bought (the line
// panel's staffing and headway sections).
//
// Nothing is kept and the world is only read. The figures come from what
// the world already knows:
//
// - riders: the passenger plan's hourly riders of each ride leg of the line
//   (``GameWorld/plannedPassengerLegFlows()``, decision 178), carried as
//   far as the trains have room on the line's fullest stretch, hour by
//   hour, those left behind waiting for the next hour;
// - fares: each leg's riders at the fare between its two stations
//   (``GameWorld/tripFare(from:to:highSpeed:)``);
// - costs: the company's own rates (`Operations.swift`): every departure,
//   every train-kilometre, the stations and the route by the hour and the
//   day, and each train's staff, energy and maintenance by its weight
//   (decision 180), less its hours in a depot (decision 209);
// - now: the line's own completed days (decision 179's accounts), the last
//   seven its trains ran. The estimate is then those days plus the
//   difference the rates and the plan make between the trains it has and
//   the trains it would have, so that "now" is the figure the line's card
//   shows and what the model gets wrong of the line is in both and cancels.
//
// The references have no such estimate to port: `Ci/`'s line form only
// prices the trains (`estimateLineFormTrainCost`, and its display is
// removed), and its ridership estimate (`hsrRidershipEstimateSoldTickets`)
// is a hash of the train number. The model is this project's own.

/// What buying trains for a line would do to its day (decision 682).
/// Money is a day's, in cents of whole dollars.
public struct TrainPurchaseEstimate: Hashable, Sendable {
    /// Where the riders' figures come from.
    public enum Demand: Hashable, Sendable {
        /// The passenger plan has riders for the line.
        case planned
        /// No plan yet, or none with the line in it (a line just made,
        /// before the clock has run): the fares cannot be said.
        case unknown
    }

    public let demand: Demand
    /// The completed days of the line's own that "now" is their average
    /// of; 0 when it has none and "now" is worked out as the estimate is.
    public let historyDays: Int
    /// The line as it is now: its fares, its running costs and what is
    /// left.
    public let faresNow: Money
    public let costNow: Money
    /// With the trains bought. The fares and what is left are `nil` with
    /// ``Demand/unknown``.
    public let fares: Money?
    public let cost: Money
    /// Of ``cost``, what the trains bought add.
    public let addedCost: Money
    /// The riders a day it would carry, and how full the fullest hour's
    /// trains would be on the fullest stretch, in thousandths of their
    /// room.
    public let riders: Int64?
    public let peakLoadPermille: Int64?
    /// The riders a day whose fares pay ``cost``, at the line's average
    /// fare; `nil` when no fare is known.
    public let breakEvenRiders: Int64?
    /// What the trains cost to buy.
    public let price: Money

    public var profitNow: Money { faresNow - costNow }

    public var profit: Money? { fares.map { $0 - cost } }

    /// What is left a day with the trains, less what is left now.
    public var change: Money? { profit.map { $0 - profitNow } }

    /// The days until ``change`` has paid ``price`` back; `nil` unless the
    /// line makes more with the trains.
    public var paybackDays: Int64? {
        guard let change, change.amount > 0, price.amount > 0 else { return nil }
        return (price.amount + change.amount - 1) / change.amount
    }
}

// MARK: - The text

extension TrainPurchaseEstimate {
    /// Whether the trains make the line's day better, worse or the same.
    public enum Tone: Hashable, Sendable {
        case better, worse, same
    }

    public var tone: Tone? {
        guard let change else { return nil }
        return change.amount > 0 ? .better : change.amount < 0 ? .worse : .same
    }

    /// "About a day: fares $ 120,000 · running $ 80,000 · leaves $ 40,000",
    /// or with no riders known, what the running costs alone.
    public func headline(in language: DisplayLanguage) -> String {
        guard let fares, let profit else {
            return language.text(
                "About \(cost.moneyText) a day to run · fares —",
                "估每天開銷 \(cost.moneyText) · 票收 —"
            )
        }
        return language.text(
            "About a day: fares \(fares.moneyText) · running \(cost.moneyText) · \(profit.amount < 0 ? "loses" : "leaves") \(Money(abs(profit.amount)).moneyText)",
            "估每天票收 \(fares.moneyText) · 開銷 \(cost.moneyText) · \(profit.amount < 0 ? "虧" : "賺") \(Money(abs(profit.amount)).moneyText)"
        )
    }

    /// The one line over the button that buys: "About $ 40,000 a day
    /// left · $ 12,000 more than now", or with no riders known, what the
    /// running costs alone. The rest (``detailTexts(in:)``) goes under the
    /// button: on a phone on its side the page is a few lines high, and
    /// the headway, this line and the button have to fit it together.
    public func summary(in language: DisplayLanguage) -> String {
        guard let profit, let change, let tone else { return headline(in: language) }
        let left = Money(abs(profit.amount)).moneyText
        let amount = Money(abs(change.amount)).moneyText
        let first = profit.amount < 0
            ? language.text("About \(left) a day lost", "估每天虧 \(left)")
            : language.text("About \(left) a day left", "估每天賺 \(left)")
        let second: String
        switch tone {
        case .same: second = language.text("the same as now", "和現在一樣")
        case .worse: second = language.text("\(amount) less than now", "比現在少 \(amount)")
        case .better: second = language.text("\(amount) more than now", "比現在多 \(amount)")
        }
        return first + " · " + second
    }

    /// Under the button: the fares and the running cost, how soon the
    /// trains pay for themselves, the riders, and what to make of it.
    public func detailTexts(in language: DisplayLanguage) -> [String] {
        var texts: [String] = []
        if fares != nil { texts.append(headline(in: language)) }
        if let days = paybackDays {
            texts.append(language.text(
                "The trains pay for themselves in about \(days.groupedText) \(days == 1 ? "day" : "days")",
                "約 \(days.groupedText) 天回本"
            ))
        }
        if let riders = ridersText(in: language) { texts.append(riders) }
        texts.append(note(in: language))
        return texts
    }

    /// "Breaks even at 3,200 riders a day · about 4,100 expected, fullest
    /// trains 85% full", or as much of it as is known.
    public func ridersText(in language: DisplayLanguage) -> String? {
        var parts: [String] = []
        if let breakEvenRiders {
            parts.append(language.text(
                "Breaks even at \(breakEvenRiders.groupedText) riders a day",
                "每天載 \(breakEvenRiders.groupedText) 人次打平"
            ))
        }
        if let riders {
            var text = language.text("about \(riders.groupedText) expected", "估 \(riders.groupedText) 人次")
            if let peakLoadPermille {
                let percent = LineLossDiagnosis.percentText(peakLoadPermille, in: language)
                text += language.text(", fullest trains \(percent) full", "，最擠時坐滿 \(percent)")
            }
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What to make of it, in a sentence.
    public func note(in language: DisplayLanguage) -> String {
        switch demand {
        case .unknown:
            language.text(
                "Riders are counted once the clock has run: the fares show then.",
                "時間開始走以後才算得出乘客，票收到時會顯示。"
            )
        case .planned:
            language.text(
                "An estimate from today's riders and fares. Weather, holidays and late trains change the real day.",
                "照今天的乘客與票價估的；天氣、假日與誤點會讓實際不同。"
            )
        }
    }

    /// The whole of it for VoiceOver.
    public func spokenText(in language: DisplayLanguage) -> String {
        ([summary(in: language)] + detailTexts(in: language)).joined(separator: language.text(". ", "。"))
    }
}

// MARK: - The model

/// A line's trains as the estimate counts them: before the purchase, or
/// after.
struct LineFleet: Equatable {
    /// Each train's weight in running costs, in thousandths of a standard
    /// train (``RollingStock/weight(of:cars:)``), added up.
    var weight: Int64 = 0
    /// Each train's kilometres' weight (its type's alone), added up.
    var distancePermille: Int64 = 0
    /// The passengers each takes at most, added up.
    var room: Int64 = 0
    var trains: Int64 = 0
    /// Trips each way in each hour of the day, in thousandths.
    var hourlyTrips: [Int64] = Array(repeating: 0, count: 24)

    mutating func add(type: TrainType?, cars: Int, economics: Bool, count: Int64 = 1) {
        weight += count * (economics ? RollingStock.weight(of: type, cars: cars) : 1_000)
        distancePermille += count * (economics ? RollingStock.pricing(of: type).operatingPermille : 1_000)
        room += count * TrainPurchaseModel.room(of: type, cars: cars)
        trains += count
    }
}

/// A day of a line with some trains, as the estimate works it out.
struct LineDayModel: Equatable {
    /// Dollars.
    var fares: Double = 0
    var cost: Double = 0
    var riders: Double = 0
    var peakLoadPermille: Int64?
}

enum TrainPurchaseModel {
    /// The most the completed days "now" is the average of.
    static let historyDays = 7

    /// The passengers a train of `type` with `cars` cars takes at most
    /// (``Train/capacity``).
    static func room(of type: TrainType?, cars: Int) -> Int64 {
        let rated = Int64(max(1, cars)) * (type?.ratedCapacityPerCar ?? Train.ratedCapacityPerCar)
        return type?.overloads ?? true ? (rated * 11 + 5) / 10 : rated
    }

    /// Of the riders who want the line's fullest stretch each hour, those
    /// the trains have room for, the others waiting for the next hour and
    /// lost at the day's end: thousandths carried, and how full the
    /// fullest hour's trains are. `need` and `offered` have 24 entries.
    static func carried(need: [Int64], offered: [Int64]) -> (permille: Int64, peakLoad: Int64?) {
        var waiting: Int64 = 0, wanted: Int64 = 0, taken: Int64 = 0
        var peak: Int64?
        // Riders left at midnight wait on for the morning: twice round
        // the day, counting the second.
        for pass in 0..<2 {
            for hour in 0..<24 {
                let want = need[hour] + waiting
                let got = min(want, offered[hour])
                waiting = want - got
                guard pass == 1 else { continue }
                wanted += need[hour]
                taken += got
                if offered[hour] > 0 { peak = max(peak ?? 0, got * 1_000 / offered[hour]) }
            }
        }
        guard wanted > 0 else { return (1_000, peak) }
        return (min(1_000, taken * 1_000 / wanted), peak)
    }
}

extension GameWorld {
    /// What buying `buying` trains of `type` with `cars` cars for line
    /// `id` would do to its day (decision 682), the line then running a
    /// train every `headway` minutes, or as often as its trains can.
    /// `price` is what they cost in all; `journey` is the line's
    /// (``GameWorld/lineJourney(_:pattern:)``) when the caller has it
    /// already, a search of the track otherwise.
    ///
    /// `nil` for a company that keeps no books or no line accounts, a
    /// line that does not exist, a freight line, a ring, a line no train
    /// can drive, and when nothing is bought.
    public func trainPurchaseEstimate(
        _ id: LineID, buying: Int, type: TrainType?, cars: Int, headway: Int64, price: Money,
        journey known: LineJourney? = nil
    ) -> TrainPurchaseEstimate? {
        guard buying > 0, headway > 0, accounts.mode == .management, lineAccounts != nil,
              let line = line(id: id), !line.isFreight, !line.isRing,
              let journey = known ?? lineJourney(id), journey.legs.count >= 2
        else { return nil }
        let economics = rollingStockEconomics

        // The trains it has, and those it would have.
        var before = LineFleet()
        for train in line.assignedTrains.compactMap({ self.train(id: $0) }) {
            before.add(type: train.type, cars: train.cars, economics: economics)
        }
        var after = before
        after.add(type: type, cars: cars, economics: economics, count: Int64(buying))

        // Trips each way, hour by hour: now at each level's headway, then
        // at the headway asked, or the round trip shared among the trains.
        let own = Int64(line.trains.count)
        let roundTrip = max(1, journey.roundTripMinutes)
        let shared = (roundTrip + own + Int64(buying) - 1) / (own + Int64(buying))
        let afterHeadway = max(headway, shared)
        var nowHeadways: [ServiceLevel: Int64] = [:]
        if own > 0 {
            for level in ServiceLevel.allCases { nowHeadways[level] = lineHeadway(id, at: level) }
        }
        var open: Int64 = 0
        for minute in 0..<1_440 where line.window.contains(minuteOfDay: minute) {
            open += 1
            let hour = minute / 60
            after.hourlyTrips[hour] += 1_000 / afterHeadway
            if let now = nowHeadways[serviceDay.level(atMinuteOfDay: minute)], now > 0 {
                before.hourlyTrips[hour] += 1_000 / now
            }
        }

        // The plan's riders of the line, by leg.
        let flows = plannedPassengerLegFlows()?.filter { $0.line == id } ?? []
        let planned = !flows.isEmpty
        let modelBefore = lineDay(line, journey: journey, fleet: before, flows: flows, openMinutes: open)
        let modelAfter = lineDay(line, journey: journey, fleet: after, flows: flows, openMinutes: open)

        // Now: the line's own days, or the model's.
        let today = FinanceHistory.floorDay(clock.now)
        let bought = acquisitions.first { $0.line == id }?.day
        let days = lineDays(id).filter { record in
            record.day < today && record.tally.departures > 0 && bought.map { record.day > $0 } ?? true
        }.suffix(TrainPurchaseModel.historyDays)
        var faresNow = modelBefore.fares, costNow = modelBefore.cost
        var historyFare: Double?
        if !days.isEmpty {
            let count = Double(days.count)
            faresNow = Double(days.reduce(0) { $0 + $1.tally.fareRevenue.amount }) / 100 / count
            costNow = Double(days.reduce(0) { $0 + $1.tally.totalCost.amount }) / 100 / count
            let riders = days.reduce(0) { $0 + $1.tally.boardings }
            if riders > 0, faresNow > 0 { historyFare = faresNow * count / Double(riders) }
        }
        let fares = max(0, faresNow + modelAfter.fares - modelBefore.fares)
        let cost = max(0, costNow + modelAfter.cost - modelBefore.cost)

        // The riders that pay for it, at the line's average fare.
        let planFare = modelAfter.riders > 0 && modelAfter.fares > 0 ? modelAfter.fares / modelAfter.riders : nil
        let averageFare = planFare ?? historyFare ?? meanStopFare(of: line)
        func money(_ dollars: Double) -> Money { Money(Int64(dollars.rounded()) * 100) }
        return TrainPurchaseEstimate(
            demand: planned ? .planned : .unknown,
            historyDays: days.count,
            faresNow: money(faresNow), costNow: money(costNow),
            fares: planned ? money(fares) : nil,
            cost: money(cost),
            addedCost: money(max(0, modelAfter.cost - modelBefore.cost)),
            riders: planned ? Int64(modelAfter.riders.rounded()) : nil,
            peakLoadPermille: planned ? modelAfter.peakLoadPermille : nil,
            breakEvenRiders: averageFare.flatMap { $0 > 0 ? Int64((cost / $0).rounded(.up)) : nil },
            price: price
        )
    }

    /// A day of `line` with `fleet`: what the company's rates make its
    /// running cost, and the fares of the plan's riders it has room for.
    func lineDay(_ line: ServiceLine, journey: LineJourney, fleet: LineFleet, flows: [PassengerLegFlow], openMinutes: Int64) -> LineDayModel {
        var day = LineDayModel()
        let unitsPerKilometre = Double(1_000 * WorldCoordinate.unitsPerMetre)
        let out = journey.legs.prefix(journey.legs.count / 2)
        let routeKm = Double(out.reduce(0) { $0 + $1.path.distance }) / unitsPerKilometre
        let stations = Double(Set(line.stops).count)
        // Trips each way a day; every trip leaves each stop but its last.
        let trips = Double(fleet.hourlyTrips.reduce(0, +)) / 1_000
        let departures = 2 * trips * Double(out.count)
        let distanceWeight = fleet.trains > 0 ? Double(fleet.distancePermille) / Double(fleet.trains) / 1_000 : 1
        let trainKm = 2 * trips * routeKm * distanceWeight
        let weight = Double(fleet.weight) / 1_000
        // Decision 209: in its depot a train pays no energy or crew.
        let onDuty = line.depots.isEmpty ? 1 : Double(openMinutes) / 1_440
        let operating = 225 * departures + 126 * trainKm + 54 * 24 * stations
        let maintenance = 36 * 24 * routeKm + 27 * trainKm + 24 * 24 * weight
        let energy = 660 * routeKm + 1_080 * weight * onDuty
        let staff = 1_860 * stations + 1_440 * weight * onDuty
        day.cost = operating + maintenance + energy + staff

        guard !flows.isEmpty, fleet.trains > 0 else { return day }
        // The riders over each stretch between neighbouring stops, each
        // way, each hour.
        var position: [StationID: Int] = [:]
        for (index, stop) in line.stops.enumerated() where position[stop] == nil { position[stop] = index }
        let stretches = max(1, line.stops.count - 1)
        var loads = Array(repeating: Array(repeating: Int64(0), count: 24 * stretches), count: 2)
        var legs: [(way: Int, riders: Int64, fare: Double)] = []
        for flow in flows {
            guard let from = position[flow.from], let to = position[flow.to], from != to else { continue }
            let way = from < to ? 0 : 1
            for hour in 0..<24 where flow.hourly[hour] > 0 {
                for stretch in min(from, to)..<max(from, to) {
                    loads[way][hour * stretches + stretch] += flow.hourly[hour]
                }
            }
            let fare = tripFare(from: flow.from, to: flow.to, highSpeed: line.isHighSpeed)
            legs.append((way, flow.hourly.reduce(0, +), Double(fare?.amount ?? 0) / 100))
        }
        let room = fleet.room / fleet.trains
        let offered = fleet.hourlyTrips.map { $0 * room / 1_000 }
        var share = [1_000.0, 1_000.0]
        for way in 0..<2 {
            let need = (0..<24).map { hour in loads[way][(hour * stretches)..<((hour + 1) * stretches)].max() ?? 0 }
            let carried = TrainPurchaseModel.carried(need: need, offered: offered)
            share[way] = Double(carried.permille)
            if let peak = carried.peakLoad { day.peakLoadPermille = max(day.peakLoadPermille ?? 0, peak) }
        }
        for leg in legs {
            let riders = Double(leg.riders) * share[leg.way] / 1_000
            day.riders += riders
            day.fares += riders * leg.fare
        }
        return day
    }

    /// The fare between two of `line`'s stops, averaged over every pair:
    /// what a rider pays when nothing says who rides.
    private func meanStopFare(of line: ServiceLine) -> Double? {
        let stops = Array(Set(line.stops)).sorted()
        var total: Int64 = 0, pairs: Int64 = 0
        for (index, from) in stops.enumerated() {
            for to in stops[(index + 1)...] {
                guard let fare = tripFare(from: from, to: to, highSpeed: line.isHighSpeed) else { continue }
                total += fare.amount
                pairs += 1
            }
        }
        return pairs > 0 ? Double(total) / Double(pairs) / 100 : nil
    }
}
