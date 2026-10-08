import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 81: linking stations for transfers from the
/// station panel, leaving a group, and Undo (decision 82), which winds the
/// transfer group IDs back with the rest of the world.
@MainActor
final class TransferGroupSessionTests: XCTestCase {
    /// Four stations along a row: West, Middle 1 km east, East 2 km east,
    /// Far 3 km east.
    private func makeSession(language: DisplayLanguage = .english) throws -> (GameSession, [StationID]) {
        var world = try makeWorld(width: 262_144, height: 8_192, balance: 100_000)
        let ids = try [("West", 0), ("Middle", 1), ("East", 2), ("Far", 3)].map { name, km in
            try world.buildStation(named: name, at: PlanPoint(x: 1_024 + Int64(km) * 64_000, y: 4_096)).id
        }
        return (GameSession(world: world, language: language), ids)
    }

    func testLinkingAndLeavingAGroup() throws {
        let (session, s) = try makeSession()
        session.selectStation(s[0])
        XCTAssertEqual(session.world.transferCandidates(for: s[0]).map(\.id), [s[1], s[2], s[3]], "nearest first")
        XCTAssertNil(session.world.transferGroupText(of: s[0]))
        XCTAssertEqual(session.world.distanceUnits(between: s[0], and: s[2]), 128_000)

        session.linkSelectedStationForTransfer(with: s[2])
        XCTAssertEqual(session.world.transferGroupText(of: s[0]), "West / East")
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Passengers can change between West and East: West / East."))
        XCTAssertEqual(session.world.transferCandidates(for: s[0]).map(\.id), [s[1], s[3]], "not the group's own")

        session.unlinkSelectedStationTransfer()
        XCTAssertEqual(session.world.transferGroups, [])
        XCTAssertEqual(session.message?.kind, .success)
        session.unlinkSelectedStationTransfer()
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "West is in no transfer group."))

        session.linkSelectedStationForTransfer(with: s[0])
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "A station cannot be linked with itself."))
    }

    func testTheMessagesAreInTheSessionsLanguage() throws {
        let (session, s) = try makeSession(language: .traditionalChinese)
        session.selectStation(s[1])
        session.linkSelectedStationForTransfer(with: s[3])
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Middle 與 Far 可以轉乘了：Middle / Far。"))
        session.unlinkSelectedStationTransfer()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Middle 已離開轉乘群組。需要這段步行的乘客會離開。"))
    }

    /// Undo winds the transfer group ID back with the world, so the group
    /// made again gets the same ID; the world stays valid, saves and loads,
    /// and Undo takes that one back too.
    func testAGroupUndoneAndMadeAgainGetsTheSameID() throws {
        let (session, s) = try makeSession()
        session.selectStation(s[0])
        session.linkSelectedStationForTransfer(with: s[1])
        let first = try XCTUnwrap(session.world.transferGroup(of: s[0]))
        XCTAssertEqual(first.id, TransferGroupID(rawValue: 1))

        session.undo()
        XCTAssertEqual(session.world.transferGroups, [])

        session.linkSelectedStationForTransfer(with: s[2])
        XCTAssertEqual(session.message?.kind, .success)
        let again = try XCTUnwrap(session.world.transferGroup(of: s[0]))
        XCTAssertEqual(again.id, first.id, "the counter went back with the world")
        XCTAssertEqual(again.stations, [s[0], s[2]])
        let saved = try SaveLibrary.encode(session.world, at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(try SaveLibrary.decode(saved), session.world)

        session.selectStation(s[3])
        session.linkSelectedStationForTransfer(with: s[2])
        XCTAssertEqual(session.world.transferGroup(of: s[3])?.id, first.id, "joins the same group")
        session.undo()
        session.undo()
        XCTAssertEqual(session.world.transferGroups, [])
        XCTAssertFalse(session.canUndo)
    }

    func testWithoutASelectedStationNothingChanges() throws {
        let (session, s) = try makeSession()
        session.linkSelectedStationForTransfer(with: s[1])
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Select a station on the map first."))
        session.unlinkSelectedStationTransfer()
        XCTAssertEqual(session.world.transferGroups, [])
        XCTAssertEqual(session.undoCount, 0)
    }
}
