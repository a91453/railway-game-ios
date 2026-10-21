// How a line spaces its trains out (ARCHITECTURE decision 309; TestFlight
// 77.1 #1). A line sent its trains out one headway apart from its first
// stop, and a train standing at its last stop (decision 172) took the same
// slot, so two trains could neither leave the two ends together nor run a
// few minutes apart. The pattern is the line's own service's; its other
// services and a ring's two ways keep their even headway.

/// How a line's own service spaces its trains out (decision 309).
public enum DispatchPattern: Hashable, Sendable {
    /// One headway apart, from whichever end a train stands at: every line
    /// before decision 309.
    case even
    /// Each end of the line sends its own trains out on its own clock, so
    /// trains leave both ends at once. About half the trains are kept at
    /// the last stop: one standing at the first stop that the first stop
    /// does not need runs there empty. Needs flexible dispatch (decision
    /// 172), as only that sends a train out from the last stop; without it
    /// the line runs even.
    case fromBothEnds
    /// Trains go out in pairs: the second `minutes` after the first, the
    /// next pair two headways after the first of this one.
    case staggered(minutes: Int64)

    /// The minutes the second train of a pair may follow the first.
    public static let staggerRange: ClosedRange<Int64> = ServiceLine.minimumHeadwayMinutes...30

    /// Whether a line can have the pattern: a stagger within
    /// ``staggerRange``.
    public var isValid: Bool {
        staggerMinutes.map(Self.staggerRange.contains) ?? true
    }

    /// The minutes of a staggered pattern, else `nil`.
    public var staggerMinutes: Int64? {
        if case .staggered(let minutes) = self { minutes } else { nil }
    }
}

extension DispatchPattern: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, minutes
    }

    /// Decodes `{"kind": "even"}`, `{"kind": "fromBothEnds"}` or
    /// `{"kind": "staggered", "minutes": n}`; whether the minutes are ones a
    /// line can have is the line's to check (``isValid``).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "even": self = .even
        case "fromBothEnds": self = .fromBothEnds
        case "staggered": self = .staggered(minutes: try container.decode(Int64.self, forKey: .minutes))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown dispatch pattern.")
        }
        guard staggerMinutes != nil || !container.contains(.minutes) else {
            throw DecodingError.dataCorruptedError(forKey: .minutes, in: container, debugDescription: "Only a staggered pattern has minutes.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .even: try container.encode("even", forKey: .kind)
        case .fromBothEnds: try container.encode("fromBothEnds", forKey: .kind)
        case .staggered(let minutes):
            try container.encode("staggered", forKey: .kind)
            try container.encode(minutes, forKey: .minutes)
        }
    }
}

/// Which end of its service a train is sent out from (decision 172).
enum DispatchEnd: Hashable, Sendable {
    case first, last
}

extension GameWorld {
    /// The pattern `line`'s `stream` keeps when it runs `planned`: the
    /// line's own on its own service while it runs two trains or more
    /// (from both ends only with flexible dispatch), else even.
    func dispatchPattern(of line: ServiceLine, _ stream: DispatchStream, planned: (trains: Int, headway: Int64)) -> DispatchPattern {
        guard stream.service == 0, stream.direction == nil, line.dispatchPattern != .even,
              min(planned.trains, line.trains.count) >= 2
        else { return .even }
        if line.dispatchPattern == .fromBothEnds, !flexDispatch { return .even }
        return line.dispatchPattern
    }

    /// Whether `line`'s `stream` keeps a clock at each end (see
    /// ``DispatchPattern/fromBothEnds``) at `now`.
    func keepsEndClocks(_ line: ServiceLine, _ stream: DispatchStream, at now: GameTime, memo: inout DispatchMemo) -> Bool {
        guard stream.service == 0, stream.direction == nil, line.dispatchPattern == .fromBothEnds,
              let planned = plannedService(of: line, stream.service, at: now, memo: &memo)
        else { return false }
        return dispatchPattern(of: line, stream, planned: planned) == .fromBothEnds
    }

    /// The earliest time `line`'s `stream`, running `planned`, sends its
    /// next train out from `end`, or `nil` when no dispatch holds it back.
    ///
    /// Even: a headway after the stream's last dispatch, from either end.
    /// From both ends: each end's own last dispatch, and its share of the
    /// trains (the last end half, down) spread over the trains' cycle, so
    /// each end's trains keep evenly apart. Staggered: the stagger after the
    /// first of a pair, the rest of two headways after the second.
    func nextDispatch(of line: ServiceLine, _ stream: DispatchStream, from end: DispatchEnd, planned: (trains: Int, headway: Int64)) -> GameTime? {
        switch dispatchPattern(of: line, stream, planned: planned) {
        case .even:
            return line.lastDispatch(of: stream).flatMap { Self.time($0, plusMinutes: planned.headway) }
        case .fromBothEnds:
            let trains = Int64(min(planned.trains, line.trains.count))
            let share = end == .last ? trains / 2 : trains - trains / 2
            let last = end == .last ? line.endLastDispatch : line.lastDispatch
            return last.flatMap { Self.time($0, plusMinutes: planned.headway * trains / share) }
        case .staggered(let minutes):
            let (short, long) = Self.staggerGaps(minutes, headway: planned.headway)
            return line.lastDispatch.flatMap { Self.time($0, plusMinutes: line.opensPair ? short : long) }
        }
    }

    /// The two gaps of a staggered pattern (decision 309) at `headway`: the
    /// stagger, at least the least headway and at most the headway (a
    /// stagger past it is the same pairs seen from the other train), and
    /// the rest of two headways.
    static func staggerGaps(_ minutes: Int64, headway: Int64) -> (short: Int64, long: Int64) {
        let cycle = 2 * headway
        let short = max(ServiceLine.minimumHeadwayMinutes, min(minutes, cycle - minutes, headway))
        return (short, max(short, cycle - short))
    }

    /// Under ``DispatchPattern/fromBothEnds``, the train of `line`'s
    /// `stream` to run empty to the last stop now, with its run, or `nil`:
    /// while fewer of the stream's trains than the last stop's share stand
    /// there or end their trip there, the first in ID order ready at the
    /// first stop, while the stream has room for one more train. Under
    /// traffic control it must take its route now.
    func trainToFarEnd(of line: ServiceLine, _ stream: DispatchStream, at now: GameTime, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        guard keepsEndClocks(line, stream, at: now, memo: &memo),
              let planned = plannedService(of: line, stream.service, at: now, memo: &memo),
              isDispatchDue(line, stream, at: now, deadhead: true, memo: &memo)
        else { return nil }
        let calls = line.calls(ofService: stream.service)
        let first = line.stops[calls[0]], last = line.stops[calls[calls.count - 1]]
        let ids = line.trains(of: stream)
        let atFarEnd = ids.count { id in
            guard let train = train(id: id) else { return false }
            return train.execution == nil ? isStopped(train, at: last) : train.timetable.last?.station == last
        }
        guard atFarEnd < min(planned.trains, ids.count) / 2 else { return nil }
        for id in ids {
            guard let index = trains.firstIndex(where: { $0.id == id }),
                  let ready = readyTrip(of: trains[index], on: line, stream.service, memo: &memo), ready.deadhead == nil,
                  !ready.fromLastCall, isStopped(trains[index], at: first),
                  let trip = emptyRun(of: line, for: trains[index], to: [last])
            else { continue }
            if isTrafficControlEnabled, let leaving = firstDeparture(of: trains[index], on: trip, calling: line.stops),
               case .held = reservingDeparture(leaving, memo: &memo.directions) {
                continue
            }
            return (index, trip)
        }
        return nil
    }
}
