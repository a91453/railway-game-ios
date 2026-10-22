import Foundation

// ARCHITECTURE decision 352: the 3D map's signs, billboards and LED
// screens, a port of `Web/CityView/src/world/ads.js` (MIT): one atlas of
// pictures and words (`Map3DSigns.png`, drawn by `tools/map3d-signs/`),
// every sign one instance of a quad that shows a part of it, lit at night
// by the glow the windows and street lights use, a screen's picture
// changing with the time. The shops' boards say what kind of shop each is
// in a word of the atlas's (art-style §7: never a real shop's name), and go
// dark when the shop closes (the night district reference's opening hours).

/// One sign: a flat board the camera may read, standing in the scene.
public struct Map3DSign: Sendable, Equatable {
    /// What it shows (`ads.js`'s `aAd.y`, and the shops' words).
    public enum Kind: Int, Sendable, CaseIterable {
        /// One of the atlas's posters.
        case poster = 0
        /// An LED screen, a new poster wiping in every few seconds.
        case screen = 1
        /// A tall banner: the left third of a banner's cell.
        case banner = 2
        /// A shop's word across a board.
        case across = 3
        /// A shop's word down a blade sign, a character at a time.
        case down = 4
    }

    public let kind: Kind
    /// Its middle.
    public let centre: Map3DPoint
    /// Half its width, toward the right of someone reading it.
    public let right: Map3DPoint
    /// Half its height, up its face.
    public let up: Map3DPoint
    /// A poster's or banner's cell, or a word's place in
    /// ``Map3DSignAtlas/shopWords``.
    public let picture: Int
    /// From 0 to 1: where a screen's posters start their round.
    public let seed: Float
    /// The board's and the letters' colours, 0xRRGGBB.
    public let board: UInt32
    public let letters: UInt32
    /// Minutes after noon its light goes out (until the next noon);
    /// ``Map3DSign/allNight`` never.
    public let closes: Float

    public static let allNight: Float = 1_440

    /// A board facing `facing` (level), `width` by `height` metres, on
    /// `centre`. The reader stands in front, looking back along `facing`,
    /// with ``Map3DPoint/up`` crossed with `facing` on their right
    /// (`ads.js`: `rx = nz, rz = -nx`).
    public init(kind: Kind, centre: Map3DPoint, facing: Map3DPoint, width: Float, height: Float, picture: Int, seed: Float,
                board: UInt32 = 0x000000, letters: UInt32 = 0xFFFFFF, closes: Float) {
        let level = Map3DPoint(facing.x, 0, facing.z).normalized ?? Map3DPoint(0, 0, 1)
        self.init(kind: kind, centre: centre, right: Map3DPoint.up.cross(level) * (width / 2), up: Map3DPoint(0, height / 2, 0),
                  picture: picture, seed: seed, board: board, letters: letters, closes: closes)
    }

    init(kind: Kind, centre: Map3DPoint, right: Map3DPoint, up: Map3DPoint, picture: Int, seed: Float, board: UInt32, letters: UInt32, closes: Float) {
        self.kind = kind
        self.centre = centre
        self.right = right
        self.up = up
        self.picture = picture
        self.seed = seed
        self.board = board
        self.letters = letters
        self.closes = closes
    }

    /// The way its face looks.
    public var facing: Map3DPoint { (right.cross(up)).normalized ?? Map3DPoint(0, 0, 1) }

    /// Its corners: bottom left, bottom right, top left, top right as
    /// read, the order the shader's strip draws them.
    public var corners: [Map3DPoint] {
        [centre - right - up, centre + right - up, centre - right + up, centre + right + up]
    }

    /// The same sign built on a thing's own axes (x forward, y up, z to
    /// the right of x) placed on `base` facing `forward`, as
    /// ``Map3DMesh/append(_:at:forward:)`` places a mesh.
    func placed(at base: Map3DPoint, forward: Map3DPoint) -> Map3DSign {
        let along = Map3DPoint(forward.x, 0, forward.z).normalized ?? Map3DPoint(1, 0, 0)
        let side = along.cross(.up)
        func turned(_ p: Map3DPoint) -> Map3DPoint { along * p.x + Map3DPoint(0, p.y, 0) + side * p.z }
        return Map3DSign(kind: kind, centre: base + turned(centre), right: turned(right), up: turned(up), picture: picture, seed: seed,
                         board: board, letters: letters, closes: closes)
    }

    /// The 16 floats the shader reads (`Map3DSignIn` in
    /// `Map3DShaders.metal`): the middle and kind, half the width and the
    /// picture, half the height and the seed, then the board's and the
    /// letters' colours (red + green × 256 + blue × 65,536, exact in a
    /// float) and when it goes dark.
    public var floats: [Float] {
        [centre.x, centre.y, centre.z, Float(kind.rawValue),
         right.x, right.y, right.z, Float(picture),
         up.x, up.y, up.z, seed,
         Self.packed(board), Self.packed(letters), closes, 0]
    }

    static func packed(_ rgb: UInt32) -> Float {
        Float((rgb >> 16) & 0xFF) + Float((rgb >> 8) & 0xFF) * 256 + Float(rgb & 0xFF) * 65_536
    }

    /// The bytes one instance takes.
    public static let stride = 64

    // MARK: Time

    /// How long a screen shows one poster, in seconds (`ads.js`: `uTime *
    /// 0.16`), the last seventh of it the next one wiping in.
    public static let screenPeriod: Float = 1 / 0.16

    /// The poster a screen of `picture` and `seed` shows `seconds` in, and
    /// how far across the next one has wiped (0 to 1), as the shader works
    /// it out.
    public static func screen(picture: Int, seed: Float, seconds: Float) -> (now: Int, next: Int, wipe: Float) {
        let t = seconds / screenPeriod + seed * 9
        let posters = Map3DSignAtlas.posters
        let now = ((picture + Int(t.rounded(.down))) % posters + posters) % posters
        let fraction = t - t.rounded(.down)
        let edge = min(max((fraction - 0.86) / 0.14, 0), 1)
        return (now, (now + 1) % posters, edge * edge * (3 - 2 * edge))
    }

    /// Minutes after noon at `hour` (0–24): what ``closes`` is compared with.
    public static func minutesAfterNoon(hour: Float) -> Float {
        let minutes = (hour * 60 - 720).truncatingRemainder(dividingBy: 1_440)
        return minutes < 0 ? minutes + 1_440 : minutes
    }

    /// Whether its light is on at `hour`: from noon until it closes.
    public func isLit(hour: Float) -> Bool { Self.minutesAfterNoon(hour: hour) < closes }

    /// The per-frame values the shader reads beside the instances: the
    /// seconds the screens run on (none with Reduce Motion: each screen
    /// holds one poster, the motion skill's rule for anything that would
    /// loop by itself), the minutes after noon, and how far from the eye
    /// signs are drawn.
    public static func clock(seconds: Double, hour: Float, quality: Map3DQuality, reduceMotion: Bool) -> [Float] {
        let running = reduceMotion ? 0 : Float(seconds.truncatingRemainder(dividingBy: 86_400))
        return [running, minutesAfterNoon(hour: hour), reach(quality), 0]
    }

    /// How far from the eye signs are drawn, in metres: on ``Map3DQuality/saving``
    /// only those near.
    public static func reach(_ quality: Map3DQuality) -> Float {
        quality == .saving ? 450 : 1_200
    }
}

/// Decision 352: the atlas `Map3DSigns.png` (`tools/map3d-signs/`): 8 by 8
/// cells of 256 pixels. Cells 0–23 are posters, 24–31 banners (in their
/// left third), 32–47 the shop words across (four 256 × 64 strips a cell)
/// and 48–63 the same words down (four 64 × 256 columns a cell).
public enum Map3DSignAtlas {
    public static let side = 2_048
    public static let cells = 8
    public static let posters = 24
    public static let banners = 8

    /// The shop words, in the atlas's order (`tools/map3d-signs/words.json`'s
    /// `shopWords`; a test checks they agree).
    public static let shopWords = [
        "便利商店", "超市", "早餐店", "豆花", "手搖飲", "麵店", "小吃", "便當",
        "水餃", "牛肉麵", "滷肉飯", "咖啡", "麵包", "冰店", "鹹酥雞", "火鍋",
        "自助餐", "飲料", "文具行", "雜貨店", "書店", "花店", "洗衣店", "水果行",
        "五金行", "照相館", "藥局", "眼鏡行", "服飾", "鐘錶行", "電器行", "機車行",
        "銀行", "診所", "牙醫", "旅館", "補習班", "美髮", "不動產", "電信",
        "彩券行", "寵物", "中藥行", "腳踏車", "茶行", "米店", "肉圓", "燒臘",
        "海產", "粥", "鞋店", "布行", "刻印", "冷氣", "瓦斯行", "影印",
        "KTV", "按摩", "網咖", "電玩", "夜市", "飯店", "大樓", "商場",
    ]

    public static func word(_ text: String) -> Int? { shopWords.firstIndex(of: text) }

    /// Where in the atlas (0 to 1, from its top left) `kind`'s `picture`
    /// lies: x, y, width, height.
    public static func rect(_ kind: Map3DSign.Kind, picture: Int) -> (x: Float, y: Float, width: Float, height: Float) {
        let cell = 1 / Float(cells)
        func at(_ index: Int) -> (Float, Float) { (Float(index % cells) * cell, Float(index / cells) * cell) }
        switch kind {
        case .poster, .screen:
            let (x, y) = at(picture % posters)
            return (x, y, cell, cell)
        case .banner:
            let (x, y) = at(posters + picture % banners)
            return (x, y, cell / 3, cell)
        case .across:
            let (x, y) = at(posters + banners + picture / 4)
            return (x, y + Float(picture % 4) * cell / 4, cell, cell / 4)
        case .down:
            let (x, y) = at(posters + banners + 16 + picture / 4)
            return (x + Float(picture % 4) * cell / 4, y, cell / 4, cell)
        }
    }
}

// MARK: - Shops' words, colours and hours

extension Map3DSignAtlas {
    /// What a shop's sign says, from what the place is called: the kind of
    /// shop its name tells, never the name (art-style §7). The first rule
    /// that matches wins.
    static let rules: [(keys: [String], word: String)] = [
        (["便利", "超商"], "便利商店"), (["超市", "量販"], "超市"), (["早餐", "早午餐"], "早餐店"), (["豆花"], "豆花"),
        (["牛肉麵"], "牛肉麵"), (["滷肉飯", "魯肉飯"], "滷肉飯"), (["肉圓"], "肉圓"), (["燒臘", "烤鴨"], "燒臘"),
        (["鹹酥雞", "雞排"], "鹹酥雞"), (["火鍋", "涮", "麻辣"], "火鍋"), (["自助餐"], "自助餐"), (["水餃", "餃"], "水餃"),
        (["便當", "飯包"], "便當"), (["粥"], "粥"), (["海產", "海鮮", "熱炒"], "海產"), (["茶行", "茶莊", "茶葉"], "茶行"),
        (["咖啡", "cafe", "coffee"], "咖啡"), (["麵包", "烘焙", "bakery", "蛋糕"], "麵包"), (["冰"], "冰店"),
        (["茶", "飲", "奶", "果汁"], "手搖飲"), (["麵"], "麵店"), (["小吃", "食堂", "美食", "餐"], "小吃"),
        (["文具"], "文具行"), (["書"], "書店"), (["花"], "花店"), (["洗衣"], "洗衣店"), (["水果", "果"], "水果行"),
        (["五金"], "五金行"), (["照相", "攝影"], "照相館"), (["眼鏡"], "眼鏡行"), (["鐘錶", "鐘表"], "鐘錶行"),
        (["中醫", "中藥", "蔘藥", "國術"], "中藥行"), (["藥"], "藥局"), (["牙"], "牙醫"), (["動物醫院", "寵物"], "寵物"),
        (["診所", "醫院", "醫"], "診所"), (["銀行", "郵局", "信用合作社", "農會", "金庫"], "銀行"),
        (["飯店", "酒店", "hotel"], "飯店"), (["旅", "民宿", "商旅"], "旅館"), (["補習", "文理", "美語", "英語", "教育", "才藝", "學苑"], "補習班"),
        (["髮", "美容", "沙龍"], "美髮"), (["房屋", "不動產", "地產", "房仲"], "不動產"), (["電信", "通訊", "手機"], "電信"),
        (["彩券"], "彩券行"), (["腳踏車", "自行車", "單車"], "腳踏車"), (["米店", "米行"], "米店"), (["鞋"], "鞋店"),
        (["布行", "布莊"], "布行"), (["刻印", "印章"], "刻印"), (["冷氣", "空調"], "冷氣"), (["瓦斯"], "瓦斯行"),
        (["影印", "印刷"], "影印"), (["ktv", "卡拉"], "KTV"), (["按摩", "養生", "足體"], "按摩"), (["網咖"], "網咖"),
        (["電玩", "遊藝", "娃娃"], "電玩"), (["夜市"], "夜市"), (["百貨", "商場", "購物", "廣場", "mall"], "商場"),
        (["電器", "家電", "3c"], "電器行"), (["機車", "摩托"], "機車行"), (["服飾", "衣", "服裝"], "服飾"), (["寵"], "寵物"),
        (["雜貨", "商行", "商店"], "雜貨店"), (["大樓", "大廈", "中心", "大樓", "館", "廳", "院", "所", "局", "署", "公司"], "大樓"),
    ]

    /// The words a shop whose name tells nothing gets, by a hash of the name.
    static let everyday = ["小吃", "雜貨店", "服飾", "飲料", "麵店", "便當", "美髮", "咖啡", "早餐店", "手搖飲", "藥局", "水果行"]

    /// The word for a place called `name`; a building's own name
    /// (`title`) that tells nothing says 大樓.
    public static func word(forName name: String, title: Bool = false) -> Int {
        let lower = name.lowercased()
        for rule in rules where rule.keys.contains(where: { lower.contains($0) }) {
            if let index = word(rule.word) { return index }
        }
        let fallback = title ? "大樓" : everyday[Int(stableHash(name) % UInt32(everyday.count))]
        return word(fallback) ?? 0
    }

    /// FNV-1a over the name's UTF-8, as `signs.mjs`'s `hash` (Swift's own
    /// hash changes every launch).
    static func stableHash(_ text: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for byte in text.utf8 { h = (h ^ UInt32(byte)) &* 16_777_619 }
        return h
    }

    /// The opening hours' kinds (the town scene reference's `closes`;
    /// the night district's signs going dark by the hour).
    enum Hours {
        case allNight, lateFood, food, shop, office, breakfast
    }

    static func hours(_ word: Int) -> Hours {
        switch shopWords[word] {
        case "便利商店", "網咖", "KTV": .allNight
        case "鹹酥雞", "火鍋", "海產", "粥", "夜市", "電玩", "按摩", "飯店", "旅館", "手搖飲", "飲料": .lateFood
        case "早餐店": .breakfast
        case "豆花", "麵店", "小吃", "便當", "水餃", "牛肉麵", "滷肉飯", "咖啡", "麵包", "冰店", "自助餐", "肉圓", "燒臘": .food
        case "銀行", "診所", "牙醫", "補習班", "不動產", "大樓", "電信", "中藥行": .office
        default: .shop
        }
    }

    /// Minutes after noon a shop selling `word` turns its sign off, by a
    /// share from 0 to 1: a convenience store never; a late snack stall
    /// 23:00–03:00; food 20:00–24:00; shops 19:00–22:00; offices and
    /// clinics 21:00–23:00 (their boards lit for the evening); a
    /// breakfast shop 13:00 (the town scene's 阿嬤早餐), dark all night.
    public static func closes(_ word: Int, share: Float) -> Float {
        let share = min(max(share, 0), 1)
        switch hours(word) {
        case .allNight: return Map3DSign.allNight
        case .lateFood: return (660 + 240 * share).rounded()
        case .food: return (480 + 240 * share).rounded()
        case .shop: return (420 + 180 * share).rounded()
        case .office: return (540 + 120 * share).rounded()
        case .breakfast: return 60
        }
    }

    /// Billboards and screens on a wall: 22:00–24:00; on a roof:
    /// 24:00–03:00; screens 22:00–24:00.
    static func adCloses(_ kind: Map3DSign.Kind, rooftop: Bool, share: Float) -> Float {
        let share = min(max(share, 0), 1)
        if rooftop { return (720 + 180 * share).rounded() }
        return kind == .screen ? (600 + 120 * share).rounded() : (660 + 120 * share).rounded()
    }

    /// `signs.mjs`'s `SIGN_COLORS` (`Web/CityView`, MIT): board and letters.
    public static let tileColours: [(board: UInt32, letters: UInt32)] = [
        (0xC8102E, 0xFFFFFF), (0xF6C400, 0x1A1A1A), (0xF4F1EA, 0x1A1A1A), (0x151515, 0xFFFFFF),
        (0x1757A6, 0xFFFFFF), (0x16794C, 0xFFFFFF), (0xE8650A, 0xFFFFFF), (0xD93B7E, 0xFFFFFF),
        (0x3A2414, 0xE9C46A), (0x14213D, 0xFFFFFF), (0xFFFFFF, 0xE8650A), (0xFFFFFF, 0x0A8F4F),
        (0x0F6FC6, 0xFFFFFF), (0x5A5D61, 0xFFFFFF),
    ]

    /// The pipeline's colour `index` as the 3D map paints it: its two
    /// convenience chains' (10, 11: white boards with the chains' orange
    /// or green letters, `signs.mjs`'s `BRAND`) as plain orange and green
    /// boards, so no board reads as a real chain's (art-style §7).
    public static func plainColour(_ index: Int) -> Int {
        switch index {
        case 10: 6
        case 11: 5
        default: min(max(index, 0), tileColours.count - 1)
        }
    }
}

extension Map3DColor {
    /// The 0xRRGGBB of a vertex colour (``rgb(_:)`` keeps red in the low
    /// byte).
    static func hex(_ color: UInt32) -> UInt32 {
        ((color & 0xFF) << 16) | (color & 0xFF00) | ((color >> 16) & 0xFF)
    }
}
