// Darwin's `mach_task_self_` is a C global: read once a second here, on the
// main actor.
@preconcurrency import Darwin
import Foundation
import GamePresentation
import os
import QuartzCore
import UIKit

/// Decision 421 (V1): keeps the screen's pace on this device for a problem
/// report. The flat map's main thread beats on a display link; the 3D map
/// hands over its frames as they reach the screen, their CPU and GPU time
/// and what they drew (``Map3DMetalView``). Once a second it looks at the
/// game (screen, speed, stations, lines, the 3D look), the memory and the
/// heat. The statistics are ``FrameTimeMeter``'s; a stretch is written to
/// a small file only when it ends (``FrameTimeLog``), never a frame at a
/// time. Nothing leaves the device but in the note the player sends.
@MainActor
final class FrameTimeRecorder: NSObject {
    static let shared = FrameTimeRecorder()
    /// The meter, for the 3D map's GPU and screen times on other threads.
    nonisolated static let meter = FrameTimeMeter(costs: FrameCostMeter.shared)
    nonisolated static let store = FrameTimeStore()

    private weak var session: GameSession?
    private var shows2D = false
    private var shows3D = false
    private var follows = false
    private var active = true
    private var link: CADisplayLink?
    private var lastLook: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
                FrameTimeRecorder.meter.memoryWarning()
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { FrameTimeRecorder.shared.setActive(false) }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { FrameTimeRecorder.shared.setActive(true) }
            },
        ]
    }

    /// The flat map of `session` shows, or (`nil`) no longer.
    func show2D(_ session: GameSession?) {
        if let session { self.session = session }
        shows2D = session != nil
        screenChanged()
    }

    /// The 3D map shows, or no longer.
    func show3D(_ shown: Bool) {
        shows3D = shown
        follows = false
        screenChanged()
    }

    /// The 3D map drew a frame (on the main actor): its CPU time and what
    /// it drew, and whether it follows a train.
    func drew3D(following: Bool, cpuMilliseconds: Double, triangles: Int, drawCalls: Int, chunks: Int) {
        let now = CACurrentMediaTime()
        if following != follows {
            follows = following
            if shows3D { look(at: now, anew: true) }
        }
        Self.meter.drew(cpuMilliseconds: cpuMilliseconds, triangles: triangles, drawCalls: drawCalls, chunks: chunks)
        look(at: now)
    }

    /// A problem report's part: the stretch going on, then those kept.
    func reportText(in language: DisplayLanguage) async -> String? {
        let going = Self.meter.current(at: CACurrentMediaTime())
        return await Task.detached(priority: .utility) {
            FrameTimeRecorder.store.current().reportText(in: language, going: going)
        }.value
    }

    private func setActive(_ isActive: Bool) {
        active = isActive
        screenChanged()
    }

    private var screen: FrameTimeScreen? {
        guard active else { return nil }
        if shows3D { return follows ? .follow3D : .map3D }
        return shows2D ? .map2D : nil
    }

    private func screenChanged() {
        let now = CACurrentMediaTime()
        guard let screen else {
            stopBeat()
            Self.store.add(Self.meter.end(at: now))
            return
        }
        if screen == .map2D { startBeat() } else { stopBeat() }
        look(at: now, anew: true)
    }

    /// Once a second, or `anew` at once: the context (a new stretch when
    /// the screen or speed changed), the memory and the heat.
    private func look(at now: CFTimeInterval, anew: Bool = false) {
        guard anew || now - lastLook >= 1, let screen else { return }
        lastLook = now
        let world = session?.world
        let context = FrameTimeContext(
            screen: screen, speed: world?.clock.speed.rawValue, stations: world?.stations.count ?? 0, lines: world?.lines.count ?? 0,
            map3D: Map3DLoadGovernor.report(UserDefaults.standard.string(forKey: Map3DMetalView.rungKey))
        )
        Self.store.add(Self.meter.update(context, at: now, wall: Date().timeIntervalSince1970))
        Self.meter.memory(footprint: Self.footprint(), available: UInt64(os_proc_available_memory()))
        Self.meter.thermal(Self.heat(ProcessInfo.processInfo.thermalState))
    }

    private func startBeat() {
        guard link == nil else { return }
        FrameCostMeter.shared.keepsFrameParts = true
        let link = CADisplayLink(target: self, selector: #selector(beat(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopBeat() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        FrameCostMeter.shared.keepsFrameParts = false
    }

    /// The flat map's beat: the main thread woke for the next frame.
    @objc private func beat(_ link: CADisplayLink) {
        Self.meter.frame(at: link.timestamp)
        look(at: link.timestamp)
    }

    /// The app's memory as the system counts it against its limit
    /// (`phys_footprint`), or `nil`.
    private static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    private static func heat(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}

/// Decision 421: the stretches kept in `Application Support/Diagnostics`,
/// beside decision 418's file, written on a queue of their own when one
/// ends.
final class FrameTimeStore: Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "frame-time-store", qos: .utility)

    func add(_ segment: FrameTimeSegment?) {
        guard let segment else { return }
        queue.async { [self] in
            lock.withLock {
                var log = Self.read()
                log.add(segment)
                guard let file = Self.file, let data = try? log.encoded() else { return }
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    /// What is kept, for a problem report.
    func current() -> FrameTimeLog {
        lock.withLock { Self.read() }
    }

    private static func read() -> FrameTimeLog {
        guard let file, let data = try? Data(contentsOf: file) else { return FrameTimeLog() }
        return FrameTimeLog.decoded(data)
    }

    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent(FrameTimeLog.fileName)
    }
}
