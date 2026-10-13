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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                GoalsSections(session: session, achievements: achievements)
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

    var body: some View {
        let language = session.language
        let world = session.world
        // Decision 183: the city's requests, in a free game.
        if world.hasCityRequests {
            CityRequestsSection(session: session)
        }
        if world.scenario == nil {
            // Decision 181: a free game's long-term goal.
            CompanyRankSection(session: session, achievements: achievements)
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
                if let location = row.location {
                    Button {
                        session.lookAt(location)
                        dismiss()
                    } label: {
                        Label {
                            Text(verbatim: language.text("Show on map", "在地圖上看"))
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                    }
                    .buttonStyle(.bordered)
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
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(verbatim: rank.headline(in: language))
                            .fontWeight(.semibold)
                    } icon: {
                        Image(systemName: rank.title == .tycoon ? "crown.fill" : "person.crop.circle.badge.checkmark")
                            .foregroundStyle(Theme.primary)
                    }
                    ProgressView(value: Double(rank.score), total: 1_000)
                        .tint(Theme.primary)
                    Text(verbatim: rank.nextTitleText(in: language))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("goals.rank")
                ForEach(rank.parts, id: \.measure) { part in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: rank.partText(part, in: language))
                            .font(.footnote)
                            .monospacedDigit()
                        ProgressView(value: Double(part.points), total: Double(part.maximum))
                            .tint(part.points == part.maximum ? Theme.success : Theme.primary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                ProgressView()
            }
        } header: {
            Text(verbatim: language.text("Company rank", "公司評等"))
        } footer: {
            Text(verbatim: language.text(
                "Measured on the best day's riders, track, stations, net worth, people within 800 m of a station, yesterday's operating ratio and the trains on time now.",
                "依最佳單日旅客、路網長度、車站數、淨值、車站 800 m 內的住戶、昨天的營業比與目前列車的準點率評分。"
            ))
        }
        .task(id: today) {
            rank = CompanyRank(world: session.world)
            town = UnservedCluster.largest(in: session.world)
            if achievements != nil { facts = AchievementFacts(world: session.world) }
        }
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
            } header: {
                Text(verbatim: language.text("Next steps", "下一步"))
            }
        }
    }
}

/// The start screen's challenges (decision 86): the week's (decision 87),
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
