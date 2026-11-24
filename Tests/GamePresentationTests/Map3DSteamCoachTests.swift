import XCTest
@testable import GamePresentation

/// Decision 957: the steam train's wooden coaches (``Map3DSteamCoach``),
/// the local studio's revision 3 of the author's old coach.
final class Map3DSteamCoachTests: XCTestCase {
    private func model(_ unit: Map3DSteamCoach.Unit, far: Bool = false) throws -> Map3DModelPack.Model {
        try XCTUnwrap(Map3DSteamCoach.model(unit, far: far), "\(unit) far \(far) does not decode")
    }

    /// Each coach decodes with the studio's triangles: 1,944 and 2,024
    /// near, 566 and 614 far.
    func testTheCoachesHaveTheStudiosTriangles() throws {
        XCTAssertEqual(try model(.middle).triangleCount, 1_944)
        XCTAssertEqual(try model(.tail).triangleCount, 2_024)
        XCTAssertEqual(try model(.middle, far: true).triangleCount, 566)
        XCTAssertEqual(try model(.tail, far: true).triangleCount, 614)
    }

    /// Every coach, near and far, is 12.12 m between its coupler faces
    /// (the model's length, not the type catalogue's 8 m), 2.38 m wide,
    /// 3.40 m from the rail to its ventilators' tops, on the rail, and
    /// centred.
    func testTheCoachesAreTheirMeasuredSize() throws {
        for unit in Map3DSteamCoach.Unit.allCases {
            for far in [false, true] {
                let coach = try model(unit, far: far)
                let label = "\(unit) far \(far)"
                XCTAssertEqual(coach.minimum.x, -6.06, accuracy: 0.02, label)
                XCTAssertEqual(coach.maximum.x, 6.06, accuracy: 0.02, label)
                XCTAssertEqual(coach.maximum.x - coach.minimum.x, Map3DSteamCoach.length, accuracy: 0.02, label)
                XCTAssertEqual(coach.minimum.y, -1.19, accuracy: 0.02, label)
                XCTAssertEqual(coach.maximum.y, 1.19, accuracy: 0.02, label)
                XCTAssertEqual(coach.minimum.z, 0, accuracy: 0.002, label)
                XCTAssertEqual(coach.maximum.z, 3.40, accuracy: 0.02, label)
            }
        }
    }

    /// The steam train's set runs the coaches, its last one's two lamps
    /// lit at its back end only, and has a far set of the light coaches;
    /// the locomotive and its tender stay #1118's.
    func testTheSteamTrainRunsTheCoaches() throws {
        let near = try XCTUnwrap(Map3DTrainSet.named("STEAM"))
        XCTAssertEqual(near.far, "STEAMFar")
        XCTAssertTrue(near.ownLengths)
        XCTAssertNotNil(Map3DTrainSet.named("STEAMFar"))
        XCTAssertTrue(Map3DTrainSet.nearOnly.contains("STEAM"))
        XCTAssertEqual(Map3DTrainRegistry.registration(ofSet: "STEAM")?.id, "steam-coach")

        let pack = Map3DModelPack.standard
        func packed(_ name: String) throws -> Map3DModelPack.Model { pack.models[try XCTUnwrap(pack.index(of: name), name)] }
        XCTAssertEqual(try packed("set-STEAM-car").triangleCount, 1_944)
        XCTAssertEqual(try packed("set-STEAMFar-car").triangleCount, 566)
        let tail = try packed("set-STEAM-tail")
        XCTAssertEqual(tail.triangleCount, 2_024)
        XCTAssertEqual(try packed("set-STEAMFar-tail").triangleCount, 614)

        // Decision 449: the pack draws a running car unlit and lights its
        // lamps each frame; the last coach's are its two red lenses at
        // its back end.
        let lamps = Map3DTrainLights.car(tail).back.tail
        XCTAssertFalse(lamps.isEmpty, "the tail lamps")
        XCTAssertTrue(lamps.allSatisfy { $0.x < -5.7 && Map3DTrainLights.isRed($0.color) })
        XCTAssertTrue(Map3DTrainLights.car(tail).front.tail.allSatisfy { $0.x > 0 })
        let middle = try packed("set-STEAM-car")
        XCTAssertFalse(middle.vertices.contains { $0.glows || $0.color == Map3DPalette.lantern })
    }

    /// Only the studio's glass material is the coaches' window glass, and
    /// each coach has some.
    func testOnlyTheGlassIsGlass() throws {
        for unit in Map3DSteamCoach.Unit.allCases {
            for far in [false, true] {
                let coach = try model(unit, far: far)
                let glass = coach.vertices.filter { $0.layer == Map3DVertex.trainGlass }
                XCTAssertFalse(glass.isEmpty, "\(unit) far \(far)")
                XCTAssertTrue(glass.allSatisfy { $0.color == Map3DTrainStyle.glass }, "\(unit) far \(far)")
            }
        }
    }

    /// Decision 957: the coach behind the duplex locomotive. Its roof
    /// (3.40 m with the ventilators) is no more than 0.3 m above the
    /// locomotive's highest point, and the coaches are not taller than
    /// the scene kit's coach they replace.
    func testTheCoachIsNotTallerThanTheLocomotive() throws {
        let locomotive = Map3DDuplexSteam.model(.locomotive)
        let coach = try model(.middle)
        print("steam coach heights: locomotive \(locomotive.maximum.z), tender \(Map3DDuplexSteam.model(.tender).maximum.z), coach \(coach.maximum.z)")
        XCTAssertLessThanOrEqual(coach.maximum.z, locomotive.maximum.z + 0.3)
    }
}
