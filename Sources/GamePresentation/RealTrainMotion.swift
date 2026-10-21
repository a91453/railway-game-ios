import Foundation
import GameCore

// The real railways' own trains on a real-world map (ARCHITECTURE decision
// 304, NEXT_PRIORITIES §17 R2): the trains of the timetables the app
// bundles, each where its timetable puts it at the game's time, drawn faint
// and small under the player's. Only drawing: they carry no one, earn
// nothing and never stand in a player's train's way, and nothing of them
// reaches GameCore or a save.
//
// Ported from the `Railway/` site (`taiwan-rail-reference-clean/source/
// main-reference.js`) and the geo-scene reference's engines
// (`geo-scene-reference-clean/source/src/engines/RailEngine.ts`):
// - a line's shape and how far along it each station is (`ensureCum`,
//   `posAlongShape`, the stations' `d` in kilometres);
// - a metro or light rail trip's place between two calls
//   (`freqTrainPosRaw`): it leaves a station at its call's second, runs the
//   segments' run time (`runBetween`) or the whole gap when that is shorter
//   or unknown, and waits at the next station for its call; the site's
//   acceleration profile (`buildProfile`) is left out, so a train runs at
//   one speed between stations;
// - the shorter way round a ring (`posBetweenStations`);
// - a scheduled train's (the High Speed Rail's) segment between a stop's
//   departure and the next stop's arrival (`RailEngine` `findCurrentSegment`);
// - a line with only headways (Taiwan Railway's `tra.json`) as the site
//   draws a line without a timetable (`buildLineSchedule`, `posPeriodic`):
//   one train there and back over the line, its stops' run times from the
//   segments or the distance at the system's speed and 25 seconds at each
//   station, and as many trains spread over the round trip as the headway
//   gives (`ln.n`).
//
// The game's own additions: the day's set of a metro timetable from the
// game's weekday and holidays (``RealServiceDay``); a trip after midnight
// from the day before's set; the headway lines run from 05:00 to midnight
// (the site's run all day); Taiwan Railway's speed, which the site does
// not give (it draws every TRA train from its dense timetable, not
// bundled); only the trains on the world's map and in the visible region.

/// Which of a timetable's sets a game day runs (decision 304): its weekday
/// and whether it is a holiday of the game's calendar.
public struct RealServiceDay: Hashable, Sendable {
    /// 0 for Sunday to 6 for Saturday (``GameDate/weekday``).
    public let weekday: Int
    public let isHoliday: Bool

    public init(weekday: Int, isHoliday: Bool = false) {
        self.weekday = ((weekday % 7) + 7) % 7
        self.isHoliday = isHoliday
    }

    /// Game day `day` of `world`: its weekday, and a holiday when the
    /// world's holidays have one on it (decision 211).
    public init(world: GameWorld, day: Int64) {
        self.init(weekday: StationDemand.weekday(ofDay: day), isHoliday: world.holiday(onDay: day) != nil)
    }
}

extension RealLineTimetable {
    /// The set a game day runs, as ``setName(forServiceDay:)`` picks a real
    /// day's: a holiday the holiday set (or the first day's), any other day
    /// its weekday's.
    public func setName(for day: RealServiceDay) -> String? {
        if day.isHoliday, let name = holiday ?? days.first { return name }
        return days.indices.contains(day.weekday) ? days[day.weekday] : nil
    }
}

/// A line's shape and how far along it each of its points is, in
/// kilometres (the site's `ensureCum`, measured as the site measures:
/// `haversineKm`, a sphere of 6,371 km, so the stations' `d` fit it).
public struct RealLineShape: Hashable, Sendable {
    public let points: [RealRailways.Coordinate]
    public let cumulativeKm: [Double]

    /// `nil` for fewer than two points.
    public init?(_ points: [RealRailways.Coordinate]) {
        guard points.count >= 2 else { return nil }
        var cumulative = [0.0]
        cumulative.reserveCapacity(points.count)
        for index in 1..<points.count {
            cumulative.append(cumulative[index - 1] + Self.haversineKm(points[index - 1], points[index]))
        }
        self.points = points
        cumulativeKm = cumulative
    }

    public var lengthKm: Double { cumulativeKm[cumulativeKm.count - 1] }

    /// The site's `posAlongShape`: the point `km` along the shape, held at
    /// its ends.
    public func coordinate(atKm km: Double) -> RealRailways.Coordinate {
        let n = points.count
        if km <= 0 { return points[0] }
        if km >= cumulativeKm[n - 1] { return points[n - 1] }
        var lo = 0, hi = n - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if cumulativeKm[mid] <= km { lo = mid } else { hi = mid }
        }
        let span = cumulativeKm[hi] - cumulativeKm[lo]
        let f = span > 0 ? (km - cumulativeKm[lo]) / span : 0
        return RealRailways.Coordinate(
            latitude: points[lo].latitude + (points[hi].latitude - points[lo].latitude) * f,
            longitude: points[lo].longitude + (points[hi].longitude - points[lo].longitude) * f
        )
    }

    /// The site's `haversineKm`.
    static func haversineKm(_ a: RealRailways.Coordinate, _ b: RealRailways.Coordinate) -> Double {
        let toRadians = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * toRadians, dLon = (b.longitude - a.longitude) * toRadians
        let x = pow(sin(dLat / 2), 2) + cos(a.latitude * toRadians) * cos(b.latitude * toRadians) * pow(sin(dLon / 2), 2)
        return 2 * 6_371 * asin(min(1, sqrt(x)))
    }
}

/// One real train's run along its line (decision 304): the places it stops
/// at, how far along the line's shape each is, and when it arrives and
/// leaves, in seconds of the service day (past 86,400 after midnight).
public struct RealTrainRun: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        public let km: Double
        public let arrival: Int
        public let departure: Int

        public init(km: Double, arrival: Int, departure: Int) {
            self.km = km
            self.arrival = arrival
            self.departure = departure
        }
    }

    public let stops: [Stop]

    /// `nil` for fewer than two stops.
    public init?(stops: [Stop]) {
        guard stops.count >= 2 else { return nil }
        self.stops = stops
    }

    public var start: Int { stops[0].arrival }
    public var end: Int { stops[stops.count - 1].departure }

    /// Where the train is at `second`, `nil` before its first stop's
    /// arrival or after its last's departure: how far along the line, and
    /// the place it is heading for (the next stop; past the last, on from
    /// the stop before). `ringKm`: a ring's length, so a train takes the
    /// shorter way round between two stops (`posBetweenStations`).
    public func place(at second: Double, ringKm: Double? = nil) -> (km: Double, towardKm: Double)? {
        guard second >= Double(start), second <= Double(end) else { return nil }
        var lo = 0, hi = stops.count - 1
        // The last stop that has arrived.
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if Double(stops[mid].arrival) <= second { lo = mid } else { hi = mid - 1 }
        }
        let stop = stops[lo]
        guard lo + 1 < stops.count else {
            let before = stops[lo - 1].km
            return (stop.km, stop.km + Self.way(from: before, to: stop.km, ringKm: ringKm))
        }
        let next = stops[lo + 1]
        if second <= Double(stop.departure) { return (stop.km, next.km) }
        let span = Double(next.arrival - stop.departure)
        let f = span > 0 ? min(1, (second - Double(stop.departure)) / span) : 1
        var km = stop.km + Self.way(from: stop.km, to: next.km, ringKm: ringKm) * f
        if let ringKm, ringKm > 0 { km = (km.truncatingRemainder(dividingBy: ringKm) + ringKm).truncatingRemainder(dividingBy: ringKm) }
        return (km, next.km)
    }

    /// How far from `a` to `b`, signed: the shorter way round a ring.
    static func way(from a: Double, to b: Double, ringKm: Double?) -> Double {
        guard let ringKm, ringKm > 0 else { return b - a }
        let forward = ((b - a).truncatingRemainder(dividingBy: ringKm) + ringKm).truncatingRemainder(dividingBy: ringKm)
        let backward = ((a - b).truncatingRemainder(dividingBy: ringKm) + ringKm).truncatingRemainder(dividingBy: ringKm)
        return forward <= backward ? forward : -backward
    }

    /// A metro or light rail trip as the site runs it (`freqTrainPosRaw`):
    /// from each call it runs the segments' run time between the two
    /// stations (``RealOperationLine/runSeconds(from:to:)``), or the whole
    /// gap when that is shorter or unknown, then waits for the next call.
    /// `nil` for a call at a station the line does not have.
    public init?(trip: RealTimetableTrip, line: RealOperationLine, stationKm: [Double]) {
        var stops: [Stop] = []
        stops.reserveCapacity(trip.calls.count)
        for (index, call) in trip.calls.enumerated() {
            guard stationKm.indices.contains(call.stationIndex) else { return nil }
            if index == 0 {
                stops.append(Stop(km: stationKm[call.stationIndex], arrival: call.second, departure: call.second))
                continue
            }
            let previous = trip.calls[index - 1]
            let span = call.second - previous.second
            let run = line.runSeconds(from: previous.stationIndex, to: call.stationIndex)
            let moving = run.map { $0 < span ? $0 : span } ?? span
            stops.append(Stop(km: stationKm[call.stationIndex], arrival: previous.second + max(0, moving), departure: call.second))
        }
        self.init(stops: stops)
    }
}

/// A train the map draws (decision 304): where it is, in world units, and
/// the way it faces, as a unit vector.
public struct RealTrainDot: Hashable, Sendable, Identifiable {
    /// The system, the line and the run: unique among the trains drawn at
    /// one time.
    public let id: String
    public let x: Double
    public let y: Double
    public let headingX: Double
    public let headingY: Double
    /// The line's own colour.
    public let color: RealRailways.RGB
}

/// The real trains of the lines on one real-world map (decision 304): made
/// once for a map, asked where the trains are at each frame.
public struct RealTrainTraffic: Sendable {
    /// One real line on the map, and how its trains run.
    public struct Line: Sendable {
        /// The operations' system key (`trtc`, `thsr`, `tra`).
        public let system: String
        public let line: RealOperationLine
        public let color: RealRailways.RGB
        public let shape: RealLineShape
        /// How far along the shape each station is.
        public let stationKm: [Double]
        let ringKm: Double?
        let schedule: Schedule
    }

    /// Runs sorted by start, and the longest, to find quickly those running
    /// at a second.
    struct Runs: Sendable {
        let runs: [RealTrainRun]
        let longest: Int

        init(_ runs: [RealTrainRun]) {
            self.runs = runs.sorted { $0.start < $1.start }
            longest = runs.map { $0.end - $0.start }.max() ?? 0
        }

        /// The indices of the runs on the road at `second`.
        func running(at second: Double) -> [Int] {
            var lo = 0, hi = runs.count
            // The first run starting after `second`.
            while lo < hi {
                let mid = (lo + hi) / 2
                if Double(runs[mid].start) <= second { lo = mid + 1 } else { hi = mid }
            }
            var found: [Int] = []
            var index = lo - 1
            while index >= 0, Double(runs[index].start) >= second - Double(longest) {
                if Double(runs[index].end) >= second { found.append(index) }
                index -= 1
            }
            return found
        }
    }

    enum Schedule: Sendable {
        /// Each set's runs, by name (a metro timetable).
        case sets(RealLineTimetable, [String: Runs])
        /// The same runs every day (the High Speed Rail's day of trains).
        case daily(Runs)
        /// One train's round trip, repeated as the headway gives
        /// (`posPeriodic`).
        case headway(RealTrainRun, period: Int)
    }

    /// The lines that come onto the map.
    public let lines: [Line]

    /// The site's speed of each system's trains where a segment has no run
    /// time, in km/h (`SYS_DEFS` `speed`; 36 for any other, `state.speed`).
    /// Taiwan Railway's is the game's own (decision 304): the site has
    /// none, and 55 km/h with 25 seconds at each station takes a train from
    /// Keelung to Zhunan (125.6 km, 37 stations) in about 2 h 32 min, as a
    /// local train does.
    static let speedKmh: [String: Double] = [
        "trtc": 34, "tymc": 45, "ntdlrt": 25, "ntalrt": 25, "sanying": 34, "krtc": 36, "tmrt": 32, "tra": 55,
    ]
    /// The site's `DWELL_SEC`.
    static let dwellSeconds = 25
    /// When the trains of a line with only a headway run: 05:00 to
    /// midnight (decision 304).
    static let headwayHours = 5 * 3_600 ..< 24 * 3_600

    /// The lines of `operations` that come within `metres` of `frame`'s
    /// map, each with the trains its data has: a metro's timetable, the
    /// High Speed Rail's day of trains, or Taiwan Railway's headways.
    public init(operations: RealRailwayOperations, frame: RealWorldFrame, bounds: WorldBounds, bought: Set<String> = [], margin metres: Double = 2_000) {
        let half = RealWorldFrame.halfExtent(of: bounds)
        let corners = [(-1.0, -1.0), (1.0, 1.0)].map { sx, sy in
            frame.worldPosition(east: sx * (half.east + metres), south: sy * (half.south + metres))
        }.map { frame.coordinate(worldX: $0.x, worldY: $0.y) }
        let box = (
            minLatitude: min(corners[0].latitude, corners[1].latitude), maxLatitude: max(corners[0].latitude, corners[1].latitude),
            minLongitude: min(corners[0].longitude, corners[1].longitude), maxLongitude: max(corners[0].longitude, corners[1].longitude)
        )
        self.init(operations: operations, bought: bought) { coordinate in
            coordinate.latitude >= box.minLatitude && coordinate.latitude <= box.maxLatitude
                && coordinate.longitude >= box.minLongitude && coordinate.longitude <= box.maxLongitude
        }
    }

    /// The lines of `operations` with a point of their shape (or a station)
    /// for which `isNear` holds, but those in `bought` (`"tra:PINGXI"`):
    /// a real line the company bought runs the company's trains instead
    /// (decision 315).
    public init(operations: RealRailwayOperations, bought: Set<String> = [], isNear: (RealRailways.Coordinate) -> Bool) {
        var lines: [Line] = []
        for system in operations.orderedSystems {
            for line in system.lines where !bought.contains("\(system.id):\(line.id)") {
                let stationPoints = line.stations.map { RealRailways.Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
                guard line.shape.contains(where: isNear) || stationPoints.contains(where: isNear) else { continue }
                if let made = Self.line(line, of: system.id, in: operations) { lines.append(made) }
            }
        }
        self.lines = lines
    }

    static func line(_ line: RealOperationLine, of system: String, in operations: RealRailwayOperations) -> Line? {
        // The shape, and each station's place on it; without a shape (or a
        // station's `d`), straight from station to station.
        let stationPoints = line.stations.map { RealRailways.Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        let shape: RealLineShape
        let stationKm: [Double]
        if let drawn = RealLineShape(line.shape), line.stations.allSatisfy({ $0.distanceKm != nil }) {
            shape = drawn
            stationKm = line.stations.map { min(max($0.distanceKm ?? 0, 0), drawn.lengthKm) }
        } else if let straight = RealLineShape(stationPoints) {
            shape = straight
            stationKm = straight.cumulativeKm
        } else {
            return nil
        }
        let ringKm = line.isLoop ? shape.lengthKm : nil
        let color = line.color.flatMap(RealRailways.RGB.init(hex:))
            ?? RealRailwayOperations.siteSystems[system].flatMap { id in RealRailways.System.all.first { $0.id == id }?.operatorColor }
            ?? RealRailways.RGB(red: 128, green: 128, blue: 128)

        let schedule: Schedule
        if let timetable = operations.timetable(forSystem: system)?.lines[line.id] {
            var sets: [String: Runs] = [:]
            for (name, trips) in timetable.sets {
                sets[name] = Runs(trips.compactMap { RealTrainRun(trip: $0, line: line, stationKm: stationKm) })
            }
            schedule = .sets(timetable, sets)
        } else if let day = operations.schedule(forSystem: system), operations.lines(inSystem: system).count == 1 {
            // The High Speed Rail: each stop by its station's name.
            var kmByName: [String: Double] = [:]
            for (station, km) in zip(line.stations, stationKm) where kmByName[station.name] == nil { kmByName[station.name] = km }
            schedule = .daily(Runs(day.trains.compactMap { train in
                RealTrainRun(stops: train.stops.compactMap { stop in
                    kmByName[stop.name].map { RealTrainRun.Stop(km: $0, arrival: stop.arrivalSecond, departure: stop.departureSecond) }
                })
            }))
        } else if let round = headwayRun(line, of: system, stationKm: stationKm, ringKm: ringKm),
                  line.peakHeadwaySec ?? line.offpeakHeadwaySec != nil {
            schedule = .headway(round, period: round.end)
        } else {
            return nil
        }
        return Line(system: system, line: line, color: color, shape: shape, stationKm: stationKm, ringKm: ringKm, schedule: schedule)
    }

    /// The site's `buildLineSchedule`: one train there and back (or once
    /// round a ring), from second 0.
    static func headwayRun(_ line: RealOperationLine, of system: String, stationKm: [Double], ringKm: Double?) -> RealTrainRun? {
        let n = line.stations.count
        guard n >= 2 else { return nil }
        let forward = Array(0..<n)
        let order = ringKm != nil ? forward + [0] : forward + forward.dropLast().reversed()
        let speed = speedKmh[system] ?? 36
        var stops: [RealTrainRun.Stop] = []
        var t = 0
        for (step, station) in order.enumerated() {
            var km = stationKm[station]
            if step == order.count - 1, let ringKm { km = ringKm }
            if step > 0 {
                let previous = order[step - 1]
                // The segment between the two (`segIdx`).
                let segment = ringKm != nil ? step - 1 : (step <= n - 1 ? step - 1 : 2 * (n - 1) - step)
                if let runs = line.segmentRunSec, runs.indices.contains(segment), let run = runs[segment], run > 0 {
                    t += run
                } else {
                    t += Int((abs(km - (stops.last?.km ?? stationKm[previous])) / speed * 3_600).rounded())
                }
            }
            let dwell = line.stations[station].dwellSec ?? dwellSeconds
            stops.append(RealTrainRun.Stop(km: km, arrival: t, departure: t + dwell))
            t += dwell
        }
        return RealTrainRun(stops: stops)
    }

    /// Where `line`'s trains are at second `second` of game day `day` (a
    /// fraction for the frames between two ticks): how far along the line
    /// each is and the place it heads for, by a key unique on the line.
    /// A trip after midnight runs on the day before's set; a headway line's
    /// trains run from 05:00 to midnight, as many as the hour's headway
    /// gives (`ln.n`).
    public func places(of line: Line, at second: Double, on day: RealServiceDay, dayBefore: RealServiceDay) -> [(key: String, km: Double, towardKm: Double)] {
        var found: [(key: String, km: Double, towardKm: Double)] = []
        func add(_ runs: Runs, at time: Double, prefix: String) {
            for index in runs.running(at: time) {
                if let place = runs.runs[index].place(at: time, ringKm: line.ringKm) {
                    found.append(("\(prefix)\(index)", place.km, place.towardKm))
                }
            }
        }
        switch line.schedule {
        case .sets(let timetable, let sets):
            if let name = timetable.setName(for: day), let runs = sets[name] { add(runs, at: second, prefix: "\(name)#") }
            if let name = timetable.setName(for: dayBefore), let runs = sets[name] { add(runs, at: second + 86_400, prefix: "-\(name)#") }
        case .daily(let runs):
            add(runs, at: second, prefix: "")
            add(runs, at: second + 86_400, prefix: "-")
        case .headway(let round, let period):
            guard Self.headwayHours.contains(Int(second)), period > 0,
                  let headway = RealTimetables.isPeak(second: Int(second)) ? line.line.peakHeadwaySec ?? line.line.offpeakHeadwaySec
                    : line.line.offpeakHeadwaySec ?? line.line.peakHeadwaySec,
                  headway > 0 else { break }
            let count = max(1, Int((Double(period) / Double(headway)).rounded()))
            for k in 0..<count {
                let time = (second + Double(k) * Double(period) / Double(count)).truncatingRemainder(dividingBy: Double(period))
                if let place = round.place(at: time, ringKm: line.ringKm) { found.append(("h\(k)", place.km, place.towardKm)) }
            }
        }
        return found
    }

    /// The trains to draw at second `second` of game day `day` on `frame`'s
    /// map, those in `visible` (world units) only, in the lines' order.
    public func trains(at second: Double, on day: RealServiceDay, dayBefore: RealServiceDay, frame: RealWorldFrame, visible: WorldRegion) -> [RealTrainDot] {
        var dots: [RealTrainDot] = []
        for line in lines {
            for place in places(of: line, at: second, on: day, dayBefore: dayBefore) {
                let here = line.shape.coordinate(atKm: place.km)
                let point = frame.worldPosition(latitude: here.latitude, longitude: here.longitude)
                guard point.x >= visible.minX, point.x <= visible.maxX, point.y >= visible.minY, point.y <= visible.maxY else { continue }
                // Which way: a little way along towards where it heads.
                let step = RealTrainRun.way(from: place.km, to: place.towardKm, ringKm: line.ringKm)
                var aheadKm = place.km + (step >= 0 ? 0.05 : -0.05)
                if let ring = line.ringKm { aheadKm = (aheadKm + ring).truncatingRemainder(dividingBy: ring) }
                let ahead = line.shape.coordinate(atKm: aheadKm)
                let aheadPoint = frame.worldPosition(latitude: ahead.latitude, longitude: ahead.longitude)
                var dx = aheadPoint.x - point.x, dy = aheadPoint.y - point.y
                // Held at the shape's end: face back from just behind.
                if (aheadKm <= 0 || aheadKm >= line.shape.lengthKm) && line.ringKm == nil {
                    let behind = line.shape.coordinate(atKm: place.km - (step >= 0 ? 0.05 : -0.05))
                    let behindPoint = frame.worldPosition(latitude: behind.latitude, longitude: behind.longitude)
                    dx = point.x - behindPoint.x
                    dy = point.y - behindPoint.y
                }
                let length = (dx * dx + dy * dy).squareRoot()
                dots.append(RealTrainDot(
                    id: "\(line.system)|\(line.line.id)|\(place.key)",
                    x: point.x, y: point.y,
                    headingX: length > 0 ? dx / length : 1, headingY: length > 0 ? dy / length : 0,
                    color: line.color
                ))
            }
        }
        return dots
    }
}

/// A real line's next train from a station (decision 304): where it goes
/// and when it leaves, in seconds of the game day (past 86,400 for a train
/// after midnight).
public struct RealNextTrain: Hashable, Sendable {
    /// The operations' system key and the line's ID.
    public let system: String
    public let line: String
    /// The line's name as the data has it, without the stretch in brackets
    /// (`縱貫線北段`, not `縱貫線北段（基隆–竹南）`).
    public let lineName: String
    /// The station the train ends at, in Chinese.
    public let destination: String
    public let second: Int
}

/// What a real line runs at a station (decision 304): its next train each
/// way, or, for a line with only headways, how often.
public enum RealStationService: Hashable, Sendable {
    case next([RealNextTrain])
    case headway(system: String, line: String, lineName: String, seconds: Int)
}

extension RealRailwayOperations {
    /// What each real line through a station of site system `siteSystem`
    /// (``RealRailways/System/id``) named `name` runs after second `second`
    /// of game day `day`: the next train each way of a metro's timetable
    /// (the day before's set for the trips after midnight) or the High
    /// Speed Rail's day of trains, those that leave from the station, not
    /// end there; or a headway line's headway at that hour, while its
    /// trains run (``RealTrainTraffic/headwayHours``). Lines in the site's
    /// order, each way by the time it leaves.
    public func service(atStationNamed name: String, siteSystem: String, after second: Int, on day: RealServiceDay, dayBefore: RealServiceDay) -> [RealStationService] {
        let key = RealRailways.stationKey(name)
        var found: [RealStationService] = []
        for system in orderedSystems where Self.siteSystems[system.id] == siteSystem {
            for line in system.lines {
                guard let index = line.stations.firstIndex(where: { RealRailways.stationKey($0.name) == key }) else { continue }
                let lineName = Self.shortName(line.name)
                var best: [String: Int] = [:]
                func consider(_ destination: String, _ time: Int) {
                    guard time >= second, destination != line.stations[index].name else { return }
                    if best[destination].map({ time < $0 }) ?? true { best[destination] = time }
                }
                if let timetable = timetable(forSystem: system.id)?.lines[line.id] {
                    for (set, offset) in [(timetable.setName(for: day), 0), (timetable.setName(for: dayBefore), -86_400)] {
                        guard let set, let trips = timetable.sets[set] else { continue }
                        for trip in trips {
                            guard let last = trip.calls.last, line.stations.indices.contains(last.stationIndex) else { continue }
                            for call in trip.calls.dropLast() where call.stationIndex == index {
                                consider(line.stations[last.stationIndex].name, call.second + offset)
                            }
                        }
                    }
                } else if let schedule = schedule(forSystem: system.id), system.lines.count == 1 {
                    let station = line.stations[index].name
                    for train in schedule.trains {
                        guard let last = train.stops.last else { continue }
                        for stop in train.stops.dropLast() where stop.stops && stop.name == station {
                            consider(last.name, stop.departureSecond)
                            consider(last.name, stop.departureSecond - 86_400)
                        }
                    }
                } else if RealTrainTraffic.headwayHours.contains(second),
                          let headway = RealTimetables.isPeak(second: second) ? line.peakHeadwaySec ?? line.offpeakHeadwaySec
                            : line.offpeakHeadwaySec ?? line.peakHeadwaySec, headway > 0 {
                    found.append(.headway(system: system.id, line: line.id, lineName: lineName, seconds: headway))
                    continue
                }
                let trains = best.map { RealNextTrain(system: system.id, line: line.id, lineName: lineName, destination: $0.key, second: $0.value) }
                    .sorted { ($0.second, $0.destination) < ($1.second, $1.destination) }
                if !trains.isEmpty { found.append(.next(trains)) }
            }
        }
        return found
    }

    /// A line's name without the stretch in brackets.
    static func shortName(_ name: String) -> String {
        guard let cut = name.firstIndex(where: { $0 == "（" || $0 == "(" }) else { return name }
        let short = name[..<cut].trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? name : short
    }
}

extension GameSession {
    /// The most real lines the station card lists the next trains of.
    static let realServiceLinesShown = 4

    /// Decision 304: the next trains of the real lines at the real station
    /// that station `id` is (its name within 450 m, as the rest of the card
    /// reads it, ``realStations(named:at:)``), or else the real place it
    /// changes with (``transferPlace(of:)``), one line of text each:
    /// "板南線 下一班：往頂埔 08:12、往南港展覽館 08:15", or
    /// "縱貫線北段：約每 10 分一班" for a line with only headways. Empty on
    /// a blank map or for a station that is no real one.
    public func realServiceText(of id: StationID) -> [String] {
        guard let railways, let operations = railways.operations, let station = world.station(id: id), !station.isDepot,
              RealWorldFrame(world: world) != nil else { return [] }
        var stations = realStations(named: station.name, at: station.location)
        if stations.isEmpty, let place = transferPlace(of: id) { stations = place.stations }
        guard !stations.isEmpty else { return [] }
        let now = world.clock.now
        let today = GameDate.floorDivide(now.seconds, GameTime.secondsPerDay)
        let second = Int(now.seconds - today * GameTime.secondsPerDay)
        let day = RealServiceDay(world: world, day: today), dayBefore = RealServiceDay(world: world, day: today - 1)
        var lines: [String] = []
        var seen: Set<String> = []
        for real in stations {
            for service in operations.service(atStationNamed: real.chinese, siteSystem: real.system.id, after: second, on: day, dayBefore: dayBefore) {
                switch service {
                case .next(let trains):
                    guard let first = trains.first, seen.insert("\(first.system)|\(first.line)").inserted else { continue }
                    let ways = trains.prefix(2).map { train in
                        let to = destinationName(train.destination, siteSystem: real.system.id)
                        return language.text("to \(to) \(Self.realClockText(train.second))", "往\(to) \(Self.realClockText(train.second))")
                    }.joined(separator: language.text(", ", "、"))
                    lines.append(language.text("\(first.lineName) next: \(ways)", "\(first.lineName) 下一班：\(ways)"))
                case .headway(let system, let line, let name, let seconds):
                    guard seen.insert("\(system)|\(line)").inserted else { continue }
                    let minutes = max(1, (seconds + 30) / 60)
                    lines.append(language.text("\(name): about every \(minutes) min", "\(name)：約每 \(minutes) 分一班"))
                }
            }
        }
        return Array(lines.prefix(Self.realServiceLinesShown))
    }

    /// A real station's name in the display language, by its Chinese name
    /// in site system `siteSystem`.
    func destinationName(_ chinese: String, siteSystem: String) -> String {
        let key = RealRailways.stationKey(chinese)
        return railways?.stations.first { $0.system.id == siteSystem && RealRailways.stationKey($0.chinese) == key }?.name(in: language) ?? chinese
    }

    /// "08:12" for a second of the day (past 86,400 the next day's).
    static func realClockText(_ second: Int) -> String {
        let s = ((second % 86_400) + 86_400) % 86_400
        let hours = s / 3_600, minutes = s % 3_600 / 60
        return (hours < 10 ? "0\(hours)" : "\(hours)") + ":" + (minutes < 10 ? "0\(minutes)" : "\(minutes)")
    }
}

/// The game clock the real trains are drawn at (decision 304): the second
/// of the game day, gliding from the last tick's to this tick's frame by
/// frame as the player's trains do (``TrainMotion``), one tick behind,
/// never ahead. A glide never reaches back past midnight: the first tick of
/// a day starts at its 00:00.
public struct RealTrainClock: Hashable, Sendable {
    /// The game day, and the timetable sets it and the day before run.
    public let day: Int64
    public let today: RealServiceDay
    public let dayBefore: RealServiceDay
    /// The seconds of `day` the glide goes from and to.
    let from: Double
    let to: Double
    /// When the tick was seen and how long the glide lasts, in seconds of
    /// the caller's clock.
    let time: Double
    let duration: Double

    /// The clock of `world` at `time` (seconds on the caller's clock),
    /// gliding from `previous` when it saw the same day or the one before.
    public init(world: GameWorld, previous: RealTrainClock? = nil, time: Double) {
        let now = world.clock.now
        let day = GameDate.floorDivide(now.seconds, GameTime.secondsPerDay)
        let second = Double(now.seconds - day * GameTime.secondsPerDay)
        self.day = day
        if let previous, previous.day == day {
            today = previous.today
            dayBefore = previous.dayBefore
        } else {
            today = RealServiceDay(world: world, day: day)
            dayBefore = RealServiceDay(world: world, day: day - 1)
        }
        to = second
        if let previous, previous.day == day || previous.day == day - 1 {
            let last = previous.day == day ? previous.to : 0
            from = min(last, second)
            duration = min(max(time - previous.time, 0.05), 0.5)
        } else {
            from = second
            duration = TrainMotion.tickSeconds
        }
        self.time = time
    }

    /// The second of ``day`` to draw at `time`; this tick's when `glides`
    /// is false (paused, or the player reduces motion).
    public func second(at time: Double, glides: Bool = true) -> Double {
        guard glides, duration > 0 else { return to }
        let share = min(max((time - self.time) / duration, 0), 1)
        return from + (to - from) * share
    }

    /// Whether the clock moved at this tick.
    public var isMoving: Bool { to > from }
}

extension RealTrainTraffic {
    /// How a real train looks beside the player's (decision 304): a short
    /// capsule its line's colour, fainter and smaller than a player's
    /// train, so the player's own stay the ones that stand out.
    public struct Look: Hashable, Sendable {
        /// Its half-width, as a share of a player's train's head radius.
        public let sizeShare: Double
        /// Its straight middle's half-length, as a share of its half-width.
        public let lengthShare: Double
        /// How much of its line's colour shows.
        public let opacity: Double
        /// Its edge in the map's ink: how much shows, and how wide, in
        /// points.
        public let edgeOpacity: Double
        public let edgeWidth: Double
    }

    public static let look = Look(sizeShare: 0.6, lengthShare: 0.8, opacity: 0.6, edgeOpacity: 0.35, edgeWidth: 0.75)

    /// The most trains drawn at once (decision 304): a guard above the most
    /// the bundled data puts on one map (157, Taipei's whole map at
    /// 08:00), so a later, denser timetable cannot slow the map.
    public static let mostDrawn = 200

    /// The real trains show from this zoom on (points per 16 m of the
    /// world, ``MapProjection/referenceSize``): zoomed out further, a
    /// whole city's trains are dots too small to follow (decision 304):
    /// about 10 km across a phone held upright.
    public static let shownFromReferenceSize = 0.6

    /// Whether the real trains show at a map zoom of `referenceSize`.
    public static func isShown(referenceSize: Double) -> Bool {
        referenceSize >= shownFromReferenceSize
    }
}
