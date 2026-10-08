import Foundation
@testable import GameCore
import XCTest

/// ARCHITECTURE decision 81: transfer groups, MapBuilder's interchanges
/// (`handleCreateInterchange`, `handleRemoveStationFromInterchange`) and the
/// `Ci/` reference's `transferGroupId`. Linking, merging, leaving, the IDs,
/// saving and the checks a save must pass. How passengers walk within a
/// group is in `PassengerWalkTransferTests`.
final class TransferGroupTests: XCTestCase {
    /// Five stations in a row, 1 km apart.
    private func makeStations() throws -> (GameWorld, [StationID]) {
        var world = try makeWorld(width: 400_000, height: 8_192, balance: 1_000_000)
        let ids = try (0..<5).map { index in
            try world.buildStation(named: "S\(index + 1)", at: PlanPoint(x: 1_024 + Int64(index) * 64_000, y: 4_096)).id
        }
        return (world, ids)
    }

    func testTwoStationsMakeAGroupAndAThirdJoinsIt() throws {
        var (world, s) = try makeStations()
        XCTAssertEqual(try world.linkTransfer(s[2], s[0]), TransferGroupID(rawValue: 1))
        XCTAssertEqual(world.transferGroups, [TransferGroup(id: TransferGroupID(rawValue: 1), stations: [s[0], s[2]])])
        XCTAssertEqual(try world.linkTransfer(s[1], s[2]), TransferGroupID(rawValue: 1), "joins the group")
        XCTAssertEqual(world.transferGroup(of: s[1])?.stations, [s[0], s[1], s[2]])
        let before = world
        XCTAssertEqual(try world.linkTransfer(s[0], s[1]), TransferGroupID(rawValue: 1), "already together")
        XCTAssertEqual(world, before)
        XCTAssertNil(world.transferGroup(of: s[4]))
    }

    /// Two groups become one: the larger keeps its ID; as large, the first
    /// station's.
    func testTwoGroupsMergeIntoTheLarger() throws {
        var (world, s) = try makeStations()
        try world.linkTransfer(s[0], s[1])
        try world.linkTransfer(s[2], s[3])
        try world.linkTransfer(s[4], s[3])
        XCTAssertEqual(world.transferGroups.map(\.id.rawValue), [1, 2])
        XCTAssertEqual(try world.linkTransfer(s[0], s[4]), TransferGroupID(rawValue: 2), "group 2 has three stations")
        XCTAssertEqual(world.transferGroups, [TransferGroup(id: TransferGroupID(rawValue: 2), stations: s)])

        var (even, t) = try makeStations()
        try even.linkTransfer(t[0], t[1])
        try even.linkTransfer(t[2], t[3])
        XCTAssertEqual(try even.linkTransfer(t[3], t[0]), TransferGroupID(rawValue: 2), "as large: the first station's")
        XCTAssertEqual(even.transferGroups.map(\.stations), [Array(t.prefix(4))])
    }

    /// Leaving: a group of one goes, and its ID is never handed out again.
    func testAStationLeavesAndAGroupOfOneGoes() throws {
        var (world, s) = try makeStations()
        try world.linkTransfer(s[0], s[1])
        try world.linkTransfer(s[0], s[2])
        try world.unlinkTransfer(s[1])
        XCTAssertEqual(world.transferGroup(of: s[0])?.stations, [s[0], s[2]])
        try world.unlinkTransfer(s[2])
        XCTAssertEqual(world.transferGroups, [])
        let before = world
        try world.unlinkTransfer(s[3])
        XCTAssertEqual(world, before, "in no group: nothing changes")
        XCTAssertEqual(try world.linkTransfer(s[3], s[4]), TransferGroupID(rawValue: 2))
    }

    func testBadLinksAreRefusedAndChangeNothing() throws {
        var (world, s) = try makeStations()
        let unknown = StationID(rawValue: 99)
        let before = world
        XCTAssertThrowsError(try world.linkTransfer(unknown, s[0])) { XCTAssertEqual($0 as? GameError, .unknownStation(unknown)) }
        XCTAssertThrowsError(try world.linkTransfer(s[0], unknown)) { XCTAssertEqual($0 as? GameError, .unknownStation(unknown)) }
        XCTAssertThrowsError(try world.linkTransfer(s[0], s[0])) { XCTAssertEqual($0 as? GameError, .invalidTransferGroup) }
        XCTAssertThrowsError(try world.unlinkTransfer(unknown)) { XCTAssertEqual($0 as? GameError, .unknownStation(unknown)) }
        XCTAssertEqual(world, before)
    }

    /// Groups and the next ID save and load; a world without them saves as
    /// before (no keys).
    func testGroupsSaveAndLoad() throws {
        var (world, s) = try makeStations()
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNil(plain["transferGroups"])
        XCTAssertNil(plain["nextTransferGroupID"])
        try world.linkTransfer(s[0], s[1])
        try world.linkTransfer(s[3], s[4])
        try world.unlinkTransfer(s[0])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertEqual(object["nextTransferGroupID"] as? Int, 3)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        XCTAssertEqual(loaded, world)
        var next = loaded
        XCTAssertEqual(try next.linkTransfer(s[0], s[1]), TransferGroupID(rawValue: 3))
    }

    /// A save is refused with groups no command makes.
    func testBrokenGroupsAreRefused() throws {
        var (world, s) = try makeStations()
        try world.linkTransfer(s[0], s[1])
        let good = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        func load(_ change: (inout [String: Any]) -> Void) -> Error? {
            var json = good
            change(&json)
            do {
                _ = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
                return nil
            } catch {
                return error
            }
        }
        XCTAssertNil(load { _ in })
        XCTAssertNotNil(load { $0["transferGroups"] = [["id": 1, "stations": [1]]] }, "one station")
        XCTAssertNotNil(load { $0["transferGroups"] = [["id": 1, "stations": [2, 1]]] }, "out of order")
        XCTAssertNotNil(load { $0["transferGroups"] = [["id": 1, "stations": [1, 99]]] }, "no such station")
        XCTAssertNotNil(load { $0["transferGroups"] = [["id": 1, "stations": [1, 2]], ["id": 1, "stations": [3, 4]]] }, "the same ID twice")
        XCTAssertNotNil(load { $0["transferGroups"] = [["id": 1, "stations": [1, 2]], ["id": 2, "stations": [2, 3]]] }, "a station in two")
        XCTAssertNotNil(load { $0["nextTransferGroupID"] = 1 }, "an ID not below the next")
    }
}
