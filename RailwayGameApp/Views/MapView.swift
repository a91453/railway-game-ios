import GameCore
import GamePresentation
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// How much of each edge of the map the screen's own controls float
    /// over (``ContentView``: the status pill at the top, the dock at the
    /// bottom leading corner, the details card at the trailing side): the
    /// map's banners, keys and buttons keep clear of them. The map itself
    /// is drawn under them.
    @Entry var mapInsets = EdgeInsets()
    /// How far down from the map's top the trailing edge's controls reach
    /// (``mapInsets``' trailing inset): the details card ends there, and
    /// below it the map's bottom-trailing buttons keep to the edge.
    @Entry var mapTrailingInsetDepth = CGFloat.infinity
    /// Decision 300: the bottom-trailing buttons stand at the edge under a
    /// panel beside the map, as tall as the credit button (``MapCornerRow``).
    @Entry var mapButtonsUnderPanel = false
    /// The screen's safe area (``ContentView``, decision 120): the map is
    /// drawn to the screen's edges, under the camera housing and the home
    /// indicator, and its banners, keys and buttons keep inside this.
    @Entry var mapSafeArea = EdgeInsets()
    /// Decision 226: where the map's bottom-leading buttons (layers, map
    /// style, expansion) stand when they share the bottom row with the
    /// tools column and the station master: their foot this far above the
    /// screen's edges, beside the column, rather than above the bottom
    /// inset. `nil`: above it, as over the dock.
    @Entry var mapLeadingRowFoot: CGFloat?
    /// Whether the layer strip shows under the status pill (decision 224's
    /// 5B): the map's round layers button opens the same list, so it shows
    /// only while the strip does not (the tutorial, while building;
    /// decision 226, 2026-10-15).
    @Entry var mapShowsLayerStrip = false
}

extension EdgeInsets {
    /// Both insets on each edge.
    func adding(_ other: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: top + other.top, leading: leading + other.leading,
            bottom: bottom + other.bottom, trailing: trailing + other.trailing
        )
    }
}

/// A viewport-sized map. The camera and derived geometry are view state;
/// taps still go through the session's ordinary world commands.
struct MapView: View {
    let session: GameSession
    /// The parent keeps this view state across portrait/landscape layouts.
    @Binding var camera: PlanCamera?
    @State private var edges: [TrackEdgeID: MapEdgeDrawing] = [:]
    /// The map under a real-world game (Stage E2): a view preference, the
    /// same for every game. The game's own OpenStreetMap base map unless
    /// the player picked another (decision 151); a choice once made stays.
    @AppStorage("realWorldMapStyle") private var mapStyle: AppleMapStyle = .openStreetMap
    /// How strongly Taiwan's real railways show on it (the `Railway/` site's
    /// track display). Faint by default, not the site's own colours: here
    /// the player's railway is drawn over them.
    @AppStorage("realRailwayTrackStyle") private var trackStyle: RealRailways.TrackStyle = .faint
    @AppStorage("mapShowsStationNames") private var showsStationNames = true
    /// Decision 313: whether a pinch past the closest zoom opens the 3D map.
    @AppStorage(Map3DHandoff.pinchOpensKey) private var pinchOpens3D = true
    @AppStorage("mapShowsWaitingCounts") private var showsWaitingCounts = true
    @AppStorage("mapShowsCatchmentRings") private var showsCatchmentRings = true
    /// Which population and travel layer is shown (``PopTravelMode``'s raw
    /// value, empty for none); a view preference, as the other layers.
    @AppStorage("mapPopTravelMode") private var popTravelModeName = ""
    @AppStorage("mapShowsFaresAndStamps") private var showsFaresAndStamps = true
    /// Decision 311: whether the building layer shows as soon as building
    /// begins (the player puts it away with the corner button), which of
    /// its two it shows and the hours of where people are; device
    /// preferences, not in the save.
    @AppStorage(BuildingLayerShortcut.autoShowsKey) private var buildingLayerAutoShows = true
    @AppStorage("mapBuildingLayer") private var buildingLayerName = PopTravelMode.potential.rawValue
    @AppStorage("mapPotentialPeriod") private var potentialPeriodName = PotentialPeriod.allDay.rawValue
    /// Whether the player folded the layer's legend (TestFlight 59.1,
    /// ``LegendFold``): a device preference, not in the save.
    @AppStorage(LegendFold.key) private var legendFold = 0
    /// Whether the player opened the legend while it stood beside a wide
    /// card (``LegendFold/isFolded(stored:compactHeight:besideCard:openedBesideCard:)``);
    /// forgotten when the card goes.
    @State private var legendOpenedBesideCard = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// Decision 182: whether the map shows the time of day and the
    /// weather (the settings' switches, on the device).
    @AppStorage(MapAmbienceSettings.dayNightKey) private var showsDayNight = true
    @AppStorage(MapAmbienceSettings.weatherKey) private var showsWeather = true
    /// Decision 304: the real lines' trains on a real-world map, on the
    /// device.
    @AppStorage(MapAmbienceSettings.realTrainsKey) private var showsRealTrains = true
    /// Decision 328: the frame readout, off unless the player turns it on.
    @AppStorage(MapAmbienceSettings.frameRateKey) private var showsFrameRate = false
    /// The real lines on this map and their trains (decision 304), worked
    /// out once for the map, and the game clock they are drawn at.
    @State private var realTrains: RealTrainTraffic?
    @State private var realTrainsVersion = 0
    @State private var realTrainClock: RealTrainClock?
    /// Decision 216: the lines' colours, the player's or the
    /// colour-blind-safe palette's; the canvases redraw when it changes.
    @AppStorage(LinePalette.key) private var linePalette: LinePalette = .standard
    /// Decision 182: the trains' moves in the last tick, to draw them
    /// gliding to where they are, and a number that changes with them.
    @State private var trainMotion = TrainMotion()
    @State private var trainMotionVersion = 0
    /// Decision 269, later: the wait before the 3D scene builds ahead,
    /// started again by each pinch step near the line.
    @State private var buildAhead: Task<Void, Never>?
    /// Decision 182: today's weather on the map, worked out once a day.
    @State private var mapWeather = MapWeather.clear
    /// The open panel, and the layer's opacity, hour and playback: kept
    /// above both layouts (``GameScreenState``).
    @Environment(GameScreenState.self) private var screen
    /// The population grid laid out on this map, made once for a grid and
    /// a map (``PopulationHeatmap``), and a number that changes with it.
    @State private var heatmap: PopulationHeatmap?
    @State private var heatmapVersion = 0
    /// The travel demand of the world's stations, worked out when their
    /// demand or the lines change, only while a travel layer is shown.
    @State private var travelDemand = TravelDemandMap(trips: [:])
    /// The travel layer's squares for the shown mode and hour, made only
    /// when one of them or the demand changes, not on every body update,
    /// and a number that changes with them.
    @State private var travelTiles: [TravelDemandMap.Tile] = []
    @State private var travelTilesVersion = 0
    /// A blank map's population layer: the world's land (Phase 6a,
    /// ``LandMap``), made when the land changes, and a number that changes
    /// with it.
    @State private var landTiles: [TravelDemandMap.Tile] = []
    @State private var landTilesVersion = 0
    /// The population tooltip of the last tapped cell, and where it was
    /// tapped (`pop-grid-tooltip`).
    @State private var cellTooltip: (info: PopulationHeatmap.CellInfo, at: ScreenPoint)?
    /// The city layers' map (Phase 6d, ``CityMap``): made only while one is
    /// shown, and again only when the land, its buildings, the stations or
    /// the last measured service change, and a number that changes with it.
    @State private var cityMap: CityMap?
    /// Decision 311: the layer shown over the player's own while building.
    @State private var buildingLayer = BuildingLayerShortcut()
    /// Decision 311: where a station would have riders, worked out in view
    /// as it is drawn (``StationPotentialMap``), and a new one only when
    /// its key changes.
    @State private var potentialMap: StationPotentialMap?
    @State private var cityMapVersion = 0
    /// Decision 126: the city's buildings on the plain map, and a version
    /// that changes when they are replaced.
    @State private var skyline: CitySkyline?
    @State private var skylineVersion = 0
    /// Decision 140: the night's growth the map is playing, and when it
    /// began; `nil` once it is done.
    @State private var skylineGrowth: SkylineLayer.Growth?
    /// The last skyline built, kept even when the task that built it was
    /// cancelled, for decision 140's comparison (not observed: it draws
    /// nothing).
    @State private var skylineMemory = SkylineMemory()
    /// Decision 270: a blank map's seeded streets, as the 3D map lays them.
    @State private var streets: SeededStreetPlan?
    @State private var streetsVersion = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The city tooltip of the last tapped cell, and where it was tapped.
    @State private var cityTooltip: (info: CityCellInfo, at: ScreenPoint)?
    /// Decision 124, H3: the height and steep slope layer's map
    /// (``TerrainMap``), made only while it is shown, and a number that
    /// changes with it; and the tooltip of the last tapped cell.
    @State private var terrainMap: TerrainMap?
    @State private var terrainMapVersion = 0
    @State private var terrainTooltip: (lines: [String], at: ScreenPoint)?
    /// Decision 178: the passenger load layer's sections (``SectionFlow``),
    /// made only while it is shown and when the plan or the lines change;
    /// the strokes it draws in the shown hour, and a number that changes
    /// with them; and the tooltip of the last tapped section.
    @State private var sectionFlow = SectionFlow()
    @State private var flowStrokes: [SectionFlow.Stroke] = []
    @State private var flowStrokesVersion = 0
    @State private var sectionFlowVersion = 0
    @State private var sectionFlowTooltip: (text: String, at: ScreenPoint)?
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// What floats over the map (``EnvironmentValues/mapInsets``).
    @Environment(\.mapInsets) private var insets
    @Environment(\.mapLeadingRowFoot) private var leadingRowFoot
    @Environment(\.mapShowsLayerStrip) private var showsLayerStrip
    @Environment(\.mapTrailingInsetDepth) private var trailingInsetDepth
    @Environment(\.mapButtonsUnderPanel) private var buttonsUnderPanel
    @Environment(\.mapSafeArea) private var safeArea
    /// The height of the bottom-trailing buttons and key, with their margin.
    @State private var bottomTrailingHeight: CGFloat = 0
    /// How far down the column at the top of the map (the status banner,
    /// the construction HUD or the traffic key) reaches.
    @State private var topColumnDepth: CGFloat = 0
    /// Where the round buttons at the bottom-leading corner, and the
    /// legend, overview map and zoom buttons at the bottom-trailing one,
    /// are on the map (``MapView/mapArea``): the build's ✕ and ✓ keep off
    /// them.
    @State private var bottomLeadingFrame: CGRect = .zero
    @State private var bottomTrailingFrame: CGRect = .zero
    /// Decision 300: the buttons' row under a phone's panel, as laid out.
    @State private var cornerRowFrame: CGRect = .zero
    /// Where a real-world map's attribution sits (decision 120): Apple's
    /// logo and legal link, or MapLibre's attribution button, and the
    /// credits. Nothing of the game is drawn there, and a touch there
    /// reaches them.
    @State private var attributionFrames: [CGRect] = []
    /// Whether Apple's map shows what the camera shows, for the UI tests
    /// (``FollowingMapView/followingText``).
    @State private var baseMapFollowing = ""
    /// How close Apple's map would come, in points per
    /// ``MapScale/referenceLength``, when it stopped short of the game's
    /// closest zoom (its imagery does not reach that close): the camera
    /// comes no closer, so the railway drawn over it lines up (decision
    /// 50's later amendment). Forgotten when the map's style changes.
    @State private var baseMapZoomLimit: Double?
    /// What the map shows of traffic control (Stage V4e), taken from the
    /// session when the world changes, not on every pan or zoom.
    @State private var traffic = TrafficOverlay()
    /// The lines along their track and the transfer groups' links
    /// (decision 84), worked out off the main actor when the track, the
    /// lines or the groups change.
    @State private var lineMap = LineMap()
    /// Which stations are named zoomed out (decision 89), worked out with
    /// the lines' map.
    @State private var stationLabels = StationLabels()
    /// The whole map, small (decision 116), worked out with the lines' map.
    @State private var miniMap: MiniMap?
    /// Decision 220: the busiest trips of the station whose panel a hold
    /// opened, worked out off the main actor, and how much of each arc is
    /// drawn yet (drawn out once, or whole at once with Reduce Motion).
    @State private var journeyTrace: JourneyTrace?
    @State private var journeyProgress = 1.0
    /// Where the camera looks while it follows a train (the reference's
    /// eased `_trackCenter`); view state only.
    @State private var followCamera = FollowCamera()
    /// The camera a game opened on, and when (``openCamera(viewport:clearOf:)``).
    @State private var openedCamera: OpenedCamera?

    private var mapLayers: MapLayerPreferences {
        MapLayerPreferences(
            showsStationNames: showsStationNames,
            showsWaitingCounts: showsWaitingCounts,
            showsCatchmentRings: showsCatchmentRings,
            popTravelMode: buildingLayer.layer(over: PopTravelMode(rawValue: popTravelModeName)),
            showsFaresAndStamps: showsFaresAndStamps
        )
    }

    /// Decision 311: the hours where people are is weighed by.
    private var potentialPeriod: PotentialPeriod {
        PotentialPeriod(rawValue: potentialPeriodName) ?? .allDay
    }

    /// Decision 311: what where people are is worked out from while it
    /// shows, `nil` otherwise.
    private var potentialKey: StationPotentialMap.Key? {
        guard mapLayers.popTravelMode == .potential else { return nil }
        return StationPotentialMap.Key(world: session.world, drafts: session.lineDraft, period: potentialPeriod)
    }

    var body: some View {
        GeometryReader { proxy in
            let bounds = session.world.bounds
            let realWorld = RealWorldFrame(world: session.world)
            // Decision 120: the map reaches the screen's edges, and what
            // floats over it keeps inside the safe area and clear of the
            // screen's controls. A real-world map (Stage E2) has Apple's
            // logo and legal link and the credits along its bottom, above
            // the home indicator: the buttons stay above them, and the
            // game's drawing goes round them to the bottom edge.
            let attributionBand = realWorld == nil ? 0 : AppleMapBackground.attributionHeight
            let screenEdges = EdgeInsets(
                top: safeArea.top, leading: safeArea.leading,
                bottom: safeArea.bottom + attributionBand, trailing: safeArea.trailing
            )
            let clear = insets.adding(screenEdges)
            let attribution = AttributionCutout(holes: realWorld == nil ? [] : attributionFrames)
            let viewport = ScreenSize(width: proxy.size.width, height: max(proxy.size.height, 1))
            // Whether the bottom-trailing buttons stand beside the trailing
            // controls (``EnvironmentValues/mapTrailingInsetDepth``): under a
            // folded control card the edge is free.
            let besideTrailing = viewport.height - screenEdges.bottom - bottomTrailingHeight
                < screenEdges.top + trailingInsetDepth
            // Decision 123: beside a card or panel that takes more than a
            // third of the width (a phone's), the zoom buttons would stand in
            // the middle of the map, over what was selected; they give way,
            // as the overview map does, and a pinch still zooms. Measured
            // with their own fixed height (44 points and two paddings of
            // 12 each side), not the column's, which they leave. The
            // tutorial points at them, so they stay while it runs.
            // Decision 300: under a phone's panel they have a row of their own.
            let zoomGivesWay = !buttonsUnderPanel && session.tutorial == nil
                && insets.trailing > viewport.width / 3
                && viewport.height - screenEdges.bottom - 92 < screenEdges.top + trailingInsetDepth
            // Decision 300: where the buttons' row under a phone's panel
            // ends in the credits' band, `nil` where it has no room there.
            let bandEnd: CGFloat? = buttonsUnderPanel && realWorld != nil
                ? MapCornerRow.bandEnd(
                    rowWidth: Double(cornerRowFrame.width), viewportWidth: viewport.width,
                    trailingInset: Double(screenEdges.trailing), credits: attributionFrames.map { ScreenFrame($0) }
                ).map { CGFloat($0) }
                : nil
            let rowInBand = bandEnd != nil
            // #593: beside such a card the legend would stand in the middle
            // of the map, over its stations: it folds. Measured with the
            // zoom buttons' fixed height, as above, not the column's, which
            // folding changes.
            // Decision 300: beside a phone's panel too, where the buttons
            // leave it alone.
            let legendBesideCard = buttonsUnderPanel || (insets.trailing > viewport.width / 3
                && viewport.height - screenEdges.bottom - 92 < screenEdges.top + trailingInsetDepth)
            let zoomLimit: Double? = realWorld != nil && mapStyle != .openStreetMap ? baseMapZoomLimit : nil
            // What the camera's own framing keeps its places clear of (#593,
            // a player's report: the opening put a station under the zoom
            // buttons): the screen's controls, the column at the top, and
            // the buttons, legend and zoom buttons in the bottom corners.
            // Only when the camera moves itself (opening a game, jumping to
            // a station or a place); the player's pans and zooms are left
            // as they are (#544).
            let cover = MapCover(
                edges: ScreenInsets(top: max(clear.top, topColumnDepth), leading: clear.leading, bottom: clear.bottom, trailing: clear.trailing),
                corners: [bottomLeadingFrame, bottomTrailingFrame, buttonsUnderPanel ? cornerRowFrame : .zero].map { ScreenFrame($0) }
            )
            let framing = cover.framing(in: viewport)
            let projection = (camera?.resized(to: viewport) ?? openingCamera(viewport: viewport, clearOf: framing)).limited(toReferenceSize: zoomLimit)
            // Decision 182: the time of day, and how strongly the night's
            // lights shine, in twentieths so that the canvases are redrawn
            // twenty times as they come on, not on every tick.
            let tint = showsDayNight ? DayNight.tint(at: session.world.clock.now) : .day
            let lights = DayNight.step(tint.lights)
            // Once for the map and its loupe, not once for each canvas.
            let waitingCounts = MapLayers.waitingPassengerCounts(in: session.world)

            VStack(spacing: 0) {
                ZStack {
                    // The land and the population and travel layer: redrawn
                    // only when the camera or the layer changes, never for
                    // a moving train.
                    MapBaseCanvas(
                        bounds: bounds,
                        drawsLand: realWorld == nil,
                        // Decision 126: a city layer colours the cells instead.
                        // Decision 140: a real-world map draws only the
                        // night's growth.
                        skyline: mapLayers.popTravelMode?.isCityLayer != true
                            ? skyline.map {
                                SkylineLayer(skyline: $0, growth: skylineGrowth, growthOnly: realWorld != nil, version: skylineVersion)
                            } : nil,
                        layer: popTravelLayer(realWorld: realWorld),
                        // Decision 182: the town's windows at night.
                        lights: realWorld == nil ? lights : 0,
                        streets: realWorld == nil ? streets : nil,
                        streetsVersion: streetsVersion,
                        camera: projection
                    )
                    .equatable()
                    // Decision 311: where a station would have riders, over
                    // the town and under the railway; it fades in and out
                    // (``MotionRule/change``), at once with Reduce Motion.
                    if let potentialMap {
                        MapPotentialCanvas(map: potentialMap, opacity: opacity(for: .potential), camera: projection)
                            .equatable()
                            .transition(reduceMotion ? .identity : .opacity.animation(MotionRule.change.animation))
                    }
                    MapCanvas(
                        world: session.world,
                        selectedTrainID: session.selectedTrainID,
                        highlightedTrainID: session.followedTrain?.id,
                        selectedStationID: session.selectedStation?.id,
                        network: session.networkOverlay,
                        building: session.buildingOverlay,
                        expansion: session.mapExpansionOverlay,
                        traffic: traffic,
                        camera: projection,
                        edges: edges,
                        layers: mapLayers,
                        waitingCounts: waitingCounts,
                        lines: lineMap,
                        routePreview: session.routePreview,
                        labels: stationLabels,
                        flowStrokes: mapLayers.popTravelMode == .sectionFlow ? flowStrokes : [],
                        flowVersion: flowStrokesVersion,
                        lights: lights,
                        lineCodes: LineBadge.codes(for: session.world.lines),
                        linePalette: linePalette,
                        // Only the traced station's: not the last one's while
                        // the next is worked out, nor once its panel closes.
                        journey: journeyTrace.flatMap { $0.station == tracedStationID && $0.line == tracedLineID ? $0 : nil },
                        journeyProgress: journeyProgress,
                        drawsLabels: false
                    )
                    .equatable()
                    // Decision 182: the time of day over the ground, the
                    // town, the track and the stations; the trains and the
                    // weather stay over it.
                    if tint.strength > 0 {
                        Palette.tint(tint)
                            .blendMode(.multiply)
                            .allowsHitTesting(false)
                    }
                    // Decision 304: the real lines' trains, faint and
                    // under the player's.
                    if showsRealTrains, let realWorld, let realTrains, let realTrainClock {
                        RealTrainCanvas(
                            traffic: realTrains,
                            version: realTrainsVersion,
                            clock: realTrainClock,
                            frame: realWorld,
                            animating: !session.world.clock.isPaused && !reduceMotion && realTrainClock.isMoving,
                            camera: projection
                        )
                        .equatable()
                    }
                    MapTrainCanvas(
                        motion: trainMotion,
                        version: trainMotionVersion,
                        animating: !session.world.clock.isPaused && trainMotion.isMoving,
                        selectedTrainID: session.selectedTrainID,
                        lights: lights,
                        plain: mapLayers.popTravelMode == .sectionFlow,
                        traffic: traffic,
                        depotRuns: session.world.depotRuns(),
                        reduceMotion: reduceMotion,
                        running: !session.world.clock.isPaused,
                        language: session.language,
                        linePalette: linePalette,
                        camera: projection
                    )
                    .equatable()
                    // Decision 182, later: following a gliding train, the
                    // camera follows its glide frame by frame.
                    if followsGlide {
                        TimelineView(.animation) { timeline in
                            Color.clear.onChange(of: timeline.date) { last, now in
                                centerOnFollowedTrain(
                                    projection: projection, at: now.timeIntervalSinceReferenceDate, elapsed: now.timeIntervalSince(last)
                                )
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    // The stations' names and waiting counts over the
                    // trains (docs/MAP_LAYERS.md 55–57), and the network
                    // tool's preview and the tracks' numbers over them;
                    // darkened with the map at night, as under the tint.
                    MapLabelCanvas(
                        world: session.world,
                        camera: projection,
                        layers: mapLayers,
                        waitingCounts: waitingCounts,
                        labels: stationLabels,
                        lineCodes: LineBadge.codes(for: session.world.lines),
                        linePalette: linePalette,
                        network: session.networkOverlay,
                        routePreview: session.routePreview,
                        edges: edges
                    )
                    .equatable()
                    .colorMultiply(Palette.dimming(tint))
                    if showsWeather, mapWeather.sky != .clear || !mapWeather.typhoonStations.isEmpty {
                        MapWeatherLayer(
                            weather: mapWeather,
                            reduceMotion: reduceMotion,
                            typhoonStations: session.world.stations.filter { mapWeather.typhoonStations.contains($0.id) }.map(\.location),
                            camera: projection
                        )
                        .equatable()
                    }
                    // Decision 204: while a finger draws track, the map
                    // under it three times closer, on the other side of
                    // the map from the finger, with the stretch's tightest
                    // radius.
                    if let finger = session.networkDragFinger {
                        let side = 132.0
                        let leftOfFinger = projection.screenPoint(of: finger).x > viewport.width / 2
                        VStack(spacing: 4) {
                            ZStack {
                                MapCanvas(
                                    world: session.world,
                                    selectedTrainID: session.selectedTrainID,
                                    highlightedTrainID: session.followedTrain?.id,
                                    selectedStationID: session.selectedStation?.id,
                                    network: session.networkOverlay,
                                    building: session.buildingOverlay,
                                    expansion: session.mapExpansionOverlay,
                                    traffic: traffic,
                                    camera: projection.loupe(at: finger, size: ScreenSize(width: side, height: side), magnification: 3),
                                    edges: edges,
                                    layers: mapLayers,
                                    waitingCounts: waitingCounts,
                                    lines: lineMap,
                                    routePreview: session.routePreview,
                                    labels: stationLabels,
                                    flowStrokes: mapLayers.popTravelMode == .sectionFlow ? flowStrokes : [],
                                    flowVersion: flowStrokesVersion,
                                    lights: lights,
                                    lineCodes: LineBadge.codes(for: session.world.lines),
                                    linePalette: linePalette,
                                    journey: nil,
                                    journeyProgress: 1
                                )
                                .equatable()
                                // Where the finger is.
                                Path { path in
                                    path.move(to: CGPoint(x: side / 2 - 8, y: side / 2))
                                    path.addLine(to: CGPoint(x: side / 2 + 8, y: side / 2))
                                    path.move(to: CGPoint(x: side / 2, y: side / 2 - 8))
                                    path.addLine(to: CGPoint(x: side / 2, y: side / 2 + 8))
                                }
                                .stroke(Palette.ink, lineWidth: 1.5)
                            }
                            .frame(width: side, height: side)
                            .background(Theme.background)
                            .clipShape(Circle())
                            .overlay { Circle().stroke(Palette.ink, lineWidth: 2) }
                            if let preview = session.networkPreview {
                                Text(verbatim: preview.radiusText(in: session.language, curveSpeedLimits: session.world.curveSpeedLimits))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.panel, in: Capsule())
                            }
                        }
                        .position(
                            x: leftOfFinger ? clear.leading + 12 + side / 2 : viewport.width - clear.trailing - 12 - side / 2,
                            y: clear.top + 12 + side / 2
                        )
                        .accessibilityHidden(true)
                    }
                }
                .mask { attribution.fill() }
                // The gestures take the touches, and let those on the
                // attribution go to it.
                .allowsHitTesting(false)
                .overlay {
                    MapGestures(camera: projection, passesThrough: attribution.holes, onCameraChange: { moved in
                        camera = moved
                        cellTooltip = nil
                        cityTooltip = nil
                        terrainTooltip = nil
                        sectionFlowTooltip = nil
                        session.mapDidMove()
                    }, paintsFrom: { location in
                        // Decision 98: zoning, one finger drags out the
                        // cells to zone. Decision 102: building track, a
                        // drag from the start or from track draws the next
                        // stretch. Any other drag, and two fingers, move
                        // and zoom the map.
                        if isZoning { return true }
                        guard screen.panel != .lines else { return false }
                        // Decision 103: a drag on the building shown moves it.
                        if session.tool == .building {
                            return session.buildingDragMoves(from: projection.planPoint(at: location))
                        }
                        guard session.tool == .network else { return false }
                        return session.networkDragDraws(
                            from: projection.planPoint(at: location),
                            reach: projection.worldDistance(NetworkBuilding.touchRadius)
                        )
                    }, onPaint: { start, end, phase in
                        // Decision 226: the tools fade while the finger is under them.
                        noteDrawing(at: phase == .moved ? end : nil, mapOrigin: proxy.frame(in: .global).origin)
                        let from = projection.planPoint(at: start), to = projection.planPoint(at: end)
                        if isZoning {
                            switch phase {
                            case .moved: session.dragZone(from: from, to: to)
                            case .ended: session.endZoneDrag(from: from, to: to)
                            case .cancelled: session.cancelZoneDrag()
                            }
                        } else if session.tool == .building {
                            switch phase {
                            case .moved: session.dragBuildingSite(from: from, to: to)
                            case .ended: session.endBuildingDrag(from: from, to: to)
                            case .cancelled: session.cancelBuildingDrag()
                            }
                        } else {
                            let reach = projection.worldDistance(NetworkBuilding.touchRadius)
                            switch phase {
                            case .moved: session.dragNetwork(from: from, to: to, reach: reach)
                            case .ended: session.endNetworkDrag(from: from, to: to, reach: reach)
                            case .cancelled: session.cancelNetworkDrag()
                            }
                        }
                    }, holdsAt: { location in
                        // Decision 119: holding a station, while only
                        // looking at the map, opens its panel.
                        // Which way a hold went, for the UI tests' trace: the
                        // flaky hold of MapInteractionTests ends with no panel
                        // and nothing yet says why (PR #755–#784 review).
                        guard session.tool == .select, screen.panel != .lines else {
                            UITestTrace.action("map.hold refused: tool \(session.tool), panel \(String(describing: screen.panel))")
                            return false
                        }
                        let reach = projection.worldDistance(NetworkBuilding.touchRadius)
                        let point = projection.planPoint(at: location)
                        let found = session.world.station(near: point, within: reach) != nil
                        UITestTrace.action("map.hold at (\(Int(location.x)), \(Int(location.y))): station \(found ? "found" : "none")")
                        // Decision 276: off a station, a line's track.
                        return found || session.lineHeld(at: point, reach: reach) != nil
                    }, onHold: { location in
                        let reach = projection.worldDistance(NetworkBuilding.touchRadius)
                        let point = projection.planPoint(at: location)
                        let held = session.holdMap(at: point, reach: reach)
                        UITestTrace.action("map.hold began: \(held.map { "station \($0.rawValue)" } ?? "no station")")
                        // Decision 276: a line held where no station is opens
                        // its panel and traces its busiest trips.
                        let line = held == nil ? session.holdLine(at: point, reach: reach) : nil
                        if line != nil { UserDefaults.standard.set(true, forKey: TrackHoldHint.seenKey) }
                        if held != nil || line != nil {
                            cellTooltip = nil
                            cityTooltip = nil
                            terrainTooltip = nil
                            sectionFlowTooltip = nil
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            screen.panel = held != nil ? .station : .lines
                        }
                    }, onPinchCloser: { pinched in
                        // Decision 269, later: resting near the closest
                        // zoom, the 3D scene starts building.
                        guard Map3DHandoff.hands(building: session.tool != .select, tutorialRuns: session.tutorial != nil,
                                                 pinchOpens: pinchOpens3D),
                              !screen.showsMap3D else { return }
                        buildAheadIfResting(near: pinched)
                    }, onPinchEnded: { pinched, asked in
                        // Decision 313: decided only as the fingers lift. A
                        // pinch that went on past the 2D map's closest zoom
                        // hands it over to the 3D map, where the 2D map
                        // was and as close (not with a building tool out,
                        // in the tutorial, or with the setting off).
                        guard Map3DHandoff.hands(building: session.tool != .select, tutorialRuns: session.tutorial != nil,
                                                 pinchOpens: pinchOpens3D),
                              !screen.showsMap3D,
                              Map3DHandoff.opensOnRelease(referenceSize: pinched.referenceSize, asked: asked) else { return }
                        UITestTrace.action("map.pinch let go past the closest zoom: 3D")
                        screen.map3DHandoff = Map3DHandoff.Plan(x: pinched.centerX, y: pinched.centerY, referenceSize: pinched.referenceSize)
                        var cut = Transaction()
                        cut.disablesAnimations = true
                        withTransaction(cut) { screen.showsMap3D = true }
                    }) { location in
                        let point = projection.planPoint(at: location)
                        let reach = projection.worldDistance(NetworkBuilding.touchRadius)
                        showCellTooltip(at: location, projection: projection)
                        // With the lines panel open the map is where the
                        // player picks stations for a line (the tutorial's
                        // line step), whichever tool is chosen.
                        if session.isChoosingMapTile, screen.panel != .lines {
                            // Decision 160: a tap chooses the tile to buy.
                            session.tapMapExpansion(at: point)
                        } else if session.tool == .network, screen.panel != .lines {
                            session.tapNetwork(at: point, reach: reach)
                        } else if session.tool == .building, screen.panel != .lines {
                            // Decisions 92 and 94: the building tool builds
                            // or demolishes where the player taps.
                            session.tapBuildingTool(at: point, reach: reach)
                        } else {
                            session.tapMap(at: point, reach: reach)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(bounds.mapLabel(in: session.language))
                .accessibilityIdentifier(TutorialTarget.map.rawValue)
                .accessibilityValue(selectionDescription)
                .background(realWorld == nil ? Color(uiColor: .secondarySystemBackground) : Color.clear)
                .clipped()
                .overlay(alignment: .top) {
                    // One column down the top of the map, so none covers
                    // another: the status banner (the follow bar stands in
                    // the row above, ``ContentView``, decision 226), then
                    // the construction HUD while a stretch is previewed,
                    // or else the traffic key at the leading edge.
                    VStack(spacing: 0) {
                        StatusBanner(session: session)
                        if showsConstructionHUD, let preview = session.networkPreview {
                            MapConstructionHUD(preview: preview, language: session.language)
                                .padding(.top, 12)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else {
                            TrafficLegend(traffic: traffic, language: session.language)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if showsFrameRate {
                            MapFrameReadout(language: session.language)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, clear.top)
                    .padding(.leading, clear.leading)
                    .padding(.trailing, clear.trailing)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topColumnDepth = $0 }
                }
                .overlay(alignment: .bottomTrailing) {
                    VStack(alignment: .trailing, spacing: 8) {
                        if let mode = mapLayers.popTravelMode {
                            PopulationLegendView(
                                mode: mode,
                                language: session.language,
                                opacity: opacityBinding(for: mode),
                                hour: Bindable(screen).popTravelHour,
                                isPlaying: screen.isPlayingPopTravel,
                                onTogglePlay: togglePopTravelPlay,
                                nothingZoned: session.world.zones.isEmpty,
                                isFlat: terrainMap?.isFlat ?? false,
                                tracksLevel: terrainMap?.tracksLevel ?? false,
                                isFolded: Binding(
                                    get: {
                                        LegendFold.isFolded(stored: legendFold, compactHeight: verticalSizeClass == .compact,
                                                            besideCard: legendBesideCard, openedBesideCard: legendOpenedBesideCard)
                                    },
                                    set: { folded in
                                        if legendBesideCard {
                                            legendOpenedBesideCard = !folded
                                        } else {
                                            legendFold = LegendFold.stored(folded: folded)
                                        }
                                    }
                                ),
                                coverage: mode == .coverage ? cityMap?.coverage : nil,
                                building: buildingLayer.isOn ? buildingLegend : nil
                            ) {
                                stopPopTravelPlay()
                                cellTooltip = nil
                                cityTooltip = nil
                                terrainTooltip = nil
                                sectionFlowTooltip = nil
                                if buildingLayer.isOn {
                                    // Decision 311: put away, as the corner button does.
                                    buildingLayerAutoShows = buildingLayer.toggle()
                                } else {
                                    popTravelModeName = ""
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                        } else if insets.trailing == 0 {
                            // Decision 116: the whole map, small; it gives
                            // way to a layer's legend, which needs the height,
                            // and to the details card or a panel at the
                            // trailing side: beside them it would stand in
                            // the middle of a phone's map, under the finger.
                            MiniMapView(map: miniMap, visible: projection.visibleRegion, language: session.language) { point in
                                if session.followedTrain != nil { session.stopFollowingTrain() }
                                camera = projection.centered(atX: point.x, y: point.y)
                                session.mapDidMove()
                            }
                            .padding(.trailing, 12)
                        }
                        // Decision 300: under a phone's panel they stand
                        // in a row of their own (below).
                        if !buttonsUnderPanel {
                            cornerButtons(camera: projection, limit: zoomLimit, zoomGivesWay: zoomGivesWay)
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.mapArea)) } action: { bottomTrailingFrame = $0 }
                    .padding(12)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        bottomTrailingHeight = frame.height
                        screen.mapCornerFrame = frame
                    }
                    // Beside the trailing controls only where they reach,
                    // and then above the dock too: moved in from the edge on
                    // a phone, the zoom buttons were under it.
                    .padding(.trailing, besideTrailing ? clear.trailing : screenEdges.trailing)
                    .padding(.bottom, besideTrailing ? clear.bottom : screenEdges.bottom)
                    .animation(.easeInOut(duration: 0.2), value: trailingInsetDepth)
                }
                .overlay(alignment: .bottomTrailing) {
                    // Decision 300: under a phone's panel, at the screen's
                    // edge, as tall as the credit button: in the credits'
                    // band where it has room beside them, a finger's target
                    // reaching into the home indicator's margin below;
                    // otherwise just above the band, and the panel ends
                    // higher (``MapCornerRow/panelRaise(underPanel:inBand:)``).
                    if buttonsUnderPanel {
                        let below: CGFloat = rowInBand ? safeArea.bottom + 1 : screenEdges.bottom + 2
                        let reach: CGFloat = min(CGFloat(MapCornerRow.reach - MapCornerRow.height), rowInBand || realWorld == nil ? below : 0)
                        let rowEnd: CGFloat = bandEnd ?? CGFloat(viewport.width) - screenEdges.trailing - CGFloat(MapCornerRow.gap)
                        cornerButtons(camera: projection, limit: zoomLimit, zoomGivesWay: false, compactReach: reach)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.mapArea)) } action: { cornerRowFrame = $0 }
                            .padding(.trailing, CGFloat(viewport.width) - rowEnd)
                            .padding(.bottom, below - reach)
                            .transition(.opacity)
                    }
                }
                .onChange(of: buttonsUnderPanel && rowInBand, initial: true) { _, inBand in
                    screen.mapRowInBand = inBand
                }
                .overlay(alignment: .bottomLeading) {
                    // On a phone's bottom row, one above the other beside the
                    // station master (decision 226, 2026-10-15, the owner).
                    let rowLayout = leadingRowFoot == nil
                        ? AnyLayout(HStackLayout(spacing: 8))
                        : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    // Decision 226, step 3: the map style is chosen in the
                    // layer list; here the expansion, and the layer list's
                    // own button while the strip does not show.
                    rowLayout {
                        if !showsLayerStrip {
                            mapLayersButton
                        }
                        // Not while building: beside the tools' Done
                        // button it was tapped by mistake (TestFlight 56.1).
                        // Not among the building tools either: a phone held
                        // sideways has no height for a fifth (decision 226).
                        if session.showsMapExpansionButton {
                            mapExpansionButton(viewport: viewport, cover: cover)
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.mapArea)) } action: { bottomLeadingFrame = $0 }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { screen.mapLeadingRowFrame = $0 }
                    .padding(12)
                    // Above the dock (decision 106), beside the tools
                    // (decision 114); on a phone's bottom row beside the
                    // tools column (decision 226, 2026-10-15).
                    .padding(.bottom, leadingRowFoot.map { screenEdges.bottom + $0 - 12 } ?? clear.bottom)
                    .padding(.leading, clear.leading)
                }
                // Decision 174, later: the sights while building, faint
                // and under the flags below.
                .overlay(alignment: .topLeading) {
                    MapAttractionMarks(session: session, camera: projection, viewport: viewport, insets: clear, isPassive: true)
                }
                // Decision 295: the real stations, choosing where a
                // platform goes on a real-world map; under the flags.
                .overlay(alignment: .topLeading) {
                    if session.offersRealStations {
                        MapRealStationPins(session: session, camera: projection, viewport: viewport, insets: clear)
                    }
                }
                // Decision 107: flags at the ends of the track previewed,
                // and beside it, or the building shown, cancel and build.
                .overlay(alignment: .topLeading) {
                    // Under the construction HUD, which shows how long the
                    // track is and what it costs.
                    MapBuildConfirm(session: session, camera: projection, viewport: viewport, insets: EdgeInsets(
                        top: max(clear.top, topColumnDepth), leading: clear.leading,
                        bottom: clear.bottom, trailing: clear.trailing
                    ), mapTop: clear.top, avoiding: [bottomLeadingFrame, bottomTrailingFrame, buttonsUnderPanel ? cornerRowFrame : .zero])
                    // Its flags and ring are where the track and the site
                    // are, which may be by the attribution.
                    .mask { attribution.fill() }
                }
                // Decision 167, later: the locks on the tiles not bought.
                .overlay(alignment: .topLeading) {
                    MapLockMarks(session: session, camera: projection, viewport: viewport, insets: clear)
                }
                // Decision 109: what needs the player, over its stations.
                .overlay(alignment: .topLeading) {
                    MapAlertBubbles(session: session, camera: projection, viewport: viewport, insets: clear)
                }
                // Decision 174: the sights, with their stars.
                .overlay(alignment: .topLeading) {
                    MapAttractionMarks(session: session, camera: projection, viewport: viewport, insets: clear)
                }
                // Decision 246: where the city's requests point.
                .overlay(alignment: .topLeading) {
                    MapRequestMarks(session: session, camera: projection, viewport: viewport, insets: clear)
                }
                // Decision 119: the station selected, looked at.
                .overlay(alignment: .topLeading) {
                    MapStationTagView(session: session, camera: projection, viewport: viewport, insets: clear)
                }
                // Decision 117: something just put up.
                .overlay(alignment: .topLeading) {
                    BuildPulseMark(pulse: session.buildPulse, camera: projection)
                        .mask { attribution.fill() }
                }
                // Decision 256: towns grown a step, fares over the stations,
                // a goal met.
                .overlay(alignment: .topLeading) {
                    TownGrowthRings(pulse: session.townPulse, camera: projection)
                        .mask { attribution.fill() }
                }
                // The fares, and decision 276's trips stamped full where
                // they ended; both off with the quick strip's Fares
                // (decision 310).
                .overlay(alignment: .topLeading) {
                    if mapLayers.showsFaresAndStamps {
                        FareFloatMarks(session: session, camera: projection)
                            .mask { attribution.fill() }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if mapLayers.showsFaresAndStamps {
                        TripStampMarks(session: session, camera: projection)
                            .mask { attribution.fill() }
                    }
                }
                .overlay {
                    GoalMetCheck(pulse: session.goalPulse, language: session.language)
                }
                // After the map's own accessibility element, which ignores
                // what lies inside it: the tooltips are read on their own.
                // And after the other overlays, so the legend and the zoom
                // and layer buttons do not cover a tooltip near them (it
                // takes no touches, so they can still be tapped).
                .overlay(alignment: .topLeading) {
                    // Not while the build's ✕ and ✓ are up (a player's
                    // report: the population grid's tooltip covered the
                    // ✓): the tap that picked the track asked the layer
                    // for its cell too.
                    if !buildPillShown {
                        cellTooltips(clear: clear, viewport: viewport, screenEdges: screenEdges)
                    }
                }
                // Nor come back, out of date, when they go.
                .onChange(of: buildPillShown) {
                    cellTooltip = nil
                    cityTooltip = nil
                    terrainTooltip = nil
                    sectionFlowTooltip = nil
                }
                .animation(.easeInOut(duration: 0.2), value: session.networkPreview != nil)
                .animation(.easeInOut(duration: 0.2), value: session.followedTrain?.id)
                .animation(.easeInOut(duration: 0.2), value: mapLayers.popTravelMode)
                .frame(height: viewport.height)
                .coordinateSpace(.named(Self.mapArea))
            }
            .background {
                if let realWorld {
                    Group {
                        if mapStyle == .openStreetMap {
                            // Decision 97: OpenStreetMap's map, drawn by
                            // MapLibre, in place of Apple's.
                            OSMMapBackground(
                                realWorld: realWorld,
                                camera: projection,
                                railways: session.railways,
                                water: session.water,
                                trackStyle: trackStyle,
                                language: session.language,
                                stations: OSMMapBackground.stationMarks(of: session.world, in: realWorld),
                                safeArea: safeArea,
                                onAttributionFrames: { attributionFrames = $0 },
                                onCredit: { screen.panel = .dataSources }
                            )
                        } else {
                            AppleMapBackground(
                                realWorld: realWorld,
                                camera: projection,
                                style: mapStyle,
                                railways: session.railways,
                                trackStyle: trackStyle,
                                language: session.language,
                                safeArea: safeArea,
                                onAttributionFrames: { attributionFrames = $0 },
                                onCredit: { screen.panel = .dataSources },
                                onFollowing: baseMapFollowingReport,
                                onZoomLimit: limitZoom
                            )
                        }
                    }
                    // Phase 6d: under the land use layer Apple's map, with
                    // its own buildings, is washed out so the cells' uses
                    // read clearly; its attribution stays as it is.
                    .overlay {
                        if mapLayers.popTravelMode == .landUse {
                            Color(uiColor: .systemBackground).opacity(0.6)
                                .mask { attribution.fill() }
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                baseMapReadout(shown: realWorld != nil && mapStyle != .openStreetMap)
                cameraZoomReadout(projection.pointsPerUnit)
                stationReadout(projection)
                expansionTileReadout(projection)
            }
            .onChange(of: isZoning) { _, zoning in
                // Decision 98: zoning shows the zones.
                if zoning {
                    stopPopTravelPlay()
                    popTravelModeName = PopTravelMode.zoning.rawValue
                }
            }
            .onChange(of: viewport, initial: true) { _, size in
                camera = camera?.resized(to: size) ?? openCamera(viewport: size, clearOf: framing)
            }
            .onChange(of: legendBesideCard) { _, beside in
                if !beside { legendOpenedBesideCard = false }
            }
            .onChange(of: mapStyle) { _, _ in
                // Another style's map (satellite imagery or the street
                // map) may come closer, or less close.
                baseMapZoomLimit = nil
            }
            .onChange(of: bounds) { _, _ in
                camera = openCamera(viewport: viewport, clearOf: framing)
            }
            .onChange(of: session.selectedStation?.id) { _, _ in
                // A station chosen in the overview may be kilometres away.
                // One already in view stays where it is, under the finger
                // that tapped it.
                // While a train is followed the camera stays on it.
                // Decision 106, later: "in view" is the map the screen's
                // controls leave, and one under them moves to its middle.
                keepSelectionClear(projection: projection, cover: cover, line: false)
            }
            // Decision 106, later: a line chosen in the lines panel, and the
            // selection when a panel opens over it, move into the map the
            // panel leaves.
            // TestFlight 59.1: only the lines panel's own choice; a line
            // that building makes or picks stays where the player looks.
            .onChange(of: session.selectedLineID) { _, _ in
                guard screen.panel == .lines else { return }
                keepSelectionClear(projection: projection, cover: cover, line: true)
            }
            // TestFlight 59.1: the details card opens and closes all through
            // building (the tool's card, a start tapped, Clear, Done); the
            // line the session keeps selected then zoomed the map out to its
            // whole length each time. Only the lines panel shows a line.
            .onChange(of: insets.trailing) { _, _ in
                keepSelectionClear(projection: projection, cover: cover,
                                   line: screen.panel == .lines && session.selectedStation == nil)
            }
            .onChange(of: session.routePreview?.request) { _, _ in
                // Decision 201: a leg shown from the line panel is brought
                // into view when its middle is out of view.
                if !session.isFollowingTrain, let preview = session.routePreview, let focus = preview.focus,
                   !projection.visibleRegion.contains(focus) {
                    camera = projection.centered(on: focus, clearOf: framing)
                }
            }
            .onChange(of: session.cameraRequest) { _, request in
                // Decision 177: the station master's tap on advice that
                // points at a place (the next town to extend to).
                guard let request else { return }
                camera = projection.centered(on: WorldCoordinate(x: request.location.x, y: request.location.y), clearOf: framing)
            }
            // Decision 188, later fix: where the places the tutorial's
            // step has the player tap stand, which its card keeps clear of.
            .onChange(of: tutorialSites(projection: projection, origin: proxy.frame(in: .global).origin), initial: true) { _, sites in
                screen.tutorialMapSites = sites
            }
            .onChange(of: session.world.clock) { _, _ in
                // While its train glides, the frames move the camera.
                guard !followsGlide else { return }
                centerOnFollowedTrain(projection: projection)
            }
            .onChange(of: session.followedTrain?.id) { _, _ in
                // A new follow snaps to its train, as the reference's
                // cleared `_trackCenter` does.
                followCamera.reset()
                centerOnFollowedTrain(projection: projection)
            }
            // Decision 269: the 3D map handed back, pinched out: the 2D
            // map where it looked, as close.
            .onChange(of: screen.map2DReturn) { _, plan in
                guard let plan else { return }
                screen.map2DReturn = nil
                if session.followedTrain != nil { session.stopFollowingTrain() }
                let centred = projection.centered(atX: plan.x, y: plan.y)
                camera = centred.zoomed(by: plan.referenceSize / centred.referenceSize,
                                        around: ScreenPoint(x: centred.viewport.width / 2, y: centred.viewport.height / 2))
                    .centered(atX: plan.x, y: plan.y)
                session.mapDidMove()
            }
            // The corners' buttons and legend are measured after the first
            // layout: a camera that opened before then, and that nothing
            // has moved since, opens again clear of them.
            .onChange(of: framing) { _, framing in
                guard let opened = openedCamera, camera == opened.camera, session.tool == .select,
                      !session.isFollowingTrain, session.tutorial == nil,
                      Date.now.timeIntervalSince(opened.at) < Self.openingSettles else { return }
                let reopened = openingCamera(viewport: viewport, clearOf: framing)
                openedCamera = OpenedCamera(camera: reopened, at: opened.at)
                camera = reopened
            }
        }
        .onChange(of: TrafficKey(world: session.world), initial: true) { _, _ in
            // Decision 64, later fix: read with the tick, off the main actor.
            traffic = session.trafficOverlay
        }
        .onChange(of: session.world.trains, initial: true) { _, _ in
            // Decision 182: each tick's trains glide from the last tick's.
            trainMotion = TrainMotion(world: session.world, previous: trainMotion, time: Date().timeIntervalSinceReferenceDate)
            trainMotionVersion &+= 1
        }
        .onChange(of: session.world.clock.now, initial: true) { _, _ in
            // Decision 304: the real trains glide with the game clock.
            guard realTrains != nil else { return }
            realTrainClock = RealTrainClock(world: session.world, previous: realTrainClock, time: Date().timeIntervalSinceReferenceDate)
        }
        .task(id: RealTrainsKey(
            realWorld: RealWorldFrame(world: session.world), bounds: session.world.bounds,
            hasData: session.railways?.operations != nil, shown: showsRealTrains,
            bought: Set(session.world.acquisitions.map(\.realLine))
        )) {
            await workOutRealTrains()
        }
        .onChange(of: MapWeatherKey(world: session.world), initial: true) { _, _ in
            mapWeather = MapWeather(world: session.world)
        }
        .task(id: JourneyTraceKey(world: session.world, station: tracedStationID, line: tracedLineID)) {
            await workOutJourneyTrace()
        }
        .task(id: LineMapKey(world: session.world)) {
            // A journey a line costs a route search a leg: on a large map
            // that is too slow for a frame.
            let world = session.world
            let (map, labels, mini) = await Task.detached(priority: .userInitiated) {
                (LineMap(world: world), StationLabels(world: world), MiniMap(world: world))
            }.value
            if !Task.isCancelled {
                lineMap = map
                stationLabels = labels
                miniMap = mini
            }
        }
        .onChange(of: HeatmapKey(total: session.population?.total, realWorld: RealWorldFrame(world: session.world)), initial: true) { _, key in
            // The grid is laid out once for a map, not on every draw.
            if let population = session.population, let frame = key.realWorld {
                heatmap = PopulationHeatmap(grid: population, frame: frame)
            } else {
                heatmap = nil
            }
            heatmapVersion &+= 1
        }
        .onChange(of: session.world.land, initial: true) { _, land in
            // A real-world map draws WorldPop's grid, which its land is from.
            landTiles = session.world.geoAnchor == nil ? LandMap.tiles(of: land) : []
            landTilesVersion &+= 1
        }
        .task(id: TravelDemandKey(world: session.world, isShown: mapLayers.popTravelMode?.usesHour == true)) {
            // Every station's day of demand, each a search over the whole
            // map with network routing: too slow for a frame on a large map.
            guard mapLayers.popTravelMode?.usesHour == true else { return }
            let world = session.world
            let demand = await Task.detached(priority: .userInitiated) {
                world.travelDemandMap()
            }.value
            if !Task.isCancelled {
                travelDemand = demand
            }
        }
        .onChange(of: TravelTilesKey(mode: mapLayers.popTravelMode, hour: screen.popTravelHour, demand: travelDemand), initial: true) { _, key in
            travelTiles = key.mode.map { key.demand.tiles(for: $0, at: key.hour) } ?? []
            travelTilesVersion &+= 1
        }
        .task(id: CityMapKey(world: session.world, isShown: mapLayers.popTravelMode?.isCityLayer == true)) {
            // Worked out once for what the layers read, not on every draw,
            // and off the main thread (decision 89): on the whole of Taiwan
            // it takes seconds with hundreds of stations.
            guard mapLayers.popTravelMode?.isCityLayer == true else {
                cityMap = nil
                cityMapVersion &+= 1
                return
            }
            let world = session.world
            let map = await Task.detached(priority: .userInitiated) { CityMap(world: world) }.value
            if !Task.isCancelled {
                cityMap = map
                cityMapVersion &+= 1
            }
        }
        .task(id: SectionFlowKey(world: session.world, isShown: mapLayers.popTravelMode == .sectionFlow)) {
            // Decision 178: every section's day of riders against its
            // trains' capacity, read from the world's kept passenger plan
            // and worked out off the main thread (a journey a line).
            guard mapLayers.popTravelMode == .sectionFlow else {
                sectionFlow = SectionFlow()
                sectionFlowVersion &+= 1
                return
            }
            let world = session.world
            let flow = await Task.detached(priority: .userInitiated) { SectionFlow(world: world) }.value
            if !Task.isCancelled {
                sectionFlow = flow
                sectionFlowVersion &+= 1
            }
        }
        .onChange(of: FlowStrokesKey(isShown: mapLayers.popTravelMode == .sectionFlow, hour: screen.popTravelHour, flow: sectionFlowVersion), initial: true) { _, key in
            flowStrokes = key.isShown ? sectionFlow.strokes(at: key.hour) : []
            flowStrokesVersion &+= 1
            sectionFlowTooltip = nil
        }
        .task(id: TerrainMapKey(world: session.world, hasHeights: session.heights != nil, isShown: mapLayers.popTravelMode == .terrain)) {
            // Decision 124, H3: the heights at the cells' corners, sampled
            // once for the map, off the main thread.
            guard mapLayers.popTravelMode == .terrain else {
                terrainMap = nil
                terrainMapVersion &+= 1
                return
            }
            let world = session.world, heights = session.heights
            let map = await Task.detached(priority: .userInitiated) { TerrainMap(world: world, heights: heights) }.value
            if !Task.isCancelled {
                terrainMap = map
                terrainMapVersion &+= 1
            }
        }
        .task(id: SkylineKey(world: session.world)) {
            // Decision 126: what the plain map shows of the city, worked out
            // off the main thread when the land or its buildings change
            // (each night at most). A real-world map shows its own town, and
            // decision 140 only what grew of it, where the land grows.
            guard session.world.geoAnchor == nil || session.world.landDemand, !session.world.land.isEmpty else {
                skyline = nil
                skylineMemory.latest = nil
                skylineGrowth = nil
                skylineVersion &+= 1
                return
            }
            // Decision 140: what grew since the last one, played over the
            // next second and a half (and faded out on a real-world map);
            // not with Reduce Motion.
            let world = session.world
            let playing = world.geoAnchor == nil ? SkylineGrowth.duration : SkylineGrowth.fadedDuration
            let built = await Task.detached(priority: .utility) { CitySkyline(world: world) }.value
            // Compared with the last skyline built, kept even when its task
            // was cancelled: land read in at 23:59 whose skyline was still
            // being built when midnight changed the key would otherwise be
            // missing from the one compared with, and rise as the night's
            // growth.
            let previous = reduceMotion ? nil : skylineMemory.latest
            skylineMemory.latest = built
            guard !Task.isCancelled else { return }
            let growth = await Task.detached(priority: .utility) { previous.flatMap { SkylineGrowth(from: $0, to: built) } }.value
            guard !Task.isCancelled else { return }
            skyline = built
            skylineGrowth = growth.map { SkylineLayer.Growth(growth: $0, start: .now) }
            skylineVersion &+= 1
            guard growth != nil else { return }
            try? await Task.sleep(for: .seconds(playing))
            guard !Task.isCancelled else { return }
            skylineGrowth = nil
            skylineVersion &+= 1
        }
        .task(id: Map3DSceneKey(world: session.world, hasHeights: false)) {
            // Decision 270: a blank map's seeded streets (decision 263),
            // worked out off the main thread when the track, the platforms,
            // the buildings or the week's city change, as the 3D map lays
            // them. None on a real-world map, which draws its own roads.
            guard session.world.geoAnchor == nil, !session.world.land.isEmpty else {
                streets = nil
                streetsVersion &+= 1
                return
            }
            let world = session.world
            let plan = await Task.detached(priority: .utility) { Map3DScene.seededStreets(world: world) }.value
            guard !Task.isCancelled else { return }
            streets = plan
            streetsVersion &+= 1
        }
        .onChange(of: session.offersCoverageShortcut, initial: true) { _, offered in
            // Decision 311: building shows where people are (or coverage,
            // as the player last chose) over the player's layer, unless
            // they put it away; leaving the tool shows their layer again.
            if offered {
                buildingLayer.choose(PopTravelMode(rawValue: buildingLayerName) ?? .potential)
                buildingLayer.buildingBegan(autoShows: buildingLayerAutoShows)
            } else {
                buildingLayer.buildingEnded()
            }
        }
        .onChange(of: popTravelModeName) {
            // A layer the player chose shows instead (decision 311).
            buildingLayer.playerChoseLayer()
        }
        .onChange(of: potentialKey, initial: true) { _, key in
            potentialMap = key.map(StationPotentialMap.init(key:))
        }
        .onChange(of: mapLayers.popTravelMode) { _, mode in
            cellTooltip = nil
            cityTooltip = nil
            terrainTooltip = nil
            sectionFlowTooltip = nil
            if mode?.usesHour != true { stopPopTravelPlay() }
        }
        .onChange(of: session.world.network, initial: true) { _, network in
            // Edges are immutable and IDs are never reused. Keep their
            // sampled geometry across ticks, pans and zooms; discard removals.
            var next: [TrackEdgeID: MapEdgeDrawing] = [:]
            for edge in network.edges {
                next[edge.id] = edges[edge.id] ?? MapEdgeDrawing(edge: edge, world: session.world)
            }
            edges = next
        }
        .onDisappear {
            // A game left while a pinch rested near the 3D line builds
            // nothing for it afterwards.
            buildAhead?.cancel()
            buildAhead = nil
        }
    }

    /// Decision 304: the real lines on a real-world map and their trains,
    /// worked out off the main actor; none on a map of no real place, or
    /// when the player turned them off.
    private func workOutRealTrains() async {
        guard showsRealTrains, let frame = RealWorldFrame(world: session.world),
              let operations = session.railways?.operations else {
            realTrains = nil
            realTrainClock = nil
            return
        }
        let bounds = session.world.bounds
        // Decision 315: a bought line runs the company's trains, not these.
        let bought = Set(session.world.acquisitions.map(\.realLine))
        let traffic = await Task.detached(priority: .utility) {
            RealTrainTraffic(operations: operations, frame: frame, bounds: bounds, bought: bought)
        }.value
        guard !Task.isCancelled else { return }
        realTrains = traffic.lines.isEmpty ? nil : traffic
        realTrainsVersion &+= 1
        realTrainClock = realTrains == nil ? nil : RealTrainClock(world: session.world, time: Date().timeIntervalSinceReferenceDate)
    }

    /// Decision 311: the building layer's switches in its legend.
    private var buildingLegend: PopulationLegendView.Building {
        PopulationLegendView.Building(
            choice: Binding(
                get: { buildingLayer.choice },
                set: { mode in
                    buildingLayer.choose(mode)
                    buildingLayerName = buildingLayer.choice.rawValue
                }
            ),
            period: Binding(get: { potentialPeriod }, set: { potentialPeriodName = $0.rawValue }),
            hasDrafts: potentialMap?.key.hasDrafts ?? !session.lineDraft.isEmpty
        )
    }

    /// What the base canvas draws of the population and travel layer, or
    /// `nil` for nothing.
    private func popTravelLayer(realWorld: RealWorldFrame?) -> PopTravelLayer? {
        guard let mode = mapLayers.popTravelMode else { return nil }
        let alpha = opacity(for: mode)
        switch mode {
        case .population:
            if let heatmap, realWorld != nil {
                return PopTravelLayer(content: .population(heatmap), key: .population(version: heatmapVersion), opacity: alpha)
            }
            // A blank map's people are its land's (Phase 6a).
            guard realWorld == nil, !landTiles.isEmpty else { return nil }
            return PopTravelLayer(content: .travel(landTiles), key: .land(version: landTilesVersion), opacity: alpha)
        case .travel, .movement:
            return PopTravelLayer(
                content: .travel(travelTiles),
                key: .travel(version: travelTilesVersion),
                opacity: alpha
            )
        case .landUse, .landValue, .coverage, .zoning:
            guard let cityMap else { return nil }
            return PopTravelLayer(content: .city(cityMap, mode), key: .city(version: cityMapVersion, mode: mode), opacity: alpha)
        case .terrain:
            guard let terrainMap, !terrainMap.isFlat else { return nil }
            return PopTravelLayer(content: .terrain(terrainMap), key: .terrain(version: terrainMapVersion), opacity: alpha)
        case .sectionFlow:
            // Drawn on the lines by the map canvas, not under them.
            return nil
        case .potential:
            // Decision 311: a canvas of its own over the town, which fades.
            return nil
        }
    }

    /// Whether the building tool zones (decision 98): a one-finger drag on
    /// the map zones cells instead of moving it.
    private var isZoning: Bool {
        session.tool == .building && session.buildingMode == .zone && screen.panel != .lines
    }

    /// The layer's opacity: the player's, or the layer's own until set
    /// (narrow screens, the reference's `innerWidth <= 768`, are compact).
    private func opacity(for mode: PopTravelMode) -> Double {
        screen.popTravelOpacity ?? PopTravel.baseOpacity(for: mode, compactWidth: sizeClass == .compact)
    }

    private func opacityBinding(for mode: PopTravelMode) -> Binding<Double> {
        Binding(
            get: { opacity(for: mode) },
            set: { screen.popTravelOpacity = PopTravel.clampedOpacity($0) }
        )
    }

    /// Play: the next hour every 1.2 s, back to 0 after 23
    /// (`startPopTravelPlay`); played on population, it shows travel
    /// demand, as the reference switches to its travel tab.
    private func togglePopTravelPlay() {
        if screen.isPlayingPopTravel {
            stopPopTravelPlay()
            return
        }
        if mapLayers.popTravelMode == .population || mapLayers.popTravelMode == nil {
            popTravelModeName = PopTravelMode.travel.rawValue
        }
        screen.startPopTravelPlay()
    }

    private func stopPopTravelPlay() {
        screen.stopPopTravelPlay()
    }

    /// Decision 226: whether a finger drawing at `point` (the map's own
    /// coordinates, whose origin lies at `mapOrigin` on the screen) is under
    /// the tools (``GameScreenState/toolsFrame``, with a margin for the
    /// finger); `nil` once it lifts. Set only when it changes, so a drag
    /// redraws the screen twice, not on every move.
    private func noteDrawing(at point: ScreenPoint?, mapOrigin: CGPoint) {
        let under = point.map { point in
            screen.toolsFrame.insetBy(dx: -16, dy: -16)
                .contains(CGPoint(x: CGFloat(point.x) + mapOrigin.x, y: CGFloat(point.y) + mapOrigin.y))
        } ?? false
        if screen.isDrawingUnderTools != under { screen.isDrawingUnderTools = under }
    }

    /// Shows the tapped cell's people and density while the population
    /// layer is on (the reference's `pop-grid-tooltip`); a tap where no one
    /// lives hides it. The tap still selects as it always does.
    /// Decision 269, later (#785's review): builds the 3D scene ahead only
    /// when a pinch rests near the line for a moment, the map still there
    /// when the wait ends, so zooming the 2D map in on the way elsewhere
    /// builds nothing.
    private func buildAheadIfResting(near pinched: PlanCamera) {
        buildAhead?.cancel()
        buildAhead = nil
        guard Map3DHandoff.buildsAhead(referenceSize: pinched.referenceSize) else { return }
        buildAhead = Task {
            try? await Task.sleep(for: .seconds(Map3DHandoff.buildsAfterResting))
            guard !Task.isCancelled, !screen.showsMap3D,
                  let now = camera, Map3DHandoff.buildsAhead(referenceSize: now.referenceSize) else { return }
            Map3DSceneCache.shared.prepare(for: session, focus: (x: now.centerX, y: now.centerY), palette: linePalette)
        }
    }

    private func showCellTooltip(at location: ScreenPoint, projection: PlanCamera) {
        // Decision 178: the passenger load layer's tooltip words the
        // stretch of track tapped: its riders against its trains' capacity.
        if mapLayers.popTravelMode == .sectionFlow {
            cellTooltip = nil
            cityTooltip = nil
            terrainTooltip = nil
            let place = projection.planPoint(at: location)
            let reach = Double(projection.worldDistance(NetworkBuilding.touchRadius))
            let hour = screen.popTravelHour
            sectionFlowTooltip = sectionFlow.nearestSection(toX: place.x, y: place.y, at: hour, within: reach, in: session.world)
                .flatMap { sectionFlow.tooltip(of: $0, at: hour, world: session.world, language: session.language) }
                .map { ($0, location) }
            return
        }
        sectionFlowTooltip = nil
        // Decision 124, H3: the height layer's tooltip says the cell's
        // height and whether it is steep.
        if mapLayers.popTravelMode == .terrain {
            cellTooltip = nil
            cityTooltip = nil
            let place = projection.worldPosition(at: location)
            terrainTooltip = terrainMap?.cellLines(atX: place.x, y: place.y, in: session.language).map { ($0, location) }
            return
        }
        terrainTooltip = nil
        sectionFlowTooltip = nil
        // Phase 6d: a city layer's tooltip says the cell's use, people and
        // land value.
        if mapLayers.popTravelMode?.isCityLayer == true {
            cellTooltip = nil
            let place = projection.worldPosition(at: location)
            cityTooltip = session.world.cityCellInfo(atX: place.x, y: place.y).map { ($0, location) }
            return
        }
        cityTooltip = nil
        guard mapLayers.popTravelMode == .population, let heatmap else {
            cellTooltip = nil
            return
        }
        let place = projection.worldPosition(at: location)
        cellTooltip = heatmap.cellInfo(atX: place.x, y: place.y).map { ($0, location) }
    }

    /// The touch each place the tutorial's step has the player tap takes
    /// on the screen (``GameSession/tutorialPlacesToTap``), in global
    /// coordinates: a tap within ``NetworkBuilding/touchRadius`` reaches it.
    private func tutorialSites(projection: PlanCamera, origin: CGPoint) -> [CGRect] {
        let radius = CGFloat(NetworkBuilding.touchRadius)
        return session.tutorialPlacesToTap.map { place in
            let point = projection.screenPoint(of: place)
            return CGRect(x: origin.x + CGFloat(point.x) - radius, y: origin.y + CGFloat(point.y) - radius, width: 2 * radius, height: 2 * radius)
        }
    }

    /// The camera a game opens on (Stage E1): what it has built, or the
    /// middle of its world, with no station under the screen's controls
    /// (`framing`, #593).
    private func openingCamera(viewport: ScreenSize, clearOf framing: ScreenInsets) -> PlanCamera {
        PlanCamera.opening(
            bounds: session.world.bounds, viewport: viewport, showing: WorldRegion.opening(in: session.world),
            keeping: session.world.stations.map { WorldCoordinate(x: $0.location.x, y: $0.location.y) }, clearOf: framing
        )
    }

    /// The opening camera, remembered as it was set, so that the corners'
    /// controls measured just after can frame it again (``openedCamera``).
    private func openCamera(viewport: ScreenSize, clearOf framing: ScreenInsets) -> PlanCamera {
        let opened = openingCamera(viewport: viewport, clearOf: framing)
        openedCamera = OpenedCamera(camera: opened, at: .now)
        return opened
    }

    /// How long after a camera opens the corners' controls may still be
    /// measured and frame it again: their first layout, not a legend opened
    /// later by the player.
    private static let openingSettles: TimeInterval = 2

    /// Whether the network tool previews a stretch, shown in the
    /// construction HUD at the top of the map.
    private var showsConstructionHUD: Bool {
        session.tool == .network && session.networkPreview != nil
    }

    private var selectionDescription: String {
        let selection = session.selectionText() ?? String(localized: "Nothing selected")
        // Decision 220: the trace's trips, which the arcs show by width.
        guard let trace = journeyTrace, trace.station == tracedStationID, trace.line == tracedLineID,
              let trips = trace.summary(in: session.world, language: session.language) else { return selection }
        return "\(selection). \(trips)"
    }

    /// Decision 220: the station whose journey trace the map draws: the
    /// selected one while its panel is open beside the map, which holding
    /// a station opens (decision 119) as does the station tag's pencil; only
    /// while looking at the map, not building.
    private var tracedStationID: StationID? {
        guard screen.panel == .station, session.tool == .select, session.networkOverlay == nil else { return nil }
        return session.selectedStationID
    }

    /// Decision 276: the line whose journey trace the map draws: the
    /// selected one while the line panel is open beside the map, which
    /// holding a line opens, and no new line is being drafted there; only
    /// while looking at the map, not building.
    private var tracedLineID: LineID? {
        guard screen.panel == .lines, session.tool == .select, session.networkOverlay == nil, session.lineDraft.isEmpty
        else { return nil }
        return session.selectedLineID
    }

    /// Works out the traced station's busiest trips, or the traced line's
    /// (decision 276), for the world as it is, off the main actor (with
    /// network routing each station's day is a search over the whole map),
    /// then draws the arcs out. The same station's or line's trace worked
    /// out again (its demand or the lines changed) replaces the arcs
    /// without drawing them out again.
    private func workOutJourneyTrace() async {
        let station = tracedStationID, line = tracedLineID
        guard station != nil || line != nil else {
            journeyTrace = nil
            return
        }
        let world = session.world
        let trace = await Task.detached(priority: .userInitiated) {
            station.map { world.journeyTrace(of: $0) } ?? line.flatMap { world.journeyTrace(ofLine: $0) }
        }.value
        guard !Task.isCancelled else { return }
        let redraws = journeyTrace?.station != station || journeyTrace?.line != line
        journeyTrace = trace
        guard trace != nil else { return }
        guard redraws else { return }
        let start = Date()
        journeyProgress = JourneyTrace.progress(elapsed: 0, reduceMotion: reduceMotion)
        while journeyProgress < 1 {
            try? await Task.sleep(for: .seconds(JourneyTrace.drawDuration / Double(JourneyTrace.drawSteps)))
            guard !Task.isCancelled else {
                journeyProgress = 1
                return
            }
            journeyProgress = JourneyTrace.progress(elapsed: Date().timeIntervalSince(start), reduceMotion: reduceMotion)
        }
    }

    /// Decision 160: starts choosing a tile of the map to buy, and shows
    /// the land owned and the tiles for sale; again, stops. While choosing
    /// it says so in words, in the accent colour, so the mode is not taken
    /// for building (TestFlight 56.1).
    private func mapExpansionButton(viewport: ScreenSize, cover: MapCover) -> some View {
        Button {
            if session.isChoosingMapTile {
                session.stopChoosingMapTile()
                return
            }
            session.startChoosingMapTile()
            if let region = session.mapExpansionOverlay?.region {
                if session.followedTrain != nil { session.stopFollowingTrain() }
                // Clear of the screen's controls and above the pill, which
                // grows along the bottom (the PR #627–#646 review).
                camera = PlanCamera(bounds: session.world.bounds, viewport: viewport, showing: region,
                                    clearOf: cover.framing(above: ScreenFrame(bottomLeadingFrame), in: viewport))
                session.mapDidMove()
            }
        } label: {
            if session.isChoosingMapTile {
                HStack(spacing: 8) {
                    Image(systemName: "plus.square.dashed")
                    Text(verbatim: session.language.text("Expanding the map", "正在擴建地圖"))
                    Divider().frame(height: 18).overlay(Theme.onAccent.opacity(0.4))
                    Image(systemName: "xmark")
                    Text(verbatim: session.language.text("Done", "結束"))
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Theme.accent, in: Capsule())
                .contentShape(Capsule())
            } else {
                // Decision 336: named, not an icon alone.
                HStack(spacing: 6) {
                    Image(systemName: "plus.square.dashed")
                        .font(.title3)
                    Text(verbatim: session.language.text("Expand Map", "擴建地圖"))
                        .font(.subheadline.weight(.semibold))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .glassBackground(in: Capsule(), interactive: true)
                .contentShape(Capsule())
            }
        }
        .accessibilityLabel(Text(verbatim: session.isChoosingMapTile
            ? session.language.text("Stop expanding the map", "結束擴建地圖")
            : session.language.text("Expand the map", "擴建地圖")))
        .accessibilityIdentifier("map.expansion")
    }

    /// The tapped cell's tooltip of the layer shown (they take no touches,
    /// so the buttons near them can still be tapped).
    @ViewBuilder
    private func cellTooltips(clear: EdgeInsets, viewport: ScreenSize, screenEdges: EdgeInsets) -> some View {
        if let cellTooltip {
            PopulationCellTooltip(info: cellTooltip.info, language: session.language)
                .offset(x: max(clear.leading + 8, min(cellTooltip.at.x + 12, viewport.width - clear.trailing - 220)), y: max(clear.top + 8, min(cellTooltip.at.y + 12, viewport.height - screenEdges.bottom - 80)))
                .allowsHitTesting(false)
        }
        if let cityTooltip {
            CityCellTooltip(info: cityTooltip.info, language: session.language)
                .offset(x: max(clear.leading + 8, min(cityTooltip.at.x + 12, viewport.width - clear.trailing - 280)), y: max(clear.top + 8, min(cityTooltip.at.y + 12, viewport.height - screenEdges.bottom - 130)))
                .allowsHitTesting(false)
        }
        if let sectionFlowTooltip {
            SectionFlowTooltip(text: sectionFlowTooltip.text)
                .offset(x: max(clear.leading + 8, min(sectionFlowTooltip.at.x + 12, viewport.width - clear.trailing - 280)), y: max(clear.top + 8, min(sectionFlowTooltip.at.y + 12, viewport.height - screenEdges.bottom - 80)))
                .allowsHitTesting(false)
        }
        if let terrainTooltip {
            TerrainCellTooltip(lines: terrainTooltip.lines, language: session.language)
                .offset(x: max(clear.leading + 8, min(terrainTooltip.at.x + 12, viewport.width - clear.trailing - 280)), y: max(clear.top + 8, min(terrainTooltip.at.y + 12, viewport.height - screenEdges.bottom - 80)))
                .allowsHitTesting(false)
        }
    }

    /// Whether the build's ✕ and ✓ are on the map (``MapBuildConfirm``).
    private var buildPillShown: Bool {
        MapBuildConfirm.isShown(session, panel: screen.panel)
    }

    /// The map's own coordinates, which the controls over it are measured
    /// in.
    nonisolated static let mapArea = "MapView.mapArea"

    private var mapLayersButton: some View {
        Button {
            screen.panel = .mapLayers
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title3)
                .frame(width: 44, height: 44)
                .glassBackground(in: Circle(), interactive: true)
        }
        .accessibilityLabel("Map Layers")
        .accessibilityIdentifier("map.layers")
    }

    /// Whether the zoom-in button zooms: not past the closest zoom, nor
    /// past `limit` (``baseMapZoomLimit``).
    private func canZoomIn(_ camera: PlanCamera, limit: Double?) -> Bool {
        guard camera.canZoomIn else { return false }
        guard let limit else { return true }
        return camera.referenceSize < limit * 0.999
    }

    /// UI tests only: whether Apple's map lines up (`map.base`).
    @ViewBuilder
    private func baseMapReadout(shown: Bool) -> some View {
        if Self.readsBaseMap, shown {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("map.base")
                .accessibilityValue(Text(verbatim: baseMapFollowing))
        }
    }

    /// UI tests only: the camera's zoom (`map.camera`, points per world
    /// unit), which building must leave alone (TestFlight 59.1).
    @ViewBuilder
    private func cameraZoomReadout(_ pointsPerUnit: Double) -> some View {
        if Self.readsBaseMap {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("map.camera")
                .accessibilityValue(Text(verbatim: String(pointsPerUnit)))
        }
    }

    /// Where the stations are on the map, in its points ("x,y" each,
    /// split by ";"), under UI tests only: the opening camera keeps them
    /// clear of the corners' buttons (#593).
    @ViewBuilder
    private func stationReadout(_ projection: PlanCamera) -> some View {
        if Self.readsBaseMap {
            let points = session.world.stations.map { station in
                let point = projection.screenPoint(of: station.location)
                return "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
            }
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("map.stations")
                .accessibilityValue(Text(verbatim: points.joined(separator: ";")))
        }
    }

    /// Where the tiles for sale are while choosing one, in the map's
    /// points (the middle of each, "x,y" split by ";"), under UI tests
    /// only: they show clear of the expansion's pill (the PR #627–#646
    /// review).
    @ViewBuilder
    private func expansionTileReadout(_ projection: PlanCamera) -> some View {
        if Self.readsBaseMap, let tiles = session.mapExpansionOverlay?.forSale, session.isChoosingMapTile {
            let points = tiles.map { tile in
                let point = projection.screenPoint(worldX: Double(tile.area.minX + tile.area.maxX) / 2, worldY: Double(tile.area.minY + tile.area.maxY) / 2)
                return "\(Int(point.x.rounded())),\(Int(point.y.rounded()))"
            }
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityIdentifier("map.expansion.tiles")
                .accessibilityValue(Text(verbatim: points.joined(separator: ";")))
        }
    }

    /// Where Apple's map says how it follows, under UI tests only.
    private var baseMapFollowingReport: (@MainActor (String) -> Void)? {
        guard Self.readsBaseMap else { return nil }
        return { baseMapFollowing = $0 }
    }

    /// Apple's map would come no closer than `limit`. Never below MapKit's
    /// level 16 or so: a limit that low would be a mistake.
    private func limitZoom(_ limit: Double) {
        baseMapZoomLimit = max(limit, MapScale.largestSize / 8)
    }

    /// Whether the map reads out how Apple's map follows it
    /// (``FollowingMapView/followingText``): in a Debug build under UI
    /// tests only.
    private static var readsBaseMap: Bool {
        #if DEBUG
        UITestTrace.isOn
        #else
        false
        #endif
    }

    /// The bottom-trailing buttons: coverage, this game's 3D map and the
    /// zoom buttons. `compactReach`: under a phone's panel (decision 300)
    /// they are as tall as the credit button, a finger's target reaching
    /// that many points below them; `nil` as they were.
    @ViewBuilder
    private func cornerButtons(camera: PlanCamera, limit: Double?, zoomGivesWay: Bool, compactReach: CGFloat? = nil) -> some View {
        HStack(alignment: .top, spacing: compactReach == nil ? 0 : 6) {
            // Decisions 292 and 311: the building layer, put away or
            // brought back with one tap while building.
            if session.offersCoverageShortcut {
                MapCoverageButton(isOn: buildingLayer.isOn, language: session.language, compactReach: compactReach) {
                    buildingLayerAutoShows = buildingLayer.toggle()
                }
            }
            // Decision 229, later: this game's 3D map, one tap away, beside
            // the zoom buttons.
            if Map3DShortcut.isShown(zoomButtonsShow: !zoomGivesWay, tutorialRuns: session.tutorial != nil) {
                map3DButton(compactReach: compactReach)
            }
            if !zoomGivesWay {
                zoomControls(camera: camera, limit: limit, compactReach: compactReach)
            }
        }
    }

    /// Decision 229, later: opens this game's 3D map (``Map3DShortcut``),
    /// as round as the overview map's button above it.
    private func map3DButton(compactReach: CGFloat?) -> some View {
        Button {
            screen.map3DHandoff = nil
            // Decision 313, later: over the place the 2D map shows.
            screen.map3DOpenedAt = camera.map { Map3DHandoff.Plan(x: $0.centerX, y: $0.centerY, referenceSize: $0.referenceSize) }
            screen.showsMap3D = true
        } label: {
            Image("Glyph3DMap")
                .resizable()
                .renderingMode(.template)
                .frame(width: compactReach == nil ? 24 : 18, height: compactReach == nil ? 24 : 18)
                .modifier(MapCornerButtonFace(compactReach: compactReach))
        }
        .accessibilityLabel(Text(verbatim: session.language.text("3D Map", "3D 地圖")))
        .accessibilityHint(Text(verbatim: session.language.text("Shows your railway, trains and town in 3D.", "用 3D 看你的鐵路、列車與城鎮。")))
        .accessibilityIdentifier("map.open3D")
        .padding(.vertical, compactReach == nil ? 12 : 0)
    }

    /// `limit`: how close the base map lets the camera come
    /// (``baseMapZoomLimit``). `compactReach` as for ``cornerButtons``.
    @ViewBuilder
    private func zoomControls(camera: PlanCamera, limit: Double?, compactReach: CGFloat? = nil) -> some View {
        if let reach = compactReach {
            let face = CGFloat(MapCornerRow.height)
            zoomButtons(camera: camera, limit: limit, face: face, reach: reach, divider: 16)
                .font(.body)
                .background(alignment: .top) {
                    Color.clear
                        .frame(height: face)
                        .glassBackground(in: Capsule(), interactive: true)
                }
                .tutorialTarget(.zoomControls)
        } else {
            zoomButtons(camera: camera, limit: limit, face: 44, reach: 0, divider: 24)
                .font(.title3)
                .glassBackground(in: Capsule(), interactive: true)
                .tutorialTarget(.zoomControls)
                .padding(12)
        }
    }

    /// The two zoom buttons, `face` points tall, each a finger's target
    /// `reach` points taller below.
    private func zoomButtons(camera: PlanCamera, limit: Double?, face: CGFloat, reach: CGFloat, divider: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Button {
                self.camera = camera.zoomedOut()
                session.mapDidMove()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 44, height: face)
                    .frame(height: face + reach, alignment: .top)
                    .contentShape(Rectangle())
            }
            .disabled(!camera.canZoomOut)
            .accessibilityLabel("Zoom out")

            Divider().frame(height: divider).frame(height: face)

            Button {
                self.camera = camera.zoomedIn()
                session.mapDidMove()
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 44, height: face)
                    .frame(height: face + reach, alignment: .top)
                    .contentShape(Rectangle())
            }
            .disabled(!canZoomIn(camera, limit: limit))
            .accessibilityLabel("Zoom in")
        }
    }

    /// Decision 106, later: moves the camera so the selected station (or,
    /// for `line`, the selected line's stops) shows in the part of the map
    /// the screen's controls leave (`cover`'s framing), in its middle, when
    /// what covers the map hides it now (``PlanCamera/hides(_:under:)``:
    /// under a control, not beside one); a line is zoomed out to fit,
    /// never in. Not
    /// while a train is followed, whose camera stays on it, nor during the
    /// tutorial, whose steps point at places on the map, nor while a
    /// building tool is chosen, whose player is zoomed in on the track
    /// (TestFlight 59.1).
    private func keepSelectionClear(projection: PlanCamera, cover: MapCover, line: Bool) {
        guard session.tool == .select, !session.isFollowingTrain, session.tutorial == nil else { return }
        if line {
            guard let selected = session.selectedLine else { return }
            let stops = selected.stops.compactMap { session.world.station(id: $0) }
                .map { WorldCoordinate(x: $0.location.x, y: $0.location.y) }
            guard let region = WorldRegion(enclosing: stops),
                  stops.contains(where: { projection.hides($0, under: cover) }) else { return }
            camera = projection.showing(region, clearOf: cover.framing(in: projection.viewport))
        } else if let station = session.selectedStation,
                  let moved = projection.keepingClear(WorldCoordinate(x: station.location.x, y: station.location.y), of: cover) {
            // Along an axis the framing leaves almost nothing of, the
            // station keeps its place.
            camera = moved
        }
    }

    /// Whether the camera follows a train that glides between ticks
    /// (decision 182): then it moves with the train every frame.
    private var followsGlide: Bool {
        session.isFollowingTrain && !session.world.clock.isPaused && trainMotion.isMoving
    }

    /// One step of the camera towards the followed train (``FollowCamera``,
    /// the reference's eased follow): once for each world the loop shows,
    /// the time between two the game loop's tick interval; or, at `time`,
    /// a frame `elapsed` after the last, towards where its glide draws it.
    private func centerOnFollowedTrain(projection: PlanCamera, at time: Double? = nil, elapsed: Double = FollowCamera.tickSeconds) {
        guard let train = session.followedTrain,
              let position = train.position,
              let location = session.world.location(of: position)?.position else { return }
        let glided = time.flatMap { trainMotion.head(of: train.id, at: $0) }
        let coordinate = glided ?? TrainMotion.Point(x: Double(location.x), y: Double(location.y))
        let center = followCamera.step(towardX: coordinate.x, y: coordinate.y, elapsed: elapsed)
        let moved = projection.centered(atX: center.x, y: center.y)
        // The tooltip is pinned to a screen point: once the map moves under
        // it, it would describe another cell, as after a pan.
        if moved != projection { cellTooltip = nil; cityTooltip = nil; terrainTooltip = nil; sectionFlowTooltip = nil }
        camera = moved
    }
}

/// The camera a game opened on, and when it was set.
private struct OpenedCamera {
    let camera: PlanCamera
    let at: Date
}

extension ScreenFrame {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

/// What the lines' map (``LineMap``, decision 84) is worked out from: the
/// track and its platforms, the lines' stops, ways, colours and whether they
/// are high-speed lines (decision 168), the
/// stations and the transfer groups; not the trains or the clock, so it is
/// worked out again only after an edit. The small map drawn with it also
/// shows only the tiles owned (decision 160), so buying one, or undoing
/// the purchase, draws it again.
private struct LineMapKey: Equatable {
    struct Line: Equatable {
        let id: LineID
        let stops: [StationID]
        let routes: [LineRoutePreference]
        /// Decision 201: the patterns' calls and routes are drawn too.
        let patterns: [[Int]]
        let patternRoutes: [[LineRoutePreference]]
        let isRing: Bool
        let color: LineColor?
        /// Decision 168: a high-speed line is drawn differently.
        let isHighSpeed: Bool
    }

    let network: RailwayNetwork
    let lines: [Line]
    let stations: [PlanPoint]
    let groups: [TransferGroup]
    let ownedTiles: [MapTile]?

    init(world: GameWorld) {
        network = world.network
        lines = world.lines.map {
            Line(
                id: $0.id, stops: $0.stops, routes: $0.routePreferences, patterns: $0.patterns.map(\.calls),
                patternRoutes: $0.patterns.map(\.routePreferences), isRing: $0.isRing, color: $0.color, isHighSpeed: $0.isHighSpeed
            )
        }
        stations = world.stations.map(\.location)
        groups = world.transferGroups
        ownedTiles = world.mapExpansion?.owned
    }
}

/// What the traffic overlay is worked out from (Stage V4e): the time
/// (a due departure starts a wait), the trains with their routes and
/// reservations, the lines that send them out, the track and whether
/// traffic control is on. The session reads the overlay with each tick
/// (``GameSession/trafficOverlay``); this says when to take it again.
private struct TrafficKey: Equatable {
    let now: GameTime
    let isEnabled: Bool
    let trains: [Train]
    let lines: [ServiceLine]
    let network: RailwayNetwork

    init(world: GameWorld) {
        now = world.clock.now
        isEnabled = world.isTrafficControlEnabled
        trains = world.trains
        lines = world.lines
        network = world.network
    }
}

/// The traffic overlay's key (Stage V4e): how many trains have movement
/// authority, wait and are deadlocked, in the map's colours; read out as
/// the overlay's summary. Shown only while there is something to show, and
/// never in the way of a tap on the map.
private struct TrafficLegend: View {
    let traffic: TrafficOverlay
    let language: DisplayLanguage

    var body: some View {
        if let summary = traffic.summary(in: language) {
            let deadlocked = traffic.waits.filter(\.isDeadlocked).count
            // Theme: kept for Phase 8. The counts are in the traffic
            // overlay's colours on the map.
            // Each count says what it counts (decision 123): "●3" alone
            // meant nothing to a player.
            HStack(spacing: 8) {
                count(traffic.authorities.count, Palette.metroGreen, language.text("cleared", "可行駛"))
                // Decision 205: as the waiting trains' dashed navy rings.
                count(traffic.waits.count - deadlocked, Palette.ink, language.text("waiting", "等候"), dashed: true)
                count(deadlocked, Palette.metroRed, language.text("deadlocked", "死結"))
            }
            .font(.caption2.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassBackground(in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: summary))
            .accessibilityIdentifier("map.traffic")
            .allowsHitTesting(false)
            .padding(12)
        }
    }

    @ViewBuilder
    private func count(_ value: Int, _ color: Color, _ name: String, dashed: Bool = false) -> some View {
        if value > 0 {
            HStack(spacing: 3) {
                if dashed {
                    Circle().strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [2.5, 1.5])).frame(width: 9, height: 9)
                } else {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(verbatim: "\(value) \(name)")
            }
        }
    }
}

/// Clock-only ticks do not redraw the map; camera changes and moving
/// trains do, and so does a change of what traffic control shows.
/// Canvas never allocates a view the size of the whole world.
private struct MapCanvas: View, Equatable {
    let world: GameWorld
    let selectedTrainID: TrainID?
    /// The followed train, whose route is drawn undimmed (as the site
    /// draws a followed train's); the selected train's when none is.
    let highlightedTrainID: TrainID?
    let selectedStationID: StationID?
    let network: NetworkOverlay?
    /// The building tool's site and the city's buildings (decision 95).
    let building: BuildingOverlay?
    /// The tiles of the map owned and for sale (decision 160).
    let expansion: MapExpansionOverlay?
    let traffic: TrafficOverlay
    let camera: PlanCamera
    let edges: [TrackEdgeID: MapEdgeDrawing]
    let layers: MapLayerPreferences
    let waitingCounts: [StationID: Int64]
    let lines: LineMap
    /// Decision 201: the leg of a line the line panel shows on the map.
    let routePreview: RoutePreview?
    let labels: StationLabels
    /// Decision 178: the passenger load layer's strokes in the shown hour,
    /// drawn in place of the lines' colours, and a number that changes with
    /// them (they are compared by it, not stroke by stroke).
    let flowStrokes: [SectionFlow.Stroke]
    let flowVersion: Int
    /// Decision 182: how strongly the stations shine at night.
    let lights: Double
    /// Decision 216: each line's code, for its badges (layers 24.5 and 55).
    let lineCodes: [LineID: String]
    /// Decision 216: compared so that the lines redraw in the new palette
    /// (``Palette/lineColor(_:custom:)`` reads it).
    let linePalette: LinePalette
    /// Decision 220: the held station's busiest trips, and how much of
    /// each arc is drawn yet.
    let journey: JourneyTrace?
    let journeyProgress: Double
    /// Whether the stations' names and waiting counts, the network tool's
    /// preview and the tracks' numbers are drawn here; the map draws them
    /// over the trains instead, in ``MapLabelCanvas``.
    var drawsLabels = true

    /// The trains are drawn over it, by ``MapTrainCanvas`` (decision 182),
    /// so a tick that only moves them does not redraw it.
    nonisolated static func == (lhs: MapCanvas, rhs: MapCanvas) -> Bool {
        // Drawn only with the names (``MapLabelCanvas`` otherwise).
        let labelsMatch = !lhs.drawsLabels || (lhs.waitingCounts == rhs.waitingCounts && lhs.labels == rhs.labels)
        return lhs.world.bounds == rhs.world.bounds
            && lhs.world.stations == rhs.world.stations
            && lhs.world.network == rhs.world.network
            && lhs.world.placedBuildings == rhs.world.placedBuildings
            && lhs.selectedTrainID == rhs.selectedTrainID
            && lhs.highlightedTrainID == rhs.highlightedTrainID
            && lhs.selectedStationID == rhs.selectedStationID
            && lhs.network == rhs.network
            && lhs.building == rhs.building
            && lhs.expansion == rhs.expansion
            && (lhs.building == nil || lhs.world.land == rhs.world.land)
            && lhs.traffic == rhs.traffic
            && lhs.camera == rhs.camera
            && lhs.edges == rhs.edges
            && lhs.layers == rhs.layers
            && labelsMatch
            && lhs.lines == rhs.lines
            && lhs.routePreview == rhs.routePreview
            && lhs.flowVersion == rhs.flowVersion
            && lhs.lights == rhs.lights
            && lhs.lineCodes == rhs.lineCodes
            && lhs.linePalette == rhs.linePalette
            && lhs.journey == rhs.journey
            && lhs.journeyProgress == rhs.journeyProgress
            && lhs.drawsLabels == rhs.drawsLabels
    }

    var body: some View {
        let lights = lights, lineCodes = lineCodes
        let world = world, selectedTrainID = selectedTrainID, highlightedTrainID = highlightedTrainID
        let selectedStationID = selectedStationID, network = network, building = building, expansion = expansion, traffic = traffic, camera = camera, edges = edges, layers = layers, waitingCounts = waitingCounts, lines = lines
        let labels = labels, latitude = world.geoAnchor?.latitudeDegrees ?? 0, flowStrokes = flowStrokes
        let routePreview = routePreview, journey = journey, journeyProgress = journeyProgress, drawsLabels = drawsLabels
        return Canvas { context, size in
            // Decision 328: timed for the frame readout.
            FrameCostMeter.shared.measure(.track) {
                context.clip(to: Path(CGRect(origin: .zero, size: size)))
                MapArt.drawMap(
                    world,
                    selectedTrainID: selectedTrainID,
                    highlightedTrainID: highlightedTrainID,
                    selectedStationID: network == nil ? selectedStationID : nil,
                    network: network,
                    building: building,
                    expansion: expansion,
                    traffic: traffic,
                    projection: camera,
                    edges: edges,
                    layers: layers,
                    waitingCounts: waitingCounts,
                    lines: lines,
                    routePreview: routePreview,
                    labels: labels,
                    flowStrokes: flowStrokes,
                    latitude: latitude,
                    lights: lights,
                    lineCodes: lineCodes,
                    journey: journey,
                    journeyProgress: journeyProgress,
                    drawsLabels: drawsLabels,
                    in: context
                )
            }
        }
    }
}

/// The stations' names and waiting counts (docs/MAP_LAYERS.md 55–57), over
/// the trains: a train stopped at a station never covers them; and over
/// them, as before, the network tool's preview and the tracks' numbers
/// (``MapArt/drawBuildMarks``). Redrawn when the camera, the stations,
/// their lines, the counts, the track or the preview change, never for a
/// moving train.
private struct MapLabelCanvas: View, Equatable {
    let world: GameWorld
    let camera: PlanCamera
    let layers: MapLayerPreferences
    let waitingCounts: [StationID: Int64]
    let labels: StationLabels
    let lineCodes: [LineID: String]
    let linePalette: LinePalette
    let network: NetworkOverlay?
    let routePreview: RoutePreview?
    let edges: [TrackEdgeID: MapEdgeDrawing]

    nonisolated static func == (lhs: MapLabelCanvas, rhs: MapLabelCanvas) -> Bool {
        lhs.world.stations == rhs.world.stations
            // The badges under the names: each line's stops and colour.
            && lhs.world.lines.elementsEqual(rhs.world.lines) { $0.id == $1.id && $0.stops == $1.stops && $0.color == $1.color }
            && lhs.world.geoAnchor == rhs.world.geoAnchor
            && lhs.camera == rhs.camera
            && lhs.layers == rhs.layers
            && lhs.waitingCounts == rhs.waitingCounts
            && lhs.labels == rhs.labels
            && lhs.lineCodes == rhs.lineCodes
            && lhs.linePalette == rhs.linePalette
            && lhs.world.network == rhs.world.network
            && lhs.network == rhs.network
            && lhs.routePreview == rhs.routePreview
            && lhs.edges == rhs.edges
    }

    var body: some View {
        let world = world, camera = camera, layers = layers, waitingCounts = waitingCounts
        let labels = labels, lineCodes = lineCodes, latitude = world.geoAnchor?.latitudeDegrees ?? 0
        let network = network, routePreview = routePreview, edges = edges
        return Canvas { context, size in
            FrameCostMeter.shared.measure(.labels) {
                context.clip(to: Path(CGRect(origin: .zero, size: size)))
                MapArt.drawStationLabels(
                    world, layers: layers, waitingCounts: waitingCounts, labels: labels, latitude: latitude,
                    lineCodes: lineCodes, projection: camera, in: context
                )
                MapArt.drawBuildMarks(world, network: network, routePreview: routePreview, projection: camera, cached: edges, in: context)
            }
        }
        .allowsHitTesting(false)
    }
}

/// What the base canvas draws of the population and travel layer, with a
/// key that says when it changed: the heatmap's layout and the travel
/// squares are compared by a version, not cell by cell. The travel version
/// changes when the squares are stored, not when the hour or demand they
/// are made from does, so the canvas never keeps the previous squares.
struct PopTravelLayer: Equatable {
    enum Content {
        case population(PopulationHeatmap)
        case travel([TravelDemandMap.Tile])
        /// A city layer (Phase 6d), drawn from the city map in view.
        case city(CityMap, PopTravelMode)
        /// The height and steep slope layer (decision 124, H3).
        case terrain(TerrainMap)
    }

    enum Key: Equatable {
        case population(version: Int)
        case travel(version: Int)
        case land(version: Int)
        case city(version: Int, mode: PopTravelMode)
        case terrain(version: Int)
    }

    let content: Content
    let key: Key
    let opacity: Double

    static func == (lhs: PopTravelLayer, rhs: PopTravelLayer) -> Bool {
        lhs.key == rhs.key && lhs.opacity == rhs.opacity
    }
}

/// The city's buildings the base canvas draws (decision 126), compared by
/// a version rather than lot by lot, and the night's growth playing on
/// them (decision 140).
struct SkylineLayer: Equatable {
    struct Growth {
        let growth: SkylineGrowth
        let start: Date
    }

    let skyline: CitySkyline
    let growth: Growth?
    /// A real-world map's: only the growth is drawn (decision 140).
    let growthOnly: Bool
    let version: Int

    static func == (lhs: SkylineLayer, rhs: SkylineLayer) -> Bool {
        lhs.version == rhs.version && lhs.growthOnly == rhs.growthOnly
    }
}

/// The land and the population and travel layer, in a canvas of their own
/// under the map: redrawn only when the camera, the map or the layer
/// changes, not on every tick that moves a train.
private struct MapBaseCanvas: View, Equatable {
    let bounds: WorldBounds
    let drawsLand: Bool
    let skyline: SkylineLayer?
    let layer: PopTravelLayer?
    /// Decision 182: how strongly the town's windows shine at night.
    let lights: Double
    /// Decision 270: the seeded streets, compared by their version.
    let streets: SeededStreetPlan?
    let streetsVersion: Int
    let camera: PlanCamera

    nonisolated static func == (lhs: MapBaseCanvas, rhs: MapBaseCanvas) -> Bool {
        lhs.bounds == rhs.bounds && lhs.drawsLand == rhs.drawsLand && lhs.skyline == rhs.skyline && lhs.layer == rhs.layer
            && lhs.lights == rhs.lights && lhs.camera == rhs.camera && lhs.streetsVersion == rhs.streetsVersion
            && (lhs.streets == nil) == (rhs.streets == nil)
    }

    var body: some View {
        let shown = self.skyline
        let bounds = bounds, drawsLand = drawsLand, growth = shown?.growth, growthOnly = shown?.growthOnly ?? false
        let skyline = shown?.skyline, layer = layer, camera = camera, lights = lights, streets = streets
        // Decision 140: redrawn every frame only while a night's growth
        // plays; otherwise the timeline is paused and the canvas is drawn
        // as before.
        return TimelineView(.animation(paused: growth == nil)) { timeline in
            Canvas { context, size in
                FrameCostMeter.shared.measure(.ground) {
                    context.clip(to: Path(CGRect(origin: .zero, size: size)))
                    MapArt.drawBase(
                        bounds: bounds,
                        drawsLand: drawsLand,
                        skyline: skyline,
                        growth: growth.map { ($0.growth, elapsed: timeline.date.timeIntervalSince($0.start)) },
                        growthOnly: growthOnly,
                        layer: layer,
                        lights: lights,
                        streets: streets,
                        projection: camera,
                        in: context
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Decision 311: where a station would have riders, in a canvas of its
/// own over the base so it can fade in and out; redrawn only when the
/// camera, the map or its opacity changes.
private struct MapPotentialCanvas: View, Equatable {
    let map: StationPotentialMap
    let opacity: Double
    let camera: PlanCamera

    nonisolated static func == (lhs: MapPotentialCanvas, rhs: MapPotentialCanvas) -> Bool {
        lhs.map.key == rhs.map.key && lhs.opacity == rhs.opacity && lhs.camera == rhs.camera
    }

    var body: some View {
        let map = map, opacity = opacity, camera = camera
        return Canvas { context, size in
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            MapArt.drawPotential(map, opacity: opacity, projection: camera, in: context)
        }
        .allowsHitTesting(false)
    }
}

/// Decision 182: the trains, over the map and the time of day's tint, each
/// gliding from where it was at the last tick to where it is, frame by
/// frame while the game runs (``TrainMotion``); drawn where they are while
/// it is paused. Compared by the motion's number, not train by train.
private struct MapTrainCanvas: View, Equatable {
    let motion: TrainMotion
    let version: Int
    let animating: Bool
    let selectedTrainID: TrainID?
    let lights: Double
    /// Every train in the map's train colour (the passenger load layer).
    let plain: Bool
    let traffic: TrafficOverlay
    /// Decision 214: the trains leaving or entering a depot, each with a
    /// plate over its head (layer 51).
    let depotRuns: [TrainID: TrainDepotState]
    /// A deadlocked train's mark beats (decision 64, later fix) unless the
    /// player reduces motion.
    let reduceMotion: Bool
    /// Whether game time runs: the rings round waiting trains pulse only
    /// then (decision 210).
    let running: Bool
    /// The tags' language (decision 210).
    let language: DisplayLanguage
    /// Decision 216: the trains are in their lines' colours.
    let linePalette: LinePalette
    let camera: PlanCamera

    nonisolated static func == (lhs: MapTrainCanvas, rhs: MapTrainCanvas) -> Bool {
        lhs.version == rhs.version && lhs.animating == rhs.animating && lhs.selectedTrainID == rhs.selectedTrainID
            && lhs.lights == rhs.lights && lhs.plain == rhs.plain && lhs.traffic == rhs.traffic && lhs.depotRuns == rhs.depotRuns
            && lhs.reduceMotion == rhs.reduceMotion && lhs.running == rhs.running && lhs.language == rhs.language
            && lhs.linePalette == rhs.linePalette && lhs.camera == rhs.camera
    }

    var body: some View {
        let motion = motion, animating = animating, selectedTrainID = selectedTrainID, lights = lights, plain = plain
        let traffic = traffic, depotRuns = depotRuns, reduceMotion = reduceMotion, running = running, language = language, camera = camera
        // A deadlock beats even while paused; the other waits pulse while
        // the game runs (decision 210).
        let beats = !reduceMotion && (traffic.waits.contains(where: \.isDeadlocked) || (running && !traffic.waits.isEmpty))
        return TimelineView(.animation(paused: !animating && !beats)) { timeline in
            Canvas { context, size in
                FrameCostMeter.shared.measure(.trains) {
                    context.clip(to: Path(CGRect(origin: .zero, size: size)))
                    MapArt.drawTrains(
                        motion,
                        progress: animating ? motion.progress(at: timeline.date.timeIntervalSinceReferenceDate) : 1,
                        selectedTrainID: selectedTrainID,
                        lights: lights,
                        plain: plain,
                        traffic: traffic,
                        depotRuns: depotRuns,
                        deadlock: TrafficOverlay.deadlockStrength(at: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion),
                        pulse: MapProblems.pulse(at: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion, running: running),
                        language: language,
                        projection: camera,
                        in: context
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Decision 304: the real lines' trains (``RealTrainTraffic``), each where
/// its timetable puts it at the game clock, gliding between ticks as the
/// player's trains do (``RealTrainClock``) and drawn where they are while
/// the game is paused or the player reduces motion. Only those on the
/// screen, none when the map is zoomed out past
/// ``RealTrainTraffic/shownFromReferenceSize``, and at most
/// ``RealTrainTraffic/mostDrawn``.
private struct RealTrainCanvas: View, Equatable {
    let traffic: RealTrainTraffic
    /// Compared by its number, not line by line.
    let version: Int
    let clock: RealTrainClock
    let frame: RealWorldFrame
    let animating: Bool
    let camera: PlanCamera

    nonisolated static func == (lhs: RealTrainCanvas, rhs: RealTrainCanvas) -> Bool {
        lhs.version == rhs.version && lhs.clock == rhs.clock && lhs.frame == rhs.frame
            && lhs.animating == rhs.animating && lhs.camera == rhs.camera
    }

    var body: some View {
        let traffic = traffic, clock = clock, frame = frame, animating = animating, camera = camera
        return TimelineView(.animation(paused: !animating)) { timeline in
            Canvas { context, size in
                guard RealTrainTraffic.isShown(referenceSize: camera.referenceSize) else { return }
                FrameCostMeter.shared.measure(.realTrains) {
                    let second = clock.second(at: timeline.date.timeIntervalSinceReferenceDate, glides: animating)
                    let dots = traffic.trains(
                        at: second, on: clock.today, dayBefore: clock.dayBefore, frame: frame,
                        visible: camera.visibleRegion.expanded(by: 12 / camera.pointsPerUnit)
                    )
                    MapArt.drawRealTrains(dots.prefix(RealTrainTraffic.mostDrawn), projection: camera, in: context)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Decision 182: today's weather over the map (``MapWeather``), the rain
/// falling frame by frame unless the player reduces motion, and the sign of
/// a typhoon beside each station it blows over.
private struct MapWeatherLayer: View, Equatable {
    let weather: MapWeather
    let reduceMotion: Bool
    let typhoonStations: [PlanPoint]
    let camera: PlanCamera

    nonisolated static func == (lhs: MapWeatherLayer, rhs: MapWeatherLayer) -> Bool {
        lhs.weather == rhs.weather && lhs.reduceMotion == rhs.reduceMotion && lhs.typhoonStations == rhs.typhoonStations
            && lhs.camera == rhs.camera
    }

    var body: some View {
        let weather = weather, reduceMotion = reduceMotion, typhoonStations = typhoonStations, camera = camera
        return TimelineView(.animation(paused: reduceMotion || weather.sky == .clear)) { timeline in
            Canvas { context, size in
                FrameCostMeter.shared.measure(.weather) {
                    context.clip(to: Path(CGRect(origin: .zero, size: size)))
                    MapArt.drawWeather(
                        weather,
                        time: timeline.date.timeIntervalSinceReferenceDate,
                        reduceMotion: reduceMotion,
                        typhoonStations: typhoonStations.map { camera.screenPoint(of: $0) },
                        stationRadius: MapArt.stationRadius(camera),
                        size: size,
                        in: context
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// What the map's weather is worked out from (decision 182): the day, the
/// world's weather and its stations.
private struct MapWeatherKey: Equatable {
    let day: Int64
    let disruptions: Disruptions?
    let stations: [StationID: PlanPoint]

    init(world: GameWorld) {
        day = world.clock.now.seconds / GameTime.secondsPerDay
        disruptions = world.disruptions
        stations = world.disruptions == nil ? [:] : Dictionary(uniqueKeysWithValues: world.stations.map { ($0.id, $0.point) })
    }
}

/// The tapped population cell (the reference's `pop-grid-tooltip`):
/// "Population grid", its estimated people and its density per km².
private struct PopulationCellTooltip: View {
    let info: PopulationHeatmap.CellInfo
    let language: DisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: language.text("Population grid", "人口網格"))
                .font(.caption.weight(.bold))
            ForEach(info.lines(in: language), id: \.self) { line in
                Text(verbatim: line)
                    .font(.caption2.monospacedDigit())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map.populationTooltip")
    }
}

/// A tapped cell on a city layer (Phase 6d): its use and density, people,
/// land value with its parts, and the station that sets it.
private struct CityCellTooltip: View {
    let info: CityCellInfo
    let language: DisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: language.text("Cell of land", "土地格"))
                .font(.caption.weight(.bold))
            ForEach(info.lines(in: language), id: \.self) { line in
                Text(verbatim: line)
                    .font(.caption2.monospacedDigit())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map.cityTooltip")
    }
}

/// The last skyline the map built (decision 140), kept across the skyline
/// task's cancellations and never observed.
@MainActor
final class SkylineMemory {
    var latest: CitySkyline?
}

/// What the city layers are worked out from (Phase 6d): the land, its
/// buildings, the stations, town growth's measures and whether the land
/// sets ridership; nothing while no city layer is shown.
/// What the plain map's city is made from (decision 126): the land, its
/// buildings and whether the map is a real place's; and the game day, so
/// the skyline is made again each midnight even when nothing grew. Growth
/// is played only between skylines of different days (decision 140), so
/// land read in or handed over the morning after a quiet night is not
/// played as growth against the day before's.
private struct SkylineKey: Equatable {
    /// `nil` on a real-world map whose land does not grow, which draws
    /// none (decision 140: one whose land grows draws what grew).
    let land: Land?
    let buildings: CityBuildings?
    let day: Int64?

    init(world: GameWorld) {
        let drawn = world.geoAnchor == nil || world.landDemand
        land = drawn ? world.land : nil
        buildings = drawn ? world.buildings : nil
        day = drawn ? world.clock.now.seconds / GameTime.secondsPerDay : nil
    }
}

/// What the height and steep slope layer is worked out from (decision
/// 124, H3): the map, its water and steep slopes, and, without the heights
/// file, the ground the world has read; nothing while it is not shown.
private struct TerrainMapKey: Equatable {
    let bounds: WorldBounds?
    let anchor: GeoAnchor?
    let terrain: Terrain?
    let ground: Ground?
    let hasHeights: Bool
    let isShown: Bool

    init(world: GameWorld, hasHeights: Bool, isShown: Bool) {
        self.isShown = isShown
        self.hasHeights = hasHeights
        bounds = isShown ? world.bounds : nil
        anchor = isShown ? world.geoAnchor : nil
        terrain = isShown ? world.terrain : nil
        // With the file a real-world map's heights are the file's; the
        // ground the world reads as track is built changes nothing then.
        ground = isShown && !(hasHeights && world.geoAnchor != nil) ? world.ground : nil
    }
}

/// A tapped cell on the height and steep slope layer (decision 124, H3):
/// its height and whether it is steep.
private struct TerrainCellTooltip: View {
    let lines: [String]
    let language: DisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: language.text("Ground", "地面"))
                .font(.caption.weight(.bold))
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.caption2.monospacedDigit())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map.terrainTooltip")
    }
}

private struct CityMapKey: Equatable {
    let land: Land?
    let buildings: CityBuildings?
    let stations: [Station]
    let growth: TownGrowth?
    let setsRidership: Bool
    /// Decision 98: the zones, and the company's buildings that make zoned
    /// land worth more.
    let zones: Zoning?
    let placed: [PlacedBuilding]
    let isShown: Bool

    init(world: GameWorld, isShown: Bool) {
        self.isShown = isShown
        land = isShown ? world.land : nil
        buildings = isShown ? world.buildings : nil
        stations = isShown ? world.stations : []
        growth = isShown ? world.townGrowth : nil
        zones = isShown ? world.zones : nil
        placed = isShown ? world.placedBuildings : []
        setsRidership = isShown && world.landDemand && world.accounts.mode == .management
    }
}

/// What the real trains are worked out from (decision 304): the map's
/// place and size, whether the real railways have arrived (they can come
/// after the game starts), and whether they are shown.
private struct RealTrainsKey: Equatable {
    let realWorld: RealWorldFrame?
    let bounds: WorldBounds
    let hasData: Bool
    let shown: Bool
    let bought: Set<String>
}

/// What the population heatmap is laid out from: the grid (by its total)
/// and the map.
private struct HeatmapKey: Equatable {
    let total: Int?
    let realWorld: RealWorldFrame?
}

/// What the passenger load layer's sections are worked out from: the lines
/// and trains, whether the world keeps a passenger plan yet, and the game
/// time in six-hour steps (a day's plan changes with the day's events), and
/// whether the layer is shown at all.
private struct SectionFlowKey: Equatable {
    let isShown: Bool
    let hasPlan: Bool
    let lines: [ServiceLine]
    let trains: Int
    let window: Int64

    init(world: GameWorld, isShown: Bool) {
        self.isShown = isShown
        hasPlan = world.keepsPassengerPlan
        // Without when each line last sent a train out, which changes at every
        // departure and which the sections do not read (the passenger plan's
        // key does the same): the layer was worked out again at each one.
        lines = isShown ? world.lines.map(\.withoutDispatchTimes) : []
        trains = isShown ? world.trains.count : 0
        window = isShown ? world.clock.now.seconds / (6 * GameTime.secondsPerHour) : 0
    }
}

/// What the passenger load layer's strokes depend on.
private struct FlowStrokesKey: Equatable {
    let isShown: Bool
    let hour: Int
    let flow: Int
}

/// The passenger load layer's tooltip: a tapped stretch of track.
private struct SectionFlowTooltip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 260, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("map.sectionFlowTooltip")
    }
}

/// What the travel layer's squares depend on.
private struct TravelTilesKey: Equatable {
    let mode: PopTravelMode?
    let hour: Int
    let demand: TravelDemandMap
}

/// What the journey trace (decision 220) is worked out from, so the map
/// works it out again only when one of them changes, not on every tick:
/// the traced station and what its day reads (``RidershipInputs``).
private struct JourneyTraceKey: Equatable {
    let station: StationID?
    /// Decision 276: the traced line, and its stops.
    let line: LineID?
    let stops: [StationID]?
    let inputs: RidershipInputs?

    init(world: GameWorld, station: StationID?, line: LineID? = nil) {
        self.station = station
        self.line = line
        stops = line.flatMap { world.line(id: $0)?.stops }
        inputs = station == nil && line == nil ? nil : RidershipInputs(world: world)
    }
}

/// What the travel demand map is worked out from (``RidershipInputs``,
/// what each station's day of demand reads, as the station panel's), and
/// whether a travel layer is shown at all; not when a line last sent a
/// train out, which none of it reads.
private struct TravelDemandKey: Equatable {
    let inputs: RidershipInputs?

    init(world: GameWorld, isShown: Bool) {
        inputs = isShown ? RidershipInputs(world: world) : nil
    }
}

/// What a painting drag did (decisions 98 and 102).
enum MapPaintPhase {
    case moved
    case ended
    case cancelled
}

/// The map's whole rectangle but for a hole round each of `holes`: where
/// the game draws nothing, so a real-world map's attribution shows
/// (decision 120).
private struct AttributionCutout: Shape {
    let holes: [CGRect]

    func path(in rect: CGRect) -> Path {
        guard !holes.isEmpty else { return Path(rect) }
        var cut = Path()
        for hole in holes {
            cut.addRoundedRect(in: hole.insetBy(dx: -4, dy: -4), cornerSize: CGSize(width: 6, height: 6))
        }
        return Path(rect).subtracting(cut)
    }
}

/// The view the map's gestures are on. A touch inside `passesThrough`
/// is not its, so it reaches what is under the map there.
private final class MapGestureView: UIView {
    var passesThrough: [CGRect] = []

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        return !passesThrough.contains { $0.insetBy(dx: -4, dy: -4).contains(point) }
    }
}

/// UIKit recognizers arbitrate taps, single-finger drags and pinches:
/// navigating must never also select a point for the construction tool.
/// A pinch uses its starting camera and centroid, including centroid drift.
private struct MapGestures: UIViewRepresentable {
    let camera: PlanCamera
    /// Where a touch goes past the gestures to what is under the map: a
    /// real-world map's attribution (decision 120).
    let passesThrough: [CGRect]
    let onCameraChange: (PlanCamera) -> Void
    /// Whether a one-finger drag that begins at a point paints (decision
    /// 98's zoning, decision 102's track) rather than moving the map:
    /// `onPaint` gets where it began, where the finger is and whether it
    /// moved, lifted or was cancelled (a second finger cancels it and
    /// moves the map). Near the edge of the view a painting finger scrolls
    /// the map that way, and where it began moves with the map.
    let paintsFrom: (ScreenPoint) -> Bool
    let onPaint: (ScreenPoint, ScreenPoint, MapPaintPhase) -> Void
    /// Whether a finger held still at a point picks something there
    /// (decision 119), and what holding it does. Where it picks nothing,
    /// the touch stays a tap however long it is held.
    let holdsAt: (ScreenPoint) -> Bool
    let onHold: (ScreenPoint) -> Void
    /// Decision 269: each step of a pinch that brings the map closer, with
    /// the camera it left (after ``onCameraChange``).
    let onPinchCloser: (PlanCamera) -> Void
    /// Decision 313: a pinch let go, with the camera it left and the zoom
    /// its fingers asked for (the zoom it began at times its scale, which
    /// the closest zoom stops).
    let onPinchEnded: (PlanCamera, Double) -> Void
    let onTap: (ScreenPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MapGestureView {
        let view = MapGestureView()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        // A pointer's wheel and a trackpad's two-finger scroll pan the map,
        // as they scrolled the ScrollView it replaced.
        pan.allowedScrollTypesMask = .all
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.45
        tap.delegate = context.coordinator
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        hold.delegate = context.coordinator
        tap.require(toFail: pan)
        tap.require(toFail: pinch)
        // A hold that picks something is not also a tap; one that picks
        // nothing fails as it would begin, and the touch is a tap.
        tap.require(toFail: hold)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(hold)
        context.coordinator.panRecognizer = pan
        return view
    }

    func updateUIView(_ uiView: MapGestureView, context: Context) {
        uiView.passesThrough = passesThrough
        context.coordinator.parent = self
        context.coordinator.cameraDidUpdate(to: camera)
    }

    static func dismantleUIView(_ uiView: MapGestureView, coordinator: Coordinator) {
        coordinator.stopGliding()
        coordinator.stopEdgeScroll()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MapGestures
        weak var panRecognizer: UIPanGestureRecognizer?
        private var panStart: PlanCamera?
        private var pinchStart: PlanCamera?
        private var pinchAnchor = CGPoint.zero
        /// Decision 313: the zoom the pinch's fingers last asked for.
        private var pinchAsked = 0.0
        /// Where a painting drag began (decision 98), while it goes on.
        private var paintStart: CGPoint?
        /// While a painting finger is near the edge of the view: where it
        /// is, the view's bounds, the camera the scroll has reached and the
        /// last frame's time (decision 102).
        private var edgeFinger: CGPoint?
        private var edgeBounds = CGRect.zero
        private var edgeCamera: PlanCamera?
        private var edgeTimestamp: CFTimeInterval?
        private var edgeLink: CADisplayLink?
        /// How close to the edge a painting finger scrolls the map, and how
        /// fast at the very edge, in points a second.
        private static let edgeZone: CGFloat = 44
        private static let edgeSpeed: CGFloat = 480
        /// The camera the gestures set last: `parent.camera` catches up only
        /// when SwiftUI next updates the view.
        private var latest: PlanCamera?
        /// After a flick the map glides on and slows down, as a scroll view
        /// does (``UIScrollView/DecelerationRate/normal``).
        private var glide: Glide?
        private var displayLink: CADisplayLink?
        /// The touch that stopped a glide: it only stops it, as in a scroll
        /// view, and does not also tap the map.
        private weak var glideStopper: UITouch?

        private struct Glide {
            let start: PlanCamera
            var velocity: CGPoint
            var offset = CGPoint.zero
            var lastTimestamp: CFTimeInterval?
        }

        init(_ parent: MapGestures) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Adding a second finger to an existing drag can start a pinch.
            (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
                || (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Each recognizer is asked about each touch: only the first
            // question about a touch can find the map still gliding.
            if glide != nil {
                stopGliding()
                glideStopper = touch
            } else if let stopper = glideStopper, stopper !== touch {
                glideStopper = nil
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UILongPressGestureRecognizer else { return true }
            let point = gestureRecognizer.location(in: gestureRecognizer.view)
            return parent.holdsAt(ScreenPoint(x: point.x, y: point.y))
        }

        @objc func hold(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            let point = gesture.location(in: gesture.view)
            parent.onHold(ScreenPoint(x: point.x, y: point.y))
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            guard glideStopper == nil else {
                glideStopper = nil
                return
            }
            let point = gesture.location(in: gesture.view)
            parent.onTap(ScreenPoint(x: point.x, y: point.y))
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                stopGliding()
                glideStopper = nil
                let location = gesture.location(in: gesture.view), moved = gesture.translation(in: gesture.view)
                let origin = CGPoint(x: location.x - moved.x, y: location.y - moved.y)
                if pinchStart == nil, parent.paintsFrom(ScreenPoint(x: origin.x, y: origin.y)) {
                    paintStart = origin
                } else {
                    panStart = parent.camera
                    latest = parent.camera
                }
            }
            if let start = paintStart {
                let point = gesture.location(in: gesture.view)
                let from = ScreenPoint(x: start.x, y: start.y), to = ScreenPoint(x: point.x, y: point.y)
                switch gesture.state {
                case .began, .changed:
                    parent.onPaint(from, to, .moved)
                    updateEdgeScroll(finger: point, bounds: gesture.view?.bounds ?? .zero)
                case .ended:
                    paintStart = nil
                    stopEdgeScroll()
                    parent.onPaint(from, to, .ended)
                default:
                    paintStart = nil
                    stopEdgeScroll()
                    parent.onPaint(from, to, .cancelled)
                }
                return
            }
            if gesture.state == .began || gesture.state == .changed || gesture.state == .ended,
               pinchStart == nil, let start = panStart {
                let delta = gesture.translation(in: gesture.view)
                setCamera(start.panned(byX: delta.x, y: delta.y))
                if gesture.state == .ended, let camera = latest {
                    startGliding(from: camera, velocity: gesture.velocity(in: gesture.view))
                }
            }
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                panStart = nil
            }
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began {
                stopGliding()
                glideStopper = nil
                panStart = nil
                // A second finger ends a painting drag without painting.
                if let start = paintStart {
                    paintStart = nil
                    stopEdgeScroll()
                    parent.onPaint(ScreenPoint(x: start.x, y: start.y), ScreenPoint(x: start.x, y: start.y), .cancelled)
                }
                pinchStart = parent.camera
                latest = parent.camera
                pinchAnchor = gesture.location(in: gesture.view)
            }
            // The centroid after a finger lifts is no longer the pinch's
            // centroid. Keep the last two-finger frame instead of jumping.
            if gesture.state == .began || gesture.state == .changed,
               gesture.numberOfTouches >= 2, let start = pinchStart {
                let point = gesture.location(in: gesture.view)
                let anchor = ScreenPoint(x: pinchAnchor.x, y: pinchAnchor.y)
                setCamera(start.zoomed(by: gesture.scale, around: anchor)
                    .panned(byX: point.x - pinchAnchor.x, y: point.y - pinchAnchor.y))
                pinchAsked = start.referenceSize * gesture.scale
                if gesture.scale > 1, let camera = latest { parent.onPinchCloser(camera) }
            }
            if gesture.state == .ended, pinchStart != nil, let camera = latest {
                parent.onPinchEnded(camera, pinchAsked)
            }
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                pinchStart = nil
                // A finger still down goes on dragging from where the pinch
                // left the map, instead of doing nothing until it is lifted.
                if let pan = panRecognizer, pan.state == .began || pan.state == .changed, let camera = latest {
                    pan.setTranslation(.zero, in: pan.view)
                    panStart = camera
                }
            }
        }

        // MARK: Scrolling at the edge while painting (decision 102)

        /// How fast a painting finger at `finger` scrolls the map: nothing
        /// away from the edges, faster the nearer the edge, towards it.
        private func edgeVelocity(finger: CGPoint, bounds: CGRect) -> CGVector {
            func speed(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
                guard high - low > 3 * Self.edgeZone else { return 0 }
                if value < low + Self.edgeZone { return Self.edgeSpeed * (1 - max(0, value - low) / Self.edgeZone) }
                if value > high - Self.edgeZone { return -Self.edgeSpeed * (1 - max(0, high - value) / Self.edgeZone) }
                return 0
            }
            return CGVector(dx: speed(finger.x, bounds.minX, bounds.maxX), dy: speed(finger.y, bounds.minY, bounds.maxY))
        }

        private func updateEdgeScroll(finger: CGPoint, bounds: CGRect) {
            edgeFinger = finger
            edgeBounds = bounds
            if edgeVelocity(finger: finger, bounds: bounds) == .zero {
                stopEdgeScroll()
            } else if edgeLink == nil {
                edgeCamera = parent.camera
                edgeTimestamp = nil
                let link = CADisplayLink(target: self, selector: #selector(edgeStep(_:)))
                link.add(to: .main, forMode: .common)
                edgeLink = link
            }
        }

        func stopEdgeScroll() {
            edgeLink?.invalidate()
            edgeLink = nil
            edgeFinger = nil
            edgeCamera = nil
            edgeTimestamp = nil
        }

        /// One frame of scrolling: the map moves, the ground where the drag
        /// began moves with it, and the painting follows the finger.
        @objc private func edgeStep(_ link: CADisplayLink) {
            guard let start = paintStart, let finger = edgeFinger, let camera = edgeCamera else {
                stopEdgeScroll()
                return
            }
            let elapsed = edgeTimestamp.map { min(link.timestamp - $0, 0.05) } ?? 0
            edgeTimestamp = link.timestamp
            let velocity = edgeVelocity(finger: finger, bounds: edgeBounds)
            guard elapsed > 0, velocity != .zero else { return }
            let dx = Double(velocity.dx) * elapsed, dy = Double(velocity.dy) * elapsed
            let moved = camera.panned(byX: dx, y: dy)
            edgeCamera = moved
            setCamera(moved)
            let shifted = CGPoint(x: start.x + CGFloat(dx), y: start.y + CGFloat(dy))
            paintStart = shifted
            parent.onPaint(ScreenPoint(x: shifted.x, y: shifted.y), ScreenPoint(x: finger.x, y: finger.y), .moved)
        }

        /// Something other than the gestures moved the map (a zoom button,
        /// a turned device, a station chosen far away): a glide must not
        /// undo it on its next frame.
        func cameraDidUpdate(to camera: PlanCamera) {
            if glide != nil, camera != latest {
                stopGliding()
            }
        }

        private func setCamera(_ camera: PlanCamera) {
            latest = camera
            parent.onCameraChange(camera)
        }

        // MARK: Gliding

        /// Below this speed, in points a second, a release just stops.
        private static let minimumGlideSpeed: CGFloat = 60

        private func startGliding(from camera: PlanCamera, velocity: CGPoint) {
            stopGliding()
            guard velocity.x.isFinite, velocity.y.isFinite,
                  hypot(velocity.x, velocity.y) >= Self.minimumGlideSpeed else { return }
            glide = Glide(start: camera, velocity: velocity)
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopGliding() {
            displayLink?.invalidate()
            displayLink = nil
            glide = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            guard var glide else { return stopGliding() }
            // Speed falls by `rate` each millisecond, as in a scroll view;
            // the distance is the exact integral over the frame.
            let elapsed = min(max(link.timestamp - (glide.lastTimestamp ?? link.timestamp - link.duration), 0), 0.05)
            glide.lastTimestamp = link.timestamp
            let rate = Double(UIScrollView.DecelerationRate.normal.rawValue)
            let decay = CGFloat(pow(rate, elapsed * 1_000))
            let distance = CGFloat((pow(rate, elapsed * 1_000) - 1) / (1_000 * log(rate)))
            glide.offset.x += glide.velocity.x * distance
            glide.offset.y += glide.velocity.y * distance
            glide.velocity.x *= decay
            glide.velocity.y *= decay
            let camera = glide.start.panned(byX: glide.offset.x, y: glide.offset.y)
            let stopped = camera == latest
            setCamera(camera)
            // Stop when it is slow, or when the map's edge holds it.
            if stopped || hypot(glide.velocity.x, glide.velocity.y) < Self.minimumGlideSpeed / 2 {
                stopGliding()
            } else {
                self.glide = glide
            }
        }
    }
}

/// The map layers sheet over the stored preferences the map reads
/// (``MapView``'s `@AppStorage` keys), so it can be presented from above
/// both layouts (``ContentView``).
struct StoredMapLayerSheet: View {
    let session: GameSession
    /// Opens the data sources (the map style's credits), in place of the
    /// list.
    let openDataSources: () -> Void
    @AppStorage("realWorldMapStyle") private var mapStyle: AppleMapStyle = .openStreetMap
    @AppStorage("realRailwayTrackStyle") private var trackStyle: RealRailways.TrackStyle = .faint
    @AppStorage("mapShowsStationNames") private var showsStationNames = true
    @AppStorage("mapShowsWaitingCounts") private var showsWaitingCounts = true
    @AppStorage("mapShowsCatchmentRings") private var showsCatchmentRings = true
    @AppStorage("mapPopTravelMode") private var popTravelModeName = ""
    @AppStorage("mapShowsFaresAndStamps") private var showsFaresAndStamps = true

    var body: some View {
        MapLayerSheet(layers: Binding(
            get: {
                MapLayerPreferences(
                    showsStationNames: showsStationNames,
                    showsWaitingCounts: showsWaitingCounts,
                    showsCatchmentRings: showsCatchmentRings,
                    popTravelMode: PopTravelMode(rawValue: popTravelModeName),
                    showsFaresAndStamps: showsFaresAndStamps
                )
            },
            set: { layers in
                showsStationNames = layers.showsStationNames
                showsWaitingCounts = layers.showsWaitingCounts
                showsCatchmentRings = layers.showsCatchmentRings
                popTravelModeName = layers.popTravelMode?.rawValue ?? ""
                showsFaresAndStamps = layers.showsFaresAndStamps
            }
        ), mapStyle: mapStyleSection)
    }

    /// Decision 226, step 3: how Apple's map under a real-world game looks,
    /// and how strongly Taiwan's real railways show on it where there are
    /// any, at the top of the list, where the map's round style menu was;
    /// with the map's data sources. Nothing for a blank map.
    private var mapStyleSection: AnyView? {
        guard let realWorld = RealWorldFrame(world: session.world) else { return nil }
        let showsRailways = session.railways?.lines(near: realWorld.anchor, within: FollowingMapView.railwayReach(of: WorldRegion(bounds: session.world.bounds))).isEmpty == false
        let language = session.language
        // Decision 184, later: drawn from these values alone, so a running
        // game's ticks leave an open picker menu alone (the sheet reads
        // the world, and is drawn again every tick).
        return AnyView(TickStable(StableKey(mapStyle, trackStyle, showsRailways, language)) { Section {
            Picker("Map Style", selection: $mapStyle) {
                ForEach(AppleMapStyle.allCases) { style in
                    Text(style.title)
                        .tag(style)
                }
            }
            .accessibilityIdentifier("map.style")
            if showsRailways {
                Picker(selection: $trackStyle) {
                    ForEach(RealRailways.TrackStyle.allCases) { style in
                        Text(verbatim: style.name(in: language))
                            .tag(style)
                    }
                } label: {
                    Label("Real Railways", systemImage: "tram")
                }
                .accessibilityIdentifier("map.realRailways")
            }
            Button(action: openDataSources) {
                Label("Data Sources", systemImage: "info.circle")
            }
            .accessibilityIdentifier("map.dataSources")
        } header: {
            Text("Map Style")
        } })
    }
}

/// Decision 328: the frame readout a player turns on in Settings: how many
/// frames a second the flat map draws, and, tapped, the longest frame and
/// what each part of the map took (``FrameCostMeter``), as the 3D map
/// shows its CPU and GPU times.
private struct MapFrameReadout: View {
    let language: DisplayLanguage
    @State private var reading: FrameCostReading?
    @State private var showsDetails = false
    @State private var link = FrameReadoutLink()

    var body: some View {
        Button {
            showsDetails.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: reading.map { "\(Int($0.framesPerSecond.rounded())) fps" } ?? "– fps")
                    .font(.headline.monospacedDigit())
                if showsDetails, let reading {
                    ForEach(reading.lines(in: language), id: \.self) { line in
                        Text(verbatim: line)
                    }
                    .font(.caption.monospacedDigit())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("map.frameRate")
        .onAppear { link.start { reading = $0 } }
        .onDisappear { link.stop() }
    }
}

/// The display link behind ``MapFrameReadout``: it fires when the main
/// thread is free to draw a frame, so its gaps are the main thread busy.
@MainActor
private final class FrameReadoutLink: NSObject {
    private var link: CADisplayLink?
    private var onReading: ((FrameCostReading) -> Void)?

    func start(_ onReading: @escaping (FrameCostReading) -> Void) {
        self.onReading = onReading
        guard link == nil else { return }
        FrameCostMeter.shared.isOn = true
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onReading = nil
        FrameCostMeter.shared.isOn = false
    }

    @objc private func frame(_ link: CADisplayLink) {
        if let reading = FrameCostMeter.shared.frame(at: link.timestamp) { onReading?(reading) }
    }
}
