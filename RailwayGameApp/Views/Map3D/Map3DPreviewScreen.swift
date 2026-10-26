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
/// the 2D map's middle and zoom), and pinched back out it hands the 2D map
/// back (`handBack`). Decision 313: both only as the fingers lift
/// (``Map3DHandoff/handsBack(handedOverAt:from:to:)``); over the game's
/// map the "2D" button goes back to the 2D map where this one looks
/// (`toMap2D`), and Build to its building tools there (`build`).
/// Decision 269, later: turned from north, a compass under the close
/// button shows where north is; a tap turns the map back.
/// Decision 313, later: it opens over the place the 2D map showed, where a
/// pinch handed it over or the 3D button opened it (`openedAt`), its scene
/// built round that place; from the settings, round what is built.
struct Map3DPreviewScreen: View {
    let session: GameSession
    var handedOver: Map3DHandoff.Plan? = nil
    var openedAt: Map3DHandoff.Plan? = nil
    /// Decision 334: the train on a station's board it opened for, shown
    /// at its platform, ringed.
    var departure: Map3DNextDeparture? = nil
    let close: () -> Void
    var handBack: ((Map3DHandoff.Plan) -> Void)? = nil
    /// Decision 313: back to the 2D map at this view's middle and scale,
    /// in its place of the close button; and the same with the building
    /// tools out. `nil` from the settings, which have no 2D map below.
    var toMap2D: ((Map3DHandoff.Plan) -> Void)? = nil
    var build: ((Map3DHandoff.Plan) -> Void)? = nil
    /// Decision 414: the game screen while the idle mode runs, whose
    /// director picks the view the train is followed from; the controls
    /// are put away and a tap ends the mode (`endAmbient`).
    var ambientScreen: GameScreenState? = nil
    var endAmbient: (() -> Void)? = nil
    @State private var built: Map3DBuiltScene?
    private var scene: Map3DScene? { built?.scene }
    @State private var sceneVersion = 0
    @State private var stats: Map3DMetalView.Stats?
    @State private var showsDetails = false
    @State private var feed = Map3DTrainFeed()
    @State private var compass = Map3DCompassState()
    @State private var cameraLink = Map3DCameraLink()
    @State private var trainLabels = Map3DTrainLabelState()
    /// Decision 403 (續二): the photo of the 3D map just taken, to share.
    @State private var photo = Map3DPhotoState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Decision 403: an iPhone on its side, where the driving strip sits in
    /// the top row so the middle of the screen stays clear.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(LinePalette.key) private var linePalette: LinePalette = .standard
    /// Decision 238's later note: the 3D look chosen in Settings; decision
    /// 365: Off (opened from Settings anyway) draws as Battery Saver.
    @AppStorage(Map3DQuality.key) private var quality: Map3DQuality = .forThisDevice
    /// Decision 339: the real timetables' trains, as on the 2D map.
    @AppStorage(MapAmbienceSettings.realTrainsKey) private var showsRealTrains = true
    /// Decision 333: from where the camera follows a train, kept.
    @AppStorage("map3DFollowView") private var followView: Map3DFollow.View = .back

    var body: some View {
        let language = DisplayLanguage.app
        let driver = self.driver
        let ambient = ambientScreen?.ambient
        ZStack {
            Map3DView(built: built, sceneVersion: sceneVersion, lighting: Map3DLighting(at: session.world.clock.now),
                      weather: Map3DWeather(MapWeather(world: session.world)), feed: feed, trainLabels: trainLabels,
                      start: handedOver, openedAt: openedAt, farOut: farOut, compass: compass, cameraLink: cameraLink, quality: quality.drawn,
                      follow: session.followedTrain.map { Map3DFollow(train: $0.id, view: ambient?.view3D ?? followView) },
                      departure: departure, world: session.world,
                      onStats: { stats = $0 })
                .ignoresSafeArea()
                .accessibilityIdentifier("map3D.view")
            Map3DRainLayer(rain: Map3DRain(MapWeather(world: session.world)), detail: stats?.streetDetail ?? .full,
                           night: Map3DLighting(at: session.world.clock.now).night, underground: stats?.underground ?? false)
                .ignoresSafeArea()
            Map3DTrainLabelsView(state: trainLabels, world: session.world)
                .ignoresSafeArea()
            if built == nil {
                ProgressView()
                    .controlSize(.large)
            }
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let toMap2D {
                            // Decision 313: the way back to the 2D map, said
                            // plainly, where the close button was.
                            Button {
                                leave(to: toMap2D)
                            } label: {
                                Label {
                                    Text(verbatim: "2D")
                                } icon: {
                                    Image(systemName: "map")
                                }
                                .font(.headline)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(.regularMaterial, in: Capsule())
                            }
                            .accessibilityLabel(Text(verbatim: language.text("2D Map", "平面地圖")))
                            .accessibilityHint(Text(verbatim: language.text("Goes back to the flat map, here.", "回到這裡的平面地圖。")))
                            .accessibilityIdentifier("map3D.close")
                        } else {
                            Button(action: close) {
                                Image(systemName: "xmark")
                                    .font(.headline)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                            }
                            .accessibilityLabel(Text(verbatim: language.text("Close", "關閉")))
                            .accessibilityIdentifier("map3D.close")
                        }
                        if let build {
                            // Decision 313: building is on the 2D map; this
                            // takes the player there with the tools out.
                            Button {
                                leave(to: build)
                            } label: {
                                Label {
                                    Text(verbatim: language.text("Build", "建設"))
                                } icon: {
                                    Image(systemName: "hammer.fill")
                                }
                                .font(.headline)
                                .padding(.horizontal, 14)
                                .frame(minWidth: 44, minHeight: 44)
                                .background(.regularMaterial, in: Capsule())
                            }
                            .accessibilityHint(Text(verbatim: language.text("Goes back to the flat map, here, with the track, train and building tools.",
                                                                            "回到這裡的平面地圖，打開軌道、列車與建物的工具。")))
                            .accessibilityIdentifier("map3D.build")
                        }
                        if session.followedTrain == nil {
                            Map3DCompassButton(state: compass)
                        }
                    }
                    Spacer(minLength: 8)
                    if verticalSizeClass == .compact, let driver {
                        Map3DDriverStrip(hud: driver, world: session.world)
                        Spacer(minLength: 8)
                    }
                    // The 3D map covers the status pill: the same pause
                    // and speeds, so a train followed here does not stand
                    // still in a paused game (the owner, 2026-10-22).
                    SpeedControl(session: session, tutorialTarget: nil)
                        .padding(4)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("map3D.speed")
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
                if verticalSizeClass != .compact, let driver {
                    Map3DDriverStrip(hud: driver, world: session.world)
                        .padding(.top, 8)
                        .transition(.card(from: .top, reduceMotion: reduceMotion))
                }
                if let prompt = driver?.promptText(in: language) {
                    Map3DDriverPrompt(text: prompt)
                        .padding(.top, 8)
                        .transition(.card(from: .top, reduceMotion: reduceMotion))
                }
                Spacer()
                if let driver {
                    HStack {
                        Map3DSpeedCard(hud: driver)
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 8)
                    .transition(.card(from: .bottom, reduceMotion: reduceMotion))
                }
                if let train = session.followedTrain {
                    Map3DFollowBar(train: train, session: session, view: $followView, takePhoto: takePhoto)
                        .transition(.card(from: .bottom, reduceMotion: reduceMotion))
                } else {
                    Text(verbatim: handedOver == nil
                         ? language.text("Pinch closer to tilt the map. Drag to move, two fingers to turn.",
                                         "兩指拉近，地圖就會傾斜。拖曳移動，兩指旋轉。")
                         : language.text("Pinch closer to tilt the map, or pinch out and let go to go back. Drag to move, two fingers to turn.",
                                         "兩指拉近地圖就傾斜，拉遠放手就回到平面地圖。拖曳移動，兩指旋轉。"))
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            // Decision 388: on the 2D map's lines (``HUDMargins``), not the
            // 16 points of a plain padding, so nothing jumps between them.
            .padding(CGFloat(HUDMargins.edge))
            .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: session.followedTrain?.id)
            .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: driver?.prompt == nil)
            .ambientHidden(ambient != nil)
            // Decision 414: the idle mode's veil and caption, and its tap.
            if ambient != nil, let ambientScreen, let endAmbient {
                AmbientCurtain(screen: ambientScreen, language: language, end: endAmbient)
            }
        }
        .task(id: Map3DSceneKey(world: session.world, hasHeights: session.heights != nil, hasRailways: session.railways != nil, focus: focus, palette: linePalette)) {
            let built = await Map3DSceneCache.shared.scene(for: session, focus: focus, palette: linePalette)
            // A newer world or the heights file started another build: a
            // cancelled one may finish after it and must not replace it.
            guard !Task.isCancelled else { return }
            self.built = built
            sceneVersion &+= 1
        }
        .onChange(of: session.world.trains, initial: true) { _, _ in
            feed.update(world: session.world, palette: linePalette)
        }
        .onChange(of: session.world.clock.now, initial: true) { _, _ in
            // Decision 339: the real trains glide with the game clock.
            feed.updateRealClock(world: session.world, shown: showsRealTrains,
                                 glides: !session.world.clock.isPaused && !reduceMotion)
            // Decision 400, 10i-6: and the player's buses with it.
            feed.updateBuses(world: session.world, palette: linePalette, glides: !session.world.clock.isPaused && !reduceMotion)
        }
        .onChange(of: showsRealTrains) { _, shown in
            feed.updateRealClock(world: session.world, shown: shown, glides: !session.world.clock.isPaused && !reduceMotion)
        }
        // Decision 360: following a train here runs at 10× at most, and
        // closing gives the 2D map its speed back.
        .onAppear {
            session.setMap3DOpen(true)
            FrameTimeRecorder.shared.show3D(true)
        }
        .onDisappear {
            session.setMap3DOpen(false)
            FrameTimeRecorder.shared.show3D(false)
        }
        .sheet(item: $photo.snapshot) { snapshot in
            Map3DSnapshotSheet(snapshot: snapshot, language: language)
        }
    }

    /// Decision 403 (續二): the 3D map as drawn next, without the cards
    /// over it, to share as the postcard is shared (decision 215).
    private func takePhoto() {
        guard let view = cameraLink.view else { return }
        let title = session.followedTrain.map(\.name) ?? DisplayLanguage.app.text("3D Map", "3D 地圖")
        let photo = photo
        // A real-world map's data, written on the photo as the postcard
        // writes its credit (decision 215).
        let credit = DataSourceCredits.map3DPhoto(realWorld: session.world.geoAnchor != nil, in: DisplayLanguage.app)
        view.capture { image in
            guard let image else { return }
            photo.snapshot = Map3DSnapshot(image: Self.credited(image, credit), title: title)
        }
    }

    /// `image` with `credit` in small type in its lower right corner, on a
    /// dark band so it reads on any sky or ground; as it is when there is
    /// none.
    private static func credited(_ image: UIImage, _ credit: String) -> UIImage {
        guard !credit.isEmpty else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
            let size = max(9, image.size.width / 48)
            let text = NSAttributedString(string: credit, attributes: [
                .font: UIFont.systemFont(ofSize: size, weight: .medium),
                .foregroundColor: UIColor.white,
            ])
            let bounds = text.boundingRect(with: CGSize(width: image.size.width - size * 2, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin], context: nil)
            let pad = size * 0.5
            let band = CGRect(x: image.size.width - bounds.width - pad * 3, y: image.size.height - bounds.height - pad * 3,
                              width: bounds.width + pad * 2, height: bounds.height + pad * 2)
            UIColor.black.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: band, cornerRadius: pad).fill()
            text.draw(with: band.insetBy(dx: pad, dy: pad), options: [.usesLineFragmentOrigin], context: nil)
        }
    }

    /// Decision 403: the driving display of the train followed.
    private var driver: Map3DDriverHUD? {
        session.followedTrain.flatMap { session.world.map3DDriverHUD(of: $0.id, in: DisplayLanguage.app) }
    }

    /// Decision 313, later: the world point the scene is built round.
    private var focus: (x: Double, y: Double)? {
        (handedOver ?? openedAt).map { (x: $0.x, y: $0.y) }
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

    /// Decision 313: the 2D map's view where this one looks, for `go`; or,
    /// before the scene is up, just closes.
    private func leave(to go: (Map3DHandoff.Plan) -> Void) {
        guard let scene, let camera = cameraLink.camera else { return close() }
        go(Map3DHandoff.plan(from: camera, in: scene))
    }

    private func statsLabel(_ stats: Map3DMetalView.Stats) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: "\(Int(stats.framesPerSecond.rounded())) fps")
                .font(.headline.monospacedDigit())
            if showsDetails {
                Group {
                    Text(verbatim: String(format: "CPU %.1f ms · GPU %.1f ms", stats.cpuMilliseconds, stats.gpuMilliseconds))
                    // The CPU waiting for the screen, apart from its work
                    // (the far view's 16.6 ms, 2026-10-21), and the pixels a
                    // point drawn (Map3DDrawScale).
                    Text(verbatim: String(format: "wait %.1f ms · %.0f×", stats.waitMilliseconds, stats.drawScale))
                    Text(verbatim: "\(stats.drawCalls) draws · \(stats.triangles.formatted()) triangles")
                    Text(verbatim: "\(stats.people) people · \(stats.vehicles) vehicles · \(stats.streetDetail)")
                    // Decision 417: the rung climbed to and its budget.
                    if let level = stats.level { Text(verbatim: level.summary) }
                    // Decision 394: the cab deep in a tunnel draws only
                    // what is under the ground.
                    if stats.underground { Text(verbatim: "underground") }
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
/// Decision 269, later (#785's review): let go on the start screen and
/// when the system is short of memory (``clear()``); a 3D map on screen
/// keeps its own scene.
@MainActor
final class Map3DSceneCache {
    static let shared = Map3DSceneCache()
    private var key: Map3DSceneKey?
    private weak var game: GameSession?
    private var building: Task<Map3DBuiltScene, Never>?
    /// What the scene built or building covers.
    private var region: WorldRegion?
    private var memoryWarning: NSObjectProtocol?

    private init() {
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Map3DSceneCache.shared.clear() }
        }
    }

    /// Lets go of the scene built or building; the next 3D map builds anew.
    func clear() {
        key = nil
        game = nil
        building = nil
        region = nil
    }

    /// Starts building `session`'s scene round `focus` (decision 313,
    /// later: the point the 2D map looks at), unless it is built or
    /// building round a point near it (``Map3DScene/FocusArea``) and holds
    /// it (``Map3DScene/holds(_:in:world:)``).
    /// Decision 314: its lines' bands in `palette`, the player's.
    func prepare(for session: GameSession, focus: (x: Double, y: Double)?, palette: LinePalette) {
        _ = task(for: session, focus: focus, palette: palette)
    }

    func scene(for session: GameSession, focus: (x: Double, y: Double)?, palette: LinePalette) async -> Map3DBuiltScene {
        await task(for: session, focus: focus, palette: palette).value
    }

    private func task(for session: GameSession, focus: (x: Double, y: Double)?, palette: LinePalette) -> Task<Map3DBuiltScene, Never> {
        let key = Map3DSceneKey(world: session.world, hasHeights: session.heights != nil, hasRailways: session.railways != nil, focus: focus, palette: palette)
        if key == self.key, game === session, let building, let region, Map3DScene.holds(focus, in: region, world: session.world) {
            return building
        }
        let world = session.world
        // The ground the world has not read yet, from the heights file,
        // so the blocks it has read do not stand up as cliffs.
        let heights = session.heights
        // Decision 326: the real railways, for where the real track has no
        // overhead line.
        let railways = world.geoAnchor == nil ? nil : session.railways
        // Decision 234: on a real-world map, the base map's roads, rivers
        // and cover, read from the file the 2D map draws.
        let tiles = world.geoAnchor == nil ? nil : BaseMapFiles.tiles
        // Decision 239: and the real buildings round Kaohsiung and
        // Taichung Stations.
        let city = world.geoAnchor == nil ? nil : BaseMapFiles.city
        // Decision 331: and Taiwan's temples.
        let temples = world.geoAnchor == nil ? nil : BaseMapFiles.temples
        // Decision 389: and Taiwan's buildings.
        let footprints = world.geoAnchor == nil ? nil : BaseMapFiles.footprints
        // Decision 385: and the land with no town on it.
        let noBuild = world.geoAnchor == nil ? nil : BaseMapFiles.noBuild
        let task = Task.detached(priority: .userInitiated) {
            let baseMap = tiles.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }.flatMap { try? BaseMapTiles(data: $0) }
            let source = Map3DChunkSource(world: world, snapshot: world.railwaySnapshot(), skyline: CitySkyline(world: world), baseMap: baseMap,
                                          cityTiles: city.map(CityTileArea.areas(in:)) ?? [],
                                          footprints: footprints.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }
                                              .flatMap { try? FootprintTiles(data: $0) },
                                          heights: heights,
                                          lineBands: Map3DLineBands(world: world, palette: palette), railways: railways,
                                          temples: temples.flatMap { try? Data(contentsOf: $0) }.flatMap { try? RealTemples(data: $0) },
                                          noBuild: noBuild.flatMap { try? Data(contentsOf: $0) }.flatMap { try? RealNoBuildLand(data: $0) })
            return Map3DBuiltScene(scene: source.scene(focus: focus), source: source)
        }
        self.key = key
        game = session
        building = task
        region = Map3DScene.region(world: world, focus: focus)
        return task
    }
}

/// Decision 358: a scene built, and what it was built from, from which
/// the chunks ahead of the camera are built as it moves.
struct Map3DBuiltScene: Sendable {
    let scene: Map3DScene
    let source: Map3DChunkSource
}

/// Decision 358: what a scene is built from, read once (the files) and
/// worked out once (the snapshot, the skyline), so the chunks built later
/// are the scene's own.
struct Map3DChunkSource: Sendable {
    let world: GameWorld
    let snapshot: RailwaySnapshot
    let skyline: CitySkyline
    let baseMap: BaseMapTiles?
    let cityTiles: [CityTileArea]
    let footprints: FootprintTiles?
    let heights: HeightGrid?
    let lineBands: Map3DLineBands
    let railways: RealRailways?
    let temples: RealTemples?
    let noBuild: RealNoBuildLand?

    func scene(focus: (x: Double, y: Double)?) -> Map3DScene {
        Map3DScene(world: world, snapshot: snapshot, skyline: skyline, focus: focus, baseMap: baseMap, cityTiles: cityTiles,
                   footprints: footprints, heights: heights, lineBands: lineBands, railways: railways, temples: temples, noBuild: noBuild)
    }

    /// Decision 359 (續): with the scene's `trackCover`, which lays the
    /// tunnels as the scene did. Decision 368: the city in full only round
    /// `detail`.
    func chunks(_ keys: [Map3DStreaming.Key], of grid: Map3DStreaming, trackCover: Map3DTrackCover, detail: Map3DPoint) -> [Map3DScene.Chunk] {
        Map3DScene.chunks(keys, of: grid, world: world, snapshot: snapshot, skyline: skyline, baseMap: baseMap, cityTiles: cityTiles,
                          footprints: footprints, heights: heights, lineBands: lineBands, railways: railways, temples: temples, noBuild: noBuild,
                          trackCover: trackCover, detail: detail)
    }
}

/// Decision 358: builds the chunks ahead of the camera as it moves, a
/// block at a time in the background (``Map3DStreaming/Window``), and lets
/// those far behind go; only on a real-world map
/// (``Map3DStreaming/streams(_:)``).
@MainActor
final class Map3DChunkStreamer {
    weak var view: Map3DMetalView?
    private var window: Map3DStreaming.Window?
    private var source: Map3DChunkSource?
    private var trackCover = Map3DTrackCover()
    private var generation = 0

    /// The chunks built since that `scene` (built anew round the same
    /// place) does not hold whole: kept until built again.
    func kept(for scene: Map3DScene) -> Set<Map3DStreaming.Key> {
        guard let window, window.grid.originX == scene.originX, window.grid.originY == scene.originY else { return [] }
        return window.built.subtracting(window.grid.keys(within: scene.region))
    }

    /// `built` is shown, with the view keeping `kept` from before.
    func start(_ built: Map3DBuiltScene?, kept: Set<Map3DStreaming.Key>) {
        generation += 1
        guard let built, Map3DStreaming.streams(built.source.world) else {
            window = nil
            source = nil
            return
        }
        window = Map3DStreaming.Window(scene: built.scene, map: WorldRegion(bounds: built.source.world.bounds), generation: generation, kept: kept)
        source = built.source
        trackCover = built.scene.trackCover
    }

    /// The camera this frame, at `time`.
    func step(_ camera: Map3DCamera, at time: CFTimeInterval) {
        guard var window, let source else { return }
        let (drop, build) = window.step(target: camera.target, at: time)
        self.window = window
        if !drop.isEmpty { view?.remove(drop) }
        guard !build.isEmpty else { return }
        let grid = window.grid, generation = window.generation, trackCover = trackCover, detail = window.buildingAround
        Task.detached(priority: .utility) { [weak self] in
            let chunks = source.chunks(build, of: grid, trackCover: trackCover, detail: detail)
            await self?.finished(chunks, keys: build, generation: generation)
        }
    }

    private func finished(_ chunks: [Map3DScene.Chunk], keys: [Map3DStreaming.Key], generation: Int) {
        guard window?.finished(keys, generation: generation) == true else { return }
        view?.place(chunks, at: keys)
    }
}

/// What makes the still scene change: track, platforms, the player's
/// buildings, and the city, which grows by night, each week; and the
/// heights file, which can arrive after the game opened; decision 313,
/// later: and the place it is built round, to a few kilometres; decision
/// 314: and the lines, whose colour bands run beside the track, in the
/// player's palette, unless no `palette` is given (the 2D map's seeded
/// streets, which have no bands); decision 326: and the real railways,
/// which can arrive after the game opened too, on a map with a place on
/// Earth (the only one that draws them: B6 of the #911–#944 review).
struct Map3DSceneKey: Hashable {
    let hasHeights: Bool
    let hasRailways: Bool
    let focus: Map3DScene.FocusArea?
    let edges: Int
    let lastEdge: TrackEdgeID?
    let platforms: Int
    let buildings: Int
    let week: Int64
    let lines: Map3DLineBands.Signature?
    let palette: LinePalette?
    /// Decision 339: a real line bought runs no real trains.
    let bought: Int
    /// Decision 400: a station road shows at once.
    let roads: Int

    init(world: GameWorld, hasHeights: Bool, hasRailways: Bool = false, focus: (x: Double, y: Double)? = nil, palette: LinePalette? = nil) {
        self.hasHeights = hasHeights
        self.hasRailways = hasRailways && world.geoAnchor != nil
        self.focus = focus.map { Map3DScene.FocusArea(x: $0.x, y: $0.y) }
        edges = world.network.edges.count
        lastEdge = world.network.edges.last?.id
        platforms = world.network.platforms.count
        buildings = world.placedBuildings.count
        week = world.clock.now.seconds / (7 * GameTime.secondsPerDay)
        lines = palette == nil ? nil : Map3DLineBands.Signature(world: world)
        self.palette = palette
        bought = world.acquisitions.count { $0.kind == .railway }
        roads = world.roads?.cells.count ?? 0
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
    /// Decision 314: what the trains' labels say.
    private var labels = Map3DTrainLabels(infos: [:])
    /// Decision 339: the clock the real trains are drawn at, `nil` while
    /// they are hidden, and whether they glide between ticks.
    private var realClock: RealTrainClock?
    private var realGlides = true
    /// Decision 400, 10i-6: the player's bus routes, the clock their buses
    /// are drawn at and the routes laid in the scene, laid again when the
    /// routes or the scene change.
    private var busWorld: GameWorld?
    private var busPalette: LinePalette = .standard
    private var busSignature: Map3DBuses.Signature?
    private var busClock: RealTrainClock?
    private var busGlides = true
    private var buses: Map3DBuses?

    func update(world: GameWorld, palette: LinePalette) {
        motion = TrainMotion(world: world, previous: motion, time: Date().timeIntervalSinceReferenceDate)
        heights = Map3DTrains.Heights(world: world)
        self.palette = palette
        activity = Map3DStreetLife.Activity(world: world)
        labels = Map3DTrainLabels(world: world)
    }

    /// Decision 339: the game clock the real trains are drawn at, or none
    /// when the player hides them.
    func updateRealClock(world: GameWorld, shown: Bool, glides: Bool) {
        realClock = shown ? RealTrainClock(world: world, previous: realClock, time: Date().timeIntervalSinceReferenceDate) : nil
        realGlides = glides
    }

    /// Decision 400, 10i-6: the game clock the player's buses are drawn at.
    func updateBuses(world: GameWorld, palette: LinePalette, glides: Bool) {
        busClock = RealTrainClock(world: world, previous: busClock, time: Date().timeIntervalSinceReferenceDate)
        busGlides = glides
        busWorld = world
        busPalette = palette
        busSignature = Map3DBuses.Signature(world: world, palette: palette)
    }

    /// Decision 400, 10i-6: the player's buses round the camera's target.
    private func busFrame(in scene: Map3DScene, camera: Map3DCamera, detail: Map3DStreetDetail, most: Int?, now: Double) -> Map3DBuses.Frame {
        guard let world = busWorld, let signature = busSignature, let clock = busClock else { return .init() }
        if buses?.isLaid(from: signature, in: scene) != true {
            buses = Map3DBuses(world: world, scene: scene, palette: busPalette)
        }
        return buses?.frame(second: clock.second(at: now, glides: busGlides), target: camera.target, distance: camera.distance,
                            detail: detail, most: most) ?? .init()
    }

    /// Decision 314: the labels of the trains whose fronts are at `heads`.
    func labels(heads: [Map3DTrains.Head], camera: Map3DCamera) -> [Map3DTrainLabels.Label] {
        labels.labels(heads: heads, camera: camera)
    }

    /// Decision 259: the people and vehicles of `scene` now, round the
    /// camera's target; standing still with Reduce Motion on.
    /// Decision 417: the player's buses first (at most the tier's), then
    /// what `budget` leaves the streets.
    func streetLife(in scene: Map3DScene, camera: Map3DCamera, lights: Float, budget: Map3DMotionBudget) -> Map3DStreetLife.Frame {
        let detail = budget.tier?.streetDetail ?? .off
        // A day's seconds, so the clock stays precise as a Float.
        let now = Date().timeIntervalSinceReferenceDate
        let time = now.truncatingRemainder(dividingBy: 86_400)
        let buses = busFrame(in: scene, camera: camera, detail: detail, most: budget.tier?.streetLimits.buses, now: now)
        return scene.streetLife.frame(target: camera.target, distance: camera.distance, time: time,
                                      still: UIAccessibility.isReduceMotionEnabled, lights: lights, detail: detail, activity: activity,
                                      buses: buses, limits: budget.limits(routeBuses: buses.instances.count))
    }

    /// The trains seen from `eye`, `ringed` with its ring (decision 334),
    /// their far models and boxes from `reach` (decision 417).
    func frame(in scene: Map3DScene, models: Map3DModelPack?, eye: Map3DPoint, ringed: TrainID?, reach: Map3DModelReach) -> Map3DTrains.Frame {
        let now = Date().timeIntervalSinceReferenceDate
        let progress = motion.isMoving ? motion.progress(at: now) : 1
        var frame = Map3DTrains.frame(motion, progress: progress, heights: heights, in: scene, models: models, eye: eye, palette: palette,
                                      ringed: ringed, reach: reach)
        // Decision 339: and the real timetables' trains, on their own track.
        if let real = scene.realTrains, let clock = realClock {
            real.add(to: &frame, second: clock.second(at: now, glides: realGlides), day: clock.today, dayBefore: clock.dayBefore,
                     models: models, eye: eye, reach: reach)
        }
        return frame
    }
}

/// The Metal view in SwiftUI, with its gestures.
private struct Map3DView: UIViewRepresentable {
    /// Decision 358: the scene, and what it was built from.
    let built: Map3DBuiltScene?
    var scene: Map3DScene? { built?.scene }
    let sceneVersion: Int
    let lighting: Map3DLighting
    /// Decision 277: the day's weather on the map.
    let weather: Map3DWeather
    let feed: Map3DTrainFeed
    /// Decision 314: where the trains' labels go.
    let trainLabels: Map3DTrainLabelState
    /// Decision 269: the 2D map's view a pinch handed over, and what to do
    /// when a pinch out is let go far enough
    /// (``Map3DHandoff/handsBack(handedOverAt:from:to:)``).
    let start: Map3DHandoff.Plan?
    /// Decision 313, later: the 2D map's view the 3D button opened this
    /// over.
    let openedAt: Map3DHandoff.Plan?
    let farOut: ((Map3DCamera) -> Void)?
    /// Decision 269, later: the way the map faces, for the compass.
    let compass: Map3DCompassState
    /// Decision 313: where the screen reads the camera, for the 2D button.
    let cameraLink: Map3DCameraLink
    let quality: Map3DQuality
    /// Decision 333: the train the camera follows, and from where.
    let follow: Map3DFollow?
    /// Decision 334: the train on a station's board the map opened for,
    /// flown to at its platform, in `world`.
    let departure: Map3DNextDeparture?
    let world: GameWorld
    let onStats: @MainActor (Map3DMetalView.Stats) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(compass: compass)
    }

    /// Decision 230: the train models, made in code once.
    // The city bus from its file (Map3DCityBus), or the box-built one.
    static let models: Map3DModelPack? = Map3DCityBus.pack(
        file: Bundle.main.url(forResource: Map3DCityBus.fileName, withExtension: Map3DCityBus.fileExtension))

    func makeUIView(context: Context) -> UIView {
        guard let view = Map3DMetalView.make(samples: quality.samplesPerPixel) else {
            let label = UILabel()
            label.text = DisplayLanguage.app.text("3D isn't available on this device.", "這台裝置無法顯示 3D。")
            label.textAlignment = .center
            label.numberOfLines = 0
            return label
        }
        context.coordinator.view = view
        cameraLink.view = view
        // Decision 421 (V2): the fixed test circles its camera.
        FrameTimeBenchRunner.shared.view3D = view
        // Decision 358: the chunks ahead of the camera, built as it moves.
        context.coordinator.streamer.view = view
        view.onCamera = { [weak coordinator = context.coordinator] camera, time in coordinator?.streamer.step(camera, at: time) }
        view.landed = { [weak coordinator = context.coordinator] in coordinator?.showHeading() }
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
        view.weather = weather
        view.onStats = onStats
        view.quality = quality
        view.reduceMotion = context.environment.accessibilityReduceMotion
        context.coordinator.farOut = farOut
        defer {
            // Decision 333: once the first scene has its camera, so the
            // flight starts from it.
            // Decision 403 (續): from the station, where it stands now.
            var follow = follow
            if let id = follow?.train, follow?.view == .station, let scene {
                follow?.lookout = Map3DFollow.lookout(of: id, in: world, scene: scene)
            }
            if context.coordinator.shownVersion != nil,
               view.following?.train != follow?.train || view.following?.view != follow?.view || view.following?.lookout != follow?.lookout {
                view.follow(follow, reduceMotion: context.environment.accessibilityReduceMotion)
                if follow == nil { context.coordinator.showHeading() }
            }
            // Decision 334: once there is a scene to fly over.
            if let scene, context.coordinator.shownVersion != nil, let departure, context.coordinator.flownTo != departure {
                context.coordinator.flownTo = departure
                view.ringed = departure.train
                let world = world
                view.fly(reduceMotion: context.environment.accessibilityReduceMotion) { camera in
                    departure.camera(in: world, scene: scene, from: camera)
                }
            }
        }
        guard let scene, context.coordinator.shownVersion != sceneVersion else { return }
        let first = context.coordinator.shownVersion == nil
        context.coordinator.shownVersion = sceneVersion
        // Decision 358: the chunks built ahead that the scene built anew
        // round the same place does not hold, kept until built again.
        let kept = context.coordinator.streamer.kept(for: scene)
        view.show(scene, keeping: kept)
        context.coordinator.streamer.start(built, kept: kept)
        // Decision 338: the train pack's sets as before them until it is
        // unlocked.
        let unlocked = TrainPack.isUnlocked(testBuild: TestBuild.isTest,
                                            switchOn: UserDefaults.standard.bool(forKey: TrainPack.testUnlockKey))
        let feed = feed, models = Map3DView.models.map { pack in
            var pack = pack
            pack.locked = TrainPack.locked(unlocked: unlocked)
            return pack
        }
        view.trains = { [weak view] eye, reach in feed.frame(in: scene, models: models, eye: eye, ringed: view?.ringed, reach: reach) }
        let labels = trainLabels
        view.trainHeads = { heads, camera in labels.show(feed.labels(heads: heads, camera: camera)) }
        view.streetLife = { camera, lights, budget in feed.streetLife(in: scene, camera: camera, lights: lights, budget: budget) }
        if first, let start {
            // Decision 269: where the 2D map was, as close, straight down.
            view.camera = Map3DHandoff.camera(from: start, in: scene, viewport: view.camera.viewport)
            context.coordinator.handedOverAt = view.camera.distance
        } else if first {
            // Open over the place the 2D map showed (decision 313, later),
            // or from the settings the middle of what is built, the whole
            // scene in view.
            let width = Float((scene.region.maxX - scene.region.minX) / Double(WorldCoordinate.unitsPerMetre))
            let height = Float((scene.region.maxY - scene.region.minY) / Double(WorldCoordinate.unitsPerMetre))
            let target = openedAt.map { scene.point(worldX: $0.x, worldY: $0.y, height: 0) } ?? .zero
            view.camera = Map3DCamera(target: target, distance: max(width, height) * 0.9, viewport: view.camera.viewport)
        }
        context.coordinator.showHeading()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: Map3DMetalView?
        var shownVersion: Int?
        /// Decision 358.
        let streamer = Map3DChunkStreamer()
        /// Decision 334: the departure last flown to.
        var flownTo: Map3DNextDeparture?
        var farOut: ((Map3DCamera) -> Void)?
        /// Decision 269: how far out the camera a pinch handed over opened;
        /// `nil` when the 3D button opened the map.
        var handedOverAt: Float?
        private var handedBack = false
        /// Decision 313: the distance as the pinch under way began.
        private var pinchFrom: Float?
        private let compass: Map3DCompassState
        /// The turn back to north running, a frame at a time.
        private var northLink: CADisplayLink?
        private var northTurn: (start: Float, began: CFTimeInterval, seconds: Double)?

        init(compass: Map3DCompassState) {
            self.compass = compass
            super.init()
            compass.turnNorth = { [weak self] reduceMotion in
                guard self?.view?.following == nil else { return }
                self?.turnNorth(reduceMotion: reduceMotion)
            }
        }

        /// Tells the compass the way the camera faces now.
        func showHeading() {
            guard let view else { return }
            let turn = view.camera.turnFromNorth, facesNorth = view.camera.facesNorth
            if compass.turn != turn { compass.turn = turn }
            if compass.facesNorth != facesNorth { compass.facesNorth = facesNorth }
        }

        /// Turns the map back to north: at once with Reduce Motion, or
        /// else over ``MotionRule/turnNorth``. A finger on the map stops it
        /// where it is, as the reference's map does.
        func turnNorth(reduceMotion: Bool) {
            guard let view else { return }
            stopTurningNorth()
            guard let rule = MotionRule.turnNorth.running(reduceMotion: reduceMotion) else {
                view.camera = view.camera.turnedNorth(from: view.camera.heading, progress: 1)
                showHeading()
                return
            }
            northTurn = (view.camera.heading, CACurrentMediaTime(), rule.seconds)
            let link = CADisplayLink(target: self, selector: #selector(northStep(_:)))
            link.add(to: .main, forMode: .common)
            northLink = link
        }

        @objc private func northStep(_ link: CADisplayLink) {
            guard let view, let turn = northTurn else { return stopTurningNorth() }
            let progress = Float((link.timestamp - turn.began) / turn.seconds)
            view.camera = view.camera.turnedNorth(from: turn.start, progress: progress)
            showHeading()
            if progress >= 1 { stopTurningNorth() }
        }

        private func stopTurningNorth() {
            northLink?.invalidate()
            northLink = nil
            northTurn = nil
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began { stopTurningNorth() }
            guard let view else { return }
            // Decision 333: following, the camera stays on the train, as
            // Mini Tokyo 3D holds its map still while it tracks one.
            guard view.following == nil else {
                recognizer.setTranslation(.zero, in: view)
                return
            }
            view.stopFlyingBack()
            let moved = recognizer.translation(in: view)
            view.camera = view.camera.panned(dx: Float(moved.x), dy: Float(moved.y))
            recognizer.setTranslation(.zero, in: view)
        }

        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            if recognizer.state == .began { stopTurningNorth() }
            guard let view else { return }
            // Decision 333: following, a pinch moves the camera in or out.
            if view.following != nil {
                view.zoomFollow(by: Float(recognizer.scale))
                recognizer.scale = 1
                return
            }
            view.stopFlyingBack()
            if recognizer.state == .began { pinchFrom = view.camera.distance }
            view.camera = view.camera.zoomed(by: Float(recognizer.scale))
            recognizer.scale = 1
            // Decision 313: decided as the fingers lift. A pinch out let go
            // far enough hands the 2D map back; never one coming closer,
            // nor on a 3D map the button opened (decision 269's fix, 71.1).
            guard recognizer.state == .ended else {
                if recognizer.state == .cancelled || recognizer.state == .failed { pinchFrom = nil }
                return
            }
            if let farOut, !handedBack, let before = pinchFrom,
               Map3DHandoff.handsBack(handedOverAt: handedOverAt, from: before, to: view.camera.distance) {
                handedBack = true
                farOut(view.camera)
            }
            pinchFrom = nil
        }

        @objc func rotate(_ recognizer: UIRotationGestureRecognizer) {
            if recognizer.state == .began { stopTurningNorth() }
            guard let view else { return }
            guard view.following == nil else {
                recognizer.rotation = 0
                return
            }
            view.stopFlyingBack()
            view.camera = view.camera.turned(by: -Float(recognizer.rotation))
            recognizer.rotation = 0
            showHeading()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Decision 313: the Metal view, for the screen to read its camera as the
/// player leaves for the 2D map. The camera stays the view's own.
@MainActor
final class Map3DCameraLink {
    weak var view: Map3DMetalView?
    var camera: Map3DCamera? { view?.camera }
}

/// Decision 269, later: the way the 3D map faces, for its compass, and how
/// to turn it back to north. The camera stays the Metal view's own; this
/// only mirrors its heading, so turning redraws the compass alone.
@MainActor
@Observable
final class Map3DCompassState {
    /// The camera's turn from north, in radians, clockwise.
    var turn: Float = 0
    /// Whether it faces north (``Map3DCamera/facesNorth``).
    var facesNorth = true
    /// Turns the map back to north; with Reduce Motion at once.
    @ObservationIgnored var turnNorth: ((_ reduceMotion: Bool) -> Void)?
}

/// Decision 269, later: the 3D map's compass, only while the map does not
/// face north, as in Apple Maps. A round button the size of the close
/// button above it; the needle, red to the north and white to the south
/// (MapLibre's compass, the reference's map), points where north is on
/// the screen. A tap turns the map back.
private struct Map3DCompassButton: View {
    let state: Map3DCompassState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !state.facesNorth {
            Button {
                state.turnNorth?(reduceMotion)
            } label: {
                ZStack {
                    Circle().fill(Theme.panel)
                    Circle().strokeBorder(Theme.textPrimary, lineWidth: 1.5)
                    ZStack {
                        needle(north: true, fill: Palette.metroRed)
                        needle(north: false, fill: .white)
                    }
                    .rotationEffect(.radians(Double(-state.turn)))
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: DisplayLanguage.app.text("Turn to north", "轉回北方")))
            .accessibilityIdentifier("map3D.compass")
        }
    }

    private func needle(north: Bool, fill: Color) -> some View {
        let half = Map3DCompassNeedle(north: north)
        return half.fill(fill)
            .overlay(half.stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 1.25, lineJoin: .round)))
    }
}

/// Half the compass's needle, in a 44-point square: from the middle to
/// the tip, 13.5 points long and 10 wide where the halves meet.
private struct Map3DCompassNeedle: Shape {
    let north: Bool

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 44
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(22, north ? 8.5 : 35.5))
        path.addLine(to: point(27, 22))
        path.addLine(to: point(17, 22))
        path.closeSubpath()
        return path
    }
}

/// Decision 314: the trains' labels now, set by the Metal view each frame
/// and drawn by ``Map3DTrainLabelsView``; set only when they move a whole
/// point or change, so a still map redraws nothing.
@MainActor
@Observable
final class Map3DTrainLabelState {
    private(set) var labels: [Map3DTrainLabels.Label] = []

    func show(_ next: [Map3DTrainLabels.Label]) {
        let rounded = next.map { Map3DTrainLabels.Label(train: $0.train, info: $0.info, x: $0.x.rounded(), y: $0.y.rounded()) }
        if rounded != labels { labels = rounded }
    }
}

/// Decision 320: the day's rain over the 3D map (``Map3DRain``), falling
/// frame by frame and flashing in a storm, unless the player reduces
/// motion: then only the light of decision 277 shows the rain. Not
/// touchable, and not read out.
private struct Map3DRainLayer: View, Equatable {
    let rain: Map3DRain
    let detail: Map3DStreetDetail
    /// How far the day's light has gone (``Map3DLighting/night``).
    let night: Float
    /// Decision 394: the cab deep in a tunnel, where no rain falls.
    let underground: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (lhs: Map3DRainLayer, rhs: Map3DRainLayer) -> Bool {
        lhs.rain == rhs.rain && lhs.detail == rhs.detail && lhs.night == rhs.night && lhs.underground == rhs.underground
    }

    var body: some View {
        let rain = rain, detail = detail
        let look = rain.look(night: night)
        let colour = Color(.sRGB, red: Double(look.colour >> 16 & 0xFF) / 255, green: Double(look.colour >> 8 & 0xFF) / 255,
                           blue: Double(look.colour & 0xFF) / 255, opacity: look.opacity)
        return Group {
            if rain.amount > 0, !reduceMotion, !underground {
                // At most 60 a second: the rain looks no smoother faster.
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        var streaks = Path()
                        for streak in rain.streaks(at: time, width: size.width, height: size.height, detail: detail) {
                            streaks.move(to: CGPoint(x: streak.x0, y: streak.y0))
                            streaks.addLine(to: CGPoint(x: streak.x1, y: streak.y1))
                        }
                        context.stroke(streaks, with: .color(colour), style: StrokeStyle(lineWidth: Map3DRain.lineWidth, lineCap: .round))
                        let flash = rain.flash(at: time)
                        if flash > 0 {
                            context.fill(Path(CGRect(origin: .zero, size: size)),
                                         with: .color(Palette.lightning.opacity(Map3DRain.flashOpacity * flash)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Decision 314: over the front of a few trains near the middle, close up,
/// the line's badge (decision 216) and its riders over its capacity, on a
/// small tag whose foot points at the train. Not touchable: the map under
/// it takes the fingers.
private struct Map3DTrainLabelsView: View {
    let state: Map3DTrainLabelState
    let world: GameWorld

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(state.labels, id: \.train) { label in
                tag(label.info)
                    .alignmentGuide(.leading) { $0[HorizontalAlignment.center] - CGFloat(label.x) }
                    .alignmentGuide(.top) { $0[.bottom] - CGFloat(label.y) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func tag(_ info: Map3DTrainLabels.Info) -> some View {
        HStack(spacing: 4) {
            LineCodeBadge(code: info.code, color: Palette.lineColor(info.line, custom: world.line(id: info.line)?.color), size: .small)
            Text(verbatim: DisplayLanguage.app.text("\(info.riders)/\(info.capacity)", "\(info.riders)／\(info.capacity)"))
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Palette.markerFill, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: DisplayLanguage.app.text("Line \(info.code), \(info.riders) riding of \(info.capacity)",
                                                                    "\(info.code) 線，載客 \(info.riders)／定員 \(info.capacity)")))
    }
}

/// Decision 333: at the foot of the 3D map while the camera follows a
/// train (``GameSession/followedTrain``): the train's line badge and name,
/// the places to follow it from (Mini Tokyo 3D's back and top back; the
/// cab, decision 337; beside it and from the station, decision 403 (續)),
/// and the stop, as the 2D map's follow bar has it (`取消跟隨`).
private struct Map3DFollowBar: View {
    let train: Train
    let session: GameSession
    @Binding var view: Map3DFollow.View
    /// Decision 403 (續二): takes a photo of the 3D map.
    let takePhoto: () -> Void

    var body: some View {
        // Decision 403 (續): five views; where they do not fit beside the
        // name in one row, they take a row of their own under it.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                title
                choices
                actions
                stop
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    title
                    Spacer(minLength: 0)
                    actions
                    stop
                }
                HStack(spacing: 9) { choices }
            }
        }
        // Decision 337: a long name gives way on a narrow phone, the
        // buttons never.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 13)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .hudFrameMark("map3D.followBar")
        .accessibilityHint(Text(verbatim: session.language.text("Pinch to move closer or farther.", "兩指縮放，拉近或拉遠。")))
    }

    @ViewBuilder private var title: some View {
        if let line = session.world.followBarInfo(of: train.id, in: session.language)?.line {
            LineCodeBadge(code: LineBadge.codes(for: session.world.lines)[line] ?? "",
                          color: Palette.lineColor(line, custom: session.world.line(id: line)?.color), size: .small)
        }
        Text(verbatim: train.name)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var choices: some View {
        ForEach(Map3DFollow.View.allCases, id: \.self) { option in
            Button {
                view = option
            } label: {
                Text(verbatim: option.text(in: session.language))
                    .font(.caption.weight(.bold))
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .frame(minHeight: 26)
                    .background(view == option ? Theme.primary : Theme.chip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(view == option ? Theme.onPrimary : Theme.textPrimary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(verbatim: option.hint(in: session.language)))
            .accessibilityAddTraits(view == option ? .isSelected : [])
            .accessibilityIdentifier("map3D.follow.\(option.rawValue)")
        }
    }

    /// Decision 403 (續二): the horn (the train's own, by its kind) and the
    /// photo, round buttons beside the stop.
    @ViewBuilder private var actions: some View {
        Button {
            session.soundHorn()
        } label: {
            roundIcon(Self.hornSymbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Horn", "鳴笛")))
        .accessibilityHint(Text(verbatim: session.language.text("Sounds the train's horn.", "讓列車鳴笛。")))
        .accessibilityIdentifier("map3D.follow.horn")
        Button(action: takePhoto) {
            roundIcon("camera.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Take Photo", "拍照")))
        .accessibilityHint(Text(verbatim: session.language.text("Saves the 3D view as a picture to share.", "把現在的 3D 畫面存成照片，可以分享。")))
        .accessibilityIdentifier("map3D.follow.photo")
    }

    /// The horn's symbol: SF Symbols 5's horn, or a speaker where a system
    /// has none.
    private static let hornSymbol = UIImage(systemName: "horn.blast.fill") != nil ? "horn.blast.fill" : "speaker.wave.3.fill"

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.caption.weight(.heavy))
            .frame(width: 26, height: 26)
            .background(Theme.chip, in: Circle())
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private var stop: some View {
        Button {
            session.stopFollowingTrain()
        } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.heavy))
                .frame(width: 26, height: 26)
                .background(Theme.error, in: Circle())
                .foregroundStyle(Theme.onError)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Stop following", "取消跟隨")))
        .accessibilityIdentifier("map3D.follow.stop")
    }
}

/// Decision 403: at the top of the 3D map while it follows a train: the
/// line, the way it runs, the next stop (or the one it stands at), how far
/// it is and how late the train runs.
private struct Map3DDriverStrip: View {
    let hud: Map3DDriverHUD
    let world: GameWorld

    var body: some View {
        let language = DisplayLanguage.app
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let line = hud.line {
                        LineCodeBadge(code: LineBadge.codes(for: world.lines)[line] ?? "",
                                      color: Palette.lineColor(line, custom: world.line(id: line)?.color), size: .small)
                    }
                    if let route = hud.routeText ?? hud.lineName {
                        Text(verbatim: route)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                if let name = hud.placeName {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if let label = hud.placeLabel(in: language) {
                            Text(verbatim: label)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(verbatim: name)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                if let lateness = hud.lateness {
                    Text(verbatim: Map3DDriverHUD.latenessText(lateness, in: language))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(lateness > 0 ? Theme.warning : Theme.success)
                }
                if let distance = hud.distanceText {
                    Text(verbatim: distance)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .monospacedDigit()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map3D.driver.strip")
        .hudFrameMark("map3D.driver.strip")
    }
}

/// Decision 403: the followed train's speed, the curve limit it keeps to
/// now (a red ring) and the next one ahead (an amber ring, with how far).
private struct Map3DSpeedCard: View {
    let hud: Map3DDriverHUD

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "\(hud.speed)")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(verbatim: "km/h")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let here = hud.limitHere {
                LimitSign(speed: here, ring: Theme.error, size: 34)
            }
            if let ahead = hud.limitAhead {
                VStack(spacing: 1) {
                    LimitSign(speed: ahead.speed, ring: Theme.warning, size: 26)
                    Text(verbatim: Map3DDriverHUD.distanceText(ahead.metres))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .monospacedDigit()
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: hud.speedLabel(in: DisplayLanguage.app)))
        .accessibilityIdentifier("map3D.driver.speed")
        .hudFrameMark("map3D.driver.speed")
    }

    /// A round speed sign: the limit on the panel's colour inside a ring.
    private struct LimitSign: View {
        let speed: Int64
        let ring: Color
        let size: CGFloat

        var body: some View {
            Text(verbatim: "\(speed)")
                .font(.system(size: size * 0.36, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.6)
                .frame(width: size, height: size)
                .background(Theme.panel, in: Circle())
                .overlay(Circle().strokeBorder(ring, lineWidth: size * 0.12))
        }
    }
}

/// Decision 403: a line under the strip near a stop ("Next stop Taoyuan,
/// 640 m") and for a moment after it stands there ("On time").
private struct Map3DDriverPrompt: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .accessibilityIdentifier("map3D.driver.prompt")
    }
}

/// Decision 403 (續二): the photo of the 3D map just taken, shown in its
/// sheet until it is closed; a class on the main actor, so the frame's
/// copy can hand it over when the GPU is done.
@MainActor
@Observable
final class Map3DPhotoState {
    var snapshot: Map3DSnapshot?
}

/// Decision 403 (續二): a photo of the 3D map, and what to call it.
struct Map3DSnapshot: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
}

/// Decision 403 (續二): the photo just taken of the 3D map, and the share
/// button, which hands it to the system's share sheet as the postcard's
/// does (decision 215): to the photos, LINE, or anywhere else.
private struct Map3DSnapshotSheet: View {
    let snapshot: Map3DSnapshot
    let language: DisplayLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let image = Image(uiImage: snapshot.image)
        NavigationStack {
            VStack(spacing: 16) {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text(verbatim: snapshot.title))
                    .accessibilityIdentifier("map3D.snapshot.image")
                ShareLink(item: image, preview: SharePreview(Text(verbatim: snapshot.title), image: image)) {
                    Label {
                        Text(verbatim: language.text("Share Photo", "分享照片"))
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ThemeProminentButtonStyle())
                .accessibilityIdentifier("map3D.snapshot.share")
            }
            .padding()
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .navigationTitle(language.text("3D Photo", "3D 照片"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Done", "完成")) { dismiss() }
                        .accessibilityIdentifier("map3D.snapshot.done")
                }
            }
        }
    }
}
