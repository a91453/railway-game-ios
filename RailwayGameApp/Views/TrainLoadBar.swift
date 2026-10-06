import GamePresentation
import SwiftUI

/// A train's load, ported from the `Ci/` reference's train panel
/// (`game-dom` `#panel-train`): a `sec-lbl` row with "Load factor"
/// (`metro.train.load_factor`) and the percentage (`#pt-load`), over a
/// 5-point `.pax-bar-bg` track whose `.pax-bar-fill` is one neutral colour
/// and turns red (`.is-overload`) only when the rounded percentage is over
/// 100 (``TrainLoadInfo/isOverload``). The reference's rated capacity and
/// current passengers rows (`#pt-cap`, `#pt-pax`) follow as one caption.
struct TrainLoadBar: View {
    let load: TrainLoadInfo
    let language: DisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: language.text("Load Factor", "載客率"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "\(load.percentage)%")
                    .font(.caption.weight(.bold).monospacedDigit())
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.paxBarTrack)
                    Capsule()
                        .fill(load.isOverload ? Palette.paxBarOverload : Palette.paxBarFill)
                        .frame(width: proxy.size.width * load.barFraction)
                }
            }
            .frame(height: 5)
            .animation(.linear(duration: 0.2), value: load.barFraction)

            Text(verbatim: language.text(
                "Current passengers \(load.passengerCount) · Rated capacity \(load.capacity)",
                "當前載客 \(load.passengerCount) · 額定載客 \(load.capacity)"
            ))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: language.text("Load Factor", "載客率")))
        .accessibilityValue(Text(verbatim: "\(load.percentage)% (\(load.passengerCount) / \(load.capacity))"))
    }
}
