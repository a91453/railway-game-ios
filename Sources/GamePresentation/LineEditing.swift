import GameCore

// A line's stops and the service day (Stage C2): the screens for
// `setLineStops` (Stage Q2a) and `setServiceDay`. The `Ci/` reference adds
// and removes a line's stations (`tutorial.transport.18`: 使用＋添加停靠车站)
// and shows when each service level runs in a tooltip
// (`metroServiceSlotTimeRanges` in `app__q_c234188b7c397f91.js`); its bands
// are fixed in code, so editing them is the app's own. Every control is one
// GameWorld command with an edited copy read from the world each time.

/// Edits of a line's stops, as pure functions.
public enum LineStopEditing {
    /// `stops` with `station` inserted before index `index` (at the end for
    /// `stops.count`).
    public static func inserting(_ station: StationID, at index: Int, into stops: [StationID]) -> [StationID] {
        var edited = stops
        edited.insert(station, at: min(max(index, 0), stops.count))
        return edited
    }

    /// `stops` without the stop at `index`.
    public static func removing(_ index: Int, from stops: [StationID]) -> [StationID] {
        guard stops.indices.contains(index) else { return stops }
        var edited = stops
        edited.remove(at: index)
        return edited
    }

    /// `stops` with the stop at `index` swapped with its neighbour `offset`
    /// (−1 or 1) away; unchanged at an end.
    public static func moving(_ index: Int, by offset: Int, in stops: [StationID]) -> [StationID] {
        let other = index + offset
        guard stops.indices.contains(index), stops.indices.contains(other) else { return stops }
        var edited = stops
        edited.swapAt(index, other)
        return edited
    }
}

/// Edits of the service day, as pure functions. Times move half an hour at
/// a time.
public enum ServiceDayEditing {
    public static let step = 30

    /// `day` with band `index` at `level`.
    public static func setting(_ index: Int, to level: ServiceLevel, in day: ServiceDay) -> ServiceDay {
        guard day.bands.indices.contains(index) else { return day }
        var bands = day.bands
        bands[index] = ServiceDay.Band(start: bands[index].start, level: level)
        return ServiceDay(bands: bands)
    }

    /// `day` with band `index` starting `minutes` later (earlier when
    /// negative), staying a minute after the band before it and a minute
    /// before the next (or midnight). The first band always starts at
    /// 00:00.
    public static func moving(_ index: Int, by minutes: Int, in day: ServiceDay) -> ServiceDay {
        guard index > 0, day.bands.indices.contains(index) else { return day }
        let earliest = day.bands[index - 1].start + 1
        let latest = (index + 1 < day.bands.count ? day.bands[index + 1].start : 1440) - 1
        var bands = day.bands
        bands[index] = ServiceDay.Band(start: min(max(bands[index].start + minutes, earliest), latest), level: bands[index].level)
        return ServiceDay(bands: bands)
    }

    /// Whether band `index` can start earlier, or later for `later`.
    public static func canMove(_ index: Int, later: Bool, in day: ServiceDay) -> Bool {
        guard index > 0, day.bands.indices.contains(index) else { return false }
        return moving(index, by: later ? 1 : -1, in: day) != day
    }

    /// `day` with its longest band split in two at its middle, rounded down
    /// to the half hour, both halves at its level, so nothing runs
    /// differently until one is changed. Unchanged when no band is longer
    /// than an hour.
    public static func splittingLongest(_ day: ServiceDay) -> ServiceDay {
        let bands = day.bands
        let ends = bands.dropFirst().map(\.start) + [1440]
        guard let index = bands.indices.max(by: { ends[$0] - bands[$0].start < ends[$1] - bands[$1].start }),
              ends[index] - bands[index].start > 60
        else { return day }
        let middle = (bands[index].start + ends[index]) / 2 / step * step
        let start = middle > bands[index].start ? middle : bands[index].start + step
        var split = bands
        split.insert(ServiceDay.Band(start: start, level: bands[index].level), at: index + 1)
        return ServiceDay(bands: split)
    }

    /// `day` without band `index`; the band before it runs on in its place.
    /// The first band stays.
    public static func removing(_ index: Int, from day: ServiceDay) -> ServiceDay {
        guard index > 0, day.bands.indices.contains(index) else { return day }
        var bands = day.bands
        bands.remove(at: index)
        return ServiceDay(bands: bands)
    }
}

extension ServiceDay {
    /// When `level` runs over the day, as the reference's tooltip lists it
    /// (`metroServiceSlotTimeRanges`): ["07:00–10:00", "16:00–20:00"],
    /// neighbouring bands of the same level joined; the last ends at 24:00.
    public func ranges(of level: ServiceLevel) -> [String] {
        var ranges: [String] = []
        var open: Int?
        for minute in 0...1440 {
            let isLevel = minute < 1440 && self.level(atMinuteOfDay: minute) == level
            if isLevel, open == nil {
                open = minute
            } else if !isLevel, let start = open {
                ranges.append("\(clockText(minuteOfDay: start))–\(minute == 1440 ? "24:00" : clockText(minuteOfDay: minute))")
                open = nil
            }
        }
        return ranges
    }

    /// Every level and when it runs: "Peak 07:00–10:00, 16:00–20:00 ·
    /// Off-peak 10:00–16:00, 20:00–21:00 · Low 00:00–07:00, 21:00–24:00",
    /// leaving out levels that never run.
    public func summaryText(in language: DisplayLanguage) -> String {
        ServiceLevel.allCases.compactMap { level in
            let ranges = ranges(of: level)
            guard !ranges.isEmpty else { return nil }
            return "\(level.title(in: language)) \(ranges.joined(separator: language.text(", ", "、")))"
        }
        .joined(separator: " · ")
    }

    /// Band `index` as the editor lists it: "From 07:00 · Peak"; "07:00 起
    /// · 尖峰".
    public func bandText(_ index: Int, in language: DisplayLanguage) -> String {
        let band = bands[index]
        let start = clockText(minuteOfDay: band.start)
        return language.text("From \(start) · \(band.level.title(in: language))", "\(start) 起 · \(band.level.title(in: language))")
    }
}

extension GameSession {
    // MARK: - A line's stops

    /// Inserts `station` into the selected line's stops before index
    /// `index` (at the end for the stop count) through
    /// `GameWorld.setLineStops(_:to:)`.
    public func insertStopIntoSelectedLine(_ station: StationID, at index: Int) {
        guard let line = requireSelectedLine() else { return }
        setStops(of: line, to: LineStopEditing.inserting(station, at: index, into: line.stops))
    }

    /// Removes stop `index` from the selected line. Passengers waiting for
    /// a trip it no longer takes leave (GameCore's `abandoned`).
    public func removeStopFromSelectedLine(at index: Int) {
        guard let line = requireSelectedLine() else { return }
        setStops(of: line, to: LineStopEditing.removing(index, from: line.stops))
    }

    /// Swaps stop `index` of the selected line with its neighbour `offset`
    /// (−1 or 1) away.
    public func moveStopOfSelectedLine(at index: Int, by offset: Int) {
        guard let line = requireSelectedLine() else { return }
        setStops(of: line, to: LineStopEditing.moving(index, by: offset, in: line.stops))
    }

    private func setStops(of line: ServiceLine, to stops: [StationID]) {
        perform { world throws(GameError) in
            try world.setLineStops(line.id, to: stops)
            let names = stops.map { world.station(id: $0)?.name ?? "#\($0.rawValue)" }.joined(separator: " – ")
            return language.text("\(line.name) now calls at \(names).", "\(line.name) 改停 \(names)。")
        }
    }

    // MARK: - The service day

    /// Runs band `index` of the service day at `level`, for every line.
    public func setServiceDayBand(_ index: Int, to level: ServiceLevel) {
        setServiceDay(ServiceDayEditing.setting(index, to: level, in: world.serviceDay), changed: index)
    }

    /// Starts band `index` `minutes` later (earlier when negative).
    public func moveServiceDayBand(_ index: Int, by minutes: Int) {
        setServiceDay(ServiceDayEditing.moving(index, by: minutes, in: world.serviceDay), changed: index)
    }

    /// Splits the longest band in two (see
    /// ``ServiceDayEditing/splittingLongest(_:)``).
    public func addServiceDayBand() {
        let day = ServiceDayEditing.splittingLongest(world.serviceDay)
        guard day != world.serviceDay else {
            message = StatusMessage(kind: .failure, text: language.text("Every band is an hour or shorter.", "每個時段都已經不超過一小時。"))
            return
        }
        let old = world.serviceDay.bands
        let added = day.bands.indices.first { $0 >= old.count || day.bands[$0] != old[$0] } ?? day.bands.count - 1
        setServiceDay(day, changed: added)
    }

    /// Removes band `index`; the band before it runs on in its place.
    public func removeServiceDayBand(_ index: Int) {
        setServiceDay(ServiceDayEditing.removing(index, from: world.serviceDay), changed: nil)
    }

    /// Goes back to ``ServiceDay/standard``.
    public func resetServiceDay() {
        setServiceDay(.standard, changed: nil)
    }

    private func setServiceDay(_ day: ServiceDay, changed index: Int?) {
        perform { world throws(GameError) in
            try world.setServiceDay(day)
            if let index, day.bands.indices.contains(index) {
                return language.text("Service day: \(day.bandText(index, in: language)).", "服務日：\(day.bandText(index, in: language))。")
            }
            return language.text("Service day: \(day.summaryText(in: language)).", "服務日：\(day.summaryText(in: language))。")
        }
    }
}
