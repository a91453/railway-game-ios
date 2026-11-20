import Foundation
import GameCore

// Decision 882: a name board at the back of every platform, the station's
// name in the game on it, as on a real platform, the same rule on the
// ground, on a viaduct and under ground.

/// The name boards' letters: Noto Sans TC Bold's glyphs on a grid of
/// ``grid`` cells, each as a few rectangles (``packed``, made by
/// `tools/platform-name-board/build_glyphs.py`), for every character of
/// the game's bundled names, kana and Latin letters.
public enum Map3DBoardGlyphs {
    /// A glyph's cells across and down.
    public static let grid = 16

    /// A glyph: how many cells it takes along a line, and its filled
    /// cells as rectangles, `x` and `y` from its top left.
    public struct Glyph: Equatable, Sendable {
        public let width: Int
        public let rectangles: [Rectangle]
    }

    public struct Rectangle: Equatable, Sendable {
        public let x: Int, y: Int, width: Int, height: Int
    }

    /// Every glyph, read once from ``packed``.
    public static let glyphs: [Character: Glyph] = {
        guard let data = Data(base64Encoded: packed, options: .ignoreUnknownCharacters) else { return [:] }
        let bytes = [UInt8](data)
        var table: [Character: Glyph] = [:], index = 0
        while index < bytes.count {
            let lead = bytes[index]
            let length = lead < 0x80 ? 1 : lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4
            guard index + length + 2 <= bytes.count,
                  let text = String(bytes: bytes[index..<index + length], encoding: .utf8), let character = text.first else { break }
            index += length
            let width = Int(bytes[index]) + 1, count = Int(bytes[index + 1])
            index += 2
            guard index + 2 * count <= bytes.count else { break }
            let rectangles = (0..<count).map { n -> Rectangle in
                let place = bytes[index + 2 * n], size = bytes[index + 2 * n + 1]
                return Rectangle(x: Int(place >> 4), y: Int(place & 15), width: Int(size >> 4) + 1, height: Int(size & 15) + 1)
            }
            index += 2 * count
            table[character] = Glyph(width: width, rectangles: rectangles)
        }
        return table
    }()

    /// A space's width, in cells.
    static let spaceWidth = 5

    /// `text` set on one line: its width in cells and its filled cells as
    /// rectangles, `x` from the line's left; a character with no glyph
    /// is left out.
    public static func layout(_ text: String) -> (width: Int, rectangles: [Rectangle]) {
        var x = 0, rectangles: [Rectangle] = []
        for character in text {
            if character.isWhitespace {
                x += spaceWidth
                continue
            }
            guard let glyph = glyphs[character] else { continue }
            rectangles += glyph.rectangles.map { Rectangle(x: x + $0.x, y: $0.y, width: $0.width, height: $0.height) }
            x += glyph.width
        }
        return (x, rectangles)
    }
}

/// FUKUOKA-NAME-BOARDS (decision 882's later note): the boards of a
/// railway in Japan, as its own: the station's Japanese name large, its
/// reading in kana over it and its English name under it, its station
/// number in the line's colour at the left, the line's colour along the
/// bottom. A system listed in ``systems`` has these boards on every map
/// it is on; a new map in Japan lists its stations here.
public enum Map3DJapaneseNameBoards {
    /// A station's board: its Japanese name, its reading and its numbers
    /// (one for each line calling, `K11`), keyed by the station's name in
    /// the game's data.
    public struct Station: Equatable, Sendable {
        public let japanese: String
        public let kana: String
        public let numbers: [String]
    }

    /// The Fukuoka City Subway's 36 stations: the Japanese names of its
    /// map pack's `station_names.json` (MLIT's railway data, CC BY 4.0),
    /// the numbers of its `track_stations.geojson` (OpenStreetMap's, the
    /// operator's own numbering), and their readings, from the operator's
    /// station list.
    public static let systems: [String: [String: Station]] = [
        "fksubway": [
            "姪濱": Station(japanese: "姪浜", kana: "めいのはま", numbers: ["K01"]),
            "室見": Station(japanese: "室見", kana: "むろみ", numbers: ["K02"]),
            "藤崎": Station(japanese: "藤崎", kana: "ふじさき", numbers: ["K03"]),
            "西新": Station(japanese: "西新", kana: "にしじん", numbers: ["K04"]),
            "唐人町": Station(japanese: "唐人町", kana: "とうじんまち", numbers: ["K05"]),
            "大濠公園": Station(japanese: "大濠公園", kana: "おおほりこうえん", numbers: ["K06"]),
            "赤坂": Station(japanese: "赤坂", kana: "あかさか", numbers: ["K07"]),
            "天神": Station(japanese: "天神", kana: "てんじん", numbers: ["K08"]),
            "中洲川端": Station(japanese: "中洲川端", kana: "なかすかわばた", numbers: ["K09", "H01"]),
            "祇園": Station(japanese: "祇園", kana: "ぎおん", numbers: ["K10"]),
            "博多": Station(japanese: "博多", kana: "はかた", numbers: ["K11", "N18"]),
            "東比惠": Station(japanese: "東比恵", kana: "ひがしひえ", numbers: ["K12"]),
            "福岡機場": Station(japanese: "福岡空港", kana: "ふくおかくうこう", numbers: ["K13"]),
            "吳服町": Station(japanese: "呉服町", kana: "ごふくまち", numbers: ["H02"]),
            "千代縣廳口": Station(japanese: "千代県庁口", kana: "ちよけんちょうぐち", numbers: ["H03"]),
            "馬出九大病院前": Station(japanese: "馬出九大病院前", kana: "まいだしきゅうだいびょういんまえ", numbers: ["H04"]),
            "箱崎宮前": Station(japanese: "箱崎宮前", kana: "はこざきみやまえ", numbers: ["H05"]),
            "箱崎九大前": Station(japanese: "箱崎九大前", kana: "はこざききゅうだいまえ", numbers: ["H06"]),
            "貝塚": Station(japanese: "貝塚", kana: "かいづか", numbers: ["H07"]),
            "橋本": Station(japanese: "橋本", kana: "はしもと", numbers: ["N01"]),
            "次郎丸": Station(japanese: "次郎丸", kana: "じろうまる", numbers: ["N02"]),
            "賀茂": Station(japanese: "賀茂", kana: "かも", numbers: ["N03"]),
            "野芥": Station(japanese: "野芥", kana: "のけ", numbers: ["N04"]),
            "梅林": Station(japanese: "梅林", kana: "うめばやし", numbers: ["N05"]),
            "福大前": Station(japanese: "福大前", kana: "ふくだいまえ", numbers: ["N06"]),
            "七隈": Station(japanese: "七隈", kana: "ななくま", numbers: ["N07"]),
            "金山": Station(japanese: "金山", kana: "かなやま", numbers: ["N08"]),
            "茶山": Station(japanese: "茶山", kana: "ちゃやま", numbers: ["N09"]),
            "別府": Station(japanese: "別府", kana: "べふ", numbers: ["N10"]),
            "六本松": Station(japanese: "六本松", kana: "ろっぽんまつ", numbers: ["N11"]),
            "櫻坂": Station(japanese: "桜坂", kana: "さくらざか", numbers: ["N12"]),
            "藥院大通": Station(japanese: "薬院大通", kana: "やくいんおおどおり", numbers: ["N13"]),
            "藥院": Station(japanese: "薬院", kana: "やくいん", numbers: ["N14"]),
            "渡邊通": Station(japanese: "渡辺通", kana: "わたなべどおり", numbers: ["N15"]),
            "天神南": Station(japanese: "天神南", kana: "てんじんみなみ", numbers: ["N16"]),
            "櫛田神社前": Station(japanese: "櫛田神社前", kana: "くしだじんじゃまえ", numbers: ["N17"]),
        ],
    ]

    /// The line a number is on: its letters (`K` of `K11`).
    static func line(ofNumber number: String) -> String { String(number.prefix { $0.isLetter }) }

    /// The line of a real line's key (`fksubway|K`, `fksubway:K`): what
    /// follows its system.
    static func line(ofRealLine key: String) -> String {
        String(key.split(whereSeparator: { $0 == "|" || $0 == ":" }).last ?? Substring(key))
    }
}

extension Map3DJapaneseNameBoards {
    /// Whether station number `number` (`K11`, `BL12`, `R10`) is on the
    /// line a real line's key names (`K`, `BL`, `R_XBT`, Kaohsiung's
    /// `KR`, Taichung's `TG`): its letters are the line's, a branch's
    /// suffix (`_XBT`) aside, or the line's but its first letter.
    static func number(_ number: String, isOn line: String) -> Bool {
        let letters = Self.line(ofNumber: number)
        let base = String(line.split(separator: "_").first ?? Substring(line))
        return letters == base || (base.count > 1 && letters == String(base.dropFirst()))
    }
}

extension Map3DPlatformProps {
    /// NAME-BOARD-STYLES (decision 882's later note): the boards of a
    /// system that are not decision 882's (Taiwan Railway's, which the
    /// railway, the High Speed Rail and the Alishan line keep).
    public enum BoardStyle: Equatable, Sendable {
        /// A metro's: white, the line's colour along its bottom, the
        /// station's number (where it has one) in the line's colour at
        /// its left, the name large with its other name under it (a
        /// Japanese station's reading over it).
        case metro
        /// Finland's: white letters on blue, the name in Finnish alone.
        case finnish
    }

    /// Each system's boards, by its id; one not here has decision 882's.
    public static let boardStyles: [String: BoardStyle] = [
        "mrt": .metro, "tymc": .metro, "ntdlrt": .metro, "ntalrt": .metro, "sanying": .metro, "krtc": .metro, "tmrt": .metro,
        "hkmtr": .metro, "fksubway": .metro, "vr": .finnish,
    ]

    /// The systems of `station_transfers.json` (TDX's station IDs, the
    /// operators' station numbers) whose numbers a system's stations carry.
    static let boardNumberSystems: [String: [String]] = [
        "mrt": ["TRTC", "NTMC"], "tymc": ["TYMC"], "ntdlrt": ["NTDLRT"], "ntalrt": ["NTALRT"], "sanying": ["SANYING"],
        "krtc": ["KRTC", "KLRT"], "tmrt": ["TMRT"],
    ]

    /// A board in a system's style: its reading (a Japanese name's kana),
    /// its station number and its line's colour.
    struct StyledBoard: Equatable {
        let style: BoardStyle
        let reading: String?
        let number: String?
        let colour: UInt32
    }

    /// A metro board's band along its face's bottom (a share of its height).
    static let metroBand: Float = 0.16
}

extension Map3DPalette {
    /// NAME-BOARD-STYLES: Finland's railway signs' blue (RAL 5017, traffic
    /// blue), white letters on it.
    public static let finnishSignBlue = Map3DColor.rgb(0x00538A)
}

/// NAME-BOARD-STYLES: what a station's boards write in each of its
/// systems' styles.
struct Map3DBoardSign: Equatable {
    struct Board: Equatable {
        let style: Map3DPlatformProps.BoardStyle
        let name: String
        let second: String?
        let reading: String?
        let numbers: [String]
        /// Each of the system's lines' colours, by the line's id (`BL`).
        let colours: [String: UInt32]
    }

    /// By system id.
    var boards: [String: Board] = [:]
    /// The system a platform with no real line of its own takes: the
    /// station's first real system, when it has a style.
    var fallback: String?

    /// The system id of a real line's key (`trtc:BL`, `tra:PINGXI`).
    static func system(ofRealLine key: String) -> String {
        let system = String(key.split(whereSeparator: { $0 == "|" || $0 == ":" }).first ?? Substring(key))
        return system == "trtc" ? "mrt" : system == "tra" ? "tra_sched" : system
    }

    /// The board on the platform of `realLine` (`nil`: one with none of its
    /// own): its name, its second name and its style; `nil` for decision
    /// 882's.
    func board(realLine: String?) -> (name: String, second: String?, board: Map3DPlatformProps.StyledBoard)? {
        guard let system = realLine.map(Self.system(ofRealLine:)) ?? fallback, let board = boards[system] else { return nil }
        let line = realLine.map(Map3DJapaneseNameBoards.line(ofRealLine:))
        let number: String?
        if let line {
            number = board.numbers.first { Map3DJapaneseNameBoards.number($0, isOn: line) } ?? (board.numbers.count == 1 ? board.numbers[0] : nil)
        } else {
            number = board.numbers.first
        }
        let lines = board.colours.sorted { $0.key < $1.key }
        var colour = line.flatMap { board.colours[$0] }
        if colour == nil, let number { colour = lines.first { Map3DJapaneseNameBoards.number(number, isOn: $0.key) }?.value }
        let shown = colour ?? lines.first?.value ?? Map3DPalette.playerRim
        return (board.name, board.second, Map3DPlatformProps.StyledBoard(style: board.style, reading: board.reading, number: number, colour: shown))
    }
}

extension Map3DPlatformProps {
    /// A name board, the old version's (SwiftRailMac's side platform
    /// modules `45e46be7` and `460efb19`: 4.1 m by 1.77 m, scaled as the
    /// furniture by 0.66): ``nameBoardLength`` long and
    /// ``nameBoardHeight`` tall in its grey frame, its foot
    /// ``nameBoardFoot`` over the platform, on two posts at the
    /// platform's back.
    static let nameBoardLength: Float = 2.7
    static let nameBoardHeight: Float = 1.17
    static let nameBoardFoot: Float = 1.3
    static let nameBoardDepth: Float = 0.1
    /// The frame's width round the white face.
    static let nameBoardFrame: Float = 0.06
    /// The old board's green band across its face, from its bottom (a
    /// share of the face's height), and its colour: decision 891, the
    /// palette's green sheet-steel roof (``Map3DPalette/cityRoofs`` [3],
    /// #3C8A5A) rather than the old texture's #106118, which the palette
    /// has nothing near.
    static let nameBoardBand: ClosedRange<Float> = 0.30...0.43
    public static let nameBoardGreen = Map3DPalette.cityRoofs[3].color
    /// Where along the old version's module (decision 860) a board
    /// stands: in its one long gap, between the square column and the
    /// poster boards (21.2 to 28.5 m), under the second hung sign.
    static let nameBoardInModule: Float = 24.87
    static let nameBoardRoom: ClosedRange<Float> = 21.3...28.4
    /// How far a board's end keeps from a canopy's column.
    static let nameBoardColumnClearance: Float = 0.4

    /// Decision 882: the middles of a platform's name boards, along a
    /// platform `length` long and `depth` deep (half of an `island` or a
    /// side platform) whose line runs as the furniture's module does when
    /// `forward`: in the middle module's gap and every second module's
    /// out from it, moved within the gap to keep clear of the `bins` and
    /// of the canopy's `columns`, which would stand before it seen from
    /// the train (one that cannot is left out); none on a platform the
    /// furniture would not stand on.
    public static func nameBoards(length: Float, depth: Float, island: Bool, forward: Bool, bins: [Float],
                                  columns: [Float] = []) -> [Float] {
        guard island ? 2 * depth >= Map3DUndergroundStations.furnishedIsland : depth >= furnishedPlatform else { return [] }
        let (count, start) = Map3DOldIslandModule.modules(along: length)
        guard count > 0 else { return [] }
        let middle = count / 2, half = nameBoardLength / 2
        return (0..<count).filter { ($0 - middle) % 2 == 0 }.compactMap { number in
            let base = start + Float(number) * Map3DOldIslandModule.length
            let wanted = base + nameBoardInModule
            let room = (base + nameBoardRoom.lowerBound + half)...(base + nameBoardRoom.upperBound - half)
            let spot = stride(from: Float(0), through: 3, by: 0.25).flatMap { [wanted + $0, wanted - $0] }.first { at in
                let along = forward ? at : length - at
                return room.contains(at) && bins.allSatisfy { abs($0 - along) >= binHalfLength + furnitureBinClearance + half }
                    && columns.allSatisfy { abs($0 - along) >= nameBoardColumnClearance + half }
            }
            return spot.map { forward ? $0 : length - $0 }
        }.sorted()
    }
}

extension Map3DScene.Builder {
    /// Decision 882: the second name of each of `world`'s stations that is
    /// a real one (as the station card's nameboard, decision 845): the
    /// official English name under a Chinese name, the Chinese one under
    /// an English name; none where the two are the same.
    static func boardSecondNames(_ world: GameWorld, _ railways: RealRailways, _ frame: RealWorldFrame) -> [StationID: String] {
        var names: [StationID: String] = [:]
        for station in world.stations where !station.isDepot {
            let at = frame.coordinate(worldX: Double(station.location.x), worldY: Double(station.location.y))
            let real = railways.stations(named: station.name, near: RealRailways.Coordinate(latitude: at.latitude, longitude: at.longitude))
            guard let first = real.first(where: { $0.english != nil }) ?? real.first else { continue }
            let key = RealRailways.stationKey(station.name)
            let english = first.english.map(RealRailways.Station.shown)
            let second = english.map { RealRailways.stationKey($0) == key } ?? false ? first.chinese : english
            if let second, RealRailways.stationKey(second) != key { names[station.id] = second }
        }
        return names
    }

    /// NAME-BOARD-STYLES: the signs of each of `world`'s stations that is a
    /// real one of a system with a style of its own (``Map3DPlatformProps/boardStyles``):
    /// a Japanese station's name and reading (``Map3DJapaneseNameBoards``),
    /// a Taiwanese metro station's numbers (`station_transfers.json`), a
    /// Finnish station's Finnish name.
    static func boardSigns(_ world: GameWorld, _ railways: RealRailways, _ frame: RealWorldFrame) -> [StationID: Map3DBoardSign] {
        typealias Props = Map3DPlatformProps
        var signs: [StationID: Map3DBoardSign] = [:]
        for station in world.stations where !station.isDepot {
            let at = frame.coordinate(worldX: Double(station.location.x), worldY: Double(station.location.y))
            let real = railways.stations(named: station.name, near: RealRailways.Coordinate(latitude: at.latitude, longitude: at.longitude))
            var sign = Map3DBoardSign()
            for found in real {
                let system = found.system.id
                guard let style = Props.boardStyles[system], sign.boards[system] == nil else { continue }
                let key = RealRailways.stationKey(station.name)
                let english = found.english.map(RealRailways.Station.shown)
                var name = station.name, reading: String?, numbers: [String] = []
                var second = english.map { RealRailways.stationKey($0) == key } ?? false ? found.chinese : english
                if let japanese = Map3DJapaneseNameBoards.systems[system]?[found.chinese] {
                    name = japanese.japanese
                    reading = japanese.kana
                    numbers = japanese.numbers
                    second = english
                }
                if style == .finnish {
                    name = english ?? station.name
                    second = nil
                }
                if let transfers = railways.transfers {
                    for numbered in Props.boardNumberSystems[system] ?? [] {
                        numbers += transfers.stations(inSystem: numbered, named: found.chinese, near: found.coordinate).map(\.stationId)
                    }
                }
                if let shown = second, RealRailways.stationKey(shown) == RealRailways.stationKey(name) { second = nil }
                var colours: [String: UInt32] = [:]
                for (lineKey, rgb) in found.system.lineColors where lineKey.hasPrefix("\(system)|") {
                    colours[String(lineKey.dropFirst(system.count + 1))] =
                        Map3DColor.rgb(UInt32(rgb.red) << 16 | UInt32(rgb.green) << 8 | UInt32(rgb.blue))
                }
                sign.boards[system] = Map3DBoardSign.Board(style: style, name: name, second: second, reading: reading, numbers: numbers,
                                                           colours: colours)
            }
            guard !sign.boards.isEmpty else { continue }
            sign.fallback = real.first.map(\.system.id).flatMap { sign.boards[$0] != nil ? $0 : nil }
            signs[station.id] = sign
        }
        return signs
    }

    /// Decision 882: a name as its board writes it: 臺 as 台, whose fewer
    /// strokes stay clear on the glyphs' 16-cell grid.
    static func boardText(_ name: String) -> String { name.replacingOccurrences(of: "臺", with: "台") }

    /// Decision 882: a name board with its foot's middle at `foot` (the
    /// platform's back), facing `out` (towards the track), as the old
    /// version's: a white face in a grey frame, a green band across it,
    /// `name` in navy over the band; its face lit at night
    /// (`underground`: always).
    static func addNameBoard(_ mesh: inout Map3DMesh, foot: Map3DPoint, out: Map3DPoint, name: String, second: String? = nil,
                             styled: Map3DPlatformProps.StyledBoard? = nil, underground: Bool) {
        typealias Props = Map3DPlatformProps
        guard let out = Map3DPoint(out.x, 0, out.z).normalized else { return }
        let along = Map3DPoint(-out.z, 0, out.x)
        let length = Props.nameBoardLength, height = Props.nameBoardHeight, depth = Props.nameBoardDepth
        let frame = Props.nameBoardFrame
        let middle = foot + out * (depth / 2)
        // The two posts, a little in from its ends.
        for end: Float in [-1, 1] {
            mesh.addBox(base: middle + along * (end * (length / 2 - 0.25)), forward: along, length: 0.06, width: 0.06,
                        height: Props.nameBoardFoot, top: Map3DPalette.steel, side: Map3DPalette.steel)
        }
        let board = middle + Map3DPoint(0, Props.nameBoardFoot, 0)
        mesh.addBox(base: board, forward: along, length: length, width: depth, height: height,
                    top: Map3DPalette.rail, side: Map3DPalette.rail)
        // The face, a little proud of the frame on the track's side.
        let faceLength = length - 2 * frame, faceHeight = height - 2 * frame
        let face = board + out * (depth / 2 + 0.005) + Map3DPoint(0, frame, 0)
        // The reader, facing the board from the track, reads to their right.
        let right = Map3DPoint(out.z, 0, -out.x)
        func quad(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ lift: Float, _ colour: UInt32) {
            func corner(_ x: Float, _ y: Float) -> Map3DPoint { face + out * lift + right * x + Map3DPoint(0, y, 0) }
            mesh.addQuad(corner(x0, y0), corner(x1, y0), corner(x1, y1), corner(x0, y1), color: colour)
        }
        let first = mesh.vertices.count
        let finnish = styled?.style == .finnish
        quad(-faceLength / 2, 0, faceLength / 2, faceHeight, 0, finnish ? Map3DPalette.finnishSignBlue : Map3DPalette.sidewalk)
        if underground { mesh.makeGlowing(from: first) } else { mesh.makeNightLit(from: first) }
        let grid = Float(Map3DBoardGlyphs.grid)
        // NAME-BOARD-STYLES: Finland's, its name alone in white on blue.
        if finnish {
            let text = Map3DBoardGlyphs.layout(name)
            guard text.width > 0 else { return }
            let cell = min(faceHeight * 0.62 / grid, (faceLength - 0.3) / Float(text.width))
            let left = -Float(text.width) * cell / 2, top = faceHeight / 2 + grid * cell / 2
            for r in text.rectangles {
                let x0 = left + Float(r.x) * cell, x1 = x0 + Float(r.width) * cell
                let y1 = top - Float(r.y) * cell, y0 = y1 - Float(r.height) * cell
                quad(x0, y0, x1, y1, 0.008, Map3DPalette.sidewalk)
            }
            return
        }
        let band = styled == nil ? Props.nameBoardBand : 0...Props.metroBand
        quad(-faceLength / 2, faceHeight * band.lowerBound, faceLength / 2, faceHeight * band.upperBound, 0.004, styled?.colour ?? Props.nameBoardGreen)
        // An arrow at each end of the band, pointing out, as on the
        // railway's boards.
        let bandLow = faceHeight * band.lowerBound, bandHigh = faceHeight * band.upperBound, mid = (bandLow + bandHigh) / 2
        let arrow = (bandHigh - bandLow) * 0.8
        for end: Float in [-1, 1] {
            let tip = end * (faceLength / 2 - 0.05), back = tip - end * arrow
            let a = face + out * 0.008 + right * tip + Map3DPoint(0, mid, 0)
            let b = face + out * 0.008 + right * back + Map3DPoint(0, mid + arrow / 2, 0)
            let c = face + out * 0.008 + right * back + Map3DPoint(0, mid - arrow / 2, 0)
            // Counter-clockwise seen from the track.
            mesh.addFan(end > 0 ? [c, a, b] : [a, c, b], normal: out, color: Map3DPalette.sidewalk)
        }
        // The name over the band, as large as fits, its second name small
        // under it when it has one.
        let room = faceHeight * (1 - band.upperBound)
        func write(_ text: (width: Int, rectangles: [Map3DBoardGlyphs.Rectangle]), height: Float, middle: Float,
                   centre: Float = 0, span: Float = faceLength - 0.2, ink: UInt32 = Map3DPalette.playerRim, lift: Float = 0.008) {
            guard text.width > 0 else { return }
            let cell = min(height / grid, span / Float(text.width))
            let left = centre - Float(text.width) * cell / 2, top = middle + grid * cell / 2
            for r in text.rectangles {
                let x0 = left + Float(r.x) * cell, x1 = x0 + Float(r.width) * cell
                let y1 = top - Float(r.y) * cell, y0 = y1 - Float(r.height) * cell
                quad(x0, y0, x1, y1, lift, ink)
            }
        }
        if let styled {
            // NAME-BOARD-STYLES: a metro's: the station's number in its
            // line's colour at the left, its letters over its figures in
            // white; the reading (a Japanese name's) over the name, the
            // other name under it.
            var textLeft = -faceLength / 2 + 0.1
            if let number = styled.number {
                let side = min(room * 0.78, 0.6), middle = bandHigh + room / 2
                let badgeLeft = textLeft, badgeRight = badgeLeft + side
                quad(badgeLeft, middle - side / 2, badgeRight, middle + side / 2, 0.006, styled.colour)
                let letters = Map3DJapaneseNameBoards.line(ofNumber: number)
                let figures = String(number.dropFirst(letters.count))
                let badgeMiddle = (badgeLeft + badgeRight) / 2
                write(Map3DBoardGlyphs.layout(letters), height: side * 0.36, middle: middle + side * 0.2, centre: badgeMiddle,
                      span: side * 0.8, ink: Map3DPalette.sidewalk, lift: 0.01)
                write(Map3DBoardGlyphs.layout(figures), height: side * 0.42, middle: middle - side * 0.17, centre: badgeMiddle,
                      span: side * 0.8, ink: Map3DPalette.sidewalk, lift: 0.01)
                textLeft = badgeRight + 0.08
            }
            let textRight = faceLength / 2 - 0.1
            let centre = (textLeft + textRight) / 2, span = textRight - textLeft
            let shownName = Map3DBoardGlyphs.layout(Self.boardText(name))
            if let reading = styled.reading {
                write(Map3DBoardGlyphs.layout(reading), height: room * 0.19, middle: bandHigh + room * 0.86, centre: centre, span: span)
                write(shownName, height: room * 0.5, middle: bandHigh + room * 0.52, centre: centre, span: span)
                if let second {
                    write(Map3DBoardGlyphs.layout(second), height: room * 0.17, middle: bandHigh + room * 0.14, centre: centre, span: span)
                }
            } else if let second {
                write(shownName, height: room * 0.6, middle: bandHigh + room * 0.62, centre: centre, span: span)
                write(Map3DBoardGlyphs.layout(second), height: room * 0.24, middle: bandHigh + room * 0.18, centre: centre, span: span)
            } else {
                write(shownName, height: room * 0.8, middle: bandHigh + room / 2, centre: centre, span: span)
            }
            return
        }
        // 臺 is written 台 (as on many of the railway's own boards): its
        // strokes run together on the glyphs' grid.
        let main = Map3DBoardGlyphs.layout(Self.boardText(name))
        let other = second.map(Map3DBoardGlyphs.layout) ?? (width: 0, rectangles: [])
        if other.width > 0 {
            write(main, height: room * 0.66, middle: bandHigh + room * 0.62)
            write(other, height: room * 0.3, middle: bandHigh + room * 0.17)
        } else {
            write(main, height: room * 0.92, middle: bandHigh + room / 2)
        }
    }
}
