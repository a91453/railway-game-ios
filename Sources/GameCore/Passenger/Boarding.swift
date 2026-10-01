// Boarding, alighting and capacity (G1b, ARCHITECTURE decision 35), ported
// from the owner's `Ci/` reference
// (`Ci/reference_snapshot/lib/app__q_c234188b7c397f91.js`):
//
// - a train at a station first lets off those whose destination it is
//   (`updateTrainAtStation`, `metroResolveTrainAlighting`), then takes on
//   those waiting for its line and direction whose destination it calls at
//   before it next turns round (`metroCollectRawTargetsForBoarding`,
//   `isValidTargetForLeg`), the farthest first, up to its room
//   (`allocateSeats`, `metroDeductBoardingPlanFromTransferQueues`);
// - its room is its operational capacity less those on board
//   (`getMetroTrainOperationalCap`: the rated capacity × 1.1).
//
// **Transitional timing, to be replaced in W2.** The `Ci/` game boards and
// alights everyone at once as a train arrives, then dwells a fixed 36 s
// (42 s at a terminal), whatever the passengers. GameCore still steps whole
// minutes with a dwell of whole minutes, so for now a train is served once,
// as it leaves the stop: everyone who came during the dwell can board, and
// the result does not depend on how the dwell is sliced. This is not the
// permanent meaning of boarding: W2 puts "arrive → doors open → passengers
// → doors close → depart" on the game's clock with the dwell rules already
// ported in `Railway/StationDwell.swift`, and replaces this timing. Who
// boards, in what order and up to what capacity stays as it is.
//
// Dependency direction (ARCHITECTURE, "GameCore 內部的依賴方向"): this file
// reads the lines' assignments, the trains' timetables, execution progress
// and cars, nothing of the track, reservations or movement, and changes
// nothing but the passengers.

/// Passengers riding a train together: from the same station to the same
/// destination.
public struct RidingGroup: Hashable, Sendable {
    /// The station they boarded at, whose ledger counts them.
    public let origin: StationID
    public let destination: StationID
    /// How many, at least 1.
    public let count: Int64

    public init(origin: StationID, destination: StationID, count: Int64) {
        self.origin = origin
        self.destination = destination
        self.count = count
    }
}

/// Everyone riding one train (G1b): the reference's `paxBuckets`, which
/// count riders by the stop they leave at, with the station they came from.
public struct TrainRiders: Hashable, Sendable {
    public let train: TrainID
    /// By ascending origin and then destination, at most one group for each
    /// pair, never empty.
    public internal(set) var groups: [RidingGroup]

    public init(train: TrainID, groups: [RidingGroup]) {
        self.train = train
        self.groups = groups
    }

    /// How many ride the train.
    public var count: Int64 {
        groups.reduce(0) { $0 + $1.count }
    }

    /// Adds `count` riders from `origin` to `destination`, keeping the
    /// groups in order.
    mutating func add(_ count: Int64, from origin: StationID, to destination: StationID) {
        if let index = groups.firstIndex(where: { $0.origin == origin && $0.destination == destination }) {
            groups[index] = RidingGroup(origin: origin, destination: destination, count: groups[index].count + count)
        } else {
            let group = RidingGroup(origin: origin, destination: destination, count: count)
            groups.insert(group, at: groups.firstIndex { ($0.origin, $0.destination) > (origin, destination) } ?? groups.count)
        }
    }
}

extension Train {
    /// How many passengers a car is rated for: the reference's 6-car train
    /// of 1,920 (`{cars: 6, cap: 1920}`), per car.
    public static let ratedCapacityPerCar: Int64 = 320

    /// How many passengers a car takes at most: its rated capacity × 1.1
    /// (the reference's `METRO_TRAIN_OPERATIONAL_LOAD_FACTOR`), exactly.
    public static let capacityPerCar: Int64 = 352

    /// How many passengers the train is rated for: its cars × 320.
    public var ratedCapacity: Int64 {
        Int64(cars) * Self.ratedCapacityPerCar
    }

    /// How many passengers the train takes at most (G1b): its cars × 352.
    public var capacity: Int64 {
        Int64(cars) * Self.capacityPerCar
    }
}

extension GameWorld {
    // MARK: - Queries

    /// The passengers riding train `id`, by ascending origin and then
    /// destination; empty if none (or no such train).
    public func riders(of id: TrainID) -> [RidingGroup] {
        riders.first { $0.train == id }?.groups ?? []
    }

    /// How many passengers ride train `id`.
    public func riderCount(of id: TrainID) -> Int64 {
        riders.first { $0.train == id }?.count ?? 0
    }

    // MARK: - Serving stops

    /// A train leaving a stop of its service: recorded by the departure
    /// phases of ``advance(ticks:)`` and served, in the order they left,
    /// once those phases are over.
    struct StopDeparture {
        let train: TrainID
        let stop: Int
        /// How far the train runs to its next call, in world units; `nil`
        /// when its service ends at this stop instead (G1c).
        let distance: Int64?
    }

    /// The boarding phase of a basic step (see ``advance(ticks:)``): serves
    /// every stop left in this step, in the order they were left.
    mutating func serve(_ departures: [StopDeparture]) {
        // Nothing to do without passengers or accounts: worlds without
        // demand in the free economy pay nothing.
        guard !passengers.isEmpty || !riders.isEmpty || accounts.mode == .management else { return }
        for departure in departures {
            serve(departure)
        }
    }

    /// Train `departure.train` leaving stop `departure.stop` of its
    /// timetable: those riding to that stop's station get off, and so does
    /// anyone still on board at a stop where the train turns round or its
    /// service ends (the reference's `releaseAll`; nobody boards for a
    /// station past such a stop, so there is never anyone). Then, unless
    /// that was the last stop, the train takes on passengers (see
    /// ``board(_:at:)``).
    private mutating func serve(_ departure: StopDeparture) {
        guard let index = trains.firstIndex(where: { $0.id == departure.train }) else { return }
        let train = trains[index]
        let stop = train.timetable[departure.stop]
        let isLast = departure.stop == train.timetable.count - 1
        if let slot = riders.firstIndex(where: { $0.train == train.id }) {
            var kept: [RidingGroup] = []
            for group in riders[slot].groups {
                if group.destination == stop.station {
                    passengers[passengerIndex(of: group.origin)].arrived += group.count
                } else if stop.reverses || isLast {
                    passengers[passengerIndex(of: group.origin)].abandoned += group.count
                } else {
                    kept.append(group)
                }
            }
            if kept.isEmpty {
                riders.remove(at: slot)
            } else {
                riders[slot].groups = kept
            }
        }
        if !isLast {
            board(train, at: departure.stop)
        }
        // A line's train counts its departure, as it leaves with those on
        // board (G1c).
        if let distance = departure.distance, assignedLine(of: train.id) != nil {
            countDeparture(distance: distance, passengers: riderCount(of: train.id), seats: train.ratedCapacity)
        }
    }

    /// `train`, assigned to a line and leaving stop `stop` of its round
    /// trip, takes on the passengers waiting at the stop's station for its
    /// line, in its direction (outbound until the far end, inbound from
    /// there), for a station it calls at before it next turns round. The
    /// farthest of those calls go first, and for one destination those who
    /// came first; each group boards whole while there is room, and the
    /// first that does not fit boards in part. Those left behind count as
    /// refused at the station.
    private mutating func board(_ train: Train, at stop: Int) {
        guard let line = assignedLine(of: train.id),
              let record = passengers.firstIndex(where: { $0.station == train.timetable[stop].station })
        else { return }
        let direction: LineDirection = stop < (train.timetable.count - 1) / 2 ? .outbound : .inbound
        // How far along each destination is: the first call at it.
        var reach: [StationID: Int] = [:]
        for call in Self.callsAhead(of: train, leaving: stop) where reach[train.timetable[call].station] == nil {
            reach[train.timetable[call].station] = call
        }
        let waiting = passengers[record].waiting
        let eligible = waiting.indices
            .filter { waiting[$0].line == line && waiting[$0].direction == direction && reach[waiting[$0].destination] != nil }
            .enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (reach[waiting[lhs.element].destination]!, reach[waiting[rhs.element].destination]!)
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
        guard !eligible.isEmpty else { return }
        var room = max(0, train.capacity - riderCount(of: train.id))
        var taken: [Int: Int64] = [:]
        var left: Int64 = 0
        var boarding = riders.first { $0.train == train.id } ?? TrainRiders(train: train.id, groups: [])
        var paying: [StationID: Int64] = [:]
        for index in eligible {
            let group = waiting[index]
            let count = min(group.count, room)
            if count > 0 {
                taken[index] = count
                room -= count
                boarding.add(count, from: passengers[record].station, to: group.destination)
                paying[group.destination, default: 0] += count
            }
            left += group.count - count
        }
        // Each destination's boarders pay together, rounded to whole
        // dollars (G1c; the reference's fare trips of a boarding plan).
        for destination in paying.keys.sorted() {
            chargeFares(paying[destination]!, from: passengers[record].station, to: destination)
        }
        if !taken.isEmpty {
            passengers[record].board(taken)
            if let slot = riders.firstIndex(where: { $0.train == train.id }) {
                riders[slot] = boarding
            } else {
                riders.insert(boarding, at: riders.firstIndex { $0.train > train.id } ?? riders.count)
            }
        }
        if left > 0 {
            passengers[record].refuse(left)
        }
    }

    /// The timetable entries `train` calls at after leaving `stop`, up to
    /// and including the next one where it turns round or its service ends.
    static func callsAhead(of train: Train, leaving stop: Int) -> ClosedRange<Int> {
        let first = stop + 1
        return first...segmentEnd(of: train, from: first)
    }

    /// The first entry at or after `stop` where `train` turns round, or the
    /// last entry.
    static func segmentEnd(of train: Train, from stop: Int) -> Int {
        let last = train.timetable.count - 1
        return (stop...last).first { train.timetable[$0].reverses } ?? last
    }

    /// Every rider of train `id` leaves it: its service ended before it
    /// reached their destinations (see ``PassengerLedger/abandoned``).
    mutating func abandonRiders(of id: TrainID) {
        guard let slot = riders.firstIndex(where: { $0.train == id }) else { return }
        for group in riders[slot].groups {
            passengers[passengerIndex(of: group.origin)].abandoned += group.count
        }
        riders.remove(at: slot)
    }

    /// The index of station `id`'s record, which every rider's origin has.
    private func passengerIndex(of id: StationID) -> Int {
        passengers.firstIndex { $0.station == id }!
    }

    // MARK: - Validation

    /// Why the riders break a G1b rule, or `nil`. ``TrainRiders``' decoder
    /// has checked each entry on its own; `passengerProblem()` the
    /// stations' records.
    ///
    /// Entries are by ascending train, each of an existing train running a
    /// service, with no more riders than it takes; every rider came from a
    /// station with a record, and rides to a station its train still calls
    /// at before it next turns round; and every station's riders make its
    /// counts add up to what it released.
    func riderProblem() -> String? {
        guard zip(riders, riders.dropFirst()).allSatisfy({ $0.train < $1.train }) else {
            return "Riders must be listed once for each train, by ascending train."
        }
        var riding: [StationID: Int64] = [:]
        for entry in riders {
            let id = entry.train.rawValue
            guard let train = train(id: entry.train), let execution = train.execution else {
                return "Passengers ride train \(id), which runs no service."
            }
            guard entry.count <= train.capacity else { return "More passengers ride train \(id) than it takes." }
            let ahead = execution.stop...Self.segmentEnd(of: train, from: execution.stop)
            for group in entry.groups {
                guard passengers.contains(where: { $0.station == group.origin }) else {
                    return "Passengers ride train \(id) from station \(group.origin.rawValue), which released none."
                }
                guard ahead.contains(where: { train.timetable[$0].station == group.destination }) else {
                    return "Passengers ride train \(id) to a station it does not call at before it turns round."
                }
                riding[group.origin, default: 0] += group.count
            }
        }
        for record in passengers where record.boardedAndRiding != riding[record.station] ?? 0 {
            return "Station \(record.station.rawValue)'s passengers do not add up to those it released."
        }
        return nil
    }
}

extension RidingGroup: Codable {
    private enum CodingKeys: String, CodingKey {
        case origin, destination, count
    }

    /// Decodes a group, rejecting a count outside
    /// `1...Train.maximumCars × Train.capacityPerCar` and a group riding to
    /// where it came from.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        origin = try container.decode(StationID.self, forKey: .origin)
        destination = try container.decode(StationID.self, forKey: .destination)
        count = try container.decode(Int64.self, forKey: .count)
        guard (1...Int64(Train.maximumCars) * Train.capacityPerCar).contains(count) else {
            throw DecodingError.dataCorruptedError(forKey: .count, in: container, debugDescription: "A riding group has 1 to a full train's passengers.")
        }
        guard origin != destination else {
            throw DecodingError.dataCorruptedError(forKey: .destination, in: container, debugDescription: "A riding group rides to another station.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin, forKey: .origin)
        try container.encode(destination, forKey: .destination)
        try container.encode(count, forKey: .count)
    }
}

extension TrainRiders: Codable {
    private enum CodingKeys: String, CodingKey {
        case train, groups
    }

    /// Decodes a train's riders, rejecting no groups, and groups out of
    /// order or twice. That the train and stations exist and the riders fit
    /// is checked by the ``GameWorld`` decoder.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        train = try container.decode(TrainID.self, forKey: .train)
        groups = try container.decode([RidingGroup].self, forKey: .groups)
        guard !groups.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .groups, in: container, debugDescription: "A train without riders is not saved.")
        }
        guard zip(groups, groups.dropFirst()).allSatisfy({ ($0.origin, $0.destination) < ($1.origin, $1.destination) }) else {
            throw DecodingError.dataCorruptedError(forKey: .groups, in: container, debugDescription: "Riding groups must be listed once each, by origin and then destination.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(train, forKey: .train)
        try container.encode(groups, forKey: .groups)
    }
}
