import Foundation
import GameCore

// The real day of the Taiwan High Speed Rail as the high-speed demo runs it
// (ARCHITECTURE decision 197): the 169 trains of the bundled
// `thsr-schedule.json` (``RealDailySchedule``) as runs (decision 133) of
// three lines, the demo's all-stops, nine-stop and five-stop lines, with
// the positioning runs and the sets each line needs to run the same day
// again and again.
//
// A run calls at every stop of its line between its ends, and a line with
// runs has no stopping patterns (decision 133), so each stopping pattern is
// a line of its own, and a line's sets run only its own runs. The real sets
// change patterns from one trip to the next; here a line whose real trains
// leave a station fewer times than they arrive there gathers sets there
// (the five-stop line's run north twice an hour and south once). So, as a
// set arrives where its line has more than it needs for the next two hours,
// and the day leaves that station with sets to spare, it runs back empty
// (a positioning run, `回送`) to where the line ends the day short, as many
// as the day is short there; the day then ends with every set where the
// next begins. The reference has neither the lines nor the positioning
// (its `sched` systems run each train from nowhere to nowhere): both are
// this project's.

/// The real day as the demo's three lines run it (decision 197).
struct HighSpeedTimetable: Sendable {
    /// One of the demo's lines.
    struct Line: Sendable {
        let english: String
        let chinese: String
        /// Its stops, by station index (0 Nangang to 11 Zuoying).
        let stops: [Int]
        /// Its runs, the real trains' and the positioning runs, by first
        /// departure; `from` and `to` are indices into ``stops``.
        let runs: [LineRun]
        /// How many of ``runs`` are positioning runs.
        let positioning: Int
        /// Its sets at midnight, the earliest to leave first: the station
        /// each stands at, whether the first run it takes leaves
        /// southbound, and the second of the day it leaves.
        let overnight: [(station: Int, southbound: Bool, leaving: Int64)]

        /// How many sets it needs.
        var sets: Int { overnight.count }
    }

    /// The demo's three lines, by the stations they call at, from the
    /// real day's commonest kinds of train: 32 call at all twelve, 58 at
    /// nine and 28 at five.
    static let kinds: [(english: String, chinese: String, stops: [Int])] = [
        ("THSR All Stops", "高鐵 各站停車", Array(0..<12)),
        ("THSR Nine Stops", "高鐵 九站停車", [0, 1, 2, 3, 4, 6, 9, 10, 11]),
        ("THSR Five Stops", "高鐵 五站停車", [0, 1, 2, 6, 11]),
    ]

    /// How soon a set that ends a run may take the next: ten minutes.
    static let turnaround: Int64 = 10 * 60
    /// How far ahead a set's own line is looked at to tell whether it is
    /// wanted where it stands: two hours, a round trip of the shortest
    /// line.
    static let lookahead: Int64 = 2 * 3_600
    /// How long after it is ready a positioning run leaves: five minutes.
    static let positioningDelay: Int64 = 5 * 60

    let lines: [Line]

    /// The day of `schedule` on the three lines. `names` are the stations'
    /// names in the data, north to south; `distances` how far along the
    /// line each stands, so a train's time at a stop it passes (one its
    /// line calls at) is read off between its calls either side.
    ///
    /// Each train goes on the line that takes the fewest calls to add or
    /// drop: 51 run as all-stops trains (8 of them, the trains that skip
    /// Banqiao, Hsinchu and Miaoli but call at Changhua and Yunlin, add
    /// those three calls), 60 as nine-stop and 58 as five-stop (19 drop a
    /// call at Tainan). A train calling at a station its line does not is
    /// timed as it was, without that call.
    init(schedule: RealDailySchedule, names: [String], distances: [Double]) {
        // The real trains, each as its calls by station index.
        typealias Call = (station: Int, arrival: Int64, departure: Int64)
        var trains: [[[Call]]] = Self.kinds.map { _ in [] }
        for train in schedule.trains {
            let calls: [Call] = train.stops.filter(\.stops).compactMap { stop in
                names.firstIndex(of: stop.name).map { (station: $0, arrival: Int64(stop.arrivalSecond), departure: Int64(stop.departureSecond)) }
            }
            guard calls.count >= 2, let low = calls.map(\.station).min(), let high = calls.map(\.station).max() else { continue }
            let called = Set(calls.map(\.station))
            var best: (cost: (Int, Int), kind: Int)?
            for (kind, line) in Self.kinds.enumerated() where line.stops.contains(low) && line.stops.contains(high) {
                let between = Set(line.stops.filter { (low...high).contains($0) })
                let added = between.subtracting(called).count, dropped = called.subtracting(between).count
                let cost = (added + dropped, added)
                if best.map({ cost < $0.cost }) ?? true { best = (cost, kind) }
            }
            if let kind = best?.kind { trains[kind].append(calls) }
        }
        lines = Self.kinds.enumerated().map { kind, line in
            Self.line(line, trains: trains[kind], distances: distances)
        }
    }

    /// One line's runs, positioning runs and sets.
    private static func line(_ kind: (english: String, chinese: String, stops: [Int]), trains: [[(station: Int, arrival: Int64, departure: Int64)]], distances: [Double]) -> Line {
        let stops = kind.stops
        // A real train as a run of the line: its times at every stop of the
        // line between its ends, a stop it passes timed between its calls
        // either side by distance.
        func run(of calls: [(station: Int, arrival: Int64, departure: Int64)]) -> LineRun {
            let first = calls[0], last = calls[calls.count - 1]
            let southbound = first.station < last.station
            let from = stops.firstIndex(of: first.station)!, to = stops.firstIndex(of: last.station)!
            let times = LineRun(from: from, to: to, times: []).calls.map { index -> LineRunTime in
                let station = stops[index]
                if let call = calls.first(where: { $0.station == station }) {
                    return LineRunTime(arrival: call.arrival, departure: call.departure)
                }
                let before = calls.last { southbound ? $0.station < station : $0.station > station }!
                let after = calls.first { southbound ? $0.station > station : $0.station < station }!
                let share = (distances[station] - distances[before.station]) / (distances[after.station] - distances[before.station])
                let time = before.departure + Int64((Double(after.arrival - before.departure) * share).rounded())
                return LineRunTime(arrival: time, departure: time)
            }
            return LineRun(from: from, to: to, times: times)
        }
        let real = trains.map(run).sorted { ($0.times[0].departure, $0.from) < ($1.times[0].departure, $1.from) }
        // A positioning run copies the times of a real train calling at all
        // the line's stops, the same way, from its first departure.
        func template(southbound: Bool) -> LineRun? {
            real.first { $0.isOutbound == southbound && Set([$0.from, $0.to]) == [0, stops.count - 1] }
        }
        let templates = (south: template(southbound: true), north: template(southbound: false))
        func positioning(from: Int, to: Int, leaving: Int64) -> LineRun {
            let southbound = from < to
            guard let template = southbound ? templates.south : templates.north else {
                preconditionFailure("No train of \(kind.english) calls at all its stops \(southbound ? "southbound" : "northbound")")
            }
            let calls = template.calls
            let start = calls.firstIndex(of: from)!, end = calls.firstIndex(of: to)!
            let shift = leaving - template.times[start].departure
            var times = template.times[start...end].map { LineRunTime(arrival: $0.arrival + shift, departure: $0.departure + shift) }
            times[0] = LineRunTime(arrival: leaving, departure: leaving)
            times[times.count - 1] = LineRunTime(arrival: times[times.count - 1].arrival, departure: times[times.count - 1].arrival)
            return LineRun(from: from, to: to, times: times)
        }

        // Where the day leaves sets to spare and where it ends short.
        var spare = [Int](repeating: 0, count: stops.count), short = spare
        for run in real {
            short[run.from] += 1
            spare[run.to] += 1
        }
        for index in stops.indices {
            let net = spare[index] - short[index]
            (spare[index], short[index]) = (max(0, net), max(0, -net))
        }

        // The day in time order: sets ready at each stop, and runs taking
        // them; a run that finds none takes one standing there since
        // midnight.
        var ready = [[Int64]](repeating: [], count: stops.count)
        var arriving: [(at: Int64, stop: Int)] = []
        var overnight: [(station: Int, southbound: Bool, leaving: Int64)] = []
        var runs = real
        var positioned = 0
        let lead = LineRun.earliestDispatch
        func arrive(_ set: (at: Int64, stop: Int)) {
            let index = arriving.firstIndex { ($0.at, $0.stop) > (set.at, set.stop) } ?? arriving.count
            arriving.insert(set, at: index)
        }
        // How many sets the stop needs over the next two hours beyond those
        // arriving.
        func wanted(at stop: Int, after time: Int64) -> Int {
            var events = real.filter { $0.from == stop && (time...time + lookahead).contains($0.times[0].departure - lead) }
                .map { (at: $0.times[0].departure - lead, change: -1) }
            events += arriving.filter { $0.stop == stop && $0.at <= time + lookahead }.map { (at: $0.at, change: 1) }
            events.sort { ($0.at, -$0.change) < ($1.at, -$1.change) }
            var balance = 0, need = 0
            for event in events {
                balance += event.change
                need = max(need, -balance)
            }
            return need
        }
        func settle(until time: Int64) {
            while let set = arriving.first, set.at <= time {
                arriving.removeFirst()
                ready[set.stop].append(set.at)
                guard spare[set.stop] > 0, ready[set.stop].count > wanted(at: set.stop, after: set.at),
                      let target = short.indices.filter({ short[$0] > 0 }).max(by: { (short[$0], -$0) < (short[$1], -$1) })
                else { continue }
                spare[set.stop] -= 1
                short[target] -= 1
                ready[set.stop].removeLast()
                let leg = positioning(from: set.stop, to: target, leaving: set.at + positioningDelay)
                runs.append(leg)
                positioned += 1
                arrive((leg.times[leg.times.count - 1].arrival + turnaround, target))
            }
        }
        for run in real {
            let leaving = run.times[0].departure
            settle(until: leaving - lead)
            if ready[run.from].isEmpty {
                overnight.append((stops[run.from], run.isOutbound, leaving))
            } else {
                ready[run.from].removeFirst()
            }
            arrive((run.times[run.times.count - 1].arrival + turnaround, run.to))
        }
        settle(until: .max)
        // What the day still leaves to spare runs back at night, after the
        // last set there is ready.
        for from in spare.indices {
            while spare[from] > 0, let target = short.indices.first(where: { short[$0] > 0 }), let last = ready[from].last {
                spare[from] -= 1
                short[target] -= 1
                ready[from].removeLast()
                runs.append(positioning(from: from, to: target, leaving: last + positioningDelay))
                positioned += 1
            }
        }
        runs.sort { ($0.times[0].departure, $0.from, $0.to) < ($1.times[0].departure, $1.from, $1.to) }
        return Line(
            english: kind.english, chinese: kind.chinese, stops: stops, runs: runs, positioning: positioned,
            overnight: overnight.sorted { ($0.leaving, $0.station) < ($1.leaving, $1.station) }
        )
    }
}
