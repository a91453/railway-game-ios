import Foundation
import GamePresentation
import XCTest

/// Decision 418: what the system recorded about freezes and exits, read
/// from its payloads' JSON, kept within bounds and written into a problem
/// report. The samples follow the format Apple documents for
/// `MXDiagnosticPayload` and `MXMetricPayload`; they are made up, no
/// player's.
final class DeviceDiagnosticsTests: XCTestCase {
    /// A hang of 1.5 s on 25 October, attributed to the main thread (the
    /// second stack). As MetricKit gives it, the root is the outermost
    /// frame (where the thread starts) and each frame's sub-frames what it
    /// called; SwiftUI called two of the game's functions, and the one
    /// with more samples is followed, into the kernel.
    static let hangPayload = """
        {
          "timeStampBegin": "2026-10-25 21:00:00 +0000",
          "timeStampEnd": "2026-10-25 21:03:00 +0000",
          "hangDiagnostics": [{
            "version": "1.0.0",
            "diagnosticMetaData": {
              "appVersion": "0.5.0", "appBuildVersion": "87.1", "osVersion": "iPhone OS 26.0 (23A341)",
              "deviceType": "iPhone18,1", "platformArchitecture": "arm64e", "regionFormat": "TW", "hangDuration": "1.5 sec"
            },
            "callStackTree": {
              "callStackPerThread": true,
              "callStacks": [
                {"threadAttributed": false, "callStackRootFrames": [
                  {"binaryUUID": "AAAA", "binaryName": "libsystem_pthread.dylib", "address": 7000, "offsetIntoBinaryTextSegment": 100, "sampleCount": 1}
                ]},
                {"threadAttributed": true, "callStackRootFrames": [
                  {"binaryUUID": "D1D1", "binaryName": "dyld", "address": 7487020808, "offsetIntoBinaryTextSegment": 257799, "sampleCount": 30, "subFrames": [
                    {"binaryUUID": "1C2B3D4E-0000-1111-2222-333344445555", "binaryName": "RailwayGame", "address": 4388203176,
                     "offsetIntoBinaryTextSegment": 28327, "sampleCount": 30, "subFrames": [
                      {"binaryUUID": "9F9F", "binaryName": "SwiftUI", "address": 6888720936, "offsetIntoBinaryTextSegment": 1051175,
                       "sampleCount": 30, "subFrames": [
                        {"binaryUUID": "1C2B3D4E-0000-1111-2222-333344445555", "binaryName": "RailwayGame", "address": 4389000000,
                         "offsetIntoBinaryTextSegment": 825151, "sampleCount": 5},
                        {"binaryUUID": "1C2B3D4E-0000-1111-2222-333344445555", "binaryName": "RailwayGame", "address": 4389455436,
                         "offsetIntoBinaryTextSegment": 1280587, "sampleCount": 25, "subFrames": [
                          {"binaryUUID": "8E8E", "binaryName": "libsystem_kernel.dylib", "address": 8195677412, "offsetIntoBinaryTextSegment": 3300,
                           "sampleCount": 25, "subFrames": [
                            {"address": 18446744005239342152, "offsetIntoBinaryTextSegment": 18503, "sampleCount": 25}
                          ]}
                        ]}
                      ]}
                    ]}
                  ]}
                ]}
              ]
            }
          }]
        }
        """

    /// A crash and a CPU exception, on 24 October.
    static let crashPayload = """
        {
          "timeStampBegin": "2026-10-24 08:00:00 +0000",
          "timeStampEnd": "2026-10-24 08:10:00 +0000",
          "crashDiagnostics": [{
            "diagnosticMetaData": {
              "appVersion": "0.5.0", "appBuildVersion": "86.1", "osVersion": "iPhone OS 26.0 (23A341)",
              "exceptionType": 1, "exceptionCode": 0, "signal": 11, "terminationReason": "Namespace SIGNAL, Code 11"
            },
            "callStackTree": {"callStacks": [{"threadAttributed": true, "callStackRootFrames": [
              {"binaryUUID": "1C2B", "binaryName": "RailwayGame", "address": 4345298128, "offsetIntoBinaryTextSegment": 261328}
            ]}]}
          }],
          "cpuExceptionDiagnostics": [{
            "diagnosticMetaData": {"totalCPUTime": "90 sec", "totalSampledTime": "180 sec"},
            "callStackTree": {"callStacks": []}
          }]
        }
        """

    /// A day of exits and the freezes' lengths.
    static let metricPayload = """
        {
          "timeStampBegin": "2026-10-24 21:00:00 +0000",
          "timeStampEnd": "2026-10-25 20:59:00 +0000",
          "appVersion": "0.5.0",
          "applicationExitMetrics": {
            "foregroundExitData": {
              "cumulativeNormalAppExitCount": 3, "cumulativeMemoryResourceLimitExitCount": 1, "cumulativeBadAccessExitCount": 0,
              "cumulativeAbnormalExitCount": 0, "cumulativeIllegalInstructionExitCount": 0, "cumulativeAppWatchdogExitCount": 2
            },
            "backgroundExitData": {
              "cumulativeNormalAppExitCount": 0, "cumulativeMemoryPressureExitCount": 5, "cumulativeSuspendedWithLockedFileExitCount": 0
            }
          },
          "applicationResponsivenessMetrics": {
            "histogrammedAppHangTime": {"histogramNumBuckets": 3, "histogramValue": {
              "1": {"bucketStart": "500 ms", "bucketEnd": "1000 ms", "bucketCount": 1},
              "0": {"bucketStart": "250 ms", "bucketEnd": "500 ms", "bucketCount": 4},
              "2": {"bucketStart": "1000 ms", "bucketEnd": "2000 ms", "bucketCount": 0}
            }}
          },
          "cellularConditionMetrics": {"cellConditionTime": {"histogramNumBuckets": 0, "histogramValue": {}}}
        }
        """

    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testAHangKeepsItsTimeLengthAndTheAttributedThreadsHeaviestPath() throws {
        var diagnostics = DeviceDiagnostics()
        diagnostics.record(diagnostics: data(Self.hangPayload))
        XCTAssertEqual(diagnostics.events.count, 1)
        let hang = try XCTUnwrap(diagnostics.events.first)
        XCTAssertEqual(hang.kind, .hang)
        XCTAssertEqual(hang.duration, 1.5)
        XCTAssertEqual(hang.app, "0.5.0 (87.1)")
        XCTAssertEqual(hang.system, "iPhone OS 26.0 (23A341)")
        // Innermost first, the kernel's frame left out.
        XCTAssertEqual(hang.frames.map(\.binary), ["libsystem_kernel.dylib", "RailwayGame", "SwiftUI", "RailwayGame", "dyld"])
        XCTAssertEqual(hang.frames[1], .init(binary: "RailwayGame", uuid: "1C2B3D4E-0000-1111-2222-333344445555", address: 4389455436, offset: 1280587))
        XCTAssertEqual(hang.framesLeft, 0)

        let text = try XCTUnwrap(diagnostics.reportText(in: .english))
        XCTAssertEqual(text, """
            Freezes and exits recorded on this device:
            Froze 1.50 s at 2026-10-25 21:03:00 UTC (0.5.0 (87.1), iPhone OS 26.0 (23A341))
              0 libsystem_kernel.dylib 0x1e8801ce4 +0xce4 8E8E
              1 RailwayGame 0x105a1c64c +0x138a4b 1C2B3D4E-0000-1111-2222-333344445555
              2 SwiftUI 0x19a998a28 +0x100a27 9F9F
              3 RailwayGame 0x1058eaaa8 +0x6ea7 1C2B3D4E-0000-1111-2222-333344445555
              4 dyld 0x1be42df08 +0x3ef07 D1D1
            """)
        XCTAssertTrue(try XCTUnwrap(diagnostics.reportText(in: .traditionalChinese)).contains("2026-10-25 21:03:00 UTC 卡住 1.50 s"))
    }

    func testCrashesAndExitsReadTheirReasonsAndTheNewestComesFirst() throws {
        var diagnostics = DeviceDiagnostics()
        diagnostics.record(diagnostics: data(Self.crashPayload))
        diagnostics.record(diagnostics: data(Self.hangPayload))
        diagnostics.record(metrics: data(Self.metricPayload))
        XCTAssertEqual(diagnostics.events.map(\.kind), [.hang, .crash, .cpu])
        XCTAssertEqual(diagnostics.events[1].detail, "EXC_BAD_ACCESS (1), SIGSEGV (11), code 0, Namespace SIGNAL, Code 11")
        XCTAssertEqual(diagnostics.events[2].detail, "CPU 90 sec / 180 sec")

        let day = try XCTUnwrap(diagnostics.days.first)
        XCTAssertEqual(day.foreground, [
            "cumulativeNormalAppExitCount": 3, "cumulativeMemoryResourceLimitExitCount": 1, "cumulativeAppWatchdogExitCount": 2,
        ])
        XCTAssertEqual(day.background, ["cumulativeMemoryPressureExitCount": 5])
        XCTAssertEqual(day.hangs, [.init(start: "250 ms", end: "500 ms", count: 4), .init(start: "500 ms", end: "1000 ms", count: 1)])

        let text = try XCTUnwrap(diagnostics.reportText(in: .english))
        XCTAssertTrue(text.contains("Closed unexpectedly at 2026-10-24 08:10:00 UTC: EXC_BAD_ACCESS (1)"), text)
        XCTAssertTrue(text.hasSuffix("""
            Exits 2026-10-24 21:00:00 UTC – 2026-10-25 20:59:00 UTC: on screen: normal 3, over the memory limit 1, stuck too long (watchdog) 2; in the background: reclaimed for memory 5.
            Freezes that day by length: 250 ms–500 ms ×4, 500 ms–1000 ms ×1.
            """), text)
        let chinese = try XCTUnwrap(diagnostics.reportText(in: .traditionalChinese))
        XCTAssertTrue(chinese.contains("畫面上：正常 3、超過記憶體上限 1、卡太久被系統結束 2；背景：被系統收回記憶體 5。"), chinese)
    }

    func testThePastPayloadsReadAgainAddNothingAndADayIsReplaced() throws {
        var diagnostics = DeviceDiagnostics()
        diagnostics.record(diagnostics: data(Self.hangPayload))
        diagnostics.record(metrics: data(Self.metricPayload))
        let once = diagnostics
        diagnostics.record(diagnostics: data(Self.hangPayload))
        diagnostics.record(metrics: data(Self.metricPayload))
        XCTAssertEqual(diagnostics, once)

        // Not a payload, or another app's format: nothing, and nothing lost.
        diagnostics.record(diagnostics: data("not json"))
        diagnostics.record(metrics: data("{\"metaData\": {}}"))
        diagnostics.record(diagnostics: data("{\"hangDiagnostics\": 3}"))
        XCTAssertEqual(diagnostics, once)

        // What the file holds reads back the same; a broken file reads as empty.
        XCTAssertEqual(DeviceDiagnostics.decoded(try diagnostics.encoded()), diagnostics)
        XCTAssertEqual(DeviceDiagnostics.decoded(data("{")), DeviceDiagnostics())
        XCTAssertNil(DeviceDiagnostics().reportText(in: .english))
    }

    func testOnlyTheNewestAreKeptAndLongStacksAreCut() throws {
        var diagnostics = DeviceDiagnostics()
        // A stack deeper than is kept: 60 frames, the root outermost, each
        // calling the next.
        var frame = "{\"binaryUUID\": \"U\", \"binaryName\": \"B\", \"address\": 59, \"offsetIntoBinaryTextSegment\": 0}"
        for depth in (0..<59).reversed() {
            frame = "{\"binaryUUID\": \"U\", \"binaryName\": \"B\", \"address\": \(depth), \"offsetIntoBinaryTextSegment\": 0, \"subFrames\": [\(frame)]}"
        }
        for day in 1...20 {
            let stamp = String(format: "2026-10-%02d 12:00:00 +0000", day)
            diagnostics.record(diagnostics: data("""
                {"timeStampEnd": "\(stamp)", "hangDiagnostics": [{"diagnosticMetaData": {"hangDuration": "\(day * 100) ms"},
                 "callStackTree": {"callStacks": [{"threadAttributed": true, "callStackRootFrames": [\(frame)]}]}}]}
                """))
            diagnostics.record(metrics: data("""
                {"timeStampBegin": "\(stamp)", "timeStampEnd": "\(stamp)", "applicationExitMetrics": {"foregroundExitData": {"cumulativeNormalAppExitCount": \(day)}}}
                """))
        }
        XCTAssertEqual(diagnostics.events.count, DeviceDiagnostics.mostEvents)
        XCTAssertEqual(diagnostics.events.first?.duration, 2.0, "the newest, 20 October")
        XCTAssertEqual(diagnostics.events.last?.duration, 0.9, "the twelfth newest, 9 October")
        XCTAssertEqual(diagnostics.events[0].frames.count, DeviceDiagnostics.mostFrames)
        XCTAssertEqual(diagnostics.events[0].frames.first?.address, 59, "the innermost first")
        XCTAssertEqual(diagnostics.events[0].frames.last?.address, UInt64(60 - DeviceDiagnostics.mostFrames))
        XCTAssertEqual(diagnostics.events[0].framesLeft, 60 - DeviceDiagnostics.mostFrames)
        XCTAssertEqual(diagnostics.days.map { $0.foreground["cumulativeNormalAppExitCount"] }, [20, 19, 18])
        XCTAssertLessThanOrEqual(try diagnostics.encoded().count, DeviceDiagnostics.mostBytes)

        let text = try XCTUnwrap(diagnostics.reportText(in: .english))
        XCTAssertEqual(text.components(separatedBy: "\n").filter { $0.hasPrefix("Froze") }.count, DeviceDiagnostics.shownEvents)
        XCTAssertTrue(text.contains("  … 12 more frames further out\n"), text)
        XCTAssertTrue(text.contains("\n7 older ones not shown.\n"), text)
        XCTAssertTrue(text.contains("on screen: normal 20; in the background: none."), text)
    }

    func testDurationsAsTheSystemWritesThem() {
        XCTAssertEqual(DeviceDiagnostics.Event.Kind.hang.rawValue, "hang")
        var diagnostics = DeviceDiagnostics()
        for (text, _) in [("1,250 ms", 1.25), ("2 min", 120.0), ("forever", 0)] {
            diagnostics.record(diagnostics: data("{\"hangDiagnostics\": [{\"diagnosticMetaData\": {\"hangDuration\": \"\(text)\"}}]}"))
        }
        XCTAssertEqual(diagnostics.events.map(\.duration), [1.25, 120, nil])
        XCTAssertEqual(diagnostics.events.last?.detail, "forever", "a length it cannot read is kept as written")
        XCTAssertEqual(diagnostics.events.first?.time, nil)
    }
}
