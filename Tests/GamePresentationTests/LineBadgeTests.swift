import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 216: a line's code and the colour-blind-safe palette.
final class LineBadgeTests: XCTestCase {
    private func line(_ id: Int, color: Int? = nil, code: String? = nil) throws -> ServiceLine {
        var json = #"{"id": \#(id), "name": "L\#(id)", "stops": [1, 2], "window": "allDay", "trainsInService": {"peak": 0, "offPeak": 0, "low": 0}"#
        if let color { json += #", "color": \#(color)"# }
        if let code { json += #", "code": "\#(code)""# }
        return try JSONDecoder().decode(ServiceLine.self, from: Data((json + "}").utf8))
    }

    func testEveryPresetAndAutomaticColourHasItsOwnLetters() {
        for color in LineColor.presets.map(\.rgb) + LineBadge.automaticColors {
            XCTAssertNotNil(LineBadge.namedCodes[color], String(color, radix: 16))
        }
        XCTAssertEqual(LineBadge.automaticCode(rgb: 0x42A5F5), "BL")
        XCTAssertEqual(LineBadge.automaticCode(rgb: 0xEF5350), "R")
        XCTAssertEqual(LineBadge.automaticCode(rgb: 0xA1887F), "BR")
        // The app's six own colours are six codes.
        XCTAssertEqual(Set(LineBadge.automaticColors.map(LineBadge.automaticCode(rgb:))).count, 6)
    }

    func testAnyOtherColourIsNamedByItsHue() {
        XCTAssertEqual(LineBadge.hueCode(rgb: 0xE3002C), "R")  // Taipei's Tamsui–Xinyi line
        XCTAssertEqual(LineBadge.hueCode(rgb: 0x0070BD), "BL")  // Bannan
        XCTAssertEqual(LineBadge.hueCode(rgb: 0x008659), "G")  // Songshan–Xindian
        XCTAssertEqual(LineBadge.hueCode(rgb: 0xF8B61C), "O")  // Zhonghe–Xinlu
        XCTAssertEqual(LineBadge.hueCode(rgb: 0x8C5A1E), "BR")
        XCTAssertEqual(LineBadge.hueCode(rgb: 0xFFDB00), "Y")  // Circular
        XCTAssertEqual(LineBadge.hueCode(rgb: 0x8246AF), "P")  // Taoyuan Airport MRT
        XCTAssertEqual(LineBadge.hueCode(rgb: 0xFAFAFA), "W")
        XCTAssertEqual(LineBadge.hueCode(rgb: 0x808080), "GY")
        XCTAssertEqual(LineBadge.hueCode(rgb: 0x101010), "K")
    }

    func testCodesAreTheLinesOwnOrNumberedAfterTheFirst() throws {
        let lines = [
            try line(1, color: 0xEF5350),
            try line(2, color: 0xEF5350),
            try line(3, color: 0x42A5F5, code: "R3"),
            try line(4, color: 0xEF5350),
            try line(5),
            try line(6, color: 0x42A5F5, code: "R3"),
        ]
        let codes = LineBadge.codes(for: lines)
        XCTAssertEqual(codes[LineID(rawValue: 1)], "R")
        XCTAssertEqual(codes[LineID(rawValue: 2)], "R2")
        // A code the player gave is never given to another line...
        XCTAssertEqual(codes[LineID(rawValue: 3)], "R3")
        XCTAssertEqual(codes[LineID(rawValue: 4)], "R4")
        // ...though two lines the player gave the same keep it.
        XCTAssertEqual(codes[LineID(rawValue: 6)], "R3")
        // No colour: the app's own for line 5, red.
        XCTAssertEqual(LineBadge.automaticColor(of: LineID(rawValue: 5)), 0xD93D3D)
        XCTAssertEqual(codes[LineID(rawValue: 5)], "R5")
    }

    func testTypedCodesAreReadLeniently() {
        XCTAssertEqual(LineBadge.code(from: "bl")?.text, "BL")
        XCTAssertEqual(LineBadge.code(from: " R 2 ")?.text, "R2")
        XCTAssertEqual(LineBadge.code(from: "ＢＬ１")?.text, "BL1")
        XCTAssertEqual(LineBadge.code(from: "ｂｌ")?.text, "BL")
        XCTAssertNil(LineBadge.code(from: "ABCD"))
        XCTAssertNil(LineBadge.code(from: "板南"))
        XCTAssertNil(LineBadge.code(from: ""))
        XCTAssertTrue(LineBadge.isBlank(" \u{3000}"))
        XCTAssertFalse(LineBadge.isBlank(" a"))
    }

    func testTheSafePaletteKeepsTheAppsOwnColoursApart() {
        XCTAssertEqual(LinePalette.safeColors.count, 8)
        let safe = Set(LinePalette.safeColors)
        for color in LineColor.presets.map(\.rgb) + LineBadge.automaticColors + [0x123456, 0xFAFAFA] {
            XCTAssertTrue(safe.contains(LinePalette.safeColor(for: color)), String(color, radix: 16))
            XCTAssertEqual(LinePalette.standard.color(for: color), color)
        }
        XCTAssertEqual(Set(LineBadge.automaticColors.map(LinePalette.safeColor(for:))).count, 6)
        // Every safe colour is somebody's.
        XCTAssertEqual(Set(LineColor.presets.map { LinePalette.safeColor(for: $0.rgb) }), safe)
        XCTAssertEqual(LinePalette.colourBlindSafe.color(for: 0xEF5350), 0xD55E00)
    }
}
