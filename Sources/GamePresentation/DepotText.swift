import GameCore

// The depot's panels and status (decision 214, on decision 209's depots):
// the station panel's "Make a depot" switch, the line panel's checklist of
// depots (decision 221: a line may have several), and what a train on its
// way to or from one, or standing in it, shows in the follow bar, its card
// and the fleet list. Everything is read from the world each time; the
// switches are `GameWorld` commands (`setStationDepot`, `setLineDepots`)
// the command log keeps.

/// Where a line's train stands with its depot (decision 209): on its way
/// out to the line, on its way in, or standing there out of service.
public enum TrainDepotState: Hashable, Sendable {
    case pullingOut
    case pullingIn
    case inDepot

    /// "Leaving depot" (出庫中), "Entering depot" (入庫中), "In depot" (在庫).
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .pullingOut: language.text("Leaving depot", "出庫中")
        case .pullingIn: language.text("Entering depot", "入庫中")
        case .inDepot: language.text("In depot", "在庫")
        }
    }
}

extension GameWorld {
    /// Where train `id` stands with a depot, or `nil` when it is nowhere
    /// near one: an empty run (decision 172) that starts at a depot is
    /// leaving it, one that ends at a depot entering it, and a train with
    /// no service stopped at a depot's platform stands in it.
    public func depotState(of id: TrainID) -> TrainDepotState? {
        guard stations.contains(where: \.isDepot), let train = train(id: id) else { return nil }
        if train.execution != nil {
            guard train.isDeadheading else { return nil }
            if let last = train.timetable.last, station(id: last.station)?.isDepot == true { return .pullingIn }
            if let first = train.timetable.first, station(id: first.station)?.isDepot == true { return .pullingOut }
            return nil
        }
        return stationsStoppedAt(by: id).contains { station(id: $0)?.isDepot == true } ? .inDepot : nil
    }

    /// The trains on their way out of a depot or into one, for the map's
    /// plate over each (`docs/MAP_LAYERS.md` layer 51); empty without a
    /// depot, as in every world before decision 209.
    public func depotRuns() -> [TrainID: TrainDepotState] {
        guard stations.contains(where: \.isDepot) else { return [:] }
        var runs: [TrainID: TrainDepotState] = [:]
        for train in trains where train.isDeadheading {
            if let state = depotState(of: train.id), state != .inDepot { runs[train.id] = state }
        }
        return runs
    }

    /// How many of line `id`'s trains stand in a depot now: the line
    /// panel's "in depot" badge.
    public func trainsInDepot(of id: LineID) -> Int {
        guard line(id: id)?.depot != nil else { return 0 }
        return trains.count { assignedLine(of: $0.id) == id && depotState(of: $0.id) == .inDepot }
    }
}

/// The station panel's depot switch for a station: whether it is a depot
/// now, and why it cannot change, if it cannot.
public struct StationDepotSwitch: Hashable, Sendable {
    public let isDepot: Bool
    /// Why the switch is off limits (a line stops here, or keeps its
    /// trains here); `nil` when it may be tried. GameCore still has the
    /// last word: a depot that would leave a line without a way along its
    /// stops is refused on the tap (``GameError/depotBlocksLine(_:)``).
    public let problem: String?

    /// "Make a depot" or "Stop being a depot".
    public func title(in language: DisplayLanguage) -> String {
        isDepot ? language.text("Stop being a depot", "取消機廠") : language.text("Make a depot", "設為機廠")
    }

    /// What a depot is, under the switch.
    public static func note(in language: DisplayLanguage) -> String {
        language.text(
            "A depot keeps a line's trains out of service: they leave it before the first train and go back after the last. No line stops there, and no line runs over its sidings.",
            "機廠是路線的列車停放的地方：首班前出庫、收班後入庫。機廠不載客，路線不能停靠，也不能走它的停車線。"
        )
    }
}

/// A depot a line may keep its trains at: a row of the line panel's
/// checklist, ticked when the line uses it.
public struct LineDepotChoice: Hashable, Sendable, Identifiable {
    public let station: StationID
    public let name: String
    public let isChosen: Bool

    public var id: StationID { station }
}

/// The line panel's depots: every depot, nearest the line's ends first,
/// each ticked when the line uses it, or why there is none to choose.
public struct LineDepotRow: Hashable, Sendable {
    /// The line's depots, in the order it keeps them; empty for none.
    public let chosen: [StationID]
    public let choices: [LineDepotChoice]
    /// Why the line cannot choose a depot: there is none yet. A line that
    /// runs to a timetable chooses one too (decision 221).
    public let problem: String?
    /// The line's trains standing in its depot now.
    public let inDepot: Int
}

extension GameSession {
    /// The selected station's depot switch, or `nil` with no station
    /// selected.
    public var selectedStationDepotSwitch: StationDepotSwitch? {
        guard let station = selectedStation else { return nil }
        return world.depotSwitch(of: station.id, in: language)
    }

    /// Makes the selected station a depot, or an ordinary station again
    /// (decision 209), saying why when GameCore refuses.
    public func setSelectedStationDepot(_ isDepot: Bool) {
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station on the map first.", "請先在地圖上選擇車站。"))
            return
        }
        if let problem = world.depotSwitch(of: station.id, in: language).problem, isDepot != station.isDepot {
            message = StatusMessage(kind: .failure, text: problem)
            return
        }
        let done = perform(.setStationDepot(station.id, isDepot)) { _, _, _ in
            isDepot
                ? language.text(
                    "\(station.name) is now a depot. Choose it as a line's depot on the line panel.",
                    "「\(station.name)」現在是機廠。到路線面板替路線選這個機廠。"
                )
                : language.text("\(station.name) is an ordinary station again.", "「\(station.name)」不再是機廠。")
        }
        // Decision 209's own message names no line: say which.
        if done == nil, let line = world.lineBlockedByDepot(station.id) {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(line) would have no way along its stops: no line runs over a depot's sidings.",
                "設成機廠會讓「\(line)」開不通：路線不能走機廠的停車線。"
            ))
        }
    }

    /// The selected line's depot row, or `nil` with no line selected.
    public var selectedLineDepotRow: LineDepotRow? {
        guard let line = selectedLine else { return nil }
        return world.depotRow(of: line.id, in: language)
    }

    /// Ticks depot `depot` for the selected line, or unticks it (decision
    /// 221): the line keeps its trains at every ticked depot, nearest its
    /// ends first, and at its ends with none ticked.
    public func toggleSelectedLineDepot(_ depot: StationID) {
        guard let line = selectedLine, let row = world.depotRow(of: line.id, in: language) else {
            message = StatusMessage(kind: .failure, text: language.text("Select a line first.", "請先選擇路線。"))
            return
        }
        var ticked = Set(row.chosen)
        let adding = ticked.insert(depot).inserted
        if !adding { ticked.remove(depot) }
        let depots = row.choices.map(\.station).filter(ticked.contains)
        let depotName = world.station(id: depot)?.name ?? ""
        perform(.setLineDepots(line.id, depots)) { _, _, _ in
            if depots.isEmpty {
                return language.text("\(line.name)'s trains now stay at its ends.", "「\(line.name)」的列車現在停在路線兩端。")
            }
            if !adding {
                return language.text("\(line.name)'s trains no longer go to the depot \(depotName).", "「\(line.name)」的列車不再回機廠「\(depotName)」。")
            }
            return depots.count == 1
                ? language.text(
                    "\(line.name) now keeps its trains at the depot \(depotName): they leave it before the first train and go back after the last.",
                    "「\(line.name)」的列車現在停機廠「\(depotName)」：首班前出庫、收班後入庫。"
                )
                : language.text(
                    "\(line.name)'s trains now go to the depot \(depotName) too: each goes back to the nearest.",
                    "「\(line.name)」的列車現在也會回機廠「\(depotName)」：每列車回最近的那一個。"
                )
        }
    }
}

extension GameWorld {
    /// The depot switch of station `id` (``StationDepotSwitch``).
    func depotSwitch(of id: StationID, in language: DisplayLanguage) -> StationDepotSwitch {
        let isDepot = station(id: id)?.isDepot == true
        func names(_ found: [ServiceLine]) -> String {
            found.map { "「\($0.name)」" }.joined(separator: language.text(", ", "、"))
        }
        if isDepot {
            let using = lines.filter { $0.depots.contains(id) }
            guard using.isEmpty else {
                let english = using.map(\.name).joined(separator: ", ")
                return StationDepotSwitch(isDepot: true, problem: language.text(
                    "\(english) \(using.count == 1 ? "keeps its" : "keep their") trains here: untick it on the line panel first.",
                    "\(names(using))把列車停在這裡：先到路線面板取消勾選這個機廠。"
                ))
            }
            return StationDepotSwitch(isDepot: true, problem: nil)
        }
        let stopping = lines.filter { $0.stops.contains(id) }
        guard stopping.isEmpty else {
            let english = stopping.map(\.name).joined(separator: ", ")
            return StationDepotSwitch(isDepot: false, problem: language.text(
                "\(english) \(stopping.count == 1 ? "stops" : "stop") here: a depot takes no passengers. Take the station off \(stopping.count == 1 ? "that line's" : "those lines'") stops first.",
                "\(names(stopping))停靠這裡：機廠不載客，先把這站從路線的停靠站拿掉。"
            ))
        }
        return StationDepotSwitch(isDepot: false, problem: nil)
    }

    /// The line a depot at station `id` would leave without a way along
    /// its stops (``GameError/depotBlocksLine(_:)``), by name.
    func lineBlockedByDepot(_ id: StationID) -> String? {
        var changed = self
        do throws(GameError) {
            try changed.setStationDepot(id, to: true)
            return nil
        } catch {
            guard case .depotBlocksLine(let line) = error else { return nil }
            return self.line(id: line)?.name
        }
    }

    /// The depot row of line `id` (``LineDepotRow``): every depot, nearest
    /// the line's ends first, by the crow's flight.
    func depotRow(of id: LineID, in language: DisplayLanguage) -> LineDepotRow? {
        guard let line = line(id: id) else { return nil }
        let inDepot = trainsInDepot(of: id)
        let ends = [line.stops.first, line.stops.last].compactMap { $0.flatMap(station(id:))?.point }
        let depots = stations.filter(\.isDepot).map { depot -> (station: Station, distance: Int64) in
            let distance = ends.map { end -> Int64 in
                let dx = Double(end.x - depot.point.x), dy = Double(end.y - depot.point.y)
                return Int64((dx * dx + dy * dy).squareRoot().rounded())
            }.min() ?? 0
            return (depot, distance)
        }.sorted { ($0.distance, $0.station.id.rawValue) < ($1.distance, $1.station.id.rawValue) }
        guard !depots.isEmpty else {
            return LineDepotRow(chosen: line.depots, choices: [], problem: language.text(
                "No depot yet: make a station no line stops at a depot on its panel, or lay sidings with the network tool's Depot.",
                "還沒有機廠：在沒有路線停靠的車站面板按「設為機廠」，或用路網工具的「機廠」鋪停車線。"
            ), inDepot: inDepot)
        }
        return LineDepotRow(
            chosen: line.depots,
            choices: depots.map { LineDepotChoice(station: $0.station.id, name: $0.station.name, isChosen: line.depots.contains($0.station.id)) },
            problem: nil, inDepot: inDepot
        )
    }
}
