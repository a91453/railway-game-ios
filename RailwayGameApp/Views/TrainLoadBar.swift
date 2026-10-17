import GamePresentation
import SwiftUI

/// A train's load, ported from the `Ci/` reference's train panel
/// (`game-dom` `#panel-train`): a `sec-lbl` row with "Load factor"
/// (`metro.train.load_factor`) and the percentage (`#pt-load`), over a
/// 5-point `.pax-bar-bg` track whose `.pax-bar-fill` is one neutral colour
/// and turns red (`.is-overload`) only when the rounded percentage is over
/// 100 (``TrainLoadInfo/isOverload``). The reference's rated capacity and
/// current passengers rows (`#pt-cap`, `#pt-pax`) follow as one caption. A
/// freight train's load is its tons (decision 155): its title and caption
/// say so (``TrainLoadInfo/isFreight``).
struct TrainLoadBar: View {
    let load: TrainLoadInfo
    let language: DisplayLanguage
    /// Decision 274: the train's cars, for its seat map under the bar;
    /// `nil` draws none (a freight train never has one).
    var cars: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: load.titleText(in: language))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(verbatim: "\(load.percentage)%")
                    .font(.caption.weight(.bold).monospacedDigit())
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.panelBorder)
                    Capsule()
                        .fill(load.isOverload ? Theme.error : Theme.textPrimary)
                        .frame(width: proxy.size.width * load.barFraction)
                }
            }
            .frame(height: 5)
            .animation(.linear(duration: 0.2), value: load.barFraction)

            Text(verbatim: load.detailText(in: language))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            if let cars, !load.isFreight {
                SeatMapView(map: SeatMap(load: load, cars: cars))
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: load.titleText(in: language)))
        // The detail line names the unit: tons for a freight train.
        .accessibilityValue(Text(verbatim: "\(load.percentage)%, \(load.detailText(in: language))"))
    }
}

/// Decision 274: a train's seats as full as it is: each car a rounded box
/// of two rows of four seats, taken seats filled, and a person standing
/// after the last car when more ride than it is rated for. Flat shapes in
/// the theme's colours (art style); still, with nothing to animate.
struct SeatMapView: View {
    let map: SeatMap

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<map.cars, id: \.self) { car in
                VStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 2) {
                            ForEach(0..<SeatMap.seatsPerCar / 2, id: \.self) { column in
                                let seat = row * SeatMap.seatsPerCar / 2 + column
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(map.isFilled(car: car, seat: seat) ? (map.standing ? Theme.error : Theme.textPrimary) : Theme.panelBorder)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.textSecondary, lineWidth: 1))
            }
            if map.standing {
                Image(systemName: "figure.stand")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.error)
            }
        }
        .accessibilityHidden(true)
    }
}
