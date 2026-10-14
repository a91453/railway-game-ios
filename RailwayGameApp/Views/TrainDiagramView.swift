import GameCore
import GamePresentation
import SwiftUI

/// The train diagram (運行圖, ARCHITECTURE decision 206) of one line, over
/// the whole screen: time across, the line's stations down, each trip's
/// planned line in the line's colour, where the trains actually were in
/// navy (the day so far from the trip log, decision 223, and since it
/// opened, between the stations too), a late train's expected line dashed in the warning
/// colour with how late it is, and a mark where two trips meet (◆) or one
/// overtakes the other (▲). Pinch to zoom, drag to move; "Now" follows the
/// clock again.
///
/// View only. ``TrainDiagram`` works everything out from the world (Linux
/// tests); this view only draws it. It is built again twice a second, away
/// from the main thread, never on every tick.
struct TrainDiagramView: View {
    let session: GameSession
    let line: LineID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var diagram: TrainDiagram?
    @State private var history = TrainDiagramHistory()
    @State private var viewport: TrainDiagramViewport?
    @State private var singleTrack: (key: SectionsKey, sections: [Bool])?
    /// The viewport when the pinch or the drag in progress began.
    @State private var gestureStart: TrainDiagramViewport?
    @State private var lastDrag: CGSize = .zero

    /// How often the diagram is built again, in real seconds.
    private static let refresh: Duration = .milliseconds(500)

    private var language: DisplayLanguage { session.language }

    var body: some View {
        NavigationStack {
            Group {
                if let diagram, let viewport {
                    VStack(spacing: 0) {
                        summary(diagram)
                        chart(diagram, viewport: viewport)
                        legend
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.background)
            .navigationTitle(Text(verbatim: language.text("Train diagram", "運行圖") + (diagram.map { " · " + $0.lineName } ?? "")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(verbatim: language.text("Close", "關閉"))
                    }
                    .accessibilityIdentifier("trainDiagram.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        guard let diagram else { return }
                        viewport?.follow(in: diagram)
                    } label: {
                        Label {
                            Text(verbatim: language.text("Now", "現在"))
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                    .disabled(viewport?.follows ?? true)
                    .accessibilityIdentifier("trainDiagram.now")
                }
            }
        }
        .task(id: line) {
            history = TrainDiagramHistory()
            diagram = nil
            viewport = nil
            while !Task.isCancelled {
                await rebuild()
                try? await Task.sleep(for: Self.refresh)
            }
        }
        .accessibilityIdentifier("trainDiagram")
    }

    /// What the single-track flags depend on: the line's stops and the track.
    private struct SectionsKey: Equatable {
        var stops: [StationID]
        var isRing: Bool
        var edges: Int
        var nodes: Int
        var platforms: Int
    }

    private func rebuild() async {
        let world = session.world
        guard let stops = world.line(id: line) else {
            diagram = nil
            return
        }
        let key = SectionsKey(stops: stops.stops, isRing: stops.isRing, edges: world.network.edges.count,
                              nodes: world.network.nodes.count, platforms: world.stations.reduce(0) { $0 + world.trackPlatforms(of: $1.id).count })
        let known = singleTrack?.key == key ? singleTrack?.sections : nil
        let remembered = history.trips
        let line = line
        let (built, sections) = await Task.detached(priority: .userInitiated) {
            let sections = known ?? TrainDiagram.singleTrackSections(of: line, in: world)
            return (TrainDiagram(world: world, line: line, singleTrack: sections, remembered: remembered), sections)
        }.value
        guard !Task.isCancelled else { return }
        singleTrack = (key, sections)
        guard let built else {
            diagram = nil
            return
        }
        history.record(built)
        diagram = built
        var view = viewport ?? TrainDiagramViewport(now: built.now)
        view.update(to: built)
        viewport = view
    }

    // MARK: Summary and legend

    private func summary(_ diagram: TrainDiagram) -> some View {
        let late = diagram.lateTrains
        let meets = diagram.marks.filter { $0.kind == .meet }.count
        let overtakes = diagram.marks.filter { $0.kind == .overtake }.count
        return HStack(spacing: 12) {
            if let first = late.first {
                Label {
                    Text(verbatim: language.text("\(late.count) late, up to \(first.lateMinutes) min",
                                                 "誤點 \(late.count) 列，最多 \(first.lateMinutes) 分"))
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                }
                .foregroundStyle(Theme.warning)
            } else {
                Label {
                    Text(verbatim: language.text("All on time", "全部準點"))
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
                .foregroundStyle(Theme.success)
            }
            Spacer(minLength: 8)
            Text(verbatim: language.text("\(meets) meets · \(overtakes) overtakes", "交會 \(meets) · 越行 \(overtakes)"))
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trainDiagram.summary")
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
        legendLine(language.text("Planned", "計畫"), style: StrokeStyle(lineWidth: 3), color: diagram.map(lineColor) ?? Theme.primary)
        legendLine(language.text("Actual", "實際"), style: StrokeStyle(lineWidth: 1.5), color: Theme.textPrimary)
        legendLine(language.text("Expected if late", "誤點後預估"), style: StrokeStyle(lineWidth: 2, dash: [5, 3]), color: Theme.warning)
        Text(verbatim: "◆ " + language.text("Meet", "交會") + "  ▲ " + language.text("Overtake", "越行"))
    }

    private func legendLine(_ text: String, style: StrokeStyle, color: Color) -> some View {
        HStack(spacing: 4) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 6))
                path.addLine(to: CGPoint(x: 20, y: 6))
            }
            .stroke(color, style: style)
            .frame(width: 20, height: 12)
            Text(verbatim: text)
        }
    }

    private func lineColor(_ diagram: TrainDiagram) -> Color {
        Palette.lineColor(diagram.line, custom: diagram.color)
    }

    // MARK: Chart

    private var gutter: CGFloat { horizontalSizeClass == .compact ? 64 : 96 }
    private static let header: CGFloat = 22
    private static let inset: CGFloat = 10

    private func chart(_ diagram: TrainDiagram, viewport: TrainDiagramViewport) -> some View {
        GeometryReader { proxy in
            let plot = CGRect(x: gutter, y: Self.header + Self.inset,
                              width: max(1, proxy.size.width - gutter - Self.inset),
                              height: max(1, proxy.size.height - Self.header - 2 * Self.inset))
            Canvas { context, _ in
                draw(diagram, viewport: viewport, in: plot, context: &context)
            }
            .contentShape(Rectangle())
            .gesture(pinch(plot: plot).simultaneously(with: drag(plot: plot)))
            .accessibilityLabel(Text(verbatim: accessibilityText(diagram)))
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.panelBorder))
        .padding(.horizontal, 8)
    }

    private func pinch(plot: CGRect) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let diagram else { return }
                let start = gestureStart ?? viewport
                gestureStart = start
                guard var view = start else { return }
                let anchorX = Double((value.startLocation.x - plot.minX) / plot.width)
                let anchorY = Double((value.startLocation.y - plot.minY) / plot.height)
                view.zoom(by: value.magnification, verticalScale: value.magnification,
                          anchorX: min(max(anchorX, 0), 1), anchorY: min(max(anchorY, 0), 1), in: diagram)
                viewport = view
            }
            .onEnded { _ in gestureStart = nil }
    }

    private func drag(plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard let diagram, var view = viewport else { return }
                let dx = value.translation.width - lastDrag.width, dy = value.translation.height - lastDrag.height
                lastDrag = value.translation
                view.pan(dx: Double(dx / plot.width), dy: Double(dy / plot.height), in: diagram)
                viewport = view
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private func draw(_ diagram: TrainDiagram, viewport: TrainDiagramViewport, in plot: CGRect, context: inout GraphicsContext) {
        func x(_ time: Int64) -> CGFloat { plot.minX + CGFloat(viewport.x(of: time)) * plot.width }
        func y(_ place: Double) -> CGFloat { plot.minY + CGFloat(viewport.y(of: diagram.offset(at: place))) * plot.height }
        func point(_ p: TrainDiagram.Point) -> CGPoint { CGPoint(x: x(p.time), y: y(p.place)) }
        func path(_ points: [TrainDiagram.Point]) -> Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: point(first))
            for p in points.dropFirst() { path.addLine(to: point(p)) }
            return path
        }
        let color = lineColor(diagram)
        let full = CGRect(x: 0, y: 0, width: plot.maxX + Self.inset, height: plot.maxY + Self.inset)

        // The stations: a rule each, names in the gutter; single track
        // drawn as a heavier bar beside the names (signal stations in the
        // warm yellow of the player's own works).
        for (row, station) in diagram.stations.enumerated() {
            let rowY = y(Double(row))
            guard rowY >= plot.minY - 1, rowY <= plot.maxY + 1 else { continue }
            var rule = Path()
            rule.move(to: CGPoint(x: plot.minX, y: rowY))
            rule.addLine(to: CGPoint(x: plot.maxX, y: rowY))
            context.stroke(rule, with: .color(Theme.panelBorder), lineWidth: station.isSignalStation ? 1.5 : 1)
            let name = Text(verbatim: station.name)
                .font(.caption2.weight(station.isSignalStation ? .regular : .semibold))
                .foregroundStyle(station.isSignalStation ? Theme.textSecondary : Theme.textPrimary)
            context.draw(name, at: CGPoint(x: plot.minX - 12, y: rowY), anchor: .trailing)
        }
        for (row, single) in diagram.singleTrack.enumerated() {
            var bar = Path()
            bar.move(to: CGPoint(x: plot.minX - 5, y: y(Double(row))))
            bar.addLine(to: CGPoint(x: plot.minX - 5, y: y(Double(row + 1))))
            context.stroke(bar, with: .color(single ? Theme.textPrimary : Theme.panelBorder), lineWidth: single ? 3 : 1.5)
        }

        // Time: a label and a faint rule on each round step.
        for tick in viewport.ticks(count: horizontalSizeClass == .compact ? 4 : 8) {
            let tickX = x(tick)
            var rule = Path()
            rule.move(to: CGPoint(x: tickX, y: plot.minY))
            rule.addLine(to: CGPoint(x: tickX, y: plot.maxY))
            context.stroke(rule, with: .color(Theme.chip), lineWidth: 1)
            context.draw(Text(verbatim: GameTime(seconds: tick).clockText).font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary),
                         at: CGPoint(x: tickX, y: Self.header / 2 + 2), anchor: .center)
        }

        var plotContext = context
        plotContext.clip(to: Path(CGRect(x: plot.minX, y: 0, width: plot.width + Self.inset, height: full.height)))

        // Now.
        var nowLine = Path()
        nowLine.move(to: CGPoint(x: x(diagram.now), y: plot.minY - Self.inset))
        nowLine.addLine(to: CGPoint(x: x(diagram.now), y: plot.maxY + Self.inset))
        plotContext.stroke(nowLine, with: .color(Theme.primary), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))

        // The planned trips, then where the trains actually were.
        for trip in diagram.trips {
            let style: StrokeStyle
            if trip.train == nil {
                style = StrokeStyle(lineWidth: 2, dash: [2, 3])
            } else if trip.isEmptyRun {
                style = StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            } else {
                style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            }
            for piece in trip.lines {
                plotContext.stroke(path(piece), with: .color(color), style: style)
            }
        }
        // Decision 223: the trips the trains actually ran, from the trip
        // log, so the day so far is there as soon as the diagram opens.
        for trip in diagram.actual {
            let style = trip.isEmptyRun
                ? StrokeStyle(lineWidth: 1, dash: [6, 4])
                : StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            for piece in trip.lines where piece.count > 1 {
                plotContext.stroke(path(piece), with: .color(Theme.textPrimary), style: style)
            }
        }
        for pieces in history.trails.values {
            for piece in pieces where piece.count > 1 {
                plotContext.stroke(path(piece), with: .color(Theme.textPrimary), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }

        // Late trains: the rest of the trip as expected.
        for train in diagram.running where train.isLate {
            plotContext.stroke(path(train.expected), with: .color(Theme.warning), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
        }

        // Meets and overtakes.
        for mark in diagram.marks {
            let at = CGPoint(x: x(mark.time), y: y(mark.place))
            guard plot.insetBy(dx: -8, dy: -8).contains(at) else { continue }
            var shape = Path()
            switch mark.kind {
            case .meet:
                shape.move(to: CGPoint(x: at.x, y: at.y - 6))
                shape.addLine(to: CGPoint(x: at.x + 6, y: at.y))
                shape.addLine(to: CGPoint(x: at.x, y: at.y + 6))
                shape.addLine(to: CGPoint(x: at.x - 6, y: at.y))
            case .overtake:
                shape.move(to: CGPoint(x: at.x, y: at.y - 6.5))
                shape.addLine(to: CGPoint(x: at.x + 6, y: at.y + 4.5))
                shape.addLine(to: CGPoint(x: at.x - 6, y: at.y + 4.5))
            }
            shape.closeSubpath()
            plotContext.fill(shape, with: .color(Theme.accent))
            plotContext.stroke(shape, with: .color(Theme.onAccent), lineWidth: 1.5)
        }

        // The trains now, and how late.
        for train in diagram.running {
            let at = point(train.now)
            let dot = Path(ellipseIn: CGRect(x: at.x - 5, y: at.y - 5, width: 10, height: 10))
            plotContext.fill(dot, with: .color(color))
            plotContext.stroke(dot, with: .color(Theme.textPrimary), lineWidth: 2)
            var label = train.name
            if let late = train.lateText(in: language) { label += " " + late }
            plotContext.draw(Text(verbatim: label).font(.caption2.weight(.semibold))
                                .foregroundStyle(train.isVeryLate ? Theme.error : train.isLate ? Theme.warning : Theme.textPrimary),
                             at: CGPoint(x: at.x + 8, y: at.y - 9), anchor: .leading)
        }
    }

    private func accessibilityText(_ diagram: TrainDiagram) -> String {
        var parts = [language.text("Train diagram of \(diagram.lineName)", "\(diagram.lineName) 的運行圖")]
        for train in diagram.lateTrains {
            parts.append(train.name + " " + (train.lateText(in: language) ?? ""))
        }
        for mark in diagram.marks.prefix(5) {
            let station = diagram.stations.first { $0.id == mark.station }?.name ?? ""
            parts.append("\(GameTime(seconds: mark.time).clockText) \(station) \(mark.kindText(in: language)) \(mark.names.joined(separator: "、"))")
        }
        return parts.joined(separator: "；")
    }
}
