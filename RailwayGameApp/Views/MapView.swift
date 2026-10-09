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
}

/// A viewport-sized map. The camera and derived geometry are view state;
/// taps still go through the session's ordinary world commands.
struct MapView: View {
    let session: GameSession
    /// The parent keeps this view state across portrait/landscape layouts.
    @Binding var camera: PlanCamera?
    @State private var edges: [TrackEdgeID: MapEdgeDrawing] = [:]
    /// How Apple's map under a real-world game looks (Stage E2): a view
    /// preference, the same for every game.
    @AppStorage("realWorldMapStyle") private var mapStyle: AppleMapStyle = .standard
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
    /// The city tooltip of the last tapped cell, and where it was tapped.
    @State private var cityTooltip: (info: CityCellInfo, at: ScreenPoint)?
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// What floats over the map (``EnvironmentValues/mapInsets``).
    @Environment(\.mapInsets) private var insets
    @Environment(\.mapTrailingInsetDepth) private var trailingInsetDepth
    /// The height of the bottom-trailing buttons and key, with their margin.
    @State private var bottomTrailingHeight: CGFloat = 0
    /// What the map shows of traffic control (Stage V4e), worked out when
    /// the world changes, not on every pan or zoom.
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
            // A real-world map (Stage E2) keeps a strip at its bottom for
            // Apple's logo and legal link; the game's map is the rest.
            let realWorld = RealWorldFrame(world: session.world)
            let strip = realWorld == nil ? 0 : AppleMapBackground.attributionHeight
            let viewport = ScreenSize(width: proxy.size.width, height: max(proxy.size.height - strip, 1))
            let projection = camera?.resized(to: viewport) ?? openingCamera(viewport: viewport)

            VStack(spacing: 0) {
                ZStack {
                    // The land and the population and travel layer: redrawn
                    // only when the camera or the layer changes, never for
                    // a moving train.
                    MapBaseCanvas(
                        bounds: bounds,
                        drawsLand: realWorld == nil,
                        layer: popTravelLayer(realWorld: realWorld),
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
                        traffic: traffic,
                        camera: projection,
                        edges: edges,
                        layers: mapLayers,
                        waitingCounts: MapLayers.waitingPassengerCounts(in: session.world),
                        lines: lineMap,
                        labels: stationLabels
                    )
                    .equatable()
                }
                .overlay {
                    MapGestures(camera: projection, onCameraChange: { moved in
                        camera = moved
                        cellTooltip = nil
                        cityTooltip = nil
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
                        if session.tool == .network, screen.panel != .lines {
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
                    .padding(.top, insets.top)
                    .padding(.leading, insets.leading)
                    .padding(.trailing, insets.trailing)
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
                                onTogglePlay: togglePopTravelPlay
                            ) {
                                stopPopTravelPlay()
                                cellTooltip = nil
                                cityTooltip = nil
                                popTravelModeName = ""
                            }
                            .transition(.scale.combined(with: .opacity))
                        } else {
                            // Decision 116: the whole map, small; it gives
                            // way to a layer's legend, which needs the height.
                            MiniMapView(map: miniMap, visible: projection.visibleRegion, language: session.language) { point in
                                if session.followedTrain != nil { session.stopFollowingTrain() }
                                camera = projection.centered(atX: point.x, y: point.y)
                                session.mapDidMove()
                            }
                            .padding(.trailing, 12)
                        }
                        zoomControls(camera: projection)
                    }
                    .padding(12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomTrailingHeight = $0 }
                    // Beside the trailing controls only where they reach:
                    // under a folded control card the edge is free.
                    .padding(.trailing, viewport.height - bottomTrailingHeight >= trailingInsetDepth ? 0 : insets.trailing)
                    .animation(.easeInOut(duration: 0.2), value: trailingInsetDepth)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 8) {
                        mapLayersButton
                        if let realWorld {
                            mapStyleMenu(realWorld)
                        }
                    }
                    .padding(12)
                    // Above the dock (decision 106), beside the tools
                    // (decision 114).
                    .padding(.bottom, insets.bottom)
                    .padding(.leading, insets.leading)
                }
                // Decision 107: flags at the ends of the track previewed,
                // and beside it, or the building shown, cancel and build.
                .overlay(alignment: .topLeading) {
                    MapBuildConfirm(session: session, camera: projection, viewport: viewport, insets: insets)
                }
                // Decision 109: what needs the player, over its stations.
                .overlay(alignment: .topLeading) {
                    MapAlertBubbles(session: session, camera: projection, viewport: viewport, insets: insets)
                }
                // Decision 119: the station selected, looked at.
                .overlay(alignment: .topLeading) {
                    MapStationTagView(session: session, camera: projection, viewport: viewport, insets: insets)
                }
                // After the map's own accessibility element, which ignores
                // what lies inside it: the tooltips are read on their own.
                // And after the other overlays, so the legend and the zoom
                // and layer buttons do not cover a tooltip near them (it
                // takes no touches, so they can still be tapped).
                .overlay(alignment: .topLeading) {
                    if let cellTooltip {
                        PopulationCellTooltip(info: cellTooltip.info, language: session.language)
                            .offset(x: max(insets.leading + 8, min(cellTooltip.at.x + 12, viewport.width - insets.trailing - 220)), y: max(insets.top + 8, min(cellTooltip.at.y + 12, viewport.height - 80)))
                            .allowsHitTesting(false)
                    }
                    if let cityTooltip {
                        CityCellTooltip(info: cityTooltip.info, language: session.language)
                            .offset(x: max(insets.leading + 8, min(cityTooltip.at.x + 12, viewport.width - insets.trailing - 280)), y: max(insets.top + 8, min(cityTooltip.at.y + 12, viewport.height - 130)))
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: session.networkPreview != nil)
                .animation(.easeInOut(duration: 0.2), value: session.followedTrain?.id)
                .animation(.easeInOut(duration: 0.2), value: mapLayers.popTravelMode)
                .frame(height: viewport.height)
                if strip > 0 {
                    // Nothing of the game over the strip: Apple's map shows
                    // through, and its legal link can be tapped.
                    Color.clear
                        .frame(height: strip)
                }
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
                                trackStyle: trackStyle,
                                language: session.language
                            )
                        } else {
                            AppleMapBackground(
                                realWorld: realWorld,
                                camera: projection,
                                style: mapStyle,
                                railways: session.railways,
                                trackStyle: trackStyle,
                                language: session.language
                            )
                        }
                    }
                    // Phase 6d: under the land use layer Apple's map, with
                    // its own buildings, is washed out so the cells' uses
                    // read clearly; its legal strip stays as it is.
                    .overlay {
                        if mapLayers.popTravelMode == .landUse {
                            VStack(spacing: 0) {
                                Color(uiColor: .systemBackground).opacity(0.6)
                                Color.clear.frame(height: strip)
                            }
                            .allowsHitTesting(false)
                        }
                    }
                }
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
            .onChange(of: bounds) { _, _ in
                camera = openingCamera(viewport: viewport)
            }
            .onChange(of: session.selectedStation?.id) { _, _ in
                // A station chosen in the overview may be kilometres away.
                // One already in view stays where it is, under the finger
                // that tapped it.
                // While a train is followed the camera stays on it.
                if !session.isFollowingTrain, let station = session.selectedStation {
                    let point = WorldCoordinate(x: station.location.x, y: station.location.y)
                    if !projection.visibleRegion.contains(point) {
                        camera = projection.centered(on: point)
                    }
                }
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
            traffic = session.world.trafficOverlay()
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
        .onChange(of: TravelDemandKey(world: session.world, isShown: mapLayers.popTravelMode?.usesHour == true), initial: true) { _, key in
            if key.isShown {
                travelDemand = session.world.travelDemandMap()
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
        .onChange(of: mapLayers.popTravelMode) { _, mode in
            cellTooltip = nil
            cityTooltip = nil
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
        Menu {
            Picker("Map Style", selection: $mapStyle) {
                ForEach(AppleMapStyle.allCases) { style in
                    Text(style.title)
                        .tag(style)
                }
            }
            if session.railways?.lines(near: realWorld.anchor, within: FollowingMapView.railwayReach(of: WorldRegion(bounds: session.world.bounds))).isEmpty == false {
                Picker(selection: $trackStyle) {
                    ForEach(RealRailways.TrackStyle.allCases) { style in
                        Text(verbatim: style.name(in: session.language))
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

    private func zoomControls(camera: PlanCamera) -> some View {
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
            .disabled(!camera.canZoomIn)
            .accessibilityLabel("Zoom in")
        }
        .font(.title3)
        .glassBackground(in: Capsule(), interactive: true)
        .tutorialTarget(.zoomControls)
        .padding(12)
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
        if moved != projection { cellTooltip = nil; cityTooltip = nil }
        camera = moved
    }
}

/// What the traffic overlay is worked out from (Stage V4e): the time
/// (a due departure starts a wait), the trains with their routes and
/// reservations, the lines that send them out, the track and whether
/// traffic control is on.
/// What the lines' map (``LineMap``, decision 84) is worked out from: the
/// track and its platforms, the lines' stops, ways and colours, the
/// stations and the transfer groups; not the trains or the clock, so it is
/// worked out again only after an edit.
private struct LineMapKey: Equatable {
    struct Line: Equatable {
        let id: LineID
        let stops: [StationID]
        let routes: [LineRoutePreference]
        let isRing: Bool
        let color: LineColor?
    }

    let network: RailwayNetwork
    let lines: [Line]
    let stations: [PlanPoint]
    let groups: [TransferGroup]

    init(world: GameWorld) {
        network = world.network
        lines = world.lines.map { Line(id: $0.id, stops: $0.stops, routes: $0.routePreferences, isRing: $0.isRing, color: $0.color) }
        stations = world.stations.map(\.location)
        groups = world.transferGroups
    }
}

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
            HStack(spacing: 8) {
                count(traffic.authorities.count, Palette.metroGreen)
                count(traffic.waits.count - deadlocked, Palette.metroAmber)
                count(deadlocked, Palette.metroRed)
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
    private func count(_ value: Int, _ color: Color) -> some View {
        if value > 0 {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(verbatim: "\(value)")
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
    let traffic: TrafficOverlay
    let camera: PlanCamera
    let edges: [TrackEdgeID: MapEdgeDrawing]
    let layers: MapLayerPreferences
    let waitingCounts: [StationID: Int64]
    let lines: LineMap
    let labels: StationLabels

    nonisolated static func == (lhs: MapCanvas, rhs: MapCanvas) -> Bool {
        lhs.world.bounds == rhs.world.bounds
            && lhs.world.stations == rhs.world.stations
            && lhs.world.trains == rhs.world.trains
            && lhs.world.network == rhs.world.network
            && lhs.world.placedBuildings == rhs.world.placedBuildings
            && lhs.selectedTrainID == rhs.selectedTrainID
            && lhs.highlightedTrainID == rhs.highlightedTrainID
            && lhs.selectedStationID == rhs.selectedStationID
            && lhs.network == rhs.network
            && lhs.building == rhs.building
            && (lhs.building == nil || lhs.world.land == rhs.world.land)
            && lhs.traffic == rhs.traffic
            && lhs.camera == rhs.camera
            && lhs.edges == rhs.edges
            && lhs.layers == rhs.layers
            && lhs.waitingCounts == rhs.waitingCounts
            && lhs.lines == rhs.lines
            && lhs.labels == rhs.labels
    }

    var body: some View {
        let world = world, selectedTrainID = selectedTrainID, highlightedTrainID = highlightedTrainID
        let selectedStationID = selectedStationID, network = network, building = building, traffic = traffic, camera = camera, edges = edges, layers = layers, waitingCounts = waitingCounts, lines = lines
        let labels = labels, latitude = world.geoAnchor?.latitudeDegrees ?? 0
        return Canvas { context, size in
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            MapArt.drawMap(
                world,
                selectedTrainID: selectedTrainID,
                highlightedTrainID: highlightedTrainID,
                selectedStationID: network == nil ? selectedStationID : nil,
                network: network,
                building: building,
                traffic: traffic,
                projection: camera,
                edges: edges,
                layers: layers,
                waitingCounts: waitingCounts,
                lines: lines,
                labels: labels,
                latitude: latitude,
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
    }

    enum Key: Equatable {
        case population(version: Int)
        case travel(version: Int)
        case land(version: Int)
        case city(version: Int, mode: PopTravelMode)
    }

    let content: Content
    let key: Key
    let opacity: Double

    static func == (lhs: PopTravelLayer, rhs: PopTravelLayer) -> Bool {
        lhs.key == rhs.key && lhs.opacity == rhs.opacity
    }
}

/// The land and the population and travel layer, in a canvas of their own
/// under the map: redrawn only when the camera, the map or the layer
/// changes, not on every tick that moves a train.
private struct MapBaseCanvas: View, Equatable {
    let bounds: WorldBounds
    let drawsLand: Bool
    let layer: PopTravelLayer?
    let camera: PlanCamera

    nonisolated static func == (lhs: MapBaseCanvas, rhs: MapBaseCanvas) -> Bool {
        lhs.bounds == rhs.bounds && lhs.drawsLand == rhs.drawsLand && lhs.layer == rhs.layer && lhs.camera == rhs.camera
    }

    var body: some View {
        let bounds = bounds, drawsLand = drawsLand, layer = layer, camera = camera
        return Canvas { context, size in
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            MapArt.drawBase(bounds: bounds, drawsLand: drawsLand, layer: layer, projection: camera, in: context)
        }
        .allowsHitTesting(false)
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

/// What the city layers are worked out from (Phase 6d): the land, its
/// buildings, the stations, town growth's measures and whether the land
/// sets ridership; nothing while no city layer is shown.
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

/// What the travel demand map is worked out from (``GameWorld/stationFlow(of:)``:
/// the stations, their demand and the lines), and whether a travel layer is
/// shown at all.
/// What the travel layer's squares depend on.
private struct TravelTilesKey: Equatable {
    let mode: PopTravelMode?
    let hour: Int
    let demand: TravelDemandMap
}

private struct TravelDemandKey: Equatable {
    let stations: [Station]
    let demands: [StationDemand?]
    let lines: [ServiceLine]
    let isShown: Bool

    init(world: GameWorld, isShown: Bool) {
        self.isShown = isShown
        if isShown {
            stations = world.stations
            demands = world.stations.map { world.stationDemand(of: $0.id) }
            lines = world.lines
        } else {
            stations = []
            demands = []
            lines = []
        }
    }
}

/// What a painting drag did (decisions 98 and 102).
enum MapPaintPhase {
    case moved
    case ended
    case cancelled
}

/// UIKit recognizers arbitrate taps, single-finger drags and pinches:
/// navigating must never also select a point for the construction tool.
/// A pinch uses its starting camera and centroid, including centroid drift.
private struct MapGestures: UIViewRepresentable {
    let camera: PlanCamera
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

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
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

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.cameraDidUpdate(to: camera)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
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
