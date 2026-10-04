// Station stops (Stage S5, ARCHITECTURE decision 31). A station's platforms
// are its TrackPlatforms, stretches of edges kept in the railway network.
// (Until Stage F3c a station on the grid also had the track tiles beside
// its tiles as platforms; they went with the grid, decision 51.)
//
// A train is stopped at a station when its journey ends at one of the
// station's platforms: its path is spent and its head is on the platform.
// The movement kernel never moves such a train by itself (see
// TrainMovement), so it stays stopped until a command gives it somewhere to
// go or takes it off the track, or its timetable service gives it a route
// when a departure comes. Being stopped is derived from the train's
// position and movement and the network, like being blocked; it is not
// stored.

extension GameWorld {
    /// The stations train `id` stands beside with its whole length (Stage
    /// S2): the stations it is stopped at (see ``stationsStoppedAt(by:)``)
    /// whose platform its whole body, from head to tail, lies on: on the
    /// head's edge, within the platform's stretch (see
    /// ``trackPlatformsAlongWholeTrain(_:)``). A train stopped with its head
    /// on a platform and its tail beyond it is stopped there, but not beside
    /// it with its whole length. The same as ``stationsStoppedAt(by:)`` for a
    /// train of one car.
    public func stationsBesideWholeTrain(_ id: TrainID) -> [StationID] {
        guard train(id: id) != nil else { return [] }
        let alongside = trackPlatformsAlongWholeTrain(id)
        return stationsStoppedAt(by: id).filter { station in alongside.contains { $0.station == station } }
    }

    /// The stations the train `id` is stopped at, in ascending ID order.
    ///
    /// A train is stopped at a station when its path is spent (no edges
    /// left, its head where the path ends; see ``TrainMovement/end``) and its
    /// head is on one of the station's platforms on the edge it is on: its
    /// distance from the edge's `from` node is within the platform's
    /// `start...end`, ends included. Its journey ends there, and it stays
    /// until a command changes that, or its timetable service gives it a
    /// route when a departure comes (see ``advance(ticks:)``):
    ///
    /// - A train passing a platform, or standing on one with its path not
    ///   spent (it would run on to the end of its edge), is not stopped
    ///   there; nor is one waiting there for an edge that was removed.
    /// - A train at a node is on the edge it arrived along, so a platform
    ///   that starts at that node on the next edge does not count.
    /// - Platforms of two stations that meet where the head is are both
    ///   stopped at.
    ///
    /// Empty for an unknown or unplaced train and for a train that is not
    /// stopped at any station. Scans the platform list once.
    public func stationsStoppedAt(by id: TrainID) -> [StationID] {
        guard let train = train(id: id), let (edge, chainage) = standingPoint(of: train) else { return [] }
        let stations = network.platforms(on: edge).filter { $0.start <= chainage && chainage <= $0.end }.map(\.station)
        return Set(stations).sorted()
    }

    /// Whether `train` is stopped at the station `id`: whether
    /// ``stationsStoppedAt(by:)`` would list `id` for it. Takes the train by
    /// value, so services can ask about the train they are updating.
    func isStopped(_ train: Train, at id: StationID) -> Bool {
        guard let (edge, chainage) = standingPoint(of: train) else { return false }
        return network.platforms(on: edge).contains { $0.station == id && $0.start <= chainage && chainage <= $0.end }
    }

    /// Where a train stands once its path is spent (Stage S5): its edge and
    /// its head's distance along it from the edge's `from` node. `nil` for an
    /// unplaced train, and for one with edges left or short of where its
    /// path ends.
    func standingPoint(of train: Train) -> (edge: TrackEdgeID, chainage: Int64)? {
        guard case .onEdge(let traversal, let offset)? = train.position, train.movement.remainingEdges.isEmpty,
              let edge = network.edge(traversal.edge), offset == (train.movement.end ?? edge.length)
        else { return nil }
        return (traversal.edge, traversal.direction == .forward ? offset : edge.length - offset)
    }
}
