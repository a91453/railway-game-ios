// Trains waiting for each other in a ring with traffic control off
// (decision 805). Decision 228 keeps the trains of real runs apart by
// rules each train applies to the trains near it: behind a tail, short of
// track shared with a train coming the other way, and, leaving a platform,
// after a faster train behind. Any two of them never wait for each other,
// but three or more can, each for the next (decision 801 found one such
// ring and took its rule away; the rules left can still close others).
// Nothing in a ring moves again by itself, and every train behind it
// stands too.
//
// So as each minute begins the trains standing held are looked at for
// rings, and of each ring one train goes first: one whose hold is an order
// of going only (``SpacingHold/isOrderOnly``), never one behind a tail or
// short of track a train coming towards it is on. It goes as far as every
// other rule lets it in that minute, and from where it then is the rules
// decide again. Nothing is remembered: a ring that is still there a minute
// later is looked at again.
//
// Everything here is derived from the world as it is; what a train waived
// lets go is only its allowance of the minute (decision 248).

extension GameWorld {
    /// Decision 805: the trains of real runs on their way that stand held
    /// with traffic control off, with no way on at all, each with the train
    /// that holds it and why (``heldUp(_:within:near:)``).
    func spacingStands(near index: [TrackEdgeID: [TrainID]], ways: inout [TrainID: SpacingWay]) -> [TrainID: (by: TrainID, why: SpacingHold)] {
        guard spacingApplies else { return [:] }
        var stands: [TrainID: (by: TrainID, why: SpacingHold)] = [:]
        for train in trains where train.position != nil && train.movement.rate > 0 {
            guard case .travellingToStop? = train.execution, let held = heldUp(train, within: 1, near: index, ways: &ways), held.clear == 0 else { continue }
            stands[train.id] = (held.by, held.why)
        }
        return stands
    }

    /// Decision 805: the rings among `stands` (``spacingStands(near:ways:)``):
    /// trains each held by the next, the last by the first. Each ring from
    /// its lowest numbered train on, the rings by that train. A train is
    /// held by one train, so it is in one ring at most.
    static func spacingRings(in stands: [TrainID: (by: TrainID, why: SpacingHold)]) -> [[TrainID]] {
        var rings: [[TrainID]] = []
        var seen: Set<TrainID> = []
        for start in stands.keys.sorted() where !seen.contains(start) {
            var walk: [TrainID] = []
            var at = start
            while stands[at] != nil, !seen.contains(at) {
                seen.insert(at)
                walk.append(at)
                at = stands[at]!.by
            }
            // Back on this walk: a ring, from where it came back to.
            guard let first = walk.firstIndex(of: at) else { continue }
            let ring = Array(walk[first...])
            let lowest = ring.indices.min { ring[$0] < ring[$1] }!
            rings.append(Array(ring[lowest...] + ring[..<lowest]))
        }
        return rings.sorted { $0[0] < $1[0] }
    }

    /// Decision 805: of each ring among `stands`, the train that goes
    /// first this minute, with the train whose turn before it is waived:
    /// the lowest numbered of those that let a train behind them pass
    /// first, or else of those short of track a train not yet on it is
    /// nearer to, that can then go on at all within `reach` of it (as far
    /// as it may travel in the minute). None of a ring where no such train
    /// can: every one of them stands behind a tail or short of a train on
    /// its track, and letting one go would run it into another.
    func releasesFromRings(
        _ stands: [TrainID: (by: TrainID, why: SpacingHold)], near index: [TrackEdgeID: [TrainID]], ways: inout [TrainID: SpacingWay],
        reach: (Train) -> Int64
    ) -> [TrainID: TrainID] {
        guard stands.count > 1 else { return [:] }
        var waived: [TrainID: TrainID] = [:]
        for ring in Self.spacingRings(in: stands) {
            let order = ring.filter { stands[$0]?.why == .passing }.sorted() + ring.filter { stands[$0]?.why == .oncomingNearer }.sorted()
            for id in order {
                guard let train = train(id: id), let holder = stands[id]?.by else { continue }
                let far = reach(train)
                guard far > 0, heldUp(train, within: far, near: index, ways: &ways, waiving: holder).map({ $0.clear > 0 }) ?? true else { continue }
                waived[id] = holder
                break
            }
        }
        return waived
    }

    /// Decision 805: the trains that stand for good with traffic control
    /// off, each with the train that holds it: those waiting for each
    /// other in a ring (``spacingRings(in:)``), and those held, through
    /// however many trains, by one of a ring. Empty under traffic control
    /// (``deadlock(memo:)`` finds its deadlocks), and without a line of
    /// real runs. Derived on every call, never saved.
    func spacingDeadlock() -> [TrainID: TrainID] {
        guard spacingApplies else { return [:] }
        var ways: [TrainID: SpacingWay] = [:]
        let stands = spacingStands(near: spacingIndex(), ways: &ways)
        var stuck = Set(Self.spacingRings(in: stands).joined())
        guard !stuck.isEmpty else { return [:] }
        var grew = true
        while grew {
            grew = false
            for (id, hold) in stands where !stuck.contains(id) && stuck.contains(hold.by) {
                stuck.insert(id)
                grew = true
            }
        }
        return Dictionary(uniqueKeysWithValues: stuck.map { ($0, stands[$0]!.by) })
    }
}
