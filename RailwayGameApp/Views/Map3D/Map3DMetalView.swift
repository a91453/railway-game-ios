import GameCore
import GamePresentation
import ImageIO
import MetalKit
import os
import UIKit

/// ARCHITECTURE decision 229: the native 3D map drawn with Metal. It only
/// uploads and draws what GamePresentation works out (``Map3DScene``,
/// ``Map3DTrains``, ``Map3DCamera``, ``Map3DLighting``) and the surfaces'
/// textures (decision 231): one pipeline for the
/// still scene a buffer per chunk, the chunks out of view skipped, the
/// trains one buffer made each frame. It also measures itself (frames a
/// second, the CPU's and the GPU's time a frame), since the step before the
/// 3D map replaces the 2D one is measuring it on devices (NEXT_PRIORITIES
/// §0 item 14).
///
/// A subclass of `MTKView` drawing in ``draw(_:)``, as MetalKit allows in
/// place of a delegate: everything stays on the main actor with the view.
final class Map3DMetalView: MTKView {
    /// What a frame costs, over the last half second.
    struct Stats: Equatable {
        var framesPerSecond: Double
        /// The CPU's time to prepare a frame and the GPU's to draw it, the
        /// middle value, in milliseconds.
        var cpuMilliseconds: Double
        /// The CPU's wait for the drawable (and for a street life buffer
        /// the GPU still reads), not counted in ``cpuMilliseconds``: the
        /// screen's pace, not the frame's work (2026-10-21).
        var waitMilliseconds: Double
        var gpuMilliseconds: Double
        /// Decision 485: the main thread's busy time a frame (everything
        /// it ran between waits, the frame's own work and SwiftUI's and the
        /// game loop's), and the longest busy stretch: a tick's work on the
        /// main thread shows here, not in ``cpuMilliseconds``.
        var mainMilliseconds: Double
        var mainLongestMilliseconds: Double
        var drawCalls: Int
        var triangles: Int
        /// Decision 259: the figures and vehicles drawn, and how much
        /// street life the device draws now.
        var people: Int
        var vehicles: Int
        var streetDetail: Map3DStreetDetail
        /// Decision 417: the rung the map has climbed to or stepped down
        /// to under load, its triangles for what moves among it (`nil`
        /// without a tier).
        var level: Map3DLoadLevel?
        /// The pixels a point drawn (``Map3DDrawScale``).
        var drawScale: Double
        /// Decision 394: whether the cab is deep in a tunnel, drawing only
        /// what is under the ground (``Map3DUnderground``).
        var underground: Bool
        /// PERF (2026-10-30): the frames a second aimed for
        /// (`preferredFramesPerSecond`), which the rain over the map
        /// keeps to.
        var aim: Int
        /// Decision 645 (D6): the light the last frame drew: its hour,
        /// how far night it was and how far the city's lights were on, so
        /// a device shows whether the 3D map's light followed the clock.
        var drawnHour: Float = 12
        var drawnNight: Float = 0
        var drawnLights: Float = 0
    }

    var camera = Map3DCamera()
    /// Decision 333: the train the camera follows, from behind
    /// (``Map3DFollow``); set with ``follow(_:reduceMotion:)``.
    private(set) var following: Map3DFollow?
    /// Decision 714 (MAP3D-FAR): the map from above (scene x and z), which
    /// a drag cannot take the camera's target off; `nil` before a scene
    /// is shown.
    var ground: (x: ClosedRange<Float>, z: ClosedRange<Float>)?
    /// Decision 333: the camera flying to the follow view (`to` is `nil`)
    /// or to a still view (`to`), a frame at a time.
    private var flying: (flight: Map3DFlight, to: Map3DCamera?)?
    /// When the follow camera last moved, for how far it turns.
    private var lastFollowStep: CFTimeInterval?
    /// Where the cabin followed is seen through (decision 342's supplement); set with the camera each frame.
    private var followedSeeThrough: Map3DPoint?
    /// Decision 334: a flight asked for, its goal worked out at the next
    /// frame from the camera as laid out (``fly(reduceMotion:to:)``).
    private var flightAsked: (reduceMotion: Bool, goal: (Map3DCamera) -> Map3DCamera?)?
    /// Decision 334: the train ringed, asked about on a station's board.
    var ringed: TrainID?
    /// Decision 403 (續二): who waits for the next frame drawn, as a
    /// picture (``capture(_:)``).
    private var captures: [@MainActor @Sendable (UIImage?) -> Void] = []
    /// Decision 394: whether the cab is deep in a tunnel this frame, and
    /// where the scene's tunnels open (``Map3DTrackCover/openings``).
    private var underground = Map3DUnderground()
    private var openings: [Map3DPoint] = []
    /// Decision 334: called as a flight to a still view lands, for the
    /// compass.
    var landed: (@MainActor () -> Void)?
    var lighting = Map3DLighting(minute: 12 * 60)
    /// Decision 277: the day's weather. The first is shown at once; a
    /// later one turns the light over ``Map3DWeather/changeSeconds``.
    var weather: Map3DWeather? {
        didSet {
            guard let weather, weather != oldValue else { return }
            let now = CACurrentMediaTime()
            let from = oldValue == nil ? weather : weatherChange?.weather(at: now) ?? weather
            weatherChange = Map3DWeather.Change(from: from, to: weather, began: now)
        }
    }
    private var weatherChange: Map3DWeather.Change?
    /// Decision 320: the day's rain, its streaks drawn last over the frame
    /// (PERF_3D_RAIN, 2026-10-30: by the GPU, no longer by a SwiftUI
    /// `Canvas` on the main thread).
    var rain = Map3DRain.none
    /// PERF_3D_RAIN: the streaks' pipeline and depth test (none where the
    /// shader does not load: then only decision 277's light shows the
    /// rain), their seeds, and the buffer holding them, made again only
    /// when the rain or the street detail changes.
    private var rainPipeline: (pipeline: MTLRenderPipelineState, depth: MTLDepthStencilState)?
    private var rainSeeds = Map3DRainDrawing()
    private var rainBuffer: MTLBuffer?
    /// This frame's light: the hour's, under the weather as far as it has
    /// turned.
    private var shown = Map3DLighting(minute: 12 * 60)
    /// The trains for this frame, seen from the eye given; decision 417:
    /// their far models and boxes from the reach given.
    var trains: (@MainActor (Map3DPoint, Map3DModelReach) -> Map3DTrains.Frame)?
    /// Decision 314: this frame's trains' fronts, as the camera sees them,
    /// for their labels.
    var trainHeads: (@MainActor ([Map3DTrains.Head], Map3DCamera) -> Void)?
    /// Decision 400 (FOLLOWBUS): where the bus followed is this frame, as
    /// the follow camera reads a vehicle (``Map3DFollow/Pose``); `nil` when
    /// it is not out.
    var busPose: (@MainActor (BusID) -> Map3DFollow.Pose?)?
    /// Decision 583 (CABLEFOLLOW): the same for the cable car cabin followed.
    var cabinPose: (@MainActor (CabinID) -> Map3DFollow.Pose?)?
    /// Decision 585 PR-4 (FERRYFOLLOW): the same for the ferry boat
    /// followed. Not seen through: it sails on open water.
    var ferryPose: (@MainActor (FerryBoatID) -> Map3DFollow.Pose?)?
    /// Decision 702 (FOLLOW-AIR): the same for the aircraft followed;
    /// `nil` once it can no longer be followed, and the camera stays.
    var aircraftPose: (@MainActor (Map3DAircraft.FlightID) -> Map3DFollow.Pose?)?
    /// Decision 606 (IDLEREAL): where a real timetable's train is.
    var realTrainPose: (@MainActor (RealTrainID) -> Map3DFollow.Pose?)?
    /// Decision 259: the people and vehicles for this frame, seen with the
    /// camera given, with the city's lights on so far; decision 417: within
    /// the budget given (the trains' triangles this frame among it).
    var streetLife: (@MainActor (Map3DCamera, Float, Map3DMotionBudget) -> Map3DStreetLife.Frame)?
    /// Decision 259: three buffers of their instances, a frame's each in
    /// turn, so none is made each frame; a frame waits for the GPU to be
    /// done with the one it fills. Decision 608, second continuation: and
    /// so the trains' boxes and shadows, the cars' instances and the glass
    /// (``Map3DFrameBuffers``), with the same wait.
    private var frameBuffers = Map3DFrameBuffers<MTLBuffer>()
    private let frameInFlight = DispatchSemaphore(value: Map3DFrameBuffers<MTLBuffer>.sets)
    /// Decision 417: how much that moves this device draws at most, by its
    /// GPU, and as the 3D look in Settings has it (decision 259's street
    /// detail with it).
    private var deviceTier: Map3DDeviceTier?
    /// Decision 417: the rung climbed to while the device keeps up and
    /// stepped down to while it cannot (fewer on the streets, the trains'
    /// far models nearer, fewer pixels), capped at the tier of the 3D look
    /// in Settings; and whether the map draws fewer pixels: for that, or
    /// as the 3D look, Low Power Mode or the phone's heat say
    /// (``Map3DQuality``).
    private var load = Map3DLoadGovernor()
    /// Decision 460: what is left to the app, looked at every half second.
    private var memoryWatch = Map3DMemoryWatch()
    private var level: Map3DLoadLevel? { quality.tier(device: deviceTier) == nil ? nil : load.level }
    private var drawsFewerPixels = false
    /// Decision 610: whether the real buildings' street fronts are drawn
    /// (``Map3DRealFacade/draws(quality:lowPower:heat:tier:)``).
    private var drawsFacades = false
    /// Decision 617: whether the glows round the lights are drawn
    /// (``Map3DGlow/draws(quality:lowPower:heat:tier:overBudget:)``).
    private var drawsGlows = false
    /// Decision 259: how much street life the device draws now; PERF_3D_RAIN:
    /// and how many rain streaks fall (``Map3DRain/streakCount(_:)``).
    private var streetDetail: Map3DStreetDetail {
        level.map { $0.streets >= .fewestOnStreets ? $0.tier.streetDetail.lowered : $0.tier.streetDetail } ?? .off
    }
    /// Decision 238's later note: the 3D look chosen in Settings.
    var quality = Map3DQuality.automatic {
        didSet {
            guard quality != oldValue else { return }
            startClimbing()
            applyQuality()
        }
    }
    /// Decision 352: with Reduce Motion the screens hold one picture;
    /// decision 356: and the water's ripples stand still.
    var reduceMotion = false
    /// Decision 230: the train models, and a buffer of each one's vertices;
    /// decision 608: the pack without its vertices, which are only in the
    /// buffers (``Map3DUploadedModels``, shared by every 3D view).
    /// Decision 653: and each model's own texture (``Map3DUploadedModels/textures``).
    private var models: (pack: Map3DModelPack, buffers: [MTLBuffer], textures: [MTLTexture?])?
    /// Decision 653: one white texel, `map3dFragment`'s model texture for
    /// every draw but a model with its own.
    private var noModelTexture: MTLTexture?
    /// Decision 617: every model's glow spots (``Map3DGlow/Table``) and
    /// the buffer holding them, made once with the models.
    private var glowSpots: (table: Map3DGlow.Table, buffer: MTLBuffer)?
    private var transparentGlass = Map3DTransparentGlass.Cache(models: [])
    private var glassDrawing: Map3DGlassPipeline?
    /// Decision 672: seeing underground, see-through, neither tested
    /// against the depth nor writing it.
    private var xrayDrawing: (pipeline: MTLRenderPipelineState, depth: MTLDepthStencilState)?
    /// Decision 672: the tunnels and underground platforms seen through
    /// the ground, made into buffers when given; `nil` (the switch off,
    /// the default): nothing of it is kept or drawn.
    var xray: Map3DXRay? {
        didSet {
            guard let mesh = xray?.mesh, !mesh.isEmpty, let vertices = makeBuffer(mesh.vertices), let indices = makeBuffer(mesh.indices) else {
                xrayBuffers = nil
                return
            }
            xrayBuffers = (vertices, indices, mesh.indices.count)
        }
    }
    private var xrayBuffers: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
    /// Decision 429: the signals' three models in `models`, and the game
    /// clock their lights follow (`nil`: as they stand, the main road
    /// green).
    private var signalModels: Map3DSignalTiming.Models?
    var signalClock: Map3DSignalTiming.Clock?
    /// Decision 445: the pedestrian signals' faces and countdowns in
    /// `models`, drawn close up as `signalClock` shows.
    private var walkModels: Map3DPedestrianSignal.Models?
    /// Review K2-6: how far their little green men have walked, carried
    /// from frame to frame.
    private var walkPace = Map3DPedestrianSignal.Pace()
    var onStats: (@MainActor (Stats) -> Void)?
    /// Decision 358: the camera each frame, once it has moved, and when.
    var onCamera: (@MainActor (Map3DCamera, CFTimeInterval) -> Void)?
    /// Decision 711: memory runs short (the system's warning, or little
    /// left to the app): the chunks out of the camera's reach are let go.
    var onMemoryShort: (@MainActor () -> Void)?
    /// Decision 711: the bytes of the chunks' buffers held.
    var heldBytes: Int { chunks.reduce(0) { $0 + $1.bytes } }
    /// Decision 578: whether the chunks round the platform the station view
    /// stands on are built; until they are, the camera stays above and
    /// behind the train, and flies to the platform once they are.
    var lookoutBuilt: (@MainActor (Map3DPoint) -> Bool)?
    /// Decision 606 (續): whether the ground round a followed real train
    /// is built, with the city in full.
    var trainGroundBuilt: (@MainActor (Map3DPoint) -> Bool)?
    private var lookoutWasBuilt = true

    /// Decision 709: the level the chunks drawn from afar were last drawn
    /// at (``Map3DFarDetail/level(distance:was:)``).
    private var farLevel = 0

    private struct Chunk {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
        /// Decision 238: how many of the indices are its ground, track and
        /// roads, and its city simplified for afar, if it has a city.
        let baseIndexCount: Int
        let far: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        /// Decision 455: the simplified city's boxes, an instance each of
        /// the one box (``Map3DBoxInstance``), and the triangles they make.
        let farBoxes: (instances: MTLBuffer, count: Int, triangles: Int)?
        /// Decision 709: what it draws from afar at each level, the first
        /// so many of its base indices, far indices, boxes and shadows.
        let farLevels: [Map3DFarDetail.Counts]
        /// Whether it was drawn in full last frame (decision 238's margin).
        var detailed = false
        /// Decision 267: its closest detail, and whether it was drawn last
        /// frame.
        let close: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        var closeUp = false
        /// Decision 445: whether it is near enough for the pedestrian
        /// signals, as close up but whether or not it has a closest detail.
        var walksClose = false
        /// The boxes standing in for some of `close`'s models: drawn in
        /// full, but not close up.
        let standIn: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        /// Decision 232: its shadows, if it has any.
        let shadows: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        /// Decision 244: its street furniture's instances, sorted by model,
        /// and where each model's run of them starts.
        /// Decision 429: a run a model and signal group for the frame, one
        /// a model for the sun's shadow map (``Map3DPropRuns``).
        let props: (instances: MTLBuffer, runs: [Map3DPropRuns.Run], shapes: [Map3DPropRuns.Run])?
        /// Decision 352: its signs' instances.
        let signs: (instances: MTLBuffer, count: Int)?
        let minimum: Map3DPoint
        let maximum: Map3DPoint
        /// Decision 342: where it is and its city's tops, for the cones
        /// of ``Map3DSeeThrough``.
        let column: Int
        let row: Int
        let cityTops: [Float]
        /// Decision 368: built without its city in full, so drawn
        /// simplified until built again.
        let coarse: Bool
        /// Decision 610: the real buildings' street fronts, made into
        /// buffers only once the chunk is drawn close up with them on
        /// (``drawsFacades``), and let go when they go off; whether they
        /// were drawn last frame.
        let facadeMesh: Map3DMesh
        var facade: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        var frontsUp = false
        /// Decision 711: how much of it this frame draws within the still
        /// scene's budget (``Map3DSceneBudget``).
        var share = Map3DSceneBudget.Share.whole
        /// Decision 711: its buffers' bytes (the street fronts' apart).
        var bytes = 0

        /// Decision 711: its triangles as the camera asks, simplified and
        /// as its ground alone.
        func cost(pack: Map3DModelPack?) -> Map3DSceneBudget.Cost {
            let ground = baseIndexCount / 3, shadow = (shadows?.indexCount ?? 0) / 3
            let simplified = ground + (far?.indexCount ?? 0) / 3 + (farBoxes?.triangles ?? 0) + shadow
            guard detailed else { return Map3DSceneBudget.Cost(whole: simplified, simplified: simplified, ground: ground) }
            var whole = indexCount / 3 + (standIn?.indexCount ?? 0) / 3 + shadow + 2 * (signs?.count ?? 0)
            if let pack, let props {
                for run in props.runs where run.model < pack.models.count { whole += pack.models[run.model].triangleCount * run.count }
            }
            return Map3DSceneBudget.Cost(whole: whole, simplified: simplified, ground: ground)
        }
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// Decision 230: the same, each vertex through its car's instance.
    private let instancedPipeline: MTLRenderPipelineState
    /// Decision 342: the city in front of the trains, seen through
    /// (``Map3DSeeThrough``).
    private let seeThroughPipeline: MTLRenderPipelineState
    /// Decision 455: the simplified city's boxes, each vertex made of its
    /// box's instance and its number in the one box's
    /// (``Map3DBoxInstance/indices``), solid and seen through.
    private let boxPipeline: MTLRenderPipelineState
    private let boxSeeThroughPipeline: MTLRenderPipelineState
    private let boxIndices: MTLBuffer
    /// Decision 232: the ground shadows, blended over what is drawn,
    /// tested against the depth but not writing it.
    private let shadowPipeline: MTLRenderPipelineState
    private let shadowDepthState: MTLDepthStencilState
    private let depthState: MTLDepthStencilState
    /// Decision 347: the sky behind everything.
    private let skyPipeline: MTLRenderPipelineState
    private let skyDepthState: MTLDepthStencilState
    /// Decision 231: the surfaces' textures, one layer each.
    private let surfaces: MTLTexture
    /// Decision 352: the signs' pipeline and their atlas; none where the
    /// shader or the picture does not load (the map is drawn without).
    private var signDrawing: (pipeline: MTLRenderPipelineState, atlas: MTLTexture)?
    /// Decision 617: the glows' pipelines (round the models' lights, round
    /// the signs), added to the picture, tested against the depth and
    /// writing none; none where they do not load (no glows are drawn).
    private var glowDrawing: (spots: MTLRenderPipelineState, signs: MTLRenderPipelineState?, depth: MTLDepthStencilState)?
    /// Decision 357: the sun's shadow map's pipelines (the chunks, the
    /// street furniture) and depth test; none where they do not load (the
    /// map is drawn with decision 232's shadows alone).
    private var sunDrawing: (chunks: MTLRenderPipelineState, instanced: MTLRenderPipelineState, boxes: MTLRenderPipelineState,
                             depth: MTLDepthStencilState)?
    /// Decision 357: the map, the region it was drawn for and when, and
    /// whether the scene changed since. A texel of nothing in its place
    /// while there is none, so the shaders always have one.
    private var sunMap: MTLTexture?
    private var sunDrawn: Map3DSunShadow.Region?
    private var sunDrawnAt: CFTimeInterval = 0
    private var sunSceneChanged = true
    private var noSunMap: MTLTexture?
    /// Decision 357: how the sun's shadows are drawn now (``Map3DSunShadow/plan(_:lowPower:heat:overBudget:)``).
    private var sunPlan: Map3DSunShadow.Plan?
    /// Decision 450: whether the trains' glass and stainless mirror, 0 or 1
    /// (``Map3DReflection/trainStrength(_:lowPower:heat:)``).
    private var trainMaterials: Float = 0
    private var chunks: [Chunk] = []
    private let gpuTimes = OSAllocatedUnfairLock(initialState: [Double]())
    private var cpuTimes: [Double] = []
    private var waitTimes: [Double] = []
    private var frames = 0
    private var lastStats = CACurrentMediaTime()
    private var lastCounts = (drawCalls: 0, triangles: 0)
    private var lastLife = (people: 0, vehicles: 0)
    /// Decision 485: the main run loop's busy stretches, from waking to
    /// waiting again, over the last half second.
    private var mainBusy = (total: 0.0, longest: 0.0)
    private var mainAwake: CFTimeInterval?
    private var mainObservers: [CFRunLoopObserver] = []

    /// The view, or `nil` where the device has no Metal or the shaders do
    /// not load.
    /// Decision 365: `samples` a pixel against jagged edges
    /// (``Map3DQuality/samplesPerPixel``), fixed while the view lives.
    static func make(samples: Int = 4) -> Map3DMetalView? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "map3dVertex"),
              let fragmentFunction = library.makeFunction(name: "map3dFragment"),
              let instancedFunction = library.makeFunction(name: "map3dInstancedVertex"),
              let shadowVertex = library.makeFunction(name: "map3dShadowVertex"),
              let shadowFragment = library.makeFunction(name: "map3dShadowFragment"),
              let seeThroughFragment = library.makeFunction(name: "map3dSeeThroughFragment"),
              let boxVertex = library.makeFunction(name: "map3dBoxVertex"),
              let skyVertex = library.makeFunction(name: "map3dSkyVertex"),
              let skyFragment = library.makeFunction(name: "map3dSkyFragment")
        else { return nil }
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = 12
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[2].format = .uchar4Normalized
        vertexDescriptor.attributes[2].offset = 24
        vertexDescriptor.attributes[2].bufferIndex = 0
        vertexDescriptor.attributes[3].format = .float3
        vertexDescriptor.attributes[3].offset = 28
        vertexDescriptor.attributes[3].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Map3DVertex>.stride
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = samples
        let depthDescriptor = MTLDepthStencilDescriptor()
        // Decision 342: the depth runs from 1 near to 0 far
        // (``Map3DCamera/projection``), so the nearer is the greater.
        depthDescriptor.depthCompareFunction = .greater
        depthDescriptor.isDepthWriteEnabled = true
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        descriptor.vertexFunction = instancedFunction
        guard let instancedPipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let depthState = device.makeDepthStencilState(descriptor: depthDescriptor),
              let surfaces = makeSurfaces(device: device, queue: queue)
        else { return nil }
        // Decision 342: the city in front of a train, its alpha turned
        // into the share of a pixel's samples it covers.
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = seeThroughFragment
        descriptor.isAlphaToCoverageEnabled = true
        guard let seeThroughPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        // Decision 455: the same two for the simplified city's boxes,
        // which read no vertices but their instances.
        descriptor.vertexFunction = boxVertex
        descriptor.vertexDescriptor = nil
        guard let boxSeeThroughPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        descriptor.isAlphaToCoverageEnabled = false
        descriptor.fragmentFunction = fragmentFunction
        guard let boxPipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let boxIndices = Map3DBoxInstance.indices.withUnsafeBytes({ bytes in
                  bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
              })
        else { return nil }
        // Decision 347: the sky, one triangle at the far plane, where the
        // depth is still the cleared 0 (nothing drawn there).
        descriptor.vertexFunction = skyVertex
        descriptor.fragmentFunction = skyFragment
        descriptor.vertexDescriptor = nil
        let skyDepthDescriptor = MTLDepthStencilDescriptor()
        skyDepthDescriptor.depthCompareFunction = .greaterEqual
        skyDepthDescriptor.isDepthWriteEnabled = false
        guard let skyPipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let skyDepthState = device.makeDepthStencilState(descriptor: skyDepthDescriptor)
        else { return nil }
        descriptor.vertexDescriptor = vertexDescriptor
        // Decision 232: what is drawn times one less the shadow's alpha,
        // plus its tint times the alpha.
        descriptor.vertexFunction = shadowVertex
        descriptor.fragmentFunction = shadowFragment
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .zero
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        let shadowDepthDescriptor = MTLDepthStencilDescriptor()
        shadowDepthDescriptor.depthCompareFunction = .greaterEqual
        shadowDepthDescriptor.isDepthWriteEnabled = false
        guard let shadowPipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let shadowDepthState = device.makeDepthStencilState(descriptor: shadowDepthDescriptor)
        else { return nil }
        let view = Map3DMetalView(device: device, queue: queue, pipeline: pipeline, instancedPipeline: instancedPipeline,
                                  seeThroughPipeline: seeThroughPipeline, boxPipeline: boxPipeline, boxSeeThroughPipeline: boxSeeThroughPipeline,
                                  boxIndices: boxIndices, shadowPipeline: shadowPipeline, shadowDepthState: shadowDepthState,
                                  depthState: depthState, skyPipeline: skyPipeline, skyDepthState: skyDepthState, surfaces: surfaces,
                                  samples: samples)
        guard let glassDrawing = Map3DGlassPipeline.make(device: device, library: library, vertexDescriptor: vertexDescriptor, samples: samples) else { return nil }
        view.glassDrawing = glassDrawing
        // Decision 352: the signs, four corners an instance, solid, tested
        // and written into the depth as the city is.
        if let signVertex = library.makeFunction(name: "map3dSignVertex"), let signFragment = library.makeFunction(name: "map3dSignFragment"),
           let atlas = makeSignAtlas(device: device, queue: queue) {
            let signs = MTLRenderPipelineDescriptor()
            signs.vertexFunction = signVertex
            signs.fragmentFunction = signFragment
            signs.colorAttachments[0].pixelFormat = .bgra8Unorm
            signs.depthAttachmentPixelFormat = .depth32Float
            signs.rasterSampleCount = samples
            if let signPipeline = try? device.makeRenderPipelineState(descriptor: signs) { view.signDrawing = (signPipeline, atlas) }
        }
        // Decision 617: the glows, added.
        if let glowVertex = library.makeFunction(name: "map3dGlowVertex"), let glowFragment = library.makeFunction(name: "map3dGlowFragment") {
            let glows = MTLRenderPipelineDescriptor()
            glows.vertexFunction = glowVertex
            glows.fragmentFunction = glowFragment
            glows.colorAttachments[0].pixelFormat = .bgra8Unorm
            glows.colorAttachments[0].isBlendingEnabled = true
            glows.colorAttachments[0].rgbBlendOperation = .add
            glows.colorAttachments[0].alphaBlendOperation = .add
            glows.colorAttachments[0].sourceRGBBlendFactor = .one
            glows.colorAttachments[0].destinationRGBBlendFactor = .one
            glows.colorAttachments[0].sourceAlphaBlendFactor = .zero
            glows.colorAttachments[0].destinationAlphaBlendFactor = .one
            glows.depthAttachmentPixelFormat = .depth32Float
            glows.rasterSampleCount = samples
            let depth = MTLDepthStencilDescriptor()
            depth.depthCompareFunction = .greater
            depth.isDepthWriteEnabled = false
            if let spots = try? device.makeRenderPipelineState(descriptor: glows), let state = device.makeDepthStencilState(descriptor: depth) {
                var signs: MTLRenderPipelineState?
                if let signVertex = library.makeFunction(name: "map3dSignGlowVertex"),
                   let signFragment = library.makeFunction(name: "map3dSignGlowFragment") {
                    glows.vertexFunction = signVertex
                    glows.fragmentFunction = signFragment
                    signs = try? device.makeRenderPipelineState(descriptor: glows)
                }
                view.glowDrawing = (spots, signs, state)
            }
        }
        // Decision 672: seeing underground, blended as the shadows are.
        if let xrayVertex = library.makeFunction(name: "map3dXRayVertex"), let xrayFragment = library.makeFunction(name: "map3dXRayFragment") {
            descriptor.vertexFunction = xrayVertex
            descriptor.fragmentFunction = xrayFragment
            descriptor.vertexDescriptor = vertexDescriptor
            let depth = MTLDepthStencilDescriptor()
            depth.depthCompareFunction = .always
            depth.isDepthWriteEnabled = false
            if let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor), let state = device.makeDepthStencilState(descriptor: depth) {
                view.xrayDrawing = (pipeline, state)
            }
        }
        // Decision 357: the city's depth from the sun, no colour.
        if let sunVertex = library.makeFunction(name: "map3dSunDepthVertex"),
           let sunInstanced = library.makeFunction(name: "map3dSunDepthInstancedVertex"),
           let sunBoxes = library.makeFunction(name: "map3dSunDepthBoxVertex") {
            let sun = MTLRenderPipelineDescriptor()
            sun.vertexFunction = sunVertex
            sun.vertexDescriptor = vertexDescriptor
            sun.depthAttachmentPixelFormat = .depth16Unorm
            let sunDepth = MTLDepthStencilDescriptor()
            sunDepth.depthCompareFunction = .less
            sunDepth.isDepthWriteEnabled = true
            if let chunks = try? device.makeRenderPipelineState(descriptor: sun),
               let depth = device.makeDepthStencilState(descriptor: sunDepth) {
                sun.vertexFunction = sunInstanced
                let instanced = try? device.makeRenderPipelineState(descriptor: sun)
                sun.vertexFunction = sunBoxes
                sun.vertexDescriptor = nil
                if let instanced, let boxes = try? device.makeRenderPipelineState(descriptor: sun) { view.sunDrawing = (chunks, instanced, boxes, depth) }
            }
        }
        // PERF_3D_RAIN (2026-10-30): decision 320's rain streaks and the
        // storm's lightning, blended over everything as the ground shadows
        // are, neither tested against the depth nor writing it.
        if let rainVertex = library.makeFunction(name: "map3dRainVertex"), let rainFragment = library.makeFunction(name: "map3dRainFragment") {
            descriptor.vertexFunction = rainVertex
            descriptor.fragmentFunction = rainFragment
            descriptor.vertexDescriptor = nil
            let rainDepth = MTLDepthStencilDescriptor()
            rainDepth.depthCompareFunction = .always
            rainDepth.isDepthWriteEnabled = false
            if let rainPipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
               let depth = device.makeDepthStencilState(descriptor: rainDepth) {
                view.rainPipeline = (rainPipeline, depth)
            }
        }
        return view
    }

    private init(
        device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState, instancedPipeline: MTLRenderPipelineState,
        seeThroughPipeline: MTLRenderPipelineState, boxPipeline: MTLRenderPipelineState, boxSeeThroughPipeline: MTLRenderPipelineState, boxIndices: MTLBuffer,
        shadowPipeline: MTLRenderPipelineState, shadowDepthState: MTLDepthStencilState, depthState: MTLDepthStencilState,
        skyPipeline: MTLRenderPipelineState, skyDepthState: MTLDepthStencilState, surfaces: MTLTexture, samples: Int
    ) {
        self.queue = queue
        self.pipeline = pipeline
        self.instancedPipeline = instancedPipeline
        self.seeThroughPipeline = seeThroughPipeline
        self.boxPipeline = boxPipeline
        self.boxSeeThroughPipeline = boxSeeThroughPipeline
        self.boxIndices = boxIndices
        self.shadowPipeline = shadowPipeline
        self.shadowDepthState = shadowDepthState
        self.depthState = depthState
        self.skyPipeline = skyPipeline
        self.skyDepthState = skyDepthState
        self.surfaces = surfaces
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        sampleCount = samples
        // Decision 342: reversed depth, 0 the farthest.
        clearDepth = 0
        preferredFramesPerSecond = 60
        deviceTier = Self.tier(of: device)
        // Decision 417: memory running short steps down on any look.
        NotificationCenter.default.addObserver(self, selector: #selector(memoryRunsShort), name: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil)
        noSunMap = makeSunMap(device: device, side: 1)
        noModelTexture = makeWhiteTexel(device: device)
        startClimbing()
        applyQuality()
    }

    /// Decision 417: the device keeps the rung it climbed to, for the 3D
    /// look and the system it climbed on (not in the save).
    nonisolated static let rungKey = "map3DLoadRung"

    /// Decision 417: starts on the rung the 3D look and this device start
    /// on (``Map3DLoadGovernor/start(for:device:remembered:memory:)``,
    /// decision 460: lower with little memory).
    private func startClimbing() {
        let system = UIDevice.current.systemVersion
        let remembered = Map3DLoadGovernor.remembered(UserDefaults.standard.string(forKey: Self.rungKey), quality: quality, system: system)
        let top = quality.tier(device: deviceTier).map(Map3DLoadLevel.top(of:)) ?? 0
        load = Map3DLoadGovernor(top: top, start: Map3DLoadGovernor.start(for: quality, device: deviceTier, remembered: remembered,
                                                                          memory: FrameTimeRecorder.memoryTier))
        rememberRung()
    }

    private func rememberRung() {
        UserDefaults.standard.set(Map3DLoadGovernor.remembering(load.rung, quality: quality, system: UIDevice.current.systemVersion),
                                  forKey: Self.rungKey)
    }

    /// Decision 653: see ``noModelTexture``.
    private func makeWhiteTexel(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let white: [UInt8] = [255, 255, 255, 255]
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: white, bytesPerRow: 4)
        return texture
    }

    /// Decision 357: a depth texture `side` texels square for the sun's
    /// shadow map, cleared to the farthest (nothing in the sun's way).
    private func makeSunMap(device: MTLDevice, side: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth16Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = texture
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1
        if let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass) {
            encoder.endEncoding()
            commands.commit()
        }
        return texture
    }

    /// Decision 357: the region the sun's shadow map holds this frame, and
    /// the region to draw it for first when it is out of date (the sun
    /// turned, the target moved on, the camera pulled out a step, the
    /// scene changed), not sooner than the plan's interval after the last
    /// drawing unless the square itself changed. None at night, on
    /// Saving, or out past ``Map3DSunShadow/farthestCamera``.
    private func wantedSunRegion(at now: CFTimeInterval) -> (drawn: Map3DSunShadow.Region?, redraw: Map3DSunShadow.Region?) {
        guard sunDrawing != nil, let plan = sunPlan, Map3DSunShadow.strength(shown) > 0, let device,
              let wanted = Map3DSunShadow.region(camera: camera, sun: shown.sunDirection, size: plan.size)
        else { return (nil, nil) }
        if let drawn = sunDrawn {
            if !sunSceneChanged, !drawn.isStale(for: wanted) { return (drawn, nil) }
            if drawn.size == wanted.size, drawn.extent == wanted.extent, now - sunDrawnAt < plan.interval { return (drawn, nil) }
        }
        if sunMap?.width != plan.size {
            sunMap = makeSunMap(device: device, side: plan.size)
            sunDrawn = nil
        }
        guard sunMap != nil else { return (nil, nil) }
        sunDrawn = wanted
        sunDrawnAt = now
        sunSceneChanged = false
        return (wanted, wanted)
    }

    /// Decision 357: draws the city's depth from the sun into its map for
    /// `region`: the chunks the sun sees there, in full where the camera
    /// draws them in full (and their street furniture), simplified afar.
    private func drawSunMap(_ region: Map3DSunShadow.Region, commands: MTLCommandBuffer, drawCalls: inout Int, triangles: inout Int) {
        guard let sunDrawing, let sunMap else { return }
        let pass = MTLRenderPassDescriptor()
        pass.depthAttachment.texture = sunMap
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            sunDrawn = nil
            return
        }
        encoder.setRenderPipelineState(sunDrawing.chunks)
        encoder.setDepthStencilState(sunDrawing.depth)
        encoder.setCullMode(.none)
        encoder.setDepthBias(0, slopeScale: Map3DSunShadow.slopeScale, clamp: Map3DSunShadow.slopeClampDepth)
        let matrix = region.matrix
        matrix.columns.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            encoder.setVertexBytes(base, length: bytes.count, index: 1)
        }
        let seen = chunks.filter { $0.share != .nothing && Map3DCamera.sees(minimum: $0.minimum, maximum: $0.maximum, through: matrix) }
        // Decision 709: from afar, what is too small to see casts nothing.
        let level = farLevel
        for chunk in seen {
            let afar = chunk.farLevels[level]
            let count = chunk.detailed ? chunk.indexCount : afar.base
            if count > 0 {
                encoder.setVertexBuffer(chunk.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32, indexBuffer: chunk.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += count / 3
            }
            if chunk.detailed, let standIn = chunk.standIn {
                encoder.setVertexBuffer(standIn.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: standIn.indexCount, indexType: .uint32, indexBuffer: standIn.indices,
                                              indexBufferOffset: 0)
                drawCalls += 1
                triangles += standIn.indexCount / 3
            }
            if !chunk.detailed, chunk.share < .ground, let far = chunk.far, afar.far > 0 {
                encoder.setVertexBuffer(far.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: afar.far, indexType: .uint32, indexBuffer: far.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += afar.far / 3
            }
        }
        // Decision 455: the simplified city's boxes, a draw a chunk.
        encoder.setRenderPipelineState(sunDrawing.boxes)
        for chunk in seen where !chunk.detailed && chunk.share < .ground {
            let afar = chunk.farLevels[level]
            guard let boxes = chunk.farBoxes, afar.boxes > 0 else { continue }
            encoder.setVertexBuffer(boxes.instances, offset: 0, index: 2)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: Map3DBoxInstance.indices.count, indexType: .uint16, indexBuffer: boxIndices,
                                          indexBufferOffset: 0, instanceCount: afar.boxes)
            drawCalls += 1
            triangles += afar.boxTriangles
        }
        if let models {
            encoder.setRenderPipelineState(sunDrawing.instanced)
            let leftOut = Map3DProp.modelsLeftOut(quality, in: models.pack)
            for chunk in seen where chunk.detailed {
                guard let props = chunk.props else { continue }
                // Decision 445: the pedestrian signals, small and close up,
                // cast none.
                for run in props.shapes where run.model < models.buffers.count && !leftOut.contains(run.model) && walkModels?.places(run.model) != true {
                    encoder.setVertexBuffer(models.buffers[run.model], offset: 0, index: 0)
                    encoder.setVertexBuffer(props.instances, offset: run.first * Self.instanceStride, index: 2)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: models.pack.models[run.model].vertexCount,
                                           instanceCount: run.count)
                    drawCalls += 1
                    triangles += models.pack.models[run.model].triangleCount * run.count
                }
            }
        }
        encoder.endEncoding()
    }

    /// The frames a second and the pixels a point that ``quality``, Low
    /// Power Mode, the phone's heat and the GPU's budget ask for.
    /// Decision 417: two steps down when the system warns of memory.
    @objc private func memoryRunsShort() {
        load.relieve()
        rememberRung()
        applyQuality()
        // Decision 610: the street fronts' buffers let go (all of them, by
        // applyQuality, when the step down stops drawing them). Decision
        // 610 續 (review L12-2): those drawn this frame are kept, since
        // the next frame would make them again at once.
        releaseFacades(keepingDrawn: true)
        // Decision 661 (review L13-4): and the per-frame buffers, grown to
        // the largest frame drawn; the next frames make them again at
        // what they need (a frame in flight keeps those it reads).
        frameBuffers.release()
        // Decision 711: and the chunks out of the camera's reach.
        onMemoryShort?()
    }

    /// Decision 610: lets go of every chunk's street fronts' buffers, or
    /// with `keepingDrawn` of those not drawn last frame.
    private func releaseFacades(keepingDrawn: Bool = false) {
        for index in chunks.indices where chunks[index].facade != nil && !(keepingDrawn && chunks[index].frontsUp) {
            chunks[index].facade = nil
            chunks[index].frontsUp = false
        }
    }

    private func applyQuality() {
        let process = ProcessInfo.processInfo
        let heat = Map3DQuality.Heat(rawValue: process.thermalState.rawValue) ?? .critical
        let plan = quality.plan(lowPower: process.isLowPowerModeEnabled, heat: heat)
        if preferredFramesPerSecond != plan.framesPerSecond { preferredFramesPerSecond = plan.framesPerSecond }
        load.deepest = Map3DLoadGovernor.deepest(lowersWhenOver: plan.lowersWhenOver)
        load.stepsDownForLoad = plan.lowersWhenOver
        load.highest = Map3DLoadGovernor.highest(heat: heat)
        sunPlan = Map3DSunShadow.plan(quality, lowPower: process.isLowPowerModeEnabled, heat: heat, overBudget: load.level.drawing.fewerPixels)
        trainMaterials = Map3DReflection.trainStrength(quality, lowPower: process.isLowPowerModeEnabled, heat: heat)
        let fewer = plan.fewerPixels || load.level.drawing.fewerPixels
        let facades = Map3DRealFacade.draws(quality: quality, lowPower: process.isLowPowerModeEnabled, heat: heat, tier: level?.tier)
        drawsGlows = Map3DGlow.draws(quality: quality, lowPower: process.isLowPowerModeEnabled, heat: heat, tier: level?.tier,
                                     overBudget: load.level.drawing.fewerPixels)
        if facades != drawsFacades {
            drawsFacades = facades
            if !facades { releaseFacades() }
        }
        if fewer != drawsFewerPixels {
            drawsFewerPixels = fewer
            setNeedsLayout()
        }
    }

    /// The newest Apple GPU family `device` belongs to, as a number (9 for
    /// `.apple9`), 0 for none.
    /// Decision 417: `device`'s tier.
    nonisolated static func tier(of device: MTLDevice) -> Map3DDeviceTier? {
        #if DEBUG
        // Decision 596: the Simulator's GPU (Apple2, decision 580) has no
        // tier, so its streets draw nothing; a screenshot of the street's
        // traffic asks for one (`-screenshot-device-tier 0…2`).
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-screenshot-device-tier"), arguments.indices.contains(index + 1),
           let asked = Int(arguments[index + 1]).flatMap(Map3DDeviceTier.init(rawValue:)) {
            return asked
        }
        #endif
        return Map3DDeviceTier.forGPU(family: appleFamily(of: device), name: device.name)
    }

    nonisolated static func appleFamily(of device: MTLDevice) -> Int {
        let families: [(MTLGPUFamily, Int)] = [(.apple9, 9), (.apple8, 8), (.apple7, 7), (.apple6, 6), (.apple5, 5), (.apple4, 4)]
        return families.first { device.supportsFamily($0.0) }?.1 ?? 0
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Decision 231: `Map3DSurfaces.png` as one array of layers with their
    /// mipmaps. The file is RGB, since Xcode premultiplies a PNG's alpha
    /// when it copies it: each layer's colour on the left and its tint mask
    /// on the right, put together here. Without the file every layer is
    /// mid grey and tints fully, so every face shows its colour alone.
    private static func makeSurfaces(device: MTLDevice, queue: MTLCommandQueue) -> MTLTexture? {
        let side = Map3DSurface.side, count = Map3DSurface.allCases.count
        var levels = 1
        while side >> levels > 0 { levels += 1 }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.width = side
        descriptor.height = side
        descriptor.arrayLength = count
        descriptor.mipmapLevelCount = levels
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let layerBytes = side * side * 4
        let pixels = surfacePixels(side: side, count: count)
            ?? [UInt8]((0..<(side * side * count)).flatMap { _ in [UInt8(128), 128, 128, 255] })
        pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            for layer in 0..<count {
                texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0, slice: layer,
                                withBytes: base + layer * layerBytes, bytesPerRow: side * 4, bytesPerImage: layerBytes)
            }
        }
        if let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commands.commit()
        }
        return texture
    }

    /// Decision 352: `Map3DSigns.png` with its first few mipmaps (to 128
    /// pixels, a word's strip still 4 pixels high: smaller, the words
    /// beside it would bleed in), or `nil` without the file.
    private static func makeSignAtlas(device: MTLDevice, queue: MTLCommandQueue) -> MTLTexture? {
        let side = Map3DSignAtlas.side
        guard let url = Bundle.main.url(forResource: "Map3DSigns", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == side, image.height == side,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: side, height: side, mipmapped: true)
        descriptor.mipmapLevelCount = 5
        descriptor.usage = .shaderRead
        guard drawn, let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0, withBytes: pixels, bytesPerRow: side * 4)
        if let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commands.commit()
        }
        return texture
    }

    /// The layers of `Map3DSurfaces.png`, RGBA, one after another, or
    /// `nil` when the file is missing or not `count` layers of `side`.
    private static func surfacePixels(side: Int, count: Int) -> [UInt8]? {
        guard let url = Bundle.main.url(forResource: "Map3DSurfaces", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == 2 * side, image.height == side * count,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let width = image.width, height = image.height
        var strip = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = strip.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Each layer's colour, with its mask's red as the alpha.
        var layers = [UInt8](repeating: 0, count: side * side * 4 * count)
        for row in 0..<(side * count) {
            for x in 0..<side {
                let colour = (row * width + x) * 4, mask = (row * width + side + x) * 4, to = (row * side + x) * 4
                layers[to] = strip[colour]
                layers[to + 1] = strip[colour + 1]
                layers[to + 2] = strip[colour + 2]
                layers[to + 3] = strip[mask]
            }
        }
        return layers
    }

    /// An instance's bytes (`Map3DInstance` in `Map3DShaders.metal`): a
    /// matrix and a colour.
    private static let instanceStride = 80
    /// Decision 617: one instance that leaves the scene as it is, for the
    /// trains' lamps' glows, already placed.
    private static let sceneInstance: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1]

    override func layoutSubviews() {
        super.layoutSubviews()
        // 2026-10-21 (decision 238's later note): fewer pixels once the GPU
        // keeps over its budget.
        let scale = CGFloat(Map3DDrawScale.scale(display: Double(traitCollection.displayScale), lowered: drawsFewerPixels,
                                                 points: Double(bounds.width * bounds.height)))
        if scale > 0, contentScaleFactor != scale { contentScaleFactor = scale }
        camera.viewport = (Float(max(bounds.width, 1)), Float(max(bounds.height, 1)))
    }

    /// Decision 333: follows `follow`'s train from now, flying there over
    /// ``MotionRule/cameraFlight`` (at once with Reduce Motion) when the
    /// train or the view changed; `nil` stops following, flying back to
    /// the map's own tilt over the same place. A pinch's distance
    /// (``Map3DFollow/scale``) stays while the same train is followed.
    func follow(_ follow: Map3DFollow?, reduceMotion: Bool) {
        let rule = MotionRule.cameraFlight.running(reduceMotion: reduceMotion)
        guard let follow else {
            guard following != nil else { return }
            following = nil
            lastFollowStep = nil
            var free = camera
            free.pitch = nil
            free.lens = nil
            flying = (Map3DFlight(from: camera, began: CACurrentMediaTime(), rule: rule), free)
            return
        }
        guard let current = following, current.subject == follow.subject else {
            following = follow
            ringed = nil
            flightAsked = nil
            flying = (Map3DFlight(from: camera, began: CACurrentMediaTime(), rule: rule), nil)
            return
        }
        if current.view == follow.view {
            // Decision 403 (續): from the station, flying on to the next
            // stop's platform; staying on the one it left until it is
            // well past, and on one the train is still running to while
            // it is the same.
            guard follow.view == .station, current.lookout != follow.lookout else { return }
            if let old = current.lookout, let new = follow.lookout, old.station == new.station, new.left || old.eye == new.eye { return }
            following?.lookout = follow.lookout
            flying = (Map3DFlight(from: camera, began: CACurrentMediaTime(), rule: rule), nil)
            return
        }
        following?.view = follow.view
        following?.lookout = follow.lookout
        flying = (Map3DFlight(from: camera, began: CACurrentMediaTime(), rule: rule), nil)
    }

    /// Decision 334: flies to `goal` (worked out from the camera at the
    /// next frame; `nil` stays) over ``MotionRule/cameraFlight``, at once
    /// with Reduce Motion, and stays there, the map's own view.
    func fly(reduceMotion: Bool, to goal: @escaping (Map3DCamera) -> Map3DCamera?) {
        following = nil
        lastFollowStep = nil
        flightAsked = (reduceMotion, goal)
    }

    /// Decision 333: a finger on the map stops the flight back to the
    /// map's own view where it is, and the camera tilts as the map's own
    /// from there.
    func stopFlyingBack() {
        guard following == nil, let flying, let still = flying.to else { return }
        camera.pitch = still.pitch
        camera.lens = still.lens
        self.flying = nil
    }

    /// Decision 333: a pinch while following moves the camera in or out.
    func zoomFollow(by factor: Float) {
        following = following?.zoomed(by: factor)
    }

    /// Decision 333: the camera this frame: on its flight, or after the
    /// followed train, whose front is among `heads`. A train not drawn
    /// this frame leaves the camera where it is.
    private func moveCamera(heads: [Map3DTrains.Head], at now: CFTimeInterval) {
        if let asked = flightAsked {
            flightAsked = nil
            if let goal = asked.goal(camera) {
                let rule = MotionRule.cameraFlight.running(reduceMotion: asked.reduceMotion)
                flying = (Map3DFlight(from: camera, began: now, rule: rule), goal)
            }
        }
        if let flying, let still = flying.to {
            // The view as it is laid out now, turned or not.
            let viewport = camera.viewport
            camera = flying.flight.camera(toward: still, at: now)
            camera.viewport = viewport
            if flying.flight.isOver(at: now) {
                self.flying = nil
                landed?()
            }
            return
        }
        guard var following else {
            // Decision 714: free, the target stays over the map.
            if flying == nil, let ground { camera = camera.held(over: ground) }
            return
        }
        let pose: Map3DFollow.Pose
        followedSeeThrough = nil
        // One switch over a local copy of the subject, and no closure that
        // captures `following`: chained `if let following.bus/.cabin/...`
        // here crashed Xcode 26.6's Release optimizer (CopyPropagation,
        // "Found outside of lifetime use?!"). Do not change it back.
        let subject = following.subject
        switch subject {
        case .bus(let bus):
            guard let found = busPose?(bus) else { return }
            pose = found
        case .cabin(let cabin):
            guard let found = cabinPose?(cabin) else { return }
            pose = found
            followedSeeThrough = Map3DSeeThrough.point(of: found)
        case .ferry(let ferry):
            guard let found = ferryPose?(ferry) else { return }
            pose = found
        case .realTrain(let real):
            guard let found = realTrainPose?(real) else { return }
            pose = found
        case .aircraft(let flight):
            guard let found = aircraftPose?(flight) else { return }
            pose = found
        case .train(let train):
            guard let head = heads.first(where: { $0.train == train }) else { return }
            pose = head.pose
        }
        // Decision 578: no jump to a platform with nothing built round it.
        if following.view == .station, let lookout = following.lookout {
            let built = lookoutBuilt?(lookout.eye) ?? true
            if built != lookoutWasBuilt {
                lookoutWasBuilt = built
                flying = (Map3DFlight(from: camera, began: now, rule: MotionRule.cameraFlight.running(reduceMotion: reduceMotion)), nil)
            }
            if !built { following.lookout = nil }
        } else {
            lookoutWasBuilt = true
        }
        let elapsed = lastFollowStep.map { now - $0 } ?? 0
        lastFollowStep = now
        if let flight = flying?.flight {
            let goal = following.camera(following: pose, from: camera, elapsed: 0, turnsAtOnce: true)
            camera = flight.camera(toward: goal, at: now)
            if flight.isOver(at: now) { flying = nil }
        } else {
            camera = following.camera(following: pose, from: camera, elapsed: elapsed)
        }
    }

    /// Decision 230: draws the trains near the eye with `uploaded`'s
    /// models; decision 608: their buffers made once, off the main thread,
    /// and shared, so this only takes them.
    func useModels(_ uploaded: Map3DUploadedModels) {
        guard let device, uploaded.buffers.allSatisfy({ $0.device === device }) else { return }
        let pack = uploaded.pack
        models = (pack, uploaded.buffers, uploaded.textures)
        glowSpots = uploaded.glowBuffer.map { (table: uploaded.glows, buffer: $0) }
        transparentGlass = uploaded.glass
        signalModels = Map3DSignalTiming.Models(pack: pack)
        walkModels = Map3DPedestrianSignal.Models(pack: pack)
    }

    /// Draws `scene` from now on; decision 358: but for the chunks at
    /// `kept`, built ahead before it, which it does not hold whole.
    func show(_ scene: Map3DScene, keeping kept: Set<Map3DStreaming.Key> = []) {
        sunSceneChanged = true
        openings = scene.trackCover.openings
        let old = chunks.filter { kept.contains(Map3DStreaming.Key(column: $0.column, row: $0.row)) }
        let held = Set(old.map { Map3DStreaming.Key(column: $0.column, row: $0.row) })
        chunks = scene.chunks.filter { !held.contains(Map3DStreaming.Key(column: $0.column, row: $0.row)) }.compactMap(makeChunk) + old
    }

    /// Decision 517 續 (PR 3b): draws `scene`'s chunks at `keys` in place
    /// of what was there, and its tunnels' openings; the other chunks
    /// drawn stay (`scene` was built again from the scene drawn, only at
    /// `keys`).
    func replace(_ keys: Set<Map3DStreaming.Key>, from scene: Map3DScene) {
        openings = scene.trackCover.openings
        place(scene.chunks.filter { keys.contains(Map3DStreaming.Key(column: $0.column, row: $0.row)) }, at: keys.sorted())
    }

    /// Decision 358: draws `built` at `keys` (in place of what was there;
    /// a key with no chunk is empty ground).
    func place(_ built: [Map3DScene.Chunk], at keys: [Map3DStreaming.Key]) {
        sunSceneChanged = true
        let replaced = Set(keys)
        chunks.removeAll { replaced.contains(Map3DStreaming.Key(column: $0.column, row: $0.row)) }
        chunks += built.compactMap(makeChunk)
    }

    /// Decision 358: lets go of the chunks at `keys`.
    func remove(_ keys: [Map3DStreaming.Key]) {
        let gone = Set(keys)
        chunks.removeAll { gone.contains(Map3DStreaming.Key(column: $0.column, row: $0.row)) }
        sunSceneChanged = true
    }

    private func makeChunk(_ chunk: Map3DScene.Chunk) -> Chunk? {
        guard !chunk.mesh.isEmpty, let vertices = makeBuffer(chunk.mesh.vertices), let indices = makeBuffer(chunk.mesh.indices)
        else { return nil }
        var shadows: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        if let shadowVertices = makeBuffer(chunk.shadows.vertices), let shadowIndices = makeBuffer(chunk.shadows.indices) {
            shadows = (shadowVertices, shadowIndices, chunk.shadows.indices.count)
        }
        var far: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        if let farVertices = makeBuffer(chunk.far.vertices), let farIndices = makeBuffer(chunk.far.indices) {
            far = (farVertices, farIndices, chunk.far.indices.count)
        }
        // Decision 455: its boxes as they are, 88 bytes each, for the
        // shader to make into vertices.
        let farBoxes = makeBuffer(chunk.farBoxes).map {
            (instances: $0, count: chunk.farBoxes.count, triangles: chunk.farBoxes.reduce(0) { $0 + $1.triangleCount })
        }
        var close: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        if let closeVertices = makeBuffer(chunk.close.vertices), let closeIndices = makeBuffer(chunk.close.indices) {
            close = (closeVertices, closeIndices, chunk.close.indices.count)
        }
        var standIn: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        if let standInVertices = makeBuffer(chunk.standIn.vertices), let standInIndices = makeBuffer(chunk.standIn.indices) {
            standIn = (standInVertices, standInIndices, chunk.standIn.indices.count)
        }
        var props: (instances: MTLBuffer, runs: [Map3DPropRuns.Run], shapes: [Map3DPropRuns.Run])?
        let sorted = Map3DPropRuns(chunk.props)
        if let instances = makeBuffer(sorted.instances.flatMap(\.floats)) {
            props = (instances, sorted.runs, sorted.shapes)
        }
        let signs = makeBuffer(chunk.signs.flatMap(\.floats)).map { (instances: $0, count: chunk.signs.count) }
        var made = Chunk(vertices: vertices, indices: indices, indexCount: chunk.mesh.indices.count, baseIndexCount: chunk.baseIndexCount,
                     far: far, farBoxes: farBoxes, farLevels: chunk.farLevels, close: close, standIn: standIn, shadows: shadows, props: props, signs: signs, minimum: chunk.minimum, maximum: chunk.maximum,
                     column: chunk.column, row: chunk.row, cityTops: chunk.cityTops, coarse: chunk.coarse, facadeMesh: chunk.facade)
        let buffers: [MTLBuffer?] = [vertices, indices, far?.vertices, far?.indices, farBoxes?.instances, close?.vertices, close?.indices,
                                     standIn?.vertices, standIn?.indices, shadows?.vertices, shadows?.indices, props?.instances, signs?.instances]
        made.bytes = buffers.reduce(0) { $0 + ($1?.length ?? 0) }
        return made
    }

    /// Decision 259: the most figures and vehicles a frame draws (the
    /// fullest detail's); their buffer is the frame's set's
    /// (``Map3DFrameBuffers``).
    /// Decision 417: the most a higher tier draws, the player's buses (at
    /// most its buses) besides its vehicles.
    private static let lifeCapacity = {
        let most = Map3DDeviceTier.higher.streetLimits
        return most.people + most.vehicles + most.buses
    }()

    /// Decision 608, second continuation: the current set's buffer for
    /// `use` with `array`'s bytes copied in (made larger first when too
    /// small); the frame has taken its set.
    private func fill<Element>(_ use: Map3DFrameBuffers<MTLBuffer>.Use, _ array: [Element]) -> MTLBuffer? {
        guard !array.isEmpty, let device else { return nil }
        return array.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress,
                  let buffer = frameBuffers.buffer(use, bytes: bytes.count,
                                                   make: { device.makeBuffer(length: $0, options: .storageModeShared) })
            else { return nil }
            buffer.contents().copyMemory(from: base, byteCount: bytes.count)
            return buffer
        }
    }

    private func makeBuffer<Element>(_ array: [Element]) -> MTLBuffer? {
        guard !array.isEmpty, let device else { return nil }
        return array.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
        }
    }

    /// 2026-10-21 (the far view's CPU: the owner's iPhone 17 Pro read 16.6
    /// ms on Taipei seen whole, one 60 Hz frame to the tenth): the frame's
    /// CPU work comes first (which chunks show and how, the trains, the
    /// street life and their buffers), and only then the drawable, as
    /// Apple advises: held as briefly as possible. The time spent waiting
    /// for it, and for a set of buffers the GPU still reads, is
    /// counted apart (``Stats/waitMilliseconds``): the CPU's time was
    /// measured from before the drawable, so a wait for the screen read
    /// as work.
    override func draw(_ rect: CGRect) {
        let start = CACurrentMediaTime()
        var waited = 0.0
        shown = lighting
        shown.weather = weatherChange?.weather(at: start) ?? .clear
        let sky = shown.background
        clearColor = MTLClearColor(red: Double(sky.x), green: Double(sky.y), blue: Double(sky.z), alpha: 1)
        // Decision 333: the trains first, so the camera following one
        // looks at where it is this frame.
        var frame = trains?(camera.eye, level?.reach ?? .standard)
        // Decision 449: their lamps and windows as the city's lights come on.
        if let pack = models?.pack, frame != nil { Map3DTrainLights.add(to: &frame!, pack: pack, lights: shown.lights) }
        moveCamera(heads: frame?.heads ?? [], at: start)
        onCamera?(camera, start)
        // Decision 394: deep in a tunnel, the cab sees nothing on the
        // ground, so none of it is drawn (nor let go: it is all there the
        // frame it is seen again).
        // A local copy of the subject, not `following?.train` in the
        // closure (Xcode 26.6 Release optimizer crash, see moveCamera).
        let followedSubject = following?.subject
        let followedTrain: TrainID? = if case .train(let id)? = followedSubject { id } else { nil }
        underground.update(view: following?.view, head: frame?.heads.first(where: { $0.train == followedTrain }), flying: flying != nil,
                           camera: camera, openings: openings)
        let below = underground.isUnderground
        let camera = camera
        // Decision 709: the far level of this frame, held at a step.
        farLevel = Map3DFarDetail.level(distance: camera.distance, was: farLevel)
        let matrix = camera.viewProjection
        // Decision 357: the sun's shadow map, drawn again when it is out
        // of date (before the frame's own pass, in the same command buffer).
        let sunRegion: (drawn: Map3DSunShadow.Region?, redraw: Map3DSunShadow.Region?) = below ? (nil, nil) : wantedSunRegion(at: start)
        let uniforms = uniformValues(matrix, seconds: start, sun: sunRegion.drawn)
        var visible: [Chunk] = []
        var visibleAt: [Int] = []
        var facadeUploads = 0
        for index in chunks.indices {
            chunks[index].share = .whole
            // Decision 238: in full near the camera, whether in view or not,
            // so the margin holds.
            chunks[index].detailed = !chunks[index].coarse
                && camera.wantsDetail(minimum: chunks[index].minimum, maximum: chunks[index].maximum, wasDetailed: chunks[index].detailed)
            // Decision 267: and its closest detail, only close up; decision
            // 380: a coarse chunk's too, which holds only the overhead line.
            chunks[index].closeUp = chunks[index].close != nil
                && camera.drawsClose(minimum: chunks[index].minimum, maximum: chunks[index].maximum, detailed: chunks[index].detailed,
                                     coarse: chunks[index].coarse, wasClose: chunks[index].closeUp)
            chunks[index].walksClose = camera.drawsClose(minimum: chunks[index].minimum, maximum: chunks[index].maximum,
                                                         detailed: chunks[index].detailed, coarse: false, wasClose: chunks[index].walksClose)
            // Decision 610: and the real buildings' street fronts, made into
            // buffers the first time.
            let frontsWereUp = chunks[index].frontsUp
            chunks[index].frontsUp = drawsFacades && !chunks[index].facadeMesh.isEmpty
                && camera.drawsClose(minimum: chunks[index].minimum, maximum: chunks[index].maximum, detailed: chunks[index].detailed,
                                     coarse: chunks[index].coarse, wasClose: chunks[index].frontsUp)
            // Decision 661 (review L13-6): a chunk leaving the close-up
            // lets go of its street fronts' buffers, as decision 610 meant
            // ("let go when not drawn"): kept, every chunk once close in a
            // dense city held them (up to some 0.9 MB each). The close-up's
            // own margin keeps a chunk at its edge from letting go and
            // making them again frame after frame.
            if frontsWereUp, !chunks[index].frontsUp { chunks[index].facade = nil }
            // Decision 610 續 (review L12-2): at most a few a frame, so a
            // city's close-up opening (or the frame after a memory
            // warning) does not copy them all in one frame; the rest show
            // in the frames after.
            if chunks[index].frontsUp, chunks[index].facade == nil, facadeUploads < Map3DRealFacade.uploadsAFrame,
               let vertices = makeBuffer(chunks[index].facadeMesh.vertices), let indices = makeBuffer(chunks[index].facadeMesh.indices) {
                chunks[index].facade = (vertices, indices, chunks[index].facadeMesh.indices.count)
                facadeUploads += 1
            }
            if Map3DCamera.sees(minimum: chunks[index].minimum, maximum: chunks[index].maximum, through: matrix) {
                visible.append(chunks[index])
                visibleAt.append(index)
            }
        }
        // Decision 711: the still scene within its budget, shared out from
        // the chunk nearest what the camera looks at: past it, a chunk is
        // drawn simplified, then as its ground alone, then not at all. The
        // sun's map draws them the same.
        let nearestFirst = visible.indices.map { place in
            (place: place, distance: Map3DStreaming.distance(of: Map3DStreaming.Key(column: visible[place].column, row: visible[place].row),
                                                             to: camera.target))
        }.sorted { $0.distance < $1.distance }
        let shares = Map3DSceneBudget.shares(of: nearestFirst.map { visible[$0.place].cost(pack: models?.pack) },
                                             within: Map3DSceneBudget.triangles(tier: level?.tier))
        for (entry, share) in zip(nearestFirst, shares) where share != .whole {
            visible[entry.place].share = share
            visible[entry.place].detailed = false
            visible[entry.place].closeUp = false
            visible[entry.place].frontsUp = false
            chunks[visibleAt[entry.place]].share = share
            chunks[visibleAt[entry.place]].detailed = false
        }
        if shares.contains(.nothing) { visible.removeAll { $0.share == .nothing } }
        trainHeads?(frame?.heads ?? [], camera)
        // Decision 342: the cars the city in front of is seen through.
        // Supplement: and the cabin followed, as one point.
        let seeThrough = Map3DSeeThrough(eye: camera.eye, cars: frame?.cars ?? [], matrix: matrix, followed: followedSeeThrough)
        // Decision 230: the cars near the eye, one draw call a model, every
        // car of it an instance.
        var carsSorted: [Map3DInstance] = []
        if let instances = frame?.instances, !instances.isEmpty, models != nil {
            carsSorted = instances.sorted { $0.model < $1.model }
        }
        // Decision 259: the people and vehicles near the target.
        // Decision 417: in what the trains leave of the budget.
        var budget = Map3DMotionBudget(tier: level?.tier, step: level?.streets ?? .full, trainTriangles: frame?.triangles(in: models?.pack) ?? 0)
        // Decision 445: and the pedestrian signals close up, while the
        // streets' people are drawn.
        let drawsWalks = !below && budget.drawsPedestrianSignals
        if drawsWalks, let walkModels, let pack = models?.pack {
            budget.signalTriangles = visible.reduce(0) { sum, chunk in
                chunk.detailed && chunk.walksClose ? sum + (chunk.props.map { walkModels.triangles($0.runs, in: pack) } ?? 0) : sum
            }
        }
        let life = below ? nil : streetLife?(camera, shown.lights, budget)
        var lifeSorted: [Map3DInstance] = []
        if let instances = life?.instances, !instances.isEmpty, models != nil {
            lifeSorted = Array(instances.sorted { $0.model < $1.model }.prefix(Self.lifeCapacity))
        }
        // Build one globally sorted scene-space glass batch for the selected
        // native model instances. Ordinary model packs fill no batch.
        var glassVertices: [Map3DVertex] = []
        if !transparentGlass.isEmpty, glassDrawing != nil {
            glassVertices = transparentGlass.vertices(instances: carsSorted + lifeSorted, eye: camera.eye, toward: camera.target)
        }
        // Decision 608, second continuation: this frame's buffers are the
        // next of three sets, once the GPU is done with it, none made anew
        // unless a set is too small for this frame.
        let boxMesh = frame.flatMap { $0.boxes.isEmpty ? nil : $0.boxes }
        let shadowMesh = frame.flatMap { $0.shadows.isEmpty ? nil : $0.shadows }
        // Decision 617: the glows round the trains' lamps, placed this frame.
        let glows = glowsNow
        // Decision 702: and the aircraft's lamps.
        let trainGlowFloats = glows && models != nil && frame != nil
            ? (Map3DGlow.trainSpots(of: frame!, pack: models!.pack) + frame!.lamps).flatMap(\.floats) : []
        // Decision 672: seeing underground, over the map only; the cars in
        // the tunnels this frame.
        let drawsXRay = xrayDrawing != nil && Map3DXRay.draws(switchOn: xray != nil, following: following != nil)
        var xrayCarMesh: Map3DMesh?
        if drawsXRay, let buried = frame?.buried, !buried.isEmpty {
            var mesh = Map3DMesh()
            Map3DXRay.addCars(buried, to: &mesh)
            xrayCarMesh = mesh.isEmpty ? nil : mesh
        }
        let fills = boxMesh != nil || shadowMesh != nil || !carsSorted.isEmpty || !lifeSorted.isEmpty || !glassVertices.isEmpty
            || !trainGlowFloats.isEmpty || xrayCarMesh != nil
        if fills {
            let waiting = CACurrentMediaTime()
            frameInFlight.wait()
            waited += CACurrentMediaTime() - waiting
            frameBuffers.advance()
        }
        var trainBoxes: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int, triangles: Int)?
        if let mesh = boxMesh, let vertices = fill(.boxVertices, mesh.vertices), let indices = fill(.boxIndices, mesh.indices) {
            trainBoxes = (vertices, indices, mesh.indices.count, mesh.triangleCount)
        }
        var trainShadows: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int, triangles: Int)?
        if let mesh = shadowMesh, let vertices = fill(.shadowVertices, mesh.vertices), let indices = fill(.shadowIndices, mesh.indices) {
            trainShadows = (vertices, indices, mesh.indices.count, mesh.triangleCount)
        }
        var xrayCars: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        if let mesh = xrayCarMesh, let vertices = fill(.xrayVertices, mesh.vertices), let indices = fill(.xrayIndices, mesh.indices) {
            xrayCars = (vertices, indices, mesh.indices.count)
        }
        var cars: (sorted: [Map3DInstance], buffer: MTLBuffer)?
        if let buffer = fill(.cars, carsSorted.flatMap(\.floats)) { cars = (carsSorted, buffer) }
        var lifeDraw: (sorted: [Map3DInstance], buffer: MTLBuffer)?
        if let buffer = fill(.life, lifeSorted.flatMap(\.floats)) { lifeDraw = (lifeSorted, buffer) }
        var glassBuffer: (buffer: MTLBuffer, vertices: Int)?
        if let buffer = fill(.glass, glassVertices) { glassBuffer = (buffer, glassVertices.count) }
        let trainGlows = fill(.glows, trainGlowFloats)
        // Decision 617: the runs of instances whose models glow, as they
        // are drawn: the instances' buffer and offset, the model, how many.
        var glowRuns: [(instances: MTLBuffer, offset: Int, model: Int, count: Int)] = []
        func glowRun(_ instances: MTLBuffer, offset: Int, model: Int, count: Int) {
            if glows, let glowSpots, glowSpots.table.spots(of: model) > 0 { glowRuns.append((instances, offset, model, count)) }
        }
        let waiting = CACurrentMediaTime()
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable, let commands = queue.makeCommandBuffer()
        else {
            // The frame's set taken goes back unused.
            if fills { frameInFlight.signal() }
            return
        }
        waited += CACurrentMediaTime() - waiting
        var drawCalls = 0, triangles = 0
        if let redraw = sunRegion.redraw {
            drawSunMap(redraw, commands: commands, drawCalls: &drawCalls, triangles: &triangles)
        }
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            // The frame's set taken goes back unused, and the sun's map is
            // drawn again next frame.
            if fills { frameInFlight.signal() }
            if sunRegion.redraw != nil { sunDrawn = nil }
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setFragmentTexture(surfaces, index: 0)
        encoder.setFragmentTexture(sunRegion.drawn == nil ? noSunMap : sunMap, index: 1)
        encoder.setFragmentTexture(noModelTexture, index: 2)
        uniforms.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            encoder.setVertexBytes(base, length: bytes.count, index: 1)
            encoder.setFragmentBytes(base, length: bytes.count, index: 1)
        }
        if !seeThrough.cars.isEmpty {
            seeThrough.floats.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setFragmentBytes(base, length: bytes.count, index: 2)
            }
        }
        var farBoxes: [(instances: MTLBuffer, count: Int, triangles: Int, seen: Bool)] = []
        // Decision 709: the farther the camera, the larger the smallest
        // thing a chunk drawn from afar draws (nothing left out up to
        // where chunks are drawn in full).
        let farLevel = farLevel
        for chunk in visible {
            let afar = chunk.farLevels[farLevel]
            // Decision 238: the city in full near the camera; afar, the
            // ground and track, then the city simplified.
            let detailed = chunk.detailed
            // Decision 342: a chunk a cone crosses draws its city apart,
            // seen through in front of the trains.
            let seen = seeThrough.cuts(column: chunk.column, row: chunk.row, tops: chunk.cityTops)
            let count = detailed ? (!seen && !below ? chunk.indexCount : chunk.baseIndexCount) : afar.base
            if count > 0 {
                encoder.setVertexBuffer(chunk.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32,
                                              indexBuffer: chunk.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += count / 3
            }
            // Decision 394: under the ground, only its ground, track and
            // roads, where the tunnels are.
            if below { continue }
            // Decision 267's closest detail (the overhead line among it)
            // stays solid.
            if chunk.closeUp, let close = chunk.close {
                encoder.setVertexBuffer(close.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: close.indexCount, indexType: .uint32,
                                              indexBuffer: close.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += close.indexCount / 3
            }
            if chunk.frontsUp, let facade = chunk.facade {
                encoder.setVertexBuffer(facade.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: facade.indexCount, indexType: .uint32,
                                              indexBuffer: facade.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += facade.indexCount / 3
            }
            if seen { encoder.setRenderPipelineState(seeThroughPipeline) }
            if detailed, seen, chunk.indexCount > chunk.baseIndexCount {
                let city = chunk.indexCount - chunk.baseIndexCount
                encoder.setVertexBuffer(chunk.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: city, indexType: .uint32, indexBuffer: chunk.indices,
                                              indexBufferOffset: chunk.baseIndexCount * MemoryLayout<UInt32>.stride)
                drawCalls += 1
                triangles += city / 3
            }
            // The kit buildings' boxes, but not over their models close up.
            if detailed, !chunk.closeUp, let standIn = chunk.standIn {
                encoder.setVertexBuffer(standIn.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: standIn.indexCount, indexType: .uint32,
                                              indexBuffer: standIn.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += standIn.indexCount / 3
            }
            if !detailed, chunk.share < .ground, let far = chunk.far, afar.far > 0 {
                encoder.setVertexBuffer(far.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: afar.far, indexType: .uint32,
                                              indexBuffer: far.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += afar.far / 3
            }
            if !detailed, chunk.share < .ground, let boxes = chunk.farBoxes, afar.boxes > 0 { farBoxes.append((boxes.instances, afar.boxes, afar.boxTriangles, seen)) }
            if seen { encoder.setRenderPipelineState(pipeline) }
        }
        // Decision 455: the simplified city's boxes, a draw a chunk, the
        // solid ones first and then those seen through.
        if !farBoxes.isEmpty {
            var seeing: Bool?
            for (instances, count, boxTriangles, seen) in farBoxes.sorted(by: { !$0.seen && $1.seen }) {
                if seeing != seen { encoder.setRenderPipelineState(seen ? boxSeeThroughPipeline : boxPipeline) }
                seeing = seen
                encoder.setVertexBuffer(instances, offset: 0, index: 2)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: Map3DBoxInstance.indices.count, indexType: .uint16,
                                              indexBuffer: boxIndices, indexBufferOffset: 0, instanceCount: count)
                drawCalls += 1
                triangles += boxTriangles
            }
            encoder.setRenderPipelineState(pipeline)
        }
        if let boxes = trainBoxes {
            encoder.setVertexBuffer(boxes.vertices, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: boxes.indexCount, indexType: .uint32,
                                          indexBuffer: boxes.indices, indexBufferOffset: 0)
            drawCalls += 1
            triangles += boxes.triangles
        }
        if let models {
            // Decision 230: the cars; decision 259: the people and vehicles.
            for (sorted, buffer) in [cars, lifeDraw].compactMap({ $0 }) {
                encoder.setRenderPipelineState(instancedPipeline)
                var first = 0
                while first < sorted.count {
                    let model = sorted[first].model
                    var last = first
                    while last + 1 < sorted.count, sorted[last + 1].model == model { last += 1 }
                    let count = last - first + 1
                    if model < models.buffers.count {
                        encoder.setVertexBuffer(models.buffers[model], offset: 0, index: 0)
                        encoder.setFragmentTexture(models.textures[model] ?? noModelTexture, index: 2)
                        encoder.setVertexBuffer(buffer, offset: first * Self.instanceStride, index: 2)
                        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: models.pack.models[model].vertexCount,
                                               instanceCount: count)
                        drawCalls += 1
                        triangles += models.pack.models[model].triangleCount * count
                        glowRun(buffer, offset: first * Self.instanceStride, model: model, count: count)
                    }
                    first = last + 1
                }
            }
        }
        // Decision 244: the street furniture of the chunks drawn in full,
        // one draw call a model and chunk. Decision 355: Saving leaves the
        // bus stops and vending machines out. Decision 429: the signals
        // one a light group, each drawn lit as the game clock shows
        // (Saving and Reduce Motion too: the light changes colour, nothing
        // moves). Decision 445: the pedestrian signals close up, their
        // figure walking and flashing with the screen's clock (still with
        // Reduce Motion or paused).
        walkPace.advance(to: start, clock: signalClock, reduceMotion: reduceMotion)
        if let models, !below {
            encoder.setRenderPipelineState(instancedPipeline)
            let leftOut = Map3DProp.modelsLeftOut(quality, in: models.pack)
            for chunk in visible where chunk.detailed {
                guard let props = chunk.props else { continue }
                for run in props.runs where run.model < models.buffers.count && !leftOut.contains(run.model) {
                    let drawn: Int
                    if let walkModels, walkModels.places(run.model) {
                        // Decision 445: a pedestrian signal only close up,
                        // its face and countdown as the clock shows (a
                        // blank digit not at all).
                        guard drawsWalks, chunk.walksClose,
                              let shown = walkModels.model(run.model, group: run.group, clock: signalClock, time: start, pace: walkPace,
                                                                reduceMotion: reduceMotion)
                        else { continue }
                        drawn = shown
                    } else {
                        drawn = signalModels?.model(run.model, group: run.group, clock: signalClock) ?? run.model
                    }
                    encoder.setVertexBuffer(models.buffers[drawn], offset: 0, index: 0)
                    encoder.setFragmentTexture(models.textures[drawn] ?? noModelTexture, index: 2)
                    encoder.setVertexBuffer(props.instances, offset: run.first * Self.instanceStride, index: 2)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: models.pack.models[drawn].vertexCount,
                                           instanceCount: run.count)
                    drawCalls += 1
                    triangles += models.pack.models[drawn].triangleCount * run.count
                    glowRun(props.instances, offset: run.first * Self.instanceStride, model: drawn, count: run.count)
                }
            }
        }
        // Decision 352: the signs of the chunks drawn in full, one draw
        // call a chunk, four corners a sign.
        if let signDrawing, !below, visible.contains(where: { $0.detailed && $0.signs != nil }) {
            encoder.setRenderPipelineState(signDrawing.pipeline)
            encoder.setFragmentTexture(signDrawing.atlas, index: 0)
            Map3DSign.clock(seconds: start, hour: shown.hour, quality: quality, reduceMotion: reduceMotion).withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setVertexBytes(base, length: bytes.count, index: 3)
                encoder.setFragmentBytes(base, length: bytes.count, index: 3)
            }
            for chunk in visible where chunk.detailed {
                guard let signs = chunk.signs else { continue }
                encoder.setVertexBuffer(signs.instances, offset: 0, index: 2)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: signs.count)
                drawCalls += 1
                triangles += 2 * signs.count
            }
        }
        // Decision 347: the sky where nothing was drawn.
        if !below {
            encoder.setRenderPipelineState(skyPipeline)
            encoder.setDepthStencilState(skyDepthState)
            Map3DSky(shown).floats(camera: camera).withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setFragmentBytes(base, length: bytes.count, index: 3)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            drawCalls += 1
            triangles += 1
        }
        // Decision 232: the ground shadows last, over everything drawn;
        // decision 394: under the ground, only the trains'.
        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setDepthStencilState(shadowDepthState)
        for chunk in visible where !below && chunk.share < .ground {
            guard let shadows = chunk.shadows else { continue }
            // Decision 709: from afar, only the shadows of what is drawn.
            let count = chunk.detailed ? shadows.indexCount : chunk.farLevels[farLevel].shadows
            guard count > 0 else { continue }
            encoder.setVertexBuffer(shadows.vertices, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32,
                                          indexBuffer: shadows.indices, indexBufferOffset: 0)
            drawCalls += 1
            triangles += count / 3
        }
        if let shadows = trainShadows {
            encoder.setVertexBuffer(shadows.vertices, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: shadows.indexCount, indexType: .uint32,
                                          indexBuffer: shadows.indices, indexBufferOffset: 0)
            drawCalls += 1
            triangles += shadows.triangles
        }
        // Decision 672: seeing underground, through everything drawn: the
        // tunnels and platforms, then the cars in them.
        if drawsXRay, let xrayDrawing {
            encoder.setRenderPipelineState(xrayDrawing.pipeline)
            encoder.setDepthStencilState(xrayDrawing.depth)
            for part in [xrayBuffers, xrayCars].compactMap({ $0 }) {
                encoder.setVertexBuffer(part.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: part.indexCount, indexType: .uint32,
                                              indexBuffer: part.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += part.indexCount / 3
            }
        }
        // After opaque geometry, sky and ground shadows: none can paint
        // over a window afterwards. Reversed-Z tests opaque depth; glass
        // never writes it, and closed panes are drawn from either side.
        if let glassDrawing, let glassBuffer {
            encoder.setRenderPipelineState(glassDrawing.pipeline)
            encoder.setDepthStencilState(glassDrawing.depth)
            encoder.setCullMode(.none)
            encoder.setFragmentTexture(surfaces, index: 0)
            encoder.setFragmentTexture(sunRegion.drawn == nil ? noSunMap : sunMap, index: 1)
            encoder.setVertexBuffer(glassBuffer.buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: glassBuffer.vertices)
            drawCalls += 1
            triangles += glassBuffer.vertices / 3
        }
        // Decision 617: last, the glows round the lights, added: the
        // models' over the instances they were drawn with, the trains'
        // lamps placed this frame, the signs'.
        if glows, let glowDrawing {
            let axes = Map3DGlow.axes(eye: camera.eye, target: camera.target, lights: shown.lights)
            encoder.setRenderPipelineState(glowDrawing.spots)
            encoder.setDepthStencilState(glowDrawing.depth)
            axes.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                encoder.setVertexBytes(base, length: bytes.count, index: 3)
            }
            let spotStride = Map3DGlow.floatsASpot * MemoryLayout<Float>.stride
            if let glowSpots {
                encoder.setVertexBuffer(glowSpots.buffer, offset: 0, index: 0)
                for run in glowRuns {
                    let spots = glowSpots.table.spots(of: run.model)
                    encoder.setVertexBufferOffset(glowSpots.table.first[run.model] * spotStride, index: 0)
                    encoder.setVertexBuffer(run.instances, offset: run.offset, index: 2)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: spots * Map3DGlow.verticesASpot, instanceCount: run.count)
                    drawCalls += 1
                    triangles += 2 * spots * run.count
                }
            }
            if let trainGlows {
                let spots = trainGlowFloats.count / Map3DGlow.floatsASpot
                encoder.setVertexBuffer(trainGlows, offset: 0, index: 0)
                Self.sceneInstance.withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { return }
                    encoder.setVertexBytes(base, length: bytes.count, index: 2)
                }
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: spots * Map3DGlow.verticesASpot)
                drawCalls += 1
                triangles += 2 * spots
            }
            if let signs = glowDrawing.signs, let signDrawing, !below, visible.contains(where: { $0.detailed && $0.signs != nil }) {
                encoder.setRenderPipelineState(signs)
                encoder.setVertexTexture(signDrawing.atlas, index: 0)
                Map3DSign.clock(seconds: start, hour: shown.hour, quality: quality, reduceMotion: reduceMotion).withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { return }
                    encoder.setVertexBytes(base, length: bytes.count, index: 3)
                }
                axes.withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { return }
                    encoder.setVertexBytes(base, length: bytes.count, index: 4)
                }
                for chunk in visible where chunk.detailed {
                    guard let signs = chunk.signs else { continue }
                    encoder.setVertexBuffer(signs.instances, offset: 0, index: 2)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: signs.count)
                    drawCalls += 1
                    triangles += 2 * signs.count
                }
            }
        }
        // PERF_3D_RAIN (2026-10-30): decision 320's rain over everything,
        // from seeds made once (``Map3DRainDrawing``) and this frame's 16
        // floats; the lightning one more instance over the whole screen.
        if let rainPipeline, rain.drawsStreaks(reduceMotion: reduceMotion, underground: below) {
            if rainSeeds.update(rain, detail: streetDetail) || rainBuffer == nil {
                rainBuffer = makeBuffer(rainSeeds.seeds)
            }
            let flash = rain.flash(at: start)
            let instances = rainSeeds.count + (flash > 0 ? 1 : 0)
            if let rainBuffer, instances > 0, bounds.width > 0, bounds.height > 0 {
                encoder.setRenderPipelineState(rainPipeline.pipeline)
                encoder.setDepthStencilState(rainPipeline.depth)
                encoder.setVertexBuffer(rainBuffer, offset: 0, index: 2)
                rain.uniforms(seconds: start, width: Double(bounds.width), height: Double(bounds.height), night: shown.night, flash: flash,
                              count: rainSeeds.count).withUnsafeBytes { bytes in
                    guard let base = bytes.baseAddress else { return }
                    encoder.setVertexBytes(base, length: bytes.count, index: 3)
                }
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances)
                drawCalls += 1
                triangles += 2 * instances
            }
        }
        encoder.endEncoding()
        if !captures.isEmpty, !drawable.texture.isFramebufferOnly {
            copyForCapture(drawable.texture, commands: commands)
        }
        let gpuTimes = gpuTimes
        if fills {
            let inFlight = frameInFlight
            commands.addCompletedHandler { @Sendable _ in inFlight.signal() }
        }
        // Decision 421: each frame's GPU time and when it reached the screen
        // (0 when it never did), for the frame time record.
        let frameTimes = FrameTimeRecorder.meter
        commands.addCompletedHandler { @Sendable buffer in
            let seconds = buffer.gpuEndTime - buffer.gpuStartTime
            if seconds > 0 {
                gpuTimes.withLock { $0.append(seconds) }
                frameTimes.gpu(milliseconds: seconds * 1_000)
            }
        }
        #if targetEnvironment(simulator)
        // The Simulator's drawables say nothing of reaching the screen: the
        // time the frame was handed over stands in (its figures are only a
        // reference for the CPU side).
        frameTimes.frame(at: CACurrentMediaTime())
        #else
        drawable.addPresentedHandler { @Sendable presented in frameTimes.frame(at: presented.presentedTime) }
        #endif
        commands.present(drawable)
        commands.commit()
        lastLife = (life?.people ?? 0, life?.vehicles ?? 0)
        let cpu = CACurrentMediaTime() - start - waited
        record(cpu: cpu, wait: waited, drawCalls: drawCalls, triangles: triangles)
        FrameTimeRecorder.shared.drew3D(following: following != nil, cpuMilliseconds: cpu * 1_000, triangles: triangles,
                                        drawCalls: drawCalls, chunks: visible.count)
    }

    /// Decision 403 (續二): the next frame drawn, as a picture the size of
    /// the drawable, for `done` (`nil` when it could not be copied), as the
    /// reference's photo journal copies its canvas after the next render
    /// (`commuter_journey` `PhotoJournal.afterRender`). The screen's
    /// drawables are only drawn into, which is quicker; one that can be
    /// read is asked for until the frame is copied.
    func capture(_ done: @escaping @MainActor @Sendable (UIImage?) -> Void) {
        captures.append(done)
        framebufferOnly = false
    }

    /// Copies the frame drawn into `texture` into a buffer as the frame's
    /// commands end, and hands the picture to those waiting.
    private func copyForCapture(_ texture: MTLTexture, commands: MTLCommandBuffer) {
        let waiting = captures
        captures = []
        framebufferOnly = true
        let width = texture.width, height = texture.height
        // Rows on 256 bytes, as a copy into a buffer may need.
        let bytesPerRow = (width * 4 + 255) / 256 * 256
        guard let device, let blit = commands.makeBlitCommandEncoder(),
              let buffer = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared)
        else {
            for done in waiting { done(nil) }
            return
        }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        let copied = Map3DCapturedFrame(buffer: buffer, width: width, height: height, bytesPerRow: bytesPerRow)
        let scale = contentScaleFactor
        commands.addCompletedHandler { @Sendable _ in
            Task { @MainActor in
                let image = copied.image(scale: scale)
                for done in waiting { done(image) }
            }
        }
    }

    /// The uniforms the shaders read (`Map3DUniforms` in
    /// `Map3DShaders.metal`): the matrix, then the sun's way and light, the
    /// ambient light from the sky and from the ground, the fog's colour,
    /// the eye and where the fog starts and ends (and decision 349's ground
    /// haze, ``Map3DGrade``), and the ground shadows'
    /// strength (decision 232) and how far the city's lights are on, then
    /// the night windows' rules (decision 229 續), then decision 356's
    /// reflections (``Map3DReflection/rows``: off on the saving quality,
    /// the ripples still with Reduce Motion; decision 450's trains' glass
    /// and stainless, ``trainMaterials``), then decision 357's sun
    /// shadow map (``Map3DSunShadow/rows(_:lighting:)``; with it, decision
    /// 232's shadows fainter). The lights are
    /// `Map3DLighting`'s (`sunLight`, `skyLight`, `groundLight`, `lights`,
    /// `nightWindowRows`), worked out in GamePresentation.
    /// Decision 617: whether this frame draws glows: they are drawn, and
    /// the city's lights are on.
    private var glowsNow: Bool { drawsGlows && glowDrawing != nil && Map3DGlow.shows(lights: shown.lights) }
    /// Review L19, P3-3: whether this frame's lamps would be drawn, for
    /// the feed that places the aircraft's.
    var lampsLit: Bool { glowsNow }

    private func uniformValues(_ matrix: Map3DMatrix, seconds: Double, sun: Map3DSunShadow.Region?) -> [Float] {
        func padded(_ light: SIMD3<Float>) -> [Float] { [light.x, light.y, light.z, 0] }
        let eye = camera.eye
        let far = camera.depthRange.far
        // Decision 277: under rain the fog is greyer and nearer.
        let fog = shown.fogScale
        return matrix.columns
            + [shown.sunDirection.x, shown.sunDirection.y, shown.sunDirection.z, 0]
            + padded(shown.sunLight)
            + padded(shown.skyLight)
            + padded(shown.groundLight)
            + padded(shown.fogColour)
            + [eye.x, eye.y, eye.z, 1]
            + [camera.distance * 1.6 * fog.near, far * 0.9 * fog.far, Map3DGrade.hazeDensity, Map3DGrade.hazeHeight]
            + [Map3DSunShadow.blobStrength(shown, drawn: sun != nil), shown.lights, glowsNow ? Map3DGlow.windowGlow : 0, 0]
            + Map3DLighting.nightWindowRows
            + Map3DReflection.rows(sky: Map3DSky(shown), sunLight: shown.sunLight, quality: quality, seconds: seconds, reduceMotion: reduceMotion,
                                     trains: trainMaterials)
            + Map3DSunShadow.rows(sun, lighting: shown)
    }

    /// Decision 485: watches the main run loop while the view is in a
    /// window: first after it wakes, last before it waits.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        for observer in mainObservers { CFRunLoopObserverInvalidate(observer) }
        mainObservers = []
        mainAwake = nil
        guard window != nil else { return }
        let woke = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.mainAwake = CACurrentMediaTime() }
        }
        let waits = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, let awake = self.mainAwake else { return }
                self.mainAwake = nil
                let busy = CACurrentMediaTime() - awake
                self.mainBusy = (self.mainBusy.total + busy, max(self.mainBusy.longest, busy))
            }
        }
        mainObservers = [woke, waits].compactMap { $0 }
        for observer in mainObservers { CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes) }
    }

    private func record(cpu: Double, wait: Double, drawCalls: Int, triangles: Int) {
        frames += 1
        cpuTimes.append(cpu)
        waitTimes.append(wait)
        lastCounts = (drawCalls, triangles)
        let now = CACurrentMediaTime()
        guard now - lastStats >= 0.5 else { return }
        let gpu = gpuTimes.withLock { times in
            let taken = times
            times.removeAll()
            return taken
        }
        let stats = Stats(
            framesPerSecond: Double(frames) / (now - lastStats),
            cpuMilliseconds: Self.median(cpuTimes) * 1_000,
            waitMilliseconds: Self.median(waitTimes) * 1_000,
            gpuMilliseconds: Self.median(gpu) * 1_000,
            mainMilliseconds: frames > 0 ? mainBusy.total / Double(frames) * 1_000 : 0,
            mainLongestMilliseconds: mainBusy.longest * 1_000,
            drawCalls: lastCounts.drawCalls,
            triangles: lastCounts.triangles,
            people: lastLife.people,
            vehicles: lastLife.vehicles,
            streetDetail: streetDetail,
            level: level,
            drawScale: Double(contentScaleFactor),
            underground: underground.isUnderground,
            aim: preferredFramesPerSecond,
            drawnHour: shown.hour,
            drawnNight: shown.night,
            drawnLights: shown.lights
        )
        // Decision 417: a step down while the device cannot keep up, a
        // step up once it has for a while.
        // Decision 417: the CPU's and the GPU's times say what to step down.
        if load.record(Map3DLoadGovernor.Sample(framesPerSecond: stats.framesPerSecond, aim: Double(preferredFramesPerSecond),
                                                cpuMilliseconds: stats.cpuMilliseconds, gpuMilliseconds: stats.gpuMilliseconds,
                                                drawingStreets: lastLife.people + lastLife.vehicles > 0)) {
            rememberRung()
        }
        // Decision 460: a step down when little memory is left, before the
        // system's warning.
        if memoryWatch.record(available: UInt64(os_proc_available_memory())) {
            load.relieve()
            rememberRung()
            onMemoryShort?()
        }
        // Low Power Mode and the heat change while the map is open.
        applyQuality()
        frames = 0
        cpuTimes.removeAll()
        waitTimes.removeAll()
        mainBusy = (0, 0)
        lastStats = now
        onStats?(stats)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }
}

extension Map3DQuality {
    /// Decision 365: what this device starts with until the player
    /// chooses: Off on a GPU older than the A14's (the Simulator is no old
    /// phone, so it starts on Automatic).
    static let forThisDevice: Map3DQuality = {
        #if targetEnvironment(simulator)
        return .automatic
        #else
        guard let device = MTLCreateSystemDefaultDevice() else { return .off }
        return startingChoice(gpuFamily: Map3DMetalView.appleFamily(of: device))
        #endif
    }()

    /// Decision 610 續 (review L12-1): the tier of the GPU every 3D view
    /// draws with (``Map3DMetalView/tier(of:)``).
    static let systemDeviceTier: Map3DDeviceTier? = MTLCreateSystemDefaultDevice().flatMap(Map3DMetalView.tier(of:))

    /// Decision 610 續 (review L12-1): whether a scene built now keeps the
    /// real buildings' street fronts: only when the 3D look chosen in
    /// Settings may draw them on this device.
    static var scenesKeepFacades: Bool {
        let chosen = UserDefaults.standard.string(forKey: key).flatMap(Map3DQuality.init(rawValue:)) ?? forThisDevice
        return Map3DRealFacade.mayDraw(quality: chosen.drawn, device: systemDeviceTier)
    }
}

/// Decision 403 (續二): a frame copied out of the 3D map's drawable
/// (``Map3DMetalView/capture(_:)``), read once the GPU has written it.
private final class Map3DCapturedFrame: @unchecked Sendable {
    private let buffer: MTLBuffer
    private let width: Int
    private let height: Int
    private let bytesPerRow: Int

    init(buffer: MTLBuffer, width: Int, height: Int, bytesPerRow: Int) {
        self.buffer = buffer
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
    }

    /// The frame as a picture: the drawable's blue, green, red and an alpha
    /// the opaque layer ignores, in sRGB.
    func image(scale: CGFloat) -> UIImage? {
        let data = Data(bytes: buffer.contents(), count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }
}

// BEGIN NATIVE GLASS PIPELINE — the macOS Metal test compiles this exact block.
private struct Map3DGlassPipeline {
    let pipeline: MTLRenderPipelineState
    let depth: MTLDepthStencilState

    static func make(device: MTLDevice, library: MTLLibrary, vertexDescriptor: MTLVertexDescriptor, samples: Int) -> Map3DGlassPipeline? {
        guard let vertex = library.makeFunction(name: "map3dVertex"),
              let fragment = library.makeFunction(name: "map3dTransparentGlassFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = samples
        descriptor.isAlphaToCoverageEnabled = false
        let colour = descriptor.colorAttachments[0]!
        colour.isBlendingEnabled = true
        colour.rgbBlendOperation = .add
        colour.alphaBlendOperation = .add
        colour.sourceRGBBlendFactor = .sourceAlpha
        colour.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colour.sourceAlphaBlendFactor = .one
        colour.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .greater
        depth.isDepthWriteEnabled = false
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let state = device.makeDepthStencilState(descriptor: depth) else { return nil }
        return Map3DGlassPipeline(pipeline: pipeline, depth: state)
    }
}
// END NATIVE GLASS PIPELINE
