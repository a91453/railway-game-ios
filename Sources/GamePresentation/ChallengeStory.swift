import GameCore

// A challenge's story after its opening words (decision 387): a few
// characters who speak, one line each, at the moments of the challenge the
// world can already tell (a day of it, its festival, a year's closing, the
// first day in profit, the first midnight in the red, the riders' goal met,
// how it ended). Data only: a challenge's script is a list of
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

    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .stationMaster: language.text("Station master", "站長")
        case .ahSong: language.text("Uncle Song", "阿松伯")
        case .xiaoWei: language.text("Xiaowei", "小葳")
        case .mia: language.text("Mia", "Mia")
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
}

/// A line of a challenge's story: when, who and what.
public struct StoryBeat: Hashable, Sendable {
    /// Unique in its story: "pingxi.4".
    public let id: String
    public let moment: StoryMoment
    public let speaker: StoryCharacter
    let english: String
    let chinese: String
    /// Decision 387: the beat says the station master's word on the
    /// festival to come too (``StationMasterAdvice/festivalComing(days:stations:percent:)``),
    /// as the line under it, in one card.
    public let carriesFestivalAdvice: Bool

    init(_ id: String, _ moment: StoryMoment, _ speaker: StoryCharacter, _ english: String, _ chinese: String, carriesFestivalAdvice: Bool = false) {
        self.id = id
        self.moment = moment
        self.speaker = speaker
        self.english = english
        self.chinese = chinese
        self.carriesFestivalAdvice = carriesFestivalAdvice
    }

    public func text(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    /// The station master's line under the story's, if it carries one and
    /// it applies in `world`.
    public func advice(in world: GameWorld) -> StationMasterAdvice? {
        carriesFestivalAdvice ? StationMasterAdvice.festival(in: world) : nil
    }
}

/// A challenge's story (decision 387): its beats, endings among them.
public struct ChallengeStory: Sendable {
    /// The challenge's id: "history.pingxi".
    public let challengeID: String
    let beats: [StoryBeat]

    /// Every challenge's story there is.
    static let all: [ChallengeStory] = [PingxiChallenge.story]

    /// The story of the challenge `id`, if it has one.
    public static func named(_ id: String) -> ChallengeStory? {
        all.first { $0.challengeID == id }
    }

    /// The beats said at `moments`, in the script's order; how it ended,
    /// when it did, alone.
    func beats(at moments: [StoryMoment]) -> [StoryBeat] {
        let ending = moments.filter(\.isEnding)
        let said = ending.isEmpty ? moments : ending
        return beats.filter { said.contains($0.moment) }
    }

    /// The beats of the day that began at the last midnight in `world`.
    public func beatsToday(in world: GameWorld) -> [StoryBeat] {
        beats(at: StoryMoment.moments(in: world, today: world.clock.now.seconds / GameTime.secondsPerDay))
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
    /// The moments of game day `today` in `world`'s challenge: what happened
    /// at the midnight that began it.
    static func moments(in world: GameWorld, today: Int64) -> [StoryMoment] {
        guard let state = world.scenario, today > state.startDay else { return [] }
        let yesterday = today - 1
        var moments: [StoryMoment] = [.day(state.elapsedDays(through: today))]
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
        if today % year == 0, today > state.startDay,
           world.accounts.years.contains(where: { $0.year == today / year - 1 }) {
            moments.append(.yearClosed)
        }
        // The first day in profit: only while every day of the challenge is
        // still in the accounts (``CompanyAccounts/keptDays``).
        let profit = { (day: DayAccount) in StationMasterAdvice.operatingResult(on: day) > .zero }
        if yesterday >= state.startDay, yesterday - state.startDay < Int64(CompanyAccounts.keptDays) - 1,
           let last = world.accounts.days.first(where: { $0.day == yesterday }), profit(last),
           !world.accounts.days.contains(where: { $0.day >= state.startDay && $0.day < yesterday && profit($0) }) {
            moments.append(.firstProfitableDay)
        }
        if state.outcome == nil, state.insolventDays == 1 { moments.append(.cashBelowZero) }
        if let riders = state.scenario.goals.firstIndex(where: { if case .dailyRiders = $0 { true } else { false } }),
           state.achieved[riders] == yesterday {
            moments.append(.ridersGoalMet)
        }
        switch state.outcome {
        case .completed(let day, let rating)? where day == yesterday: moments.append(.completed(rating))
        case .failed(let day, _)? where day == yesterday: moments.append(.failed)
        default: break
        }
        return moments
    }
}

/// Tells a challenge's story as the game is played (decision 387): the
/// beats of each day it sees begin, and none of the day it first looks at,
/// so a game loaded or started is not told again what belongs to a day
/// before. Transient, like the station master's memory of what it said;
/// a new game is a new teller.
public struct StoryTeller: Sendable {
    private var lastDay: Int64?

    public init() {}

    /// The beats to tell now that `world` is as it is.
    public mutating func look(at world: GameWorld) -> [StoryBeat] {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        defer { lastDay = today }
        guard let lastDay, today > lastDay,
              let story = world.scenario.flatMap({ ChallengeStory.named($0.scenario.id) }) else { return [] }
        return story.beatsToday(in: world)
    }
}
