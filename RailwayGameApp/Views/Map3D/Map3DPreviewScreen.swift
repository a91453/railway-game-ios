import Foundation
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
///
/// Decision 269: a pinch on the 2D map hands it over here (`handedOver`,
/// the 2D map's middle and zoom), and pinched back out past
/// ``Map3DHandoff/closesAt`` it hands the 2D map back (`handBack`).
struct Map3DPreviewScreen: View {
    let session: GameSession
    var handedOver: Map3DHandoff.Plan? = nil
    let close: () -> Void
    var handBack: ((Map3DHandoff.Plan) -> Void)? = nil
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
                      start: handedOver, farOut: farOut, onStats: { stats = $0 })
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
                Text(verbatim: handedOver == nil
                     ? language.text("Pinch closer to tilt the map. Drag to move, two fingers to turn.",
                                     "兩指拉近，地圖就會傾斜。拖曳移動，兩指旋轉。")
                     : language.text("Pinch closer to tilt the map, or out to go back. Drag to move, two fingers to turn.",
                                     "兩指拉近地圖就傾斜，拉遠就回到平面地圖。拖曳移動，兩指旋轉。"))
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
            .padding()
        }
        .task(id: Map3DSceneKey(world: session.world, hasHeights: session.heights != nil)) {
            let built = await Map3DSceneCache.shared.scene(for: session)
            // A newer world or the heights file started another build: a
            // cancelled one may finish after it and must not replace it.
            guard !Task.isCancelled else { return }
            scene = built
            sceneVersion &+= 1
        }
        .onChange(of: session.world.trains, initial: true) { _, _ in
            feed.update(world: session.world, palette: linePalette)
        }
    }

    /// Decision 269: pinched out past the line, the 2D map's view to hand
    /// back; nothing when the 3D button opened this.
    private var farOut: ((Map3DCamera) -> Void)? {
        guard let handBack else { return nil }
        return { camera in
            guard let scene else { return }
            handBack(Map3DHandoff.plan(from: camera, in: scene))
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
                    Text(verbatim: "\(stats.people) people · \(stats.vehicles) vehicles · \(stats.streetDetail)")
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Decision 269: the last scene built, kept while the world it shows
/// stays the same, so the 3D map opens at once when a pinch hands the 2D
/// map over; the 2D map starts it (``prepare(for:)``) as the pinch comes
/// near. One build at a time for each world. Kept for one game: the key
/// counts only what changes within a game, and two new games (a lesson,
/// then free play) both start with no track, no buildings, in week 0.
@MainActor
final class Map3DSceneCache {
    static let shared = Map3DSceneCache()
    private var key: Map3DSceneKey?
    private weak var game: GameSession?
    private var building: Task<Map3DScene, Never>?

    /// Starts building `session`'s scene, unless it is built or building.
    func prepare(for session: GameSession) {
        _ = task(for: session)
    }

    func scene(for session: GameSession) async -> Map3DScene {
        await task(for: session).value
    }

    private func task(for session: GameSession) -> Task<Map3DScene, Never> {
        let key = Map3DSceneKey(world: session.world, hasHeights: session.heights != nil)
        if key == self.key, game === session, let building { return building }
        let world = session.world
        // The ground the world has not read yet, from the heights file,
        // so the blocks it has read do not stand up as cliffs.
        let heights = session.heights
        // Decision 234: on a real-world map, the base map's roads, rivers
        // and cover, read from the file the 2D map draws.
        let tiles = world.geoAnchor == nil ? nil : BaseMapFiles.tiles
        // Decision 239: and the real buildings round Kaohsiung and
        // Taichung Stations.
        let city = world.geoAnchor == nil ? nil : BaseMapFiles.city
        let task = Task.detached(priority: .userInitiated) {
            let baseMap = tiles.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }.flatMap { try? BaseMapTiles(data: $0) }
            return Map3DScene(world: world, baseMap: baseMap, cityTiles: city.map(CityTileArea.areas(in:)) ?? [],
                              heights: heights)
        }
        self.key = key
        game = session
        building = task
        return task
    }
}

/// What makes the still scene change: track, platforms, the player's
/// buildings, and the city, which grows by night, each week; and the
/// heights file, which can arrive after the game opened.
struct Map3DSceneKey: Hashable {
    let hasHeights: Bool
    let edges: Int
    let lastEdge: TrackEdgeID?
    let platforms: Int
    let buildings: Int
    let week: Int64

    init(world: GameWorld, hasHeights: Bool) {
        self.hasHeights = hasHeights
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
    /// Decision 259: the stations' crowds, as the world's passengers say.
    private var activity = Map3DStreetLife.Activity()

    func update(world: GameWorld, palette: LinePalette) {
        motion = TrainMotion(world: world, previous: motion, time: Date().timeIntervalSinceReferenceDate)
        heights = Map3DTrains.Heights(world: world)
        self.palette = palette
        activity = Map3DStreetLife.Activity(world: world)
    }

    /// Decision 259: the people and vehicles of `scene` now, round the
    /// camera's target; standing still with Reduce Motion on.
    func streetLife(in scene: Map3DScene, camera: Map3DCamera, lights: Float, detail: Map3DStreetDetail) -> Map3DStreetLife.Frame {
        // A day's seconds, so the clock stays precise as a Float.
        let time = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86_400)
        return scene.streetLife.frame(target: camera.target, distance: camera.distance, time: time,
                                      still: UIAccessibility.isReduceMotionEnabled, lights: lights, detail: detail, activity: activity)
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
    /// Decision 269: the 2D map's view a pinch handed over, and what to do
    /// when pinched back out past ``Map3DHandoff/closesAt``.
    let start: Map3DHandoff.Plan?
    let farOut: ((Map3DCamera) -> Void)?
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
        context.coordinator.farOut = farOut
        guard let scene, context.coordinator.shownVersion != sceneVersion else { return }
        let first = context.coordinator.shownVersion == nil
        context.coordinator.shownVersion = sceneVersion
        view.show(scene)
        let feed = feed, models = Map3DView.models
        view.trains = { eye in feed.frame(in: scene, models: models, eye: eye) }
        view.streetLife = { camera, lights, detail in feed.streetLife(in: scene, camera: camera, lights: lights, detail: detail) }
        if first, let start {
            // Decision 269: where the 2D map was, as close, straight down.
            view.camera = Map3DHandoff.camera(from: start, in: scene, viewport: view.camera.viewport)
            context.coordinator.handedOverAt = view.camera.distance
        } else if first {
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
        var farOut: ((Map3DCamera) -> Void)?
        /// Decision 269: how far out the camera a pinch handed over opened;
        /// `nil` when the 3D button opened the map.
        var handedOverAt: Float?
        private var handedBack = false

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            let moved = recognizer.translation(in: view)
            view.camera = view.camera.panned(dx: Float(moved.x), dy: Float(moved.y))
            recognizer.setTranslation(.zero, in: view)
        }

        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view else { return }
            let before = view.camera.distance
            view.camera = view.camera.zoomed(by: Float(recognizer.scale))
            recognizer.scale = 1
            // Decision 269: pinched back out past the line, the 2D map takes
            // over again; never as it comes closer, nor on a 3D map the
            // button opened (later fix, 71.1).
            if let farOut, !handedBack,
               Map3DHandoff.handsBack(handedOverAt: handedOverAt, from: before, to: view.camera.distance) {
                handedBack = true
                farOut(view.camera)
            }
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
