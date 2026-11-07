import GameCore
@testable import GamePresentation
import XCTest

/// Decision 632: the collection's ferries and cable cars in 3D, and the
/// cable car page's real figures.
final class CollectionShowcaseTests: XCTestCase {
    func testTheCableCarPageGivesEachRealLinesFigures() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let entries = FerryCollection.cableways(in: language)
            XCTAssertEqual(entries.map(\.id), ["maokong", "sunMoonLake"])
            XCTAssertTrue(entries.allSatisfy { $0.lines.count >= 3 })
            XCTAssertFalse(FerryCollection.cablewayNote(in: language).isEmpty)
        }
        let chinese = FerryCollection.cableways(in: .traditionalChinese)
        // Maokong: the official site's 4.033 km, 4 + 2 stations, 136 cabins
        // (30 crystal), 8 and 5 seats; opened 2007-07-04.
        let maokong = chinese[0].lines.joined(separator: "\n")
        for figure in ["2007 年 7 月 4 日", "4.033 公里", "4 個車站、2 個轉角站", "136 部", "30 部", "8 人", "5 人"] {
            XCTAssertTrue(maokong.contains(figure), figure)
        }
        let sunMoon = chinese[1].lines.joined(separator: "\n")
        for figure in ["2009 年 12 月 28 日", "1.877 公里", "2 個車站", "86 部", "8 人"] {
            XCTAssertTrue(sunMoon.contains(figure), figure)
        }
        // The game's own figures agree: Maokong's spans are the official
        // 4,033 m, its six stops four that board; Sun Moon Lake's two stops.
        XCTAssertEqual(RealCableway.maokong.legMetres.reduce(0, +), 4_033)
        XCTAssertEqual(RealCableway.maokong.stops.filter(\.boards).count, 4)
        XCTAssertEqual(RealCableway.maokong.stops.filter { !$0.boards }.count, 2)
        XCTAssertEqual(RealCableway.sunMoonLake.stops.count, 2)
    }

    /// Every piece on both stages is a model the 3D map draws, near and far.
    func testEveryPieceIsADrawnModel() {
        let pack = Map3DModelPack.standard
        for exhibit in Map3DCollectionShowcase.Exhibit.allCases {
            for far in [false, true] {
                let layout = Map3DCollectionShowcase.layout(exhibit, far: far)
                XCTAssertFalse(layout.pieces.isEmpty)
                for piece in layout.pieces {
                    XCTAssertNotNil(pack.index(of: piece.model), piece.model)
                    XCTAssertEqual(piece.model.hasSuffix("-far"), far, piece.model)
                }
                let frame = Map3DCollectionShowcase.frame(layout, pack: pack)
                XCTAssertEqual(frame.instances.count, layout.pieces.count + layout.ropes.count)
            }
        }
    }

    func testTheFerriesAreBothRealBoatsOnWater() {
        let layout = Map3DCollectionShowcase.layout(.ferries)
        XCTAssertEqual(layout.pieces.map(\.model), Map3DFerry.Boat.allCases.map { Map3DFerry.name($0) })
        XCTAssertTrue(layout.ropes.isEmpty)
        // Bows level at x 0, side by side with water between their beams.
        for (piece, boat) in zip(layout.pieces, Map3DFerry.Boat.allCases) {
            XCTAssertEqual(piece.at.x + boat.length / 2, 0, accuracy: 0.001)
            XCTAssertEqual(piece.at.y, Map3DFerries.waterLift, accuracy: 0.001)
        }
        let gap = layout.pieces[1].at.z - layout.pieces[0].at.z - (Map3DFerry.Boat.tamsui.beam + Map3DFerry.Boat.cijin.beam) / 2
        XCTAssertGreaterThan(gap, 4)
        // The ground is water, the 3D map's.
        let ground = Map3DCollectionShowcase.ground(layout)
        XCTAssertFalse(ground.mesh.vertices.isEmpty)
        XCTAssertTrue(ground.mesh.vertices.allSatisfy { abs($0.layer - Map3DVertex.water) < 0.01 })
    }

    func testTheCableCarsHangFromTheirRopeBetweenTwoTowers() {
        let layout = Map3DCollectionShowcase.layout(.cableways)
        let cabins = layout.pieces.filter { $0.model.hasPrefix("cablecar-cabin-") }
        XCTAssertEqual(cabins.map(\.model), Map3DCableCar.Cabin.allCases.map { "cablecar-cabin-" + $0.rawValue }
                       + Map3DCableCar.SunMoonCabin.allCases.map { "cablecar-cabin-sunmoon-" + $0.rawValue })
        XCTAssertEqual(layout.pieces.filter { $0.model == "cablecar-tower" }.count, 4)
        XCTAssertEqual(layout.ropes.count, 4)
        let height = Map3DCableCar.ropeHeight(ofTower: Map3DCableCar.towerHeight)
        for cabin in cabins {
            // On a rope: its grip at the rope's height, on one of the ropes' lines, between the towers.
            XCTAssertEqual(cabin.at.y, height, accuracy: 0.001)
            let rope = layout.ropes.first { abs($0.from.z - cabin.at.z) < 0.001 }
            let along = try? XCTUnwrap(rope, cabin.model)
            if let along { XCTAssertTrue((along.from.x...along.to.x).contains(cabin.at.x), cabin.model) }
        }
        // Its body clears the ground.
        XCTAssertGreaterThan(height - Map3DCableCar.cabinDrop, 5)
    }

    func testTheCameraLooksAtTheExhibit() {
        for exhibit in Map3DCollectionShowcase.Exhibit.allCases {
            let layout = Map3DCollectionShowcase.layout(exhibit)
            let content = Map3DShowcaseContent.exhibit(layout)
            for view in Map3DShowcase.View.allCases {
                let camera = content.camera(view, viewport: (844, 390))
                XCTAssertGreaterThanOrEqual(camera.distance, Map3DShowcase.nearest, "\(exhibit) \(view)")
                XCTAssertLessThanOrEqual(camera.distance, Map3DShowcase.farthest)
                XCTAssertGreaterThanOrEqual(camera.target.x, layout.low.x - 0.001)
                XCTAssertLessThanOrEqual(camera.target.x, layout.high.x + 0.001)
            }
            // The view from above takes in more than the close one.
            XCTAssertGreaterThan(content.camera(.overhead, viewport: (844, 390)).distance, content.camera(.closeUp, viewport: (844, 390)).distance)
            XCTAssertNotEqual(exhibit.viewName(.closeUp, in: .traditionalChinese), Map3DShowcase.View.closeUp.name(in: .traditionalChinese))
            XCTAssertEqual(exhibit.viewName(.side, in: .english), "Side")
        }
        // The trains' content is the garage's as before.
        let rows = Map3DShowcase.layout(keys: Map3DShowcase.defaultKeys)
        XCTAssertEqual(Map3DShowcaseContent.trains(rows).frame().instances.count, Map3DShowcase.frame(rows).instances.count)
        XCTAssertEqual(Map3DShowcaseContent.trains(rows).camera(.side, viewport: (844, 390)).distance,
                       Map3DShowcase.camera(.side, rows: rows, viewport: (844, 390)).distance)
    }
}
