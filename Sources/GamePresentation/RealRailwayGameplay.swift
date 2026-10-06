import Foundation
import GameCore

// Taiwan's real railway data put to use in play (2026-10-06): defaults the
// player starts from where their stations are real ones, and what the real
// station is. Every default goes into the world through the usual
// GameWorld commands (`setLineTargetHeadways`, the platform's length), so
// GameCore never sees a real railway and a save keeps nothing of it.
//
// A station of the world is a real one when its name is a real station's,
// in any language or system's spelling (``RealRailways/stationKey(_:)``),
// and, on a real-world map, it stands closer to it than the site's transfer
// distance (450 m; ``RealRailways/stations(named:near:)``).

extension GameSession {
    /// Where world point `point` is on the Earth; `nil` on a blank map.
    func realCoordinate(of point: PlanPoint) -> RealRailways.Coordinate? {
        guard let frame = RealWorldFrame(world: world) else { return nil }
        let coordinate = frame.coordinate(worldX: Double(point.x), worldY: Double(point.y))
        return RealRailways.Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// The real stations a station named `name` at `point` is.
    func realStations(named name: String, at point: PlanPoint?) -> [RealRailways.Station] {
        guard let railways else { return [] }
        return railways.stations(named: name, near: point.flatMap(realCoordinate(of:)))
    }

    /// The Chinese names the real data may know a station named `name` at
    /// `point` by: its own, then those of the real stations it is.
    func realNames(of name: String, at point: PlanPoint?) -> [String] {
        var names = [name]
        for station in realStations(named: name, at: point) where !names.contains(station.chinese) {
            names.append(station.chinese)
        }
        return names
    }

    /// The TRA station a station named `name` at `point` is: its name as
    /// `tra_station_class.json` or `tra_station_info.json` has it.
    func realTRAStationName(of name: String, at point: PlanPoint?) -> String? {
        guard let data = railways?.stationData else { return nil }
        let candidates: [String]
        if point != nil {
            // On a real-world map, only a TRA station that is there.
            candidates = realStations(named: name, at: point).filter { $0.system.id == "tra_sched" }.map(\.chinese)
        } else {
            candidates = realNames(of: name, at: nil)
        }
        return candidates.first { data.stationClass(forStation: $0) != nil || data.stationInfo(forStation: $0) != nil }
    }

    // MARK: - The station inspector

    /// What the real data knows of station `id`, one line each: its TRA
    /// code and grade, its address, its Taipei Metro codes, the other
    /// railways' codes for the same place, the routes to change to there
    /// (`station_transfers.json`, as the site's `transferRoutesAtStation`
    /// lists them) and the tracks a TRA train can wait on to be overtaken.
    /// Empty for a station that is no real one.
    public func realStationDetails(of id: StationID) -> [String] {
        guard let railways, let station = world.station(id: id) else { return [] }
        let point: PlanPoint? = RealWorldFrame(world: world) == nil ? nil : station.location
        var lines: [String] = []

        var traID: String?
        if let data = railways.stationData, let tra = realTRAStationName(of: station.name, at: point) {
            var parts: [String] = []
            if let info = data.stationInfo(forStation: tra) {
                traID = info.id
                parts.append(language.text("TRA \(info.id)", "台鐵 \(info.id)"))
            }
            if let grade = data.stationClass(forStation: tra) {
                parts.append(grade.name(in: language))
            }
            if !parts.isEmpty { lines.append(parts.joined(separator: " · ")) }
            if let info = data.stationInfo(forStation: tra), !info.address.isEmpty {
                lines.append(language.text("Address: \(info.address)", "地址：\(info.address)"))
            }
        }

        var codes: [String] = []
        if let data = railways.stationData {
            for name in realNames(of: station.name, at: point) {
                for code in data.trtcCodes(forStation: name) where !codes.contains(code) {
                    codes.append(code)
                }
            }
        }
        if !codes.isEmpty {
            lines.append(language.text("Taipei Metro \(codes.joined(separator: " / "))", "台北捷運 \(codes.joined(separator: " / "))"))
        }

        if let transfers = railways.transfers, let point, let coordinate = realCoordinate(of: point),
           let anchor = realNames(of: station.name, at: point).lazy.compactMap({ transfers.station(named: $0, near: coordinate) }).first {
            let members = [anchor] + transfers.partners(of: anchor)
            // Without the codes already listed above.
            let other = members.filter { member in
                !(member.system == "TRA" && member.stationId == traID) && !(member.system == "TRTC" && codes.contains(member.stationId))
            }
            if !other.isEmpty {
                let text = other.map { "\($0.system) \($0.stationId)" }.joined(separator: " · ")
                lines.append(language.text("Codes: \(text)", "站碼：\(text)"))
            }
            let routes = transfers.transferRoutes(at: anchor)
            if !routes.isEmpty {
                let text = routes.map(\.label).joined(separator: language.text(", ", "、"))
                lines.append(language.text("Transfers: \(text)", "可轉乘：\(text)"))
            }
        }

        if let data = railways.stationData, let tra = realTRAStationName(of: station.name, at: point),
           let overtake = data.overtakeStation(forStation: tra), !overtake.dirs.isEmpty {
            let text = overtake.waitingTracks.map { "\($0.direction) \($0.tracks)" }.joined(separator: language.text(", ", "、"))
            lines.append(language.text("Overtaking tracks: \(text)", "待避股道：\(text)"))
        }
        return lines
    }

    // MARK: - Platform length

    /// How many cars a platform of a station named `name` at `point` is
    /// long enough for by default: a TRA station's grade gives the median
    /// platform length of its tier (`tra_platforms.json` `estLenByTier`,
    /// tiers as `index.html` gives them: 特等 0, 一等 1, 二等 2, 三等 3, any
    /// other grade 4), in whole cars (``Train/carLength``, 16 m), within
    /// ``Train/minimumCars`` to ``Train/maximumCars``. `nil` for a station
    /// that is no graded TRA station.
    public func realPlatformCars(forStationNamed name: String, at point: PlanPoint?) -> Int? {
        guard let data = railways?.stationData,
              let tra = realTRAStationName(of: name, at: point),
              let grade = data.stationClass(forStation: tra),
              let metres = data.estimatedPlatformLength(for: grade) else { return nil }
        let cars = Int(metres * Double(WorldCoordinate.unitsPerMetre) / Double(Train.carLength))
        return min(max(cars, Train.minimumCars), Train.maximumCars)
    }

    /// Sets ``platformCars`` to the real default for the station the next
    /// platform serves (``realPlatformCars(forStationNamed:at:)``), unless
    /// the player changed it since the last default.
    func suggestPlatformCars() {
        let target: (name: String, point: PlanPoint?)?
        if let id = platformStationID, let station = world.station(id: id) {
            target = (station.name, station.location)
        } else if let stretch = networkPlatformStretch, let geometry = world.trackGeometry(of: stretch.edge) {
            target = (stationName, geometry.location(at: (stretch.start + stretch.end) / 2).position.plan)
        } else {
            target = nil
        }
        guard let target else { return }
        let point = RealWorldFrame(world: world) == nil ? nil : target.point
        guard let cars = realPlatformCars(forStationNamed: target.name, at: point) else { return }
        if platformCars == automaticPlatformCars {
            platformCars = cars
        }
        automaticPlatformCars = cars
    }

    // MARK: - Headways

    /// The real line a line calling at `stops` follows: the one, in the
    /// site's order of systems and lines, that has the most of the stops
    /// among its stations (two at least), with its system's file key.
    public func realLine(calling stops: [StationID]) -> (system: String, line: RealOperationLine)? {
        guard let railways, let operations = railways.operations else { return nil }
        let realMap = RealWorldFrame(world: world) != nil
        // Each stop's real stations, as (site system, name key).
        let identities: [Set<String>] = stops.map { id in
            guard let station = world.station(id: id) else { return [] }
            return Set(realStations(named: station.name, at: realMap ? station.location : nil).map {
                "\($0.system.id)|\(RealRailways.stationKey($0.chinese))"
            })
        }
        var best: (system: String, line: RealOperationLine, count: Int)?
        for system in operations.orderedSystems {
            guard let site = RealRailwayOperations.siteSystems[system.id] else { continue }
            for line in system.lines {
                let keys = Set(line.stations.map { "\(site)|\(RealRailways.stationKey($0.name))" })
                let count = identities.filter { !$0.isDisjoint(with: keys) }.count
                if count >= 2, count > (best?.count ?? 0) {
                    best = (system.id, line, count)
                }
            }
        }
        return best.map { ($0.system, $0.line) }
    }

    /// The target headways of a line following real line `line` of system
    /// `system`: its peak and off-peak headways (the site's
    /// `peakHeadwaySec` and `offpeakHeadwaySec`, read as its `headwayOf`
    /// reads them), to the nearest minute and at least
    /// ``ServiceLine/minimumHeadwayMinutes``. The real data has no headway
    /// for the game's low level, so it is left to the train count.
    public func realTargetHeadways(of line: RealOperationLine, inSystem system: String) -> TargetHeadways? {
        let operations = railways?.operations
        func minutes(peak: Bool) -> Int64? {
            guard let seconds = operations?.headway(forLine: line.id, inSystem: system, peak: peak) ?? (peak ? line.peakHeadwaySec : line.offpeakHeadwaySec),
                  seconds > 0 else { return nil }
            return min(max(Int64((seconds + 30) / 60), ServiceLine.minimumHeadwayMinutes), GameTime.minutesPerDay)
        }
        let targets = TargetHeadways(peak: minutes(peak: true), offPeak: minutes(peak: false))
        return targets == .none ? nil : targets
    }

    // MARK: - Track sections

    /// How far from a track's end a station may stand for the track to
    /// join it, as far as the real data goes: the site's transfer distance
    /// (450 m).
    static let realSectionReach: Int64 = 450 * WorldCoordinate.unitsPerMetre

    /// The real section between the stations of the world named `a` and
    /// `b` (at `pointA`, `pointB` on a real-world map): `tra_track_sections.json`
    /// read with the site's `traSectionKey`.
    func realTrackSection(between a: Station, and b: Station) -> TRATrackSection? {
        guard let data = railways?.stationData else { return nil }
        let realMap = RealWorldFrame(world: world) != nil
        guard let nameA = realTRAStationName(of: a.name, at: realMap ? a.location : nil),
              let nameB = realTRAStationName(of: b.name, at: realMap ? b.location : nil),
              nameA != nameB else { return nil }
        return data.trackSection(between: nameA, and: nameB)
    }

    /// "Real: double track (臺北–萬華)" for the real section between
    /// stations `a` and `b`; `nil` where there is none. The game builds
    /// each track as its own edge, so this is information for the player,
    /// not a setting: lay a second track beside the first for a double one.
    public func realTrackSectionText(between a: StationID, and b: StationID) -> String? {
        guard let stationA = world.station(id: a), let stationB = world.station(id: b),
              let section = realTrackSection(between: stationA, and: stationB) else { return nil }
        let tracks = switch section.tracks {
        case 1: language.text("single track", "單線")
        case 2: language.text("double track", "雙線")
        default: language.text("\(section.tracks) tracks", "\(section.tracks) 線")
        }
        let pair = section.pair.replacingOccurrences(of: "|", with: "–")
        return language.text("Real: \(tracks) (\(pair))", "實際：\(tracks)（\(pair)）")
    }

    /// The same for the stretch of track the network tool's ends would
    /// make, where each end lies within ``realSectionReach`` of a station.
    func realTrackSectionText(from start: NetworkAnchor, to end: NetworkAnchor) -> String? {
        guard railways?.stationData != nil else { return nil }
        func station(at anchor: NetworkAnchor) -> Station? {
            let point: PlanPoint? = switch anchor {
            case .node(let id): world.trackNode(id)?.position.plan
            case .point(let point): point
            }
            return point.flatMap { world.station(near: $0, within: Self.realSectionReach) }
        }
        guard let a = station(at: start), let b = station(at: end), a.id != b.id else { return nil }
        return realTrackSectionText(between: a.id, and: b.id)
    }
}
