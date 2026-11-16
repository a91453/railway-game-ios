import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 795: the Christmas livery on each running car by its parts, the
/// line page's choice and the fourth week's mission.
final class Map3DChristmasLiveryTests: XCTestCase {
    private var directory: URL!
    private let calendar = WinterEvent.calendar(in: TimeZone(identifier: "Asia/Taipei")!)
    private let livery = Map3DWinterDecor.christmasLivery

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Map3DChristmasLiveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func isShade(_ colour: UInt32, of base: UInt32) -> Bool {
        (0...63).contains { Map3DColor.shaded(base | 0xFF00_0000, Float($0) / 63) == colour }
    }

    /// Every running car of the pack has a table, its body painted red over
    /// most of its sides; the rest of the pack has none.
    func testEveryRunningCarHasItsBodyPainted() {
        let pack = Map3DModelPack.standard
        var missing: [String] = []
        for (index, model) in pack.models.enumerated() {
            guard Map3DTrainLights.isRunning(model.name) else {
                XCTAssertNil(pack.christmas[index], model.name)
                continue
            }
            guard let table = pack.christmas[index] else { missing.append(model.name); continue }
            XCTAssertEqual(table.count, model.vertexCount, model.name)
            XCTAssertTrue(table.contains { $0 & 0b11 == Map3DChristmasLivery.Part.body.rawValue }, model.name)
        }
        XCTAssertEqual(missing, [], "running cars with nothing to paint")
    }

    /// The repainted car: the same triangles where they were; its glass,
    /// lamps, roof and front as they were; every vertex changed a shade of
    /// one of the livery's three colours, opaque.
    func testOnlyTheBodyBandAndLineChange() {
        let pack = Map3DModelPack.standard
        for (index, table) in pack.christmas {
            let model = pack.models[index]
            let painted = Map3DChristmasLivery.recoloured(model.vertices, table: table)
            XCTAssertEqual(painted.count, model.vertices.count)
            for (old, new) in zip(model.vertices, painted) {
                XCTAssertEqual(old.position, new.position)
                guard old != new else { continue }
                XCTAssertFalse(old.glows, model.name)
                XCTAssertNotEqual(old.layer, Map3DVertex.trainGlass, model.name)
                XCTAssertGreaterThanOrEqual(abs(old.ny), Map3DChristmasLivery.sideward, "\(model.name): only the sides")
                XCTAssertEqual(new.color >> 24, 0xFF)
                XCTAssertTrue([livery.body, livery.band, livery.line].contains { isShade(new.color, of: $0) }, model.name)
            }
        }
    }

    /// The parts of the cars the most lines run: the commuter's white body
    /// red and its line band white; the EMU3000's and the Puyuma's white
    /// bodies red; doors with the body, never glass.
    func testTheCommonCarsParts() throws {
        let pack = Map3DModelPack.standard
        for name in ["commuter-car", "commuter-cab"] {
            let index = try XCTUnwrap(pack.index(of: name), name)
            let model = pack.models[index]
            let table = try XCTUnwrap(pack.christmas[index], name)
            let parts = table.map { Map3DChristmasLivery.Part(rawValue: $0 & 0b11)! }
            // The line's colour band is white.
            let striped = model.vertices.indices.filter { model.vertices[$0].color >> 24 != 0xFF && abs(model.vertices[$0].ny) >= 0.6 }
            XCTAssertFalse(striped.isEmpty, name)
            XCTAssertTrue(striped.contains { parts[$0] == .band }, name)
            // The white side is red.
            let white = model.vertices.indices.filter {
                Map3DChristmasLivery.isShade(model.vertices[$0].color, of: Map3DTrains.body) && abs(model.vertices[$0].ny) >= 0.6
                    && model.vertices[$0].z > 1.2 && model.vertices[$0].z < 3
            }
            XCTAssertFalse(white.isEmpty, name)
            XCTAssertGreaterThan(Double(white.filter { parts[$0] == .body }.count) / Double(white.count), 0.8, name)
        }
        // No glass is ever painted, on any car.
        for (index, table) in pack.christmas {
            let model = pack.models[index]
            for at in model.vertices.indices where model.vertices[at].layer == Map3DVertex.trainGlass || model.vertices[at].glows {
                XCTAssertEqual(table[at], 0, model.name)
            }
        }
    }

    /// A car's trains wear it only on a line chosen while it can be chosen.
    func testTheFrameMarksTheLiveriedLinesCars() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 60)
        let line = try XCTUnwrap(world.lines.first)
        let scene = Map3DScene(world: world), motion = TrainMotion(world: world, time: 0), heights = Map3DTrains.Heights(world: world)
        let pack = Map3DModelPack.standard
        let boxes = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: nil, eye: nil)
        let eye = try XCTUnwrap(boxes.boxes.vertices.first?.position) + Map3DPoint(0, 100, 0)
        let plain = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: pack, eye: eye)
        let liveried = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: pack, eye: eye, christmas: [line.id])
        XCTAssertFalse(plain.instances.isEmpty)
        XCTAssertFalse(plain.instances.contains(where: \.christmas))
        XCTAssertEqual(liveried.instances.count, plain.instances.count)
        XCTAssertTrue(liveried.instances.contains(where: \.christmas))
        XCTAssertTrue(liveried.instances.filter(\.christmas).allSatisfy { pack.christmas[$0.model] != nil })
    }

    /// Outside the event it cannot be chosen; during it, it can; after it,
    /// only with the fourth week's badge. The lines chosen reach the
    /// fourth week's mission, and the device keeps them by the game's row.
    @MainActor
    func testTheChoiceTheMissionAndTheDevicesRecord() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 2 * 1_440)
        let line = try XCTUnwrap(world.lines.first)
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        let session = GameSession(world: world, language: .traditionalChinese)

        launcher.attachChristmasLivery(to: session, row: "row-1", at: date(2026, 11, 20), calendar: calendar)
        XCTAssertFalse(session.christmasLiveryAvailable)
        session.setChristmasLivery(true, for: line.id)
        XCTAssertEqual(session.christmasLiveryChosen, [], "not before the event")

        launcher.attachChristmasLivery(to: session, row: "row-1", at: date(2026, 12, 23), calendar: calendar)
        XCTAssertTrue(session.christmasLiveryAvailable)
        session.setChristmasLivery(true, for: line.id)
        XCTAssertTrue(session.wearsChristmasLivery(line.id))
        XCTAssertEqual(session.christmasLiveryLines, [line.id])

        // The fourth week's mission sees it and keeps the livery for good.
        let eve = try XCTUnwrap(WinterMission.named("christmasEve"))
        XCTAssertTrue(eve.isMet(by: WinterMissionFacts(world: session.world, liveried: session.christmasLiveryLines)))
        launcher.checkWinterEvent(of: session, at: date(2026, 12, 23), calendar: calendar)
        XCTAssertTrue(launcher.winterEvent.hasEarned(eve, season: 2026))
        launcher.checkWinterEvent(of: session, at: date(2027, 3, 1), calendar: calendar)
        XCTAssertTrue(session.christmasLiveryAvailable, "kept for good")
        XCTAssertEqual(session.christmasLiveryLines, [line.id])

        // Kept on the device only for a game with a row (the launcher's
        // own game); a session not its own writes nothing.
        let file = directory.appendingPathComponent(GameLauncher.preferencesFileName)
        XCTAssertNil(LauncherPreferences.read(from: file)?.christmasLiveries)
    }

    /// Without the badge, after the event: not chosen, not drawn.
    @MainActor
    func testAfterTheEventWithoutTheBadgeNothingWearsIt() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 60)
        let line = try XCTUnwrap(world.lines.first)
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        let session = GameSession(world: world, language: .traditionalChinese)
        launcher.attachChristmasLivery(to: session, row: nil, at: date(2026, 12, 2), calendar: calendar)
        session.setChristmasLivery(true, for: line.id)
        XCTAssertEqual(session.christmasLiveryLines, [line.id])
        launcher.checkWinterEvent(of: session, at: date(2027, 1, 8), calendar: calendar)
        XCTAssertFalse(session.christmasLiveryAvailable)
        XCTAssertEqual(session.christmasLiveryLines, [])
        XCTAssertFalse(WinterMissionFacts(world: session.world, liveried: session.christmasLiveryLines).hasLiveriedLineRunning)
    }

    /// The preferences keep the lines by row, and read back.
    func testThePreferencesKeepTheLinesByRow() throws {
        var preferences = LauncherPreferences()
        preferences.christmasLiveries = ["row-1": [3, 7]]
        let file = directory.appendingPathComponent("prefs.data")
        preferences.write(to: file)
        XCTAssertEqual(LauncherPreferences.read(from: file)?.christmasLiveries, ["row-1": [3, 7]])
    }
}
