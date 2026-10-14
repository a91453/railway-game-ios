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
            let edgeText = edgeCount == 1 ? "1 track section" : "\(edgeCount) track sections"
            return "\(stationText) · \(edgeText)"
        case .traditionalChinese:
            return "\(stationCount) 座車站 · \(edgeCount) 段軌道"
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

    /// How near a station must be for a train to be "near" it: 500 m.
    static let nearStationReach: Int64 = 500 * WorldCoordinate.unitsPerMetre

    /// Where train `id` is, in the player's words (author's report,
    /// 2026-10-14: the track number and "units" meant nothing to a
    /// player): the nearest station, "Near Central" within
    /// ``nearStationReach`` or "1.2 km from Central"; "Not on the track"
    /// while unplaced, "On the track" with no station. Where it is going
    /// is ``trainPathStatusText(of:in:)``'s. `nil` for an unknown train.
    public func trainWhereText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let train = train(id: id) else { return nil }
        guard let position = train.position else { return train.positionText(in: language) }
        guard let point = location(of: position)?.position.plan else { return language.text("On the track", "在軌道上") }
        var nearest: (station: Station, squared: Int64)?
        for station in stations {
            let dx = station.location.x - point.x, dy = station.location.y - point.y
            let squared = dx * dx + dy * dy
            if nearest == nil || squared < nearest!.squared { nearest = (station, squared) }
        }
        guard let nearest else { return language.text("On the track", "在軌道上") }
        if nearest.squared <= Self.nearStationReach * Self.nearStationReach {
            return language.text("Near \(nearest.station.name)", "在 \(nearest.station.name) 附近")
        }
        let distance = NetworkBuilding.distanceText(Int64(Double(nearest.squared).squareRoot().rounded()), in: language)
        return language.text("\(distance) from \(nearest.station.name)", "距 \(nearest.station.name) \(distance)")
    }
}

extension TrainPosition {
    /// Where a train is, as GameCore records it, in whole metres: "Track #3
    /// forward, 4 m along". The cards show ``GameWorld/trainWhereText(of:in:)``.
    public func displayText(in language: DisplayLanguage) -> String {
        switch self {
        case .onEdge(let traversal, let offset):
            language.text(
                "\(traversal.edge.displayText(in: language)) \(traversal.direction == .forward ? "forward" : "backward"), \(NetworkBuilding.lengthText(offset, in: language)) along",
                "\(traversal.edge.displayText(in: language)) \(traversal.direction == .forward ? "正向" : "反向")，距起點 \(NetworkBuilding.lengthText(offset, in: language))"
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
    /// "Track #3".
    public func displayText(in language: DisplayLanguage) -> String {
        switch self {
        case .edge(let number): language.text("Track #\(number)", "軌段 #\(number)")
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

    /// Whether the train has a path left on the track network: an edge
    /// beyond the one it is on, or a stop ahead on this one.
    var hasPathAhead: Bool {
        guard case .onEdge(_, let offset)? = position else { return false }
        if !movement.remainingEdges.isEmpty { return true }
        guard let end = movement.end else { return false }
        return end > offset
    }

    /// The path the train has left on the track network: "No path ahead",
    /// "Path: 1 more edge, Track #4",
    /// "Path: 3 more edges, ending on Track #9", with ", stopping 47 m
    /// along it" when it stops part of the way along the last (Stage S5),
    /// or "Path: stops 16 m ahead" on the edge it is on.
    public func pathText(in language: DisplayLanguage) -> String {
        guard case .onEdge(_, let offset)? = position else { return language.text("No path ahead", "前方沒有路徑") }
        let edges = movement.remainingEdges
        guard let last = edges.last else {
            guard let end = movement.end, end > offset else { return language.text("No path ahead", "前方沒有路徑") }
            let ahead = NetworkBuilding.distanceText(end - offset, in: language)
            return language.text("Path: stops \(ahead) ahead", "路徑：前方 \(ahead) 處停車")
        }
        let edge = last.displayText(in: language)
        let stop = movement.end.map {
            let along = NetworkBuilding.lengthText($0, in: language)
            return language.text(", stopping \(along) along it", "，在其 \(along) 處停車")
        } ?? ""
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
    /// Not enough cash for what `action` (as ``PlayerCommand/actionText(in:)``
    /// words it, such as "buy a train") costs: `required`, with
    /// `available` in hand, in whole dollars as the cash shows them
    /// (``Money/shortfallTexts(required:available:)``).
    public static func insufficientFundsText(
        required: Money, available: Money, doing action: String?, in language: DisplayLanguage
    ) -> String {
        let (required, available) = Money.shortfallTexts(required: required, available: available)
        guard let action else {
            return language.text(
                "Not enough cash: this costs \(required) and you have \(available).",
                "餘額不足：需要 \(required)，目前只有 \(available)。"
            )
        }
        return language.text(
            "Not enough cash to \(action): it costs \(required) and you have \(available).",
            "餘額不足，無法\(action)：需要 \(required)，目前只有 \(available)。"
        )
    }

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
            Self.insufficientFundsText(required: required, available: available, doing: nil, in: language)
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
        case .trainInService(let id):
            language.text(
                "Train #\(id.rawValue) is on the track or on a line. Take it off the line and the track first.",
                "列車 #\(id.rawValue) 還在軌道或路線上。請先把它從路線與軌道上撤下。"
            )
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
        case .invalidLineDwell:
            language.text(
                "A train stays at a stop \(ServiceDwell.minimum) s to \(ServiceLine.maximumDwellSeconds / 60) min.",
                "停站時間要在 \(ServiceDwell.minimum) 秒到 \(ServiceLine.maximumDwellSeconds / 60) 分鐘之間。"
            )
        case .invalidServiceWindow:
            language.text(
                "A line opens between 00:00 and 23:59 and closes after it opens, by 06:00 the next morning.",
                "開班時間須在 00:00 到 23:59 之間，收班時間須晚於開班時間，最晚到次日 06:00。"
            )
        case .invalidTrainsInService:
            language.text("A line runs from 0 to 1,000 trains at each level.", "路線每個時段的上線列車數要在 0 到 1,000 列之間。")
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
            language.text("Choose a route for a leg of this service.", "請為這個停站模式的路段選擇進路。")
        case .invalidLineRuns:
            language.text(
                "A timetable's trains each run between two of the line's stops at times that never go back. A ring, a line with patterns or one calling at a station twice has no timetable.",
                "時刻表的每一班車都在路線的兩站之間行駛，時間不能倒退。環線、有停站模式或重複停靠同一站的路線不能有時刻表。"
            )
        case .invalidLinePattern:
            language.text(
                "A pattern calls at two of its line's stops or more, in the line's order. A ring has no patterns.",
                "停站模式至少要依路線的順序，停靠路線上的兩站以上。環線不能有停站模式。"
            )
        case .unknownLinePattern(let index):
            language.text("The line has no pattern #\(index + 1).", "這條路線沒有停站模式 #\(index + 1)。")
        case .invalidTrainLength:
            language.text(
                "A train has \(Train.minimumCars) to \(Train.maximumCars) cars.",
                "列車可以有 \(Train.minimumCars) 到 \(Train.maximumCars) 節車廂。"
            )
        case .unknownTrackNode:
            language.text(
                "That point of the track network no longer exists.",
                "這個軌道接點已經不存在。"
            )
        case .unknownTrackEdge:
            language.text(
                "That track no longer exists.",
                "這段軌道已經不存在。"
            )
        case .invalidTrackGeometry:
            language.text(
                "Track can't be built there: it must stay on the map within 64 m of the ground, start and end at different points, and run smoothly.",
                "這裡不能建軌道：軌道必須在地圖內、與地面的高度差在 64 公尺以內、起點與終點不能是同一點，而且線形要平順。"
            )
        case .trackNodeInUse:
            language.text(
                "Track still ends there. Remove that track first.",
                "還有軌道接在這裡。請先拆除那段軌道。"
            )
        case .trackEdgeInUse:
            language.text(
                "A train is on that track. Take the train off the track first.",
                "這段軌道上有列車。請先把列車移出軌道。"
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
        case .trackConflict:
            language.text(
                "That track would cross another track without 8 m between them. Pass over or under it, or join the two tracks where they meet.",
                "這段軌道會與另一段軌道交叉，但兩者的高度差不到 8 公尺。請從上方或下方通過，或讓兩段軌道在交會處相接。"
            )
        case .trackTooClose:
            language.text(
                "That track would run less than 4 m beside another track. Keep parallel tracks 4 m apart, centre to centre, or pass 8 m over or under.",
                "這段軌道與另一段軌道並行時距離不到 4 公尺。平行的軌道中心之間至少要 4 公尺，或上下相差 8 公尺。"
            )
        case .tracksWouldBeTooClose:
            language.text(
                "Without that track, two tracks nearby would run less than 4 m apart with no junction near. Remove one of them first.",
                "拆掉這段軌道之後，附近兩段軌道之間會不到 4 公尺，又沒有相接的交會點。請先拆掉其中一條。"
            )
        case .trackEdgeInLineRoute(let line):
            language.text(
                "Line #\(line.rawValue)'s chosen path runs along that track. Clear the line's path first.",
                "路線 #\(line.rawValue) 指定的進路經過這段軌道。請先清除該路線指定的進路。"
            )
        case .trackEdgeHasPlatform:
            language.text(
                "A station has a platform on that track. Remove the platform first: in Network, choose Remove, tap that track and tap “Remove platform”.",
                "這段軌道上有車站的月台。請先拆除月台：在「路網」選「拆除」，點這段軌道，再按「拆除月台」。"
            )
        case .invalidPlatform:
            language.text(
                "A platform must lie on a level stretch of a single track and not overlap another platform.",
                "月台必須位於同一段軌道的平坦區間，而且不能與其他月台重疊。"
            )
        case .trackReserved(let id):
            language.text(
                "Train #\(id.rawValue)'s route runs over that track. Wait for it to pass.",
                "列車 #\(id.rawValue) 的路線要經過這段軌道，請等它通過。"
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
                "經營模式的客源來自車站周邊的土地，不能直接設定。"
            )
        case .invalidTransferGroup:
            language.text("A station cannot be linked with itself.", "車站不能和自己組成轉乘群組。")
        case .invalidScenario:
            language.text("This challenge cannot be started here.", "這個挑戰無法在這裡開始。")
        case .trainTypeUnavailable(let type?):
            language.text(
                "\(type.title(in: language)) is not available in this era.",
                "這個年代還沒有\(type.title(in: language))。"
            )
        case .trainTypeUnavailable(nil):
            language.text(
                "\(Train.standardCarName(in: language)) is not available in this era.",
                "這個年代還沒有\(Train.standardCarName(in: language))。"
            )
        case .buildingOverlaps(let id):
            language.text("That would stand on building #\(id.rawValue).", "這裡已經有建物 #\(id.rawValue)。")
        case .buildingOnTrack:
            language.text("A building cannot stand on or right beside track.", "建物不能蓋在軌道上或緊貼軌道。")
        case .buildingOnStation(let id):
            language.text("A building cannot stand on station #\(id.rawValue).", "建物不能蓋在車站 #\(id.rawValue) 上。")
        case .unknownPlacedBuilding(let id):
            language.text("There is no building #\(id.rawValue).", "沒有建物 #\(id.rawValue)。")
        case .invalidZoneArea:
            language.text(
                "Zone cells inside the map, at most \(Zoning.maximumSide) cells a side at a time.",
                "分區要在地圖內，一次最多 \(Zoning.maximumSide) × \(Zoning.maximumSide) 格。"
            )
        case .onWater:
            language.text("Nothing can be built or zoned on water.", "水上不能蓋建物，也不能劃分區。")
        case .onSteepSlope:
            language.text("The hillside is too steep to build or zone on.", "坡度太陡，不能蓋建物，也不能劃分區。")
        case .needsShore:
            language.text("A wharf or a marina goes on the shore, part over the water.", "漁人碼頭與遊艇港要蓋在岸邊，一部分在水上。")
        case .groundNotLoaded:
            language.text("The ground there has not been read yet.", "那裡的地面高度還沒有讀入。")
        case .trackOverWater:
            language.text(
                "Track crosses water only on a bridge at least 4 m above it, or in a tunnel at least 10 m below.",
                "軌道要過水只能用橋（離水面至少 4 公尺）或隧道（水面下至少 10 公尺）。"
            )
        case .structureTooHigh:
            language.text("A viaduct or bridge stands at most 64 m above the ground.", "高架或橋離地面最多 64 公尺。")
        case .freightNotEnabled:
            language.text("This game has no freight.", "這局遊戲沒有貨運。")
        case .freightFacilityExists(let id):
            language.text("Station #\(id.rawValue) already has a freight yard.", "車站 #\(id.rawValue) 已經有貨運場。")
        case .noFreightFacility(let id):
            language.text("Station #\(id.rawValue) has no freight yard.", "車站 #\(id.rawValue) 沒有貨運場。")
        case .buildingMaterialsNotEnabled:
            language.text("This game has no building materials.", "這局遊戲沒有建材。")
        case .mapExpansionNotEnabled:
            language.text("This map is not bought tile by tile.", "這張地圖沒有分區塊購買。")
        case .mapExpansionEnabled:
            language.text("This map is bought tile by tile already.", "這張地圖已經是分區塊購買。")
        case .invalidMapTile:
            language.text("That tile is not on the map.", "那一塊不在地圖上。")
        case .invalidRidersStep:
            language.text("The riders each tile needs must be at least 1.", "每塊要的每日運量至少是 1 人次。")
        case .mapTileOwned:
            language.text("You own that tile already.", "這一塊已經是你的了。")
        case .mapTileNotAdjacent:
            language.text("Buy a tile next to one you own.", "只能買和已擁有區塊相鄰的一塊。")
        case .mapExpansionLocked(let riders):
            language.text(
                "Carry \(Money(riders).displayText) riders in a day to buy one more tile.",
                "要有一天的運量達到 \(Money(riders).displayText) 人次，才能再買一塊。"
            )
        case .tourismNotEnabled:
            language.text("This game has no tourism.", "這局遊戲沒有觀光。")
        case .unknownAttraction:
            language.text("There is no such attraction.", "沒有這個景點。")
        case .attractionMaxedOut:
            language.text("The souvenir shop is at its top level.", "名產店已經是最高等級。")
        case .cityRequestsNotEnabled:
            language.text("This game has no city requests.", "這局遊戲沒有城市委託案。")
        case .unknownCityRequest:
            language.text("That request is no longer open.", "這件委託已經不在了。")
        case .cityRequestLimitReached(let limit):
            language.text(
                "The city trusts you with \(limit) request\(limit == 1 ? "" : "s") at a time: finish one first.",
                "以目前的信賴度，同時只能承接 \(limit) 件委託，先完成一件吧。"
            )
        case .depotIsLineStop:
            language.text(
                "A depot cannot be a line's stop: trains only wait there out of service.",
                "機廠不能當路線的停靠站：列車只在那裡停放，不載客。"
            )
        case .notADepot:
            language.text("That station is not a depot.", "這個車站不是機廠。")
        case .stationIsDepot:
            language.text("A depot has no shops.", "機廠不能開店。")
        case .stationHasCommerce:
            language.text("This station has shops: demolish them before making it a depot.", "這個車站有商業：先拆除商業，才能改成機廠。")
        case .stationCommerceMaxedOut:
            language.text("The station's shops are at their top level.", "這一站的商業已經是最高等級。")
        case .noStationCommerce:
            language.text("This station has no shops.", "這個車站沒有商業。")
        case .depotInUse:
            language.text("A line keeps its trains at this depot: give that line another depot first.", "有路線把列車停在這個機廠：先替那條路線換一個機廠。")
        case .depotListedTwice:
            language.text("This depot is already one of the line's.", "這個機廠已經是這條路線的了。")
        case .depotBlocksLine:
            language.text(
                "No line runs over a depot's sidings, and a line would then have no way along its stops.",
                "路線不能走機廠的停車線，設成機廠會讓一條路線走不通。"
            )
        case .mapTileNotOwned:
            language.text("You don't own this land yet: buy the tile with Expand the Map first.", "這塊地還不是你的，請先用「擴建地圖」買下這一塊。")
        case .invalidGround:
            language.text(
                "Each block of the ground's heights must lie in the world and be read once.",
                "每個地面高度的區塊須在世界範圍內，而且只讀入一次。"
            )
        case .invalidTerrain:
            language.text(
                "Each cell of water must lie in the world, appear once and have no land on it.",
                "每格水域須在世界範圍內、只列一次，而且上面沒有土地。"
            )
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

/// The game's calendar (secretary room, decision 175). GameCore has no
/// calendar, only days; the display gives them the one the game's rules
/// already use: a year of 360 days, twelve months of 30
/// (``FinancePeriod``), the first day a Monday (``StationDemand/weekday(ofDay:)``).
public struct GameDate: Hashable, Sendable {
    /// The game day, from 0.
    public let day: Int64

    /// `value / divisor` rounded down, also for a day before the start.
    static func floorDivide(_ value: Int64, _ divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }

    public init(day: Int64) {
        self.day = day
    }

    /// The year, from 1.
    public var year: Int64 { GameDate.floorDivide(day, FinancePeriod.year.days) + 1 }
    /// The month, 1 to 12.
    public var month: Int { Int(GameDate.floorDivide(day, FinancePeriod.month.days) % 12 + 12) % 12 + 1 }
    /// The day of the month, 1 to 30.
    public var dayOfMonth: Int { Int(((day % 30) + 30) % 30) + 1 }
    /// 0 for Sunday to 6 for Saturday.
    public var weekday: Int { StationDemand.weekday(ofDay: day) }

    /// "Sat" or "六".
    public func weekdayName(in language: DisplayLanguage) -> String {
        let english = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let chinese = ["日", "一", "二", "三", "四", "五", "六"]
        return language.text(english[weekday], chinese[weekday])
    }

    /// "Year 2 · May 12 (Sat)" or "第 2 年 5 月 12 日（六）".
    public func text(in language: DisplayLanguage) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return language.text(
            "Year \(year) · \(months[month - 1]) \(dayOfMonth) (\(weekdayName(in: language)))",
            "第 \(year) 年 \(month) 月 \(dayOfMonth) 日（\(weekdayName(in: language))）"
        )
    }

    /// "May 12 (Sat)" or "5/12（六）": the short form of a forecast row.
    public func shortText(in language: DisplayLanguage) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return language.text(
            "\(months[month - 1]) \(dayOfMonth) (\(weekdayName(in: language)))",
            "\(month)/\(dayOfMonth)（\(weekdayName(in: language))）"
        )
    }
}

extension GameTime {
    /// The date of the day this time is in.
    public var date: GameDate {
        GameDate(day: GameDate.floorDivide(seconds, Self.secondsPerDay))
    }

    /// The HUD's clock with the calendar: "Year 2 · May 12 (Sat) 08:40",
    /// "第 2 年 5 月 12 日（六）08:40", rounded down to the minute.
    public func calendarText(in language: DisplayLanguage) -> String {
        let minuteOfDay = (minute % Self.minutesPerDay + Self.minutesPerDay) % Self.minutesPerDay
        let time = "\(Self.twoDigits(minuteOfDay / 60)):\(Self.twoDigits(minuteOfDay % 60))"
        return language.text("\(date.text(in: language)) \(time)", "\(date.text(in: language))\(time)")
    }

    /// The status board's shorter clock (decision 226), for when the
    /// whole date leaves no room for one row: "Y2 May 12 (Sat) 08:40",
    /// "2 年 5/12（六）08:40".
    public func shortCalendarText(in language: DisplayLanguage) -> String {
        let minuteOfDay = (minute % Self.minutesPerDay + Self.minutesPerDay) % Self.minutesPerDay
        let time = "\(Self.twoDigits(minuteOfDay / 60)):\(Self.twoDigits(minuteOfDay % 60))"
        let day = date.shortText(in: language)
        return language.text("Y\(date.year) \(day) \(time)", "\(date.year) 年 \(day)\(time)")
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

extension GameClock {
    /// The clock with the calendar (decision 175), as the HUD shows it:
    /// ``GameTime/calendarText(in:)``, with the seconds while they matter
    /// (see ``displayText(in:)``).
    public func calendarText(in language: DisplayLanguage) -> String {
        withSecondsWhileTheyMatter(now.calendarText(in: language))
    }

    /// ``GameTime/shortCalendarText(in:)`` as the HUD shows it, with the
    /// seconds while they matter (decision 226).
    public func shortCalendarText(in language: DisplayLanguage) -> String {
        withSecondsWhileTheyMatter(now.shortCalendarText(in: language))
    }

    private func withSecondsWhileTheyMatter(_ text: String) -> String {
        guard !(now.isWholeMinute && (speed == .paused || speed.tenthsPerTick >= GameSpeed.normal.tenthsPerTick)) else { return text }
        let seconds = now.secondOfMinute
        return "\(text):\(seconds < 10 ? "0" : "")\(seconds)"
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
        case .fast: "6000×"
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
        case .fast: language.text("6000 times real time, fast forward", "真實時間的 6000 倍，快轉")
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
        if let id = selectedBuildingID, let text = buildingInspectorText(of: id) {
            return text
        }
        if let edge = selectedTrackEdge, let text = trackInspectionText(of: edge) {
            return text
        }
        return nil
    }
}

extension TrainType {
    /// The type's name, as the author named them for players in Taiwan
    /// (decision 171). The reference labels its types
    /// `TRAIN_TYPES[type].label` ("A型" to "D型", "APM", "磁浮", "云轨",
    /// "单轨"): a letter or a brand tells a player there nothing. The metros
    /// are named for their size or build ("大型捷運", "多門捷運"), the
    /// others for what they are ("磁浮列車", "自動接駁列車"). Only this text
    /// changes: a type is saved and replayed by its raw value.
    /// Each type's name has a row in ``names``, by its code (decision 225);
    /// a type without one is a mistake `TrainTypeNameTests` catches.
    public func title(in language: DisplayLanguage) -> String {
        guard let name = Self.names[rawValue] else { preconditionFailure("The train type \(rawValue) has no name.") }
        return language.text(name.english, name.chinese)
    }

    /// The names, by code: English, then Traditional Chinese.
    static let names: [String: (english: String, chinese: String)] = [
        "A": ("Large metro", "大型捷運"),
        "B": ("Medium metro", "中型捷運"),
        "C": ("Light metro", "輕型捷運"),
        "L": ("Linear-motor metro", "線性馬達捷運"),
        "D": ("Multi-door metro", "多門捷運"),
        "APM": ("Automated shuttle", "自動接駁列車"),
        "MAGLEV": ("Maglev train", "磁浮列車"),
        "SKYRAIL": ("Light monorail", "輕型單軌"),
        "MONORAIL": ("Monorail train", "單軌列車"),
        "STEAM": ("Steam train", "蒸汽列車"),
        "HSR": ("High-speed set", "高鐵列車"),
        "EMU3000": ("New Tze-Chiang", "新自強號"),
    ]
}

extension Train {
    /// The type of its cars, what each carries and its doors:
    /// "Medium metro · 260 a car · 4 doors", or "General train · 320 a car · 4
    /// doors".
    public func typeText(in language: DisplayLanguage) -> String {
        Self.typeText(type, in: language)
    }

    /// The name of the car a train without a type has (decision 171):
    /// "General train" / "通用列車". Code and documents still call it the
    /// standard car.
    public static func standardCarName(in language: DisplayLanguage) -> String {
        language.text("General train", "通用列車")
    }

    /// The same for a train of cars of `type` (`nil`: the standard car).
    public static func typeText(_ type: TrainType?, in language: DisplayLanguage) -> String {
        let name = type?.title(in: language) ?? standardCarName(in: language)
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
