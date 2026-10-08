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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                GoalsSections(session: session)
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

    var body: some View {
        let language = session.language
        let world = session.world
        if world.scenario == nil {
            Section {
                Text(verbatim: language.text("This game has no goals. Start a challenge from the start screen.", "這局沒有目標。可以從開始畫面選擇挑戰。"))
                    .foregroundStyle(Theme.textSecondary)
            }
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

/// The start screen's challenges (decision 86): each with its story, goals
/// and ratings; choosing one starts a new game on a blank map with it.
struct ChallengePicker: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let language = launcher.language
        NavigationStack {
            List {
                ForEach(Challenge.sandbox) { challenge in
                    Button {
                        dismiss()
                        launcher.startChallenge(challenge)
                    } label: {
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
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("challenge.\(challenge.id)")
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
}
