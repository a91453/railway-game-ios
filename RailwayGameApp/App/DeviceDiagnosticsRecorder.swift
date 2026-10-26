import Foundation
import GamePresentation
import MetricKit

/// Decision 418: keeps what the system records about this app's freezes
/// and exits (MetricKit) in a file of its own, in Application Support, for
/// a problem report to carry (``ProblemReportRows``). What is kept, and
/// how little, is ``DeviceDiagnostics``'s; this only receives and saves.
/// Nothing leaves the device but in the note the player sends.
///
/// The system delivers on a queue of its own, about once a day for the
/// day's metrics and, from iOS 15, soon after a diagnostic; a lock keeps
/// two deliveries from writing at once.
final class DeviceDiagnosticsRecorder: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = DeviceDiagnosticsRecorder()

    private let lock = NSLock()

    /// Starts receiving, and reads what the system delivered since the
    /// last start (the file keeps each once).
    func start() {
        let manager = MXMetricManager.shared
        manager.add(self)
        let diagnostics = manager.pastDiagnosticPayloads.map { $0.jsonRepresentation() }
        let metrics = manager.pastPayloads.map { $0.jsonRepresentation() }
        guard !diagnostics.isEmpty || !metrics.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            self.record(diagnostics: diagnostics, metrics: metrics)
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        record(diagnostics: payloads.map { $0.jsonRepresentation() }, metrics: [])
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        record(diagnostics: [], metrics: payloads.map { $0.jsonRepresentation() })
    }

    private func record(diagnostics: [Data], metrics: [Data]) {
        guard !diagnostics.isEmpty || !metrics.isEmpty else { return }
        update { kept in
            for json in diagnostics { kept.record(diagnostics: json) }
            for json in metrics { kept.record(metrics: json) }
        }
    }

    /// What is kept, for a problem report; empty when nothing is.
    func current() -> DeviceDiagnostics {
        lock.withLock { Self.read() }
    }

    private func update(_ change: (inout DeviceDiagnostics) -> Void) {
        lock.withLock {
            var diagnostics = Self.read()
            let before = diagnostics
            change(&diagnostics)
            guard diagnostics != before, let file = Self.file, let data = try? diagnostics.encoded() else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private static func read() -> DeviceDiagnostics {
        guard let file, let data = try? Data(contentsOf: file) else { return DeviceDiagnostics() }
        return DeviceDiagnostics.decoded(data)
    }

    /// Application Support/Diagnostics/device-diagnostics.json: the app's
    /// own file, apart from the saves.
    private static var file: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent(DeviceDiagnostics.fileName)
    }
}
