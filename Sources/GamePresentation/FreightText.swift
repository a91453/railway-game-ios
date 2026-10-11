import GameCore

// What the station panel, the line panel and the economy panel show of
// freight (ARCHITECTURE decision 155), and the session's commands for it,
// in English or Traditional Chinese (see ``DisplayLanguage``). All of it is
// read from the world; nothing here is kept.

extension GameWorld {
    /// Whether this game has freight, so that its controls are shown.
    public var hasFreight: Bool {
        freight != nil
    }

    /// What a freight yard at `station` holds and makes, for the station
    /// panel, or `nil` while it has none or freight is off.
    public func freightYardText(at station: StationID, in language: DisplayLanguage) -> String? {
        guard let yard = freightFacility(at: station) else { return nil }
        let supply = freightSupply(at: station)
        let waiting = language.text(
            "\(yard.stock) t waiting (up to \(Freight.stockLimit) t)",
            "待運 \(yard.stock) 噸（最多 \(Freight.stockLimit) 噸）"
        )
        let makes = supply > 0
            ? language.text("The industry round it makes about \(supply) t a day.", "周圍的工業每天約產出 \(supply) 噸。")
            : language.text(
                "No industry within \(Freight.catchmentRadius / WorldCoordinate.unitsPerMetre) m makes cargo for it.",
                "周圍 \(Freight.catchmentRadius / WorldCoordinate.unitsPerMetre) 公尺內沒有工業供貨。"
            )
        return waiting + "\n" + makes
    }

    /// What station `station` holds of building materials and gets a day
    /// without a train (decision 156), for the station panel; `nil` while
    /// building materials are off.
    public func materialsText(at station: StationID, in language: DisplayLanguage) -> String? {
        guard freight?.buildingMaterials == true else { return nil }
        let stock = materialsStock(at: station), daily = materialsSuppliedPerDay(at: station)
        let held = language.text(
            "Building materials: \(stock) t (up to \(Freight.materialsLimit) t); \(daily) t a day arrive by road.",
            "建材置場：\(stock) 噸（最多 \(Freight.materialsLimit) 噸）；每天由公路運來 \(daily) 噸。"
        )
        // Decision 158: and whether the town ran short last night.
        guard isShortOfMaterials(station) else { return held }
        return held + "\n" + language.text(
            "Short last night: the town grew at a quarter. A raise takes 31 to 169 t, a new block 16 t.",
            "昨晚缺建材：城市只長了四分之一。升級一棟要 31 到 169 噸，新的一格 16 噸。"
        )
    }

    /// Whether this game has building materials, so a yard can send them.
    public var hasBuildingMaterials: Bool {
        freight?.buildingMaterials == true
    }

    /// What building a yard costs and does, for the button's footer.
    public func freightYardHelp(in language: DisplayLanguage) -> String {
        language.text(
            "A freight yard takes the cargo the industrial land within \(Freight.catchmentRadius / WorldCoordinate.unitsPerMetre) m makes, and holds it until a train of a freight line loads it. Trains let their cargo off at the next yard and are paid by the ton and the kilometre.",
            "貨運場收下周圍 \(Freight.catchmentRadius / WorldCoordinate.unitsPerMetre) 公尺內工業區產出的貨物，存放到貨運路線的列車來裝。列車在下一個貨運場卸貨，依噸數與公里數計運費。"
        )
    }

    /// The freight line's cargo, for the line panel: the tons its trains
    /// carry now, or `nil` for a line that carries passengers.
    public func freightLineText(_ id: LineID, in language: DisplayLanguage) -> String? {
        guard let line = line(id: id), line.isFreight else { return nil }
        let trains = line.assignedTrains
        let tons = trains.reduce(Int64(0)) { $0 + cargoOnBoard(of: $1) }
        let capacity = trains.reduce(Int64(0)) { $0 + Self.freightCapacity(cars: train(id: $1)?.cars ?? 0) }
        return language.text(
            "Carrying \(tons) t of \(capacity) t on \(trains.count) trains.",
            "\(trains.count) 列列車載運中：\(tons) 噸／\(capacity) 噸。"
        )
    }

    /// What making a line a freight line means, for the toggle's footer.
    public func freightLineHelp(in language: DisplayLanguage) -> String {
        language.text(
            "Nobody rides a freight line: its trains, \(Freight.tonsPerCar) t a car, load and unload at the stations with a freight yard. Take its trains off first to change it.",
            "貨運路線不載客：列車（每節車廂 \(Freight.tonsPerCar) 噸）只在有貨運場的車站裝卸貨。要改變類型，先把列車從路線上拿下來。"
        )
    }

    /// The freight totals for the economy panel, or `nil` while there is
    /// nothing to say.
    public func freightTotalsText(in language: DisplayLanguage) -> String? {
        guard let state = freight, !state.facilities.isEmpty || state.produced > 0 else { return nil }
        return language.text(
            "Freight: \(state.produced) t made, \(state.delivered) t delivered, \(state.waiting) t waiting, \(state.onBoard) t on board, \(state.spilled + state.lost) t spilled or lost.",
            "貨運：累計產出 \(state.produced) 噸、送達 \(state.delivered) 噸；待運 \(state.waiting) 噸、車上 \(state.onBoard) 噸；溢出或損失 \(state.spilled + state.lost) 噸。"
        )
    }
}

extension GameSession {
    /// Builds a freight yard at the selected station (decision 155).
    public func buildFreightYardAtSelectedStation() {
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station on the map first.", "請先在地圖上選擇車站。"))
            return
        }
        perform { world throws(GameError) in
            try world.buildFreightFacility(at: station.id)
            return language.text(
                "\(station.name) has a freight yard for \(Freight.facilityCost.moneyText).",
                "\(station.name) 蓋了貨運場，花費 \(Freight.facilityCost.moneyText)。"
            )
        }
    }

    /// Takes the selected station's freight yard away, and the cargo
    /// waiting in it (decision 155).
    public func removeFreightYardAtSelectedStation() {
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station on the map first.", "請先在地圖上選擇車站。"))
            return
        }
        perform { world throws(GameError) in
            try world.removeFreightFacility(at: station.id)
            return language.text("\(station.name)'s freight yard is gone.", "\(station.name) 的貨運場已拆除。")
        }
    }

    /// Sets what the selected station's freight yard sends (decision 156).
    public func setFreightProductAtSelectedStation(_ kind: CargoKind) {
        guard let station = selectedStation, world.freightFacility(at: station.id)?.product != kind else { return }
        perform { world throws(GameError) in
            try world.setFreightProduct(at: station.id, to: kind)
            return language.text(
                "\(station.name)'s yard sends \(kind.title(in: .english).lowercased()).",
                "\(station.name) 的貨運場改出\(kind.title(in: .traditionalChinese))。"
            )
        }
    }

    /// Makes the selected line a freight line, or a passenger line again
    /// (decision 155).
    public func setSelectedLineFreight(_ isFreight: Bool) {
        guard let line = requireSelectedLine(), line.isFreight != isFreight else { return }
        perform { world throws(GameError) in
            try world.setLineFreight(line.id, to: isFreight)
            return isFreight
                ? language.text("\(line.name) now carries freight.", "\(line.name) 改為貨運路線。")
                : language.text("\(line.name) carries passengers again.", "\(line.name) 改回客運路線。")
        }
    }
}

extension CargoKind {
    /// Goods or building materials.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .goods: language.text("Goods", "一般貨物")
        case .materials: language.text("Building materials", "建材")
        }
    }
}
