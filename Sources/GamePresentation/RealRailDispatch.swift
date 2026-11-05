import Foundation

// Decision 600: the track each real train runs on, from one station to the
// next, as the owner's site assigns it (`Railway/taiwan-rail-reference-
// clean/source/rail-3d/physical/dispatch.json`, bound to a train by
// `plan-binding.js`, run by `motion.js`): the station track it stops at, the
// side of a double line, the crossovers between. An estimate of the site's,
// not the railway's own working. `tools/real-railways/extract_tracks.py`
// writes it (`rail_dispatch.json`) as stretches of `rail_tracks.json`'s
// tracks.

/// Decision 600: the real trains' track assignment.
public struct RealRailDispatch: Sendable, Equatable {
    /// A stretch of a track a path runs along: from point `from` of track
    /// `track` (of ``RealRailTracks/tracks``) to point `to`, either way.
    struct Run: Sendable, Equatable {
        let track: Int
        let from: Int
        let to: Int
    }

    /// One train's assignment.
    struct Plan: Sendable, Equatable {
        /// Its system, as ``RealRailTracks/Track/system`` names it.
        let system: String
        let number: String
        /// Its first departure and last arrival, seconds of the day.
        let first: Int
        let last: Int
        /// Its stations (of ``RealRailDispatch/stations``), whether it
        /// calls at each, and the path (of ``RealRailDispatch/paths``)
        /// between each two.
        let stations: [Int]
        let calls: [Bool]
        let paths: [Int]
        /// Whether another train may borrow its paths (`templateEligible`).
        let lends: Bool
    }

    /// The stations' names (``key(_:)``).
    let stations: [String]
    /// Each path, the stretches it runs along in order.
    let paths: [[Run]]
    let plans: [Plan]
    /// The plans of each system by number, and the stations each system's
    /// plans have.
    private let byNumber: [String: [String: [Int]]]
    private let known: [String: Set<Int>]
    private let stationIndex: [String: Int]

    /// Reads `rail_dispatch.json` against `tracks` (its ways). Throws for
    /// one out of shape: a plan's paths not one between each two stations,
    /// a station or path it does not list, or a way `tracks` has not.
    public init(data: Data, tracks: RealRailTracks) throws {
        struct File: Decodable {
            struct RawPlan: Decodable {
                let s: Int
                let n: String
                let k: [Int]
                let t: [Int]
                let q: [Int]
                let p: [Int]
                let x: Int?
            }

            let systems: [String]
            let stations: [String]
            let paths: [[StringOrInt]]
            let plans: [RawPlan]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        func corrupt(_ what: String) -> DecodingError { DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: what)) }
        var byWay: [String: Int] = [:]
        for (index, track) in tracks.tracks.enumerated() {
            if let way = track.way { byWay[way] = index }
        }
        paths = try file.paths.map { raw in
            guard raw.count.isMultiple(of: 3), !raw.isEmpty else { throw corrupt("A path's stretches are not in threes") }
            return try stride(from: 0, to: raw.count, by: 3).map { at in
                guard case .string(let way) = raw[at], case .int(let from) = raw[at + 1], case .int(let to) = raw[at + 2],
                      let track = byWay[way], tracks.tracks[track].points.indices.contains(from), tracks.tracks[track].points.indices.contains(to)
                else { throw corrupt("A path runs on a track the tracks have not") }
                return Run(track: track, from: from, to: to)
            }
        }
        stations = file.stations
        plans = try file.plans.map { raw in
            guard file.systems.indices.contains(raw.s), raw.k.count == 2, raw.t.count >= 2, raw.q.count == raw.t.count,
                  raw.p.count == raw.t.count - 1, raw.t.allSatisfy(file.stations.indices.contains),
                  raw.p.allSatisfy(file.paths.indices.contains)
            else { throw corrupt("Plan \(raw.n) is out of shape") }
            return Plan(system: file.systems[raw.s], number: raw.n, first: raw.k[0], last: raw.k[1], stations: raw.t,
                        calls: raw.q.map { $0 != 0 }, paths: raw.p, lends: raw.x != 1)
        }
        var byNumber: [String: [String: [Int]]] = [:], known: [String: Set<Int>] = [:]
        for (index, plan) in plans.enumerated() {
            byNumber[plan.system, default: [:]][plan.number, default: []].append(index)
            known[plan.system, default: []].formUnion(plan.stations)
        }
        self.byNumber = byNumber
        self.known = known
        stationIndex = Dictionary(file.stations.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A number or a string, as a path's stretches mix them.
    enum StringOrInt: Decodable {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let int = try? container.decode(Int.self) { self = .int(int) } else { self = .string(try container.decode(String.self)) }
        }
    }

    /// The site's `stationKey` (`timing.js`): `臺` as `台`, without what
    /// is in brackets or a trailing `-環島`.
    static func key(_ name: String) -> String {
        var name = name.replacingOccurrences(of: "臺", with: "台")
        while let open = name.firstIndex(where: { $0 == "(" || $0 == "（" }),
              let close = name[open...].firstIndex(where: { $0 == ")" || $0 == "）" }) {
            var start = open
            while start > name.startIndex, name[name.index(before: start)].isWhitespace { start = name.index(before: start) }
            name.removeSubrange(start...close)
        }
        if name.hasSuffix("-環島") { name.removeLast(3) }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// A leg of a bound train: from station `from` to station `to` (their
    /// names, ``key(_:)``), on path `path`.
    struct Leg: Sendable, Equatable {
        let from: String
        let to: String
        let path: Int
    }

    /// The legs of the train of `system` numbered `number`, calling at or
    /// passing `stops` in order (each its name, whether it calls there),
    /// leaving its first at `first` and reaching its last at `last`
    /// (seconds of the day), as the site's `plan-binding.js` binds it:
    /// stations no plan of its system has (a station opened since, 平鎮)
    /// left out; its own plan, of its number and the same stations (the
    /// one nearest its times, as `byTrain`); else the stretch of another
    /// train's plan over the same stations in a row that may be lent, the
    /// fewest stations it calls at or passes otherwise, then the shortest
    /// plan, then the first. `nil` for neither.
    func legs(system: String, number: String, stops: [(name: String, calls: Bool)], first: Int, last: Int) -> [Leg]? {
        guard let known = known[system] else { return nil }
        var names: [Int] = [], calls: [Bool] = []
        for stop in stops {
            guard let index = stationIndex[Self.key(stop.name)], known.contains(index) else { continue }
            names.append(index)
            calls.append(stop.calls)
        }
        guard names.count >= 2 else { return nil }
        func legs(_ plan: Plan, from start: Int) -> [Leg] {
            (0..<names.count - 1).map { Leg(from: stations[names[$0]], to: stations[names[$0 + 1]], path: plan.paths[start + $0]) }
        }
        let own = (byNumber[system]?[number] ?? []).map { plans[$0] }.filter { $0.stations == names }
        if let plan = own.min(by: { abs($0.first - first) + abs($0.last - last) < abs($1.first - first) + abs($1.last - last) }) {
            return legs(plan, from: 0)
        }
        var best: (plan: Plan, start: Int, score: Int)?
        for plan in plans where plan.system == system && plan.lends && plan.stations.count >= names.count {
            for start in 0...(plan.stations.count - names.count) where Array(plan.stations[start..<start + names.count]) == names {
                let mismatched = (1..<max(1, names.count - 1)).filter { calls[$0] != plan.calls[start + $0] }.count
                let score = mismatched * 10_000 + plan.stations.count - names.count
                if best.map({ score < $0.score }) ?? true { best = (plan, start, score) }
            }
        }
        return best.map { legs($0.plan, from: $0.start) }
    }
}
