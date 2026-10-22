import GameCore

// The secretary room (ARCHITECTURE decision 175): the session reads what
// each step of the game changed and keeps it in the news log, pauses for
// the events that matter when the player asked it to, and closes each month
// with a report. Everything is derived from the world; nothing here is
// game state, and GameCore is untouched.

/// What the secretary last saw of the world, to tell what is new in the
/// next step. Not saved: a loaded game starts from what it shows.
struct NewsWatch {
    var day: Int64
    var hour: Int64?
    var month: Int64
    var inDebt: Bool
    var achieved: Set<Int>
    var scenarioID: String?
    var outcomeSeen: Bool
    var deadlineWarned: Bool
    var announcedTyphoons: Set<Int64>
    var landUnlocked: Bool
    /// The day each kind of advice was last written, by key.
    var adviceDays: [String: Int64] = [:]
    /// The day cash last fell below zero and said so: cash that hovers
    /// about zero crosses it again and again, which is told once in ten days.
    var debtNewsDay: Int64 = -100

    init(world: GameWorld) {
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        day = today
        hour = nil
        month = today / FinancePeriod.month.days
        inDebt = world.accounts.mode == .management && world.economy.showsInTheRed
        achieved = Set(world.scenario?.achieved.enumerated().compactMap { $1 == nil ? nil : $0 } ?? [])
        scenarioID = world.scenario?.scenario.id
        outcomeSeen = world.scenario?.outcome != nil
        // A loaded challenge already in its last week has been warned.
        deadlineWarned = world.scenario.map {
            $0.scenario.deadlineDays > 14 && $0.outcome == nil && world.accounts.mode == .management
                && $0.scenario.deadlineDays - $0.elapsedDays(through: today) <= 7
        } ?? false
        announcedTyphoons = Set(world.typhoons(onDay: today).filter { $0.announced <= today }.map(\.start))
        landUnlocked = Self.isLandUnlocked(world)
    }

    /// Whether the company's best day lets it buy another tile of the map
    /// and it has the money for it.
    static func isLandUnlocked(_ world: GameWorld) -> Bool {
        guard let expansion = world.mapExpansion, world.accounts.mode == .management else { return false }
        return expansion.allowance > expansion.owned.count && world.economy.canAfford(expansion.nextPrice)
            && !world.mapTilesForSale().isEmpty
    }
}

extension GameSession {
    /// The day the world is on.
    private var newsToday: Int64 { world.clock.now.seconds / GameTime.secondsPerDay }

    // MARK: - The log

    /// Opens the log: everything in it counts as seen.
    public func markNewsRead() {
        news.markRead()
    }

    /// Takes the log read from a save's side file. The baseline of the
    /// monthly report it had stays; the watch starts from the world.
    public func restoreNews(_ log: NewsLog) {
        isRestoringNews = true
        news = log
        // A baseline of a month not yet reported (a file from another game),
        // the one the game is in too, would stop the reports until the
        // clock caught up.
        let month = world.clock.now.seconds / GameTime.secondsPerDay / FinancePeriod.month.days
        if let reported = news.baseline?.reportedMonth, reported >= month { news.baseline = nil }
        isRestoringNews = false
        if news.baseline == nil { news.baseline = MonthlyBaseline(world: world) }
        newsWatch = NewsWatch(world: world)
    }

    /// Writes the status line's message into the log.
    func noteMessageInNews() {
        guard let message, !isMessageKeptOutOfNews, !message.text.isEmpty else { return }
        let kind: NewsCategory = message.kind == .success ? .success : .failure
        let isEnglish = language == .english
        // The same words again and again (a failed tap repeated) are one item.
        if news.items.prefix(5).contains(where: { $0.text(in: language) == message.text }) { return }
        news.add(
            day: newsToday, kind, english: isEnglish ? message.text : nil, chinese: isEnglish ? nil : message.text
        )
    }

    /// Whether the thing an item points at is still in the world.
    public func canGo(to item: NewsItem) -> Bool {
        switch item.target {
        case .station(let id)?: world.station(id: StationID(rawValue: id)) != nil
        case .line(let id)?: world.line(id: LineID(rawValue: id)) != nil
        case .train(let id)?: world.train(id: TrainID(rawValue: id))?.position != nil
        case nil: false
        }
    }

    /// "Go" on an item: selects the station, line or train and asks the map
    /// to show it (a train is followed).
    public func goTo(_ item: NewsItem) {
        guard canGo(to: item) else { return }
        switch item.target {
        case .station(let raw)?:
            let id = StationID(rawValue: raw)
            selectStation(id)
            focusMap(onStation: id)
        case .line(let raw)?:
            let id = LineID(rawValue: raw)
            selectLine(id)
            if let first = world.line(id: id)?.stops.first { focusMap(onStation: first) }
        case .train(let raw)?:
            let id = TrainID(rawValue: raw)
            // As a tap on the train: the inspector shows it alone.
            tapTrain(id)
            followTrain(id)
        case nil:
            break
        }
    }

    private func focusMap(onStation id: StationID) {
        guard let station = world.station(id: id) else { return }
        if isFollowingTrain { stopFollowingTrain() }
        lookAt(station.location)
    }

    // MARK: - Reading a step

    /// Called after every step of the game: writes what is new into the
    /// log, pauses for what matters and closes a month.
    func observeNews(closedBefore: Int64?) {
        let today = newsToday
        let managed = world.accounts.mode == .management
        var pauseReason: (english: String, chinese: String)?
        func wantPause(_ english: String, _ chinese: String) {
            if pauseReason == nil { pauseReason = (english, chinese) }
        }
        if news.baseline == nil { news.baseline = MonthlyBaseline(world: world) }

        // The year's close.
        if let year = world.accounts.years.last, year.year != closedBefore {
            let profit = year.income.netProfit
            news.add(day: today, .yearEnd) { language in
                language.text(
                    "Year \(year.year + 1) closed: net profit \(profit.moneyText)",
                    "第 \(year.year + 1) 年結算：淨利 \(profit.moneyText)"
                )
            }
        }

        // The scenario: goals met, how it ended, its last week.
        if let state = world.scenario {
            if state.scenario.id != newsWatch.scenarioID {
                newsWatch.scenarioID = state.scenario.id
                newsWatch.achieved = []
                newsWatch.outcomeSeen = false
                newsWatch.deadlineWarned = false
            }
            for (index, day) in state.achieved.enumerated() where day != nil && !newsWatch.achieved.contains(index) {
                newsWatch.achieved.insert(index)
                let english = world.goalProgress(in: .english)
                let chinese = world.goalProgress(in: .traditionalChinese)
                guard english.indices.contains(index) else { continue }
                news.add(
                    day: today, .goal, english: "Goal met: \(english[index].title)", chinese: "目標達成：\(chinese[index].title)"
                )
                wantPause("Goal met", "目標達成")
            }
            if !newsWatch.outcomeSeen, state.outcome != nil {
                newsWatch.outcomeSeen = true
                news.add(
                    day: today, .scenario,
                    english: world.scenarioStatusText(in: .english), chinese: world.scenarioStatusText(in: .traditionalChinese)
                )
            }
            // A challenge stopped by free play is never judged (an old save
            // switched before the lock): nothing to count down.
            if state.outcome == nil, world.accounts.mode == .management, !newsWatch.deadlineWarned, state.scenario.deadlineDays > 14 {
                let left = state.scenario.deadlineDays - state.elapsedDays(through: today)
                if left <= 7 {
                    newsWatch.deadlineWarned = true
                    news.add(day: today, .deadline) { language in
                        language.text(
                            "The challenge ends in \(max(0, left)) day\(left == 1 ? "" : "s").",
                            "挑戰剩 \(max(0, left)) 天結束。"
                        )
                    }
                    wantPause("The challenge's last week", "挑戰剩不到 7 天")
                }
            }
        } else {
            newsWatch.scenarioID = nil
        }

        // Cash going below zero.
        let inDebt = managed && world.economy.showsInTheRed
        if inDebt != newsWatch.inDebt {
            newsWatch.inDebt = inDebt
            if inDebt, today - newsWatch.debtNewsDay >= 10 {
                newsWatch.debtNewsDay = today
                let countdown = world.insolvencyCountdown
                news.add(day: today, .debt) { language in
                    let base = language.text("Cash is below zero.", "現金低於零。")
                    guard let countdown else { return base }
                    return base + " " + insolvencyCountdownText(countdown, in: language) + (language == .english ? "." : "。")
                }
                wantPause("Cash is below zero", "現金低於零")
            }
        }

        if today != newsWatch.day {
            newsWatch.day = today
            observeNewDay(today, managed: managed, wantPause: wantPause)
        }

        // What the station master said, once an hour of game time.
        let hour = world.clock.now.seconds / GameTime.secondsPerHour
        if hour != newsWatch.hour {
            newsWatch.hour = hour
            observeAdvice(today)
        }

        if let pauseReason, pausesForImportantEvents, !world.clock.isPaused {
            pauseForEvent()
            isMessageKeptOutOfNews = true
            message = StatusMessage(
                kind: .success, text: language.text("Paused: \(pauseReason.english).", "已暫停：\(pauseReason.chinese)。")
            )
            isMessageKeptOutOfNews = false
        }
    }

    /// What a new day brings: a holiday or typhoon begins, fuel changes,
    /// land can be bought, a month closes.
    private func observeNewDay(_ today: Int64, managed: Bool, wantPause: (String, String) -> Void) {
        for run in world.holidays(from: today, through: today) where run.start == today {
            let percent = (run.boost + 5) / 10
            let days = run.end - run.start
            news.add(day: today, .holiday) { language in
                language.text(
                    "\(run.holiday.kind.title(in: language)) begins: +\(percent)% demand on every line for \(days) day\(days == 1 ? "" : "s").",
                    "\(run.holiday.kind.title(in: language))開始：全線需求 +\(percent)%，連續 \(days) 天。"
                )
            }
        }

        let served = Set(world.lines.filter { !$0.isFreight }.flatMap(\.stops))
        for typhoon in world.typhoons(onDay: today) {
            let hit = world.stations.filter {
                served.contains($0.id) && $0.operationMode != .closed && typhoon.covers($0.point)
            }.count
            if newsWatch.announcedTyphoons.insert(typhoon.start).inserted {
                let wait = max(0, typhoon.start - today), percent = typhoon.drop / 10
                news.add(day: today, .typhoon) { language in
                    if hit == 0 {
                        return wait > 0
                            ? language.text(
                                "Typhoon warning: it arrives in \(wait) day\(wait == 1 ? "" : "s"); it misses our stations.",
                                "颱風預警：\(wait) 天後來襲，不經過我們的車站。"
                            )
                            : language.text("A typhoon is blowing; it misses our stations.", "颱風正在吹，不經過我們的車站。")
                    }
                    // As the station master's typhoon advice says it.
                    let over = hit == 1 ? "one" : "\(hit)"
                    return wait > 0
                        ? language.text(
                            "Typhoon warning: it arrives in \(wait) day\(wait == 1 ? "" : "s"), over \(over) of our stations, about \(percent)% fewer passengers there.",
                            "颱風預警：\(wait) 天後來襲，影響 \(hit) 個車站，那裡旅客約少 \(percent)%。"
                        )
                        : language.text(
                            "A typhoon is blowing over \(over) of our stations, about \(percent)% fewer passengers there.",
                            "颱風正在影響 \(hit) 個車站，那裡旅客約少 \(percent)%。"
                        )
                }
                if hit > 0 { wantPause("Typhoon warning", "颱風預警") }
            } else if typhoon.start == today {
                news.add(day: today, .typhoon) { language in
                    language.text("The typhoon arrives today.", "颱風今天來襲。")
                }
            }
        }

        if managed, let spell = world.fuelSpell(onDay: today), spell.start == today {
            let percent = (spell.index - 1_000) / 10, days = spell.end - spell.start
            news.add(day: today, .fuel) { language in
                percent >= 0
                    ? language.text("Fuel and power cost \(percent)% more for \(days) days.", "油電價格上漲 \(percent)%，持續 \(days) 天。")
                    : language.text("Fuel and power cost \(-percent)% less for \(days) days.", "油電價格下跌 \(-percent)%，持續 \(days) 天。")
            }
        }

        let unlocked = NewsWatch.isLandUnlocked(world)
        if unlocked, !newsWatch.landUnlocked, let price = world.mapExpansion?.nextPrice {
            news.add(day: today, .land) { language in
                language.text(
                    "A tile of the map can be bought for \(price.moneyText). Open Expand on the map.",
                    "可以用 \(price.moneyText) 買下一塊地圖。點地圖上的「擴建」。"
                )
            }
        }
        newsWatch.landUnlocked = unlocked

        if today / FinancePeriod.month.days > newsWatch.month {
            newsWatch.month = today / FinancePeriod.month.days
            closeMonth(newsWatch.month - 1, today: today)
        }
    }

    /// Writes the report of month `month`, which has just ended.
    private func closeMonth(_ month: Int64, today: Int64) {
        guard let baseline = news.baseline, month > baseline.reportedMonth else { return }
        defer {
            var next = MonthlyBaseline(world: world)
            next.reportedMonth = month
            news.baseline = next
        }
        guard monthlyReportMode != .off, let report = MonthlyReport.make(month: month, in: world, baseline: baseline) else { return }
        news.add(day: today, .monthly) { report.newsText(in: $0) }
        // Not over the tutorial's cards, nor a demo being looked at.
        if monthlyReportMode == .openAndPause, pausesForImportantEvents, tutorial == nil, !news.isDemo {
            monthEndReport = report
            pauseForEvent()
        }
    }

    /// What the station master says now, written once while it stays the
    /// same worry. Decision 330: the game loop works it out with the tick
    /// that made the world, off the main actor (``workedAdvice``); else
    /// here.
    private func observeAdvice(_ today: Int64) {
        let worked = workedAdvice.flatMap { $0.revision == worldRevision ? $0.advice : nil }
        workedAdvice = nil
        let said: StationMasterAdvice?
        if let worked {
            if let leader = worked.leader { lineLossLeaderMemo.keep(leader, atRevision: commandRevision) }
            said = worked.advice
        } else {
            said = StationMasterAdvice(world: world, worstLosingLine: { worstLosingLine })
        }
        guard let advice = said, let entry = advice.newsEntry else { return }
        if let last = newsWatch.adviceDays[entry.key], today - last < 10 { return }
        newsWatch.adviceDays[entry.key] = today
        let english = advice.text(in: .english), chinese = advice.text(in: .traditionalChinese)
        // A game loaded again says the same thing it said before saving.
        if news.items.prefix(30).contains(where: { $0.english == english && $0.chinese == chinese }) { return }
        news.add(day: today, entry.category, english: english, chinese: chinese, target: entry.target)
    }
}

/// Decision 330: the station master's advice (``StationMasterAdvice``),
/// some 40 ms on the Yilan Line, worked out off the main actor with the
/// tick that made the world (``GameSession/LoopTick``), as
/// ``GameSession/observeNews(closedBefore:)`` would work it out on it
/// after the tick: once a game hour, asking the losing line the session
/// keeps while it still answers.
struct AdviceProbe: Sendable {
    /// ``NewsWatch/hour`` when the tick began.
    let hour: Int64?
    /// What the session's ``LineLossLeaderMemo`` keeps at the tick's
    /// command revision, if anything.
    let leader: KeptLineLossLeader?

    /// The advice for `world`, when the hour it is in is not the one last
    /// read; `nil` when it is.
    func advice(of world: GameWorld) -> WorkedAdvice? {
        guard world.clock.now.seconds / GameTime.secondsPerHour != hour else { return nil }
        let day = world.lineLossSettledDay
        var worked: KeptLineLossLeader?
        let advice = StationMasterAdvice(world: world) {
            if let leader, leader.day == day { return leader.leader }
            let losing = world.worstLosingLine()
            worked = KeptLineLossLeader(day: day, leader: losing)
            return losing
        }
        return WorkedAdvice(advice: advice, leader: worked)
    }
}

/// What ``AdviceProbe`` worked out: the advice, and the losing line when
/// it worked that out too, for the session to keep.
struct WorkedAdvice: Equatable, Sendable {
    let advice: StationMasterAdvice?
    let leader: KeptLineLossLeader?
}
