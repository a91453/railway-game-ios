import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 806: the Christmas livery as decoration on each running car
/// (in place of decision 795's repainting); decision 795: the line page's
/// choice and the fourth week's mission.
final class Map3DChristmasLiveryTests: XCTestCase {
    private var directory: URL!
    private let calendar = WinterEvent.calendar(in: TimeZone(identifier: "Asia/Taipei")!)

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
        // The same colour darkened by one factor, each channel within a step.
        func channels(_ value: UInt32) -> [Float] { [0, 8, 16].map { Float((value >> $0) & 0xFF) } }
        let have = channels(colour), want = channels(base)
        guard let most = want.indices.max(by: { want[$0] < want[$1] }), want[most] > 0 else { return false }
        let factor = have[most] / want[most]
        return factor <= 1.001 && zip(have, want).allSatisfy { abs($0 - $1 * factor) <= 1.5 }
    }

    private func dressed(_ name: String, in pack: Map3DModelPack) throws -> (model: Map3DModelPack.Model, wear: Map3DChristmasLivery.Wear, all: [Map3DVertex]) {
        let index = try XCTUnwrap(pack.index(of: name), name)
        let model = pack.models[index], wear = try XCTUnwrap(pack.christmas[index], name)
        return (model, wear, Map3DChristmasLivery.dressed(model.vertices, minimum: model.minimum, maximum: model.maximum, wear: wear))
    }

    /// The nine trains the look was judged on (decision 806), four cars each.
    private func judged(in pack: Map3DModelPack) -> [String] {
        var names: Set<String> = []
        for code in ["highSpeed", "emu500", "emu3000", "puyuma", "wenhu370", "danhaiLRT", "mtrUrbanLine", "pushPull", "ALISHAN"] {
            for car in pack.layout(forType: code, count: 4) ?? [] { names.insert(pack.models[car.model].name) }
        }
        return names.sorted()
    }

    /// Every running car of the pack wears something, the rest nothing: a
    /// head or a single car its cab's decoration at the front, a tail at the
    /// back, a far set's car the far look; its walls' top within the car.
    func testEveryRunningCarWearsIt() {
        let pack = Map3DModelPack.standard
        var far = 0
        for (index, model) in pack.models.enumerated() {
            guard Map3DTrainLights.isRunning(model.name) else {
                XCTAssertNil(pack.christmas[index], model.name)
                continue
            }
            guard let wear = pack.christmas[index] else { XCTFail("\(model.name) wears nothing"); continue }
            let unit = model.name.split(separator: "-").last.map(String.init) ?? ""
            XCTAssertEqual(wear.front, ["head", "cab", "single"].contains(unit), model.name)
            XCTAssertEqual(wear.back, ["tail", "single"].contains(unit), model.name)
            XCTAssertGreaterThan(wear.top, model.minimum.z + (model.maximum.z - model.minimum.z) * 0.4, model.name)
            XCTAssertLessThanOrEqual(wear.top, model.maximum.z, model.name)
            if wear.far { far += 1 }
        }
        XCTAssertEqual(far, pack.models.filter { model in Map3DChristmasLivery.farPrefixes.contains { model.name.hasPrefix($0) } }.count)
        XCTAssertGreaterThan(far, 0)
    }

    /// A dressed car: its own triangles first, where they were; only faces
    /// that look up, near the walls' top, change, to a shade of the snow;
    /// no glass, no lamp and no side is touched.
    func testOnlyTheRoofIsRepainted() throws {
        let pack = Map3DModelPack.standard
        for name in judged(in: pack) + ["commuter-car", "commuter-cab"] {
            let (model, wear, all) = try dressed(name, in: pack)
            XCTAssertGreaterThan(all.count, model.vertices.count, name)
            XCTAssertEqual(all.count % 3, 0, name)
            var snowed = 0
            for (old, new) in zip(model.vertices, all) {
                XCTAssertEqual(old.position, new.position)
                guard old != new else { continue }
                snowed += 1
                XCTAssertFalse(old.glows, name)
                XCTAssertNotEqual(old.layer, Map3DVertex.trainGlass, name)
                XCTAssertGreaterThanOrEqual(old.nz, Map3DChristmasLivery.upward, "\(name): only what looks up")
                XCTAssertGreaterThan(old.z, wear.top - 1.2, name)
                XCTAssertEqual(new.color >> 24, 0xFF)
                XCTAssertTrue(isShade(new.color, of: Map3DChristmasLivery.snow), name)
                XCTAssertEqual(new.layer, Map3DVertex.plain, name)
            }
            // The Alishan cars' red roofs stay red; every other of these has snow.
            if !name.contains("ALISHAN") { XCTAssertGreaterThan(snowed, 0, "\(name): no snow") }
        }
    }

    /// The decoration: every car of the nine trains has bulbs along its
    /// roof, lit, a red one among the warm; only a cab car has the wreath's
    /// and the ribbons' triangles; all of it within the car's box and a
    /// little over it, and within the budget.
    func testTheDecorationOfTheJudgedTrains() throws {
        let pack = Map3DModelPack.standard
        for name in judged(in: pack) {
            let (model, wear, all) = try dressed(name, in: pack)
            let added = Array(all[model.vertices.count...])
            let lit = added.filter(\.glows)
            XCTAssertGreaterThanOrEqual(lit.count / 12, 6, "\(name): bulbs")
            XCTAssertTrue(lit.contains { $0.color == Map3DChristmasLivery.redBulb }, "\(name): a red bulb")
            XCTAssertTrue(lit.contains { $0.color == Map3DChristmasLivery.bulb }, "\(name): a warm bulb")
            XCTAssertLessThanOrEqual(added.count / 3, wear.front || wear.back ? 900 : 420, "\(name): triangles")
            for v in added {
                XCTAssertGreaterThanOrEqual(v.x, model.minimum.x - 0.3, name)
                XCTAssertLessThanOrEqual(v.x, model.maximum.x + 0.3, name)
                XCTAssertLessThanOrEqual(abs(v.y), max(abs(model.minimum.y), abs(model.maximum.y)) + 0.3, name)
                XCTAssertLessThanOrEqual(v.z, model.maximum.z + 1.3, name)
            }
            // Gold is the ribbons' edge: on a cab car only.
            let golden = added.contains { !$0.glows && isShade($0.color, of: Map3DChristmasLivery.gold) }
            XCTAssertEqual(golden, wear.front || wear.back, name)
        }
    }

    /// A long nose (the 700T's, the Puyuma's): the bow and the ribbons'
    /// crossing lie on the roof at its full height, not on the slope.
    func testTheRibbonsCrossOnTheRoofBehindALongNose() throws {
        let pack = Map3DModelPack.standard
        for name in ["set-highSpeed-head", "set-puyuma-head", "set-emu3000-head", "set-emu500-head"] {
            let (model, wear, all) = try dressed(name, in: pack)
            let added = Array(all[model.vertices.count...])
            // The bow's loops: the decoration's highest unlit points.
            let peak = try XCTUnwrap(added.filter { !$0.glows }.max { $0.z < $1.z }, name)
            XCTAssertGreaterThan(peak.z, wear.top, "\(name): the bow is on the roof")
            // Ribbon over the roof: gold at roof height across the whole width.
            let over = added.filter { !$0.glows && isShade($0.color, of: Map3DChristmasLivery.gold) && $0.z > wear.top - 0.4 }
            XCTAssertFalse(over.isEmpty, name)
            XCTAssertLessThan(over.map(\.y).min() ?? 0, -0.5, name)
            XCTAssertGreaterThan(over.map(\.y).max() ?? 0, 0.5, name)
            // Behind the nose: no further forward than the bow by more than the ribbons' lean.
            XCTAssertLessThan(peak.x, model.maximum.x - 2, name)
        }
    }

    /// WREATH-NOSE: on a long nose (the 700T's, the Puyuma's, the
    /// EMU3000's, the N700S's) the wreath is smaller and lies on the tip:
    /// it touches no window glass (no corner of it inside any pane's box,
    /// with a margin), stays under the windscreen's lowest corner over its
    /// width, and never reaches out past the car's front or sides.
    func testALongNosesWreathLeavesTheWindscreenClear() throws {
        let pack = Map3DModelPack.standard
        for name in ["set-highSpeed-head", "set-highSpeed-tail", "set-puyuma-head", "set-puyuma-tail",
                     "set-emu3000-head", "set-emu3000-tail", "set-n700sG-head", "highSpeed-cab"] {
            let index = try XCTUnwrap(pack.index(of: name), name)
            let model = pack.models[index], wear = try XCTUnwrap(pack.christmas[index], name)
            let half = max(abs(model.minimum.y), abs(model.maximum.y))
            for nose: Float in (wear.front ? [1] : []) + (wear.back ? [-1] : []) {
                var dresser = Dresser(model.vertices, minimum: model.minimum, maximum: model.maximum, top: wear.top)
                XCTAssertNotNil(dresser.longNose(nose), "\(name): a long nose")
                dresser.addWreath(nose: nose)
                let wreath = dresser.out
                XCTAssertFalse(wreath.isEmpty, name)
                let front = nose > 0 ? model.maximum.x : -model.minimum.x
                let width = wreath.map { abs($0.y) }.max() ?? 0
                XCTAssertLessThanOrEqual(width, half * Map3DChristmasLivery.wreath * Map3DChristmasLivery.noseWreath + 0.01, "\(name): smaller")
                for v in wreath { XCTAssertLessThanOrEqual(v.x * nose, front + 1e-4, "\(name): out past its front") }
                // Every pane of the car, side windows too, by its box.
                var lowest = Float.infinity
                for first in stride(from: 0, to: model.vertices.count - 2, by: 3)
                    where [Map3DVertex.trainGlass, Map3DVertex.trainGlassLit].contains(model.vertices[first].layer) {
                    let pane = model.vertices[first ..< first + 3]
                    let (xs, ys, zs) = (pane.map(\.x), pane.map(\.y), pane.map(\.z))
                    let margin: Float = 0.05
                    for v in wreath {
                        let inside = v.x >= xs.min()! - margin && v.x <= xs.max()! + margin && v.y >= ys.min()! - margin
                            && v.y <= ys.max()! + margin && v.z >= zs.min()! - margin && v.z <= zs.max()! + margin
                        XCTAssertFalse(inside, "\(name): the wreath at \(v.position) touches a pane")
                        if inside { break }
                    }
                    // The windscreen over the wreath's width: glass at the cab's end facing forward, over the floor.
                    if model.vertices[first].nx * nose > 0, abs(model.vertices[first].ny) < 0.6, ys.min()! <= width, ys.max()! >= -width,
                       xs.allSatisfy({ $0 * nose > front - model.length * 0.35 }), zs.min()! > model.maximum.z * 0.3 {
                        lowest = min(lowest, zs.min()!)
                    }
                }
                XCTAssertLessThan(lowest, .infinity, "\(name): a windscreen")
                XCTAssertLessThanOrEqual(wreath.map(\.z).max() ?? 0, lowest - 0.1, "\(name): under the windscreen")
            }
        }
    }

    /// A flat front keeps decision 806's wreath: no long nose there.
    func testAFlatFrontKeepsItsWreath() throws {
        let pack = Map3DModelPack.standard
        for name in ["commuter-cab", "set-emu500-head", "set-mtrUrbanLine-head", "set-wenhu370-head", "set-danhaiLRT-head",
                     "set-pushPull-head", "set-ALISHAN-head", "set-emu800-head"] {
            let index = try XCTUnwrap(pack.index(of: name), name)
            let model = pack.models[index], wear = try XCTUnwrap(pack.christmas[index], name)
            let dresser = Dresser(model.vertices, minimum: model.minimum, maximum: model.maximum, top: wear.top)
            XCTAssertNil(dresser.longNose(1), name)
        }
    }

    /// A far car: the snow and a lit line along each edge, a few triangles,
    /// no bulb of another colour, no ribbon, no glow.
    func testAFarCarWearsOnlySnowAndALitLine() throws {
        let pack = Map3DModelPack.standard
        for name in ["set-highSpeedFar-head", "set-emu500Far-panto", "set-pushPullFar-car"] {
            let (model, wear, all) = try dressed(name, in: pack)
            XCTAssertTrue(wear.far, name)
            let added = Array(all[model.vertices.count...])
            XCTAssertFalse(added.isEmpty, name)
            XCTAssertLessThanOrEqual(added.count / 3, 80, name)
            XCTAssertTrue(added.allSatisfy { $0.glows && $0.color == Map3DChristmasLivery.bulb }, name)
            XCTAssertTrue(Map3DChristmasLivery.halos(minimum: model.minimum, maximum: model.maximum, wear: wear).isEmpty)
        }
    }

    /// The glows: two a car in the livery, over its roof, after the lamps
    /// and within the frame's most; none at strength 0; steady with Reduce
    /// Motion, between the low and 1 without.
    func testTheCarsGlowsAndTheirSlowSwell() throws {
        let pack = Map3DModelPack.standard
        var frame = Map3DShowcase.frame(Map3DShowcase.layout(keys: [Map3DShowcase.catalog[0].key]), pack: pack)
        let lamps = Map3DGlow.trainSpots(of: frame, pack: pack)
        for at in frame.instances.indices { frame.instances[at].christmas = pack.christmas[frame.instances[at].model] != nil }
        let near = frame.instances.filter { $0.christmas && pack.christmas[$0.model]?.far == false }.count
        XCTAssertGreaterThan(near, 0)
        let festive = Map3DGlow.trainSpots(of: frame, pack: pack, festive: 0.5)
        XCTAssertEqual(Array(festive.prefix(lamps.count)), lamps)
        XCTAssertEqual(festive.count, min(Map3DGlow.mostTrainSpots, lamps.count + 2 * near))
        for spot in festive.dropFirst(lamps.count) { XCTAssertEqual(spot.strength, Map3DChristmasLivery.haloStrength * 0.5, accuracy: 1e-6) }
        XCTAssertEqual(Map3DGlow.trainSpots(of: frame, pack: pack, festive: 0), lamps)
        // Every train in the livery at once: still within the most.
        var all = Map3DShowcase.frame(Map3DShowcase.layout(keys: Map3DShowcase.catalog.map(\.key)), pack: pack)
        for at in all.instances.indices { all.instances[at].christmas = true }
        XCTAssertLessThanOrEqual(Map3DGlow.trainSpots(of: all, pack: pack).count, Map3DGlow.mostTrainSpots)

        for second in stride(from: 0.0, to: 10, by: 0.1) {
            XCTAssertEqual(Map3DChristmasLivery.twinkle(seconds: second, reduceMotion: true), 1)
            let value = Map3DChristmasLivery.twinkle(seconds: second, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(value, Map3DChristmasLivery.twinkleLow)
            XCTAssertLessThanOrEqual(value, 1)
        }
        XCTAssertEqual(Map3DChristmasLivery.twinkle(seconds: 0, reduceMotion: false), Map3DChristmasLivery.twinkleLow)
        XCTAssertEqual(Map3DChristmasLivery.twinkle(seconds: Map3DChristmasLivery.twinklePeriod / 2, reduceMotion: false), 1, accuracy: 1e-5)
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

    /// L25 P3-1 (decision 814): a game never saved by hand has no row, so
    /// its livery had nowhere to be kept, and an autosave read back after
    /// the app reopened wore none. The first choice now gives the game its
    /// row, which its autosaves name.
    @MainActor
    func testAGameOnlyAutosavedKeepsItsLiveryWhenTheAppReopens() async throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 60)
        let line = try XCTUnwrap(world.lines.first)
        let library = SaveLibrary(directory: directory)
        try library.save(world, as: .autosave, at: date(2026, 12, 23))
        do {
            let launcher = GameLauncher(library: library, language: .traditionalChinese)
            await launcher.continueGame(at: date(2026, 12, 23))?.value
            let session = try XCTUnwrap(launcher.session)
            XCTAssertNil(launcher.gameRow, "never saved by hand")
            launcher.attachChristmasLivery(to: session, row: launcher.gameRow, at: date(2026, 12, 23), calendar: calendar)
            session.setChristmasLivery(true, for: line.id)
            XCTAssertNotNil(launcher.gameRow, "the first choice gives the game its row")
            XCTAssertTrue(launcher.autosaveCurrentGame(at: date(2026, 12, 23)))
        }
        let reopened = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await reopened.continueGame(at: date(2026, 12, 24))?.value
        let session = try XCTUnwrap(reopened.session)
        XCTAssertEqual(session.christmasLiveryChosen, [line.id], "the autosave's row keeps it")
        XCTAssertEqual(reopened.entries.count, 1, "no save of the player's was made")
    }

    /// Decision 795 (later): one change puts it on every passenger line or
    /// takes it off them all, the device is told once, and not outside the
    /// event.
    @MainActor
    func testEveryPassengerLineAtOnce() throws {
        // NewGameCampaignTests' two lines: a second beside the first.
        let bounds = GameWorld.newGameBounds, towns = Land.townCentres(seed: 1, in: bounds)
        let first = towns[0], second = towns[1]
        let edgeX = second.x > first.x ? 40_000 : bounds.width - 40_000
        let edge = PlanPoint(x: edgeX, y: first.y + (first.y - second.y) * (edgeX - first.x) / (first.x - second.x))
        var world = try newGameLine(through: [first, second])
        world = try newGameLine(through: [PlanPoint(x: first.x, y: first.y + 6_144), PlanPoint(x: edge.x, y: edge.y + 6_144)], in: world)
        let lines = Set(world.lines.filter { !$0.isFreight }.map(\.id))
        XCTAssertEqual(lines.count, 2)
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        let session = GameSession(world: world, language: .traditionalChinese)

        launcher.attachChristmasLivery(to: session, row: "row-1", at: date(2026, 11, 20), calendar: calendar)
        session.setChristmasLiveryOnAllPassengerLines(true)
        XCTAssertEqual(session.christmasLiveryChosen, [], "not before the event")
        XCTAssertFalse(session.allPassengerLinesWearChristmasLivery)

        launcher.attachChristmasLivery(to: session, row: "row-1", at: date(2026, 12, 23), calendar: calendar)
        var told = 0
        let keep = session.christmasLiveryChanged
        session.christmasLiveryChanged = { told += 1; keep?($0) }
        session.setChristmasLivery(true, for: try XCTUnwrap(lines.first))
        XCTAssertFalse(session.allPassengerLinesWearChristmasLivery, "one of two")
        told = 0
        session.setChristmasLiveryOnAllPassengerLines(true)
        XCTAssertEqual(session.christmasLiveryLines, lines)
        XCTAssertTrue(session.allPassengerLinesWearChristmasLivery)
        XCTAssertEqual(told, 1)
        session.setChristmasLiveryOnAllPassengerLines(true)
        XCTAssertEqual(told, 1, "nothing changed, nothing told")

        session.setChristmasLiveryOnAllPassengerLines(false)
        XCTAssertEqual(session.christmasLiveryLines, [])
        XCTAssertFalse(session.allPassengerLinesWearChristmasLivery)
        XCTAssertEqual(told, 2)
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
