import GameCore
import GamePresentation
import SwiftUI

/// Immutable, derived edge geometry. Kept by MapView, never by GameCore
/// or the save format, so panning and train ticks do not resample curves.
struct MapEdgeDrawing: Equatable, Sendable {
    let edge: TrackEdge
    let geometry: TrackGeometry
    let bounds: WorldRegion

    init?(edge: TrackEdge, world: GameWorld) {
        guard let geometry = world.trackGeometry(of: edge.id),
              let bounds = WorldRegion(enclosing: geometry.points) else { return nil }
        self.edge = edge
        self.geometry = geometry
        self.bounds = bounds
    }
}

/// Viewport drawing through MapProjection, also for a future rotated or
/// tilted map. Full detail has ballast, platforms, nodes and station names;
/// overview keeps thin routes and readable station/train marks.
enum MapArt {
    static func drawMap(
        _ world: GameWorld,
        selectedTrainID: TrainID?,
        selectedStationID: StationID? = nil,
        network overlay: NetworkOverlay? = nil,
        traffic: TrafficOverlay = TrafficOverlay(),
        projection: some MapProjection,
        edges: [TrackEdgeID: MapEdgeDrawing],
        drawsLand: Bool = true,
        in context: GraphicsContext
    ) {
        let referenceSize = projection.referenceSize
        let detail = projection.detail
        let region = drawingRegion(projection)
        let bounds = WorldRegion(bounds: world.bounds)
        let land = polygon([
            screenPoint(bounds.minX, bounds.minY, projection),
            screenPoint(bounds.maxX, bounds.minY, projection),
            screenPoint(bounds.maxX, bounds.maxY, projection),
            screenPoint(bounds.minX, bounds.maxY, projection)
        ])
        // Over Apple's map (Stage E2) only the map's edge is drawn.
        if drawsLand {
            context.fill(land, with: .color(Palette.land))
        }
        context.stroke(land, with: .color(Palette.mapEdge), lineWidth: 1)

        drawNetwork(world, projection: projection, cached: edges, in: context)
        drawAuthorities(traffic, selectedTrainID: selectedTrainID, projection: projection, in: context)
        for station in world.stations {
            drawPointStation(station, isSelected: station.id == selectedStationID, projection: projection, in: context)
        }
        if let overlay { drawNetworkOverlay(overlay, projection: projection, in: context) }
        drawWaits(traffic, projection: projection, in: context)

        for train in world.trains {
            guard let position = train.position, let location = world.location(of: position) else { continue }
            // A tail may still be visible when its head is offscreen. Only
            // query its body if it could reach the view from the head.
            if detail == .full,
               region.expanded(by: Double(train.length)).contains(location.position) {
                let body = polyline(world.bodyPath(of: train.id), projection: projection)
                context.stroke(body, with: .color(Palette.train.opacity(0.75)), style: StrokeStyle(lineWidth: max(3, referenceSize * 0.3), lineCap: .round, lineJoin: .round))
            }
            if region.contains(location.position) {
                drawTrain(at: location, isSelected: train.id == selectedTrainID, projection: projection, in: context)
            }
        }
        drawWaitMarks(traffic, projection: projection, in: context)
    }

    // MARK: - Traffic control (Stage V4e, decision 64)

    /// How much of its colour an authority keeps when its train is not the
    /// selected one: the `Railway/` site's `FOLLOW_DIM`.
    private static let followDim = 0.62

    /// The width of an authority's line; its casing is wider by the site's
    /// 8.5 : 4.4, under the train's body and over the ballast.
    private static func authorityWidth(_ projection: some MapProjection) -> Double {
        max(2.5, projection.referenceSize * 0.2)
    }

    /// Each train's movement authority, drawn as the `Railway/` site draws a
    /// followed train's route (index.html: an 8.5 casing in `followCase`,
    /// then a 4.4 line in the train's colour dimmed by `FOLLOW_DIM`), over
    /// the track and under stations and trains. The selected train's is
    /// drawn last and undimmed.
    private static func drawAuthorities(_ traffic: TrafficOverlay, selectedTrainID: TrainID?, projection: some MapProjection, in context: GraphicsContext) {
        let width = authorityWidth(projection)
        let ordered = traffic.authorities.filter { $0.train != selectedTrainID } + traffic.authorities.filter { $0.train == selectedTrainID }
        for authority in ordered {
            let color = authority.train == selectedTrainID ? Palette.metroGreen : Palette.metroGreen.opacity(followDim)
            drawTrafficTrack(authority.track, color: color, width: width, projection: projection, in: context)
        }
    }

    /// Where each waiting train meets the train holding its route, wider
    /// than an authority: amber as the wait's words are, red in a
    /// deadlock; and a dashed line from the waiting train's head to it.
    private static func drawWaits(_ traffic: TrafficOverlay, projection: some MapProjection, in context: GraphicsContext) {
        let width = authorityWidth(projection) * 1.3
        let region = drawingRegion(projection)
        for wait in traffic.waits {
            let color = wait.isDeadlocked ? Palette.metroRed : Palette.metroAmber
            drawTrafficTrack(wait.contested, color: color, width: width, projection: projection, in: context)
            guard wait.from != wait.to, let reach = WorldRegion(enclosing: [wait.from, wait.to]), region.intersects(reach) else { continue }
            // Dashed, so drawn whole (see the tunnels in drawNetwork).
            let dash = max(3, projection.referenceSize * 0.3)
            context.stroke(wholePolyline([wait.from, wait.to], projection: projection), with: .color(color), style: StrokeStyle(lineWidth: max(1.5, projection.referenceSize * 0.08), lineCap: .butt, dash: [dash, dash * 0.6]))
        }
    }

    /// A ring round each waiting train's head, over the trains: red with a
    /// warning sign for a deadlocked one.
    private static func drawWaitMarks(_ traffic: TrafficOverlay, projection: some MapProjection, in context: GraphicsContext) {
        let region = drawingRegion(projection)
        let radius = max(2.5, projection.referenceSize * 0.26) + 4
        for wait in traffic.waits where region.contains(wait.from) {
            let center = projection.screenPoint(of: wait.from)
            let ring = disc(at: center, radius: radius)
            context.stroke(ring, with: .color(Color(uiColor: .systemBackground)), lineWidth: 5)
            context.stroke(ring, with: .color(wait.isDeadlocked ? Palette.metroRed : Palette.metroAmber), lineWidth: 3)
            guard wait.isDeadlocked else { continue }
            var sign = context.resolve(Image(systemName: "exclamationmark.triangle.fill"))
            sign.shading = .color(Palette.metroRed)
            let size = radius * 1.4
            context.draw(sign, in: CGRect(x: center.x + radius * 0.6, y: center.y - radius * 0.6 - size, width: size, height: size))
        }
    }

    private static func drawTrafficTrack(_ track: TrafficOverlay.Track, color: Color, width: Double, projection: some MapProjection, in context: GraphicsContext) {
        let region = drawingRegion(projection)
        let full = projection.detail == .full
        for line in track.lines where line.count > 1 {
            let path = polyline(line, projection: projection)
            if full {
                context.stroke(path, with: .color(Palette.followCase), style: StrokeStyle(lineWidth: width * 8.5 / 4.4, lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        for node in track.nodes where region.contains(node) {
            context.stroke(disc(at: projection.screenPoint(of: node), radius: width), with: .color(color), lineWidth: max(1.5, width * 0.45))
        }
    }

    private static func drawNetwork(_ world: GameWorld, projection: some MapProjection, cached: [TrackEdgeID: MapEdgeDrawing], in context: GraphicsContext) {
        let region = drawingRegion(projection)
        let referenceSize = projection.referenceSize
        let detail = projection.detail
        let edges = world.network.edges.compactMap { edge -> MapEdgeDrawing? in
            // A command can reach Canvas before onChange refreshes the cache.
            let drawing = cached[edge.id] ?? MapEdgeDrawing(edge: edge, world: world)
            return drawing.flatMap { region.intersects($0.bounds) ? $0 : nil }
        }.sorted {
            ($0.geometry.startHeight + $0.geometry.endHeight, $0.edge.id)
                < ($1.geometry.startHeight + $1.geometry.endHeight, $1.edge.id)
        }
        if detail == .full {
            let geometries = Dictionary(uniqueKeysWithValues: edges.map { ($0.edge.id, $0.geometry) })
            for platform in world.network.platforms {
                guard let points = geometries[platform.edge]?.points(from: platform.start, to: platform.end),
                      let bounds = WorldRegion(enclosing: points), region.intersects(bounds) else { continue }
                context.stroke(polyline(points, projection: projection), with: .color(Palette.station.opacity(0.85)), style: StrokeStyle(lineWidth: max(3, referenceSize * 0.75), lineCap: .butt, lineJoin: .round))
            }
        }
        for drawing in edges {
            // A tunnel is dashed: cut where the view ends, its dashes would
            // restart at the cut and shift as the map pans. Draw it whole.
            let line = drawing.edge.structure == .tunnel
                ? wholePolyline(drawing.geometry.points, projection: projection)
                : polyline(drawing.geometry.points, projection: projection)
            drawEdge(line, structure: drawing.edge.structure, detail: detail, referenceSize: referenceSize, in: context)
        }
        guard detail == .full else { return }
        let radius = max(1.5, referenceSize * 0.08)
        for node in world.network.nodes where region.contains(node.position) {
            let dot = disc(at: projection.screenPoint(of: node.position), radius: radius)
            context.fill(dot, with: .color(Palette.rail))
            if world.isTunnelPortal(node.id) {
                context.stroke(disc(at: projection.screenPoint(of: node.position), radius: radius * 2.5), with: .color(Palette.rail), lineWidth: max(1, radius * 0.6))
            }
        }
    }

    private static func drawNetworkOverlay(_ overlay: NetworkOverlay, projection: some MapProjection, in context: GraphicsContext) {
        let referenceSize = projection.referenceSize
        if overlay.highlight.count > 1 {
            let band = polyline(overlay.highlight, projection: projection)
            switch overlay.highlightKind {
            case .removal:
                context.stroke(band, with: .color(Color.red.opacity(0.6)), style: StrokeStyle(lineWidth: max(6, referenceSize * 0.6), lineCap: .round, lineJoin: .round))
            case .platform:
                context.stroke(band, with: .color(Palette.rail), style: StrokeStyle(lineWidth: max(6, referenceSize * 0.85), lineCap: .butt, lineJoin: .round))
                context.stroke(band, with: .color(Palette.station), style: StrokeStyle(lineWidth: max(4, referenceSize * 0.75), lineCap: .butt, lineJoin: .round))
            }
        }
        if overlay.preview.count > 1 {
            let line = polyline(overlay.preview, projection: projection)
            let width = max(2, referenceSize * 0.12)
            if overlay.previewIsBuildable {
                context.stroke(line, with: .color(Color.accentColor.opacity(0.3)), style: StrokeStyle(lineWidth: referenceSize * 0.5, lineCap: .round, lineJoin: .round))
                context.stroke(line, with: .color(Color.accentColor), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            } else {
                // Dashed, so drawn whole (see the tunnels in drawNetwork).
                context.stroke(wholePolyline(overlay.preview, projection: projection), with: .color(Color.gray), style: StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round, dash: [max(2, referenceSize * 0.25), max(2, referenceSize * 0.2)]))
            }
        }
        let radius = max(5, referenceSize * 0.2)
        let region = drawingRegion(projection)
        for (index, anchor) in overlay.anchors.enumerated() where region.contains(anchor) {
            let dot = disc(at: projection.screenPoint(of: anchor), radius: radius)
            if index == 0 {
                context.fill(dot, with: .color(Color.accentColor))
                context.stroke(dot, with: .color(Color(uiColor: .systemBackground)), lineWidth: 2)
            } else {
                context.stroke(dot, with: .color(Color(uiColor: .systemBackground)), lineWidth: 5)
                context.stroke(dot, with: .color(Color.accentColor), lineWidth: 3)
            }
        }
    }

    /// Segment culling also handles long edges with both ends offscreen.
    private static func polyline(_ points: [WorldCoordinate], projection: some MapProjection) -> Path {
        let runs = MapScale.visiblePolylines(points, projection: projection, margin: max(12, projection.referenceSize), minimumSpacing: projection.detail == .overview ? 2 : 0)
        var path = Path()
        for run in runs {
            path.move(to: cgPoint(run[0]))
            for point in run.dropFirst() { path.addLine(to: cgPoint(point)) }
        }
        return path
    }

    /// Every point, uncut, for a dashed line: the dashes then start at its
    /// first point wherever the view is. The callers draw only lines that
    /// reach the view.
    private static func wholePolyline(_ points: [WorldCoordinate], projection: some MapProjection) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: cgPoint(projection.screenPoint(of: first)))
        for point in points.dropFirst() {
            path.addLine(to: cgPoint(projection.screenPoint(of: point)))
        }
        return path
    }

    private static func drawEdge(_ line: Path, structure: TrackStructure, detail: MapDetail, referenceSize: Double, in context: GraphicsContext) {
        let rail = StrokeStyle(lineWidth: max(1.5, referenceSize * 0.1), lineCap: .round, lineJoin: .round)
        switch (structure, detail) {
        case (.tunnel, _):
            context.stroke(line, with: .color(Palette.rail.opacity(0.55)), style: StrokeStyle(lineWidth: rail.lineWidth, lineCap: .butt, lineJoin: .round, dash: [max(2, referenceSize * 0.3), max(2, referenceSize * 0.2)]))
        case (_, .overview):
            context.stroke(line, with: .color(Palette.rail), style: StrokeStyle(lineWidth: max(1, referenceSize * 0.12), lineCap: .round, lineJoin: .round))
        case (.surface, .full):
            context.stroke(line, with: .color(Palette.ballast), style: StrokeStyle(lineWidth: referenceSize * 0.42, lineCap: .round, lineJoin: .round))
            context.stroke(line, with: .color(Palette.rail), style: rail)
        case (.elevated, .full), (.bridge, .full):
            context.stroke(line, with: .color(Palette.rail.opacity(0.35)), style: StrokeStyle(lineWidth: referenceSize * 0.58, lineCap: .butt, lineJoin: .round))
            context.stroke(line, with: .color(Palette.ballast), style: StrokeStyle(lineWidth: referenceSize * 0.42, lineCap: .butt, lineJoin: .round))
            context.stroke(line, with: .color(Palette.rail), style: rail)
        }
    }

    private static func drawTrain(at location: TrackLocation, isSelected: Bool, projection: some MapProjection, in context: GraphicsContext) {
        let center = projection.screenPoint(of: location.position)
        let radius = max(2.5, projection.referenceSize * 0.26)
        if projection.detail == .full {
            let dx = Double(location.direction.dx), dy = Double(location.direction.dy)
            let length = (dx * dx + dy * dy).squareRoot()
            if length > 0 {
                let distance = radius * 1.7 / projection.pointsPerUnit
                let end = projection.screenPoint(worldX: Double(location.position.x) + dx / length * distance, worldY: Double(location.position.y) + dy / length * distance)
                var nose = Path()
                nose.move(to: cgPoint(center))
                nose.addLine(to: cgPoint(end))
                context.stroke(nose, with: .color(Palette.train), style: StrokeStyle(lineWidth: max(2, projection.referenceSize * 0.12), lineCap: .round))
            }
        }
        let dot = disc(at: center, radius: radius)
        context.fill(dot, with: .color(Palette.train))
        context.stroke(dot, with: .color(isSelected ? .accentColor : Color(uiColor: .systemBackground)), lineWidth: isSelected ? 3 : 1.5)
    }

    private static func drawPointStation(_ station: Station, isSelected: Bool, projection: some MapProjection, in context: GraphicsContext) {
        let center = projection.screenPoint(of: station.location)
        let radius = max(5, projection.referenceSize * 0.32)
        let badgeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        // Resolving and measuring a name is the costly part, and every pan
        // frame redraws: first rule out stations whose badge and name cannot
        // reach the view. A caption2 character is under 24 points wide and a
        // line under 48 high at the largest text size, so this bound needs no
        // measuring.
        let reach = max(radius + 6, Double(station.name.count) * 12)
        let largest = CGRect(x: center.x - reach, y: center.y - radius - 6, width: reach * 2, height: radius * 2 + 10 + 48)
        guard largest.intersects(context.clipBoundingRect) else { return }
        let name = projection.detail == .full
            ? context.resolve(Text(verbatim: station.name).font(.caption2.weight(.semibold)).foregroundStyle(Palette.rail)) : nil
        let nameSize = name?.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)) ?? .zero
        let nameRect = CGRect(x: center.x - nameSize.width / 2, y: center.y + radius + 4, width: nameSize.width, height: nameSize.height)
        // Include the measured label, not only the station's anchor: a name
        // can be visible while its station is just outside the viewport.
        guard badgeRect.insetBy(dx: -6, dy: -6).intersects(context.clipBoundingRect)
            || nameRect.intersects(context.clipBoundingRect) else { return }
        let badge = Path(ellipseIn: badgeRect)
        context.fill(badge, with: .color(Palette.station))
        context.stroke(badge, with: .color(Palette.rail.opacity(0.5)), lineWidth: 1)
        if isSelected {
            let ring = disc(at: center, radius: radius + 3)
            context.stroke(ring, with: .color(Color(uiColor: .systemBackground)), lineWidth: 5)
            context.stroke(ring, with: .color(.accentColor), lineWidth: 3)
        }
        if let name {
            drawStationSymbol(at: center, size: radius * 1.05, context: context)
            context.draw(name, at: CGPoint(x: center.x, y: center.y + radius + 4), anchor: .top)
        }
    }

    private static func drawStationSymbol(at center: ScreenPoint, size: Double, context: GraphicsContext) {
        var symbol = context.resolve(Image(systemName: "tram.fill"))
        symbol.shading = .color(Palette.stationSymbol)
        let natural = symbol.size
        guard natural.width > 0, natural.height > 0 else { return }
        let scale = min(size / natural.width, size / natural.height)
        let width = natural.width * scale, height = natural.height * scale
        context.draw(symbol, in: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height))
    }

    private static func drawingRegion(_ projection: some MapProjection) -> WorldRegion {
        projection.visibleRegion.expanded(by: max(12, projection.referenceSize) / projection.pointsPerUnit)
    }

    private static func screenPoint(_ x: Double, _ y: Double, _ projection: some MapProjection) -> CGPoint {
        cgPoint(projection.screenPoint(worldX: x, worldY: y))
    }

    private static func cgPoint(_ point: ScreenPoint) -> CGPoint { CGPoint(x: point.x, y: point.y) }

    private static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private static func disc(at point: ScreenPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
}
