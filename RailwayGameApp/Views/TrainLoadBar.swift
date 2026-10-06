import GamePresentation
import SwiftUI

/// A tactile progress bar for a train's load factor, faithfully matching
/// `Ci/`'s `pax-bar-fill` styling and color thresholds:
/// - `< 70%`: green (`Palette.metroGreen`)
/// - `70% ..< 90%`: amber (`Palette.metroAmber`)
/// - `>= 90%`: red (`Palette.metroRed`), with overload animation / alert
struct TrainLoadBar: View {
    let load: TrainLoadInfo
    let language: DisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label {
                    Text(verbatim: language.text("Load Factor", "載客率"))
                        .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(barColor)
                }

                Spacer()

                Text(verbatim: "\(load.passengerCount) / \(load.capacity) · \(load.percentage)%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(barColor)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let fillRatio = min(1.0, max(0.0, load.loadFactor))
                let fillWidth = width * CGFloat(fillRatio)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .systemGray5))
                        .frame(height: 8)

                    Capsule()
                        .fill(barColor)
                        .frame(width: fillWidth, height: 8)
                }
            }
            .frame(height: 8)

            if load.isOverload {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(verbatim: language.text("Over capacity", "超載運行中"))
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Color.red)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(language.text("Load Factor", "載客率")): \(load.percentage)% (\(load.passengerCount) / \(load.capacity))"))
    }

    private var barColor: Color {
        switch load.level {
        case .normal:
            return Palette.metroGreen
        case .busy:
            return Palette.metroAmber
        case .crowded:
            return Palette.metroRed
        }
    }
}
