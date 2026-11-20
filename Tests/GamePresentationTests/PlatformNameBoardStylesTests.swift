import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// FUKUOKA-NAME-BOARDS and NAME-BOARD-STYLES (decision 882's later
/// notes): each system's platform name boards in its own style: a metro's
/// with the station's number and the line's colour (a Japanese one's with
/// its Japanese name and reading), Finland's white on blue.
@MainActor
final class PlatformNameBoardStylesTests: XCTestCase {
    typealias Builder = Map3DScene.Builder
    typealias Props = Map3DPlatformProps

    /// Every station of the pack's three lines has its board, with the
    /// numbers the pack's stations carry, and every letter of it is drawn.
    func testEveryStationHasItsBoardWithThePacksNumbers() throws {
        let table = try XCTUnwrap(Map3DJapaneseNameBoards.systems["fksubway"])
        let root = try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)).root
        let data = try Data(contentsOf: root.appendingPathComponent("track_stations.geojson"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var numbers: [String: Set<String>] = [:]
        for feature in try XCTUnwrap(json["features"] as? [[String: Any]]) {
            let properties = try XCTUnwrap(feature["properties"] as? [String: Any])
            numbers[try XCTUnwrap(properties["name"] as? String), default: []].insert(try XCTUnwrap(properties["code"] as? String))
        }
        XCTAssertEqual(Set(table.keys), Set(numbers.keys))
        for (name, station) in table {
            XCTAssertEqual(Set(station.numbers), numbers[name], name)
            for character in station.japanese + station.kana + station.numbers.joined() {
                XCTAssertNotNil(Map3DBoardGlyphs.glyphs[character], "\(name): \(character)")
            }
        }
        // The Japanese names are the pack's own.
        let names = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("station_names.json"))) as? [String: Any]
        let systems = try XCTUnwrap(names?["systems"] as? [String: Any])
        let fk = try XCTUnwrap(systems["fksubway"] as? [String: [String: String]])
        for (name, station) in table { XCTAssertEqual(fk[name]?["ja"], station.japanese, name) }
    }

    static func signs(_ session: GameSession, buying lines: [String]? = nil) throws -> [String: Map3DBoardSign] {
        for line in session.buyableRealLines where lines?.contains(line.id) ?? true {
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), "\(line.id): \(session.message?.text ?? "")")
        }
        let world = session.world, railways = try XCTUnwrap(session.railways)
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        var byName: [String: Map3DBoardSign] = [:]
        for (id, sign) in Builder.boardSigns(world, railways, frame) { byName[try XCTUnwrap(world.station(id: id)).name] = sign }
        return byName
    }

    /// On a game of Fukuoka's map every station has a Japanese sign, its
    /// English name the pack's, and the platform of each line gets that
    /// line's number and colour.
    func testFukuokasStationsGetTheirSigns() throws {
        let signs = try Self.signs(FukuokaRailwaysTests.fukuoka())
        XCTAssertEqual(signs.count, 36)
        let hakata = try XCTUnwrap(signs["博多"])
        let k = try XCTUnwrap(hakata.board(realLine: "fksubway:K")), n = try XCTUnwrap(hakata.board(realLine: "fksubway:N"))
        XCTAssertEqual(k.name, "博多")
        XCTAssertEqual(k.second, "Hakata")
        XCTAssertEqual(k.board, Props.StyledBoard(style: .metro, reading: "はかた", number: "K11", colour: Map3DColor.rgb(0xFF4500),
                                                  transfers: [Props.Badge(number: "N18", colour: Map3DColor.rgb(0x008000))]))
        XCTAssertEqual(n.board.transfers.map(\.number), ["K11"])
        XCTAssertEqual(n.board.number, "N18")
        XCTAssertEqual(n.board.colour, Map3DColor.rgb(0x008000))
        XCTAssertEqual(hakata.board(realLine: nil)?.board.number, "K11")
        XCTAssertEqual(try XCTUnwrap(signs["中洲川端"]).board(realLine: "fksubway|H")?.board.number, "H01")
        XCTAssertEqual(try XCTUnwrap(signs["姪濱"]).board(realLine: "fksubway:K")?.name, "姪浜")
    }

    /// Taipei's metro: an interchange's number on each line's platform
    /// (Da'an's BR09 and R05), the Chinese name with the English under it.
    func testTaipeisMetroBoardsCarryEachLinesNumber() throws {
        let signs = try Self.signs(RealLineAcquisitionTests.game(round: "trtc:BR"), buying: ["trtc:BR"])
        let daan = try XCTUnwrap(signs["大安"])
        let brown = try XCTUnwrap(daan.board(realLine: "trtc:BR"))
        XCTAssertEqual(brown.name, "大安")
        XCTAssertEqual(brown.second, "Daan")
        XCTAssertEqual(brown.board.number, "BR09")
        XCTAssertNil(brown.board.reading)
        XCTAssertEqual(brown.board.colour, Map3DColor.rgb(0xC48C31))
        XCTAssertEqual(brown.board.transfers, [Props.Badge(number: "R05", colour: Map3DColor.rgb(0xE3002C))])
        XCTAssertEqual(daan.board(realLine: "trtc:R")?.board.number, "R05")
        XCTAssertEqual(daan.board(realLine: "trtc:R")?.board.transfers.map(\.number), ["BR09"])
        XCTAssertEqual(daan.board(realLine: "trtc:R_XBT")?.board.number, "R05")
        XCTAssertEqual(try XCTUnwrap(signs["忠孝復興"]).board(realLine: "trtc:BL")?.board.number, "BL15")
        // The railway's platforms keep decision 882's board.
        XCTAssertNil(daan.board(realLine: "tra:WL"))
    }

    /// Kaohsiung's metro: its line ids (`KR`, `KO`) are not its numbers'
    /// letters (`R`, `O`); its light rail's are (`C`).
    func testKaohsiungsMetroBoardsFindTheirLinesNumbers() throws {
        let signs = try Self.signs(RealLineAcquisitionTests.game(round: "krtc:C"), buying: ["krtc:C"])
        XCTAssertEqual(try XCTUnwrap(signs["籬仔內"]).board(realLine: "krtc:C")?.board.number, "C1")
        let transfers = try XCTUnwrap(BundledRealData.railways().transfers)
        let formosa = try XCTUnwrap(transfers.station(inSystem: "KRTC", named: "美麗島", near: RealRailways.Coordinate(latitude: 22.6313, longitude: 120.3020)))
        let numbers = transfers.stations(inSystem: "KRTC", named: "美麗島", near: formosa.coordinate).map(\.stationId)
        XCTAssertEqual(Set(numbers), ["O5", "R10"])
        let sign = Map3DBoardSign(boards: ["krtc": .init(style: .metro, name: "美麗島", second: "Formosa Boulevard", reading: nil, numbers: numbers,
                                                         colours: ["KR": 1, "KO": 2, "C": 3])], fallback: "krtc")
        XCTAssertEqual(sign.board(realLine: "krtc:KO")?.board.number, "O5")
        XCTAssertEqual(sign.board(realLine: "krtc:KO")?.board.colour, 2)
        XCTAssertEqual(sign.board(realLine: "krtc:KR")?.board.number, "R10")
        // TRANSFER-BADGES: each platform's board shows the other line's number too.
        XCTAssertEqual(sign.board(realLine: "krtc:KO")?.board.transfers, [Props.Badge(number: "R10", colour: 1)])
        XCTAssertEqual(sign.board(realLine: "krtc:KR")?.board.transfers, [Props.Badge(number: "O5", colour: 2)])
        XCTAssertEqual(sign.board(realLine: nil)?.board.colour, numbers.first == "O5" ? 2 : 1)
    }

    /// Hong Kong's: the MTR's Chinese and English names and the line's
    /// colour, no number (its platforms show none).
    func testHongKongsBoardsAreTheMTRs() throws {
        let signs = try Self.signs(HongKongMapTests.hongKong())
        XCTAssertFalse(signs.isEmpty)
        for sign in signs.values {
            let board = try XCTUnwrap(sign.board(realLine: nil) ?? sign.boards.first.map { (key, _) in sign.board(realLine: "\(key):X") } ?? nil)
            XCTAssertEqual(board.board.style, .metro)
            XCTAssertNil(board.board.number)
        }
        XCTAssertTrue(signs.values.contains { $0.board(realLine: nil)?.second != nil }, "the English names")
    }

    /// Lapland's: Finland's white on blue, the Finnish name alone.
    func testLaplandsBoardsAreFinlands() throws {
        let signs = try Self.signs(RovaniemiRailwaysTests.rovaniemi())
        let rovaniemi = try XCTUnwrap(signs["羅瓦涅米"]?.board(realLine: "vr:KJA"))
        XCTAssertEqual(rovaniemi.name, "Rovaniemi")
        XCTAssertNil(rovaniemi.second)
        XCTAssertEqual(rovaniemi.board.style, .finnish)
    }

    /// A Japanese board: its band and number in the line's colour, the
    /// number's letters in white, the reading, name and English name in
    /// ink over the band, all on the face.
    func testAJapaneseBoardIsLaidOut() throws {
        let colour = Map3DColor.rgb(0xFF4500)
        let styled = Props.StyledBoard(style: .metro, reading: "はかた", number: "K11", colour: colour)
        var mesh = Map3DMesh(), plain = Map3DMesh()
        let out = Map3DPoint(0, 0, -1)
        Builder.addNameBoard(&mesh, foot: Map3DPoint(0, 0, 0), out: out, name: "博多", second: "Hakata", styled: styled, underground: true)
        Builder.addNameBoard(&plain, foot: Map3DPoint(0, 0, 0), out: out, name: "博多", second: "Hakata", underground: true)
        XCTAssertFalse(mesh.vertices.contains { $0.color == Props.nameBoardGreen })
        let faceLow = Props.nameBoardFoot + Props.nameBoardFrame
        let faceHeight = Props.nameBoardHeight - 2 * Props.nameBoardFrame
        let bandTop = faceLow + faceHeight * Props.metroBand
        let coloured = mesh.vertices.filter { $0.color == colour }
        // The band along the bottom and the number's square at the left.
        XCTAssertTrue(coloured.contains { abs($0.y - faceLow) < 0.001 })
        let badge = coloured.filter { $0.y > bandTop + 0.01 }
        XCTAssertFalse(badge.isEmpty)
        // The reader, facing it from the track (out −z), reads towards −x.
        XCTAssertTrue(badge.allSatisfy { -$0.x < -Props.nameBoardLength / 2 + 0.8 })
        let ink = mesh.vertices.filter { $0.color == Map3DPalette.playerRim }
        XCTAssertTrue(ink.allSatisfy { $0.y >= bandTop - 0.001 && $0.y <= faceLow + faceHeight + 0.001 && $0.nz < -0.99 })
        let badgeRight = try XCTUnwrap(badge.map { -$0.x }.max())
        XCTAssertTrue(ink.allSatisfy { -$0.x > badgeRight })
        XCTAssertGreaterThan(ink.count, plain.vertices.filter { $0.color == Map3DPalette.playerRim }.count, "the reading too")
        // The number's letters in white on its square, in front of it.
        let white = mesh.vertices.filter { $0.color == Map3DPalette.sidewalk && $0.layer != Map3DVertex.glowing && $0.y > bandTop }
        XCTAssertFalse(white.isEmpty)
        if let path = ProcessInfo.processInfo.environment["PLATFORM_NAME_BOARD_STYLES_PREVIEW"] {
            typealias Sample = (name: String, second: String?, styled: Props.StyledBoard?)
            let samples: [Sample] = [
                ("臺南", "Tainan", nil),
                ("台北車站", "Taipei Main Station", Props.StyledBoard(style: .metro, reading: nil, number: "BL12", colour: Map3DColor.rgb(0x0070BD),
                                                                   transfers: [Props.Badge(number: "R10", colour: Map3DColor.rgb(0xE3002C))])),
                ("美麗島", "Formosa Boulevard", Props.StyledBoard(style: .metro, reading: nil, number: "O5", colour: Map3DColor.rgb(0xFF9500),
                                                              transfers: [Props.Badge(number: "R10", colour: Map3DColor.rgb(0xE30964))])),
                ("美麗島", "Formosa Boulevard", Props.StyledBoard(style: .metro, reading: nil, number: "R10", colour: Map3DColor.rgb(0xE30964),
                                                              transfers: [Props.Badge(number: "O5", colour: Map3DColor.rgb(0xFF9500))])),
                ("中環", "Central", Props.StyledBoard(style: .metro, reading: nil, number: nil, colour: Map3DColor.rgb(0xED1D24))),
                ("博多", "Hakata", Props.StyledBoard(style: .metro, reading: "はかた", number: "K11", colour: Map3DColor.rgb(0xFF4500),
                                                     transfers: [Props.Badge(number: "N18", colour: Map3DColor.rgb(0x008000))])),
                ("Rovaniemi", nil, Props.StyledBoard(style: .finnish, reading: nil, number: nil, colour: Map3DColor.rgb(0x3FA535))),
                ("美麗島", "Formosa Boulevard", Props.StyledBoard(style: .metro, reading: nil, number: "O5", colour: Map3DColor.rgb(0xFF9500))),
            ]
            let boards = samples.map { sample -> [String: Any] in
                var board = Map3DMesh()
                Builder.addNameBoard(&board, foot: Map3DPoint(0, 0, 0), out: out, name: sample.name, second: sample.second,
                                     styled: sample.styled, underground: true)
                return Self.json(board)
            }
            try JSONSerialization.data(withJSONObject: boards).write(to: URL(fileURLWithPath: path))
        }
    }

    static func json(_ mesh: Map3DMesh) -> [String: Any] {
        var positions: [Float] = [], colours: [Int] = []
        for v in mesh.vertices { positions += [v.x, v.y, v.z]; colours.append(Int(v.color & 0xFF_FFFF)) }
        return ["positions": positions, "colours": colours, "indices": mesh.indices.map { Int($0) }]
    }
}
