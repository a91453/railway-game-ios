import GameCore

// Decision 955: the network tool's track system (decision 951's
// `TrackEdge.system`), chosen before the track is laid, and what the
// menus and messages say about it: which train types a line's track
// carries, and a guideway train's first beam.

extension TrackSystem {
    /// What it is, for the network tool's menu and its summary line.
    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .conventional: language.text("Ordinary track", "一般軌道")
        case .straddle: language.text("Monorail beam", "跨座式單軌梁")
        case .maglev: language.text("Maglev guideway", "磁浮軌道梁")
        case .suspended: language.text("Suspended monorail beam", "懸吊式單軌梁")
        }
    }

    /// The systems in the order the network tool offers them.
    public static let offered: [TrackSystem] = [.conventional, .straddle, .maglev, .suspended]
}

extension GameSession {
    /// Decision 955: lays the next stretches as `system`. A guideway is
    /// elevated unless the player forced another structure: the tool's
    /// automatic or surface choice becomes elevated, and becomes automatic
    /// again when ordinary track is chosen back.
    public func chooseNetworkSystem(_ system: TrackSystem) {
        guard system != networkSystem else { return }
        networkSystem = system
        if system.isGuideway {
            if networkStructure == .automatic || networkStructure == .surface {
                networkStructure = .elevated
                networkStructureRaisedForGuideway = true
            }
        } else if networkStructureRaisedForGuideway {
            if networkStructure == .elevated { networkStructure = .automatic }
            networkStructureRaisedForGuideway = false
        }
    }

    /// Decision 955: what the network tool says under its options while a
    /// guideway is chosen: what joins it, that it does not cross ordinary
    /// track on the level, and which trains run on it; `nil` for ordinary
    /// track.
    public var networkSystemNote: String? {
        Self.guidewayNote(networkSystem, in: language)
    }

    static func guidewayNote(_ system: TrackSystem, in language: DisplayLanguage) -> String? {
        guard system.isGuideway else { return nil }
        let train = TrainType.allCases.first { $0.trackSystem == system }.map { Train.typeText($0, in: language) } ?? ""
        return language.text(
            "Only \(train) trains run on it, and it joins only the same guideway. It can't cross ordinary track on the level: go over or under it.",
            "只有\(train)跑得上去，也只接同一種梁；不能和一般軌道在同一高度交叉，要從上面或下面越過。"
        )
    }

    /// Decision 955: what the network tool says when the stretch would
    /// cross `crossed` at one level and the two are of different systems,
    /// which GameCore refuses (they would share a node); `nil` when they
    /// are of one system, where a diamond may do (decision 887).
    func levelCrossingProblem(across crossed: TrackEdgeID, system: TrackSystem, in world: GameWorld) -> (text: String, brief: String)? {
        guard let other = world.network.edge(crossed), other.system != system else { return nil }
        return (
            language.text(
                "A guideway and other track can't cross on the level. Make this stretch elevated or a tunnel to pass over or under it.",
                "軌道梁和別種軌道不能在同一高度交叉。請把這段改成高架或隧道，從上面或下面越過。"
            ),
            language.text("Can't cross other track on the level", "不能平面交叉")
        )
    }
}

extension GameWorld {
    /// Decision 955: whether a train of `type` may run line `id`'s track
    /// (``TrackCompatibility``): every kind of track it runs on carries
    /// it. A line with no way through yet has no track to say no.
    public func runsOnTrack(_ type: TrainType?, ofLine id: LineID) -> Bool {
        trackKinds(ofLine: id).allSatisfy { TrackCompatibility.runs(type, on: $0) }
    }

    /// Decision 955: the offered type line `id`'s guideway carries, when
    /// it runs on one; `nil` on ordinary track.
    func guidewayType(ofLine id: LineID) -> TrainType? {
        guard let system = trackKinds(ofLine: id).map(\.system).first(where: \.isGuideway) else { return nil }
        return offeredTrainTypes.first { $0.trackSystem == system }
    }

    /// Decision 955: what a player who gives a train `type` is told while
    /// the company has none of its guideway: to lay one first. `nil` for
    /// a type that runs on ordinary track, or once there is one.
    public func guidewayFirstHint(for type: TrainType?, in language: DisplayLanguage) -> String? {
        guard let system = type?.trackSystem, system.isGuideway,
              !network.edges.contains(where: { $0.system == system })
        else { return nil }
        let name = system.name(in: language)
        return language.text(
            " It runs only on its own guideway: lay one first, choosing \(name) in the track tool.",
            "它只能跑自己的軌道梁：請先在鋪軌工具選「\(name)」蓋梁。"
        )
    }
}
