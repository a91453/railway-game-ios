import GameCore
import GamePresentation
import SwiftUI
import UIKit

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
    @State private var showsDataSources = false
    @State private var showsMapLayers = false

    private var mapLayers: MapLayerPreferences {
        get {
            MapLayerPreferences(
                showsStationNames: showsStationNames,
                showsWaitingCounts: showsWaitingCounts,
                showsCatchmentRings: showsCatchmentRings
            )
        }
        set {
            showsStationNames = newValue.showsStationNames
            showsWaitingCounts = newValue.showsWaitingCounts
            showsCatchmentRings = newValue.showsCatchmentRings
        }
    }

    private var mapLayersBinding: Binding<MapLayerPreferences> {
        Binding(
            get: { mapLayers },
            set: { mapLayers = $0 }
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
                MapCanvas(
                    world: session.world,
                    selectedTrainID: session.selectedTrainID,
                    selectedStationID: session.selectedStation?.id,
                    network: session.networkOverlay,
                    camera: projection,
                    edges: edges,
                    drawsLand: realWorld == nil,
                    layers: mapLayers,
                    waitingCounts: MapLayers.waitingPassengerCounts(in: session.world)
                )
                .equatable()
                .overlay {
                    MapGestures(camera: projection, onCameraChange: { moved in
                        camera = moved
                        session.mapDidMove()
                    }) { location in
                        let point = projection.planPoint(at: location)
                        let reach = projection.worldDistance(NetworkBuilding.touchRadius)
                        if session.tool == .network {
                            session.tapNetwork(at: point, reach: reach)
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
                .overlay(alignment: .bottomTrailing) {
                    zoomControls(camera: projection)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 8) {
                        mapLayersButton
                        if let realWorld {
                            mapStyleMenu(realWorld)
                        }
                    }
                    .padding(12)
                }
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
                    AppleMapBackground(
                        realWorld: realWorld,
                        camera: projection,
                        style: mapStyle,
                        railways: RealRailways.bundled,
                        trackStyle: trackStyle,
                        language: session.language
                    )
                }
            }
            .sheet(isPresented: $showsDataSources) {
                DataSourcesView(language: session.language)
            }
            .sheet(isPresented: $showsMapLayers) {
                MapLayerSheet(layers: mapLayersBinding)
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
                if let station = session.selectedStation {
                    let point = WorldCoordinate(x: station.location.x, y: station.location.y)
                    if !projection.visibleRegion.contains(point) {
                        camera = projection.centered(on: point)
                    }
                }
            }
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

    /// The camera a game opens on (Stage E1): what it has built, or the
    /// middle of its world.
    private func openingCamera(viewport: ScreenSize) -> PlanCamera {
        PlanCamera(bounds: session.world.bounds, viewport: viewport, showing: WorldRegion.built(in: session.world))
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
            if RealRailways.bundled?.lines(near: realWorld.anchor, within: 16_000).isEmpty == false {
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
                showsDataSources = true
            } label: {
                Label("Data Sources", systemImage: "info.circle")
            }
            .accessibilityIdentifier("map.dataSources")
        } label: {
            Image(systemName: "map")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel("Map Style")
        .accessibilityIdentifier("map.style")
    }

    private var mapLayersButton: some View {
        Button {
            showsMapLayers = true
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
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
        .background(.regularMaterial, in: Capsule())
        .tutorialTarget(.zoomControls)
        .padding(12)
    }
}

/// Clock-only ticks do not redraw the map; camera changes and moving
/// trains do. Canvas never allocates a view the size of the whole world.
private struct MapCanvas: View, Equatable {
    let world: GameWorld
    let selectedTrainID: TrainID?
    let selectedStationID: StationID?
    let network: NetworkOverlay?
    let camera: PlanCamera
    let edges: [TrackEdgeID: MapEdgeDrawing]
    /// Whether the land is filled in: not over Apple's map (Stage E2).
    let drawsLand: Bool
    let layers: MapLayerPreferences
    let waitingCounts: [StationID: Int64]

    nonisolated static func == (lhs: MapCanvas, rhs: MapCanvas) -> Bool {
        lhs.world.bounds == rhs.world.bounds
            && lhs.world.stations == rhs.world.stations
            && lhs.world.trains == rhs.world.trains
            && lhs.world.network == rhs.world.network
            && lhs.selectedTrainID == rhs.selectedTrainID
            && lhs.selectedStationID == rhs.selectedStationID
            && lhs.network == rhs.network
            && lhs.camera == rhs.camera
            && lhs.edges == rhs.edges
            && lhs.drawsLand == rhs.drawsLand
            && lhs.layers == rhs.layers
            && lhs.waitingCounts == rhs.waitingCounts
    }

    var body: some View {
        let world = world, selectedTrainID = selectedTrainID
        let selectedStationID = selectedStationID, network = network, camera = camera, edges = edges, drawsLand = drawsLand, layers = layers, waitingCounts = waitingCounts
        return Canvas { context, size in
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            MapArt.drawMap(
                world,
                selectedTrainID: selectedTrainID,
                selectedStationID: network == nil ? selectedStationID : nil,
                network: network,
                projection: camera,
                edges: edges,
                drawsLand: drawsLand,
                layers: layers,
                waitingCounts: waitingCounts,
                in: context
            )
        }
    }
}

/// UIKit recognizers arbitrate taps, single-finger drags and pinches:
/// navigating must never also select a point for the construction tool.
/// A pinch uses its starting camera and centroid, including centroid drift.
private struct MapGestures: UIViewRepresentable {
    let camera: PlanCamera
    let onCameraChange: (PlanCamera) -> Void
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
        tap.delegate = context.coordinator
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        tap.require(toFail: pan)
        tap.require(toFail: pinch)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        context.coordinator.panRecognizer = pan
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.cameraDidUpdate(to: camera)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopGliding()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MapGestures
        weak var panRecognizer: UIPanGestureRecognizer?
        private var panStart: PlanCamera?
        private var pinchStart: PlanCamera?
        private var pinchAnchor = CGPoint.zero
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
                panStart = parent.camera
                latest = parent.camera
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
