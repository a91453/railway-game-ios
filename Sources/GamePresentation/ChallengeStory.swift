import GameCore

// A challenge's story after its opening words (decision 387): a few
// characters who speak, one line each, at the moments of the challenge the
// world can already tell (a day of it, its festival, a year's closing, the
// first day in profit, the first midnight in the red, a milestone reached,
// a share of the riders' goal first carried, the riders' goal met, how it
// ended), some only after another (a beat told, a milestone reached). Data
// only: a challenge's script is a list of
// ``StoryBeat``s, and the triggers are worked out from the world as it
// stands, so nothing is saved and GameCore does not change. The app tells a
// beat when it sees its day begin (``StoryTeller``), so a loaded game does
// not tell again what was told before it was saved.

/// Who speaks a line of a challenge's story.
public enum StoryCharacter: String, CaseIterable, Hashable, Sendable {
    /// The station master (decisions 118, 122): drawn by the region.
    case stationMaster
    /// Uncle Song (Pingxi): a miner's son who grew up in Jingtong.
    case ahSong
    /// Xiaowei (Pingxi): the third of her family to keep a lantern shop on
    /// Shifen's old street.
    case xiaoWei
    /// Mia (Pingxi): a backpacker from Melbourne, in Taiwan for the
    /// lanterns.
    case mia
    /// Ah-Shui (Liu Mingchuan): a soldier turned foreman of a track gang,
    /// digging Shiqiuling from both ends.
    case ahShui
    /// Mr Walsh (Liu Mingchuan): Henry Walsh, the British driver of
    /// Teng-Yun.
    case walsh
    /// Manager Ye (Liu Mingchuan): who keeps a tea house at Twatutia.
    case ye
    /// Master Lin (Jiji): who sawed timber in Checheng's mill when young.
    case lin
    /// Xiulan (Jiji): who keeps a shop by Jiji station, and saw it lean
    /// after the 921 earthquake and rise again.
    case xiulan
    /// Ah-Kun's letters (Jiji): a worker on the Sun Moon Lake works in the
    /// 1920s, who never appears; his letters to his mother do.
    case ahKun
    /// Mr Chou (the sandbox challenges): the young founder of the company,
    /// who keeps a close eye on its books.
    case chou
    /// Fang (the sandbox challenges): a reporter on the local paper, keen
    /// to break every story first.
    case fang
    /// Mayor Chen (the sandbox challenges): mayor for twenty years, now
    /// retired, who remembers when there were only rice paddies and buses.
    case mayorChen

    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .stationMaster: language.text("Station master", "站長")
        case .ahSong: language.text("Uncle Song", "阿松伯")
        case .xiaoWei: language.text("Xiaowei", "小葳")
        case .mia: language.text("Mia", "Mia")
        case .ahShui: language.text("Ah-Shui", "阿水")
        case .walsh: language.text("Mr Walsh", "華師傅")
        case .ye: language.text("Manager Ye", "葉掌櫃")
        case .lin: language.text("Master Lin", "林師傅")
        case .xiulan: language.text("Xiulan", "秀蘭")
        case .ahKun: language.text("Ah-Kun's letter home", "阿坤的家書")
        case .chou: language.text("Mr Chou", "周老闆")
        case .fang: language.text("Fang", "阿芳")
        case .mayorChen: language.text("Mayor Chen", "陳鎮長")
        }
    }

    /// The asset catalog's portrait, or `nil` for the station master,
    /// whose face is the region's (``RegionStyle``).
    public var portrait: String? {
        switch self {
        case .stationMaster: nil
        case .ahSong: "StoryAhSong"
        case .xiaoWei: "StoryXiaoWei"
        case .mia: "StoryMia"
        case .ahShui: "StoryAhShui"
        case .walsh: "StoryWalsh"
        case .ye: "StoryYe"
        case .lin: "StoryLin"
        case .xiulan: "StoryXiulan"
        case .ahKun: "StoryAhKunLetter"
        case .chou: "StoryChou"
        case .fang: "StoryFang"
        case .mayorChen: "StoryMayorChen"
        }
    }
}

/// A moment of a challenge a line of its story is said at: something that
/// happened at the last midnight, or the day that began then.
public enum StoryMoment: Hashable, Sendable {
    /// Day `n` of the challenge began (1 is the day it started).
    case day(Int64)
    /// Its festival (decision 90) was announced today.
    case festivalAnnounced
    /// Its festival's first day.
    case festivalBegins
    /// The day after its festival's last.
    case festivalOver
    /// A year was closed at the last midnight.
    case yearClosed
    /// The first day of the challenge that made money ended.
    case firstProfitableDay
    /// The company's cash was below zero at the last midnight, and not at
    /// the one before.
    case cashBelowZero
    /// The riders' goal was met at the last midnight.
    case ridersGoalMet
    /// The challenge's goal `index` (a milestone, decision 153) was met at
    /// the last midnight.
    case milestone(Int)
    /// The day that ended at the last midnight carried `percent`% of the
    /// riders' goal, the first day of the challenge that did.
    case riders(percent: Int64)
    /// The challenge's goal `goal` stood at `percent`% or more (as the
    /// goals panel's bar has it) when the day began, the first day the
    /// story's teller saw it so: population, high-rises, profit or worth
    /// keep no past to tell the day it got there from, so only a teller
    /// that saw the day before can (``StoryTeller``).
    case progress(goal: Int, percent: Int64)
    /// The challenge was completed with `rating` at the last midnight.
    case completed(ScenarioRating)
    /// The challenge was lost at the last midnight.
    case failed

    /// Whether it is how the challenge ended.
    var isEnding: Bool {
        switch self {
        case .completed, .failed: true
        default: false
        }
    }

    /// Whether it comes back (every year, every time the cash goes red), or
    /// is how it ended: what can come only once has a day of its own
    /// (``StoryMoment/day(of:in:today:)``).
    var recurs: Bool {
        switch self {
        case .festivalAnnounced, .festivalBegins, .festivalOver, .yearClosed, .cashBelowZero, .completed, .failed: true
        case .day, .firstProfitableDay, .ridersGoalMet, .milestone, .riders, .progress: false
        }
    }
}

/// What a beat waits for (decision 387): a beat of its story told first
/// (Ah-Kun's letters, in order), or a milestone reached (Jiji's station
/// spoken of only once the line reaches it). The beat is then told on the
/// later of its own day and that one's.
public enum StoryPrerequisite: Hashable, Sendable {
    /// The beat `id`, which comes only once.
    case beat(String)
    /// The challenge's goal `index`.
    case milestone(Int)
}

/// The station master's word a beat says too, in one card (decision 387):
/// the story's line over it, rather than the two apart.
public enum StoryAdvice: Hashable, Sendable {
    /// The festival to come (decision 90).
    case festival
    /// A steam train too short to pay (decision 153).
    case shortSteamTrains
    /// The challenge's first words: its line says them already, so the card
    /// only stands for them.
    case welcome
    /// Cash below zero: its line says what to do, so the card only stands
    /// for the station master's word.
    case debt
    /// A station full or crowded.
    case crowding

    /// Whether the card shows the station master's word under the line.
    var showsLine: Bool {
        switch self {
        case .festival, .shortSteamTrains, .crowding: true
        case .welcome, .debt: false
        }
    }
}

/// A line of a challenge's story: when, who and what.
public struct StoryBeat: Hashable, Sendable {
    /// Unique in its story: "pingxi.4".
    public let id: String
    public let moment: StoryMoment
    public let speaker: StoryCharacter
    let english: String
    let chinese: String
    /// The station master's word the beat says too, if any.
    public let carries: StoryAdvice?
    /// What it waits for, if anything; only a beat whose moment comes once
    /// waits.
    public let after: StoryPrerequisite?

    init(
        _ id: String, _ moment: StoryMoment, _ speaker: StoryCharacter, _ english: String, _ chinese: String,
        carries: StoryAdvice? = nil, after: StoryPrerequisite? = nil
    ) {
        precondition(after == nil || !moment.recurs, "Only a beat that comes once waits: \(id)")
        self.id = id
        self.moment = moment
        self.speaker = speaker
        self.english = english
        self.chinese = chinese
        self.carries = carries
        self.after = after
    }

    public func text(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    /// The station master's word the beat stands for, if it carries one
    /// and it applies in `world`: kept from being said again apart.
    public func advice(in world: GameWorld) -> StationMasterAdvice? {
        switch carries {
        case .festival?: StationMasterAdvice.festival(in: world)
        case .shortSteamTrains?: StationMasterAdvice.shortSteamTrains(in: world)
        case .welcome?: StationMasterAdvice.welcome(in: world)
        case .debt?: StationMasterAdvice.debt(in: world)
        case .crowding?: StationMasterAdvice.crowding(in: world)
        case nil: nil
        }
    }

    /// The line under the story's on the card, if any.
    public func adviceLine(in world: GameWorld) -> StationMasterAdvice? {
        carries?.showsLine == true ? advice(in: world) : nil
    }
}

/// A challenge's story (decision 387): its beats, endings among them.
public struct ChallengeStory: Sendable {
    /// The challenge's id: "history.pingxi".
    public let challengeID: String
    let beats: [StoryBeat]

    /// Every challenge's story there is.
    static let all: [ChallengeStory] = [PingxiChallenge.story, LiuMingchuanChallenge.story, BranchLineChallenge.jijiStory] + Challenge.sandboxStories

    /// The story of the challenge `id`, if it has one.
    public static func named(_ id: String) -> ChallengeStory? {
        all.first { $0.challengeID == id }
    }

    /// The beats told on game day `today` in `world`, in the script's
    /// order: those whose moment comes back and came at the midnight that
    /// began it, and those that come once and are due that day; how it
    /// ended, when it did, alone.
    func beats(on today: Int64, in world: GameWorld) -> [StoryBeat] {
        let moments = StoryMoment.moments(in: world, today: today)
        if let ending = moments.first(where: \.isEnding) {
            return beats.filter { $0.moment == ending }
        }
        return beats.filter { beat in
            beat.moment.recurs ? moments.contains(beat.moment) : day(of: beat, in: world, today: today) == today
        }
    }

    /// The day the beat that comes once is told, as `world` stands on
    /// game day `today`: the day its moment began, or the later day its
    /// prerequisite's did; `nil` while either is to come or cannot be
    /// told.
    func day(of beat: StoryBeat, in world: GameWorld, today: Int64) -> Int64? {
        guard let own = StoryMoment.day(of: beat.moment, in: world, today: today) else { return nil }
        switch beat.after {
        case nil:
            return own
        case .milestone(let goal)?:
            guard let achieved = world.scenario?.achieved, achieved.indices.contains(goal), let met = achieved[goal] else { return nil }
            return max(own, met + 1)
        case .beat(let id)?:
            guard let first = beats.first(where: { $0.id == id }), first.id != beat.id,
                  let before = day(of: first, in: world, today: today) else { return nil }
            return max(own, before)
        }
    }

    /// The beats waiting on a goal's progress (``StoryMoment/progress(goal:percent:)``)
    /// whose goal stands at their mark in `world` on game day `today` and
    /// whose prerequisite is met, in the script's order, but for those in
    /// `seen`, which takes them in: the beats a teller looking at this day
    /// has not seen due before. None once the challenge is over.
    func progressBeats(in world: GameWorld, today: Int64, seen: inout Set<String>) -> [StoryBeat] {
        guard let state = world.scenario, state.outcome == nil else { return [] }
        let fractions = world.goalProgress(in: .english).map(\.fraction)
        var due: [StoryBeat] = []
        for beat in beats where !seen.contains(beat.id) {
            guard case .progress(let goal, let percent) = beat.moment, fractions.indices.contains(goal),
                  fractions[goal] * 100 >= Double(percent) else { continue }
            switch beat.after {
            case nil:
                break
            case .milestone(let goal)?:
                guard state.achieved.indices.contains(goal), let met = state.achieved[goal], met + 1 <= today else { continue }
            case .beat(let id)?:
                guard let first = beats.first(where: { $0.id == id }) else { continue }
                if case .progress = first.moment {
                    guard seen.contains(id) else { continue }
                } else {
                    guard let before = day(of: first, in: world, today: today), before <= today else { continue }
                }
            }
            seen.insert(beat.id)
            due.append(beat)
        }
        return due
    }

    /// The beats of the day that began at the last midnight in `world`.
    public func beatsToday(in world: GameWorld) -> [StoryBeat] {
        beats(on: world.clock.now.seconds / GameTime.secondsPerDay, in: world)
    }

    /// How the challenge played in `world` ended, in its story's words, or
    /// `nil` while it runs: the goals panel shows it under the outcome.
    public func ending(in world: GameWorld) -> StoryBeat? {
        let moment: StoryMoment? = switch world.scenario?.outcome {
        case .completed(_, let rating)?: .completed(rating)
        case .failed?: .failed
        case nil: nil
        }
        return moment.flatMap { moment in beats.first { $0.moment == moment } }
    }
}

extension StoryMoment {
    /// The moments that come back of game day `today` in `world`'s
    /// challenge, and how it ended: what happened at the midnight that
    /// began it.
    static func moments(in world: GameWorld, today: Int64) -> [StoryMoment] {
        guard let state = world.scenario, today > state.startDay else { return [] }
        let yesterday = today - 1
        var moments: [StoryMoment] = []
        // Decision 90: a festival starts on day `dayOfYear` of a year,
        // announced `notice` days before, only after the challenge began,
        // at a station still standing, while demand events run
        // (``GameWorld/startDemandEventDay``).
        let year = FinancePeriod.year.days
        func isFestivalStart(_ start: Int64, _ event: ScenarioEvent) -> Bool {
            start > state.startDay && ((start - event.dayOfYear) % year + year) % year == 0
        }
        let festivals = world.demandEvents == nil ? [] : state.scenario.events.filter { world.station(id: $0.station) != nil }
        if festivals.contains(where: { isFestivalStart(today + $0.notice, $0) }) { moments.append(.festivalAnnounced) }
        if festivals.contains(where: { isFestivalStart(today, $0) }) { moments.append(.festivalBegins) }
        if festivals.contains(where: { isFestivalStart(today - $0.days, $0) }) { moments.append(.festivalOver) }
        // A year closes at the midnight that ends its last day (decision
        // 86): one that ran since the challenge began.
        if today % year == 0, world.accounts.years.contains(where: { $0.year == today / year - 1 }) {
            moments.append(.yearClosed)
        }
        if state.outcome == nil, state.insolventDays == 1 { moments.append(.cashBelowZero) }
        switch state.outcome {
        case .completed(let day, let rating)? where day == yesterday: moments.append(.completed(rating))
        case .failed(let day, _)? where day == yesterday: moments.append(.failed)
        default: break
        }
        return moments
    }

    /// The day the moment that comes once began (the day after it
    /// happened), as `world` stands on game day `today`: `nil` while it is
    /// to come, or when it can no longer be told. Never the day the
    /// challenge started.
    static func day(of moment: StoryMoment, in world: GameWorld, today: Int64) -> Int64? {
        guard let state = world.scenario else { return nil }
        let goals = state.scenario.goals
        let ridersGoal = goals.firstIndex { if case .dailyRiders = $0 { true } else { false } }
        // What the days' accounts tell: only while every day of the
        // challenge is still in them (``CompanyAccounts/keptDays``).
        let firstDay = { (counts: (DayAccount) -> Bool) -> Int64? in
            guard today - 1 - state.startDay < Int64(CompanyAccounts.keptDays) - 1 else { return nil }
            return world.accounts.days.first { $0.day >= state.startDay && counts($0) }.map { $0.day + 1 }
        }
        let day: Int64? = switch moment {
        case .day(let n): state.startDay + n - 1
        case .milestone(let goal): goals.indices.contains(goal) ? state.achieved[goal].map { $0 + 1 } : nil
        case .ridersGoalMet: ridersGoal.flatMap { state.achieved[$0] }.map { $0 + 1 }
        case .riders(let percent):
            ridersGoal.flatMap { index -> Int64? in
                guard case .dailyRiders(let target) = goals[index] else { return nil }
                return firstDay { $0.fareTrips * 100 >= target * percent }
            }
        case .firstProfitableDay: firstDay { StationMasterAdvice.operatingResult(on: $0) > .zero }
        case .progress, .festivalAnnounced, .festivalBegins, .festivalOver, .yearClosed, .cashBelowZero, .completed, .failed: nil
        }
        return day.flatMap { $0 > state.startDay ? $0 : nil }
    }
}

/// Tells a challenge's story as the game is played (decision 387): the
/// beats of each day it sees begin, and none of the day it first looks at,
/// so a game loaded or started is not told again what belongs to a day
/// before. Transient, like the station master's memory of what it said;
/// a new game is a new teller.
public struct StoryTeller: Sendable {
    private var lastDay: Int64?
    /// The beats waiting on a goal's progress it has seen due, told or not
    /// (those due on the day it first looked at are not told).
    private var seen: Set<String> = []

    public init() {}

    /// The beats to tell now that `world` is as it is.
    public mutating func look(at world: GameWorld) -> [StoryBeat] {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        defer { lastDay = today }
        let isNewDay = lastDay.map { today > $0 } ?? false
        guard lastDay == nil || isNewDay,
              let story = world.scenario.flatMap({ ChallengeStory.named($0.scenario.id) }) else { return [] }
        let progress = story.progressBeats(in: world, today: today, seen: &seen)
        // The day it first looks at is noted, not told.
        guard isNewDay else { return [] }
        let told = Set((story.beatsToday(in: world) + progress).map(\.id))
        return story.beats.filter { told.contains($0.id) }
    }
}
