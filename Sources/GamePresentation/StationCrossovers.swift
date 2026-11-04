import GameCore

// Decision 572 (TestFlight 111.1, a save from before it: "can the track
// before and after a station get its crossovers by itself when it is
// built? I have two trains now, but a third still will not go on"). The
// platform tool lays a station's crossovers only since decision 571, and
// only when it sets platforms on both tracks itself. A station built on
// both tracks before that, and one whose single track was made double
// ("Make double track" copies its platforms onto the second track, but
// lays crossovers only at the run's ends, which may lie outside the
// platforms), has none past its platforms, so the line still counts it as
// single track. Here the station panel offers to lay them, priced first,
// and "Make double track" lays them with the second track. Nothing changes
// a player's track when a game is loaded: the panel offers, the player
// taps. The crossovers are decision 571's (``stationCrossovers(of:in:lookingIn:)``),
// laid where it would have laid them.

/// What the station panel offers to lay between a station's two tracks
/// (decision 572): how many crossovers, their price, and why the cash in
/// hand does not pay it.
public struct StationCrossoverOffer: Equatable, Sendable {
    public let count: Int
    public let cost: Money
    public let problem: String?
}

/// ``GameSession/stationCrossoverOffer(for:)`` as last worked out.
struct StationCrossoverOfferMemo {
    let station: StationID
    let commandRevision: Int
    let offer: StationCrossoverOffer?
    let command: PlayerCommand?
}

extension GameSession {
    /// The crossovers station `id` lacks between the two tracks of a
    /// double track (decision 572): for each platform with the same
    /// station's platform on the track beside it, decision 571's crossovers
    /// past its ends where no turnout stands within
    /// ``DoubleTrack/stationCrossoverReach`` on that side. Planned and
    /// built in turn on `world` (a pricing or preview copy), each seeing
    /// the ones before, so the two platforms of a pair get one set between
    /// them. Returns them in order, and `world` with them built; GameCore's
    /// refusals (no room, a train in the way, want of cash) leave one out.
    ///
    /// The trains are taken off the track in the draft first: GameCore
    /// never cuts track a train stands on, and a line's trains run on these
    /// tracks all day. ``layLiftingTrains(_:in:)`` lays them with the trains.
    func missingStationCrossovers(of id: StationID, in world: GameWorld) -> (stretches: [PlayerCommand.TrackStretch], built: GameWorld) {
        var draft = world
        for train in draft.trains where train.position != nil {
            _ = try? draft.unassignTrain(train.id)
            if draft.train(id: train.id)?.execution != nil { _ = try? draft.stopTrainService(train.id) }
            _ = try? draft.unplaceTrain(train.id)
        }
        var stretches: [PlayerCommand.TrackStretch] = []
        // Each pass lays one platform's; those it lays split edges, so the
        // platforms are read again. Each laid turnout stops the next pass
        // laying one on that side, so it ends; the bound is a backstop.
        var looked: Set<TrackPlatform> = []
        for _ in 0..<(2 * draft.network.platforms(of: id).count + 1) {
            // The platform whose track meets another station's own
            // crossover near that station's platform goes first: its
            // crossover's near turnout then lies on the same track as
            // there (``nearTurnoutDistance(from:station:in:)``).
            let all = draft.network.platforms(of: id)
            let ordered = all.enumerated().sorted { a, b in
                let first = nearTurnoutDistance(from: a.element, station: id, in: draft) ?? .max
                let second = nearTurnoutDistance(from: b.element, station: id, in: draft) ?? .max
                return first != second ? first < second : a.offset < b.offset
            }.map(\.element)
            let next = ordered.first { platform in
                guard !looked.contains(platform), let geometry = draft.trackGeometry(of: platform.edge),
                      let beside = trackBeside(platform.edge, near: geometry.location(at: (platform.start + platform.end) / 2).position.plan, in: draft)?.beside
                else { return false }
                return draft.network.platforms(on: beside.edge).contains { $0.station == id }
            }
            guard let platform = next else { break }
            looked.insert(platform)
            let found = stationCrossovers(of: (platform.edge, platform.start, platform.end), in: draft, lookingIn: draft)
            for crossover in found {
                var trial = draft
                guard (try? crossover.build(in: &trial, heights: heights)) != nil else { continue }
                draft = trial
                stretches.append(crossover)
            }
            if !found.isEmpty { looked = [] }
        }
        return (stretches, draft)
    }

    /// How far from another station's platform the first turnout lies
    /// that the track from `platform` (of station `station`) reaches
    /// either way through plain joints, when that is within
    /// ``DoubleTrack/stationThroat``; `nil` where none is.
    ///
    /// Decision 572: a station's single crossover (decision 571) has a
    /// near turnout just past one track's platform and a far one on the
    /// other. Measured on a 3 km double track with a terminus at each end
    /// and three trains, simple rules with traffic control: with the near
    /// turnouts on the same track at both ends the trains ran all day;
    /// with them on different tracks all three stood deadlocked from the
    /// first trip on (1,074 minutes). The platform tool tapping one track
    /// at both stations lays them the first way; the panel finds it by
    /// laying the crossover from the platform whose track meets the other
    /// station's near turnout, the nearer of its two.
    func nearTurnoutDistance(from platform: TrackPlatform, station: StationID, in world: GameWorld) -> Int64? {
        guard let start = world.network.edge(platform.edge) else { return nil }
        var best: Int64?
        for forward in [false, true] {
            var node = forward ? start.to : start.from
            var came = platform.edge
            for _ in 0..<world.network.edges.count {
                guard let ends = world.network.node(node)?.ends else { break }
                if ends.count >= 3 {
                    for end in ends where end.edge != came {
                        guard let edge = world.network.edge(end.edge) else { continue }
                        for other in world.network.platforms(on: end.edge) where other.station != station {
                            let distance = edge.from == node ? other.start : edge.length - other.end
                            if distance <= DoubleTrack.stationThroat, distance < (best ?? .max) { best = distance }
                        }
                    }
                    break
                }
                guard ends.count == 2, let next = ends.first(where: { $0.edge != came }), let edge = world.network.edge(next.edge) else { break }
                node = edge.from == node ? edge.to : edge.from
                came = next.edge
            }
        }
        return best
    }

    /// Lays `crossovers` in `world` in turn. A train standing on or holding
    /// the track one cuts is taken off its line and the track and, once
    /// all are laid, put back where its line's trips start (or at its far
    /// end, or at a platform beside either, ``placeBeside(_:of:journeys:in:)``),
    /// as the passing loop ＋ lays does (decision 264). Returns the names
    /// of the trains moved. Throws what GameCore refused, or
    /// ``GameError/trackReserved(_:)`` for a train that cannot go back.
    func layLiftingTrains(_ crossovers: [PlayerCommand.TrackStretch], in world: inout GameWorld) throws(GameError) -> [String] {
        var lifted: [(train: TrainID, line: LineID, pattern: Int?)] = []
        for crossover in crossovers {
            while true {
                var attempt = world
                do throws(GameError) {
                    _ = try crossover.build(in: &attempt, heights: heights)
                    world = attempt
                    break
                } catch {
                    // A train on no line is the player's to move: refused.
                    guard case .trackReserved(let id) = error, lifted.count < world.trains.count,
                          let line = world.assignedLine(of: id) else { throw error }
                    let pattern = world.assignedPattern(of: id)
                    try world.unassignTrain(id)
                    if world.train(id: id)?.execution != nil { try world.stopTrainService(id) }
                    if world.train(id: id)?.position != nil { try world.unplaceTrain(id) }
                    lifted.append((id, line, pattern))
                }
            }
        }
        var moved: [String] = []
        for (train, line, pattern) in lifted {
            guard let journey = world.lineJourney(line) else { throw .trackReserved(train) }
            let back = Self.farEndJourney(of: line, in: world)
            var placed = world
            if (try? Self.placeAtStart(train, of: journey, in: &placed)) != nil {
                world = placed
            } else if let back, (try? Self.placeAtStart(train, of: back, in: &placed)) != nil {
                world = placed
            } else if let beside = Self.placeBeside(train, of: line, journeys: [journey, back].compactMap { $0 }, in: world) {
                world = beside
            } else {
                throw .trackReserved(train)
            }
            try world.assignTrain(train, to: line, pattern: pattern)
            moved.append(world.train(id: train)?.name ?? "")
        }
        return moved
    }

    /// What the station panel offers to lay between station `id`'s two
    /// tracks (decision 572), or `nil` when it has nothing to lay: no
    /// platform on both tracks, or its crossovers there already. Worked
    /// out once for each station and command.
    public func stationCrossoverOffer(for id: StationID) -> StationCrossoverOffer? {
        let draft = stationCrossoverDraft(for: id)
        guard let offer = draft.offer else { return nil }
        // L9-3: the cash in hand now, not when it was worked out: time and
        // fares change it without a command.
        return StationCrossoverOffer(count: offer.count, cost: offer.cost, problem: shortfallText(offer.cost, doing: draft.command))
    }

    func stationCrossoverDraft(for id: StationID) -> StationCrossoverOfferMemo {
        if let memo = stationCrossoverOfferMemo, memo.station == id, memo.commandRevision == commandRevision { return memo }
        var memo = StationCrossoverOfferMemo(station: id, commandRevision: commandRevision, offer: nil, command: nil)
        if allows(UnlockableTool.doubleTrack), world.station(id: id) != nil, world.network.platforms(of: id).count >= 2 {
            let found = missingStationCrossovers(of: id, in: world.pricingCopy())
            if !found.stretches.isEmpty {
                let command = PlayerCommand.buildStationCrossovers(id, found.stretches)
                let cost = Money(GameWorld.pricingBalance.amount - found.built.economy.balance.amount)
                memo = StationCrossoverOfferMemo(
                    station: id, commandRevision: commandRevision,
                    offer: StationCrossoverOffer(count: found.stretches.count, cost: cost, problem: nil),
                    command: command
                )
            }
        }
        stationCrossoverOfferMemo = memo
        return memo
    }

    /// The station panel's button (decision 572): what it says it lays,
    /// and for how much.
    public func stationCrossoverButtonText(_ offer: StationCrossoverOffer) -> String {
        offer.count == 1
            ? language.text("Add a crossover between the two tracks (\(offer.cost.moneyText))", "在兩條軌道之間加一組渡線（\(offer.cost.moneyText)）")
            : language.text(
                "Add a crossover at each end between the two tracks (\(offer.cost.moneyText))",
                "在兩條軌道之間兩端各加一組渡線（\(offer.cost.moneyText)）"
            )
    }

    /// What the station panel says under the button (decision 572).
    public var stationCrossoverHelp: String {
        language.text(
            "Without a crossover, trains cannot change between the two tracks here, so the line runs fewer trains.",
            "沒有渡線時，列車在這站不能換到另一條軌道，路線能排的列車會變少。"
        )
    }

    /// Lays the crossovers ``stationCrossoverOffer(for:)`` offers for
    /// station `id`, as one command that undo takes back.
    public func addStationCrossovers(_ id: StationID) {
        guard let command = stationCrossoverDraft(for: id).command else { return }
        let done = perform(command) { outcome, before, world in
            let cost = Money(before.economy.balance.amount - world.economy.balance.amount)
            return (outcome.number == 1
                ? language.text(
                    "Added a crossover between the two tracks for \(cost.moneyText). Trains can now pass each other at this station.",
                    "已在兩條軌道之間加一組渡線，花費 \(cost.moneyText)。列車可以在這站交會了。"
                )
                : language.text(
                    "Added a crossover at each end between the two tracks for \(cost.moneyText). Trains can now pass each other at this station.",
                    "已在兩條軌道之間兩端各加一組渡線，花費 \(cost.moneyText)。列車可以在這站交會了。"
                )) + Self.liftedText(outcome, in: language)
        }
        if done != nil { playSound?(.track) }
    }
}
