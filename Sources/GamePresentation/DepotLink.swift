import GameCore

// Decision 573 (player report 111.1): a depot laid behind a line's end
// was no line's depot until the player ticked it on the line panel, so
// after the last train the line's trains stayed at the platforms. Now a
// new depot (the depot tool's sidings, or the station panel's "Make a
// depot") is made the depot of the one line it serves at once, in the
// same edit (one Undo takes both back); with several such lines the
// banner offers each. A line it serves is one without a depot yet whose
// end (any stop, on a ring) a train leaving the depot reaches within
// ``DepotLink/reach`` of track. Lines that run to a timetable count too
// (decision 221).

/// How near a new depot must be to a line to be made its depot.
public enum DepotLink {
    /// Track from the depot to the line's nearer end: 3 km.
    public static let reach: Int64 = 3_000 * WorldCoordinate.unitsPerMetre
    /// How many lines the banner offers at most.
    public static let offered = 3
}

/// The banner's offer to make a new depot the depot of lines near it
/// (``StatusMessage/depotOffer``).
public struct DepotLinkOffer: Hashable, Sendable {
    public let depot: StationID
    public let lines: [LineID]
}

extension GameWorld {
    /// The lines with no depot that depot `id` serves (see the file's
    /// header), by ID.
    func linesServed(byDepot id: StationID) -> [LineID] {
        guard station(id: id)?.isDepot == true else { return [] }
        let starts = trackPlatforms(of: id).flatMap { platform -> [TrainPosition] in
            guard let length = network.edge(platform.edge)?.length else { return [] }
            let middle = (platform.start + platform.end) / 2
            return [
                .onEdge(TrackTraversal(edge: platform.edge, direction: .forward), offset: middle),
                .onEdge(TrackTraversal(edge: platform.edge, direction: .backward), offset: length - middle),
            ]
        }
        guard !starts.isEmpty else { return [] }
        var distance: [StationID: Int64?] = [:]
        func reach(_ stop: StationID) -> Int64? {
            if let known = distance[stop] { return known }
            let found = starts.compactMap { path(from: $0, toStation: stop)?.distance }.min()
            distance[stop] = found
            return found
        }
        return lines.filter { line in
            guard line.depots.isEmpty, !line.stops.isEmpty else { return false }
            let ends = line.isRing ? line.stops : [line.stops.first!, line.stops.last!]
            return ends.contains { reach($0).map { $0 <= DepotLink.reach } ?? false }
        }.map(\.id).sorted { $0.rawValue < $1.rawValue }
    }
}

extension GameSession {
    /// Runs `body` as one edit to ``undo()`` (``beginEditGesture()``),
    /// unless a gesture is already open, which it then joins.
    func asOneEdit<Result>(_ body: () -> Result) -> Result {
        guard !isEditGestureInProgress else { return body() }
        beginEditGesture()
        defer { endEditGesture() }
        return body()
    }

    /// After depot `depot` was made (its message `done` already said
    /// so): makes it the depot of the one line it serves, or offers the
    /// lines when several, and says so after `done`.
    func linkNewDepot(_ depot: StationID, done: String) {
        let lines = world.linesServed(byDepot: depot)
        let name = world.station(id: depot)?.name ?? ""
        let gap = language.text(" ", "")
        if lines.count == 1, let line = world.line(id: lines[0]) {
            do throws(GameError) {
                try performCommand(.edit(.setLineDepots(line.id, [depot])))
                message = StatusMessage(kind: .success, text: done + gap + language.text(
                    "It is now \(line.name)'s depot: after the last train the line's trains run into it.",
                    "已設為「\(line.name)」的機廠，收班後列車會開進來。"
                ))
            } catch {
                message = StatusMessage(kind: .success, text: done + gap + Self.chooseOnLinePanel(in: language))
            }
            return
        }
        guard !lines.isEmpty else {
            message = StatusMessage(kind: .success, text: done + gap + Self.chooseOnLinePanel(in: language))
            return
        }
        message = StatusMessage(
            kind: .success,
            text: done + gap + language.text(
                "Several lines end near \(name): tap one to make this its depot.",
                "「\(name)」附近有好幾條路線：點路線名稱，設為它的機廠。"
            ),
            depotOffer: DepotLinkOffer(depot: depot, lines: Array(lines.prefix(DepotLink.offered)))
        )
    }

    static func chooseOnLinePanel(in language: DisplayLanguage) -> String {
        language.text("Choose it as a line's depot on the line panel.", "到路線面板替路線選這個機廠。")
    }

    /// The banner button's title: the line's name, so several fit side by
    /// side (the message above says what a tap does).
    public func depotOfferChip(line id: LineID) -> String {
        world.line(id: id)?.name ?? ""
    }

    /// What the banner button does, for VoiceOver: "Make it Main's
    /// depot", 「設為「Main」的機廠」.
    public func depotOfferTitle(line id: LineID) -> String {
        let name = world.line(id: id)?.name ?? ""
        return language.text("Make it \(name)'s depot", "設為「\(name)」的機廠")
    }

    /// The banner's button: makes `depot` one of line `id`'s depots.
    public func linkDepot(_ depot: StationID, to id: LineID) {
        guard let line = world.line(id: id) else { return }
        let depots = line.depots.contains(depot) ? line.depots : line.depots + [depot]
        let name = world.station(id: depot)?.name ?? ""
        perform(.edit(.setLineDepots(id, depots))) { _, _, _ in
            language.text(
                "\(line.name) now keeps its trains at the depot \(name): they leave it before the first train and go back after the last.",
                "「\(line.name)」的列車現在停機廠「\(name)」：首班前出庫、收班後入庫。"
            )
        }
    }
}
