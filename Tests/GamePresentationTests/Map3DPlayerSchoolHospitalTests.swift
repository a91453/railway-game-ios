import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 963: the player's primary school and hospital are the
/// studio's models, in the brief's colours, laid on their plots as its
/// §11 set them.
final class Map3DPlayerSchoolHospitalTests: XCTestCase {
    typealias Studio = Map3DPlayerSchoolHospital

    /// All three decode at the studio's size and triangles (its
    /// revision-3 README's check), each its middle at its origin.
    func testTheModelsDecode() throws {
        let sizes: [(String, Int, Float, Float, Float)] = [
            (Studio.schoolName, 925, 32.92, 36.40, 11.49),
            (Studio.gymName, 198, 17.16, 27.41, 10.64),
            (Studio.hospitalName, 1_718, 26.79, 21.86, 14.03),
        ]
        for (name, triangles, across, deep, high) in sizes {
            let model = try XCTUnwrap(Studio.model(name), name)
            XCTAssertEqual(model.triangleCount, triangles, name)
            XCTAssertEqual(model.maximum.x - model.minimum.x, across, accuracy: 0.03, name)
            XCTAssertEqual(model.maximum.y - model.minimum.y, deep, accuracy: 0.03, name)
            XCTAssertEqual(model.maximum.z, high, accuracy: 0.03, name)
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.01, name)
            XCTAssertEqual(model.maximum.x + model.minimum.x, 0, accuracy: 0.03, name)
            XCTAssertEqual(model.maximum.y + model.minimum.y, 0, accuracy: 0.03, name)
        }
    }

    /// Every colour is the palette's (the brief's §8), ten materials ten
    /// colours, and the hospital has its blue sign.
    func testTheirColoursAreThePalettes() throws {
        let palette = Set(Studio.meshPalette)
        XCTAssertEqual(palette.count, Studio.meshPalette.count)
        for name in [Studio.schoolName, Studio.gymName, Studio.hospitalName] {
            let model = try XCTUnwrap(Studio.model(name))
            XCTAssertTrue(Set(model.vertices.map(\.color)).isSubset(of: palette), name)
        }
        let hospital = try XCTUnwrap(Studio.model(Studio.hospitalName))
        XCTAssertTrue(hospital.vertices.contains { $0.color == Map3DPalette.canopy }, "the sign's blue")
        let gym = try XCTUnwrap(Studio.model(Studio.gymName))
        XCTAssertTrue(gym.vertices.contains { $0.color == Map3DPalette.gymGreen }, "the gym's green roof")
    }

    /// The first school and the first hospital are the studio's; the
    /// kindergarten and the clinic with its day-care wing stay as they
    /// were.
    func testTheFirstLooksAreTheStudios() throws {
        for (kind, colour) in [(PlacedBuildingKind.school, Map3DPalette.schoolWalls), (.hospital, Map3DPalette.canopy)] {
            let layouts = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[kind])
            XCTAssertEqual(layouts.count, kind.looks)
            XCTAssertTrue(layouts[0].mesh.vertices.contains { $0.color == Map3DDepotFacilities.glass }, "\(kind): the studio's windows")
            XCTAssertTrue(layouts[0].mesh.vertices.contains { $0.color == colour }, "\(kind)")
        }
        let clinic = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[.hospital]?[1])
        XCTAssertFalse(clinic.mesh.vertices.contains { $0.color == Map3DDepotFacilities.glass }, "the clinic is the civic kit's")
    }

    /// Laid on its plot, each layout keeps inside the plot, and no two
    /// of its tall things (what is drawn from farther as boxes) overlap.
    func testTheyFitTheirPlots() throws {
        for kind in [PlacedBuildingKind.school, .hospital] {
            // 3,072 world units are a school's 46 m.
            let half = Float(kind.side) * 46 / 3_072 / 2
            let layout = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[kind]?.first)
            let bounds = try XCTUnwrap(layout.mesh.bounds)
            for value in [bounds.min.x, bounds.min.z] { XCTAssertGreaterThanOrEqual(value, -half, "\(kind)") }
            for value in [bounds.max.x, bounds.max.z] { XCTAssertLessThanOrEqual(value, half, "\(kind)") }
            XCTAssertEqual(layout.boxes.filter { $0.height > 9 }.count, kind == .school ? 3 : 1, "\(kind): the school's two wings and its gym, or the hospital")
            for (i, a) in layout.boxes.enumerated() {
                for b in layout.boxes[(i + 1)...] {
                    let apart = abs(a.centre.x - b.centre.x) >= (a.length + b.length) / 2 - 0.05
                        || abs(a.centre.z - b.centre.z) >= (a.width + b.width) / 2 - 0.05
                    XCTAssertTrue(apart, "\(kind): \(a) and \(b) overlap")
                }
            }
        }
    }

    /// Each faces the street (+x): the school's long wing, its brown roof,
    /// at the front, its gym at the back; the hospital's tall front block
    /// before its low back one, the brown terrace.
    func testTheyFaceTheStreet() throws {
        func meanX(_ kind: PlacedBuildingKind, _ colour: UInt32) throws -> Float {
            let layout = try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[kind]?.first)
            let xs = layout.mesh.vertices.filter { $0.color == colour }.map(\.x)
            XCTAssertFalse(xs.isEmpty)
            return xs.reduce(0, +) / Float(max(xs.count, 1))
        }
        XCTAssertGreaterThan(try meanX(.school, Map3DPalette.cityRoofs[5].color), 8, "the long wing at the front")
        XCTAssertLessThan(try meanX(.school, Map3DPalette.gymGreen), -4, "the gym at the back")
        XCTAssertLessThan(try meanX(.hospital, Map3DPalette.cityRoofs[5].color), Studio.hospitalAt.x, "the terrace at the back")
    }
}
