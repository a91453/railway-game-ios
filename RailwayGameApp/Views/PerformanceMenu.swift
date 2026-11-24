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
    /// `train.performance` or `line.performance`.
    let identifier: String
    /// TRAIN-IDENTITY: `false` on a train's card, under the train's one
    /// name: the figures alone, the preset ticked in the menu.
    var showsName = true
    /// Under the train's name beside its picture: the figures alone on
    /// one line, a little smaller rather than wrapped (owner, 2026-11-24).
    var compact = false
    let choose: @MainActor (TrainPerformance) -> Void

    nonisolated static func == (lhs: PerformanceMenu, rhs: PerformanceMenu) -> Bool {
        lhs.performance == rhs.performance && lhs.language == rhs.language && lhs.identifier == rhs.identifier
            && lhs.showsName == rhs.showsName && lhs.compact == rhs.compact
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
            // Touched over at least 44 points: the footnote line alone was
            // some 16 points tall (full lane run 38362099969).
            if compact {
                HStack(spacing: 4) {
                    Text(verbatim: text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .imageScale(.small)
                }
                .font(.footnote)
                .monospacedDigit()
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            } else {
                Label(text, systemImage: "speedometer")
                    .font(.footnote)
                    .monospacedDigit()
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("Performance: \(performance.displayText(in: language))")
        .accessibilityHint("Chooses how it accelerates, brakes and how fast it may run.")
    }

    private var text: String {
        showsName ? performance.displayText(in: language) : performance.figuresText(in: language)
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
