import GameCore
import GamePresentation
import SwiftUI

/// The achievements (decision 181): each with what it asks, how to get it
/// (the reference's `how`), the day it was unlocked, and, from a game, how
/// far the game is towards it. Opened from the start screen and from the
/// company rank in a free game.
struct AchievementsView: View {
    let language: DisplayLanguage
    let records: AchievementRecords
    /// The game's facts, for the progress; `nil` on the start screen.
    var facts: AchievementFacts?

    var body: some View {
        List {
            Section {
                // Decision 174: in a game without attractions, the
                // tourists' marks are not listed.
                ForEach(Achievement.all.filter { facts?.hasTourism ?? true || !$0.needsTourism }) { achievement in
                    row(achievement)
                }
            } footer: {
                Text(verbatim: language.text(
                    "Checked every midnight in your own games; the demos do not count. Kept on this device.",
                    "每天午夜在你自己的遊戲裡檢查，示範地圖不算。記錄在這台裝置上。"
                ))
            }
        }
        .navigationTitle(Text(verbatim: language.text(
            "Achievements \(records.count)/\(Achievement.all.count)", "成就 \(records.count)/\(Achievement.all.count)"
        )))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ achievement: Achievement) -> some View {
        let date = records.unlocked[achievement.id]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: achievement.symbol)
                .font(.title3)
                .frame(width: 32)
                .foregroundStyle(date == nil ? Theme.textSecondary : Theme.primary)
                .opacity(date == nil ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: achievement.title(in: language))
                        .fontWeight(.semibold)
                    Spacer()
                    if let date {
                        Text(date, format: .dateTime.year().month().day())
                            .font(.caption)
                            .foregroundStyle(Theme.success)
                    }
                }
                Text(verbatim: achievement.detail(in: language))
                    .font(.footnote)
                if date == nil, let facts, let progress = achievement.progress(of: facts),
                   let text = achievement.progressText(of: facts) {
                    ProgressView(value: Double(progress.now), total: Double(progress.need))
                        .tint(Theme.primary)
                    Text(verbatim: text)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(verbatim: achievement.how(in: language))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("achievement.\(achievement.id)")
    }
}
