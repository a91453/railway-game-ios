import GameCore

// Arranging trains on the train roster by dragging (decision 512): a
// train's name held and dragged onto a row of another line gives the
// train to that line; a planned box of a train's own repeating timetable
// held and dragged sideways moves its timetable earlier or later. Where
// the finger is, how far it moved in time, and what letting go would do
// are worked out here (Linux tests); the app's `TrainRosterView` draws
// the drag and sends one command when the finger lifts.

/// Where a drag on the roster is and what letting go would do.
public enum TrainRosterDrag {
    /// Times a sideways drag snaps to, in seconds: five minutes.
    public static let snap: Int64 = 5 * GameTime.secondsPerMinute
    /// The smallest a drag handle is, in points, either way: the touch
    /// target of `docs/UI_THEME.md`.
    public static let handleSize: Double = 44
    /// How long a finger holds before a drag starts, in seconds, so a
    /// swipe still scrolls the hours and the trains.
    public static let holdSeconds: Double = 0.35

    /// The row at `y` points down the table (its hours' axis included),
    /// or `nil` above the first row or below the last.
    public static func row(atY y: Double, axisHeight: Double, rowHeight: Double, rows: Int) -> Int? {
        guard rowHeight > 0, y >= axisHeight else { return nil }
        let index = Int((y - axisHeight) / rowHeight)
        return index < rows ? index : nil
    }

    /// The seconds a sideways drag of `width` points moves a trip, at
    /// `hourWidth` points an hour, snapped to the nearest ``snap``.
    public static func shift(forWidth width: Double, hourWidth: Double) -> Int64 {
        guard hourWidth > 0, width.isFinite else { return 0 }
        let steps = (width / hourWidth * Double(GameTime.secondsPerHour) / Double(snap)).rounded()
        return Int64(max(-1_000, min(1_000, steps))) * snap
    }

    /// The index of the planned box of `row` under `second`, or `nil`.
    public static func plannedCell(of row: TrainRoster.Row, at second: Int64) -> Int? {
        row.cells.firstIndex { $0.state == .planned && $0.start <= second && second <= $0.end }
    }

    // MARK: Giving a train to another line

    /// What dropping a train on a row of another line would do.
    public struct LineMove: Hashable, Sendable {
        public enum Verdict: Hashable, Sendable {
            /// The row is the train's own line: nothing changes.
            case sameLine
            /// The train is out on a trip: it is given to another line
            /// only between trips.
            case onATrip
            /// The world refuses it, saying why.
            case refused(String)
            /// It moves.
            case moves
        }

        public let train: TrainID
        public let line: LineID
        public let lineName: String
        public let verdict: Verdict
        /// What the player should know before letting go: the new line
        /// runs fewer trains than it would have, the train is too long for
        /// a platform, it has to be brought to the line, or the old line is
        /// left a train short.
        public let notes: [String]

        /// Whether letting go sends the command.
        public var drops: Bool { verdict == .moves }

        /// The line under the finger: "To Blue Line"; or why not.
        public func text(in language: DisplayLanguage) -> String {
            switch verdict {
            case .sameLine: language.text("Already on \(lineName)", "已經在\(lineName)")
            case .onATrip: language.text("On a trip: try again when it finishes", "正在跑這一趟：跑完再拖")
            case .refused(let why): why
            case .moves: language.text("To \(lineName)", "改派到\(lineName)")
            }
        }
    }

    // MARK: Moving a timetable

    /// What dropping a planned box `seconds` later (earlier when below 0)
    /// would do to its train's own timetable.
    public struct Shift: Hashable, Sendable {
        public enum Verdict: Hashable, Sendable {
            /// Not moved far enough to snap.
            case unchanged
            /// The train is not waiting at its first stop, where a
            /// timetable can be changed without stopping it halfway.
            case notAtFirstStop(station: String)
            /// It moves, its first trip from then on leaving at
            /// `departure` (seconds of game time).
            case moves(departure: Int64)
        }

        public let train: TrainID
        public let seconds: Int64
        public let verdict: Verdict
        /// Another train that would leave the same station in the same
        /// minute: "Two leaves A then too".
        public let clash: String?

        public var drops: Bool {
            if case .moves = verdict { true } else { false }
        }

        /// "+15 min · leaves 08:45"; or why not.
        public func text(in language: DisplayLanguage) -> String {
            let minutes = seconds / GameTime.secondsPerMinute
            let signed = minutes > 0 ? "+\(minutes)" : "\(minutes)"
            switch verdict {
            case .unchanged: return language.text("Drag sideways to move it", "左右拖，改它的時刻")
            case .notAtFirstStop(let station):
                return language.text("Moves only while it waits at \(station)", "停在\(station)等發車時才能改")
            case .moves(let departure):
                return language.text("\(signed) min · leaves \(GameTime(seconds: departure).clockText)",
                                     "\(signed) 分 · \(GameTime(seconds: departure).clockText) 開")
            }
        }
    }

    /// `train`'s own timetable `seconds` later, with every time kept at or
    /// after second 0 by moving a repeating one a whole period on; `nil`
    /// for a train without a repeating timetable of its own.
    public static func shiftedTimetable(of train: Train, by seconds: Int64) -> [ScheduledStop]? {
        guard let period = train.timetablePeriod, period > 0, let first = train.timetable.first else { return nil }
        var shift = seconds % period
        if first.arrival.seconds + shift < 0 { shift += period }
        if let last = train.timetable.last, last.departure.seconds + shift >= Int64.max / 2 { return nil }
        return train.timetable.map {
            ScheduledStop(station: $0.station, arrival: GameTime(seconds: $0.arrival.seconds + shift),
                          departure: GameTime(seconds: $0.departure.seconds + shift), reverses: $0.reverses)
        }
    }

    /// What moving `train`'s own timetable `seconds` would do, seen in
    /// `roster` built from `world`.
    public static func shift(of train: TrainID, by seconds: Int64, in world: GameWorld, roster: TrainRoster) -> Shift? {
        guard let own = world.train(id: train), let period = own.timetablePeriod, period > 0,
              let first = own.timetable.first, own.execution != nil else { return nil }
        guard seconds % period != 0 else { return Shift(train: train, seconds: seconds, verdict: .unchanged, clash: nil) }
        guard case .waitingAtStop(0, _) = own.execution else {
            let name = world.station(id: first.station)?.name ?? "?"
            return Shift(train: train, seconds: seconds, verdict: .notAtFirstStop(station: name), clash: nil)
        }
        // The first trip it leaves on once started again: the first cycle
        // whose first departure is not before now (`startTrainService`).
        guard let shifted = shiftedTimetable(of: own, by: seconds)?.first else { return nil }
        let gap = world.clock.now.seconds - shifted.departure.seconds
        let cycle = gap <= 0 ? 0 : (gap + period - 1) / period
        let departure = shifted.departure.seconds + cycle * period
        // Another train leaving the same station in the same minute.
        let start = departure - (first.departure.seconds - first.arrival.seconds)
        let from = world.station(id: first.station)?.name
        let clash = roster.rows.first { row in
            row.train != train && row.cells.contains { cell in
                cell.from == from && abs(cell.start - start) < GameTime.secondsPerMinute
            }
        }
        return Shift(train: train, seconds: seconds, verdict: .moves(departure: departure),
                     clash: clash.map { "\($0.name)" })
    }
}

extension TrainRosterDrag.Shift {
    /// "Two leaves Taipei in the same minute".
    public func clashText(station: String, in language: DisplayLanguage) -> String? {
        clash.map { language.text("\($0) leaves \(station) in the same minute", "\($0) 也在同一分鐘從\(station)開") }
    }
}

extension GameSession {
    /// What dropping train `trainID` on a row of line `lineID` would do
    /// (decision 512): the edit run on a copy of the world, so the
    /// preview is what letting go does.
    public func rosterLineMove(of trainID: TrainID, to lineID: LineID) -> TrainRosterDrag.LineMove? {
        guard let train = world.train(id: trainID), let line = world.line(id: lineID) else { return nil }
        func move(_ verdict: TrainRosterDrag.LineMove.Verdict, _ notes: [String] = []) -> TrainRosterDrag.LineMove {
            TrainRosterDrag.LineMove(train: trainID, line: lineID, lineName: line.name, verdict: verdict, notes: notes)
        }
        let from = world.assignedLine(of: trainID)
        if from == lineID { return move(.sameLine) }
        // A line's train out on a trip finishes it as a service of its own,
        // which a line cannot take.
        if from != nil, world.trips(of: trainID).last?.isRunning == true || train.execution != nil { return move(.onATrip) }
        var moved = world
        do throws(GameError) {
            _ = try apply(.moveTrainToLine(trainID, lineID), to: &moved)
        } catch {
            return move(.refused(error.playerMessage(in: language)))
        }
        var notes: [String] = []
        if let unused = moved.lineUnusedTrains(ofTrain: trainID) {
            notes.append(language.text(
                "\(line.name) runs \(unused.busiest): run \(unused.target) to use it",
                "\(line.name) 只跑 \(unused.busiest) 列：要加開到 \(unused.target) 列才會用到它"
            ))
        }
        if let short = moved.shortPlatformCall(ofTrain: trainID) {
            notes.append(moved.shortPlatformText(short, in: language))
        }
        let stops = Set(moved.stationsStoppedAt(by: trainID))
        let ends = [line.stops.first, line.stops.last].compactMap(\.self)
        let reaches = moved.flexDispatch ? !stops.isEmpty : ends.contains { stops.contains($0) } || line.isRing && !stops.isDisjoint(with: line.stops)
        if !reaches, let start = line.stops.first {
            notes.append(language.text(
                "It leaves once it stops at \(moved.stationName(start))",
                "它要停到\(moved.stationName(start))才會出發"
            ))
        }
        if let from, let old = moved.line(id: from), old.targetHeadways == .none {
            let busiest = ServiceLevel.allCases.map { old.trainsInService[$0] }.max() ?? 0
            if old.trains.count < busiest {
                notes.append(language.text(
                    "\(old.name) is set to run \(busiest) and keeps \(old.trains.count)",
                    "\(old.name) 設定跑 \(busiest) 列，只剩 \(old.trains.count) 列"
                ))
            }
        }
        return move(.moves, notes)
    }

    /// Gives train `trainID` to line `lineID`'s own service, taking it off
    /// its line first (decision 512: the roster's drag), as one edit Undo
    /// takes back.
    public func moveTrain(_ trainID: TrainID, toLine lineID: LineID) {
        guard let train = world.train(id: trainID), let line = world.line(id: lineID) else { return }
        perform(.moveTrainToLine(trainID, lineID)) { outcome, _, _ in
            var text = language.text("\(train.name) now runs for \(line.name).", "\(train.name) 改派到\(line.name)。")
            if outcome.number > 0 {
                text += language.text(" \(line.name) now runs \(outcome.number).", "\(line.name) 現在跑 \(outcome.number) 列。")
            }
            return text
        }
    }

    /// Moves train `trainID`'s own repeating timetable `seconds` later
    /// (earlier below 0), stopping and starting its service where it waits
    /// at its first stop (decision 512), as one edit Undo takes back.
    public func shiftTrainTimetable(_ trainID: TrainID, by seconds: Int64) {
        guard let train = world.train(id: trainID) else { return }
        perform(.shiftTrainTimetable(trainID, by: seconds)) { _, _, _ in
            let minutes = seconds / GameTime.secondsPerMinute
            return minutes > 0
                ? language.text("\(train.name) runs \(minutes) min later.", "\(train.name) 的時刻往後 \(minutes) 分。")
                : language.text("\(train.name) runs \(-minutes) min earlier.", "\(train.name) 的時刻提前 \(-minutes) 分。")
        }
    }
}
