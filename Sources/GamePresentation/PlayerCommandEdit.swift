import GameCore

extension PlayerCommand {
    /// An edit from a panel or a tool other than the network tool's track
    /// (ARCHITECTURE decision 193, later): the `GameWorld` command it is,
    /// with the values the panel worked out for it, so the command log keeps
    /// it and a replay makes it again. Each does what its function's
    /// closure did before; ``GameSession/apply(_:to:)`` runs it.
    ///
    /// Written with GameCore's own coding of its values (a train's
    /// performance, a timetable, fare rules…): a refused edit's value that
    /// a world cannot hold does not read back, and the replay stops there
    /// (``CommandLog/Entry``).
    public enum Edit: Hashable, Sendable, Codable {
        // MARK: The company
        case setTrafficControl(Bool)
        case setDisruptions(Disruptions?)
        case setPassengerRoutingMode(PassengerRoutingMode)
        case setEconomyMode(EconomyMode)
        case setFareRules(FareRules)
        case borrow(Money)
        case repayLoan(Money)
        case setServiceDay(ServiceDay)

        // MARK: Trains
        case purchaseTrain(name: String)
        case sellTrain(TrainID)
        case setTrainCars(TrainID, cars: Int)
        /// The car type, and, for a train still running as standard, the
        /// type's own way of running (decision 168).
        case setTrainType(TrainID, TrainType?)
        case setTrainRate(TrainID, rate: Int64)
        /// ``GameWorld/useTrainPerformanceForMovement(_:)``.
        case resumeTrain(TrainID)
        /// A path to a berth, then running at its performance.
        case sendTrain(TrainID, along: [Step], stoppingAt: Int64?)
        case reverseTrain(TrainID)
        case unplaceTrain(TrainID)
        /// The performance, and running at it if the train is moving.
        case setTrainPerformance(TrainID, TrainPerformance)
        case setTrainTimetable(TrainID, [ScheduledStop], period: Int64?)
        case startTrainService(TrainID)
        case stopTrainService(TrainID)
        /// To a service of a line, setting it to run its trains when it
        /// runs none (``GameSession/assignSelectedTrainToSelectedLine(pattern:)``).
        case assignTrain(TrainID, LineID, pattern: Int?)
        case unassignTrain(TrainID)
        /// On a platform of a station, the way nearer `heading`
        /// (``GameSession/placeSelectedTrain()``).
        case placeTrain(TrainID, at: StationID, heading: CompassHeading)
        /// Trains bought, placed and assigned to run a line every `headway`
        /// minutes (decision 101), named in `language`.
        case staffLine(LineID, headway: Int64, type: TrainType?, cars: Int, language: DisplayLanguage)
        /// A line's waiting trains re-formed (decision 180); what is left as
        /// it was is said in `language`.
        case reformLine(LineID, type: TrainType?, cars: Int, language: DisplayLanguage)

        // MARK: Stations
        case renameStation(StationID, name: String)
        case removeStation(StationID)
        case setStationDemand(StationID, StationDemand?)
        /// A station's demand given to every station of its lines.
        case applyStationDemand(StationDemand, to: [StationID])
        case setStationOperationMode(StationID, StationOperationMode)
        case linkTransfer(StationID, StationID)
        case unlinkTransfer(StationID)
        case buildFreightYard(StationID)
        case removeFreightYard(StationID)
        case setFreightProduct(StationID, CargoKind)

        // MARK: Lines
        /// A line, and the real line's target headways where it is one.
        case createLine(name: String, stops: [StationID], targets: TargetHeadways?)
        case duplicateLine(LineID, name: String)
        case removeLine(LineID)
        case renameLine(LineID, name: String)
        case setLineColor(LineID, LineColor?)
        case setLineStops(LineID, [StationID])
        case reverseLineStops(LineID)
        case setLineRoutes(LineID, [LineRoutePreference], pattern: Int?)
        case setLineWindow(LineID, ServiceWindow)
        case setLineRing(LineID, Bool)
        case setLineTrains(LineID, TrainsInService, pattern: Int?)
        case setLineTargets(LineID, TargetHeadways, pattern: Int?)
        case addLinePattern(LineID, calls: [Int])
        case removeLinePattern(LineID, index: Int)
        case setLinePerformance(LineID, TrainPerformance)
        case setLineFreight(LineID, Bool)

        // MARK: Land and the city
        /// The site's land read in (decision 95), then the building.
        case placeBuilding(PlacedBuildingKind, at: PlanPoint)
        case sellBuilding(PlacedBuildingID)
        case demolishBuilding(PlacedBuildingID)
        /// A zone, or `nil` to clear.
        case setZone(ZoneChoice, rows: ClosedRange<Int>, columns: ClosedRange<Int>)
        case buyMapTile(MapTile)
        case acceptRequest(Int)
        case declineRequest(Int)
        case investInSouvenirShop(AttractionID)

        /// A step of a train's path: an edge and the way along it.
        public struct Step: Hashable, Sendable, Codable {
            public let edge: Int
            public let forward: Bool

            public init(_ traversal: TrackTraversal) {
                edge = traversal.edge.number
                forward = traversal.direction == .forward
            }

            var traversal: TrackTraversal {
                TrackTraversal(edge: .edge(edge), direction: forward ? .forward : .backward)
            }
        }

        /// A zone, or none, written by its raw value.
        public struct ZoneChoice: Hashable, Sendable, Codable {
            public let zone: Zone?

            public init(_ zone: Zone?) {
                self.zone = zone
            }

            public init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() {
                    zone = nil
                } else {
                    let raw = try container.decode(String.self)
                    guard let zone = Zone(rawValue: raw) else {
                        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown zone \(raw).")
                    }
                    self.zone = zone
                }
            }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(zone?.rawValue)
            }
        }

        /// The name the log gives it: its case.
        public var name: String {
            String(String(describing: self).prefix { $0 != "(" })
        }
    }
}

extension GameSession {
    /// Runs `edit` on `world`, as its function's closure did: all of it or,
    /// throwing, none.
    func apply(_ edit: PlayerCommand.Edit, to world: inout GameWorld) throws(GameError) -> PlayerCommand.Outcome {
        var outcome = PlayerCommand.Outcome()
        switch edit {
        case .setTrafficControl(let enabled): try world.setTrafficControl(enabled)
        case .setDisruptions(let disruptions): world.setDisruptions(disruptions)
        case .setPassengerRoutingMode(let mode): world.setPassengerRoutingMode(mode)
        case .setEconomyMode(let mode): world.setEconomyMode(mode)
        case .setFareRules(let rules): try world.setFareRules(rules)
        case .borrow(let amount): try world.borrow(amount)
        case .repayLoan(let amount): try world.repayLoan(amount)
        case .setServiceDay(let day): try world.setServiceDay(day)

        case .purchaseTrain(let name): outcome.train = try world.purchaseTrain(named: name)
        case .sellTrain(let id): try world.sellTrain(id)
        case .setTrainCars(let id, let cars): try world.setTrainCars(id, to: cars)
        case .setTrainType(let id, let type):
            guard let train = world.train(id: id) else { throw .unknownTrain(id) }
            try world.setTrainType(id, to: type)
            if let performance = type?.performance, train.performance == .standard {
                try world.setTrainPerformance(id, to: performance)
            }
            if let line = world.assignedLine(of: id) {
                outcome.highSpeed = try world.planAtHighSpeedWhenRunByHighSpeedSets(line)
            }
        case .setTrainRate(let id, let rate): try world.setTrainMovementRate(id, to: rate)
        case .resumeTrain(let id): try world.useTrainPerformanceForMovement(id)
        case .sendTrain(let id, let steps, let end):
            try world.setTrainContinuation(id, along: steps.map(\.traversal), stoppingAt: end)
            try world.useTrainPerformanceForMovement(id)
        case .reverseTrain(let id): try world.reverseTrain(id)
        case .unplaceTrain(let id): try world.unplaceTrain(id)
        case .setTrainPerformance(let id, let performance):
            guard let train = world.train(id: id) else { throw .unknownTrain(id) }
            try world.setTrainPerformance(id, to: performance)
            if train.position != nil, train.movement.rate > 0 { try world.useTrainPerformanceForMovement(id) }
        case .setTrainTimetable(let id, let stops, let period): try world.setTrainTimetable(id, to: stops, repeatingEvery: period)
        case .startTrainService(let id):
            try world.startTrainService(id)
            try world.useTrainPerformanceForMovement(id)
        case .stopTrainService(let id): try world.stopTrainService(id)
        case .assignTrain(let id, let lineID, let pattern):
            guard let train = world.train(id: id) else { throw .unknownTrain(id) }
            try world.assignTrain(id, to: lineID, pattern: pattern)
            if train.position != nil { try world.useTrainPerformanceForMovement(id) }
            // Decision 168: a line that runs high-speed sets and nothing else
            // is a high-speed line, without a second step.
            outcome.highSpeed = try world.planAtHighSpeedWhenRunByHighSpeedSets(lineID)
            if let assigned = world.line(id: lineID) {
                let service = pattern.map { $0 + 1 } ?? 0
                let counts = service == 0 ? assigned.trainsInService : assigned.patterns[service - 1].trainsInService
                let targets = service == 0 ? assigned.targetHeadways : assigned.patterns[service - 1].targetHeadways
                if counts == .none, targets == TargetHeadways() {
                    let trains = (service == 0 ? assigned.trains : assigned.patterns[service - 1].trains).count
                    let started = assigned.isRing ? max(2, trains + trains % 2) : max(1, trains)
                    try world.setLineTrainsInService(lineID, to: TrainsInService(peak: started, offPeak: started, low: started), pattern: pattern)
                    outcome.number = started
                }
            }
        case .unassignTrain(let id): try world.unassignTrain(id)
        case .placeTrain(let id, let station, let heading):
            outcome.placed = try Self.place(id, atPlatformOf: station, heading: heading, in: &world)
        case .staffLine(let id, let headway, let type, let cars, let language):
            (outcome.held, outcome.unfit) = try Self.staff(id, headway: headway, type: type, cars: cars, in: &world, language: language)
        case .reformLine(let id, let type, let cars, let language):
            (outcome.number, outcome.left) = try Self.reform(id, type: type, cars: cars, in: &world, language: language)

        case .renameStation(let id, let name): try world.renameStation(id, to: name)
        case .removeStation(let id): try world.removeStation(id)
        case .setStationDemand(let id, let demand): try world.setStationDemand(id, to: demand)
        case .applyStationDemand(let demand, let targets):
            for target in targets {
                try world.setStationDemand(target, to: Self.demand(demand, for: target, in: world))
            }
        case .setStationOperationMode(let id, let mode): try world.setStationOperationMode(id, to: mode)
        case .linkTransfer(let a, let b): _ = try world.linkTransfer(a, b)
        case .unlinkTransfer(let id): try world.unlinkTransfer(id)
        case .buildFreightYard(let id): try world.buildFreightFacility(at: id)
        case .removeFreightYard(let id): try world.removeFreightFacility(at: id)
        case .setFreightProduct(let id, let kind): try world.setFreightProduct(at: id, to: kind)

        case .createLine(let name, let stops, let targets):
            let line = try world.createLine(named: name, stops: stops)
            if let targets { try world.setLineTargetHeadways(line.id, to: targets, pattern: nil) }
            outcome.line = line
        case .duplicateLine(let id, let name): outcome.line = try world.duplicateLine(id, named: name)
        case .removeLine(let id): try world.removeLine(id)
        case .renameLine(let id, let name): try world.renameLine(id, to: name)
        case .setLineColor(let id, let color): try world.setLineColor(id, to: color)
        case .setLineStops(let id, let stops): try world.setLineStops(id, to: stops)
        case .reverseLineStops(let id): try world.reverseLineStops(id)
        case .setLineRoutes(let id, let routes, let pattern): try world.setLineRoutePreferences(id, to: routes, pattern: pattern)
        case .setLineWindow(let id, let window): try world.setLineServiceWindow(id, to: window)
        case .setLineRing(let id, let ring): try world.setLineRing(id, to: ring)
        case .setLineTrains(let id, let trains, let pattern): try world.setLineTrainsInService(id, to: trains, pattern: pattern)
        case .setLineTargets(let id, let targets, let pattern): try world.setLineTargetHeadways(id, to: targets, pattern: pattern)
        case .addLinePattern(let id, let calls): outcome.number = try world.addLinePattern(id, calling: calls)
        case .removeLinePattern(let id, let index): try world.removeLinePattern(id, at: index)
        case .setLinePerformance(let id, let performance): try world.setLinePerformance(id, to: performance)
        case .setLineFreight(let id, let freight): try world.setLineFreight(id, to: freight)

        case .placeBuilding(let kind, let point):
            // The site's land, read when it was picked, may have gone with an
            // undo since: read it again, as part of the edit (decision 95).
            Self.readLand(within: Self.buildingLandReach, of: [point], in: &world, population: population, places: places, water: water, coverage: coverage)
            outcome.number = world.placedBuildingQuote(kind, at: point)?.cleared.count ?? 0
            outcome.building = try world.placeBuilding(kind, at: point)
        case .sellBuilding(let id): outcome.sale = try world.sellPlacedBuilding(id)
        case .demolishBuilding(let id): try world.removePlacedBuilding(id)
        case .setZone(let choice, let rows, let columns): outcome.number = try world.setZone(choice.zone, rows: rows, columns: columns)
        case .buyMapTile(let tile): try world.buyMapTile(tile)
        case .acceptRequest(let id): try world.acceptRequest(id)
        case .declineRequest(let id): try world.declineRequest(id)
        case .investInSouvenirShop(let id): try world.investInSouvenirShop(of: id)
        }
        return outcome
    }
}
