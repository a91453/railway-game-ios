// Passengers who wait too long leave (ARCHITECTURE decision 731, the
// owner's earlier desktop game's `PassengerDemand.expire`: a group still
// queued `maxWaitSeconds` after it came leaves and is counted as
// abandoned). Only the rule is the earlier game's; the patience is this
// project's.
//
// With ``GameWorld/passengerPatience`` on, at each whole minute, after the
// 04:00 send-home and before the minute's passengers are released, every
// group still waiting ``PassengerPatience/minutes(longTrip:)`` after it
// could first board (``WaitingGroup/since``, or its ``WaitingGroup/readyAt``
// at a station where it changes trains) leaves, counted at its original
// station as ``PassengerLedger/gaveUp``. Those on a train are not touched.
// It is decided at whole minutes only, as the passengers are released, so a
// long advance and the same time minute by minute leave the same groups.

/// How long passengers wait for a train before they give up (decision
/// 731).
public enum PassengerPatience {
    /// How long one on an ordinary trip waits: 40 minutes.
    public static let ordinaryMinutes: Int64 = 40
    /// How long one on a long trip waits: 90 minutes. Someone going far
    /// has fewer other ways to get there.
    public static let longMinutes: Int64 = 90
    /// From this straight-line distance between where a trip starts and
    /// ends (20 km) it is a long trip.
    public static let longDistance: Int64 = 20_000 * WorldCoordinate.unitsPerMetre

    /// How many minutes a passenger waits, on a long trip or not.
    public static func minutes(longTrip: Bool) -> Int64 {
        longTrip ? longMinutes : ordinaryMinutes
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns on or off whether passengers who wait too long leave
    /// (decision 731). Passengers already waiting stay; turned on, those
    /// who have waited longer than their patience leave at the next whole
    /// minute.
    public mutating func setPassengerPatience(_ enabled: Bool) {
        passengerPatience = enabled
    }

    // MARK: - Queries

    /// Whether the trip `group` waiting at `station` is on is a long one
    /// (decision 731): it goes beyond the map (between an outside
    /// connection and a station that is not one), rides a high-speed line,
    /// or starts and ends at least ``PassengerPatience/longDistance`` apart
    /// in a straight line.
    func isLongTrip(_ group: WaitingGroup, at station: StationID) -> Bool {
        let origin = group.journey?.origin ?? station
        let destination = group.journey?.destination ?? group.destination
        if isOutsideConnection(origin) != isOutsideConnection(destination) { return true }
        let lines = group.journey.map { $0.legs.map(\.line) } ?? [group.line]
        if lines.contains(where: { line(id: $0)?.isHighSpeed == true }) { return true }
        guard let squared = squaredDistance(from: origin, to: destination) else { return false }
        let far = PassengerPatience.longDistance
        return squared >= far * far
    }

    // MARK: - Stepping

    /// Decision 731: at a whole minute `now`, with
    /// ``passengerPatience`` on, every group still waiting its patience
    /// after it could first board leaves, counted at its original station
    /// as ``PassengerLedger/gaveUp``.
    mutating func sendImpatientPassengersAway(at now: GameTime) {
        guard passengerPatience else { return }
        let shortest = PassengerPatience.ordinaryMinutes * GameTime.secondsPerMinute
        var gaveUp: [StationID: Int64] = [:]
        for index in passengers.indices {
            // The queue is in the order of `since`, and nobody can board
            // before it: a station whose first group came within the
            // shortest patience has nobody to send away.
            guard let first = passengers[index].waiting.first, now.seconds - first.since.seconds >= shortest else { continue }
            let station = passengers[index].station
            let leaving = Set(passengers[index].waiting.filter { group in
                let since = max(group.since, group.readyAt ?? group.since)
                let patience = PassengerPatience.minutes(longTrip: isLongTrip(group, at: station)) * GameTime.secondsPerMinute
                return now.seconds - since.seconds >= patience
            })
            guard !leaving.isEmpty else { continue }
            let left = passengers[index].abandonGroups { !leaving.contains($0) }
            for group in left {
                gaveUp[group.journey?.origin ?? station, default: 0] += group.count
            }
        }
        guard !gaveUp.isEmpty else { return }
        for origin in gaveUp.keys.sorted() {
            if let record = passengers.firstIndex(where: { $0.station == origin }) {
                passengers[record].gaveUp += gaveUp[origin]!
            }
        }
        passengers.removeAll { $0.isEmpty }
    }
}
