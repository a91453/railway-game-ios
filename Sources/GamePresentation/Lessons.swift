import GameCore

// The lessons (ARCHITECTURE decision 266, CORE_LOOP §2, after decision 254):
// short games of one goal each, 1 to 3 stars, each teaching one more thing.
// One state decides what a player has: the lessons passed (kept on the
// device, ``LauncherPreferences``) open the next lesson, and a game played
// as a lesson shows only the tools unlocked by the lessons up to it, read
// from the world's scenario, so a saved lesson keeps them. Every other game
// (free play, the challenges, the demos, saves from before) has them all.
// The tutorial's step engine (decision 188) is each lesson's guide: lesson 1
// is its first part, the line built and run until the first fares, lesson 2
// its second, the line's card and a station's riders.
//
// A lesson is a `Challenge` (decision 86) on a blank map of fixed towns,
// its goals GameCore's `Scenario`: gold, silver and bronze are 3, 2 and 1
// stars. The reference has no lessons, stars or unlocks of railway tools;
// `Railway/island_city_reference_clean/` unlocks its buildings by chapters
// (`g41.js` `UNLOCK`, `unlocked(t)`), which this follows: a lesson passed
// opens the next, and everything is open outside them.

/// A tool a lesson unlocks (decision 266): hidden in the lessons before it.
public enum UnlockableTool: String, CaseIterable, Codable, Sendable {
    /// "Add a Train" on the line card (decision 264).
    case addTrain
    /// The network tool's Loop mode (decision 204), and the line card's
    /// "Add a Passing Loop Here".
    case passingLoop
    /// The network tool's Depot mode (decision 214).
    case depot
    /// The Train tool: trains bought and placed by hand.
    case trainTool
    /// The Building tool.
    case buildingTool
    /// The lines panel's details under Advanced: stopping patterns,
    /// routes, service day, target headways, depots (#497).
    case lineDetails
    /// Decision 271: the track panel's one-tap double track (decision 203's
    /// upgrade).
    case doubleTrack
    /// Decision 271: freight yards and freight lines (decision 155), on in
    /// every new game.
    case freight
}

/// A lesson: a challenge, the tools it unlocks and the steps that guide it.
public struct Lesson: Sendable, Identifiable {
    /// 1, 2, 3…
    public let number: Int
    public let challenge: Challenge
    /// The tools it teaches, open from it on.
    public let unlocks: [UnlockableTool]
    /// Its guide's steps (``Tutorial``), in order; none for a lesson that
    /// only says what to do.
    let guide: [TutorialStep]

    public var id: String { challenge.id }

    /// The towns every lesson is played on: seed 1's, so its targets are
    /// measured on the same map the player gets (decision 266).
    public static let seed: UInt32 = 1

    /// Stars for a rating: gold 3, silver 2, bronze 1.
    public static func stars(for rating: ScenarioRating) -> Int {
        switch rating {
        case .gold: 3
        case .silver: 2
        case .bronze: 1
        }
    }

    /// The tools open in this lesson: those of the lessons up to it.
    public var tools: Set<UnlockableTool> {
        Set(Self.all.prefix(number).flatMap(\.unlocks))
    }

    /// The days for each count of stars: "3 stars: 1 day · 2 stars: 2 days
    /// · 1 star: 3 days".
    public func starsText(in language: DisplayLanguage) -> String {
        let scenario = challenge.scenario(seed: Self.seed, in: GameWorld.newGameBounds)
        func days(_ count: Int64) -> String { language.text("\(count) \(count == 1 ? "day" : "days")", "\(count) 天") }
        return [
            language.text("★★★ within ", "★★★ ") + days(scenario.goldDays),
            language.text("★★ within ", "★★ ") + days(scenario.silverDays),
            language.text("★ within ", "★ ") + days(scenario.deadlineDays),
        ].joined(separator: " · ")
    }

    /// What it teaches, in a line, for its card.
    public func teaches(in language: DisplayLanguage) -> String {
        switch number {
        case 1: language.text("Lay track, build stations and open a line.", "鋪軌道、蓋車站、開路線。")
        case 2: language.text("Extend a line and read its card.", "延長路線，看懂路線卡。")
        case 3: language.text("Run a second train: Add a Train and a passing loop.", "加開第二列車：加開一列車與待避線。")
        case 4: language.text("Open a second line; riders change trains where the lines meet.", "開第二條線，乘客在兩線交會的車站轉乘。")
        case 5: language.text("Double the track so trains no longer wait to pass.", "把單線改成雙線，列車不用再等交會。")
        case 6: language.text("Set when a line runs, how often and where it stops.", "設定路線的營運時段、班距與停靠。")
        case 7: language.text("Build a depot where the trains rest at night.", "蓋一座機廠，列車晚上回去休息。")
        case 8: language.text("Carry freight between two freight yards.", "在兩座貨運場之間載貨。")
        case 9: language.text("Take visitors to a sight and build beside it.", "把遊客載到景點，在旁邊蓋建物。")
        default: language.text("Take on the city's requests for a reward.", "接下城市的委託，完成就有獎勵。")
        }
    }
}

extension Lesson {
    /// The lessons, in order.
    public static let all: [Lesson] = [first, second, third, fourth, fifth, sixth, seventh, eighth, ninth, tenth]

    /// The lesson with `id`, as a save names its scenario.
    public static func named(_ id: String) -> Lesson? {
        all.first { $0.id == id }
    }

    /// The towns of the lessons' map.
    static func towns(in bounds: WorldBounds) -> [PlanPoint] {
        Land.townCentres(seed: seed, in: bounds)
    }

    /// Lesson 9's sight (decision 271): 3 km beyond the second town, on
    /// from the first, where no town's stations reach.
    static func sight(in bounds: WorldBounds) -> PlanPoint {
        let towns = towns(in: bounds)
        let dx = Double(towns[1].x - towns[0].x), dy = Double(towns[1].y - towns[0].y)
        let span = (dx * dx + dy * dy).squareRoot(), reach = Double(3_000 * WorldCoordinate.unitsPerMetre)
        return PlanPoint(x: towns[1].x + Int64(dx / span * reach), y: towns[1].y + Int64(dy / span * reach))
    }

    /// A lesson after the third: one goal of riders a day, its days for
    /// 3, 2 and 1 stars, and what it teaches in a read step (decision 271).
    private static func later(
        _ number: Int, titles: (String, String), stories: (String, String), goals: @escaping @Sendable ([PlanPoint], PlanPoint, WorldBounds) -> [Goal],
        days: (Int64, Int64, Int64), unlocks: [UnlockableTool], step: (title: (String, String), body: (String, String))
    ) -> Lesson {
        Lesson(
            number: number,
            challenge: Challenge(
                id: "lesson.\(number)", titles: titles, stories: stories,
                rules: { _, bounds in
                    Scenario(
                        id: "lesson.\(number)", goals: goals(towns(in: bounds), sight(in: bounds), bounds),
                        goldDays: days.0, silverDays: days.1, deadlineDays: days.2
                    )
                }
            ),
            unlocks: unlocks,
            guide: [TutorialStep(id: "lesson.\(number)", chapter: .service, targets: [], goal: .read, title: step.title, body: step.body)]
        )
    }

    private static func steps(_ ids: [String]) -> [TutorialStep] {
        ids.compactMap { id in Tutorial.standardSteps.first { $0.id == id } }
    }

    /// Lesson 1: a first line, from the first town to the second.
    static let first = Lesson(
        number: 1,
        challenge: Challenge(
            id: "lesson.1",
            titles: ("The First Line", "第一條線"),
            stories: (
                "Two towns, no railway yet. Lay track between them, build a station in each, open a line and watch its first fares come in.",
                "兩座小鎮，還沒有鐵路。在兩鎮之間鋪軌道、各蓋一座車站、開一條線，看第一筆車資進帳。"
            ),
            rules: { _, bounds in
                let towns = Lesson.towns(in: bounds)
                return Scenario(
                    id: "lesson.1",
                    goals: [.connect(points: Array(towns.prefix(2)), radius: Land.catchmentRadius), .dailyRiders(Lesson.firstRiders)],
                    goldDays: 1, silverDays: 2, deadlineDays: 3
                )
            }
        ),
        unlocks: [],
        // The tutorial's first part (decision 188): the line is opened with
        // its train (decision 264), so "Buy … and Start Service" is gone.
        guide: steps([
            "build.network", "map.move", "track.draw", "track.build", "station.mode", "station.first.site", "station.first.build",
            "station.second.site", "station.second.build", "build.done", "line.open", "line.stations", "line.create", "time.play",
            "first.fare",
        ])
    )

    /// Lesson 2: the third town, on the same line.
    static let second = Lesson(
        number: 2,
        challenge: Challenge(
            id: "lesson.2",
            titles: ("The Third Town", "第三個城鎮"),
            stories: (
                "Your line links two towns. Lay track on to the third, add its station to the line, and carry all three.",
                "路線連起了兩座小鎮。把軌道延伸到第三座，把新車站加進路線，三鎮一起載。"
            ),
            rules: { _, bounds in
                Scenario(
                    id: "lesson.2",
                    goals: [.connect(points: Lesson.towns(in: bounds), radius: Land.catchmentRadius), .dailyRiders(Lesson.secondRiders)],
                    goldDays: 2, silverDays: 3, deadlineDays: 5
                )
            }
        ),
        unlocks: [],
        guide: [extendStep] + steps(["line.card.open", "line.card.read", "station.select", "station.ridership"])
    )

    /// Lesson 3: a second train on the first line.
    static let third = Lesson(
        number: 3,
        challenge: Challenge(
            id: "lesson.3",
            titles: ("A Second Train", "多一列車"),
            stories: (
                "One train leaves people waiting. Run a second: the two pass each other at a passing loop on the single track.",
                "一列車跑不完，旅客在等。加開第二列車，兩列在單線中間的待避線交會。"
            ),
            rules: { _, bounds in
                let towns = Lesson.towns(in: bounds)
                return Scenario(
                    id: "lesson.3",
                    goals: [.connect(points: Array(towns.prefix(2)), radius: Land.catchmentRadius), .dailyRiders(Lesson.thirdRiders)],
                    goldDays: 3, silverDays: 4, deadlineDays: 6
                )
            }
        ),
        unlocks: [.addTrain, .passingLoop],
        guide: [addTrainStep]
    )

    /// Lesson 4: a second line, from the first town to the third.
    static let fourth = later(
        4, titles: ("Two Lines", "兩條線"),
        stories: (
            "The third town has no railway yet. Open a second line to it from the first town's station: riders change trains there.",
            "第三座城鎮還沒有鐵路。從第一座城鎮的車站開第二條線過去，乘客會在那一站轉乘。"
        ),
        goals: { towns, _, _ in [.connect(points: towns, radius: Land.catchmentRadius), .dailyRiders(Lesson.fourthRiders)] },
        days: (2, 3, 5), unlocks: [],
        step: (
            ("Open a second line to the third town", "開第二條線到第三座城鎮"),
            (
                "Lay track from the first town's station to the third town and build a station there. Then open Lines, create a new line with the two and open it from its card.",
                "從第一座城鎮的車站鋪軌道到第三座城鎮，在那裡蓋車站。再打開「路線」，用這兩站開新路線，在卡片上按「開通路線」。"
            )
        )
    )

    /// Lesson 5: double track (decision 203's one tap).
    static let fifth = later(
        5, titles: ("Double Track", "雙線"),
        stories: (
            "On single track, trains wait for each other at the passing loops. Double the busiest stretch and they run straight through.",
            "單線上，列車要在待避線等對向車。把最忙的那一段改成雙線，列車就能一路開過去。"
        ),
        goals: { _, _, _ in [.dailyRiders(Lesson.laterRiders)] }, days: (3, 4, 6), unlocks: [.doubleTrack],
        step: (
            ("Tap a stretch of track, then Double Track", "點一段軌道，再按「雙線」"),
            ("The second track is laid beside the first, and the trains keep to their own.", "第二條軌道會鋪在旁邊，兩個方向的列車各走各的。")
        )
    )

    /// Lesson 6: the line's details under Advanced.
    static let sixth = later(
        6, titles: ("Line Details", "路線的細節"),
        stories: (
            "A line can run all day or only at the busy hours, as often as you like, and skip stops. A new line's card sets its hours and trains; later, open Advanced on the line card.",
            "路線可以全天開或只在尖峰開，班距隨你定，也可以跳過某些站。新路線的卡片可以設營運時間與列車；之後再打開路線卡的「進階」。"
        ),
        goals: { _, _, _ in [.dailyRiders(Lesson.laterRiders)] }, days: (3, 4, 6), unlocks: [.lineDetails],
        step: (
            ("Open Lines, then Advanced", "打開「路線」，再打開「進階」"),
            ("Set the service day and how often trains come. Fewer trains cost less; more carry more.", "設定營運時段與班距。車少比較省，車多載得多。")
        )
    )

    /// Lesson 7: a depot.
    static let seventh = later(
        7, titles: ("The Depot", "機廠"),
        stories: (
            "Trains that stop for the night need somewhere to rest. Build a depot at the end of a line and send its trains there.",
            "晚上停駛的列車要有地方休息。在路線的盡頭蓋一座機廠，讓列車回去。"
        ),
        goals: { _, _, _ in [.dailyRiders(Lesson.laterRiders)] }, days: (3, 4, 6), unlocks: [.depot],
        step: (
            ("Build, then Depot, then tap the end of a track", "按「建造」、「機廠」，再點軌道的盡頭"),
            ("Then choose the depot on the line card, under Advanced.", "接著在路線卡的「進階」選這座機廠。")
        )
    )

    /// Lesson 8: freight.
    static let eighth = later(
        8, titles: ("Freight", "貨運"),
        stories: (
            "Towns make goods and need them. Build a freight yard at two stations and run a freight train between them.",
            "城鎮會生產貨物，也需要貨物。在兩座車站蓋貨運場，開一列貨運列車往返。"
        ),
        goals: { _, _, _ in [.dailyRiders(Lesson.laterRiders)] }, days: (3, 4, 6), unlocks: [.freight],
        step: (
            ("Tap a station, then Build Freight Yard", "點一座車站，再按「蓋貨運場」"),
            ("Do the same at a second station, then make a line between them carry freight.", "第二座車站也蓋一座，再把兩站之間的一條路線改成載貨。")
        )
    )

    /// Lesson 9: a sight, beyond the second town.
    static let ninth = later(
        9, titles: ("A Sight", "觀光景點"),
        stories: (
            "Visitors come from far away to see a sight beyond the second town. Take your railway there, then build beside it.",
            "第二座城鎮再過去有一處景點，遠方的遊客會來。把鐵路延伸過去，再在旁邊蓋建物。"
        ),
        goals: { towns, sight, _ in [.connect(points: [towns[1], sight], radius: Land.catchmentRadius), .dailyRiders(Lesson.laterRiders)] },
        days: (3, 4, 6), unlocks: [.buildingTool],
        step: (
            ("Lay track to the sight and build a station", "鋪軌道到景點，蓋一座車站"),
            ("Add the station to a line. A hotel beside it brings more visitors.", "把車站加進路線。旁邊蓋一間旅館，遊客會更多。")
        )
    )

    /// Lesson 10: the city's requests.
    static let tenth = later(
        10, titles: ("The City's Requests", "城市的委託"),
        stories: (
            "The city asks for help: more riders, a station somewhere, goods delivered. Take on a request and meet it in time for a reward.",
            "城市會提出委託：更多乘客、在某處蓋站、運送貨物。接下委託，在期限內完成就有獎勵。"
        ),
        goals: { _, _, _ in [.dailyRiders(Lesson.laterRiders)] }, days: (3, 4, 6), unlocks: [.trainTool],
        step: (
            ("Open the city's requests and take one", "打開城市的委託，接下一件"),
            ("Each says what to do and by when. After this lesson every tool is yours.", "每件委託都寫著要做什麼、期限到何時。過了這關，所有工具都歸你。")
        )
    )

    /// The riders a day each lesson asks for (decision 266, measured with
    /// `Policy`: LessonTargetReportTests). Lesson 1's line carries some
    /// 59,500 a day from its first day; the third town adds some 8,500; a
    /// second train on seed 1's line adds next to none (decision 266).
    static let firstRiders: Int64 = 30_000
    static let secondRiders: Int64 = 65_000
    static let thirdRiders: Int64 = 60_000
    /// Decision 271: lesson 4's, and those after it, which begin with both
    /// lines (provisional until measured).
    static let fourthRiders: Int64 = 65_000
    static let laterRiders: Int64 = 69_000

    /// Lesson 2's first step: what to build, read.
    static let extendStep = TutorialStep(
        id: "lesson.extend", chapter: .line,
        targets: [.linesButton],
        goal: .read,
        title: ("Extend your line to the third town", "把路線延伸到第三個城鎮"),
        body: (
            "Lay track from your line's end to the third town and build a station there. Then open Lines and add it to the line's stops.",
            "從路線的終點把軌道鋪到第三座小鎮，在那裡蓋一座車站，再打開「路線」把它加進停靠站。"
        )
    )

    /// Lesson 3's step: what to tap, read.
    static let addTrainStep = TutorialStep(
        id: "lesson.addTrain", chapter: .service,
        targets: [.linesButton],
        goal: .read,
        title: ("Open Lines and tap Add a Train", "打開「路線」，按「加開一列車」"),
        body: (
            "Two trains on one track pass at a passing loop. If your line has none, the card adds one.",
            "兩列車在單線上要靠待避線交會。路線還沒有待避線時，路線卡會幫你加一處。"
        )
    )
}

extension GameWorld {
    /// A lesson's game (decision 266): a new game of simple rules
    /// (decision 258) on the usual 16 km blank map, its towns seed 1's,
    /// without holidays, sights or the city's requests, and the lesson's
    /// scenario. After lesson 1 the game begins with lesson 1's line, from
    /// the first town to the second, opened with its train as the player
    /// opened it, so each lesson goes on from the one before; after lesson
    /// 4, with lesson 4's line on to the third town too (decision 271). What a
    /// lesson turns on stays on in the ones after it: lesson 9's sight, the
    /// city's requests in lesson 10. Freight is on in every new game; a
    /// lesson shows it from lesson 8 (``GameSession/showsFreight``).
    @MainActor
    public static func newGame(lesson: Lesson) -> GameWorld {
        newGame(lesson: lesson, opensFirstLine: lesson.number > 1)
    }

    /// ``newGame(lesson:)``, with or without the lines of the lessons
    /// before it: the target report builds lessons 1–3's itself, as a play
    /// does (LessonTargetReportTests).
    @MainActor
    static func newGame(lesson: Lesson, opensFirstLine: Bool) -> GameWorld {
        var world = newGame(eventSeed: Lesson.seed, rules: .simple)
        world.setDisruptions(nil)
        world.setTourism(nil)
        world.setCityRequests(seed: nil)
        if lesson.number >= 9 {
            world.setTourism([Attraction(
                id: AttractionID(rawValue: 1), name: "望海岬", englishName: "Seaview Point",
                point: Lesson.sight(in: world.bounds), kind: .coast, baseStars: 400
            )])
        }
        if lesson.number >= 10 { world.setCityRequests(seed: Lesson.seed) }
        do {
            if opensFirstLine {
                let towns = Lesson.towns(in: world.bounds)
                var opening = CurvedOpening(auto: true)
                try opening.openFirstLine(&world, from: towns[0], to: towns[1])
                // Lesson 4's line: on from the first town's end of the
                // track to the third town, calling at every station.
                if lesson.number > 4 { try opening.extend(&world, to: towns[2]) }
            }
            try world.startScenario(lesson.challenge.scenario(seed: Lesson.seed, in: world.bounds))
        } catch {
            // A new game is managed, has the money for the line, and the
            // lessons' rules are this file's.
            preconditionFailure("Could not start lesson \(lesson.number): \(error)")
        }
        return world
    }

    /// The lesson this game is, from its scenario, or `nil`.
    public var lesson: Lesson? {
        scenario.flatMap { Lesson.named($0.scenario.id) }
    }
}

extension GameSession {
    /// The lesson being played, or `nil` (decision 266).
    public var lesson: Lesson? {
        world.lesson
    }

    /// Whether `tool` is open in this game (decision 266): in a lesson,
    /// only those unlocked by the lessons up to it; in any other game, all.
    public func allows(_ tool: UnlockableTool) -> Bool {
        lesson.map { $0.tools.contains(tool) } ?? true
    }

    /// Whether the game's freight is shown (decision 271): a game with
    /// freight, and in a lesson, from lesson 8.
    public var showsFreight: Bool {
        world.hasFreight && allows(UnlockableTool.freight)
    }

    /// Whether the construction tool is open (decision 266): Network and
    /// Select always, Train and Building once unlocked.
    public func allows(_ tool: ConstructionTool) -> Bool {
        switch tool {
        case .select, .network: true
        case .train: allows(.trainTool)
        case .building: allows(.buildingTool)
        }
    }

    /// Whether the network tool's mode is open (decision 266): laying
    /// track, platforms and removing always, Loop and Depot once unlocked.
    public func allows(_ mode: NetworkToolMode) -> Bool {
        switch mode {
        case .passingLoop: allows(UnlockableTool.passingLoop)
        case .depot: allows(UnlockableTool.depot)
        default: true
        }
    }
}

/// How a lesson ended (decision 266), for its result card.
public struct LessonResult: Hashable, Sendable {
    public let lesson: Int
    /// 1 to 3 stars, or 0 when the days ran out.
    public let stars: Int
    /// The days it took.
    public let days: Int64

    public init?(world: GameWorld) {
        guard let lesson = world.lesson, let outcome = world.scenario?.outcome else { return nil }
        self.lesson = lesson.number
        switch outcome {
        case .completed(let day, let rating):
            stars = Lesson.stars(for: rating)
            days = day
        case .failed(let day, _):
            stars = 0
            days = day
        }
    }

    /// The next lesson, when there is one and this one was passed.
    public var next: Lesson? {
        stars > 0 && lesson < Lesson.all.count ? Lesson.all[lesson] : nil
    }

    public func title(in language: DisplayLanguage) -> String {
        stars > 0 ? language.text("Lesson \(lesson) passed", "第 \(lesson) 關過關") : language.text("Out of days", "時間到了")
    }

    public func detail(in language: DisplayLanguage) -> String {
        stars > 0
            ? language.text("Done in \(days) \(days == 1 ? "day" : "days").", "用了 \(days) 天完成。")
            : language.text("The goal was not met in time. Try again?", "期限內沒有達成目標，再試一次？")
    }
}
