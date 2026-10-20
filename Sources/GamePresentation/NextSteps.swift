import GameCore

// City Transport Manager study 4.0, step M2 (4.3, first stage): a free game
// shows a short chain of next steps, each with its progress, and the map
// answers when one is met (decision 256's check and tune). The steps teach
// what a railway is made of: a line, a day that pays, a second line, a
// second train, a station two lines share, and the people the stations
// reach (decision 292). Nothing is paid for them: every step is read from
// the world as it is, and nothing is saved. Riders a day are not a step:
// one line between two towns carries tens of thousands from its first day
// (a new game of simple rules, measured), and a real map's towns differ too
// much for one number to mean the same everywhere.

/// One of a free game's next steps, in the order they are shown.
public enum NextStep: Int, CaseIterable, Hashable, Sendable {
    /// A line.
    case firstLine
    /// A day settled at midnight with more coming in than its running
    /// costs.
    case profitableDay
    /// A second line.
    case secondLine
    /// Two trains on one line.
    case secondTrain
    /// A station two lines call at, where passengers change trains.
    case transferStation
    /// Stations within reach of half the residents and jobs (decision
    /// 292): only on a map with land.
    case halfCovered

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .firstLine: language.text("Open your first line", "開第一條線")
        case .profitableDay: language.text("A day that makes money", "有一天營運有賺錢")
        case .secondLine: language.text("Open a second line", "開第二條線")
        case .secondTrain: language.text("Run two trains on one line", "讓一條線跑兩列車")
        case .transferStation: language.text("A station two lines share", "一座兩條路線都停的車站")
        case .halfCovered: language.text("Reach half the residents and jobs", "車站涵蓋一半的居民與工作")
        }
    }

    /// What to do for it, in a sentence.
    public func hint(in language: DisplayLanguage) -> String {
        switch self {
        case .firstLine:
            language.text(
                "Lay track between two towns, give each a platform, then pick both in the Lines panel.",
                "在兩個城鎮之間鋪軌、各設一座月台，再到路線面板點選兩站。"
            )
        case .profitableDay:
            language.text(
                "Each day is settled at midnight: fares in, running costs, staff and energy out.",
                "每天午夜結算：票收進來，營運成本、人事與電費出去。"
            )
        case .secondLine:
            language.text("Join another town, or a busy place on the way.", "接到另一個城鎮，或沿途人多的地方。")
        case .secondTrain:
            language.text("In the Lines panel, select the line and tap Add a Train.", "在路線面板選路線，按「加開列車」。")
        case .transferStation:
            language.text(
                "Start a new line at a station another line already calls at, so passengers can change there.",
                "從另一條路線已經停的車站開新路線，乘客就能在那裡轉車。"
            )
        case .halfCovered:
            language.text(
                "Build stations where the coverage layer shows people no station reaches.",
                "在腹地涵蓋層顯示還沒有車站的地方蓋車站。"
            )
        }
    }
}

/// How far one step has come.
public struct NextStepProgress: Equatable, Sendable {
    public let step: NextStep
    /// What it has, and what it asks for.
    public let value: Int64
    public let target: Int64

    public init(step: NextStep, value: Int64, target: Int64) {
        self.step = step
        self.value = value
        self.target = target
    }

    public var isMet: Bool { value >= target }

    /// 0 to 1, for the bar.
    public var fraction: Double {
        target > 0 ? min(1, Double(max(0, value)) / Double(target)) : 1
    }

    /// "1/2", or "34% / 50%" for coverage.
    public var progressText: String {
        step == .halfCovered ? "\(min(value, 100))% / \(target)%" : "\(min(value, target))/\(target)"
    }
}

/// A free game's next steps (``NextStep``), as the world stands.
public struct NextSteps: Equatable, Sendable {
    public let steps: [NextStepProgress]

    public init(steps: [NextStepProgress]) {
        self.steps = steps
    }

    /// The steps of `world`: every one, the coverage step only on a map
    /// with land.
    public init(world: GameWorld) {
        let lines = world.lines.filter { !$0.isFreight }
        let today = FinanceHistory.floorDay(world.clock.now)
        let paid = world.accounts.days.contains { day in
            day.day < today && day.fareRevenue + day.freightRevenue > day.totalCost
        }
        let mostTrains = lines.map { Int64($0.trains.count) }.max() ?? 0
        let mostLines = world.stations.map { station in
            Int64(lines.filter { $0.stops.contains(station.id) }.count)
        }.max() ?? 0
        var steps = [
            NextStepProgress(step: .firstLine, value: Int64(lines.count), target: 1),
            NextStepProgress(step: .profitableDay, value: paid ? 1 : 0, target: 1),
            NextStepProgress(step: .secondLine, value: Int64(lines.count), target: 2),
            NextStepProgress(step: .secondTrain, value: mostTrains, target: 2),
            NextStepProgress(step: .transferStation, value: mostLines >= 2 ? 1 : 0, target: 1),
        ]
        if !world.land.isEmpty {
            steps.append(NextStepProgress(step: .halfCovered, value: world.catchmentCoverage().percent ?? 0, target: 50))
        }
        self.init(steps: steps)
    }

    /// The first step not met, or `nil` when all are.
    public var current: NextStepProgress? {
        steps.first { !$0.isMet }
    }

    /// How many are met.
    public var metCount: Int {
        steps.filter(\.isMet).count
    }

    /// The steps met.
    public var met: Set<NextStep> {
        Set(steps.filter(\.isMet).map(\.step))
    }

    /// "Next: Open a second line · 3/6", or "All 6 steps done".
    public func chipText(in language: DisplayLanguage) -> String {
        guard let current else {
            return language.text("All \(steps.count) steps done", "\(steps.count) 個步驟都完成了")
        }
        let title = current.step.title(in: language)
        return language.text("Next: \(title) · \(metCount)/\(steps.count)", "下一步：\(title) · \(metCount)/\(steps.count)")
    }
}

struct NextStepsMemo {
    struct Key: Equatable {
        let revision: Int
        let day: Int64
    }

    let key: Key
    let steps: NextSteps?
}

extension GameSession {
    /// The next steps of a free game (``NextSteps``), or `nil` in a
    /// challenge, a lesson, the tutorial, a demo or free play without
    /// money. Worked out once for each command and game day, not at every
    /// tick.
    public var nextSteps: NextSteps? {
        guard world.scenario == nil, tutorial == nil, !news.isDemo, world.accounts.mode == .management else { return nil }
        let key = NextStepsMemo.Key(revision: commandRevision, day: FinanceHistory.floorDay(world.clock.now))
        if let memo = nextStepsMemo, memo.key == key { return memo.steps }
        let steps = NextSteps(world: world)
        nextStepsMemo = NextStepsMemo(key: key, steps: steps)
        return steps
    }

    /// The titles of the next steps met since the last look, for decision
    /// 256's check and tune; `before`: the world before the command or step
    /// of time, which a first look takes as what was met already. A step
    /// met once (and lost to an undo, say) is not met again.
    func newlyMetNextSteps(since before: GameWorld) -> [String] {
        guard let steps = nextSteps else { return [] }
        let known = nextStepsCelebrated ?? NextSteps(world: before).met
        let new = steps.steps.filter { $0.isMet && !known.contains($0.step) }
        nextStepsCelebrated = known.union(steps.met)
        return new.map { $0.step.title(in: language) }
    }

    /// After a command: the check and tune for the next steps it met.
    func noteNextSteps(since before: GameWorld) {
        let titles = newlyMetNextSteps(since: before)
        guard !titles.isEmpty else { return }
        goalPulse = GoalPulse(titles: titles, serial: (goalPulse?.serial ?? 0) + 1)
        playSound?(.goalMet)
    }
}
