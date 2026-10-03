import GameCore

// Read-only track facts (Stage C2) that Phase 4.5 Stage S1 derives: the
// sections of the track network between branch points (`networkSections`,
// Stage F3c), how many separate tracks join each pair of a line's stops
// (`lineTrackCounts`: single or double track) and the track two trains
// occupy at once (`occupancyConflicts`). All of it is read from the world
// when shown; nothing is kept.

extension TrackResource {
    /// "Tile (3, 1)", "Link (3, 1)–(4, 1)", "Node #2", or for part of an
    /// edge of the track network "Edge #4, 1024–2048".
    public func displayText(in language: DisplayLanguage) -> String {
        switch self {
        case .node(let node):
            return node.displayText(in: language)
        case .span(let span):
            let edge = span.edge.displayText(in: language)
            guard case .edge = span.edge else { return edge }
            return "\(edge), \(span.start)–\(span.end)"
        }
    }
}

extension GameWorld {
    /// How many sections the track network has (``networkSections()``):
    /// "4 sections" or "4 sections · 1 loop"; "4 個區段 · 1 個環線". `nil`
    /// without track.
    public func trackSectionsSummary(in language: DisplayLanguage) -> String? {
        let sections = networkSections()
        guard !sections.isEmpty else { return nil }
        let loops = sections.filter(\.isLoop).count
        let count = language.text("\(sections.count) \(sections.count == 1 ? "section" : "sections")", "\(sections.count) 個區段")
        guard loops > 0 else { return count }
        return count + language.text(" · \(loops) \(loops == 1 ? "loop" : "loops")", " · \(loops) 個環線")
    }

    /// Each pair of consecutive stops of line `id` and the separate tracks
    /// joining them (``lineTrackCounts(_:)``): "Alpha–Beta · single
    /// track", "Beta–Gamma · double track", "· 3 tracks", or "· no track".
    /// Empty for an unknown line.
    public func lineTrackCountTexts(_ id: LineID, in language: DisplayLanguage) -> [String] {
        guard let line = line(id: id), let counts = lineTrackCounts(id) else { return [] }
        return zip(zip(line.stops, line.stops.dropFirst()), counts).map { pair, count in
            let tracks = switch count {
            case 0: language.text("no track", "沒有軌道")
            case 1: language.text("single track", "單線")
            case 2: language.text("double track", "雙線")
            default: language.text("\(count) tracks", "\(count) 線")
            }
            return "\(stationName(pair.0))–\(stationName(pair.1)) · \(tracks)"
        }
    }

    /// The track two trains or more occupy at once (``occupancyConflicts()``):
    /// "T1 and T2 on tile (3, 1)"; "T1、T2 都在格 (3, 1)". Empty when none do.
    public func occupancyConflictTexts(in language: DisplayLanguage) -> [String] {
        occupancyConflicts().map { conflict in
            let names = conflict.trains.map { train(id: $0)?.name ?? "#\($0.rawValue)" }
            let place = conflict.resource.displayText(in: language)
            return language.text(
                "\(names.joined(separator: " and ")) on \(place.lowercased())",
                "\(names.joined(separator: "、")) 都在\(place)"
            )
        }
    }
}
