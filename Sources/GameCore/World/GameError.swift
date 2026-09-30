/// A game rule violation reported by ``GameWorld`` and related types.
///
/// These are expected, recoverable outcomes of player actions, not programmer
/// errors. Cases carry structured data rather than user-facing text so the
/// presentation layer can localise them.
public enum GameError: Error, Hashable, Sendable {
    /// Map dimensions must lie in `1...GridMap.maximumSideLength`.
    case invalidMapSize(width: Int, height: Int)
    /// The position is not inside the map.
    case outOfBounds(GridPosition)
    /// Something is already built at the position.
    case tileOccupied(GridPosition)
    /// A track piece must connect in at least one direction, and only in the
    /// four known directions (no other bits set).
    case invalidTrackConnections
    /// Names must contain at least one non-whitespace character.
    case invalidName
    /// The balance cannot cover the cost.
    case insufficientFunds(required: Money, available: Money)
    /// Track removal was requested where there is no track (an empty tile or
    /// a station).
    case noTrackToRemove(GridPosition)
    /// The track at the position carries a placed train (it is the train's
    /// node, or an end of its link), so it cannot be removed.
    case trackInUse(GridPosition)
    /// No train with this ID exists.
    case unknownTrain(TrainID)
    /// The train is already on the track. Placement does not move a train;
    /// unplace it first.
    case trainAlreadyPlaced(TrainID)
    /// The train is not on the track, so there is nothing to unplace or
    /// reverse.
    case trainNotPlaced(TrainID)
    /// A train cannot be placed there: the position is not at a track tile
    /// or strictly inside a link between two joined track tiles (see
    /// ``TrainPosition``).
    case invalidTrainPosition
    /// A train's movement rate must not be negative.
    case invalidMovementRate
    /// A continuation must name, in order, nodes the train can enter from
    /// where it is: each joined to the one before (starting from the train's
    /// node, or the end of its link), with no immediate U-turn.
    case invalidContinuation
    /// Advancing that many ticks at the current speed would take game time
    /// past the largest minute the clock can hold. Nothing was advanced.
    case clockOverflow
    /// Every ID of the kind the command would allocate (stations, or
    /// trains) has been handed out: the world keeps the next ID in an `Int`,
    /// so the last one it can allocate is `Int.max - 1`. Nothing was built
    /// or bought, and nothing was charged.
    case idsExhausted
    /// A timetable's times go back in time: at every stop they must satisfy
    /// `0 <= arrival <= departure`, and each departure must be no later than
    /// the next stop's arrival.
    case invalidTimetable
    /// No station with this ID exists.
    case unknownStation(StationID)
    /// The train is running its timetable, and the service owns its
    /// continuation and timetable: it cannot be given a path, reversed,
    /// taken off the track, given another timetable or started again. Stop
    /// the service first.
    case trainServiceActive(TrainID)
    /// The train is not running a timetable service, so there is none to
    /// stop.
    case trainServiceNotActive(TrainID)
    /// The train has no timetable, so there is no service to start.
    case noTimetable(TrainID)
    /// A service starts from the first stop of the timetable, so the train
    /// must be stopped at that stop's station (see
    /// ``GameWorld/stationsStoppedAt(by:)``).
    case trainNotAtFirstStop(TrainID)
    /// No service line with this ID exists.
    case unknownLine(LineID)
    /// A line calls at two stations or more, and never at the same station
    /// twice in a row.
    case invalidLineStops
    /// A line's rate, the speed its journeys are planned at, is at least 1.
    case invalidLineRate
    /// A line's service window opens at a minute of the day (`0...1439`) and
    /// closes after it, no later than 06:00 the next morning (`1800`).
    case invalidServiceWindow
    /// A line cannot be set to run a negative number of trains.
    case invalidTrainsInService
    /// A service day's bands start at minute 0 of the day and strictly
    /// increase within the day.
    case invalidServiceDay
    /// A target headway is 2 to 1440 minutes (see ``TargetHeadways``).
    case invalidHeadway
    /// The train is assigned to a line, which runs its timetable and
    /// service: it cannot be given another timetable, have a service
    /// started or stopped, or be assigned again. Take it off the line
    /// first.
    case trainOnLine(TrainID)
    /// The train is not assigned to a line, so there is none to take it
    /// off.
    case trainNotOnLine(TrainID)
    /// A line's pattern calls at two of the line's stops or more, in the
    /// line's order (strictly increasing indices into its stops). Also
    /// thrown when new stops for a line would leave a pattern calling past
    /// its last stop.
    case invalidLinePattern
    /// The line has no pattern at this index.
    case unknownLinePattern(Int)
    /// A station grows only onto a tile beside one of its tiles.
    case invalidStationTile(GridPosition)
    /// A train has ``Train/minimumCars`` to ``Train/maximumCars`` cars.
    case invalidTrainLength
    /// No node of the track network has this ID (Stage S3). A grid tile is
    /// not a node of the network.
    case unknownTrackNode(TrackNodeID)
    /// No edge of the track network has this ID (Stage S3). A grid link is
    /// not an edge of the network.
    case unknownTrackEdge(TrackEdgeID)
    /// The track network cannot have that geometry (Stage S3): a point
    /// outside the map or, since Stage S4, outside
    /// ``RailwayNetwork/heightRange``, a node where one already stands, an
    /// edge from a node to itself, or a curve or profile that does not make
    /// an edge a train can run along (see
    /// ``TrackGeometry/init(from:to:curve:profile:)``).
    case invalidTrackGeometry
    /// Edges of the track network still end at the node, so it cannot be
    /// removed; remove them first (Stage S3).
    case trackNodeInUse(TrackNodeID)
    /// A placed train's head or body is on the edge, so it cannot be
    /// removed; unplace the train first (Stage S3).
    case trackEdgeInUse(TrackEdgeID)
    /// The edge would be steeper than ``TrackProfile/maximumGrade``
    /// somewhere (Stage S4).
    case trackTooSteep
    /// The edge's structure cannot carry track at the heights of its ends
    /// (Stage S4; see ``TrackStructure/allows(height:)``).
    case invalidTrackStructure
    /// The edge would meet this edge in plan, away from a node they share,
    /// with less than ``TrackStructure/clearance`` between them (Stage S4).
    /// A level crossing needs a node both edges end at.
    case trackConflict(TrackEdgeID)
    /// A station has a platform on the edge, so it cannot be removed;
    /// remove the platform first (Stage S4).
    case trackEdgeHasPlatform(TrackEdgeID)
    /// A platform on the track network must lie within its edge, be level,
    /// and not overlap another platform on the edge; one to remove must
    /// exist (Stage S4).
    case invalidPlatform
    /// Under traffic control (Phase 4.6 Stage T), this train holds track
    /// the command needs: it stands on it, or has reserved it for its
    /// route. The lowest numbered such train.
    case trackReserved(TrainID)
    /// Traffic control cannot be turned on while these two trains need the
    /// same track (Stage T): the first train, in ID order, whose track meets
    /// an earlier train's, and the earliest train it meets.
    case trainsShareTrack(TrainID, TrainID)
}
