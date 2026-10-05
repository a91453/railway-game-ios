/// A game rule violation reported by ``GameWorld`` and related types.
///
/// These are expected, recoverable outcomes of player actions, not programmer
/// errors. Cases carry structured data rather than user-facing text so the
/// presentation layer can localise them.
public enum GameError: Error, Hashable, Sendable {
    /// Each side of the world, in world units, must lie in
    /// `1...WorldBounds.maximumSide`.
    case invalidMapSize(width: Int64, height: Int64)
    /// The point is not inside the world's bounds.
    case outOfBounds(PlanPoint)
    /// Names must contain at least one non-whitespace character.
    case invalidName
    /// The balance cannot cover the cost.
    case insufficientFunds(required: Money, available: Money)
    /// No train with this ID exists.
    case unknownTrain(TrainID)
    /// The train is already on the track. Placement does not move a train;
    /// unplace it first.
    case trainAlreadyPlaced(TrainID)
    /// The train is not on the track, so there is nothing to unplace or
    /// reverse.
    case trainNotPlaced(TrainID)
    /// A train cannot be placed there: the position is not on an edge of the
    /// track network, or its body does not fit the track behind it (see
    /// ``TrainPosition``).
    case invalidTrainPosition
    /// A train's movement rate must not be negative.
    case invalidMovementRate
    /// A path must name, in order, edges the train can enter from where it
    /// is, each joining the one before at the node they share, and end within
    /// its last edge, not behind the train.
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
    /// The train is running its timetable, and the service owns its path
    /// and timetable: it cannot be given a path, reversed,
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
    /// A train's or line's performance has every rate and its top speed
    /// within what a running curve is built for, and a coast slower than
    /// its braking (see ``TrainPerformance/isValid``; Stage W2c).
    case invalidTrainPerformance
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
    /// A physical preference must name a directed leg of its service.
    case invalidLineRoutePreference
    /// The line has no pattern at this index.
    case unknownLinePattern(Int)
    /// A train has ``Train/minimumCars`` to ``Train/maximumCars`` cars.
    case invalidTrainLength
    /// No node of the track network has this ID (Stage S3).
    case unknownTrackNode(TrackNodeID)
    /// No edge of the track network has this ID (Stage S3).
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
    /// The edge would run closer than ``RailwayNetwork/trackSpacing`` beside
    /// this edge in plan at one level, at points farther apart along the
    /// track than ``RailwayNetwork/partingReach`` (or not joined by track at
    /// all): not one junction's tracks parting (Stage F2, ARCHITECTURE
    /// decision 52).
    case trackTooClose(TrackEdgeID)
    /// Removing the edge would leave these two edges, the lower numbered
    /// first, closer than ``RailwayNetwork/trackSpacing`` at points farther
    /// apart along the track than ``RailwayNetwork/partingReach``: the edge
    /// is the junction they part from (Stage F2, ARCHITECTURE decision 52).
    /// Remove one of them first.
    case tracksWouldBeTooClose(TrackEdgeID, TrackEdgeID)
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
    /// A station starts 0 to ``StationDemand/maximumDailyTrips`` trips a day
    /// (G1a).
    case invalidStationDemand
    /// Fare rules out of range, or distance steps that do not cover every
    /// distance once from 0 with only the last open-ended (G1c; see
    /// ``FareRules/isValid``).
    case invalidFareRules
}
