import GameCore

// Decision 912 (CROSS-PLATFORM-TRANSFER): what the station panel and the
// platform picker say about changing lines at a station. The rule is
// GameCore's (``GameWorld/platformChange(from:to:)``); this only gathers
// it for the screen: which lines stop at each platform, and for each two
// lines that call here how long the change takes.

/// Decision 912: the changes between the lines that call at one station.
public struct StationTransfers: Equatable, Sendable {
    /// Two lines that both call here, and the quickest and slowest change
    /// between them over the ways each runs.
    public struct Pair: Equatable, Sendable, Identifiable {
        public let first: LineID
        public let second: LineID
        public let firstName: String
        public let secondName: String
        public let quickest: PlatformChange
        public let slowest: PlatformChange

        public var id: [LineID] { [first, second] }

        /// "Line 1 ⇄ Line 2".
        public var title: String { "\(firstName) ⇄ \(secondName)" }

        /// "Across the platform, 1 min", with the slowest way when it is
        /// another: "; other way: another level, 4 min".
        public func text(in language: DisplayLanguage) -> String {
            let best = StationTransfers.text(of: quickest, in: language)
            let worst = StationTransfers.text(of: slowest, in: language)
            guard worst != best else { return best }
            return language.text("\(best); other way: \(worst)", "\(best)；另一方向\(worst)")
        }
    }

    public let pairs: [Pair]
    /// For each of the station's platforms that a line names, the lines
    /// whose trains stop there, in line order.
    public let linesAt: [TrackPlatform: [LineID]]

    public init(world: GameWorld, station: StationID) {
        let calls = world.platformCalls(at: station)
        var linesAt: [TrackPlatform: [LineID]] = [:]
        for call in calls {
            guard let platform = call.platform else { continue }
            if !(linesAt[platform] ?? []).contains(call.line) { linesAt[platform, default: []].append(call.line) }
        }
        let lines = calls.reduce(into: [LineID]()) { if !$0.contains($1.line) { $0.append($1.line) } }
        func name(_ id: LineID) -> String { world.line(id: id)?.name ?? "" }
        var pairs: [Pair] = []
        for (index, first) in lines.enumerated() {
            for second in lines.dropFirst(index + 1) {
                let from = calls.filter { $0.line == first }
                let to = calls.filter { $0.line == second }
                var changes: [PlatformChange] = []
                for a in from {
                    for b in to {
                        guard let p = a.platform, let q = b.platform else {
                            changes.append(.unknown)
                            continue
                        }
                        changes.append(world.platformChange(from: p, to: q) ?? .unknown)
                    }
                }
                guard let quickest = changes.min(by: Self.isQuicker), let slowest = changes.max(by: Self.isQuicker) else { continue }
                pairs.append(Pair(first: first, second: second, firstName: name(first), secondName: name(second),
                                  quickest: quickest, slowest: slowest))
            }
        }
        self.pairs = pairs
        self.linesAt = linesAt
    }

    /// The quicker change: the one passengers can board sooner after, then
    /// the one weighed lighter in route choice.
    static func isQuicker(_ a: PlatformChange, _ b: PlatformChange) -> Bool {
        (a.minimumSeconds, a.penaltySeconds) < (b.minimumSeconds, b.penaltySeconds)
    }

    /// Whole minutes, rounded up, at least 1.
    static func minutes(_ seconds: Int64) -> Int64 {
        max(1, (seconds + 59) / 60)
    }

    /// "Across the platform, 1 min", "Over a footbridge, 3 min",
    /// "Another level, 5 min", or for a line that names no platform
    /// "Platform not set, 2 min".
    public static func text(of change: PlatformChange, in language: DisplayLanguage) -> String {
        let m = minutes(change.minimumSeconds)
        return switch change.kind {
        case .acrossPlatform: language.text("Across the platform, \(m) min", "對面換乘 \(m) 分")
        case .sameLevel: language.text("Over a footbridge, \(m) min", "走天橋 \(m) 分")
        case .otherLevel: language.text("Another level, \(m) min", "跨層 \(m) 分")
        case .unspecified: language.text("Platform not set, \(m) min", "沒指定月台 \(m) 分")
        }
    }

    /// Decision 912, the platform picker: what choosing `platform` for
    /// line `line` makes of its changes with the other lines that name a
    /// platform here, the quickest for each: "Across from Line 2",
    /// "Same level as Line 3", "Another level from Line 4". Empty when no
    /// other line names one.
    public static func notes(world: GameWorld, choosing platform: TrackPlatform, for line: LineID,
                             in language: DisplayLanguage) -> [String] {
        var best: [LineID: PlatformChange] = [:]
        var order: [LineID] = []
        for call in world.platformCalls(at: platform.station) where call.line != line {
            guard let other = call.platform, let change = world.platformChange(from: platform, to: other) else { continue }
            if best[call.line] == nil { order.append(call.line) }
            if let known = best[call.line], !isQuicker(change, known) { continue }
            best[call.line] = change
        }
        return order.compactMap { id in
            guard let change = best[id], let name = world.line(id: id)?.name else { return nil }
            return switch change.kind {
            case .acrossPlatform: language.text("Across from \(name)", "和\(name)對面")
            case .sameLevel: language.text("Same level as \(name)", "和\(name)同層")
            case .otherLevel: language.text("Another level from \(name)", "和\(name)不同層")
            case .unspecified: nil
            }
        }
    }
}

extension GameSession {
    /// Decision 912: ``RoutePreview/choiceTexts(_:in:)`` of a leg's route
    /// choices for line `line`, each followed by what its platform makes of
    /// the changes with the other lines there ("Tracks #5 (platform) ·
    /// Across from Line 2").
    public func routeChoiceTexts(_ choices: [LineRoutePreference], line: LineID) -> [String] {
        let texts = RoutePreview.choiceTexts(choices, in: language)
        return zip(choices, texts).map { choice, text in
            let notes = StationTransfers.notes(world: world, choosing: choice.platform, for: line, in: language)
            return notes.isEmpty ? text : "\(text) · \(notes.joined(separator: language.text(", ", "、")))"
        }
    }

    /// Decision 912: what the platform `preference` names makes of line
    /// `line`'s changes there, or `nil` for none (or no preference).
    public func platformTransferNote(_ preference: LineRoutePreference?, line: LineID) -> String? {
        guard let preference else { return nil }
        let notes = StationTransfers.notes(world: world, choosing: preference.platform, for: line, in: language)
        return notes.isEmpty ? nil : notes.joined(separator: language.text(", ", "、"))
    }
}
