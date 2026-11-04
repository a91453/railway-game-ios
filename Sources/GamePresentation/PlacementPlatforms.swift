import GameCore

// Decision 584, PR-2 (TestFlight 111.1, the author's station of two
// platforms): a train placed at a station of two or more platforms went to
// whichever ``GameSession/platforms(for:at:in:)`` tried first, the first as
// long as it in track order, so an 80 m train always went to the 80 m main
// line even when its line runs on the other track. Now the train tool lists
// the station's platforms before the train is placed, and the player picks
// one. The one picked for them is the first, in that same order, on the
// track network of the train's line (the track joined to its other stops'
// platforms), and one no train stands on and as long as the train before
// one that is not.
//
// The reference has nothing to port: `Ci/`'s lines come with their trains
// and nothing is ever placed by hand. Native.

/// A platform of the station a train is about to be placed at, as the train
/// tool lists it (decision 584).
public struct PlacementPlatformChoice: Hashable, Sendable, Identifiable {
    public let platform: TrackPlatform
    /// Its number, from 1, as the station card numbers them.
    public let number: Int
    /// The train standing on it, if any.
    public let holder: TrainID?
    /// Whether it is shorter than the train.
    public let isShort: Bool
    /// Whether it is on the track network of the train's line.
    public let isOnLine: Bool

    public var id: TrackPlatform { platform }
}

extension GameWorld {
    /// The platforms of `station` train `id` could be placed on, in the
    /// station card's order, when the station has two or more and the
    /// train is off the track; otherwise none (decision 584). `line` is the
    /// line whose track is preferred: the train's own, else this one.
    public func placementPlatformChoices(for id: TrainID, at station: StationID, line: LineID? = nil) -> [PlacementPlatformChoice] {
        guard let train = train(id: id), train.position == nil else { return [] }
        let platforms = trackPlatforms(of: station)
        guard platforms.count > 1 else { return [] }
        let onLine = platformsOnLineTrack(platforms, of: assignedLine(of: id) ?? line, at: station)
        return platforms.enumerated().map { index, platform in
            PlacementPlatformChoice(
                platform: platform, number: index + 1, holder: trainStanding(on: platform),
                isShort: platform.length < train.length, isOnLine: onLine.contains(platform)
            )
        }
    }

    /// The platform picked for train `id` at `station` before the player
    /// picks one (decision 584): in ``GameSession/platforms(for:at:in:)``'s
    /// order, those on the track of its line (or `line`) first; of them,
    /// the first no train stands on and as long as the train, else the
    /// first no train stands on, else the first. `nil` at a station of one
    /// platform or none.
    public func defaultPlacementPlatform(for id: TrainID, at station: StationID, line: LineID? = nil) -> TrackPlatform? {
        preferredPlacementPlatforms(for: id, at: station, line: line).first
    }

    /// Every platform of `station` in the order ``defaultPlacementPlatform(for:at:line:)``
    /// prefers them; empty at a station of one platform or none.
    func preferredPlacementPlatforms(for id: TrainID, at station: StationID, line: LineID?) -> [TrackPlatform] {
        let choices = placementPlatformChoices(for: id, at: station, line: line)
        guard let train = train(id: id), !choices.isEmpty else { return [] }
        let byPlatform = Dictionary(uniqueKeysWithValues: choices.map { ($0.platform, $0) })
        let tried = GameSession.platforms(for: train, at: station, in: self)
        let ordered = tried.filter { byPlatform[$0]?.isOnLine == true } + tried.filter { byPlatform[$0]?.isOnLine != true }
        let free = ordered.filter { byPlatform[$0]?.holder == nil }
        let fits = free.filter { byPlatform[$0]?.isShort == false }
        var seen = Set<TrackPlatform>()
        return (fits + free + ordered).filter { seen.insert($0).inserted }
    }

    /// The platforms among `platforms` on track joined to a platform of
    /// another stop of line `id`: the line's own track network.
    func platformsOnLineTrack(_ platforms: [TrackPlatform], of id: LineID?, at station: StationID) -> Set<TrackPlatform> {
        guard let id, let line = line(id: id) else { return [] }
        let others = line.stops.filter { $0 != station }.flatMap { trackPlatforms(of: $0) }
        guard !others.isEmpty else { return [] }
        var parent: [TrackNodeID: TrackNodeID] = [:]
        func root(_ node: TrackNodeID) -> TrackNodeID {
            var node = node
            while let up = parent[node], up != node { node = up }
            return node
        }
        for edge in network.edges {
            let a = root(edge.from), b = root(edge.to)
            if a != b { parent[a] = b }
        }
        func part(of platform: TrackPlatform) -> TrackNodeID? {
            network.edge(platform.edge).map { root($0.from) }
        }
        let lineParts = Set(others.compactMap(part(of:)))
        return Set(platforms.filter { part(of: $0).map(lineParts.contains) ?? false })
    }

    /// The first train, by ID, standing on `platform`: its head within the
    /// platform's stretch, or a car on the platform's edge behind it.
    func trainStanding(on platform: TrackPlatform) -> TrainID? {
        guard let edge = network.edge(platform.edge) else { return nil }
        return trains.first { train in
            guard case .onEdge(let traversal, let offset)? = train.position else { return false }
            if traversal.edge != platform.edge { return train.trailEdges.contains(platform.edge) }
            let head = traversal.direction == .forward ? offset : edge.length - offset
            let tail = traversal.direction == .forward ? head - train.length : head + train.length
            return min(head, tail) <= platform.end && max(head, tail) >= platform.start
        }?.id
    }
}

extension PlacementPlatformChoice {
    /// "Platform 2 · 80 m".
    public func title(in language: DisplayLanguage) -> String {
        let length = NetworkBuilding.lengthText(platform.length, in: language)
        return language.text("Platform \(number) · \(length)", "第 \(number) 月台 · \(length)")
    }

    /// What the player should know of it before placing the train there:
    /// who stands on it, that it is shorter than the train, or that the
    /// train's line runs on its track. `nil` when none is.
    public func note(train: TrainID, line: LineID?, in world: GameWorld, language: DisplayLanguage) -> String? {
        if let holder {
            let name = world.train(id: holder)?.name ?? ""
            return language.text("\(name) stands here", "\(name) 停在這裡")
        }
        if isShort {
            return language.text("Shorter than the train", "比列車短")
        }
        if isOnLine, let id = world.assignedLine(of: train) ?? line, let name = world.line(id: id)?.name {
            return language.text("\(name)'s track", "\(name)的軌道")
        }
        return nil
    }
}

extension GameSession {
    /// The line whose track the train tool prefers for the selected train:
    /// its own, else the selected line when it calls at the selected
    /// station (decision 584).
    var placementLine: LineID? {
        guard let train = selectedTrain, let station = selectedStation else { return nil }
        if let own = world.assignedLine(of: train.id) { return own }
        guard let line = selectedLine, line.stops.contains(station.id) else { return nil }
        return line.id
    }

    /// The selected station's platforms for the selected train, when it is
    /// off the track and the station has two or more (decision 584).
    public var placementPlatformChoices: [PlacementPlatformChoice] {
        guard let train = selectedTrain, let station = selectedStation else { return [] }
        return world.placementPlatformChoices(for: train.id, at: station.id, line: placementLine)
    }

    /// The platform the selected train will be placed on: the one the
    /// player picked at this station, else the one picked for them
    /// (``GameWorld/defaultPlacementPlatform(for:at:line:)``). `nil` at a
    /// station of one platform or none.
    public var placementPlatform: TrackPlatform? {
        guard let train = selectedTrain, let station = selectedStation else { return nil }
        if let picked = pickedPlacementPlatform, picked.station == station.id,
           world.trackPlatforms(of: station.id).contains(picked) {
            return picked
        }
        return world.defaultPlacementPlatform(for: train.id, at: station.id, line: placementLine)
    }

    /// Picks the platform the selected train is placed on.
    public func pickPlacementPlatform(_ platform: TrackPlatform) {
        pickedPlacementPlatform = platform
    }

    /// The note beside choice `choice` in the train tool.
    public func placementPlatformNote(_ choice: PlacementPlatformChoice) -> String? {
        guard let train = selectedTrain else { return nil }
        return choice.note(train: train.id, line: placementLine, in: world, language: language)
    }

    /// Where the selected train goes at a station of two or more platforms
    /// (decision 584): the platform the player picked, alone; or, when they
    /// picked none, the first GameCore takes of
    /// ``GameWorld/defaultPlacementPlatform(for:at:line:)``'s order.
    /// `nil` at a station of one platform or none, or when GameCore takes
    /// it on none of them.
    func placementPlatformToUse(for train: Train, at station: Station) -> TrackPlatform? {
        if let picked = pickedPlacementPlatform, picked.station == station.id,
           world.trackPlatforms(of: station.id).contains(picked) {
            return picked
        }
        let order = world.preferredPlacementPlatforms(for: train.id, at: station.id, line: placementLine)
        for platform in order {
            var draft = world
            if (try? Self.place(train.id, on: platform, heading: placementHeading, in: &draft)) != nil { return platform }
        }
        return order.first
    }
}
