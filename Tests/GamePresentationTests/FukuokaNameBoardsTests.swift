import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// FUKUOKA-NAME-BOARDS (decision 882's later note): the Fukuoka City
/// Subway's platform name boards as its own: the Japanese name, its
/// reading, the English name, the station's number and the line's colour.
@MainActor
final class FukuokaNameBoardsTests: XCTestCase {
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

    /// On a game of Fukuoka's map every station has a Japanese sign, its
    /// English name the pack's, and the platform of each line gets that
    /// line's number and colour.
    func testAGamesStationsGetTheirSigns() throws {
        let session = try FukuokaRailwaysTests.fukuoka()
        for line in session.buyableRealLines {
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), line.id)
        }
        let world = session.world, railways = try FukuokaRailwaysTests.railways()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let signs = Builder.boardJapaneseSigns(world, railways, frame)
        XCTAssertEqual(Set(signs.values.map(\.japanese)).count, 36)
        let hakata = try XCTUnwrap(signs.values.first { $0.japanese == "博多" })
        XCTAssertEqual(hakata.kana, "はかた")
        XCTAssertEqual(hakata.english, "Hakata")
        XCTAssertEqual(hakata.board(realLine: "fksubway:K")?.number, "K11")
        XCTAssertEqual(hakata.board(realLine: "fksubway:N")?.number, "N18")
        XCTAssertEqual(hakata.board(realLine: "fksubway:N")?.colour, Map3DColor.rgb(0x008000))
        XCTAssertEqual(hakata.board(realLine: "fksubway:K")?.colour, Map3DColor.rgb(0xFF4500))
        XCTAssertEqual(hakata.board(realLine: nil)?.number, "K11")
        let nakasu = try XCTUnwrap(signs.values.first { $0.japanese == "中洲川端" })
        XCTAssertEqual(nakasu.board(realLine: "fksubway|H")?.number, "H01")
        // Taiwan's stations keep decision 882's boards.
        XCTAssertNil(Map3DJapaneseNameBoards.systems["trtc"])
    }

    /// A Japanese board: its band and number in the line's colour, the
    /// number's letters in white, the reading, name and English name in
    /// ink over the band, all on the face.
    func testAJapaneseBoardIsLaidOut() throws {
        let colour = Map3DColor.rgb(0xFF4500)
        let japanese = Props.JapaneseBoard(kana: "はかた", number: "K11", colour: colour)
        var mesh = Map3DMesh(), plain = Map3DMesh()
        let out = Map3DPoint(0, 0, -1)
        Builder.addNameBoard(&mesh, foot: Map3DPoint(0, 0, 0), out: out, name: "博多", second: "Hakata", japanese: japanese, underground: true)
        Builder.addNameBoard(&plain, foot: Map3DPoint(0, 0, 0), out: out, name: "博多", second: "Hakata", underground: true)
        XCTAssertFalse(mesh.vertices.contains { $0.color == Props.nameBoardGreen })
        let faceLow = Props.nameBoardFoot + Props.nameBoardFrame
        let faceHeight = Props.nameBoardHeight - 2 * Props.nameBoardFrame
        let bandTop = faceLow + faceHeight * Props.japaneseBand
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
        if let path = ProcessInfo.processInfo.environment["FUKUOKA_NAME_BOARD_PREVIEW"] {
            var boards: [[String: Any]] = []
            for (name, kana, english, number, hex) in [("博多", "はかた", "Hakata", "K11", UInt32(0xFF4500)),
                                                       ("中洲川端", "なかすかわばた", "Nakasu-Kawabata", "H01", 0x0077CC),
                                                       ("櫛田神社前", "くしだじんじゃまえ", "Kushida-jinja-mae", "N17", 0x008000)] {
                var board = Map3DMesh()
                Builder.addNameBoard(&board, foot: Map3DPoint(0, 0, 0), out: out, name: name, second: english,
                                     japanese: Props.JapaneseBoard(kana: kana, number: number, colour: Map3DColor.rgb(hex)), underground: true)
                boards.append(Self.json(board))
            }
            boards.append(Self.json(plain))
            try JSONSerialization.data(withJSONObject: boards).write(to: URL(fileURLWithPath: path))
        }
    }

    static func json(_ mesh: Map3DMesh) -> [String: Any] {
        var positions: [Float] = [], colours: [Int] = []
        for v in mesh.vertices { positions += [v.x, v.y, v.z]; colours.append(Int(v.color & 0xFF_FFFF)) }
        return ["positions": positions, "colours": colours, "indices": mesh.indices.map { Int($0) }]
    }
}
