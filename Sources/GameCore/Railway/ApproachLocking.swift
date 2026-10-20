// Approach locking (ARCHITECTURE decision 294). With traffic control and
// block sections on, a service of a line with runs (decision 133) set off
// on a long leg took its whole route at once when it was free: a train
// leaving Taichung for Zuoying held Zuoying's turnouts for the 50 minutes
// it took to get there, and no set standing at Zuoying could leave north
// through them, so the runs they were for were dropped. A real railway sets
// the route into a station only as the train comes near it.
//
// So such a train holds its route only as far as the last block boundary
// ``approachHold`` short of its stop until it comes within
// ``approachReach`` of the stop; from there it takes the rest as any train
// takes more of its route (decision 212), as a block falls free. What it
// holds before is plain line it holds whole as before, so no train can
// come at it there; what it leaves is the end of its way, which a train
// can only use without the line it holds. Derived from the train and the
// network, never saved; with traffic control or block sections off, and
// for any other train, nothing changes.

extension GameWorld {
    /// How near its stop a service of a line with runs comes before it
    /// takes the rest of its route (decision 294): 896,000 units, 14 km,
    /// the ``approachHold`` it leaves, the 8.3 km a high-speed set needs to
    /// stop from 300 km/h, and a block more.
    static let approachReach: Int64 = 896_000

    /// How much of its route at least such a service leaves untaken while
    /// it is farther than ``approachReach`` from its stop: 256,000 units,
    /// 4 km, more than a station's turnouts and platforms.
    static let approachHold: Int64 = 256_000

    /// How far along its route (see ``AuthorityEnvelopes``) `train` may
    /// hold now (decision 294), or `nil` when it may hold all of it: with
    /// traffic control and block sections on, a service of a line with runs
    /// travelling to a stop more than ``approachReach`` away holds it only
    /// to the last block boundary ``approachHold`` or more short of the
    /// stop. `nil` also when there is no such boundary beyond its head.
    func approachLimit(of train: Train, _ envelopes: AuthorityEnvelopes) -> Int64? {
        guard isTrafficControlEnabled, blockSections, case .travellingToStop? = train.execution,
              envelopes.length > Self.approachReach, envelopes.length < .max, followsRealTimetable(train)
        else { return nil }
        let limit = blockBoundary(envelopes, atOrBefore: envelopes.length - Self.approachHold)
        return limit >= 1 ? limit : nil
    }

    /// Decision 294: `candidate`, about to set off, with its route held
    /// only to `limit` along `envelopes` (see ``approachLimit(of:_:)``),
    /// or, `following`, as far as the trains ahead leave it short of that
    /// (Stage U2), or the lowest numbered other train holding track it
    /// needs that far.
    func reservingApproach(_ candidate: Train, envelopes: AuthorityEnvelopes, limit: Int64, following: Bool,
                           memo: inout DirectionMemo) -> Reserving {
        let needs = authorityEnvelope(envelopes, to: limit)
        let holders = trackHolders(memo: &memo)
        guard let holder = holder(of: needs, except: candidate.id, holders: holders) else {
            var train = candidate
            train.reservation = needs.sorted()
            return .granted(train)
        }
        if following, let train = followingAuthority(of: candidate, route: cover(of: approachStretches(of: candidate, envelopes, to: limit)),
                                                     limit: limit, memo: &memo) {
            return .granted(train)
        }
        return .held(by: holder)
    }

    /// What `train` covers from its tail to `distance` along `envelopes`:
    /// its body, then its route as far as that.
    private func approachStretches(of train: Train, _ envelopes: AuthorityEnvelopes, to distance: Int64) -> [TrackStretch] {
        guard !envelopes.stretches.isEmpty else { return bodyStretches(of: train) }
        let end = authorityEnd(envelopes, to: distance)
        return bodyStretches(of: train) + Array(envelopes.stretches[..<end.index]) + [end.part]
    }
}
