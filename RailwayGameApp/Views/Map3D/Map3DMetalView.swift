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
    }

    var camera = Map3DCamera()
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
        let minimum: Map3DPoint
        let maximum: Map3DPoint
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// Decision 230: the same, each vertex through its car's instance.
    private let instancedPipeline: MTLRenderPipelineState
    /// Decision 232: the ground shadows, blended over what is drawn,
    /// tested against the depth but not writing it.
    private let shadowPipeline: MTLRenderPipelineState
    private let shadowDepthState: MTLDepthStencilState
    private let depthState: MTLDepthStencilState
    /// Decision 231: the surfaces' textures, one layer each.
    private let surfaces: MTLTexture
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
              let shadowFragment = library.makeFunction(name: "map3dShadowFragment")
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
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        descriptor.vertexFunction = instancedFunction
        guard let instancedPipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let depthState = device.makeDepthStencilState(descriptor: depthDescriptor),
              let surfaces = makeSurfaces(device: device, queue: queue)
        else { return nil }
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
        shadowDepthDescriptor.depthCompareFunction = .lessEqual
        shadowDepthDescriptor.isDepthWriteEnabled = false
        guard let shadowPipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let shadowDepthState = device.makeDepthStencilState(descriptor: shadowDepthDescriptor)
        else { return nil }
        return Map3DMetalView(device: device, queue: queue, pipeline: pipeline, instancedPipeline: instancedPipeline,
                              shadowPipeline: shadowPipeline, shadowDepthState: shadowDepthState, depthState: depthState, surfaces: surfaces)
    }

    private init(
        device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState, instancedPipeline: MTLRenderPipelineState,
        shadowPipeline: MTLRenderPipelineState, shadowDepthState: MTLDepthStencilState, depthState: MTLDepthStencilState, surfaces: MTLTexture
    ) {
        self.queue = queue
        self.pipeline = pipeline
        self.instancedPipeline = instancedPipeline
        self.shadowPipeline = shadowPipeline
        self.shadowDepthState = shadowDepthState
        self.depthState = depthState
        self.surfaces = surfaces
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        sampleCount = Self.samples
        clearDepth = 1
        preferredFramesPerSecond = 60
        streetDetail = Map3DStreetDetail.forGPUFamily(Self.appleFamily(of: device))
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
        camera.viewport = (Float(max(bounds.width, 1)), Float(max(bounds.height, 1)))
    }

    /// Decision 230: draws the trains near the eye with `pack`'s models.
    func useModels(_ pack: Map3DModelPack) {
        let buffers = pack.models.compactMap { makeBuffer($0.vertices) }
        guard buffers.count == pack.models.count else { return }
        models = (pack, buffers)
    }

    /// Draws `scene` from now on.
    func show(_ scene: Map3DScene) {
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
            return Chunk(vertices: vertices, indices: indices, indexCount: chunk.mesh.indices.count, baseIndexCount: chunk.baseIndexCount,
                         far: far, close: close, shadows: shadows, props: props, minimum: chunk.minimum, maximum: chunk.maximum)
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
        let camera = camera
        let matrix = camera.viewProjection
        let uniforms = uniformValues(matrix)
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
        let frame = trains?(camera.eye)
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
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else {
            // The street life buffer taken goes back unused.
            if lifeDraw != nil { lifeInFlight.signal() }
            return
        }
        waited += CACurrentMediaTime() - waiting
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setFragmentTexture(surfaces, index: 0)
        uniforms.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            encoder.setVertexBytes(base, length: bytes.count, index: 1)
            encoder.setFragmentBytes(base, length: bytes.count, index: 1)
        }
        var drawCalls = 0, triangles = 0
        for chunk in visible {
            // Decision 238: the city in full near the camera; afar, the
            // ground and track, then the city simplified.
            let detailed = chunk.detailed
            let count = detailed ? chunk.indexCount : chunk.baseIndexCount
            if count > 0 {
                encoder.setVertexBuffer(chunk.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: count, indexType: .uint32,
                                              indexBuffer: chunk.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += count / 3
            }
            if chunk.closeUp, let close = chunk.close {
                encoder.setVertexBuffer(close.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: close.indexCount, indexType: .uint32,
                                              indexBuffer: close.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += close.indexCount / 3
            }
            if !detailed, let far = chunk.far {
                encoder.setVertexBuffer(far.vertices, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: far.indexCount, indexType: .uint32,
                                              indexBuffer: far.indices, indexBufferOffset: 0)
                drawCalls += 1
                triangles += far.indexCount / 3
            }
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
        // one draw call a model and chunk.
        if let models {
            encoder.setRenderPipelineState(instancedPipeline)
            for chunk in visible where chunk.detailed {
                guard let props = chunk.props else { continue }
                for run in props.runs where run.model < models.buffers.count {
                    encoder.setVertexBuffer(models.buffers[run.model], offset: 0, index: 0)
                    encoder.setVertexBuffer(props.instances, offset: run.first * Self.instanceStride, index: 2)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: models.pack.models[run.model].vertices.count,
                                           instanceCount: run.count)
                    drawCalls += 1
                    triangles += models.pack.models[run.model].triangleCount * run.count
                }
            }
        }
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
    /// the eye and where the fog starts and ends, and the ground shadows'
    /// strength (decision 232) and how far the city's lights are on, then
    /// the night windows' rules (decision 229 續). The lights are
    /// `Map3DLighting`'s (`sunLight`, `skyLight`, `groundLight`, `lights`,
    /// `nightWindowRows`), worked out in GamePresentation.
    private func uniformValues(_ matrix: Map3DMatrix) -> [Float] {
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
            + [camera.distance * 1.6 * fog.near, far * 0.9 * fog.far, 0, 0]
            + [Map3DShadow.strength(shown), shown.lights, 0, 0]
            + Map3DLighting.nightWindowRows
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
            streetDetail: streetDetail
        )
        // Decision 259: a device that cannot hold its frame rate while
        // drawing street life draws less of it.
        let drawingLife = lastLife.people + lastLife.vehicles > 0
        slowWindows = drawingLife && stats.framesPerSecond < Double(preferredFramesPerSecond) * 0.75 ? slowWindows + 1 : 0
        if Map3DStreetDetail.shouldLower(framesPerSecond: stats.framesPerSecond, aim: Double(preferredFramesPerSecond), windows: slowWindows) {
            streetDetail = streetDetail.lowered
            slowWindows = 0
        }
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
