import GameCore
import GamePresentation
import SwiftUI

/// How a line plans its journeys (Stage C3), and a menu of the metro
/// game's design speeds: its speed limit (decision 962: a train runs as
/// its model does, so the presets are no longer offered).
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
    /// `line.performance`.
    let identifier: String
    let choose: @MainActor (TrainPerformance) -> Void

    nonisolated static func == (lhs: PerformanceMenu, rhs: PerformanceMenu) -> Bool {
        lhs.performance == rhs.performance && lhs.language == rhs.language && lhs.identifier == rhs.identifier
    }

    var body: some View {
        Menu {
            Section(language.text("Speed limit", "限速")) {
                ForEach(PerformancePreset.designSpeeds, id: \.self) { speed in
                    Button {
                        choose(performance.withTopSpeed(speed))
                    } label: {
                        option("\(speed) km/h", isChosen: speed == performance.topSpeed)
                    }
                }
            }
        } label: {
            // Touched over at least 44 points: the footnote line alone was
            // some 16 points tall (full lane run 38362099969).
            Label(text, systemImage: "speedometer")
                .font(.footnote)
                .monospacedDigit()
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityHint(Text(verbatim: language.text("Sets the fastest its trains are planned to run.", "設定這條線的列車最快照多少排班。")))
    }

    private var text: String {
        language.text("Speed limit \(performance.topSpeed) km/h", "限速 \(performance.topSpeed) km/h")
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
