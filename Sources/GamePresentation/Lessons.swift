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
        default: language.text("Run a second train: Add a Train and a passing loop.", "加開第二列車：加開一列車與待避線。")
        }
    }
}

extension Lesson {
    /// The lessons, in order.
    public static let all: [Lesson] = [first, second, third]

    /// The lesson with `id`, as a save names its scenario.
    public static func named(_ id: String) -> Lesson? {
        all.first { $0.id == id }
    }

    /// The towns of the lessons' map.
    static func towns(in bounds: WorldBounds) -> [PlanPoint] {
        Land.townCentres(seed: seed, in: bounds)
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
                    goldDays: 3, silverDays: 4, deadlineDays: 6
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

    /// The riders a day each lesson asks for (decision 266, measured with
    /// `Policy`: LessonTargetReportTests).
    static let firstRiders: Int64 = 30_000
    static let secondRiders: Int64 = 80_000
    static let thirdRiders: Int64 = 100_000

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
    /// scenario.
    public static func newGame(lesson: Lesson) -> GameWorld {
        var world = newGame(eventSeed: Lesson.seed, rules: .simple)
        world.setDisruptions(nil)
        world.setTourism(nil)
        world.setCityRequests(seed: nil)
        do {
            try world.startScenario(lesson.challenge.scenario(seed: Lesson.seed, in: world.bounds))
        } catch {
            // A new game is managed and the lessons' rules are this file's.
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
