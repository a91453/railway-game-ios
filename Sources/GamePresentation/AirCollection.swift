import GameCore

/// Decision 701: the collection's aircraft page: the four aircraft of
/// decision 698's studies in words a player reads, which airports each is
/// seen at, the two airports its 3D stage shows, and the airports of the
/// game's own map with the day's flights (decision 695's, read as they are).
/// No operator's name or mark anywhere: a type is named by its seats and
/// engines.
public enum AirCollection {
    public typealias Kind = Map3DAircraftStudies.Kind
    public typealias Entry = FerryCollection.Entry

    /// Where a type flies.
    public enum Reach: Sendable {
        /// The small islands off Taiwan's shores.
        case islands
        /// Between Taiwan's cities and its islands.
        case domestic
        /// Nearby countries, and the busiest domestic flights.
        case regional
        /// Other continents.
        case longHaul
    }

    /// The four types, smallest first: the order of the 3D stage's row.
    public static let kinds = Kind.allCases

    /// About how many passengers a type seats: the 19 and 70 of the two
    /// propeller types' names, and a usual cabin of the single-aisle and
    /// twin-aisle jets the studies' sizes are of.
    public static func seats(_ kind: Kind) -> Int {
        switch kind {
        case .commuter19: 19
        case .regional70: 70
        case .narrowJet: 180
        case .wideJet: 300
        }
    }

    public static func reach(_ kind: Kind) -> Reach {
        switch kind {
        case .commuter19: .islands
        case .regional70: .domestic
        case .narrowJet: .regional
        case .wideJet: .longHaul
        }
    }

    /// The airports of ``AirportCatalog`` a type is seen at, by key. Keys
    /// the catalogue does not have (yet) are passed over, so an airport it
    /// gains later joins its types' lists by being named here.
    ///
    /// The 19-seat type flies from Kaohsiung and Taitung to the small
    /// islands (Qimei, Wang'an, Lanyu, Green Island) and between Magong
    /// and Qimei; the 70-seat type is the domestic and island fleet's;
    /// single-aisle jets fly the regional international flights of every
    /// international airport and the busiest island flights (Kinmen,
    /// Magong); twin-aisle jets fly from Taoyuan, and daily from Songshan
    /// and Kaohsiung.
    static let airportKeys: [Kind: Set<String>] = [
        .commuter19: ["khh", "ttt", "mzg", "cmj", "wot", "kyd", "gni"],
        .regional70: ["tsa", "rmq", "khh", "tnn", "cyi", "hun", "ttt", "mzg", "knh", "lzn", "mfk"],
        .narrowJet: ["tpe1", "tpe2", "tsa", "rmq", "khh", "tnn", "hun", "mzg", "knh"],
        .wideJet: ["tpe1", "tpe2", "tsa", "khh"],
    ]

    /// The catalogue's airports a type is seen at, in the catalogue's order.
    static func places(of kind: Kind) -> [AirportCatalog.Place] {
        let keys = airportKeys[kind] ?? []
        return AirportCatalog.places.filter { keys.contains($0.key) }
    }

    /// The types seen at the catalogue's airport of this Chinese name
    /// (an ``Airport`` carries the catalogue's names), smallest first;
    /// empty for an airport the catalogue does not have.
    public static func kinds(atAirportNamed name: String) -> [Kind] {
        guard let place = AirportCatalog.places.first(where: { $0.chinese == name }) else { return [] }
        return kinds.filter { airportKeys[$0]?.contains(place.key) == true }
    }

    /// A type's name: its seats or body, and its engines.
    public static func name(_ kind: Kind, in language: DisplayLanguage) -> String {
        switch kind {
        case .commuter19: language.text("19-seat twin propeller", "十九座雙螺旋槳")
        case .regional70: language.text("70-seat twin turboprop", "七十座雙渦輪螺旋槳")
        case .narrowJet: language.text("Narrow-body jet", "窄體噴射客機")
        case .wideJet: language.text("Wide-body jet", "廣體噴射客機")
        }
    }

    /// A list of names as a sentence reads them.
    static func listed(_ names: [String], in language: DisplayLanguage) -> String {
        names.joined(separator: language.text(", ", "、"))
    }

    /// An airport's name as the list gives it: Taoyuan's two terminals as
    /// one airport.
    static func shortName(_ place: AirportCatalog.Place, in language: DisplayLanguage) -> String {
        place.key.hasPrefix("tpe") ? language.text("Taoyuan Airport", "桃園機場") : language.text(place.english, place.chinese)
    }

    /// The four aircraft, one entry each: seats, where it flies, its size,
    /// and the airports it is seen at.
    public static func aircraft(in language: DisplayLanguage) -> [Entry] {
        kinds.map { kind in
            let size = Map3DAircraftStudies.dimensions(kind)
            let seats = seats(kind)
            let first: String = switch reach(kind) {
            case .islands: language.text("\(seats) seats · short hops to the small islands", "\(seats) 個座位 · 飛小離島的短程航線")
            case .domestic: language.text("\(seats) seats · domestic flights and the islands", "\(seats) 個座位 · 飛國內線與離島")
            case .regional: language.text("About \(seats) seats · nearby countries and the busiest island flights",
                                          "約 \(seats) 個座位 · 飛鄰近國家，也飛最忙的離島航線")
            case .longHaul: language.text("About \(seats) seats · long international flights", "約 \(seats) 個座位 · 飛長程國際線")
            }
            var seen: [String] = []
            for place in places(of: kind) {
                let name = shortName(place, in: language)
                if !seen.contains(name) { seen.append(name) }
            }
            var lines = [
                first,
                language.text("\(size.length.metresText) m long · \(size.wingspan.metresText) m wingspan",
                              "長 \(size.length.metresText) 公尺 · 翼展 \(size.wingspan.metresText) 公尺"),
            ]
            if !seen.isEmpty {
                lines.append(language.text("Seen at ", "看得到的機場：") + listed(seen, in: language))
            }
            return Entry(id: kind.rawValue, title: name(kind, in: language), lines: lines)
        }
    }

    /// The two airports the 3D stage shows, with what stands on each.
    public static func scenes(in language: DisplayLanguage) -> [(exhibit: Map3DCollectionShowcase.Exhibit, entry: Entry)] {
        [
            (.cityAirport, Entry(id: "cityAirport", title: language.text("City airport", "城市機場"), lines: [
                language.text("A terminal with four boarding bridges, a control tower and a hangar",
                              "有四座空橋的航廈、塔台與機棚"),
                language.text("Two narrow-body jets at the bridges, a 70-seat turboprop on a remote stand",
                              "兩架窄體噴射客機靠空橋，一架七十座螺旋槳客機停在遠端機位"),
            ])),
            (.islandAirport, Entry(id: "islandAirport", title: language.text("Island airport", "離島機場"), lines: [
                language.text("A small terminal with its tower on the roof, beside a short runway",
                              "屋頂上有小塔台的小航廈，旁邊是一條短跑道"),
                language.text("A 19-seat twin propeller on the apron: passengers walk out to it",
                              "十九座雙螺旋槳停在停機坪，旅客走路登機"),
            ])),
        ]
    }

    /// The airports of this game's map, one entry each: the day's flights
    /// and air passengers (or that a typhoon shut it), and the types seen
    /// there. Empty for a map without airports.
    public static func mapAirports(_ days: [AirportDay], in language: DisplayLanguage) -> [Entry] {
        days.map { day in
            var lines = [
                day.isClosed
                    ? language.text("Closed by the typhoon today: no flights.", "今天因颱風關閉，沒有航班。")
                    : language.text("\(day.flights.groupedText) flights and \(day.passengers.groupedText) air passengers today",
                                    "今天 \(day.flights.groupedText) 架次、\(day.passengers.groupedText) 位旅客進出"),
            ]
            let seen = kinds(atAirportNamed: day.airport.name).map { name($0, in: language) }
            if !seen.isEmpty { lines.append(language.text("Seen here: ", "看得到：") + listed(seen, in: language)) }
            return Entry(id: "airport.\(day.airport.id)", title: day.airport.title(in: language), lines: lines)
        }
    }

    /// The header over ``mapAirports(_:in:)``.
    public static func mapAirportsTitle(in language: DisplayLanguage) -> String {
        language.text("Airports on this map", "這張地圖的機場")
    }

    /// The page's note: what the airports do in a game.
    public static func note(in language: DisplayLanguage) -> String {
        language.text(
            "Flights come and go by themselves at the airports of a real-world map. Build a station that trains call at within 800 m of a terminal and its passengers ride your trains.",
            "實景地圖上的機場，航班會自己起降。在航廈 800 公尺內蓋一座有列車停靠的車站，旅客就會搭你的車。"
        )
    }
}

private extension Float {
    /// Metres to two places, as the makers give an aircraft's size.
    var metresText: String {
        let hundredths = Int((self * 100).rounded())
        let cents = hundredths % 100
        return "\(hundredths / 100)." + (cents < 10 ? "0" : "") + "\(cents)"
    }
}
