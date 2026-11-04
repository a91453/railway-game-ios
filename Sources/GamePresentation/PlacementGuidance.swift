import GameCore

// Decision 584 (TestFlight 111.1, the author: "the game's set-up really is a
// bit complicated"): a new player could not tell why a train would not go
// on the track, nor what to do next. The train tool's button said "Place
// Train 3 Here" with no station picked; a refusal said only "a train's
// route runs over that track"; and a line given its trains while an idle
// train stood at its first stop bought one more and ran none. What the
// game says instead: which station to pick, whose train holds the
// platform, how short the platform is, and that an idle train with no line
// can be given the line rather than buying another.
//
// The reference has nothing to port: `Ci/`'s lines come with their trains
// and nothing is ever placed by hand. Native.

/// Why train placement at a station would be refused (decision 584).
public enum TrainPlacementProblem: Hashable, Sendable {
    /// No station is picked.
    case noStation
    /// The station has no platform on the track.
    case noPlatform(StationID)
    /// `train` stands on (or under traffic control holds) the platforms.
    case held(StationID, by: TrainID)
    /// Every platform is shorter than the train and the track behind none
    /// takes the rest: `longest` world units, `cars` cars would fit.
    case tooShort(StationID, longest: Int64, cars: Int)
    /// The platform picked, number `platform` (from 1), is shorter than
    /// the train, `length` world units, and the track behind it does not
    /// take the rest; a longer one stands at the station (decision 584).
    case pickedTooShort(StationID, platform: Int, length: Int64, cars: Int)
    /// Refused for another reason, as GameCore says it.
    case refused(GameError)
}

/// A train standing at a stop of a line with no line and nothing to do
/// (decision 584).
public struct IdleTrainAtStop: Hashable, Sendable {
    public let train: TrainID
    public let station: StationID
}

extension GameWorld {
    /// Why unplaced train `id` cannot be placed at `station` facing nearer
    /// `heading`, or `nil` when it can (tried on a copy, as
    /// ``GameSession/placeSelectedTrain()`` would place it). `nil` for a
    /// train that does not exist or is already placed.
    ///
    /// Decision 584: with `platform`, on that platform alone (the one the
    /// player picked at a station of two or more).
    public func trainPlacementProblem(
        _ id: TrainID, at station: StationID?, heading: CompassHeading, platform: TrackPlatform? = nil
    ) -> TrainPlacementProblem? {
        guard let train = train(id: id), train.position == nil else { return nil }
        guard let station, self.station(id: station) != nil else { return .noStation }
        let platforms = trackPlatforms(of: station)
        guard let longest = platforms.map(\.length).max() else { return .noPlatform(station) }
        var draft = self
        do throws(GameError) {
            if let platform {
                _ = try GameSession.place(id, on: platform, heading: heading, in: &draft)
            } else {
                _ = try GameSession.place(id, atPlatformOf: station, heading: heading, in: &draft)
            }
            return nil
        } catch {
            if case .trackReserved(let holder) = error { return .held(station, by: holder) }
            let pitch = max(train.carPitch, 1)
            if case .invalidTrainPosition = error, longest < train.length {
                return .tooShort(station, longest: longest, cars: max(Int(longest / pitch), Train.minimumCars))
            }
            if case .invalidTrainPosition = error, let platform, platform.length < train.length {
                let number = (platforms.firstIndex(of: platform) ?? 0) + 1
                return .pickedTooShort(station, platform: number, length: platform.length, cars: max(Int(platform.length / pitch), Train.minimumCars))
            }
            return .refused(error)
        }
    }

    /// What the player is told of `problem` for train `id`: why, and what
    /// to do next, in a sentence or two.
    public func trainPlacementProblemText(_ problem: TrainPlacementProblem, train id: TrainID, in language: DisplayLanguage) -> String {
        let name = train(id: id)?.name ?? ""
        switch problem {
        case .noStation:
            return language.text(
                "Tap a station on the map first, then place \(name) there.",
                "先點地圖上的車站，再把 \(name) 放在那裡。"
            )
        case .noPlatform(let station):
            return language.text(
                "\(stationName(station)) has no platform yet. Add one with the network tool.",
                "\(stationName(station)) 還沒有月台。請用路網工具加上月台。"
            )
        case .held(let station, let holder):
            return platformHeldText(at: station, by: holder, in: language)
        case .tooShort(let station, let longest, let cars):
            let train = train(id: id)
            let whole = Int64(train?.cars ?? 1) * (train?.carPitch ?? 0)
            let count = train?.cars ?? 1
            return language.text(
                "\(name) is too long for \(stationName(station)): its longest platform is \(NetworkBuilding.lengthText(longest, in: language)), the train \(count) \(count == 1 ? "car" : "cars"), \(NetworkBuilding.lengthText(whole, in: language)). Shorten it to \(cars) \(cars == 1 ? "car" : "cars"), or lengthen a platform.",
                "\(name) 太長，\(stationName(station)) 放不下：最長的月台 \(NetworkBuilding.lengthText(longest, in: language))，列車 \(count) 節共 \(NetworkBuilding.lengthText(whole, in: language))。減到 \(cars) 節，或把月台加長。"
            )
        case .pickedTooShort(let station, let number, let length, let cars):
            let train = train(id: id)
            let whole = Int64(train?.cars ?? 1) * (train?.carPitch ?? 0)
            let count = train?.cars ?? 1
            return language.text(
                "\(stationName(station))'s platform \(number) is \(NetworkBuilding.lengthText(length, in: language)), too short for \(name), \(count) \(count == 1 ? "car" : "cars"), \(NetworkBuilding.lengthText(whole, in: language)). Pick a longer platform, or shorten it to \(cars) \(cars == 1 ? "car" : "cars").",
                "\(stationName(station))第 \(number) 月台 \(NetworkBuilding.lengthText(length, in: language))，放不下 \(name)（\(count) 節共 \(NetworkBuilding.lengthText(whole, in: language))）。選較長的月台，或減到 \(cars) 節。"
            )
        case .refused(let error):
            return error.playerMessage(in: language)
        }
    }

    /// "Gangho's platform is taken by Train 4", and what to do about it:
    /// a train with no line and no trip can be given a line (decision 584);
    /// any other leaves first.
    public func platformHeldText(at station: StationID, by holder: TrainID, in language: DisplayLanguage) -> String {
        let place = stationName(station)
        let train = train(id: holder)?.name ?? ""
        let held = language.text("\(place)'s platform is taken by \(train).", "\(place)的月台被 \(train) 佔著。")
        if isIdleWithoutLine(holder) {
            return held + language.text(
                " It has no line: give it one in its train card, or move it, and try again.",
                "它沒有路線：在它的列車卡配屬路線，或把它開走，再試一次。"
            )
        }
        return held + language.text(" Try again once it has left.", "等它開走再試一次。")
    }

    /// Whether train `id` stands on the track with no line, no service and
    /// no way ahead: it waits for the player.
    public func isIdleWithoutLine(_ id: TrainID) -> Bool {
        guard let train = train(id: id) else { return false }
        return train.position != nil && train.execution == nil && !train.hasPathAhead && assignedLine(of: id) == nil
    }

    /// The trains standing on a platform of `station`, in ID order: their
    /// head within a platform's stretch of its edge, or a car on a
    /// platform's edge behind it.
    public func trainsStanding(at station: StationID) -> [TrainID] {
        let platforms = network.platforms(of: station)
        guard !platforms.isEmpty else { return [] }
        return trains.filter { train in
            guard case .onEdge(let traversal, let offset)? = train.position else { return false }
            for platform in platforms {
                if train.trailEdges.contains(platform.edge) { return true }
                guard platform.edge == traversal.edge, let edge = network.edge(platform.edge) else { continue }
                // The train's stretch of its head edge, measured forward.
                let head = traversal.direction == .forward ? offset : edge.length - offset
                let tail = traversal.direction == .forward ? head - train.length : head + train.length
                if min(head, tail) <= platform.end, max(head, tail) >= platform.start { return true }
            }
            return false
        }
        .map(\.id)
    }

    /// The train standing at line `id`'s first stop that does not run for
    /// it, an idle one with no line first: what keeps the line's new trains
    /// off the track there (decision 584). `nil` when none does.
    public func lineStartBlocker(_ id: LineID) -> TrainID? {
        guard let line = line(id: id), let first = line.stops.first else { return nil }
        let others = trainsStanding(at: first).filter { assignedLine(of: $0) != id }
        return others.first(where: isIdleWithoutLine) ?? others.first
    }

    /// The trains standing at a stop of line `id` with no line and nothing
    /// to do (decision 584): given the line, they run for it without
    /// buying another.
    public func idleTrainsAtStops(of id: LineID) -> [IdleTrainAtStop] {
        guard let line = line(id: id) else { return [] }
        var found: [IdleTrainAtStop] = []
        for stop in line.stops {
            for train in trainsStanding(at: stop) where isIdleWithoutLine(train) && !found.contains(where: { $0.train == train }) {
                found.append(IdleTrainAtStop(train: train, station: stop))
            }
        }
        return found
    }

    /// What line `id`'s panel says of an idle train standing at one of its
    /// stops (decision 584).
    public func idleTrainAtStopText(_ train: TrainID, at station: StationID, line id: LineID, in language: DisplayLanguage) -> String {
        let name = self.train(id: train)?.name ?? ""
        let line = line(id: id)?.name ?? ""
        return language.text(
            "\(name) stands at \(stationName(station)) with no line. Give it \(line) instead of buying another.",
            "\(name) 停在\(stationName(station))、沒有路線。可以把它配屬給\(line)，不必再買。"
        )
    }

    /// What a message about trains left off line `id`'s track adds when a
    /// train of no use to the line holds its first stop: whose it is and
    /// what to do. `nil` when none does.
    func lineStartBlockedText(_ id: LineID, in language: DisplayLanguage) -> (text: String, train: TrainID)? {
        guard let blocker = lineStartBlocker(id), let first = line(id: id)?.stops.first else { return nil }
        let line = line(id: id)?.name ?? ""
        let held = platformHeldText(at: first, by: blocker, in: language)
        guard isIdleWithoutLine(blocker) else { return (held, blocker) }
        let name = train(id: blocker)?.name ?? ""
        return (language.text(
            "\(stationName(first))'s platform is taken by \(name), which has no line: give it \(line) and it runs for it.",
            "\(stationName(first))的月台被 \(name) 佔著，它沒有路線：把它配屬給\(line)就能開。"
        ), blocker)
    }
}

extension GameSession {
    /// Decision 584: the train tool's button with no station picked asks
    /// for one rather than offering to place the train nowhere. `nil` with
    /// no train selected (no button).
    public var trainActionTitle: String? {
        guard let train = selectedTrain else { return nil }
        guard selectedStation != nil else { return language.text("Tap a Station on the Map First", "先點地圖上的車站") }
        return train.position == nil
            ? language.text("Place \(train.name) Here", "把「\(train.name)」放在這裡")
            : language.text("Send \(train.name) Here", "派「\(train.name)」到這裡")
    }

    /// Whether the train tool's button acts: a station is picked.
    public var trainActionIsReady: Bool {
        selectedTrain != nil && selectedStation != nil
    }

    /// "Go" on a message naming a train (decision 584): selects it as a tap
    /// would and follows it on the map.
    public func goToTrain(_ id: TrainID) {
        guard world.train(id: id) != nil else { return }
        tapTrain(id)
        followTrain(id)
    }

    /// The chip's title for "Go" to train `id`.
    public func goToTrainTitle(_ id: TrainID) -> String {
        let name = world.train(id: id)?.name ?? ""
        return language.text("Go to \(name)", "前往 \(name)")
    }

    /// Decision 584: after a command that left trains of line `id` off the
    /// track because a train held its first stop, the message offers "Go"
    /// to that train.
    func pointToLineStartBlocker(_ id: LineID, after outcome: PlayerCommand.Outcome?) {
        guard let outcome, outcome.held > 0, let current = message, world.lineStartBlockedText(id, in: language) != nil,
              let blocker = world.lineStartBlocker(id) else { return }
        message = StatusMessage(
            kind: current.kind, text: current.text, fundsNeeded: current.fundsNeeded, sellableTrain: current.sellableTrain,
            depotOffer: current.depotOffer, goToTrain: blocker
        )
    }
}
