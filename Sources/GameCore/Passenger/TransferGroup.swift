/// Identifies a transfer group. IDs are allocated by ``GameWorld`` from 1
/// and never handed out again while the world keeps them (see
/// ``GameWorld/linkTransfer(_:_:)``).
public struct TransferGroupID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: TransferGroupID, rhs: TransferGroupID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Stations passengers change trains between as if they were one complex,
/// however far apart (ARCHITECTURE decision 81): MapBuilder's interchange
/// (`handleCreateInterchange`, `interchanges`) and the `Ci/` metro game's
/// transfer group (`transferGroupId`), which links stations beyond a
/// passage. Without a group, passengers walk only to stations less than
/// ``PassengerTransferRules/maximumWalkMetres`` away; within one they walk
/// to any of its stations, at the tier of the distance (``PassengerTransferTier/virtual``
/// beyond a passage) and 5 km/h.
public struct TransferGroup: Hashable, Codable, Sendable {
    public let id: TransferGroupID
    /// The group's stations, at least two, in ascending ID order. A station
    /// is in one group at most.
    public internal(set) var stations: [StationID]
}

extension GameWorld {
    /// The transfer group station `id` is in, or `nil`.
    public func transferGroup(of id: StationID) -> TransferGroup? {
        transferGroups.first { $0.stations.contains(id) }
    }

    /// Whether stations `a` and `b` are two stations of one transfer group.
    func areLinkedForTransfer(_ a: StationID, _ b: StationID) -> Bool {
        a != b && transferGroups.contains { $0.stations.contains(a) && $0.stations.contains(b) }
    }

    /// Links stations `a` and `b` for transfers (decision 81, MapBuilder's
    /// `handleCreateInterchange`): neither in a group, a new group of the
    /// two with the next transfer group ID; one in a group, the other joins
    /// it; each in its own group, the two groups become one, keeping the
    /// larger's ID (`a`'s when they are as large) and dropping the other's;
    /// already together, nothing changes. Free. Returns the group they are
    /// in.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``
    ///   for `a`, then `b`, ``GameError/invalidTransferGroup`` when they are
    ///   the same station, or ``GameError/idsExhausted``.
    @discardableResult
    public mutating func linkTransfer(_ a: StationID, _ b: StationID) throws(GameError) -> TransferGroupID {
        for id in [a, b] where station(id: id) == nil {
            throw .unknownStation(id)
        }
        guard a != b else { throw .invalidTransferGroup }
        let first = transferGroups.firstIndex { $0.stations.contains(a) }
        let second = transferGroups.firstIndex { $0.stations.contains(b) }
        let linked: TransferGroupID
        switch (first, second) {
        case let (first?, second?) where first == second:
            return transferGroups[first].id
        case let (first?, second?):
            let keep = transferGroups[first].stations.count >= transferGroups[second].stations.count ? first : second
            let drop = keep == first ? second : first
            transferGroups[keep].stations = (transferGroups[keep].stations + transferGroups[drop].stations).sorted()
            linked = transferGroups[keep].id
            transferGroups.remove(at: drop)
        case let (group?, nil), let (nil, group?):
            transferGroups[group].stations = (transferGroups[group].stations + [transferGroups[group].stations.contains(a) ? b : a]).sorted()
            linked = transferGroups[group].id
        case (nil, nil):
            let (id, next) = try Self.allocateID(from: nextTransferGroupID)
            linked = TransferGroupID(rawValue: id)
            nextTransferGroupID = next
            transferGroups.append(TransferGroup(id: linked, stations: [a, b].sorted()))
        }
        passengerPlan = PassengerPlanCache()
        return linked
    }

    /// Takes station `id` out of its transfer group (decision 81, MapBuilder's
    /// `handleRemoveStationFromInterchange`): a group left with one station
    /// goes, and its ID is not handed out again. Nothing changes for a
    /// station in no group. Passengers whose journey walks between stations
    /// no longer linked leave when it can no longer be taken.
    ///
    /// - Throws: ``GameError/unknownStation(_:)``.
    public mutating func unlinkTransfer(_ id: StationID) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard let index = transferGroups.firstIndex(where: { $0.stations.contains(id) }) else { return }
        transferGroups[index].stations.removeAll { $0 == id }
        if transferGroups[index].stations.count < 2 {
            transferGroups.remove(at: index)
        }
        abandonUnservedPassengers()
    }

    /// Why the transfer groups break the world's rules, or `nil`: IDs
    /// ascending and below the next, at least two stations each, in
    /// ascending order, every one of them existing and in one group only.
    func transferGroupProblem() -> String? {
        guard Self.isStrictlyIncreasing(transferGroups.map(\.id.rawValue), below: nextTransferGroupID) else {
            return "Transfer group IDs must be unique, ascending and below nextTransferGroupID."
        }
        var grouped: Set<StationID> = []
        for group in transferGroups {
            guard group.stations.count >= 2, zip(group.stations, group.stations.dropFirst()).allSatisfy({ $0 < $1 }) else {
                return "Transfer group \(group.id.rawValue) needs two stations or more, in ascending order."
            }
            for id in group.stations {
                guard station(id: id) != nil else {
                    return "Transfer group \(group.id.rawValue) has station \(id.rawValue), which does not exist."
                }
                guard grouped.insert(id).inserted else {
                    return "Station \(id.rawValue) is in two transfer groups."
                }
            }
        }
        return nil
    }
}
