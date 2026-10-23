import GameCore
import GamePresentation
import SwiftUI

/// The scenario's goals (decision 86): its title and where it stands, each
/// goal with how far it is and the day it was met, and the days each
/// rating needs. Opened from the game menu and the economy panel, and by
/// itself when the scenario ends while playing. Everything shown is read
/// from `session.world`; the words come from GamePresentation.
struct GoalsPanel: View {
    let session: GameSession
    /// The achievements unlocked (decision 181), for the rank's link.
    var achievements: AchievementRecords?
    /// The station stamps (decision 353), for the passport's link.
    var stamps: StationStampRecords? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                GoalsSections(session: session, achievements: achievements, stamps: stamps)
            }
            .navigationTitle(Text(verbatim: session.world.scenarioTitle(in: session.language) ?? session.language.text("Goals", "目標")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: session.language.text("Done", "完成"))
                    }
                    .accessibilityIdentifier("goals.done")
                }
            }
        }
    }
}

/// The goals panel's sections, also shown in the economy panel.
struct GoalsSections: View {
    let session: GameSession
    var achievements: AchievementRecords?
    var stamps: StationStampRecords? = nil

    var body: some View {
        let language = session.language
        let world = session.world
        // CTM study M2: a free game's next steps, first.
        if let steps = session.nextSteps {
            NextStepsSection(steps: steps, language: language)
        }
        // Decision 183: the city's requests, in a free game.
        if world.hasCityRequests {
            CityRequestsSection(session: session)
        }
        if world.scenario == nil {
            // Decision 181: a free game's long-term goal.
            CompanyRankSection(session: session, achievements: achievements, stamps: stamps)
        } else {
            Section {
                if let status = world.scenarioStatusText(in: language) {
                    Label {
                        Text(verbatim: status)
                            .fontWeight(.semibold)
                    } icon: {
                        Image(systemName: icon(of: world.scenario?.outcome))
                            .foregroundStyle(tint(of: world.scenario?.outcome))
                    }
                    .accessibilityIdentifier("goals.status")
                }
                // Decision 175: the days left before the red ends it.
                if let days = world.insolvencyCountdown {
                    Label {
                        Text(verbatim: insolvencyCountdownText(days, in: language) + language.text(
                            ": cash has been below zero at midnight",
                            "：午夜現金仍低於零"
                        ))
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.error)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.error)
                    }
                    .accessibilityIdentifier("goals.insolvency")
                }
                if let story = world.scenario.flatMap({ Challenge.named($0.scenario.id) })?.story(in: language) {
                    Text(verbatim: story)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            } footer: {
                if let ratings = world.scenarioRatingsText(in: language) {
                    Text(verbatim: ratings)
                }
            }
            Section {
                ForEach(Array(world.goalProgress(in: language).enumerated()), id: \.offset) { _, goal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: goal.metOnDay == nil ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(goal.metOnDay == nil ? Theme.textSecondary : Theme.success)
                            Text(verbatim: goal.title)
                                .fontWeight(.semibold)
                            Spacer()
                            if let day = goal.metOnDay {
                                Text(verbatim: language.text("Day \(day)", "第 \(day) 天"))
                                    .font(.caption)
                                    .foregroundStyle(Theme.success)
                            }
                        }
                        ProgressView(value: goal.fraction)
                            .tint(goal.metOnDay == nil ? Theme.primary : Theme.success)
                        Text(verbatim: goal.detail)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(verbatim: language.text("Goals", "目標"))
            } footer: {
                Text(verbatim: language.text(
                    "Goals are checked every midnight. After a challenge ends, the game goes on.",
                    "每天午夜檢查目標。挑戰結束之後可以繼續玩下去。"
                ))
            }
            TodaySettlementsSection(session: session)
        }
    }

    private func icon(of outcome: ScenarioOutcome?) -> String {
        switch outcome {
        case .completed?: "medal.fill"
        case .failed?: "xmark.octagon.fill"
        case nil: "flag.fill"
        }
    }

    private func tint(of outcome: ScenarioOutcome?) -> Color {
        switch outcome {
        case .completed?: Theme.success
        case .failed?: Theme.error
        case nil: Theme.primary
        }
    }
}

/// The city's requests (decision 183): the trust and the subsidies, the
/// requests in hand with their progress and days left, the month's offers
/// to take on or turn down, and the last results. "Show on map" takes the
/// map to the place asked about.
struct CityRequestsSection: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let language = session.language
        let world = session.world
        let rows = world.cityRequestRows(in: language, placeNames: session.placeNames)
        let room = (world.cityRequests?.active.count ?? 0) < (world.cityRequests?.capacity ?? 0)
        Section {
            if let trust = world.cityTrustText(in: language) {
                Text(verbatim: trust)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("requests.trust")
            }
            if let subsidy = world.citySubsidyText(in: language) {
                Text(verbatim: subsidy)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            if rows.isEmpty {
                Text(verbatim: language.text("No requests this month. New ones come on the 1st.", "這個月沒有委託，下個月 1 日會有新的。"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(rows) { row in
                requestRow(row, room: room, language: language)
            }
            ForEach(world.cityRequestResults(in: language, placeNames: session.placeNames).prefix(5)) { result in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: result.title)
                        Text(verbatim: result.text)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } icon: {
                    Image(systemName: result.succeeded ? "checkmark.seal.fill" : "xmark.circle")
                        .foregroundStyle(result.succeeded ? Theme.success : Theme.textSecondary)
                }
                .font(.footnote)
            }
        } header: {
            Text(verbatim: language.text("City requests", "委託案"))
        } footer: {
            Text(verbatim: world.cityRequestsHelp(in: language))
        }
    }

    private func requestRow(_ row: CityRequestRow, room: Bool, language: DisplayLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: row.isActive ? "hourglass" : "envelope.badge")
                    .foregroundStyle(row.isActive ? Theme.primary : Theme.textSecondary)
                Text(verbatim: row.title)
                    .fontWeight(.semibold)
                Spacer()
                Text(verbatim: row.rewardText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.success)
                    .monospacedDigit()
            }
            Text(verbatim: row.detail)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if row.isActive {
                ProgressView(value: Double(row.progress) / 1_000)
                    .tint(Theme.primary)
            }
            HStack {
                Text(verbatim: row.progressText + " · " + row.daysLeftText)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                Spacer()
            }
            HStack(spacing: 12) {
                if !row.isActive {
                    Button {
                        session.acceptRequest(row.id)
                    } label: {
                        Text(verbatim: language.text("Take on", "承接"))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!room)
                    .accessibilityIdentifier("requests.accept.\(row.id)")
                }
                Button(role: row.isActive ? ButtonRole.destructive : nil) {
                    session.declineRequest(row.id)
                } label: {
                    Text(verbatim: row.isActive ? language.text("Give up", "放棄") : language.text("Turn down", "婉拒"))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("requests.decline.\(row.id)")
                if row.location != nil {
                    Button {
                        // Decision 246: pointed out there, ringed, with
                        // its card.
                        session.showRequestOnMap(row.id)
                        dismiss()
                    } label: {
                        Label {
                            Text(verbatim: language.text("Show on map", "在地圖上看"))
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("requests.show.\(row.id)")
                }
            }
            .font(.caption)
        }
        .font(.footnote)
        .padding(.vertical, 2)
    }
}

/// The company's rank (decision 181): the score and title, each measure's
/// bar, what the next title needs, the next tile of the map, three next
/// milestones and the next town to reach. Measured when the panel opens
/// and once a game day, not every tick: the people served and the town
/// read the whole land.
struct CompanyRankSection: View {
    let session: GameSession
    let achievements: AchievementRecords?
    /// Decision 353: the passport's link beside the achievements'.
    var stamps: StationStampRecords? = nil
    @State private var rank: CompanyRank?
    @State private var town: UnservedCluster?
    /// What the achievements read, measured with the rank.
    @State private var facts: AchievementFacts?
    @Environment(\.dismiss) private var dismiss

    private var today: Int64 {
        session.world.clock.now.seconds / GameTime.secondsPerDay
    }

    var body: some View {
        let language = session.language
        Section {
            // Decision 200: a game with unlimited funds is not ranked.
            if session.world.economy.unlimitedFunds {
                Text(verbatim: GameEconomy.uncountedText(in: language))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("goals.uncounted")
            } else if let rank {
                // Decision 224 (1C): the titles as a line, the company's
                // train where it stands.
                PromotionLineView(line: PromotionLine(rank: rank), language: language)
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(verbatim: rank.headline(in: language))
                            .fontWeight(.semibold)
                    } icon: {
                        Image(systemName: rank.title == .tycoon ? "crown.fill" : "person.crop.circle.badge.checkmark")
                            .foregroundStyle(Theme.primary)
                    }
                    Text(verbatim: rank.nextTitleText(in: language))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("goals.rank")
                // Decision 224 (1C): the seven measures as a train's cars.
                ScoreTrainView(rank: rank, language: language)
                    .accessibilityIdentifier("goals.scoreTrain")
            } else {
                ProgressView()
            }
        } header: {
            Text(verbatim: language.text("Company rank", "公司評等"))
        } footer: {
            Text(verbatim: language.text(
                "Rises with your best day's riders, track, stations, net worth, people near stations, operating ratio and trains on time.",
                "最佳單日旅客、路網長度、車站數、淨值、車站附近的住戶、營業比與準點率越好，評等越高。"
            ))
        }
        .task(id: today) {
            rank = CompanyRank(world: session.world)
            town = UnservedCluster.largest(in: session.world)
            if achievements != nil { facts = AchievementFacts(world: session.world) }
        }
        // Decision 224 (1C): today's trips under the rank.
        TodaySettlementsSection(session: session)
        if let rank {
            Section {
                if let tiles = session.mapExpansionText {
                    Label {
                        Text(verbatim: tiles)
                    } icon: {
                        Image(systemName: "square.grid.3x3.topleft.filled")
                    }
                    .font(.footnote)
                }
                ForEach(rank.milestones(), id: \.measure) { milestone in
                    Label {
                        Text(verbatim: milestone.text(in: language))
                            .monospacedDigit()
                    } icon: {
                        Image(systemName: "flag")
                    }
                    .font(.footnote)
                }
                if let town {
                    Button {
                        session.lookAt(town.center)
                        dismiss()
                    } label: {
                        Label {
                            Text(verbatim: town.suggestionText(in: session.world, language: language))
                        } icon: {
                            Image(systemName: "location.magnifyingglass")
                        }
                        .font(.footnote)
                    }
                    .accessibilityIdentifier("goals.nextTown")
                }
                if let achievements, session.world.economy.unlimitedFunds {
                    // Decision 200: the entry is greyed and says why.
                    Label {
                        Text(verbatim: language.text(
                            "Achievements \(achievements.count)/\(Achievement.all.count): not counted with unlimited funds",
                            "成就 \(achievements.count)/\(Achievement.all.count)：資金無限的局不計成就"
                        ))
                    } icon: {
                        Image(systemName: "rosette")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("goals.achievements")
                } else if let achievements {
                    NavigationLink {
                        AchievementsView(language: language, records: achievements, facts: facts)
                    } label: {
                        Label {
                            Text(verbatim: language.text(
                                "Achievements \(achievements.count)/\(Achievement.all.count)",
                                "成就 \(achievements.count)/\(Achievement.all.count)"
                            ))
                        } icon: {
                            Image(systemName: "rosette")
                        }
                        .font(.footnote)
                    }
                    .accessibilityIdentifier("goals.achievements")
                }
                // Decision 353: the passport too, which a game with
                // unlimited funds still fills (decision 348).
                if let stamps {
                    NavigationLink {
                        StationStampPassportView(
                            language: language, records: stamps, railways: session.railways, placeNames: session.placeNames
                        )
                    } label: {
                        Label {
                            Text(verbatim: StationStampPassport.summary(count: stamps.count, total: nil, in: language))
                        } icon: {
                            Image(systemName: "seal")
                        }
                        .font(.footnote)
                    }
                    .accessibilityIdentifier("goals.stamps")
                }
            } header: {
                Text(verbatim: language.text("Next steps", "下一步"))
            }
        }
    }
}

/// The new game page's challenges (decision 86; decision 381 moved them
/// there from the start screen): the week's (decision 87),
/// then the others, each with its story, goals, ratings and the player's
/// best; choosing one starts a new game on a blank map with it.
struct ChallengePicker: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss
    /// The week when the picker opened.
    @State private var weekly = WeeklyChallenge(containing: Date())

    var body: some View {
        let language = launcher.language
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                        launcher.startWeeklyChallenge()
                    } label: {
                        card(weekly.challenge, in: language)
                    }
                    .accessibilityIdentifier("challenge.weekly")
                } header: {
                    Text(verbatim: language.text("This week", "本週"))
                } footer: {
                    Text(verbatim: language.text(
                        "Everyone gets the same map until Sunday night, Taiwan time: \(weekly.daysLeft(from: Date())) days left.",
                        "到台灣時間週日午夜前，大家都玩同一張地圖：還剩 \(weekly.daysLeft(from: Date())) 天。"
                    ))
                }
                // Decision 90: Taiwan's railway history, on real maps that
                // wait for the real-world data.
                Section {
                    ForEach(Challenge.history) { challenge in
                        Button {
                            dismiss()
                            launcher.startChallenge(challenge)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                card(challenge, in: language)
                                if challenge.map == .pingxi {
                                    Label {
                                        Text(verbatim: PingxiChallenge.festivalText(in: language))
                                    } icon: {
                                        Image(systemName: "sparkles")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Theme.primary)
                                } else if challenge.map == .liuMingchuan {
                                    // Decision 153: its milestones and era.
                                    Label {
                                        Text(verbatim: LiuMingchuanChallenge.milestonesText(in: language))
                                    } icon: {
                                        Image(systemName: "flag.checkered")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Theme.primary)
                                } else if case .branchLine(let id) = challenge.map, let line = BranchLineChallenge.line(id) {
                                    // Decision 289: its milestones and sights.
                                    Label {
                                        Text(verbatim: line.cardText(in: language))
                                    } icon: {
                                        Image(systemName: "tram")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Theme.primary)
                                }
                            }
                        }
                        .disabled(launcher.railways == nil)
                        .accessibilityIdentifier("challenge.\(challenge.id)")
                    }
                } header: {
                    Text(verbatim: language.text("Taiwan railway history", "台灣鐵道史"))
                } footer: {
                    Text(verbatim: launcher.railways == nil
                        ? language.text("Waiting for the real-world data.", "正在等待實景資料。")
                        : language.text("On a map of the real place.", "在真實地點的地圖上開局。"))
                }
                Section {
                    ForEach(Challenge.sandbox) { challenge in
                        Button {
                            dismiss()
                            launcher.startChallenge(challenge)
                        } label: {
                            card(challenge, in: language)
                        }
                        .accessibilityIdentifier("challenge.\(challenge.id)")
                    }
                } header: {
                    Text(verbatim: language.text("Challenges", "挑戰"))
                } footer: {
                    Text(verbatim: language.text("A new map each time.", "每次都是新的地圖。"))
                }
            }
            .navigationTitle(Text(verbatim: language.text("Challenges", "挑戰")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Cancel", "取消"))
                    }
                }
            }
        }
    }

    private func card(_ challenge: Challenge, in language: DisplayLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: challenge.title(in: language))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(verbatim: challenge.story(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            ForEach(challenge.goalsText(in: language), id: \.self) { goal in
                Label {
                    Text(verbatim: goal)
                } icon: {
                    Image(systemName: "flag")
                }
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
            }
            Text(verbatim: challenge.ratingsText(in: language))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if let best = launcher.records.best[challenge.id] {
                Label {
                    Text(verbatim: best.text(in: language))
                } icon: {
                    Image(systemName: "medal.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.success)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The lessons (decision 266): one card each, in order, with the stars it
/// was passed with; a lesson opens once the one before it is passed.
struct LessonPicker: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let language = launcher.language
        NavigationStack {
            List {
                // Decision 266, later: every lesson passed, the way on is
                // free play, where every tool is open.
                if launcher.passedEveryLesson {
                    Section {
                        Label {
                            Text(verbatim: language.text(
                                "Every lesson passed. Free play has every tool from the start.",
                                "全部關卡都過了。自由模式一開始就有全部的工具。"
                            ))
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Theme.accent)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityIdentifier("lessons.allPassed")
                        Button {
                            dismiss()
                            launcher.startNewGame()
                        } label: {
                            Text(verbatim: language.text("Start Free Play", "開始自由模式"))
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(ThemeProminentButtonStyle())
                        .accessibilityIdentifier("lessons.freePlay")
                    }
                }
                Section {
                    ForEach(Lesson.all) { lesson in
                        card(lesson, in: language)
                    }
                } footer: {
                    Text(verbatim: language.text(
                        "Each lesson teaches one thing in a short game. Pass one to open the next. Free play has every tool from the start.",
                        "每一關用一場短短的遊戲教一件事，過關就開下一關。自由模式一開始就有全部的工具。"
                    ))
                }
            }
            .navigationTitle(Text(verbatim: language.text("Lessons", "入門")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(verbatim: language.text(
                        "Lessons · ★ \(launcher.lessonStarTotal)/\(3 * Lesson.all.count)",
                        "入門 · ★ \(launcher.lessonStarTotal)/\(3 * Lesson.all.count)"
                    ))
                    .font(.headline)
                    .accessibilityIdentifier("lessons.title")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Cancel", "取消"))
                    }
                }
            }
        }
    }

    private func card(_ lesson: Lesson, in language: DisplayLanguage) -> some View {
        let isOpen = launcher.isOpen(lesson)
        let stars = launcher.stars(of: lesson)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(lesson.number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 28, height: 28)
                    .background(isOpen ? Theme.primary : Theme.textSecondary, in: Circle())
                Text(verbatim: lesson.challenge.title(in: language))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                LessonStars(count: stars)
                    .accessibilityLabel(Text(verbatim: language.text("\(stars) of 3 stars", "3 顆星中的 \(stars) 顆")))
            }
            Text(verbatim: lesson.challenge.story(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Label {
                Text(verbatim: lesson.teaches(in: language))
            } icon: {
                Image(systemName: "graduationcap")
            }
            .font(.footnote)
            .foregroundStyle(Theme.textPrimary)
            ForEach(lesson.challenge.goalsText(in: language), id: \.self) { goal in
                Label {
                    Text(verbatim: goal)
                } icon: {
                    Image(systemName: "flag")
                }
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
            }
            Text(verbatim: lesson.starsText(in: language))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if isOpen {
                Button {
                    dismiss()
                    launcher.startLesson(lesson)
                } label: {
                    Text(verbatim: stars > 0 ? language.text("Play Again", "再玩一次") : language.text("Start", "開始"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ThemeProminentButtonStyle())
                .accessibilityIdentifier("lesson.\(lesson.number).start")
            } else {
                Label {
                    Text(verbatim: language.text("Pass lesson \(lesson.number - 1) to open it.", "先通過第 \(lesson.number - 1) 關。"))
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lesson.\(lesson.number)")
    }
}

/// Three stars, `count` of them filled (decision 266): SF Symbols, as the
/// interface's icons are (decision 121).
struct LessonStars: View {
    let count: Int
    var shown = 3

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < count && index < shown ? "star.fill" : "star")
                    .foregroundStyle(index < count && index < shown ? Theme.accent : Theme.textSecondary)
            }
        }
        .font(.subheadline)
    }
}

/// How a lesson ended (decision 266): its stars, lit one after another
/// (`MotionRule.pop`, 0.15 s apart, at once with Reduce Motion), and the
/// next lesson, the same again, or the game played on.
struct LessonResultCard: View {
    let result: LessonResult
    let language: DisplayLanguage
    let next: () -> Void
    let again: () -> Void
    let keepPlaying: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = 0

    var body: some View {
        VStack(spacing: 14) {
            Text(verbatim: result.title(in: language))
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("lessonResult.title")
            LessonStars(count: result.stars, shown: lit)
                .font(.largeTitle)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: language.text("\(result.stars) of 3 stars", "3 顆星中的 \(result.stars) 顆")))
                .accessibilityIdentifier("lessonResult.stars")
            Text(verbatim: result.detail(in: language))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if result.next != nil {
                Button(action: next) {
                    Text(verbatim: language.text("Next Lesson", "下一關"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ThemeProminentButtonStyle())
                .accessibilityIdentifier("lessonResult.next")
            }
            Button(action: again) {
                Text(verbatim: language.text("Play Again", "再玩一次"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("lessonResult.again")
            Button(action: keepPlaying) {
                Text(verbatim: language.text("Keep Playing", "繼續玩"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("lessonResult.keepPlaying")
        }
        .padding(24)
        .frame(maxWidth: 360)
        .task {
            guard !reduceMotion else {
                lit = result.stars
                return
            }
            for star in 1...max(1, result.stars) where star <= result.stars {
                try? await Task.sleep(for: .milliseconds(150))
                withAnimation(MotionRule.pop.layout(reduceMotion: reduceMotion)) { lit = star }
            }
        }
    }
}
