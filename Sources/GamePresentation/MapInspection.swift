import GameCore

// What the select tool shows of track and trains (ARCHITECTURE decision
// 184), besides stations and the company's buildings (decision 173). The
// reference's map shows a train's panel (`Ci/` `openPanelTrain`) but no
// panel for track; the track's lines come from the map's own line layer
// (``LineMap``, MapBuilder's interline segments) and its "signal" from the
// route reservation the trains already run under: this game has no signal
// posts, only track a train holds or has reserved ahead of it.

/// The track the select tool picked: the lines that run along it and
/// whether a train holds it. Derived from the world when shown, never
/// saved.
public struct TrackInspection: Equatable, Sendable {
    /// What the block of track says, as a signal at its entry would.
    public enum Signal: Equatable, Sendable {
        /// No train holds or has reserved any of it: clear.
        case clear
        /// A train has reserved it for its route ahead.
        case reserved(TrainID)
        /// A train stands or runs on it.
        case occupied(TrainID)
    }

    public let edge: TrackEdgeID
    /// The lines whose trains run along it, by ID.
    public let lines: [LineID]
    public let signal: Signal
    public let length: Int64
    public let structure: TrackStructure
}

extension GameWorld {
    /// Edge `id` as the select tool shows it, or `nil` for an edge the
    /// network does not have. A train on the edge is reported before one
    /// that has only reserved it, the first by ID.
    public func trackInspection(of id: TrackEdgeID) -> TrackInspection? {
        trackInspection(of: id, along: LineMap(world: self))
    }

    /// ``trackInspection(of:)`` with the world's line map `lineMap` already
    /// built (``GameSession/trackInspection(of:)`` keeps it).
    func trackInspection(of id: TrackEdgeID, along lineMap: LineMap) -> TrackInspection? {
        guard let edge = network.edge(id) else { return nil }
        var lines: [LineID] = []
        for stretch in lineMap.stretches where stretch.edge == id && !lines.contains(stretch.line) {
            lines.append(stretch.line)
        }
        func touches(_ resources: [TrackResource]) -> Bool {
            resources.contains { resource in
                if case .span(let span) = resource { return span.edge == id }
                return false
            }
        }
        var signal = TrackInspection.Signal.clear
        for train in trains.sorted(by: { $0.id < $1.id }) {
            if touches(occupiedResources(of: train.id)) {
                signal = .occupied(train.id)
                break
            }
            if case .clear = signal, touches(reservedResources(of: train.id)) {
                signal = .reserved(train.id)
            }
        }
        return TrackInspection(edge: id, lines: lines.sorted(), signal: signal, length: edge.length, structure: edge.structure)
    }

    /// "Track #3 · 320 m · Elevated · Lines: Red, Blue · Signal: clear", or
    /// in Chinese "軌段 #3 · 320 公尺 · 高架 · 路線：紅線、藍線 · 號誌：綠燈（無列車）":
    /// since decision 201 with the track's number, the one the line
    /// panel's routes and the map's labels use.
    public func trackInspectionText(of id: TrackEdgeID, in language: DisplayLanguage) -> String? {
        trackInspection(of: id).map { trackInspectionText(of: $0, in: language) }
    }

    /// What ``trackInspectionText(of:in:)`` says of `inspection`.
    func trackInspectionText(of inspection: TrackInspection, in language: DisplayLanguage) -> String {
        let names = inspection.lines.compactMap { line(id: $0)?.name }
        let lines = names.isEmpty
            ? language.text("No line runs here", "沒有路線經過")
            : language.text("Lines: \(names.joined(separator: ", "))", "路線：\(names.joined(separator: "、"))")
        return [
            inspection.edge.displayText(in: language),
            NetworkBuilding.lengthText(inspection.length, in: language),
            inspection.structure.name(in: language),
            lines,
            signalText(inspection.signal, in: language),
        ].joined(separator: " · ")
    }

    /// "Signal: clear", "Signal: caution, reserved for Express", "Signal:
    /// stop, Express on it".
    public func signalText(_ signal: TrackInspection.Signal, in language: DisplayLanguage) -> String {
        switch signal {
        case .clear:
            language.text("Signal: clear", "號誌：綠燈（無列車）")
        case .reserved(let id):
            language.text("Signal: caution, reserved for \(trainName(id))", "號誌：黃燈（\(trainName(id)) 已預留進路）")
        case .occupied(let id):
            language.text("Signal: stop, \(trainName(id)) on it", "號誌：紅燈（\(trainName(id)) 佔用中）")
        }
    }

    private func trainName(_ id: TrainID) -> String {
        train(id: id)?.name ?? "#\(id.rawValue)"
    }

    /// What the select tool adds under a train's summary (decision 184):
    /// its line, how full it is and how it stands against its timetable:
    /// "Line: Red · Load 63% · 5 min late", "路線：紅線 · 滿載率 63% · 誤點
    /// 5 分". `nil` for an unknown train.
    public func trainInspectionText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard train(id: id) != nil else { return nil }
        let line = assignedServiceName(of: id, in: language).map { language.text("Line: \($0)", "路線：\($0)") }
            ?? language.text("No line", "未配屬路線")
        var parts = [line]
        if let load = trainLoadInfo(of: id) {
            parts.append(language.text("Load \(load.percentage)%", "滿載率 \(load.percentage)%"))
        }
        if let punctuality = trainServiceStatus(of: id, in: language)?.punctuality {
            parts.append(punctuality.text(in: language))
        }
        return parts.joined(separator: " · ")
    }
}

extension GameSession {
    /// ``GameWorld/trackInspection(of:)`` for the inspector, which reads it
    /// several times a frame while the game runs: the line map it needs (a
    /// route search a leg of every line) is built once for each
    /// ``commandRevision``, as only a command changes the track and the
    /// lines; the signal is read from the world as it is now.
    public func trackInspection(of id: TrackEdgeID) -> TrackInspection? {
        guard world.network.edge(id) != nil else { return nil }
        return world.trackInspection(of: id, along: commandLineMap())
    }

    /// The world's line map, built once for each ``commandRevision``.
    private func commandLineMap() -> LineMap {
        if let kept = inspectionLineMap, kept.revision == commandRevision { return kept.map }
        let map = LineMap(world: world)
        inspectionLineMap = (commandRevision, map)
        return map
    }

    /// Decision 276: the line a hold at `point` lands on, where no station
    /// is: the lowest numbered line the map draws along the track within
    /// `reach` of it; `nil` off the lines.
    public func lineHeld(at point: PlanPoint, reach: Int64) -> LineID? {
        guard world.bounds.contains(point), let at = world.trackEdgePoint(near: point, within: reach) else { return nil }
        return commandLineMap().stretches
            .filter { $0.edge == at.edge && $0.start <= at.distance && at.distance <= $0.end }
            .map(\.line).min()
    }

    /// Decision 276: holding a line selects it, for the line panel and its
    /// journey trace; the line held, or `nil` off the lines.
    @discardableResult
    public func holdLine(at point: PlanPoint, reach: Int64) -> LineID? {
        guard let id = lineHeld(at: point, reach: reach) else { return nil }
        selectLine(id)
        return id
    }

    /// ``GameWorld/trackInspectionText(of:in:)`` from ``trackInspection(of:)``.
    public func trackInspectionText(of id: TrackEdgeID) -> String? {
        trackInspection(of: id).map { world.trackInspectionText(of: $0, in: language) }
    }
}
