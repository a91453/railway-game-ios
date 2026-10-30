import GameCore

// Decision 478's load charts: what the game already keeps about how full
// its lines are, put in a shape the app draws with Swift Charts.
//
// - A line's riders between each pair of its stops, both ways
//   (``LineLoadProfile``): the railways' 断面輸送量 or 站間運量, read from
//   the kept passenger plan (``GameWorld/plannedPassengerLegFlows()``) as
//   the section flow layer reads it (decision 178), but for this line's
//   own legs only.
// - A section's riders hour by hour against its seats
//   (``NetworkFlowReport/SectionRow/hourlyChart(title:in:)``).
// - A line's fullest train each day against its seats
//   (``LineReport/peakLoadChart(in:)``), from the line accounts.
//
// Presentation only: worked out when asked, never stored.

/// A line's planned riders between each pair of neighbouring stops, each
/// way, all day.
public struct LineLoadProfile: Equatable, Sendable {
    /// One way of one section at its fullest hour.
    public struct Peak: Equatable, Sendable {
        public let hour: Int
        public let load: Int64
        public let capacity: Int64

        public init(hour: Int, load: Int64, capacity: Int64) {
            self.hour = hour
            self.load = load
            self.capacity = capacity
        }

        /// Load as a whole percent of the seats, or `nil` with no trains.
        public var percent: Int? {
            capacity > 0 ? Int((load * 100 + capacity / 2) / capacity) : nil
        }

        /// The hour carrying the largest share of its seats (riders with no
        /// trains first; then the larger load; then the earlier), or `nil`
        /// when nobody rides: the network flow report's rule.
        public static func fullest(loads: [Int64], capacities: [Int64]) -> Peak? {
            var best: (hour: Int, ratio: Double)?
            for hour in 0..<min(loads.count, capacities.count) where loads[hour] > 0 {
                let ratio = capacities[hour] > 0 ? Double(loads[hour]) / Double(capacities[hour]) : .infinity
                if best == nil || ratio > best!.ratio || (ratio == best!.ratio && loads[hour] > loads[best!.hour]) {
                    best = (hour, ratio)
                }
            }
            return best.map { Peak(hour: $0.hour, load: loads[$0.hour], capacity: capacities[$0.hour]) }
        }
    }

    /// The stretch from one stop to the next, in the line's stop order.
    public struct Section: Equatable, Sendable, Identifiable {
        public let index: Int
        public let from: String
        public let to: String
        /// Riders a day from `from` to `to`, and back.
        public let outbound: Int64
        public let inbound: Int64
        public let outboundPeak: Peak?
        public let inboundPeak: Peak?

        public var id: Int { index }
        /// "Alpha – Beta".
        public var label: String { "\(from) – \(to)" }
    }

    public let line: LineID
    /// Whether the world keeps a passenger plan (before the first minute
    /// of play it does not, and there is nothing to show).
    public let hasPlan: Bool
    /// The two ways' names: "To Gamma", "To Alpha".
    public let outboundName: String
    public let inboundName: String
    public let sections: [Section]

    /// The section with the most riders either way; `nil` when nobody rides.
    public var busiest: Section? {
        var best: Section?
        for section in sections where max(section.outbound, section.inbound) > 0 {
            if max(section.outbound, section.inbound) > max(best?.outbound ?? 0, best?.inbound ?? 0) { best = section }
        }
        return best
    }

    /// The sentence over the chart, also VoiceOver's summary.
    public func summaryText(in language: DisplayLanguage) -> String {
        guard hasPlan else { return language.text("Run the game a minute to see the riders.", "讓遊戲走一分鐘，就看得到乘客。") }
        guard let busiest else { return language.text("Nobody rides this line yet.", "這條線還沒有人搭。") }
        let outbound = busiest.outbound >= busiest.inbound
        let (from, to) = outbound ? (busiest.from, busiest.to) : (busiest.to, busiest.from)
        let riders = (outbound ? busiest.outbound : busiest.inbound).groupedText
        var text = language.text("Busiest: \(from) → \(to), \(riders) riders a day", "最多人：\(from) → \(to)，一天 \(riders) 人")
        if let peak = outbound ? busiest.outboundPeak : busiest.inboundPeak {
            let hours = "\(SectionFlow.hourText(peak.hour))–\(SectionFlow.hourText((peak.hour + 1) % 24))"
            if let percent = peak.percent {
                text += language.text(" · fullest \(hours) at \(percent)% of the seats", " · 最擠 \(hours)，座位的 \(percent)%")
            } else {
                text += language.text(" · fullest \(hours) with no trains", " · 最擠 \(hours)，沒有列車")
            }
        }
        return text
    }

    /// A tapped section's numbers both ways, on one line.
    public func sectionText(_ section: Section, in language: DisplayLanguage) -> String {
        func way(_ name: String, _ riders: Int64, _ peak: Peak?) -> String {
            let count = riders.groupedText
            var text = language.text("\(name) \(count) a day", "\(name) 一天 \(count) 人")
            if let peak {
                let share = peak.percent.map { "\($0)%" } ?? language.text("no trains", "沒有列車")
                text += language.text(", fullest \(SectionFlow.hourText(peak.hour)) \(share)", "，最擠 \(SectionFlow.hourText(peak.hour)) \(share)")
            }
            return text
        }
        return [section.label, way(outboundName, section.outbound, section.outboundPeak), way(inboundName, section.inbound, section.inboundPeak)]
            .joined(separator: " · ")
    }

    /// The chart: each section along x in stop order, a bar each way, in
    /// people.
    public func chart(in language: DisplayLanguage) -> ChartSpec {
        ChartSpec(
            title: language.text("Riders between stops", "各站間載客"), xTitle: language.text("Section", "區間"),
            xLabels: sections.map(\.label), axis: .people,
            series: [
                ChartSeries(name: outboundName, mark: .bars, values: sections.map { Double($0.outbound) }),
                ChartSeries(name: inboundName, mark: .bars, values: sections.map { Double($0.inbound) }),
            ],
            summary: summaryText(in: language), language: language
        )
    }

    init(line: LineID, hasPlan: Bool, outboundName: String, inboundName: String, sections: [Section]) {
        self.line = line
        self.hasPlan = hasPlan
        self.outboundName = outboundName
        self.inboundName = inboundName
        self.sections = sections
    }
}

extension LineLoadProfile {
    /// The profile of line `id` in `world` now. Reads the whole network's
    /// planned legs and the line's headways: run it off the main thread.
    public init(world: GameWorld, line id: LineID, in language: DisplayLanguage = .english) {
        guard let line = world.line(id: id), line.stops.count >= 2 else {
            self.init(line: id, hasPlan: world.keepsPassengerPlan, outboundName: "", inboundName: "", sections: [])
            return
        }
        let names = line.stops.map { world.station(id: $0)?.name ?? "" }
        let outboundName = line.isRing
            ? language.text("In stop order", "順著站序") : language.text("To \(names.last!)", "往 \(names.last!)")
        let inboundName = line.isRing
            ? language.text("Against stop order", "逆著站序") : language.text("To \(names.first!)", "往 \(names.first!)")
        guard let flows = world.plannedPassengerLegFlows() else {
            self.init(line: id, hasPlan: false, outboundName: outboundName, inboundName: inboundName, sections: [])
            return
        }
        let count = line.isRing ? line.stops.count : line.stops.count - 1
        let empty = Array(repeating: Array(repeating: Int64(0), count: 24), count: count)
        var loads: [LineDirection: [[Int64]]] = [.outbound: empty, .inbound: empty]
        for flow in flows where flow.line == id {
            for segment in SectionFlow.segments(of: line, from: flow.from, to: flow.to, direction: flow.direction) where segment < count {
                for hour in 0..<24 { loads[flow.direction]![segment][hour] += flow.hourly[hour] }
            }
        }
        let capacities = SectionFlow.capacities(of: line, in: world, segmentCount: count)
        let sections = (0..<count).map { segment in
            let out = loads[.outbound]![segment], back = loads[.inbound]![segment]
            return Section(
                index: segment, from: names[segment], to: names[(segment + 1) % names.count],
                outbound: out.reduce(0, +), inbound: back.reduce(0, +),
                outboundPeak: Peak.fullest(loads: out, capacities: capacities[segment]),
                inboundPeak: Peak.fullest(loads: back, capacities: capacities[segment])
            )
        }
        self.init(line: id, hasPlan: true, outboundName: outboundName, inboundName: inboundName, sections: sections)
    }
}

// MARK: - A section hour by hour

extension NetworkFlowReport.SectionRow {
    /// The section's riders as bars and its seats as a dashed line, hour
    /// by hour, in people.
    public func hourlyChart(title: String, in language: DisplayLanguage) -> ChartSpec {
        ChartSpec(
            title: title, xTitle: language.text("Hour", "時段"),
            xLabels: (0..<24).map(SectionFlow.hourText), axis: .people,
            series: [
                ChartSeries(name: language.text("Riders", "乘客"), mark: .bars, values: loads.map { Double($0) }),
                ChartSeries(name: language.text("Seats", "座位"), mark: .dashedLine, values: capacities.map { Double($0) }),
            ],
            summary: hourlySummary(in: language), language: language
        )
    }

    /// The hours more ride than the trains carry.
    public var hoursOverTheSeats: Int {
        zip(loads, capacities).filter { load, capacity in load > capacity }.count
    }

    /// "Fullest 08:00–09:00: 348 riders, 116% of the seats · over the
    /// seats 3 hours".
    public func hourlySummary(in language: DisplayLanguage) -> String {
        let hours = "\(SectionFlow.hourText(hour))–\(SectionFlow.hourText((hour + 1) % 24))"
        let riders = load.groupedText
        var text = percent.map {
            language.text("Fullest \(hours): \(riders) riders, \($0)% of the seats", "最擠 \(hours)：\(riders) 人，座位的 \($0)%")
        } ?? language.text("Fullest \(hours): \(riders) riders with no trains", "最擠 \(hours)：\(riders) 人，沒有列車")
        let over = hoursOverTheSeats
        text += over == 0
            ? language.text(" · never over the seats", " · 都沒超過座位")
            : language.text(" · over the seats \(over) \(over == 1 ? "hour" : "hours")", " · 超過座位 \(over) 個小時")
        return text
    }

    /// A tapped hour's numbers: "08:00–09:00 · 348 riders · 300 seats · 116%".
    public func hourText(_ hour: Int, in language: DisplayLanguage) -> String {
        let hour = min(max(hour, 0), 23)
        let load = loads.indices.contains(hour) ? loads[hour] : 0
        let capacity = capacities.indices.contains(hour) ? capacities[hour] : 0
        var parts = [
            "\(SectionFlow.hourText(hour))–\(SectionFlow.hourText((hour + 1) % 24))",
            language.text("\(load.groupedText) riders", "\(load.groupedText) 人"),
        ]
        if capacity > 0 {
            parts.append(language.text("\(capacity.groupedText) seats", "\(capacity.groupedText) 座位"))
            parts.append("\((load * 100 + capacity / 2) / capacity)%")
        } else {
            parts.append(language.text("no trains", "沒有列車"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The fullest train each day

extension LineReport {
    /// Each day's fullest train as it left a stop, in percent of its seats,
    /// as a line; the app draws the seats as a rule at 100%.
    public func peakLoadChart(in language: DisplayLanguage) -> ChartSpec {
        ChartSpec(
            title: language.text("Fullest train by day", "每日最擠的一班"), xTitle: language.text("Day", "日"),
            xLabels: days.map { language.text("Day \($0.day + 1)", "第 \($0.day + 1) 天") }, axis: .percent,
            series: [ChartSeries(name: language.text("Fullest train", "最擠的一班"), mark: .line, values: days.map { Double($0.peakLoadPercent) })],
            summary: peakLoadSummary(in: language), language: language
        )
    }

    /// "Fullest Day 12 at 132% · over the seats 2 of 3 days".
    public func peakLoadSummary(in language: DisplayLanguage) -> String {
        guard var fullest = days.first else { return language.text("No days recorded yet.", "還沒有每日紀錄。") }
        for day in days where day.peakLoadPercent > fullest.peakLoadPercent { fullest = day }
        let over = days.filter { $0.peakLoadPercent > 100 }.count
        let first = language.text("Fullest Day \(fullest.day + 1) at \(fullest.peakLoadPercent)%", "最擠第 \(fullest.day + 1) 天，\(fullest.peakLoadPercent)%")
        let second = over == 0
            ? language.text("never over the seats", "都沒超過座位")
            : language.text("over the seats \(over) of \(days.count) days", "\(days.count) 天中 \(over) 天超過座位")
        return first + " · " + second
    }
}
