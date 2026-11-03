import GameCore

// Decision 566: the new-train arrival card. The first time the company has
// a train of a real model it did not have (an EMU3000, a 700T, a Puyuma, a
// Wenhu line car), a card shows it lifted ashore at a port with ribbons, in
// the model's paint, with a sentence of how the real first ones arrived.
// Shown once a model and a session, kept in the news log.
//
// Only presentation: which model a train is comes from the world, as the
// 3D map draws it (``Map3DTrainSet/variant(of:number:locked:)``), and a
// model "already seen" is one the fleet had before the command. Neither
// GameCore nor the save knows of it.

/// A real model's arrival, as the card shows it.
public struct NewTrainArrival: Hashable, Sendable, Identifiable {
    /// The 3D set key of the model (``Map3DTrainSet/key``).
    public let key: String
    let english: String
    let chinese: String
    /// The body, stripe and front colours of the drawing (`0xRRGGBB`).
    public let body: Int
    public let stripe: Int
    public let cab: Int
    /// How the real first ones arrived, when a source says so (decision
    /// 566 lists them); `nil` for "the first ones arrived" only.
    let landing: Landing?

    public var id: String { key }

    /// Where and when the real first train came ashore.
    struct Landing: Hashable, Sendable {
        let englishPort: String
        let chinesePort: String
        let year: Int
        let month: Int
        /// `nil` where the sources agree only on the month.
        let day: Int?
    }

    /// The model's name.
    public func name(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    /// The card's title.
    public func title(in language: DisplayLanguage) -> String {
        language.text("New train: \(english)", "新車抵台：\(chinese)")
    }

    /// The sentence of how the real first ones arrived.
    public func story(in language: DisplayLanguage) -> String {
        guard let landing else {
            return language.text("The first ones arrived in Taiwan.", "首批抵台。")
        }
        let englishMonths = ["January", "February", "March", "April", "May", "June", "July",
                             "August", "September", "October", "November", "December"]
        let month = englishMonths[landing.month - 1]
        switch language {
        case .english:
            let date = landing.day.map { "on \($0) \(month) \(landing.year)" } ?? "in \(month) \(landing.year)"
            return "The first one came ashore at \(landing.englishPort) \(date)."
        case .traditionalChinese:
            let date = "\(landing.year) 年 \(landing.month) 月" + (landing.day.map { " \($0) 日" } ?? "")
            return "首批列車在 \(date)於\(landing.chinesePort)上岸。"
        }
    }

    /// The news log's line.
    public func newsText(in language: DisplayLanguage) -> String {
        language.text("A new train joined the fleet: \(english)", "新車抵台：\(chinese)加入車隊")
    }
}

/// The models a card is shown for, and which of them a fleet has.
public enum NewTrainArrivals {
    /// The models with a card, by 3D set key. Imported fleets only: the
    /// Danhai and Ankeng light rails were built in Taiwan (no port), the
    /// N700S-G is no Taiwanese train (decision 338), and the tourist trains
    /// are rebuilt coaches. Colours are each model's 3D set's or
    /// ``TrainLivery``'s.
    public static let catalog: [String: NewTrainArrival] = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })

    static let entries: [NewTrainArrival] = [
        model("emu3000", "EMU3000", "EMU3000 城際列車", TrainLivery.emu3000,
              Landing(englishPort: "Hualien Port", chinesePort: "花蓮港", year: 2021, month: 7, day: 30)),
        model("highSpeed", "THSR 700T", "高鐵 700T", TrainLivery.highSpeed,
              Landing(englishPort: "Kaohsiung", chinesePort: "高雄", year: 2004, month: 5, day: 24)),
        model("puyuma", "Puyuma (TEMU2000)", "普悠瑪號（TEMU2000）", TrainLivery.puyuma,
              Landing(englishPort: "Keelung Port", chinesePort: "基隆港", year: 2012, month: 10, day: nil)),
        model("taroko", "Taroko (TEMU1000)", "太魯閣號（TEMU1000）", TrainLivery.taroko, nil),
        model("emu900", "EMU900 local", "EMU900 區間車", colours(0xC9CCCE, 0xF2C230, 0x262C57),
              Landing(englishPort: "Hualien Port", chinesePort: "花蓮港", year: 2020, month: 10, day: 24)),
        model("emu800", "EMU800 local", "EMU800 區間車", TrainLivery.emu800, nil),
        model("emu700", "EMU700 local", "EMU700 區間車", colours(0xC4C9CD, 0xE9AD59, 0x344B80), nil),
        model("metroC371", "Taipei Metro C371", "北捷 C371", TrainLivery.metroC381, nil),
        model("metroC381", "Taipei Metro C381", "北捷 C381", TrainLivery.metroC381, nil),
        model("metroC341", "Taipei Metro C341", "北捷 C341", TrainLivery.metroC381, nil),
        model("circular610", "Circular Line train", "環狀線列車", colours(0xE3E6E7, 0xF2C230, 0x343D45),
              Landing(englishPort: "Taipei Port", chinesePort: "台北港", year: 2016, month: 11, day: nil)),
        model(Map3DTrainSet.sanyingKey, "Sanying Line train", "三鶯線列車", colours(0xE3E6E7, 0x13A9CF, 0x343D45),
              Landing(englishPort: "Taipei Port", chinesePort: "台北港", year: 2023, month: 8, day: nil)),
        model("wenhu", "Wenhu Line train", "文湖線列車", colours(0xE3E6E7, 0x397BAD, 0x24292E), nil),
        model(Map3DTrainSet.wenhuVAL256Key, "Wenhu Line VAL256", "文湖線 VAL256", colours(0xE3E6E7, 0x468D63, 0x24292E), nil),
        model(Map3DTrainSet.wenhu370Key, "Wenhu Line Type 370", "文湖線 370 型", colours(0xE3E6E7, 0x397BAD, 0x24292E), nil),
        model(Map3DTrainSet.taoyuanAirport1000Key, "Airport MRT Type 1000", "機場捷運 1000 型", colours(0xC4C9CD, 0x3D7FC2, 0x30363D), nil),
        model(Map3DTrainSet.taoyuanAirport2000Key, "Airport MRT Type 2000", "機場捷運 2000 型", colours(0xC4C9CD, 0x7E4E9C, 0x30363D), nil),
        model("kaohsiung", "Kaohsiung MRT train", "高雄捷運列車", colours(0xC9CCCE, 0x45D3C0, 0x30363D), nil),
        model("taichungGreen", "Taichung MRT Green Line train", "台中捷運綠線列車", colours(0xE3E6E7, 0x7CC058, 0x30363D), nil),
        model("klrtCAF", "Kaohsiung light rail (CAF)", "高雄輕軌（CAF）", colours(0xE3E6E7, 0x7CC058, 0x30363D), nil),
        model("klrtCitadis", "Kaohsiung light rail (Citadis)", "高雄輕軌（Citadis）", colours(0xE3E6E7, 0x7CC058, 0x30363D), nil),
        model("dieselRailcar", "DR1000 railcar", "DR1000 柴油客車", colours(0xBBBDB9, 0xE77448, 0xE9BB3B), nil),
        model("ALISHAN", "Alishan Forest Railway train", "阿里山林鐵列車", colours(0xB83230, 0xE9E1CF, 0x1E4A3E), nil),
    ]

    private typealias Landing = NewTrainArrival.Landing

    private static func colours(_ body: Int, _ stripe: Int, _ cab: Int) -> TrainLivery {
        TrainLivery(body: body, stripe: stripe, cab: cab, nose: .flat)
    }

    private static func model(
        _ key: String, _ english: String, _ chinese: String, _ livery: TrainLivery, _ landing: Landing?
    ) -> NewTrainArrival {
        NewTrainArrival(
            key: key, english: english, chinese: chinese,
            body: livery.body ?? 0xC9CCCE, stripe: livery.stripe ?? 0x7B8794, cab: livery.cab ?? 0x222A38,
            landing: landing
        )
    }

    /// The model each train of `world` is drawn as, by its set key: a
    /// bought real line's stock, else its type's or performance's set,
    /// split by number as the 3D map splits it. The train pack counts as
    /// locked, so a model is the same whatever the pack (the 700T, the
    /// E500 push-pull).
    public static func models(in world: GameWorld) -> Set<String> {
        let bought = RealLineStock.setKeys(in: world)
        var models = Set<String>()
        for train in world.trains {
            let base = bought[train.id] ?? Map3DTrainSet.key(type: train.type, performance: train.performance)
            let variant = Map3DTrainSet.variant(of: base, number: train.id.rawValue, locked: TrainPack.sets)
            models.insert(Map3DTrainSet.named(variant)?.key ?? variant)
        }
        return models
    }

    /// The models of `now` with a card that `before` does not have, in the
    /// catalog's order.
    public static func arrivals(now: Set<String>, before: Set<String>) -> [NewTrainArrival] {
        entries.filter { now.contains($0.key) && !before.contains($0.key) }
    }
}

extension GameSession {
    /// Whether this game shows new-train cards: not the demo, the tutorial
    /// or a lesson (their trains are not the player's choice), as the
    /// station stamps (decision 353).
    var showsTrainArrivals: Bool {
        !news.isDemo && tutorial == nil && lesson == nil
    }

    /// After a command: the models the fleet has now; those with a card
    /// it did not have before, and that this session has not shown, go to
    /// ``trainArrivals`` and the news log.
    func noteTrainArrivals() {
        let models = NewTrainArrivals.models(in: world)
        defer { fleetModels = models }
        guard models != fleetModels, showsTrainArrivals else { return }
        let new = NewTrainArrivals.arrivals(now: models, before: fleetModels.union(trainArrivalsShown))
        guard !new.isEmpty else { return }
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        for arrival in new {
            trainArrivalsShown.insert(arrival.key)
            news.add(day: today, .newTrain) { arrival.newsText(in: $0) }
        }
        trainArrivals += new
    }

    /// Shows the cards of the models `keys` (catalog keys), whatever the
    /// fleet: for the website screenshot test (decision 566).
    public func showTrainArrivals(_ keys: [String]) {
        trainArrivals += keys.compactMap { NewTrainArrivals.catalog[$0] }
    }

    /// The player closed the card in front: the next one shows, or, with
    /// `all`, none of those waiting.
    public func dismissTrainArrival(all: Bool = false) {
        if all { trainArrivals = [] } else if !trainArrivals.isEmpty { trainArrivals.removeFirst() }
    }
}
