import GameCore

// The line panel's choice of how a line's trains leave (ARCHITECTURE
// decision 309; TestFlight 77.1 #1): evenly apart, from both ends at once,
// or in pairs a few minutes apart.

/// One choice of how a line's trains leave, with what the panel says of it.
public struct LineDispatchPatternChoice: Hashable, Sendable, Identifiable {
    public let pattern: DispatchPattern
    public var id: DispatchPattern { pattern }

    /// The staggers the menu offers, in minutes.
    public static let staggers: [Int64] = [2, 3, 5, 10, 15, 20, 30]

    public func title(in language: DisplayLanguage) -> String {
        switch pattern {
        case .even: language.text("Evenly apart", "平均錯開")
        case .fromBothEnds: language.text("From both ends at once", "兩端對開")
        case .staggered(let minutes): language.text("Second train \(minutes) min later", "第二列晚 \(minutes) 分")
        }
    }
}

extension GameSession {
    /// The ways the selected line's trains can leave (decision 309), for
    /// the line panel: none for a ring or a line with a timetable of its
    /// own, which keep theirs; both ends only where a train can be sent out
    /// from the last stop.
    public var selectedLineDispatchChoices: [LineDispatchPatternChoice] {
        guard let line = selectedLine, !line.isRing, !line.hasRuns else { return [] }
        let patterns: [DispatchPattern] = [.even] + (world.flexDispatch ? [.fromBothEnds] : [])
            + LineDispatchPatternChoice.staggers.map { .staggered(minutes: $0) }
        return patterns.map(LineDispatchPatternChoice.init)
    }

    /// What the panel says under the choice, in a sentence: what the
    /// selected line's trains do with it.
    public func dispatchPatternFooter(_ pattern: DispatchPattern) -> String {
        switch pattern {
        case .even:
            language.text("Trains leave one after another, evenly apart.", "列車一班接一班，平均錯開發車。")
        case .fromBothEnds:
            language.text(
                "Half the trains wait at the last station, and trains leave both ends at the same time.",
                "一半的車在終點站等，兩端同時發車。"
            )
        case .staggered(let minutes):
            language.text(
                "Trains leave in pairs: the second \(minutes) min after the first.",
                "列車兩列一組，第二列晚 \(minutes) 分發車。"
            )
        }
    }

    /// Sets how the selected line's trains leave (decision 309).
    public func setSelectedLineDispatchPattern(_ pattern: DispatchPattern) {
        guard let line = requireSelectedLine() else { return }
        let title = LineDispatchPatternChoice(pattern: pattern).title(in: language)
        perform(.setLineDispatchPattern(line.id, pattern)) { _, _, _ in
            language.text("\(line.name): \(title.lowercased()).", "\(line.name)：\(title)。")
        }
    }
}
