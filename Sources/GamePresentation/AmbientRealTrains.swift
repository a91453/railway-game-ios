import GameCore

// Decision 606 (IDLEREAL, 2026-11-05): the idle mode (decision 414) follows
// the real timetables' trains too, not only the player's own: "放空模式……
// 可以不要局限自己的車，在路上跑的尚未收購也能跟隨" (the owner). Only view
// state: nothing here changes the world, the save or a golden value.

/// A real timetable's train (decision 304) the 3D map can follow: its
/// system and line, as ``RealTrainTraffic`` names them, and its place's key
/// (``RealTrainTraffic/places(of:at:on:dayBefore:)``), unique on the line
/// while it runs.
public struct RealTrainID: Hashable, Sendable {
    public let system: String
    public let line: String
    public let place: String

    public init(system: String, line: String, place: String) {
        self.system = system
        self.line = line
        self.place = place
    }
}

/// Decision 606: what the idle mode knows of the real trains on the map:
/// which run now and how much each is worth a look (the site's
/// `pickTourTrain`), where one is, and the line naming it and where it goes
/// ("普悠瑪號 往樹林"). Made once when the mode starts, off the main actor.
public struct AmbientRealTrains: Sendable {
    /// What a Taiwan Railway train of the week's timetable is, by number.
    struct TRATrain: Sendable, Equatable {
        let kind: String
        let model: String
        let destination: String
    }

    public let traffic: RealTrainTraffic
    let frame: RealWorldFrame
    let railways: RealRailways?
    let tra: [String: TRATrain]
    /// The High Speed Rail's trains' last stops, by number.
    let highSpeed: [String: String]

    /// The trains of `traffic` (the real lines on `frame`'s map), named
    /// from `operations`' timetables and `railways`' stations.
    public init(traffic: RealTrainTraffic, operations: RealRailwayOperations, frame: RealWorldFrame, railways: RealRailways?) {
        self.traffic = traffic
        self.frame = frame
        self.railways = railways
        var tra: [String: TRATrain] = [:]
        if traffic.lines.contains(where: { $0.system == "tra" }), let week = operations.weekSchedule(forSystem: RealTrainTraffic.traSchedule) {
            for train in week.trains where tra[train.number] == nil {
                tra[train.number] = TRATrain(kind: train.kind, model: train.model, destination: train.stops.last?.name ?? "")
            }
        }
        self.tra = tra
        var highSpeed: [String: String] = [:]
        if traffic.lines.contains(where: { $0.system == "thsr" }), let day = operations.schedule(forSystem: "thsr") {
            for train in day.trains { highSpeed[train.number] = train.stops.last?.name }
        }
        self.highSpeed = highSpeed
    }

    // MARK: - Which are worth a look (the site's pickTourTrain)

    /// The site's `TOUR_W`: how much likelier a Taiwan Railway train of a
    /// kind is picked than a local train; any other train is 1.
    public static let tourWeights: [String: Double] = ["其他": 24, "莒光/復興": 10, "自強": 5, "區間快": 2, "區間車": 1]
    /// The site's `TOUR_CAP`: no train weighs more than this share of all
    /// the candidates' weights together, so one rare train does not come
    /// round again and again.
    public static let tourCap = 0.03
    /// How much likelier a rare or named train is (the site's `w *= 4`).
    public static let rareFactor = 4.0
    /// The site's `tra_special_trains.json` `rollingStock` of rarity
    /// 稀有, by the timetable's model (`carNames`): the Taroko, the DR3100
    /// and the Chu-Kuang.
    public static let rareModels: Set<String> = ["自強(太,障)", "自強(D31)", "莒光"]
    /// The same file's `namedTrains` with their numbers: the trains with a
    /// name of their own, by number.
    public static let namedTrains: [String: (english: String, chinese: String)] = [
        "5898": ("Blue Train", "藍皮解憂號"), "5899": ("Blue Train", "藍皮解憂號"),
        "6652": ("Sea Breeze", "海風號"), "6655": ("Sea Breeze", "海風號"),
        "6676": ("Mountain Mist", "山嵐號"), "6677": ("Mountain Mist", "山嵐號"),
        "1": ("Formosa Star", "環島之星"), "2": ("Formosa Star", "環島之星"),
        "8888": ("Mountain and Sea", "山海號"), "8889": ("Plains", "平原號"),
    ]

    /// The site's weight of a train before the cap: its kind's
    /// (``tourWeights``, `nil` for a train of another system), four times
    /// that for a rare or named one.
    public static func tourWeight(kind: String?, rare: Bool) -> Double {
        let weight = kind.flatMap { tourWeights[$0] } ?? 1
        return rare ? weight * rareFactor : weight
    }

    /// The weight of real train `id`.
    func weight(of id: RealTrainID) -> Double {
        guard id.system == "tra", let number = Self.traNumber(ofPlace: id.place) else { return Self.tourWeight(kind: nil, rare: false) }
        let train = tra[number]
        let model = RealTrainTraffic.traModel(ofPlace: id.place) ?? train?.model
        let rare = Self.namedTrains[number] != nil || model.map { Self.rareModels.contains($0) } ?? false
        return Self.tourWeight(kind: train?.kind, rare: rare)
    }

    /// The trains running at second `second` of game day `day` (`dayBefore`
    /// the day before), each with its weight, in the lines' order.
    public func candidates(at second: Double, on day: RealServiceDay, dayBefore: RealServiceDay) -> [AmbientDirector.Cast.RealTrain] {
        traffic.lines.flatMap { line in
            traffic.places(of: line, at: second, on: day, dayBefore: dayBefore).map { place in
                let id = RealTrainID(system: line.system, line: line.line.id, place: place.key)
                return AmbientDirector.Cast.RealTrain(id: id, weight: weight(of: id))
            }
        }
    }

    // MARK: - Where one is

    func line(of id: RealTrainID) -> RealTrainTraffic.Line? {
        traffic.lines.first { $0.system == id.system && $0.line.id == id.line }
    }

    func place(of id: RealTrainID, at second: Double, on day: RealServiceDay, dayBefore: RealServiceDay) -> (km: Double, towardKm: Double)? {
        guard let line = line(of: id) else { return nil }
        return traffic.places(of: line, at: second, on: day, dayBefore: dayBefore).first { $0.key == id.place }.map { ($0.km, $0.towardKm) }
    }

    /// Where real train `id` is at second `second` of the day, in world
    /// units; `nil` when it is not running.
    public func location(of id: RealTrainID, at second: Double, on day: RealServiceDay, dayBefore: RealServiceDay) -> WorldCoordinate? {
        guard let line = line(of: id), let place = place(of: id, at: second, on: day, dayBefore: dayBefore) else { return nil }
        let here = line.shape.coordinate(atKm: place.km)
        let point = frame.worldPosition(latitude: here.latitude, longitude: here.longitude)
        return WorldCoordinate(x: Int64(point.x.rounded()), y: Int64(point.y.rounded()))
    }

    // MARK: - What it is and where it goes

    /// The number in a Taiwan Railway or High Speed Rail place key.
    static func traNumber(ofPlace key: String) -> String? {
        guard let cut = key.lastIndex(of: "#") else { return nil }
        return String(key[key.index(after: cut)...])
    }

    /// What a Taiwan Railway train of `model` (its timetable's) and `kind`
    /// is called (`tra_special_trains.json`'s `rollingStock` names).
    static func traName(model: String, kind: String?) -> (english: String, chinese: String) {
        if model.hasPrefix("自強(3000") || model == "110K" || model == "110M" { return ("New Tze-Chiang", "新自強號") }
        if model.contains("(太,") { return ("Taroko", "太魯閣號") }
        if model.contains("(普,") { return ("Puyuma", "普悠瑪號") }
        if model.contains("(PP") { return ("Push-pull Tze-Chiang", "推拉式自強號") }
        if model.contains("(D31") { return ("DR3100 Tze-Chiang", "柴聯自強號") }
        if model.hasPrefix("莒光") { return ("Chu-Kuang", "莒光號") }
        if model.hasPrefix("自強") { return ("Tze-Chiang", "自強號") }
        if model.hasPrefix("區間快") { return ("Fast Local", "區間快車") }
        if model.hasPrefix("區間車") { return ("Local", "區間車") }
        if model.hasPrefix("普通車") { return ("Ordinary", "普通車") }
        switch kind {
        case "自強": return ("Tze-Chiang", "自強號")
        case "莒光/復興": return ("Chu-Kuang", "莒光號")
        case "區間快": return ("Fast Local", "區間快車")
        default: return ("Taiwan Railway", "臺鐵")
        }
    }

    /// A real station's name in `language`, by its Chinese name in
    /// operations system `system`.
    func stationName(_ chinese: String, system: String, in language: DisplayLanguage) -> String {
        guard language != .traditionalChinese, let site = RealRailwayOperations.siteSystems[system] else { return chinese }
        let key = RealRailways.stationKey(chinese)
        return railways?.stations.first { $0.system.id == site && RealRailways.stationKey($0.chinese) == key }?.name(in: language) ?? chinese
    }

    /// The system's name, for a metro train in English (the data names
    /// its lines in Chinese only).
    func systemName(_ system: String, in language: DisplayLanguage) -> String? {
        guard let site = RealRailwayOperations.siteSystems[system] else { return nil }
        return RealRailways.System.all.first { $0.id == site }?.name(in: language)
    }

    /// Decision 606: the line the idle mode shows of real train `id` at
    /// second `second`: what train it is and where it goes, "普悠瑪號 往樹林"
    /// ("Puyuma to Shulin"), "高鐵 123 次 往左營", "板南線 往頂埔"; `nil` when
    /// it is not running.
    public func caption(of id: RealTrainID, at second: Double, on day: RealServiceDay, dayBefore: RealServiceDay,
                        language: DisplayLanguage) -> String? {
        guard let line = line(of: id), let place = place(of: id, at: second, on: day, dayBefore: dayBefore) else { return nil }
        let name: (english: String, chinese: String)
        var destination: String?
        switch id.system {
        case "tra":
            let number = Self.traNumber(ofPlace: id.place) ?? ""
            let train = tra[number]
            name = Self.namedTrains[number] ?? Self.traName(model: RealTrainTraffic.traModel(ofPlace: id.place) ?? train?.model ?? "",
                                                             kind: train?.kind)
            destination = train?.destination
        case "thsr":
            let number = traffic.number(of: line, place: id.place)
            name = number.map { ("THSR \($0)", "高鐵 \($0) 次") } ?? ("THSR", "高鐵")
            destination = number.flatMap { highSpeed[$0] }
        default:
            let short = RealRailwayOperations.shortName(line.line.name)
            let english = systemName(id.system, in: .english) ?? short
            name = RealTrainTraffic.isExpress(place: id.place) ? ("\(english) express", "\(short)直達車") : (english, short)
        }
        if destination == nil, line.ringKm == nil, !line.stationKm.isEmpty {
            // The end of the line it heads for.
            let up = RealTrainRun.way(from: place.km, to: place.towardKm, ringKm: nil) >= 0
            let end = traffic.lastStopKm(of: line, place: id.place, on: day, dayBefore: dayBefore)
                ?? (up ? line.stationKm[line.stationKm.count - 1] : line.stationKm[0])
            let nearest = line.stationKm.indices.min { abs(line.stationKm[$0] - end) < abs(line.stationKm[$1] - end) }
            destination = nearest.map { line.line.stations[$0].name }
        }
        let title = language.text(name.english, name.chinese)
        guard let destination, !destination.isEmpty else { return title }
        let to = stationName(destination, system: id.system, in: language)
        return language.text("\(title) to \(to)", "\(title) 往\(to)")
    }
}

extension RealTrainTraffic {
    /// The runs of `line` and the key in them of the train at `place`
    /// (without its set's name or the day before's `-`).
    private func runs(of line: Line, place: String, on day: RealServiceDay, dayBefore: RealServiceDay) -> (runs: Runs, key: String)? {
        let earlier = place.hasPrefix("-")
        let key = earlier ? String(place.dropFirst()) : place
        switch line.schedule {
        case .sets(let timetable, let sets):
            guard let cut = key.firstIndex(of: "#"), let name = timetable.setName(for: earlier ? dayBefore : day),
                  key[..<cut] == name, let runs = sets[name] else { return nil }
            return (runs, String(key[key.index(after: cut)...]))
        case .daily(let runs):
            return (runs, key)
        case .week(let days):
            return (days[RealWeekTimetable.bit(of: earlier ? dayBefore : day)], key)
        case .headway:
            return nil
        }
    }

    /// Decision 606: the train number of the train at `place` on `line`,
    /// when its timetable gives one (the High Speed Rail's, Taiwan
    /// Railway's).
    func number(of line: Line, place: String) -> String? {
        let key = place.hasPrefix("-") ? String(place.dropFirst()) : place
        switch line.schedule {
        case .daily(let runs):
            guard let index = Int(key), let numbers = runs.numbers, numbers.indices.contains(index) else { return nil }
            return numbers[index]
        case .week:
            return AmbientRealTrains.traNumber(ofPlace: key)
        default:
            return nil
        }
    }

    /// Decision 606: how far along `line` the last stop of the train at
    /// `place` is; `nil` for a headway line's trains, which run there and
    /// back.
    func lastStopKm(of line: Line, place: String, on day: RealServiceDay, dayBefore: RealServiceDay) -> Double? {
        guard let (runs, key) = runs(of: line, place: place, on: day, dayBefore: dayBefore),
              let index = runs.runs.indices.first(where: { runs.key($0) == key }) else { return nil }
        return runs.runs[index].stops.last?.km
    }
}

extension Map3DRealTrains {
    /// Decision 606: where real train `id` is at second `second` of game
    /// day `day`, as the follow camera reads it (``Map3DFollow/Pose``):
    /// its front car where it is drawn; `nil` when it is not running or
    /// its front is not drawn (in a tunnel, past the scene, on a line the
    /// player bought).
    public func pose(of id: RealTrainID, second: Double, day: RealServiceDay, dayBefore: RealServiceDay) -> Map3DFollow.Pose? {
        guard let index = traffic.lines.firstIndex(where: { $0.system == id.system && $0.line.id == id.line }), !tracks[index].isEmpty,
              let place = traffic.places(of: traffic.lines[index], at: second, on: day, dayBefore: dayBefore).first(where: { $0.key == id.place })
        else { return nil }
        let line = traffic.lines[index]
        let ring = line.ringKm ?? line.shape.lengthKm
        let isRing = line.ringKm != nil
        let formation = Self.formation(of: formations[index], system: line.system, place: place.key)
        let way: Double = RealTrainRun.way(from: place.km, to: place.towardKm, ringKm: isRing ? ring : nil) >= 0 ? 1 : -1
        let length = Double(formation.cars) * Self.carPitch
        var front = place.km + way * length / 2
        if !isRing { front = min(max(front, 0), ring) }
        let bound = legs[index][place.key.hasPrefix("-") ? String(place.key.dropFirst()) : place.key]
        func at(_ km: Double) -> Map3DPoint? {
            railPoint(line: index, atKm: km, way: way, ring: isRing ? ring : nil, bound: bound)
        }
        guard let a = at(front), let b = at(front - way * Self.carLength) else { return nil }
        var ahead = a - b
        ahead.y = 0
        guard let forward = ahead.normalized else { return nil }
        var bases: [Map3DPoint] = []
        for car in 0..<formation.cars {
            let start = front - way * Double(car) * Self.carPitch
            if let p = at(start), let q = at(start - way * Self.carLength) { bases.append((p + q) * 0.5) }
        }
        let middle = bases.isEmpty ? nil : bases.reduce(Map3DPoint(0, 0, 0), +) * (1 / Float(bases.count))
        return Map3DFollow.Pose(forward: forward, nose: a, rail: (a + b) * 0.5, middle: middle,
                                length: Float(length * 1_000))
    }
}
