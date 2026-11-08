import Foundation
import GameCore
import GamePresentation
import Metal
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
    /// Decision 517: Build hands over this view too, to come back to as
    /// building ends.
    var build: ((Map3DHandoff.Plan, Map3DBuildReturn.Viewpoint) -> Void)? = nil
    /// Decision 517: the view Build left, opened again as building ended.
    var resumes: Map3DBuildReturn.Viewpoint? = nil
    /// Decision 517 續: a station tapped here, its tag's details (`false`)
    /// or its pencil (`true`) opened on the 2D map where this one looks.
    /// `nil` from the settings, which have no 2D map below: no taps there.
    var openStation: ((Map3DHandoff.Plan, _ rename: Bool) -> Void)? = nil
    /// Decision 414: the game screen while the idle mode runs, whose
    /// director picks the view the train is followed from; the controls
    /// are put away and a tap ends the mode (`endAmbient`).
    var ambientScreen: GameScreenState? = nil
    var endAmbient: (() -> Void)? = nil
    @State private var built: Map3DBuiltScene?
    private var scene: Map3DScene? { built?.scene }
    @State private var sceneVersion = 0
    /// K1-1, K2-4: whether ``Map3DTrainModels`` has made them, off the main
    /// thread; decision 546: the scene is shown before they are.
    @State private var modelsReady = false
    @State private var stats: Map3DMetalView.Stats?
    @State private var showsDetails = false
    /// Decision 625 續: the Debug app's `-screenshot-3d-clean` leaves out
    /// the frame rate and the gesture hint, for screenshots of the map alone.
    #if DEBUG
    private static let screenshotClean = ProcessInfo.processInfo.arguments.contains("-screenshot-3d-clean")
    #else
    private static let screenshotClean = false
    #endif
    @State private var feed = Map3DTrainFeed()
    @State private var compass = Map3DCompassState()
    @State private var cameraLink = Map3DCameraLink()
    @State private var trainLabels = Map3DTrainLabelState()
    /// Decision 517 續: the station tapped and where its tag stands.
    @State private var stationTag = Map3DStationTagState()
    /// Decision 403 (續二): the photo of the 3D map just taken, to share.
    @State private var photo = Map3DPhotoState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Decision 437: plays the evening garbage truck's tune.
    @Environment(GameAudio.self) private var audio: GameAudio?
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
                      start: handedOver, openedAt: openedAt, resumes: resumes, farOut: farOut, compass: compass, cameraLink: cameraLink, quality: quality.drawn,
                      follow: followed(ambient: ambient),
                      departure: departure, world: session.world, modelsReady: modelsReady,
                      stationTag: stationTag,
                      onTap: openStation == nil || ambient != nil ? nil : { @MainActor camera, point in tapped(camera, at: point) },
                      onStats: { stats = $0 })
                .ignoresSafeArea()
                .accessibilityIdentifier("map3D.view")
            Map3DRainLayer(rain: Map3DRain(MapWeather(world: session.world)), detail: stats?.streetDetail ?? .full,
                           aim: stats?.aim ?? 60,
                           night: Map3DLighting(at: session.world.clock.now).night, underground: stats?.underground ?? false)
                .ignoresSafeArea()
            Map3DTrainLabelsView(state: trainLabels, world: session.world)
                .ignoresSafeArea()
            if let openStation, ambient == nil {
                Map3DStationTagView(state: stationTag, session: session) { rename in
                    leave { plan in openStation(plan, rename) }
                }
                .ignoresSafeArea()
            }
            if built == nil {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityIdentifier("map3D.loading")
            } else if !modelsReady {
                // Decision 546: the scene up, its trains' models still being
                // made (boxes meanwhile); nothing drawn, for VoiceOver and a
                // screenshot test to wait on.
                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: language.text("Loading trains", "列車載入中")))
                    .accessibilityIdentifier("map3D.trainsLoading")
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
                                guard let scene, let camera = cameraLink.camera else { return close() }
                                build(Map3DHandoff.plan(from: camera, in: scene), Map3DBuildReturn.Viewpoint(camera: camera, in: scene))
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
                        if !session.isFollowingVehicle {
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
                    VStack(alignment: .trailing, spacing: 6) {
                        SpeedControl(session: session, tutorialTarget: nil)
                            .padding(4)
                            .background(.regularMaterial, in: Capsule())
                            .accessibilityIdentifier("map3D.speed")
                        // Decision 645 (B5): the 3D map covers the 2D
                        // map's clock, so it shows the same one here.
                        Map3DClock(session: session)
                    }
                    if let stats, !Self.screenshotClean {
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
                } else if let bus = session.busFollowBar {
                    Map3DBusFollowBar(facts: bus, session: session, view: $followView, takePhoto: takePhoto)
                        .transition(.card(from: .bottom, reduceMotion: reduceMotion))
                } else if let cabin = session.cabinFollowBar {
                    // Decision 583 (CABLEFOLLOW).
                    Map3DCabinFollowBar(facts: cabin, session: session, view: $followView, takePhoto: takePhoto)
                        .transition(.card(from: .bottom, reduceMotion: reduceMotion))
                } else if let ferry = session.ferryFollowBar {
                    // Decision 585 PR-4 (FERRYFOLLOW).
                    Map3DFerryFollowBar(facts: ferry, session: session, view: $followView, takePhoto: takePhoto)
                        .transition(.card(from: .bottom, reduceMotion: reduceMotion))
                } else if !Self.screenshotClean {
                    Text(verbatim: handedOver == nil
                         ? language.text("Pinch closer to tilt the map, and push two fingers up to tilt it more. Drag to move, two fingers to turn.",
                                         "兩指拉近，地圖就會傾斜；兩指往上推，斜得更多。拖曳移動，兩指旋轉。")
                         : language.text("Pinch closer to tilt the map and push two fingers up to tilt it more, or pinch out and let go to go back. Drag to move, two fingers to turn.",
                                         "兩指拉近地圖就傾斜，兩指往上推斜得更多，拉遠放手就回到平面地圖。拖曳移動，兩指旋轉。"))
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
            .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: session.busFollowBar != nil)
            .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: session.cabinFollowBar != nil)
            .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: session.ferryFollowBar != nil)
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
        .task {
            // K1-1, K2-4: the train models (and their baked shade), made
            // once on another thread, as the train showcase makes them;
            // decision 546: often made already, after the game opened.
            // Decision 608: how long the 3D map waits for them (made ahead,
            // then put on the GPU here), in a UI test's trace.
            let asked = ContinuousClock.now
            await Map3DTrainModels.shared.make()
            let waited = asked.duration(to: .now)
            UITestTrace.action("map3D.models ready after \(waited.components.seconds * 1000 + waited.components.attoseconds / 1_000_000_000_000_000) ms")
            modelsReady = true
        }
        // Decision 379 續四: once a step's glide stops going on, with the
        // heights and labels of the world it glides to.
        .onChange(of: session.glideKey, initial: true) { _, key in
            guard !key.goesOn else { return }
            feed.update(session: session, palette: linePalette)
        }
        .onChange(of: session.world.clock.now, initial: true) { _, _ in
            // CABVIEW-2 (decision 379 續三): over the game loop's whole
            // step, as the trains do.
            guard !session.glidesOnThroughTheStep else { return }
            // Decision 339: the real trains glide with the game clock.
            feed.updateRealClock(world: session.world, shown: showsRealTrains,
                                 glides: !session.world.clock.isPaused && !reduceMotion)
            // Decision 400, 10i-6: and the player's buses with it.
            feed.updateBuses(world: session.world, palette: linePalette, roads: session.busRoads, glides: !session.world.clock.isPaused && !reduceMotion)
        }
        // Decision 517 續: a station picked on the 2D map keeps its tag here,
        // once the scene is up to stand it on.
        .onChange(of: sceneVersion) { _, _ in
            guard openStation != nil, stationTag.station == nil, let id = session.selectedStationID,
                  let scene, let camera = cameraLink.camera else { return }
            let space = Map3DPick.Space(scene: scene)
            stationTag.show(id, at: Map3DTap.anchor(of: id, in: session.world, space: space, ground: Map3DPick.ground(of: scene, world: session.world)),
                            seenBy: camera)
        }
        // Decision 606 (IDLEREAL): a real train the idle mode follows that
        // this map cannot find (in a tunnel, past the scene) for a while
        // is passed over.
        .task(id: ambientScreen?.ambient?.realTrain) { await watchRealTrain() }
        .onChange(of: showsRealTrains) { _, shown in
            feed.updateRealClock(world: session.world, shown: shown, glides: !session.world.clock.isPaused && !reduceMotion)
        }
        // Decision 360: following a train here runs at 10× at most, and
        // closing gives the 2D map its speed back.
        .onAppear {
            session.setMap3DOpen(true)
            FrameTimeRecorder.shared.show3D(true)
            let audio = audio
            feed.garbageTruckSound = { [weak audio] sound in audio?.setGarbageTruck(sound) }
        }
        .onDisappear {
            session.setMap3DOpen(false)
            FrameTimeRecorder.shared.show3D(false)
            // Decision 460: a device of little memory does not keep the
            // scene once the 3D map closes.
            if !FrameTimeRecorder.memoryTier.keepsSceneBuilt { Map3DSceneCache.shared.clear() }
            feed.garbageTruckSound = nil
            audio?.setGarbageTruck(nil)
        }
        .sheet(item: $photo.snapshot) { snapshot in
            Map3DSnapshotSheet(snapshot: snapshot, language: language)
        }
    }

    /// Decision 403 (續二): the 3D map as drawn next, without the cards
    /// over it, to share as the postcard is shared (decision 215).
    private func takePhoto() {
        guard let view = cameraLink.view else { return }
        let title = session.followedTrain.map(\.name) ?? session.busFollowBar?.routeName ?? session.cabinFollowBar?.name
            ?? session.ferryFollowBar?.name
            ?? DisplayLanguage.app.text("3D Map", "3D 地圖")
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
    /// none. Decision 434: the train showcase's photos too.
    static func credited(_ image: UIImage, _ credit: String) -> UIImage {
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

    /// Decision 333: what the camera follows, a train or (decision 400,
    /// FOLLOWBUS) a bus; a bus has no platform, so its station view is from
    /// behind.
    private func followed(ambient: AmbientScreen?) -> Map3DFollow? {
        let view = ambient?.view3D ?? followView
        // Decision 606 (IDLEREAL): the idle mode's real train.
        if let real = ambient?.realTrain { return Map3DFollow(realTrain: real, view: view) }
        if let train = session.followedTrain { return Map3DFollow(train: train.id, view: view) }
        if let bus = session.followedBusID, session.busFollowBar != nil { return Map3DFollow(bus: bus, view: view == .station ? .back : view) }
        // Decision 583 (CABLEFOLLOW): a cabin, from its window, above or beside.
        if let cabin = session.followedCabinID, session.cabinFollowBar != nil { return Map3DFollow(cabin: cabin, view: view) }
        // Decision 585 PR-4 (FERRYFOLLOW): a boat, from its bridge, its window, above or beside.
        if let boat = session.followedFerryBoatID, session.ferryFollowBar != nil { return Map3DFollow(ferry: boat, view: view) }
        return nil
    }

    /// Decision 517 續: a tap at `point` seen by `camera` does to the
    /// station under it what a tap on the 2D map does: selects it, its tag
    /// under it; elsewhere lets go. Not while following a train.
    private func tapped(_ camera: Map3DCamera, at point: CGPoint) {
        guard let scene, !session.isFollowingVehicle else { return }
        // Decision 400 (FOLLOWBUS): a bus under the finger is followed.
        if session.tool == .select, session.tutorial == nil,
           let bus = feed.bus(atX: Float(point.x), y: Float(point.y), camera: camera, in: scene) {
            session.followBus(bus)
            return
        }
        // Decision 583 (CABLEFOLLOW): and a cable car cabin.
        if session.tool == .select, session.tutorial == nil,
           let cabin = feed.cabin(atX: Float(point.x), y: Float(point.y), camera: camera, in: scene) {
            session.followCabin(cabin)
            return
        }
        // Decision 585 PR-4 (FERRYFOLLOW): and a ferry boat.
        if session.tool == .select, session.tutorial == nil,
           let boat = feed.ferryBoat(atX: Float(point.x), y: Float(point.y), camera: camera, in: scene) {
            session.followFerryBoat(boat)
            return
        }
        guard let hit = Map3DPick.pick(atX: Float(point.x), y: Float(point.y), camera: camera, scene: scene, world: session.world)
        else { return }
        let id = session.tapMap3D(at: hit, reach: Map3DTap.reach(at: hit.point, camera: camera))
        let space = Map3DPick.Space(scene: scene)
        let anchor = id.flatMap { Map3DTap.anchor(of: $0, in: session.world, space: space, ground: Map3DPick.ground(of: scene, world: session.world)) }
        stationTag.show(id, at: anchor, seenBy: camera)
    }

    /// Decision 606: tells the idle mode when the built map first shows
    /// its real train on built ground, and passes it on when it has not
    /// been found for ``AmbientDirector/realTrainLostChecks`` checks in a
    /// row, a second apart, or found where the ground round it is not
    /// built for ``AmbientDirector/realTrainBareChecks`` (``AmbientDirector/RealTrainWatch``).
    private func watchRealTrain() async {
        guard let id = ambientScreen?.ambient?.realTrain else { return }
        var watch = AmbientDirector.RealTrainWatch()
        while !Task.isCancelled, ambientScreen?.ambient?.realTrain == id {
            try? await Task.sleep(for: .seconds(1))
            guard let scene else { continue }
            let pose = feed.realTrainPose(id, in: scene)
            let built = pose.map { cameraLink.view?.trainGroundBuilt?($0.rail) ?? true } ?? false
            switch watch.check(found: pose != nil, built: built) {
            case .waiting:
                break
            case .seen:
                if ambientScreen?.ambient?.realTrainSeen == false {
                    // The corner line naming it fades in as it shows.
                    withAnimation(reduceMotion ? nil : MotionRule.ambientCut.animation) { ambientScreen?.ambient?.realTrainSeen = true }
                }
            case .lost:
                ambientScreen?.ambient?.lostRealTrain = id
                return
            }
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
                    // Decision 485: the main thread's busy time a frame
                    // and its longest stretch, the game loop's ticks with it.
                    Text(verbatim: String(format: "main %.1f ms · longest %.0f ms", stats.mainMilliseconds, stats.mainLongestMilliseconds))
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
                    // Decision 645 (D6): the light the last frame drew.
                    Text(verbatim: String(format: "light %02d:%02d · night %.2f · lights %.2f", Int(stats.drawnHour) % 24,
                                          Int(stats.drawnHour * 60) % 60, stats.drawnNight, stats.drawnLights))
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Decision 546: the 3D map's train models (``Map3DView/makeModels()``), made
/// once, off the main thread: ahead, a while after a game opens (when 3D
/// is on and the device keeps a scene built, decision 460) or when a pinch
/// rests near the 3D map, or when the 3D map opens, which shows its scene
/// before them. Always at a low priority (`.utility`, a UI test's warm-up
/// too), never raised: they are made on every core at once
/// (``Map3DModelPack``, ``Map3DTrainOcclusion``), and made at the 3D map's
/// priority the Simulator's main thread stood still for 61 s (#1693). So
/// whoever waits for them waits on a continuation, which raises nothing,
/// not on the task's value, which would raise it to the waiter's priority.
///
/// Decision 608: then put on the GPU, on another task of the same low
/// priority, the first time a 3D map or the train showcase asks for them
/// (``make(priority:)``): the vertices go to the GPU once, off the main
/// thread, and the CPU keeps only their names, vertex counts, bounds,
/// lamps, signs and glass (``Map3DUploadedModels``), held for the app's
/// life and shared by the 3D map and the train showcase. Not when they
/// are made ahead (``start(priority:)``, ``makePack(priority:)``): made
/// over the 2D map with their buffers, the Simulator dropped a UI test's
/// pinch on the 2D map that came two seconds later (#1876's runs
/// 42125321805 and 42140345310, main's 42140330949 green), so over the 2D
/// map they stay what they were before decision 608.
@MainActor
final class Map3DTrainModels {
    static let shared = Map3DTrainModels()
    private var started = false
    private var made = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// The models made, with their vertices, until they are on the GPU.
    private var pack: Map3DModelPack?
    private var uploading = false
    private var uploadedOrFailed = false
    private var waitingForUpload: [CheckedContinuation<Void, Never>] = []
    /// Decision 608: the models on the GPU, once uploaded (`nil` before, or
    /// where the device has no Metal or no memory for them).
    private(set) var uploaded: Map3DUploadedModels?

    /// Starts making them, unless made or under way.
    func start(priority: TaskPriority = .utility) {
        guard !started else { return }
        started = true
        Task.detached(priority: priority) {
            let pack = Map3DView.makeModels()
            await Map3DTrainModels.shared.finished(pack)
        }
    }

    /// Once they are made, starting them if nothing has; not yet on the GPU.
    func makePack(priority: TaskPriority = .utility) async {
        start(priority: priority)
        guard !made else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Once they are made and on the GPU (``uploaded``).
    func make(priority: TaskPriority = .utility) async {
        await makePack(priority: priority)
        guard !uploadedOrFailed else { return }
        if !uploading {
            uploading = true
            // The task holds the vertices' last reference, so they are
            // let go of there, not on the main thread.
            let pack = self.pack
            self.pack = nil
            Task.detached(priority: priority) {
                let uploaded = pack.flatMap(Map3DUploadedModels.make(from:))
                await Map3DTrainModels.shared.finishedUpload(uploaded)
            }
        }
        await withCheckedContinuation { waitingForUpload.append($0) }
    }

    private func finished(_ pack: Map3DModelPack?) {
        self.pack = pack
        made = true
        let woken = waiting
        waiting = []
        for continuation in woken { continuation.resume() }
    }

    private func finishedUpload(_ uploaded: Map3DUploadedModels?) {
        UITestTrace.action("map3D.models uploaded: \(uploaded.map { "\($0.buffers.count) buffers" } ?? "none")")
        self.uploaded = uploaded
        uploadedOrFailed = true
        let woken = waitingForUpload
        waitingForUpload = []
        for continuation in woken { continuation.resume() }
    }

    /// How long after a game opens they are made ahead: past its first
    /// moves, which the cores are left to.
    static let aheadAfter: Duration = .seconds(8)
}

/// Decision 608: the 3D map's train and street models on the GPU, one
/// buffer each, made once off the main thread and never changed, so any
/// thread may read them; the CPU keeps the pack without its vertices
/// (names, vertex counts, bounds, lamps, destination signs) and the glass
/// the transparent-glass pass sorts each frame, taken before the
/// vertices are let go of.
final class Map3DUploadedModels: @unchecked Sendable {
    let pack: Map3DModelPack
    let buffers: [MTLBuffer]
    let glass: Map3DTransparentGlass.Cache
    /// Decision 617: every model's glow spots, and a buffer of them
    /// (`nil` when no model glows).
    let glows: Map3DGlow.Table
    let glowBuffer: MTLBuffer?

    private init(pack: Map3DModelPack, buffers: [MTLBuffer], glass: Map3DTransparentGlass.Cache, glows: Map3DGlow.Table, glowBuffer: MTLBuffer?) {
        self.pack = pack
        self.buffers = buffers
        self.glass = glass
        self.glows = glows
        self.glowBuffer = glowBuffer
    }

    /// Puts the vertices of `full` (``Map3DView/makeModels()``) in
    /// buffers on the system's Metal device (the one every 3D view draws
    /// with), then lets go of them on the CPU: this pack's, once its
    /// caller lets go of it, and ``Map3DModelPack/standard``'s, which it
    /// was made from. Slow: never on the main thread.
    static func make(from full: Map3DModelPack) -> Map3DUploadedModels? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let buffers = full.models.compactMap { model in
            model.vertices.withUnsafeBytes { bytes in
                bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
            }
        }
        guard buffers.count == full.models.count else { return nil }
        let glass = Map3DTransparentGlass.Cache(models: full.models)
        let glows = Map3DGlow.Table(models: full.models)
        let glowBuffer = glows.floats.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
        }
        let uploaded = Map3DUploadedModels(pack: full.withoutVertices(), buffers: buffers, glass: glass, glows: glows, glowBuffer: glowBuffer)
        Map3DModelPack.letGoOfStandardVertices()
        return uploaded
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
    /// Review L-1: a build still running when let go is held until it ends.
    private var hold = Map3DSceneHold()
    /// What the scene built or building covers.
    private var region: WorldRegion?
    /// Decision 517 續 (PR 3b): the point it is built round.
    private var builtFocus: (x: Double, y: Double)?
    private var memoryWarning: NSObjectProtocol?

    private init() {
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { Map3DSceneCache.shared.clear() }
        }
    }

    /// Lets go of the scene built; one still building is let go once it
    /// ends, and a 3D map opened meanwhile takes it (review L-1). The
    /// next 3D map after that builds anew.
    func clear() {
        if hold.clear() { drop() }
    }

    private func drop() {
        key = nil
        game = nil
        building = nil
        region = nil
        builtFocus = nil
    }

    private func finished(_ number: Int) {
        if hold.finished(number) { drop() }
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
            hold.reuse()
            return building
        }
        // Decision 517 續 (PR 3b's measurement): why this one is built.
        let why: Map3DSceneBuildTime.Why = if let previous = self.key, game === session {
            previous.edges != key.edges || previous.lastEdge != key.lastEdge ? .track : .other
        } else {
            .first
        }
        let world = session.world
        // Decision 517 續 (PR 3b): only the track or the platforms changed
        // since the scene built or building, on a map that builds ahead,
        // where it was built round a point it still holds: it is built
        // again only round what changed, round the same point, once it is
        // done. A scene built round no point (from the settings) is built
        // round the middle of what is built, which new track moves.
        let partOf: (task: Task<Map3DBuiltScene, Never>, focus: (x: Double, y: Double))? =
            if let previous = self.key, game === session, previous.differsOnlyInTrack(from: key), let building, let region,
               let builtFocus, Map3DStreaming.streams(world), Map3DScene.holds(focus, in: region, world: world),
               Map3DScene.region(world: world, focus: builtFocus) == region {
                (building, builtFocus)
            } else {
                nil
            }
        let centre = partOf?.focus ?? focus
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
        let facades = key.facades
        let task = Task.detached(priority: .userInitiated) {
            let seconds = { (duration: Duration) in Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18 }
            // Decision 517 續 (PR 3b): the scene before, once built, with
            // its chunks round the change built again from its files.
            if let partOf {
                let old = await partOf.task.value
                let clock = ContinuousClock()
                let started = clock.now
                let source = old.source.with(world, lineBands: Map3DLineBands(world: world, palette: palette))
                if Map3DSceneRebuild.fits(old.scene, world: world, focus: centre) {
                    let read = clock.now
                    let keys = Map3DSceneRebuild.keys(round: Map3DSceneRebuild.changes(from: old.source.snapshot, old.source.world,
                                                                                        to: source.snapshot, world),
                                                      in: old.scene, map: WorldRegion(bounds: world.bounds))
                    let scene = source.scene(rebuilding: keys, of: old.scene)
                    let number = Map3DSceneBuildLog.shared.add(Map3DSceneBuildTime(
                        why: why, realWorld: world.geoAnchor != nil, edges: world.network.edges.count, chunks: scene.chunks.count,
                        triangles: scene.triangleCount, readSeconds: seconds(read - started), buildSeconds: seconds(clock.now - read),
                        wall: Date().timeIntervalSince1970, rebuiltChunks: keys.count))
                    return Map3DBuiltScene(scene: scene, source: source, buildNumber: number,
                                           rebuilt: old.buildNumber.map { (from: $0, keys: keys) })
                }
            }
            let clock = ContinuousClock()
            let started = clock.now
            let baseMap = tiles.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }.flatMap { try? BaseMapTiles(data: $0) }
            let source = Map3DChunkSource(world: world, snapshot: world.railwaySnapshot(), skyline: CitySkyline(world: world), baseMap: baseMap,
                                          cityTiles: city.map(CityTileArea.areas(in:)) ?? [],
                                          footprints: footprints.flatMap { try? Data(contentsOf: $0, options: .alwaysMapped) }
                                              .flatMap { try? FootprintTiles(data: $0) },
                                          heights: heights,
                                          lineBands: Map3DLineBands(world: world, palette: palette), railways: railways,
                                          temples: temples.flatMap { try? Data(contentsOf: $0) }.flatMap { try? RealTemples(data: $0) },
                                          noBuild: noBuild.flatMap { try? Data(contentsOf: $0) }.flatMap { try? RealNoBuildLand(data: $0) },
                                          facades: facades)
            let read = clock.now
            let scene = source.scene(focus: centre)
            let number = Map3DSceneBuildLog.shared.add(Map3DSceneBuildTime(
                why: why, realWorld: world.geoAnchor != nil, edges: world.network.edges.count, chunks: scene.chunks.count,
                triangles: scene.triangleCount, readSeconds: seconds(read - started), buildSeconds: seconds(clock.now - read),
                wall: Date().timeIntervalSince1970))
            return Map3DBuiltScene(scene: scene, source: source, buildNumber: number)
        }
        self.key = key
        game = session
        building = task
        region = Map3DScene.region(world: world, focus: centre)
        builtFocus = centre
        let number = hold.start()
        Task {
            _ = await task.value
            finished(number)
        }
        return task
    }
}

/// Decision 358: a scene built, and what it was built from, from which
/// the chunks ahead of the camera are built as it moves.
struct Map3DBuiltScene: Sendable {
    let scene: Map3DScene
    let source: Map3DChunkSource
    /// Decision 517 續: its number in ``Map3DSceneBuildLog``, for the time
    /// it takes to show.
    var buildNumber: Int?
    /// Decision 517 續 (PR 3b): built from the scene of build `from` with
    /// only its chunks at `keys` built again; `nil` when built whole.
    var rebuilt: (from: Int, keys: Set<Map3DStreaming.Key>)?
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
    /// Decision 610 續 (review L12-1): whether the real buildings' street
    /// fronts are built (``Map3DQuality/scenesKeepFacades``).
    let facades: Bool

    func scene(focus: (x: Double, y: Double)?) -> Map3DScene {
        Map3DScene(world: world, snapshot: snapshot, skyline: skyline, focus: focus, baseMap: baseMap, cityTiles: cityTiles,
                   footprints: footprints, heights: heights, lineBands: lineBands, railways: railways, temples: temples, noBuild: noBuild,
                   facades: facades)
    }

    /// Decision 517 續 (PR 3b): the same files for `world`, its track,
    /// city and the lines' bands (`lineBands`) worked out again.
    func with(_ world: GameWorld, lineBands: Map3DLineBands) -> Map3DChunkSource {
        Map3DChunkSource(world: world, snapshot: world.railwaySnapshot(), skyline: CitySkyline(world: world), baseMap: baseMap,
                         cityTiles: cityTiles, footprints: footprints, heights: heights, lineBands: lineBands, railways: railways,
                         temples: temples, noBuild: noBuild, facades: facades)
    }

    /// Decision 517 續 (PR 3b): `old` with its chunks at `keys` built
    /// again from this, as ``scene(focus:)`` builds the whole (the city in
    /// full round the middle on a map that builds ahead, decision 368).
    func scene(rebuilding keys: Set<Map3DStreaming.Key>, of old: Map3DScene) -> Map3DScene {
        Map3DScene(rebuilding: keys, of: old, world: world, snapshot: snapshot, skyline: skyline, baseMap: baseMap, cityTiles: cityTiles,
                   footprints: footprints, heights: heights, lineBands: lineBands, railways: railways, temples: temples, noBuild: noBuild,
                   detail: Map3DStreaming.streams(world) ? Map3DPoint(0, 0, 0) : nil, facades: facades)
    }

    /// Decision 359 (續): with the scene's `trackCover`, which lays the
    /// tunnels as the scene did. Decision 368: the city in full only round
    /// `detail`.
    func chunks(_ keys: [Map3DStreaming.Key], of grid: Map3DStreaming, trackCover: Map3DTrackCover, detail: Map3DPoint) -> [Map3DScene.Chunk] {
        Map3DScene.chunks(keys, of: grid, world: world, snapshot: snapshot, skyline: skyline, baseMap: baseMap, cityTiles: cityTiles,
                          footprints: footprints, heights: heights, lineBands: lineBands, railways: railways, temples: temples, noBuild: noBuild,
                          trackCover: trackCover, detail: detail, facades: facades)
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
    /// Decision 578: the platform of the stop the followed train runs to,
    /// whose surroundings are built before it gets there.
    var stops: [Map3DPoint] = []
    /// Decision 583: the way the followed cabin runs, the strip ahead's
    /// (``Map3DStreaming/Window/step(target:at:stops:ahead:)``).
    var ahead: (@MainActor () -> SIMD2<Float>?)?
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

    /// Decision 578: whether the chunks round `point` are all built (with
    /// no window, the scene is whole).
    func isBuilt(round point: Map3DPoint) -> Bool {
        window?.isBuilt(round: point) ?? true
    }

    /// Decision 606 (續): the same, with the city in full there.
    func isBuiltInFull(round point: Map3DPoint) -> Bool {
        window?.isBuiltInFull(round: point) ?? true
    }

    /// The camera this frame, at `time`.
    func step(_ camera: Map3DCamera, at time: CFTimeInterval) {
        guard var window, let source else { return }
        let (drop, build) = window.step(target: camera.target, at: time, stops: stops, ahead: ahead?())
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
    /// BUGHUNT_BUILD P2-2: a road laid along the city's (free, decision
    /// 487) shows at once too, though the count above stays.
    let ownRoads: Set<CellPosition>
    /// Decision 506, later: an expanded station's bigger building shows
    /// at once.
    let expansions: Int
    /// Decision 610 續 (review L12-1): whether the street fronts are built,
    /// so a scene is built again when the 3D look starts or stops drawing
    /// them.
    let facades: Bool

    init(world: GameWorld, hasHeights: Bool, hasRailways: Bool = false, focus: (x: Double, y: Double)? = nil, palette: LinePalette? = nil,
         facades: Bool = Map3DQuality.scenesKeepFacades) {
        self.facades = facades
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
        // PERF_3D_COCKPIT: counted, not made into one set at every tick.
        roads = world.roads?.roadCellCount ?? 0
        ownRoads = world.roads?.built ?? []
        expansions = Map3DStationKit.expansionSignature(of: world)
    }

    /// Decision 517 續 (PR 3b): whether `other` differs from this only in
    /// the track and the platforms (what a scene can build again in part).
    func differsOnlyInTrack(from other: Map3DSceneKey) -> Bool {
        self != other && hasHeights == other.hasHeights && hasRailways == other.hasRailways && focus == other.focus
            && buildings == other.buildings && week == other.week && lines == other.lines && palette == other.palette
            && bought == other.bought && roads == other.roads && ownRoads == other.ownRoads && expansions == other.expansions
            && facades == other.facades
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
    /// routes or the scene change (off the main actor, decision 424's
    /// second sequel).
    private var busWorld: GameWorld?
    private var busPalette: LinePalette = .standard
    private var busRoads: BusRoads?
    private var busSignature: Map3DBuses.Signature?
    private var busClock: RealTrainClock?
    private var busGlides = true
    private let buses = Map3DBuses.Layer()
    /// Decision 575 續 (CABLEMAP): the player's cable cars laid in the
    /// scene, laid again when the cable cars or the scene change.
    private var cableways: Map3DCableways?
    private var cablewaysScene: (x: Double, y: Double)?
    /// Decision 585 PR-3 (FERRY3): the player's ferries laid in the
    /// scene, laid again when the routes or the scene change.
    private var ferries: Map3DFerries?
    private var ferriesScene: (x: Double, y: Double)?
    /// Decision 400 (FOLLOWBUS): the bus the camera follows, always drawn.
    var followedBus: BusID?
    /// Decision 583 (CABLEFOLLOW): the cabin the camera follows, always
    /// drawn whole, its way the cable cars' ahead.
    var followedCabin: CabinID?
    /// Decision 585 PR-4 (FERRYFOLLOW): the boat the camera follows, always
    /// drawn whole, its way the ferries' ahead.
    var followedFerry: FerryBoatID?
    /// Decision 437: told the evening garbage truck's tune as heard from
    /// the camera each frame (``GameAudio/setGarbageTruck(_:)``, which
    /// acts only on a change), `nil` when there is none near.
    var garbageTruckSound: ((Map3DGarbageTruck.Sound?) -> Void)?

    /// Decision 485: the glide and the heights the tick worked out off
    /// the main actor (the glide shared with the 2D map under this one),
    /// not worked out again here at every tick.
    func update(session: GameSession, palette: LinePalette) {
        let world = session.world
        motion = session.trainMotion(after: motion, at: Date().timeIntervalSinceReferenceDate)
        heights = session.map3DTrainHeights()
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
    func updateBuses(world: GameWorld, palette: LinePalette, roads: BusRoads?, glides: Bool) {
        busClock = RealTrainClock(world: world, previous: busClock, time: Date().timeIntervalSinceReferenceDate)
        busGlides = glides
        busWorld = world
        busPalette = palette
        busRoads = roads
        busSignature = Map3DBuses.Signature(world: world, palette: palette, roads: roads)
    }

    /// Decision 400, 10i-6: the player's buses round the camera's target;
    /// none, or the ones laid before, while they are laid off the main
    /// actor (decision 424's second sequel).
    private func busFrame(in scene: Map3DScene, camera: Map3DCamera, detail: Map3DStreetDetail, most: Int?, now: Double) -> Map3DBuses.Frame {
        guard let world = busWorld, let signature = busSignature, let clock = busClock,
              let laid = buses.buses(signature, world: world, in: scene, palette: busPalette, roads: busRoads) else { return .init() }
        return laid.frame(second: clock.second(at: now, glides: busGlides), target: camera.target, distance: camera.distance,
                          detail: detail, most: most, followed: followedBus)
    }

    /// Decision 400 (FOLLOWBUS): where bus `id` is now, as the follow
    /// camera reads it, at the clock the buses are drawn at.
    func busPose(_ id: BusID, in scene: Map3DScene) -> Map3DFollow.Pose? {
        guard let world = busWorld, let signature = busSignature, let clock = busClock,
              let laid = buses.buses(signature, world: world, in: scene, palette: busPalette, roads: busRoads) else { return nil }
        return laid.pose(of: id, second: clock.second(at: Date().timeIntervalSinceReferenceDate, glides: busGlides))
    }

    /// Decision 400 (FOLLOWBUS): the bus drawn under the finger at
    /// (`x`, `y`), if any, for a tap on the map.
    func bus(atX x: Float, y: Float, camera: Map3DCamera, in scene: Map3DScene) -> BusID? {
        guard let world = busWorld, let signature = busSignature, let clock = busClock,
              let laid = buses.buses(signature, world: world, in: scene, palette: busPalette, roads: busRoads) else { return nil }
        return laid.bus(atX: x, y: y, camera: camera, second: clock.second(at: Date().timeIntervalSinceReferenceDate, glides: busGlides),
                        within: Map3DBuses.tapReach)
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
        // Decision 437: the evening garbage truck, among the buses.
        let trucks = Map3DGarbageTruck.frame(in: scene.streetLife, camera: camera, clock: busClock, glides: busGlides, now: now,
                                             still: UIAccessibility.isReduceMotionEnabled, budget: budget)
        garbageTruckSound?(Map3DGarbageTruck.sound(of: trucks, camera: camera))
        let buses = busFrame(in: scene, camera: camera, detail: detail, most: budget.tier?.streetLimits.buses, now: now).adding(trucks)
        // Decision 596: while the signals change, the traffic and the
        // walkers go by the game's clock (the buses'), waiting at them.
        var signals: Double?
        if let world = busWorld, let clock = busClock, Map3DSignalTiming.changes(at: world.clock.runningSpeed) {
            signals = Double(clock.day * GameTime.secondsPerDay) + clock.second(at: now, glides: busGlides)
        }
        return scene.streetLife.frame(target: camera.target, distance: camera.distance, time: time,
                                      still: UIAccessibility.isReduceMotionEnabled, lights: lights, detail: detail, activity: activity,
                                      buses: buses, limits: budget.limits(routeBuses: buses.instances.count), signals: signals)
    }

    /// The trains seen from `eye`, `ringed` with its ring (decision 334),
    /// their far models and boxes from `reach` (decision 417).
    func frame(in scene: Map3DScene, models: Map3DModelPack?, eye: Map3DPoint, target: Map3DPoint? = nil, ringed: TrainID?,
               reach: Map3DModelReach) -> Map3DTrains.Frame {
        let now = Date().timeIntervalSinceReferenceDate
        let progress = motion.isMoving ? motion.progress(at: now) : 1
        var frame = Map3DTrains.frame(motion, progress: progress, heights: heights, in: scene, models: models, eye: eye, palette: palette,
                                      ringed: ringed, reach: reach)
        // Decision 339: and the real timetables' trains, on their own track.
        if let real = scene.realTrains, let clock = realClock {
            real.add(to: &frame, second: clock.second(at: now, glides: realGlides), day: clock.today, dayBefore: clock.dayBefore,
                     models: models, eye: eye, reach: reach)
        }
        // Decision 436: the cab cars' lit destination signs, close up.
        Map3DHeadSign.add(to: &frame, signs: models?.headSigns ?? [:], eye: eye)
        // Decision 575 續 (CABLEMAP): and the cable cars' halls, towers,
        // ropes and cabins, on the buses' clock.
        if let models, let laid = laidCableways(in: scene), let second = cableSecond(at: now) {
            // Decision 583: the followed cabin's way is ahead.
            let ahead = followedCabin.flatMap { laid.pose(of: $0, second: second)?.forward }
            frame.instances += laid.frame(second: second, eye: eye, target: target ?? eye, pack: models, reach: reach.farModel,
                                          following: followedCabin, ahead: ahead).instances
        }
        // Decision 585 PR-3 (FERRY3): and the ferries' piers and boats, on
        // the same clock.
        if let models, let laid = laidFerries(in: scene), let second = cableSecond(at: now) {
            // Decision 585 PR-4: the followed boat's way is ahead.
            let ahead = followedFerry.flatMap { laid.pose(of: $0, second: second)?.forward }
            frame.instances += laid.frame(second: second, eye: eye, target: target ?? eye, pack: models, reach: reach.farModel,
                                          following: followedFerry, ahead: ahead).instances
        }
        return frame
    }

    /// Decision 606 (IDLEREAL): where real train `id` is now, as the
    /// follow camera reads it, at the clock the real trains are drawn at;
    /// `nil` while they are hidden or it is not drawn.
    func realTrainPose(_ id: RealTrainID, in scene: Map3DScene) -> Map3DFollow.Pose? {
        guard let real = scene.realTrains, let clock = realClock else { return nil }
        return real.pose(of: id, second: clock.second(at: Date().timeIntervalSinceReferenceDate, glides: realGlides),
                         day: clock.today, dayBefore: clock.dayBefore)
    }

    /// Decision 585 PR-4 (FERRYFOLLOW): where boat `id` is now, as the
    /// follow camera reads it.
    func ferryPose(_ id: FerryBoatID, in scene: Map3DScene) -> Map3DFollow.Pose? {
        guard let laid = laidFerries(in: scene), let second = cableSecond(at: Date().timeIntervalSinceReferenceDate) else { return nil }
        return laid.pose(of: id, second: second)
    }

    /// Decision 585 PR-4: the pier the followed boat comes to next, built
    /// round before it is there; none when no boat is followed.
    func ferryStopsAhead(in scene: Map3DScene?) -> [Map3DPoint] {
        guard let followedFerry, let scene, let laid = laidFerries(in: scene),
              let second = cableSecond(at: Date().timeIntervalSinceReferenceDate),
              let pier = laid.pierAhead(of: followedFerry, second: second) else { return [] }
        return [pier]
    }

    /// Decision 585 PR-4: the boat drawn under the finger at (`x`, `y`), if any.
    func ferryBoat(atX x: Float, y: Float, camera: Map3DCamera, in scene: Map3DScene) -> FerryBoatID? {
        guard let laid = laidFerries(in: scene), let second = cableSecond(at: Date().timeIntervalSinceReferenceDate) else { return nil }
        return laid.boat(atX: x, y: y, camera: camera, second: second, within: Map3DBuses.tapReach)
    }

    /// Decision 585 PR-3: the ferries laid in `scene`, laid again when
    /// they or the scene change; `nil` with none.
    private func laidFerries(in scene: Map3DScene) -> Map3DFerries? {
        guard let world = busWorld, !world.ferryRoutes.isEmpty else { return nil }
        if ferries?.routes != world.ferryRoutes || ferriesScene?.x != scene.originX || ferriesScene?.y != scene.originY {
            ferries = Map3DFerries(world: world, scene: scene)
            ferriesScene = (scene.originX, scene.originY)
        }
        return ferries
    }

    /// Decision 575 續: the cable cars laid in `scene`, laid again when
    /// they or the scene change; `nil` with none.
    private func laidCableways(in scene: Map3DScene) -> Map3DCableways? {
        guard let world = busWorld, !world.cableways.isEmpty else { return nil }
        if cableways?.cableways != world.cableways || cablewaysScene?.x != scene.originX || cablewaysScene?.y != scene.originY {
            cableways = Map3DCableways(world: world, scene: scene)
            cablewaysScene = (scene.originX, scene.originY)
        }
        return cableways
    }

    /// The game second the cable cars are drawn at (the buses' clock).
    private func cableSecond(at now: Double) -> Double? {
        guard let clock = busClock else { return nil }
        return Double(clock.day * GameTime.secondsPerDay) + clock.second(at: now, glides: busGlides)
    }

    /// Decision 583 (CABLEFOLLOW): where cabin `id` is now, as the follow
    /// camera reads it.
    func cabinPose(_ id: CabinID, in scene: Map3DScene) -> Map3DFollow.Pose? {
        guard let laid = laidCableways(in: scene), let second = cableSecond(at: Date().timeIntervalSinceReferenceDate) else { return nil }
        return laid.pose(of: id, second: second)
    }

    /// Decision 583: the hall the followed cabin comes to next, built round
    /// before it is there; none when no cabin is followed.
    func cabinStopsAhead(in scene: Map3DScene?) -> [Map3DPoint] {
        guard let followedCabin, let scene, let laid = laidCableways(in: scene),
              let second = cableSecond(at: Date().timeIntervalSinceReferenceDate),
              let hall = laid.stopAhead(of: followedCabin, second: second) else { return [] }
        return [hall]
    }

    /// Decision 583: the cabin drawn under the finger at (`x`, `y`), if any.
    func cabin(atX x: Float, y: Float, camera: Map3DCamera, in scene: Map3DScene) -> CabinID? {
        guard let laid = laidCableways(in: scene), let second = cableSecond(at: Date().timeIntervalSinceReferenceDate) else { return nil }
        return laid.cabin(atX: x, y: y, camera: camera, second: second, within: Map3DBuses.tapReach)
    }
}

/// Decision 645 (B5, the Mac playtest of 2026-11-08: "3D 看不到時間"):
/// the game's date and time in the 3D map's corner, the status bar's
/// shorter clock (``GameClock/shortCalendarText(in:)``) read from the
/// session's world as the 2D map's is; nothing kept of its own. Only
/// shown, not a button: the forecast stays on the 2D map.
private struct Map3DClock: View {
    let session: GameSession

    var body: some View {
        let text = session.world.clock.shortCalendarText(in: session.language)
        Label {
            Text(verbatim: text)
                .monospacedDigit()
        } icon: {
            Image(systemName: "clock.fill")
                .foregroundStyle(Theme.primary)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: session.language.text("Game time \(text)", "遊戲時間 \(text)")))
        .accessibilityIdentifier("map3D.clock")
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
    /// Decision 517: the view Build left, to open at again.
    let resumes: Map3DBuildReturn.Viewpoint?
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
    /// Whether ``Map3DTrainModels`` has made them (decision 546: the scene
    /// is shown before).
    let modelsReady: Bool
    /// Decision 517 續: placed under its station each frame.
    let stationTag: Map3DStationTagState
    /// Decision 517 續: a tap on the map, with the camera then and where,
    /// in points; `nil` takes none.
    let onTap: (@MainActor (Map3DCamera, CGPoint) -> Void)?
    let onStats: @MainActor (Map3DMetalView.Stats) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(compass: compass)
    }

    /// Decision 230: the train models, made in code once.
    // The city bus, the evening trucks (decision 437) and the conifers,
    // bushes and tanks (decision 458) from their files, or the code-made
    // ones. K1-1, K2-4: made off the main thread (the screen's
    // `modelsReady`), never first read in `makeUIView`.
    // Decision 608: made once, by ``Map3DTrainModels``, which keeps
    // them on the GPU (``Map3DUploadedModels``), not held here.
    nonisolated static func makeModels() -> Map3DModelPack? {
        Map3DSceneryProp.pack(Map3DGarbageTruck.pack(
        Map3DCityBus.pack(file: Bundle.main.url(forResource: Map3DCityBus.fileName, withExtension: Map3DCityBus.fileExtension)),
        files: Map3DGarbageTruck.fileNames.compactMapValues { Bundle.main.url(forResource: $0, withExtension: Map3DGarbageTruck.fileExtension) }),
        files: Dictionary(uniqueKeysWithValues: Map3DSceneryProp.allCases.compactMap { prop in
            Bundle.main.url(forResource: prop.fileName, withExtension: Map3DSceneryProp.fileExtension).map { (prop, $0) }
        }))
    }

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
        view.lookoutBuilt = { [weak coordinator = context.coordinator] eye in coordinator?.streamer.isBuilt(round: eye) ?? true }
        view.trainGroundBuilt = { [weak coordinator = context.coordinator] rail in coordinator?.streamer.isBuiltInFull(round: rail) ?? true }
        view.landed = { [weak coordinator = context.coordinator] in coordinator?.showHeading() }
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.rotate(_:)))
        // Decision 555: two fingers dragged up or down lean the map over.
        let tilt = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tilt(_:)))
        tilt.minimumNumberOfTouches = 2
        tilt.maximumNumberOfTouches = 2
        // Decision 517 續: a tap, which a drag, a pinch or a turn is not.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        for recognizer in [pan, pinch, rotation, tilt, tap] as [UIGestureRecognizer] {
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
        // Decision 429: the junctions' signals change with the game clock.
        view.signalClock = Map3DSignalTiming.Clock(world.clock)
        context.coordinator.farOut = farOut
        context.coordinator.onTap = onTap
        defer {
            // Decision 333: once the first scene has its camera, so the
            // flight starts from it.
            // Decision 403 (續): from the station, where it stands now.
            var follow = follow
            // One switch over a local copy of the subject rather than
            // `follow?.bus`, `.cabin`, ...: those crashed Xcode 26.6's
            // Release optimizer (CopyPropagation). Do not change it back.
            var followedTrain: TrainID?, followedBus: BusID?, followedCabin: CabinID?, followedFerry: FerryBoatID?
            switch follow?.subject {
            case .train(let id)?: followedTrain = id
            case .bus(let id)?: followedBus = id
            case .cabin(let id)?: followedCabin = id
            case .ferry(let id)?: followedFerry = id
            case .realTrain?, nil: break
            }
            feed.followedBus = followedBus
            feed.followedCabin = followedCabin
            feed.followedFerry = followedFerry
            if let id = followedTrain, follow?.view == .station, let scene {
                follow?.lookout = Map3DFollow.lookout(of: id, in: world, scene: scene)
            }
            // Decision 578: from the moment it leaves a stop, the next
            // stop's surroundings are built, unless it is too far to be
            // offered.
            context.coordinator.streamer.stops = context.coordinator.stopsAhead(of: followedTrain, in: world, scene: scene)
                + feed.cabinStopsAhead(in: scene) + feed.ferryStopsAhead(in: scene)
            if context.coordinator.shownVersion != nil,
               view.following?.subject != follow?.subject || view.following?.view != follow?.view || view.following?.lookout != follow?.lookout {
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
        // Decision 546: the scene shown as soon as it is built, its trains
        // as boxes and its street furniture left out until the models are
        // made (``Map3DTrainModels``), then drawn with them.
        if modelsReady, !context.coordinator.hasModels, let models = Map3DTrainModels.shared.uploaded {
            context.coordinator.hasModels = true
            view.useModels(models)
            if let scene, context.coordinator.shownVersion != nil { showTrains(in: scene, on: view, context: context) }
        }
        guard let scene, context.coordinator.shownVersion != sceneVersion else { return }
        let first = context.coordinator.shownVersion == nil
        context.coordinator.shownVersion = sceneVersion
        // Decision 358: the chunks built ahead that the scene built anew
        // round the same place does not hold, kept until built again.
        let kept = context.coordinator.streamer.kept(for: scene)
        let showing = ContinuousClock.now
        if !first, let rebuilt = built?.rebuilt, context.coordinator.shownBuild == rebuilt.from {
            // Decision 517 續 (PR 3b): built again from the scene shown,
            // only where the track changed: only those chunks handed over,
            // the rest drawn on as they are.
            view.replace(rebuilt.keys, from: scene)
        } else {
            view.show(scene, keeping: kept)
        }
        context.coordinator.shownBuild = built?.buildNumber
        // Decision 517 續 (PR 3b's measurement): how long handing it over took.
        if let number = built?.buildNumber {
            let took = ContinuousClock.now - showing
            Map3DSceneBuildLog.shared.shown(number, seconds: Double(took.components.seconds) + Double(took.components.attoseconds) * 1e-18)
        }
        context.coordinator.streamer.start(built, kept: kept)
        showTrains(in: scene, on: view, context: context)
        let feed = feed, labels = trainLabels, tag = stationTag
        view.trainHeads = { heads, camera in
            labels.show(feed.labels(heads: heads, camera: camera))
            tag.place(seenBy: camera)
        }
        view.streetLife = { camera, lights, budget in feed.streetLife(in: scene, camera: camera, lights: lights, budget: budget) }
        view.busPose = { id in feed.busPose(id, in: scene) }
        view.cabinPose = { id in feed.cabinPose(id, in: scene) }
        view.ferryPose = { id in feed.ferryPose(id, in: scene) }
        view.realTrainPose = { id in feed.realTrainPose(id, in: scene) }
        // Decision 583: the strip built ahead lies the way the followed
        // cabin runs; decision 585 PR-4: or boat.
        context.coordinator.streamer.ahead = { [weak view] in
            // One switch over a local copy of the subject: the chained
            // `following?.cabin ?? .ferry ?? .realTrain` crashed Xcode
            // 26.6's Release optimizer (CopyPropagation). Do not change it back.
            let subject = view?.following?.subject
            let found: Map3DFollow.Pose?
            switch subject {
            case .cabin(let id)?: found = feed.cabinPose(id, in: scene)
            case .ferry(let id)?: found = feed.ferryPose(id, in: scene)
            // Decision 606: or real train.
            case .realTrain(let id)?: found = feed.realTrainPose(id, in: scene)
            case .train?, .bus?, nil: found = nil
            }
            guard let pose = found else { return nil }
            return SIMD2(pose.forward.x, pose.forward.z)
        }
        if first, let start {
            // Decision 269: where the 2D map was, as close, straight down.
            view.camera = Map3DHandoff.camera(from: start, in: scene, viewport: view.camera.viewport)
            context.coordinator.handedOverAt = view.camera.distance
        } else if first, let resumes {
            // Decision 517: back where Build left, turned and leaning as it was.
            view.camera = resumes.camera(in: scene, viewport: view.camera.viewport)
        } else if first {
            // Open over the place the 2D map showed (decision 313, later),
            // as close as it was but never further than the whole scene
            // (decision 645, D5), or from the settings the middle of what
            // is built, the whole scene in view.
            let width = Float((scene.region.maxX - scene.region.minX) / Double(WorldCoordinate.unitsPerMetre))
            let height = Float((scene.region.maxY - scene.region.minY) / Double(WorldCoordinate.unitsPerMetre))
            let target = openedAt.map { scene.point(worldX: $0.x, worldY: $0.y, height: 0) } ?? .zero
            let distance = Map3DHandoff.openingDistance(of: openedAt, sceneSpan: max(width, height),
                                                        viewportHeight: Double(view.camera.viewport.height))
            view.camera = Map3DCamera(target: target, distance: distance, viewport: view.camera.viewport)
        }
        #if DEBUG
        // Decision 555: a screenshot's camera, over its scene's place.
        if first, let camera = Self.screenshotCamera(in: scene, of: world, viewport: view.camera.viewport) { view.camera = camera }
        #endif
        context.coordinator.showHeading()
    }

    #if DEBUG
    /// Decision 555: the camera `-screenshot-3d-view` asks for over the
    /// place of the `-screenshot-scene` (Debug builds only).
    private static func screenshotCamera(in scene: Map3DScene, of world: GameWorld, viewport: (width: Float, height: Float)) -> Map3DCamera? {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let asked = value("-screenshot-3d-view").flatMap(Map3DScreenshotView.init) else { return nil }
        // Decision 575 續 (CABLEMAP): over a span of the cable car.
        if let span = value("-screenshot-3d-cableway") { return asked.camera(cableway: span, in: scene, of: world, viewport: viewport) }
        // Decision 585 PR-3 (FERRY3): over the first ferry's first boat.
        if arguments.contains("-screenshot-3d-ferry") { return asked.camera(ferryIn: scene, of: world, viewport: viewport) }
        // Decision 602: over a place of the scene's map ("latitude,longitude").
        if let at = value("-screenshot-3d-at")?.split(separator: ",").compactMap({ Double($0) }), at.count == 2 {
            return asked.camera(at: (latitude: at[0], longitude: at[1]), in: scene, of: world, viewport: viewport)
        }
        guard let place = value("-screenshot-scene").flatMap(ScreenshotScene.init(rawValue:))?.place else { return nil }
        return asked.camera(at: place, in: scene, of: world, viewport: viewport)
    }
    #endif

    /// Draws `scene`'s trains on `view`: with the models once they are
    /// made (decision 546), boxes before.
    private func showTrains(in scene: Map3DScene, on view: Map3DMetalView, context: Context) {
        // Decision 338: the train pack's sets as before them until it is
        // unlocked.
        let unlocked = TrainPack.isUnlocked(testBuild: TestBuild.isTest,
                                            switchOn: UserDefaults.standard.bool(forKey: TrainPack.testUnlockKey))
        let pushPullE1000 = UserDefaults.standard.bool(forKey: TrainPack.pushPullE1000Key)
        // Never read before they are made: the main thread would wait for them.
        let feed = feed, models = context.coordinator.hasModels ? Map3DTrainModels.shared.uploaded.map { uploaded in
            var pack = uploaded.pack
            pack.locked = TrainPack.locked(unlocked: unlocked, pushPullE1000: pushPullE1000)
            return pack
        } : nil
        view.trains = { [weak view] eye, reach in feed.frame(in: scene, models: models, eye: eye, target: view?.camera.target, ringed: view?.ringed,
                                                                 reach: reach) }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: Map3DMetalView?
        var shownVersion: Int?
        /// Decision 517 續 (PR 3b): the number of the build shown
        /// (``Map3DSceneBuildLog``), whose chunks a scene built again from
        /// it replaces only where it built them again.
        var shownBuild: Int?
        /// Decision 546: whether the view has the train models.
        var hasModels = false
        /// Decision 358.
        let streamer = Map3DChunkStreamer()
        /// Decision 578: the stop ahead's platform eye, worked out again
        /// only when the train, its stop or the scene changes.
        private var stopAhead: (train: TrainID, station: StationID, originX: Double, originY: Double, eye: Map3DPoint?)?

        func stopsAhead(of train: TrainID?, in world: GameWorld, scene: Map3DScene?) -> [Map3DPoint] {
            guard let train, let scene, let station = world.map3DStopAhead(of: train),
                  Map3DFollow.stationViewIsOffered(remainingMetres: world.map3DMetresToStopAhead(of: train)) else {
                stopAhead = nil
                return []
            }
            if let known = stopAhead, known.train == train, known.station == station,
               known.originX == scene.originX, known.originY == scene.originY {
                return known.eye.map { [$0] } ?? []
            }
            let eye = Map3DFollow.lookout(of: train, at: station, in: world, scene: scene)?.eye
            stopAhead = (train, station, scene.originX, scene.originY, eye)
            return eye.map { [$0] } ?? []
        }
        /// Decision 334: the departure last flown to.
        var flownTo: Map3DNextDeparture?
        var farOut: ((Map3DCamera) -> Void)?
        var onTap: (@MainActor (Map3DCamera, CGPoint) -> Void)?
        /// Decision 269: how far out the camera a pinch handed over opened;
        /// `nil` when the 3D button opened the map.
        var handedOverAt: Float?
        private var handedBack = false
        /// Decision 313: the distance as the pinch under way began.
        private var pinchFrom: Float?
        /// Decision 555: the two fingers under way, whether they lean the
        /// map, the camera as they touched down and how far down the
        /// screen the lean has taken them so far.
        private var tiltDrag: Map3DTiltDrag?
        private var tiltStart: Map3DCamera?
        private var tiltDropped: Float = 0
        /// Whether two fingers are leaning the map: the pinch and the turn wait.
        private var leaning: Bool { tiltDrag?.verdict == .leans }
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
            // Decision 555: two fingers leaning the map do not zoom it.
            guard !leaning else {
                recognizer.scale = 1
                pinchFrom = nil
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

        /// Decision 555: two fingers dragged up the screen lean the map
        /// over, down stand it up again, as far as the distance's own
        /// tilt (``Map3DCamera/leaned(dy:)``); following a train they do
        /// nothing. Until ``Map3DTiltDrag`` tells a lean from a pinch or a
        /// turn, those act; once it leans, the camera's distance and
        /// heading go back to where the fingers touched down. The tilt
        /// follows the fingers, with no animation of its own, so Reduce
        /// Motion leaves it as it is.
        @objc func tilt(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            func fingers() -> (Map3DTiltDrag.Point, Map3DTiltDrag.Point)? {
                guard recognizer.numberOfTouches == 2 else { return nil }
                let a = recognizer.location(ofTouch: 0, in: view), b = recognizer.location(ofTouch: 1, in: view)
                return ((Float(a.x), Float(a.y)), (Float(b.x), Float(b.y)))
            }
            switch recognizer.state {
            case .began:
                stopTurningNorth()
                tiltDrag = nil
                tiltStart = nil
                tiltDropped = 0
                guard view.following == nil, let (a, b) = fingers() else { return }
                tiltDrag = Map3DTiltDrag(a, b)
                tiltStart = view.camera
            case .changed:
                guard var drag = tiltDrag, view.following == nil, let (a, b) = fingers() else { return }
                let was = drag.verdict
                guard drag.move(a, b) == .leans else {
                    tiltDrag = drag
                    return
                }
                tiltDrag = drag
                if was != .leans, let start = tiltStart {
                    view.stopFlyingBack()
                    var camera = view.camera
                    camera.distance = start.distance
                    camera.heading = start.heading
                    view.camera = camera
                    showHeading()
                }
                let drop = drag.drop(a, b)
                view.camera = view.camera.leaned(dy: drop - tiltDropped)
                tiltDropped = drop
            default:
                tiltDrag = nil
                tiltStart = nil
                tiltDropped = 0
            }
        }

        /// Decision 517 續: following a train, a tap does nothing here.
        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view, view.following == nil, let onTap else { return }
            onTap(view.camera, recognizer.location(in: view))
        }

        @objc func rotate(_ recognizer: UIRotationGestureRecognizer) {
            if recognizer.state == .began { stopTurningNorth() }
            guard let view else { return }
            guard view.following == nil, !leaning else {
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

/// Decision 517 續: the station tapped on the 3D map, and where its tag
/// stands: set by the screen on a tap, placed by the Metal view each frame
/// as the camera moves, only when it moves a whole point.
@MainActor
@Observable
final class Map3DStationTagState {
    private(set) var station: StationID?
    /// Where the station is drawn, in the view's points; `nil` behind the eye.
    private(set) var point: CGPoint?
    @ObservationIgnored private var anchor: Map3DPoint?

    func show(_ id: StationID?, at anchor: Map3DPoint?, seenBy camera: Map3DCamera) {
        station = anchor == nil ? nil : id
        self.anchor = anchor
        point = anchor.flatMap { camera.screenPoint(of: $0) }.map { CGPoint(x: CGFloat($0.x.rounded()), y: CGFloat($0.y.rounded())) }
        pending = point
    }

    /// Called from the Metal view's frame: the move is taken after the
    /// frame, once, not while the frame (which a view update can start) is
    /// being drawn, so placing the tag never starts another update inside
    /// one.
    func place(seenBy camera: Map3DCamera) {
        let next = anchor.flatMap { camera.screenPoint(of: $0) }.map { CGPoint(x: CGFloat($0.x.rounded()), y: CGFloat($0.y.rounded())) }
        pending = next
        guard next != point, !isPlacing else { return }
        isPlacing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            isPlacing = false
            if pending != point { point = pending }
        }
    }

    @ObservationIgnored private var pending: CGPoint?
    @ObservationIgnored private var isPlacing = false
}

/// Decision 517 續: the 2D map's station tag (decision 119,
/// ``StationTagCard``) under the station tapped on the 3D map; its details
/// and pencil open on the 2D map. Shown while that station stays selected
/// and nothing is followed; it pops up as on the 2D map (``MotionRule/pop``).
private struct Map3DStationTagView: View {
    let state: Map3DStationTagState
    let session: GameSession
    let open: (_ rename: Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var size = CGSize(width: 160, height: 44)
    /// The map's viewport, measured rather than read in a GeometryReader
    /// (CRASHSWEEP-3).
    @State private var viewport: CGSize = .zero

    /// The controls along the top and the hint along the bottom, kept clear.
    private static let clear: (top: Float, leading: Float, bottom: Float, trailing: Float) = (72, 0, 64, 0)

    // CRASHSWEEP-3: the viewport from `onGeometryChange`, whose measuring
    // closure is sendable, not a GeometryReader's closure, which SwiftUI
    // calls again as the map's size changes and its asynchronous renderer
    // may call off the main thread (CRASH101). The tag waits for the
    // first size.
    var body: some View {
        ZStack(alignment: .topLeading) {
            if viewport != .zero, let tag, let origin = origin(in: viewport) {
                StationTagCard(tag: tag, session: session, details: { open(false) }, rename: { open(true) }, identifier: "map3D.stationTag")
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .offset(origin)
                    .transition(.pop(anchor: .top, reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: state.station)
    }

    private var tag: StationTag? {
        guard session.tool == .select, session.tutorial == nil, !session.isFollowingVehicle,
              let id = state.station, id == session.selectedStationID else { return nil }
        return StationTag(world: session.world, station: id)
    }

    private func origin(in viewport: CGSize) -> CGSize? {
        guard let point = state.point,
              let origin = Map3DTap.tagOrigin(under: Float(point.x), Float(point.y), width: Float(size.width), height: Float(size.height),
                                              viewport: (Float(viewport.width), Float(viewport.height)), clear: Self.clear)
        else { return nil }
        return CGSize(width: CGFloat(origin.x), height: CGFloat(origin.y))
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
    /// PERF (2026-10-30): the frames a second the 3D map aims for.
    let aim: Int
    /// How far the day's light has gone (``Map3DLighting/night``).
    let night: Float
    /// Decision 394: the cab deep in a tunnel, where no rain falls.
    let underground: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    nonisolated static func == (lhs: Map3DRainLayer, rhs: Map3DRainLayer) -> Bool {
        lhs.rain == rhs.rain && lhs.detail == rhs.detail && lhs.aim == rhs.aim && lhs.night == rhs.night && lhs.underground == rhs.underground
    }

    var body: some View {
        let rain = rain, detail = detail
        let look = rain.look(night: night)
        let colour = Color(.sRGB, red: Double(look.colour >> 16 & 0xFF) / 255, green: Double(look.colour >> 8 & 0xFF) / 255,
                           blue: Double(look.colour & 0xFF) / 255, opacity: look.opacity)
        return Group {
            if rain.amount > 0, !reduceMotion, !underground {
                // No more often than the map under it, 60 a second at most.
                TimelineView(.animation(minimumInterval: Map3DRain.minimumInterval(aim: aim))) { timeline in
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
        // CRASHSWEEP-3: each tag's foot placed by a Layout of the app's own,
        // which SwiftUI calls as plain (not main-actor) code, rather than
        // by alignment guides, whose closures are main-actor code that its
        // asynchronous renderer may call off the main thread (CRASH101).
        Map3DTrainLabelsLayout {
            ForEach(state.labels, id: \.train) { label in
                tag(label.info)
                    .layoutValue(key: Map3DTrainLabelFoot.self, value: CGPoint(x: CGFloat(label.x), y: CGFloat(label.y)))
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

/// Where a train's tag points, in the 3D map's points: the middle of the
/// tag's bottom edge (``Map3DTrainLabelsLayout``).
private struct Map3DTrainLabelFoot: LayoutValueKey {
    static let defaultValue = CGPoint.zero
}

/// ``Map3DTrainLabelsView``'s tags, each with the middle of its bottom
/// edge at its ``Map3DTrainLabelFoot``. As large as it is offered. (The
/// alignment guides it replaced placed the tags only against one another:
/// the stack shrank to them, so a lone tag sat in the screen's top-left
/// corner rather than over its train.)
private struct Map3DTrainLabelsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let foot = subview[Map3DTrainLabelFoot.self]
            subview.place(at: CGPoint(x: bounds.minX + foot.x, y: bounds.minY + foot.y), anchor: .bottom,
                          proposal: ProposedViewSize(bounds.size))
        }
    }
}

/// One of ``Map3DFollowBar``'s places to follow the train from.
private struct Map3DFollowChoice: View {
    let option: Map3DFollow.View
    @Binding var selection: Map3DFollow.View
    let language: DisplayLanguage
    /// Decision 578: why it cannot be chosen now, if it cannot.
    var unavailable: String?
    /// Decision 585 PR-4 (FERRYFOLLOW): a boat's names (駕駛台, 船艙窗).
    var ferry = false

    var body: some View {
        let blocked = unavailable != nil && selection != option
        Button {
            // Decision 578 (FOLLOWVIEW-2): a screenshot run once kept 後方
            // after its tap on 車窗; the UI test trace says whether the
            // action ran, if it happens again.
            UITestTrace.action("map3D.follow.\(option.rawValue) (was \(selection.rawValue))")
            selection = option
        } label: {
            Text(verbatim: ferry ? option.ferryText(in: language) : option.text(in: language))
                .font(.caption.weight(.bold))
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(minHeight: 26)
                .background(selection == option ? Theme.primary : Theme.chip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(selection == option ? Theme.onPrimary : Theme.textPrimary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .opacity(blocked ? 0.4 : 1)
        .accessibilityHint(Text(verbatim: unavailable ?? (ferry ? option.ferryHint(in: language) : option.hint(in: language))))
        .accessibilityAddTraits(selection == option ? .isSelected : [])
        .accessibilityIdentifier("map3D.follow.\(option.rawValue)")
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
        let selection = $view
        let language = session.language
        // Decision 578: the station view waits while the next stop is too far.
        let stationOffered = Map3DFollow.stationViewIsOffered(remainingMetres: session.world.map3DMetresToLookoutStop(of: train.id))
        let tooFar = Map3DFollow.stationTooFarText(in: language)
        // A sendable closure, not main-actor code (CRASHSWEEP): the bar's
        // two layouts stand in a ViewThatFits, which SwiftUI's asynchronous
        // renderer may measure, and build, off the main thread (CRASH101).
        return ForEach(Map3DFollow.View.allCases, id: \.self) { @Sendable option in
            Map3DFollowChoice(option: option, selection: selection, language: language,
                              unavailable: option == .station && !stationOffered ? tooFar : nil)
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

/// Decision 400 (FOLLOWBUS): the bar over the 3D map while the camera
/// follows a bus: the route's name, where the bus is going and the stop it
/// comes to next, the places to follow it from (not the station view: a
/// bus has no platform), the photo and the stop.
private struct Map3DBusFollowBar: View {
    let facts: BusFollowFacts
    let session: GameSession
    @Binding var view: Map3DFollow.View
    let takePhoto: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                title
                choices
                actions
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    title
                    Spacer(minLength: 0)
                    actions
                }
                HStack(spacing: 9) { choices }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 13)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .hudFrameMark("map3D.busFollowBar")
        .accessibilityHint(Text(verbatim: session.language.text("Pinch to move closer or farther.", "兩指縮放，拉近或拉遠。")))
    }

    private var title: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(facts.color.map { Palette.color($0) } ?? Palette.train)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: facts.routeName + " · " + facts.directionText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(verbatim: facts.stopText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var choices: some View {
        let selection = $view
        let language = session.language
        return ForEach(Map3DFollow.View.allCases.filter { $0 != .station }, id: \.self) { @Sendable option in
            Map3DFollowChoice(option: option, selection: selection, language: language)
        }
    }

    @ViewBuilder private var actions: some View {
        Button(action: takePhoto) {
            round("camera.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Take Photo", "拍照")))
        .accessibilityHint(Text(verbatim: session.language.text("Saves the 3D view as a picture to share.", "把現在的 3D 畫面存成照片，可以分享。")))
        .accessibilityIdentifier("map3D.follow.photo")
        Button {
            session.stopFollowingBus()
        } label: {
            round("xmark").foregroundStyle(Theme.onError).background(Theme.error, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Stop following", "取消跟隨")))
        .accessibilityIdentifier("map3D.follow.stop")
    }

    private func round(_ name: String) -> some View {
        Image(systemName: name)
            .font(.caption.weight(.heavy))
            .frame(width: 26, height: 26)
            .background(Theme.chip, in: Circle())
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Decision 583 (CABLEFOLLOW): the bar while the 3D map follows a cable
/// car cabin, as the bus's: the cable car, the way it goes, the next
/// station, and its three views (window, above, beside).
private struct Map3DCabinFollowBar: View {
    let facts: CabinFollowFacts
    let session: GameSession
    @Binding var view: Map3DFollow.View
    let takePhoto: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                title
                choices
                actions
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    title
                    Spacer(minLength: 0)
                    actions
                }
                HStack(spacing: 9) { choices }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 13)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .hudFrameMark("map3D.cabinFollowBar")
        .accessibilityHint(Text(verbatim: session.language.text("Pinch to move closer or farther.", "兩指縮放，拉近或拉遠。")))
    }

    private var title: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Palette.cableway)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: ([facts.name, facts.kind].compactMap { $0 } + [facts.directionText]).joined(separator: " · "))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(verbatim: facts.stopText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var choices: some View {
        let shown = $view
        let selection = Binding(get: { Map3DFollow.cabinView(shown.wrappedValue) }, set: { shown.wrappedValue = $0 })
        let language = session.language
        return ForEach(Map3DFollow.cabinViews, id: \.self) { @Sendable option in
            Map3DFollowChoice(option: option, selection: selection, language: language)
        }
    }

    @ViewBuilder private var actions: some View {
        Button(action: takePhoto) {
            round("camera.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Take Photo", "拍照")))
        .accessibilityHint(Text(verbatim: session.language.text("Saves the 3D view as a picture to share.", "把現在的 3D 畫面存成照片，可以分享。")))
        .accessibilityIdentifier("map3D.follow.photo")
        Button {
            session.stopFollowingTrain()
        } label: {
            round("xmark").foregroundStyle(Theme.onError).background(Theme.error, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Stop following", "取消跟隨")))
        .accessibilityIdentifier("map3D.follow.stop")
    }

    private func round(_ name: String) -> some View {
        Image(systemName: name)
            .font(.caption.weight(.heavy))
            .frame(width: 26, height: 26)
            .background(Theme.chip, in: Circle())
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Decision 585 PR-4 (FERRYFOLLOW): the bar while the 3D map follows a
/// ferry boat, as the cabin's: the route, the pier it sails to, when it
/// comes in or leaves, and its four views (bridge, window, above, beside).
private struct Map3DFerryFollowBar: View {
    let facts: FerryFollowFacts
    let session: GameSession
    @Binding var view: Map3DFollow.View
    let takePhoto: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                title
                choices
                actions
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    title
                    Spacer(minLength: 0)
                    actions
                }
                HStack(spacing: 9) { choices }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 13)
        .padding(.vertical, 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .hudFrameMark("map3D.ferryFollowBar")
        .accessibilityHint(Text(verbatim: session.language.text("Pinch to move closer or farther.", "兩指縮放，拉近或拉遠。")))
    }

    private var title: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Palette.ferry)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: [facts.name, facts.directionText].joined(separator: " · "))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(verbatim: facts.stopText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var choices: some View {
        let shown = $view
        let selection = Binding(get: { Map3DFollow.ferryView(shown.wrappedValue) }, set: { shown.wrappedValue = $0 })
        let language = session.language
        return ForEach(Map3DFollow.ferryViews, id: \.self) { @Sendable option in
            Map3DFollowChoice(option: option, selection: selection, language: language, ferry: true)
        }
    }

    @ViewBuilder private var actions: some View {
        Button(action: takePhoto) {
            round("camera.fill")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Take Photo", "拍照")))
        .accessibilityHint(Text(verbatim: session.language.text("Saves the 3D view as a picture to share.", "把現在的 3D 畫面存成照片，可以分享。")))
        .accessibilityIdentifier("map3D.follow.photo")
        Button {
            session.stopFollowingTrain()
        } label: {
            round("xmark").foregroundStyle(Theme.onError).background(Theme.error, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: session.language.text("Stop following", "取消跟隨")))
        .accessibilityIdentifier("map3D.follow.stop")
    }

    private func round(_ name: String) -> some View {
        Image(systemName: name)
            .font(.caption.weight(.heavy))
            .frame(width: 26, height: 26)
            .background(Theme.chip, in: Circle())
            .foregroundStyle(Theme.textPrimary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
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
/// does (decision 215): to the photos, LINE, or anywhere else. Decision
/// 434: the train showcase's photos too.
struct Map3DSnapshotSheet: View {
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

#if DEBUG
/// A UI test's train models made before it opens the 3D map
/// (`-ui-test-3d-models-first`, Debug builds only). Made where the 3D map
/// makes them (``Map3DTrainModels``), at launch: on the Simulator they take
/// some 30 s of CPU, and while they were made over an open 3D map the app
/// answered no UI query for 50 to 90 s, past XCTest's 100 s (main
/// 6ebf8c7's full lane, run 41354792858). Their marker,
/// `debug.map3DModelsReady`, is on the 2D map, where a query answers at
/// once. Made at the game's low priority (`.utility`): their shade is baked on every core
/// at once (`Map3DTrainOcclusion.baked`), and made at the 3D map's
/// priority before it the Simulator's main thread stood still for 61 s
/// and a query failed (FLANE5's run 41371388190).
@MainActor
@Observable
final class Map3DModelsWarmUp {
    static let shared = Map3DModelsWarmUp()
    private(set) var isReady = false
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Task {
            // Decision 546: the same making as the game's, at its priority.
            // At `.background` a busy Simulator did not finish them in 240 s
            // (main a48121b's full lane, run 41406244046, and its rerun
            // 41416405737); `.utility` is still below the 3D map's priority,
            // which stood the main thread still for 61 s (#1693).
            // Made, not yet on the GPU: the 3D map that opens puts them
            // there (decision 608), as it does for a player.
            await Map3DTrainModels.shared.makePack(priority: .utility)
            isReady = true
        }
    }
}

/// ``Map3DModelsWarmUp``'s marker for a UI test: an element of no size
/// that takes no touch.
struct Map3DModelsWarmUpMarker: View {
    var body: some View {
        if Map3DModelsWarmUp.shared.isReady {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: "3D models ready"))
                .accessibilityIdentifier("debug.map3DModelsReady")
        }
    }
}
#endif
