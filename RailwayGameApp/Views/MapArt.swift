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
        highlightedTrainID: TrainID? = nil,
        selectedStationID: StationID? = nil,
        network overlay: NetworkOverlay? = nil,
        building: BuildingOverlay? = nil,
        traffic: TrafficOverlay = TrafficOverlay(),
        projection: some MapProjection,
        edges: [TrackEdgeID: MapEdgeDrawing],
        layers: MapLayerPreferences = .default,
        waitingCounts: [StationID: Int64] = [:],
        lines: LineMap = LineMap(),
        labels: StationLabels = StationLabels(),
        latitude: Double = 0,
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
        // The land (and the population and travel layer over it) is drawn
        // by ``drawBase``, in a canvas of its own under this one; over
        // Apple's map (Stage E2) the base draws no land, only this edge.
        // Decision 123: past the edge the map is shaded, so the edge reads
        // as where the game's map ends; over a real-world map, a lone line
        // down the screen looked like a fault in the drawing.
        var beyond = Path(context.clipBoundingRect)
        beyond.addPath(land)
        context.fill(beyond, with: .color(Palette.mapEdge.opacity(0.12)), style: FillStyle(eoFill: true))
        context.stroke(land, with: .color(Palette.mapEdge), lineWidth: 1)

        if layers.showsCatchmentRings {
            drawCatchmentRings(world, projection: projection, in: context)
        }

        drawNetwork(world, projection: projection, cached: edges, in: context)
        drawLines(lines, world: world, projection: projection, cached: edges, in: context)
        drawTransfers(lines, projection: projection, in: context)
        drawAuthorities(traffic, selectedTrainID: highlightedTrainID ?? selectedTrainID, projection: projection, in: context)
        if let building {
            drawCityBuildingSites(world, overlay: building, projection: projection, in: context)
        }
        drawPlacedBuildings(world, projection: projection, in: context)
        if let building { drawBuildingOverlay(building, projection: projection, in: context) }
        for station in world.stations {
            drawPointStation(
                station,
                isSelected: station.id == selectedStationID,
                layers: layers,
                waitingCount: waitingCounts[station.id] ?? 0,
                projection: projection,
                in: context
            )
        }
        if detail != .full && layers.showsStationNames {
            drawOverviewNames(world, labels: labels, latitude: latitude, projection: projection, in: context)
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
            // Decision 121: the sign on its own solid outline, a size up,
            // so its mark reads over any map.
            let size = radius * 1.4
            let sign = CGRect(x: center.x + radius * 0.6, y: center.y - radius * 0.6 - size, width: size, height: size)
            var halo = context.resolve(MapGlyph.warningSolid.image)
            halo.shading = .color(Color(uiColor: .systemBackground))
            context.draw(halo, in: sign.insetBy(dx: -size * 0.15, dy: -size * 0.15))
            var mark = context.resolve(MapGlyph.warning.image)
            mark.shading = .color(Palette.metroRed)
            context.draw(mark, in: sign)
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
            // Decision 124: an automatic edge stretch by stretch, as the
            // ground carries it; an explicit one whole.
            let spans = drawing.edge.sectionSpans
            for span in spans {
                let points = spans.count == 1 ? drawing.geometry.points : drawing.geometry.points(from: span.start, to: span.end)
                // A tunnel is dashed: cut where the view ends, its dashes
                // would restart at the cut and shift as the map pans. Draw
                // it whole.
                let line = span.kind == .tunnel ? wholePolyline(points, projection: projection) : polyline(points, projection: projection)
                drawEdge(line, structure: span.kind.structure, detail: detail, referenceSize: referenceSize, in: context)
            }
        }
        guard detail == .full else { return }
        let radius = max(1.5, referenceSize * 0.08)
        for node in world.network.nodes where region.contains(node.position) {
            let dot = disc(at: projection.screenPoint(of: node.position), radius: radius)
            context.fill(dot, with: .color(Palette.ink))
            if world.isTunnelPortal(node.id) {
                context.stroke(disc(at: projection.screenPoint(of: node.position), radius: radius * 2.5), with: .color(Palette.ink), lineWidth: max(1, radius * 0.6))
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
                context.stroke(band, with: .color(Palette.ink), style: StrokeStyle(lineWidth: max(6, referenceSize * 0.85), lineCap: .butt, lineJoin: .round))
                context.stroke(band, with: .color(Palette.station), style: StrokeStyle(lineWidth: max(4, referenceSize * 0.75), lineCap: .butt, lineJoin: .round))
            }
        }
        // Decision 95: the company's buildings it would pull down.
        for rect in overlay.cleared {
            drawMarked(rect, colour: Color.red, projection: projection, in: context)
        }
        // The next stretch, and an X crossover's mirrored diagonal.
        for points in [overlay.preview, overlay.crossing] where points.count > 1 {
            let line = polyline(points, projection: projection)
            let width = max(2, referenceSize * 0.12)
            if overlay.previewIsBuildable {
                context.stroke(line, with: .color(Color.accentColor.opacity(0.3)), style: StrokeStyle(lineWidth: referenceSize * 0.5, lineCap: .round, lineJoin: .round))
                context.stroke(line, with: .color(Color.accentColor), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            } else {
                // Dashed, so drawn whole (see the tunnels in drawNetwork).
                context.stroke(wholePolyline(points, projection: projection), with: .color(Color.gray), style: StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round, dash: [max(2, referenceSize * 0.25), max(2, referenceSize * 0.2)]))
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

    /// The track as the app icon draws it (decision 84): a teal bed with a
    /// pale line down the middle; a viaduct or bridge with a navy casing,
    /// a tunnel dashed.
    private static func drawEdge(_ line: Path, structure: TrackStructure, detail: MapDetail, referenceSize: Double, in context: GraphicsContext) {
        let centre = StrokeStyle(lineWidth: max(1, referenceSize * 0.08), lineCap: .round, lineJoin: .round)
        switch (structure, detail) {
        case (.tunnel, _):
            context.stroke(line, with: .color(Palette.track.opacity(0.6)), style: StrokeStyle(lineWidth: max(1.5, referenceSize * 0.14), lineCap: .butt, lineJoin: .round, dash: [max(2, referenceSize * 0.3), max(2, referenceSize * 0.2)]))
        case (_, .overview):
            context.stroke(line, with: .color(Palette.track), style: StrokeStyle(lineWidth: max(1.5, referenceSize * 0.16), lineCap: .round, lineJoin: .round))
        case (.surface, .full), (.automatic, .full):
            context.stroke(line, with: .color(Palette.track), style: StrokeStyle(lineWidth: referenceSize * 0.42, lineCap: .round, lineJoin: .round))
            context.stroke(line, with: .color(Palette.trackCentre), style: centre)
        case (.elevated, .full), (.bridge, .full):
            context.stroke(line, with: .color(Palette.ink.opacity(0.35)), style: StrokeStyle(lineWidth: referenceSize * 0.58, lineCap: .butt, lineJoin: .round))
            context.stroke(line, with: .color(Palette.track), style: StrokeStyle(lineWidth: referenceSize * 0.42, lineCap: .butt, lineJoin: .round))
            context.stroke(line, with: .color(Palette.trackCentre), style: centre)
        }
    }

    // MARK: - Lines and transfer groups (decision 84)

    /// The width of a line drawn on the track; lines sharing track sit
    /// this far apart, touching, as MapBuilder's 8 px lines do.
    private static func lineWidth(_ projection: some MapProjection) -> Double {
        projection.detail == .full ? max(2.5, projection.referenceSize * 0.22) : max(2, projection.referenceSize * 0.16)
    }

    /// Each line in its colour along the track its trains take, side by
    /// side where lines share it (``LineMap``, MapBuilder's
    /// `js-Map-segments--solid`: butt caps, each line its offset out); in
    /// a tunnel, faded as the track is.
    private static func drawLines(_ lines: LineMap, world: GameWorld, projection: some MapProjection, cached: [TrackEdgeID: MapEdgeDrawing], in context: GraphicsContext) {
        guard !lines.stretches.isEmpty else { return }
        let region = drawingRegion(projection)
        let width = lineWidth(projection)
        var drawings: [TrackEdgeID: MapEdgeDrawing] = [:]
        for stretch in lines.stretches {
            guard let drawing = drawings[stretch.edge] ?? cached[stretch.edge] ?? world.network.edge(stretch.edge).flatMap({ MapEdgeDrawing(edge: $0, world: world) }) else { continue }
            drawings[stretch.edge] = drawing
            guard region.intersects(drawing.bounds) else { continue }
            let end = min(stretch.end, drawing.geometry.length)
            guard stretch.start < end else { continue }
            let points = drawing.geometry.points(from: stretch.start, to: end).map { cgPoint(projection.screenPoint(of: $0)) }
            let path = offsetPolyline(points, by: stretch.offset * width)
            let color = Palette.lineColor(stretch.line, custom: stretch.color)
            // Decision 124: in an automatic edge's tunnel too.
            let middle = (stretch.start + end) / 2
            let inTunnel = drawing.edge.sectionSpans.first { $0.start <= middle && middle <= $0.end }?.kind == .tunnel
            context.stroke(path, with: .color(inTunnel ? color.opacity(0.5) : color), style: StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round))
        }
    }

    /// Each transfer group as a white link with a navy edge through its
    /// stations (MapBuilder's `js-Map-interchanges--inner` and `--outer`:
    /// an 8 px white line inside a 2 px black edge), over the lines and
    /// under the stations.
    private static func drawTransfers(_ lines: LineMap, projection: some MapProjection, in context: GraphicsContext) {
        let inner = lineWidth(projection) * 1.2
        for group in lines.transfers {
            let points = group.map { cgPoint(projection.screenPoint(of: $0)) }
            guard let first = points.first else { continue }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            guard path.boundingRect.insetBy(dx: -inner, dy: -inner).intersects(context.clipBoundingRect) else { continue }
            context.stroke(path, with: .color(Palette.transferEdge), style: StrokeStyle(lineWidth: inner + 4, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(Palette.transferLink), style: StrokeStyle(lineWidth: inner, lineCap: .round, lineJoin: .round))
        }
    }

    /// `points` moved `distance` points to their left as they go (a
    /// negative distance to the right), each corner on the bisector so the
    /// line keeps its distance from the track, as Mapbox's `line-offset`.
    private static func offsetPolyline(_ points: [CGPoint], by distance: Double) -> Path {
        var path = Path()
        var distinct: [CGPoint] = []
        for point in points where distinct.last != point { distinct.append(point) }
        guard distinct.count > 1 else { return path }
        // The left of a step on the screen, whose y grows down.
        func left(_ a: CGPoint, _ b: CGPoint) -> CGVector {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            return CGVector(dx: dy / length, dy: -dx / length)
        }
        for index in distinct.indices {
            let before = index > 0 ? left(distinct[index - 1], distinct[index]) : nil
            let after = index < distinct.count - 1 ? left(distinct[index], distinct[index + 1]) : nil
            var normal = after ?? before ?? CGVector(dx: 0, dy: 0)
            if let before, let after {
                let sx = before.dx + after.dx, sy = before.dy + after.dy
                let length = (sx * sx + sy * sy).squareRoot()
                if length > 1e-6 {
                    // Out along the bisector, further at a sharper corner,
                    // at most twice as far.
                    let bisector = CGVector(dx: sx / length, dy: sy / length)
                    let scale = 1 / max(0.5, bisector.dx * after.dx + bisector.dy * after.dy)
                    normal = CGVector(dx: bisector.dx * scale, dy: bisector.dy * scale)
                }
            }
            let shifted = CGPoint(x: distinct[index].x + normal.dx * distance, y: distinct[index].y + normal.dy * distance)
            if index == 0 { path.move(to: shifted) } else { path.addLine(to: shifted) }
        }
        return path
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

    private static func drawCatchmentRings(_ world: GameWorld, projection: some MapProjection, in context: GraphicsContext) {
        let radiusWorldUnits = MapLayers.catchmentRadiusWorldUnits
        let screenRadius = MapLayers.catchmentScreenRadius(pointsPerUnit: projection.pointsPerUnit)
        guard screenRadius > 1 else { return }

        let region = drawingRegion(projection)
        for station in world.stations {
            let stationRegion = WorldRegion(
                minX: Double(station.location.x) - radiusWorldUnits,
                minY: Double(station.location.y) - radiusWorldUnits,
                maxX: Double(station.location.x) + radiusWorldUnits,
                maxY: Double(station.location.y) + radiusWorldUnits
            )
            guard region.intersects(stationRegion) else { continue }

            let center = projection.screenPoint(of: station.location)
            let circle = disc(at: center, radius: screenRadius)

            // Overlapping rings compound naturally with translucent fill
            context.fill(circle, with: .color(Palette.station.opacity(0.08)))
            let strokeWidth = max(1.0, min(2.0, projection.pointsPerUnit * 1.5))
            context.stroke(
                circle,
                with: .color(Palette.station.opacity(0.35)),
                style: StrokeStyle(lineWidth: strokeWidth, dash: [6, 4])
            )
        }
    }

    /// The map's land and the population and travel layer over it: what
    /// changes only with the camera or the layer's data, so the map view
    /// draws it in a canvas of its own that a moving train never redraws.
    static func drawBase(
        bounds worldBounds: WorldBounds,
        drawsLand: Bool,
        skyline: CitySkyline?,
        layer: PopTravelLayer?,
        projection: some MapProjection,
        in context: GraphicsContext
    ) {
        if drawsLand {
            let bounds = WorldRegion(bounds: worldBounds)
            let land = polygon([
                screenPoint(bounds.minX, bounds.minY, projection),
                screenPoint(bounds.maxX, bounds.minY, projection),
                screenPoint(bounds.maxX, bounds.maxY, projection),
                screenPoint(bounds.minX, bounds.maxY, projection)
            ])
            context.fill(land, with: .color(Palette.land))
        }
        if let skyline {
            drawSkyline(skyline, projection: projection, in: context)
        }
        guard let layer else { return }
        switch layer.content {
        case .population(let heatmap):
            drawPopulation(heatmap, opacity: layer.opacity, projection: projection, in: context)
        case .travel(let tiles):
            drawTravel(tiles, opacity: layer.opacity, projection: projection, in: context)
        case .city(let map, let mode):
            drawCity(map, mode: mode, opacity: layer.opacity, projection: projection, in: context)
        }
    }

    /// A city layer (Phase 6d, ``CityMap``): only the cells in view, merged
    /// into blocks when zoomed out (``CityMap/blockSize(pointsPerUnit:)``),
    /// one fill a colour.
    private static func drawCity(_ map: CityMap, mode: PopTravelMode, opacity: Double, projection: some MapProjection, in context: GraphicsContext) {
        let blockSize = CityMap.blockSize(pointsPerUnit: projection.pointsPerUnit)
        drawTravel(map.tiles(for: mode, in: drawingRegion(projection), blockSize: blockSize), opacity: opacity, projection: projection, in: context)
    }

    /// Below this many points a 64 m cell, the town is too small to draw.
    private static let skylineMinimumCellPoints = 3.0
    /// From this many points a cell, buildings rise by their density;
    /// below it they are flat footprints.
    private static let skylineRisingCellPoints = 9.0
    /// From this many points a footprint, a D3 or D4 building shows its
    /// floors as bands across its wall.
    private static let skylineBandsMinimumSide = 14.0

    /// The city's buildings (decision 126, ``CitySkyline``): each the
    /// middle square of its cell, a pale roof in its use's hue raised over
    /// a deeper wall by its density, edged in navy; parks and farms as open
    /// ground. Drawn row by row from the north, so a building in front
    /// covers the foot of the ones behind; each row's shapes are filled a
    /// colour at a time. Flat when zoomed out, nothing when a cell is a few
    /// points.
    private static func drawSkyline(_ skyline: CitySkyline, projection: some MapProjection, in context: GraphicsContext) {
        let cellPoints = Double(Land.cellLength) * projection.pointsPerUnit
        guard !skyline.isEmpty, cellPoints >= skylineMinimumCellPoints else { return }
        let rises = cellPoints >= skylineRisingCellPoints
        let lots = skyline.lots(in: drawingRegion(projection), rowsBelow: rises ? CitySkyline.rowsRisenOver : 0)
        let length = Double(Land.cellLength), side = Double(PlacedBuildingRules.cityBuildingSide), inset = (length - side) / 2
        let lineWidth = cellPoints < 14 ? 0.6 : 1
        var ground: [LandUse: Path] = [:], walls: [LandUse: Path] = [:], roofs: [LandUse: Path] = [:], outlines = Path()
        func drawRow() {
            for use in LandUse.allCases {
                if let path = ground[use] { context.fill(path, with: .color(Palette.cityRoof(use))) }
            }
            for use in LandUse.allCases {
                if let path = walls[use] { context.fill(path, with: .color(Palette.cityWall(use))) }
                if let path = roofs[use] { context.fill(path, with: .color(Palette.cityRoof(use))) }
            }
            context.stroke(outlines, with: .color(Palette.cityOutline), lineWidth: lineWidth)
            ground = [:]
            walls = [:]
            roofs = [:]
            outlines = Path()
        }
        var row = lots.first?.row
        for lot in lots {
            if lot.row != row {
                drawRow()
                row = lot.row
            }
            let minX = Double(lot.column) * length, minY = Double(lot.row) * length
            if lot.isOpenGround {
                let rect = screenRect(minX: minX, minY: minY, maxX: minX + length, maxY: minY + length, projection)
                ground[lot.use, default: Path()].addRect(rect)
                continue
            }
            let foot = screenRect(minX: minX + inset, minY: minY + inset, maxX: minX + inset + side, maxY: minY + inset + side, projection)
            let rise = rises ? foot.height * CitySkyline.heightShare(density: lot.density) : 0
            let roof = foot.offsetBy(dx: 0, dy: -rise)
            let whole = CGRect(x: foot.minX, y: roof.minY, width: foot.width, height: foot.maxY - roof.minY)
            walls[lot.use, default: Path()].addRect(whole)
            var top = Path(roof)
            // A tall building's floors, as pale bands down its wall.
            if rise > 0, lot.density >= 3, foot.width >= skylineBandsMinimumSide {
                let step = foot.width * 0.28
                var y = roof.maxY + foot.width * 0.12
                while y + foot.width * 0.1 <= foot.maxY - foot.width * 0.05 {
                    top.addRect(CGRect(x: foot.minX + foot.width * 0.18, y: y, width: foot.width * 0.64, height: foot.width * 0.1))
                    y += step
                }
            }
            roofs[lot.use, default: Path()].addPath(top)
            outlines.addRect(whole)
            if rise > 0 {
                outlines.move(to: CGPoint(x: roof.minX, y: roof.maxY))
                outlines.addLine(to: CGPoint(x: roof.maxX, y: roof.maxY))
            }
        }
        drawRow()
    }

    /// The narrowest a player's building is drawn, in points, with its
    /// kind's glyph (decision 121): under it the glyph would be a smudge.
    private static let glyphMinimumSide = 14.0

    /// The buildings the player placed (city building P0-A, decision 92):
    /// each a square in its kind's colour, edged in ink, always at least a
    /// few points across so it stays visible zoomed out, with its kind's glyph
    /// once it is large enough (decision 121).
    private static func drawPlacedBuildings(_ world: GameWorld, projection: some MapProjection, in context: GraphicsContext) {
        guard !world.placedBuildings.isEmpty else { return }
        let region = drawingRegion(projection)
        let minimum = 4.0
        for building in world.placedBuildings {
            let area = WorldRegion(minX: Double(building.minX), minY: Double(building.minY), maxX: Double(building.maxX), maxY: Double(building.maxY))
            guard region.intersects(area) else { continue }
            var rect = screenRect(minX: area.minX, minY: area.minY, maxX: area.maxX, maxY: area.maxY, projection)
            if rect.width < minimum {
                rect = rect.insetBy(dx: (rect.width - minimum) / 2, dy: (rect.height - minimum) / 2)
            }
            let colour: Color = switch building.kind {
            case .house: Palette.house
            case .shop: Palette.shop
            case .office: Palette.office
            case .wharf: Palette.wharf
            case .marina: Palette.marina
            }
            let shape = Path(roundedRect: rect, cornerRadius: min(3, rect.width * 0.12))
            context.fill(shape, with: .color(colour))
            context.stroke(shape, with: .color(Palette.ink), lineWidth: rect.width < 10 ? 0.75 : 1.25)
            // Decision 121: what it is, once there is room to read it.
            let side = min(rect.width, rect.height)
            guard side >= glyphMinimumSide else { continue }
            var glyph = context.resolve(building.kind.mapGlyph.image)
            glyph.shading = .color(Palette.buildingGlyph)
            let size = side * 0.62
            context.draw(glyph, in: CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size))
        }
    }

    /// Where the city's buildings stand (decision 95), while the building
    /// tool chooses a site: the middle square of each cell of land in view,
    /// faintly, once a cell is 8 points or more across.
    private static func drawCityBuildingSites(_ world: GameWorld, overlay: BuildingOverlay, projection: some MapProjection, in context: GraphicsContext) {
        guard overlay.showsCityBuildingSites, !world.land.isEmpty,
              Double(Land.cellLength) * projection.pointsPerUnit >= 8 else { return }
        let region = drawingRegion(projection)
        let length = Double(Land.cellLength)
        let firstRow = max(0, Int((region.minY / length).rounded(.down))), lastRow = min(Land.rows(in: world.bounds) - 1, Int((region.maxY / length).rounded(.down)))
        let firstColumn = max(0, Int((region.minX / length).rounded(.down))), lastColumn = min(Land.columns(in: world.bounds) - 1, Int((region.maxX / length).rounded(.down)))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return }
        var sites = Path()
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn where world.land.cell(row: row, column: column) != nil {
                let square = PlanRect.cityBuilding(row: row, column: column)
                sites.addRect(screenRect(minX: Double(square.minX), minY: Double(square.minY), maxX: Double(square.maxX), maxY: Double(square.maxY), projection))
            }
        }
        context.fill(sites, with: .color(Palette.ink.opacity(0.08)))
        context.stroke(sites, with: .color(Palette.ink.opacity(0.3)), style: StrokeStyle(lineWidth: 0.75, dash: [3, 2]))
    }

    /// The building tool's site (decision 95): the city's buildings it
    /// would buy out marked in red, and the building itself, green where it
    /// can stand and red where it cannot.
    private static func drawBuildingOverlay(_ overlay: BuildingOverlay, projection: some MapProjection, in context: GraphicsContext) {
        // Decision 98: the cells a zoning drag would zone, in the zone's
        // colour (grey, outlined only, when it clears them).
        if let drag = overlay.zoneDrag {
            let rect = screenRect(minX: Double(drag.minX), minY: Double(drag.minY), maxX: Double(drag.maxX), maxY: Double(drag.maxY), projection)
            let colour = overlay.zoneDragColor.map { Color($0) } ?? Color.gray
            let shape = Path(rect)
            if overlay.zoneDragColor != nil {
                context.fill(shape, with: .color(colour.opacity(0.35)))
            }
            context.stroke(shape, with: .color(colour), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
        for rect in overlay.boughtOut {
            drawMarked(rect, colour: Color.red, projection: projection, in: context)
        }
        guard let site = overlay.site else { return }
        var rect = screenRect(minX: Double(site.minX), minY: Double(site.minY), maxX: Double(site.maxX), maxY: Double(site.maxY), projection)
        if rect.width < 6 {
            rect = rect.insetBy(dx: (rect.width - 6) / 2, dy: (rect.height - 6) / 2)
        }
        let colour = overlay.siteIsBuildable ? Palette.metroGreen : Color.red
        let shape = Path(roundedRect: rect, cornerRadius: min(3, rect.width * 0.12))
        context.fill(shape, with: .color(colour.opacity(0.45)))
        context.stroke(shape, with: .color(colour), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
    }

    /// `rect` filled and edged in `colour`: something that would come down.
    private static func drawMarked(_ rect: PlanRect, colour: Color, projection: some MapProjection, in context: GraphicsContext) {
        let shape = Path(screenRect(minX: Double(rect.minX), minY: Double(rect.minY), maxX: Double(rect.maxX), maxY: Double(rect.maxY), projection))
        context.fill(shape, with: .color(colour.opacity(0.3)))
        context.stroke(shape, with: .color(colour), lineWidth: 1.5)
    }

    /// The screen rectangle of the world rectangle from (`minX`, `minY`)
    /// to (`maxX`, `maxY`).
    private static func screenRect(minX: Double, minY: Double, maxX: Double, maxY: Double, _ projection: some MapProjection) -> CGRect {
        let a = screenPoint(minX, minY, projection)
        let b = screenPoint(maxX, maxY, projection)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// The population grid (`chinaGrid`'s 1 km gradient) at the layer's
    /// opacity (`fill-opacity`): only the cells in view, merged into blocks
    /// when zoomed out (``PopulationHeatmap/blockSize(pointsPerUnit:)``),
    /// and one fill for each step of the gradient rather than one for each
    /// cell. The outline (the LandScan grid's `rgba(8,48,107,0.45)` at
    /// width 0.4, `0.88 × opacity / 0.72`) only once cells are 12 points
    /// or more, where it can be told apart.
    private static func drawPopulation(_ heatmap: PopulationHeatmap, opacity: Double, projection: some MapProjection, in context: GraphicsContext) {
        let blockSize = heatmap.blockSize(pointsPerUnit: projection.pointsPerUnit)
        let tiles = heatmap.tiles(in: drawingRegion(projection), blockSize: blockSize)
        guard !tiles.isEmpty else { return }
        var bands = Array(repeating: Path(), count: PopTravel.populationBands)
        var outline = Path()
        var outlined = blockSize == 1
        for tile in tiles {
            let rect = screenRect(minX: tile.minX, minY: tile.minY, maxX: tile.maxX, maxY: tile.maxY, projection)
            bands[tile.band].addRect(rect)
            if outlined {
                if rect.width < 12 { outlined = false } else { outline.addRect(rect) }
            }
        }
        for (band, path) in bands.enumerated() where !path.isEmpty {
            context.fill(path, with: .color(Color(PopTravel.populationBandColor(band)).opacity(opacity)))
        }
        if outlined {
            let alpha = 0.45 * min(1, 0.88 * opacity / 0.72)
            context.stroke(outline, with: .color(Color(PopTravel.populationOutline).opacity(alpha)), lineWidth: 0.4)
        }
    }

    /// The travel demand or demand change squares, one fill a colour.
    private static func drawTravel(_ tiles: [TravelDemandMap.Tile], opacity: Double, projection: some MapProjection, in context: GraphicsContext) {
        let region = drawingRegion(projection)
        var paths: [PopTravel.RGB: Path] = [:]
        var order: [PopTravel.RGB] = []
        for tile in tiles {
            guard tile.maxX > region.minX, tile.minX < region.maxX, tile.maxY > region.minY, tile.minY < region.maxY else { continue }
            if paths[tile.color] == nil { order.append(tile.color) }
            paths[tile.color, default: Path()].addRect(screenRect(minX: tile.minX, minY: tile.minY, maxX: tile.maxX, maxY: tile.maxY, projection))
        }
        for color in order {
            if let path = paths[color] {
                context.fill(path, with: .color(Color(color).opacity(opacity)))
            }
        }
    }

    private static func drawPointStation(
        _ station: Station,
        isSelected: Bool,
        layers: MapLayerPreferences,
        waitingCount: Int64,
        projection: some MapProjection,
        in context: GraphicsContext
    ) {
        let center = projection.screenPoint(of: station.location)
        let radius = max(5, projection.referenceSize * 0.32)
        let badgeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        // Resolving and measuring a name is the costly part, and every pan
        // frame redraws: first rule out stations whose badge and name cannot
        // reach the view. A caption2 character is under 24 points wide and a
        // line under 48 high at the largest text size, so this bound needs no
        // measuring.
        let reach = max(radius + 6, Double(station.name.count) * 12)
        let largest = CGRect(x: center.x - reach, y: center.y - radius - 20, width: reach * 2, height: radius * 2 + 20 + 48)
        guard largest.intersects(context.clipBoundingRect) else { return }
        let name = (projection.detail == .full && layers.showsStationNames)
            ? context.resolve(Text(verbatim: station.name).font(.caption2.weight(.semibold)).foregroundStyle(Palette.ink)) : nil
        let nameSize = name?.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)) ?? .zero
        let nameRect = CGRect(x: center.x - nameSize.width / 2, y: center.y + radius + 4, width: nameSize.width, height: nameSize.height)
        // Include the measured label, not only the station's anchor: a name
        // can be visible while its station is just outside the viewport.
        guard badgeRect.insetBy(dx: -6, dy: -6).intersects(context.clipBoundingRect)
            || nameRect.intersects(context.clipBoundingRect) else { return }
        let badge = Path(ellipseIn: badgeRect)
        context.fill(badge, with: .color(Palette.station))
        context.stroke(badge, with: .color(Palette.ink), lineWidth: 1.5)
        if isSelected {
            let ring = disc(at: center, radius: radius + 3)
            context.stroke(ring, with: .color(Color(uiColor: .systemBackground)), lineWidth: 5)
            context.stroke(ring, with: .color(.accentColor), lineWidth: 3)
        }
        drawStationSymbol(at: center, size: radius * 1.05, context: context)
        if let name {
            context.draw(name, at: CGPoint(x: center.x, y: center.y + radius + 4), anchor: .top)
        }

        // Waiting passengers count badge
        if layers.showsWaitingCounts && projection.detail == .full {
            if waitingCount > 0 {
                let countText = context.resolve(
                    Text(verbatim: "\(waitingCount)")
                        .font(.system(size: max(8, min(11, radius * 0.7)), weight: .bold))
                        .foregroundStyle(Color.white)
                )
                let countSize = countText.measure(in: CGSize(width: 120, height: 24))
                let pillWidth = max(countSize.width + 6, radius * 1.5)
                let pillHeight = max(countSize.height + 2, 11)
                let pillY = center.y - radius - pillHeight / 2 - 2
                let pillRect = CGRect(x: center.x - pillWidth / 2, y: pillY - pillHeight / 2, width: pillWidth, height: pillHeight)
                let pillPath = Path(roundedRect: pillRect, cornerRadius: pillHeight / 2)
                context.fill(pillPath, with: .color(Palette.metroBlue))
                context.stroke(pillPath, with: .color(Color(uiColor: .systemBackground)), lineWidth: 1)
                context.draw(countText, at: CGPoint(x: center.x, y: pillY), anchor: .center)
            }
        }
    }

    /// The most stations named on a zoomed-out map at once, and the most
    /// names measured for it in a frame (measuring is the costly part).
    private static let overviewNameLimit = 60
    private static let overviewNamesMeasured = 150

    /// Zoomed out (decision 89), the names of the stations whose lines'
    /// level the map's zoom is above (MapBuilder's `zoomThreshold`), the
    /// widest lines' first: a name that would cover one already drawn is
    /// left out, and at most ``overviewNameLimit`` are drawn of the first
    /// ``overviewNamesMeasured`` near the view. Each sits on
    /// a pale plate so it reads over the lines and Apple's map.
    private static func drawOverviewNames(
        _ world: GameWorld, labels: StationLabels, latitude: Double, projection: some MapProjection, in context: GraphicsContext
    ) {
        let zoom = StationLabels.zoom(pointsPerUnit: projection.pointsPerUnit, latitude: latitude)
        let view = context.clipBoundingRect
        let near = view.insetBy(dx: -160, dy: -60)
        let radius = max(5, projection.referenceSize * 0.32)
        let points = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.id, $0) })
        var placed: [CGRect] = []
        var measured = 0
        for entry in labels.named(atZoom: zoom) {
            guard placed.count < overviewNameLimit, measured < overviewNamesMeasured else { break }
            guard let station = points[entry.station] else { continue }
            let center = projection.screenPoint(of: station.location)
            guard near.contains(CGPoint(x: center.x, y: center.y)) else { continue }
            measured += 1
            let name = context.resolve(Text(verbatim: station.name).font(.caption2.weight(.semibold)).foregroundStyle(Palette.ink))
            let size = name.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
            let rect = CGRect(x: center.x - size.width / 2, y: center.y + radius + 2, width: size.width, height: size.height)
            guard rect.intersects(view), !placed.contains(where: { $0.insetBy(dx: -3, dy: -1).intersects(rect) }) else { continue }
            placed.append(rect)
            context.fill(Path(roundedRect: rect.insetBy(dx: -2, dy: 0), cornerRadius: 3), with: .color(Palette.land.opacity(0.8)))
            context.draw(name, at: CGPoint(x: center.x, y: center.y + radius + 2), anchor: .top)
        }
    }

    private static func drawStationSymbol(at center: ScreenPoint, size: Double, context: GraphicsContext) {
        var symbol = context.resolve(MapGlyph.train.image)
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
