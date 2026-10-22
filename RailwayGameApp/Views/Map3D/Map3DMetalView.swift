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
        var drawCalls: Int
        var triangles: Int
        /// Decision 259: the figures and vehicles drawn, and how much
        /// street life the device draws now.
        var people: Int
        var vehicles: Int
        var streetDetail: Map3DStreetDetail
        /// The pixels a point drawn (``Map3DDrawScale``).
        var drawScale: Double
    }

    var camera = Map3DCamera()
    /// Decision 333: the train the camera follows, from behind
    /// (``Map3DFollow``); set with ``follow(_:reduceMotion:)``.
    private(set) var following: Map3DFollow?
    /// Decision 333: the camera flying to the follow view (`to` is `nil`)
    /// or to a still view (`to`), a frame at a time.
    private var flying: (flight: Map3DFlight, to: Map3DCamera?)?
    /// When the follow camera last moved, for how far it turns.
    private var lastFollowStep: CFTimeInterval?
    /// Decision 334: a flight asked for, its goal worked out at the next
    /// frame from the camera as laid out (``fly(reduceMotion:to:)``).
    private var flightAsked: (reduceMotion: Bool, goal: (Map3DCamera) -> Map3DCamera?)?
    /// Decision 334: the train ringed, asked about on a station's board.
    var ringed: TrainID?
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
    /// This frame's light: the hour's, under the weather as far as it has
    /// turned.
    private var shown = Map3DLighting(minute: 12 * 60)
    /// The trains for this frame, seen from the eye given.
    var trains: (@MainActor (Map3DPoint) -> Map3DTrains.Frame)?
    /// Decision 314: this frame's trains' fronts, as the camera sees them,
    /// for their labels.
    var trainHeads: (@MainActor ([Map3DTrains.Head], Map3DCamera) -> Void)?
    /// Decision 259: the people and vehicles for this frame, seen with the
    /// camera given, with the city's lights on so far, at the detail given.
    var streetLife: (@MainActor (Map3DCamera, Float, Map3DStreetDetail) -> Map3DStreetLife.Frame)?
    /// Decision 259: three buffers of their instances, a frame's each in
    /// turn, so none is made each frame; a frame waits for the GPU to be
    /// done with the one it fills.
    private var lifeBuffers: [MTLBuffer] = []
    private var lifeBuffer = 0
    private let lifeInFlight = DispatchSemaphore(value: 3)
    /// Decision 259: how much street life this device draws: by its GPU to
    /// begin with, one step less each time it cannot hold its frame rate.
    private(set) var streetDetail = Map3DStreetDetail.off
    private var slowWindows = 0
    /// 2026-10-21: whether the GPU kept over its budget (``Map3DDrawScale``),
    /// until the map closes, and whether the map draws fewer pixels: for
    /// that, or as the 3D look in Settings, Low Power Mode or the phone's
    /// heat say (``Map3DQuality``).
    private var gpuOverBudget = false
    private var drawsFewerPixels = false
    private var overBudgetWindows = 0
    /// Decision 238's later note: the 3D look chosen in Settings.
    var quality = Map3DQuality.automatic {
        didSet { if quality != oldValue { applyQuality() } }
    }
    /// Decision 352: with Reduce Motion the screens hold one picture;
    /// decision 356: and the water's ripples stand still.
    var reduceMotion = false
    /// Decision 230: the train models, and a buffer of each one's vertices.
    private var models: (pack: Map3DModelPack, buffers: [MTLBuffer])?
    var onStats: (@MainActor (Stats) -> Void)?

    private struct Chunk {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
        /// Decision 238: how many of the indices are its ground, track and
        /// roads, and its city simplified for afar, if it has a city.
        let baseIndexCount: Int
        let far: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        /// Whether it was drawn in full last frame (decision 238's margin).
        var detailed = false
        /// Decision 267: its closest detail, and whether it was drawn last
        /// frame.
        let close: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        var closeUp = false
        /// Decision 232: its shadows, if it has any.
        let shadows: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
        /// Decision 244: its street furniture's instances, sorted by model,
        /// and where each model's run of them starts.
        let props: (instances: MTLBuffer, runs: [(model: Int, first: Int, count: Int)])?
        /// Decision 352: its signs' instances.
        let signs: (instances: MTLBuffer, count: Int)?
        let minimum: Map3DPoint
        let maximum: Map3DPoint
        /// Decision 342: where it is and its city's tops, for the cones
        /// of ``Map3DSeeThrough``.
        let column: Int
        let row: Int
        let cityTops: [Float]
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// Decision 230: the same, each vertex through its car's instance.
    private let instancedPipeline: MTLRenderPipelineState
    /// Decision 342: the city in front of the trains, seen through
    /// (``Map3DSeeThrough``).
    private let seeThroughPipeline: MTLRenderPipelineState
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
    /// Decision 357: the sun's shadow map's pipelines (the chunks, the
    /// street furniture) and depth test; none where they do not load (the
    /// map is drawn with decision 232's shadows alone).
    private var sunDrawing: (chunks: MTLRenderPipelineState, instanced: MTLRenderPipelineState, depth: MTLDepthStencilState)?
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
    private var chunks: [Chunk] = []
    private let gpuTimes = OSAllocatedUnfairLock(initialState: [Double]())
    private var cpuTimes: [Double] = []
    private var waitTimes: [Double] = []
    private var frames = 0
    private var lastStats = CACurrentMediaTime()
    private var lastCounts = (drawCalls: 0, triangles: 0)
    private var lastLife = (people: 0, vehicles: 0)

    /// The view, or `nil` where the device has no Metal or the shaders do
    /// not load.
    static func make() -> Map3DMetalView? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "map3dVertex"),
              let fragmentFunction = library.makeFunction(name: "map3dFragment"),
              let instancedFunction = library.makeFunction(name: "map3dInstancedVertex"),
              let shadowVertex = library.makeFunction(name: "map3dShadowVertex"),
              let shadowFragment = library.makeFunction(name: "map3dShadowFragment"),
              let seeThroughFragment = library.makeFunction(name: "map3dSeeThroughFragment"),
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
        descriptor.isAlphaToCoverageEnabled = false
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
                                  seeThroughPipeline: seeThroughPipeline, shadowPipeline: shadowPipeline, shadowDepthState: shadowDepthState,
                                  depthState: depthState, skyPipeline: skyPipeline, skyDepthState: skyDepthState, surfaces: surfaces)
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
        // Decision 357: the city's depth from the sun, no colour.
        if let sunVertex = library.makeFunction(name: "map3dSunDepthVertex"),
           let sunInstanced = library.makeFunction(name: "map3dSunDepthInstancedVertex") {
            let sun = MTLRenderPipelineDescriptor()
            sun.vertexFunction = sunVertex
            sun.vertexDescriptor = vertexDescriptor
            sun.depthAttachmentPixelFormat = .depth32Float
            let sunDepth = MTLDepthStencilDescriptor()
            sunDepth.depthCompareFunction = .less
            sunDepth.isDepthWriteEnabled = true
            if let chunks = try? device.makeRenderPipelineState(descriptor: sun),
               let depth = device.makeDepthStencilState(descriptor: sunDepth) {
                sun.vertexFunction = sunInstanced
                if let instanced = try? device.makeRenderPipelineState(descriptor: sun) { view.sunDrawing = (chunks, instanced, depth) }
            }
        }
        return view
    }

    private init(
        device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState, instancedPipeline: MTLRenderPipelineState,
        seeThroughPipeline: MTLRenderPipelineState, shadowPipeline: MTLRenderPipelineState, shadowDepthState: MTLDepthStencilState, depthState: MTLDepthStencilState,
        skyPipeline: MTLRenderPipelineState, skyDepthState: MTLDepthStencilState, surfaces: MTLTexture
    ) {
        self.queue = queue
        self.pipeline = pipeline
        self.instancedPipeline = instancedPipeline
        self.seeThroughPipeline = seeThroughPipeline
        self.shadowPipeline = shadowPipeline
        self.shadowDepthState = shadowDepthState
        self.depthState = depthState
        self.skyPipeline = skyPipeline
        self.skyDepthState = skyDepthState
        self.surfaces = surfaces
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        sampleCount = Self.samples
        // Decision 342: reversed depth, 0 the farthest.
        clearDepth = 0
        preferredFramesPerSecond = 60
        streetDetail = Map3DStreetDetail.forGPUFamily(Self.appleFamily(of: device))
        noSunMap = makeSunMap(device: device, side: 1)
        applyQuality()
    }

    /// Decision 357: a depth texture `side` texels square for the sun's
    /// shadow map, cleared to the farthest (nothing in the sun's way).
    private func makeSunMap(device: MTLDevice, side: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: side, height: side, mipmapped: false)
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
              let wanted = Map3DSunShadow.region(target: camera.target, distance: camera.distance, sun: shown.sunDirection, size: plan.size)
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
        let seen = chunks.filter { Map3DCamera.sees(minimum: $0.minimum, maximum: $0.maximum, through: matrix) }
        for chunk in seen {
            let count = chunk.detailed ? chunk.indexCount : chunk.baseIndexCount
            if count > 0 {
                encoder.setVertexBuffer(chunk.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32, indexBuffer: chunk.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += count / 3
            }
            if !chunk.detailed, let far = chunk.far {
                encoder.setVertexBuffer(far.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: far.indexCount, indexType: .uint32, indexBuffer: far.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += far.indexCount / 3
            }
        }
        if let models {
            encoder.setRenderPipelineState(sunDrawing.instanced)
            let leftOut = Map3DProp.modelsLeftOut(quality, in: models.pack)
            for chunk in seen where chunk.detailed {
                guard let props = chunk.props else { continue }
                for run in props.runs where run.model < models.buffers.count && !leftOut.contains(run.model) {
                    encoder.setVertexBuffer(models.buffers[run.model], offset: 0, index: 0)
                    encoder.setVertexBuffer(props.instances, offset: run.first * Self.instanceStride, index: 2)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: models.pack.models[run.model].vertices.count,
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
    private func applyQuality() {
        let process = ProcessInfo.processInfo
        let heat = Map3DQuality.Heat(rawValue: process.thermalState.rawValue) ?? .critical
        let plan = quality.plan(lowPower: process.isLowPowerModeEnabled, heat: heat)
        if preferredFramesPerSecond != plan.framesPerSecond { preferredFramesPerSecond = plan.framesPerSecond }
        sunPlan = Map3DSunShadow.plan(quality, lowPower: process.isLowPowerModeEnabled, heat: heat, overBudget: gpuOverBudget)
        let fewer = plan.fewerPixels || (plan.lowersWhenOver && gpuOverBudget)
        if fewer != drawsFewerPixels {
            drawsFewerPixels = fewer
            setNeedsLayout()
        }
    }

    /// The newest Apple GPU family `device` belongs to, as a number (9 for
    /// `.apple9`), 0 for none.
    private static func appleFamily(of device: MTLDevice) -> Int {
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

    /// Four samples a pixel smooth the thin rails; every iPhone and iPad
    /// takes four.
    private static let samples = 4
    /// An instance's bytes (`Map3DInstance` in `Map3DShaders.metal`): a
    /// matrix and a colour.
    private static let instanceStride = 80

    override func layoutSubviews() {
        super.layoutSubviews()
        // 2026-10-21 (decision 238's later note): fewer pixels once the GPU
        // keeps over its budget.
        let scale = CGFloat(Map3DDrawScale.scale(display: Double(traitCollection.displayScale), lowered: drawsFewerPixels))
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
        guard let current = following, current.train == follow.train else {
            following = follow
            ringed = nil
            flightAsked = nil
            flying = (Map3DFlight(from: camera, began: CACurrentMediaTime(), rule: rule), nil)
            return
        }
        guard current.view != follow.view else { return }
        following?.view = follow.view
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
        guard let following, let head = heads.first(where: { $0.train == following.train }) else { return }
        let elapsed = lastFollowStep.map { now - $0 } ?? 0
        lastFollowStep = now
        if let flight = flying?.flight {
            let goal = following.camera(following: head, from: camera, elapsed: 0, turnsAtOnce: true)
            camera = flight.camera(toward: goal, at: now)
            if flight.isOver(at: now) { flying = nil }
        } else {
            camera = following.camera(following: head, from: camera, elapsed: elapsed)
        }
    }

    /// Decision 230: draws the trains near the eye with `pack`'s models.
    func useModels(_ pack: Map3DModelPack) {
        let buffers = pack.models.compactMap { makeBuffer($0.vertices) }
        guard buffers.count == pack.models.count else { return }
        models = (pack, buffers)
    }

    /// Draws `scene` from now on.
    func show(_ scene: Map3DScene) {
        sunSceneChanged = true
        chunks = scene.chunks.compactMap { chunk in
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
            var close: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int)?
            if let closeVertices = makeBuffer(chunk.close.vertices), let closeIndices = makeBuffer(chunk.close.indices) {
                close = (closeVertices, closeIndices, chunk.close.indices.count)
            }
            var props: (instances: MTLBuffer, runs: [(model: Int, first: Int, count: Int)])?
            let sorted = chunk.props.sorted { $0.model < $1.model }
            if let instances = makeBuffer(sorted.flatMap(\.floats)) {
                var runs: [(model: Int, first: Int, count: Int)] = []
                for (index, instance) in sorted.enumerated() {
                    if let last = runs.last, last.model == instance.model {
                        runs[runs.count - 1].count += 1
                    } else {
                        runs.append((instance.model, index, 1))
                    }
                }
                props = (instances, runs)
            }
            let signs = makeBuffer(chunk.signs.flatMap(\.floats)).map { (instances: $0, count: chunk.signs.count) }
            return Chunk(vertices: vertices, indices: indices, indexCount: chunk.mesh.indices.count, baseIndexCount: chunk.baseIndexCount,
                         far: far, close: close, shadows: shadows, props: props, signs: signs, minimum: chunk.minimum, maximum: chunk.maximum,
                         column: chunk.column, row: chunk.row, cityTops: chunk.cityTops)
        }
    }

    /// Decision 259: the most figures and vehicles a frame draws (the
    /// fullest detail's), and the next of the three buffers for them,
    /// once the GPU is done with it.
    private static let lifeCapacity = Map3DStreetDetail.full.people + Map3DStreetDetail.full.vehicles

    private func nextLifeBuffer() -> MTLBuffer? {
        if lifeBuffers.isEmpty, let device {
            lifeBuffers = (0..<3).compactMap { _ in device.makeBuffer(length: Self.lifeCapacity * Self.instanceStride, options: .storageModeShared) }
        }
        guard lifeBuffers.count == 3 else { return nil }
        lifeInFlight.wait()
        lifeBuffer = (lifeBuffer + 1) % 3
        return lifeBuffers[lifeBuffer]
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
    /// for it, and for a street life buffer the GPU still reads, is
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
        let frame = trains?(camera.eye)
        moveCamera(heads: frame?.heads ?? [], at: start)
        let camera = camera
        let matrix = camera.viewProjection
        // Decision 357: the sun's shadow map, drawn again when it is out
        // of date (before the frame's own pass, in the same command buffer).
        let sunRegion = wantedSunRegion(at: start)
        let uniforms = uniformValues(matrix, seconds: start, sun: sunRegion.drawn)
        var visible: [Chunk] = []
        for index in chunks.indices {
            // Decision 238: in full near the camera, whether in view or not,
            // so the margin holds.
            chunks[index].detailed = camera.wantsDetail(minimum: chunks[index].minimum, maximum: chunks[index].maximum,
                                                        wasDetailed: chunks[index].detailed)
            // Decision 267: and its closest detail, only close up.
            chunks[index].closeUp = chunks[index].detailed && chunks[index].close != nil
                && camera.wantsClose(minimum: chunks[index].minimum, maximum: chunks[index].maximum, wasClose: chunks[index].closeUp)
            if Map3DCamera.sees(minimum: chunks[index].minimum, maximum: chunks[index].maximum, through: matrix) {
                visible.append(chunks[index])
            }
        }
        trainHeads?(frame?.heads ?? [], camera)
        // Decision 342: the cars the city in front of is seen through.
        let seeThrough = Map3DSeeThrough(eye: camera.eye, cars: frame?.cars ?? [], matrix: matrix)
        var trainBoxes: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int, triangles: Int)?
        if let mesh = frame?.boxes, !mesh.isEmpty, let vertices = makeBuffer(mesh.vertices), let indices = makeBuffer(mesh.indices) {
            trainBoxes = (vertices, indices, mesh.indices.count, mesh.triangleCount)
        }
        var trainShadows: (vertices: MTLBuffer, indices: MTLBuffer, indexCount: Int, triangles: Int)?
        if let mesh = frame?.shadows, !mesh.isEmpty, let vertices = makeBuffer(mesh.vertices), let indices = makeBuffer(mesh.indices) {
            trainShadows = (vertices, indices, mesh.indices.count, mesh.triangleCount)
        }
        // Decision 230: the cars near the eye, one draw call a model, every
        // car of it an instance.
        var cars: (sorted: [Map3DInstance], buffer: MTLBuffer)?
        if let instances = frame?.instances, !instances.isEmpty, models != nil {
            let sorted = instances.sorted { $0.model < $1.model }
            if let buffer = makeBuffer(sorted.flatMap(\.floats)) { cars = (sorted, buffer) }
        }
        // Decision 259: the people and vehicles near the target.
        let life = streetLife?(camera, shown.lights, streetDetail)
        var lifeDraw: (sorted: [Map3DInstance], buffer: MTLBuffer)?
        if let instances = life?.instances, !instances.isEmpty, models != nil {
            let waiting = CACurrentMediaTime()
            let buffer = nextLifeBuffer()
            waited += CACurrentMediaTime() - waiting
            if let buffer {
                let sorted = Array(instances.sorted { $0.model < $1.model }.prefix(Self.lifeCapacity))
                let floats = sorted.flatMap(\.floats)
                floats.withUnsafeBytes { bytes in
                    if let base = bytes.baseAddress { buffer.contents().copyMemory(from: base, byteCount: bytes.count) }
                }
                lifeDraw = (sorted, buffer)
            }
        }
        let waiting = CACurrentMediaTime()
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable, let commands = queue.makeCommandBuffer()
        else {
            // The street life buffer taken goes back unused.
            if lifeDraw != nil { lifeInFlight.signal() }
            return
        }
        waited += CACurrentMediaTime() - waiting
        var drawCalls = 0, triangles = 0
        if let redraw = sunRegion.redraw {
            drawSunMap(redraw, commands: commands, drawCalls: &drawCalls, triangles: &triangles)
        }
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            // The street life buffer taken goes back unused, and the sun's
            // map is drawn again next frame.
            if lifeDraw != nil { lifeInFlight.signal() }
            if sunRegion.redraw != nil { sunDrawn = nil }
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setFragmentTexture(surfaces, index: 0)
        encoder.setFragmentTexture(sunRegion.drawn == nil ? noSunMap : sunMap, index: 1)
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
        for chunk in visible {
            // Decision 238: the city in full near the camera; afar, the
            // ground and track, then the city simplified.
            let detailed = chunk.detailed
            // Decision 342: a chunk a cone crosses draws its city apart,
            // seen through in front of the trains.
            let seen = seeThrough.cuts(column: chunk.column, row: chunk.row, tops: chunk.cityTops)
            let count = detailed && !seen ? chunk.indexCount : chunk.baseIndexCount
            if count > 0 {
                encoder.setVertexBuffer(chunk.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32,
                                              indexBuffer: chunk.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += count / 3
            }
            // Decision 267's closest detail (the overhead line among it)
            // stays solid.
            if chunk.closeUp, let close = chunk.close {
                encoder.setVertexBuffer(close.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: close.indexCount, indexType: .uint32,
                                              indexBuffer: close.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += close.indexCount / 3
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
            if !detailed, let far = chunk.far {
                encoder.setVertexBuffer(far.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: far.indexCount, indexType: .uint32,
                                              indexBuffer: far.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += far.indexCount / 3
            }
            if seen { encoder.setRenderPipelineState(pipeline) }
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
                        encoder.setVertexBuffer(buffer, offset: first * Self.instanceStride, index: 2)
                        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: models.pack.models[model].vertices.count,
                                               instanceCount: count)
                        drawCalls += 1
                        triangles += models.pack.models[model].triangleCount * count
                    }
                    first = last + 1
                }
            }
        }
        // Decision 244: the street furniture of the chunks drawn in full,
        // one draw call a model and chunk. Decision 355: Saving leaves the
        // bus stops and vending machines out.
        if let models {
            encoder.setRenderPipelineState(instancedPipeline)
            let leftOut = Map3DProp.modelsLeftOut(quality, in: models.pack)
            for chunk in visible where chunk.detailed {
                guard let props = chunk.props else { continue }
                for run in props.runs where run.model < models.buffers.count && !leftOut.contains(run.model) {
                    encoder.setVertexBuffer(models.buffers[run.model], offset: 0, index: 0)
                    encoder.setVertexBuffer(props.instances, offset: run.first * Self.instanceStride, index: 2)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: models.pack.models[run.model].vertices.count,
                                           instanceCount: run.count)
                    drawCalls += 1
                    triangles += models.pack.models[run.model].triangleCount * run.count
                }
            }
        }
        // Decision 352: the signs of the chunks drawn in full, one draw
        // call a chunk, four corners a sign.
        if let signDrawing, visible.contains(where: { $0.detailed && $0.signs != nil }) {
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
        encoder.setRenderPipelineState(skyPipeline)
        encoder.setDepthStencilState(skyDepthState)
        Map3DSky(shown).floats(camera: camera).withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            encoder.setFragmentBytes(base, length: bytes.count, index: 3)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        drawCalls += 1
        triangles += 1
        // Decision 232: the ground shadows last, over everything drawn.
        encoder.setRenderPipelineState(shadowPipeline)
        encoder.setDepthStencilState(shadowDepthState)
        for chunk in visible {
            guard let shadows = chunk.shadows else { continue }
            encoder.setVertexBuffer(shadows.vertices, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: shadows.indexCount, indexType: .uint32,
                                          indexBuffer: shadows.indices, indexBufferOffset: 0)
            drawCalls += 1
            triangles += shadows.indexCount / 3
        }
        if let shadows = trainShadows {
            encoder.setVertexBuffer(shadows.vertices, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: shadows.indexCount, indexType: .uint32,
                                          indexBuffer: shadows.indices, indexBufferOffset: 0)
            drawCalls += 1
            triangles += shadows.triangles
        }
        encoder.endEncoding()
        let gpuTimes = gpuTimes
        if lifeDraw != nil {
            let inFlight = lifeInFlight
            commands.addCompletedHandler { @Sendable _ in inFlight.signal() }
        }
        commands.addCompletedHandler { @Sendable buffer in
            let seconds = buffer.gpuEndTime - buffer.gpuStartTime
            if seconds > 0 { gpuTimes.withLock { $0.append(seconds) } }
        }
        commands.present(drawable)
        commands.commit()
        lastLife = (life?.people ?? 0, life?.vehicles ?? 0)
        record(cpu: CACurrentMediaTime() - start - waited, wait: waited, drawCalls: drawCalls, triangles: triangles)
    }

    /// The uniforms the shaders read (`Map3DUniforms` in
    /// `Map3DShaders.metal`): the matrix, then the sun's way and light, the
    /// ambient light from the sky and from the ground, the fog's colour,
    /// the eye and where the fog starts and ends (and decision 349's ground
    /// haze, ``Map3DGrade``), and the ground shadows'
    /// strength (decision 232) and how far the city's lights are on, then
    /// the night windows' rules (decision 229 續), then decision 356's
    /// reflections (``Map3DReflection/rows``: off on the saving quality,
    /// the ripples still with Reduce Motion), then decision 357's sun
    /// shadow map (``Map3DSunShadow/rows(_:lighting:)``; with it, decision
    /// 232's shadows fainter). The lights are
    /// `Map3DLighting`'s (`sunLight`, `skyLight`, `groundLight`, `lights`,
    /// `nightWindowRows`), worked out in GamePresentation.
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
            + [Map3DSunShadow.blobStrength(shown, drawn: sun != nil), shown.lights, 0, 0]
            + Map3DLighting.nightWindowRows
            + Map3DReflection.rows(sky: Map3DSky(shown), sunLight: shown.sunLight, quality: quality, seconds: seconds, reduceMotion: reduceMotion)
            + Map3DSunShadow.rows(sun, lighting: shown)
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
            drawCalls: lastCounts.drawCalls,
            triangles: lastCounts.triangles,
            people: lastLife.people,
            vehicles: lastLife.vehicles,
            streetDetail: streetDetail,
            drawScale: Double(contentScaleFactor)
        )
        // Decision 259: a device that cannot hold its frame rate while
        // drawing street life draws less of it.
        let drawingLife = lastLife.people + lastLife.vehicles > 0
        slowWindows = drawingLife && stats.framesPerSecond < Double(preferredFramesPerSecond) * 0.75 ? slowWindows + 1 : 0
        if Map3DStreetDetail.shouldLower(framesPerSecond: stats.framesPerSecond, aim: Double(preferredFramesPerSecond), windows: slowWindows) {
            streetDetail = streetDetail.lowered
            slowWindows = 0
        }
        overBudgetWindows = Map3DDrawScale.isOver(gpuMilliseconds: stats.gpuMilliseconds, aim: Double(preferredFramesPerSecond))
            ? overBudgetWindows + 1 : 0
        if Map3DDrawScale.shouldLower(windows: overBudgetWindows) { gpuOverBudget = true }
        // Low Power Mode and the heat change while the map is open.
        applyQuality()
        frames = 0
        cpuTimes.removeAll()
        waitTimes.removeAll()
        lastStats = now
        onStats?(stats)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }
}
