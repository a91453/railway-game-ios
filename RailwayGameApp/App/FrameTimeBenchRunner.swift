import Foundation
import GameCore
import GamePresentation
import Observation
import QuartzCore
import UIKit

/// Decision 421 (V2): runs one scenario of the fixed test of the screen's
/// pace (``FrameTimeBench``), from the test builds' hidden entry in
/// Settings. It opens the game the scenario names, lets it settle, then
/// moves the camera along the scenario's path for a minute while
/// ``FrameTimeRecorder`` times the frames, and keeps the stretch as a run
/// (``FrameTimeBenchResults``). The game screen shows its progress and
/// carries out what it asks (``FrameTimeBenchOverlay``).
@MainActor
@Observable
final class FrameTimeBenchRunner {
    static let shared = FrameTimeBenchRunner()
    nonisolated static let store = FrameTimeBenchStore()

    enum Phase: Equatable {
        /// The game is being made and its lines laid.
        case preparing
        /// The game runs a few seconds before it is timed.
        case settling
        /// Timed, since this time on the frames' clock.
        case measuring(since: CFTimeInterval)
        /// Done: the run kept, or `nil` when too few frames were timed.
        case done(FrameTimeBenchRun?)
        case failed
    }

    struct Running: Equatable {
        let scenario: FrameTimeBench.Scenario
        var phase: Phase
    }

    private(set) var running: Running?
    /// Runs since the app started: the first is after a cold start.
    @ObservationIgnored private var runsSinceLaunch = 0
    /// What the game screen does for a run: opens the 3D map and moves
    /// the 2D map's camera.
    @ObservationIgnored var open3D: (@MainActor () -> Void)?
    @ObservationIgnored var close3D: (@MainActor () -> Void)?
    @ObservationIgnored var camera2D: (@MainActor () -> PlanCamera?)?
    @ObservationIgnored var move2D: (@MainActor (PlanCamera) -> Void)?
    /// The 3D map's view while it is open (``Map3DView``).
    @ObservationIgnored weak var view3D: Map3DMetalView?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var start2D: PlanCamera?
    @ObservationIgnored private var start3D: Map3DCamera?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Starts `scenario` in a new game from `launcher`.
    func run(_ scenario: FrameTimeBench.Scenario, launcher: GameLauncher) {
        stop()
        running = Running(scenario: scenario, phase: .preparing)
        task = Task { await carryOut(scenario, launcher: launcher) }
    }

    /// Ends a run early, or puts away a finished one's card.
    func stop() {
        task?.cancel()
        task = nil
        stopMoving()
        running = nil
    }

    private func carryOut(_ scenario: FrameTimeBench.Scenario, launcher: GameLauncher) async {
        guard let session = await launcher.openFrameTimeBench(lines: scenario.lines), !Task.isCancelled else {
            if !Task.isCancelled { running?.phase = .failed }
            return
        }
        session.setSpeed(.normal)
        running?.phase = .settling
        // The game screen opens on the new game first.
        try? await Task.sleep(for: .seconds(1))
        if scenario.view != .pan2D {
            if scenario.view == .follow3D, let train = FrameTimeBench.followed(in: session.world) {
                session.followTrain(train)
            }
            open3D?()
            // The 3D map's scene is built off the main thread first.
            for _ in 0..<60 where view3D == nil {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        try? await Task.sleep(for: .seconds(FrameTimeBench.settleSeconds))
        guard !Task.isCancelled else { return }
        FrameTimeRecorder.shared.restart()
        let since = CACurrentMediaTime()
        running?.phase = .measuring(since: since)
        startMoving(scenario.view)
        try? await Task.sleep(for: .seconds(FrameTimeBench.seconds))
        guard !Task.isCancelled else { return }
        let segment = FrameTimeRecorder.shared.snapshot()
        stopMoving()
        let run = segment.map {
            FrameTimeBenchRun(scenario: scenario, device: Self.device, simulator: Self.isSimulator, cold: runsSinceLaunch == 0, segment: $0)
        }
        runsSinceLaunch += 1
        if let run { Self.store.add(run) }
        // The result's card is on the game screen, under the 3D map.
        if scenario.view != .pan2D { close3D?() }
        running?.phase = .done(run)
    }

    private func startMoving(_ view: FrameTimeBench.View) {
        start2D = view == .pan2D ? camera2D?() : nil
        start3D = view == .orbit3D ? view3D?.camera : nil
        let link = CADisplayLink(target: LinkTarget { [weak self] link in self?.move(link) }, selector: #selector(LinkTarget.fire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopMoving() {
        link?.invalidate()
        link = nil
        start2D = nil
        start3D = nil
    }

    /// Each frame: the camera where the scenario's path has it.
    private func move(_ link: CADisplayLink) {
        guard case .measuring(let since)? = running?.phase else { return }
        let seconds = link.timestamp - since
        if let start2D { move2D?(FrameTimeBench.camera2D(from: start2D, at: seconds)) }
        if let start3D { view3D?.camera = FrameTimeBench.camera3D(from: start3D, at: seconds) }
    }

    /// The device's model identifier ("iPhone17,1"), the Simulator's of the
    /// device it plays.
    nonisolated static let device: String = {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    nonisolated static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

/// A display link's target (the link keeps it), calling back each frame
/// on the main run loop.
@MainActor
private final class LinkTarget: NSObject {
    let tick: @MainActor (CADisplayLink) -> Void

    init(_ tick: @escaping @MainActor (CADisplayLink) -> Void) {
        self.tick = tick
    }

    @objc func fire(_ link: CADisplayLink) {
        tick(link)
    }
}

/// Decision 421 (V2): the test's runs kept in `Application Support/Diagnostics`,
/// beside the frame time record.
final class FrameTimeBenchStore: Sendable {
    private let lock = NSLock()

    func add(_ run: FrameTimeBenchRun) {
        change { $0.add(run) }
    }

    func clear(device: String) {
        change { $0.clear(device: device) }
    }

    func current() -> FrameTimeBenchResults {
        lock.withLock { Self.read() }
    }

    private func change(_ body: (inout FrameTimeBenchResults) -> Void) {
        lock.withLock {
            var results = Self.read()
            body(&results)
            guard let file = Self.file, let data = try? results.encoded() else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private static func read() -> FrameTimeBenchResults {
        guard let file, let data = try? Data(contentsOf: file) else { return FrameTimeBenchResults() }
        return FrameTimeBenchResults.decoded(data)
    }

    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent(FrameTimeBenchResults.fileName)
    }
}
