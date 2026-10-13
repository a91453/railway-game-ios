import GameCore

// The train diagram (運行圖, ARCHITECTURE decision 206; NEXT_PRIORITIES §0
// item 11, §4 item 4): one line, time across and its stations down, each
// trip of its trains drawn as the line its timetable plans, and where each
// train is now on top. Where two trips are at a station together the
// diagram marks a meet (交會, opposite ways) or an overtake (越行, the same
// way, the later one leaving first); a train behind its timetable shows
// how late and the rest of its trip shifted by that much.
//
// View only, never edited: everything is read from the world each time it
// is built (the trains' timetables and executions, the fixed-timetable
// runs not yet sent out, ``GameWorld/lateness(of:)`` and, with traffic
// control, ``GameWorld/scheduledTrafficWaits()``). The reference has no
// train diagram to port (`a91453/railway-reference-private`, searched
// 2026-10-13); the drawing is the classic time-distance graph (Marey,
// Ibry), as JMRI's TimeTable tool draws one; nothing of theirs is used.

public struct TrainDiagram: Equatable, Sendable {
    /// A row of the diagram: a stop of the line. A ring has its first stop
    /// again as its last row, so a trip round from the last stop to the
    /// first runs down to it.
    public struct Station: Equatable, Sendable {
        public let id: StationID
        public let name: String
        /// 0 at the top row to 1 at the bottom, spaced by the distance
        /// between the stations (at least ``minimumGap`` of the whole).
        public let offset: Double
        /// A station closed to passengers that trains call at to meet: a
        /// signal station (號誌站, decision 204).
        public let isSignalStation: Bool
    }

    /// A moment of a trip: when, and where along the rows (0 at the first
    /// row, 1.5 halfway from the second to the third).
    public struct Point: Equatable, Sendable {
        public let time: Int64
        public let place: Double

        public init(time: Int64, place: Double) {
            self.time = time
            self.place = place
        }
    }

    /// One planned trip: a cycle of a train's timetable, or a run of a fixed
    /// timetable not yet sent out.
    public struct Trip: Equatable, Sendable, Identifiable {
        public let id: String
        /// The train, or `nil` for a run no train has taken out yet.
        public let train: TrainID?
        public let name: String
        /// 0 for the line's own service, `n` for its `n`th pattern.
        public let service: Int
        /// An empty run to the line's other end (decision 172).
        public let isEmptyRun: Bool
        /// Its line, in pieces where it leaves the rows (a ring's way
        /// round from the last row back to the first).
        public let lines: [[Point]]
    }

    /// A train running a trip now.
    public struct Running: Equatable, Sendable, Identifiable {
        public let train: TrainID
        public let name: String
        /// Where it is now, at ``TrainDiagram/now``.
        public let now: Point
        /// Whole seconds behind its timetable, 0 when on time or early.
        public let lateSeconds: Int64
        /// The rest of its trip as it will run if it stays as late: from
        /// ``now``, the timetable's points shifted by ``lateSeconds``. Empty
        /// for a train less than a minute late.
        public let expected: [Point]

        public var id: TrainID { train }
        /// Whole minutes late.
        public var lateMinutes: Int { Int(min(lateSeconds, 24 * 3600) / 60) }
        public var isLate: Bool { lateMinutes >= 1 }
        /// Five minutes or more: the reference's strong badge
        /// (`todayDelayBadge`'s `hi`).
        public var isVeryLate: Bool { lateMinutes >= 5 }

        /// "誤點 3 分", or `nil` under a minute.
        public func lateText(in language: DisplayLanguage) -> String? {
            isLate ? language.text("\(lateMinutes) min late", "誤點 \(lateMinutes) 分") : nil
        }
    }

    /// Two trips at a station together.
    public struct Mark: Equatable, Sendable, Identifiable {
        public enum Kind: String, Equatable, Sendable {
            /// Opposite ways: one waits for the other to pass (交會).
            case meet
            /// The same way: the one that came first leaves after the other (越行).
            case overtake
        }

        public let kind: Kind
        public let station: StationID
        /// The row (a ring's first stop is row 0).
        public let place: Double
        /// When the two are there together: the middle of it, or, for a
        /// wait traffic control set, when the waiting train may leave.
        public let time: Int64
        /// The two trips' names: the one waiting first.
        public let names: [String]
        /// Set by traffic control (``GameWorld/scheduledTrafficWaits()``)
        /// rather than read off the timetables.
        public let isDispatched: Bool
        /// At a signal station.
        public let isSignalStation: Bool

        public var id: String { "\(kind.rawValue)|\(station.rawValue)|\(time)|\(names.joined(separator: "|"))" }

        /// "交會" or "越行".
        public func kindText(in language: DisplayLanguage) -> String {
            switch kind {
            case .meet: language.text("Meet", "交會")
            case .overtake: language.text("Overtake", "越行")
            }
        }
    }

    public let line: LineID
    public let lineName: String
    public let color: LineColor?
    public let stations: [Station]
    /// Whether the line between row `i` and row `i + 1` is single track,
    /// when it was asked (``singleTrackSections(of:in:)``); empty otherwise.
    public let singleTrack: [Bool]
    /// The time the diagram covers.
    public let from: Int64
    public let to: Int64
    public let now: Int64
    public let trips: [Trip]
    public let running: [Running]
    public let marks: [Mark]

    /// How far back and ahead of now a diagram is built: four hours each way.
    public static let reachSeconds: Int64 = 4 * GameTime.secondsPerHour
    /// The least share of the axis between two rows, so stations close
    /// together still have room for their names.
    public static let minimumGap = 0.04
    /// The most trips one train adds, so a short repeating timetable cannot
    /// make a diagram huge.
    static let cyclesPerTrain: Int64 = 96

    /// The trains running late, the latest first.
    public var lateTrains: [Running] {
        running.filter(\.isLate).sorted { ($0.lateSeconds, $1.train.rawValue) > ($1.lateSeconds, $0.train.rawValue) }
    }
}

// MARK: - Building

extension TrainDiagram {
    /// The diagram of line `id` in `world`, from `from` to `to` (by default
    /// ``reachSeconds`` either side of now); `nil` for an unknown line or one
    /// with fewer than two stops. `singleTrack` is
    /// ``singleTrackSections(of:in:)``, worked out once by the caller since
    /// it reads the track; without it every station's meets are marked.
    ///
    /// A line's train gets a timetable for one trip at a time, so the trips
    /// it ran before are gone from the world: `remembered` (a
    /// ``TrainDiagramHistory``'s) adds those still in the time covered.
    public init?(world: GameWorld, line id: LineID, from: Int64? = nil, to: Int64? = nil, singleTrack: [Bool] = [],
                 remembered: [Trip] = []) {
        guard let line = world.line(id: id), line.stops.count > 1 else { return nil }
        let now = world.clock.now.seconds
        let from = from ?? now - Self.reachSeconds
        let to = max(from + 1, to ?? now + Self.reachSeconds)
        self.line = id
        lineName = line.name
        color = line.color
        self.now = now
        self.from = from
        self.to = to
        stations = Self.rows(of: line, in: world)
        self.singleTrack = singleTrack.count == stations.count - 1 ? singleTrack : []
        let rows = Rows(line: line)

        var trips: [Trip] = []
        var services: [TrainID: Int] = [:]
        for train in line.trains { services[train] = 0 }
        for (index, pattern) in line.patterns.enumerated() {
            for train in pattern.trains { services[train] = index + 1 }
        }
        for trainID in line.assignedTrains {
            guard let train = world.train(id: trainID) else { continue }
            trips += Self.trips(of: train, service: services[trainID] ?? 0, rows: rows, from: from, to: to)
        }
        trips += Self.runTrips(of: line, rows: rows, from: from, to: to, now: now)
        let known = Set(trips.map(\.id))
        let earlier = remembered.filter { trip in
            !known.contains(trip.id) && trip.lines.contains { $0.contains { (from...to).contains($0.time) } }
        }
        trips = earlier + trips
        self.trips = trips

        var running: [Running] = []
        let dots = Dictionary(world.lineTrainDots(id).map { ($0.train, $0) }, uniquingKeysWith: { first, _ in first })
        for trainID in line.assignedTrains {
            guard let train = world.train(id: trainID), let execution = train.execution, let dot = dots[trainID] else { continue }
            let late = max(0, world.lateness(of: trainID) ?? 0)
            let here = Point(time: now, place: dot.position)
            var expected: [Point] = []
            if late >= GameTime.secondsPerMinute {
                expected = [here] + Self.pointsAhead(of: train, execution: execution, rows: rows, after: here)
                    .map { Point(time: $0.time + late, place: $0.place) }
            }
            running.append(Running(train: trainID, name: train.name, now: here, lateSeconds: late, expected: expected))
        }
        self.running = running
        marks = Self.marks(trips: trips, waits: world.isTrafficControlEnabled ? world.scheduledTrafficWaits() : [],
                           rows: rows, stations: stations, singleTrack: self.singleTrack, from: from, to: to)
    }

    /// Whether each stretch between two neighbouring stops of line `id` is
    /// single track (``GameWorld/parallelTracks(between:and:)`` is 1 or
    /// less), in row order. Reads the track, so worth keeping while the
    /// network and the stops stay the same.
    public static func singleTrackSections(of id: LineID, in world: GameWorld) -> [Bool] {
        guard let line = world.line(id: id), line.stops.count > 1 else { return [] }
        let stops = line.isRing ? line.stops + [line.stops[0]] : line.stops
        return zip(stops, stops.dropFirst()).map { world.parallelTracks(between: $0, and: $1) <= 1 }
    }

    /// The share of the axis at `place` (a row, or between two).
    public func offset(at place: Double) -> Double {
        guard let last = stations.last else { return 0 }
        guard place > 0 else { return stations[0].offset }
        guard place < Double(stations.count - 1) else { return last.offset }
        let below = Int(place)
        let fraction = place - Double(below)
        return stations[below].offset + (stations[below + 1].offset - stations[below].offset) * fraction
    }

    // MARK: Rows

    /// Where the line's stops go: a station's index in ``ServiceLine/stops``
    /// (a ring's first stop is also the row after its last).
    struct Rows {
        let stops: [StationID]
        let isRing: Bool

        init(line: ServiceLine) {
            self.init(stops: line.stops, isRing: line.isRing)
        }

        init(stops: [StationID], isRing: Bool) {
            self.stops = stops
            self.isRing = isRing
        }

        /// The row of `station` nearest `near`.
        func row(of station: StationID, near: Double?) -> Int? {
            let rows = stops.indices.filter { stops[$0] == station }
            guard let near else { return rows.first }
            return rows.min { abs(Double($0) - near) < abs(Double($1) - near) }
        }
    }

    static func rows(of line: ServiceLine, in world: GameWorld) -> [Station] {
        let stops = line.isRing ? line.stops + [line.stops[0]] : line.stops
        let points = stops.map { world.station(id: $0)?.point }
        var gaps: [Double] = zip(points, points.dropFirst()).map { a, b in
            guard let a, let b else { return 0 }
            let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
            return (dx * dx + dy * dy).squareRoot()
        }
        let total = gaps.reduce(0, +)
        // Evenly spaced when the distances say nothing.
        if total <= 0 { gaps = gaps.map { _ in 1 } }
        let sum = gaps.reduce(0, +)
        let floor = sum * minimumGap
        gaps = gaps.map { max($0, floor) }
        let spread = gaps.reduce(0, +)
        var offsets = [0.0]
        for gap in gaps { offsets.append(offsets[offsets.count - 1] + gap / spread) }
        return stops.enumerated().map { index, id in
            let station = world.station(id: id)
            return Station(id: id, name: station?.name ?? "", offset: min(1, offsets[index]),
                           isSignalStation: station?.operationMode == .closed)
        }
    }

    // MARK: Trips

    /// The trips of `train`'s timetable that reach into `from...to`: each
    /// cycle of a repeating one, or the one it runs once.
    static func trips(of train: Train, service: Int, rows: Rows, from: Int64, to: Int64) -> [Trip] {
        let timetable = train.timetable
        guard let first = timetable.first, let last = timetable.last else { return [] }
        let cycles: ClosedRange<Int64>
        if let period = train.timetablePeriod, period > 0 {
            let lowest = max(0, (from - last.departure.seconds) / period - 1)
            let highest = (to - first.arrival.seconds) / period + 1
            guard highest >= lowest else { return [] }
            cycles = lowest...min(highest, lowest + cyclesPerTrain - 1)
        } else {
            guard last.departure.seconds >= from, first.arrival.seconds <= to else { return [] }
            cycles = 0...0
        }
        var trips: [Trip] = []
        for cycle in cycles {
            let (shift, overflow) = cycle.multipliedReportingOverflow(by: train.timetablePeriod ?? 0)
            guard !overflow, shift <= Int64.max / 2 - last.departure.seconds else { break }
            var stops = timetable.map { (station: $0.station, arrival: $0.arrival.seconds + shift, departure: $0.departure.seconds + shift) }
            // A repeating timetable runs on to the next cycle's first stop.
            if let period = train.timetablePeriod, period > 0 {
                let next = first.arrival.seconds + shift + period
                stops.append((station: first.station, arrival: next, departure: next))
            }
            guard stops[stops.count - 1].departure >= from, stops[0].arrival <= to else { continue }
            let lines = Self.lines(through: stops, rows: rows)
            guard !lines.isEmpty else { continue }
            trips.append(Trip(id: "t\(train.id.rawValue)|\(stops[0].arrival)", train: train.id, name: train.name, service: service,
                              isEmptyRun: train.isDeadheading, lines: lines))
        }
        return trips
    }

    /// The runs of a fixed timetable (decision 133) no train has taken out,
    /// on the days that reach into `from...to`.
    static func runTrips(of line: ServiceLine, rows: Rows, from: Int64, to: Int64, now: Int64) -> [Trip] {
        guard !line.runs.isEmpty else { return [] }
        let day = GameTime.secondsPerDay
        let firstDay = max(0, from / day - 1), lastDay = max(0, to / day)
        guard lastDay >= firstDay else { return [] }
        var trips: [Trip] = []
        for (index, run) in line.runs.enumerated() {
            let sent = line.runDays.indices.contains(index) ? line.runDays[index] : nil
            for date in firstDay...lastDay {
                guard run.days & (1 << StationDemand.weekday(ofDay: date)) != 0, (sent ?? -1) < date else { continue }
                let base = date * day
                // A run no train took out in time was dropped for the day.
                guard now <= base + (run.times.first?.departure ?? 0) + LineRun.latestDispatch else { continue }
                let stops = zip(run.calls, run.times).map { call, time in
                    (station: line.stops[call], arrival: base + time.arrival, departure: base + time.departure)
                }
                guard let a = stops.first, let b = stops.last, b.departure >= from, a.arrival <= to else { continue }
                let lines = Self.lines(through: stops, rows: rows)
                guard !lines.isEmpty else { continue }
                trips.append(Trip(id: "r\(index)|\(date)", train: nil, name: "", service: 0, isEmptyRun: false, lines: lines))
            }
        }
        return trips
    }

    /// The line through `stops`: arriving and leaving at each one's row, in
    /// pieces where a stop is off the line or a ring goes round.
    static func lines(through stops: [(station: StationID, arrival: Int64, departure: Int64)], rows: Rows) -> [[Point]] {
        var lines: [[Point]] = []
        var current: [Point] = []
        var previous: Int?
        let count = rows.stops.count
        func finish() {
            if current.count > 1 { lines.append(current) }
            current = []
        }
        for stop in stops {
            guard let row = rows.row(of: stop.station, near: previous.map(Double.init)) else {
                finish()
                previous = nil
                continue
            }
            if let previous, rows.isRing, abs(row - previous) == count - 1 {
                // Round the ring: down to the extra last row, or up from it.
                if previous == count - 1 {
                    current.append(Point(time: stop.arrival, place: Double(count)))
                    finish()
                } else if let left = current.last {
                    finish()
                    current = [Point(time: left.time, place: Double(count))]
                }
            }
            current.append(Point(time: stop.arrival, place: Double(row)))
            if stop.departure > stop.arrival {
                current.append(Point(time: stop.departure, place: Double(row)))
            }
            previous = row
        }
        finish()
        return lines
    }

    /// The timetable's points still ahead of a train at `here`: the calls
    /// after the one it is at or heading for, to the end of the cycle.
    static func pointsAhead(of train: Train, execution: TimetableExecution, rows: Rows, after here: Point) -> [Point] {
        let timetable = train.timetable
        guard timetable.indices.contains(execution.stop) else { return [] }
        let shift = (train.timetablePeriod ?? 0) * execution.cycle
        var points: [Point] = []
        var previous: Double? = here.place
        let start: Int
        switch execution {
        case .waitingAtStop(let stop, _): start = stop
        case .travellingToStop(let stop, _): start = stop
        }
        for index in start..<timetable.count {
            let stop = timetable[index]
            guard let row = rows.row(of: stop.station, near: previous) else { break }
            // A ring going round: stop at the end of the rows.
            if let previous, abs(Double(row) - previous) > Double(rows.stops.count) / 2 { break }
            let arrival = stop.arrival.seconds + shift, departure = stop.departure.seconds + shift
            if case .waitingAtStop = execution, index == start {
                // Due out at `departure`: the caller adds the lateness,
                // which for a train held past it is the time since.
                points.append(Point(time: departure, place: Double(row)))
            } else {
                points.append(Point(time: arrival, place: Double(row)))
                if departure > arrival { points.append(Point(time: departure, place: Double(row))) }
            }
            previous = Double(row)
        }
        return points
    }

    // MARK: Marks

    /// A trip at a row: from when it arrives to when it leaves (the same
    /// second when it runs through), and which way it goes on.
    struct Visit {
        var trip: Int
        var row: Int
        var arrival: Int64
        var departure: Int64
        /// +1 down the rows, -1 up.
        var way: Int
    }

    static func visits(of trip: Trip, index: Int, rowCount: Int, isRing: Bool) -> [Visit] {
        var visits: [Visit] = []
        let ringRow = rowCount - 1
        func normal(_ row: Int) -> Int { isRing && row == ringRow ? 0 : row }
        for line in trip.lines {
            // Ways of each segment, to give a stop the way it goes on.
            func way(after segment: Int) -> Int {
                var j = segment
                while j + 1 < line.count {
                    let d = line[j + 1].place - line[j].place
                    if d != 0 { return d > 0 ? 1 : -1 }
                    j += 1
                }
                j = segment
                while j > 0 {
                    let d = line[j].place - line[j - 1].place
                    if d != 0 { return d > 0 ? 1 : -1 }
                    j -= 1
                }
                return 1
            }
            // Rows run through between two points.
            func passes(from a: Point, to b: Point) {
                let low = min(a.place, b.place), high = max(a.place, b.place)
                var row = Int(low.rounded(.down)) + 1
                while Double(row) < high {
                    let fraction = (Double(row) - a.place) / (b.place - a.place)
                    let time = a.time + Int64((Double(b.time - a.time) * fraction).rounded())
                    visits.append(Visit(trip: index, row: normal(row), arrival: time, departure: time, way: b.place > a.place ? 1 : -1))
                    row += 1
                }
            }
            var i = 0
            while i < line.count {
                let point = line[i]
                if point.place == point.place.rounded() {
                    var j = i
                    while j + 1 < line.count, line[j + 1].place == point.place { j += 1 }
                    visits.append(Visit(trip: index, row: normal(Int(point.place)), arrival: point.time, departure: line[j].time, way: way(after: j)))
                    if j + 1 < line.count { passes(from: line[j], to: line[j + 1]) }
                    i = j + 1
                } else {
                    if i + 1 < line.count { passes(from: point, to: line[i + 1]) }
                    i += 1
                }
            }
        }
        return visits
    }

    static func marks(trips: [Trip], waits: [ScheduledTrafficWait], rows: Rows, stations: [Station],
                      singleTrack: [Bool], from: Int64, to: Int64) -> [Mark] {
        var marks: [Mark] = []
        // Traffic control's own waits first: what will actually happen.
        let names = Dictionary(trips.compactMap { trip in trip.train.map { ($0, trip.name) } }, uniquingKeysWith: { first, _ in first })
        for wait in waits where names[wait.train] != nil && names[wait.other] != nil {
            guard (from...to).contains(wait.departure.seconds), let row = rows.row(of: wait.station, near: nil) else { continue }
            marks.append(Mark(kind: wait.kind == .meet ? .meet : .overtake, station: wait.station, place: Double(row),
                              time: wait.departure.seconds, names: [names[wait.train] ?? "", names[wait.other] ?? ""],
                              isDispatched: true, isSignalStation: stations[row].isSignalStation))
        }
        // Then what the timetables plan.
        var byRow: [Int: [Visit]] = [:]
        for (index, trip) in trips.enumerated() {
            for visit in visits(of: trip, index: index, rowCount: stations.count, isRing: rows.isRing) {
                byRow[visit.row, default: []].append(visit)
            }
        }
        for row in byRow.keys.sorted() {
            let visits = byRow[row]!.sorted { ($0.arrival, $0.trip) < ($1.arrival, $1.trip) }
            let station = stations[row]
            // Meets on double track are no event: only where a stretch
            // beside the station is single track, or at a signal station.
            let besideSingle = singleTrack.isEmpty
                || (row > 0 && singleTrack[row - 1]) || (row < singleTrack.count && singleTrack[row])
                || (rows.isRing && row == 0 && singleTrack.last == true)
            for (n, a) in visits.enumerated() {
                for b in visits[(n + 1)...] {
                    guard b.arrival <= a.departure else { break }
                    // A train's own trips meet only themselves at a terminus.
                    guard a.trip != b.trip, trips[a.trip].train == nil || trips[a.trip].train != trips[b.trip].train else { continue }
                    let kind: Mark.Kind
                    if a.way != b.way {
                        guard besideSingle || station.isSignalStation, a.departure > a.arrival || b.departure > b.arrival else { continue }
                        kind = .meet
                    } else {
                        // Came first, left after the other.
                        guard a.arrival < b.arrival, b.departure < a.departure else { continue }
                        kind = .overtake
                    }
                    let time = (max(a.arrival, b.arrival) + min(a.departure, b.departure)) / 2
                    guard (from...to).contains(time) else { continue }
                    let pair = [trips[a.trip].name, trips[b.trip].name]
                    // Traffic control's mark for the same two stands.
                    let known = marks.contains { mark in
                        mark.isDispatched && mark.station == station.id && Set(mark.names) == Set(pair) && abs(mark.time - time) <= 900
                    }
                    guard !known else { continue }
                    marks.append(Mark(kind: kind, station: station.id, place: Double(row), time: time, names: pair,
                                      isDispatched: false, isSignalStation: station.isSignalStation))
                }
            }
        }
        return marks.sorted { ($0.time, $0.place, $0.id) < ($1.time, $1.place, $1.id) }
    }
}

// MARK: - History

/// What a diagram on the screen remembers while it is open (decision 206):
/// the trips the world no longer holds (a line's train is given one trip
/// at a time) and where each train actually was, sampled each time the
/// diagram was built. View state only; it starts empty when the diagram
/// opens and again when the line changes or the clock goes back (a game
/// loaded).
public struct TrainDiagramHistory: Equatable, Sendable {
    public private(set) var line: LineID?
    public private(set) var trips: [TrainDiagram.Trip] = []
    /// Each train's actual places, in pieces where it stopped running a
    /// trip or went round a ring.
    public private(set) var trails: [TrainID: [[TrainDiagram.Point]]] = [:]
    private var last: Int64?

    public init() {}

    /// Keeps `diagram`'s trips and where its trains are now.
    public mutating func record(_ diagram: TrainDiagram) {
        if line != diagram.line || (last ?? .min) > diagram.now {
            self = TrainDiagramHistory()
            line = diagram.line
        }
        last = diagram.now
        let keep = diagram.now - TrainDiagram.reachSeconds
        var byID = Dictionary(trips.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for trip in diagram.trips where trip.train != nil { byID[trip.id] = trip }
        trips = byID.values
            .filter { trip in trip.lines.contains { $0.last.map { $0.time >= keep } ?? false } }
            .sorted { $0.id < $1.id }
        let half = Double(max(1, diagram.stations.count - 1)) / 2
        var running = Set<TrainID>()
        for train in diagram.running {
            running.insert(train.train)
            var pieces = trails[train.train] ?? []
            if let previous = pieces.last?.last, previous.time < train.now.time, abs(previous.place - train.now.place) <= half {
                pieces[pieces.count - 1].append(train.now)
            } else if pieces.last?.last?.time != train.now.time {
                pieces.append([train.now])
            }
            trails[train.train] = pieces
        }
        for (train, pieces) in trails {
            // A train no longer running starts a new piece when it runs again.
            var kept = pieces.compactMap { piece -> [TrainDiagram.Point]? in
                let recent = piece.filter { $0.time >= keep }
                return recent.isEmpty ? nil : recent
            }
            if !running.contains(train), kept.last?.isEmpty == false { kept.append([]) }
            trails[train] = kept.isEmpty ? nil : kept
        }
    }
}

// MARK: - Viewport

/// The part of a ``TrainDiagram`` on the screen, moved by pinching and
/// dragging (decision 206): times from ``start`` for ``span`` seconds
/// across, and the station axis from ``top`` for ``height`` of it down.
/// View state only; both are clamped to the diagram's time and axis.
public struct TrainDiagramViewport: Equatable, Sendable {
    public private(set) var start: Double
    public private(set) var span: Double
    public private(set) var top: Double
    public private(set) var height: Double
    /// Whether the view keeps now in sight as the clock runs, at
    /// ``followShare`` from the leading edge; a drag stops it.
    public private(set) var follows: Bool

    /// The closest the time axis zooms: 15 minutes across.
    public static let shortestSpan: Double = 15 * 60
    /// The widest: the whole of ``TrainDiagram/reachSeconds`` both ways.
    public static let longestSpan = Double(2 * TrainDiagram.reachSeconds)
    /// Two hours across when the diagram opens.
    public static let openingSpan: Double = 2 * 3600
    /// The least share of the station axis shown: zoomed in, a sixth.
    public static let shortestHeight = 1.0 / 6
    /// Where now stands while following: a quarter of the way across.
    public static let followShare = 0.25

    public init(now: Int64, span: Double = TrainDiagramViewport.openingSpan) {
        self.span = min(max(span, Self.shortestSpan), Self.longestSpan)
        start = Double(now) - self.span * Self.followShare
        top = 0
        height = 1
        follows = true
    }

    /// Keeps now in sight, if following, and the view inside `diagram`.
    public mutating func update(to diagram: TrainDiagram) {
        if follows { start = Double(diagram.now) - span * Self.followShare }
        clamp(to: diagram)
    }

    /// Zooms by `scale` across and `verticalScale` down (above 1 closer)
    /// about the point at `anchorX`, `anchorY` (shares of the view), which
    /// stays where it is.
    public mutating func zoom(by scale: Double, verticalScale: Double, anchorX: Double, anchorY: Double, in diagram: TrainDiagram) {
        guard scale > 0, verticalScale > 0 else { return }
        let time = start + span * anchorX
        span = min(max(span / scale, Self.shortestSpan), Self.longestSpan)
        start = time - span * anchorX
        let place = top + height * anchorY
        height = min(max(height / verticalScale, Self.shortestHeight), 1)
        top = place - height * anchorY
        if follows { start = Double(diagram.now) - span * Self.followShare }
        clamp(to: diagram)
    }

    /// Moves the view by `dx`, `dy` shares of it (positive drags the
    /// diagram right and down, back in time and up the stations), and stops
    /// following now when it moves in time.
    public mutating func pan(dx: Double, dy: Double, in diagram: TrainDiagram) {
        if dx != 0 { follows = false }
        start -= dx * span
        top -= dy * height
        clamp(to: diagram)
    }

    /// Back to following now.
    public mutating func follow(in diagram: TrainDiagram) {
        follows = true
        update(to: diagram)
    }

    /// The share across the view of `time` (0 leading edge, 1 trailing).
    public func x(of time: Int64) -> Double {
        (Double(time) - start) / span
    }

    /// The share down the view of axis share `offset`.
    public func y(of offset: Double) -> Double {
        (offset - top) / height
    }

    /// The time at the view's share `x`.
    public func time(at x: Double) -> Double {
        start + span * x
    }

    /// The times to label across, on a round step giving about `count`.
    public func ticks(count: Int = 6) -> [Int64] {
        let steps: [Int64] = [5, 10, 15, 20, 30, 60, 120, 180, 240].map { $0 * 60 }
        let wanted = span / Double(max(1, count))
        let step = steps.first { Double($0) >= wanted } ?? steps[steps.count - 1]
        var tick = Int64((start / Double(step)).rounded(.up)) * step
        var ticks: [Int64] = []
        while Double(tick) <= start + span {
            ticks.append(tick)
            tick += step
        }
        return ticks
    }

    private mutating func clamp(to diagram: TrainDiagram) {
        let low = Double(diagram.from), high = Double(diagram.to)
        span = min(span, max(Self.shortestSpan, high - low))
        start = min(max(start, low), max(low, high - span))
        top = min(max(top, 0), 1 - height)
    }
}
