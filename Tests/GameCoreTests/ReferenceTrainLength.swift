import GameCore

/// Decision 27, written a second time for ``ReferenceWorld``: train length
/// and the whole train beside a station. The body behind the head on the
/// track network is in `ReferenceNetwork.swift`. (Until Stage F3c this also
/// held the body on the grid, the pull along a station's platform tiles and
/// platform tracks; they went with the grid, ARCHITECTURE decision 51.)
extension ReferenceWorld {
    static let carUnits: Int64 = 1024

    /// One car to a tile's width: from each car's centre to the next.
    static func length(_ train: Train) -> Int64 {
        Int64(train.cars - 1) * carUnits
    }

    static func length(cars: Int) -> Int64 {
        Int64(cars - 1) * carUnits
    }

    /// Decision 31: stopped there, the whole body along one platform of
    /// the station.
    func stationsBesideWholeTrain(_ id: TrainID) -> [StationID] {
        let alongside = trackPlatformsAlong(id).map(\.station)
        return stationsStoppedAt(by: id).filter(alongside.contains)
    }
}
