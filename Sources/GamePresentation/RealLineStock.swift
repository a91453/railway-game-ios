import GameCore

/// Decision 535: the trains of a real line the company bought (decision
/// 315, decision 400) are drawn and named as the line's own stock, the
/// same as before it was bought (``Map3DRealTrains/formation(system:id:name:)``):
/// the Neiwan Line's DR1000 railcars, the Danhai light rail's own trains,
/// the Xinbeitou Branch Line's C371. So are the trains the player puts on
/// the line later. Only how they look and what they are called: their
/// performance, type and cars stay GameCore's, as bought.
public enum RealLineStock {
    /// The set key the trains of the real line `id`
    /// (``LineAcquisition/realLine``, `"tra:NEIWAN"`) are drawn as, `nil`
    /// for a line the game has no set of its own for.
    static func setKey(ofRealLine id: String) -> String? {
        guard let colon = id.firstIndex(of: ":") else { return nil }
        let system = String(id[..<colon]), network = String(id[id.index(after: colon)...])
        let name = system == "tra" ? RealBranchLine.names[network]?.chinese ?? network : network
        let key = Map3DRealTrains.formation(system: system, id: network, name: name).key
        return key.isEmpty ? nil : key
    }

    /// The set key each train on a line `world` bought is drawn as
    /// (``setKey(ofRealLine:)``), by train: every train the line has,
    /// those it was bought with and those put on it since.
    static func setKeys(in world: GameWorld) -> [TrainID: String] {
        var keys: [TrainID: String] = [:]
        for acquisition in world.acquisitions where acquisition.kind == .railway {
            guard let id = acquisition.line, let line = world.line(id: id),
                  let key = setKey(ofRealLine: acquisition.realLine) else { continue }
            for train in line.assignedTrains { keys[train] = key }
        }
        return keys
    }

    /// What a train drawn as set `key` is called, `nil` for a set that is
    /// no real line's stock.
    static func name(ofSet key: String, in language: DisplayLanguage) -> String? {
        switch key {
        case "dieselRailcar": language.text("DR1000 railcar", "DR1000 柴油客車")
        case "emu800": language.text("EMU800 local", "EMU800 區間車")
        case "emu500": language.text("EMU500 local", "EMU500 區間車")
        case "emu900": language.text("EMU900 local", "EMU900 區間車")
        case "danhaiLRT": language.text("Danhai light rail train", "淡海輕軌列車")
        case "ankengLRT": language.text("Ankeng light rail train", "安坑輕軌列車")
        case "metroC371": language.text("Taipei Metro C371", "北捷 C371")
        case Map3DTrainSet.sanyingKey: language.text("Sanying Line train", "三鶯線列車")
        default: nil
        }
    }

    /// What the trains of a line drawn as set `key` are called: as
    /// ``name(ofSet:in:)``, but a local line's three fleets together.
    static func lineName(ofSet key: String, in language: DisplayLanguage) -> String? {
        key == "emu800" ? language.text("EMU500 / 800 / 900 local", "EMU500／800／900 區間車") : name(ofSet: key, in: language)
    }
}

extension GameWorld {
    /// Decision 535: what train `id` is, when it runs on a real line the
    /// company bought: that line's stock, as the 3D map draws it (a local
    /// line's three fleets split by the train's number, as
    /// ``Map3DTrainSet/variant(of:number:locked:)``); `nil` for any other.
    public func boughtStockText(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let key = RealLineStock.setKeys(in: self)[id] else { return nil }
        return RealLineStock.name(ofSet: Map3DTrainSet.variant(of: key, number: id.rawValue), in: language)
    }

    /// Decision 535: what the trains of line `id` are, when it is a real
    /// line the company bought; `nil` for any other.
    public func boughtStockText(ofLine id: LineID, in language: DisplayLanguage) -> String? {
        guard let acquisition = acquisitions.first(where: { $0.kind == .railway && $0.line == id }),
              let key = RealLineStock.setKey(ofRealLine: acquisition.realLine) else { return nil }
        return RealLineStock.lineName(ofSet: key, in: language)
    }
}
