import Foundation
import GameCore

// The second Taiwan railway history challenge (decision 153): build Liu
// Mingchuan's railway, the Qing dynasty's line from the harbour at Keelung
// to Twatutia (Dadaocheng) by Taipei, then on to Hsinchu. It is played on a
// real-world map from Keelung to Hsinchu, its ground and towns today's, with
// nothing built: the player lays the line, with the era's steam trains only.
//
// The history in its story is from public sources (the English and Chinese
// Wikipedia's "Liu Mingchuan", "Taiwan Railway (Qing dynasty)" /
// 「全臺鐵路商務總局」, 「獅球嶺隧道」, 「騰雲號」): Liu Mingchuan, the first
// governor of the province of Taiwan, began the railway in 1887; the line
// from Keelung through the Shiqiuling tunnel to Twatutia opened in 1891,
// crossing the Tamsui River on a wooden bridge, and the line on to Hsinchu
// in 1893. Its first engines, Teng-Yun among them, came from Germany (the
// owner's `Railway/city_world_reference/` tells the same of Teng-Yun). Its
// targets, money, days and the steam train's numbers are this project's.

extension Challenge {
    /// Build Liu Mingchuan's railway from Keelung to Hsinchu.
    static let liuMingchuan = Challenge(
        id: "history.liuMingchuan",
        titles: ("Liu Mingchuan's Railway", "劉銘傳鐵路：基隆到新竹"),
        stories: (
            "1887: Liu Mingchuan, the first governor of the province of Taiwan, sets out to build the island's first railway. Lay it from the harbour at Keelung through the Shiqiuling ridge to Twatutia by Taipei, which it reached in 1891, then across the Tamsui River and on to Hsinchu, which it reached in 1893. Only the era's steam trains run: small coaches behind engines like Teng-Yun, bought from Germany.",
            "1887 年，台灣首任巡撫劉銘傳開始興建全台第一條鐵路。從基隆港出發，穿過獅球嶺，鋪到台北城外的大稻埕（史實 1891 年通車）；再跨過淡水河，一路延伸到新竹（1893 年通車）。這個年代只有蒸汽列車：小小的客車，跟在騰雲號這樣從德國買來的機車後面。"
        ),
        map: .liuMingchuan,
        rules: { _, _ in LiuMingchuanChallenge.scenario }
    )
}

/// The Liu Mingchuan challenge's map, places, milestones and targets
/// (decision 153).
public enum LiuMingchuanChallenge {
    /// The map's box, in degrees: west of Hsinchu to east of Keelung's
    /// harbour, north of Keelung to south of Hsinchu, a few kilometres round
    /// the line's towns.
    static let west = 120.90
    static let east = 121.80
    static let north = 25.19
    static let south = 24.75

    /// The middle of the box, as ``WholeTaiwan/anchor`` works its own out.
    public static let anchor: GeoAnchor = {
        let y = (RealWorldFrame.mercatorY(north) + RealWorldFrame.mercatorY(south)) / 2
        let latitude = asin(tanh((0.5 - y / RealWorldFrame.worldPoints) * 2 * Double.pi)) * 180 / .pi
        guard let anchor = GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: (west + east) / 2) else {
            preconditionFailure("The middle of the Liu Mingchuan map is not on the Earth.")
        }
        return anchor
    }()

    /// The world round ``anchor`` that holds the box: some 91 by 49 km.
    public static let bounds: WorldBounds = {
        let frame = RealWorldFrame(anchor: anchor, bounds: .standard)
        let corners = [(north, west), (south, east)].map { frame.worldPosition(latitude: $0.0, longitude: $0.1) }
        let halfWidth = corners.map { abs($0.x - frame.middleX) }.max() ?? 0
        let halfHeight = corners.map { abs($0.y - frame.middleY) }.max() ?? 0
        do {
            return try WorldBounds(width: Int64((2 * halfWidth).rounded(.up)), height: Int64((2 * halfHeight).rounded(.up)))
        } catch {
            preconditionFailure("The Liu Mingchuan map does not fit in a world: \(error)")
        }
    }()

    /// A place of the line's history, where on the Earth it is.
    struct Place {
        let english: String
        let chinese: String
        let latitude: Double
        let longitude: Double

        func name(in language: DisplayLanguage) -> String {
            language.text(english, chinese)
        }

        /// Where it is on the challenge's map.
        var point: PlanPoint {
            let position = RealWorldFrame(anchor: LiuMingchuanChallenge.anchor, bounds: LiuMingchuanChallenge.bounds)
                .worldPosition(latitude: latitude, longitude: longitude)
            return PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
        }
    }

    /// The towns the milestones name. Keelung, Badu, Taoyuan and Hsinchu are
    /// the TRA stations of the owner's `Railway/site_archive_clean/data/tra.json`
    /// (OpenStreetMap), on or by the sites of the Qing stations; Twatutia's
    /// station stood by today's Tacheng Street, some 650 m north-west of
    /// Taipei Main Station, which is within a station's reach of it.
    static let keelung = Place(english: "Keelung", chinese: "基隆", latitude: 25.1330324, longitude: 121.7392299)
    static let badu = Place(english: "Badu", chinese: "八堵", latitude: 25.1084954, longitude: 121.7290072)
    static let twatutia = Place(english: "Twatutia", chinese: "大稻埕", latitude: 25.0510, longitude: 121.5115)
    static let taoyuan = Place(english: "Taoyuan", chinese: "桃仔園", latitude: 24.988726, longitude: 121.3137769)
    static let hsinchu = Place(english: "Hsinchu", chinese: "新竹", latitude: 24.8014026, longitude: 120.971678)
    static let towns = [keelung, badu, twatutia, taoyuan, hsinchu]

    /// A milestone: the places it links, and what it is called.
    struct Milestone {
        let places: [Place]
        let english: String
        let chinese: String
    }

    /// The line's milestones, in the order history met them: over the
    /// Shiqiuling ridge from Keelung to Badu (the tunnel was finished in
    /// 1890), Keelung to Twatutia (1891), across the Tamsui River from
    /// Twatutia to Taoyuan (a wooden bridge in its day; every way from
    /// Twatutia to Taoyuan crosses the river), and on to Hsinchu (1893).
    static let milestones = [
        Milestone(places: [keelung, badu], english: "Shiqiuling: Keelung to Badu", chinese: "獅球嶺：基隆—八堵"),
        Milestone(places: [keelung, twatutia], english: "Keelung to Twatutia (1891)", chinese: "基隆—大稻埕通車（1891）"),
        Milestone(places: [twatutia, taoyuan], english: "Over the Tamsui: Twatutia to Taoyuan", chinese: "淡水河鐵橋：大稻埕—桃仔園"),
        Milestone(places: [keelung, twatutia, hsinchu], english: "On to Hsinchu (1893)", chinese: "延伸到新竹（1893）"),
    ]

    /// The targets were measured (decision 153, `LiuMingchuanReportTests`,
    /// release build): the line to Twatutia and its stations cost some
    /// $5.4–5.7 million, the line on to Hsinchu $12.4–12.8 million with
    /// its train. A steam train of four cars loses $30,000 a day on the
    /// line to Twatutia, never pays for the rest and goes bankrupt on day
    /// 150; one of eight cars earns $10,000 a day and reaches Hsinchu on
    /// day 1,323 (bronze); one of sixteen earns $108,000 and reaches it on
    /// day 106 (silver); sixteen cars with the company's $5 million loan
    /// from the first day and fares by distance, on day 54 (gold). The
    /// deadline is the six years from 1887 to 1893. The line on to Hsinchu
    /// loses money, as Liu's did: with sixteen cars the two lines together
    /// about break even.
    /// Riders a day to reach.
    static let ridersTarget: Int64 = 15_000
    /// What the governor's treasury starts the railway with: $8 million,
    /// enough for the line to Twatutia and its trains; the line on to
    /// Hsinchu is paid for by what that line earns.
    static let startingBalance = Money(800_000_000)
    static let year = FinancePeriod.year.days

    /// The scenario: the milestones and the riders, steam trains only.
    static let scenario = Scenario(
        id: "history.liuMingchuan",
        goals: milestones.map { .connect(points: $0.places.map(\.point), radius: Land.catchmentRadius) } + [.dailyRiders(ridersTarget)],
        goldDays: 75, silverDays: year, deadlineDays: 6 * year, insolvencyDays: 60, trainTypes: [.steam]
    )

    /// What the station master says first (decision 153): what the
    /// challenge asks, its era's catch, and where to begin.
    static func welcomeText(in language: DisplayLanguage) -> String {
        let years = scenario.deadlineDays / year
        return language.text(
            "1887: the governor wants Taiwan's first railway. Lay it from Keelung's harbour through Shiqiuling to Twatutia, then over the Tamsui to Hsinchu, within \(years) years. Steam trains carry only 50 a car, so make them long. Tap Build, then Network, to begin!",
            "1887 年，巡撫要修台灣第一條鐵路：從基隆港穿過獅球嶺到大稻埕，再跨過淡水河鋪到新竹，\(years) 年內完成。蒸汽列車每節只坐 50 人，列車要夠長。點「建設」再選「路網」開始吧！"
        )
    }

    /// What the station master says when milestone `index` is reached.
    static func milestoneCheer(_ index: Int, in language: DisplayLanguage) -> String {
        switch index {
        case 0: language.text("Through Shiqiuling! Trains from Keelung reach Badu.", "獅球嶺打通了！基隆的列車開得到八堵了。")
        case 1: language.text("Keelung to Twatutia is open, as in 1891!", "基隆到大稻埕通車了，就像 1891 年！")
        case 2: language.text("Over the Tamsui! The way to Taoyuan is open.", "跨過淡水河了！往桃仔園的路通了。")
        default: language.text("On to Hsinchu! Governor Liu's railway is done, as in 1893.", "通車到新竹了！劉巡撫的鐵路完成了，就像 1893 年。")
        }
    }

    /// The milestone goal `index` of the scenario names, if it is one.
    static func milestoneTitle(_ index: Int, in language: DisplayLanguage) -> String? {
        milestones.indices.contains(index) ? language.text(milestones[index].english, milestones[index].chinese) : nil
    }

    /// The challenge's world: a new real-world game on the map from Keelung
    /// to Hsinchu with the treasury's money, its land read in round each
    /// station as it is built (as the whole of Taiwan's, decision 88), and
    /// none of it yet; the line's ends are its story, so its edges bring no
    /// one from beyond the map (decision 137). The app reads in the towns
    /// round ``towns`` and maps the ground (``GameLauncher``).
    public static func make(eventSeed: UInt32 = 1) -> GameWorld {
        var world = GameWorld.newGame(anchor: anchor, bounds: bounds, balance: startingBalance, eventSeed: eventSeed, land: [])
        world.setLandOnDemand()
        world.setOutsideConnections(false)
        // Decision 154: its targets were measured without holidays.
        world.setDisruptions(nil)
        // Decision 157: nor with building materials.
        world.setBuildingMaterials(false)
        do {
            try world.startScenario(scenario)
        } catch {
            preconditionFailure("Could not start the Liu Mingchuan challenge: \(error)")
        }
        return world
    }

    /// The milestones' line on the challenge card.
    public static func milestonesText(in language: DisplayLanguage) -> String {
        language.text(
            "Milestones: Shiqiuling, Twatutia, the Tamsui bridge, Hsinchu · steam trains only, 50 a car",
            "里程碑：獅球嶺、大稻埕、淡水河鐵橋、新竹 · 只有蒸汽列車，每節 50 人"
        )
    }
}
