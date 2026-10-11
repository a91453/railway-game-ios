import Foundation

// The 3D city view (ARCHITECTURE decision 152) is jeantimex/tokyo's web
// renderer, built from `Web/CityView` and bundled as the folder
// `Resources/CityView`. A web view cannot run it from `file:` URLs (its
// ES modules, its worker and its `fetch` of the tiles all need a web
// origin), so the app serves the folder over HTTP on the loopback address
// only, and the web view loads it from `http://localhost`. This is the
// part of that server with no networking in it: which file a request asks
// for, and the head of the answer.

/// The areas of the bundled city view, in the settings' order: Kaohsiung
/// Station (decision 152), whose railways are all underground, and
/// Taichung Station (decision 161), whose TRA viaduct shows the trains.
public enum CityViewArea: String, CaseIterable, Identifiable, Sendable {
    case kaohsiung
    case taichung

    public var id: String { rawValue }

    /// The page the app opens for the area, as light as the owner tried it
    /// on an iPhone 17 Pro (a 400 m view, no clouds, no birds, no traffic).
    public var startPath: String {
        "/index.html?area=\(rawValue)&radius=400&clouds=0&birds=0&traffic=0"
    }
}

/// How the app's loopback server answers the city view's requests
/// (decision 152).
public enum CityViewServing {

    /// The file a request's head asks for, relative to the served folder
    /// ("index.html" for the root), or `nil`: not a GET or HEAD, no path,
    /// or a path that would leave the folder (`..`, a hidden file, a
    /// backslash or a NUL). The query and the fragment are dropped.
    public static func file(requestHead: String) -> String? {
        let line = requestHead.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let words = line.split(separator: " ")
        guard words.count == 3, words[0] == "GET" || words[0] == "HEAD", words[2].hasPrefix("HTTP/1.") else { return nil }
        var target = Substring(words[1])
        if let end = target.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            target = target[..<end]
        }
        guard target.hasPrefix("/"), let decoded = String(target).removingPercentEncoding else { return nil }
        let parts = decoded.split(separator: "/", omittingEmptySubsequences: true)
        if parts.isEmpty {
            return "index.html"
        }
        guard parts.allSatisfy({ !$0.hasPrefix(".") && !$0.contains("\\") && !$0.contains("\u{0}") }) else { return nil }
        return parts.joined(separator: "/")
    }

    /// Whether the request only asks for the head (HEAD).
    public static func isHead(_ requestHead: String) -> Bool {
        requestHead.hasPrefix("HEAD ")
    }

    /// The media type of a served file, by its extension.
    public static func contentType(of file: String) -> String {
        let suffix = file.split(separator: ".").last.map { $0.lowercased() } ?? ""
        switch suffix {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }

    /// The head of an answer: `200 OK` with the file's type and length, or
    /// `404 Not Found` (`contentType` nil). Every answer closes its
    /// connection; the web view opens another for the next file.
    public static func responseHead(contentType: String?, length: Int) -> Data {
        var lines = [contentType == nil ? "HTTP/1.1 404 Not Found" : "HTTP/1.1 200 OK"]
        lines.append("Content-Type: \(contentType ?? "text/plain; charset=utf-8")")
        lines.append("Content-Length: \(length)")
        lines.append("Cache-Control: no-cache")
        lines.append("Connection: close")
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }
}
