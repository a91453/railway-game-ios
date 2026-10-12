import GameCore

// What needs the player, on the map where it is (ARCHITECTURE decision
// 109, UI/UX step UX-5c): a crowded station, or a line with no train to
// run it, shows a small bubble over its station, and a tap on the bubble
// goes to it. SimCity BuildIt floats such bubbles over its buildings, and
// Unciv folds its notices to an edge; the reference's `Ci/` posts crowding
// as a notice with a cooldown (`emitCrowdAndFullTrainNotices`). Here the
// bubbles are worked out from the world each time it is drawn, so nothing
// is stored and nothing needs dismissing: a bubble goes when its cause
// does.

/// Something on the map that needs the player.
public struct MapAlert: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// Half the station's room for waiting passengers or more is
        /// taken (``StationPassengers/capacity``).
        case crowded(waiting: Int64)
        /// The station's room is full: passengers arriving now leave.
        case full(waiting: Int64)
        /// The line has no train, so no one rides it.
        case lineWithoutTrains(LineID)
        /// The line has lost money on each of the last seven days
        /// (decision 179).
        case lineLosingMoney(LineID)
        /// The town round the station was short of building materials at
        /// the last midnight and grew slowly (decision 158).
        case materialsShort
        /// The train is in a deadlock under traffic control: it waits for
        /// track only trains waiting with it hold (decision 184; Stage V2's
        /// ``GameWorld/deadlockedTrains()``). Over its head.
        case trainStuck(TrainID)
        /// A sight of four stars or more has no station within reach
        /// (decisions 174 and 184), once the company runs a line. Over it.
        case sightWithoutStation(AttractionID)
        /// A challenge is lost when the cash stays below zero this many
        /// more days (decisions 175 and 184). Over the first station.
        case insolvency(days: Int64)
    }

    public let kind: Kind
    /// The station the bubble stands over, or `nil` for a train's or a
    /// sight's.
    public let station: StationID?
    /// Where it stands.
    public let location: PlanPoint

    /// What the bubble is about, whatever it says now (decision 184,
    /// later): the kind of worry and the station, line, train or sight it
    /// is over. The waiting count, the days left and where a train's head
    /// is are left out, so a bubble whose figure changes stays the same
    /// bubble on the map instead of popping up again at every tick; a
    /// crowded station that fills stays one bubble too.
    public struct ID: Hashable, Sendable {
        enum Subject: Hashable, Sendable {
            case waiting, lineWithoutTrains(LineID), lineLosingMoney(LineID), materialsShort
            case trainStuck(TrainID), sightWithoutStation(AttractionID), insolvency
        }

        let subject: Subject
        let station: StationID?
    }

    public var id: ID {
        let subject: ID.Subject = switch kind {
        case .crowded, .full: .waiting
        case .lineWithoutTrains(let line): .lineWithoutTrains(line)
        case .lineLosingMoney(let line): .lineLosingMoney(line)
        case .materialsShort: .materialsShort
        case .trainStuck(let train): .trainStuck(train)
        case .sightWithoutStation(let sight): .sightWithoutStation(sight)
        case .insolvency: .insolvency
        }
        return ID(subject: subject, station: station)
    }

    public init(kind: Kind, station: StationID?, location: PlanPoint) {
        self.kind = kind
        self.station = station
        self.location = location
    }

    /// What the bubble says, short.
    public func text(in language: DisplayLanguage, lineName: String? = nil, subject: String? = nil) -> String {
        switch kind {
        case .crowded(let waiting):
            language.text("Crowded · \(Money(waiting).displayText)", "擁擠 · \(Money(waiting).displayText) 人")
        case .full:
            language.text("Full", "滿了")
        case .lineWithoutTrains:
            language.text("\(lineName ?? "Line"): no trains", "\(lineName ?? "路線")：沒有列車")
        case .lineLosingMoney:
            language.text("\(lineName ?? "Line"): losing money", "\(lineName ?? "路線")：連續虧損")
        case .materialsShort:
            language.text("Short of building materials", "缺建材")
        case .trainStuck:
            language.text("\(subject ?? "Train"): stuck", "\(subject ?? "列車")：卡住了")
        case .sightWithoutStation:
            language.text("\(subject ?? "Sight"): no station", "\(subject ?? "景點")：沒有車站")
        case .insolvency(let days):
            insolvencyCountdownText(days, in: language)
        }
    }
}

extension GameWorld {
    /// The bubbles the map shows (decision 109): each station whose
    /// waiting passengers fill half its room or more, and the first stop
    /// of each line without a train, its own or its patterns'. Stations by
    /// ascending ID, then lines by ascending ID; a station crowded and a
    /// line's first stop at once gets both.
    public func mapAlerts() -> [MapAlert] {
        var alerts: [MapAlert] = []
        // Worked out for every frame the map draws: the counts in one pass,
        // not a search of the records for each station.
        let counts = MapLayers.waitingPassengerCounts(in: self)
        for station in stations {
            let waiting = counts[station.id] ?? 0
            if waiting >= StationPassengers.capacity {
                alerts.append(MapAlert(kind: .full(waiting: waiting), station: station.id, location: station.location))
            } else if waiting * 2 >= StationPassengers.capacity {
                alerts.append(MapAlert(kind: .crowded(waiting: waiting), station: station.id, location: station.location))
            }
        }
        for line in lines where line.trains.isEmpty && line.patterns.allSatisfy({ $0.trains.isEmpty }) {
            guard let first = line.stops.first, let station = station(id: first) else { continue }
            alerts.append(MapAlert(kind: .lineWithoutTrains(line.id), station: first, location: station.location))
        }
        // Decision 179: a line that has lost money a week running.
        for line in lines where lineLosingMoney(line.id) {
            guard let first = line.stops.first, let station = station(id: first) else { continue }
            alerts.append(MapAlert(kind: .lineLosingMoney(line.id), station: first, location: station.location))
        }
        // Decision 158: then the stations short of building materials.
        for id in freight?.lastShort ?? [] {
            guard let station = station(id: id) else { continue }
            alerts.append(MapAlert(kind: .materialsShort, station: id, location: station.location))
        }
        return alerts
    }

    /// The bubbles decision 184 adds, after ``mapAlerts()``: each train in
    /// a deadlock, each sight of ``alertedSightStars`` or more without a
    /// station once a passenger line runs, and a challenge's days left in
    /// the red. Apart from ``mapAlerts()``, which the station master asks
    /// at every step: a deadlock is worked out from every waiting train.
    public func situationAlerts() -> [MapAlert] {
        var alerts: [MapAlert] = []
        if isTrafficControlEnabled {
            for id in deadlockedTrains() {
                guard let head = bodyPath(of: id).first else { continue }
                alerts.append(MapAlert(kind: .trainStuck(id), station: nil, location: PlanPoint(x: head.x, y: head.y)))
            }
        }
        if let tourism, lines.contains(where: { !$0.isFreight }) {
            // The rating with its hotels (``stars(of:)``), as the panel shows it.
            for sight in tourism.attractions where stars(of: sight) >= Self.alertedSightStars && attractionStation(of: sight.id) == nil {
                alerts.append(MapAlert(kind: .sightWithoutStation(sight.id), station: nil, location: sight.point))
            }
        }
        if let days = insolvencyCountdown, let first = stations.first {
            alerts.append(MapAlert(kind: .insolvency(days: days), station: first.id, location: first.location))
        }
        return alerts
    }

    /// The rating from which a sight without a station shows on the map,
    /// in hundredths of a star: the ones worth a line, not all of them.
    public static let alertedSightStars = 400
}

/// The bubbles ``GameSession/situationAlerts`` worked out, and for what.
struct SituationAlertsMemo {
    let revision: Int
    let period: Int64
    let alerts: [MapAlert]
}

extension GameSession {
    /// How long ``situationAlerts`` keeps its bubbles while game time runs
    /// and no command changes the world: ten game minutes, a second at the
    /// normal speed.
    static let situationAlertsPeriod: Int64 = 10 * 60

    /// ``GameWorld/situationAlerts()``, as the map draws them: worked out
    /// again after a command (``commandRevision``) and every
    /// ``situationAlertsPeriod`` of game time, not at every tick and every
    /// read. The deadlock search behind a stuck train's bubble asks a route
    /// of every waiting train: tens of milliseconds a time on the
    /// real-world demo, read twice a frame and ten frames a second.
    public var situationAlerts: [MapAlert] {
        let period = world.clock.now.seconds / Self.situationAlertsPeriod
        if let memo = situationAlertsMemo, memo.revision == commandRevision, memo.period == period {
            return memo.alerts
        }
        let alerts = world.situationAlerts()
        situationAlertsMemo = SituationAlertsMemo(revision: commandRevision, period: period, alerts: alerts)
        return alerts
    }

    /// Goes to what `alert` is about: selects its station, or for a line
    /// without trains, the line, so the line panel shows how to staff it
    /// (decision 101). Returns whether the line panel should open. Never
    /// changes the world.
    @discardableResult
    public func respond(to alert: MapAlert) -> Bool {
        switch alert.kind {
        case .crowded, .full, .materialsShort, .insolvency:
            if let station = alert.station { selectStation(station) }
            return false
        case .lineWithoutTrains(let line), .lineLosingMoney(let line):
            selectLine(line)
            return true
        case .trainStuck(let train):
            // As a tap on the train: the inspector shows it alone.
            if world.train(id: train) != nil { tapTrain(train) }
            return false
        case .sightWithoutStation:
            lookAt(alert.location)
            return false
        }
    }
}
