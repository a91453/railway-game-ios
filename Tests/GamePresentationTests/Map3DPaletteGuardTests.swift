import Foundation
@testable import GamePresentation
import XCTest

/// Decision 891: the 3D map's colours come from ``Map3DPalette``. The
/// owner's old models brought into the game are drawn in its colours, and
/// no colour written in GamePresentation outside it may be new: those
/// there were on 2026-11-20 are listed in `tools/palette-guard/baseline.txt`,
/// which may only shrink.
final class Map3DPaletteGuardTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let sources = root.appendingPathComponent("Sources/GamePresentation")
    static let baselineFile = root.appendingPathComponent("tools/palette-guard/baseline.txt")

    /// Each GamePresentation source file's name and text, sorted by name.
    static func sourceFiles() throws -> [(name: String, text: String)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") }.sorted()
        return try names.map { ($0, try String(contentsOf: sources.appendingPathComponent($0), encoding: .utf8)) }
    }

    /// The `enum Map3DPalette { … }` and `extension Map3DPalette { … }`
    /// blocks of `text`, their braces matched.
    static func paletteBlocks(_ text: String) -> [Range<String.Index>] {
        var blocks: [Range<String.Index>] = []
        let pattern = try! NSRegularExpression(pattern: #"(public )?(enum|extension) Map3DPalette \{"#)
        let whole = NSRange(text.startIndex..., in: text)
        for match in pattern.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text) else { continue }
            var depth = 1
            var index = range.upperBound
            while depth > 0, index < text.endIndex {
                if text[index] == "{" { depth += 1 } else if text[index] == "}" { depth -= 1 }
                index = text.index(after: index)
            }
            blocks.append(range.lowerBound..<index)
        }
        return blocks
    }

    static func hexes(_ pattern: String, in text: Substring) -> [String] {
        let expression = try! NSRegularExpression(pattern: pattern)
        let string = String(text)
        return expression.matches(in: string, range: NSRange(string.startIndex..., in: string)).compactMap {
            Range($0.range(at: 1), in: string).map { string[$0].uppercased() }
        }
    }

    /// Every colour (`0xRRGGBB`) written in a ``Map3DPalette`` block.
    static func paletteHexes(_ files: [(name: String, text: String)]) -> Set<String> {
        var palette = Set<String>()
        for file in files {
            for block in paletteBlocks(file.text) {
                palette.formUnion(hexes(#"0x([0-9A-Fa-f]{6})\b"#, in: file.text[block]))
            }
        }
        return palette
    }

    /// "File.swift RRGGBB" for each colour written as `rgb(0x…)` or
    /// `rgbColor(0x…)` outside the palette's blocks and not the palette's.
    static func looseColours(_ files: [(name: String, text: String)], palette: Set<String>) -> Set<String> {
        var loose = Set<String>()
        for file in files {
            var rest = file.text
            for block in paletteBlocks(file.text).reversed() { rest.removeSubrange(block) }
            for hex in hexes(#"\brgb(?:Color)?\(0x([0-9A-Fa-f]{6})\)"#, in: rest[...]) where !palette.contains(hex) {
                loose.insert("\(file.name) \(hex)")
            }
        }
        return loose
    }

    func testNoColourOutsideThePaletteIsNew() throws {
        let files = try Self.sourceFiles()
        XCTAssertGreaterThan(files.count, 100)
        let palette = Self.paletteHexes(files)
        XCTAssertGreaterThan(palette.count, 100)
        let loose = Self.looseColours(files, palette: palette)
        let baseline = Set(try String(contentsOf: Self.baselineFile, encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("#") })
        let added = loose.subtracting(baseline).sorted()
        XCTAssertEqual(added, [], """
            Colours not in Map3DPalette: use one of its colours, or add the colour to \
            Map3DPalette with its reason (decision 891). Never add them to tools/palette-guard/baseline.txt.
            """)
        let gone = baseline.subtracting(loose).sorted()
        XCTAssertEqual(gone, [], "No longer in the sources: remove these lines from tools/palette-guard/baseline.txt.")
    }

    /// The owner's old models in the game (decision 891's list) are drawn
    /// in the palette's colours only.
    func testTheOldModelsAreInThePalette() throws {
        let palette = Set(Self.paletteHexes(try Self.sourceFiles()).map { Map3DColor.rgb(UInt32($0, radix: 16)!) })
        func check(_ colours: [UInt32], _ what: String, file: StaticString = #filePath, line: UInt = #line) {
            let off = colours.filter { !palette.contains($0) }.map { String($0, radix: 16) }
            XCTAssertEqual(off, [], "\(what): colours not in Map3DPalette", file: file, line: line)
        }
        // The red commuter car e752e7a2; its glass is the trains' own.
        check(Map3DRedCommuter.meshPalette.filter { $0 != Map3DTrainStyle.glass }, "red commuter car")
        check(Map3DSunMoonLandmark.materialColours, "Sun Moon Lake landmarks")
        check(Map3DOldIslandModule.parts.map(\.colour), "old island module and platform furniture")
        check([Map3DPlatformProps.nameBoardGreen], "platform name board")
        // Fukuoka Tower is drawn in the landmarks' materials.
        check(Map3DHongKongLandmark.materialColours, "landmark materials (Fukuoka Tower)")
        typealias Prop = Map3DSceneryProp
        check([Prop.bunkerBrick, Prop.bunkerStone, Prop.bunkerSteel, Prop.bunkerCoal, Prop.bunkerWood], "coal bunker")
    }
}
