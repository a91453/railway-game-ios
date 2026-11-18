import GameCore

/// Decision 847: the platform screen doors and gates of the real lines the
/// player bought, as the real ones have them: full-height screen doors
/// (the station kit's `platformScreenDoors`, 2.5 m with its header) or a
/// waist-high gate (`halfHeightScreenDoors`, at the line's own height),
/// along the platform's edge with an opening at each of the calling
/// train's doors. Only what the platform looks like: no rule reads it,
/// and nothing is saved.
///
/// Which line has which (checked on 2026-11-18, the decision's table):
/// Taipei Metro's Wenhu and Circular lines full-height everywhere; its
/// four high-capacity lines full-height at the stations built with them
/// (the Xinyi, Songshan, Luzhou and Xinzhuang sections, Dingpu, Nangang
/// Exhibition Center) and the 1.45 m gates added since 2018 at the older
/// ones; the MTR's underground stations, the Airport Express's, the Tung
/// Chung Line's (but Sunny Bay), the Tseung Kwan O Line's and the old
/// West Rail's full-height, the others' gates (1.2 m on the Disneyland
/// Resort Line, 1.55 m on the urban lines, 1.7 m on the Tuen Ma and South
/// Island lines, 1.8 m on the East Rail Line); Kaohsiung's underground
/// stations full-height and only Daliao of its raised ones a gate;
/// Taoyuan's and Taichung's raised stations gates and underground ones
/// full-height. TRA, the high-speed railway, Finland, the light rails and
/// the player's own lines none.
public enum Map3DScreenDoors {
    /// The doors along one platform's edge.
    public struct Doors: Hashable, Sendable {
        /// How high they stand above the platform, metres.
        public let height: Float
        /// Whether they reach the ceiling (screen doors with a header over
        /// them), not a gate the platform's air passes over.
        public let full: Bool

        /// The station kit's `platformScreenDoors`.
        public static let full = Doors(height: 2.5, full: true)
        /// A gate `height` metres high (the kit's `halfHeightScreenDoors`
        /// is 1.3 m).
        public static func gate(_ height: Float) -> Doors { Doors(height: height, full: false) }
    }

    /// Taipei Metro's gates added at the older high-capacity stations: the
    /// first batch's 1.45 m.
    static let taipeiGate = Doors.gate(1.45)
    /// A gate whose height the sources did not give.
    static let otherGate = Doors.gate(1.5)

    /// The doors of the platform of a line bought as `realLine`
    /// (``LineAcquisition/realLine``, `trtc:BL`) at the station called
    /// `station` (its Chinese name), whose track runs in a tunnel when
    /// `underground`; `nil` for none.
    public static func doors(realLine: String, station: String, underground: Bool) -> Doors? {
        let parts = realLine.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let (system, line) = (parts[0], parts[1])
        switch system {
        case "trtc":
            switch line {
            case "BR", "Y": return .full
            case "R_XBT", "G_XBT": return taipeiGate
            default: return (taipeiBuiltWith[line] ?? []).contains(station) ? .full : taipeiGate
            }
        case "hkmtr":
            if underground { return .full }
            switch line {
            case "AEL", "TCL": return station == "欣澳" ? .gate(1.55) : .full
            case "TKL", "TKL_LHP": return .full
            case "DRL": return .gate(1.2)
            case "SIL": return .gate(1.7)
            case "TML": return westRail.contains(station) ? .full : .gate(1.7)
            case "EAL", "EAL_LMC": return station == "紅磡" ? .full : .gate(1.8)
            default: return .gate(1.55)
            }
        case "krtc":
            guard line == "KR" || line == "KO" else { return nil }
            if underground { return .full }
            return station == "大寮" ? otherGate : nil
        case "tymc", "tmrt":
            return underground ? .full : otherGate
        default:
            return nil
        }
    }

    /// Taipei Metro's high-capacity stations built with screen doors, by
    /// line (`trtc.json`'s names); the line's other stations had theirs
    /// added later as gates.
    static let taipeiBuiltWith: [String: Set<String>] = [
        "R": ["廣慈/奉天宮", "象山", "台北101/世貿", "信義安和", "大安", "大安森林公園", "東門"],
        "G": ["北門", "中山", "松江南京", "南京復興", "台北小巨蛋", "南京三民", "松山"],
        "O_XINZHUANG": ["東門", "忠孝新生", "松江南京", "行天宮", "中山國小", "民權西路", "大橋頭", "台北橋", "菜寮", "三重",
                        "先嗇宮", "頭前庄", "新莊", "輔大", "丹鳳", "迴龍"],
        "O_LUZHOU": ["東門", "忠孝新生", "松江南京", "行天宮", "中山國小", "民權西路", "大橋頭", "三重國小", "三和國中", "徐匯中學",
                     "三民高中", "蘆洲"],
        "BL": ["頂埔", "南港展覽館"],
    ]

    /// The Tuen Ma Line's stations of the old West Rail, which had screen
    /// doors from the start; the old Ma On Shan Line's had gates added.
    static let westRail: Set<String> = ["屯門", "兆康", "天水圍", "朗屏", "元朗", "錦上路", "荃灣西", "美孚", "南昌", "柯士甸", "尖東"]

    /// Which real line runs on each track and calls at each station of a
    /// world, and the trains each runs.
    public struct Plan: Sendable {
        /// The real line whose purchase laid each edge.
        var edges: [TrackEdgeID: String] = [:]
        /// The real lines calling at each station, in order.
        var stations: [StationID: [String]] = [:]
        /// The trains each real line runs.
        var formations: [String: [Map3DPlatformProps.Formation]] = [:]
        /// The stations' names.
        var names: [StationID: String] = [:]
        /// Decision 859: which way the trains calling at the platform on
        /// each edge stand there, as the lines' journeys stop them.
        var stands: [TrackEdgeID: Map3DPlatformProps.Stands] = [:]

        public init() {}

        /// `world`'s bought railways.
        public init(world: GameWorld) {
            let bought = world.acquisitions.filter { $0.kind == .railway }
            guard !bought.isEmpty else { return }
            var lineOf: [LineID: String] = [:]
            for acquisition in bought {
                if let line = acquisition.line { lineOf[line] = acquisition.realLine }
                for edge in acquisition.track ?? [] where edges[edge] == nil { edges[edge] = acquisition.realLine }
            }
            var trainLine: [TrainID: String] = [:]
            for line in world.lines {
                guard let real = lineOf[line.id] else { continue }
                for station in Set(line.stops) where !(stations[station] ?? []).contains(real) {
                    stations[station, default: []].append(real)
                    if names[station] == nil { names[station] = world.station(id: station)?.name }
                }
                for train in line.trains { trainLine[train] = real }
            }
            let unit = Float(WorldCoordinate.unitsPerMetre)
            for train in world.trains {
                guard let real = trainLine[train.id], let doors = train.type?.doorsPerCar, doors > 0 else { continue }
                formations[real, default: []].append(Map3DPlatformProps.Formation(cars: train.cars, carLength: Float(train.carPitch) / unit,
                                                                                  doors: Int(doors)))
            }
            for key in stations.keys { stations[key]?.sort() }
            // Decision 859: GameCore stops every train with its head at
            // the platform's far end the way it travels (its berth), not
            // in its middle; so where the line's trains stand depends on
            // which way they come in. Each leg of each of its journeys ends
            // at such a berth.
            for line in world.lines where lineOf[line.id] != nil {
                var patterns: [Int?] = [nil]
                for index in line.patterns.indices { patterns.append(index) }
                for pattern in patterns {
                    guard let journey = world.lineJourney(line.id, pattern: pattern),
                          case .onEdge(var at, _) = journey.start else { continue }
                    let farEnd = journey.isRing ? -1 : journey.legs.count / 2
                    for (index, leg) in journey.legs.enumerated() {
                        // It turns round where it stands at the far end and
                        // where it turns back between the ends.
                        if index == farEnd || journey.intermediateTurnbacks.contains(index) { at = at.reversed }
                        if let last = leg.path.traversals.last { at = last }
                        guard leg.path.distance > 0 else { continue }
                        stands[at.edge, default: []].insert(at.direction == .forward ? .forward : .backward)
                    }
                }
            }
            // At the line's two ends trains stand both ways round: those
            // in from the line at the end away from it, those out of the
            // sidings and depots beyond, which its journeys leave out, at
            // the end towards it, and each platform takes both through the
            // day (the Wenhu Line's Taipei Zoo and Nangang Exhibition
            // Center, four tracks each).
            for line in world.lines where lineOf[line.id] != nil && !line.isRing && line.stops.count >= 2 {
                for end in [line.stops[0], line.stops[line.stops.count - 1]] {
                    for platform in world.network.platforms(of: end) { stands[platform.edge] = [.forward, .backward] }
                }
            }
        }

        /// Decision 859: which way the trains calling at the platform on
        /// `edge` stand there; empty when none of the lines bought does.
        public func stands(edge: TrackEdgeID) -> Map3DPlatformProps.Stands {
            stands[edge] ?? []
        }

        /// The real line of the platform on `edge` at `station`: the one
        /// that laid the edge, else the first calling there.
        func realLine(edge: TrackEdgeID, station: StationID) -> String? {
            edges[edge] ?? stations[station]?.first
        }

        /// The doors of the platform on `edge` at `station`; `nil` for none.
        public func doors(edge: TrackEdgeID, station: StationID, underground: Bool) -> Doors? {
            guard let real = realLine(edge: edge, station: station) else { return nil }
            return Map3DScreenDoors.doors(realLine: real, station: names[station] ?? "", underground: underground)
        }

        /// The trains of the line on `edge` at `station`.
        func trains(edge: TrackEdgeID, station: StationID) -> [Map3DPlatformProps.Formation] {
            realLine(edge: edge, station: station).flatMap { formations[$0] } ?? []
        }
    }

    // MARK: Layout

    /// How wide an opening is, metres: the screen door's leaves, as wide as
    /// the trains' doors and a little more.
    public static let opening: Float = 2.0
    /// How far from the platform's edge they stand, metres: behind the
    /// edge lights (0.12 m), in front of the queue lines (0.7 m).
    public static let setBack: Float = 0.3

    /// The pieces along a platform `length` metres long, from its start:
    /// an opening (`door` true) at each door of the calling train
    /// (`formations`, the longest that fits, standing where `stands`
    /// says, as ``Map3DPlatformProps/doorCentres(length:formations:kind:stands:)``
    /// stands it), fixed panels between them and, decision 859, on along
    /// the rest of the platform, as the real ones run its whole length.
    /// Empty when no train fits.
    public static func pieces(length: Float, formations: [Map3DPlatformProps.Formation],
                              stands: Map3DPlatformProps.Stands = []) -> [(from: Float, to: Float, door: Bool)] {
        let calling = formations.filter { $0.doors > 0 }
        guard Map3DPlatformProps.markedTrain(length: length, formations: calling) != nil else { return [] }
        let doors = Map3DPlatformProps.doorCentres(length: length, formations: calling, kind: .metro, stands: stands)
        let start: Float = 0.2, end = length - 0.2
        guard end > start + opening else { return [] }
        var pieces: [(from: Float, to: Float, door: Bool)] = []
        var at = start
        for centre in doors {
            let from = max(start, centre - opening / 2), to = min(end, centre + opening / 2)
            guard to > at else { continue }
            // Decision 859: two doors nearer than an opening's width (a
            // train standing each way round at a line's end) share one
            // wider opening.
            if let last = pieces.last, last.door, from < at + 0.05 {
                pieces[pieces.count - 1].to = to
            } else {
                if from > at + 0.05 { pieces.append((at, from, false)) }
                pieces.append((max(at, from), to, true))
            }
            at = to
        }
        if end > at + 0.05 { pieces.append((at, end, false)) }
        return pieces
    }
}

// MARK: - Building

extension Map3DScene.Builder {
    /// Decision 847: how deep the header over full-height doors is, and
    /// the rail along a gate's top, metres.
    static let doorHeader: Float = 0.25
    static let gateRail: Float = 0.08

    /// Decision 847: the doors along a platform `doors`, its pieces (as
    /// ``Map3DScreenDoors/pieces(length:formations:stands:)`` cuts them) at
    /// `across` metres to the line's right of `path`, standing on `top`:
    /// glass between the steel frames of each opening, a header in the
    /// kit's canopy colour over them (a rail on a gate). Only the glass is
    /// lit after dark.
    static func addScreenDoors(_ mesh: inout Map3DMesh, path: Map3DStreetLife.Path, across: Float, top: Float,
                               pieces: [(from: Float, to: Float, door: Bool)], doors: Map3DScreenDoors.Doors) {
        guard !pieces.isEmpty else { return }
        func at(_ along: Float) -> (point: Map3DPoint, along: Map3DPoint, right: Map3DPoint) {
            let place = path.at(min(max(along, 0), path.length))
            return (place.point + place.right * across + Map3DPoint(0, top, 0), place.along, place.right)
        }
        let band = doors.full ? doorHeader : gateRail
        let glassTop = doors.height - band
        let up = Map3DPoint(0, 1, 0)
        // The glass, one face (the map draws both sides).
        let glassStart = mesh.vertices.count
        for piece in pieces {
            let a = at(piece.from).point, b = at(piece.to).point
            mesh.addQuad(a, b, b + up * glassTop, a + up * glassTop, color: StationKitBuilder.glass)
        }
        mesh.makeNightLit(from: glassStart)
        // The header or rail over it: its two faces a little proud of the
        // glass, and its top.
        let half: Float = doors.full ? 0.1 : 0.04
        for piece in pieces {
            let a = at(piece.from), b = at(piece.to)
            let low = up * glassTop, high = up * doors.height
            let aIn = a.point - a.right * half, bIn = b.point - b.right * half
            let aOut = a.point + a.right * half, bOut = b.point + b.right * half
            mesh.addQuad(aIn + low, bIn + low, bIn + high, aIn + high, color: Map3DColor.shaded(Map3DPalette.canopy, 0.86))
            mesh.addQuad(aOut + low, bOut + low, bOut + high, aOut + high, color: Map3DColor.shaded(Map3DPalette.canopy, 0.80))
            mesh.addQuad(aIn + high, aOut + high, bOut + high, bIn + high, color: Map3DPalette.canopy)
        }
        // The frames each side of each opening, up to the header, and
        // the seam where its two leaves meet, a strip each side of the
        // glass (6 cm off it, clear of its plane).
        for piece in pieces where piece.door {
            for end in [piece.from, piece.to] {
                let p = at(end)
                mesh.addBox(base: p.point, forward: p.along, length: 0.12, width: 0.18, height: doors.height, top: StationKitBuilder.steel,
                            side: StationKitBuilder.steel, capped: !doors.full)
            }
            let middle = at((piece.from + piece.to) / 2)
            for off: Float in [-0.06, 0.06] {
                let foot = middle.point + middle.right * off, half = middle.along * 0.025
                mesh.addQuad(foot - half, foot + half, foot + half + up * glassTop, foot - half + up * glassTop,
                             color: Map3DColor.shaded(StationKitBuilder.steel, 0.86))
            }
        }
    }
}
