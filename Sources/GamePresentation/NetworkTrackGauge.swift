import GameCore

// Decision 970: the network tool's gauge (`TrackEdge.gauge`), chosen
// before ordinary track is laid, and what the menus and messages say
// about it.

extension TrackGauge {
    /// What it is, for the network tool's menu: its rails, and whom they
    /// carry.
    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .cape: return language.text("1,067 mm (Taiwan Railway, Japanese lines)", "1,067 mm（台鐵、日本在來線）")
        case .standard: return language.text("1,435 mm (metro, light rail, mini-Shinkansen)", "1,435 mm（捷運、輕軌、迷你新幹線）")
        case .shinkansen: return language.text("1,435 mm high-speed (wide trains)", "1,435 mm 高鐵（新幹線車寬）")
        case .forest: return language.text("762 mm (forest railway)", "762 mm（林鐵）")
        case .broad: return language.text("1,524 mm (Finland)", "1,524 mm（芬蘭）")
        default:
            let rails = sortedRails.map { Self.millimetres($0.rawValue) }.joined(separator: " + ")
            return loading == .shinkansen
                ? language.text("\(rails) mm high-speed", "\(rails) mm 高鐵")
                : language.text("\(rails) mm", "\(rails) mm")
        }
    }

    /// What the network tool's gauge button says once it is chosen: the
    /// millimetres alone, on one line (NETWORK-PANEL-SIMPLE: the whole
    /// name took two lines in a narrow card and ran over the buttons
    /// below). The menu still says whom each carries.
    public func shortName(in language: DisplayLanguage) -> String {
        let rails = sortedRails.map { Self.millimetres($0.rawValue) }.joined(separator: " + ")
        return loading == .shinkansen
            ? language.text("\(rails) mm high-speed", "\(rails) mm 高鐵")
            : "\(rails) mm"
    }

    /// `1435` as "1,435".
    static func millimetres(_ value: Int) -> String {
        value >= 1_000 ? "\(value / 1_000),\(String(value % 1_000).leftPadded(to: 3))" : "\(value)"
    }

    /// The tool's first choice: the gauge of the track a stretch joins.
    public static func automaticName(in language: DisplayLanguage) -> String {
        language.text("Automatic (as the track it joins)", "自動（跟接上的軌道一樣）")
    }

    /// ``automaticName(in:)`` on the gauge button.
    public static func automaticShortName(in language: DisplayLanguage) -> String {
        language.text("Auto gauge", "自動軌距")
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}

extension GameSession {
    /// Decision 970: lays the next stretches of ordinary track at `gauge`;
    /// `nil` at that of the track each joins.
    public func chooseNetworkGauge(_ gauge: TrackGauge?) {
        guard gauge != networkGauge else { return }
        networkGauge = gauge
    }
}

extension GameWorld {
    /// Decision 970: what a player who gives a train `type` is told while
    /// no ordinary track of the company carries it: to lay track of its
    /// gauge first. `nil` for a type of no real model, a guideway's, or
    /// once some track carries it.
    public func gaugeFirstHint(for type: TrainType?, in language: DisplayLanguage) -> String? {
        guard let wheels = type?.gauge,
              !network.edges.contains(where: { !$0.system.isGuideway && wheels.runs(on: $0.gauge) }),
              let gauge = TrackGauge.offered.first(where: { wheels.runs(on: $0) })
        else { return nil }
        let name = gauge.name(in: language)
        return language.text(
            " It needs track of its own gauge: lay some first, choosing \(name) in the track tool.",
            "它要跑自己軌距的軌道：請先在鋪軌工具選「\(name)」鋪軌。"
        )
    }
}

extension Array where Element == PlayerCommand.TrackStretch {
    /// Decision 970: a chain of stretches none of which has a gauge of its
    /// own, each given that of the ordinary track the chain starts or ends
    /// at in `world`: laid one after another from its start, the edges
    /// before the last would otherwise join nothing and be laid at the
    /// default. Mountain track keeps its own; unchanged when it joins no
    /// ordinary track or a stretch has a gauge.
    func joiningGauge(in world: GameWorld) -> [PlayerCommand.TrackStretch] {
        guard allSatisfy({ $0.gauge == nil }) else { return self }
        func gauge(at anchor: NetworkAnchor?) -> TrackGauge? {
            switch anchor {
            case .node(let id)?: return world.network.gauge(at: id)
            case .track(let point)?:
                guard let edge = world.network.edge(point.edge), !edge.system.isGuideway else { return nil }
                return edge.gauge
            case .point?, nil: return nil
            }
        }
        guard let joined = gauge(at: first?.start) ?? gauge(at: last?.end) else { return self }
        return map { stretch in
            guard !stretch.mountain else { return stretch }
            return PlayerCommand.TrackStretch(
                start: stretch.start, end: stretch.end, from: stretch.from, to: stretch.to, curve: stretch.curve, profile: stretch.profile,
                structure: stretch.structure, ground: stretch.ground, mountain: stretch.mountain, system: stretch.system, gauge: joined
            )
        }
    }
}
