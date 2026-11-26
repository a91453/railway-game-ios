import GameCore

// Decision 983: the paints a player chooses for a line's trains.
//
// A model of train (a ``TrainPaintFamily``: its near set and its far set)
// lists the paints it can wear beside the one its recipe is built in. A
// paint is a list of colour swaps: every shade of one colour on the car's
// own triangles becomes the same shade of another. Nothing is added to the
// model pack and no model's vertices change: the app makes a second vertex
// buffer the first time a car is drawn in a paint, as it does for the
// Christmas livery (decision 795), so the models' hashes stay as they are
// whatever the player chooses.
//
// Which paint a line's trains wear is the player's device's to keep, by the
// game's row (``LauncherPreferences/trainPaints``), not the save's: only
// how the trains look, and no command.

/// A paint a model of train can wear in place of its own.
public struct TrainPaint: Hashable, Sendable {
    /// Every shade of ``from`` on a car becomes the same shade of ``to``
    /// (colours as the vertices carry them, ``Map3DColor``).
    public struct Swap: Hashable, Sendable {
        let from: UInt32
        let to: UInt32
        /// The heights over the rail it reaches, metres; `nil` for the
        /// whole car. For a colour the car has elsewhere too (a white
        /// body whose roof stays as it is).
        let heights: ClosedRange<Float>?

        public init(from: UInt32, to: UInt32, heights: ClosedRange<Float>? = nil) {
            self.from = from
            self.to = to
            self.heights = heights
        }
    }

    /// Its name in the device's record, its family's own: never changed
    /// once released.
    public let id: String
    let english: String
    let chinese: String
    /// The colour that stands for it in the menu, as the vertices carry
    /// theirs (``swatchRGB`` for the interface).
    let swatch: UInt32
    let swaps: [Swap]

    /// ``swatch`` as `0xRRGGBB`.
    public var swatchRGB: Int { Self.rgb(swatch) }

    static func rgb(_ colour: UInt32) -> Int {
        Int((colour & 0xFF) << 16 | (colour >> 8 & 0xFF) << 8 | (colour >> 16 & 0xFF))
    }

    public init(id: String, english: String, chinese: String, swatch: UInt32, swaps: [Swap]) {
        self.id = id
        self.english = english
        self.chinese = chinese
        self.swatch = swatch
        self.swaps = swaps
    }

    public func name(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    /// How far a channel of a vertex may lie from its colour's shade and
    /// still be that colour: the recipe's shade and the baked one
    /// (decision 439) each round once.
    static let tolerance: Float = 1.5
    /// A shade whose brightest channel would be under this is black
    /// whatever it was a shade of, and no colour's to claim: left alone.
    static let darkest: Float = 8

    /// How much of `base` the colour `colour` is, when it is a shade of
    /// it: each channel `base`'s times one factor, to within ``tolerance``.
    static func shade(of colour: UInt32, in base: UInt32) -> Float? {
        let c = channels(colour), b = channels(base)
        let size = b[0] * b[0] + b[1] * b[1] + b[2] * b[2]
        guard size > 0 else { return nil }
        let factor = (c[0] * b[0] + c[1] * b[1] + c[2] * b[2]) / size
        let brightest = max(b[0], b[1], b[2])
        guard factor * brightest >= darkest, factor <= 1 + tolerance / brightest else { return nil }
        for at in 0..<3 where abs(c[at] - factor * b[at]) > tolerance { return nil }
        return min(factor, 1)
    }

    static func channels(_ colour: UInt32) -> [Float] {
        [0, 8, 16].map { Float((colour >> UInt32($0)) & 0xFF) }
    }

    /// `vertices` (a car's in the pack, three to a triangle) in this
    /// paint: as many, where they were, each a shade of a swapped colour
    /// the same shade of the new one. Only the car's opaque paint: its
    /// glass, its lamps, what glows and its band in the line's colour (a
    /// vertex with alpha below 1) stay.
    public func painted(_ vertices: [Map3DVertex]) -> [Map3DVertex] {
        var out = vertices
        for at in out.indices {
            let vertex = out[at]
            guard vertex.color >> 24 == 0xFF, vertex.layer == Map3DVertex.plain || vertex.layer == Map3DVertex.trainSteel else { continue }
            for swap in swaps where swap.heights?.contains(vertex.z) ?? true {
                guard let factor = Self.shade(of: vertex.color, in: swap.from) else { continue }
                out[at].color = Map3DColor.shaded(swap.to, factor)
                // Decision 450: painted over, it is no longer stainless.
                if vertex.layer == Map3DVertex.trainSteel {
                    out[at].layer = Map3DVertex.plain
                    out[at].u = 0
                }
                break
            }
        }
        return out
    }
}

/// A model of train and the paints it can wear.
public struct TrainPaintFamily: Sendable {
    /// Its name in the device's record: never changed once released.
    public let id: String
    /// The sets whose cars it paints (``Map3DTrainSet/key``): the near
    /// one and its far one.
    let sets: [String]
    let english: String
    let chinese: String
    /// What its own paint, the recipe's, is called, and the colour that
    /// stands for it in the menu (``ownSwatchRGB`` for the interface).
    let ownEnglish: String
    let ownChinese: String
    let ownSwatch: UInt32
    /// The others, in the menu's order. At most 255.
    public let paints: [TrainPaint]

    public init(id: String, sets: [String], english: String, chinese: String,
                ownEnglish: String, ownChinese: String, ownSwatch: UInt32, paints: [TrainPaint]) {
        self.id = id
        self.sets = sets
        self.english = english
        self.chinese = chinese
        self.ownEnglish = ownEnglish
        self.ownChinese = ownChinese
        self.ownSwatch = ownSwatch
        self.paints = paints
    }

    /// ``ownSwatch`` as `0xRRGGBB`.
    public var ownSwatchRGB: Int { TrainPaint.rgb(ownSwatch) }

    /// The train's name.
    public func name(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    /// Its own paint's name.
    public func ownName(in language: DisplayLanguage) -> String {
        language.text(ownEnglish, ownChinese)
    }

    /// The paint called `id`; `nil` for its own, and for a name it does
    /// not have (one a later build dropped).
    public func paint(_ id: String?) -> TrainPaint? {
        id.flatMap { id in paints.first { $0.id == id } }
    }

    /// What an instance carries for the paint called `id`
    /// (``Map3DInstance/paint``): 0 for its own, else one more than its
    /// place in ``paints``.
    func slot(of id: String?) -> UInt8 {
        guard let id, let at = paints.firstIndex(where: { $0.id == id }) else { return 0 }
        return UInt8(clamping: at + 1)
    }

    /// The paint an instance's `slot` stands for.
    public func paint(slot: UInt8) -> TrainPaint? {
        slot > 0 && Int(slot) <= paints.count ? paints[Int(slot) - 1] : nil
    }

    /// Every family: the hand-written sets', then the registered trains'
    /// (``Map3DTrainRegistration/paints``), in the pack's order.
    public static let all: [TrainPaintFamily] = [Map3DTrainShapeRefresh.highSpeedPaints] + Map3DTrainRegistry.trains.compactMap(\.paints)

    /// The family that paints the set `key`'s cars.
    public static func named(set key: String) -> TrainPaintFamily? {
        index(ofSet: key).map { all[$0] }
    }

    static func index(ofSet key: String) -> Int? {
        bySet[key]
    }

    private static let bySet: [String: Int] = {
        var found: [String: Int] = [:]
        for (at, family) in all.enumerated() {
            for key in family.sets where found[key] == nil { found[key] = at }
        }
        return found
    }()

    /// The family of each model in `models` that has one, by the model's
    /// index: a car is `set-<key>-<unit>`.
    static func families(of models: [Map3DModelPack.Model]) -> [Int: Int] {
        var found: [Int: Int] = [:]
        for (index, model) in models.enumerated() where model.name.hasPrefix("set-") {
            guard let dash = model.name.lastIndex(of: "-") else { continue }
            let key = String(model.name[model.name.index(model.name.startIndex, offsetBy: 4)..<dash])
            if let family = bySet[key] { found[index] = family }
        }
        return found
    }
}

extension Map3DTrains {
    /// Decision 983: the paint family of each of `world`'s trains on line
    /// `line`, as the 3D map draws them (``Heights/init(world:)`` and
    /// ``cars(of:progress:heights:models:)``): the set its type, its
    /// number and its length come to, with the train pack's `locked` sets.
    /// None for a freight line, whose trains are drawn as freight.
    static func paintFamilies(on line: LineID, in world: GameWorld, locked: Set<String>) -> [TrainPaintFamily] {
        guard let line = world.line(id: line), !line.isFreight, !TrainPaintFamily.all.isEmpty else { return [] }
        // Decision 536: a real line bought, its own stock.
        let bought = world.acquisitions.first { $0.kind == .railway && $0.line == line.id }
            .flatMap { RealLineStock.setKey(ofRealLine: $0.realLine) }
        var found: Set<Int> = []
        for id in line.assignedTrains {
            guard let train = world.train(id: id) else { continue }
            let key = bought ?? Map3DTrainSet.key(type: train.type, performance: train.performance)
            let drawn = Map3DTrainSet.variant(of: key, number: id.rawValue, locked: locked)
            guard let set = Map3DTrainSet.set(forKey: drawn, count: max(train.cars, 1), locked: locked),
                  let family = TrainPaintFamily.index(ofSet: set.key) else { continue }
            found.insert(family)
        }
        return found.sorted().map { TrainPaintFamily.all[$0] }
    }
}

/// Decision 983: a line page's menu of one model's paints, worked out
/// before the menu is drawn (the ticks leave it alone, ``TickStable``).
public struct TrainPaintMenu: Equatable, Sendable, Identifiable {
    public struct Row: Equatable, Sendable, Identifiable {
        /// The paint's name in the record (``TrainPaint/id``), `""` for
        /// the model's own.
        public let id: String
        public let name: String
        /// `0xRRGGBB`.
        public let swatch: Int
        public let isChosen: Bool
    }

    /// The family's name in the record (``TrainPaintFamily/id``).
    public let id: String
    /// The model's name and "paint": the menu's label.
    public let title: String
    /// The model's own paint first, then the others.
    public let rows: [Row]

    /// The row the line's trains wear now.
    public var chosen: Row { rows.first(where: \.isChosen) ?? rows[0] }
}

extension GameSession {
    /// Decision 983: the paints drawn now, by line and family: those
    /// chosen for the lines the company still has.
    public var trainPaints: [LineID: [String: String]] {
        guard !trainPaintChosen.isEmpty else { return [:] }
        return trainPaintChosen.filter { chosen in world.lines.contains { $0.id == chosen.key } }
    }

    /// The models of train on `line` that have paints to choose, with the
    /// train pack's `locked` sets (``TrainPack/locked(unlocked:pushPullE1000:)``).
    public func trainPaintFamilies(on line: LineID, locked: Set<String>) -> [TrainPaintFamily] {
        Map3DTrains.paintFamilies(on: line, in: world, locked: locked)
    }

    /// The line page's menus for `line`: one for each model of train on
    /// it with paints to choose, none for most lines.
    public func trainPaintMenus(on line: LineID, locked: Set<String>) -> [TrainPaintMenu] {
        trainPaintFamilies(on: line, locked: locked).map { family in
            let chosen = trainPaint(of: family, on: line)
            let own = TrainPaintMenu.Row(id: "", name: family.ownName(in: language), swatch: family.ownSwatchRGB, isChosen: chosen == nil)
            let others = family.paints.map {
                TrainPaintMenu.Row(id: $0.id, name: $0.name(in: language), swatch: $0.swatchRGB, isChosen: chosen == $0)
            }
            let name = family.name(in: language)
            return TrainPaintMenu(id: family.id, title: language.text("\(name) paint", "\(name) 塗裝"), rows: [own] + others)
        }
    }

    /// The paint `line`'s trains of `family` wear; `nil` for their own.
    public func trainPaint(of family: TrainPaintFamily, on line: LineID) -> TrainPaint? {
        family.paint(trainPaintChosen[line]?[family.id])
    }

    /// Paints `line`'s trains of the family `menu` (``TrainPaintMenu/id``)
    /// in the paint `row` (``TrainPaintMenu/Row/id``, `""` their own).
    /// Only how they look: no command, nothing saved with the game.
    public func chooseTrainPaint(_ row: String, in menu: String, on line: LineID) {
        guard let family = TrainPaintFamily.all.first(where: { $0.id == menu }) else { return }
        setTrainPaint(family.paint(row), of: family, on: [line])
    }

    /// Puts the paint `line`'s trains of the family `menu` wear on every
    /// line that runs that model now, in one change; a line opened
    /// afterwards is chosen on its own. How many lines wear it then.
    @discardableResult
    public func putTrainPaintOnEveryLine(of menu: String, from line: LineID, locked: Set<String>) -> Int {
        guard let family = TrainPaintFamily.all.first(where: { $0.id == menu }) else { return 0 }
        let lines = lines(running: family, locked: locked)
        setTrainPaint(trainPaint(of: family, on: line), of: family, on: lines)
        return lines.count
    }

    /// The passenger lines that run a train of `family` now.
    public func lines(running family: TrainPaintFamily, locked: Set<String>) -> [LineID] {
        world.lines.map(\.id).filter { line in
            Map3DTrains.paintFamilies(on: line, in: world, locked: locked).contains { $0.id == family.id }
        }
    }

    /// Paints the trains of `family` on every line in `lines` in `paint`,
    /// or in their own (`nil`), in one change: the device is told once.
    public func setTrainPaint(_ paint: TrainPaint?, of family: TrainPaintFamily, on lines: [LineID]) {
        var chosen = trainPaintChosen.filter { chosen in world.lines.contains { $0.id == chosen.key } }
        for line in lines where world.lines.contains(where: { $0.id == line }) {
            var ofLine = chosen[line] ?? [:]
            ofLine[family.id] = family.paint(paint?.id)?.id
            chosen[line] = ofLine.isEmpty ? nil : ofLine
        }
        guard chosen != trainPaintChosen else { return }
        trainPaintChosen = chosen
        trainPaintChanged?(chosen)
    }
}
