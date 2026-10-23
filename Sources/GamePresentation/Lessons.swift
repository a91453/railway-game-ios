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
    /// 3, 2 and 1 stars, and what it teaches in a read step (decision 271),
    /// or in `guide`'s steps, one action each (decision 376).
    private static func later(
        _ number: Int, titles: (String, String), stories: (String, String), goals: @escaping @Sendable ([PlanPoint], PlanPoint, WorldBounds) -> [Goal],
        days: (Int64, Int64, Int64), unlocks: [UnlockableTool], step: (title: (String, String), body: (String, String)),
        guide: [TutorialStep]? = nil
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
            guide: guide ?? [TutorialStep(id: "lesson.\(number)", chapter: .service, targets: [], goal: .read, title: step.title, body: step.body)]
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
        guide: thirdGuide
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
        ),
        guide: fourthGuide
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
        ),
        guide: fifthGuide
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
        ),
        guide: sixthGuide
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
        ),
        guide: seventhGuide
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
        ),
        guide: eighthGuide
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
        ),
        guide: ninthGuide
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
        ),
        guide: tenthGuide
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

    // Decision 376: lessons 3–6, one action each, as lesson 1's guide.
    // A step taken over from an earlier guide keeps its id ("lesson.addTrain",
    // "lesson.4", "lesson.5", "lesson.6"), the step the launcher keeps to
    // take a guide up again at; the tutorial's own steps are used as they are.

    /// Lesson 3: Lines, Add a Train, the passing loop it runs through, time.
    static let thirdGuide: [TutorialStep] = [
        TutorialStep(
            id: "lesson.3.lines", chapter: .service,
            targets: [.linesButton],
            goal: .openLines,
            setup: [.selectNewestLine],
            title: ("Tap Lines", "點「路線」"),
            body: ("Your line's card shows its trains.", "路線卡上有它的列車。")
        ),
        TutorialStep(
            id: "lesson.addTrain", chapter: .service,
            targets: [.addTrain],
            goal: .addTrain,
            panel: .lines,
            title: ("Tap Add a Train", "按「加開一列車」"),
            body: (
                "A second train is bought and sent off, with a passing loop if the track needs one.",
                "第二列車會買好發車，單線需要時也會加一處待避線。"
            )
        ),
        TutorialStep(
            id: "lesson.3.loop", chapter: .service,
            targets: [.map],
            goal: .selectPassingLoop,
            setup: [.clearSelection],
            panel: .closed,
            title: ("Tap the passing loop", "點待避線"),
            body: (
                "Two tracks and no platform: a train waits there for the one coming the other way.",
                "兩條軌道、沒有月台的地方，列車在這裡等對向車。"
            )
        ),
    ] + steps(["time.play"])

    /// Lesson 4: track on to the third town, its station, a second line.
    static let fourthGuide: [TutorialStep] = [
        TutorialStep(
            id: "lesson.4", chapter: .track,
            targets: [.buildEntry],
            goal: .chooseTool(.network),
            panel: .closed,
            title: ("Tap Build", "點「建設」"),
            body: (
                "The third town needs track from the first town's station.",
                "第三座城鎮需要一段從第一座城鎮車站鋪過去的軌道。"
            )
        ),
        TutorialStep(
            id: "lesson.4.track", chapter: .track,
            targets: [.map],
            goal: .drawTrack,
            setup: [.layTrack],
            title: ("Tap a station, then the third town", "點車站，再點第三座城鎮"),
            body: (
                "Start at the first town's station, so the new track joins your line's.",
                "從第一座城鎮的車站開始鋪，新軌道才會接上路線。"
            )
        ),
    ] + steps(["track.build", "station.mode"]) + [
        TutorialStep(
            id: "lesson.4.site", chapter: .stations,
            targets: [.map],
            goal: .pickPlatformSite(1),
            title: ("Tap your track in the third town", "點第三座城鎮裡的軌道"),
            body: ("The ring shows who lives within a walk.", "圓圈裡是走路就能到站的居民。")
        ),
    ] + steps(["station.first.build"]) + [
        TutorialStep(
            id: "lesson.4.done", chapter: .stations,
            targets: [.selectTool],
            goal: .chooseTool(.select),
            panel: .closed,
            title: ("Tap Done to stop building", "點「完成」結束建造"),
            body: ("Time runs again. Next, a second line.", "時間會繼續走。接著開第二條線。")
        ),
    ] + steps(["line.open"]) + [
        TutorialStep(
            id: "lesson.4.stations", chapter: .line,
            targets: [.map],
            goal: .pickLineStations,
            panel: .lines,
            title: ("Tap the old station, then the new", "點舊車站，再點新車站"),
            body: (
                "Pick the first town's station: riders change between your two lines there.",
                "先點第一座城鎮的車站，乘客會在那裡轉乘兩條線。"
            )
        ),
    ] + steps(["line.create", "time.play"])

    /// Lesson 5: a stretch of track picked, made double, built.
    static let fifthGuide: [TutorialStep] = [
        TutorialStep(
            id: "lesson.5", chapter: .track,
            targets: [.map],
            goal: .selectTrack,
            setup: [.clearSelection],
            panel: .closed,
            title: ("Tap a stretch of track", "點一段軌道"),
            body: ("Pick the track between two stations, away from the trains.", "選兩站之間的軌道，避開列車。")
        ),
        TutorialStep(
            id: "lesson.5.double", chapter: .track,
            targets: [.doubleTrack],
            goal: .draftDoubleTrack,
            title: ("Tap Make double track", "按「升級為複線」"),
            body: (
                "The second track goes beside the first, as far as the switches at each end.",
                "第二條軌道會鋪在旁邊，一直到兩端的道岔。"
            )
        ),
        TutorialStep(
            id: "lesson.5.build", chapter: .track,
            targets: [.mapConfirm],
            goal: .buildDoubleTrack,
            title: ("Tap ✓ to build it", "按 ✓ 蓋好"),
            body: (
                "The price is on the button. On double track, the trains each way keep to their own.",
                "按鈕上就是價錢。複線上，兩個方向的列車各走各的。"
            )
        ),
    ] + steps(["time.play"])

    /// Lesson 6: Lines, Advanced, the line's hours, its headway, a
    /// stopping pattern.
    static let sixthGuide: [TutorialStep] = [
        TutorialStep(
            id: "lesson.6", chapter: .service,
            targets: [.linesButton],
            goal: .openLines,
            setup: [.selectNewestLine],
            title: ("Tap Lines", "點「路線」"),
            body: ("Your line's hours, trains and stops are set here.", "路線的營運時間、列車和停靠站都在這裡設定。")
        ),
        TutorialStep(
            id: "lesson.6.advanced", chapter: .service,
            targets: [.advancedSwitch],
            goal: .showAdvanced,
            panel: .lines,
            title: ("Turn on Advanced", "打開「進階」"),
            body: ("It shows the service day and the stopping patterns.", "會顯示營運時段和停靠模式。")
        ),
        TutorialStep(
            id: "lesson.6.hours", chapter: .service,
            targets: [.serviceHours],
            goal: .changeServiceHours,
            panel: .lines,
            title: ("Change when your line runs", "改路線的營運時間"),
            body: (
                "Tap Run All Day for trains all night, or back to 06:00–24:00. Each hour costs to run.",
                "按「全天營運」讓列車整夜行駛，或改回 06:00–24:00。"
            )
        ),
        TutorialStep(
            id: "lesson.6.headway", chapter: .service,
            targets: [.headwayPicker, .headwayChange],
            goal: .changeHeadway,
            panel: .lines,
            title: ("Pick the minutes, then Every … min", "選班距，再按「調整為每…分」"),
            body: (
                "Fewer minutes: more trains, more riders and more costs.",
                "分鐘越少，列車越多、乘客越多，成本也越高。"
            )
        ),
        TutorialStep(
            id: "lesson.6.pattern", chapter: .service,
            targets: [.addPattern],
            goal: .addPattern,
            panel: .lines,
            title: ("Add a stopping pattern", "加一種停站模式"),
            body: (
                "Pick From and To, turn on Non-stop to skip the stops between, then tap Add.",
                "選「起點」和「終點」，打開「直達車」跳過中間的站，再按「加入」。"
            )
        ),
    ] + steps(["time.play"])

    // Decision 376, later: lessons 7–10, as lessons 3–6. The first step of
    // each keeps the id of the read step it takes over ("lesson.7" …
    // "lesson.10").

    /// Lesson 7: Build, Depot, the end of a track, its sidings, then the
    /// line's depot.
    static let seventhGuide: [TutorialStep] = [
        TutorialStep(
            id: "lesson.7", chapter: .track,
            targets: [.buildEntry],
            goal: .chooseTool(.network),
            panel: .closed,
            title: ("Tap Build", "點「建設」"),
            body: ("A depot goes where a track ends.", "機廠蓋在軌道的盡頭。")
        ),
        TutorialStep(
            id: "lesson.7.mode", chapter: .track,
            targets: [.networkModes],
            goal: .chooseNetworkMode(.depot),
            setup: [.clearPicks],
            title: ("Tap Depot", "點「機廠」"),
            body: ("Sidings where your trains stand for the night.", "列車晚上停放的停車線。")
        ),
        TutorialStep(
            id: "lesson.7.end", chapter: .track,
            targets: [.map],
            goal: .pickDepotEnd,
            title: ("Tap the end of a track", "點軌道的盡頭"),
            body: ("The sidings run on straight from it.", "停車線會從那裡直直往前鋪。")
        ),
        TutorialStep(
            id: "lesson.7.build", chapter: .track,
            targets: [.actionButton],
            goal: .buildDepot,
            title: ("Tap Lay Depot Sidings", "按「鋪機廠停車線」"),
            body: ("The price is on the button.", "按鈕上就是價錢。")
        ),
        TutorialStep(
            id: "lesson.7.done", chapter: .track,
            targets: [.selectTool],
            goal: .chooseTool(.select),
            panel: .closed,
            title: ("Tap Done to stop building", "點「完成」結束建造"),
            body: ("Next, send a line's trains to the depot.", "接著讓路線的列車回機廠。")
        ),
        TutorialStep(
            id: "lesson.7.lines", chapter: .service,
            targets: [.linesButton],
            goal: .openLines,
            setup: [.selectDepotLine],
            title: ("Tap Lines", "點「路線」"),
            body: ("Your line's card lists the depots it can use.", "路線卡上列出它能用的機廠。")
        ),
        TutorialStep(
            id: "lesson.7.depot", chapter: .service,
            targets: [.lineDepot],
            goal: .chooseDepot,
            panel: .lines,
            title: ("Tick your depot", "勾選你的機廠"),
            body: (
                "After the last train, they go there; before the first, they come out.",
                "收班後列車回機廠，首班前再出庫。"
            )
        ),
    ] + steps(["time.play"])

    /// Lesson 8: a freight yard at two stations, then a freight line
    /// between them.
    static let eighthGuide: [TutorialStep] = [
        TutorialStep(
            id: "lesson.8", chapter: .stations,
            targets: [.map],
            goal: .selectStationForFreight,
            setup: [.clearSelection],
            panel: .closed,
            title: ("Tap one of your stations", "點你的一座車站"),
            body: ("A freight yard goes beside it.", "貨運場蓋在車站旁邊。")
        ),
        TutorialStep(
            id: "lesson.8.panel", chapter: .stations,
            targets: [.ridership],
            goal: .openStationPanel,
            title: ("Tap Station…", "點「車站…」"),
            body: ("Freight is near the bottom of the station panel.", "貨運在車站面板的下方。")
        ),
        TutorialStep(
            id: "lesson.8.yard", chapter: .stations,
            targets: [.freightYard],
            goal: .buildFreightYard(1),
            title: ("Tap Build Freight Yard", "按「蓋貨運場」"),
            body: ("The towns around it send and take goods here.", "附近的城鎮會在這裡寄貨、收貨。")
        ),
        TutorialStep(
            id: "lesson.8.second", chapter: .stations,
            targets: [.map],
            goal: .selectStationForFreight,
            panel: .closed,
            title: ("Tap another station", "點另一座車站"),
            body: ("Goods need a yard at each end.", "貨物兩端都要有貨運場。")
        ),
        TutorialStep(
            id: "lesson.8.panel2", chapter: .stations,
            targets: [.ridership],
            goal: .openStationPanel,
            title: ("Tap Station… again", "再點「車站…」"),
            body: ("Freight is near the bottom again.", "貨運一樣在下方。")
        ),
        TutorialStep(
            id: "lesson.8.yard2", chapter: .stations,
            targets: [.freightYard],
            goal: .buildFreightYard(2),
            title: ("Tap Build Freight Yard again", "再按「蓋貨運場」"),
            body: ("Next, a train to carry the goods.", "接著開一列車載貨。")
        ),
    ] + steps(["line.open"]) + [
        TutorialStep(
            id: "lesson.8.stations", chapter: .line,
            targets: [.map],
            goal: .pickLineStations,
            panel: .lines,
            title: ("Tap the two freight yards", "點兩座貨運場的車站"),
            body: ("A freight line calls at the stations with yards.", "貨運路線停靠有貨運場的車站。")
        ),
        TutorialStep(
            id: "lesson.8.freight", chapter: .line,
            targets: [.mapConfirm],
            goal: .createFreightLine,
            panel: .lines,
            title: ("Tap ✓, then Freight line", "按 ✓，再打開「貨運路線」"),
            body: ("On the card, turn on Freight line, then tap Open Line.", "在卡片上打開「貨運路線」，再按「開通路線」。")
        ),
    ] + steps(["time.play"])

    /// Lesson 9: track and a station to the sight, a line to it, then a
    /// hotel beside it.
    static let ninthGuide: [TutorialStep] = [
        TutorialStep(
            id: "lesson.9", chapter: .track,
            targets: [.buildEntry],
            goal: .chooseTool(.network),
            panel: .closed,
            title: ("Tap Build", "點「建設」"),
            body: ("The sight lies beyond the second town.", "景點在第二座城鎮再過去。")
        ),
        TutorialStep(
            id: "lesson.9.track", chapter: .track,
            targets: [.map],
            goal: .drawTrack,
            setup: [.layTrack],
            title: ("Tap a station, then the sight", "點車站，再點景點"),
            body: (
                "Start at the second town's station, so the new track joins your line's.",
                "從第二座城鎮的車站開始鋪，新軌道才會接上路線。"
            )
        ),
    ] + steps(["track.build", "station.mode"]) + [
        TutorialStep(
            id: "lesson.9.site", chapter: .stations,
            targets: [.map],
            goal: .pickPlatformSite(1),
            title: ("Tap your track by the sight", "點景點旁的軌道"),
            body: ("Visitors walk from the station to the sight.", "遊客從車站走路去景點。")
        ),
    ] + steps(["station.first.build"]) + [
        TutorialStep(
            id: "lesson.9.done", chapter: .stations,
            targets: [.selectTool],
            goal: .chooseTool(.select),
            panel: .closed,
            title: ("Tap Done to stop building", "點「完成」結束建造"),
            body: ("Next, a line to the sight.", "接著開一條線到景點。")
        ),
    ] + steps(["line.open"]) + [
        TutorialStep(
            id: "lesson.9.stations", chapter: .line,
            targets: [.map],
            goal: .pickLineStations,
            panel: .lines,
            title: ("Tap the old station, then the new", "點舊車站，再點新車站"),
            body: ("Pick the second town's station, then the sight's.", "先點第二座城鎮的車站，再點景點的車站。")
        ),
    ] + steps(["line.create"]) + [
        TutorialStep(
            id: "lesson.9.buildings", chapter: .passengers,
            targets: [.buildEntry, .buildingTool],
            goal: .chooseTool(.building),
            panel: .closed,
            title: ("Tap Build, then Buildings", "點「建設」，再點「建物」"),
            body: ("A hotel near the sight brings more visitors.", "景點附近的飯店會帶來更多遊客。")
        ),
        TutorialStep(
            id: "lesson.9.hotel", chapter: .passengers,
            targets: [.hotelKind],
            goal: .chooseBuildingKind(.hotel),
            title: ("Tap Hotel", "點「飯店」"),
            body: ("Its guests ride your trains too.", "住客也會搭你的車。")
        ),
        TutorialStep(
            id: "lesson.9.site.hotel", chapter: .passengers,
            targets: [.map],
            goal: .pickBuildingSite,
            title: ("Tap the map by the new station", "點新車站旁的地圖"),
            body: ("Within a walk of the sight and the station.", "走路就能到景點和車站的地方。")
        ),
        TutorialStep(
            id: "lesson.9.put", chapter: .passengers,
            targets: [.mapConfirm],
            goal: .putUpBuilding(.hotel),
            title: ("Tap ✓ to build it", "按 ✓ 蓋好"),
            body: ("The price is on the button.", "按鈕上就是價錢。")
        ),
    ] + steps(["time.play"])

    /// Lesson 10: one of the city's requests taken on.
    static let tenthGuide: [TutorialStep] = [
        TutorialStep(
            id: "lesson.10", chapter: .service,
            targets: [.requestsButton],
            goal: .acceptRequest,
            panel: .closed,
            title: ("Tap the requests, then Take on", "點委託，再按「承接」"),
            body: (
                "Each says what to do and by when. Meet it in time for a reward.",
                "每件都寫著要做什麼、期限到何時，準時完成有獎勵。"
            )
        ),
    ] + steps(["time.play"])
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
        // Decision 319: the lessons' targets were measured without the tide.
        world.setTidalDemand(false)
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
