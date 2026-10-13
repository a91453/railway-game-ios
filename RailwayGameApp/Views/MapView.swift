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
    /// The screen's safe area (``ContentView``, decision 120): the map is
    /// drawn to the screen's edges, under the camera housing and the home
    /// indicator, and its banners, keys and buttons keep inside this.
    @Entry var mapSafeArea = EdgeInsets()
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
    @AppStorage("mapShowsWaitingCounts") private var showsWaitingCounts = true
    @AppStorage("mapShowsCatchmentRings") private var showsCatchmentRings = true
    /// Which population and travel layer is shown (``PopTravelMode``'s raw
    /// value, empty for none); a view preference, as the other layers.
    @AppStorage("mapPopTravelMode") private var popTravelModeName = ""
    /// Decision 182: whether the map shows the time of day and the
    /// weather (the settings' switches, on the device).
    @AppStorage(MapAmbienceSettings.dayNightKey) private var showsDayNight = true
    @AppStorage(MapAmbienceSettings.weatherKey) private var showsWeather = true
    /// Decision 182: the trains' moves in the last tick, to draw them
    /// gliding to where they are, and a number that changes with them.
    @State private var trainMotion = TrainMotion()
    @State private var trainMotionVersion = 0
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
    @Environment(\.mapTrailingInsetDepth) private var trailingInsetDepth
    @Environment(\.mapSafeArea) private var safeArea
    /// The height of the bottom-trailing buttons and key, with their margin.
    @State private var bottomTrailingHeight: CGFloat = 0
    /// How far down the column at the top of the map (the status banner,
    /// the construction HUD or the traffic key) reaches.
    @State private var topColumnDepth: CGFloat = 0
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
    /// Where the camera looks while it follows a train (the reference's
    /// eased `_trackCenter`); view state only.
    @State private var followCamera = FollowCamera()

    private var mapLayers: MapLayerPreferences {
        MapLayerPreferences(
            showsStationNames: showsStationNames,
            showsWaitingCounts: showsWaitingCounts,
            showsCatchmentRings: showsCatchmentRings,
            popTravelMode: PopTravelMode(rawValue: popTravelModeName)
        )
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
            let zoomGivesWay = session.tutorial == nil
                && insets.trailing > viewport.width / 3
                && viewport.height - screenEdges.bottom - 92 < screenEdges.top + trailingInsetDepth
            let zoomLimit: Double? = realWorld != nil && mapStyle != .openStreetMap ? baseMapZoomLimit : nil
            let projection = (camera?.resized(to: viewport) ?? openingCamera(viewport: viewport)).limited(toReferenceSize: zoomLimit)
            // Decision 182: the time of day, and how strongly the night's
            // lights shine, in twentieths so that the canvases are redrawn
            // twenty times as they come on, not on every tick.
            let tint = showsDayNight ? DayNight.tint(at: session.world.clock.now) : .day
            let lights = DayNight.step(tint.lights)

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
                        camera: projection
                    )
                    .equatable()
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
                        waitingCounts: MapLayers.waitingPassengerCounts(in: session.world),
                        lines: lineMap,
                        routePreview: session.routePreview,
                        labels: stationLabels,
                        flowStrokes: mapLayers.popTravelMode == .sectionFlow ? flowStrokes : [],
                        flowVersion: flowStrokesVersion,
                        lights: lights
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
                    MapTrainCanvas(
                        motion: trainMotion,
                        version: trainMotionVersion,
                        animating: !session.world.clock.isPaused && trainMotion.isMoving,
                        selectedTrainID: session.selectedTrainID,
                        lights: lights,
                        plain: mapLayers.popTravelMode == .sectionFlow,
                        traffic: traffic,
                        reduceMotion: reduceMotion,
                        camera: projection
                    )
                    .equatable()
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
                                    waitingCounts: MapLayers.waitingPassengerCounts(in: session.world),
                                    lines: lineMap,
                                    routePreview: session.routePreview,
                                    labels: stationLabels,
                                    flowStrokes: mapLayers.popTravelMode == .sectionFlow ? flowStrokes : [],
                                    flowVersion: flowStrokesVersion,
                                    lights: lights
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
                                Text(verbatim: preview.radiusText(in: session.language))
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
                        guard session.tool == .select, screen.panel != .lines else { return false }
                        let reach = projection.worldDistance(NetworkBuilding.touchRadius)
                        return session.world.station(near: projection.planPoint(at: location), within: reach) != nil
                    }, onHold: { location in
                        let reach = projection.worldDistance(NetworkBuilding.touchRadius)
                        if session.holdMap(at: projection.planPoint(at: location), reach: reach) != nil {
                            cellTooltip = nil
                            cityTooltip = nil
                            terrainTooltip = nil
                            sectionFlowTooltip = nil
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            screen.panel = .station
                        }
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
                    // another: the status banner, the train follow bar when
                    // active, then the construction HUD while a stretch is previewed,
                    // or else the traffic key at the leading edge.
                    VStack(spacing: 0) {
                        StatusBanner(session: session)
                        if let train = session.followedTrain {
                            FollowBar(train: train, session: session) {
                                session.stopFollowingTrain()
                            }
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if showsConstructionHUD, let preview = session.networkPreview {
                            MapConstructionHUD(preview: preview, language: session.language)
                                .padding(.top, 12)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else {
                            TrafficLegend(traffic: traffic, language: session.language)
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
                                tracksLevel: terrainMap?.tracksLevel ?? false
                            ) {
                                stopPopTravelPlay()
                                cellTooltip = nil
                                cityTooltip = nil
                                terrainTooltip = nil
                                sectionFlowTooltip = nil
                                popTravelModeName = ""
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
                        if !zoomGivesWay {
                            zoomControls(camera: projection, limit: zoomLimit)
                        }
                    }
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
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 8) {
                        mapLayersButton
                        if let realWorld {
                            mapStyleMenu(realWorld)
                        }
                        // Not while building: beside the tools' Done
                        // button it was tapped by mistake (TestFlight 56.1).
                        if session.showsMapExpansionButton {
                            mapExpansionButton(viewport: viewport)
                        }
                    }
                    .padding(12)
                    // Above the dock (decision 106), beside the tools
                    // (decision 114).
                    .padding(.bottom, clear.bottom)
                    .padding(.leading, clear.leading)
                }
                // Decision 174, later: the sights while building, faint
                // and under the flags below.
                .overlay(alignment: .topLeading) {
                    MapAttractionMarks(session: session, camera: projection, viewport: viewport, insets: clear, isPassive: true)
                }
                // Decision 107: flags at the ends of the track previewed,
                // and beside it, or the building shown, cancel and build.
                .overlay(alignment: .topLeading) {
                    // Under the construction HUD, which shows how long the
                    // track is and what it costs.
                    MapBuildConfirm(session: session, camera: projection, viewport: viewport, insets: EdgeInsets(
                        top: max(clear.top, topColumnDepth), leading: clear.leading,
                        bottom: clear.bottom, trailing: clear.trailing
                    ), mapTop: clear.top)
                    // Its flags and ring are where the track and the site
                    // are, which may be by the attribution.
                    .mask { attribution.fill() }
                }
                // Decision 109: what needs the player, over its stations.
                .overlay(alignment: .topLeading) {
                    MapAlertBubbles(session: session, camera: projection, viewport: viewport, insets: clear)
                }
                // Decision 174: the sights, with their stars.
                .overlay(alignment: .topLeading) {
                    MapAttractionMarks(session: session, camera: projection, viewport: viewport, insets: clear)
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
                // After the map's own accessibility element, which ignores
                // what lies inside it: the tooltips are read on their own.
                // And after the other overlays, so the legend and the zoom
                // and layer buttons do not cover a tooltip near them (it
                // takes no touches, so they can still be tapped).
                .overlay(alignment: .topLeading) {
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
                .animation(.easeInOut(duration: 0.2), value: session.networkPreview != nil)
                .animation(.easeInOut(duration: 0.2), value: session.followedTrain?.id)
                .animation(.easeInOut(duration: 0.2), value: mapLayers.popTravelMode)
                .frame(height: viewport.height)
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
            }
            .onChange(of: isZoning) { _, zoning in
                // Decision 98: zoning shows the zones.
                if zoning {
                    stopPopTravelPlay()
                    popTravelModeName = PopTravelMode.zoning.rawValue
                }
            }
            .onChange(of: viewport, initial: true) { _, size in
                camera = camera?.resized(to: size) ?? openingCamera(viewport: size)
            }
            .onChange(of: mapStyle) { _, _ in
                // Another style's map (satellite imagery or the street
                // map) may come closer, or less close.
                baseMapZoomLimit = nil
            }
            .onChange(of: bounds) { _, _ in
                camera = openingCamera(viewport: viewport)
            }
            .onChange(of: session.selectedStation?.id) { _, _ in
                // A station chosen in the overview may be kilometres away.
                // One already in view stays where it is, under the finger
                // that tapped it.
                // While a train is followed the camera stays on it.
                // Decision 106, later: "in view" is the map the screen's
                // controls leave, and one under them moves to its middle.
                keepSelectionClear(projection: projection, clear: clear, line: false)
            }
            // Decision 106, later: a line chosen in the lines panel, and the
            // selection when a panel opens over it, move into the map the
            // panel leaves.
            .onChange(of: session.selectedLineID) { _, _ in
                keepSelectionClear(projection: projection, clear: clear, line: true)
            }
            .onChange(of: insets.trailing) { _, _ in
                keepSelectionClear(projection: projection, clear: clear, line: session.selectedStation == nil)
            }
            .onChange(of: session.routePreview?.request) { _, _ in
                // Decision 201: a leg shown from the line panel is brought
                // into view when its middle is out of view.
                if !session.isFollowingTrain, let preview = session.routePreview, let focus = preview.focus,
                   !projection.visibleRegion.contains(focus) {
                    camera = projection.centered(on: focus)
                }
            }
            .onChange(of: session.cameraRequest) { _, request in
                // Decision 177: the station master's tap on advice that
                // points at a place (the next town to extend to).
                guard let request else { return }
                camera = projection.centered(on: WorldCoordinate(x: request.location.x, y: request.location.y))
            }
            // Decision 188, later fix: where the places the tutorial's
            // step has the player tap stand, which its card keeps clear of.
            .onChange(of: tutorialSites(projection: projection, origin: proxy.frame(in: .global).origin), initial: true) { _, sites in
                screen.tutorialMapSites = sites
            }
            .onChange(of: session.world.clock) { _, _ in
                centerOnFollowedTrain(projection: projection)
            }
            .onChange(of: session.followedTrain?.id) { _, _ in
                // A new follow snaps to its train, as the reference's
                // cleared `_trackCenter` does.
                followCamera.reset()
                centerOnFollowedTrain(projection: projection)
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
        .onChange(of: MapWeatherKey(world: session.world), initial: true) { _, _ in
            mapWeather = MapWeather(world: session.world)
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

    /// Shows the tapped cell's people and density while the population
    /// layer is on (the reference's `pop-grid-tooltip`); a tap where no one
    /// lives hides it. The tap still selects as it always does.
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
    /// middle of its world.
    private func openingCamera(viewport: ScreenSize) -> PlanCamera {
        PlanCamera(bounds: session.world.bounds, viewport: viewport, showing: WorldRegion.opening(in: session.world))
    }

    /// Whether the network tool previews a stretch, shown in the
    /// construction HUD at the top of the map.
    private var showsConstructionHUD: Bool {
        session.tool == .network && session.networkPreview != nil
    }

    private var selectionDescription: String {
        session.selectionText() ?? String(localized: "Nothing selected")
    }

    /// Chooses how Apple's map under a real-world game looks, and how
    /// strongly Taiwan's real railways show on it where there are any.
    private func mapStyleMenu(_ realWorld: RealWorldFrame) -> some View {
        // Decision 184, later: drawn from these values alone, so a running
        // game's ticks leave the open menu alone.
        let showsRailways = session.railways?.lines(near: realWorld.anchor, within: FollowingMapView.railwayReach(of: WorldRegion(bounds: session.world.bounds))).isEmpty == false
        let language = session.language
        return TickStable(StableKey(mapStyle, trackStyle, showsRailways, language)) {
            Menu {
                Picker("Map Style", selection: $mapStyle) {
                    ForEach(AppleMapStyle.allCases) { style in
                        Text(style.title)
                            .tag(style)
                    }
                }
                if showsRailways {
                    Picker(selection: $trackStyle) {
                        ForEach(RealRailways.TrackStyle.allCases) { style in
                            Text(verbatim: style.name(in: language))
                                .tag(style)
                        }
                    } label: {
                        Label("Real Railways", systemImage: "tram")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("map.realRailways")
                }
                Button {
                    screen.panel = .dataSources
                } label: {
                    Label("Data Sources", systemImage: "info.circle")
                }
                .accessibilityIdentifier("map.dataSources")
            } label: {
                Image(systemName: "map")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .glassBackground(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Map Style")
            .accessibilityIdentifier("map.style")
        }
    }

    /// Decision 160: starts choosing a tile of the map to buy, and shows
    /// the land owned and the tiles for sale; again, stops. While choosing
    /// it says so in words, in the accent colour, so the mode is not taken
    /// for building (TestFlight 56.1).
    private func mapExpansionButton(viewport: ScreenSize) -> some View {
        Button {
            if session.isChoosingMapTile {
                session.stopChoosingMapTile()
                return
            }
            session.startChoosingMapTile()
            if let region = session.mapExpansionOverlay?.region {
                if session.followedTrain != nil { session.stopFollowingTrain() }
                camera = PlanCamera(bounds: session.world.bounds, viewport: viewport, showing: region)
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
                Image(systemName: "plus.square.dashed")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .glassBackground(in: Circle(), interactive: true)
            }
        }
        .accessibilityLabel(Text(verbatim: session.isChoosingMapTile
            ? session.language.text("Stop expanding the map", "結束擴建地圖")
            : session.language.text("Expand the map", "擴建地圖")))
        .accessibilityIdentifier("map.expansion")
    }

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

    /// `limit`: how close the base map lets the camera come
    /// (``baseMapZoomLimit``).
    private func zoomControls(camera: PlanCamera, limit: Double?) -> some View {
        HStack(spacing: 0) {
            Button {
                self.camera = camera.zoomedOut()
                session.mapDidMove()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .disabled(!camera.canZoomOut)
            .accessibilityLabel("Zoom out")

            Divider().frame(height: 24)

            Button {
                self.camera = camera.zoomedIn()
                session.mapDidMove()
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .disabled(!canZoomIn(camera, limit: limit))
            .accessibilityLabel("Zoom in")
        }
        .font(.title3)
        .glassBackground(in: Capsule(), interactive: true)
        .tutorialTarget(.zoomControls)
        .padding(12)
    }

    /// Decision 106, later: moves the camera so the selected station (or,
    /// for `line`, the selected line's stops) shows in the part of the map
    /// the screen's controls leave (`clear`), in its middle, when it does
    /// not show there now; a line is zoomed out to fit, never in. Not
    /// while a train is followed, whose camera stays on it, nor during the
    /// tutorial, whose steps point at places on the map.
    private func keepSelectionClear(projection: PlanCamera, clear: EdgeInsets, line: Bool) {
        guard !session.isFollowingTrain, session.tutorial == nil else { return }
        let free = ScreenInsets(top: clear.top, leading: clear.leading, bottom: clear.bottom, trailing: clear.trailing)
        if line {
            guard let selected = session.selectedLine else { return }
            let stops = selected.stops.compactMap { session.world.station(id: $0) }
                .map { WorldCoordinate(x: $0.location.x, y: $0.location.y) }
            guard let region = WorldRegion(enclosing: stops),
                  !stops.allSatisfy({ projection.showsClear($0, of: free) }) else { return }
            camera = projection.showing(region, clearOf: free)
        } else if let station = session.selectedStation {
            let point = WorldCoordinate(x: station.location.x, y: station.location.y)
            if !projection.showsClear(point, of: free) {
                camera = projection.centered(on: point, clearOf: free)
            }
        }
    }

    /// One step of the camera towards the followed train (``FollowCamera``,
    /// the reference's eased follow), once for each world the loop shows:
    /// the time between two is the game loop's tick interval.
    private func centerOnFollowedTrain(projection: PlanCamera) {
        guard let train = session.followedTrain,
              let position = train.position,
              let coordinate = session.world.location(of: position)?.position else { return }
        let center = followCamera.step(towardX: Double(coordinate.x), y: Double(coordinate.y), elapsed: FollowCamera.tickSeconds)
        let moved = projection.centered(atX: center.x, y: center.y)
        // The tooltip is pinned to a screen point: once the map moves under
        // it, it would describe another cell, as after a pan.
        if moved != projection { cellTooltip = nil; cityTooltip = nil; terrainTooltip = nil; sectionFlowTooltip = nil }
        camera = moved
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

    /// The trains are drawn over it, by ``MapTrainCanvas`` (decision 182),
    /// so a tick that only moves them does not redraw it.
    nonisolated static func == (lhs: MapCanvas, rhs: MapCanvas) -> Bool {
        lhs.world.bounds == rhs.world.bounds
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
            && lhs.waitingCounts == rhs.waitingCounts
            && lhs.lines == rhs.lines
            && lhs.routePreview == rhs.routePreview
            && lhs.labels == rhs.labels
            && lhs.flowVersion == rhs.flowVersion
            && lhs.lights == rhs.lights
    }

    var body: some View {
        let lights = lights
        let world = world, selectedTrainID = selectedTrainID, highlightedTrainID = highlightedTrainID
        let selectedStationID = selectedStationID, network = network, building = building, expansion = expansion, traffic = traffic, camera = camera, edges = edges, layers = layers, waitingCounts = waitingCounts, lines = lines
        let labels = labels, latitude = world.geoAnchor?.latitudeDegrees ?? 0, flowStrokes = flowStrokes
        let routePreview = routePreview
        return Canvas { context, size in
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
                in: context
            )
        }
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
    let camera: PlanCamera

    nonisolated static func == (lhs: MapBaseCanvas, rhs: MapBaseCanvas) -> Bool {
        lhs.bounds == rhs.bounds && lhs.drawsLand == rhs.drawsLand && lhs.skyline == rhs.skyline && lhs.layer == rhs.layer
            && lhs.lights == rhs.lights && lhs.camera == rhs.camera
    }

    var body: some View {
        let shown = self.skyline
        let bounds = bounds, drawsLand = drawsLand, growth = shown?.growth, growthOnly = shown?.growthOnly ?? false
        let skyline = shown?.skyline, layer = layer, camera = camera, lights = lights
        // Decision 140: redrawn every frame only while a night's growth
        // plays; otherwise the timeline is paused and the canvas is drawn
        // as before.
        return TimelineView(.animation(paused: growth == nil)) { timeline in
            Canvas { context, size in
                context.clip(to: Path(CGRect(origin: .zero, size: size)))
                MapArt.drawBase(
                    bounds: bounds,
                    drawsLand: drawsLand,
                    skyline: skyline,
                    growth: growth.map { ($0.growth, elapsed: timeline.date.timeIntervalSince($0.start)) },
                    growthOnly: growthOnly,
                    layer: layer,
                    lights: lights,
                    projection: camera,
                    in: context
                )
            }
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
    /// A deadlocked train's mark beats (decision 64, later fix) unless the
    /// player reduces motion.
    let reduceMotion: Bool
    let camera: PlanCamera

    nonisolated static func == (lhs: MapTrainCanvas, rhs: MapTrainCanvas) -> Bool {
        lhs.version == rhs.version && lhs.animating == rhs.animating && lhs.selectedTrainID == rhs.selectedTrainID
            && lhs.lights == rhs.lights && lhs.plain == rhs.plain && lhs.traffic == rhs.traffic
            && lhs.reduceMotion == rhs.reduceMotion && lhs.camera == rhs.camera
    }

    var body: some View {
        let motion = motion, animating = animating, selectedTrainID = selectedTrainID, lights = lights, plain = plain
        let traffic = traffic, reduceMotion = reduceMotion, camera = camera
        let beats = !reduceMotion && traffic.waits.contains(where: \.isDeadlocked)
        return TimelineView(.animation(paused: !animating && !beats)) { timeline in
            Canvas { context, size in
                context.clip(to: Path(CGRect(origin: .zero, size: size)))
                MapArt.drawTrains(
                    motion,
                    progress: animating ? motion.progress(at: timeline.date.timeIntervalSinceReferenceDate) : 1,
                    selectedTrainID: selectedTrainID,
                    lights: lights,
                    plain: plain,
                    traffic: traffic,
                    deadlock: TrafficOverlay.deadlockStrength(at: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion),
                    projection: camera,
                    in: context
                )
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
    @AppStorage("mapShowsStationNames") private var showsStationNames = true
    @AppStorage("mapShowsWaitingCounts") private var showsWaitingCounts = true
    @AppStorage("mapShowsCatchmentRings") private var showsCatchmentRings = true
    @AppStorage("mapPopTravelMode") private var popTravelModeName = ""

    var body: some View {
        MapLayerSheet(layers: Binding(
            get: {
                MapLayerPreferences(
                    showsStationNames: showsStationNames,
                    showsWaitingCounts: showsWaitingCounts,
                    showsCatchmentRings: showsCatchmentRings,
                    popTravelMode: PopTravelMode(rawValue: popTravelModeName)
                )
            },
            set: { layers in
                showsStationNames = layers.showsStationNames
                showsWaitingCounts = layers.showsWaitingCounts
                showsCatchmentRings = layers.showsCatchmentRings
                popTravelModeName = layers.popTravelMode?.rawValue ?? ""
            }
        ))
    }
}
