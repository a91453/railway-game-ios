import Foundation
import GameCore

// Achievements (ARCHITECTURE decision 181): 28 marks of what the player
// has done, kept on the device across games, checked each midnight. The
// list, its "how to get it" lines and its progress readings are the
// reference's (`Railway/site_archive_clean/index.html`: `ACHIEVEMENTS`,
// `ACH_TESTS`, `ACH_PROG`, `achContext`), which judged them by the rides the
// player followed; here they are judged by the state of the game, and the
// marks the reference had no game for (the challenges, the company's
// buildings, freight, the map) are this project's. Nothing here is game
// state: the record is a file beside the saves, like the challenge
// records, and GameCore is untouched.

/// What a world has, read once for every achievement's test (the
/// reference's `achContext`).
public struct AchievementFacts: Hashable, Sendable {
    public var figures: CompanyFigures
    /// Whether any day the accounts keep had freight delivered.
    public var hasDeliveredFreight = false
    /// The company's own buildings (decision 94).
    public var companyBuildings = 0
    /// The tiles of the map bought beyond the first (decision 160).
    public var tilesBought = 0
    /// Whether a D4 building stands within 800 m of an open station.
    public var towerByAStation = false
    /// Whether today is the day after the typhoon season (1 July to the
    /// end of October) and the company owes nothing: no loan, cash not
    /// below zero.
    public var typhoonSeasonOverDebtFree = false
    public var hasRingLine = false
    /// A line with trains whose service starts before 05:00.
    public var hasEarlyLine = false
    /// A line with trains that runs past midnight.
    public var hasOvernightLine = false
    /// A train of the High Speed Rail's performance or type.
    public var hasHighSpeedTrain = false
    /// The most passenger lines calling at one station.
    public var mostLinesAtAStation = 0
    /// The longest passenger line, station to station in straight lines,
    /// in metres.
    public var longestLineMetres: Int64 = 0
    /// The most calls of a passenger line.
    public var mostStopsOnALine = 0
    public var trains = 0
    /// The scenario completed with gold, if any, and the completed
    /// scenario's ID.
    public var completedGold = false
    public var completedScenario: String?

    public init(figures: CompanyFigures = CompanyFigures()) {
        self.figures = figures
    }

    public init(world: GameWorld) {
        figures = CompanyFigures(world: world)
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        hasDeliveredFreight = world.accounts.days.contains { $0.freightRevenue > .zero }
        companyBuildings = world.placedBuildings.count
        tilesBought = max(0, (world.mapExpansion?.owned.count ?? 1) - 1)
        typhoonSeasonOverDebtFree = today % FinancePeriod.year.days == AchievementFacts.typhoonSeasonEnd
            && world.accounts.loan == .zero && world.economy.balance >= .zero
        let served = CompanyFigures.servedCells(in: world)
        towerByAStation = world.buildings.all.contains { building in
            building.density == .d4 && building.cells.contains { served.contains($0) }
        }
        var linesAt: [StationID: Int] = [:]
        for line in world.lines where !line.isFreight {
            let running = !line.trains.isEmpty || line.patterns.contains { !$0.trains.isEmpty }
            for stop in Set(line.stops) { linesAt[stop, default: 0] += 1 }
            mostStopsOnALine = max(mostStopsOnALine, line.stops.count)
            let points = line.stops.compactMap { world.station(id: $0)?.location }
            var length: Int64 = 0
            for (a, b) in zip(points, points.dropFirst()) {
                let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
                length += Int64((dx * dx + dy * dy).squareRoot())
            }
            longestLineMetres = max(longestLineMetres, length / WorldCoordinate.unitsPerMetre)
            guard running else { continue }
            if line.isRing { hasRingLine = true }
            switch line.window {
            case .allDay:
                hasEarlyLine = true
                hasOvernightLine = true
            case .hours(let open, let close):
                if open < 300 { hasEarlyLine = true }
                if close > 1440 { hasOvernightLine = true }
            }
        }
        mostLinesAtAStation = linesAt.values.max() ?? 0
        hasHighSpeedTrain = world.trains.contains { $0.performance == .highSpeed || $0.type == .highSpeed }
        trains = world.trains.count
        if let state = world.scenario, case .completed(_, let rating)? = state.outcome {
            completedScenario = state.scenario.id
            completedGold = rating == .gold
        }
    }

    /// The day of the 360-day year after the typhoon season (1 November).
    static let typhoonSeasonEnd: Int64 = 300
}

/// One achievement (the reference's `ACHIEVEMENTS` entry with its
/// `ACH_TESTS` and `ACH_PROG`).
public struct Achievement: Identifiable, Hashable, Sendable {
    public let id: String
    /// Its SF Symbol.
    public let symbol: String
    let english: (title: String, detail: String, how: String)
    let chinese: (title: String, detail: String, how: String)
    /// How far the facts are towards it, `now` of `need`; `nil` for a mark
    /// that is had or not (the reference's `note` progress).
    let progress: @Sendable (AchievementFacts) -> (now: Int64, need: Int64)?
    let test: @Sendable (AchievementFacts) -> Bool

    public static func == (lhs: Achievement, rhs: Achievement) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public func title(in language: DisplayLanguage) -> String {
        language.text(english.title, chinese.title)
    }

    /// What it asks (the reference's `desc`).
    public func detail(in language: DisplayLanguage) -> String {
        language.text(english.detail, chinese.detail)
    }

    /// How to get it (the reference's `how`).
    public func how(in language: DisplayLanguage) -> String {
        language.text(english.how, chinese.how)
    }

    public func isMet(by facts: AchievementFacts) -> Bool {
        test(facts)
    }

    /// How far `facts` are towards it, or `nil` for a mark that is had or
    /// not.
    public func progress(of facts: AchievementFacts) -> (now: Int64, need: Int64)? {
        progress(facts).map { (min($0.now, $0.need), $0.need) }
    }

    /// "31,200 / 50,000", "12.4 / 50.0 km" for a length (metres).
    public func progressText(of facts: AchievementFacts) -> String? {
        guard let (now, need) = progress(of: facts) else { return nil }
        guard isLength else { return "\(Money(now).displayText) / \(Money(need).displayText)" }
        func km(_ metres: Int64) -> String { WorldBounds.kilometresText(metres * WorldCoordinate.unitsPerMetre) }
        return "\(km(now)) / \(km(need)) km"
    }

    /// Whether its count is a length in metres.
    private var isLength: Bool {
        id.hasPrefix("track") || id == "longLine"
    }

    // MARK: - The list

    /// A mark reached when a count passes `need`.
    private static func count(
        _ id: String, _ symbol: String, need: Int64, _ english: (String, String, String), _ chinese: (String, String, String),
        _ value: @escaping @Sendable (AchievementFacts) -> Int64
    ) -> Achievement {
        Achievement(
            id: id, symbol: symbol, english: english, chinese: chinese, progress: { (value($0), need) }, test: { value($0) >= need }
        )
    }

    /// A mark that is had or not.
    private static func flag(
        _ id: String, _ symbol: String, _ english: (String, String, String), _ chinese: (String, String, String),
        _ test: @escaping @Sendable (AchievementFacts) -> Bool
    ) -> Achievement {
        Achievement(id: id, symbol: symbol, english: english, chinese: chinese, progress: { _ in nil }, test: test)
    }

    /// The 28 achievements, in the order the list shows them.
    public static let all: [Achievement] = [
        // The reference's `first`, `rider5`, `rider15`: rides followed,
        // here riders in a day.
        count("firstFare", "ticket.fill", need: 1,
              ("First Fare", "Take a passenger's first fare", "Build two stations, a line between them and a train: the first rider pays."),
              ("第一筆票收", "收到第一位旅客的車資", "蓋兩座車站、一條路線和一列車，第一位乘客就會付錢。")) { $0.figures.bestDayRiders },
        count("riders1k", "person.2.fill", need: 1_000,
              ("Regulars", "1,000 riders in a day", "Stations in the middle of towns fill trains faster than ones at the edge."),
              ("月台常客", "單日旅客 1,000 人次", "車站蓋在城鎮中心，比蓋在邊緣更快坐滿。")) { $0.figures.bestDayRiders },
        count("riders10k", "person.3.fill", need: 10_000,
              ("Railway Soul", "10,000 riders in a day", "Join two towns: trips between towns are what fill a line."),
              ("鐵道魂", "單日旅客 10,000 人次", "把兩個城鎮連起來：城鎮之間的旅次才坐得滿。")) { $0.figures.bestDayRiders },
        count("riders100k", "person.3.sequence.fill", need: 100_000,
              ("Rush Hour", "100,000 riders in a day", "More trains at the peak and longer trains on the busy lines."),
              ("尖峰時刻", "單日旅客 100,000 人次", "尖峰多開車，忙的路線加長編組。")) { $0.figures.bestDayRiders },
        count("riders1m", "building.columns.fill", need: 1_000_000,
              ("A Million a Day", "1,000,000 riders in a day", "A long-term goal: a network that reaches every town on a large map."),
              ("百萬運量", "單日旅客 1,000,000 人次", "長期目標：路網連到大地圖上的每一個城鎮。")) { $0.figures.bestDayRiders },
        // `km100` to `km5000`: kilometres ridden, here kilometres built.
        count("track10", "point.topleft.down.to.point.bottomright.curvepath.fill", need: 10_000,
              ("Ten Kilometres", "Build 10 km of track", "Each line's track counts, sidings and the second track too."),
              ("十公里", "路網長度 10 km", "每一條軌道都算，側線與複線也算。")) { $0.figures.trackMetres },
        count("track50", "map.fill", need: 50_000,
              ("Across the County", "Build 50 km of track", "Reach for the next town rather than doubling what you have."),
              ("跨越縣境", "路網長度 50 km", "往下一個城鎮延伸，比在原地加線快。")) { $0.figures.trackMetres },
        count("track200", "globe.asia.australia.fill", need: 200_000,
              ("A Thousand Li", "Build 200 km of track", "About Taipei to Taichung: a trunk line between cities."),
              ("千里鐵道", "路網長度 200 km", "大約臺北到臺中的距離：一條城市之間的幹線。")) { $0.figures.trackMetres },
        count("track1000", "globe", need: 1_000_000,
              ("The Thousand-Kilometre Club", "Build 1,000 km of track", "A long-term goal; the whole of Taiwan or a large map bought tile by tile."),
              ("千公里俱樂部", "路網長度 1,000 km", "長期目標：全台灣地圖，或一塊一塊買大的地圖。")) { $0.figures.trackMetres },
        // `long300` and `stops50`: one long ride, one stopping train.
        count("longLine", "arrow.left.and.right", need: 50_000,
              ("In One Go", "A line 50 km long, station to station", "Measured in straight lines from each station to the next."),
              ("一氣呵成", "一條 50 km 以上的路線（站間直線）", "從每一站到下一站的直線距離加起來。")) { $0.longestLineMetres },
        count("stoppingLine", "circle.dotted", need: 20,
              ("Every Station Is a View", "A line calling at 20 stations", "A stopping service that serves every town along the way."),
              ("站站是風景", "一條停靠 20 站以上的路線", "站站都停的路線，沿途城鎮都服務到。")) { Int64($0.mostStopsOnALine) },
        // `early` and `night`: a train's departure, here a line's hours.
        flag("earlyBird", "sunrise.fill",
             ("Early Bird", "A line whose first train leaves before 05:00", "Open the line's hours earlier in its timetable."),
             ("早鳥", "一條 05:00 前就發出首班車的路線", "在路線的時刻表把營運時間提早。")) { $0.hasEarlyLine },
        flag("nightOwl", "moon.stars.fill",
             ("Night Owl", "A line that runs past midnight", "Close the line's hours after 24:00, or run it all day."),
             ("夜行者", "一條跨午夜營運的路線", "把路線的收班時間設在 24:00 以後，或整天營運。")) { $0.hasOvernightLine },
        // `loop`: round the island, here a ring line.
        flag("ringLine", "arrow.triangle.2.circlepath",
             ("Round and Round", "Run a ring line", "Make a line whose last station is its first and send trains round it."),
             ("繞圈圈", "第一條營運中的環狀線", "建一條頭尾相接的路線，並派車行駛。")) { $0.hasRingLine },
        // `day3`: three rides in a day, here three lines at a station.
        count("hub", "point.3.connected.trianglepath.dotted", need: 3,
              ("Interchange", "Three lines calling at one station", "Bring a second and a third line into your busiest station."),
              ("轉乘樞紐", "三條路線共用一站", "把第二、第三條路線接進最忙的車站。")) { Int64($0.mostLinesAtAStation) },
        // `tilting`: the tilting trains, here the High Speed Rail's.
        flag("highSpeed", "bolt.fill",
             ("Bullet Train", "Run a train of the High Speed Rail's performance", "Choose the High Speed Rail for a line on long, straight track."),
             ("子彈列車", "一列高鐵性能的列車", "在又長又直的軌道上，讓路線使用高鐵車種。")) { $0.hasHighSpeedTrain },
        // `stockAll`: the rolling stock collected, here the fleet.
        count("fleet20", "tram.fill", need: 20,
              ("Fleet", "Own 20 trains", "Busy lines need more trains at the peak."),
              ("車隊成形", "擁有 20 列車", "忙的路線在尖峰需要更多列車。")) { Int64($0.trains) },
        // `stn25`, `stn100`: stations collected, here stations built.
        count("stations25", "mappin.and.ellipse", need: 25,
              ("Station Tour", "Build 25 stations", "Every station counts, each line's own and shared ones."),
              ("車站巡禮", "車站 25 座", "每一座車站都算。")) { Int64($0.figures.stations) },
        count("stations50", "mappin.circle.fill", need: 50,
              ("Fifty Stations", "Build 50 stations", "A stop every kilometre or two in town, farther apart between towns."),
              ("五十站", "車站 50 座", "市區每一兩公里一站，城鎮之間站距拉長。")) { Int64($0.figures.stations) },
        count("stations100", "building.2.crop.circle.fill", need: 100,
              ("A Hundred Stations", "Build 100 stations", "A network that reaches every town."),
              ("百站達成", "車站 100 座", "路網連到每一個城鎮。")) { Int64($0.figures.stations) },
        // This project's own: what a company does.
        count("firstBuilding", "building.fill", need: 1,
              ("Developer", "Put up the company's first building", "Build an office or homes by a station: its rent comes every day."),
              ("建商起步", "第一棟公司建物", "在車站旁蓋辦公大樓或住宅，每天收租。")) { Int64($0.companyBuildings) },
        flag("firstFreight", "shippingbox.fill",
             ("First Tonne", "Deliver freight", "Run a freight line from a factory to a station that wants its goods."),
             ("第一噸貨", "第一次送達貨物", "開一條從工廠到需要貨物的車站的貨運路線。")) { $0.hasDeliveredFreight },
        count("firstTile", "square.grid.3x3.topleft.filled", need: 1,
              ("New Ground", "Buy a tile of the map", "On a map bought tile by tile, a best day of riders unlocks the next tile."),
              ("開疆闢土", "買下第一格地圖", "分區購買的地圖上，最佳單日運量會解鎖下一塊。")) { Int64($0.tilesBought) },
        flag("tower", "building.2.fill",
             ("Station Tower", "A D4 tower within 800 m of a station", "Well-served stations raise the buildings round them a density a night."),
             ("站前大樓", "車站 800 m 內出現 D4 大樓", "服務好的車站，周圍的建物每晚會長高一級。")) { $0.towerByAStation },
        flag("typhoonSeason", "tropicalstorm",
             ("Weathered the Storms", "End the typhoon season with no debt", "On 1 November, no loan and cash not below zero."),
             ("安然度颱", "颱風季結束時沒有負債", "11 月 1 日那天沒有借款，現金也不是負的。")) { $0.typhoonSeasonOverDebtFree },
        flag("challengeGold", "medal.fill",
             ("Gold Medal", "Complete a challenge with gold", "Meet every goal within the gold days."),
             ("挑戰金牌", "以金牌完成一項挑戰", "在金牌天數內達成所有目標。")) { $0.completedGold },
        flag("pingxi", "fan.fill",
             ("Pingxi Line", "Complete the Pingxi challenge", "Taiwan railway history: the Pingxi Line's coal and its lantern festival."),
             ("平溪線", "完成平溪線劇本", "台灣鐵道史：平溪線的運煤與天燈節。")) { $0.completedScenario == "history.pingxi" },
        flag("liuMingchuan", "flag.checkered",
             ("Liu Mingchuan's Railway", "Complete the Liu Mingchuan challenge", "Taiwan railway history: Keelung to Hsinchu, milestone by milestone."),
             ("劉銘傳鐵路", "完成劉銘傳劇本", "台灣鐵道史：基隆到新竹，一個里程碑一個里程碑。")) { $0.completedScenario == "history.liuMingchuan" },
    ]

    public static func named(_ id: String) -> Achievement? {
        all.first { $0.id == id }
    }
}

/// The achievements the player has unlocked and when (decision 181): a
/// small JSON file beside the saves (`achievements.data`, beside
/// `challenge-records.data`), not a save. A file that cannot be read is
/// none unlocked; an ID no longer in the list is kept, not shown.
public struct AchievementRecords: Sendable {
    public let file: URL
    /// When each was unlocked, by ID.
    public private(set) var unlocked: [String: Date]

    public static let fileName = "achievements.data"

    private struct Stored: Codable {
        var version: Int
        var unlocked: [String: Date]
    }

    private static let version = 1

    public init(file: URL) {
        self.file = file
        let stored = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        unlocked = stored.flatMap { $0.version <= Self.version ? $0.unlocked : nil } ?? [:]
    }

    /// How many of the list are unlocked.
    public var count: Int {
        Achievement.all.count { unlocked[$0.id] != nil }
    }

    public func isUnlocked(_ achievement: Achievement) -> Bool {
        unlocked[achievement.id] != nil
    }

    /// Unlocks what `facts` meet that is not unlocked yet, writes the file
    /// and returns them, in the list's order.
    public mutating func unlock(meeting facts: AchievementFacts, at date: Date = Date()) -> [Achievement] {
        let new = Achievement.all.filter { unlocked[$0.id] == nil && $0.isMet(by: facts) }
        guard !new.isEmpty else { return [] }
        for achievement in new { unlocked[achievement.id] = date }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(Stored(version: Self.version, unlocked: unlocked)).write(to: file, options: .atomic)
        return new
    }
}

extension GameSession {
    /// Says that `achievements` were unlocked (decision 181): an item each
    /// in the news log, the status line and the coins.
    public func noteAchievements(_ achievements: [Achievement]) {
        guard let first = achievements.first else { return }
        for achievement in achievements {
            news.add(day: world.clock.now.seconds / GameTime.secondsPerDay, .achievement) { language in
                language.text(
                    "Achievement unlocked: \(achievement.title(in: language)) (\(achievement.detail(in: language)))",
                    "解鎖成就：\(achievement.title(in: language))（\(achievement.detail(in: language))）"
                )
            }
        }
        let more = achievements.count - 1
        isMessageKeptOutOfNews = true
        message = StatusMessage(kind: .success, text: more > 0
            ? language.text(
                "Achievement unlocked: \(first.title(in: language)) and \(more) more",
                "解鎖成就：\(first.title(in: language))等 \(achievements.count) 項"
            )
            : language.text("Achievement unlocked: \(first.title(in: language))", "解鎖成就：\(first.title(in: language))"))
        isMessageKeptOutOfNews = false
        playSound?(.income)
    }
}
