import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// LONG-NAMES (decision 882's later note): every real station's board, in
/// its system's style with the most a board can hold beside its name (its
/// number and two other lines' numbers), sets its name within the face,
/// narrowed before it is made smaller, and none smaller than
/// ``minimumShare`` of its line's height.
@MainActor
final class PlatformNameBoardLongNamesTests: XCTestCase {
    typealias Builder = Map3DScene.Builder
    typealias Props = Map3DPlatformProps

    /// The smallest share of its wanted height a line may be set at.
    static let minimumShare: Float = 0.5

    nonisolated static let everywhere: RealRailways.Loaded = RealRailways.load(overseas: Set(OverseasMap.allCases), pack: HongKongRailwaysTests.pack) { name, ext in
        try BundledRealData.file(name, ext)
    }

    /// Each real station's board, worst case, and the lines it set.
    static func boards() throws -> [(station: String, lines: [Props.BoardLine])] {
        let railways = try XCTUnwrap(everywhere.railways)
        var found: [(String, [Props.BoardLine])] = []
        let out = Map3DPoint(0, 0, -1)
        for station in railways.stations {
            let system = station.system.id
            let english = station.english.map(RealRailways.Station.shown)
            var name = station.chinese, second = english, reading: String?
            let style = Props.boardStyles[system]
            if let japanese = Map3DJapaneseNameBoards.systems[system]?[station.chinese] {
                name = japanese.japanese
                reading = japanese.kana
            }
            if style == .finnish { name = english ?? name; second = nil }
            let numbered = Props.boardNumberSystems[system] != nil || Map3DJapaneseNameBoards.systems[system] != nil
            let styled = style.map { style in
                Props.StyledBoard(style: style, reading: reading, number: numbered ? "BL12" : nil, colour: 0,
                                  transfers: numbered ? [Props.Badge(number: "R10", colour: 0), Props.Badge(number: "O12", colour: 0)] : [])
            }
            var mesh = Map3DMesh()
            let lines = Builder.addNameBoard(&mesh, foot: Map3DPoint(0, 0, 0), out: out, name: name, second: second, styled: styled,
                                             underground: true)
            found.append(("\(system) \(name)", lines))
        }
        return found
    }

    func testEveryStationsNameFitsItsBoard() throws {
        let boards = try Self.boards()
        XCTAssertGreaterThan(boards.count, 600)
        var worst: [(String, String, Float)] = []
        for (station, lines) in boards {
            XCTAssertFalse(lines.isEmpty, station)
            for line in lines {
                XCTAssertLessThanOrEqual(line.width, line.span + 0.001, "\(station): \(line.text)")
                XCTAssertGreaterThanOrEqual(line.cellWidth, line.cellHeight * Props.nameBoardNarrowest - 0.0001, "\(station): \(line.text)")
                worst.append((station, line.text, line.cellHeight / line.wanted))
                XCTAssertGreaterThanOrEqual(line.cellHeight / line.wanted, Self.minimumShare, "\(station): \(line.text)")
            }
        }
        if ProcessInfo.processInfo.environment["LONG_NAMES_REPORT"] != nil {
            for (station, text, share) in worst.sorted(by: { $0.2 < $1.2 }).prefix(30) { print("LONG", station, "|", text, share) }
        }
    }

    /// The longest names drawn, for the preview.
    func testWriteTheLongNamesPreview() throws {
        guard let path = ProcessInfo.processInfo.environment["LONG_NAMES_PREVIEW"] else { throw XCTSkip("preview only") }
        typealias Sample = (name: String, second: String?, styled: Props.StyledBoard?)
        func metro(_ number: String?, _ colour: UInt32, reading: String? = nil, _ transfers: [Props.Badge] = []) -> Props.StyledBoard {
            Props.StyledBoard(style: .metro, reading: reading, number: number, colour: Map3DColor.rgb(colour), transfers: transfers)
        }
        let samples: [Sample] = [
            ("體育大學站", "National Taiwan Sport University Station", metro("A7", 0x8246AF)),
            ("台北海洋大學", "Taipei University of Marine Technology", metro("V28", 0xFF2A00)),
            ("南港展覽館", "Taipei Nangang Exhibition Center", metro("BR24", 0xC48C31, [Props.Badge(number: "BL23", colour: Map3DColor.rgb(0x0070BD))])),
            ("台北101/世貿", "Taipei 101/World Trade Center", metro("R03", 0xE3002C)),
            ("馬出九大病院前", "Maidashi-Kyudaibyoinmae", metro("H04", 0x0077CC, reading: "まいだしきゅうだいびょういんまえ")),
            ("耕莘安康院區", "Cardinal Tien Hospital An Kang Branch", metro("K04", 0x9E925E)),
        ]
        let out = Map3DPoint(0, 0, -1)
        let boards = samples.map { sample -> [String: Any] in
            var board = Map3DMesh()
            Builder.addNameBoard(&board, foot: Map3DPoint(0, 0, 0), out: out, name: sample.name, second: sample.second,
                                 styled: sample.styled, underground: true)
            return PlatformNameBoardStylesTests.json(board)
        }
        try JSONSerialization.data(withJSONObject: boards).write(to: URL(fileURLWithPath: path))
    }
}
