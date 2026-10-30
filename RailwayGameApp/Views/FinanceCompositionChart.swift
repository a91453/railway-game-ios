import Accessibility
import Charts
import GameCore
import GamePresentation
import SwiftUI

/// The economy panel's income and cost donuts (decision 480): what the
/// report's period earned and spent, by kind, each ring with its total in
/// the middle. The slices, their shares and the sentences are
/// ``FinanceComposition``'s (tested in `GamePresentation`).
///
/// Each kind keeps its colour (``FinanceComposition/Category/colorSlot``,
/// the theme's chart colours in the dataviz order; "Other" is grey), and
/// colour is never the only cue: every slice is listed beside its ring
/// with its name, amount and share. Touching a slice, or its row, spells
/// it out under the ring; VoiceOver plays each ring as an audio graph.
struct FinanceCompositionChart: View {
    let composition: FinanceComposition
    let language: DisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: language.text("Income and costs by kind", "收支組成"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach([composition.income, composition.costs], id: \.side) { ring in
                CompositionRing(ring: ring, language: language)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("economy.composition")
    }

    static func color(_ category: FinanceComposition.Category) -> Color {
        switch category.colorSlot {
        case 1: Theme.chartBlue
        case 2: Theme.chartOrange
        case 3: Theme.chartAqua
        case 4: Theme.chartYellow
        case 5: Theme.chartMagenta
        case 6: Theme.chartGreen
        case 7: Theme.chartViolet
        case 8: Theme.chartRed
        default: Theme.textSecondary
        }
    }
}

/// One donut and its slices listed beside it; an empty ring keeps its
/// place with its total ($ 0, or "—" with no accounts yet) and no ring.
private struct CompositionRing: View {
    let ring: FinanceComposition.Ring
    let language: DisplayLanguage
    /// Where a finger is on the ring, in dollars from its start.
    @State private var touched: Double?
    /// The slice whose row was tapped, until it is tapped again.
    @State private var pinned: FinanceComposition.Category?
    /// iPhone held sideways is short: a smaller ring keeps the whole of it
    /// on the screen with the rows beside it.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var diameter: CGFloat {
        verticalSizeClass == .compact ? 104 : 136
    }

    private var selected: FinanceComposition.Slice? {
        if let touched, let slice = ring.slice(atDollars: touched) { return slice }
        return pinned.flatMap { category in ring.slices.first { $0.category == category } }
    }

    private var identifier: String {
        ring.side == .income ? "economy.composition.income" : "economy.composition.costs"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    donut
                    rows
                }
                VStack(alignment: .leading, spacing: 12) {
                    donut
                    rows
                }
            }
            Text(verbatim: selected.map { ring.detailText(of: $0, in: language) } ?? ring.summaryText(in: language))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("\(identifier).detail")
        }
        // A Form row sizes itself from the ring's ideal height; stating it
        // keeps the whole ring in the row.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var donut: some View {
        if ring.isEmpty {
            centre
                .frame(width: diameter, height: diameter)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier)
        } else {
            chart
        }
    }

    /// The ring's name and total, in its middle.
    private var centre: some View {
        VStack(spacing: 2) {
            Text(verbatim: ring.title(in: language))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: ring.totalText)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var chart: some View {
        let spec = ring.chart(in: language)
        return Chart(ring.slices) { slice in
            SectorMark(
                angle: .value(spec.yTitle, Double(slice.amount.amount) / 100),
                innerRadius: .ratio(0.62),
                angularInset: 1
            )
            .cornerRadius(3)
            .foregroundStyle(FinanceCompositionChart.color(slice.category))
            .opacity(selected == nil || selected == slice ? 1 : 0.45)
        }
        .chartAngleSelection(value: $touched)
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame {
                    let plot = geometry[frame]
                    centre
                        .frame(width: plot.width * 0.56)
                    .position(x: plot.midX, y: plot.midY)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(Text(verbatim: spec.title))
        .accessibilityValue(Text(verbatim: spec.summary))
        .accessibilityChartDescriptor(ChartAudioGraph(spec: spec))
        .accessibilityIdentifier(identifier)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ring.slices) { slice in
                Button {
                    pinned = pinned == slice.category ? nil : slice.category
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(FinanceCompositionChart.color(slice.category))
                            .frame(width: 10, height: 10)
                        Text(verbatim: slice.category.displayName(in: language))
                            .foregroundStyle(Theme.textPrimary)
                            .fontWeight(selected == slice ? .semibold : .regular)
                        Spacer(minLength: 8)
                        Text(verbatim: "\(slice.amount.moneyText) · \(ring.percentText(of: slice))")
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: ring.detailText(of: slice, in: language)))
                .accessibilityAddTraits(pinned == slice.category ? .isSelected : [])
                .accessibilityIdentifier("\(identifier).\(slice.category.rawValue)")
            }
        }
    }
}
