import Charts
import GameCore
import GamePresentation
import SwiftUI

/// The network's flow report (decision 416): the lines by the `Ci/`
/// reference's flow dashboard metrics, the busiest sections and the demand
/// the network leaves unmet. Opened from the lines panel's toolbar and the
/// section flow layer's legend. A section or a pair tapped closes the sheet
/// and shows it on the map; a line tapped opens it in the lines panel.
struct NetworkFlowSheet: View {
    @Bindable var session: GameSession
    @Environment(GameScreenState.self) private var screen
    @State private var page: NetworkFlowReport.Page = .lines
    @State private var metric: NetworkFlowReport.LineMetric = .ridership
    @State private var descending = true
    /// Worked out off the main thread (``NetworkFlowReport/init(world:)``);
    /// `nil` until the first one is ready.
    @State private var report: NetworkFlowReport?
    /// The section the hour-by-hour chart shows (decision 478); the
    /// fullest when none is picked.
    @State private var chartSection: Int?

    /// The report is worked out again every ten minutes of game time, and
    /// when the lines change.
    private var refreshKey: [Int64] {
        [session.world.clock.now.seconds / 600, Int64(session.world.lines.count)]
    }

    var body: some View {
        let language = session.language
        NavigationStack {
            List {
                Section {
                    Picker(selection: $page) {
                        ForEach(NetworkFlowReport.Page.allCases, id: \.self) { page in
                            Text(verbatim: page.title(in: language)).tag(page)
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("networkFlow.page")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                if let report {
                    switch page {
                    case .lines: linesPage(report)
                    case .sections: sectionsPage(report)
                    case .unmet: unmetPage(report)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(Text(verbatim: NetworkFlowReport.title(in: language)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { screen.panel = nil }
                }
            }
            .task(id: refreshKey) {
                let world = session.world
                let worked = await Task.detached(priority: .userInitiated) { NetworkFlowReport(world: world) }.value
                report = worked
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Lines

    @ViewBuilder
    private func linesPage(_ report: NetworkFlowReport) -> some View {
        let language = session.language
        let rows = report.lines(sortedBy: metric, descending: descending)
        let largest = rows.map { $0.value(metric) }.max() ?? 0
        Section {
            ForEach(rows) { row in
                Button {
                    session.openLine(row.line)
                    screen.panel = .lines
                } label: {
                    lineRow(row, largest: largest)
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Picker(selection: $metric) {
                    ForEach(NetworkFlowReport.LineMetric.allCases, id: \.self) { metric in
                        Text(verbatim: metric.title(in: language)).tag(metric)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("networkFlow.metric")
                Spacer()
                Button {
                    descending.toggle()
                } label: {
                    Image(systemName: descending ? "arrow.down" : "arrow.up")
                }
                .accessibilityLabel(Text(verbatim: descending
                    ? language.text("Largest first", "由高到低") : language.text("Smallest first", "由低到高")))
            }
        } footer: {
            Text(verbatim: metric.subtitle(in: language))
        }
    }

    private func lineRow(_ row: NetworkFlowReport.LineRow, largest: Double) -> some View {
        let color = Palette.lineColor(row.line, custom: session.world.line(id: row.line)?.color)
        let share = largest > 0 ? row.value(metric) / largest : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: row.valueText(metric, in: session.language))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(color)
                    .frame(width: max(4, proxy.size.width * share))
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sectionsPage(_ report: NetworkFlowReport) -> some View {
        let language = session.language
        // Decision 472: the fullest sections ranked, over the list.
        if !report.rankedSections.isEmpty {
            Section {
                SectionRankingChart(spec: report.rankingChart(in: session.world, language: language), rows: report.rankedSections, language: language)
            }
        }
        // Decision 478: one section hour by hour.
        if let row = report.sections.first(where: { $0.section == chartSection }) ?? report.sections.first {
            Section {
                Picker(selection: Binding(get: { row.section }, set: { chartSection = $0 })) {
                    ForEach(report.sections) { choice in
                        Text(verbatim: NetworkFlowReport.title(of: choice, in: session.world)).tag(choice.section)
                    }
                } label: {
                    Text(verbatim: language.text("Section", "區間"))
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("networkFlow.hourly.section")
                SectionHourlyChart(row: row, title: NetworkFlowReport.title(of: row, in: session.world), language: language)
            } header: {
                Text(verbatim: language.text("Hour by hour", "各時段"))
            } footer: {
                Text(verbatim: language.text(
                    "Riders each hour against the seats its trains carry. Tap an hour for its numbers.",
                    "每個小時的乘客對列車的座位。點一個小時看數字。"))
            }
        }
        Section {
            if report.sections.isEmpty {
                Text(verbatim: report.hasPlan
                    ? language.text("Nobody rides the lines yet.", "還沒有人搭車。")
                    : language.text("Run the game a minute to see the riders.", "讓遊戲走一分鐘，就看得到乘客。"))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(report.sections) { row in
                Button {
                    show(from: row.from, to: row.to)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: NetworkFlowReport.title(of: row, in: session.world))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(verbatim: NetworkFlowReport.valueText(of: row, in: language))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(row.isOverloaded ? Color(SectionFlow.overloadedColor) : Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "map")
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        } footer: {
            Text(verbatim: language.text(
                "Each section at its fullest hour, riders against what its trains carry. Tap one to see it on the map.",
                "每個區間最擠的那個小時，乘客對列車的運能。點一下在地圖上看。"))
        }
    }

    // MARK: - Unmet demand

    @ViewBuilder
    private func unmetPage(_ report: NetworkFlowReport) -> some View {
        let language = session.language
        ForEach(NetworkFlowReport.UnmetKind.allCases, id: \.self) { kind in
            Section {
                let rows = report.unmet(kind)
                if rows.isEmpty {
                    Text(verbatim: kind.emptyText(in: language))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(rows) { row in
                    Button {
                        show(from: row.from, to: row.to)
                    } label: {
                        HStack {
                            Text(verbatim: row.title(in: session.world))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(verbatim: row.valueText(in: language))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(verbatim: kind.title(in: language))
            } footer: {
                Text(verbatim: kind.subtitle(in: language))
            }
        }
    }

    /// Closes the sheet and shows the two stations on the map.
    private func show(from a: StationID, to b: StationID) {
        session.lookOver(from: a, to: b)
        screen.panel = nil
    }
}

/// Decision 472: the fullest sections as bars of how full each is at its
/// fullest hour, fullest first, with a dashed rule at the trains' seats
/// (100%). A section fuller than its seats is in the error colour and its
/// figure says so; the bars are VoiceOver's audio graph.
private struct SectionRankingChart: View {
    let spec: ChartSpec
    let rows: [NetworkFlowReport.SectionRow]
    let language: DisplayLanguage

    /// Not literals: a literal here would be a string to translate.
    private static let sectionAxis = "Section"
    private static let percentAxis = "Percent"
    /// Each bar's room, growing with the text size so its label fits.
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 30

    var body: some View {
        let top = max(100, rows.compactMap(\.percent).max() ?? 0)
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: spec.title)
                .font(.caption.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Chart {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    BarMark(x: .value(Self.percentAxis, row.percent ?? 0), y: .value(Self.sectionAxis, spec.xLabels[index]))
                        .foregroundStyle(row.isOverloaded ? Theme.error : Theme.chartBlue)
                        .annotation(position: .trailing, alignment: .leading) {
                            Text(verbatim: "\(row.percent ?? 0)%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(row.isOverloaded ? Theme.error : Theme.textSecondary)
                        }
                }
                RuleMark(x: .value(Self.percentAxis, 100))
                    .foregroundStyle(Theme.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartXScale(domain: 0...Double(top) * 1.15)
            .chartXAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(Theme.panelBorder)
                    AxisValueLabel {
                        if let number = value.as(Int.self) {
                            Text(verbatim: "\(number)%")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(height: CGFloat(rows.count) * rowHeight + rowHeight)
            .accessibilityLabel(Text(verbatim: spec.title))
            .accessibilityValue(Text(verbatim: spec.summary))
            .accessibilityChartDescriptor(ChartAudioGraph(spec: spec))
            .accessibilityIdentifier("networkFlow.ranking")
            Text(verbatim: spec.summary)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
