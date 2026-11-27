import GameCore

// TestFlight, 2026-11-27 (a player on an iPhone 17): "with many stops the
// line is not drawn, and its trains do not run to the stops added." A
// station tapped while picking a new line's stops was always put after the
// last one picked. The draft's own hint says to tap the first station, the
// last, and then a station between to choose the way, and the card that
// leads from Build to a new line (decision 1024) opens the draft with both
// ends already picked; so a station tapped next, one the line passes, made
// the line run to its end, back to that station and on again. A line can
// turn round only at its ends, so it had no journey: the map drew nothing
// and no train was sent out. Adding a station to a line "where it fits"
// guessed the place from where the stations stand (decision 80), which on a
// curving or doubling-back line can be the wrong pair of stops, with the
// same result.
//
// The place is now found on the track: between the two stops the track
// between them passes the station at, as the draft already finds the
// stations between (decision 100); or else wherever the line can then be
// driven end to end without turning round on the way, the shortest round
// trip. Presentation only: the stops are still checked and set by GameCore.

extension GameWorld {
    /// Where station `station` joins the stops `stops` (a line's, or a new
    /// line's picked so far) as an index to insert it at, found on the
    /// track; `nil` when the track gives no place, and the caller keeps
    /// its own.
    ///
    /// First, between the first two stops in a row whose track passes the
    /// station (``stationsAlongTrack(from:to:)``). Then `preferred`, the
    /// caller's own place, if a line through the stops with the station
    /// there can drive its whole round trip and turns round only at its
    /// ends, tried on a copy of the world. Otherwise, of the other places
    /// (after the last stop, between each two, before the first) where it
    /// can, the one with the shortest round trip, the first tried among
    /// equals. `nil` for fewer than two stops, a station
    /// already among them, or a station that does not exist.
    public func trackInsertionIndex(of station: StationID, into stops: [StationID], preferring preferred: Int) -> Int? {
        guard stops.count >= 2, !stops.contains(station), self.station(id: station) != nil else { return nil }
        for index in stops.indices.dropFirst()
        where stationsAlongTrack(from: stops[index - 1], to: stops[index])?.contains(station) == true {
            return index
        }
        let preferred = min(max(preferred, 0), stops.count)
        if roundTripWithoutTurning(LineStopEditing.inserting(station, at: preferred, into: stops)) != nil { return preferred }
        var tried: Set<Int> = [preferred]
        var best: (index: Int, seconds: Int64)?
        for index in [stops.count] + Array(1..<stops.count) + [0] where tried.insert(index).inserted {
            guard let seconds = roundTripWithoutTurning(LineStopEditing.inserting(station, at: index, into: stops)) else { continue }
            if best.map({ seconds < $0.seconds }) ?? true { best = (index, seconds) }
        }
        return best?.index
    }

    /// The seconds of the round trip of a new line calling at `stops`, on a
    /// copy of the world, or `nil` when it cannot be driven or turns round
    /// at a stop between its ends.
    func roundTripWithoutTurning(_ stops: [StationID]) -> Int64? {
        var trial = self
        guard let line = try? trial.createLine(named: "Route", stops: stops),
              let journey = trial.lineJourney(line.id), journey.intermediateTurnbacks.isEmpty
        else { return nil }
        return journey.roundTripSeconds
    }
}
