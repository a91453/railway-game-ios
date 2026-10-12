import GameCore
import GamePresentation
import SwiftUI

/// How a train or a line runs (Stage C3), and a menu of the reference
/// presets and the metro game's design speeds.
///
/// Keeps no performance of its own: `performance` is read from the world
/// when the view is drawn, and a choice calls `choose`, which applies one
/// `GameWorld` command through the session.
///
/// Equatable on what it shows, and used with `.equatable()`, so the ticks of
/// a running game leave it alone while it is open (decision 184, later).
struct PerformanceMenu: View, Equatable {
    let performance: TrainPerformance
    let language: DisplayLanguage
    let choose: @MainActor (TrainPerformance) -> Void

    nonisolated static func == (lhs: PerformanceMenu, rhs: PerformanceMenu) -> Bool {
        lhs.performance == rhs.performance && lhs.language == rhs.language
    }

    var body: some View {
        Menu {
            Section("Preset") {
                ForEach(PerformancePreset.allCases, id: \.self) { preset in
                    Button {
                        choose(preset.performance)
                    } label: {
                        option(preset.title(in: language), isChosen: preset.performance == performance)
                    }
                }
            }
            Section("Design speed") {
                ForEach(PerformancePreset.designSpeeds, id: \.self) { speed in
                    Button {
                        choose(performance.withTopSpeed(speed))
                    } label: {
                        option("\(speed) km/h", isChosen: speed == performance.topSpeed)
                    }
                }
            }
        } label: {
            Label(performance.displayText(in: language), systemImage: "speedometer")
                .font(.footnote)
                .monospacedDigit()
        }
        .accessibilityLabel("Performance: \(performance.displayText(in: language))")
        .accessibilityHint("Chooses how it accelerates, brakes and how fast it may run.")
    }

    @ViewBuilder
    private func option(_ title: String, isChosen: Bool) -> some View {
        if isChosen {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: "checkmark")
            }
        } else {
            Text(verbatim: title)
        }
    }
}
