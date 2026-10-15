import GameCore
import GamePresentation
import SwiftUI
import UIKit

/// ARCHITECTURE decision 229, step 1: the player's own railway and town in
/// native 3D, full screen, from the settings' preview. It reads the
/// session's world and never changes it; the camera is the view's own.
/// Pinch closer and the map tilts (``Map3DCamera``); drag to move, two
/// fingers to turn. The corner shows how smoothly it runs, which is what
/// this step is for: measuring the 3D map on devices before it replaces
/// the 2D one.
struct Map3DPreviewScreen: View {
    let session: GameSession
    let close: () -> Void
    @State private var scene: Map3DScene?
    @State private var sceneVersion = 0
    @State private var stats: Map3DMetalView.Stats?
    @State private var showsDetails = false
    @State private var feed = Map3DTrainFeed()
    @AppStorage(LinePalette.key) private var linePalette: LinePalette = .standard

    var body: some View {
        let language = DisplayLanguage.app
        ZStack {
            Map3DView(scene: scene, sceneVersion: sceneVersion, lighting: Map3DLighting(at: session.world.clock.now), feed: feed,
                      onStats: { stats = $0 })
                .ignoresSafeArea()
                .accessibilityIdentifier("map3D.view")
            if scene == nil {
                ProgressView()
                    .controlSize(.large)
            }
            VStack {
                HStack(alignment: .top) {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel(Text(verbatim: language.text("Close", "關閉")))
                    .accessibilityIdentifier("map3D.close")
                    Spacer()
                    if let stats {
                        Button {
                            showsDetails.toggle()
                        } label: {
                            statsLabel(stats)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("map3D.stats")
                    }
                }
                Spacer()
                Text(verbatim: language.text("Pinch closer to tilt the map. Drag to move, two fingers to turn.",
                                             "兩指拉近，地圖就會傾斜。拖曳移動，兩指旋轉。"))
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
            .padding()
        }
        .task(id: Map3DSceneKey(world: session.world)) {
            let world = session.world
            let built = await Task.detached(priority: .userInitiated) { Map3DScene(world: world) }.value
            scene = built
            sceneVersion &+= 1
        }
        .onChange(of: session.world.trains, initial: true) { _, _ in
            feed.update(world: session.world, palette: linePalette)
        }
    }

    private func statsLabel(_ stats: Map3DMetalView.Stats) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: "\(Int(stats.framesPerSecond.rounded())) fps")
                .font(.headline.monospacedDigit())
            if showsDetails {
                Group {
                    Text(verbatim: String(format: "CPU %.1f ms · GPU %.1f ms", stats.cpuMilliseconds, stats.gpuMilliseconds))
                    Text(verbatim: "\(stats.drawCalls) draws · \(stats.triangles.formatted()) triangles")
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// What makes the still scene change: track, platforms, the player's
/// buildings, and the city, which grows by night, each week.
private struct Map3DSceneKey: Hashable {
    let edges: Int
    let lastEdge: TrackEdgeID?
    let platforms: Int
    let buildings: Int
    let week: Int64

    init(world: GameWorld) {
        edges = world.network.edges.count
        lastEdge = world.network.edges.last?.id
        platforms = world.network.platforms.count
        buildings = world.placedBuildings.count
        week = world.clock.now.seconds / (7 * GameTime.secondsPerDay)
    }
}

/// The trains between ticks (decision 182), read once a frame by the Metal
/// view: the last tick's motion and the bodies' heights. Not observed:
/// the view draws every frame anyway.
@MainActor
final class Map3DTrainFeed {
    private var motion = TrainMotion()
    private var heights = Map3DTrains.Heights()
    private var palette: LinePalette = .standard

    func update(world: GameWorld, palette: LinePalette) {
        motion = TrainMotion(world: world, previous: motion, time: Date().timeIntervalSinceReferenceDate)
        heights = Map3DTrains.Heights(world: world)
        self.palette = palette
    }

    func frame(in scene: Map3DScene, models: Map3DModelPack?, eye: Map3DPoint) -> Map3DTrains.Frame {
        let progress = motion.isMoving ? motion.progress(at: Date().timeIntervalSinceReferenceDate) : 1
        return Map3DTrains.frame(motion, progress: progress, heights: heights, in: scene, models: models, eye: eye, palette: palette)
    }
}

/// The Metal view in SwiftUI, with its gestures.
private struct Map3DView: UIViewRepresentable {
    let scene: Map3DScene?
    let sceneVersion: Int
    let lighting: Map3DLighting
    let feed: Map3DTrainFeed
    let onStats: @MainActor (Map3DMetalView.Stats) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Decision 230: the train models, made in code once.
    static let models: Map3DModelPack? = Map3DModelPack.standard

    func makeUIView(context: Context) -> UIView {
        guard let view = Map3DMetalView.make() else {
            let label = UILabel()
            label.text = DisplayLanguage.app.text("3D isn't available on this device.", "這台裝置無法顯示 3D。")
            label.textAlignment = .center
            label.numberOfLines = 0
            return label
        }
        context.coordinator.view = view
        if let models = Self.models {
            view.useModels(models)
        }
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.rotate(_:)))
        for recognizer in [pan, pinch, rotation] as [UIGestureRecognizer] {
            recognizer.delegate = context.coordinator
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? Map3DMetalView else { return }
        view.lighting = lighting
        view.onStats = onStats
        guard let scene, context.coordinator.shownVersion != sceneVersion else { return }
        let first = context.coordinator.shownVersion == nil
        context.coordinator.shownVersion = sceneVersion
        view.show(scene)
        let feed = feed, models = Map3DView.models
        view.trains = { eye in feed.frame(in: scene, models: models, eye: eye) }
        if first {
            // Open over the middle of what is built, the whole of it in view.
            let width = Float((scene.region.maxX - scene.region.minX) / Double(WorldCoordinate.unitsPerMetre))
            let height = Float((scene.region.maxY - scene.region.minY) / Double(WorldCoordinate.unitsPerMetre))
            view.camera = Map3DCamera(target: .zero, distance: max(width, height) * 0.9, viewport: view.camera.viewport)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: Map3DMetalView?
        var shownVersion: Int?

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            let moved = recognizer.translation(in: view)
            view.camera = view.camera.panned(dx: Float(moved.x), dy: Float(moved.y))
            recognizer.setTranslation(.zero, in: view)
        }

        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view else { return }
            view.camera = view.camera.zoomed(by: Float(recognizer.scale))
            recognizer.scale = 1
        }

        @objc func rotate(_ recognizer: UIRotationGestureRecognizer) {
            guard let view else { return }
            view.camera = view.camera.turned(by: -Float(recognizer.rotation))
            recognizer.rotation = 0
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
