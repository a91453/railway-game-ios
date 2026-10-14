import GameCore
import GamePresentation
import SwiftUI

/// Decision 224 (1C), its last part: today's settlements under the company
/// rank. Today's finished trips, how many were on time and what they
/// earned, then the latest eight, each with its line's badge, its route,
/// its takings and an on-time or late stamp (decision 223's capsule).
/// Read from the trip log (``TripSettlements``, decision 223 point 5) once
/// a game minute, not every tick. Not shown at all without a trip today
/// (no trip log, or none finished yet): decision 224 shows no made-up rows.
struct TodaySettlementsSection: View {
    let session: GameSession
    /// The minute's settlements, kept so the ticks between do not read the
    /// trip log again. A box, not state: filled while the body is drawn,
    /// which must not ask for another drawing. (A `.task` would never run
    /// while the section shows nothing.)
    @State private var cache = Cache()

    @MainActor
    private final class Cache {
        var minute: Int64?
        var settled: TripSettlements?
    }

    private var minute: Int64 {
        session.world.clock.now.seconds / GameTime.secondsPerMinute
    }

    /// This minute's settlements, read again when the minute has changed.
    private func current() -> TripSettlements? {
        if cache.minute != minute {
            cache.settled = TripSettlements(world: session.world, limit: 8)
            cache.minute = minute
        }
        return cache.settled
    }

    var body: some View {
        let language = session.language
        Group {
            if let settled = current(), settled.completed > 0 || !settled.entries.isEmpty {
                Section {
                    summary(settled, language: language)
                    ForEach(settled.entries) { entry in
                        row(entry, language: language)
                    }
                } header: {
                    Text(verbatim: language.text("Today's trips", "今天的結算"))
                } footer: {
                    Text(verbatim: language.text(
                        "Each train's run to the end of its line, as it arrives: the fares it brought in and whether it was on time.",
                        "每一班列車跑完全程時記一筆：帶進多少票收、有沒有準點。"
                    ))
                }
                .accessibilityIdentifier("goals.settlements")
            }
        }
    }

    private func summary(_ settled: TripSettlements, language: DisplayLanguage) -> some View {
        HStack(spacing: 0) {
            figure(language.text("Trips", "完成班次"), "\(settled.completed)")
            figure(language.text("On time", "準點率"), settled.onTimePercent.map { "\($0)%" } ?? "—")
            figure(language.text("Fares", "票收"), "+" + TrainRoster.shortMoney(settled.fares), tint: Theme.success)
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ title: String, _ value: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ entry: TripSettlements.Entry, language: DisplayLanguage) -> some View {
        HStack(spacing: 8) {
            if let line = entry.line {
                LineCodeBadge(
                    code: entry.lineCode ?? "",
                    color: Palette.lineColor(line, custom: session.world.line(id: line)?.color),
                    size: .small
                )
            } else {
                Circle()
                    .fill(Palette.train)
                    .frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.trainName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(verbatim: entry.routeText)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: entry.fareText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.success)
                .monospacedDigit()
            TrainStatusCapsule(text: entry.stampText(in: language), kind: entry.isLate ? .late : .onTime)
            if let late = entry.lateText(in: language) {
                Text(verbatim: late)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.warning)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
