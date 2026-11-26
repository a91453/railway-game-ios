import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 983: the paints a player chooses for a line's trains.
final class TrainPaintTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("TrainPaintTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A high-speed track with four stations: `fast` and `second`, two
    /// high-speed lines staffed with high-speed sets, and `plain`, an
    /// ordinary line staffed with ordinary trains.
    @MainActor
    private func session() throws -> (session: GameSession, fast: LineID, second: LineID, plain: LineID) {
        let track = TestLine(tiles: 9, row: 1, gauge: .shinkansen)
        var world = try makeWorld(width: 9_216, height: 4_096, balance: 100_000_000, speed: .normal)
        try track.build(in: &world)
        var stops: [StationID] = []
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5), ("Delta", 7)] {
            stops.append(try track.buildStation(named: name, beside: x, at: 0, in: &world))
        }
        let fast = try world.createLine(named: "Fast", stops: stops).id
        let second = try world.createLine(named: "Second", stops: [stops[0], stops[3]]).id
        let plain = try world.createLine(named: "Plain", stops: [stops[1], stops[2]]).id
        for line in [fast, second, plain] { try world.setLineServiceWindow(line, to: .allDay) }
        try world.setLinePerformance(fast, to: .highSpeed)
        try world.setLinePerformance(second, to: .highSpeed)
        let session = GameSession(world: world, language: .traditionalChinese)
        for line in [fast, second, plain] {
            session.selectLine(line)
            session.staffSelectedLine(headway: 10)
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        return (session, fast, second, plain)
    }

    /// The families: names of their own, sets the map has (a near set
    /// with its far one), cars in the pack, and paints with names of
    /// their own, each of which changes some car of the family.
    func testEveryFamilyPaintsCarsOfThePack() throws {
        let pack = Map3DModelPack.standard
        XCTAssertFalse(TrainPaintFamily.all.isEmpty)
        XCTAssertEqual(Set(TrainPaintFamily.all.map(\.id)).count, TrainPaintFamily.all.count)
        var claimed: Set<String> = []
        for (at, family) in TrainPaintFamily.all.enumerated() {
            XCTAssertFalse(family.id.isEmpty)
            XCTAssertFalse(family.paints.isEmpty, family.id)
            XCTAssertLessThanOrEqual(family.paints.count, 255, family.id)
            XCTAssertEqual(Set(family.paints.map(\.id)).count, family.paints.count, family.id)
            XCTAssertFalse(family.paints.contains { $0.id.isEmpty }, "\(family.id): \"\" is its own paint")
            for key in family.sets {
                let set = try XCTUnwrap(Map3DTrainSet.byKey[key], "\(family.id): no set \(key)")
                XCTAssertTrue(claimed.insert(key).inserted, "\(key) is in two families")
                if let far = set.far { XCTAssertTrue(family.sets.contains(far), "\(family.id): \(key)'s far set \(far)") }
                XCTAssertEqual(TrainPaintFamily.named(set: key)?.id, family.id)
            }
            let cars = pack.paintFamilies.filter { $0.value == at }.keys.sorted()
            XCTAssertFalse(cars.isEmpty, "\(family.id): no car in the pack")
            for car in cars { XCTAssertEqual(pack.paintFamily(of: car)?.id, family.id) }
            for (place, paint) in family.paints.enumerated() {
                XCTAssertEqual(family.slot(of: paint.id), UInt8(place + 1))
                XCTAssertEqual(family.paint(slot: UInt8(place + 1)), paint)
                XCTAssertEqual(family.paint(paint.id), paint)
                for swap in paint.swaps {
                    let alone = TrainPaint(id: paint.id, english: "", chinese: "", swatch: paint.swatch, swaps: [swap])
                    XCTAssertTrue(cars.contains { alone.painted(pack.models[$0].vertices) != pack.models[$0].vertices },
                                  "\(family.id) \(paint.id): a swap that changes no car")
                }
            }
            XCTAssertEqual(family.slot(of: nil), 0)
            XCTAssertEqual(family.slot(of: "a paint it never had"), 0)
            XCTAssertNil(family.paint(slot: 0))
            XCTAssertNil(family.paint(slot: UInt8(family.paints.count + 1)))
        }
        // A car of no family: the pack's first, a box.
        XCTAssertNil(pack.paintFamily(of: 0))
    }

    /// A painted car: as many vertices, where they were, facing as they
    /// did; only opaque paint changes, each shade of the old colour the
    /// same shade of the new one; glass, lamps and the band in the line's
    /// colour stay; none of the old colour is left.
    func testAPaintSwapsItsColourShadeForShade() throws {
        let pack = Map3DModelPack.standard
        for (at, family) in TrainPaintFamily.all.enumerated() {
            for paint in family.paints {
                for car in pack.paintFamilies.filter({ $0.value == at }).keys.sorted() {
                    let model = pack.models[car], name = "\(model.name) in \(paint.id)"
                    let painted = paint.painted(model.vertices)
                    XCTAssertEqual(painted.count, model.vertices.count, name)
                    // Each pair of colours once: a car has thousands of vertices in a few.
                    var pairs: Set<[UInt32]> = []
                    var kept = true
                    for (old, new) in zip(model.vertices, painted) where old != new {
                        var same = new
                        same.color = old.color
                        same.layer = old.layer
                        same.u = old.u
                        // Where it was, facing as it did; no band in the line's colour, no lamp, no glass.
                        kept = kept && same == old && old.color >> 24 == 0xFF && !old.glows && new.layer == Map3DVertex.plain
                            && (old.layer == Map3DVertex.plain || old.layer == Map3DVertex.trainSteel)
                        pairs.insert([old.color, new.color])
                    }
                    XCTAssertTrue(kept, "\(name): more than its opaque paint's colour changed")
                    for pair in pairs {
                        XCTAssertEqual(pair[1] >> 24, 0xFF, name)
                        let swap = try XCTUnwrap(paint.swaps.first { TrainPaint.shade(of: pair[0], in: $0.from) != nil }, name)
                        let before = try XCTUnwrap(TrainPaint.shade(of: pair[0], in: swap.from))
                        let after = try XCTUnwrap(TrainPaint.shade(of: pair[1], in: swap.to), name)
                        XCTAssertEqual(after, before, accuracy: 0.02, name)
                    }
                    // Painted again, nothing more changes unless a swap's new colour is another's old one.
                    if Set(paint.swaps.map(\.from)).isDisjoint(with: paint.swaps.map(\.to)) {
                        XCTAssertEqual(paint.painted(painted), painted, name)
                    }
                }
            }
        }
    }

    /// The 700T: built in its real orange band; "teal" turns every orange
    /// triangle the game's earlier teal and leaves its white body, its
    /// black line and its glass alone, on every car (decision 988: the
    /// owner's old cars, with no far set).
    func testThe700TsOrangeBandTurnsTeal() throws {
        let pack = Map3DModelPack.standard
        let family = try XCTUnwrap(TrainPaintFamily.named(set: "highSpeed"))
        XCTAssertEqual(family.ownSwatchRGB, 0xEA6A1E, "the 2D map's orange (TrainLivery.highSpeed)")
        XCTAssertEqual(family.ownSwatchRGB, TrainLivery.highSpeed.stripe)
        let teal = try XCTUnwrap(family.paint("teal"))
        let orange = Map3DTrainShapeRefresh.highSpeedBandColor, game = Map3DTrainShapeRefresh.highSpeedGameBandColor
        func count(_ vertices: [Map3DVertex], shadesOf colour: UInt32) -> Int {
            vertices.filter { $0.color >> 24 == 0xFF && !$0.glows && $0.layer == Map3DVertex.plain && TrainPaint.shade(of: $0.color, in: colour) != nil }.count
        }
        for name in ["set-highSpeed-head", "set-highSpeed-car", "set-highSpeed-panto", "set-highSpeed-tail",
                     "set-highSpeed-carBack", "set-highSpeed-pantoBack"] {
            let model = pack.models[try XCTUnwrap(pack.index(of: name), name)]
            let banded = count(model.vertices, shadesOf: orange)
            XCTAssertGreaterThan(banded, 0, "\(name): an orange band")
            XCTAssertEqual(count(model.vertices, shadesOf: game), 0, "\(name): no teal of its own")
            let painted = teal.painted(model.vertices)
            XCTAssertEqual(count(painted, shadesOf: orange), 0, "\(name): no orange left")
            XCTAssertEqual(count(painted, shadesOf: game), banded, "\(name): every orange vertex teal")
            XCTAssertEqual(zip(model.vertices, painted).filter { $0 != $1 }.count, banded, "\(name): nothing else")
        }
    }

    /// A shade is its colour times one factor; another colour, and a
    /// black too dark to tell, is no shade of it.
    func testWhatCountsAsAShade() {
        let orange = Map3DColor.rgb(0xEA6A1E)
        XCTAssertEqual(TrainPaint.shade(of: orange, in: orange), 1)
        XCTAssertEqual(TrainPaint.shade(of: Map3DColor.shaded(orange, 0.62), in: orange) ?? 0, 0.62, accuracy: 0.01)
        XCTAssertEqual(TrainPaint.shade(of: Map3DColor.shaded(Map3DColor.shaded(orange, 0.8), 0.7), in: orange) ?? 0, 0.56, accuracy: 0.01)
        XCTAssertNil(TrainPaint.shade(of: Map3DColor.rgb(0xF6F6F4), in: orange), "white")
        XCTAssertNil(TrainPaint.shade(of: Map3DColor.rgb(0x3E8C8C), in: orange), "teal")
        XCTAssertNil(TrainPaint.shade(of: Map3DColor.rgb(0xEA1E6A), in: orange), "its channels in another order")
        XCTAssertNil(TrainPaint.shade(of: Map3DColor.rgb(0x030201), in: orange), "black")
        XCTAssertNil(TrainPaint.shade(of: orange, in: Map3DColor.rgb(0x000000)))
        XCTAssertEqual(TrainPaint.rgb(orange), 0xEA6A1E)
        // Only between its heights.
        let low = TrainPaint(id: "low", english: "", chinese: "", swatch: orange,
                             swaps: [TrainPaint.Swap(from: orange, to: Map3DColor.rgb(0x3E8C8C), heights: 0...1)])
        var under = Map3DVertex(Map3DPoint(0, 0, 0.5), normal: Map3DPoint(0, 0, 1), color: orange), over = under
        over.z = 2
        XCTAssertEqual(low.painted([under, over]).map(\.color), [Map3DColor.rgb(0x3E8C8C), orange])
        // A stainless side painted over is plain paint.
        under.layer = Map3DVertex.trainSteel
        under.u = 0.7
        let repainted = low.painted([under])[0]
        XCTAssertEqual(repainted.layer, Map3DVertex.plain)
        XCTAssertEqual(repainted.u, 0)
    }

    /// The 3D map's frame: the cars of the chosen line's 700Ts carry the
    /// paint's slot, every other car none.
    @MainActor
    func testTheFrameMarksTheChosenLinesCars() throws {
        let (session, fast, _, plain) = try session()
        var world = session.world
        try world.advance(ticks: 90)
        let scene = Map3DScene(world: world), motion = TrainMotion(world: world, time: 0), heights = Map3DTrains.Heights(world: world)
        var pack = Map3DModelPack.standard
        // Every high-speed set a 700T, as while the train pack is locked.
        pack.locked = [Map3DN700S.key]
        let boxes = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: nil, eye: nil)
        let eye = try XCTUnwrap(boxes.boxes.vertices.first?.position) + Map3DPoint(0, 100, 0)
        let own = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: pack, eye: eye)
        XCTAssertTrue(own.instances.contains { pack.paintFamily(of: $0.model) != nil }, "a 700T in sight")
        XCTAssertFalse(own.instances.contains { $0.paint != 0 })

        let chosen = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: pack, eye: eye,
                                       paints: [fast: ["highSpeed": "teal"], plain: ["highSpeed": "teal"]])
        XCTAssertEqual(chosen.instances.count, own.instances.count)
        let painted = chosen.instances.filter { $0.paint != 0 }
        XCTAssertFalse(painted.isEmpty)
        XCTAssertTrue(painted.allSatisfy { $0.paint == 1 && pack.paintFamily(of: $0.model)?.id == "highSpeed" })
        // The second high-speed line's sets, not chosen, and the plain line's trains keep their own.
        XCTAssertLessThan(painted.count, own.instances.filter { pack.paintFamily(of: $0.model) != nil }.count)
        for (before, after) in zip(own.instances, chosen.instances) {
            XCTAssertEqual(after.model, before.model)
            XCTAssertEqual(after.transform, before.transform)
        }
        // A paint the family never had, and a family the line does not run: their own.
        let unknown = Map3DTrains.frame(motion, progress: 1, heights: heights, in: scene, models: pack, eye: eye,
                                        paints: [fast: ["highSpeed": "plaid", "steam": "teal"]])
        XCTAssertFalse(unknown.instances.contains { $0.paint != 0 })
    }

    /// The line page: a menu for the 700T on a high-speed line (its own
    /// orange first and chosen), none on a line of ordinary trains; a
    /// choice is the line's alone, tells the device once, and its own
    /// paint leaves no record.
    @MainActor
    func testTheLinePagesMenuAndTheChoice() throws {
        let (session, fast, second, plain) = try session()
        let locked: Set<String> = [Map3DN700S.key]
        XCTAssertEqual(session.trainPaintMenus(on: plain, locked: locked), [])
        XCTAssertEqual(session.trainPaintMenus(on: LineID(rawValue: 999), locked: locked), [])
        let menu = try XCTUnwrap(session.trainPaintMenus(on: fast, locked: locked).first)
        XCTAssertEqual(session.trainPaintMenus(on: fast, locked: locked).count, 1)
        XCTAssertEqual(menu.id, "highSpeed")
        XCTAssertEqual(menu.title, "700T 塗裝")
        XCTAssertEqual(menu.rows.map(\.id), ["", "teal"])
        XCTAssertEqual(menu.rows.map(\.name), ["橘色帶", "青綠帶"])
        XCTAssertEqual(menu.rows.map(\.isChosen), [true, false])
        XCTAssertEqual(menu.chosen.id, "")
        XCTAssertEqual(menu.rows[0].swatch, 0xEA6A1E)
        XCTAssertNotEqual(menu.rows[1].swatch, menu.rows[0].swatch)
        // With the train pack open the odd-numbered sets are the N700ST (N700ST-PAINT),
        // whose orange line the same menu paints: the menu is there whichever is on the line.
        XCTAssertEqual(session.trainPaintMenus(on: fast, locked: []).map(\.id), ["highSpeed"])

        var told: [[LineID: [String: String]]] = []
        session.trainPaintChanged = { told.append($0) }
        session.chooseTrainPaint("teal", in: "highSpeed", on: fast)
        XCTAssertEqual(session.trainPaintChosen, [fast: ["highSpeed": "teal"]])
        XCTAssertEqual(session.trainPaints, [fast: ["highSpeed": "teal"]])
        XCTAssertEqual(told, [[fast: ["highSpeed": "teal"]]])
        XCTAssertEqual(session.trainPaintMenus(on: fast, locked: locked).first?.chosen.id, "teal")
        XCTAssertEqual(session.trainPaintMenus(on: second, locked: locked).first?.chosen.id, "", "the other line keeps its own")
        session.chooseTrainPaint("teal", in: "highSpeed", on: fast)
        XCTAssertEqual(told.count, 1, "nothing changed, nothing told")
        session.chooseTrainPaint("teal", in: "no such model", on: fast)
        session.chooseTrainPaint("teal", in: "highSpeed", on: LineID(rawValue: 999))
        XCTAssertEqual(told.count, 1)
        XCTAssertEqual(session.undoCount, 3, "no command: only the three lines' trains were bought")

        session.chooseTrainPaint("", in: "highSpeed", on: fast)
        XCTAssertEqual(session.trainPaintChosen, [:])
        XCTAssertEqual(told.count, 2)
        // A paint a later build dropped reads as the model's own.
        session.trainPaintChosen = [fast: ["highSpeed": "plaid"]]
        XCTAssertEqual(session.trainPaintMenus(on: fast, locked: locked).first?.chosen.id, "")
        // In English.
        let english = GameSession(world: session.world, language: .english)
        XCTAssertEqual(english.trainPaintMenus(on: fast, locked: locked).first?.title, "700T paint")
        XCTAssertEqual(english.trainPaintMenus(on: fast, locked: locked).first?.rows.map(\.name), ["Orange band", "Teal band"])
    }

    /// One change puts a line's choice on every line running that model,
    /// and on no other; the device is told once.
    @MainActor
    func testEveryLineRunningTheModelAtOnce() throws {
        let (session, fast, second, plain) = try session()
        let locked: Set<String> = [Map3DN700S.key]
        let family = try XCTUnwrap(TrainPaintFamily.named(set: "highSpeed"))
        XCTAssertEqual(Set(session.lines(running: family, locked: locked)), [fast, second])
        var told = 0
        session.trainPaintChanged = { _ in told += 1 }
        session.chooseTrainPaint("teal", in: "highSpeed", on: second)
        told = 0
        XCTAssertEqual(session.putTrainPaintOnEveryLine(of: "highSpeed", from: second, locked: locked), 2)
        XCTAssertEqual(session.trainPaintChosen, [fast: ["highSpeed": "teal"], second: ["highSpeed": "teal"]])
        XCTAssertNil(session.trainPaintChosen[plain])
        XCTAssertEqual(told, 1)
        session.putTrainPaintOnEveryLine(of: "highSpeed", from: fast, locked: locked)
        XCTAssertEqual(told, 1, "nothing changed, nothing told")
        // Back to their own on one, then on all.
        session.chooseTrainPaint("", in: "highSpeed", on: fast)
        told = 0
        session.putTrainPaintOnEveryLine(of: "highSpeed", from: fast, locked: locked)
        XCTAssertEqual(session.trainPaintChosen, [:])
        XCTAssertEqual(told, 1)
        XCTAssertEqual(session.putTrainPaintOnEveryLine(of: "no such model", from: fast, locked: locked), 0)
    }

    /// The device keeps the paints by the game's row, not the save: a
    /// game only autosaved takes its row at the first choice (decision
    /// 814's way), and the app reopened wears them again; a line that is
    /// gone wears none.
    @MainActor
    func testTheDeviceKeepsThePaintsByTheGamesRow() async throws {
        let (made, fast, second, _) = try session()
        let library = SaveLibrary(directory: directory)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        try library.save(made.world, as: .autosave, at: day)
        let file = directory.appendingPathComponent(GameLauncher.preferencesFileName)
        do {
            let launcher = GameLauncher(library: library, language: .traditionalChinese)
            await launcher.continueGame(at: day)?.value
            let session = try XCTUnwrap(launcher.session)
            XCTAssertNil(launcher.gameRow, "never saved by hand")
            XCTAssertEqual(session.trainPaintChosen, [:])
            session.chooseTrainPaint("teal", in: "highSpeed", on: fast)
            let row = try XCTUnwrap(launcher.gameRow, "the first choice gives the game its row")
            XCTAssertEqual(LauncherPreferences.read(from: file)?.trainPaints, [row: [String(fast.rawValue): ["highSpeed": "teal"]]])
            session.chooseTrainPaint("teal", in: "highSpeed", on: second)
            session.chooseTrainPaint("", in: "highSpeed", on: second)
            XCTAssertEqual(LauncherPreferences.read(from: file)?.trainPaints, [row: [String(fast.rawValue): ["highSpeed": "teal"]]])
            XCTAssertTrue(launcher.autosaveCurrentGame(at: day))
        }
        let reopened = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await reopened.continueGame(at: day.addingTimeInterval(86_400))?.value
        let session = try XCTUnwrap(reopened.session)
        XCTAssertEqual(session.trainPaintChosen, [fast: ["highSpeed": "teal"]], "the autosave's row keeps it")
        XCTAssertEqual(reopened.entries.count, 1, "no save of the player's was made")

        // The line deleted: nothing drawn for it, and the next choice drops its record.
        session.selectLine(fast)
        session.removeSelectedLine()
        XCTAssertNil(session.world.line(id: fast))
        XCTAssertEqual(session.trainPaints, [:])
        session.chooseTrainPaint("teal", in: "highSpeed", on: second)
        XCTAssertEqual(session.trainPaintChosen, [second: ["highSpeed": "teal"]])
        // Back to its own everywhere: the row's record goes.
        session.chooseTrainPaint("", in: "highSpeed", on: second)
        XCTAssertNil(LauncherPreferences.read(from: file)?.trainPaints)
    }

    /// The preferences keep the paints by row, line and model, and a file
    /// written before them reads back with none.
    func testThePreferencesKeepThePaintsByRow() throws {
        var preferences = LauncherPreferences()
        let file = directory.appendingPathComponent("prefs.data")
        preferences.write(to: file)
        XCTAssertNil(LauncherPreferences.read(from: file)?.trainPaints)
        preferences.trainPaints = ["row-1": ["3": ["highSpeed": "teal"], "7": ["highSpeed": "teal"]]]
        preferences.write(to: file)
        XCTAssertEqual(LauncherPreferences.read(from: file)?.trainPaints, ["row-1": ["3": ["highSpeed": "teal"], "7": ["highSpeed": "teal"]]])
    }
}
