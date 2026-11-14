import GameCore

// Decision 755 (PLATFORM-BOOK PB-3): the line panel's list of platforms for
// one leg. A leg could hold a list since decision 740, but only a save or
// the command could set it; the leg's row now lists its platforms in order
// (the first is the one its route menu picks), lets the player add another
// of the station's platforms, move one up or down and take one off, and
// says where the list cannot work: a platform gone or too short for the
// line's longest train, and fewer platforms than the trains its timetables
// have at the station at once (the train after them waits at the stop
// before).

/// One leg's list of platforms as the line panel shows it.
public struct PlatformListLeg: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let platform: TrackPlatform
        /// "Platform on track #5 (120 m)".
        public let text: String
        /// Why a train of the line cannot stop there, or `nil`.
        public let problem: String?
    }

    /// The leg's first platform, then the others in order.
    public let entries: [Entry]
    /// The station's other platforms the list may take next, each with its
    /// text; empty once the list is full.
    public let choices: [TrackPlatform]
    public let choiceTexts: [String]
    /// That the list has fewer platforms than trains at the station at
    /// once, or `nil`.
    public let warning: String?

    /// Whether it is a list (more than one platform): the leg's trains
    /// then stop only at these.
    public var isList: Bool { entries.count > 1 }
}

/// Decision 755: the edits a leg's list takes, each a whole new
/// preference for ``GameWorld/setLineRoutePreferences(_:to:pattern:)``,
/// or `nil` where the edit does not apply.
public enum PlatformListEdit {
    /// `preference` with `platform` added at the end of its list.
    public static func adding(_ platform: TrackPlatform, to preference: LineRoutePreference) -> LineRoutePreference? {
        guard platform.station == preference.platform.station, platform != preference.platform,
              !preference.alternates.contains(platform), preference.alternates.count < LineRoutePreference.maximumAlternates
        else { return nil }
        return with(preference, alternates: preference.alternates + [platform])
    }

    /// `preference` without the platform at `index` of its list (1 or
    /// later: the first is the route menu's to change).
    public static func removing(at index: Int, from preference: LineRoutePreference) -> LineRoutePreference? {
        guard index >= 1, index <= preference.alternates.count else { return nil }
        var alternates = preference.alternates
        alternates.remove(at: index - 1)
        return with(preference, alternates: alternates)
    }

    /// `preference` with the platform at `index` of its list (1 or later)
    /// moved `offset` places, staying after the first.
    public static func moving(at index: Int, by offset: Int, in preference: LineRoutePreference) -> LineRoutePreference? {
        let target = index + offset
        guard index >= 1, index <= preference.alternates.count, target >= 1, target <= preference.alternates.count, offset != 0 else { return nil }
        var alternates = preference.alternates
        alternates.swapAt(index - 1, target - 1)
        return with(preference, alternates: alternates)
    }

    /// `chosen`, the leg's new first platform and walk from its route
    /// menu, keeping the list `old` had behind it: the old platforms in
    /// their order, less the one now first, as many as fit. `chosen` as it
    /// is when `old` had no list.
    public static func keepingList(of old: LineRoutePreference?, in chosen: LineRoutePreference) -> LineRoutePreference {
        guard let old, let list = old.platformList, chosen.alternates.isEmpty, old.platform.station == chosen.platform.station else { return chosen }
        let kept = list.filter { $0 != chosen.platform }.prefix(LineRoutePreference.maximumAlternates)
        return with(chosen, alternates: Array(kept))
    }

    private static func with(_ preference: LineRoutePreference, alternates: [TrackPlatform]) -> LineRoutePreference {
        LineRoutePreference(from: preference.from, to: preference.to, tracks: preference.tracks, platform: preference.platform, alternates: alternates)
    }
}

extension GameWorld {
    /// Decision 755: leg `from` → `to` of line `id`'s service (its own for
    /// `pattern` `nil`) as its list of platforms, in `language`; `nil`
    /// when the leg names no platform.
    public func platformListLeg(_ id: LineID, from: Int, to: Int, pattern: Int? = nil, in language: DisplayLanguage) -> PlatformListLeg? {
        guard let line = line(id: id) else { return nil }
        if let pattern, !line.patterns.indices.contains(pattern) { return nil }
        let routes = pattern.map { line.patterns[$0].routePreferences } ?? line.routePreferences
        guard let preference = routes.first(where: { $0.from == from && $0.to == to }) else { return nil }
        let station = preference.platform.station
        let list = preference.platformList ?? [preference.platform]
        let trainIDs = pattern.map { line.patterns[$0].trains } ?? line.trains
        let longest = trainIDs.compactMap { train(id: $0)?.length }.max() ?? 0
        let onNetwork = Set(trackPlatforms(of: station))
        let entries = list.map { platform in
            PlatformListLeg.Entry(
                platform: platform, text: Self.platformText(platform, in: language),
                problem: Self.platformProblem(platform, onNetwork: onNetwork.contains(platform), longest: longest, in: language)
            )
        }
        let choices = list.count > LineRoutePreference.maximumAlternates
            ? [] : trackPlatforms(of: station).filter { !list.contains($0) }.sorted()
        var warning: String?
        if list.count > 1 {
            let atOnce = mostTrainsAtOnce(at: station, line: id, pattern: pattern)
            if atOnce > list.count {
                let name = self.station(id: station)?.name ?? "#\(station.rawValue)"
                warning = language.text(
                    "Up to \(atOnce) trains of this line are at \(name) at once, but the list has \(list.count) platforms: the others wait at the stop before.",
                    "這條線同時最多有 \(atOnce) 列車在 \(name)，清單只有 \(list.count) 座月台：多的會在前一站等。"
                )
            }
        }
        return PlatformListLeg(
            entries: entries, choices: choices, choiceTexts: choices.map { Self.platformText($0, in: language) }, warning: warning
        )
    }

    /// "Platform on track #5 (120 m)".
    static func platformText(_ platform: TrackPlatform, in language: DisplayLanguage) -> String {
        let track = RoutePreview.label(of: platform.edge)
        let metres = platform.length / WorldCoordinate.unitsPerMetre
        return language.text("Platform on track \(track) (\(metres) m)", "月台在軌段 \(track)（\(metres) 公尺）")
    }

    static func platformProblem(_ platform: TrackPlatform, onNetwork: Bool, longest: Int64, in language: DisplayLanguage) -> String? {
        guard onNetwork else { return language.text("This platform is gone", "這座月台已經拆掉了") }
        guard platform.length < longest else { return nil }
        let metres = longest / WorldCoordinate.unitsPerMetre
        return language.text(
            "Too short for this line's longest train (\(metres) m): its trains skip it",
            "放不下這條線最長的列車（\(metres) 公尺），列車不會停這座"
        )
    }
}

extension GameSession {
    /// ``GameWorld/platformListLeg(_:from:to:pattern:in:)`` of the
    /// selected line.
    public func platformListLeg(from: Int, to: Int, pattern: Int? = nil) -> PlatformListLeg? {
        guard let line = selectedLine else { return nil }
        return world.platformListLeg(line.id, from: from, to: to, pattern: pattern, in: language)
    }

    /// Adds `platform` to the end of the selected line's list for the leg.
    public func addSelectedLinePlatform(_ platform: TrackPlatform, from: Int, to: Int, pattern: Int? = nil) {
        editSelectedLinePlatforms(from: from, to: to, pattern: pattern) { PlatformListEdit.adding(platform, to: $0) }
    }

    /// Takes the platform at `index` (1 or later) off the leg's list.
    public func removeSelectedLinePlatform(at index: Int, from: Int, to: Int, pattern: Int? = nil) {
        editSelectedLinePlatforms(from: from, to: to, pattern: pattern) { PlatformListEdit.removing(at: index, from: $0) }
    }

    /// Moves the platform at `index` (1 or later) of the leg's list
    /// `offset` places.
    public func moveSelectedLinePlatform(at index: Int, by offset: Int, from: Int, to: Int, pattern: Int? = nil) {
        editSelectedLinePlatforms(from: from, to: to, pattern: pattern) { PlatformListEdit.moving(at: index, by: offset, in: $0) }
    }

    private func editSelectedLinePlatforms(from: Int, to: Int, pattern: Int?, _ edit: (LineRoutePreference) -> LineRoutePreference?) {
        guard let line = requireSelectedLine() else { return }
        if let pattern, !line.patterns.indices.contains(pattern) { return }
        var routes = pattern.map { line.patterns[$0].routePreferences } ?? line.routePreferences
        guard let index = routes.firstIndex(where: { $0.from == from && $0.to == to }), let edited = edit(routes[index]) else { return }
        routes[index] = edited
        let station = world.station(id: edited.platform.station)?.name ?? ""
        let chosen = routes
        perform(.setLineRoutes(line.id, chosen, pattern: pattern)) { _, _, _ in
            edited.alternates.isEmpty
                ? language.text("Trains stop only at the first platform at \(station) again, or another when it is taken.", "\(station) 改回只指定一座月台，被占用時改停別座。")
                : language.text("Updated the platforms trains stop at in \(station), in order.", "已更新 \(station) 依序停靠的月台清單。")
        }
    }
}
