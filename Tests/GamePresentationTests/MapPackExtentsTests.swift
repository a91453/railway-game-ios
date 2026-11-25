import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 969: a pack whose map grew lists the extents it had before
/// (`pack.json`'s `earlier`), each the north-west part of the next.
final class MapPackExtentsTests: XCTestCase {
    private func manifest(_ extent: String, earlier: String? = nil) -> Data {
        Data(#"{"id":"x","extent":\#(extent)\#(earlier.map { #","earlier":\#($0)"# } ?? "")}"#.utf8)
    }

    private let fukuoka = #"{"north":33.72,"south":33.52,"west":130.29,"east":130.48}"#
    private let kumamoto = #"{"north":33.72,"south":32.69,"west":130.29,"east":130.9}"#

    func testAPackThatNeverGrewHasNoEarlierExtent() throws {
        let read = try MapPack.extents(ofManifest: manifest(fukuoka))
        XCTAssertEqual(read.extent, MapPack.Extent(north: 33.72, south: 33.52, west: 130.29, east: 130.48))
        XCTAssertEqual(read.earlier, [])
        XCTAssertEqual(try MapPack.extent(ofManifest: manifest(fukuoka)), read.extent)
    }

    func testAGrownPackListsTheExtentsItHadOldestFirst() throws {
        let read = try MapPack.extents(ofManifest: manifest(kumamoto, earlier: "[\(fukuoka)]"))
        XCTAssertEqual(read.extent, MapPack.Extent(north: 33.72, south: 32.69, west: 130.29, east: 130.9))
        XCTAssertEqual(read.earlier, [MapPack.Extent(north: 33.72, south: 33.52, west: 130.29, east: 130.48)])
        // The reader of the extent alone is as before.
        XCTAssertEqual(try MapPack.extent(ofManifest: manifest(kumamoto, earlier: "[\(fukuoka)]")), read.extent)
    }

    func testAnEarlierExtentIsTheNorthWestPartOfTheNext() {
        // Another corner, larger than the map now, or the same as it.
        let moved = #"{"north":33.70,"south":33.52,"west":130.29,"east":130.48}"#
        let west = #"{"north":33.72,"south":33.52,"west":130.20,"east":130.48}"#
        let larger = #"{"north":33.72,"south":32.50,"west":130.29,"east":130.48}"#
        for earlier in [moved, west, larger, kumamoto] {
            XCTAssertThrowsError(try MapPack.extents(ofManifest: manifest(kumamoto, earlier: "[\(earlier)]")), earlier)
        }
    }

    /// Fukuoka's grew to Kumamoto (KUMAMOTO-GROUND); the others have not
    /// grown.
    func testOnlyFukuokasPackInTheAppHasGrown() throws {
        for city in OverseasMap.allCases {
            let pack = try XCTUnwrap(HongKongRailwaysTests.pack(city))
            let fukuoka = MapPack.Extent(north: 33.72, south: 33.52, west: 130.29, east: 130.48)
            XCTAssertEqual(try MapPack.extents(ofManifest: pack.file("pack", "json")).earlier, city == .fukuoka ? [fukuoka] : [], "\(city)")
        }
    }
}
