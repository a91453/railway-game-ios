import GameCore
import GamePresentation
import SwiftUI
import UIKit

/// Decision 421 (V2): the fixed test of the screen's pace, in the test
/// builds' Settings beside the demo mode: each scenario with its runs on
/// this device and a button to run it, and the results to copy.
struct FrameTimeBenchList: View {
    let launcher: GameLauncher
    /// Closes Settings, for the run's game to show.
    let closeSettings: () -> Void
    @State private var results = FrameTimeBenchResults()

    var body: some View {
        let language = DisplayLanguage.app
        let device = FrameTimeBenchRunner.device
        List {
            Section {
                Text(verbatim: language.text(
                    "Each test starts a new game and moves the map for a minute. Run each one three times, closing the app completely before each.",
                    "每一項會開新遊戲，讓地圖動一分鐘。每項跑三次，每次之前先把 App 完全關掉。"
                ))
                .font(.callout)
                if FrameTimeBenchRunner.isSimulator {
                    Text(verbatim: language.text("On the Simulator the figures say little about a device.", "在模擬器上的數字和實機差很多，只能參考。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(FrameTimeBench.scenarios) { scenario in
                    row(scenario, summary: results.summary(of: scenario, on: device), language: language)
                }
            }
            Section {
                if let text = results.reportText(on: device, in: language) {
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Label(language.text("Copy the Results", "複製結果"), systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        FrameTimeBenchRunner.store.clear(device: device)
                        results = FrameTimeBenchRunner.store.current()
                    } label: {
                        Label(language.text("Clear the Results", "清除結果"), systemImage: "trash")
                    }
                }
            } footer: {
                Text(verbatim: language.text(
                    "The results are also sent with Report a Problem.",
                    "回報問題時也會附上結果。"
                ))
            }
        }
        .navigationTitle(Text(verbatim: language.text("Screen Pace Test", "畫面節奏測試")))
        .task {
            results = await Task.detached(priority: .utility) { FrameTimeBenchRunner.store.current() }.value
        }
    }

    private func row(_ scenario: FrameTimeBench.Scenario, summary: FrameTimeBenchSummary, language: DisplayLanguage) -> some View {
        Button {
            closeSettings()
            FrameTimeBenchRunner.shared.run(scenario, launcher: launcher)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: scenario.title(in: language))
                    .foregroundStyle(.primary)
                Text(verbatim: summaryText(summary, language: language))
                    .font(.caption)
                    .foregroundStyle(summary.isUnsteady ? .orange : .secondary)
            }
        }
        .accessibilityIdentifier("frameTimeBench.\(scenario.id)")
    }

    private func summaryText(_ summary: FrameTimeBenchSummary, language: DisplayLanguage) -> String {
        guard !summary.runs.isEmpty else { return language.text("Not run yet", "還沒跑") }
        let runs = language.text("\(summary.runs.count) of \(FrameTimeBench.runs) runs", "\(summary.runs.count)／\(FrameTimeBench.runs) 次")
        let p95 = String(format: "p95 %.1f ms", summary.p95.middle)
        let unsteady = summary.isUnsteady ? language.text(" · unsteady", " · 不穩定") : ""
        return "\(runs) · \(p95)\(unsteady)"
    }
}

/// Decision 421 (V2): over the game while a test runs: which test, how
/// far it is, and at the end its result to copy.
struct FrameTimeBenchOverlay: View {
    let runner: FrameTimeBenchRunner
    let language: DisplayLanguage

    var body: some View {
        if let running = runner.running {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: running.scenario.title(in: language))
                    .font(.subheadline.weight(.semibold))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(verbatim: status(running.phase, now: context.date))
                        .font(.caption)
                        .monospacedDigit()
                }
                HStack {
                    if case .done(let run?) = running.phase {
                        Button(language.text("Copy", "複製")) {
                            UIPasteboard.general.string = ([running.scenario.title(in: language)]
                                + run.segment.lines(in: language)).joined(separator: "\n")
                        }
                    }
                    Button(isFinished(running.phase) ? language.text("Close", "關閉") : language.text("Stop", "停止")) {
                        runner.stop()
                    }
                    .accessibilityIdentifier("frameTimeBench.stop")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("frameTimeBench.card")
        }
    }

    private func isFinished(_ phase: FrameTimeBenchRunner.Phase) -> Bool {
        switch phase {
        case .done, .failed: true
        default: false
        }
    }

    private func status(_ phase: FrameTimeBenchRunner.Phase, now: Date) -> String {
        switch phase {
        case .preparing:
            return language.text("Laying the lines…", "正在鋪線…")
        case .settling:
            return language.text("Getting ready…", "準備中…")
        case .measuring(let since):
            let left = max(0, Int((FrameTimeBench.seconds - (CACurrentMediaTime() - since)).rounded()))
            return language.text("Timing: \(left) s left. Leave the screen alone.", "計時中：還剩 \(left) 秒，請不要碰螢幕。")
        case .done(let run?):
            return language.text(
                String(format: "Done: p95 %.1f ms, %d severe stalls.", run.p95, run.severe),
                String(format: "完成：p95 %.1f ms，嚴重停頓 %d 次。", run.p95, run.severe)
            )
        case .done(nil):
            return language.text("Done, but too few frames were timed.", "完成，但計到的畫面太少。")
        case .failed(let railwaysLoading):
            return FrameTimeBench.notStarted(railwaysLoading: railwaysLoading, in: language)
        }
    }
}
