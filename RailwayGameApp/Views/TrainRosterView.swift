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
///
/// Decision 777: looking and arranging are two pages, picked at the top as
/// the finance screen's are. The Arrange page lists beside the rows the
/// trains no line runs, each held and dragged onto a line's row to give it
/// that line; both pages draw the wait between two trips as a hatched
/// block with how long it is.
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
    /// Which page shows: the roster, or arranging it (decision 777).
    @State private var page: Page = .roster
    /// What the last drop did, said under the header.
    @State private var result: String?
    @GestureState private var lineDrag: LineDrag? = nil
    @GestureState private var shiftDrag: ShiftDrag? = nil
    @GestureState private var waitingDrag: LineDrag? = nil
    /// The edits made here that Undo can take back (L3-6, #1588's review:
    /// Undo here took back what was built before the roster opened).
    @State private var rosterEdits = 0
    /// The line under a dragged name, and the train of a held planned box,
    /// for the drag that started at `start` (L3-7, #1588's review: the
    /// roster is built again every second, and a row added above moved
    /// what lay under the finger).
    @State private var nameTarget: (start: CGPoint, line: LineID?)?
    @State private var heldBox: (start: CGPoint, train: TrainID?)?
    /// The line under a train dragged from the waiting column, for the
    /// drag that started at `start`, as `nameTarget` is.
    @State private var waitingTarget: (start: CGPoint, line: LineID?)?
    /// Where the table's panel is on the page, and the top of its rows
    /// (which scroll), for a train dragged in from the waiting column.
    @State private var tableFrame: CGRect = .zero
    @State private var rowsTop: CGFloat = 0
    /// The table's size, measured rather than read in a GeometryReader
    /// (CRASHSWEEP-3).
    @State private var tableSize: CGSize = .zero

    /// A train's name being dragged over the rows.
    private struct LineDrag {
        let train: TrainID
        let name: String
        var location: CGPoint = .zero
        var row: Int?
        var line: LineID?
        var move: TrainRosterDrag.LineMove?
    }

    /// The roster's two pages (decision 777).
    private enum Page: Hashable {
        case roster, arrange

        func title(in language: DisplayLanguage) -> String {
            switch self {
            case .roster: language.text("Roster", "運用表")
            case .arrange: language.text("Arrange", "編排")
            }
        }
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
    private static let axisHeight = TrainRosterChart.axisHeight
    private static let table = "trainRoster.table"
    nonisolated private static let pageSpace = "trainRoster.page"

    private var language: DisplayLanguage { session.language }
    private var compactWidth: Bool { horizontalSizeClass == .compact }
    /// Whether the trains can be dragged (decision 512): the Arrange page.
    private var arranging: Bool { page == .arrange }
    /// The waiting trains' column on the Arrange page.
    private var waitingWidth: CGFloat { compactWidth ? 132 : 188 }
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
                        HStack(alignment: .top, spacing: 0) {
                            if roster.rows.isEmpty {
                                Text(verbatim: language.text("No trains ran on this day.", "這一天沒有列車行駛。"))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                table(roster)
                            }
                            if arranging {
                                waitingColumn(roster)
                            }
                        }
                        legend
                    }
                    .coordinateSpace(.named(Self.pageSpace))
                    .overlay(alignment: .topLeading) { waitingDragMark }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // The owner's report on 133: held sideways, the names were
            // under the notch.
            .clearsTheNotch()
            .background(Theme.background)
            .navigationTitle(Text(verbatim: language.text("Train roster", "列車運用表")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Decision 777: looking and arranging, as the finance
                // screen's pages.
                ToolbarItem(placement: .principal) {
                    Picker(selection: $page) {
                        // Written out, not a ForEach: its rows' closure
                        // would be main-actor code SwiftUI keeps (ROSTERCRASH).
                        Text(verbatim: Page.roster.title(in: language)).tag(Page.roster)
                        Text(verbatim: Page.arrange.title(in: language)).tag(Page.arrange)
                    } label: {
                        Text(verbatim: language.text("Page", "分頁"))
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                    .accessibilityIdentifier("trainRoster.page")
                }
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
                            let before = session.undoCount
                            session.undo()
                            if session.undoCount < before { rosterEdits = max(0, rosterEdits - 1) }
                            result = session.message?.text
                            rebuild += 1
                        } label: {
                            Label {
                                Text(verbatim: language.text("Undo", "復原"))
                            } icon: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                        }
                        .disabled(!session.canUndo || min(rosterEdits, session.undoCount) == 0)
                        .accessibilityIdentifier("trainRoster.undo")
                    }
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
        // Decision 512: moving trains on the roster, today only.
        .onChange(of: page) {
            result = nil
            if arranging { day = .today }
        }
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
                    Text(verbatim: TrainRoster.Day.today.title(in: language)).tag(TrainRoster.Day.today)
                    Text(verbatim: TrainRoster.Day.yesterday.title(in: language)).tag(TrainRoster.Day.yesterday)
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
        } else if let drag = waitingDrag {
            if let move = drag.move {
                note(([move.text(in: language)] + move.notes).joined(separator: "；"), ok: move.drops)
            } else {
                note(language.text("Drop \(drag.name) on the row of the line it should run", "把 \(drag.name) 放到要跑的路線那一列"), ok: false)
            }
        } else if let drag = shiftDrag, let shift = drag.shift {
            let station = session.world.train(id: drag.train)?.timetable.first.map { session.world.station(id: $0.station)?.name ?? "?" } ?? "?"
            note(([shift.text(in: language)] + [shift.clashText(station: station, in: language)].compactMap(\.self)).joined(separator: "；"),
                 ok: shift.drops && shift.clash == nil)
        } else if arranging {
            Text(verbatim: result ?? language.text(
                "Hold a train's name, or a train on the right, and drag it onto a line's row to have it run there. Hold a planned box and drag it sideways to change its times.",
                "長按車名或右邊還沒排的列車，拖到路線的列上就派過去。長按預定的格子左右拖，改它的時刻。"
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
            TrainRosterWaitSwatch()
                .frame(width: 18, height: 12)
            Text(verbatim: language.text("Waiting", "空檔"))
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

    /// CRASHSWEEP-3: the table's size comes from `onGeometryChange`, whose
    /// measuring closure is sendable, not from a GeometryReader's closure,
    /// which SwiftUI calls again whenever the size changes (the rows'
    /// height does as arranging starts and ends) and its asynchronous
    /// renderer may call off the main thread (CRASH101). The rows wait for
    /// the first size, so the focused train is scrolled to at its height.
    private func table(_ roster: TrainRoster) -> some View {
        ZStack(alignment: .topLeading) {
            if tableSize != .zero {
                tableRows(roster, size: tableSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { tableSize = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.pageSpace)) } action: { tableFrame = $0 }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.panelBorder))
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func tableRows(_ roster: TrainRoster, size: CGSize) -> some View {
        // Decision 512: arranging keeps the full rows, so a name to
        // hold is at least 44 points high.
        let compact = !arranging
            && TrainRosterLayout.usesCompactRows(rows: roster.rows.count, height: Double(size.height - Self.axisHeight))
        let rowHeight = CGFloat(compact ? TrainRosterLayout.compactRowHeight : TrainRosterLayout.fullRowHeight)
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: Self.axisHeight)
                        // Built here, in `body`, not in a closure the
                        // ForEach keeps: arranging turns short rows into
                        // full ones, and SwiftUI may build the new rows off
                        // the main thread (ROSTERCRASH, as CRASH101).
                        TrainRosterBuiltRows(Array(roster.rows.enumerated()), id: \.element.id) { index, row in
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
                        .frame(width: max(0, size.width - nameWidth))
                }
                .frame(width: size.width, alignment: .leading)
                .coordinateSpace(.named(Self.table))
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.pageSpace)).minY } action: { rowsTop = $0 }
                .overlay(alignment: .topLeading) { lineDragMarks(rowHeight: rowHeight, width: size.width) }
            }
            .onAppear {
                if let focus { reader.scrollTo(focus, anchor: .center) }
            }
        }
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
                    // Decision 523, 續二: the first that fits the column.
                    let texts = row.revenueTexts(in: language)
                    ViewThatFits(in: .horizontal) {
                        revenueText(texts[0])
                        revenueText(texts[1])
                        revenueText(texts[2])
                    }
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
            // How much of the day it ran, as a short upright bar. A
            // sendable closure, not main-actor code (CRASHSWEEP-2): SwiftUI
            // reads the bar again when the row's height changes, which its
            // asynchronous renderer may do off the main thread (CRASH101).
            let utilisation = CGFloat(row.utilisation)
            GeometryReader { @Sendable bar in
                TrainRosterUtilisationBar(height: bar.size.height, utilisation: utilisation)
            }
            .frame(width: 4)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 8)
    }

    /// One of a row's revenue lines (``TrainRoster/Row/revenueTexts(in:)``),
    /// at its own width so `ViewThatFits` can tell whether it fits.
    private func revenueText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func hours(_ roster: TrainRoster, rowHeight: CGFloat, compact: Bool) -> some View {
        let width = hourWidth * 24
        let height = Self.axisHeight + rowHeight * CGFloat(roster.rows.count)
        let nowX = x(roster.now, in: roster)
        // The drawing is a sendable value's, not this view's main-actor
        // code: the rows' height, and so the canvas, changes as arranging
        // starts and ends (ROSTERCRASH, as CRASH101).
        let chart = TrainRosterChart(
            roster: roster, rowHeight: rowHeight, compact: compact, language: language, hourWidth: hourWidth,
            moved: shiftDrag.map { TrainRosterChart.Moved(row: $0.row, seconds: $0.seconds, drops: $0.shift?.drops == true) }
        )
        return ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    Canvas { @Sendable context, _ in
                        chart.draw(in: &context)
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
        TrainRosterChart.x(time, dayStart: roster.dayStart, hourWidth: hourWidth)
    }

    private func firstTripX(_ roster: TrainRoster) -> CGFloat {
        let first = roster.rows.compactMap { $0.cells.first?.start }.min() ?? roster.dayStart
        return max(0, x(first, in: roster))
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
                    let line = index.flatMap { rows[$0].line }
                    if index != moving.row || line != moving.line {
                        moving.row = index
                        moving.line = line
                        moving.move = line.flatMap { session.rosterLineMove(of: row.train, to: $0) }
                    }
                }
                state = moving
            }
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                let line = target(drag.location.y).flatMap { rows[$0].line }
                if nameTarget?.start != drag.startLocation || nameTarget?.line != line {
                    nameTarget = (drag.startLocation, line)
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value, let held = nameTarget, held.start == drag.startLocation,
                      let line = held.line, session.rosterLineMove(of: row.train, to: line)?.drops == true else { return }
                rosterEdit { session.moveTrain(row.train, toLine: line) }
            }
    }

    /// Where the dragged name is, and the row it would land on.
    @ViewBuilder
    private func lineDragMarks(rowHeight: CGFloat, width: CGFloat) -> some View {
        if let drag = lineDrag ?? waitingDrag {
            ZStack(alignment: .topLeading) {
                if let row = drag.row {
                    let ok = drag.move?.drops == true
                    Rectangle()
                        .fill((ok ? Theme.primary : Theme.warning).opacity(0.18))
                        .overlay(Rectangle().strokeBorder(ok ? Palette.ink : Theme.warning, lineWidth: 2))
                        .frame(width: width, height: rowHeight)
                        .offset(y: Self.axisHeight + rowHeight * CGFloat(row))
                }
                // The name under the finger; one from the waiting column
                // is drawn over the whole page instead.
                if lineDrag != nil {
                    draggedName(drag.name)
                        .position(drag.location)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The name under the finger, see-through with an ink outline: the
    /// art style has no shadows.
    private func draggedName(_ name: String) -> some View {
        Text(verbatim: name)
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: TrainRosterDrag.handleSize)
            .background(Theme.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.ink, lineWidth: 2))
            .fixedSize()
    }

    // MARK: Waiting trains (decision 777)

    /// Beside the rows on the Arrange page: the trains no line runs.
    private func waitingColumn(_ roster: TrainRoster) -> some View {
        let rows = roster.only(line: allLines ? nil : line).rows
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: language.text("Not on a line · \(roster.waiting.count)", "還沒排的列車 · \(roster.waiting.count)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if roster.waiting.isEmpty {
                Text(verbatim: language.text("Every train runs on a line or a timetable of its own.", "每列車都排上路線或自己的時刻了。"))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.vertical) {
                    // A plain stack: a lazy one builds its cells as it
                    // lays them out, off the main thread (CRASHSWEEP-2).
                    VStack(spacing: 6) {
                        TrainRosterBuiltRows(roster.waiting, id: \.id) { waiting in
                            waitingCard(waiting, rows: rows)
                        }
                    }
                }
            }
        }
        .frame(width: waitingWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.trailing, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trainRoster.waiting")
    }

    private func waitingCard(_ waiting: TrainRoster.Waiting, rows: [TrainRoster.Row]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: waiting.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(verbatim: waiting.detailText(in: language))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: TrainRosterDrag.handleSize)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.panelBorder))
        .opacity(waitingDrag?.train == waiting.train ? 0.4 : 1)
        .contentShape(Rectangle())
        .gesture(waitingDragGesture(waiting, rows: rows))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: waiting.name + "，" + waiting.detailText(in: language)))
        .accessibilityActions {
            TrainRosterBuiltRows(session.world.lines, id: \.id) { line in
                Button(language.text("Run on \(line.name)", "派到\(line.name)")) {
                    rosterEdit { session.moveTrain(waiting.train, toLine: line.id) }
                }
            }
        }
        .accessibilityIdentifier("trainRoster.waiting.\(waiting.train.rawValue)")
    }

    /// A waiting train held, then dragged onto a line's row. The finger is
    /// followed on the page; the row is found from where the rows have
    /// scrolled to.
    private func waitingDragGesture(_ waiting: TrainRoster.Waiting, rows: [TrainRoster.Row]) -> some Gesture {
        let frame = tableFrame
        let top = rowsTop
        let rowHeight = Double(TrainRosterLayout.fullRowHeight)
        func target(_ point: CGPoint) -> Int? {
            guard frame.contains(point) else { return nil }
            return TrainRosterDrag.row(atY: Double(point.y - top), axisHeight: Double(Self.axisHeight), rowHeight: rowHeight, rows: rows.count)
        }
        return LongPressGesture(minimumDuration: TrainRosterDrag.holdSeconds)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.pageSpace)))
            .updating($waitingDrag) { value, state, _ in
                guard case .second(true, let drag) = value else { return }
                var moving = state ?? LineDrag(train: waiting.train, name: waiting.name)
                if let drag {
                    moving.location = drag.location
                    let index = target(drag.location)
                    let line = index.flatMap { rows[$0].line }
                    if index != moving.row || line != moving.line {
                        moving.row = index
                        moving.line = line
                        moving.move = line.flatMap { session.rosterLineMove(of: waiting.train, to: $0) }
                    }
                }
                state = moving
            }
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                let line = target(drag.location).flatMap { rows[$0].line }
                if waitingTarget?.start != drag.startLocation || waitingTarget?.line != line {
                    waitingTarget = (drag.startLocation, line)
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value, let held = waitingTarget, held.start == drag.startLocation,
                      let line = held.line, session.rosterLineMove(of: waiting.train, to: line)?.drops == true else { return }
                rosterEdit { session.moveTrain(waiting.train, toLine: line) }
            }
    }

    /// The waiting train under the finger, over the whole page.
    @ViewBuilder
    private var waitingDragMark: some View {
        if let drag = waitingDrag {
            draggedName(drag.name)
                .position(drag.location)
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
            .onChanged { value in
                guard case .second(true, let drag?) = value, heldBox?.start != drag.startLocation else { return }
                heldBox = (drag.startLocation, box(drag.startLocation)?.train)
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value, let held = heldBox, held.start == drag.startLocation,
                      let train = held.train else { return }
                let seconds = TrainRosterDrag.shift(forWidth: Double(drag.translation.width), hourWidth: perHour)
                guard TrainRosterDrag.shift(of: train, by: seconds, in: session.world, roster: roster)?.drops == true else { return }
                rosterEdit { session.shiftTrainTimetable(train, by: seconds) }
            }
    }

    /// The same moves for VoiceOver and Switch Control: to each other
    /// line, and five minutes either way for a train of its own timetable.
    @ViewBuilder
    private func arrangeActions(_ row: TrainRoster.Row) -> some View {
        TrainRosterBuiltRows(session.world.lines.filter { $0.id != row.line }, id: \.id) { line in
            Button(language.text("Move to \(line.name)", "改派到\(line.name)")) {
                rosterEdit { session.moveTrain(row.train, toLine: line.id) }
            }
        }
        if row.cells.contains(where: { $0.state == .planned }) {
            Button(language.text("5 min earlier", "提前 5 分")) {
                rosterEdit { session.shiftTrainTimetable(row.train, by: -TrainRosterDrag.snap) }
            }
            Button(language.text("5 min later", "延後 5 分")) {
                rosterEdit { session.shiftTrainTimetable(row.train, by: TrainRosterDrag.snap) }
            }
        }
    }

    /// Makes an edit of the roster's, counted for its Undo (L3-6).
    private func rosterEdit(_ edit: () -> Void) {
        let before = session.undoCount
        edit()
        if session.undoCount > before { rosterEdits += 1 }
        result = session.message?.text
        rebuild += 1
    }

    private func spoken(_ row: TrainRoster.Row) -> String {
        var parts = [row.name, TrainRoster.shortMoney(row.revenue, in: language), language.text("in use \(row.utilisation)%", "使用率 \(row.utilisation)%")]
        if let note = row.dispatchText(in: language) { parts.append(note) }
        parts += row.cells.map { $0.spokenText(in: language) }
        return parts.joined(separator: "；")
    }
}

/// What the roster's hours draw (decision 223, layout C; the waits of
/// decision 777): a sendable value, so the canvas's closure is not
/// main-actor code. SwiftUI draws the canvas again when the rows' height
/// changes, as it does when arranging starts and ends, and may do so off
/// the main thread, where main-actor code stops the app (ROSTERCRASH, the
/// kind of CRASH101).
private struct TrainRosterChart: Sendable {
    /// The planned boxes of a row dragged sideways.
    struct Moved: Sendable {
        let row: Int
        let seconds: Int64
        /// Whether letting go would move them.
        let drops: Bool
    }

    static let axisHeight: CGFloat = 24
    static let rowGap: CGFloat = 4

    let roster: TrainRoster
    let rowHeight: CGFloat
    let compact: Bool
    let language: DisplayLanguage
    /// Points an hour takes across.
    let hourWidth: CGFloat
    let moved: Moved?

    static func x(_ time: Int64, dayStart: Int64, hourWidth: CGFloat) -> CGFloat {
        CGFloat(Double(time - dayStart) / Double(GameTime.secondsPerHour)) * hourWidth
    }

    private func x(_ time: Int64) -> CGFloat {
        Self.x(time, dayStart: roster.dayStart, hourWidth: hourWidth)
    }

    func draw(in context: inout GraphicsContext) {
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

        // The trips, and the waits between them (decision 777).
        for (index, row) in roster.rows.enumerated() {
            let top = Self.axisHeight + rowHeight * CGFloat(index) + Self.rowGap
            let boxHeight = rowHeight - 2 * Self.rowGap
            for gap in row.gaps {
                draw(gap, in: CGRect(x: x(gap.start), y: top, width: x(gap.end) - x(gap.start), height: boxHeight),
                     context: &context)
            }
            for cell in row.cells {
                let left = x(cell.start)
                let right = max(left + 4, x(cell.end))
                let box = CGRect(x: left, y: top, width: right - left, height: boxHeight)
                draw(cell, in: box, context: &context)
            }
        }
        if let moved { draw(moved, context: &context) }

        // Now, with its time on a tag.
        if roster.day == .today {
            let nowX = x(roster.now)
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

    /// A wait between two trips: a hatched block, a little narrower than
    /// the wait so the trips beside it stay apart, with how long it is
    /// where it fits (decision 777).
    private func draw(_ gap: TrainRoster.Gap, in span: CGRect, context: inout GraphicsContext) {
        let block = span.insetBy(dx: 2, dy: 0)
        guard block.width >= 4 else { return }
        TrainRosterHatch.draw(in: block, context: &context, colors: TrainRosterHatch.Colors())
        let label = context.resolve(Text(verbatim: gap.text(in: language))
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.textPrimary))
        let size = label.measure(in: CGSize(width: block.width, height: block.height))
        let tag = CGRect(x: block.midX - size.width / 2 - 5, y: block.midY - size.height / 2 - 2,
                         width: size.width + 10, height: size.height + 4)
        guard tag.width + 4 <= block.width, tag.height <= block.height else { return }
        let capsule = Path(roundedRect: tag, cornerRadius: tag.height / 2)
        context.fill(capsule, with: .color(Theme.panel))
        context.stroke(capsule, with: .color(Theme.panelBorder), lineWidth: 1)
        context.draw(label, at: CGPoint(x: tag.midX, y: tag.midY), anchor: .center)
    }

    private func draw(_ cell: TrainRoster.Cell, in box: CGRect, context: inout GraphicsContext) {
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
            let line = cell.isLate ? (cell.lateText ?? "") : cell.state == .planned ? "" : TrainRoster.shortMoney(cell.fare, in: language)
            layer.draw(Text(verbatim: line).font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(color),
                       at: CGPoint(x: box.minX + 4, y: box.midY), anchor: .leading)
        } else {
            layer.draw(Text(verbatim: cell.routeText + late).font(.caption2.weight(.bold)).foregroundStyle(color),
                       at: CGPoint(x: box.minX + 4, y: box.minY + 2), anchor: .topLeading)
            layer.draw(Text(verbatim: cell.detailText(in: language)).font(.caption2.monospacedDigit()).foregroundStyle(color),
                       at: CGPoint(x: box.minX + 4, y: box.maxY - 2), anchor: .bottomLeading)
        }
    }

    /// The planned boxes of the row being dragged, where they would go:
    /// see-through, outlined in ink (no shadows in the art style).
    private func draw(_ moved: Moved, context: inout GraphicsContext) {
        guard roster.rows.indices.contains(moved.row) else { return }
        let top = Self.axisHeight + rowHeight * CGFloat(moved.row) + Self.rowGap
        let dx = CGFloat(Double(moved.seconds) / Double(GameTime.secondsPerHour)) * hourWidth
        for cell in roster.rows[moved.row].cells where cell.state == .planned {
            let left = x(cell.start) + dx
            let right = max(left + 4, x(cell.end) + dx)
            let shape = Path(roundedRect: CGRect(x: left, y: top, width: right - left, height: rowHeight - 2 * Self.rowGap), cornerRadius: 4)
            context.fill(shape, with: .color((moved.drops ? Theme.primary : Theme.warning).opacity(0.35)))
            context.stroke(shape, with: .color(moved.drops ? Palette.ink : Theme.warning), lineWidth: 2)
        }
    }
}

/// Rows built at once, where the view's `body` runs, for a `ForEach` to
/// hand out. A `ForEach`'s own closure is kept and called when SwiftUI
/// needs a row, which its asynchronous renderer may do off the main
/// thread; written in a view it is main-actor code, and stops the app
/// there (CRASH101). Here the kept closure only returns what was built.
private struct TrainRosterBuiltRows<ID: Hashable>: View {
    private let rows: [TrainRosterBuiltRow<ID>]

    init<Data: Sequence, Content: View>(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: (Data.Element) -> Content) {
        rows = data.map { TrainRosterBuiltRow(id: $0[keyPath: id], view: AnyView(content($0))) }
    }

    var body: some View {
        ForEach(rows) { @Sendable row in row.view }
    }
}

private struct TrainRosterBuiltRow<ID: Hashable>: Identifiable {
    let id: ID
    let view: AnyView
}

/// A roster row's day of running (``TrainRoster/Row/utilisation``, in
/// percent) as an upright bar `height` points high, filled from the foot.
private struct TrainRosterUtilisationBar: View {
    let height: CGFloat
    let utilisation: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.chip
            Theme.primary
                .frame(height: height * utilisation / 100)
        }
    }
}

/// The legend's swatch of a wait (decision 777), a view of its own with a
/// sendable closure: the legend stands in a `ViewThatFits`, measured off
/// the main thread (CRASH101).
private struct TrainRosterWaitSwatch: View {
    var body: some View {
        let colors = TrainRosterHatch.Colors()
        Canvas { @Sendable context, size in
            TrainRosterHatch.draw(in: CGRect(origin: .zero, size: size), context: &context, colors: colors)
        }
        .accessibilityHidden(true)
    }
}

/// A wait between two trips (decision 777): diagonal stripes on the faint
/// chip, in a rounded box.
enum TrainRosterHatch {
    struct Colors: Sendable {
        var fill = Theme.chip
        var stripe = Theme.textSecondary.opacity(0.45)
        var border = Theme.panelBorder
    }

    static func draw(in box: CGRect, context: inout GraphicsContext, colors: Colors) {
        let shape = Path(roundedRect: box, cornerRadius: 4)
        context.fill(shape, with: .color(colors.fill))
        var layer = context
        layer.clip(to: shape)
        var stripes = Path()
        var start = box.minX - box.height
        while start < box.maxX {
            stripes.move(to: CGPoint(x: start, y: box.maxY))
            stripes.addLine(to: CGPoint(x: start + box.height, y: box.minY))
            start += 6
        }
        layer.stroke(stripes, with: .color(colors.stripe), lineWidth: 1.5)
        context.stroke(shape, with: .color(colors.border), lineWidth: 1)
    }
}
