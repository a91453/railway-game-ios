import GameCore
import GamePresentation
import SwiftUI

/// The train roster (列車運用表, ARCHITECTURE decision 223, point 3, layout
/// A): a row for each train (its line's badge, its name, what it earned and
/// how much of the day it ran), a box for each trip across the day's hours:
/// on time in the success colour, late in the warning colour with "+N" and
/// a navy corner, the trip running now outlined in navy, the trips still
/// to come dashed. Many trains on an iPhone held sideways take the short
/// rows of layout C.
///
/// View only. ``TrainRoster`` works it all out from the trip log (Linux
/// tests); this view only draws it, built again every second away from the
/// main thread.
struct TrainRosterView: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var day: TrainRoster.Day = .today
    @State private var roster: TrainRoster?
    /// Counts up to ask the hours to scroll to now.
    @State private var scrollToNow = 0

    /// How often the roster is built again, in real seconds.
    private static let refresh: Duration = .seconds(1)
    private static let axisHeight: CGFloat = 24
    private static let rowGap: CGFloat = 4

    private var language: DisplayLanguage { session.language }
    private var compactWidth: Bool { horizontalSizeClass == .compact }
    /// Points an hour takes across.
    private var hourWidth: CGFloat { compactWidth ? 90 : 120 }
    private var nameWidth: CGFloat { compactWidth ? 104 : 150 }

    var body: some View {
        NavigationStack {
            Group {
                if let roster {
                    VStack(spacing: 0) {
                        header(roster)
                        if roster.rows.isEmpty {
                            Text(verbatim: language.text("No trains ran on this day.", "這一天沒有列車行駛。"))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            table(roster)
                        }
                        legend
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.background)
            .navigationTitle(Text(verbatim: language.text("Train roster", "列車運用表")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Close", "關閉"))
                    }
                    .accessibilityIdentifier("trainRoster.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        scrollToNow += 1
                    } label: {
                        Label {
                            Text(verbatim: language.text("Now", "現在"))
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                    .disabled(day != .today)
                    .accessibilityIdentifier("trainRoster.now")
                }
            }
        }
        .task(id: day) {
            roster = nil
            while !Task.isCancelled {
                let world = session.world
                let shown = day
                let built = await Task.detached(priority: .userInitiated) {
                    TrainRoster(world: world, day: shown)
                }.value
                guard !Task.isCancelled else { return }
                roster = built
                try? await Task.sleep(for: Self.refresh)
            }
        }
        .accessibilityIdentifier("trainRoster")
    }

    // MARK: Header and legend

    private func header(_ roster: TrainRoster) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(verbatim: roster.summaryText(in: language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityIdentifier("trainRoster.summary")
                Spacer(minLength: 8)
                Picker(selection: $day) {
                    ForEach(TrainRoster.Day.allCases, id: \.self) { day in
                        Text(verbatim: day.title(in: language)).tag(day)
                    }
                } label: {
                    Text(verbatim: language.text("Day", "日期"))
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("trainRoster.day")
            }
            Text(verbatim: language.text(
                "Each box is one trip and what it earned for its line. Riders who change trains pay once, where they start.",
                "每一格是一趟，寫它替路線賺到的票價。轉乘的旅客只在起點付一次票。"
            ))
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { legendItems }
            VStack(alignment: .leading, spacing: 4) { legendItems }
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var legendItems: some View {
        legendBox(language.text("On time", "準點"), fill: Theme.success, mark: false)
        legendBox(language.text("Late", "誤點"), fill: Theme.warning, mark: true)
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Palette.ink, lineWidth: 2)
                .frame(width: 18, height: 12)
            Text(verbatim: language.text("Running", "行駛中"))
        }
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Theme.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 18, height: 12)
            Text(verbatim: language.text("Planned", "預定"))
        }
        HStack(spacing: 4) {
            Rectangle()
                .fill(Palette.ink)
                .frame(width: 2, height: 12)
            Text(verbatim: language.text("Now", "現在"))
        }
    }

    private func legendBox(_ text: String, fill: Color, mark: Bool) -> some View {
        HStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(fill)
                    .frame(width: 18, height: 12)
                if mark {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 6, y: 0))
                        path.addLine(to: CGPoint(x: 6, y: 6))
                        path.closeSubpath()
                    }
                    .fill(Palette.ink)
                    .frame(width: 6, height: 6)
                }
            }
            Text(verbatim: text)
        }
    }

    // MARK: Table

    private func table(_ roster: TrainRoster) -> some View {
        GeometryReader { proxy in
            let compact = TrainRosterLayout.usesCompactRows(rows: roster.rows.count, height: Double(proxy.size.height - Self.axisHeight))
            let rowHeight = CGFloat(compact ? TrainRosterLayout.compactRowHeight : TrainRosterLayout.fullRowHeight)
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: Self.axisHeight)
                        ForEach(Array(roster.rows.enumerated()), id: \.element.id) { index, row in
                            nameCell(row, compact: compact)
                                .frame(width: nameWidth, height: rowHeight)
                                .background(index.isMultiple(of: 2) ? Theme.chip : Color.clear)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(verbatim: spoken(row)))
                        }
                    }
                    hours(roster, rowHeight: rowHeight, compact: compact)
                }
            }
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.panelBorder))
        .padding(.horizontal, 8)
    }

    private func nameCell(_ row: TrainRoster.Row, compact: Bool) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let line = row.line, let code = row.lineCode {
                        LineCodeBadge(code: code, color: Palette.lineColor(line, custom: session.world.line(id: line)?.color), size: .small)
                    }
                    Text(verbatim: row.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                if !compact {
                    Text(verbatim: TrainRoster.shortMoney(row.revenue) + " · " + "\(row.utilisation)%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // How much of the day it ran, as a short upright bar.
            GeometryReader { bar in
                ZStack(alignment: .bottom) {
                    Theme.chip
                    Theme.primary
                        .frame(height: bar.size.height * CGFloat(row.utilisation) / 100)
                }
            }
            .frame(width: 4)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 8)
    }

    private func hours(_ roster: TrainRoster, rowHeight: CGFloat, compact: Bool) -> some View {
        let width = hourWidth * 24
        let height = Self.axisHeight + rowHeight * CGFloat(roster.rows.count)
        let nowX = x(roster.now, in: roster)
        return ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        draw(roster, rowHeight: rowHeight, compact: compact, context: &context)
                    }
                    .frame(width: width, height: height)
                    .accessibilityHidden(true)
                    // Where the hours scroll to: now, or the day's first
                    // trip for yesterday.
                    Color.clear
                        .frame(width: 1, height: 1)
                        .padding(.leading, roster.day == .today ? min(max(nowX, 0), width - 1) : firstTripX(roster))
                        .id(Self.anchor)
                }
            }
            .onAppear { reader.scrollTo(Self.anchor, anchor: UnitPoint(x: 0.7, y: 0)) }
            .onChange(of: scrollToNow) { reader.scrollTo(Self.anchor, anchor: UnitPoint(x: 0.7, y: 0)) }
            .onChange(of: roster.day) { reader.scrollTo(Self.anchor, anchor: UnitPoint(x: 0.1, y: 0)) }
        }
    }

    private static let anchor = "trainRoster.anchor"

    private func x(_ time: Int64, in roster: TrainRoster) -> CGFloat {
        CGFloat(Double(time - roster.dayStart) / Double(GameTime.secondsPerHour)) * hourWidth
    }

    private func firstTripX(_ roster: TrainRoster) -> CGFloat {
        let first = roster.rows.compactMap { $0.cells.first?.start }.min() ?? roster.dayStart
        return max(0, x(first, in: roster))
    }

    private func draw(_ roster: TrainRoster, rowHeight: CGFloat, compact: Bool, context: inout GraphicsContext) {
        let width = hourWidth * 24
        let height = Self.axisHeight + rowHeight * CGFloat(roster.rows.count)

        // Every other row on the faint chip, as the names beside them.
        for index in roster.rows.indices where index.isMultiple(of: 2) {
            let band = CGRect(x: 0, y: Self.axisHeight + rowHeight * CGFloat(index), width: width, height: rowHeight)
            context.fill(Path(band), with: .color(Theme.chip))
        }

        // The hours: a label and a faint rule each.
        for hour in 0..<24 {
            let hourX = hourWidth * CGFloat(hour)
            var rule = Path()
            rule.move(to: CGPoint(x: hourX, y: Self.axisHeight))
            rule.addLine(to: CGPoint(x: hourX, y: height))
            context.stroke(rule, with: .color(Theme.panelBorder), lineWidth: 1)
            let label = Text(verbatim: GameTime(seconds: roster.dayStart + Int64(hour) * GameTime.secondsPerHour).clockText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            context.draw(label, at: CGPoint(x: hourX + 3, y: Self.axisHeight / 2), anchor: .leading)
        }

        // The trips.
        for (index, row) in roster.rows.enumerated() {
            let top = Self.axisHeight + rowHeight * CGFloat(index) + Self.rowGap
            let boxHeight = rowHeight - 2 * Self.rowGap
            for cell in row.cells {
                let left = x(cell.start, in: roster)
                let right = max(left + 4, x(cell.end, in: roster))
                let box = CGRect(x: left, y: top, width: right - left, height: boxHeight)
                draw(cell, in: box, compact: compact, context: &context)
            }
        }

        // Now, with its time on a tag.
        if roster.day == .today {
            let nowX = x(roster.now, in: roster)
            var line = Path()
            line.move(to: CGPoint(x: nowX, y: Self.axisHeight - 4))
            line.addLine(to: CGPoint(x: nowX, y: height))
            context.stroke(line, with: .color(Palette.ink), lineWidth: 2)
            let tag = context.resolve(Text(verbatim: GameTime(seconds: roster.now).clockText)
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(Palette.markerFill))
            let size = tag.measure(in: CGSize(width: 80, height: Self.axisHeight))
            let tagRect = CGRect(x: nowX - size.width / 2 - 4, y: 2, width: size.width + 8, height: Self.axisHeight - 6)
            context.fill(Path(roundedRect: tagRect, cornerRadius: 4), with: .color(Palette.ink))
            context.draw(tag, at: CGPoint(x: tagRect.midX, y: tagRect.midY), anchor: .center)
        }
    }

    private func draw(_ cell: TrainRoster.Cell, in box: CGRect, compact: Bool, context: inout GraphicsContext) {
        let shape = Path(roundedRect: box, cornerRadius: 4)
        let fill: Color?
        let text: Color
        switch cell.state {
        case .onTime:
            fill = Theme.success
            text = Theme.onPrimary
        case .late:
            fill = Theme.warning
            text = Theme.onPrimary
        case .running:
            fill = cell.isLate ? Theme.warning : Theme.success
            text = Theme.onPrimary
        case .interrupted:
            fill = Theme.chip
            text = Theme.textSecondary
        case .planned:
            fill = nil
            text = Theme.textSecondary
        }
        if let fill {
            context.fill(shape, with: .color(cell.isEmptyRun ? Theme.chip : fill))
        }
        switch cell.state {
        case .running:
            context.stroke(shape, with: .color(Palette.ink), lineWidth: 2)
        case .planned:
            context.stroke(shape, with: .color(Theme.textSecondary), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        case .interrupted:
            context.stroke(shape, with: .color(Theme.textSecondary), lineWidth: 1)
        default:
            if cell.isEmptyRun { context.stroke(shape, with: .color(Theme.textSecondary), lineWidth: 1) }
        }
        // A late trip's navy corner: grey alone cannot tell late from on
        // time (decision 223, point 4).
        if cell.isLate {
            var corner = Path()
            corner.move(to: CGPoint(x: box.maxX - 8, y: box.minY))
            corner.addLine(to: CGPoint(x: box.maxX, y: box.minY))
            corner.addLine(to: CGPoint(x: box.maxX, y: box.minY + 8))
            corner.closeSubpath()
            context.fill(corner, with: .color(Palette.ink))
        }

        // The words, where the box is wide enough.
        guard box.width >= 28 else { return }
        let color = cell.isEmptyRun ? Theme.textSecondary : text
        var layer = context
        layer.clip(to: shape)
        let late = cell.lateText.map { " " + $0 } ?? ""
        if compact {
            let line = cell.isLate ? (cell.lateText ?? "") : cell.state == .planned ? "" : TrainRoster.shortMoney(cell.fare)
            layer.draw(Text(verbatim: line).font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(color),
                       at: CGPoint(x: box.minX + 4, y: box.midY), anchor: .leading)
        } else {
            layer.draw(Text(verbatim: cell.routeText + late).font(.caption2.weight(.bold)).foregroundStyle(color),
                       at: CGPoint(x: box.minX + 4, y: box.minY + 2), anchor: .topLeading)
            layer.draw(Text(verbatim: cell.detailText(in: language)).font(.caption2.monospacedDigit()).foregroundStyle(color),
                       at: CGPoint(x: box.minX + 4, y: box.maxY - 2), anchor: .bottomLeading)
        }
    }

    private func spoken(_ row: TrainRoster.Row) -> String {
        var parts = [row.name, TrainRoster.shortMoney(row.revenue), language.text("in use \(row.utilisation)%", "使用率 \(row.utilisation)%")]
        parts += row.cells.map { $0.spokenText(in: language) }
        return parts.joined(separator: "；")
    }
}
