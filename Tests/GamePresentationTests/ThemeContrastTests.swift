import Foundation
import XCTest

/// UI review 2026-10-28, C: the app's colours (`RailwayGameApp/Views/
/// Theme.swift`, read as text: the app's target does not build on Linux)
/// keep WCAG AA, 4.5:1, for text on the colours it sits on, in light and
/// dark; and no view puts white text on a status colour, which is pale in
/// dark (white on dark `error` #FF9B9B is about 2:1).
final class ThemeContrastTests: XCTestCase {
    private static let views = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("RailwayGameApp/Views")

    /// Each `static let name = dynamic(light: 0x…, dark: 0x…)` at full
    /// opacity, and `primary` from the `AccentColor` asset.
    private func colours() throws -> [String: (light: UInt32, dark: UInt32)] {
        let source = try String(contentsOf: Self.views.appendingPathComponent("Theme.swift"), encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #"static let (\w+) = dynamic\(light: 0x([0-9A-F]{6}), dark: 0x([0-9A-F]{6})\)"#)
        var found: [String: (UInt32, UInt32)] = [:]
        for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let part = { (index: Int) in String(source[Range(match.range(at: index), in: source)!]) }
            found[part(1)] = (UInt32(part(2), radix: 16)!, UInt32(part(3), radix: 16)!)
        }
        let asset = Self.views.deletingLastPathComponent()
            .appendingPathComponent("Resources/Assets.xcassets/AccentColor.colorset/Contents.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: asset)) as? [String: Any])
        let entries = try XCTUnwrap(json["colors"] as? [[String: Any]])
        let rgb = entries.map { entry -> (UInt32, Bool) in
            let components = (entry["color"] as? [String: Any])?["components"] as? [String: String] ?? [:]
            let channel = { (key: String) in UInt32(components[key]!.dropFirst(2), radix: 16)! }
            return (channel("red") << 16 | channel("green") << 8 | channel("blue"), entry["appearances"] != nil)
        }
        found["primary"] = (try XCTUnwrap(rgb.first { !$0.1 }).0, try XCTUnwrap(rgb.first { $0.1 }).0)
        return found
    }

    private func luminance(_ rgb: UInt32) -> Double {
        func linear(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.040_45 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb >> 16 & 0xFF) + 0.7152 * linear(rgb >> 8 & 0xFF) + 0.0722 * linear(rgb & 0xFF)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testTextOnAColourKeepsAA() throws {
        let colours = try colours()
        let pairs = colours.keys.filter { $0.hasPrefix("on") }.sorted()
        XCTAssertEqual(pairs, ["onAccent", "onError", "onPrimary"])
        for on in pairs {
            let base = on.dropFirst(2).prefix(1).lowercased() + on.dropFirst(3)
            let text = try XCTUnwrap(colours[on]), fill = try XCTUnwrap(colours[base], base)
            XCTAssertGreaterThanOrEqual(contrast(text.light, fill.light), 4.5, "\(on) on \(base), light")
            XCTAssertGreaterThanOrEqual(contrast(text.dark, fill.dark), 4.5, "\(on) on \(base), dark")
        }
        // What the review measured: white on dark error.
        XCTAssertLessThan(contrast(0xFFFFFF, try XCTUnwrap(colours["error"]).dark), 4.5)
    }

    /// No white text on a status or theme fill: it is the `on…` colour's
    /// place. A `.white` within the few lines before such a fill is the
    /// same view's text.
    func testNoWhiteTextOnAThemeFill() throws {
        let fill = try NSRegularExpression(pattern: #"(fill|background)\((Capsule\(\)\.fill\()?Theme\.(error|warning|success|primary|accent)\b"#)
        let files = try FileManager.default.subpathsOfDirectory(atPath: Self.views.path).filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let lines = try String(contentsOf: Self.views.appendingPathComponent(file), encoding: .utf8)
                .components(separatedBy: "\n")
            for (index, line) in lines.enumerated()
            where fill.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                let before = lines[max(0, index - 4)...index]
                XCTAssertFalse(
                    before.contains { $0.contains("foregroundStyle(.white)") || $0.contains("foregroundColor(.white)") },
                    "\(file):\(index + 1): white text on a theme fill; use its on… colour"
                )
            }
        }
    }
}
