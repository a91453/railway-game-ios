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
    /// A line's dwell is ``ServiceDwell/minimum`` to
    /// ``ServiceLine/maximumDwellSeconds`` seconds (decision 207).
    case invalidLineDwell
    /// A line's dispatch pattern (decision 309) staggers its trains by
    /// ``DispatchPattern/staggerRange`` minutes; a ring and a line with
    /// runs space them evenly; and only a world with flexible dispatch
    /// sends them from both ends.
    case invalidDispatchPattern
    /// A line's service window opens at a minute of the day (`0...1439`) and
    /// closes after it, no later than 06:00 the next morning (`1800`).
    case invalidServiceWindow
    /// A line cannot be set to run fewer than 0 trains at a level, or more
    /// than ``TrainsInService/maximum``.
    case invalidTrainsInService
    /// A service day's bands start at minute 0 of the day and strictly
    /// increase within the day.
    case invalidServiceDay
    /// A target headway is 2 to 1440 minutes (see ``TargetHeadways``).
    case invalidHeadway
    /// The train is assigned to a line, which runs its timetable and
    /// service: it cannot be given another timetable, have a service
    /// started or stopped, or be assigned again, and its line's stops
    /// cannot be reversed. Take it off the line first.
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
    /// A line's runs (decision 133) each go from one of its stops to
    /// another with a time for every call, times that never go back, on
    /// some day of the week; and only a line that is not a ring, has no
    /// patterns and calls at no station twice has runs.
    case invalidLineRuns
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
    /// A turnout would stand on track steeper than
    /// ``TrackProfile/maximumTurnoutGrade`` (decision 233).
    case turnoutTooSteep
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
    /// A line's chosen physical path (decision 61) runs along the edge, so
    /// it cannot be split; clear that line's path first.
    case trackEdgeInLineRoute(LineID)
    /// A platform on the track network must lie within its edge, be level,
    /// and not overlap another platform on the edge; one to remove must
    /// exist (Stage S4).
    case invalidPlatform
    /// Under traffic control (Phase 4.6 Stage T), this train holds track
    /// the command needs: it stands on it, or has reserved it for its
    /// route. The lowest numbered such train. Also, with or without
    /// traffic control, a train running a service whose way to its next
    /// stop runs over the track a command would split or remove
    /// (decision 186).
    case trackReserved(TrainID)
    /// Traffic control cannot be turned on while these two trains need the
    /// same track (Stage T): the first train, in ID order, whose track meets
    /// an earlier train's, and the earliest train it meets.
    case trainsShareTrack(TrainID, TrainID)
    /// A station starts 0 to ``StationDemand/maximumDailyTrips`` trips a day
    /// (G1a).
    case invalidStationDemand
    /// A mode shift's cap is 0 to 1000 thousandths (decision 332).
    case invalidModeShift
    /// Fare rules out of range, or distance steps that do not cover every
    /// distance once from 0 with only the last open-ended (G1c; see
    /// ``FareRules/isValid``).
    case invalidFareRules
    /// A loan or repayment that is not a whole number of
    /// ``CompanyAccounts/loanStep``s above 0, that would take the loan past
    /// ``CompanyAccounts/maximumLoan``, or repay more than is owed
    /// (decision 67).
    case invalidLoanAmount
    /// Loans are a managed company's (decision 67): free play has none.
    case loanNeedsManagement
    /// Land with a cell outside the world, listed twice, with a negative
    /// count, more than ``Land/maximumPerCell`` residents or jobs, or no one
    /// living or working there (Phase 6a).
    case invalidLand
    /// A managed company's ridership comes from the land while demand from
    /// land is on (Phase 6b): a station's cannot be set.
    case stationDemandFromLand
    /// A transfer group needs two different stations (decision 81): a
    /// station cannot be linked with itself.
    case invalidTransferGroup
    /// A scenario needs a managed company, at least one goal, its days in
    /// order and its targets positive and in the world (decision 86).
    case invalidScenario
    /// The scenario's era has no trains of this type (decision 86), or,
    /// `nil`, no standard cars (decision 153).
    case trainTypeUnavailable(TrainType?)
    /// The train is on the track, on a line or running a service, so it
    /// cannot be sold (decision 180).
    case trainInService(TrainID)
    /// A building would share ground with this placed building (decision 92).
    case buildingOverlaps(PlacedBuildingID)
    /// A building would stand on, or too near, this edge's track (decision 92).
    case buildingOnTrack(TrackEdgeID)
    /// A building would stand on, or too near, this station (decision 92).
    case buildingOnStation(StationID)
    /// There is no building of the player's with this ID (decision 94).
    case unknownPlacedBuilding(PlacedBuildingID)
    /// A rectangle of cells to zone that reaches outside the world, or is
    /// more than ``Zoning/maximumSide`` cells a side (decision 98).
    case invalidZoneArea
    /// Water with a cell outside the world or its blocks read, listed twice,
    /// or where there is land; or set on a world whose land is read as it is
    /// needed (decision 105).
    case invalidTerrain
    /// A building would stand on water, or every cell to zone is water
    /// (decision 105): the first such cell, by row and then column.
    case onWater(row: Int, column: Int)
    /// A wharf or a marina stands on the shore (decision 111): part of it
    /// over water and part on land.
    case needsShore
    /// A building's look is not one its kind has (decision 361).
    case invalidBuildingLook
    /// A building would stand on a steep slope, or every cell to zone is
    /// water or steep and the first is steep (decision 115): that cell.
    case onSteepSlope(row: Int, column: Int)
    /// The ground's heights (decision 124) are for no block, or for a block
    /// outside the world, listed twice or already read; or the world is
    /// asked to have ground when it has it already or has track.
    case invalidGround
    /// Track or a node where a world with ground has not read the ground
    /// (decision 124).
    case groundNotLoaded
    /// Track over water on the surface or a viaduct, or a bridge or tunnel
    /// too close to the water (decision 124).
    case trackOverWater
    /// A viaduct or bridge more than 64 m above the ground (decision 124).
    case structureTooHigh
    /// A freight command in a world without freight (decision 155).
    case freightNotEnabled
    /// The station already has a freight facility (decision 155).
    case freightFacilityExists(StationID)
    /// The station has no freight facility (decision 155).
    case noFreightFacility(StationID)
    /// Building materials in a world without them (decision 156).
    case buildingMaterialsNotEnabled
    /// A command about buying the map in a world whose map is not bought
    /// (decision 160).
    case mapExpansionNotEnabled
    /// Buying the map is turned on once, as a game starts, and is on
    /// already (decision 160): turning it on again would forget the tiles
    /// bought while their land stays in the books.
    case mapExpansionEnabled
    /// The tile lies outside the world, or what the company built lies
    /// outside the tile it would own (decision 160).
    case invalidMapTile
    /// The riders each tile bought needs are below 1 or above
    /// ``MapExpansion/maximumRidersStep`` (decision 167).
    case invalidRidersStep
    /// The company owns the tile already (decision 160).
    case mapTileOwned
    /// The tile is not beside one the company owns (decision 160).
    case mapTileNotAdjacent
    /// The company's best day has not carried the riders it needs for one
    /// more tile (decision 160).
    case mapExpansionLocked(ridersNeeded: Int64)
    /// The ground lies in a tile of the map the company does not own
    /// (decision 160): it buys the tile first.
    case mapTileNotOwned(MapTile)
    /// A tourism command in a world without tourism (decision 174).
    case tourismNotEnabled
    /// There is no attraction with this ID (decision 174).
    case unknownAttraction(AttractionID)
    /// The attraction's souvenir shop is at its top level (decision 174).
    case attractionMaxedOut
    /// A city request command in a world without them (decision 183).
    case cityRequestsNotEnabled
    /// No offered or accepted city request has this ID (decision 183).
    case unknownCityRequest(Int)
    /// The company already has as many requests in hand as the city's
    /// trust allows (decision 183).
    case cityRequestLimitReached(limit: Int)
    /// A depot cannot be a line's stop, and a line's stop cannot become a
    /// depot (decision 209): the station a line calls at.
    case depotIsLineStop(StationID)
    /// The station is not a depot (decision 209).
    case notADepot(StationID)
    /// The depot is a line's depot, which must be changed first (decision
    /// 209): the line.
    case depotInUse(LineID)
    /// A line's depots name this depot twice (decision 221).
    case depotListedTwice(StationID)
    /// Making the station a depot would leave a line with no way along its
    /// stops, as no line's service runs over a depot's sidings (decision
    /// 209): the line.
    case depotBlocksLine(LineID)
    /// A depot has no shops (decision 222): the depot.
    case stationIsDepot(StationID)
    /// A station with shops cannot become a depot (decision 222): the
    /// station, whose shops are demolished first.
    case stationHasCommerce(StationID)
    /// The station's shops are at their top level, or already built
    /// (decision 222).
    case stationCommerceMaxedOut
    /// The station has no shops (decision 222).
    case noStationCommerce(StationID)
    /// The real line, or the line its trains run as, was bought already
    /// (decision 315).
    case lineAlreadyAcquired
    /// A purchase of a real line names no line, too many riders, or a line
    /// without a timetable or one that has run it (decision 315).
    case invalidAcquisition
    /// A road command in a world without roads (decision 400).
    case roadsNotEnabled
    /// The roads are turned on once, and are on already (decision 428).
    case roadsEnabled
    /// The base map's roads name a block outside the world or a cell
    /// outside the blocks read (decision 400).
    case invalidRoads
    /// The station's cell has a road already (decision 400): the station.
    case stationOnRoad(StationID)
    /// No road lies within ``RoadGrid/stationRoadMetres`` of the station
    /// (decision 400): the roads have not grown there yet.
    case roadTooFar
    /// No bus route has this number (decision 400, 10i-2).
    case unknownBusRoute(BusRouteID)
    /// A bus route with no stops or too many, legs not one a stop or too
    /// long, a headway or runs out of range, or too many buses.
    case invalidBusRoute
    /// A bus stop, or the station a drawn route ends at, is on no road.
    case busStopOffRoad
    /// No road joins this leg's ends (0 for the first stop to the
    /// next; the last stop's leg ends at the station).
    case busStopsNotConnected(leg: Int)
}
