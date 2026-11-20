import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 902: the player's shop and office block are the studio's
/// models, in the brief's colours, their fronts to the street.
final class Map3DPlayerShopOfficeTests: XCTestCase {
    /// Both decode at the studio's size and triangles (its README's check).
    func testTheModelsDecode() throws {
        let shop = try XCTUnwrap(Map3DPlayerShopOffice.model(Map3DPlayerShopOffice.shopName))
        let office = try XCTUnwrap(Map3DPlayerShopOffice.model(Map3DPlayerShopOffice.officeName))
        XCTAssertEqual(shop.triangleCount, 1_978)
        XCTAssertEqual(office.triangleCount, 1_910)
        XCTAssertEqual(shop.maximum.x - shop.minimum.x, 21.88, accuracy: 0.02)
        XCTAssertEqual(shop.maximum.y - shop.minimum.y, 15.30, accuracy: 0.02)
        XCTAssertEqual(shop.maximum.z, 13.45, accuracy: 0.02)
        XCTAssertEqual(office.maximum.x - office.minimum.x, 27.25, accuracy: 0.02)
        XCTAssertEqual(office.maximum.z, 26.95, accuracy: 0.02)
        XCTAssertEqual(shop.minimum.z, 0, accuracy: 0.02)
        XCTAssertEqual(office.minimum.z, 0, accuracy: 0.02)
    }

    /// Every colour is the palette's (the brief's table), and the shop's
    /// four walls are four different colours.
    func testTheirColoursAreThePalettes() throws {
        let palette = Set(Map3DPlayerShopOffice.meshPalette)
        XCTAssertEqual(palette.count, Map3DPlayerShopOffice.meshPalette.count, "sixteen materials, sixteen colours")
        for name in [Map3DPlayerShopOffice.shopName, Map3DPlayerShopOffice.officeName] {
            let model = try XCTUnwrap(Map3DPlayerShopOffice.model(name))
            XCTAssertTrue(Set(model.vertices.map(\.color)).isSubset(of: palette), name)
        }
        let shop = try XCTUnwrap(Map3DPlayerShopOffice.model(Map3DPlayerShopOffice.shopName))
        let walls = Map3DPlayerShopOffice.meshPalette[0..<4]
        XCTAssertTrue(Set(walls).isSubset(of: Set(shop.vertices.map(\.color))))
    }

    /// Laid on its plot, each stands nearer its front (+x, the street
    /// side the yellow box's windows faced) than its back, as the brief
    /// set it (3 m and 2 m in from the plot's front), and the shop's
    /// arcade is at its front.
    func testTheyFaceTheStreet() throws {
        for kind in [PlacedBuildingKind.shop, .office] {
            let layout = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[kind]?.first, "\(kind)")
            let bounds = try XCTUnwrap(layout.mesh.bounds)
            XCTAssertGreaterThan(bounds.max.x, -bounds.min.x + 2, "\(kind): its front out to the street")
            XCTAssertEqual(bounds.max.z, -bounds.min.z, accuracy: 0.6, "\(kind): in the middle across")
        }
        let shop = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[.shop]?.first)
        let shade = shop.mesh.vertices.filter { $0.color == Map3DPalette.arcade && $0.y < 3.5 }
        XCTAssertFalse(shade.isEmpty)
        let front = shade.filter { $0.x > 0 }.count
        XCTAssertGreaterThan(front, (shade.count - front) * 2, "the shop's arcade at its front")
    }
}
