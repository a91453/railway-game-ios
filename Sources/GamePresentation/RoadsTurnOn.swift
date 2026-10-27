// Decision 428: a game that started without roads (a save from before
// decision 400, or a map whose new games had none) can turn them on, from
// the bus tool, so its buses can run. Never by itself as a save is read:
// the player's old game does not grow roads unasked.

import GameCore

/// What the bus tool offers in a game without roads (decision 428).
public enum RoadsOffer: Hashable, Sendable {
    /// The roads can be turned on: a blank map's grow from its towns, a
    /// real-world map's are read from the base map with its land.
    case available
    /// A real-world map outside Taiwan whose land came all at once (or not
    /// at all): the base map is Taiwan's alone, so no roads would come.
    case unreadable

    /// What the bus tool says about it.
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .available:
            language.text(
                "This game has no roads yet. Turn them on and the towns' roads grow toward your stations, and buses can run on them.",
                "這個存檔還沒有道路。打開後，城鎮的路會慢慢長向車站，就能開公車。"
            )
        case .unreadable:
            language.text("Maps outside Taiwan have no road data yet, so buses can't run here.", "台灣以外的地圖還沒有道路資料，不能開公車。")
        }
    }

    /// The button that turns them on, and the title of its confirmation.
    public static func buttonTitle(in language: DisplayLanguage) -> String {
        language.text("Turn On Roads and Buses", "打開道路與公車")
    }

    /// What the confirmation says before they are turned on.
    public static func confirmation(in language: DisplayLanguage) -> String {
        language.text(
            "Once on, roads can't be turned off. They grow a little each month. It's free.",
            "打開後不能關閉，路會每個月長一點。不用花錢。"
        )
    }
}

extension GameWorld {
    /// The middles of the towns a blank map began with (decision 428),
    /// whose roads turning them on starts from, as a new game's
    /// (``Land/townCentres(seed:in:)``). A new game draws its towns, demand
    /// events, weather and the city's requests from one seed, and buying
    /// the map keeps it: the first of these the world still holds whose
    /// towns other than the first (always the world's middle) have land
    /// at their middles is taken. With none, only the world's middle.
    func startingTowns() -> [PlanPoint] {
        let seeds = [mapExpansion?.townSeed, demandEvents?.seed, disruptions?.seed, cityRequests?.seed].compactMap { $0 }
        for seed in seeds {
            let towns = Land.townCentres(seed: seed, in: bounds)
            let peopled = towns.dropFirst().allSatisfy {
                land.cell(row: Int($0.y / Land.cellLength), column: Int($0.x / Land.cellLength)) != nil
            }
            if peopled { return towns }
        }
        return [PlanPoint(x: bounds.width / 2, y: bounds.height / 2)]
    }
}

extension GameSession {
    /// Whether the bus tool is in the toolbar (decision 428): in every
    /// game but the tutorial and the lessons. Without roads it offers to
    /// turn them on (``roadsOffer``); with them it draws routes
    /// (``allowsBusTool``).
    public var offersBusTool: Bool {
        tutorial == nil && lesson == nil
    }

    /// What the bus tool offers in a game without roads, or `nil` when the
    /// game has them or is the tutorial or a lesson (decision 428).
    /// Decision 440: a real-world map of Taiwan whose land came all at once
    /// reads the base map's roads round its stations
    /// (``readRoads(in:baseMap:ahead:)``); only one elsewhere has none.
    public var roadsOffer: RoadsOffer? {
        guard world.roads == nil, offersBusTool else { return nil }
        guard let anchor = world.geoAnchor, world.landBlocks == nil else { return .available }
        return CountryLookup.country(at: anchor) == "TW" ? .available : .unreadable
    }

    /// Turns the roads on (decision 428): a blank map's from the towns it
    /// began with (``GameWorld/startingTowns()``), a real-world map's read
    /// from the base map with its land, in the same edit. Free, and they
    /// stay on. Refused in the tutorial and the lessons, and on a map
    /// whose roads cannot be read; GameCore refuses a game that has them.
    public func turnOnRoads() {
        guard offersBusTool else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Roads can't be turned on in the tutorial or a lesson.", "教學與課程中不能打開道路。"
            ))
            return
        }
        guard roadsOffer != .unreadable else {
            message = StatusMessage(kind: .failure, text: RoadsOffer.unreadable.text(in: language))
            return
        }
        perform(.turnOnRoads(towns: world.geoAnchor == nil ? world.startingTowns() : [])) { _, _, _ in
            language.text(
                "Roads and buses are on. The roads grow toward your stations each month.",
                "道路與公車打開了。路每個月會往車站長一點。"
            )
        }
    }
}
