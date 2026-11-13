import GameCore

// The reference for taking turns on single track (decision 718), written
// from the decision's words, not from GameCore's code: of the services
// waiting with their doors closed, one that could go lets the one that has
// waited longest go first when their ways cross head on and only moving
// trains (or none) keep that one.

extension ReferenceWorld {
    /// When a service waiting at a stop came to wait: its doors closed.
    private func cameToWait(_ train: Train) -> Int64? {
        guard train.position != nil, let service = train.service, service.waiting, let closing = service.closing else { return nil }
        return Self.capped(closing, 9)
    }

    /// The runs `train`'s head is on and goes along to where its route ends.
    private func runsFromHead(_ train: Train) -> [Run] {
        guard let window = routeWindow(train) else { return [] }
        return Array(window.path[(path(of: train).count - 1)...])
    }

    /// Whether `train` is going somewhere now: a service between stops that
    /// holds track and has room ahead on it.
    private func moving(_ train: Train) -> Bool {
        guard let service = train.service, !service.waiting, !train.reservation.isEmpty else { return false }
        if let room = authority(train) { return room > 0 }
        return needs(train).moves
    }

    /// The train `off` lets go first: `waiter` as it would set off now.
    func turnOwed(by off: Train, from waiter: Train) -> Int? {
        guard trafficControl, let mine = cameToWait(waiter), needs(off).moves else { return nil }
        let headOn = Set(runsFromHead(off).map { Run(edge: $0.edge, forward: !$0.forward) })
        var world = self
        let plan = world.routeMemo.scheduled ?? world.scheduledPlan()
        // Longest waiting first; of the same second, the lower numbered.
        let older = trains.compactMap { other -> (since: Int64, train: Train)? in
            guard other.id != off.id, let since = cameToWait(other), since <= clockSeconds, (since, other.id) < (mine, off.id) else { return nil }
            return (since, other)
        }.sorted { ($0.since, $0.train.id) < ($1.since, $1.train.id) }
        for (_, other) in older {
            guard world.waitingScheduled(other, plan: plan) == nil, let leaving = firstLeaving(other) else { continue }
            let wanted = needs(leaving)
            guard wanted.moves, runsFromHead(leaving).contains(where: headOn.contains) else { continue }
            if !world.canSetOff(leaving) {
                guard holder(of: wanted.resources, except: other.id) != nil,
                      !trains.contains(where: { $0.id != other.id && !moving($0) && blocks($0, wanted.resources, for: other.id) })
                else { continue }
            }
            return other.id
        }
        return nil
    }
}
