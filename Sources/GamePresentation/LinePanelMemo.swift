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
    private var headwayChanges: [Int64: LineHeadwayChange?] = [:]
    private var shortfall: LineTrainShortfall??
    private var runningHeadway: Int64??

    /// The lines list's train texts, kept for a command and the language
    /// whichever line is selected.
    private struct RowKey: Equatable {
        let session: ObjectIdentifier
        let revision: Int
        let language: DisplayLanguage
    }

    private var rowKey: RowKey?
    private var rowTexts: [LineID: String] = [:]
    /// Mac playtest C2: the lines whose page this memo has had ready
    /// (``prepare(_:headway:of:)``).
    private var preparedLines: Set<LineID> = []

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
        headwayChanges = [:]
        shortfall = nil
        runningHeadway = nil
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

    /// ``GameWorld/lineHeadwayChange(_:headway:)``.
    public func headwayChange(_ id: LineID, headway: Int64, of session: GameSession) -> LineHeadwayChange? {
        keep(id, of: session)
        if let kept = headwayChanges[headway] { return kept }
        let change = session.world.lineHeadwayChange(id, headway: headway)
        headwayChanges[headway] = .some(change)
        return change
    }

    /// ``GameWorld/lineTrainShortfall(_:)``.
    public func trainShortfall(_ id: LineID, of session: GameSession) -> LineTrainShortfall? {
        keep(id, of: session)
        if let kept = shortfall { return kept }
        let found = session.world.lineTrainShortfall(id)
        shortfall = .some(found)
        return found
    }

    /// ``GameWorld/lineRunningHeadway(_:)``.
    public func runningHeadway(_ id: LineID, of session: GameSession) -> Int64? {
        keep(id, of: session)
        if let kept = runningHeadway { return kept }
        let headway = session.world.lineRunningHeadway(id)
        runningHeadway = .some(headway)
        return headway
    }

    /// ``GameWorld/lineTrainsRowText(_:in:)``, for any line of the list.
    public func trainsRowText(_ id: LineID, of session: GameSession) -> String {
        let now = RowKey(session: ObjectIdentifier(session), revision: session.commandRevision, language: session.language)
        if now != rowKey {
            rowKey = now
            rowTexts = [:]
        }
        if let kept = rowTexts[id] { return kept }
        let text = session.world.lineTrainsRowText(id, in: session.language)
        rowTexts[id] = text
        return text
    }

    // MARK: - The page ready before it shows (Mac playtest C2)

    /// What a line's page reads first, worked out together from one world.
    struct Prepared: Sendable {
        let summaries: [LineServiceSummary]
        let journeyText: String?
        let trackCountTexts: [String]
        let coverageTexts: [ServiceLevel: String?]
        let capacityWarning: String?
        let shortfall: LineTrainShortfall?
        let runningHeadway: Int64?
        let rowText: String
        let headwayChange: (headway: Int64, change: LineHeadwayChange?)?

        init(world: GameWorld, line id: LineID, headway: Int64?, language: DisplayLanguage) {
            summaries = world.lineServiceSummaries(id, in: language)
            journeyText = world.lineJourneyText(id, in: language)
            trackCountTexts = world.lineTrackCountTexts(id, in: language)
            coverageTexts = Dictionary(uniqueKeysWithValues: ServiceLevel.allCases.map { ($0, world.lineCoverageText(id, at: $0, in: language)) })
            capacityWarning = world.lineCapacityWarning(id, in: language)
            shortfall = world.lineTrainShortfall(id)
            runningHeadway = world.lineRunningHeadway(id)
            rowText = world.lineTrainsRowText(id, in: language)
            headwayChange = headway.map { ($0, world.lineHeadwayChange(id, headway: $0)) }
        }
    }

    /// Whether this memo has had `id`'s page ready (``prepare(_:headway:of:)``):
    /// until then the page shows its first lines and a wait.
    public func hasPrepared(_ id: LineID) -> Bool {
        preparedLines.contains(id)
    }

    /// Mac playtest C2 (2026-11-08): what `id`'s page reads first (its
    /// services, trains, coverage and headway; some 400 ms of track
    /// searches on the bought Wenhu Line's main actor, the frame rate
    /// down to 5–10 as it opened), worked out off the main actor on the
    /// world as it is now, and kept as if read here when no command
    /// changed the world meanwhile. `headway` is the one the page offers
    /// to staff. Once a line's page has been ready it is read as before.
    public func prepare(_ id: LineID, headway: Int64?, of session: GameSession) async {
        guard !preparedLines.contains(id) else { return }
        let (world, language, revision) = (session.world, session.language, session.commandRevision)
        let worked = await Task.detached(priority: .userInitiated) {
            Prepared(world: world, line: id, headway: headway, language: language)
        }.value
        defer { preparedLines.insert(id) }
        // A command since: the page works out what it reads itself.
        guard session.commandRevision == revision, session.language == language else { return }
        keep(id, of: session)
        if summaries == nil { summaries = worked.summaries }
        if journeyText == nil { journeyText = .some(worked.journeyText) }
        if trackCountTexts == nil { trackCountTexts = worked.trackCountTexts }
        for (level, text) in worked.coverageTexts where coverageTexts[level] == nil { coverageTexts[level] = .some(text) }
        if capacityWarning == nil { capacityWarning = .some(worked.capacityWarning) }
        if shortfall == nil { shortfall = .some(worked.shortfall) }
        if runningHeadway == nil { runningHeadway = .some(worked.runningHeadway) }
        if let change = worked.headwayChange, headwayChanges[change.headway] == nil { headwayChanges[change.headway] = .some(change.change) }
        let row = RowKey(session: ObjectIdentifier(session), revision: revision, language: language)
        if row != rowKey {
            rowKey = row
            rowTexts = [:]
        }
        if rowTexts[id] == nil { rowTexts[id] = worked.rowText }
    }
}
