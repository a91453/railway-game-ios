import Accessibility
import Charts
import GameCore
import GamePresentation
import SwiftUI

/// A line's riders between each pair of its stops (decision 478): one row
/// per section in stop order, the riders one way to the right of the
/// middle and the other way to the left, so the busiest stretch of the
/// line stands out at a glance. The numbers and sentences are
/// ``LineLoadProfile``'s, tested in `GamePresentation`; worked out off the
/// main thread every ten minutes of game time and when the stops change.
///
/// Colours are the finance charts' first two slots (``Theme/chartBlue`` one
/// way, ``Theme/chartOrange`` the other), named in the legend; touching a
/// row reads its numbers out in words.
struct LineLoadProfileChart: View {
    @Bindable var session: GameSession
    let line: ServiceLine
    @State private var profile: LineLoadProfile?
    @State private var selected: String?
    /// Not literals: a literal here would be a string to translate.
    private static let wayKey = "Way"
    private static let zeroKey = "Zero"

    private var refreshKey: [Int64] {
        [Int64(line.id.rawValue), session.world.clock.now.seconds / 600, session.language == .english ? 0 : 1]
            + line.stops.map { Int64($0.rawValue) }
    }

    var body: some View {
        let language = session.language
        VStack(alignment: .leading, spacing: 10) {
            if let profile {
                Text(verbatim: selectedSection(of: profile).map { profile.sectionText($0, in: language) } ?? profile.summaryText(in: language))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("line.load.summary")
                if profile.busiest != nil {
                    chart(profile)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("line.load")
        .task(id: refreshKey) {
            let world = session.world, id = line.id
            profile = await Task.detached(priority: .userInitiated) { LineLoadProfile(world: world, line: id, in: language) }.value
        }
    }

    /// A section's place on the chart: its number and its stops, so a
    /// station that is a stop twice still gives two rows.
    private func key(_ section: LineLoadProfile.Section) -> String {
        "\(section.index + 1). \(section.label)"
    }

    private func selectedSection(of profile: LineLoadProfile) -> LineLoadProfile.Section? {
        guard let selected else { return nil }
        return profile.sections.first { key($0) == selected }
    }

    private func chart(_ profile: LineLoadProfile) -> some View {
        let spec = profile.chart(in: session.language)
        let colors = [Theme.chartBlue, Theme.chartOrange]
        return Chart {
            ForEach(profile.sections) { section in
                BarMark(x: .value(spec.yTitle, Double(section.outbound)), y: .value(spec.xTitle, key(section)))
                    .foregroundStyle(by: .value(Self.wayKey, profile.outboundName))
                    .opacity(selected == nil || selected == key(section) ? 1 : 0.45)
                BarMark(x: .value(spec.yTitle, -Double(section.inbound)), y: .value(spec.xTitle, key(section)))
                    .foregroundStyle(by: .value(Self.wayKey, profile.inboundName))
                    .opacity(selected == nil || selected == key(section) ? 1 : 0.45)
            }
            RuleMark(x: .value(Self.zeroKey, 0.0))
                .foregroundStyle(Theme.textSecondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartForegroundStyleScale(domain: spec.legendNames, range: colors)
        .chartLegend(position: .top, alignment: .leading) {
            ChartLegend(names: spec.legendNames, colors: colors)
        }
        .chartYSelection(value: $selected)
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.panelBorder)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        // Both ways count up from the middle.
                        Text(verbatim: abs(number).formatted(.number.notation(.compactName)))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .frame(height: CGFloat(40 + 26 * profile.sections.count))
        .accessibilityLabel(Text(verbatim: spec.title))
        .accessibilityValue(Text(verbatim: spec.summary))
        .accessibilityChartDescriptor(ChartAudioGraph(spec: spec))
        .accessibilityIdentifier("line.load.chart")
    }
}

/// A section's riders hour by hour against what its trains carry
/// (decision 478): riders as bars, the seats as a dashed step line, so the
/// hours over the line stand out. The numbers are the network flow
/// report's (``NetworkFlowReport/SectionRow/hourlyChart(title:in:)``).
struct SectionHourlyChart: View {
    let row: NetworkFlowReport.SectionRow
    let title: String
    let language: DisplayLanguage
    @State private var selected: Int?
    /// Not a literal: a literal here would be a string to translate.
    private static let seriesKey = "Series"

    var body: some View {
        let spec = row.hourlyChart(title: title, in: language)
        let colors = [Theme.chartBlue, Theme.textPrimary]
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: selected.map { row.hourText($0, in: language) } ?? spec.summary)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("networkFlow.hourly.summary")
            Chart {
                ForEach(0..<min(24, row.loads.count), id: \.self) { hour in
                    BarMark(x: .value(spec.xTitle, hour), y: .value(spec.yTitle, Double(row.loads[hour])))
                        .foregroundStyle(by: .value(Self.seriesKey, spec.series[0].name))
                        .opacity(selected == nil || selected == hour ? 1 : 0.45)
                }
                ForEach(0..<min(24, row.capacities.count), id: \.self) { hour in
                    LineMark(x: .value(spec.xTitle, hour), y: .value(spec.yTitle, Double(row.capacities[hour])),
                             series: .value(Self.seriesKey, spec.series[1].name))
                        .foregroundStyle(by: .value(Self.seriesKey, spec.series[1].name))
                        .interpolationMethod(.stepCenter)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            }
            .chartForegroundStyleScale(domain: spec.legendNames, range: colors)
            .chartLegend(position: .bottom, alignment: .leading) {
                ChartLegend(names: spec.legendNames, colors: colors, dashedLast: true)
            }
            .chartXSelection(value: $selected)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(verbatim: hour < 10 ? "0\(hour):00" : "\(hour):00")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.panelBorder)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(verbatim: number.formatted(.number.notation(.compactName)))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .frame(height: 150)
            .accessibilityLabel(Text(verbatim: spec.title))
            .accessibilityValue(Text(verbatim: spec.summary))
            .accessibilityChartDescriptor(ChartAudioGraph(spec: spec))
            .accessibilityIdentifier("networkFlow.hourly.chart")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("networkFlow.hourly")
    }
}
