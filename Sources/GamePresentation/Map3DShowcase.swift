import Foundation
import GameCore

/// Decision 434: the train showcase, every train the 3D map draws laid out
/// on open ground to look at, turn round and photograph. The demo mode's
/// (decision 351) for now; its input is only which trains and how many
/// cars, so the train pack's 3D preview can take the same scene later.
///
/// The rows are laid as `tools/map3d-preview` lays decision 318's rows
/// (`MAP3D_TRAINS`): a set drawn at its models' own lengths by
/// ``Map3DModelPack/layout(forType:count:)``, any other a car each 20 m,
/// 20.5 m apart, the last one the head turned round unless its set has a
/// tail; each car stood with ``Map3DTrains/instance(of:index:from:to:stripe:)``.
/// The heads all face +x, level with each other at x 0, the first row at
/// z 0 and the next ones ``rowSpacing`` further toward +z.
public enum Map3DShowcase {
    /// The kinds the picker groups the trains in.
    public enum Category: String, CaseIterable, Sendable {
        case taiwanRailway, highSpeed, metro, lightRail, other

        public func name(in language: DisplayLanguage) -> String {
            switch self {
            case .taiwanRailway: language.text("Taiwan Railway", "台鐵")
            case .highSpeed: language.text("High-Speed Rail", "高鐵")
            case .metro: language.text("Metro", "捷運")
            case .lightRail: language.text("Light Rail", "輕軌")
            case .other: language.text("Other", "其他")
            }
        }

        /// The track's gauge under them, metres: the high-speed line's,
        /// the metros' and the light rail's standard gauge, Taiwan
        /// Railway's 1,067 mm (the steam train and the commuter sets run
        /// on it too).
        var gauge: Float {
            switch self {
            case .highSpeed, .metro, .lightRail: 1.435
            case .taiwanRailway, .other: 1.067
            }
        }
    }

    /// One train in the catalog: its set (``Map3DTrainSet/key``, never a
    /// far one), its name, its kind and how many cars it is shown with.
    public struct Entry: Equatable, Identifiable, Sendable {
        public let key: String
        public let english: String
        public let chinese: String
        public let category: Category
        /// The cars it starts with, and the most it can have (the least is
        /// 1, or ``mostCars`` for a formation that never changes).
        public let defaultCars: Int
        public let mostCars: Int
        /// The fewest cars it can have: a set of a fixed formation always
        /// has its own.
        public let fewestCars: Int
        /// The band of a set that takes its line's colour (0xRRGGBB).
        let stripe: UInt32

        public var id: String { key }

        public func name(in language: DisplayLanguage) -> String {
            language.text(english, chinese)
        }

        init(_ key: String, _ english: String, _ chinese: String, _ category: Category, cars: Int, most: Int? = nil,
             fixed: Bool = false, stripe: UInt32 = 0x2F6DB5) {
            self.key = key
            self.english = english
            self.chinese = chinese
            self.category = category
            defaultCars = cars
            mostCars = most ?? cars
            fewestCars = fixed ? cars : 1
            self.stripe = stripe
        }
    }

    /// Every train the 3D map draws with a model of its own, once: each
    /// near set of ``Map3DTrainSet/all`` (its far one is the far switch),
    /// by kind, the newer trains first in each. The names are the game's
    /// own where it has one (`TrainTypeSpec`'s names in `DisplayText`,
    /// ``PerformancePreset``'s, the train pack's in Settings).
    public static let catalog: [Entry] = [
        // Taiwan Railway: the multiple units by when they first ran, then
        // the locomotive-hauled trains, then the sightseeing trains.
        Entry("emu3000", "EMU3000 Tze-Chiang", "EMU3000 新自強號", .taiwanRailway, cars: 12),
        // Decision 435: and the EMU900, ten cars as it runs.
        Entry("emu900", "EMU900 local", "EMU900 區間車", .taiwanRailway, cars: 10),
        Entry("emu800", "EMU800 local", "EMU800 區間車", .taiwanRailway, cars: 8),
        Entry("puyuma", "TEMU2000 Puyuma", "TEMU2000 普悠瑪號", .taiwanRailway, cars: 8, fixed: true),
        Entry("taroko", "TEMU1000 Taroko", "TEMU1000 太魯閣號", .taiwanRailway, cars: 8, fixed: true),
        Entry("dieselRailcar", "DR1000 railcar", "DR1000 柴油客車", .taiwanRailway, cars: 2, most: 3),
        Entry("dieselExpress", "DR3100 diesel Tze-Chiang", "DR3100 柴聯自強號", .taiwanRailway, cars: 6, most: 9),
        Entry("pushPullE1000", "Push-pull Tze-Chiang, E1000", "推拉式自強號（E1000）", .taiwanRailway, cars: 12, most: 14),
        Entry("emu500", "EMU500 local", "EMU500 區間車", .taiwanRailway, cars: 8),
        Entry("pushPull", "Push-pull Tze-Chiang, E500", "推拉式自強號（E500）", .taiwanRailway, cars: 12, most: 14),
        Entry("R200CK", "Chu-Kuang, R200 diesel", "莒光號（R200 柴電機車）", .taiwanRailway, cars: 8, most: 12),
        Entry("E500CK", "Chu-Kuang, E500 locomotive", "莒光號（E500 電力機車）", .taiwanRailway, cars: 8, most: 12),
        Entry("E200CK", "Chu-Kuang, E200 locomotive", "莒光號（E200 電力機車）", .taiwanRailway, cars: 8, most: 12),
        Entry("R100CK", "Chu-Kuang, R100 diesel", "莒光號（R100 柴電機車）", .taiwanRailway, cars: 8, most: 12),
        Entry("BLUE", "Blue Train sightseeing train", "藍皮解憂號", .taiwanRailway, cars: 6, most: 10),
        Entry("MINGRI", "Ming-Ri sightseeing train", "鳴日號", .taiwanRailway, cars: 8, most: 10),
        Entry("SUMMER", "Midsummer Formosa steam train", "仲夏寶島號", .taiwanRailway, cars: 6, most: 10),
        Entry("STAR", "Formosa Star sightseeing train", "環島之星", .taiwanRailway, cars: 8, most: 10),
        // High-speed rail.
        Entry("n700sG", "N700S-G", "N700S-G", .highSpeed, cars: 12),
        Entry("highSpeed", "THSR 700T", "台灣高鐵 700T", .highSpeed, cars: 12),
        // Metro: the C381 in the Bannan line's blue and the Wenhu line's
        // car in its brown, as their bands take a line's colour.
        Entry("metroC341", "Taipei Metro C341", "台北捷運 C341", .metro, cars: 6),
        Entry("metroC381", "Taipei Metro C381", "台北捷運 C381", .metro, cars: 6, stripe: 0x0070BD),
        Entry("wenhu", "Taipei Metro Wenhu line", "台北捷運文湖線", .metro, cars: 4, stripe: 0xC48C31),
        Entry("fourCarMetro", "Four-car metro", "四節捷運列車", .metro, cars: 4, most: 6),
        // Light rail.
        Entry("greenTram", "Green low-floor tram", "綠色低地板電車", .lightRail, cars: 2, most: 4),
        Entry("fiveSectionLRT", "Five-section light rail", "五節輕軌電車", .lightRail, cars: 2, fixed: true),
        Entry("sevenSectionLRT", "Seven-section light rail", "七節輕軌電車", .lightRail, cars: 3, fixed: true),
        Entry("blueSeven", "Seven-section blue tram", "七節藍色電車", .lightRail, cars: 7, fixed: true),
        // Other: the steam train and the short commuter sets.
        Entry("STEAM", "Steam train", "蒸汽列車", .other, cars: 6, most: 10),
        Entry("threeCarUrban", "Three-car urban EMU", "三節都市電聯車", .other, cars: 3, fixed: true),
        Entry("greenCommuter", "Two-car green EMU", "兩節綠色電聯車", .other, cars: 2, fixed: true),
    ]

    /// The entry of `key`.
    public static func entry(_ key: String) -> Entry? {
        catalog.first { $0.key == key }
    }

    /// The trains shown first: one of each kind people photograph most,
    /// Taiwan Railway's newest two, the Taipei Metro's newest, the
    /// high-speed set and the Puyuma.
    public static let defaultKeys = ["emu3000", "emu800", "metroC341", "highSpeed", "puyuma"]

    /// The most trains shown at once: eight rows 9 m apart are 63 m
    /// across, which the overhead view still shows whole on a phone held
    /// upright, and eight twelve-car sets (some 2,400 triangles a car near,
    /// up to 11,500 a cab) stay within what the 3D map draws of trains.
    public static let mostRows = 8

    /// The trains picked, in the order picked, and each one's cars.
    public struct Selection: Equatable, Sendable {
        public private(set) var keys: [String]
        public private(set) var cars: [String: Int] = [:]

        public init(keys: [String] = Map3DShowcase.defaultKeys) {
            self.keys = Array(keys.filter { Map3DShowcase.entry($0) != nil }.prefix(Map3DShowcase.mostRows))
        }

        public var isFull: Bool { keys.count >= Map3DShowcase.mostRows }

        /// Picks `key`, or puts it back; `false` when it could not be
        /// picked, ``mostRows`` being shown already.
        @discardableResult
        public mutating func toggle(_ key: String) -> Bool {
            if let index = keys.firstIndex(of: key) {
                keys.remove(at: index)
                return true
            }
            guard !isFull, Map3DShowcase.entry(key) != nil else { return false }
            keys.append(key)
            return true
        }

        /// The cars `key` is shown with.
        public func cars(of key: String) -> Int {
            cars[key] ?? Map3DShowcase.entry(key)?.defaultCars ?? 1
        }

        /// Shows `key` with `count` cars, kept within its entry's range.
        public mutating func setCars(_ count: Int, of key: String) {
            guard let entry = Map3DShowcase.entry(key) else { return }
            cars[key] = min(max(count, entry.fewestCars), entry.mostCars)
        }
    }

    // MARK: - The rows

    /// The rows' spacing, metres, as the preview tool's rows with room
    /// for each one's ballast between.
    public static let rowSpacing: Float = 9
    /// The rails' top over the ground, metres: the 3D map's ballast
    /// (``Map3DScene/Builder/bedDrop`` under it) standing on the ground.
    public static let railTop: Float = 0.5
    /// A car's length and pitch when its set is not drawn at its models'
    /// own lengths, as the preview tool's.
    static let carLength: Float = 20
    static let carPitch: Float = 20.5

    /// One car: its model in the pack and the points
    /// ``Map3DTrains/instance(of:index:from:to:stripe:)`` stands it
    /// between: `back` to `front`, which for a car turned round are its
    /// own front and back.
    public struct Car: Equatable, Sendable {
        public let model: Int
        public let back: Map3DPoint
        public let front: Map3DPoint
    }

    /// One train's row.
    public struct Row: Equatable, Sendable {
        public let key: String
        public let cars: [Car]
        /// Across the rows, metres.
        public let z: Float
        /// Its head's front, and the back of its last car.
        public var head: Map3DPoint { Map3DPoint(0, Map3DShowcase.railTop, z) }
        public let tailX: Float
        public var length: Float { -tailX }
    }

    /// The rows of `keys` (the first ``mostRows`` known ones), each with
    /// its cars in `cars` (its entry's default when missing), drawn with
    /// its set's far models when `far` and it has them.
    public static func layout(keys: [String], cars: [String: Int] = [:], far: Bool = false,
                              pack: Map3DModelPack = .standard) -> [Row] {
        // Every set as it is, whatever the train pack has locked.
        var pack = pack
        pack.locked = []
        let known = keys.compactMap { entry($0) }.prefix(mostRows)
        return known.enumerated().map { index, entry in
            let count = min(max(cars[entry.key] ?? entry.defaultCars, entry.fewestCars), entry.mostCars)
            let set = Map3DTrainSet.byKey[entry.key]
            let key = far ? set?.far ?? entry.key : entry.key
            let z = Float(index) * rowSpacing
            var x: Float = 0
            var laid: [Car] = []
            for car in Self.cars(of: key, count: count, pack: pack) {
                let front = Map3DPoint(x, railTop, z), back = Map3DPoint(x - car.length, railTop, z)
                laid.append(car.turned ? Car(model: car.model, back: front, front: back) : Car(model: car.model, back: back, front: front))
                x -= car.length + car.gap
            }
            let tail = laid.map { min($0.back.x, $0.front.x) }.min() ?? 0
            return Row(key: entry.key, cars: laid, z: z, tailX: tail)
        }
    }

    /// The cars of a `count`-car train of the set `key`, front to back.
    static func cars(of key: String, count: Int, pack: Map3DModelPack) -> [(model: Int, length: Float, gap: Float, turned: Bool)] {
        guard let set = Map3DTrainSet.byKey[key] else { return [] }
        if set.ownLengths, let laid = pack.layout(forType: key, count: count) {
            return laid.map { ($0.model, $0.length, $0.gap, false) }
        }
        // The set itself, not what a train of its key would be drawn as
        // (the green tram's two cars are the five-section LRT's).
        let tail = pack.index(of: set.tailName)
        return (0..<count).compactMap { index in
            guard let model = pack.modelIndex(of: set, carIndex: index, count: count) else { return nil }
            let turned = count > 1 && index == count - 1 && tail == nil
            return (model, carLength, carPitch - carLength, turned)
        }
    }

    /// The rows' cars as instances of `pack`'s models, each with its soft
    /// shadow under it, as the 3D map draws a train.
    public static func frame(_ rows: [Row], pack: Map3DModelPack = .standard) -> Map3DTrains.Frame {
        var frame = Map3DTrains.Frame()
        for row in rows {
            let stripe = Map3DColor.rgb(entry(row.key)?.stripe ?? 0x2F6DB5)
            for car in row.cars where pack.models.indices.contains(car.model) {
                frame.instances.append(Map3DTrains.instance(of: pack.models[car.model], index: car.model, from: car.back, to: car.front,
                                                            stripe: stripe))
                let length = (car.front - car.back).length
                let centre = (car.front + car.back) * 0.5 + Map3DPoint(0, 0.05 - Map3DScene.Builder.bedDrop, 0)
                frame.shadows.addShadow(
                    inner: Map3DMesh.footprint(centre: centre, forward: Map3DPoint(1, 0, 0), length: length, width: Map3DTrains.carWidth),
                    outer: Map3DMesh.footprint(centre: centre, forward: Map3DPoint(1, 0, 0), length: length + 1,
                                               width: Map3DTrains.carWidth + 1),
                    darkness: 0.38)
            }
            if let head = row.cars.first {
                frame.cars.append((head.front + head.back) * 0.5)
            }
        }
        return frame
    }

    // MARK: - The ground

    /// How far the ground reaches past the trains, metres.
    static let groundMargin: Float = 40
    static let groundColour = Map3DColor.rgb(0x9EA199)

    /// The open ground under `rows`: one flat piece reaching
    /// ``groundMargin`` past them, and under each train its ballast and
    /// two rails at its kind's gauge, as the 3D map lays its track. No
    /// overhead line, no third rail, no town.
    public static func ground(_ rows: [Row]) -> Map3DScene.Chunk {
        var mesh = Map3DMesh()
        let longest = rows.map(\.length).max() ?? 0
        let across = Float(max(rows.count - 1, 0)) * rowSpacing
        let low = Map3DPoint(-longest - groundMargin, 0, -groundMargin), high = Map3DPoint(groundMargin, 0, across + groundMargin)
        mesh.addQuad(Map3DPoint(low.x, 0, low.z), Map3DPoint(low.x, 0, high.z), Map3DPoint(high.x, 0, high.z), Map3DPoint(high.x, 0, low.z),
                     color: groundColour)
        let ballast = Map3DPaint(.ballast, .tile(width: 5, height: 2.4))
        for row in rows {
            let gauge = entry(row.key)?.category.gauge ?? 1.067
            let line = [Map3DPoint(row.tailX - 6, railTop, row.z), Map3DPoint(6, railTop, row.z)]
            mesh.addRibbon(along: line, width: Map3DScene.Builder.bedTop, lift: -Map3DScene.Builder.bedDrop, depth: 0.6,
                           top: Map3DPalette.ballast, side: Map3DPalette.ballast, topPaint: ballast)
            let offset = (gauge + Map3DScene.Builder.railWidth) / 2
            for side: Float in [-1, 1] {
                mesh.addRibbon(along: line, width: Map3DScene.Builder.railWidth, offset: side * offset, lift: 0,
                               depth: Map3DScene.Builder.railHeight, top: Map3DPalette.railTop, side: Map3DPalette.rail)
            }
        }
        let count = mesh.indices.count
        return Map3DScene.Chunk(column: 0, row: 0, mesh: mesh, baseIndexCount: count, far: Map3DMesh(), close: Map3DMesh(),
                                standIn: Map3DMesh(), shadows: Map3DMesh(), props: [], minimum: Map3DPoint(low.x, -1, low.z),
                                maximum: Map3DPoint(high.x, 8, high.z),
                                cityTops: Array(repeating: -.infinity, count: Map3DSeeThrough.cells * Map3DSeeThrough.cells),
                                signs: [], coarse: false)
    }

    // MARK: - The light

    /// The times of day the showcase is lit at, with the 3D map's own light
    /// (``Map3DLighting``): the cab lamps glow from dusk.
    public enum Light: String, CaseIterable, Sendable {
        case day, dusk, night

        /// The minute of the day: 14:00 (the preview tool's), 18:00, 21:00.
        public var minute: Double {
            switch self {
            case .day: 14 * 60
            case .dusk: 18 * 60
            case .night: 21 * 60
            }
        }

        public var lighting: Map3DLighting { Map3DLighting(minute: minute) }

        public func name(in language: DisplayLanguage) -> String {
            switch self {
            case .day: language.text("Day", "白天")
            case .dusk: language.text("Dusk", "黃昏")
            case .night: language.text("Night", "夜晚")
            }
        }
    }

    // MARK: - The camera

    /// The camera's ready views.
    public enum View: String, CaseIterable, Sendable {
        /// The first train's head, close, from in front and to one side,
        /// as #1340's preview picture: heading −120°, 18 m.
        case closeUp
        /// The first train from beside it, whole.
        case side
        /// Every train from above, leaning a little.
        case overhead

        public func name(in language: DisplayLanguage) -> String {
            switch self {
            case .closeUp: language.text("Front", "車頭特寫")
            case .side: language.text("Side", "側面")
            case .overhead: language.text("Above", "俯瞰")
            }
        }
    }

    /// The nearest and farthest the showcase's camera comes, metres: nearer
    /// than the 3D map's (``Map3DCamera/nearest``), to stand by a cab.
    public static let nearest: Float = 6
    public static let farthest: Float = 1_500
    /// How far the camera leans, from straight down, at most and least:
    /// the reference's garage (`train-garage.js`, `turn`) keeps its eye
    /// 0.08 to 1.48 radians over the level.
    static let mostTilt: Float = .pi / 2 - 0.08
    static let leastTilt: Float = .pi / 2 - 1.48

    /// The camera of `view` over `rows` on a screen `viewport` points.
    public static func camera(_ view: View, rows: [Row], viewport: (width: Float, height: Float)) -> Map3DCamera {
        var camera = Map3DCamera(viewport: viewport)
        let first = rows.first
        let length = first?.length ?? 20
        let aspect = max(viewport.width, 1) / max(viewport.height, 1)
        let halfTall = tanf(Map3DCamera.fieldOfView / 2), halfWide = halfTall * aspect
        switch view {
        case .closeUp:
            camera.target = Map3DPoint(-4, railTop + 2, first?.z ?? 0)
            camera.heading = -120 * .pi / 180
            // The garage's first view's height, 0.39 radians over the level.
            camera.pitch = .pi / 2 - 0.39
            camera.distance = 18
        case .side:
            // The head end of a long train, about three cars, so the
            // cars stay large enough to read.
            let span = min(length, 62)
            camera.target = Map3DPoint(-span / 2, railTop + 2, first?.z ?? 0)
            camera.heading = .pi
            camera.pitch = 82 * .pi / 180
            camera.distance = min(max(span / 2 * 1.15 / halfWide, 20), farthest)
        case .overhead:
            let longest = rows.map(\.length).max() ?? 20
            let across = Float(max(rows.count - 1, 0)) * rowSpacing
            camera.target = Map3DPoint(-longest / 2, 0, across / 2)
            camera.heading = .pi
            camera.pitch = 20 * .pi / 180
            let fit = max(longest / 2 * 1.15 / halfWide, (across / 2 + 6) * 1.3 / halfTall)
            camera.distance = min(max(fit, 30), farthest)
        }
        return camera
    }

    /// `camera` turned round its target as a finger drags `dx`, `dy`
    /// points: across turns it, down lowers it toward the level; as the
    /// garage's drag turns its model, 0.012 and 0.008 radians a point.
    public static func orbited(_ camera: Map3DCamera, dx: Float, dy: Float) -> Map3DCamera {
        var camera = camera
        camera.heading = (camera.heading - dx * 0.012).truncatingRemainder(dividingBy: 2 * .pi)
        camera.pitch = min(max((camera.pitch ?? camera.tilt) + dy * 0.008, leastTilt), mostTilt)
        return camera
    }

    /// `camera` `factor` times closer, within ``nearest`` and ``farthest``.
    public static func zoomed(_ camera: Map3DCamera, by factor: Float) -> Map3DCamera {
        guard factor > 0, factor.isFinite else { return camera }
        var camera = camera
        camera.distance = min(max(camera.distance / factor, nearest), farthest)
        return camera
    }

    /// The turntable's turn: once round in this many seconds, the garage's
    /// turning model's 0.35 radians a second (about 18 s).
    public static let turnSeconds: Double = 2 * .pi / 0.35

    /// `camera` turned on round its target over `seconds` of the turntable.
    public static func turning(_ camera: Map3DCamera, seconds: Double) -> Map3DCamera {
        var camera = camera
        camera.heading = (camera.heading + Float(seconds / turnSeconds) * 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        return camera
    }
}

extension Map3DShowcase {
    /// The name in a photo's corner: the game's own, as the postcard's
    /// wordmark (decision 215); the showcase has no map data to credit.
    public static func photoCredit(in language: DisplayLanguage) -> String {
        language.text("Along the Line", "沿線")
    }
}
