import GameCore
import GamePresentation
import SwiftUI
import UIKit

/// A viewport-sized map. The camera and derived geometry are view state;
/// taps still go through the session's ordinary world commands.
struct MapView: View {
    let session: GameSession
    @State private var camera: PlanCamera?
    @State private var edges: [TrackEdgeID: MapEdgeDrawing] = [:]

    var body: some View {
        GeometryReader { proxy in
            let map = session.world.map
            let viewport = ScreenSize(width: proxy.size.width, height: proxy.size.height)
            let projection = camera?.resized(to: viewport) ?? PlanCamera(map: map, viewport: viewport)

            MapCanvas(
                world: session.world,
                selectedTrainID: session.selectedTrainID,
                selection: session.selection,
                selectedStationID: session.selectedStation?.id,
                network: session.networkOverlay,
                camera: projection,
                edges: edges
            )
            .equatable()
            .overlay {
                MapGestures(camera: projection, onCameraChange: { camera = $0 }) { location in
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
            .accessibilityLabel("Map, \(map.width) by \(map.height) tiles")
            .accessibilityIdentifier(TutorialTarget.map.rawValue)
            .accessibilityValue(selectionDescription)
            .accessibilityHint("Use the actions to move the selected tile.")
            .accessibilityAction(named: "Select tile to the north") { moveSelection(.north, camera: projection) }
            .accessibilityAction(named: "Select tile to the east") { moveSelection(.east, camera: projection) }
            .accessibilityAction(named: "Select tile to the south") { moveSelection(.south, camera: projection) }
            .accessibilityAction(named: "Select tile to the west") { moveSelection(.west, camera: projection) }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                zoomControls(camera: projection)
            }
            .onChange(of: viewport, initial: true) { _, size in
                camera = camera?.resized(to: size) ?? PlanCamera(map: map, viewport: size)
            }
            .onChange(of: WorldRegion(map: map)) { _, _ in
                camera = PlanCamera(map: map, viewport: viewport)
            }
            .onChange(of: session.selectedStation?.id) { _, _ in
                // A station chosen in the overview may be kilometres away.
                if let station = session.selectedStation {
                    camera = projection.centered(on: WorldCoordinate(x: station.location.x, y: station.location.y))
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

    private var selectionDescription: String {
        session.selectionText() ?? String(localized: "Nothing selected")
    }

    private func moveSelection(_ direction: TrackDirection, camera: PlanCamera) {
        session.moveSelection(direction)
        if let selection = session.selection {
            self.camera = camera.centered(on: WorldCoordinate(centreOf: selection))
        }
    }

    private func zoomControls(camera: PlanCamera) -> some View {
        HStack(spacing: 0) {
            Button {
                self.camera = camera.zoomedOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .disabled(!camera.canZoomOut)
            .accessibilityLabel("Zoom out")

            Divider().frame(height: 24)

            Button {
                self.camera = camera.zoomedIn()
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
    let selection: GridPosition?
    let selectedStationID: StationID?
    let network: NetworkOverlay?
    let camera: PlanCamera
    let edges: [TrackEdgeID: MapEdgeDrawing]

    nonisolated static func == (lhs: MapCanvas, rhs: MapCanvas) -> Bool {
        lhs.world.map == rhs.world.map
            && lhs.world.stations == rhs.world.stations
            && lhs.world.trains == rhs.world.trains
            && lhs.world.network == rhs.world.network
            && lhs.selectedTrainID == rhs.selectedTrainID
            && lhs.selection == rhs.selection
            && lhs.selectedStationID == rhs.selectedStationID
            && lhs.network == rhs.network
            && lhs.camera == rhs.camera
            && lhs.edges == rhs.edges
    }

    var body: some View {
        let world = world, selectedTrainID = selectedTrainID, selection = selection
        let selectedStationID = selectedStationID, network = network, camera = camera, edges = edges
        return Canvas { context, size in
            context.clip(to: Path(CGRect(origin: .zero, size: size)))
            TileArt.drawMap(
                world,
                selectedTrainID: selectedTrainID,
                selection: network == nil ? selection : nil,
                selectedStationID: network == nil ? selectedStationID : nil,
                network: network,
                projection: camera,
                edges: edges,
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
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        tap.require(toFail: pan)
        tap.require(toFail: pinch)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: MapGestures
        private var panStart: PlanCamera?
        private var pinchStart: PlanCamera?
        private var pinchAnchor = CGPoint.zero

        init(_ parent: MapGestures) { self.parent = parent }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Adding a second finger to an existing drag can start a pinch.
            (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
                || (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let point = gesture.location(in: gesture.view)
            parent.onTap(ScreenPoint(x: point.x, y: point.y))
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { panStart = parent.camera }
            if gesture.state == .began || gesture.state == .changed || gesture.state == .ended,
               pinchStart == nil, let start = panStart {
                let delta = gesture.translation(in: gesture.view)
                parent.onCameraChange(start.panned(byX: delta.x, y: delta.y))
            }
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                panStart = nil
            }
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began {
                panStart = nil
                pinchStart = parent.camera
                pinchAnchor = gesture.location(in: gesture.view)
            }
            // The centroid after a finger lifts is no longer the pinch's
            // centroid. Keep the last two-finger frame instead of jumping.
            if gesture.state == .began || gesture.state == .changed,
               gesture.numberOfTouches >= 2, let start = pinchStart {
                let point = gesture.location(in: gesture.view)
                let anchor = ScreenPoint(x: pinchAnchor.x, y: pinchAnchor.y)
                parent.onCameraChange(start.zoomed(by: gesture.scale, around: anchor)
                    .panned(byX: point.x - pinchAnchor.x, y: point.y - pinchAnchor.y))
            }
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                pinchStart = nil
            }
        }
    }
}
