import GameCore

/// Decision 26, written a second time for ``ReferenceWorld``: what trains
/// occupy, the conflicts between them and parallel tracks, on the track
/// network (Stage F3c removed the grid's tiles, links and sections,
/// ARCHITECTURE decision 51). Written from the rules, not from GameCore.
extension ReferenceWorld {
    func occupiedResources(of id: TrainID) -> [TrackResource] {
        guard let train = trains.first(where: { $0.id == id.rawValue }) else { return [] }
        return occupied(train)
    }

    func occupied(_ train: Train) -> [TrackResource] {
        guard train.position != nil else { return [] }
        return networkResources(of: train)
    }

    func occupancyConflicts() -> [TrackConflict] {
        let occupied = trains.flatMap { train in occupiedResources(of: TrainID(rawValue: train.id)).map { ($0, train.id) } }
        let resources = Set(occupied.map(\.0)).sorted()
        return resources.compactMap { resource in
            let ids = occupied.filter { $0.0 == resource }.map(\.1).sorted()
            return ids.count > 1 ? TrackConflict(resource: resource, trains: ids.map(TrainID.init(rawValue:))) : nil
        }
    }

    /// The track network's separate tracks (see
    /// `ReferenceNetworkSections.swift`).
    func parallelTracks(between a: StationID, and b: StationID) -> Int {
        networkParallelTracks(between: a, and: b)
    }
}
