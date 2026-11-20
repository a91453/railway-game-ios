import Foundation
@testable import GamePresentation
import XCTest

/// Decision 901: Finland's houses and blocks of flats drawn near as the
/// studio's models, fitted to a building's outline within a fifth.
final class Map3DNordicHousesTests: XCTestCase {
    /// Every model decodes, stands on the ground, its body about the size
    /// its unit says and its colours its materials' indices.
    func testTheModelsDecode() throws {
        for unit in Map3DNordicHouses.Unit.allCases {
            let model = try XCTUnwrap(Map3DNordicHouses.models[unit], unit.rawValue)
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.35, unit.rawValue)
            XCTAssertGreaterThanOrEqual(model.maximum.x - model.minimum.x, unit.body.length - 0.05, unit.rawValue)
            XCTAssertLessThanOrEqual(model.maximum.x - model.minimum.x, unit.body.length + 4, unit.rawValue)
            XCTAssertTrue(model.vertices.allSatisfy { Int($0.color) < Map3DNordicHouses.Material.allCases.count }, unit.rawValue)
        }
    }

    /// Which model a building is drawn as: by kind, floors and roof, the
    /// nearest body within a fifth; none past that.
    func testTheUnitFitsTheOutline() {
        typealias U = Map3DNordicHouses
        XCTAssertEqual(U.unit(kind: .house, storeys: 1, pitched: true, length: 12, width: 7), .houseB)
        XCTAssertEqual(U.unit(kind: .house, storeys: 1, pitched: true, length: 9, width: 7.5), .houseA)
        XCTAssertEqual(U.unit(kind: .house, storeys: 2, pitched: true, length: 8.5, width: 8), .houseC)
        XCTAssertEqual(U.unit(kind: .flats, storeys: 3, pitched: false, length: 26, width: 12), .block3)
        XCTAssertEqual(U.unit(kind: .flats, storeys: 5, pitched: false, length: 30, width: 12), .block5)
        XCTAssertNil(U.unit(kind: .house, storeys: 1, pitched: false, length: 12, width: 7), "a flat-roofed house stays a box")
        XCTAssertNil(U.unit(kind: .house, storeys: 1, pitched: true, length: 20, width: 7), "too long")
        XCTAssertNil(U.unit(kind: .flats, storeys: 8, pitched: false, length: 30, width: 12), "too tall")
        XCTAssertNil(U.unit(kind: .office, storeys: 3, pitched: false, length: 24, width: 11))
    }

    /// The building's own wall and roof colours go on its wall and roof;
    /// a white wall's trim a step deeper so it shows.
    func testTheColoursAreTheBuildings() {
        let wall = Map3DNordic.houseWalls[0], roof = Map3DNordic.flatRoof
        let colours = Map3DNordicHouses.colours(wall: wall, roof: roof)
        XCTAssertEqual(colours.count, Map3DNordicHouses.Material.allCases.count)
        XCTAssertEqual(colours[Map3DNordicHouses.Material.wall.rawValue], wall)
        XCTAssertEqual(colours[Map3DNordicHouses.Material.roof.rawValue], roof)
        let white = Map3DNordic.houseWalls[3]
        XCTAssertEqual(Map3DNordicHouses.colours(wall: white, roof: roof)[Map3DNordicHouses.Material.trim.rawValue], Map3DNordic.trim)
    }

    /// Laid along a way, stretched, each face keeps its outward side and
    /// the model stays on its outline.
    func testAppendKeepsTheOutline() throws {
        let model = try XCTUnwrap(Map3DNordicHouses.models[.houseB])
        var mesh = Map3DMesh()
        let colours = Map3DNordicHouses.colours(wall: Map3DNordic.houseWalls[0], roof: Map3DNordic.flatRoof)
        mesh.appendNordic(model, at: Map3DPoint(100, 5, 50), forward: Map3DPoint(0, 0, 1), scale: (1.1, 0.9), colours: colours, backLeft: true)
        XCTAssertEqual(mesh.triangleCount, model.triangleCount)
        let bounds = try XCTUnwrap(mesh.bounds)
        XCTAssertEqual(bounds.min.y, 5 + model.minimum.z, accuracy: 0.01)
        XCTAssertEqual((bounds.max.z + bounds.min.z) / 2, 50, accuracy: 2.5, "along the way")
        XCTAssertGreaterThanOrEqual(bounds.max.z - bounds.min.z, 12 * 1.1 - 0.05)
    }
}
