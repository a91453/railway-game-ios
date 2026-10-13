import GameCore

/// What the line panel shows of its selected line that only a command
/// changes (decision 184, later): its services, each leg's route choices,
/// its journey, its tracks, the stretches no service covers and what
/// staffing it takes. They search the track, hundreds of milliseconds a
/// draw on the high-speed demo, and the panel is drawn again at every tick
/// while the game runs. Each is worked out once for a
/// ``GameSession/commandRevision``, the selected line and the language,
/// and read back the same until one of them changes, as
/// ``GameSession/trackInspection(of:)`` keeps its line map. What a tick
/// does change, the trains on a trip, is counted from the world as it is
/// now.
///
/// The view keeps one for as long as it is shown; it is not game state.
@MainActor
public final class LinePanelMemo {
    private struct Key: Equatable {
        let session: ObjectIdentifier
        let revision: Int
        let line: LineID
        let language: DisplayLanguage
    }

    private struct Leg: Hashable {
        let pattern: Int?
        let from: Int
        let to: Int
    }

    private struct Staffing: Hashable {
        let headway: Int64
        let type: TrainType?
        let cars: Int
    }

    private var key: Key?
    private var summaries: [LineServiceSummary]?
    private var routeChoices: [Leg: [LineRoutePreference]] = [:]
    private var journeyText: String??
    private var trackCountTexts: [String]?
    private var coverageTexts: [ServiceLevel: String?] = [:]
    private var staffingPlans: [Staffing: LineStaffingPlan?] = [:]
    private var capacityWarning: String??

    public init() {}

    /// Starts again when the session, a command, the line or the language
    /// has changed since what is kept was worked out.
    private func keep(_ line: LineID, of session: GameSession) {
        let now = Key(session: ObjectIdentifier(session), revision: session.commandRevision, line: line, language: session.language)
        guard now != key else { return }
        key = now
        summaries = nil
        routeChoices = [:]
        journeyText = nil
        trackCountTexts = nil
        coverageTexts = [:]
        staffingPlans = [:]
        capacityWarning = nil
    }

    /// ``GameWorld/lineServiceSummaries(_:in:)``, with the trains on a trip
    /// counted as they are now.
    public func serviceSummaries(_ id: LineID, of session: GameSession) -> [LineServiceSummary] {
        keep(id, of: session)
        let world = session.world
        let kept = summaries ?? world.lineServiceSummaries(id, in: session.language)
        summaries = kept
        guard let line = world.line(id: id) else { return kept }
        return kept.map { summary in
            let trains = summary.pattern.map { line.patterns[$0].trains } ?? line.trains
            return LineServiceSummary(
                pattern: summary.pattern,
                title: summary.title,
                callsText: summary.callsText,
                levels: summary.levels,
                assigned: summary.assigned,
                running: trains.count { world.train(id: $0)?.execution != nil }
            )
        }
    }

    /// ``GameWorld/lineRouteChoices(_:from:to:pattern:)``.
    public func routeChoices(_ id: LineID, from: Int, to: Int, pattern: Int?, of session: GameSession) -> [LineRoutePreference] {
        keep(id, of: session)
        let leg = Leg(pattern: pattern, from: from, to: to)
        if let kept = routeChoices[leg] { return kept }
        let choices = session.world.lineRouteChoices(id, from: from, to: to, pattern: pattern)
        routeChoices[leg] = choices
        return choices
    }

    /// ``GameWorld/lineJourneyText(_:in:)``.
    public func journeyText(_ id: LineID, of session: GameSession) -> String? {
        keep(id, of: session)
        if let kept = journeyText { return kept }
        let text = session.world.lineJourneyText(id, in: session.language)
        journeyText = .some(text)
        return text
    }

    /// ``GameWorld/lineTrackCountTexts(_:in:)``.
    public func trackCountTexts(_ id: LineID, of session: GameSession) -> [String] {
        keep(id, of: session)
        if let kept = trackCountTexts { return kept }
        let texts = session.world.lineTrackCountTexts(id, in: session.language)
        trackCountTexts = texts
        return texts
    }

    /// ``GameWorld/lineCoverageText(_:at:in:)``.
    public func coverageText(_ id: LineID, at level: ServiceLevel, of session: GameSession) -> String? {
        keep(id, of: session)
        if let kept = coverageTexts[level] { return kept }
        let text = session.world.lineCoverageText(id, at: level, in: session.language)
        coverageTexts[level] = .some(text)
        return text
    }

    /// ``GameWorld/lineStaffingPlan(_:headway:type:cars:)``.
    public func staffingPlan(_ id: LineID, headway: Int64, type: TrainType?, cars: Int, of session: GameSession) -> LineStaffingPlan? {
        keep(id, of: session)
        let staffing = Staffing(headway: headway, type: type, cars: cars)
        if let kept = staffingPlans[staffing] { return kept }
        let plan = session.world.lineStaffingPlan(id, headway: headway, type: type, cars: cars)
        staffingPlans[staffing] = .some(plan)
        return plan
    }

    /// ``GameWorld/lineCapacityWarning(_:in:)``.
    public func capacityWarning(_ id: LineID, of session: GameSession) -> String? {
        keep(id, of: session)
        if let kept = capacityWarning { return kept }
        let text = session.world.lineCapacityWarning(id, in: session.language)
        capacityWarning = .some(text)
        return text
    }
}
