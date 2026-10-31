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
/// ``TrainRoster`` works it all out from the trip log (Linux tests); this
/// view only draws it, built again every second away from the main thread.
///
/// Decision 512: opened from a line's page it shows that line's trains,
/// and from a train's card that train's row, outlined. Under Arrange, a
/// train's name held and dragged onto a row of another line gives it to
/// that line, and a planned box held and dragged sideways moves its
/// train's timetable; ``TrainRosterDrag`` says where the finger is and
/// what letting go does, and letting go sends one command Undo takes back.
struct TrainRosterView: View {
    let session: GameSession
    /// The line whose trains it shows, or `nil` for all.
    var line: LineID? = nil
    /// The train whose row it scrolls to and outlines.
    var focus: TrainID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var day: TrainRoster.Day = .today
    @State private var roster: TrainRoster?
    /// Counts up to ask the hours to scroll to now.
    @State private var scrollToNow = 0
    /// Counts up to build the roster again at once, after an edit.
    @State private var rebuild = 0
    /// Opened from a line's page: whether it shows every line's trains.
    @State private var allLines = false
    /// Whether the trains can be dragged (decision 512).
    @State private var arranging = false
    /// What the last drop did, said under the header.
    @State private var result: String?
    @GestureState private var lineDrag: LineDrag? = nil
    @GestureState private var shiftDrag: ShiftDrag? = nil

    /// A train's name being dragged over the rows.
    private struct LineDrag {
        let train: TrainID
        let name: String
        var location: CGPoint = .zero
        var row: Int?
        var move: TrainRosterDrag.LineMove?
    }

    /// A planned box being dragged sideways.
    private struct ShiftDrag {
        let row: Int
        let train: TrainID
        var seconds: Int64 = 0
        var shift: TrainRosterDrag.Shift?
    }

    /// How often the roster is built again, in real seconds.
    private static let refresh: Duration = .seconds(1)
    private static let axisHeight: CGFloat = 24
    private static let rowGap: CGFloat = 4
    private static let table = "trainRoster.table"

    private var language: DisplayLanguage { session.language }
    private var compactWidth: Bool { horizontalSizeClass == .compact }
    /// Points an hour takes across.
    private var hourWidth: CGFloat { compactWidth ? 90 : 120 }
    /// The names' column; arranging adds the grip before the name, so the
    /// name keeps its room (decision 512).
    private var nameWidth: CGFloat { (compactWidth ? 104 : 150) + (arranging ? 24 : 0) }

    var body: some View {
        NavigationStack {
            Group {
                if let built = roster {
                    let roster = built.only(line: allLines ? nil : line)
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
                ToolbarItemGroup(placement: .primaryAction) {
                    if arranging {
                        Button {
                            session.undo()
                            result = session.message?.text
                            rebuild += 1
                        } label: {
                            Label {
                                Text(verbatim: language.text("Undo", "復原"))
                            } icon: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                        }
                        .disabled(!session.canUndo)
                        .accessibilityIdentifier("trainRoster.undo")
                    }
                    // Decision 512: moving trains on the roster, today only.
                    Button {
                        arranging.toggle()
                        result = nil
                        if arranging { day = .today }
                    } label: {
                        Text(verbatim: arranging ? language.text("Done", "完成") : language.text("Arrange", "編排"))
                    }
                    .accessibilityIdentifier("trainRoster.arrange")
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
        .onChange(of: day) { roster = nil }
        .task(id: RosterKey(day: day, rebuild: rebuild)) {
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

    /// What the roster is built again for.
    private struct RosterKey: Hashable {
        let day: TrainRoster.Day
        let rebuild: Int
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
                .disabled(arranging)
                .accessibilityIdentifier("trainRoster.day")
            }
            if let line, let name = session.world.line(id: line)?.name {
                Picker(selection: $allLines) {
                    Text(verbatim: name).tag(false)
                    Text(verbatim: language.text("All lines", "全部路線")).tag(true)
                } label: {
                    Text(verbatim: language.text("Lines", "路線"))
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("trainRoster.lines")
            }
            dragNote
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Under the header: what the drag under the finger would do, what
    /// the last drop did, how to arrange, or what a box is.
    @ViewBuilder
    private var dragNote: some View {
        if let drag = lineDrag {
            if let move = drag.move {
                note(([move.text(in: language)] + move.notes).joined(separator: "；"), ok: move.drops)
            } else {
                note(language.text("Drop \(drag.name) on a row of another line", "把 \(drag.name) 放到別條線的列上"), ok: false)
            }
        } else if let drag = shiftDrag, let shift = drag.shift {
            let station = session.world.train(id: drag.train)?.timetable.first.map { session.world.station(id: $0.station)?.name ?? "?" } ?? "?"
            note(([shift.text(in: language)] + [shift.clashText(station: station, in: language)].compactMap(\.self)).joined(separator: "；"),
                 ok: shift.drops && shift.clash == nil)
        } else if arranging {
            Text(verbatim: result ?? language.text(
                "Hold a train's name and drag it onto another line's row to move it there. Hold a planned box and drag it sideways to change its times.",
                "長按車名，拖到別條線的列上就改派過去。長按預定的格子左右拖，改它的時刻。"
            ))
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier("trainRoster.arrangeHint")
        } else {
            Text(verbatim: language.text(
                "Each box is one trip and what it earned for its line. Riders who change trains pay once, where they start.",
                "每一格是一趟，寫它替路線賺到的票價。轉乘的旅客只在起點付一次票。"
            ))
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func note(_ text: String, ok: Bool) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: ok ? "arrow.down.to.line" : "exclamationmark.triangle.fill")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(ok ? Theme.textPrimary : Theme.warning)
        .accessibilityIdentifier("trainRoster.dragNote")
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
            // Decision 512: arranging keeps the full rows, so a name to
            // hold is at least 44 points high.
            let compact = !arranging
                && TrainRosterLayout.usesCompactRows(rows: roster.rows.count, height: Double(proxy.size.height - Self.axisHeight))
            let rowHeight = CGFloat(compact ? TrainRosterLayout.compactRowHeight : TrainRosterLayout.fullRowHeight)
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: Self.axisHeight)
                            ForEach(Array(roster.rows.enumerated()), id: \.element.id) { index, row in
                                nameCell(row, compact: compact)
                                    .frame(width: nameWidth, height: rowHeight)
                                    .background(index.isMultiple(of: 2) ? Theme.chip : Color.clear)
                                    .overlay {
                                        if row.train == focus {
                                            Rectangle().strokeBorder(Palette.ink, lineWidth: 2)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .gesture(nameDrag(row, roster: roster, rowHeight: rowHeight), including: arranging ? .all : .subviews)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(Text(verbatim: spoken(row)))
                                    .accessibilityActions { if arranging { arrangeActions(row) } }
                                    .id(row.train)
                            }
                        }
                        // As wide as the table leaves: the hours' scroll
                        // view took more and pushed the names right
                        // (decision 512's screenshot review).
                        hours(roster, rowHeight: rowHeight, compact: compact)
                            .frame(width: max(0, proxy.size.width - nameWidth))
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                    .coordinateSpace(.named(Self.table))
                    .overlay(alignment: .topLeading) { lineDragMarks(rowHeight: rowHeight, width: proxy.size.width) }
                }
                .onAppear {
                    if let focus { reader.scrollTo(focus, anchor: .center) }
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
            if arranging {
                Image(systemName: "line.3.horizontal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
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
                    // Why a line's train has no planned boxes.
                    if let note = row.dispatchText(in: language) {
                        Text(verbatim: note)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
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
                    let moving = shiftDrag
                    Canvas { context, _ in
                        draw(roster, rowHeight: rowHeight, compact: compact, context: &context)
                        if let moving { drawMoved(moving, in: roster, rowHeight: rowHeight, context: &context) }
                    }
                    .frame(width: width, height: height)
                    .gesture(boxDrag(roster, rowHeight: rowHeight), including: arranging ? .all : .subviews)
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

    // MARK: Arranging (decision 512)

    /// A train's name held, then dragged onto a row of another line.
    private func nameDrag(_ row: TrainRoster.Row, roster: TrainRoster, rowHeight: CGFloat) -> some Gesture {
        let rows = roster.rows
        func target(_ y: CGFloat) -> Int? {
            TrainRosterDrag.row(atY: Double(y), axisHeight: Double(Self.axisHeight), rowHeight: Double(rowHeight), rows: rows.count)
        }
        return LongPressGesture(minimumDuration: TrainRosterDrag.holdSeconds)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.table)))
            .updating($lineDrag) { value, state, _ in
                guard case .second(true, let drag) = value else { return }
                var moving = state ?? LineDrag(train: row.train, name: row.name)
                if let drag {
                    moving.location = drag.location
                    let index = target(drag.location.y)
                    if index != moving.row {
                        moving.row = index
                        moving.move = index.flatMap { rows[$0].line }.flatMap { session.rosterLineMove(of: row.train, to: $0) }
                    }
                }
                state = moving
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value, let index = target(drag.location.y), let line = rows[index].line,
                      session.rosterLineMove(of: row.train, to: line)?.drops == true else { return }
                session.moveTrain(row.train, toLine: line)
                result = session.message?.text
                rebuild += 1
            }
    }

    /// Where the dragged name is, and the row it would land on.
    @ViewBuilder
    private func lineDragMarks(rowHeight: CGFloat, width: CGFloat) -> some View {
        if let drag = lineDrag {
            ZStack(alignment: .topLeading) {
                if let row = drag.row {
                    let ok = drag.move?.drops == true
                    Rectangle()
                        .fill((ok ? Theme.primary : Theme.warning).opacity(0.18))
                        .overlay(Rectangle().strokeBorder(ok ? Palette.ink : Theme.warning, lineWidth: 2))
                        .frame(width: width, height: rowHeight)
                        .offset(y: Self.axisHeight + rowHeight * CGFloat(row))
                }
                // The name under the finger, see-through with an ink
                // outline: the art style has no shadows.
                Text(verbatim: drag.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: TrainRosterDrag.handleSize)
                    .background(Theme.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.ink, lineWidth: 2))
                    .fixedSize()
                    .position(drag.location)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A planned box held, then dragged sideways.
    private func boxDrag(_ roster: TrainRoster, rowHeight: CGFloat) -> some Gesture {
        let rows = roster.rows
        let perHour = Double(hourWidth)
        // The row and train of the planned box at `point`, if any.
        func box(_ point: CGPoint) -> (row: Int, train: TrainID)? {
            guard let index = TrainRosterDrag.row(atY: Double(point.y), axisHeight: Double(Self.axisHeight), rowHeight: Double(rowHeight), rows: rows.count)
            else { return nil }
            let second = roster.dayStart + Int64(Double(point.x) / perHour * Double(GameTime.secondsPerHour))
            return TrainRosterDrag.plannedCell(of: rows[index], at: second).map { _ in (index, rows[index].train) }
        }
        return LongPressGesture(minimumDuration: TrainRosterDrag.holdSeconds)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($shiftDrag) { value, state, _ in
                guard case .second(true, let drag?) = value else { return }
                if state == nil {
                    guard let found = box(drag.startLocation) else { return }
                    state = ShiftDrag(row: found.row, train: found.train)
                }
                guard var moving = state else { return }
                let seconds = TrainRosterDrag.shift(forWidth: Double(drag.translation.width), hourWidth: perHour)
                if seconds != moving.seconds || moving.shift == nil {
                    moving.seconds = seconds
                    moving.shift = TrainRosterDrag.shift(of: moving.train, by: seconds, in: session.world, roster: roster)
                }
                state = moving
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value, let train = box(drag.startLocation)?.train else { return }
                let seconds = TrainRosterDrag.shift(forWidth: Double(drag.translation.width), hourWidth: perHour)
                guard TrainRosterDrag.shift(of: train, by: seconds, in: session.world, roster: roster)?.drops == true else { return }
                session.shiftTrainTimetable(train, by: seconds)
                result = session.message?.text
                rebuild += 1
            }
    }

    /// The planned boxes of the row being dragged, where they would go:
    /// see-through, outlined in ink (no shadows in the art style).
    private func drawMoved(_ moving: ShiftDrag, in roster: TrainRoster, rowHeight: CGFloat, context: inout GraphicsContext) {
        guard roster.rows.indices.contains(moving.row) else { return }
        let ok = moving.shift?.drops == true
        let top = Self.axisHeight + rowHeight * CGFloat(moving.row) + Self.rowGap
        let dx = CGFloat(Double(moving.seconds) / Double(GameTime.secondsPerHour)) * hourWidth
        for cell in roster.rows[moving.row].cells where cell.state == .planned {
            let left = x(cell.start, in: roster) + dx
            let right = max(left + 4, x(cell.end, in: roster) + dx)
            let shape = Path(roundedRect: CGRect(x: left, y: top, width: right - left, height: rowHeight - 2 * Self.rowGap), cornerRadius: 4)
            context.fill(shape, with: .color((ok ? Theme.primary : Theme.warning).opacity(0.35)))
            context.stroke(shape, with: .color(ok ? Palette.ink : Theme.warning), lineWidth: 2)
        }
    }

    /// The same moves for VoiceOver and Switch Control: to each other
    /// line, and five minutes either way for a train of its own timetable.
    @ViewBuilder
    private func arrangeActions(_ row: TrainRoster.Row) -> some View {
        ForEach(session.world.lines.filter { $0.id != row.line }, id: \.id) { line in
            Button(language.text("Move to \(line.name)", "改派到\(line.name)")) {
                session.moveTrain(row.train, toLine: line.id)
                result = session.message?.text
                rebuild += 1
            }
        }
        if row.cells.contains(where: { $0.state == .planned }) {
            ForEach([-TrainRosterDrag.snap, TrainRosterDrag.snap], id: \.self) { seconds in
                Button(seconds < 0 ? language.text("5 min earlier", "提前 5 分") : language.text("5 min later", "延後 5 分")) {
                    session.shiftTrainTimetable(row.train, by: seconds)
                    result = session.message?.text
                    rebuild += 1
                }
            }
        }
    }

    private func spoken(_ row: TrainRoster.Row) -> String {
        var parts = [row.name, TrainRoster.shortMoney(row.revenue), language.text("in use \(row.utilisation)%", "使用率 \(row.utilisation)%")]
        if let note = row.dispatchText(in: language) { parts.append(note) }
        parts += row.cells.map { $0.spokenText(in: language) }
        return parts.joined(separator: "；")
    }
}
