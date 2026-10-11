import GameCore

// The challenges a new game can start with (decision 86), and how the goals
// panel words a scenario, its goals and how far they are met, in English
// or Traditional Chinese. The goals and their judgement are GameCore's
// (`Scenario`, `Goal`); this file only picks the targets and the words.
// No reference has railway goals: the challenges, their targets and their
// stories are this project's.

/// The map a challenge is played on.
public enum ChallengeMap: Hashable, Sendable {
    /// A new game's blank map, its towns drawn from a seed.
    case blank
    /// The real-world demo's map as it was before decision 132, its
    /// Pingxi, Yilan and Shenao Lines built flat (decision 90): it needs
    /// the app's real railways.
    case pingxi
    /// The real-world map from Keelung to Hsinchu with nothing built, its
    /// land read in as stations are built (decision 153).
    case liuMingchuan
}

/// A challenge the start screen offers: its words, its map, and the
/// scenario it plays there.
public struct Challenge: Hashable, Sendable, Identifiable {
    public let id: String
    let titles: (english: String, chinese: String)
    let stories: (english: String, chinese: String)
    public let map: ChallengeMap
    /// The scenario on its map: on a blank one, the one whose towns were
    /// drawn from `seed`.
    let rules: @Sendable (_ seed: UInt32, _ bounds: WorldBounds) -> Scenario

    init(
        id: String, titles: (english: String, chinese: String), stories: (english: String, chinese: String), map: ChallengeMap = .blank,
        rules: @escaping @Sendable (_ seed: UInt32, _ bounds: WorldBounds) -> Scenario
    ) {
        self.id = id
        self.titles = titles
        self.stories = stories
        self.map = map
        self.rules = rules
    }

    public func title(in language: DisplayLanguage) -> String {
        language.text(titles.english, titles.chinese)
    }

    public func story(in language: DisplayLanguage) -> String {
        language.text(stories.english, stories.chinese)
    }

    public func scenario(seed: UInt32, in bounds: WorldBounds) -> Scenario {
        rules(seed, bounds)
    }

    public static func == (lhs: Challenge, rhs: Challenge) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension Challenge {
    /// The challenges on a blank map, easiest first. Decision 86 set their
    /// targets on a fixed first line that decision 137 left losing money;
    /// decision 145 measured them again with `ChallengeReportTests` and set
    /// them so that the least each asks, played and waited out, earns
    /// bronze, one more thing silver, and gold asks for more than the
    /// report's plays. On seeds 1–3 the three towns linked by two lines from
    /// the first, a train of four cars each, first carry 350,000 riders a
    /// day on day 284–306; trains of eight cars, on day 193–229: until about
    /// day 120 the riders are the demand's, after it the trains' room. More
    /// lines and stations between the towns do not bring it forward. The
    /// same two lines reach 600,000 people on day 475–494 and equity of
    /// $800 million on day 1,028–1,031; with eight cars, on day 426–451 and
    /// 847–868.
    public static let sandbox: [Challenge] = [threeTowns, cityBuilder, tycoon]

    /// The challenge with `id`, as a save names its scenario: one of
    /// ``sandbox`` or ``history`` (decision 90), or a week's (decision 87).
    public static func named(_ id: String) -> Challenge? {
        (sandbox + history).first { $0.id == id } ?? WeeklyChallenge.named(id)?.challenge
    }

    private static let year = FinancePeriod.year.days

    /// Link the map's three towns, and carry their people.
    static let threeTowns = Challenge(
        id: "sandbox.threeTowns",
        titles: ("Three Towns", "三鎮連線"),
        stories: (
            "Three towns grow apart, a few kilometres from each other, with only buses between them. Link all three by rail, and carry their people.",
            "三座小鎮相隔幾公里，各自發展，彼此之間只有客運往來。用鐵路把三座小鎮串起來，載運鎮上的居民。"
        ),
        rules: { seed, bounds in
            Scenario(
                id: "sandbox.threeTowns",
                goals: [.connect(points: Land.townCentres(seed: seed, in: bounds), radius: Land.catchmentRadius), .dailyRiders(350_000)],
                goldDays: 180, silverDays: 270, deadlineDays: year, insolvencyDays: 60
            )
        }
    )

    /// Grow the city round the railway.
    static let cityBuilder = Challenge(
        id: "sandbox.cityBuilder",
        titles: ("Railway Town", "鐵道造鎮"),
        stories: (
            "A railway brings people, and people bring buildings. Grow the towns along your lines into a city of 600,000.",
            "鐵路帶來人潮，人潮帶來高樓。讓沿線的小鎮長成六十萬人口、高樓林立的城市。"
        ),
        rules: { _, _ in
            Scenario(
                id: "sandbox.cityBuilder",
                // Decision 145: silver between the day trains of eight
                // cars bring 600,000 people (426–451) and four cars (475–494).
                goals: [.population(600_000), .tallBuildings(500), .dailyRiders(350_000)],
                goldDays: year, silverDays: 465, deadlineDays: 2 * year, insolvencyDays: 60
            )
        }
    )

    /// Build a railway company worth a fortune.
    static let tycoon = Challenge(
        id: "sandbox.tycoon",
        titles: ("Railway Tycoon", "鐵道大亨"),
        stories: (
            "Turn a small railway into a great company: $300 million of profit in a year, and a company worth $800 million.",
            "把一間小小的鐵路公司經營成大企業：一年賺進 3 億，讓公司身價突破 8 億。"
        ),
        rules: { _, _ in
            Scenario(
                id: "sandbox.tycoon",
                goals: [.annualNetProfit(Money(30_000_000_000)), .equity(Money(80_000_000_000))],
                goldDays: 2 * year, silverDays: 5 * year / 2, deadlineDays: 3 * year, insolvencyDays: 60
            )
        }
    )
}

extension GameWorld {
    /// A new game on a blank map with `challenge`'s scenario: the towns
    /// drawn from `seed`, the goals judged from its first midnight.
    public static func newGame(challenge: Challenge, eventSeed: UInt32) -> GameWorld {
        var world = newGame(eventSeed: eventSeed)
        do {
            try world.startScenario(challenge.scenario(seed: eventSeed, in: world.bounds))
        } catch {
            // A new game is managed and the challenges' rules are this
            // file's, so a refusal is a programming error.
            preconditionFailure("Could not start the challenge \(challenge.id): \(error)")
        }
        return world
    }
}

// MARK: - Words

extension ScenarioRating {
    public func displayName(in language: DisplayLanguage) -> String {
        switch self {
        case .gold: language.text("Gold", "金牌")
        case .silver: language.text("Silver", "銀牌")
        case .bronze: language.text("Bronze", "銅牌")
        }
    }
}

/// How far a goal is: what it asks, what there is now, and whether it was
/// met (and on which day of the scenario).
public struct GoalProgress: Hashable, Sendable {
    public let title: String
    /// Now against the target, such as "45,210 / 100,000".
    public let detail: String
    /// 0…1, for a bar.
    public let fraction: Double
    /// The scenario's day (1 for its first) it was met on, or `nil`.
    public let metOnDay: Int64?
}

extension GameWorld {
    /// The scenario's goals as the goals panel shows them, in order, or
    /// `[]` without one.
    public func goalProgress(in language: DisplayLanguage) -> [GoalProgress] {
        guard let state = scenario else { return [] }
        return zip(state.scenario.goals, state.achieved).enumerated().map { index, pair in
            let (goal, achieved) = pair
            let met = achieved.map { state.elapsedDays(through: $0) }
            func counted(_ now: Int64, _ target: Int64, _ title: String) -> GoalProgress {
                GoalProgress(
                    title: title, detail: "\(Money(now).displayText) / \(Money(target).displayText)",
                    fraction: met != nil ? 1 : min(1, Double(max(0, now)) / Double(target)), metOnDay: met
                )
            }
            func money(_ now: Money, _ target: Money, _ title: String) -> GoalProgress {
                GoalProgress(
                    title: title, detail: "\(now.moneyText) / \(target.moneyText)",
                    fraction: met != nil ? 1 : min(1, Double(max(0, now.amount)) / Double(target.amount)), metOnDay: met
                )
            }
            switch goal {
            case .connect(let points, let radius):
                let served = points.count { point in stationsServed(near: point, radius: radius) }
                let joined = connectedStations(near: points, radius: radius) != nil
                return GoalProgress(
                    title: Challenge.milestoneTitle(of: state.scenario.id, goal: index, in: language)
                        ?? language.text("Link all \(points.count) towns by rail", "用鐵路連通全部 \(points.count) 座城鎮"),
                    detail: joined
                        ? language.text("All linked", "已全部連通")
                        : language.text("\(served) of \(points.count) have a station on a line", "\(served) / \(points.count) 座有路線停靠的車站"),
                    fraction: met != nil || joined ? 1 : Double(served) / Double(points.count) * 0.9, metOnDay: met
                )
            case .dailyRiders(let target):
                return counted(lastDayTrips(), target, language.text("Riders a day", "每日運量（人次）"))
            case .population(let target):
                return counted(totalResidents(), target, language.text("Population", "城市人口"))
            case .tallBuildings(let target):
                return counted(Int64(tallBuildingCount()), Int64(target), language.text("High-rises (D4)", "高樓（D4）"))
            case .annualNetProfit(let target):
                let best = accounts.years.map(\.income.netProfit).max() ?? .zero
                return money(best, target, language.text("Net profit in a year", "年度淨利"))
            case .equity(let target):
                return money(balanceSheet().equity, target, language.text("Company worth (equity)", "公司權益"))
            }
        }
    }

    /// Whether a station within `radius` of `point` has a line calling.
    func stationsServed(near point: PlanPoint, radius: Int64) -> Bool {
        let served = Set(lines.flatMap(\.stops))
        let squared = radius * radius
        return stations.contains { station in
            let dx = station.point.x - point.x, dy = station.point.y - point.y
            return served.contains(station.id) && dx * dx + dy * dy <= squared
        }
    }

    /// The train types a train may be given (decision 153): the
    /// scenario's era's, or without an era the reference's, which leave out
    /// the era-only steam train.
    public var offeredTrainTypes: [TrainType] {
        scenario?.scenario.trainTypes ?? TrainType.reference
    }

    /// Whether a train may have the standard car: not in an era with types
    /// (decision 153).
    public var offersStandardCar: Bool {
        scenario?.scenario.trainTypes == nil
    }

    /// The scenario's title, by its challenge, or `nil` without one.
    public func scenarioTitle(in language: DisplayLanguage) -> String? {
        scenario.map { Challenge.named($0.scenario.id)?.title(in: language) ?? $0.scenario.id }
    }

    /// Where the scenario stands: "Day 12 of 360 · gold by day 60", or how
    /// it ended.
    public func scenarioStatusText(in language: DisplayLanguage) -> String? {
        guard let state = scenario else { return nil }
        let rules = state.scenario
        switch state.outcome {
        case .completed(let day, let rating)?:
            let days = state.elapsedDays(through: day)
            return language.text(
                "Completed in \(days) days: \(rating.displayName(in: language))",
                "第 \(days) 天完成：\(rating.displayName(in: language))"
            )
        case .failed(let day, let reason)?:
            let days = state.elapsedDays(through: day)
            return switch reason {
            case .deadline: language.text("Time ran out after \(days) days", "\(days) 天期限已到，挑戰失敗")
            case .insolvency: language.text("Bankrupt on day \(days): too long in the red", "第 \(days) 天破產：現金赤字太久")
            }
        case nil:
            let today = scenarioDay() ?? 1
            let next: String
            if today <= rules.goldDays {
                next = language.text("gold by day \(rules.goldDays)", "第 \(rules.goldDays) 天前完成可得金牌")
            } else if today <= rules.silverDays {
                next = language.text("silver by day \(rules.silverDays)", "第 \(rules.silverDays) 天前完成可得銀牌")
            } else {
                next = language.text("bronze by day \(rules.deadlineDays)", "第 \(rules.deadlineDays) 天前完成可得銅牌")
            }
            return language.text("Day \(today) of \(rules.deadlineDays) · \(next)", "第 \(today) 天，共 \(rules.deadlineDays) 天 · \(next)")
        }
    }

    /// The days each rating needs: "Gold within 60 days · silver 120 ·
    /// bronze 360".
    public func scenarioRatingsText(in language: DisplayLanguage) -> String? {
        guard let rules = scenario?.scenario else { return nil }
        return Self.ratingsText(rules, in: language)
    }

    static func ratingsText(_ rules: Scenario, in language: DisplayLanguage) -> String {
        language.text(
            "Gold within \(rules.goldDays) days · silver \(rules.silverDays) · bronze \(rules.deadlineDays)",
            "金牌 \(rules.goldDays) 天內 · 銀牌 \(rules.silverDays) 天 · 銅牌 \(rules.deadlineDays) 天"
        )
    }
}

extension Challenge {
    /// What goal `goal` of the scenario `id` is called when it is a named
    /// milestone (decision 153), or `nil`.
    static func milestoneTitle(of id: String, goal: Int, in language: DisplayLanguage) -> String? {
        id == liuMingchuan.id ? LiuMingchuanChallenge.milestoneTitle(goal, in: language) : nil
    }

    /// The ratings' days on the challenge card.
    public func ratingsText(in language: DisplayLanguage) -> String {
        GameWorld.ratingsText(scenario(seed: 1, in: GameWorld.newGameBounds), in: language)
    }

    /// The goals on the challenge card, one line each.
    public func goalsText(in language: DisplayLanguage) -> [String] {
        scenario(seed: 1, in: GameWorld.newGameBounds).goals.enumerated().map { index, goal in
            switch goal {
            case .connect(let points, _):
                Self.milestoneTitle(of: id, goal: index, in: language)
                    ?? language.text("Link all \(points.count) towns by rail", "用鐵路連通全部 \(points.count) 座城鎮")
            case .dailyRiders(let count):
                language.text("\(Money(count).displayText) riders a day", "每日運量 \(Money(count).displayText) 人次")
            case .population(let count):
                language.text("A population of \(Money(count).displayText)", "城市人口 \(Money(count).displayText) 人")
            case .tallBuildings(let count):
                language.text("\(count) high-rises", "\(count) 棟高樓")
            case .annualNetProfit(let amount):
                language.text("A year's net profit of \(amount.moneyText)", "年度淨利 \(amount.moneyText)")
            case .equity(let amount):
                language.text("A company worth \(amount.moneyText)", "公司權益 \(amount.moneyText)")
            }
        }
    }
}
