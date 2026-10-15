import GamePresentation
import MetalKit
import os
import UIKit

/// ARCHITECTURE decision 229: the native 3D map drawn with Metal. It only
/// uploads and draws what GamePresentation works out (``Map3DScene``,
/// ``Map3DTrains``, ``Map3DCamera``, ``Map3DLighting``): one pipeline for the
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
        var gpuMilliseconds: Double
        var drawCalls: Int
        var triangles: Int
    }

    var camera = Map3DCamera()
    var lighting = Map3DLighting(minute: 12 * 60)
    /// The trains for this frame, seen from the eye given.
    var trains: (@MainActor (Map3DPoint) -> Map3DTrains.Frame)?
    /// Decision 230: the train models, and a buffer of each one's vertices.
    private var models: (pack: Map3DModelPack, buffers: [MTLBuffer])?
    var onStats: (@MainActor (Stats) -> Void)?

    private struct Chunk {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
        let minimum: Map3DPoint
        let maximum: Map3DPoint
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// Decision 230: the same, each vertex through its car's instance.
    private let instancedPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var chunks: [Chunk] = []
    private let gpuTimes = OSAllocatedUnfairLock(initialState: [Double]())
    private var cpuTimes: [Double] = []
    private var frames = 0
    private var lastStats = CACurrentMediaTime()
    private var lastCounts = (drawCalls: 0, triangles: 0)

    /// The view, or `nil` where the device has no Metal or the shaders do
    /// not load.
    static func make() -> Map3DMetalView? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "map3dVertex"),
              let fragmentFunction = library.makeFunction(name: "map3dFragment"),
              let instancedFunction = library.makeFunction(name: "map3dInstancedVertex")
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
              let depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
        else { return nil }
        return Map3DMetalView(device: device, queue: queue, pipeline: pipeline, instancedPipeline: instancedPipeline, depthState: depthState)
    }

    private init(
        device: MTLDevice, queue: MTLCommandQueue, pipeline: MTLRenderPipelineState, instancedPipeline: MTLRenderPipelineState,
        depthState: MTLDepthStencilState
    ) {
        self.queue = queue
        self.pipeline = pipeline
        self.instancedPipeline = instancedPipeline
        self.depthState = depthState
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        depthStencilPixelFormat = .depth32Float
        sampleCount = Self.samples
        clearDepth = 1
        preferredFramesPerSecond = 60
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
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
            return Chunk(vertices: vertices, indices: indices, indexCount: chunk.mesh.indices.count, minimum: chunk.minimum, maximum: chunk.maximum)
        }
    }

    private func makeBuffer<Element>(_ array: [Element]) -> MTLBuffer? {
        guard !array.isEmpty, let device else { return nil }
        return array.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
        }
    }

    override func draw(_ rect: CGRect) {
        let start = CACurrentMediaTime()
        let sky = Self.rgb(lighting.sky)
        clearColor = MTLClearColor(red: Double(sky.0), green: Double(sky.1), blue: Double(sky.2), alpha: 1)
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let matrix = camera.viewProjection
        let uniforms = uniformValues(matrix)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        uniforms.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            encoder.setVertexBytes(base, length: bytes.count, index: 1)
            encoder.setFragmentBytes(base, length: bytes.count, index: 1)
        }
        var drawCalls = 0, triangles = 0
        for chunk in chunks where Map3DCamera.sees(minimum: chunk.minimum, maximum: chunk.maximum, through: matrix) {
            encoder.setVertexBuffer(chunk.vertices, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: chunk.indexCount, indexType: .uint32,
                                          indexBuffer: chunk.indices, indexBufferOffset: 0)
            drawCalls += 1
            triangles += chunk.indexCount / 3
        }
        let frame = trains?(camera.eye)
        if let mesh = frame?.boxes, !mesh.isEmpty, let vertices = makeBuffer(mesh.vertices), let indices = makeBuffer(mesh.indices) {
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indices.count, indexType: .uint32,
                                          indexBuffer: indices, indexBufferOffset: 0)
            drawCalls += 1
            triangles += mesh.triangleCount
        }
        // Decision 230: the cars near the eye, one draw call a model, every
        // car of it an instance.
        if let instances = frame?.instances, !instances.isEmpty, let models {
            let sorted = instances.sorted { $0.model < $1.model }
            if let buffer = makeBuffer(sorted.flatMap(\.floats)) {
                encoder.setRenderPipelineState(instancedPipeline)
                var first = 0
                while first < sorted.count {
                    let model = sorted[first].model
                    var last = first
                    while last + 1 < sorted.count, sorted[last + 1].model == model { last += 1 }
                    let count = last - first + 1
                    encoder.setVertexBuffer(models.buffers[model], offset: 0, index: 0)
                    encoder.setVertexBuffer(buffer, offset: first * Self.instanceStride, index: 2)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: models.pack.models[model].vertices.count,
                                           instanceCount: count)
                    drawCalls += 1
                    triangles += models.pack.models[model].triangleCount * count
                    first = last + 1
                }
            }
        }
        encoder.endEncoding()
        let gpuTimes = gpuTimes
        commands.addCompletedHandler { @Sendable buffer in
            let seconds = buffer.gpuEndTime - buffer.gpuStartTime
            if seconds > 0 { gpuTimes.withLock { $0.append(seconds) } }
        }
        commands.present(drawable)
        commands.commit()
        record(cpu: CACurrentMediaTime() - start, drawCalls: drawCalls, triangles: triangles)
    }

    /// The uniforms the shaders read (`Map3DUniforms` in
    /// `Map3DShaders.metal`): the matrix, then the sun's way and light, the
    /// ambient light from the sky and from the ground, the fog's colour,
    /// the eye and where the fog starts and ends. The keyframes' strengths
    /// are three.js's; scaled here so the noon sun on a roof comes to about
    /// white, with the colours as they are (no tone mapping).
    private func uniformValues(_ matrix: Map3DMatrix) -> [Float] {
        let sun = Self.rgb(lighting.sun), sky = Self.rgb(lighting.sky), ground = Self.rgb(lighting.ground)
        let sunScale = lighting.sunStrength * 0.16
        let ambient = lighting.ambient * 0.5
        func tinted(_ colour: (Float, Float, Float), _ share: Float, _ scale: Float) -> [Float] {
            [(1 + (colour.0 - 1) * share) * scale, (1 + (colour.1 - 1) * share) * scale, (1 + (colour.2 - 1) * share) * scale, 0]
        }
        let eye = camera.eye
        let far = camera.depthRange.far
        return matrix.columns
            + [lighting.sunDirection.x, lighting.sunDirection.y, lighting.sunDirection.z, 0]
            + [sun.0 * sunScale, sun.1 * sunScale, sun.2 * sunScale, 0]
            + tinted(sky, 0.3, ambient)
            + tinted(ground, 0.5, ambient * 0.8)
            + [sky.0, sky.1, sky.2, 0]
            + [eye.x, eye.y, eye.z, 1]
            + [camera.distance * 1.6, far * 0.9, 0, 0]
    }

    private static func rgb(_ colour: PopTravel.RGB) -> (Float, Float, Float) {
        (Float(colour.red) / 255, Float(colour.green) / 255, Float(colour.blue) / 255)
    }

    private func record(cpu: Double, drawCalls: Int, triangles: Int) {
        frames += 1
        cpuTimes.append(cpu)
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
            gpuMilliseconds: Self.median(gpu) * 1_000,
            drawCalls: lastCounts.drawCalls,
            triangles: lastCounts.triangles
        )
        frames = 0
        cpuTimes.removeAll()
        lastStats = now
        onStats?(stats)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.sorted()[values.count / 2]
    }
}
