import GameCore
import GamePresentation
import SwiftUI

/// Immutable, derived edge geometry. Kept by MapView, never by GameCore
/// or the save format, so panning and train ticks do not resample curves.
struct MapEdgeDrawing: Equatable, Sendable {
    let edge: TrackEdge
    let geometry: TrackGeometry
    let bounds: WorldRegion
    /// Decision 124, H3: the side slopes of its embankments and cuttings.
    let slopes: [TrackSlope]

    init?(edge: TrackEdge, world: GameWorld) {
        guard let geometry = world.trackGeometry(of: edge.id),
              let bounds = WorldRegion(enclosing: geometry.points) else { return nil }
        self.edge = edge
        self.geometry = geometry
        self.bounds = bounds
        // Only an automatic edge has embankments and cuttings.
        slopes = edge.structure == .automatic
            ? world.longSection(of: edge.id).map { TrackSlope.slopes(of: $0, geometry: geometry) } ?? []
            : []
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
        expansion: MapExpansionOverlay? = nil,
        traffic: TrafficOverlay = TrafficOverlay(),
        projection: some MapProjection,
        edges: [TrackEdgeID: MapEdgeDrawing],
        layers: MapLayerPreferences = .default,
        waitingCounts: [StationID: Int64] = [:],
        lines: LineMap = LineMap(),
        routePreview: RoutePreview? = nil,
        labels: StationLabels = StationLabels(),
        flowStrokes: [SectionFlow.Stroke] = [],
        latitude: Double = 0,
        lights: Double = 0,
        lineCodes: [LineID: String] = [:],
        journey: JourneyTrace? = nil,
        journeyProgress: Double = 1,
        drawsLabels: Bool = true,
        in context: GraphicsContext
    ) {
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
        // Decision 160: the land not owned yet is shaded too, and the
        // tiles for sale marked while the player chooses one.
        if let expansion {
            drawMapExpansion(expansion, land: land, projection: projection, in: context)
        }

        if layers.showsCatchmentRings {
            drawCatchmentRings(world, projection: projection, in: context)
        }

        // Decision 213: the real lines the network tool traces, under the
        // track (docs/MAP_LAYERS.md, 22.5).
        if let overlay, !overlay.traceable.isEmpty {
            drawTraceableLines(overlay, projection: projection, in: context)
        }
        drawNetwork(world, projection: projection, cached: edges, in: context)
        if flowStrokes.isEmpty {
            drawLines(lines, world: world, projection: projection, cached: edges, codes: lineCodes, in: context)
        } else {
            drawSectionFlow(flowStrokes, world: world, projection: projection, cached: edges, in: context)
        }
        drawTransfers(lines, projection: projection, in: context)
        // Decision 220: the held station's busiest trips (docs/MAP_LAYERS.md, 25.5).
        if let journey {
            drawJourneyTrace(journey, world: world, progress: journeyProgress, projection: projection, in: context)
        }
        if let routePreview {
            drawRoutePreview(routePreview, world: world, projection: projection, cached: edges, in: context)
        }
        drawAuthorities(traffic, selectedTrainID: highlightedTrainID ?? selectedTrainID, projection: projection, in: context)
        if let building {
            drawCityBuildingSites(world, overlay: building, projection: projection, in: context)
        }
        drawPlacedBuildings(world, projection: projection, in: context)
        if let building { drawBuildingOverlay(building, projection: projection, in: context) }
        // Decision 182: at night each station shines, under its badge.
        if lights > 0 {
            drawStationLights(world, lights: lights, projection: projection, in: context)
        }
        // Decision 168: the stations a high-speed line calls at have a second ring.
        let fast = world.highSpeedStations
        for station in world.stations {
            drawPointStation(
                station,
                isSelected: station.id == selectedStationID,
                isHighSpeed: fast.contains(station.id),
                projection: projection,
                in: context
            )
        }
        if drawsLabels {
            drawStationLabels(world, layers: layers, waitingCounts: waitingCounts, labels: labels, latitude: latitude,
                              lineCodes: lineCodes, projection: projection, in: context)
            drawBuildMarks(world, network: overlay, routePreview: routePreview, projection: projection, cached: edges, in: context)
        }
        drawWaits(traffic, projection: projection, in: context)
        // The trains and the rings round the waiting ones are drawn over
        // this, by ``drawTrains``, in a canvas of their own (decision 182);
        // and over them the stations' names and waiting counts
        // (``drawStationLabels``, docs/MAP_LAYERS.md 55–57) and over those
        // the network tool's preview and the tracks' numbers
        // (``drawBuildMarks``), unless `drawsLabels` draws them here (the
        // track-drawing loupe).
    }

    /// The network tool's preview and the tracks' numbers (decision 201),
    /// over the stations' names, as they were before the names moved over
    /// the trains (#603).
    static func drawBuildMarks(
        _ world: GameWorld,
        network overlay: NetworkOverlay?,
        routePreview: RoutePreview?,
        projection: some MapProjection,
        cached edges: [TrackEdgeID: MapEdgeDrawing],
        in context: GraphicsContext
    ) {
        if let overlay { drawNetworkOverlay(overlay, projection: projection, in: context) }
        drawTrackNumbers(world, preview: routePreview, projection: projection, cached: edges, in: context)
    }

    /// The stations' names (with their lines' badges under them, decision
    /// 216), the names zoomed out (decision 89) and the waiting counts and
    /// crowded rings (decision 210): over the trains, so a train stopped at
    /// a station never covers its name or count (docs/MAP_LAYERS.md 55–57).
    static func drawStationLabels(
        _ world: GameWorld,
        layers: MapLayerPreferences,
        waitingCounts: [StationID: Int64],
        labels: StationLabels,
        latitude: Double,
        lineCodes: [LineID: String],
        projection: some MapProjection,
        in context: GraphicsContext
    ) {
        if layers.showsStationNames {
            if projection.detail == .full {
                // Decision 216: the badges of the lines calling at each
                // station, under its name.
                let badges = stationBadges(world, codes: lineCodes)
                for station in world.stations {
                    drawStationName(station, badges: badges[station.id] ?? [], projection: projection, in: context)
                }
            } else {
                drawOverviewNames(world, labels: labels, latitude: latitude, projection: projection, in: context)
            }
        }
        // Decision 210: the waiting counts and crowded rings, over every
        // station and name, at a middle zoom too.
        if layers.showsWaitingCounts {
            drawStationProblems(world, waitingCounts: waitingCounts, projection: projection, in: context)
        }
    }

    // MARK: - Trains (decision 182)

    /// The trains, each where it is `progress` of the way through its glide
    /// from the last tick (``TrainMotion``), then the rings round the
    /// waiting ones, a deadlocked one's as strong as `deadlock`
    /// (``TrafficOverlay/deadlockStrength(at:reduceMotion:)``). A train is in its line's colour (``Palette/trainColor``),
    /// every one in the map's train colour with `plain`; its body is cased
    /// in ``Palette/ink`` so that it reads over its own line. At night
    /// (`lights` above 0) each head shines in the stations' warm yellow.
    static func drawTrains(
        _ motion: TrainMotion,
        progress: Double,
        selectedTrainID: TrainID?,
        lights: Double,
        plain: Bool,
        traffic: TrafficOverlay,
        depotRuns: [TrainID: TrainDepotState] = [:],
        deadlock: Double = 1,
        pulse: Double? = nil,
        language: DisplayLanguage = .english,
        projection: some MapProjection,
        in context: GraphicsContext
    ) {
        let region = drawingRegion(projection)
        let referenceSize = projection.referenceSize
        var plates: [(point: ScreenPoint, state: TrainDepotState)] = []
        for run in motion.runs {
            guard let head = run.head(at: progress) else { continue }
            if let state = depotRuns[run.train], region.contains(x: head.point.x, y: head.point.y) {
                plates.append((projection.screenPoint(worldX: head.point.x, worldY: head.point.y), state))
            }
            let colour = Palette.trainColor(run.look, plain: plain)
            let isSelected = run.train == selectedTrainID
            let inView = region.contains(x: head.point.x, y: head.point.y)
            if lights > 0, inView {
                let center = projection.screenPoint(worldX: head.point.x, worldY: head.point.y)
                let radius = trainHeadRadius(referenceSize)
                context.fill(disc(at: center, radius: radius * 3.2), with: .color(Palette.station.opacity(0.18 * lights)))
                context.fill(disc(at: center, radius: radius * 2), with: .color(Palette.station.opacity(0.3 * lights)))
            }
            if projection.detail == .full {
                // Decision 205: close up, its cars. A tail may still be
                // visible when its head is offscreen.
                let cars = TrainCars.count(length: run.length, carPitch: run.carPitch)
                let reach = run.length + run.lag + TrainCars.drawnCarLength * Double(cars)
                guard region.expanded(by: reach).contains(x: head.point.x, y: head.point.y) else { continue }
                drawCars(
                    TrainCars.cars(body: run.body(at: progress), heading: head.heading, count: cars),
                    colour: colour, livery: run.livery, painted: !plain, isSelected: isSelected, projection: projection, in: context
                )
                continue
            }
            guard inView else { continue }
            drawTrain(
                at: head.point, heading: head.heading, colour: colour,
                isSelected: isSelected, isHighSpeed: run.isHighSpeed, projection: projection, in: context
            )
        }
        // Layer 51, over the trains and under the waits.
        for plate in plates {
            drawDepotPlate(plate.state, over: plate.point, radius: trainHeadRadius(referenceSize), in: context)
        }
        drawWaitMarks(traffic, deadlock: deadlock, pulse: pulse, language: language, projection: projection, in: context)
    }

    /// Decision 214 (`docs/UI_THEME.md` 機廠): a train leaving or entering
    /// its depot has a small square plate over its head, navy with a white
    /// edge and glyph, the garage on the left going out, on the right going
    /// in; no words, no circle, so it reads apart from the waits' rings and
    /// tags.
    private static func drawDepotPlate(_ state: TrainDepotState, over head: ScreenPoint, radius: Double, in context: GraphicsContext) {
        let side = max(12, radius * 2.6)
        let rect = CGRect(x: head.x - side / 2, y: head.y - radius - 3 - side, width: side, height: side)
        let plate = Path(roundedRect: rect, cornerRadius: 3)
        context.fill(plate, with: .color(Palette.ink))
        context.stroke(plate, with: .color(Palette.markerFill), lineWidth: 1.5)
        var glyph = context.resolve((state == .pullingIn ? MapGlyph.depotIn : MapGlyph.depotOut).image)
        glyph.shading = .color(Palette.markerFill)
        context.draw(glyph, in: rect.insetBy(dx: side * 0.14, dy: side * 0.14))
    }

    // MARK: - Weather (decision 182)

    /// Today's weather over the map (``MapWeather``) at `time` seconds: the
    /// map darkened by it, the rain falling and the lightning flashing
    /// unless `reduceMotion` (then only darkened, a little more), and a
    /// typhoon's sign beside each station it blows over (`typhoonStations`,
    /// their places on the screen).
    static func drawWeather(
        _ weather: MapWeather,
        time: Double,
        reduceMotion: Bool,
        typhoonStations: [ScreenPoint],
        stationRadius: Double,
        size: CGSize,
        in context: GraphicsContext
    ) {
        let screen = Path(CGRect(origin: .zero, size: size))
        let dimming = weather.dimming(reduceMotion: reduceMotion)
        if dimming > 0 { context.fill(screen, with: .color(Palette.weatherShade.opacity(dimming))) }
        if !reduceMotion {
            var rain = Path()
            for streak in weather.streaks(at: time, width: size.width, height: size.height) {
                rain.move(to: CGPoint(x: streak.x0, y: streak.y0))
                rain.addLine(to: CGPoint(x: streak.x1, y: streak.y1))
            }
            context.stroke(rain, with: .color(Palette.rain), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            let flash = weather.flash(at: time)
            if flash > 0 { context.fill(screen, with: .color(Palette.lightning.opacity(0.35 * flash))) }
        }
        // The sign on a pale disc edged in ink, up and to the right of the
        // station's badge, as the waiting count's pill is above it.
        let side = max(14, stationRadius * 1.4)
        var tinted = context.resolve(MapGlyph.typhoon.image)
        tinted.shading = .color(Palette.ink)
        for station in typhoonStations {
            let center = CGPoint(x: station.x + stationRadius * 1.1, y: station.y - stationRadius * 1.1)
            let badge = Path(ellipseIn: CGRect(x: center.x - side * 0.65, y: center.y - side * 0.65, width: side * 1.3, height: side * 1.3))
            guard badge.boundingRect.intersects(context.clipBoundingRect) else { continue }
            context.fill(badge, with: .color(Palette.land))
            context.stroke(badge, with: .color(Palette.ink), lineWidth: 1.5)
            context.draw(tinted, in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
        }
    }

    /// The radius of a station's badge on the map (``drawPointStation``).
    static func stationRadius(_ projection: some MapProjection) -> Double {
        max(5, projection.referenceSize * 0.32)
    }

    private static func trainPolyline(_ points: [TrainMotion.Point], projection: some MapProjection) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let screen = cgPoint(projection.screenPoint(worldX: point.x, worldY: point.y))
            if index == 0 { path.move(to: screen) } else { path.addLine(to: screen) }
        }
        return path
    }

    /// Decision 182: each station in view shines at night, a warm disc
    /// under its badge as strong as the night's `lights`.
    private static func drawStationLights(_ world: GameWorld, lights: Double, projection: some MapProjection, in context: GraphicsContext) {
        let radius = max(5, projection.referenceSize * 0.32) * 2.4
        var glow = Path()
        let bounds = context.clipBoundingRect.insetBy(dx: -radius, dy: -radius)
        for station in world.stations {
            let center = projection.screenPoint(of: station.location)
            guard bounds.contains(CGPoint(x: center.x, y: center.y)) else { continue }
            glow.addPath(disc(at: center, radius: radius))
        }
        context.fill(glow, with: .color(Palette.station.opacity(0.35 * lights)))
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
    /// than an authority: decision 205, a navy band cased in white (it was
    /// amber, the colour a line can have), red in a deadlock; and a dashed
    /// line from the waiting train's head to it.
    private static func drawWaits(_ traffic: TrafficOverlay, projection: some MapProjection, in context: GraphicsContext) {
        let width = authorityWidth(projection) * 1.3
        let region = drawingRegion(projection)
        for wait in traffic.waits {
            let color = wait.isDeadlocked ? Palette.metroRed : Palette.ink
            if wait.isDeadlocked {
                drawTrafficTrack(wait.contested, color: color, width: width, projection: projection, in: context)
            } else {
                drawTrafficTrack(wait.contested, color: color, width: width + 1, casing: Palette.markerFill, casingWidth: width + 4, projection: projection, in: context)
            }
            guard wait.from != wait.to, let reach = WorldRegion(enclosing: [wait.from, wait.to]), region.intersects(reach) else { continue }
            // Dashed, so drawn whole (see the tunnels in drawNetwork).
            let dash = max(3, projection.referenceSize * 0.3)
            context.stroke(wholePolyline([wait.from, wait.to], projection: projection), with: .color(color), style: StrokeStyle(lineWidth: max(1.5, projection.referenceSize * 0.08), lineCap: .butt, dash: [dash, dash * 0.6]))
        }
    }

    /// A ring round each waiting train's head, over the trains: decision
    /// 205, dashed navy on a white halo (a shape no line has; it was amber),
    /// solid red with a warning sign for a deadlocked one, beating as
    /// strong as `deadlock`.
    /// Rings that would overlap move apart across their track
    /// (``WaitMarkSides``, the `Railway/` site's `blockSideShift`).
    /// Decision 210: at most ``MapProblems/waitMarkLimit`` of them, the
    /// deadlocked first (``MapProblems/shownWaits(_:inView:)``); while the
    /// game runs a second ring grows out of each other one and fades as
    /// `pulse` goes from 0 to 1; and from a middle zoom in, the first
    /// ``MapProblems/waitTagLimit`` carry a tag beside them with why they
    /// wait and for which train, one that would cover another left out.
    static func drawWaitMarks(
        _ traffic: TrafficOverlay, deadlock: Double = 1, pulse: Double? = nil, language: DisplayLanguage = .english,
        projection: some MapProjection, in context: GraphicsContext
    ) {
        let region = drawingRegion(projection)
        let radius = trainHeadRadius(projection.referenceSize) + 6
        let shown = MapProblems.shownWaits(traffic.waits) { region.contains($0.from) }
        let marks = shown.map { wait in
            let center = projection.screenPoint(of: wait.from)
            // A step of a metre (64 units) the way the train faces.
            let length = (Double(wait.heading.dx) * Double(wait.heading.dx) + Double(wait.heading.dy) * Double(wait.heading.dy)).squareRoot()
            let scale = length > 0 ? 64 / length : 0
            let ahead = projection.screenPoint(
                worldX: Double(wait.from.x) + Double(wait.heading.dx) * scale,
                worldY: Double(wait.from.y) + Double(wait.heading.dy) * scale
            )
            return WaitMarkSides.Mark(train: wait.train, center: center, along: ScreenPoint(x: ahead.x - center.x, y: ahead.y - center.y))
        }
        // The ring and its 6-point halo.
        let offsets = WaitMarkSides.offsets(marks, size: radius * 2 + 6)
        let tags = MapProblems.level(referenceSize: projection.referenceSize) != .hidden
        var placement = MapProblems.Placement(limit: MapProblems.waitTagLimit)
        for (wait, placed) in zip(shown, marks) {
            var center = placed.center
            if let offset = offsets[wait.train] {
                center.x += offset.x
                center.y += offset.y
            }
            var context = context
            if wait.isDeadlocked { context.opacity = deadlock }
            if tags, !placement.isFull {
                drawWaitTag(wait, at: center, radius: radius, language: language, placement: &placement, in: context)
            }
            let ring = disc(at: center, radius: radius)
            if !wait.isDeadlocked, let pulse {
                context.stroke(disc(at: center, radius: radius + 9 * pulse), with: .color(Palette.ink.opacity(0.7 * (1 - pulse))), lineWidth: 1.5)
            }
            context.stroke(ring, with: .color(Palette.markerFill), lineWidth: 6)
            guard wait.isDeadlocked else {
                context.stroke(ring, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3, dash: [4.5, 3]))
                continue
            }
            context.stroke(ring, with: .color(Palette.metroRed), lineWidth: 3)
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

    /// Decision 210: why a waiting train waits, on a white plate edged in
    /// navy (red for a deadlock) to the right of its ring: "等交會 · 莒光 3".
    private static func drawWaitTag(
        _ wait: TrafficOverlay.Wait, at center: ScreenPoint, radius: Double, language: DisplayLanguage,
        placement: inout MapProblems.Placement, in context: GraphicsContext
    ) {
        let text = context.resolve(
            Text(verbatim: wait.reason.tag(holder: wait.holderName, in: language))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.ink)
        )
        let size = text.measure(in: CGSize(width: 240, height: 40))
        let plate = CGRect(x: center.x + radius + 5, y: center.y - size.height / 2 - 1.5, width: size.width + 8, height: size.height + 3)
        guard plate.intersects(context.clipBoundingRect),
              placement.place(.init(x: plate.minX, y: plate.minY, width: plate.width, height: plate.height)) else { return }
        let path = Path(roundedRect: plate, cornerRadius: 3)
        context.fill(path, with: .color(Palette.markerFill))
        context.stroke(path, with: .color(wait.isDeadlocked ? Palette.metroRed : Palette.ink), lineWidth: 1.2)
        context.draw(text, at: CGPoint(x: plate.minX + 4, y: center.y), anchor: .leading)
    }

    private static func drawTrafficTrack(
        _ track: TrafficOverlay.Track, color: Color, width: Double,
        casing: Color = Palette.followCase, casingWidth: Double? = nil,
        projection: some MapProjection, in context: GraphicsContext
    ) {
        let region = drawingRegion(projection)
        let full = projection.detail == .full
        for line in track.lines where line.count > 1 {
            let path = polyline(line, projection: projection)
            if full {
                context.stroke(path, with: .color(casing), style: StrokeStyle(lineWidth: casingWidth ?? width * 8.5 / 4.4, lineCap: .round, lineJoin: .round))
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
        if detail == .full {
            drawSlopes(edges.flatMap(\.slopes), projection: projection, in: context)
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

    /// Decision 124, H3 (``TrackSlope``): beside an embankment or a
    /// cutting, a band as wide as its slopes run, and hachures across it,
    /// under the track; the bank's colour for a fill, a deeper earth for a
    /// cut. One fill and one stroke a kind.
    private static func drawSlopes(_ slopes: [TrackSlope], projection: some MapProjection, in context: GraphicsContext) {
        guard !slopes.isEmpty else { return }
        var bands: [TrackSectionKind: Path] = [:], hachures: [TrackSectionKind: Path] = [:]
        for slope in slopes {
            for band in slope.bands {
                bands[slope.kind, default: Path()].addPath(polygon(band.map { screenPoint($0.x, $0.y, projection) }))
            }
            for hachure in slope.hachures {
                hachures[slope.kind, default: Path()].move(to: screenPoint(hachure.from.x, hachure.from.y, projection))
                hachures[slope.kind, default: Path()].addLine(to: screenPoint(hachure.to.x, hachure.to.y, projection))
            }
        }
        let width = max(0.5, projection.referenceSize * 0.03)
        for kind in [TrackSectionKind.embankment, .cutting] {
            let color = kind == .embankment ? Palette.embankment : Palette.cutting
            if let band = bands[kind] { context.fill(band, with: .color(color.opacity(0.4))) }
            if let lines = hachures[kind] { context.stroke(lines, with: .color(color), lineWidth: width) }
        }
    }

    /// Decision 213: the real lines the network tool can trace, as thin
    /// navy dashes (ink: light on a dark map), so they read as neither the
    /// player's track (turquoise) nor a line's colour; the stretch it would
    /// trace now lit by a wide soft navy band, under the stretch's preview.
    private static func drawTraceableLines(_ overlay: NetworkOverlay, projection: some MapProjection, in context: GraphicsContext) {
        // Cut to the view (a real line runs hundreds of kilometres, too many
        // dashes to draw whole when close in): a dash may shift a little
        // as a bend comes into the view's margin.
        let dash = StrokeStyle(lineWidth: 1.6, lineCap: .butt, lineJoin: .round, dash: [6, 4])
        for line in overlay.traceable {
            context.stroke(polyline(line, projection: projection), with: .color(Palette.ink.opacity(0.75)), style: dash)
        }
        if overlay.tracedWay.count > 1 {
            let way = polyline(overlay.tracedWay, projection: projection)
            context.stroke(way, with: .color(Palette.ink.opacity(0.28)), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
            context.stroke(way, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
        }
    }

    private static func drawNetworkOverlay(_ overlay: NetworkOverlay, projection: some MapProjection, in context: GraphicsContext) {
        let referenceSize = projection.referenceSize
        // Decision 285: a platform on the track beside too.
        for highlight in [overlay.highlight, overlay.besideHighlight] where highlight.count > 1 {
            let band = polyline(highlight, projection: projection)
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
        // The next stretch, and an X crossover's mirrored diagonal (or a
        // double track's parallel) and the double track's crossovers.
        // Decision 213: the rest of a traced stretch after it stops, as a
        // stretch that cannot be built.
        if overlay.unbuilt.count > 1 {
            let width = max(2, referenceSize * 0.12)
            context.stroke(wholePolyline(overlay.unbuilt, projection: projection), with: .color(Color.gray), style: StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round, dash: [max(2, referenceSize * 0.25), max(2, referenceSize * 0.2)]))
        }
        for points in [overlay.preview, overlay.crossing] + overlay.crossovers where points.count > 1 {
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
            context.stroke(line, with: .color(Palette.track), style: StrokeStyle(lineWidth: trackWidth(referenceSize), lineCap: .round, lineJoin: .round))
            context.stroke(line, with: .color(Palette.trackCentre), style: centre)
        case (.elevated, .full), (.bridge, .full):
            // The casing stays as much wider than the bed as it was.
            context.stroke(line, with: .color(Palette.ink.opacity(0.35)), style: StrokeStyle(lineWidth: trackWidth(referenceSize) * 0.58 / 0.42, lineCap: .butt, lineJoin: .round))
            context.stroke(line, with: .color(Palette.track), style: StrokeStyle(lineWidth: trackWidth(referenceSize), lineCap: .butt, lineJoin: .round))
            context.stroke(line, with: .color(Palette.trackCentre), style: centre)
        }
    }

    // MARK: - Lines and transfer groups (decision 84)

    /// The width of a line drawn on the track; lines sharing track sit
    /// this far apart, touching, as MapBuilder's 8 px lines do.
    private static func lineWidth(_ projection: some MapProjection) -> Double {
        // Decision 195: as much narrower than the bed as it was, so the
        // bed still shows either side of the line near true width.
        projection.detail == .full ? max(2.5, trackWidth(projection.referenceSize) * 0.22 / 0.42) : max(2, projection.referenceSize * 0.16)
    }

    // MARK: - Near true widths (decision 195)

    /// Zoomed in from this size (points for ``MapScale/referenceLength``,
    /// 16 m; the phone's default is 32, the most 64), the track and the
    /// trains narrow towards their true widths, so the two tracks of a
    /// double line (4–5 m apart) stand apart...
    static let trueWidthFromSize = 32.0
    /// ...and from this size on they are drawn at them; in between they
    /// narrow in a straight line, so no zoom makes them jump.
    static let trueWidthAtSize = 48.0
    /// The track's bed, in shares of 16 m: 6.72 m as drawn below
    /// ``trueWidthFromSize``, 3.52 m (a standard-gauge track's sleepers
    /// and ballast shoulder, about 3.5 m) from ``trueWidthAtSize``.
    static let trackWidthShare = (drawn: 0.42, near: 0.22)
    /// A train's body: 4.8 m, then 3.2 m (a Taiwanese car is 2.9–3.4 m
    /// wide).
    static let trainWidthShare = (drawn: 0.30, near: 0.20)

    /// How far towards true widths the map is drawn at `referenceSize`: 0
    /// up to ``trueWidthFromSize``, 1 from ``trueWidthAtSize``.
    static func nearTrue(_ referenceSize: Double) -> Double {
        min(max((referenceSize - trueWidthFromSize) / (trueWidthAtSize - trueWidthFromSize), 0), 1)
    }

    /// The track's bed in full detail, in points.
    static func trackWidth(_ referenceSize: Double) -> Double {
        let share = trackWidthShare.drawn + (trackWidthShare.near - trackWidthShare.drawn) * nearTrue(referenceSize)
        return referenceSize * share
    }

    /// A train's body in full detail, in points.
    static func trainWidth(_ referenceSize: Double) -> Double {
        let share = trainWidthShare.drawn + (trainWidthShare.near - trainWidthShare.drawn) * nearTrue(referenceSize)
        return referenceSize * share
    }

    /// How much narrower a train is drawn than below ``trueWidthFromSize``:
    /// its head and nose narrow with its body.
    static func trainNearTrueScale(_ referenceSize: Double) -> Double {
        referenceSize > 0 ? trainWidth(referenceSize) / (referenceSize * trainWidthShare.drawn) : 1
    }

    /// The radius of a train's head (and of its light and wait ring).
    static func trainHeadRadius(_ referenceSize: Double) -> Double {
        max(2.5, referenceSize * 0.26 * trainNearTrueScale(referenceSize))
    }

    /// Each line in its colour along the track its trains take, side by
    /// side where lines share it (``LineMap``, MapBuilder's
    /// `js-Map-segments--solid`: butt caps, each line its offset out); in
    /// a tunnel, faded as the track is. Decision 168: a high-speed line has
    /// a navy casing, drawn under every line, so it reads as the heavier
    /// line of the network (the app icon's thick navy outline) without
    /// moving the lines beside it. Decision 249: a line ridden one way only
    /// beside its track on the left of that way, so a double track's two
    /// ways stand apart with the beds between them; many lines on a track
    /// narrower; and the arrows once on the track, not across the lines.
    private static func drawLines(_ lines: LineMap, world: GameWorld, projection: some MapProjection, cached: [TrackEdgeID: MapEdgeDrawing], codes: [LineID: String] = [:], in context: GraphicsContext) {
        guard !lines.stretches.isEmpty else { return }
        let region = drawingRegion(projection)
        let width = lineWidth(projection)
        var drawings: [TrackEdgeID: MapEdgeDrawing] = [:]
        var drawn: [(path: Path, color: Color, width: Double, isHighSpeed: Bool, inTunnel: Bool)] = []
        // Decision 216: each line's longest piece on the screen, for its
        // badge (layer 24.5).
        var longest: [LineID: (points: [CGPoint], length: Double, color: Color)] = [:]
        let view = context.clipBoundingRect
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
            drawn.append((path, color, stretch.width * width, stretch.isHighSpeed, inTunnel))
            if !codes.isEmpty, !inTunnel {
                let shifted = offsetPoints(points, by: stretch.offset * width).filter { view.contains($0) }
                let length = polylineLength(shifted)
                if length > (longest[stretch.line]?.length ?? 0) {
                    longest[stretch.line] = (shifted, length, color)
                }
            }
        }
        for stretch in drawn where stretch.isHighSpeed {
            context.stroke(
                stretch.path, with: .color(stretch.inTunnel ? Palette.ink.opacity(0.5) : Palette.ink),
                style: StrokeStyle(lineWidth: stretch.width + max(4, stretch.width * 0.9), lineCap: .butt, lineJoin: .round)
            )
        }
        for stretch in drawn {
            context.stroke(
                stretch.path, with: .color(stretch.inTunnel ? stretch.color.opacity(0.5) : stretch.color),
                style: StrokeStyle(lineWidth: stretch.width, lineCap: .butt, lineJoin: .round)
            )
        }
        drawRibbonBadges(longest, codes: codes, height: projection.detail == .full ? 14 : 12, in: context)
        guard projection.detail == .full else { return }
        // Decision 201: where a track's lines run one way only, arrows that
        // way, on the track (decision 249).
        let arrowView = view.insetBy(dx: -width * 2, dy: -width * 2)
        let spacing = max(72, width * 16)
        for oneWay in lines.oneWay {
            guard let drawing = drawings[oneWay.edge], region.intersects(drawing.bounds) else { continue }
            let end = min(oneWay.end, drawing.geometry.length)
            guard oneWay.start < end else { continue }
            let points = drawing.geometry.points(from: oneWay.start, to: end).map { projection.screenPoint(of: $0) }
            for mark in PolylineMarks.marks(along: points, spacing: spacing, limit: 60) {
                let point = cgPoint(mark.point)
                guard arrowView.contains(point) else { continue }
                drawArrow(at: point, angle: mark.angle + (oneWay.way == .backward ? .pi : 0), size: width * LineMap.arrowSize, in: context)
            }
        }
    }

    // MARK: - Route preview and track numbers (decision 201)

    /// An arrowhead pointing at `angle` (radians from the screen's x axis):
    /// the site's `drawArrowAt` (`Railway/site_archive_clean/index.html`),
    /// its tip `size` ahead and its back corners 0.55 `size` behind and
    /// 0.95 `size` either side, white with a navy edge so it reads on any
    /// line's colour, as the transfer links do.
    private static func drawArrow(at point: CGPoint, angle: Double, size: Double, in context: GraphicsContext) {
        let c = cos(angle), n = sin(angle)
        func corner(_ along: Double, _ across: Double) -> CGPoint {
            CGPoint(x: point.x + c * along - n * across, y: point.y + n * along + c * across)
        }
        var arrow = Path()
        arrow.move(to: corner(size, 0))
        arrow.addLine(to: corner(-0.55 * size, 0.95 * size))
        arrow.addLine(to: corner(-0.55 * size, -0.95 * size))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(Palette.transferLink))
        context.stroke(arrow, with: .color(Palette.transferEdge), style: StrokeStyle(lineWidth: max(1, size * 0.25), lineJoin: .round))
    }

    /// The pieces of `preview` on the screen, each in the way its trains
    /// drive it, with its edge.
    private static func previewPolylines(
        _ preview: RoutePreview, world: GameWorld, projection: some MapProjection, cached: [TrackEdgeID: MapEdgeDrawing]
    ) -> [(edge: TrackEdgeID, points: [ScreenPoint])] {
        preview.pieces.compactMap { piece in
            guard let drawing = cached[piece.edge] ?? world.network.edge(piece.edge).flatMap({ MapEdgeDrawing(edge: $0, world: world) }) else { return nil }
            let end = min(piece.end, drawing.geometry.length)
            guard piece.start < end else { return nil }
            let points = drawing.geometry.points(from: piece.start, to: end).map { projection.screenPoint(of: $0) }
            return (edge: piece.edge, points: piece.isForward ? points : Array(points.reversed()))
        }
    }

    /// Decision 201: the leg the line panel shows, as the site outlines a
    /// followed train's route (`followLayers` in
    /// `Railway/site_archive_clean/data/track_style_layers.json`: a pale
    /// casing under the line's colour, 8.5 and 4.4 px), here wider than
    /// the line's own colour so it stands out over it, with arrows the way
    /// the trains go.
    private static func drawRoutePreview(
        _ preview: RoutePreview, world: GameWorld, projection: some MapProjection, cached: [TrackEdgeID: MapEdgeDrawing], in context: GraphicsContext
    ) {
        let pieces = previewPolylines(preview, world: world, projection: projection, cached: cached)
        guard !pieces.isEmpty else { return }
        let width = lineWidth(projection) * 1.4
        var path = Path()
        for piece in pieces {
            guard let first = piece.points.first else { continue }
            path.move(to: cgPoint(first))
            for point in piece.points.dropFirst() { path.addLine(to: cgPoint(point)) }
        }
        let color = Palette.lineColor(preview.request.line, custom: preview.color)
        context.stroke(path, with: .color(Palette.followCase), style: StrokeStyle(lineWidth: width * 8.5 / 4.4, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        let view = context.clipBoundingRect.insetBy(dx: -width * 2, dy: -width * 2)
        let spacing = max(40, width * 9)
        for mark in PolylineMarks.marks(along: pieces.flatMap { $0.points }, spacing: spacing, limit: 150) {
            let point = cgPoint(mark.point)
            guard view.contains(point) else { continue }
            drawArrow(at: point, angle: mark.angle, size: width * 0.85, in: context)
        }
    }

    /// From this size (points for ``MapScale/referenceLength``; the phone
    /// opens at 32) every track in view shows its number; less close only
    /// the previewed leg's do, so the map is not crowded.
    static let trackNumbersFromSize = 44.0
    /// A track shorter than this on the screen, in points, is not numbered
    /// when every track is.
    private static let trackNumberMinimumLength = 64.0
    /// The most numbers drawn at once.
    private static let trackNumberLimit = 80

    /// Decision 201: each track's number ("#7"), the one the line panel's
    /// routes and the select tool use, at its middle. The previewed leg's
    /// tracks always, on navy plates beside the path; zoomed in from
    /// ``trackNumbersFromSize``, every track in view, on pale plates. A
    /// number that would cover one already drawn is left out.
    private static func drawTrackNumbers(
        _ world: GameWorld, preview: RoutePreview?, projection: some MapProjection, cached: [TrackEdgeID: MapEdgeDrawing], in context: GraphicsContext
    ) {
        let view = context.clipBoundingRect
        var placed: [CGRect] = []
        var numbered = Set<TrackEdgeID>()
        func plate(_ edge: TrackEdgeID, at mark: PolylineMarks.Mark, beside distance: Double, strong: Bool) {
            guard placed.count < trackNumberLimit else { return }
            let point = cgPoint(PolylineMarks.shifted(mark, by: distance).point)
            let text = context.resolve(
                Text(verbatim: RoutePreview.label(of: edge))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(strong ? Palette.land : Palette.ink)
            )
            let size = text.measure(in: CGSize(width: 120, height: 40))
            let rect = CGRect(x: point.x - size.width / 2 - 4, y: point.y - size.height / 2 - 1, width: size.width + 8, height: size.height + 2)
            guard rect.intersects(view), !placed.contains(where: { $0.intersects(rect) }) else { return }
            placed.append(rect)
            let shape = Path(roundedRect: rect, cornerRadius: rect.height / 2)
            context.fill(shape, with: .color(strong ? Palette.ink : Palette.land.opacity(0.92)))
            context.stroke(shape, with: .color(strong ? Palette.land : Palette.ink), lineWidth: 1)
            context.draw(text, at: point, anchor: .center)
        }
        if let preview {
            let beside = lineWidth(projection) * 1.4 * 8.5 / 4.4 / 2 + 10
            for piece in previewPolylines(preview, world: world, projection: projection, cached: cached) where !numbered.contains(piece.edge) {
                guard let middle = PolylineMarks.middle(of: piece.points) else { continue }
                numbered.insert(piece.edge)
                plate(piece.edge, at: middle, beside: beside, strong: true)
            }
        }
        guard projection.detail == .full, projection.referenceSize >= trackNumbersFromSize else { return }
        let region = drawingRegion(projection)
        let beside = trackWidth(projection.referenceSize) / 2 + 9
        for edge in world.network.edges where !numbered.contains(edge.id) {
            guard let drawing = cached[edge.id] ?? MapEdgeDrawing(edge: edge, world: world), region.intersects(drawing.bounds) else { continue }
            let points = drawing.geometry.points.map { projection.screenPoint(of: $0) }
            guard PolylineMarks.length(of: points) >= trackNumberMinimumLength, let middle = PolylineMarks.middle(of: points) else { continue }
            plate(edge.id, at: middle, beside: beside, strong: false)
        }
    }

    /// Decision 178: the passenger load layer. Each section of track in the
    /// shown hour as a line as wide as its riders (2 to 10 points) and as
    /// dark as its trains are full, red over capacity, in place of the lines'
    /// colours; the two ways of a track are drawn side by side, each on the
    /// left of the way it is ridden, so they never cover each other.
    private static func drawSectionFlow(_ strokes: [SectionFlow.Stroke], world: GameWorld, projection: some MapProjection, cached: [TrackEdgeID: MapEdgeDrawing], in context: GraphicsContext) {
        let region = drawingRegion(projection)
        var drawings: [TrackEdgeID: MapEdgeDrawing] = [:]
        for stroke in strokes {
            let width = projection.detail == .full ? stroke.width : max(1.5, stroke.width * 0.6)
            let color = Color(stroke.color)
            for piece in stroke.pieces {
                guard let drawing = drawings[piece.edge] ?? cached[piece.edge] ?? world.network.edge(piece.edge).flatMap({ MapEdgeDrawing(edge: $0, world: world) }) else { continue }
                drawings[piece.edge] = drawing
                guard region.intersects(drawing.bounds) else { continue }
                let end = min(piece.end, drawing.geometry.length)
                guard piece.start < end else { continue }
                let points = drawing.geometry.points(from: piece.start, to: end).map { cgPoint(projection.screenPoint(of: $0)) }
                // The left of the way it is ridden: the edge's own left when
                // ridden forward, its right when ridden backward.
                let path = offsetPolyline(points, by: (piece.forward ? 1 : -1) * width / 2)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round))
            }
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

    /// Decision 220: the journey trace. An arc from the held station to
    /// each of its busiest pairs (``JourneyTrace``), or between the busiest
    /// pairs of a held line's stops (decision 276), navy on a white edge,
    /// as wide as its trips, the narrowest drawn first so the busiest lies
    /// on top; drawn out from the station as `progress` goes to 1. Once
    /// whole, each arc's trips on a white plate edged in navy halfway
    /// along it, left out where it would cover one already written.
    private static func drawJourneyTrace(
        _ trace: JourneyTrace, world: GameWorld, progress: Double, projection: some MapProjection, in context: GraphicsContext
    ) {
        // Each arc from its own start: the traced station, or for a line's
        // trace (decision 276) the earlier of its pair of stops.
        let curves: [(arc: JourneyTrace.Arc, origin: ScreenPoint, end: ScreenPoint)] = trace.arcs.compactMap { arc in
            guard let from = world.station(id: arc.from), let to = world.station(id: arc.station) else { return nil }
            return (arc: arc, origin: projection.screenPoint(of: from.location), end: projection.screenPoint(of: to.location))
        }
        let share = min(1, max(0, progress))
        for (arc, origin, end) in curves.reversed() {
            var path = Path()
            path.move(to: cgPoint(origin))
            path.addQuadCurve(to: cgPoint(end), control: cgPoint(JourneyTrace.control(from: origin, to: end)))
            let shown = share < 1 ? path.trimmedPath(from: 0, to: share) : path
            guard shown.boundingRect.insetBy(dx: -arc.width - 3, dy: -arc.width - 3).intersects(context.clipBoundingRect) else { continue }
            context.stroke(shown, with: .color(Palette.journeyCase), style: StrokeStyle(lineWidth: arc.width + 3, lineCap: .round))
            context.stroke(shown, with: .color(Palette.journeyArc), style: StrokeStyle(lineWidth: arc.width, lineCap: .round))
        }
        guard share >= 1 else { return }
        let view = context.clipBoundingRect
        var placed: [CGRect] = []
        for (arc, origin, end) in curves {
            let point = cgPoint(JourneyTrace.apex(from: origin, to: end))
            let text = context.resolve(
                Text(verbatim: JourneyTrace.tripsText(arc))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
            )
            let size = text.measure(in: CGSize(width: 120, height: 40))
            let rect = CGRect(x: point.x - size.width / 2 - 4, y: point.y - size.height / 2 - 1, width: size.width + 8, height: size.height + 2)
            guard rect.intersects(view), !placed.contains(where: { $0.intersects(rect) }) else { continue }
            placed.append(rect)
            let plate = Path(roundedRect: rect, cornerRadius: rect.height / 2)
            context.fill(plate, with: .color(Palette.markerFill))
            context.stroke(plate, with: .color(Palette.ink), lineWidth: 1)
            context.draw(text, at: point, anchor: .center)
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

    /// A train's head zoomed out: a dot (close up its cars are drawn
    /// instead, ``drawCars``, decision 205). Decision 168: a high-speed set's head is an arrow along that
    /// way instead, so that it reads as another kind of train at a glance
    /// (and in grey: the shape is the difference, not the colour).
    private static func drawTrain(
        at position: TrainMotion.Point, heading: TrainMotion.Point, colour: Color,
        isSelected: Bool, isHighSpeed: Bool, projection: some MapProjection, in context: GraphicsContext
    ) {
        let center = projection.screenPoint(worldX: position.x, worldY: position.y)
        let radius = trainHeadRadius(projection.referenceSize)
        let dx = heading.x, dy = heading.y
        let length = (dx * dx + dy * dy).squareRoot()
        // A point ahead of the train, on the screen.
        var ahead: CGPoint?
        if length > 0 {
            let distance = radius * 1.7 / projection.pointsPerUnit
            ahead = cgPoint(projection.screenPoint(worldX: position.x + dx / length * distance, worldY: position.y + dy / length * distance))
        }
        var head = disc(at: center, radius: radius)
        if isHighSpeed, let ahead {
            let from = cgPoint(center)
            let along = CGVector(dx: ahead.x - from.x, dy: ahead.y - from.y)
            let size = (along.dx * along.dx + along.dy * along.dy).squareRoot()
            if size > 0 {
                let ux = along.dx / size, uy = along.dy / size
                let tip = CGPoint(x: from.x + ux * radius * 2, y: from.y + uy * radius * 2)
                let back = CGPoint(x: from.x - ux * radius, y: from.y - uy * radius)
                let left = CGPoint(x: back.x - uy * radius * 1.2, y: back.y + ux * radius * 1.2)
                let right = CGPoint(x: back.x + uy * radius * 1.2, y: back.y - ux * radius * 1.2)
                head = polygon([tip, left, right])
            }
        }
        // Decision 205: edged in navy, as its body; selected, a warm yellow
        // edge inside a navy line (both were the system's background and
        // the track's teal).
        if isSelected {
            context.stroke(head, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 8, lineJoin: .round))
            context.stroke(head, with: .color(Palette.trainSelection), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
        }
        context.fill(head, with: .color(colour))
        context.stroke(head, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    /// Decision 304: the real lines' trains, each a short capsule along its
    /// way in its line's colour, fainter and smaller than the player's
    /// trains (``RealTrainTraffic/look``), edged in a light trace of
    /// ``Palette/ink``.
    static func drawRealTrains(_ dots: some Sequence<RealTrainDot>, projection: some MapProjection, in context: GraphicsContext) {
        let look = RealTrainTraffic.look
        let radius = trainHeadRadius(projection.referenceSize) * look.sizeShare
        let half = radius * look.lengthShare, side = radius
        for dot in dots {
            let center = projection.screenPoint(worldX: dot.x, worldY: dot.y)
            // The screen is north up, as the world: its heading as it is.
            let ux = dot.headingX, uy = dot.headingY
            let body = Path(
                roundedRect: CGRect(x: -half - side, y: -side, width: 2 * (half + side), height: 2 * side), cornerRadius: side
            ).applying(CGAffineTransform(translationX: center.x, y: center.y).rotated(by: atan2(uy, ux)))
            let colour = Color(red: Double(dot.color.red) / 255, green: Double(dot.color.green) / 255, blue: Double(dot.color.blue) / 255)
            context.fill(body, with: .color(colour.opacity(look.opacity)))
            context.stroke(body, with: .color(Palette.ink.opacity(look.edgeOpacity)), lineWidth: look.edgeWidth)
        }
    }

    /// Decision 205: a train close up, car by car (``TrainCars``), each car
    /// in its colour with a navy joint between, the whole cased in
    /// ``Palette/ink`` and the leading car's nose its model's shape
    /// (decision 243: pointed for a high-speed set, decision 168, round or
    /// flat). The nose is its head: no dot. Selected, a warm yellow edge
    /// inside a navy line round it, where the selection was the track's
    /// teal. Painted (decision 243), a model's cars are its body's colour
    /// with a band of the line's `colour` edged in navy along them, and its
    /// nose its cab's colour; a train of no model is all its line's colour.
    private static func drawCars(
        _ cars: [[TrainMotion.Point]], colour: Color, livery: TrainLivery, painted: Bool, isSelected: Bool,
        projection: some MapProjection, in context: GraphicsContext
    ) {
        guard let leading = cars.first, leading.count > 1 else { return }
        let width = max(3, trainWidth(projection.referenceSize))
        // The nose's shape stands on the first car, this far back from its
        // front, in world units.
        let noseLength = switch livery.nose {
        case .pointed: width * 1.2 / projection.pointsPerUnit
        case .round: width / 2 / projection.pointsPerUnit
        case .flat: width / 4 / projection.pointsPerUnit
        }
        let front = TrainMotion.Trail(leading)
        guard let tip = front.point(at: 0), let base = front.point(at: noseLength),
              let along = front.direction(at: noseLength) else { return }
        let shortened = [front.points(from: noseLength, to: front.length)] + cars.dropFirst()
        var whole = Path()
        for (index, car) in shortened.enumerated() {
            for (step, point) in car.enumerated() {
                let screen = cgPoint(projection.screenPoint(worldX: point.x, worldY: point.y))
                if index == 0, step == 0 { whole.move(to: screen) } else { whole.addLine(to: screen) }
            }
        }
        let tipPoint = cgPoint(projection.screenPoint(worldX: tip.x, worldY: tip.y))
        let basePoint = cgPoint(projection.screenPoint(worldX: base.x, worldY: base.y))
        // Across the train, on the screen, half a body wide.
        let ahead = projection.screenPoint(worldX: base.x + along.x, worldY: base.y + along.y)
        var across = CGVector(dx: -(ahead.y - basePoint.y), dy: ahead.x - basePoint.x)
        let size = (across.dx * across.dx + across.dy * across.dy).squareRoot()
        across = size > 0 ? CGVector(dx: across.dx / size * width / 2, dy: across.dy / size * width / 2) : .zero
        let nose: Path = switch livery.nose {
        case .pointed:
            polygon([tipPoint, CGPoint(x: basePoint.x + across.dx, y: basePoint.y + across.dy), CGPoint(x: basePoint.x - across.dx, y: basePoint.y - across.dy)])
        case .round:
            Path(ellipseIn: CGRect(x: basePoint.x - width / 2, y: basePoint.y - width / 2, width: width, height: width))
        case .flat:
            polygon([
                CGPoint(x: basePoint.x + across.dx, y: basePoint.y + across.dy), CGPoint(x: tipPoint.x + across.dx, y: tipPoint.y + across.dy),
                CGPoint(x: tipPoint.x - across.dx, y: tipPoint.y - across.dy), CGPoint(x: basePoint.x - across.dx, y: basePoint.y - across.dy),
            ])
        }
        let body = painted ? livery.body.map(Palette.rgb) : nil
        // The way the tail ends, on the screen, so each casing squares it off
        // half its own extra width beyond the last car.
        let tail = TrainMotion.Trail(shortened.last ?? leading)
        let tailEnd = tail.point(at: tail.length).map { cgPoint(projection.screenPoint(worldX: $0.x, worldY: $0.y)) }
        let tailLead = tail.point(at: tail.length - 1).map { cgPoint(projection.screenPoint(worldX: $0.x, worldY: $0.y)) }
        func outline(_ extra: Double, _ colour: Color) {
            context.stroke(whole, with: .color(colour), style: StrokeStyle(lineWidth: width + extra, lineCap: .butt, lineJoin: .round))
            context.fill(nose, with: .color(colour))
            context.stroke(nose, with: .color(colour), style: StrokeStyle(lineWidth: extra, lineJoin: .round))
            guard let end = tailEnd, let lead = tailLead else { return }
            let span = max(hypot(end.x - lead.x, end.y - lead.y), 0.001)
            var cap = Path()
            cap.move(to: end)
            cap.addLine(to: CGPoint(x: end.x + (end.x - lead.x) / span * extra / 2, y: end.y + (end.y - lead.y) / span * extra / 2))
            context.stroke(cap, with: .color(colour), style: StrokeStyle(lineWidth: width + extra, lineCap: .butt))
        }
        if isSelected {
            outline(9, Palette.ink)
            outline(7, Palette.trainSelection)
        }
        outline(3, Palette.ink)
        // Each car, leaving a navy joint before the next.
        let joint = 1.5 / projection.pointsPerUnit
        for (index, car) in shortened.enumerated() {
            let trail = TrainMotion.Trail(car)
            let kept = trainPolyline(trail.points(from: 0, to: trail.length - (index == shortened.count - 1 ? 0 : joint)), projection: projection)
            context.stroke(kept, with: .color(body ?? colour), style: StrokeStyle(lineWidth: width, lineCap: .butt, lineJoin: .round))
            guard body != nil else { continue }
            // Decision 243: the line's band, edged in navy so that a pale
            // line colour still shows on a white or silver body.
            context.stroke(kept, with: .color(Palette.liveryBandEdge), style: StrokeStyle(lineWidth: width * 0.4 + 1, lineCap: .butt, lineJoin: .round))
            context.stroke(kept, with: .color(colour), style: StrokeStyle(lineWidth: width * 0.4, lineCap: .butt, lineJoin: .round))
        }
        context.fill(nose, with: .color(body == nil ? colour : livery.cab.map(Palette.rgb) ?? colour))
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
        growth: (SkylineGrowth, elapsed: Double)?,
        growthOnly: Bool,
        layer: PopTravelLayer?,
        lights: Double = 0,
        streets: SeededStreetPlan? = nil,
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
        // Decision 270: under the town, its seeded streets.
        if let streets { drawStreets(streets, projection: projection, in: context) }
        if let skyline, !growthOnly {
            drawSkyline(skyline, growth: growth, growthOnly: false, lights: lights, projection: projection, in: context)
        } else if let skyline, let growth {
            // Decision 140: a real-world map's own houses stand under it;
            // only what grew is drawn, fading out once it has risen.
            var faded = context
            faded.opacity = SkylineGrowth.shown(elapsed: growth.elapsed)
            drawSkyline(skyline, growth: growth, growthOnly: true, projection: projection, in: faded)
        }
        guard let layer else { return }
        switch layer.content {
        case .population(let heatmap):
            drawPopulation(heatmap, opacity: layer.opacity, projection: projection, in: context)
        case .travel(let tiles):
            drawTravel(tiles, opacity: layer.opacity, projection: projection, in: context)
        case .city(let map, let mode):
            drawCity(map, mode: mode, opacity: layer.opacity, projection: projection, in: context)
        case .terrain(let map):
            drawTerrain(map, opacity: layer.opacity, projection: projection, in: context)
        }
    }

    /// The height and steep slope layer (decision 124, H3, ``TerrainMap``):
    /// the blocks in view, tinted and shaded, merged when zoomed out as the
    /// city's are; then the steep ones hatched, lines falling to the right
    /// about 6 points apart, so the hatching runs on across blocks.
    private static func drawTerrain(_ map: TerrainMap, opacity: Double, projection: some MapProjection, in context: GraphicsContext) {
        let blockSize = CityMap.blockSize(pointsPerUnit: projection.pointsPerUnit)
        let tiles = map.tiles(in: drawingRegion(projection), blockSize: blockSize)
        drawTravel(tiles.shaded, opacity: opacity, projection: projection, in: context)
        guard !tiles.steep.isEmpty else { return }
        let spacing = 6.0
        var hatching = Path()
        for tile in tiles.steep {
            let rect = screenRect(minX: tile.minX, minY: tile.minY, maxX: tile.maxX, maxY: tile.maxY, projection)
            // The lines x + y = c, at every multiple of the spacing across
            // the block, cut to it.
            let low = ((rect.minX + rect.minY) / spacing).rounded(.up), high = ((rect.maxX + rect.maxY) / spacing).rounded(.down)
            guard low <= high else { continue }
            for k in Int(low)...Int(high) {
                let c = Double(k) * spacing
                let start = CGPoint(x: max(rect.minX, c - rect.maxY), y: min(rect.maxY, c - rect.minX))
                let end = CGPoint(x: min(rect.maxX, c - rect.minY), y: max(rect.minY, c - rect.maxX))
                hatching.move(to: start)
                hatching.addLine(to: end)
            }
        }
        context.stroke(hatching, with: .color(Color(TerrainMap.steepColor).opacity(min(1, opacity))), lineWidth: 0.75)
    }

    /// A city layer (Phase 6d, ``CityMap``): only the cells in view, merged
    /// into blocks when zoomed out (``CityMap/blockSize(pointsPerUnit:)``),
    /// one fill a colour.
    private static func drawCity(_ map: CityMap, mode: PopTravelMode, opacity: Double, projection: some MapProjection, in context: GraphicsContext) {
        let blockSize = CityMap.blockSize(pointsPerUnit: projection.pointsPerUnit)
        drawTravel(map.tiles(for: mode, in: drawingRegion(projection), blockSize: blockSize), opacity: opacity, projection: projection, in: context)
    }

    /// Decision 311: where a station would have riders
    /// (``StationPotentialMap``), only the blocks in view, merged as the
    /// city's layers are, one fill a colour.
    static func drawPotential(_ map: StationPotentialMap, opacity: Double, projection: some MapProjection, in context: GraphicsContext) {
        let blockSize = CityMap.blockSize(pointsPerUnit: projection.pointsPerUnit)
        drawTravel(map.tiles(in: drawingRegion(projection), blockSize: blockSize), opacity: opacity, projection: projection, in: context)
    }

    /// Decision 270: from this many points a 64 m cell the seeded streets
    /// fade in, fully drawn from ``streetsFullCellPoints``.
    private static let streetsCellPoints = 16.0
    private static let streetsFullCellPoints = 24.0

    /// Decision 270: a blank map's seeded streets (decision 263), as the
    /// real map's 2D roads (decision 241): white over a pale casing, at
    /// their true width but never under a point; every casing first, then
    /// the fills, the larger roads last, so crossings join.
    private static func drawStreets(_ plan: SeededStreetPlan, projection: some MapProjection, in context: GraphicsContext) {
        let cellPoints = Double(Land.cellLength) * projection.pointsPerUnit
        guard !plan.isEmpty, cellPoints >= streetsCellPoints else { return }
        let roads = plan.roads(in: drawingRegion(projection))
        guard !roads.isEmpty else { return }
        var faded = context
        faded.opacity = min(1, (cellPoints - streetsCellPoints) / (streetsFullCellPoints - streetsCellPoints))
        let pointsPerMetre = Double(WorldCoordinate.unitsPerMetre) * projection.pointsPerUnit
        func path(_ road: SeededStreetPlan.Road) -> Path {
            var path = Path()
            path.move(to: screenPoint(Double(road.points[0].x), Double(road.points[0].y), projection))
            for point in road.points.dropFirst() { path.addLine(to: screenPoint(Double(point.x), Double(point.y), projection)) }
            return path
        }
        for road in roads {
            faded.stroke(path(road), with: .color(Palette.roadCasing),
                         style: StrokeStyle(lineWidth: max(1, road.width * pointsPerMetre) + 1.5, lineCap: .square))
        }
        for road in roads {
            faded.stroke(path(road), with: .color(road.major ? Palette.roadMajor : Palette.road),
                         style: StrokeStyle(lineWidth: max(1, road.width * pointsPerMetre), lineCap: .square))
        }
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
    /// points. While a night's `growth` plays (decision 140), the lots that
    /// grew are drawn as it says at `elapsed`: rising, a new one swelling
    /// to its size, its roof lit in the station's yellow; with `growthOnly`
    /// (a real-world map), only they are.
    private static func drawSkyline(
        _ skyline: CitySkyline,
        growth: (SkylineGrowth, elapsed: Double)?,
        growthOnly: Bool,
        lights: Double = 0,
        projection: some MapProjection,
        in context: GraphicsContext
    ) {
        let cellPoints = Double(Land.cellLength) * projection.pointsPerUnit
        guard !skyline.isEmpty, cellPoints >= skylineMinimumCellPoints else { return }
        let rises = cellPoints >= skylineRisingCellPoints
        let lots = skyline.lots(in: drawingRegion(projection), rowsBelow: rises ? CitySkyline.rowsRisenOver : 0)
        let length = Double(Land.cellLength)
        let lineWidth = cellPoints < 14 ? 0.6 : 1
        var ground: [LandUse: Path] = [:], walls: [LandUse: Path] = [:], roofs: [LandUse: Path] = [:], outlines = Path()
        var lit: [(roof: CGRect, light: Double)] = []
        // Decision 182: at night two lots in three have a lit window.
        var windows = Path()
        func drawRow() {
            for use in LandUse.allCases {
                if let path = ground[use] { context.fill(path, with: .color(Palette.cityRoof(use))) }
            }
            for use in LandUse.allCases {
                if let path = walls[use] { context.fill(path, with: .color(Palette.cityWall(use))) }
                if let path = roofs[use] { context.fill(path, with: .color(Palette.cityRoof(use))) }
            }
            for (roof, light) in lit {
                context.fill(Path(roof), with: .color(Palette.station.opacity(0.85 * light)))
            }
            context.stroke(outlines, with: .color(Palette.cityOutline), lineWidth: lineWidth)
            if lights > 0 { context.fill(windows, with: .color(Palette.station.opacity(lights))) }
            windows = Path()
            ground = [:]
            walls = [:]
            roofs = [:]
            outlines = Path()
            lit = []
        }
        var row = lots.first?.row
        for lot in lots {
            if lot.row != row {
                drawRow()
                row = lot.row
            }
            let frame = growth.flatMap { $0.0.frame(of: lot, elapsed: $0.elapsed) }
            if growthOnly, frame == nil { continue }
            let minX = Double(lot.column) * length, minY = Double(lot.row) * length
            if lot.isOpenGround {
                let rect = screenRect(minX: minX, minY: minY, maxX: minX + length, maxY: minY + length, projection)
                ground[lot.use, default: Path()].addRect(rect)
                continue
            }
            if let frame, !frame.isShown { continue }
            // Decision 142: each on its own square, its density's with the
            // city's footprints.
            let drawnSide = Double(lot.side) * (frame?.sideShare ?? 1), drawnInset = (length - drawnSide) / 2
            let foot = screenRect(
                minX: minX + drawnInset, minY: minY + drawnInset,
                maxX: minX + drawnInset + drawnSide, maxY: minY + drawnInset + drawnSide,
                projection
            )
            // Scaled with the footprint as drawn, so a new building swelling
            // to its size keeps its proportions.
            let rise = rises ? foot.height * (frame?.heightShare ?? CitySkyline.heightShare(density: lot.density)) : 0
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
            if let frame, frame.light > 0 { lit.append((roof: roof, light: frame.light)) }
            if lights > 0, foot.width >= 3, (lot.column &* 73_856_093 ^ lot.row &* 19_349_663) % 3 != 0 {
                let side = foot.width * 0.34
                // On the wall of a building that rises, else on its roof.
                let window = rise > side
                    ? CGRect(x: foot.midX - side / 2, y: roof.maxY + (rise - side) / 2, width: side, height: side)
                    : CGRect(x: foot.midX - side / 2, y: foot.midY - side / 2 - rise, width: side, height: side)
                windows.addRect(window)
            }
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
    /// Decision 205: a building smaller than ``glyphMinimumSide`` is drawn
    /// as a badge that size over its ground, so its kind still reads, while
    /// 16 m is at least this many points (a street block still shows);
    /// zoomed out further it is a plain square again, or the badges would
    /// cover the map.
    static let buildingBadgeFromSize = 6.0

    /// The buildings the player placed (city building P0-A, decision 92):
    /// each a square in the station's yellow, edged in ink, always at least a
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
            var side = min(rect.width, rect.height)
            var share = 0.62
            if side < glyphMinimumSide, projection.referenceSize >= buildingBadgeFromSize {
                // Decision 205: its ground, then a badge over it.
                context.fill(Path(rect), with: .color(Palette.playerBuilding))
                rect = CGRect(x: rect.midX - glyphMinimumSide / 2, y: rect.midY - glyphMinimumSide / 2, width: glyphMinimumSide, height: glyphMinimumSide)
                side = glyphMinimumSide
                share = 0.66
            }
            let shape = Path(roundedRect: rect, cornerRadius: min(3, rect.width * 0.12))
            context.fill(shape, with: .color(Palette.playerBuilding))
            context.stroke(shape, with: .color(Palette.ink), lineWidth: rect.width < 10 ? 0.75 : 1.25)
            // Decision 121: what it is, once there is room to read it.
            guard side >= glyphMinimumSide else { continue }
            var glyph = context.resolve(building.kind.mapGlyph.image)
            glyph.shading = .color(Palette.buildingGlyph)
            let size = side * share
            context.draw(glyph, in: CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size))
        }
    }

    /// Where the city's buildings stand (decision 95), while the building
    /// tool chooses a site: the middle square of each cell of land in view,
    /// or on a real-world map round the site (decision 140), faintly, once
    /// a cell is 8 points or more across.
    private static func drawCityBuildingSites(_ world: GameWorld, overlay: BuildingOverlay, projection: some MapProjection, in context: GraphicsContext) {
        guard overlay.showsCityBuildingSites, !world.land.isEmpty,
              Double(Land.cellLength) * projection.pointsPerUnit >= 8 else { return }
        var region = drawingRegion(projection)
        if let area = overlay.citySitesArea {
            region = WorldRegion(
                minX: max(region.minX, Double(area.minX)), minY: max(region.minY, Double(area.minY)),
                maxX: min(region.maxX, Double(area.maxX)), maxY: min(region.maxY, Double(area.maxY))
            )
        }
        let length = Double(Land.cellLength)
        let firstRow = max(0, Int((region.minY / length).rounded(.down))), lastRow = min(Land.rows(in: world.bounds) - 1, Int((region.maxY / length).rounded(.down)))
        let firstColumn = max(0, Int((region.minX / length).rounded(.down))), lastColumn = min(Land.columns(in: world.bounds) - 1, Int((region.maxX / length).rounded(.down)))
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return }
        var sites = Path()
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn where world.land.cell(row: row, column: column) != nil {
                let square = PlanRect.cityBuilding(row: row, column: column, in: world)
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

    /// The tiles of a map bought tile by tile (decision 160): the world
    /// outside the tiles owned shaded as past the map's edge, each tile for
    /// sale edged with its price (a lock when the best day has not unlocked
    /// it), and the tile chosen filled.
    private static func drawMapExpansion(_ expansion: MapExpansionOverlay, land: Path, projection: some MapProjection, in context: GraphicsContext) {
        func shape(_ rect: PlanRect) -> Path {
            polygon([
                screenPoint(Double(rect.minX), Double(rect.minY), projection), screenPoint(Double(rect.maxX), Double(rect.minY), projection),
                screenPoint(Double(rect.maxX), Double(rect.maxY), projection), screenPoint(Double(rect.minX), Double(rect.maxY), projection),
            ])
        }
        var unowned = land
        for rect in expansion.owned {
            unowned.addPath(shape(rect))
        }
        context.fill(unowned, with: .color(Palette.mapEdge.opacity(0.18)), style: FillStyle(eoFill: true))
        for tile in expansion.forSale {
            let outline = shape(tile.area)
            let isChosen = expansion.chosen == tile.area
            if isChosen {
                context.fill(outline, with: .color(Palette.metroGreen.opacity(0.18)))
            }
            context.stroke(
                outline, with: .color(tile.isUnlocked ? Palette.metroGreen : Palette.mapEdge),
                style: StrokeStyle(lineWidth: isChosen ? 3 : 1.5, dash: [8, 5])
            )
            let middle = screenPoint(Double(tile.area.minX + tile.area.maxX) / 2, Double(tile.area.minY + tile.area.maxY) / 2, projection)
            let price = Text(verbatim: tile.price.moneyText).font(.caption.weight(.bold)).monospacedDigit()
            let label = tile.isUnlocked ? price : Text(MapGlyph.lock.image).font(.caption) + Text(verbatim: " ") + price
            context.draw(label.foregroundStyle(Palette.ink), at: middle)
        }
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
        isHighSpeed: Bool,
        projection: some MapProjection,
        in context: GraphicsContext
    ) {
        let center = projection.screenPoint(of: station.location)
        let radius = stationRadius(projection)
        let badgeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        guard badgeRect.insetBy(dx: -6, dy: -6).intersects(context.clipBoundingRect) else { return }
        // Decision 214: a depot's badge is an arch, round above and square
        // below, with the garage in it (`docs/UI_THEME.md` 機廠).
        let badge = station.isDepot ? archPath(in: badgeRect) : Path(ellipseIn: badgeRect)
        context.fill(badge, with: .color(Palette.station))
        context.stroke(badge, with: .color(Palette.ink), lineWidth: 1.5)
        // Decision 168: a station a high-speed line calls at has a second
        // ring round the badge, under the selection's.
        if isHighSpeed {
            context.stroke(Path(ellipseIn: badgeRect.insetBy(dx: -3, dy: -3)), with: .color(Palette.ink), lineWidth: 1.5)
        }
        if isSelected {
            let ring = disc(at: center, radius: radius + 3)
            context.stroke(ring, with: .color(Color(uiColor: .systemBackground)), lineWidth: 5)
            context.stroke(ring, with: .color(.accentColor), lineWidth: 3)
        }
        if station.isDepot {
            drawStationSymbol(.depot, at: ScreenPoint(x: center.x, y: center.y + radius * 0.06), size: radius * 1.1, context: context)
        } else {
            drawStationSymbol(at: center, size: radius * 1.05, context: context)
        }
    }

    /// A station's name under its badge, on its plate, and the badges of
    /// its lines in a row under it (decision 216), zoomed in.
    private static func drawStationName(
        _ station: Station,
        badges: [(code: String, color: Color)],
        projection: some MapProjection,
        in context: GraphicsContext
    ) {
        let center = projection.screenPoint(of: station.location)
        let radius = stationRadius(projection)
        // Resolving and measuring a name is the costly part, and every pan
        // frame redraws: first rule out stations whose name cannot reach
        // the view. A caption2 character is under 24 points wide and a line
        // under 48 high at the largest text size, so this bound needs no
        // measuring; the shops' square (decision 222) adds 20 to its left.
        let reach = Double(station.name.count) * 12 + 20
        let largest = CGRect(x: center.x - reach, y: center.y + radius, width: reach * 2, height: 4 + 48 + 14)
        guard largest.intersects(context.clipBoundingRect) else { return }
        let name = context.resolve(Text(verbatim: station.name).font(.caption2.weight(.semibold)).foregroundStyle(Palette.ink))
        let nameSize = name.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        let nameRect = CGRect(x: center.x - nameSize.width / 2, y: center.y + radius + 4, width: nameSize.width, height: nameSize.height)
        // Decision 205: on the same pale plate as the names zoomed out
        // (``drawOverviewNames``), so it reads over a line or a town.
        context.fill(Path(roundedRect: nameRect.insetBy(dx: -2, dy: 0), cornerRadius: 3), with: .color(Palette.land.opacity(0.8)))
        context.draw(name, at: CGPoint(x: center.x, y: center.y + radius + 4), anchor: .top)
        // Decision 222: the station's shops, a warm yellow square to the
        // left of its name with one, two or three bags in it.
        if let level = station.commerce {
            let side = max(12, min(16, nameSize.height))
            let chip = CGRect(x: nameRect.minX - 4 - side, y: nameRect.midY - side / 2, width: side, height: side)
            let square = Path(roundedRect: chip, cornerRadius: 3)
            context.fill(square, with: .color(Palette.playerBuilding))
            context.stroke(square, with: .color(Palette.ink), lineWidth: 1.2)
            drawStationSymbol(.shops(level), at: ScreenPoint(x: chip.midX, y: chip.midY), size: side * 0.8, context: context)
        }
        // Decision 216: the badges of its lines in a row under the name,
        // at most four.
        if !badges.isEmpty {
            let shown = badges.prefix(4)
            let height = 12.0, gap = 2.0
            let widths = shown.map { lineBadgeWidth($0.code, height: height, in: context) }
            var x = center.x - (widths.reduce(0, +) + gap * Double(widths.count - 1)) / 2
            for (badge, badgeWidth) in zip(shown, widths) {
                drawLineBadge(badge.code, color: badge.color, in: CGRect(x: x, y: nameRect.maxY + 2, width: badgeWidth, height: height), context: context)
                x += badgeWidth + gap
            }
        }
    }

    // MARK: - Line badges (decision 216)

    /// The code and colour of each line calling at each station, in the
    /// lines' order, for the badges under its name.
    private static func stationBadges(_ world: GameWorld, codes: [LineID: String]) -> [StationID: [(code: String, color: Color)]] {
        guard !codes.isEmpty else { return [:] }
        var badges: [StationID: [(code: String, color: Color)]] = [:]
        for line in world.lines {
            guard let code = codes[line.id] else { continue }
            let color = Palette.lineColor(line.id, custom: line.color)
            var seen = Set<StationID>()
            for stop in line.stops where seen.insert(stop).inserted {
                badges[stop, default: []].append((code, color))
            }
        }
        return badges
    }

    /// The font of a badge `height` points high: the code is 0.66 of it,
    /// heavy and rounded (`docs/UI_THEME.md` 線號徽章).
    private static func lineBadgeText(_ code: String, height: Double, in context: GraphicsContext) -> GraphicsContext.ResolvedText {
        context.resolve(Text(verbatim: code).font(.system(size: height * 0.66, weight: .heavy, design: .rounded)).foregroundStyle(Palette.ink))
    }

    /// How wide a badge of `code` is drawn at `height`: the colour patch
    /// (0.42 of the height), the code with 0.21 either side, at least 0.9.
    private static func lineBadgeWidth(_ code: String, height: Double, in context: GraphicsContext) -> Double {
        let text = lineBadgeText(code, height: height, in: context).measure(in: CGSize(width: 200, height: height))
        return height * 0.42 + max(height * 0.9, text.width + height * 0.42)
    }

    /// A line's badge in `rect` (``LineCodeBadge`` on the map): white,
    /// edged in navy, a patch of the line's colour at its left behind a
    /// navy rule, the code in navy.
    private static func drawLineBadge(_ code: String, color: Color, in rect: CGRect, context: GraphicsContext) {
        let corner = rect.height * 0.22
        let tag = Path(roundedRect: rect, cornerRadius: corner)
        context.fill(tag, with: .color(Palette.markerFill))
        let patch = rect.height * 0.42
        var inner = context
        inner.clip(to: tag)
        inner.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: patch, height: rect.height)), with: .color(color))
        inner.fill(Path(CGRect(x: rect.minX + patch - 0.5, y: rect.minY, width: 1, height: rect.height)), with: .color(Palette.ink))
        context.stroke(tag, with: .color(Palette.ink), lineWidth: 1.5)
        context.draw(lineBadgeText(code, height: rect.height, in: context), at: CGPoint(x: rect.minX + patch + (rect.width - patch) / 2, y: rect.midY), anchor: .center)
    }

    /// Decision 216 (layer 24.5): each line's badge at the middle of its
    /// longest piece on the screen, if the piece is three badges long; a
    /// badge that would cover one already drawn is left out.
    private static func drawRibbonBadges(
        _ longest: [LineID: (points: [CGPoint], length: Double, color: Color)], codes: [LineID: String], height: Double, in context: GraphicsContext
    ) {
        var placed: [CGRect] = []
        for (line, piece) in longest.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let code = codes[line] else { continue }
            let badgeWidth = lineBadgeWidth(code, height: height, in: context)
            guard piece.length >= badgeWidth * 3, let middle = pointAlong(piece.points, at: piece.length / 2) else { continue }
            let rect = CGRect(x: middle.x - badgeWidth / 2, y: middle.y - height / 2, width: badgeWidth, height: height)
            guard !placed.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(rect) }) else { continue }
            placed.append(rect)
            drawLineBadge(code, color: piece.color, in: rect, context: context)
        }
    }

    /// `points` moved about `distance` to their left, as
    /// ``offsetPolyline(_:by:)`` draws them (each point along the step
    /// through its neighbours: near enough to place a badge).
    private static func offsetPoints(_ points: [CGPoint], by distance: Double) -> [CGPoint] {
        guard distance != 0, points.count > 1 else { return points }
        return points.indices.map { index in
            let a = points[max(index - 1, 0)], b = points[min(index + 1, points.count - 1)]
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
            return CGPoint(x: points[index].x + dy / length * distance, y: points[index].y - dx / length * distance)
        }
    }

    private static func polylineLength(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// The point `distance` along `points`.
    private static func pointAlong(_ points: [CGPoint], at distance: Double) -> CGPoint? {
        var left = distance
        for (a, b) in zip(points, points.dropFirst()) {
            let step = hypot(b.x - a.x, b.y - a.y)
            if step >= left, step > 0 {
                let t = left / step
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            left -= step
        }
        return points.last
    }

    // MARK: - Problems at the stations (decision 210)

    /// The waiting counts over the stations in view, at a middle zoom too
    /// (``MapProblems/level(referenceSize:)``): decision 205's white pill
    /// edged in navy, its people glyph one, two or three people as the
    /// station is quiet, crowded or full (art-style §2). Placed full first,
    /// then crowded, then the most waiting (``MapProblems/stationOrder(_:)``);
    /// a pill that would cover one already drawn is left out, and none
    /// after ``MapProblems/pillLimit(_:)``. Round a crowded station a ring
    /// that goes as far round as its room is taken, navy on a white halo,
    /// a whole red ring when full: its shape, not only its colour, says so.
    private static func drawStationProblems(
        _ world: GameWorld, waitingCounts: [StationID: Int64], projection: some MapProjection, in context: GraphicsContext
    ) {
        let level = MapProblems.level(referenceSize: projection.referenceSize)
        guard level != .hidden else { return }
        let radius = stationRadius(projection)
        let near = context.clipBoundingRect.insetBy(dx: -60, dy: -40)
        var centers: [StationID: ScreenPoint] = [:]
        var visible: [StationID: Int64] = [:]
        for station in world.stations {
            guard let waiting = waitingCounts[station.id], waiting > 0 else { continue }
            let center = projection.screenPoint(of: station.location)
            guard near.contains(CGPoint(x: center.x, y: center.y)) else { continue }
            centers[station.id] = center
            visible[station.id] = waiting
        }
        let limit = MapProblems.pillLimit(level)
        var placement = MapProblems.Placement(limit: limit)
        var rings = 0
        let fontSize = level == .full ? max(8, min(11, radius * 0.7)) : 8
        for entry in MapProblems.stationOrder(visible) {
            guard !placement.isFull || rings < limit else { break }
            guard let center = centers[entry.station] else { continue }
            let crowding = MapProblems.Crowding(waiting: entry.waiting)
            let ringRadius = radius + max(4.5, radius * 0.35)
            if crowding != .normal, rings < limit {
                rings += 1
                drawCrowdedRing(at: center, radius: ringRadius, fill: MapProblems.fill(waiting: entry.waiting), isFull: crowding == .full, in: context)
            }
            guard !placement.isFull else { continue }
            let countText = context.resolve(
                Text(verbatim: Money(entry.waiting).displayText)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(Palette.ink)
            )
            let countSize = countText.measure(in: CGSize(width: 120, height: 24))
            let icon = fontSize + 1
            let pillHeight = max(countSize.height + 3, icon + 4)
            let pillWidth = 3 + icon + 1.5 + countSize.width + 4
            let top = crowding == .normal ? radius : ringRadius + 1.5
            let pillY = center.y - top - pillHeight / 2 - 3
            let pillRect = CGRect(x: center.x - pillWidth / 2, y: pillY - pillHeight / 2, width: pillWidth, height: pillHeight)
            guard placement.place(.init(x: pillRect.minX, y: pillRect.minY, width: pillRect.width, height: pillRect.height)) else { continue }
            let pillPath = Path(roundedRect: pillRect, cornerRadius: pillHeight / 2)
            context.fill(pillPath, with: .color(Palette.markerFill))
            context.stroke(pillPath, with: .color(Palette.ink), lineWidth: 1.5)
            let glyph: MapGlyph = switch crowding {
            case .normal: .person
            case .crowded: .crowd
            case .full: .full
            }
            var people = context.resolve(glyph.image)
            people.shading = .color(Palette.ink)
            context.draw(people, in: CGRect(x: pillRect.minX + 3, y: pillY - icon / 2, width: icon, height: icon))
            context.draw(countText, at: CGPoint(x: pillRect.minX + 3 + icon + 1.5, y: pillY), anchor: .leading)
        }
    }

    /// A crowded station's ring (decision 210): a white halo, a faint navy
    /// track, and from the top clockwise a navy arc `fill` of the way
    /// round; a whole red ring when the station is full.
    private static func drawCrowdedRing(at center: ScreenPoint, radius: Double, fill: Double, isFull: Bool, in context: GraphicsContext) {
        let ring = disc(at: center, radius: radius)
        context.stroke(ring, with: .color(Palette.markerFill), lineWidth: 5)
        context.stroke(ring, with: .color(Palette.ink.opacity(0.35)), lineWidth: 0.8)
        guard !isFull else {
            context.stroke(ring, with: .color(Palette.metroRed), lineWidth: 3)
            return
        }
        var arc = Path()
        arc.addArc(
            center: CGPoint(x: center.x, y: center.y), radius: radius,
            startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fill), clockwise: false
        )
        context.stroke(arc, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
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

    /// An arch filling `rect`: a half circle on a square, its lower
    /// corners rounded by 0.28 of the radius.
    private static func archPath(in rect: CGRect) -> Path {
        let radius = rect.width / 2, corner = radius * 0.28
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - corner, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - corner), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private static func drawStationSymbol(_ glyph: MapGlyph = .train, at center: ScreenPoint, size: Double, context: GraphicsContext) {
        var symbol = context.resolve(glyph.image)
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

private extension WorldRegion {
    /// Whether the point (`x`, `y`) lies inside or on the edge.
    func contains(x: Double, y: Double) -> Bool {
        minX <= x && x <= maxX && minY <= y && y <= maxY
    }
}
