import GameCore

// The new line's draft in one line (City Transport Manager study, 4.2,
// step M0): "3 stops · 4.2 km · about 6 min · $ 1,200,000" at the top of
// the draft, so the player sees what the line will be while picking its
// stations, not after it is made. Every figure is what the world already
// knows: the path and running time a line through the stops would have
// (``GameWorld/lineJourney(_:pattern:)``, the trial line
// ``StationPairComparison`` drives too) and what opening it costs under
// simple rules (``GameSession/lineOpeningPreview``). Where no track joins
// the stations picked, the line says why instead (decision 284).

/// The one line over the new line's draft (``GameSession/lineDraftSummary``).
public struct LineDraftSummary: Equatable, Sendable {
    /// "3 stops · 4.2 km · about 6 min · $ 1,200,000", or what to tap
    /// next, or why no track joins the stations picked.
    public let text: String
    /// Whether ``text`` says why the line cannot run yet: drawn in the
    /// warning colour.
    public let isProblem: Bool

    public init(text: String, isProblem: Bool) {
        self.text = text
        self.isProblem = isProblem
    }
}

/// How far a train runs from a line's first call to its last, and in how
/// long, with a new line's own performance.
struct LineDraftRun: Equatable {
    /// World units along the track, out.
    let distance: Int64
    /// Seconds out: every leg, and the dwell at each call between the ends.
    let seconds: Int64
}

extension GameWorld {
    /// How far and how long one way a line calling at `stops` would run,
    /// as its trains would drive it; `nil` when no such line can be made
    /// or driven.
    func lineDraftRun(stops: [StationID]) -> LineDraftRun? {
        var trial = self
        guard let line = try? trial.createLine(named: "Route", stops: stops),
              let journey = trial.lineJourney(line.id) else { return nil }
        let out = journey.legs.prefix(stops.count - 1)
        let dwells = Int64(max(0, stops.count - 2)) * journey.dwellSeconds
        return LineDraftRun(
            distance: out.reduce(0) { $0 + $1.path.distance },
            seconds: out.reduce(0) { $0 + $1.seconds } + dwells
        )
    }

    /// The draft's line when no track joins the stations picked: which
    /// station, or which two, in a few words (the full sentence is
    /// ``lineDraftGapText(_:in:)``).
    func lineDraftGapSummary(_ gap: LineDraftGap, in language: DisplayLanguage) -> String {
        switch gap {
        case .noPlatform(let id):
            let name = stationName(id)
            return language.text("\(name) has no platform yet", "\(name) 還沒有月台")
        case .separateTracks(let a, let b):
            let first = stationName(a), second = stationName(b)
            return language.text(
                "The platforms of \(first) and \(second) are not on joined track",
                "\(first) 和 \(second) 的月台不在相連的軌道上"
            )
        case .noWay:
            return language.text("No track joins these stations yet", "這些車站之間還沒有軌道相連")
        }
    }
}

struct LineDraftSummaryMemo {
    struct Key: Equatable {
        let stops: [StationID]
        let picked: Int
        let gap: LineDraftGap?
        let revision: Int
        let language: DisplayLanguage
    }

    let key: Key
    let summary: LineDraftSummary
}

extension GameSession {
    /// The one line over the new line's draft: how many stations it calls
    /// at, how long it is, how long a train takes from end to end and,
    /// under simple rules, what opening it costs; with one station picked,
    /// what to tap next; where no track joins the stations picked, why
    /// (decision 284). `nil` while no line is being picked. Worked out once
    /// for each draft and command (not at every tick).
    public var lineDraftSummary: LineDraftSummary? {
        guard isPickingLineStops || !lineDraft.isEmpty else { return nil }
        let stops = lineDraftStops
        let key = LineDraftSummaryMemo.Key(
            stops: stops, picked: lineDraft.count, gap: lineDraftGap, revision: commandRevision, language: language
        )
        if let memo = lineDraftSummaryMemo, memo.key == key { return memo.summary }
        let summary = workOutLineDraftSummary(stops: stops)
        lineDraftSummaryMemo = LineDraftSummaryMemo(key: key, summary: summary)
        return summary
    }

    private func workOutLineDraftSummary(stops: [StationID]) -> LineDraftSummary {
        switch lineDraft.count {
        case 0:
            return LineDraftSummary(text: language.text("Tap the line's first station", "點路線的第一站"), isProblem: false)
        case 1:
            return LineDraftSummary(
                text: language.text("1 stop · tap the line's next station", "1 站 · 點路線的下一站"), isProblem: false
            )
        default:
            break
        }
        if let gap = lineDraftGap {
            return LineDraftSummary(text: world.lineDraftGapSummary(gap, in: language), isProblem: true)
        }
        // The stations it reaches: a line back to where it started, or
        // back through a station, calls there twice.
        let returns = stops.count > 2 && stops.first == stops.last
        let count = Set(stops).count
        var parts = [returns
            ? language.text("\(count) stops, back to the start", "\(count) 站（回到起點）")
            : language.text("\(count) stops", "\(count) 站")]
        if let run = world.lineDraftRun(stops: stops), run.distance > 0 {
            let minutes = max(1, (run.seconds + 30) / GameTime.secondsPerMinute)
            parts.append(StationPairComparison.kilometres(run.distance / WorldCoordinate.unitsPerMetre))
            parts.append(language.text("about \(minutes) min", "約 \(minutes) 分"))
        }
        if let opening = lineOpeningPreview, opening.cost.amount > 0 {
            parts.append(opening.cost.moneyText)
        }
        return LineDraftSummary(text: parts.joined(separator: " · "), isProblem: false)
    }
}
