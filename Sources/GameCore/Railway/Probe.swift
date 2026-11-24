// PROBE (TYMC-QINGPU-FULL): measuring switches. Not for main.
#if canImport(Glibc)
import Glibc
#endif

enum Probe {
    nonisolated(unsafe) static let flags: Set<String> = {
        #if canImport(Glibc)
        guard let raw = getenv("TYMC_X") else { return [] }
        return Set(String(cString: raw).split(separator: ",").map(String.init))
        #else
        return []
        #endif
    }()
    nonisolated(unsafe) static let window: (Int64, Int64)? = {
        #if canImport(Glibc)
        guard let raw = getenv("TYMC_TRACE") else { return nil }
        let parts = String(cString: raw).split(separator: "-").compactMap { Int64($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
        #else
        return nil
        #endif
    }()
    static func on(_ flag: String) -> Bool { flags.contains(flag) }
    nonisolated(unsafe) static let numbers: [String: Int64] = {
        var known: [String: Int64] = [:]
        #if canImport(Glibc)
        for name in ["TYMC_DL", "TYMC_DR"] {
            if let raw = getenv(name), let value = Int64(String(cString: raw)) { known[name] = value }
        }
        #endif
        return known
    }()
    static func number(_ name: String) -> Int64? { numbers[name] }
    nonisolated(unsafe) static var dumped: Set<String> = []
    static func tracing(_ now: Int64) -> Bool { window.map { $0.0 <= now && now <= $0.1 } ?? false }
    static func log(_ text: String) {
        #if canImport(Glibc)
        let line = text + "\n"
        _ = line.withCString { write(2, $0, strlen($0)) }
        #endif
    }
    static func hm(_ seconds: Int64) -> String {
        let m = seconds % 86_400 / 60
        return "d\(seconds / 86_400) \(m / 60 < 10 ? "0" : "")\(m / 60):\(m % 60 < 10 ? "0" : "")\(m % 60)"
    }
}
