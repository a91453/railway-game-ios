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
        guard let edge = network.edge(id) else { return nil }
        var lines: [LineID] = []
        for stretch in LineMap(world: self).stretches where stretch.edge == id && !lines.contains(stretch.line) {
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

    /// "Track · 320 m · Elevated · Lines: Red, Blue · Signal: clear", or
    /// in Chinese "軌道 · 320 公尺 · 高架 · 路線：紅線、藍線 · 號誌：綠燈（無列車）".
    public func trackInspectionText(of id: TrackEdgeID, in language: DisplayLanguage) -> String? {
        guard let inspection = trackInspection(of: id) else { return nil }
        let names = inspection.lines.compactMap { line(id: $0)?.name }
        let lines = names.isEmpty
            ? language.text("No line runs here", "沒有路線經過")
            : language.text("Lines: \(names.joined(separator: ", "))", "路線：\(names.joined(separator: "、"))")
        return [
            language.text("Track", "軌道"),
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
