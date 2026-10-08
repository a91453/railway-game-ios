import GameCore

// Transfer groups (ARCHITECTURE decision 81): the station panel links the
// selected station with another for transfers, however far apart
// (MapBuilder's `handleCreateInterchange`), or takes it out of its group
// (`handleRemoveStationFromInterchange`). Each is one GameWorld command
// through `perform`, so Undo takes it back.

extension GameWorld {
    /// The stations of station `id`'s transfer group, by name, joined by
    /// " / " as the `Ci/` reference names a group
    /// (`_buildTransferGroupDisplayName`), in the group's (ID) order; `nil`
    /// for a station in no group.
    public func transferGroupText(of id: StationID) -> String? {
        transferGroup(of: id).map { group in
            group.stations.compactMap { station(id: $0)?.name }.joined(separator: " / ")
        }
    }

    /// The stations station `id` could be linked with for transfers: the
    /// ``transferCandidateLimit`` nearest not already in its group, nearest
    /// first, then by ID.
    public func transferCandidates(for id: StationID) -> [Station] {
        guard let origin = station(id: id) else { return [] }
        let grouped = Set(transferGroup(of: id)?.stations ?? [id])
        return stations.filter { !grouped.contains($0.id) && $0.id != id }
            .map { (station: $0, distance: Self.squaredDistance(origin.point, $0.point)) }
            .sorted { ($0.distance, $0.station.id) < ($1.distance, $1.station.id) }
            .prefix(Self.transferCandidateLimit)
            .map(\.station)
    }

    /// How far apart stations `a` and `b` stand, in world units, rounded
    /// to the nearest; `nil` if either does not exist.
    public func distanceUnits(between a: StationID, and b: StationID) -> Int64? {
        guard let from = station(id: a), let to = station(id: b) else { return nil }
        return Int64(Double(Self.squaredDistance(from.point, to.point)).squareRoot().rounded())
    }

    /// How many stations ``transferCandidates(for:)`` offers: a menu's worth
    /// on a real-world map of hundreds.
    public static let transferCandidateLimit = 20

    private static func squaredDistance(_ a: PlanPoint, _ b: PlanPoint) -> Int64 {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy
    }
}

extension GameSession {
    /// Links the selected station with station `other` for transfers
    /// through `GameWorld.linkTransfer(_:_:)` (decision 81): passengers
    /// walk between the stations of a group however far apart.
    public func linkSelectedStationForTransfer(with other: StationID) {
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station on the map first.", "請先在地圖上選擇車站。"))
            return
        }
        let otherName = world.station(id: other)?.name ?? "#\(other.rawValue)"
        perform { world throws(GameError) in
            try world.linkTransfer(station.id, other)
            let group = world.transferGroupText(of: station.id) ?? ""
            return language.text(
                "Passengers can change between \(station.name) and \(otherName): \(group).",
                "\(station.name) 與 \(otherName) 可以轉乘了：\(group)。"
            )
        }
    }

    /// Takes the selected station out of its transfer group through
    /// `GameWorld.unlinkTransfer(_:)`; a group left with one station goes.
    public func unlinkSelectedStationTransfer() {
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station on the map first.", "請先在地圖上選擇車站。"))
            return
        }
        guard world.transferGroup(of: station.id) != nil else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(station.name) is in no transfer group.", "\(station.name) 不在任何轉乘群組。"
            ))
            return
        }
        perform { world throws(GameError) in
            try world.unlinkTransfer(station.id)
            return language.text(
                "\(station.name) left its transfer group. Passengers who needed the walk leave.",
                "\(station.name) 已離開轉乘群組。需要這段步行的乘客會離開。"
            )
        }
    }
}
