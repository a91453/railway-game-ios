import GameCore

// Player-facing text for GameCore values, in English or Traditional Chinese
// (see ``DisplayLanguage``). GameCore stays free of UI copy; the app shows
// these strings as they are.

extension GameWorld {
    /// What station `id` is: "Station · Central", and its platforms on the
    /// track network once it has any (Stage F1: their number and length
    /// tell its size), "Station · Central · 2 platforms, 128 m".
    public func stationSummary(_ id: StationID, in language: DisplayLanguage) -> String {
        let label = language.text("Station", "車站")
        guard let station = station(id: id) else { return "\(label) · #\(id.rawValue)" }
        var parts = [label, station.name]
        let platforms = trackPlatforms(of: id)
        if !platforms.isEmpty {
            let length = NetworkBuilding.lengthText(platforms.reduce(0) { $0 + $1.length }, in: language)
            parts.append(language.text(
                platforms.count == 1 ? "1 platform, \(length)" : "\(platforms.count) platforms, \(length)",
                "\(platforms.count) 座月台，共 \(length)"
            ))
        }
        return parts.joined(separator: " · ")
    }
}

extension Station {
    /// Where the station stands, for lists: its point (Stage F1) in metres
    /// east and south of the map's north-west corner, "x 41 m, y 17 m".
    public func placeText(in language: DisplayLanguage) -> String {
        point.placeText(in: language)
    }
}

extension PlanPoint {
    /// The point in metres east and south of the map's north-west corner,
    /// "x 41 m, y 17 m".
    public func placeText(in language: DisplayLanguage) -> String {
        "x \(NetworkBuilding.lengthText(x, in: language)), y \(NetworkBuilding.lengthText(y, in: language))"
    }
}

extension WorldBounds {
    /// The map view's accessibility label (Stage F3d): how far the world
    /// reaches, "Map, 16.4 by 16.4 kilometres", to the nearest tenth of a
    /// kilometre. The world has no cells to count.
    public func mapLabel(in language: DisplayLanguage) -> String {
        let east = Self.kilometresText(width), south = Self.kilometresText(height)
        return language.text("Map, \(east) by \(south) kilometres", "地圖，\(east) × \(south) 公里")
    }

    /// `units` in kilometres, to the nearest tenth: "16.4".
    static func kilometresText(_ units: Int64) -> String {
        let tenth = 100 * WorldCoordinate.unitsPerMetre
        let tenths = (units + tenth / 2) / tenth
        return "\(tenths / 10).\(tenths % 10)"
    }
}

extension GameWorld {
    /// How much has been built: the stations and the track network's
    /// edges, such as "3 stations · 4 edges"; "3 座車站 · 4 個軌段".
    public func networkSummary(in language: DisplayLanguage) -> String {
        let stationCount = stations.count
        let edgeCount = network.edges.count
        switch language {
        case .english:
            let stationText = stationCount == 1 ? "1 station" : "\(stationCount) stations"
            let edgeText = edgeCount == 1 ? "1 edge" : "\(edgeCount) edges"
            return "\(stationText) · \(edgeText)"
        case .traditionalChinese:
            return "\(stationCount) 座車站 · \(edgeCount) 個軌段"
        }
    }
}

extension GameWorld {
    /// The stations the train `id` is stopped at, such as "Stopped at
    /// Central" (several in ascending ID order: "Stopped at Central,
    /// Market"), or `nil` when it is not stopped at a station. Read from
    /// `stationsStoppedAt(by:)`. A train of several cars not wholly beside
    /// one of them (see `stationsBesideWholeTrain(_:)`) is told so:
    /// "Stopped at Central · the platform is too short for all its cars".
    public func stationStopText(of id: TrainID, in language: DisplayLanguage) -> String? {
        let stopped = stationsStoppedAt(by: id)
        let names = stopped.map { station(id: $0)?.name ?? "#\($0.rawValue)" }
        guard !names.isEmpty else { return nil }
        let text = language.text(
            "Stopped at \(names.joined(separator: ", "))",
            "停在 \(names.joined(separator: "、"))"
        )
        guard stationsBesideWholeTrain(id).count < stopped.count else { return text }
        return text + language.text(" · the platform is too short for all its cars", " · 月台太短，容不下所有車廂")
    }
}

extension TrainPosition {
    /// Where a train is, exactly as GameCore records it: "Edge #3 forward,
    /// 256 units along".
    public func displayText(in language: DisplayLanguage) -> String {
        switch self {
        case .onEdge(let traversal, let offset):
            language.text(
                "\(traversal.edge.displayText(in: language)) \(traversal.direction == .forward ? "forward" : "backward"), \(offset) units along",
                "\(traversal.edge.displayText(in: language)) \(traversal.direction == .forward ? "正向" : "反向")，距起點 \(offset) 單位"
            )
        }
    }
}

extension TrackNodeID {
    /// "Node #3".
    public func displayText(in language: DisplayLanguage) -> String {
        switch self {
        case .node(let number): language.text("Node #\(number)", "節點 #\(number)")
        }
    }
}

extension TrackEdgeID {
    /// "Edge #3".
    public func displayText(in language: DisplayLanguage) -> String {
        switch self {
        case .edge(let number): language.text("Edge #\(number)", "軌段 #\(number)")
        }
    }
}

extension Train {
    /// The train's position, or "Not on the track" while it is unplaced.
    public func positionText(in language: DisplayLanguage) -> String {
        position?.displayText(in: language) ?? language.text("Not on the track", "不在軌道上")
    }

    /// How many cars it has: "1 car", "3 cars".
    public func carsText(in language: DisplayLanguage) -> String {
        Self.carsText(cars, in: language)
    }

    /// "1 car", "3 cars", or "3 節車廂".
    static func carsText(_ cars: Int, in language: DisplayLanguage) -> String {
        language.text(cars == 1 ? "1 car" : "\(cars) cars", "\(cars) 節車廂")
    }

    /// The path the train has left on the track network: "No path ahead",
    /// "Path: 1 more edge, Edge #4",
    /// "Path: 3 more edges, ending on Edge #9", with ", stopping 3000 units
    /// along it" when it stops part of the way along the last (Stage S5),
    /// or "Path: stops 1024 units ahead" on the edge it is on.
    public func pathText(in language: DisplayLanguage) -> String {
        guard case .onEdge(_, let offset)? = position else { return language.text("No path ahead", "前方沒有路徑") }
        let edges = movement.remainingEdges
        guard let last = edges.last else {
            guard let end = movement.end, end > offset else { return language.text("No path ahead", "前方沒有路徑") }
            return language.text("Path: stops \(end - offset) units ahead", "路徑：前方 \(end - offset) 單位處停車")
        }
        let edge = last.displayText(in: language)
        let stop = movement.end.map { language.text(", stopping \($0) units along it", "，在其 \($0) 單位處停車") } ?? ""
        switch language {
        case .english:
            return edges.count == 1
                ? "Path: 1 more edge, \(edge)\(stop)"
                : "Path: \(edges.count) more edges, ending on \(edge)\(stop)"
        case .traditionalChinese:
            return edges.count == 1
                ? "路徑：再 1 個軌段，\(edge)\(stop)"
                : "路徑：再 \(edges.count) 個軌段，終於\(edge)\(stop)"
        }
    }
}

extension TrainMovement {
    /// The rate, such as "Rate 128 / min": world units per game minute
    /// (``WorldCoordinate/unitsPerMetre`` to a metre).
    public func rateText(in language: DisplayLanguage) -> String {
        language.text("Rate \(rate) / min", "速率 \(rate)／分鐘")
    }
}

extension GameError {
    /// What went wrong, in words a player can act on. GameError itself
    /// carries only structured data.
    public func playerMessage(in language: DisplayLanguage) -> String {
        switch self {
        case .invalidMapSize(let width, let height):
            language.text(
                "A map \(NetworkBuilding.lengthText(width, in: language)) by \(NetworkBuilding.lengthText(height, in: language)) is not supported.",
                "不支援 \(NetworkBuilding.lengthText(width, in: language)) × \(NetworkBuilding.lengthText(height, in: language)) 的地圖。"
            )
        case .outOfBounds(let point):
            language.text("\(point.placeText(in: language)) is outside the map.", "\(point.placeText(in: language)) 在地圖外。")
        case .invalidName:
            language.text("Enter a name.", "請輸入名稱。")
        case .insufficientFunds(let required, let available):
            language.text(
                "Not enough cash: this costs \(required.centsText) and you have \(available.centsText).",
                "餘額不足：需要 \(required.centsText)，目前只有 \(available.centsText)。"
            )
        case .unknownTrain(let id):
            language.text("There is no train #\(id.rawValue).", "沒有列車 #\(id.rawValue)。")
        case .trainAlreadyPlaced(let id):
            language.text("Train #\(id.rawValue) is already on the track.", "列車 #\(id.rawValue) 已經在軌道上。")
        case .trainNotPlaced(let id):
            language.text("Train #\(id.rawValue) is not on the track.", "列車 #\(id.rawValue) 不在軌道上。")
        case .invalidTrainPosition:
            language.text(
                "A train can only be placed on the track, with track behind it for all its cars.",
                "列車只能放在軌道上，而且後方要有足夠的軌道容納所有車廂。"
            )
        case .invalidMovementRate:
            language.text("A train's rate cannot be negative.", "列車的速率不能是負數。")
        case .invalidContinuation:
            language.text(
                "The train cannot follow that path: each step must lead to joined track, without turning back.",
                "列車無法沿這條路徑行駛：每一步都必須接到相連的軌道，而且不能折返。"
            )
        case .clockOverflow:
            language.text("Game time cannot advance any further.", "遊戲時間已經無法再往前推進。")
        case .idsExhausted:
            language.text("This game has no IDs left for anything more of this kind.", "這個遊戲已經沒有可用的編號，無法再增加這類項目。")
        case .invalidTimetable:
            language.text(
                "A timetable's times cannot be negative or go back: each stop leaves no earlier than it arrives, and no later than the next stop arrives. A repeating timetable needs a stop, and a period long enough to start again without going back.",
                "時刻表的時間不能是負數，也不能倒流：每一站的發車不早於到站，也不晚於下一站的到站。重複的時刻表至少要有一站，週期也要夠長，重新開始時時間才不會倒流。"
            )
        case .unknownStation(let id):
            language.text("There is no station #\(id.rawValue).", "沒有車站 #\(id.rawValue)。")
        case .trainServiceActive(let id):
            language.text(
                "Train #\(id.rawValue) is running its timetable. Stop its service first.",
                "列車 #\(id.rawValue) 正在依時刻表運行。請先停止它的服務。"
            )
        case .trainServiceNotActive(let id):
            language.text("Train #\(id.rawValue) is not running a timetable.", "列車 #\(id.rawValue) 沒有在依時刻表運行。")
        case .noTimetable(let id):
            language.text("Train #\(id.rawValue) has no timetable to run.", "列車 #\(id.rawValue) 沒有可執行的時刻表。")
        case .trainNotAtFirstStop(let id):
            language.text(
                "Train #\(id.rawValue) must be stopped at its timetable's first station to start its service.",
                "列車 #\(id.rawValue) 必須停在時刻表的第一站，才能開始服務。"
            )
        case .unknownLine(let id):
            language.text("There is no line #\(id.rawValue).", "沒有路線 #\(id.rawValue)。")
        case .invalidLineStops:
            language.text(
                "A line calls at two stations or more, and not at the same station twice in a row. A ring calls at three or more, and not at the same station first and last.",
                "路線至少要停靠兩個車站，而且不能連續兩次停靠同一站。環線至少要三站，第一站與最後一站也不能相同。"
            )
        case .invalidTrainPerformance:
            language.text(
                "That acceleration, braking or top speed is out of range.",
                "加速度、減速度或最高速度超出範圍。"
            )
        case .invalidServiceWindow:
            language.text(
                "A line opens between 00:00 and 23:59 and closes after it opens, by 06:00 the next morning.",
                "開班時間須在 00:00 到 23:59 之間，收班時間須晚於開班時間，最晚到次日 06:00。"
            )
        case .invalidTrainsInService:
            language.text("A line cannot run a negative number of trains.", "路線的上線列車數不能是負數。")
        case .invalidServiceDay:
            language.text(
                "The day's service levels must start at 00:00 and change at later times within the day.",
                "一天的服務等級必須從 00:00 開始，之後只能在同一天較晚的時間改變。"
            )
        case .invalidHeadway:
            language.text("A target headway must be between 2 minutes and 24 hours.", "目標班距須在 2 分鐘到 24 小時之間。")
        case .trainOnLine(let id):
            language.text(
                "Train #\(id.rawValue) runs for a line. Take it off the line first.",
                "列車 #\(id.rawValue) 正在為路線服務。請先把它從路線移除。"
            )
        case .trainNotOnLine(let id):
            language.text("Train #\(id.rawValue) is not on a line.", "列車 #\(id.rawValue) 不屬於任何路線。")
        case .invalidLineRoutePreference:
            language.text("Choose a physical path for a leg of this service.", "請為這個服務模式的路段選擇股道與月台。")
        case .invalidLinePattern:
            language.text(
                "A pattern calls at two of its line's stops or more, in the line's order. A ring has no patterns.",
                "服務模式至少要依路線的順序，停靠路線上的兩站以上。環線不能有服務模式。"
            )
        case .unknownLinePattern(let index):
            language.text("The line has no pattern #\(index + 1).", "這條路線沒有服務模式 #\(index + 1)。")
        case .invalidTrainLength:
            language.text(
                "A train has \(Train.minimumCars) to \(Train.maximumCars) cars.",
                "列車可以有 \(Train.minimumCars) 到 \(Train.maximumCars) 節車廂。"
            )
        case .unknownTrackNode(let node):
            language.text(
                "\(node.displayText(in: language)) is not a node of the track network.",
                "\(node.displayText(in: language)) 不是路網的節點。"
            )
        case .unknownTrackEdge(let edge):
            language.text(
                "\(edge.displayText(in: language)) is not an edge of the track network.",
                "\(edge.displayText(in: language)) 不是路網的軌段。"
            )
        case .invalidTrackGeometry:
            language.text(
                "Track can't be built there: it must stay on the map within 64 m of the ground, start and end at different nodes, and run smoothly.",
                "這裡不能建軌道：軌道必須在地圖內、與地面的高度差在 64 公尺以內、起點與終點是不同的節點，而且線形要平順。"
            )
        case .trackNodeInUse(let node):
            language.text(
                "Track still ends at \(node.displayText(in: language).lowercased()). Remove that track first.",
                "還有軌道接在\(node.displayText(in: language))。請先拆除那段軌道。"
            )
        case .trackEdgeInUse(let edge):
            language.text(
                "A train is on \(edge.displayText(in: language).lowercased()). Take the train off the track first.",
                "\(edge.displayText(in: language)) 上有列車。請先把列車移出軌道。"
            )
        case .trackTooSteep:
            language.text(
                "That track would be too steep. Track may climb or fall at most 40 in 1000; make it longer or the height difference smaller.",
                "這段軌道太陡了。坡度最多是千分之 40；請把軌道加長，或縮小高度差。"
            )
        case .invalidTrackStructure:
            language.text(
                "That structure can't carry track at those heights: surface track stays within 2 m of the ground, viaducts and bridges above it, tunnels below it.",
                "這種結構物無法在這個高度鋪設軌道：地面軌道與地面的高度差在 2 公尺以內，高架與橋樑在地面以上，隧道在地面以下。"
            )
        case .trackConflict(let edge):
            language.text(
                "That track would cross \(edge.displayText(in: language).lowercased()) without 8 m between them. Pass over or under it, or cross at a shared node.",
                "這段軌道會與\(edge.displayText(in: language))交叉，但兩者的高度差不到 8 公尺。請從上方或下方通過，或在共用的節點交會。"
            )
        case .trackTooClose(let edge):
            language.text(
                "That track would run less than 4 m beside \(edge.displayText(in: language).lowercased()). Keep parallel tracks 4 m apart, centre to centre, or pass 8 m over or under.",
                "這段軌道與\(edge.displayText(in: language))並行時距離不到 4 公尺。平行的軌道中心之間至少要 4 公尺，或上下相差 8 公尺。"
            )
        case .tracksWouldBeTooClose(let first, let second):
            language.text(
                "Without that track, \(first.displayText(in: language).lowercased()) and \(second.displayText(in: language).lowercased()) would run less than 4 m apart with no junction near. Remove one of them first.",
                "拆掉這段軌道之後，\(first.displayText(in: language))與\(second.displayText(in: language))之間不到 4 公尺，附近又沒有相接的交會點。請先拆掉其中一條。"
            )
        case .trackEdgeInLineRoute(let line):
            language.text(
                "Line #\(line.rawValue)'s chosen path runs along that track. Clear the line's path first.",
                "路線 #\(line.rawValue) 指定的股道經過這段軌道。請先清除該路線的指定股道。"
            )
        case .trackEdgeHasPlatform(let edge):
            language.text(
                "A station has a platform on \(edge.displayText(in: language).lowercased()). Remove the platform first.",
                "\(edge.displayText(in: language)) 上有車站的月台。請先拆除月台。"
            )
        case .invalidPlatform:
            language.text(
                "A platform must lie on a level stretch of one edge and not overlap another platform.",
                "月台必須位於同一個軌段上的平坦區間，而且不能與其他月台重疊。"
            )
        case .trackReserved(let id):
            language.text(
                "Train #\(id.rawValue) holds that track under traffic control. Wait for it to clear the route.",
                "在交通控制下，這段軌道由列車 #\(id.rawValue) 預約中。請等它讓出進路。"
            )
        case .trainsShareTrack(let first, let second):
            language.text(
                "Trains #\(first.rawValue) and #\(second.rawValue) need the same track, so traffic control can't be turned on. Move one of them first.",
                "列車 #\(first.rawValue) 與 #\(second.rawValue) 需要同一段軌道，所以無法開啟交通控制。請先移動其中一台。"
            )
        case .invalidStationDemand:
            // Money's text is only the digits, grouped by thousands.
            language.text(
                "A station starts 0 to \(Money(StationDemand.maximumDailyTrips).displayText) trips a day.",
                "車站每天的出發旅次是 0 到 \(Money(StationDemand.maximumDailyTrips).displayText)。"
            )
        case .invalidFareRules:
            language.text(
                "Fares must be 0 or more, and distance steps must start at 0 km, follow on without gaps, and end with one that has no end.",
                "票價須為非負金額；階梯票價的區間須從 0 公里開始連續銜接，最後一個區間的結束距離須留空。"
            )
        case .invalidLoanAmount:
            language.text(
                "Loans are borrowed and repaid \(CompanyAccounts.loanStep.moneyText) at a time, up to \(CompanyAccounts.maximumLoan.moneyText) in all, and no more than is owed.",
                "貸款以每次 \(CompanyAccounts.loanStep.moneyText) 借入與償還，總額最多 \(CompanyAccounts.maximumLoan.moneyText)，償還不能超過欠款。"
            )
        case .loanNeedsManagement:
            language.text("Only a managed company can borrow.", "只有經營模式的公司可以貸款。")
        case .stationDemandFromLand:
            language.text(
                "A managed company's ridership comes from the land round its stations.",
                "經營模式的運量來自車站周邊的土地，不能直接設定。"
            )
        case .invalidTransferGroup:
            language.text("A station cannot be linked with itself.", "車站不能和自己組成轉乘群組。")
        case .invalidLand:
            language.text(
                "Each cell of land must lie in the world, appear once, and hold 0 to \(Money(Land.maximumPerCell).displayText) residents and jobs, not both 0.",
                "每格土地須在世界範圍內、只列一次，居民與就業各 0 到 \(Money(Land.maximumPerCell).displayText)，且不能都是 0。"
            )
        }
    }
}

extension Money {
    /// The amount with thousands separators, such as "1,000,000".
    ///
    /// Deterministic rather than locale-dependent, so it reads the same in
    /// every message and test.
    public var displayText: String {
        let digits = String(amount.magnitude)
        var text = amount < 0 ? "-" : ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                text.append(",")
            }
            text.append(digit)
        }
        return text
    }
}

extension GameTime {
    /// Day and time of day, such as "Day 1 · 08:30", rounded down to the
    /// minute. Second 0 is the start of day 1. Display only: GameCore has
    /// no calendar.
    public func displayText(in language: DisplayLanguage) -> String {
        let (day, minuteOfDay) = dayAndMinute
        let time = "\(Self.twoDigits(minuteOfDay / 60)):\(Self.twoDigits(minuteOfDay % 60))"
        return language.text("Day \(day + 1) · \(time)", "第 \(day + 1) 日 · \(time)")
    }

    /// ``displayText(in:)`` with the seconds, such as "Day 1 · 08:30:15".
    public func displayTextWithSeconds(in language: DisplayLanguage) -> String {
        "\(displayText(in: language)):\(Self.twoDigits(secondOfMinute))"
    }

    /// The day (from 0) and the minute of that day, also before second 0.
    private var dayAndMinute: (day: Int64, minuteOfDay: Int64) {
        var day = minute / Self.minutesPerDay
        var minuteOfDay = minute % Self.minutesPerDay
        if minuteOfDay < 0 {
            minuteOfDay += Self.minutesPerDay
            day -= 1
        }
        return (day, minuteOfDay)
    }

    private static func twoDigits(_ value: Int64) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

extension GameClock {
    /// The clock as the HUD shows it: ``GameTime/displayText(in:)``, with
    /// the seconds (``GameTime/displayTextWithSeconds(in:)``) while they
    /// matter, at a speed slower than a minute a tick or between whole
    /// minutes.
    public func displayText(in language: DisplayLanguage) -> String {
        now.isWholeMinute && (speed == .paused || speed.tenthsPerTick >= GameSpeed.normal.tenthsPerTick)
            ? now.displayText(in: language) : now.displayTextWithSeconds(in: language)
    }
}

extension GameSpeed {
    /// Compact label for the speed controls: how many times real time it
    /// runs at, as the host ticks every 100 ms.
    public func label(in language: DisplayLanguage) -> String {
        switch self {
        case .paused: language.text("Pause", "暫停")
        case .x1: "1×"
        case .x10: "10×"
        case .x60: "60×"
        case .normal: "600×"
        case .double: "1200×"
        }
    }

    /// Spoken name, since "1×" reads poorly aloud.
    public func accessibilityName(in language: DisplayLanguage) -> String {
        switch self {
        case .paused: language.text("Paused", "已暫停")
        case .x1: language.text("Real time", "真實時間")
        case .x10: language.text("10 times real time", "真實時間的 10 倍")
        case .x60: language.text("60 times real time", "真實時間的 60 倍")
        case .normal: language.text("600 times real time", "真實時間的 600 倍")
        case .double: language.text("1200 times real time", "真實時間的 1200 倍")
        }
    }
}

extension GameSession {
    /// What the inspector shows about the selection (Stage F1): the
    /// selected station (see ``GameWorld/stationSummary(_:in:)``) and who
    /// waits there by line and direction (G1c); or the train a tap on the
    /// map picked (``GameSession/tappedTrainID``, see
    /// ``GameWorld/trainSummary(of:in:)``). `nil` when neither is
    /// selected.
    public func selectionText() -> String? {
        if let station = selectedStation {
            let summary = world.stationSummary(station.id, in: language)
            guard let waiting = world.waitingSummary(at: station.id, in: language) else { return summary }
            return "\(summary) · \(waiting)"
        }
        if let train = tappedTrainID, let summary = world.trainSummary(of: train, in: language) {
            return summary
        }
        return nil
    }
}

extension TrainType {
    /// The type's name, as the reference labels it (`TRAIN_TYPES[type].label`,
    /// `metroTrainTypeLabel`): "Type B" / "B型", "Maglev" / "磁浮".
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .a, .b, .c, .l, .d: language.text("Type \(rawValue)", "\(rawValue)型")
        case .apm: "APM"
        case .maglev: language.text("Maglev", "磁浮")
        case .skyRail: language.text("Sky rail", "雲軌")
        case .monorail: language.text("Monorail", "單軌")
        }
    }
}

extension Train {
    /// The type of its cars, what each carries and its doors:
    /// "Type B · 260 a car · 4 doors", or "Standard car · 320 a car · 4 doors".
    public func typeText(in language: DisplayLanguage) -> String {
        Self.typeText(type, in: language)
    }

    /// The same for a train of cars of `type` (`nil`: the standard car).
    public static func typeText(_ type: TrainType?, in language: DisplayLanguage) -> String {
        let name = type?.title(in: language) ?? language.text("Standard car", "標準車")
        let perCar = type?.ratedCapacityPerCar ?? ratedCapacityPerCar
        let doors = type?.doorsPerCar ?? ServiceDwell.doorsPerCar
        return language.text("\(name) · \(perCar) a car · \(doors) doors", "\(name) · 每節 \(perCar) 人 · \(doors) 門")
    }
}

extension LineColor {
    /// "#EF5350", as the reference writes a line's colour.
    public var hexText: String {
        let digits = String(rgb, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }
}
