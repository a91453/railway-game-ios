import GameCore

// Decision 332: what the station and line cards say of the riders who take
// a scooter or a car instead, and of those the fare keeps away (decision
// 36), and the one thing that brings most of them back. Worked out from
// ``GameWorld/modeShiftLosses(from:)``; nothing is kept.

/// What kept riders off the trains from a station, or on a line.
public struct ModeShiftSummary: Hashable, Sendable {
    /// The one thing that brings most of them back.
    public enum Reason: Hashable, Sendable {
        /// They wait longest: more trains.
        case fewTrains
        /// They ride longest: faster trains or a straighter line.
        case slowTrains
        /// The fare kept most of them away.
        case fares
        /// Every station it reaches is close by, where people walk or ride
        /// and nobody switches.
        case nearby
    }

    /// The trips a day lost, rounded to tens (0 for ``Reason/nearby``).
    public let riders: Int64
    public let reason: Reason
    /// Whether more of them drive than ride a scooter.
    public let byCar: Bool
    /// On a line, the pair that lost most: where from and where to.
    public let top: (from: StationID, to: StationID)?

    public init(riders: Int64, reason: Reason, byCar: Bool, top: (from: StationID, to: StationID)? = nil) {
        self.riders = riders
        self.reason = reason
        self.byCar = byCar
        self.top = top
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.riders == rhs.riders && lhs.reason == rhs.reason && lhs.byCar == rhs.byCar
            && lhs.top?.from == rhs.top?.from && lhs.top?.to == rhs.top?.to
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(riders)
        hasher.combine(reason)
        hasher.combine(byCar)
        hasher.combine(top?.from)
        hasher.combine(top?.to)
    }

    /// The SF Symbol before the line: a car when more of them drive.
    public var symbol: String { byCar ? "car.fill" : "scooter" }

    /// `trips` rounded half up to tens.
    static func tens(_ trips: Int64) -> Int64 { (trips + 5) / 10 * 10 }

    /// The summary of `losses`, or `nil` when they lost under five riders
    /// and not every one is close by (or there are none).
    public init?(_ losses: [ModeShiftLoss], top: (from: StationID, to: StationID)? = nil) {
        let riders = Self.tens(losses.reduce(0) { $0 + $1.switched + $1.tooExpensive })
        guard riders > 0 else {
            guard !losses.isEmpty, losses.allSatisfy(\.isNear) else { return nil }
            self.init(riders: 0, reason: .nearby, byCar: false)
            return
        }
        let waiting = losses.filter(\.waitsLongest).reduce(0) { $0 + $1.switched }
        let riding = losses.filter { !$0.waitsLongest }.reduce(0) { $0 + $1.switched }
        let fares = losses.reduce(0) { $0 + $1.tooExpensive }
        let reason: Reason = waiting >= riding && waiting >= fares ? .fewTrains : riding >= fares ? .slowTrains : .fares
        let cars = losses.filter(\.byCar).reduce(0) { $0 + $1.switched }
        let scooters = losses.filter { !$0.byCar }.reduce(0) { $0 + $1.switched }
        self.init(riders: riders, reason: reason, byCar: cars > scooters, top: top)
    }

    /// How many switch, on a station's card.
    public func stationText(in language: DisplayLanguage) -> String {
        guard reason != .nearby else { return reasonText(in: language) }
        let count = Money(riders).displayText
        return language.text("About \(count) a day ride or drive instead", "每天約 \(count) 人改騎機車或開車")
    }

    /// How many switch on a line, and between which stations most do.
    public func lineText(in world: GameWorld, language: DisplayLanguage) -> String {
        let count = Money(riders).displayText
        guard let top, let from = world.station(id: top.from)?.name, let to = world.station(id: top.to)?.name else {
            return language.text("About \(count) a day on this line ride or drive instead", "這條線每天約 \(count) 人改騎車")
        }
        return language.text(
            "About \(count) a day on this line ride or drive instead; most from \(from) to \(to)",
            "這條線每天約 \(count) 人改騎車；最多的是\(from)到\(to)"
        )
    }

    /// What brings them back.
    public func reasonText(in language: DisplayLanguage) -> String {
        switch reason {
        case .fewTrains: language.text("Trains are too few; more trains bring them back", "班次太少，加開班次可以拉回來")
        case .slowTrains:
            language.text("Trains are too slow; faster trains or a straighter line bring them back", "列車太慢，換快一點的車或拉直路線可以拉回來")
        case .fares: language.text("Fares are too high; lower fares bring them back", "票價太貴，降一點可以拉回來")
        case .nearby: language.text("Most people this close walk or ride", "附近的人多半走路或騎車")
        }
    }
}

extension GameWorld {
    /// Decision 332: what kept the riders from station `id` off the trains,
    /// or `nil` without riders switching to scooters and cars or when
    /// nothing did.
    public func stationModeShift(of id: StationID) -> ModeShiftSummary? {
        ModeShiftSummary(modeShiftLosses(from: id))
    }

    /// Decision 332: what kept riders off line `id`, the pairs whose
    /// fastest route rides it, and the pair that lost most (the first by
    /// station IDs on a tie), or `nil` as ``stationModeShift(of:)``.
    public func lineModeShift(_ id: LineID) -> ModeShiftSummary? {
        guard modeShift != nil else { return nil }
        var losses: [ModeShiftLoss] = []
        var top: (from: StationID, to: StationID, lost: Int64)?
        for station in stations.map(\.id).sorted() {
            for loss in modeShiftLosses(from: station) where loss.lines.contains(id) {
                losses.append(loss)
                let lost = loss.switched + loss.tooExpensive
                if lost > (top?.lost ?? 0) { top = (station, loss.destination, lost) }
            }
        }
        return ModeShiftSummary(losses.filter { !$0.isNear || $0.switched + $0.tooExpensive > 0 }, top: top.map { ($0.from, $0.to) })
    }
}
