import Foundation
import GameCore
import Observation

/// Owns the app's single authoritative ``GameWorld`` for as long as the app
/// runs, and applies every gameplay change to it through `GameWorld` commands.
///
/// SwiftUI observes the session rather than GameCore: `GameWorld` stays a
/// plain `Sendable` value type, and this class is the one place that holds it.
/// Views read ``world`` and call the session's methods; they never keep their
/// own copy of game state.
///
/// Besides the world, the session keeps only transient UI state: the selected
/// point and station, the active tool, the drafts of the network tool, the draft station name,
/// the selected train, the heading for placing it, the selected line, the
/// stops picked for a new line, the copied station demand, the tutorial on
/// screen, and the last action's message, written in ``language``. Anything shown about the game,
/// including where each train is and where it is going, is derived from
/// ``world`` on demand.
///
/// The session also hosts the game loop: it measures real time, turns it into
/// whole ticks with a ``TickAccumulator`` and calls `GameWorld.advance(ticks:)`.
/// Wall-clock time never reaches GameCore.
///
/// Main-actor isolated because SwiftUI and the game loop run on the main
/// actor, so no locks or `@unchecked Sendable` are needed. Only working out
/// a tick runs elsewhere, on a copy of the world, which the session takes as
/// its world only if no command changed it meanwhile (decision 143).
@MainActor
@Observable
public final class GameSession {
    /// The authoritative game state. Only the session mutates it.
    public private(set) var world: GameWorld {
        didSet {
            worldRevision &+= 1
            if !isApplyingTick { commandRevision &+= 1 }
            // Decision 305: a paused game has no tick to look again after
            // a command (decision 330, later: off the main actor).
            if !isApplyingTick, world.clock.isPaused { lookAgainForNightSkip() }
            // Decision 193: a change no recorded path made is logged as one.
            if !isLogging { log(.unrecorded("world")) }
            refreshScreenFacts()
        }
    }
    /// Decision 367: what the screen's frame shows of the world, changed
    /// only when it changes (``ScreenFacts``), not at every tick.
    public internal(set) var screenFacts = ScreenFacts()
    /// What reached ``world`` since this session began (decision 193).
    @ObservationIgnored public private(set) var commandLog: CommandLog
    /// Whether a path that logs its own change is changing ``world``.
    @ObservationIgnored private var isLogging = false
    /// The transfer points last worked out (decision 298) and what from.
    @ObservationIgnored var transferMemo: TransferMemo?
    /// Counts the changes to ``world``, so what is worked out from it (the
    /// track preview, ``networkPreview``) is kept until it changes.
    @ObservationIgnored private(set) var worldRevision = 0
    /// Counts the changes to ``world`` other than game time moving on (a
    /// command, an undo or redo, a setting), so what only those change
    /// (the lines along the track, ``trackInspection(of:)``) is worked out
    /// once for them, not at every tick.
    @ObservationIgnored private(set) var commandRevision = 0
    /// The losing line the station master names, kept between commands and
    /// days (decision 194, later; ``worstLosingLine``).
    @ObservationIgnored let lineLossLeaderMemo = LineLossLeaderMemo()
    /// Decision 330: the station master's advice the game loop's tick
    /// worked out, for the world at ``worldRevision`` `revision`.
    @ObservationIgnored var workedAdvice: (revision: Int, advice: WorkedAdvice)?

    /// ``GameWorld/worstLosingLine()``, worked out again only after a
    /// command or once a day has settled (decision 194, later): the station
    /// master asks every hour of game time.
    public var worstLosingLine: LineLossLeader? {
        lineLossLeaderMemo.leader(of: self)
    }

    /// How many times ``worstLosingLine`` was worked out (for the tests).
    var worstLosingLineWorkedOut: Int { lineLossLeaderMemo.workedOut }
    /// Whether ``finish(_:)`` is putting a step of game time in place.
    @ObservationIgnored private var isApplyingTick = false
    /// The bubbles ``situationAlerts`` last worked out, and for what.
    @ObservationIgnored var situationAlertsMemo: SituationAlertsMemo?
    /// Why lines hold their trains, as ``trainPathStatusText(of:)`` last
    /// worked it out, and for what.
    @ObservationIgnored var lineDispatchHoldMemo: LineDispatchHoldMemo?
    /// How many times ``lineDispatchHoldText(of:)`` was worked out (for
    /// the tests).
    @ObservationIgnored var lineDispatchHoldsWorkedOut = 0
    /// The line map ``trackInspection(of:)`` last built, and for which
    /// ``commandRevision``.
    @ObservationIgnored var inspectionLineMap: (revision: Int, map: LineMap)?
    /// The leg of a line the map shows (decision 201; ``routePreview``).
    public internal(set) var routePreviewRequest: RoutePreview.Request?
    /// The preview last worked out, and for which request and
    /// ``commandRevision``.
    @ObservationIgnored var routePreviewMemo: (revision: Int, request: RoutePreview.Request, preview: RoutePreview?)?
    /// The one-time card about track numbers and routes waiting to be
    /// shown (decision 201, later; ``RouteHint``).
    public internal(set) var routeHint: RouteHint.Trigger?
    /// The legs on two tracks or more when ``watchRouteHint()`` last looked.
    @ObservationIgnored var routeHintLegs: Set<RouteHint.Leg>?
    /// The lines a passing loop just built lies on, offered its signal
    /// station as a stop (decision 204, later; ``PassingLoopOffer``).
    public internal(set) var passingLoopOffer: PassingLoopOffer?
    /// The line whose train waits on single track, for the one-time card
    /// about passing loops (``PassingLoopHint``).
    public internal(set) var passingLoopHint: LineID?
    /// The track preview of the picked ends, kept for the draft and world it
    /// was worked out for (see ``networkPreview``).
    @ObservationIgnored var networkPreviewMemo: NetworkPreviewMemo?
    /// The passing loop at the picked place, kept as the track preview is.
    @ObservationIgnored var passingLoopMemo: PassingLoopMemo?
    /// Decision 264: what opening the drafted line costs, worked out once
    /// for each draft and world.
    @ObservationIgnored var lineOpeningMemo: LineOpeningMemo?
    /// The draft's one line (``lineDraftSummary``), kept likewise.
    @ObservationIgnored var lineDraftSummaryMemo: LineDraftSummaryMemo?
    /// Decision 303: what the new line's confirmation card shows, kept
    /// likewise.
    @ObservationIgnored var lineConfirmationMemo: LineConfirmationMemo?
    /// CTM study M2: the next steps (``nextSteps``), kept likewise, and
    /// those already answered with the check (``newlyMetNextSteps()``).
    @ObservationIgnored var nextStepsMemo: NextStepsMemo?
    @ObservationIgnored var nextStepsCelebrated: Set<NextStep>?
    /// The coverage the next steps last counted (``catchmentCoverage``),
    /// and how many times it was counted (for the tests).
    @ObservationIgnored var coverageMemo: CoverageMemo?
    @ObservationIgnored var catchmentCoverageCounted = 0
    /// Decision 264: the selected line's shortfall of places to pass.
    @ObservationIgnored var passingShortfallMemo: PassingShortfallMemo?
    /// The depot's sidings at the picked end, kept likewise.
    @ObservationIgnored var depotYardMemo: DepotYardMemo?
    /// The levelling of the platform's stretch, kept likewise (see
    /// ``networkPlatformLevelling``).
    @ObservationIgnored var platformLevellingMemo: PlatformLevellingMemo?
    /// The tutorial's staffing plan of a line, kept for the world it was
    /// worked out for (see ``tutorialStaffingPlan(_:)``).
    @ObservationIgnored var tutorialStaffingMemo: (revision: Int, line: LineID, plan: LineStaffingPlan?)?
    /// The platform track menu's choices with their costs (each a dry run
    /// on a copy of the world), kept for the platform and the
    /// ``commandRevision`` they were worked out for.
    @ObservationIgnored var platformTrackMenuMemo: [TrackPlatform: (revision: Int, choices: [MenuChoice<PlatformTrackPlacement>])] = [:]
    /// What traffic control shows (``trafficOverlay``,
    /// ``routeWaitText(of:)``), kept for the ``worldRevision`` it was read
    /// for; the game loop reads it off the main actor with each tick.
    @ObservationIgnored var trafficMemo: (revision: Int, reading: TrafficReading)?

    /// The language of the session's messages and suggested names, and of
    /// the text the app derives from the world (Stage L1). Set once: iOS
    /// restarts an app whose language changes.
    public let language: DisplayLanguage

    /// Where the selection is: the point of the player's last tap on the
    /// map, or where the station they picked stands, exactly as it is (Stage
    /// F3d: never rounded to anything coarser). Always in the world's
    /// bounds when set.
    public private(set) var selectedPoint: PlanPoint?

    /// The station the player last picked (Stage F1): an ID only, never a
    /// copy of the station. Read the selected station through
    /// ``selectedStation``. A station is picked by where it stands
    /// (``tapMap(at:reach:)``) or by name (``selectStation(_:)``).
    public private(set) var selectedStationID: StationID? {
        didSet { refreshScreenFacts() }
    }

    /// What the action button does.
    public private(set) var tool: ConstructionTool = .select

    /// What the building tool places where the player taps (decision 92).
    public var buildingKind: PlacedBuildingKind = .house
    /// Which look the building tool puts up (decision 361), kept for each
    /// kind the player has picked one for; the first otherwise.
    public var buildingLooks: [PlacedBuildingKind: Int] = [:]
    /// Whether a tap with the building tool builds, demolishes (decision
    /// 94), sells (decision 130) or zones (decision 98).
    public var buildingMode: BuildingToolMode = .build {
        didSet {
            buildingSite = nil
            zoneDrag = nil
            saleCandidate = nil
        }
    }
    /// What the zoning mode zones cells for (decision 98), or `nil` to
    /// clear their zones.
    public var zoningZone: Zone? = .residential
    /// The cells a drag with the zoning mode would zone, while the finger
    /// is down (decision 98).
    public internal(set) var zoneDrag: CellRectangle?
    /// Where the building tool would build, once the player tapped there
    /// (decision 95): the map shows the building there and what it would
    /// cost and pull down, and the action button builds it.
    public internal(set) var buildingSite: PlanPoint?
    /// The company's building the sell mode would sell, once the player
    /// tapped it (decision 130): the map marks it, the card shows what it
    /// would bring in and the gain or loss, and the action button sells it.
    public internal(set) var saleCandidate: PlacedBuildingID?
    /// Whether a tap on the map chooses a tile of the map to buy (decision
    /// 160): the map marks the tiles for sale and their prices.
    public internal(set) var isChoosingMapTile = false
    /// The tile of the map chosen to buy (decision 160): the map marks it,
    /// and the pill beside it buys it.
    public internal(set) var chosenMapTile: MapTile?
    /// Whether a tap with the building tool builds there at once rather
    /// than showing the building first (decision 103): for putting up one
    /// building after another. Undo takes each back.
    public var buildingBuildsOnTap = false
    /// While a finger drags the shown building (decision 103): where the
    /// site was when the drag began, which a cancelled drag puts back.
    @ObservationIgnored var buildingDragSiteBefore: PlanPoint?

    /// Name for the next station. Pre-filled with a suggestion the player can
    /// edit; GameCore decides whether it is valid.
    public var stationName: String

    /// The name the session last suggested for ``stationName``. A new
    /// suggestion replaces ``stationName`` only while it is still this one:
    /// a name the player typed is never overwritten.
    @ObservationIgnored var automaticStationName: String

    /// The car count the session last suggested for ``platformCars``
    /// (from a real TRA station's grade); replaced, like the name, only
    /// while the player has not changed it.
    @ObservationIgnored var automaticPlatformCars: Int = GameSession.defaultPlatformCars

    /// The car count a platform is built for where no real default applies.
    static let defaultPlatformCars = 4

    /// The train the train tool acts on: an ID only, never a copy of the
    /// train. Read the train itself through ``selectedTrain``.
    public private(set) var selectedTrainID: TrainID?

    /// The train the last tap on the map picked (see ``tapMap(at:reach:)``),
    /// which the select tool's inspector shows; `nil` once a tap or a
    /// command selects a station or a point instead.
    public private(set) var tappedTrainID: TrainID? {
        didSet { refreshScreenFacts() }
    }

    /// The company's building the last tap on the map picked with the
    /// select tool (decision 173), which the inspector shows; an ID only.
    public private(set) var selectedBuildingID: PlacedBuildingID? {
        didSet { refreshScreenFacts() }
    }
    /// The track the last tap with the select tool picked where there was
    /// no station, train or building (decision 184), which the inspector
    /// shows (``GameWorld/trackInspectionText(of:in:)``); an ID only.
    public private(set) var selectedTrackEdge: TrackEdgeID? {
        didSet {
            if selectedTrackEdge != oldValue { trackUpgrade = nil }
            refreshScreenFacts()
        }
    }
    /// What the track card is about to build on ``selectedTrackEdge``
    /// (decision 247, TrackUpgrade.swift): `nil` until the player picks
    /// "Make double track" or "Add X crossover".
    public internal(set) var trackUpgrade: TrackUpgradeKind?
    /// Which side of the picked track the second track goes, and whether
    /// it runs to the switches at both ends (the default) or covers only
    /// the piece picked.
    public var trackUpgradeSide: PlatformTrackSide = .left
    public var trackUpgradeWholeRun = true
    @ObservationIgnored var trackUpgradeMemo: TrackUpgradeMemo?
    /// How many times the drafted upgrade was worked out (for the tests).
    @ObservationIgnored var trackUpgradeWorkedOut = 0

    /// The train the camera follows: the `Ci/` reference's
    /// `trackedTrainId`, kept apart from the selection
    /// (``selectedTrainID``, the reference's `selectedTrainId`), so picking
    /// another train or a station never moves or ends it. An ID only; read
    /// the train through ``followedTrain``, which is `nil` once the train is
    /// gone or off the track. Started with ``followTrain(_:)`` or
    /// ``toggleFollowTrain()``; ended by the player (``stopFollowingTrain()``,
    /// a drag, pinch or zoom of the map through ``mapDidMove()``, closing the
    /// train with ``clearSelection()``), or when the train leaves the track,
    /// stops existing or its line is removed.
    public private(set) var followedTrainID: TrainID? {
        didSet { if followedTrainID != oldValue { updateMap3DSpeedCap() } }
    }

    /// The way the selected train faces when it is placed: along its
    /// platform, the way nearer this compass point. Only used by
    /// ``placeSelectedTrain()``; it never turns a train that is on the track.
    public private(set) var placementHeading: CompassHeading = .east

    /// The outcome of the last action, for the status line. Cleared when the
    /// player selects another point or tool.
    public internal(set) var message: StatusMessage? {
        didSet {
            messageSerial &+= 1
            noteMessageInNews()
            // Decision 184: something refused sounds so.
            if message?.kind == .failure { playSound?(.refused) }
        }
    }

    /// Counts each time ``message`` is set, the same message again
    /// included: a second "Saved the game." is a newer message, which the
    /// banner announces and shows for its own while
    /// (``StatusMessage/autoDismissDelay``, ``dismissMessage(posted:)``).
    public private(set) var messageSerial: UInt64 = 0

    /// The year that closed while the game ran, until the player has seen
    /// its year-end report (Phase 7a, decision 85): which year it is, never
    /// a copy of the statement, which stays the world's. Read it through
    /// ``yearEndStatement``. Not set by loading a game whose years closed
    /// before.
    public private(set) var yearEndYear: Int64?

    /// The statement of ``yearEndYear``, as the world has it.
    public var yearEndStatement: AnnualStatement? {
        yearEndYear.flatMap { year in world.accounts.years.last { $0.year == year } }
    }

    /// The player has seen the year-end report.
    public func dismissYearEnd() {
        yearEndYear = nil
    }

    // MARK: - The secretary room (decision 175)

    /// The news log (``NewsLog``): what the station master said, what
    /// happened and when. Kept with the save, never in it.
    /// Whether ``restoreNews(_:)`` is putting a save's log in place.
    @ObservationIgnored var isRestoringNews = false
    public internal(set) var news = NewsLog() {
        didSet {
            refreshScreenFacts()
            // Decision 184: a new worry (debt, a deadline, a typhoon, a town
            // short of materials) rings the warning. A refusal has its own
            // sound; a log read from a save rings nothing.
            guard !isRestoringNews, let newest = news.items.first, newest.id != oldValue.items.first?.id,
                  newest.category.isWorry, newest.category != .failure
            else { return }
            playSound?(.warning)
        }
    }

    /// The month that closed while the game ran, until the player has seen
    /// its report (set by the month's closing, like ``yearEndYear``).
    public internal(set) var monthEndReport: MonthlyReport?

    /// The player has seen the monthly report.
    public func dismissMonthEnd() {
        monthEndReport = nil
    }

    /// Whether the game pauses for typhoons, goals met, debt and a
    /// challenge's last week (the settings; kept on the device, so the app
    /// sets it).
    public var pausesForImportantEvents = true

    /// What happens when a month closes (the settings).
    public var monthlyReportMode: MonthlyReportMode = .openAndPause

    /// What the log last saw of the world, to tell what is new.
    @ObservationIgnored var newsWatch: NewsWatch
    /// Set while the session writes a message of its own into the log in
    /// words of its own.
    @ObservationIgnored var isMessageKeptOutOfNews = false

    /// Whether the scenario ended while the game ran (decision 86), until
    /// the player has seen how: its goals panel opens. Not set by loading a
    /// game whose scenario ended before.
    public private(set) var scenarioJustEnded = false

    /// The player has seen how the scenario ended.
    public func dismissScenarioEnd() {
        scenarioJustEnded = false
    }

    /// The line the line panel shows: an ID only, never a copy of the line.
    /// Read the line itself through ``selectedLine``.
    public private(set) var selectedLineID: LineID?

    /// The real line just bought (decision 315), for the card that says
    /// so; the card clears it when closed.
    public var lastLineAcquired: RealLineAcquired?

    /// The real line offered on the purchase card (decision 315), while
    /// the card is open.
    public var shownRealLineOffer: RealLineOffer?

    /// The stations picked, in order, for the next line. Only a draft:
    /// GameCore checks them when ``createLineFromDraft()`` creates the line.
    public private(set) var lineDraft: [StationID] = []

    /// Decision 303: the new line's confirmation card while it is up, the
    /// settings it opens the drafted line with (``confirmLineDraft()``).
    public internal(set) var lineConfirmation: LineConfirmation?

    /// The stations along the track through ``lineDraft``
    /// (`GameWorld.stationsAlongTrack(through:)`, decision 100), kept up to
    /// date as the draft and the track change; `nil` for fewer than two
    /// picked stations or when no track joins two picked in a row.
    public private(set) var lineDraftRoute: [StationID]?

    /// Why no track joins the stations of ``lineDraft`` (decision 284),
    /// kept with ``lineDraftRoute``: `nil` while a route is found or for
    /// fewer than two picked stations.
    public private(set) var lineDraftGap: LineDraftGap?

    /// Which stations along ``lineDraftRoute`` the new line calls at.
    public var lineDraftStopping: LineDraftStopping = .everyStation

    /// The stations along the route the player left out with
    /// ``LineDraftStopping/custom``.
    public private(set) var lineDraftSkipped: Set<StationID> = []

    /// Whether a tap on a station on the map adds it to ``lineDraft``
    /// (decision 100), so the player picks a new line's ends on the map
    /// without a button for each.
    public private(set) var isPickingLineStops = false

    /// The station demand copied to paste onto other stations (Stage C2;
    /// see ``copySelectedStationDemand()``). Only a clipboard: GameCore
    /// checks it when it is pasted.
    public internal(set) var demandClipboard: StationDemand?

    // The network tool (Stage C1): drafts only, read through GameCore when
    // used (see NetworkSession.swift).

    /// What a tap does with the network tool.
    public internal(set) var networkMode: NetworkToolMode = .build
    /// The ends picked for the next stretch of track: an existing node, or
    /// a point for a new one. Nothing is built until
    /// ``buildNetworkTrack()``.
    public internal(set) var networkStart: NetworkAnchor?
    public internal(set) var networkEnd: NetworkAnchor?
    /// While a finger draws track (decision 102): the end picked before the
    /// drag began, which a cancelled drag puts back.
    @ObservationIgnored var networkDragEndBefore: NetworkAnchor??
    /// Whether the drag under way picked a new start (it began on other
    /// track): cancelled, it keeps that start but not the old end.
    @ObservationIgnored var networkDragMovedStart = false
    /// Where the finger drawing track is, for the magnifier (decision 204);
    /// `nil` when no drag draws track.
    public internal(set) var networkDragFinger: PlanPoint?
    /// What carries the next stretch of track: what the ground asks for
    /// (decision 124) unless the player forces a structure.
    public var networkStructure: TrackStructure = .automatic
    /// How high a new node goes above the ground there (decision 124; in a
    /// world without ground, above 0 m), in world units (64 to a metre).
    public var networkHeight: Int64 = 0

    /// How far the demo mode's real lines have got while they are laid
    /// (decision 351, ``layDemoRealLines(in:)``); `nil` otherwise.
    public internal(set) var demoRealLinesProgress: DemoRealLines.Progress?

    /// Whether the demo is laying the real lines now: the speed, pause,
    /// the night skip, Undo and Redo wait until it is done (review E's
    /// E2), so what it lays stays one Undo.
    public var isLayingDemoRealLines: Bool {
        demoRealLinesProgress != nil
    }
    /// Whether a trace keeps the real line's tunnels and viaducts at any
    /// ``networkHeight``, as the demo mode's real lines are laid, each on
    /// its own level where they would cross (decision 351).
    var demoKeepsRealStructures = false
    /// Whether the next stretch continues the track at its ends smoothly
    /// (the default), or runs straight.
    public var networkFollowsTrack = true
    /// Whether a tap near the track joins it (the default): a node, or a
    /// turnout on an edge, whatever its height. Off, every tap is a new
    /// point at ``networkHeight``, so a parallel track can be laid 4 m
    /// beside another (``RailwayNetwork/trackSpacing``), closer than a tap
    /// reaches, or a viaduct's end set over a track.
    public var networkSnapsToTrack = true
    /// Whether a stretch between two tracks is built as an X (scissors)
    /// crossover, with the mirrored diagonal crossing it at a diamond in
    /// the middle (see ``networkPicksCrossover``), rather than one.
    public var networkBuildsScissors = false
    /// Whether each stretch gets a second track beside it, 5 m apart
    /// (decision 204, ``DoubleTrack``), on ``networkDoubleSide`` of the
    /// way it is drawn.
    /// With ``networkTracesRealRailway`` too, the traced stretch gets it
    /// (decision 247); until the player sets it, a traced stretch is
    /// single or double as the real line is (its later,
    /// ``tracedDouble(_:)``).
    public var networkBuildsDouble = false {
        didSet { networkDoubleChosen = true }
    }
    /// Whether the player has set ``networkBuildsDouble``: from then on a
    /// traced stretch follows it, not the real line.
    public internal(set) var networkDoubleChosen = false
    /// The "Double" switch as it shows: what the stretch drawn will be
    /// (single or double as the real line is, while that decides it), and
    /// otherwise ``networkBuildsDouble``. Setting it sets that.
    public var networkDoubleShown: Bool {
        get { networkPreview?.tracedDouble ?? networkBuildsDouble }
        set { networkBuildsDouble = newValue }
    }
    public var networkDoubleSide: PlatformTrackSide = .left
    /// Whether the next stretch follows the real railway under a
    /// real-world map (decision 213, ``tracePlan(from:to:)``): ends snap
    /// to the real lines, and the track between follows them.
    public var networkTracesRealRailway = false
    /// The real lines of the map, projected once for each map (decision
    /// 213, ``realRailwayTraces``).
    @ObservationIgnored var realRailwayTracesMemo: (key: RealRailwayTracesKey, traces: RealRailwayTraces)?
    /// The real line ``networkTracedWay`` last found, and between which
    /// points: the map reads it at every redraw.
    @ObservationIgnored var tracedWayMemo: (key: TracedWayKey, way: [WorldCoordinate])?
    /// How many times ``networkTracedWay`` was worked out (for the tests).
    @ObservationIgnored var tracedWaysWorkedOut = 0
    /// Which side of the picked track a passing loop goes (decision 204).
    public var networkLoopSide: PlatformTrackSide = .left
    /// The depot tool's sidings (decision 214, ``DepotYard``): how many,
    /// which side of the track's end they fan out to, and the end picked.
    public var networkDepotSidings = DepotYard.defaultSidings
    public var networkDepotSide: PlatformTrackSide = .left
    public internal(set) var networkDepotEnd: TrackNodeID?
    /// Whether a stretch that climbs or falls eases into and out of its
    /// grade with vertical curves at both ends (the default, decision 164),
    /// where it fits under the steepest grade.
    public var networkEasesGrade = true
    /// The place on an edge the platform and remove modes picked.
    public internal(set) var networkEdgePoint: NetworkEdgePoint?
    /// How many cars the next platform is long enough for.
    public var platformCars = GameSession.defaultPlatformCars
    /// The station the next platform serves; `nil` builds a new station
    /// named ``stationName`` beside it.
    public var platformStationID: StationID?

    /// Who lives where on real-world maps in Taiwan, which sets the
    /// ridership of a managed company's new stations there (see
    /// PopulationGrid.swift); `nil` gives them the city's. The app's
    /// bundled grid, set by the launcher; never saved.
    @ObservationIgnored public var population: PopulationGrid?

    /// What there is around places on real-world maps in Taiwan, which
    /// sets the kind of a managed company's new stations there (see
    /// PlaceGrid.swift); `nil` makes them all serve homes. The app's
    /// bundled grid, set by the launcher; never saved.
    @ObservationIgnored public var places: PlaceGrid?

    /// Taiwan's water (decision 105), read in with the land of a map whose
    /// land is read as it is needed; `nil` without the app's file.
    @ObservationIgnored public var water: WaterGrid?

    /// Taiwan's ground height (decision 124), which the network tool shows
    /// at the ends it picked on a real-world map; `nil` without the app's
    /// file. It can arrive after a game opened: a track preview worked out
    /// without it is worked out again.
    @ObservationIgnored public var heights: HeightGrid? {
        didSet {
            networkPreviewMemo = nil
            platformLevellingMemo = nil
            passingLoopMemo = nil
            depotYardMemo = nil
            lineOpeningMemo = nil
            lineDraftSummaryMemo = nil
            lineConfirmationMemo = nil
        }
    }

    /// How much of the ground real buildings cover (decision 147), read in
    /// with the land of a map whose land is read as it is needed; `nil`
    /// without the app's file.
    @ObservationIgnored public var coverage: CoverageGrid?

    /// Taiwan's real railways (stations and lines) for real-world maps.
    /// Handed to each session by the launcher; never saved. Once they are
    /// there, a station name still as first suggested is suggested again
    /// from them, at the middle of a real-world map. Observed: they can
    /// arrive after the game starts (``GameLauncher/loadRealWorldData(reading:)``),
    /// and the map then draws them.
    public var railways: RealRailways? {
        didSet {
            railwaysRevision &+= 1
            suggestStationNameAtTheMiddle()
            // Decision 298: the transfers come with the railways.
            refreshTransfers()
        }
    }

    /// Counts the changes to ``railways`` (decision 328).
    @ObservationIgnored private(set) var railwaysRevision = 0
    /// ``buyableRealLines`` as last worked out, and from what.
    @ObservationIgnored var buyableRealLinesMemo: (key: BuyableRealLinesKey, sale: RealLineSale)?

    /// Taiwan's place names (decision 159), which a new station on a
    /// real-world map is named after when no real station is right there.
    /// Handed to each session by the launcher with the railways; never
    /// saved. Like them, a station name still as first suggested is
    /// suggested again once they are there.
    @ObservationIgnored public var placeNames: PlaceNames? {
        didSet { suggestStationNameAtTheMiddle() }
    }

    private func suggestStationNameAtTheMiddle() {
        let middle = RealWorldFrame(world: world).map { PlanPoint(x: Int64($0.middleX), y: Int64($0.middleY)) }
        suggestStationName(at: middle)
    }

    /// The tutorial on screen (Stage C5), or `nil`. Moved through the
    /// tutorial methods (see TutorialSession.swift); never saved.
    public internal(set) var tutorial: Tutorial? {
        didSet {
            noteTutorialStepToResume()
            refreshScreenFacts()
        }
    }
    /// Whether new lines wait for the player to buy their trains, under
    /// simple rules too (decision 264): for tests that staff lines by hand.
    /// Since decision 266 the tutorial (lesson 1's guide) no longer sets it.
    /// Never saved.
    public internal(set) var staffsLinesByHand = false
    /// The tutorial the player skipped, kept to be taken up again at the
    /// same step from the game menu (``resumeTutorial()``; decision 188,
    /// later fix, TestFlight 54.1), or `nil`. Never saved; the launcher
    /// keeps its step between launches.
    public internal(set) var skippedTutorial: Tutorial? {
        didSet { noteTutorialStepToResume() }
    }
    /// Whether the lines panel is on screen, as the app tells it
    /// (``linesPanelDidChange(isShown:)``), for the tutorial's
    /// ``TutorialGoal/openLines``. Only UI state, never saved.
    public internal(set) var isLinesPanelShown = false
    /// Called with the step a tutorial left now would be taken up again
    /// at, the one on screen or skipped (`nil` when there is none, as once
    /// it is finished), whenever it changes: the launcher keeps it, so the
    /// tutorial can be taken up again after the app is closed.
    @ObservationIgnored public var onTutorialStepToResume: (@MainActor (String?) -> Void)?
    @ObservationIgnored var notedTutorialStepToResume: String?
    /// Called when the player finishes the tutorial's last step (decision
    /// 177): the launcher notes it in its preferences. Not on Skip.
    @ObservationIgnored public var onTutorialCompleted: (@MainActor () -> Void)?
    /// Called after a step that passed midnight (decision 181): the
    /// launcher checks the achievements.
    @ObservationIgnored public var onMidnight: (@MainActor () -> Void)?

    /// The world as it was before each of the latest edits, oldest first,
    /// at most ``undoLimit`` of them (ARCHITECTURE decision 82): what
    /// ``undo()`` goes back to. Snapshots only, never played or shown; the
    /// world is ``world``. Pushed by ``performEdit(_:)``, emptied as soon as
    /// game time moves on, and never saved, so a new game, a loaded save
    /// and the start screen (each a new session) start without any.
    private(set) var undoHistory: [GameWorld] = []
    /// The worlds ``undo()`` took back, the latest undone last (decision
    /// 184, the simulator's `future` stack): what ``redo()`` goes forward
    /// to. Emptied by any new edit and, like ``undoHistory``, as soon as
    /// game time moves on; never saved.
    private(set) var redoHistory: [GameWorld] = []

    /// Counts the edits, undos and redos that changed the world (decision
    /// 184, later): with the game hour, when the station master's advice
    /// is worked out again (``stationMasterRefreshKey``). Never saved.
    public private(set) var editSerial = 0

    /// When the station master's advice can have changed (decision 184,
    /// later, after #420's review): an edit, or a new hour of game time,
    /// as the secretary's log asks it once an hour (decision 175). The
    /// advice can read the whole land (``UnservedCluster``), so the corner
    /// works it out only when this changes, not at every tick.
    public struct AdviceRefreshKey: Hashable, Sendable {
        /// The session: another game is other advice.
        let session: ObjectIdentifier
        let edit: Int
        let hour: Int64
    }

    public var stationMasterRefreshKey: AdviceRefreshKey {
        AdviceRefreshKey(session: ObjectIdentifier(self), edit: editSerial, hour: world.clock.now.seconds / GameTime.secondsPerHour)
    }

    /// Whether a control is being dragged (``beginEditGesture()``), so its
    /// edits make one snapshot between them.
    @ObservationIgnored private var isEditGestureOpen = false
    /// Whether the open gesture has already kept its snapshot.
    @ObservationIgnored private var editGestureHasSnapshot = false

    /// Plays the sounds the session's changes call for (``SoundCue``): a
    /// train in service arriving at a station, track built, another tool.
    /// The app's player, set by the launcher; `nil` plays nothing. Never
    /// saved.
    @ObservationIgnored public var playSound: (@MainActor (SoundCue) -> Void)?
    /// Decision 219, stage 2: the factor on the music while the followed
    /// train runs into an interchange (``MusicDuck``), told to the app
    /// when it changes; `nil` tells no one.
    @ObservationIgnored public var duckMusic: (@MainActor (Double) -> Void)?
    /// The factor last told to ``duckMusic``.
    @ObservationIgnored private var musicDuck = 1.0
    /// Decision 343: the sound of the followed train running
    /// (``RunningSound``), told to the app when it changes; `nil` for
    /// silence. `nil` tells no one.
    @ObservationIgnored public var runningSound: (@MainActor (RunningSound?) -> Void)?
    /// The sound last told to ``runningSound``.
    @ObservationIgnored private var lastRunningSound: RunningSound?
    /// Decision 346: the sound of the weather the map shows
    /// (``WeatherSound``), told to the app when it changes and at once
    /// when set; `nil` for a clear sky. `nil` tells no one.
    @ObservationIgnored public var weatherSound: (@MainActor (WeatherSound?) -> Void)? {
        didSet {
            weatherKey = nil
            lastWeatherSound = nil
            updateWeatherSound()
        }
    }
    /// The sound last told to ``weatherSound``.
    @ObservationIgnored private var lastWeatherSound: WeatherSound?
    /// What the weather was last worked out from: the day and the world's
    /// weather, all it changes with.
    @ObservationIgnored private var weatherKey: WeatherKey?

    /// The last thing the player put up, which the map marks (decision
    /// 117, ``notePutUp(at:)``); `nil` before any. Never saved.
    public internal(set) var buildPulse: BuildPulse?
    /// The last money that came in, which the status pill floats up
    /// (decision 117, ``noteIncome(since:)``); `nil` before any. Never
    /// saved.
    public internal(set) var incomePulse: IncomePulse?
    /// Decision 256: the fares the last step took, by station, which the
    /// map floats over them (``FareFloatBoard``); `nil` before any. Never
    /// saved.
    public internal(set) var farePulse: FarePulse?
    /// Decision 276: the trips the last step ended full (decision 310), which
    /// the map stamps at the stations they ended at (``TripStampBoard``);
    /// `nil` before any. Never saved.
    public internal(set) var tripStampPulse: TripStampPulse?
    /// Decision 353: the station stamps the last midnight collected,
    /// which the map lands over their stations; `nil` before any. Never
    /// saved.
    public internal(set) var stationStampPulse: StationStampPulse?
    /// Decision 353: when each station stamp in the passport was
    /// collected, by its key (``StationStampRecords/dates``), for the
    /// station panel. The record is the launcher's file; this is its
    /// copy for the game, never saved.
    public internal(set) var collectedStamps: [String: Date] = [:]
    /// Decision 276: the fullest each running trip's train has been, read
    /// after every step for the stamps. Never saved.
    @ObservationIgnored var tripLoads = TripLoads()
    /// Decision 256: the goals the last step met, which the map checks off
    /// with a tune; `nil` before any. Never saved.
    public internal(set) var goalPulse: GoalPulse?
    /// Decision 256: the towns the last midnight grew a step, which the
    /// map rings; `nil` before any. Never saved.
    public internal(set) var townPulse: TownGrowthPulse?
    /// Where the map is asked to look (decision 177): the station master's
    /// tap on advice that points at a place. The map view moves its camera
    /// when it changes. Never saved.
    public internal(set) var cameraRequest: CameraRequest?
    /// The city's request the map points out (decision 246,
    /// ``showRequestOnMap(_:)``); `nil` for none. Never saved.
    public internal(set) var focusedRequestID: Int?

    /// The trains the player is looking at, whose arrivals ring at full
    /// volume (``SoundCue/arrival(watched:)``): the one the camera follows,
    /// the one last tapped on the map, and the selected one while the
    /// train tool is open.
    public var watchedTrainIDs: Set<TrainID> {
        var watched = Set([followedTrainID, tappedTrainID].compactMap { $0 })
        if tool == .train, let selectedTrainID {
            watched.insert(selectedTrainID)
        }
        return watched
    }

    /// Real time per simulation tick. At 600× (``GameSpeed/normal``) a tick
    /// is one game minute, so a game day lasts 144 real seconds; at 1× it is
    /// a tenth of a game second (Stage W2a).
    public nonisolated static let tickInterval: Duration = .milliseconds(100)
    /// The most real time one loop step turns into ticks (five ticks).
    public nonisolated static let maximumStepDuration: Duration = .milliseconds(500)

    @ObservationIgnored private var tickAccumulator = TickAccumulator(
        tickInterval: GameSession.tickInterval,
        maximumElapsed: GameSession.maximumStepDuration
    )
    @ObservationIgnored private var gameLoop: Task<Void, Never>?

    // MARK: - Watching speed (decision 195)

    /// How fast the game really runs and the followed train goes, as the
    /// status pill shows them: a new speed reads afresh, and not following
    /// a train shows no train's speed.
    public var viewingSpeed: ViewingSpeed {
        let shown = shownViewingSpeed
        let same = shown.speed == world.clock.speed
        return ViewingSpeed(
            speed: world.clock.speed, actualTenths: same ? shown.actualTenths : nil, isBehind: same && shown.isBehind,
            trainKilometresPerHour: followedTrainID == nil ? nil : shown.trainKilometresPerHour
        )
    }

    /// What ``viewingSpeed`` last read, as it is shown: set only when what
    /// is shown changes, so a tick that changes nothing shown changes
    /// nothing observed.
    private var shownViewingSpeed = ViewingSpeed(speed: .paused, permille: nil, trainKilometresPerHour: nil)
    @ObservationIgnored private var speedMeter = GameSpeedMeter()
    @ObservationIgnored private var trainSpeedometer = TrainSpeedometer()
    /// Decision 224: which platforms had a train standing at them over the
    /// last game hour, for the station's operations page.
    @ObservationIgnored public private(set) var platformUse = PlatformUse()
    /// The real time the game has run, and the ticks put in place in it,
    /// for ``speedMeter``.
    @ObservationIgnored private var realTimeRun: Duration = .zero
    @ObservationIgnored private var ticksRun: Int64 = 0

    /// Notes that `elapsed` real time went by in a step of the game, after
    /// its ticks were put in place: how fast it really ran (none while
    /// paused), and what the pill shows of it.
    private func noteRealTime(_ elapsed: Duration) {
        if world.clock.isPaused {
            speedMeter.reset()
        } else {
            realTimeRun += max(elapsed, .zero)
            speedMeter.record(real: realTimeRun, ticks: ticksRun, speed: world.clock.speed)
        }
        let shown = ViewingSpeed(
            speed: world.clock.speed, permille: speedMeter.permilleOfSpeed,
            trainKilometresPerHour: followedTrainID == nil ? nil : trainSpeedometer.kilometresPerHour
        )
        if shown != shownViewingSpeed { shownViewingSpeed = shown }
    }

    /// A managed company's stations without ridership get the city's
    /// (``StationDemand/cityDefault``), as stations built since do; saves
    /// from before ARCHITECTURE decision 46 may have such stations.
    public init(world: GameWorld, language: DisplayLanguage = .english) {
        let world = Self.withCityRidership(world)
        self.world = world
        self.commandLog = CommandLog(start: world)
        self.language = language
        let suggested = Self.suggestedStationName(for: world, in: language)
        self.stationName = suggested
        self.automaticStationName = suggested
        self.selectedTrainID = world.trains.first?.id
        self.selectedLineID = world.lines.first?.id
        self.newsWatch = NewsWatch(world: world)
        // What the first monthly report compares with.
        self.news.baseline = MonthlyBaseline(world: world)
        refreshNightSkipOffer()
        refreshScreenFacts()
    }

    // MARK: - Selection

    /// A tap on the map at `point` with the select or train tool (Stage
    /// F1), reaching `reach` world units: selects the station whose mark
    /// is within half the reach; or else the train drawn nearest within
    /// reach (`GameWorld.train(near:within:)`, see ``tapTrain(_:)``); or
    /// else the nearest station within reach
    /// (`GameWorld.station(near:within:)`), and the point itself. A station
    /// right under the finger wins over a train beside it, so a station's
    /// mark always selects it. Only distance decides what a tap picks; the
    /// point is kept exactly (Stage F3d). Taps outside the world's bounds
    /// are ignored. Never changes the world.
    public func tapMap(at point: PlanPoint, reach: Int64) {
        guard world.bounds.contains(point) else { return }
        var station = world.station(near: point, within: reach / 2)?.id
        if station == nil, let train = world.train(near: point, within: reach) {
            tapTrain(train)
            return
        }
        station = station ?? world.station(near: point, within: reach)?.id
        if station == nil, tool == .select, let building = world.placedBuildings.first(where: {
            point.x >= $0.minX && point.x < $0.maxX && point.y >= $0.minY && point.y < $0.maxY
        }) {
            selectBuilding(building.id, at: point)
            return
        }
        // A stop the draft refused keeps the message saying why.
        var refused = false
        if isPickingLineStops, let station {
            refused = !appendToLineDraft(station)
        }
        // Decision 184: with nothing else there, the track under the tap.
        let track = station == nil && tool == .select ? world.trackEdgePoint(near: point, within: reach)?.edge : nil
        guard point != selectedPoint || station != selectedStationID || tappedTrainID != nil || track != selectedTrackEdge else { return }
        selectedPoint = point
        selectedStationID = station
        tappedTrainID = nil
        selectedBuildingID = nil
        selectedTrackEdge = track
        if !refused { message = nil }
    }

    /// Chooses the building the inspector shows as the one to sell: opens
    /// the building tool's sell mode on it (decision 173).
    public func sellSelectedBuilding() {
        guard let id = selectedBuildingID, world.placedBuilding(id: id) != nil else { return }
        selectTool(.building)
        buildingMode = .sell
        saleCandidate = id
    }

    /// Selects the company's building `id` for the inspector (decision
    /// 173), letting go of the station and train. Never changes the world.
    private func selectBuilding(_ id: PlacedBuildingID, at point: PlanPoint) {
        guard id != selectedBuildingID else { return }
        selectedBuildingID = id
        selectedPoint = point
        selectedStationID = nil
        tappedTrainID = nil
        selectedTrackEdge = nil
        message = nil
    }

    /// A tap that picked train `id`: it becomes the train the train tool
    /// acts on, and the select tool's inspector shows it. The select tool
    /// lets go of the station or point it had; the train tool keeps it, as
    /// the place it sends the train to. A stuck train's bubble and the news
    /// log's "Go" pick a train the same way.
    func tapTrain(_ id: TrainID) {
        guard tappedTrainID != id || selectedTrainID != id || (tool == .select && selectedPoint != nil) else { return }
        selectedTrainID = id
        tappedTrainID = id
        if tool == .select {
            selectedPoint = nil
            selectedStationID = nil
            selectedBuildingID = nil
            selectedTrackEdge = nil
        }
        message = nil
    }

    /// Selects station `id` and the point it stands at. Never changes the
    /// world; an ID the world does not have is ignored.
    public func selectStation(_ id: StationID) {
        guard let station = world.station(id: id), id != selectedStationID || station.point != selectedPoint || tappedTrainID != nil else { return }
        selectedPoint = station.point
        selectedStationID = id
        tappedTrainID = nil
        selectedBuildingID = nil
        selectedTrackEdge = nil
        message = nil
    }

    /// Lets go of the selected station, point and tapped train: the
    /// inspector closes. Like the reference's `closePanelTrain`, closing
    /// the train also ends following it.
    public func clearSelection() {
        selectedPoint = nil
        selectedStationID = nil
        tappedTrainID = nil
        selectedBuildingID = nil
        selectedTrackEdge = nil
        followedTrainID = nil
        updateFollowSounds()
        message = nil
    }

    /// Selects train `id` (the train tool's picker, the fleet list). Never
    /// changes the world or what the camera follows, even when another
    /// train is picked (the reference keeps `trackedTrainId` apart from
    /// `selectedTrainId`); an ID the world does not have is ignored.
    public func selectTrain(_ id: TrainID) {
        guard world.train(id: id) != nil else { return }
        selectedTrainID = id
        tappedTrainID = id
        message = nil
    }

    // MARK: - Following a train

    /// The followed train (``followedTrainID``) while it exists and stands
    /// on the track; `nil` otherwise, so the follow bar and the camera never
    /// show a train that cannot be followed.
    public var followedTrain: Train? {
        guard let id = followedTrainID, let train = world.train(id: id), train.position != nil else { return nil }
        return train
    }

    /// Whether the camera follows a train now (``followedTrain``).
    public var isFollowingTrain: Bool {
        followedTrain != nil
    }

    /// Whether the camera follows train `id` now.
    public func isFollowing(_ id: TrainID) -> Bool {
        followedTrain?.id == id
    }

    /// Starts following train `id` (the reference's `toggleTrainFollow`
    /// turning on). Only a train on the track can be followed; for any
    /// other, or an unknown ID, nothing changes. Never changes the world or
    /// the selection.
    public func followTrain(_ id: TrainID) {
        guard let train = world.train(id: id), train.position != nil else { return }
        followedTrainID = id
        updateFollowSounds()
    }

    /// Stops following (the follow bar's unfollow button).
    public func stopFollowingTrain() {
        followedTrainID = nil
        updateFollowSounds()
    }

    /// Tells the app the factor on the music (``MusicDuck``) and the
    /// followed train's running sound (``RunningSound``, decision 343) when
    /// they changed: after a step, and when following starts or stops.
    func updateFollowSounds() {
        if let runningSound {
            let sound = RunningSound.of(following: followedTrain, in: world)
            if sound != lastRunningSound {
                lastRunningSound = sound
                runningSound(sound)
            }
        }
        guard let duckMusic else { return }
        let gain = MusicDuck.gain(following: followedTrain, in: world)
        guard gain != musicDuck else { return }
        musicDuck = gain
        duckMusic(gain)
    }

    /// The train panel's follow button (the reference's `toggleTrainFollow`):
    /// stops following when the selected train is the one followed,
    /// otherwise follows the selected train if it is on the track. Without
    /// a selected train nothing changes.
    public func toggleFollowTrain() {
        guard let id = selectedTrainID else { return }
        toggleFollowTrain(id)
    }

    /// The select tool's follow button on the train it inspects
    /// (``tappedTrainID``): stops following when `id` is the followed
    /// train, otherwise follows it if it is on the track. Never changes the
    /// world or the selection.
    public func toggleFollowTrain(_ id: TrainID) {
        if isFollowing(id) {
            stopFollowingTrain()
        } else {
            followTrain(id)
        }
    }

    /// Lets go of a followed train that no longer exists or has left the
    /// track (the reference ends `trackedTrainId` when its train is gone).
    func endFollowIfGone() {
        if followedTrainID != nil, followedTrain == nil {
            followedTrainID = nil
        }
        // Every edit ends here: one that stops the followed train's service
        // or ends following brings the music back now, not at the next step.
        updateFollowSounds()
        // Decision 346: and one that changes the weather (its settings, an
        // undo) changes its sound now.
        updateWeatherSound()
    }

    /// Estimates the 800-metre walking catchment population of station `id`
    /// when the session runs on a real-world map with population data.
    public func stationCatchmentPopulation(of id: StationID) -> Int? {
        guard let station = world.station(id: id),
              let realWorld = RealWorldFrame(world: world),
              let population else { return nil }
        let coord = realWorld.coordinate(worldX: Double(station.location.x), worldY: Double(station.location.y))
        return population.people(within: StationDemand.catchmentRadius, ofLatitude: coord.latitude, longitude: coord.longitude)
    }

    // MARK: - Tools

    /// Switches tools. Changes nothing in the world but the clock:
    /// choosing a tool that builds (``ConstructionTool/pausesGame``) pauses
    /// a running game, and leaving those tools resumes it if the session
    /// paused it and the player has not touched the speed since
    /// (ARCHITECTURE decision 99). Choosing a tile of the map to buy pauses
    /// it the same way (decision 160, later), and a tool that builds keeps
    /// that pause.
    public func selectTool(_ newTool: ConstructionTool) {
        guard newTool != tool else { return }
        tool = newTool
        buildingSite = nil
        saleCandidate = nil
        endChoosingMapTile()
        zoneDrag = nil
        message = nil
        if newTool.pausesGame {
            // Not in the tutorial, where Undo is off (decision 188).
            if pauseForBuilding(), tutorial == nil {
                message = StatusMessage(
                    kind: .success,
                    text: language.text(
                        "Paused while you build, so every edit can be undone. Leave the tool or press play to go on.",
                        "建造時自動暫停，每一步都能復原。換回其他工具或按播放就會繼續。"
                    )
                )
            }
        } else {
            endPauseForBuilding()
        }
        playSound?(.transition)
    }

    /// Pauses a running game for building (decision 99), so each edit can
    /// be undone until time moves on: `true` when it paused it now.
    func pauseForBuilding() -> Bool {
        guard !world.clock.isPaused else { return false }
        logging(.pause) { $0.pause() }
        isPausedForBuilding = true
        return true
    }

    /// Resumes the game ``pauseForBuilding()`` paused, unless the player
    /// has touched the speed since.
    func endPauseForBuilding() {
        guard isPausedForBuilding, !isLayingDemoRealLines else { return }
        isPausedForBuilding = false
        if world.clock.isPaused { logging(.resume) { $0.resume() } }
    }

    /// Whether the session paused the game itself when a building tool was
    /// chosen (decision 99), or a tile of the map to buy (decision 160,
    /// later), so leaving the building tools, or the tiles, resumes it.
    /// Any speed change by the player, pausing and resuming included,
    /// lets go of it: the speed is then the player's.
    public private(set) var isPausedForBuilding = false {
        didSet { refreshNightSkipOfferOffTheMainActor() }
    }

    // MARK: - Speed

    /// Changes the game speed through the world's clock, the only record of it.
    /// Waits while the demo lays the real lines (review E's E2): a tick
    /// would split the one Undo it lays as.
    public func setSpeed(_ speed: GameSpeed) {
        guard !isLayingDemoRealLines else { return }
        changeSpeed(isSpeedCappedIn3D ? Map3DFollowSpeed.capped(speed) : speed)
    }

    /// The speeds the speed menu offers (decision 360): up to 10× while
    /// following a train on the 3D map, every speed otherwise.
    public var speedChoices: [GameSpeed] {
        Map3DFollowSpeed.choices(capped: isSpeedCappedIn3D)
    }

    /// Tells the session the 3D map opened or closed (decision 360): while
    /// it is open and the camera follows a train, the game runs at 10× at
    /// most, and closing it gives back the speed the session lowered.
    public func setMap3DOpen(_ open: Bool) {
        guard open != isMap3DOpen else { return }
        isMap3DOpen = open
        updateMap3DSpeedCap()
    }

    @ObservationIgnored private var isMap3DOpen = false

    /// Whether the speed is held to 10× at most now: the 3D map is open and
    /// follows a train (decision 360).
    public private(set) var isSpeedCappedIn3D = false

    /// The speed the game ran at before following on the 3D map lowered
    /// it, given back when following there ends; `nil` when it was not
    /// lowered.
    @ObservationIgnored private var speedBefore3D: GameSpeed?

    private func updateMap3DSpeedCap() {
        let capped = isMap3DOpen && followedTrainID != nil
        guard capped != isSpeedCappedIn3D else { return }
        isSpeedCappedIn3D = capped
        if capped {
            let running = world.clock.runningSpeed
            let lowered = Map3DFollowSpeed.capped(running)
            guard lowered != running else { return }
            speedBefore3D = running
            setRunningSpeed(lowered)
        } else if let before = speedBefore3D {
            speedBefore3D = nil
            setRunningSpeed(before)
        }
    }

    /// Runs the game at `speed`, or, paused, resumes it at `speed` later,
    /// keeping the pause and what paused it.
    private func setRunningSpeed(_ speed: GameSpeed) {
        guard speed != world.clock.runningSpeed else { return }
        dropNightSkip()
        let paused = world.clock.isPaused
        logging(.setSpeed(speed)) { $0.setSpeed(speed) }
        if paused { logging(.pause) { $0.pause() } }
    }

    /// ``setSpeed(_:)`` whatever is under way.
    func changeSpeed(_ speed: GameSpeed) {
        isPausedForBuilding = false
        isPausedForEvent = false
        dropNightSkip()
        // Decision 143: any write drops the tick being worked out, so the
        // speed the game already runs at is not written again.
        var clock = world.clock
        clock.setSpeed(speed)
        guard clock != world.clock else { return }
        logging(.setSpeed(speed)) { $0.setSpeed(speed) }
    }

    /// Pauses a running game for an event the player should see (decision
    /// 175); does nothing to one already paused.
    func pauseForEvent() {
        guard !world.clock.isPaused else { return }
        logging(.pause) { $0.pause() }
        isPausedForEvent = true
    }

    /// ``nightSkip`` as last looked at, after each tick and each command
    /// while paused (decision 305): what the shortcut shows, which a view
    /// reads without following the world every tick.
    public internal(set) var nightSkipOffer: NightSkip?

    /// The skip over a quiet night under way (decision 305), or `nil`.
    public internal(set) var nightSkipRun: NightSkipRun?

    /// Whether a quiet night is skipped without the shortcut being pressed
    /// (decision 305, the settings; kept on the device, so the app sets
    /// it). Off unless the player turns it on.
    public var skipsQuietNights = false

    /// The run ahead behind ``nightSkip``.
    @ObservationIgnored var nightSkipMemo: NightSkipMemo?

    /// How many times ``nightSkip`` ran ahead on the main actor: what the
    /// tests count (player feedback 82.1).
    @ObservationIgnored var nightSkipRunAheadOnMain = 0

    /// The run ahead under way off the main actor after a command while
    /// paused (decision 330, later) or after the game loop's tick
    /// (decision 369), or `nil`.
    @ObservationIgnored var nightSkipLookAhead: Task<Void, Never>?

    /// The first move of the night whose skip ended or was stopped, so the
    /// setting does not start it again.
    @ObservationIgnored var autoSkipDeclined: GameTime?

    /// Whether the session paused the game itself for an event (decision
    /// 175), and the player has not touched the speed since.
    public internal(set) var isPausedForEvent = false

    /// The world as a save keeps it (decision 99, 175 and 184, later): the
    /// world, but running at the player's speed when the session paused it
    /// by itself, for a building tool or an event. A game saved, or
    /// autosaved on leaving the app, while a tool or the monthly report
    /// held it then goes on when continued, as the player left it running.
    public var worldToSave: GameWorld {
        var saved = world
        // Decision 360: the speed the 3D map lowered is saved as it was.
        if let before = speedBefore3D {
            let paused = saved.clock.isPaused
            saved.setSpeed(before)
            if paused { saved.pause() }
        }
        if saved.clock.isPaused, isPausedForBuilding || isPausedForEvent { saved.resume() }
        return saved
    }

    /// "Keep Playing" on a lesson's result card (decision 266): runs the
    /// game again at its speed when the session paused it by itself for
    /// the goal met (decision 175); a pause of the player's own stays.
    public func keepPlaying() {
        guard world.clock.isPaused, isPausedForEvent else { return }
        togglePause()
    }

    /// Pauses a running game, or resumes a paused one at the speed it ran
    /// at (see `GameClock.runningSpeed`).
    public func togglePause() {
        guard !isLayingDemoRealLines else { return }
        isPausedForBuilding = false
        isPausedForEvent = false
        dropNightSkip()
        if world.clock.isPaused {
            logging(.resume) { $0.resume() }
        } else {
            logging(.pause) { $0.pause() }
        }
    }

    // MARK: - Traffic control

    /// Turns traffic control on or off through
    /// `GameWorld.setTrafficControl(_:)`. With it on, a train takes its whole
    /// route before it leaves and others wait for it; turning it on is
    /// refused while two trains need the same track.
    public func setTrafficControl(_ enabled: Bool) {
        perform(.setTrafficControl(enabled)) { _, _, _ in
            enabled
                ? language.text(
                    "Traffic control is on. Trains take their whole route before they leave.",
                    "交通控制已開啟。列車出發前會先預約整條進路。"
                )
                : language.text("Traffic control is off. Trains no longer wait for each other.", "交通控制已關閉。列車不再互相等待。")
        }
    }

    // MARK: - Disruptions

    /// Whether this game's holidays and events stay as they are because it
    /// has a scenario's goals (decision 154, later): a challenge is the
    /// same for everyone (decision 145), so they cannot be turned on. An
    /// older save that has them on keeps them too (the owner's decision on
    /// the #319–#400 review): turned off, a result reached on holiday peaks
    /// would be kept, and nothing in the save remembers they were on.
    public var eventsAreFixed: Bool {
        world.scenario != nil
    }

    /// Sets how strongly disruptions bite, or turns them off with `nil`
    /// (decision 154), through `GameWorld.setDisruptions(_:)`. The country
    /// whose holidays the game keeps stays as it is; turned on again, it is
    /// the map's (``CountryLookup``), or Taiwan's on a blank map. Decision
    /// 162: the weather's seed stays too; turned on, it is the demand
    /// events' (1 without them). In a game with a scenario's goals they
    /// stay as they are (``eventsAreFixed``).
    public func setDisruptionLevel(_ level: DisruptionLevel?) {
        guard level != world.disruptions?.level else { return }
        guard !eventsAreFixed else {
            message = StatusMessage(kind: .failure, text: world.disruptions == nil
                ? language.text(
                    "A challenge's rules are fixed: it has no holidays, weather or other events.",
                    "挑戰的規則固定，不含連假、天氣與其他事件。"
                )
                : Self.challengeSavedWithEventsText(in: language))
            return
        }
        let country = world.disruptions?.country ?? world.geoAnchor.map(CountryLookup.country(at:)) ?? HolidayCalendar.home
        let seed = world.disruptions?.seed ?? world.demandEvents?.seed ?? 1
        perform(.setDisruptions(level.flatMap { Disruptions(level: $0, country: country, seed: seed) })) { _, _, _ in
            level == nil
                ? language.text("Holidays and other events off: every week's demand is the same.", "連假等事件已關閉：每週的需求都一樣。")
                : language.text("Holidays and other events on: \(level!.title(in: language)).", "連假等事件已開啟：\(level!.title(in: language))。")
        }
    }

    /// What a challenge saved with holidays and events on says of them
    /// (decision 154, later): they stay, and its result is not kept.
    public static func challengeSavedWithEventsText(in language: DisplayLanguage) -> String {
        language.text(
            "This challenge was saved with holidays and events on: they stay as they are, and its result is not kept.",
            "這一局挑戰存檔時已開著連假與事件：設定不能更改，成績不列入紀錄。"
        )
    }

    // MARK: - Passenger routing

    /// Chooses how passengers released from now on find their way, through
    /// `GameWorld.setPassengerRoutingMode(_:)`: across the whole network,
    /// changing trains and walking between stations nearby (`network`), or
    /// only on a line that calls at both ends (`direct`). Those already
    /// waiting or riding keep their way.
    public func setPassengerRoutingMode(_ mode: PassengerRoutingMode) {
        guard mode != world.passengerRoutingMode else { return }
        perform(.setPassengerRoutingMode(mode)) { _, _, _ in
            mode == .network
                ? language.text(
                    "Passengers now plan journeys across the network and change trains.",
                    "乘客現在會規劃跨路線的旅程並轉乘。"
                )
                : language.text(
                    "Passengers now take only a line that serves both their stations.",
                    "乘客現在只搭兩站都停靠的路線。"
                )
        }
    }

    // MARK: - Economy

    /// Switches a managed company to free play through
    /// `GameWorld.setEconomyMode(_:)`: no fares or running costs, and
    /// ridership the player sets. Free play cannot become managed again,
    /// as the reference loads a free-play save only in free play
    /// (`MetroSaveModePolicy`): its ridership would be the player's, not
    /// the city's.
    ///
    /// A company in the red cannot switch: building still costs money in
    /// free play, which has no income, so a negative balance could never be
    /// built out of and the switch cannot be undone. Nor can a company with
    /// a loan: interest is paid only by a managed company (decision 67), so
    /// the loan would become money it never pays for. Nor can a challenge
    /// being played (``isFreePlayLocked``).
    public func setEconomyMode(_ mode: EconomyMode) {
        guard mode != world.accounts.mode else { return }
        guard mode == .free else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Free play cannot become a managed company again. Start a new game to manage one.",
                "自由模式無法再改回經營模式。要經營公司，請開新遊戲。"
            ))
            return
        }
        guard !isFreePlayLocked else {
            message = StatusMessage(kind: .failure, text: Self.freePlayLockedText(in: language))
            return
        }
        guard world.economy.balance >= .zero else {
            message = StatusMessage(kind: .failure, text: language.text(
                "The company is in the red. Free play has no income and building still costs money, so you could not build anything. Bring the balance back above zero first, or start a new game.",
                "公司目前虧損。自由模式沒有收入，蓋東西仍要花錢，切過去就什麼都蓋不了。請先讓餘額回到零以上，或開新遊戲。"
            ))
            return
        }
        guard world.accounts.loan == .zero else {
            message = StatusMessage(kind: .failure, text: language.text(
                "The company still owes \(world.accounts.loan.moneyText). Free play pays no interest, so repay the loan before switching.",
                "公司仍有 \(world.accounts.loan.moneyText) 貸款。自由模式不付利息，請先還清貸款再切換。"
            ))
            return
        }
        _ = try? performCommand(.edit(.setEconomyMode(mode)))
        message = StatusMessage(kind: .success, text: language.text(
            "Free play: no fares or running costs, and you set each station's ridership.",
            "自由模式：不收票價，也沒有營運成本；各站的客源由你設定。"
        ))
    }

    /// Whether this game cannot become free play because a challenge is
    /// being played (decision 86, later): its goals, deadline and
    /// bankruptcy are judged only at a managed company's midnights, so in
    /// free play it would never end. Once it has ended, the game may.
    public var isFreePlayLocked: Bool {
        world.scenario.map { $0.outcome == nil } ?? false
    }

    /// Why ``isFreePlayLocked`` keeps the game managed.
    public static func freePlayLockedText(in language: DisplayLanguage) -> String {
        language.text(
            "A challenge is being played: its goals are judged only for a managed company. Finish it, or start a new game for free play.",
            "挑戰進行中：目標只在經營模式下判定。完成挑戰，或開新遊戲玩自由模式。"
        )
    }

    /// Sets the network's fare rules through `GameWorld.setFareRules(_:)`.
    public func setFareRules(_ rules: FareRules) {
        perform(.setFareRules(rules)) { _, _, _ in
            language.text("Fares: \(rules.displayText(in: language)).", "已更新票價規則：\(rules.displayText(in: language))。")
        }
    }

    /// Sells a day pass at `price`, or stops with `nil`, through
    /// `GameWorld.setDayPass(_:)` (decision 324). Going on sale, or at a
    /// new price, prints a ticket (decision 373).
    public func setDayPass(_ price: Money?) {
        let before = world.accounts.dayPass
        let done = perform(.setDayPass(price)) { _, _, _ in
            guard let price else { return language.text("Day passes are no longer sold.", "已停售一日週遊券。") }
            return language.text("Day passes on sale at \(price.centsText).", "一日週遊券開賣，每張 \(price.centsText)。")
        }
        if done != nil, price != nil, price != before { playSound?(.ticketIssued) }
    }

    // MARK: - Game loop

    /// Whether the real-time loop is currently advancing the world.
    public var isGameLoopRunning: Bool {
        gameLoop != nil
    }

    /// Turns `elapsed` real time into whole ticks and advances the world by
    /// them, at once, on the main actor. While paused, elapsed time is
    /// discarded rather than saved up. If GameCore refuses to advance (game
    /// time is at its limit), the world is unchanged and the refusal is
    /// shown as the status message. The game loop does the same a tick at a
    /// time, worked out off the main actor (``startGameLoop()``).
    public func advance(realElapsed elapsed: Duration) {
        let ticks = dueTicks(realElapsed: elapsed)
        if ticks > 0 {
            let listening = playSound != nil
            finish(Result { () throws(GameError) in try Self.advanced(world, by: ticks, listening: listening) })
        }
        noteRealTime(elapsed)
    }

    /// Puts `ticks` of game time in place at once, as the game loop does a
    /// tick at a time: a replay of the command log (decision 193).
    func advance(ticks: Int) {
        finish(Result { () throws(GameError) in try Self.advanced(world, by: ticks, listening: false) })
    }

    /// The whole ticks `elapsed` real time makes due; none while paused,
    /// when the time is discarded rather than saved up.
    private func dueTicks(realElapsed elapsed: Duration) -> Int {
        guard !world.clock.isPaused else {
            tickAccumulator.reset()
            return 0
        }
        return tickAccumulator.ticks(for: elapsed)
    }

    /// What a step of ticks made of a world: the world after it, and the
    /// trains that arrived at a call within it and where, in train order.
    struct TickStep: Sendable {
        var world: GameWorld
        var arrived: [SoundCue.ArrivedTrain]
        /// How many ticks it is.
        var ticks: Int
        /// What traffic control shows of ``world``, when the step read it.
        var traffic: TrafficReading?
        /// Decision 330: the station master's advice for ``world``, when
        /// the step worked it out.
        var advice: WorkedAdvice?
    }

    /// `world` advanced by `ticks`, all or nothing. `listening` (sounds
    /// are played) advances a tick at a time, comparing only the arrival
    /// times (holding the whole world would copy what the ticks change): a
    /// step of several ticks can hold a train sent out, arriving and
    /// completing its service, and a completed service keeps no times to
    /// compare. Reads nothing but its arguments, so it can run off the main
    /// actor.
    nonisolated static func advanced(_ world: GameWorld, by ticks: Int, listening: Bool) throws(GameError) -> TickStep {
        var world = world
        guard listening else {
            try world.advance(ticks: ticks)
            return TickStep(world: world, arrived: [], ticks: ticks)
        }
        var arrived: [SoundCue.ArrivedTrain] = []
        for _ in 0..<ticks {
            let arrivals = SoundCue.arrivals(in: world)
            try world.advance(ticks: 1)
            arrived += SoundCue.trainsArrived(since: arrivals, in: world)
        }
        return TickStep(world: world, arrived: arrived, ticks: ticks)
    }

    /// Makes `outcome`, a step worked out from ``world`` as it is now, the
    /// world, with what follows a step: no edit before it can be undone,
    /// the arrival sound, the income (decision 117), the year's close and
    /// the scenario's end. A refused step changes nothing and shows the
    /// refusal.
    /// `fromLoop`: the game loop's tick, after which the night skip runs
    /// ahead off the main actor (decision 369).
    private func finish(_ outcome: Result<TickStep, GameError>, fromLoop: Bool = false) {
        let step: TickStep
        switch outcome {
        case .success(let advanced):
            step = advanced
        case .failure(let error):
            message = refusal(error)
            return
        }
        isApplyingTick = true
        defer { isApplyingTick = false }
        // Decision 330: each piece timed for the map's frame readout.
        let meter = FrameCostMeter.shared
        let closedBefore = world.accounts.years.last?.year
        let endedBefore = world.scenario?.outcome != nil
        let lastEntry = world.accounts.entries.last
        let dayBefore = world.clock.now.seconds / GameTime.secondsPerDay
        let timeBefore = world.clock.now
        let worldBefore = world
        meter.measure(.stepWorld) {
            isLogging = true
            world = step.world
            isLogging = false
            log(.advance(ticks: step.ticks), at: timeBefore)
            // Decision 195: the ticks that ran, and the followed train's way.
            ticksRun += Int64(step.ticks)
            if let traffic = step.traffic { trafficMemo = (worldRevision, traffic) }
            // Decision 330: likewise, for this world only.
            workedAdvice = step.advice.map { (worldRevision, $0) }
            // Game time moved on: no edit before it can be undone. Emptied
            // only when not empty (decision 367): emptying an empty history
            // still told everything reading Undo and Redo to look again,
            // the screen's frame among them, at every tick.
            if !undoHistory.isEmpty { undoHistory.removeAll() }
            if !redoHistory.isEmpty { redoHistory.removeAll() }
            editGestureHasSnapshot = false
        }
        meter.measure(.stepFollow) {
            endFollowIfGone()
            trainSpeedometer.observe(followedTrainID, from: worldBefore, to: world)
        }
        meter.measure(.stepPlatforms) { platformUse.record(world) }
        meter.measure(.stepSound) {
            if let playSound, let cue = SoundCue.arrivalCue(for: step.arrived, watched: watchedTrainIDs, speed: world.clock.speed, in: world) {
                playSound(cue)
            }
            updateFollowSounds()
        }
        meter.measure(.stepIncome) {
            // Decision 117: fares and rent settled within the step.
            noteIncome(since: lastEntry)
            retireCoveredShortfall()
            noteDayLoss(since: dayBefore)
        }
        // Decision 256: fares over the stations, goals met, towns grown.
        meter.measure(.stepActions) { noteActions(since: worldBefore) }
        if let closed = world.accounts.years.last?.year, closed != closedBefore {
            yearEndYear = closed
        }
        if !endedBefore, world.scenario?.outcome != nil {
            scenarioJustEnded = true
        }
        // Decision 175: the secretary room reads what the step changed.
        meter.measure(.stepNews) { observeNews(closedBefore: closedBefore) }
        if world.clock.now.seconds / GameTime.secondsPerDay > dayBefore {
            meter.measure(.stepMidnight) { onMidnight?() }
        }
        // Decision 305: the night's skip goes on, ends or starts.
        meter.measure(.stepNightSkip) { continueNightSkip(aheadOffTheMainActor: fromLoop) }
    }

    /// A tick of the game loop being worked out off the main actor
    /// (decision 143), from the world as it was when it began.
    struct LoopTick: Sendable {
        /// The world the tick advances.
        let world: GameWorld
        /// ``worldRevision`` when the tick began: a command since then
        /// changed the world the tick was worked out from.
        let revision: Int
        /// Whether sounds are played (see ``advanced(_:by:listening:)``).
        let listening: Bool
        /// Whether to read what traffic control shows of the world after
        /// the tick (``TrafficReading``), with the words of ``train``'s
        /// wait: the last tick of a step is the one shown.
        var readsTraffic = true
        /// The selected train when the tick began.
        let train: TrainID?
        let language: DisplayLanguage
        /// The last reading, whose kinds of scheduled waits the tick's
        /// reading keeps (decision 210).
        var previousTraffic: TrafficReading?
        /// Decision 330: what the tick needs to work out the station
        /// master's advice, which the news reads once a game hour.
        var advice: AdviceProbe?

        /// Advances ``world`` by one tick off the main actor, and reads
        /// what traffic control shows of it there too (decision 64's later
        /// fix: a deadlock search takes longer than a frame). The world
        /// is a copy: the session's stays as it is, and commands still
        /// apply to it, while this runs.
        func work() async -> Result<TickStep, GameError> {
            let tick = self
            return await Task.detached(priority: .userInitiated) {
                // Decision 328: timed for the map's frame readout.
                FrameCostMeter.shared.measure(.step) {
                    Result { () throws(GameError) in
                        var step = try GameSession.advanced(tick.world, by: 1, listening: tick.listening)
                        if tick.readsTraffic {
                            step.traffic = TrafficReading(world: step.world, train: tick.train, in: tick.language, previous: tick.previousTraffic)
                        }
                        // Decision 330: some 40 ms on the Yilan Line, once
                        // a game hour.
                        step.advice = tick.advice?.advice(of: step.world)
                        return step
                    }
                }
            }.value
        }
    }

    /// A tick of the game loop beginning from the world as it is now, or
    /// `nil` while paused.
    func beginLoopTick() -> LoopTick? {
        guard !world.clock.isPaused else { return nil }
        return LoopTick(
            world: world, revision: worldRevision, listening: playSound != nil, train: selectedTrainID, language: language,
            previousTraffic: trafficMemo?.reading,
            advice: AdviceProbe(hour: newsWatch.hour, leader: lineLossLeaderMemo.kept(atRevision: commandRevision))
        )
    }

    // MARK: - Traffic control on the map (decision 64)

    /// What the map draws of traffic control (``GameCore/GameWorld/trafficOverlay()``)
    /// for the world as it is now: read with the tick that made it, off
    /// the main actor, or else (after a command) here, once.
    public var trafficOverlay: TrafficOverlay {
        trafficReading().overlay
    }

    /// ``GameCore/GameWorld/routeWaitText(of:in:)`` of the world as it is
    /// now, in ``language``: the selected train's read with the tick, and
    /// none searched for a train the tick's reading shows waits for nothing.
    public func routeWaitText(of id: TrainID) -> String? {
        var reading = trafficReading()
        let text = reading.waitText(of: id, in: world, language: language)
        trafficMemo = (worldRevision, reading)
        return text
    }

    private func trafficReading() -> TrafficReading {
        if let memo = trafficMemo, memo.revision == worldRevision { return memo.reading }
        let reading = TrafficReading(world: world, in: language)
        trafficMemo = (worldRevision, reading)
        return reading
    }

    /// Ends `tick` with what ``LoopTick/work()`` made of it: the world
    /// after it, as ``advance(realElapsed:)`` would make it. A command
    /// since the tick began (an edit, an undo, a pause, a speed) changed
    /// the world it was worked out from, so the tick is dropped and the
    /// game falls behind by it, the command standing as the player made
    /// it on the world they saw. Returns whether the tick was taken.
    @discardableResult
    func finish(_ tick: LoopTick, with outcome: Result<TickStep, GameError>) -> Bool {
        guard tick.revision == worldRevision else { return false }
        FrameCostMeter.shared.measure(.afterStep) { finish(outcome, fromLoop: true) }
        return true
    }

    /// Starts advancing the world in real time. Calling it while the loop is
    /// already running does nothing, so the world is never ticked twice.
    ///
    /// Each tick is worked out off the main actor (decision 143), so a slow
    /// tick never stops the screen: the map, gestures and commands go on,
    /// on the world as it was before the tick, until the tick is done. One
    /// tick is worked out at a time and shown as soon as it is done. A step
    /// still turns at most ``maximumStepDuration`` into ticks, and the time
    /// spent working them out counts as elapsed, so when ticks take longer
    /// than ``tickInterval`` the game runs slower than its speed instead of
    /// piling up ticks to catch up.
    public func startGameLoop() {
        guard gameLoop == nil else { return }
        tickAccumulator.reset()
        gameLoop = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while true {
                // Sleeping only paces the loop; the ticks come from measured time.
                do {
                    try await Task.sleep(for: GameSession.tickInterval, clock: clock)
                } catch {
                    return
                }
                // A stop that arrives while this task waits to resume must
                // not let one more step through.
                guard !Task.isCancelled, let self else { return }
                let now = clock.now
                let elapsed = now - last
                let ticks = self.dueTicks(realElapsed: elapsed)
                last = now
                for index in 0..<ticks {
                    guard var tick = self.beginLoopTick() else { break }
                    tick.readsTraffic = index == ticks - 1
                    let outcome = await tick.work()
                    // Nor may a stop while the tick was worked out.
                    guard !Task.isCancelled else { return }
                    self.finish(tick, with: outcome)
                    // Decision 330: the world the tick replaced is let go
                    // here, timed for the map's frame readout.
                    let releasing = ContinuousClock.now
                    _ = consume tick
                    FrameCostMeter.shared.record(.release, since: releasing)
                    if case .failure = outcome { break }
                }
                // Decision 195: how fast the game really ran.
                self.noteRealTime(elapsed)
            }
        }
    }

    /// Stops the loop and drops any partial tick. The host calls this when the
    /// app leaves the foreground; restarting later does not replay the time
    /// spent away.
    public func stopGameLoop() {
        gameLoop?.cancel()
        gameLoop = nil
        tickAccumulator.reset()
        // The time away is not time the game failed to run.
        speedMeter.reset()
    }

    // MARK: - Trains

    /// The selected train as the world has it now, or `nil` if none is
    /// selected. Its position, rate and continuation are always GameCore's;
    /// the session never keeps a copy.
    public var selectedTrain: Train? {
        selectedTrainID.flatMap { world.train(id: $0) }
    }

    /// The selected train's rate as GameCore has it (0 without a selected
    /// train). Setting it calls ``setSelectedTrainRate(_:)``, so a control
    /// bound to it never holds a rate of its own. A slider bound to it
    /// brackets each drag with ``beginEditGesture()`` and
    /// ``endEditGesture()`` (its `onEditingChanged`), so one drag is one
    /// edit to undo.
    public var selectedTrainRate: Int64 {
        get { selectedTrain?.movement.rate ?? 0 }
        set { setSelectedTrainRate(newValue) }
    }

    /// Chooses the heading for the next placement. Never changes the world.
    public func setPlacementHeading(_ heading: CompassHeading) {
        placementHeading = heading
    }

    /// Buys a train through `GameWorld.purchaseTrain(named:)`, which charges
    /// its cost and allocates its ID, and selects it. It is not on the track
    /// until it is placed.
    public func purchaseTrain() {
        let bought = perform(.purchaseTrain(name: Self.suggestedTrainName(for: world, in: language))) { outcome, _, _ in
            let name = outcome.train?.name ?? ""
            return language.text("Bought \(name). Select a station to place it.", "已購買 \(name)。請選擇要放置它的車站。")
        }
        if let purchased = bought?.train?.id {
            selectedTrainID = purchased
            tappedTrainID = purchased
        }
    }

    /// Sells train `id` back through `GameWorld.sellTrain(_:)` (decision
    /// 180): 70 % of its books, and only a train off its lines. Decision
    /// 327: one on the track is stopped and taken off it first. A sold
    /// train that was selected or followed is let go.
    public func sellTrain(_ id: TrainID) {
        guard let train = world.train(id: id) else { return }
        let quote = world.trainSaleQuote(id)
        guard perform(.sellTrainWhereItStands(id), message: { _, _, _ in
            language.text("Sold \(train.name) for \(quote.moneyText).", "已出售 \(train.name)，取得 \(quote.moneyText)。")
        }) != nil else { return }
        if selectedTrainID == id { selectedTrainID = world.trains.first?.id }
        if tappedTrainID == id { tappedTrainID = nil }
    }

    /// Puts the selected train on a platform of the selected station on
    /// the track network (Stage C1; see ``place(_:atPlatformOf:)``).
    public func placeSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station to place \(train.name) at.", "請選擇要放置 \(train.name) 的車站。"))
            return
        }
        guard !world.trackPlatforms(of: station.id).isEmpty else {
            message = StatusMessage(kind: .failure, text: language.text(
                "\(station.name) has no platform yet. Add one with the network tool.",
                "\(station.name) 還沒有月台。請用路網工具加上月台。"
            ))
            return
        }
        place(train, atPlatformOf: station)
    }

    /// Sets how many cars the selected train has through
    /// `GameWorld.setTrainCars(_:to:)`: only while it is off the track.
    public func setSelectedTrainCars(_ cars: Int) {
        guard let train = requireSelectedTrain() else { return }
        perform(.setTrainCars(train.id, cars: cars)) { _, before, world in
            let balance = before.economy.balance
            let count = Train.carsText(cars, in: language)
            // Added cars are paid for (decision 46).
            let paid = balance - world.economy.balance
            guard paid > .zero else { return language.text("\(train.name) now has \(count).", "\(train.name) 現在有 \(count)。") }
            return language.text("\(train.name) now has \(count), for \(paid.moneyText).", "\(train.name) 現在有 \(count)，花費 \(paid.moneyText)。")
        }
    }

    /// Renames the selected station through `GameWorld.renameStation(_:to:)`.
    public func renameSelectedStation(to name: String) {
        guard let station = selectedStation else { return }
        perform(.renameStation(station.id, name: name)) { _, _, _ in
            language.text("Renamed \(station.name) to \(name).", "已將 \(station.name) 更名為 \(name)。")
        }
    }

    /// Renames the selected line through `GameWorld.renameLine(_:to:)`.
    public func renameSelectedLine(to name: String) {
        guard let line = requireSelectedLine() else { return }
        perform(.renameLine(line.id, name: name)) { _, _, _ in
            language.text("Renamed \(line.name) to \(name).", "已將 \(line.name) 更名為 \(name)。")
        }
    }

    /// Sets the selected line's colour through
    /// `GameWorld.setLineColor(_:to:)`; `nil` gives back the app's pick.
    public func setSelectedLineColor(_ color: LineColor?) {
        guard let line = requireSelectedLine() else { return }
        perform(.setLineColor(line.id, color)) { _, _, _ in
            language.text("\(line.name) has a new colour.", "\(line.name) 換了顏色。")
        }
    }

    /// Sets the selected line's code (decision 216) through
    /// `GameWorld.setLineCode(_:to:)`: `text` as ``LineBadge/code(from:)``
    /// reads it, or the app's own for a blank one. Text that is no code
    /// changes nothing and says why.
    public func setSelectedLineCode(_ text: String) {
        guard let line = requireSelectedLine() else { return }
        let code = LineBadge.code(from: text)
        guard code != nil || LineBadge.isBlank(text) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "A line code is one to three letters A–Z or digits.",
                "線號是一到三個英文字母或數字。"
            ))
            return
        }
        perform(.setLineCode(line.id, code)) { _, _, _ in
            code.map { language.text("\(line.name) is now \($0.text).", "\(line.name) 的線號改為 \($0.text)。") }
                ?? language.text("\(line.name) has its own code again.", "\(line.name) 改回自動線號。")
        }
    }

    /// Borrows one ``CompanyAccounts/loanStep`` through
    /// `GameWorld.borrow(_:)` (decision 67).
    public func borrowLoanStep() {
        perform(.borrow(CompanyAccounts.loanStep)) { _, _, _ in
            language.text("Borrowed \(CompanyAccounts.loanStep.moneyText).", "借入 \(CompanyAccounts.loanStep.moneyText)。")
        }
    }

    /// Repays one ``CompanyAccounts/loanStep`` through
    /// `GameWorld.repayLoan(_:)` (decision 67).
    public func repayLoanStep() {
        perform(.repayLoan(CompanyAccounts.loanStep)) { _, _, _ in
            language.text("Repaid \(CompanyAccounts.loanStep.moneyText).", "償還 \(CompanyAccounts.loanStep.moneyText)。")
        }
    }

    /// Sets the type of the selected train's cars through
    /// `GameWorld.setTrainType(_:to:)` (`nil`: the standard car): only while
    /// it is off the track. A train still running as standard that is given a
    /// type with its own way of running (the high-speed set, decision 168)
    /// runs that way, in the same edit; and so does the line it is assigned
    /// to, if it runs high-speed sets and nothing else.
    public func setSelectedTrainType(_ type: TrainType?) {
        guard let train = requireSelectedTrain() else { return }
        perform(.setTrainType(train.id, type)) { outcome, before, world in
            let balance = before.economy.balance
            let text = Train.typeText(type, in: language)
            var said = language.text("\(train.name) now has \(text).", "\(train.name) 現在是 \(text)。")
            // Decision 180: a change of type is a refit, paid for.
            let refit = balance - world.economy.balance
            if refit > .zero {
                said += language.text(" The refit cost \(refit.moneyText).", "改裝費 \(refit.moneyText)。")
            }
            if outcome.highSpeed, let id = world.assignedLine(of: train.id), let line = world.line(id: id) {
                said += language.nowHighSpeedText(line.name)
            }
            return said
        }
    }

    /// Sets the selected train's rate through
    /// `GameWorld.setTrainMovementRate(_:to:)`. Like a speed change, a new
    /// rate is shown by the control itself rather than announced; a rejected
    /// one is reported.
    public func setSelectedTrainRate(_ rate: Int64) {
        guard let train = requireSelectedTrain() else { return }
        do throws(GameError) {
            try performCommand(.edit(.setTrainRate(train.id, rate: rate)))
        } catch {
            message = refusal(error)
        }
    }

    /// An explicit operational hold, separate from the configured km/h speed.
    public func holdSelectedTrain() {
        setSelectedTrainRate(0)
    }

    public func resumeSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        perform(.resumeTrain(train.id)) { _, _, _ in
            language.text("Resumed \(train.name).", "已恢復 \(train.name) 運行。")
        }
    }

    /// Sends the selected train to the selected station: to where it stops
    /// at one of the station's platforms on the track network that it
    /// fits, along `GameWorld.path(from:toStation:length:)`, committed
    /// unchanged with `GameWorld.setTrainContinuation(_:along:stoppingAt:)`
    /// (Stage S5). Both run against the same world within this one call,
    /// with nothing in between, so the path can never be stale. The session
    /// never finds or edits a path itself.
    ///
    /// Without a path (no platform as long as the train that it can reach
    /// without turning back) nothing changes, and the train keeps the path
    /// it had.
    public func sendSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select the station to send \(train.name) to.", "請選擇 \(train.name) 要前往的車站。"))
            return
        }
        guard let position = train.position else {
            message = StatusMessage(kind: .failure, text: GameError.trainNotPlaced(train.id).playerMessage(in: language))
            return
        }
        guard let path = world.path(from: position, toStation: station.id, length: train.length) else {
            message = StatusMessage(
                kind: .failure,
                text: language.text(
                    "No route for \(train.name) to \(station.name): it needs a platform on the track network as long as the train, that it can reach without turning back. Its path is unchanged.",
                    "\(train.name) 沒有路可以到 \(station.name)：路網上要有不短於列車、而且不折返就能到達的月台。路徑沒有改變。"
                )
            )
            return
        }
        perform(.sendTrain(train.id, along: path.traversals.map(PlayerCommand.Edit.Step.init), stoppingAt: path.end)) { _, _, _ in
            let sent = path.distance == 0
                ? language.text("\(train.name) stops at \(station.name).", "\(train.name) 停在 \(station.name)。")
                : language.text(
                    "Sent \(train.name) to \(station.name), \(NetworkBuilding.distanceText(path.distance, in: language)) along the track.",
                    "已派 \(train.name) 前往 \(station.name)，沿軌道 \(NetworkBuilding.distanceText(path.distance, in: language))。"
                )
            return sent
        }
    }

    /// Turns the selected train around where it stands through
    /// `GameWorld.reverseTrain(_:)`, which also clears its continuation.
    public func reverseSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        perform(.reverseTrain(train.id)) { _, _, _ in
            language.text("Reversed \(train.name); its path was cleared.", "\(train.name) 已反向，路徑已清除。")
        }
    }

    /// Takes the selected train off the track through
    /// `GameWorld.unplaceTrain(_:)`, which also clears its rate and path.
    public func unplaceSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        // Follow ends only once the train is off the track (``perform``
        // checks): a refused command leaves it where it was, still followed.
        perform(.unplaceTrain(train.id)) { _, _, _ in
            language.text("Took \(train.name) off the track.", "已將 \(train.name) 移出軌道。")
        }
    }

    /// The selected train, or `nil` after reporting that there is none.
    func requireSelectedTrain() -> Train? {
        guard let id = selectedTrainID else {
            message = StatusMessage(kind: .failure, text: language.text("Buy a train first.", "請先購買列車。"))
            return nil
        }
        guard let train = world.train(id: id) else {
            message = StatusMessage(kind: .failure, text: GameError.unknownTrain(id).playerMessage(in: language))
            return nil
        }
        return train
    }

    // MARK: - Lines

    /// The selected line as the world has it now, or `nil` if none is
    /// selected (or it was removed).
    public var selectedLine: ServiceLine? {
        selectedLineID.flatMap { world.line(id: $0) }
    }

    /// Chooses the line the line panel shows. Never changes the world; an
    /// ID the world does not have is ignored.
    public func selectLine(_ id: LineID) {
        guard id != selectedLineID, world.line(id: id) != nil else { return }
        selectedLineID = id
        message = nil
    }

    /// Adds the selected station to the end of the new line's stops. Never
    /// changes the world.
    public func addSelectedStationToLineDraft() {
        guard let station = selectedStation else {
            message = StatusMessage(
                kind: .failure,
                text: language.text("Select a station on the map to add it to the new line.", "請在地圖上選擇車站，加到新路線。")
            )
            return
        }
        appendToLineDraft(station.id)
    }

    /// Adds station `id` to the end of the new line's stops, unless it is
    /// already the last.
    /// Adds station `id` to the new line's stops; returns whether it did.
    @discardableResult
    private func appendToLineDraft(_ id: StationID) -> Bool {
        guard let station = world.station(id: id) else { return false }
        guard lineDraft.last != station.id else {
            message = StatusMessage(
                kind: .failure,
                text: language.text(
                    "\(station.name) is already the last stop. A line cannot call at the same station twice in a row.",
                    "\(station.name) 已經是最後一站。路線不能連續兩次停靠同一站。"
                )
            )
            return false
        }
        lineDraft.append(station.id)
        refreshLineDraftRoute()
        message = nil
        return true
    }

    /// Drops the last stop picked for the new line.
    public func removeLastLineDraftStop() {
        guard !lineDraft.isEmpty else { return }
        lineDraft.removeLast()
        refreshLineDraftRoute()
    }

    public func clearLineDraft() {
        lineConfirmation = nil
        lineDraft = []
        lineDraftStopping = .everyStation
        lineDraftSkipped = []
        isPickingLineStops = false
        refreshLineDraftRoute()
    }

    /// Starts adding the stations tapped on the map (``tapMap(at:reach:)``)
    /// to the new line (decision 100). The app sends map taps there while
    /// the lines panel is open, whichever tool is chosen. `announces`:
    /// whether the status line says how; the tutorial's lines panel starts
    /// picking by itself, its card saying it (decision 188).
    public func startPickingLineStops(announces: Bool = true) {
        isPickingLineStops = true
        guard announces else { return }
        message = StatusMessage(
            kind: .success,
            text: language.text(
                "Tap the line's first station on the map, then its last. Tap a station between to choose the way.",
                "在地圖上點路線的起點，再點終點。有分岔時，點中間的車站指定經過哪裡。"
            )
        )
    }

    /// Starts a new line at the selected station (decision 112): a new
    /// draft with it as the first stop, and the next station tapped on the
    /// map as the next. A draft already begun is dropped. Never changes
    /// the world.
    public func startLineFromSelectedStation() {
        guard let station = selectedStation else {
            addSelectedStationToLineDraft()
            return
        }
        clearLineDraft()
        appendToLineDraft(station.id)
        isPickingLineStops = true
        message = StatusMessage(
            kind: .success,
            text: language.text(
                "The line starts at \(station.name). Tap its last station on the map.",
                "路線從\(station.name)出發。在地圖上點它的終點站。"
            )
        )
    }

    /// Stops adding tapped stations to the new line; the draft stays.
    public func stopPickingLineStops() {
        isPickingLineStops = false
    }

    /// Leaves station `id` out of the new line, or puts it back
    /// (``LineDraftStopping/custom``). The two ends are always called at.
    public func toggleLineDraftStop(_ id: StationID) {
        guard let route = lineDraftRoute, id != route.first, id != route.last else { return }
        lineDraftStopping = .custom
        if lineDraftSkipped.contains(id) {
            lineDraftSkipped.remove(id)
        } else {
            lineDraftSkipped.insert(id)
        }
    }

    /// The stops the new line will call at, in order: the stations along
    /// the track as ``lineDraftStopping`` chooses them, or the picked
    /// stations when no track joins them (``lineDraftRoute`` is `nil`).
    public var lineDraftStops: [StationID] {
        guard let route = lineDraftRoute else { return lineDraft }
        switch lineDraftStopping {
        case .everyStation:
            return route
        case .pickedStations:
            return lineDraft
        case .custom:
            return route.enumerated().filter { index, station in
                index == 0 || index == route.count - 1 || !lineDraftSkipped.contains(station)
            }.map(\.element)
        }
    }

    /// Finds ``lineDraftRoute`` again; a station skipped that is no
    /// longer on it is forgotten.
    func refreshLineDraftRoute() {
        let route = world.stationsAlongTrack(through: lineDraft)
        if route != lineDraftRoute { lineDraftRoute = route }
        let gap = route == nil ? world.lineDraftGap(through: lineDraft) : nil
        if gap != lineDraftGap { lineDraftGap = gap }
        let along = Set(route ?? [])
        if !lineDraftSkipped.isSubset(of: along) { lineDraftSkipped.formIntersection(along) }
    }

    /// Creates a line calling at ``lineDraftStops``, in order, through
    /// `GameWorld.createLine(named:stops:)`, and selects it. The draft is
    /// kept when GameCore refuses the stops.
    ///
    /// Where the stops are on a real line (``realLine(calling:)``), the new
    /// line starts with that line's peak and off-peak headways as its
    /// targets (``realTargetHeadways(of:inSystem:)``), through
    /// `GameWorld.setLineTargetHeadways(_:to:pattern:)` in the same step.
    ///
    /// `card`: the confirmation card's settings (decision 303), which set
    /// the line's name, colour, hours and trains at each time of day.
    public func createLineFromDraft(as card: LineConfirmation? = nil) {
        refreshLineDraftRoute()
        let stops = lineDraftStops
        let real = realLine(calling: stops).flatMap { match in
            realTargetHeadways(of: match.line, inSystem: match.system).map { (name: match.line.name, targets: $0) }
        }
        // Decision 264: under simple rules the line comes with its first
        // train, and the passing loop its single track needs.
        let name = Self.suggestedLineName(for: world, in: language)
        let planned = card.map { lineConfirmationPlan($0, stops: stops, targets: real?.targets) }
            ?? autoServicePlan(creating: name, stops: stops, targets: real?.targets).flatMap({ feasible($0) })
        if runsLinesForThePlayer, let found = planned {
            let plan = found.plan
            let balance = world.economy.balance
            let made = perform(.autoService(plan)) { outcome, _, world in
                guard let id = outcome.line?.id else { return "" }
                return Self.autoServiceText(
                    plan, outcome: outcome, line: id, cost: Money(balance.amount - world.economy.balance.amount), in: world, language: language,
                    loopWaits: found.trainInTheWay
                )
            }
            if let created = made?.line?.id {
                selectedLineID = created
                clearLineDraft()
            }
            return
        }
        let made = perform(.createLine(name: name, stops: stops, targets: real?.targets)) { outcome, _, _ in
            let name = outcome.line?.name ?? ""
            var detail = ""
            if let real {
                let levels = [(ServiceLevel.peak, real.targets.peak), (.offPeak, real.targets.offPeak)].compactMap { level, minutes in
                    minutes.map { "\(level.title(in: language)) \(headwayText(minutes: $0, in: language).lowercased())" }
                }.joined(separator: language.text(", ", "、"))
                detail = language.text(" Target headways from \(real.name): \(levels).", "目標班距依 \(real.name)：\(levels)。")
            }
            return language.text(
                "Created \(name) with \(stops.count) stops. Set how many trains it runs.",
                "已建立 \(name)，共 \(stops.count) 站。請設定上線列車數。"
            ) + detail
        }
        if let created = made?.line?.id {
            selectedLineID = created
            clearLineDraft()
        }
    }

    /// Removes the selected line through `GameWorld.removeLine(_:)` and
    /// sells its trains (decision 327), so none is left on the track.
    public func removeSelectedLine() {
        guard let line = requireSelectedLine() else { return }
        let followsLineTrain = followedTrainID.map { world.assignedLine(of: $0) == line.id } ?? false
        let sale = world.lineRemovalSale(line.id)
        let removed = perform(.removeLineSellingTrains(line.id)) { _, _, _ in
            guard sale.trains > 0 else { return language.text("Removed \(line.name).", "已刪除 \(line.name)。") }
            return language.text(
                "Removed \(line.name) and sold its \(sale.trains) \(sale.trains == 1 ? "train" : "trains") for \(sale.proceeds.moneyText).",
                "已刪除 \(line.name)，並賣掉它的 \(sale.trains) 列車，取得 \(sale.proceeds.moneyText)。"
            )
        }
        // The reference removes a line's trains with it, which ends
        // following one of them (`trackedTrainId` of a gone train).
        if removed != nil && followsLineTrain {
            followedTrainID = nil
            updateFollowSounds()
        }
        selectedLineID = world.lines.first?.id
    }

    /// One directed leg of the selected service: replace or clear its
    /// preference through the world's atomic command.
    public func setSelectedLineRoute(from: Int, to: Int, preference: LineRoutePreference?, pattern: Int? = nil) {
        guard let line = requireSelectedLine() else { return }
        var routes = pattern.flatMap { line.patterns.indices.contains($0) ? line.patterns[$0].routePreferences : nil } ?? line.routePreferences
        routes.removeAll { $0.from == from && $0.to == to }
        if let preference { routes.append(preference) }
        let chosen = routes
        let done = perform(.setLineRoutes(line.id, chosen, pattern: pattern)) { _, _, _ in
            language.text("Updated the tracks the line takes between these stops.", "已更新路線在這兩站之間走的軌段。")
        }
        // Decision 201: the map shows the leg as the trains now take it.
        if done != nil { previewRoute(from: from, to: to, pattern: pattern) }
    }

    /// Runs the selected line all day, or from 06:00 to midnight.
    public func setSelectedLineAllDay(_ allDay: Bool) {
        guard let line = requireSelectedLine() else { return }
        perform(.setLineWindow(line.id, allDay ? .allDay : .standard)) { _, _, _ in
            allDay
                ? language.text("\(line.name) runs all day.", "\(line.name) 全天營運。")
                : language.text("\(line.name) runs from 06:00 to midnight.", "\(line.name) 從 06:00 營運到午夜。")
        }
    }

    /// Makes the selected line a ring, its trains going on from its last
    /// stop back to the first, half of them each way round (decision 49),
    /// or a line that turns round at its ends again. A ring runs its trains
    /// in pairs: GameCore makes its counts even, down.
    public func setSelectedLineRing(_ isRing: Bool) {
        guard let line = requireSelectedLine(), line.isRing != isRing else { return }
        perform(.setLineRing(line.id, isRing)) { _, _, _ in
            isRing
                ? language.text(
                    "\(line.name) is a ring: its trains go on from the last stop to the first, half of them each way round.",
                    "\(line.name) 改為環線：列車從最後一站接著開回第一站，一半依站序、一半反方向。"
                )
                : language.text("\(line.name) turns round at its ends again.", "\(line.name) 改回在兩端折返。")
        }
    }

    /// Sets how many trains a service of the selected line runs at `level`
    /// (its own for `pattern` `nil`), keeping the other levels. How many it
    /// can run is derived; see ``GameWorld/lineServiceSummaries(_:)``. A
    /// ring's count is made even, down (decision 49).
    public func setSelectedLineTrains(_ count: Int, at level: ServiceLevel, pattern: Int? = nil) {
        guard let line = requireSelectedLine() else { return }
        let current = pattern.flatMap { line.patterns.indices.contains($0) ? line.patterns[$0].trainsInService : nil } ?? line.trainsInService
        var counts = current
        switch level {
        case .peak: counts.peak = count
        case .offPeak: counts.offPeak = count
        case .low: counts.low = count
        }
        let changed = counts
        perform(.setLineTrains(line.id, changed, pattern: pattern)) { _, _, _ in
            language.text(
                "\(line.name): \(count) \(count == 1 ? "train" : "trains") at \(level.title(in: language).lowercased()).",
                "\(line.name)：\(level.title(in: language))上線 \(count) 列。"
            )
        }
    }

    /// Sets or clears a service's target headway at `level`, keeping the
    /// other levels.
    public func setSelectedLineTargetHeadway(_ minutes: Int64?, at level: ServiceLevel, pattern: Int? = nil) {
        guard let line = requireSelectedLine() else { return }
        let current = pattern.flatMap { line.patterns.indices.contains($0) ? line.patterns[$0].targetHeadways : nil } ?? line.targetHeadways
        var targets = current
        switch level {
        case .peak: targets.peak = minutes
        case .offPeak: targets.offPeak = minutes
        case .low: targets.low = minutes
        }
        let changed = targets
        perform(.setLineTargets(line.id, changed, pattern: pattern)) { _, _, _ in
            let levelName = level.title(in: language)
            switch language {
            case .english:
                let what = minutes.map { headwayText(minutes: $0, in: language).lowercased() } ?? "the train count"
                return "\(line.name) at \(levelName.lowercased()): \(what)."
            case .traditionalChinese:
                let what = minutes.map { headwayText(minutes: $0, in: language) } ?? "依上線列車數"
                return "\(line.name)：\(levelName)\(what)。"
            }
        }
    }

    /// Adds a pattern to the selected line from stop `first` to stop
    /// `last` (indices into its stops): calling at every stop between, a
    /// short working, or at the two ends only, an express.
    public func addPatternToSelectedLine(from first: Int, to last: Int, express: Bool) {
        guard let line = requireSelectedLine() else { return }
        let calls = express ? [first, last] : (first <= last ? Array(first...last) : [first, last])
        perform(.addLinePattern(line.id, calls: calls)) { outcome, _, world in
            let index = outcome.number
            let title = world.serviceTitle(of: world.line(id: line.id)!, calls: calls, in: language)
            return language.text(
                "Added \(title) to \(line.name) as pattern \(index + 1).",
                "已在 \(line.name) 加入\(title)（停站模式 \(index + 1)）。"
            )
        }
    }

    /// Removes the selected line's pattern at `index`; its trains finish
    /// the trip they are on.
    public func removePatternFromSelectedLine(_ index: Int) {
        guard let line = requireSelectedLine() else { return }
        perform(.removeLinePattern(line.id, index: index)) { _, _, _ in
            language.text("Removed pattern \(index + 1) from \(line.name).", "已從 \(line.name) 刪除停站模式 \(index + 1)。")
        }
    }

    /// Assigns the selected train to a service of the selected line (its
    /// own for `pattern` `nil`), which sends it out from the service's first
    /// stop once it waits there.
    ///
    /// A new line runs no trains at any level and has no target headways,
    /// so a train assigned to it would never leave: when the service runs
    /// none, it is set to run its assigned trains at every level (a ring's
    /// count made even, up, as each way needs one).
    public func assignSelectedTrainToSelectedLine(pattern: Int? = nil) {
        guard let train = requireSelectedTrain(), let line = requireSelectedLine() else { return }
        assign(train, to: line, pattern: pattern)
    }

    /// Assigns train `trainID` to a service of line `lineID` (its own for
    /// `pattern` `nil`), as ``assignSelectedTrainToSelectedLine(pattern:)``
    /// does: the train
    /// card's line menu and the line panel's menu of trains without a
    /// line (TestFlight 54.1).
    public func assignTrain(_ trainID: TrainID, toLine lineID: LineID, pattern: Int? = nil) {
        guard let train = world.train(id: trainID) else {
            message = StatusMessage(kind: .failure, text: GameError.unknownTrain(trainID).playerMessage(in: language))
            return
        }
        guard let line = world.line(id: lineID) else {
            message = StatusMessage(kind: .failure, text: GameError.unknownLine(lineID).playerMessage(in: language))
            return
        }
        assign(train, to: line, pattern: pattern)
    }

    private func assign(_ train: Train, to line: ServiceLine, pattern: Int?) {
        perform(.assignTrain(train.id, line.id, pattern: pattern)) { outcome, _, world in
            let fast = outcome.highSpeed, started = outcome.number
            let service = world.assignedServiceName(of: train.id, in: language) ?? line.name
            var text = language.text(
                "\(train.name) now runs for \(service). It leaves once it waits at the first stop.",
                "\(train.name) 現在為 \(service) 服務。它在第一站等候後就會出發。"
            )
            if fast { text += language.nowHighSpeedText(line.name) }
            // A line outside its window sends nobody out until it opens.
            let opens: String
            if let assigned = world.line(id: line.id), world.serviceLevel(of: line.id, at: world.clock.now) == nil,
               case .hours(let open, _) = assigned.window {
                let time = clockText(minuteOfDay: open % 1_440)
                opens = language.text(" \(line.name) opens at \(time).", "\(line.name) \(time) 開始營運。")
            } else {
                opens = ""
            }
            // Decision 284: a train too long for a call never leaves; say
            // so, last, as it is assigned.
            let tooLong = world.shortPlatformCall(ofTrain: train.id).map { short in
                language.text(" ", "") + world.shortPlatformText(short, in: language) + language.text(".", "。")
            } ?? ""
            // TestFlight 60.1: a line already running trains keeps its
            // counts, so the new train would wait: say so, and how.
            if started == 0, let unused = world.lineUnusedTrains(ofTrain: train.id) {
                let now = unused.busiest
                return text + opens + language.text(
                    " \(service) is set to run \(now) \(now == 1 ? "train" : "trains"): tap Run \(unused.target) on the train card, or set it in the Lines panel.",
                    "\(service) 只設定上線 \(now) 列：在列車卡按「加開到 \(unused.target) 列」，或在路線面板設定。"
                ) + tooLong
            }
            guard started > 0 else { return text + opens + tooLong }
            return text + opens + language.text(
                " \(service) ran no trains, so it now runs \(started) at every level.",
                "\(service) 原本沒有上線列車，現在各時段上線 \(started) 列。"
            ) + tooLong
        }
    }

    /// Takes the selected train off its line; a trip under way is finished.
    public func unassignSelectedTrain() {
        guard let train = requireSelectedTrain() else { return }
        unassignTrain(train.id)
    }

    /// Takes train `trainID` off its line, as ``unassignSelectedTrain()``
    /// does: the line card's "take off a train" (decision 194, later).
    public func unassignTrain(_ trainID: TrainID) {
        guard let train = world.train(id: trainID) else {
            message = StatusMessage(kind: .failure, text: GameError.unknownTrain(trainID).playerMessage(in: language))
            return
        }
        perform(.unassignTrain(train.id)) { _, _, _ in
            language.text("Took \(train.name) off its line. A trip under way is finished.", "已將 \(train.name) 移出路線。進行中的這一趟會跑完。")
        }
    }

    /// Starts the selected train's own timetable through
    /// `GameWorld.startTrainService(_:)`.
    public func startSelectedTrainService() {
        guard let train = requireSelectedTrain() else { return }
        perform(.startTrainService(train.id)) { _, _, _ in
            language.text("\(train.name) is running its timetable.", "\(train.name) 開始依時刻表運行。")
        }
    }

    /// Stops the selected train's service through
    /// `GameWorld.stopTrainService(_:)`; it keeps its timetable.
    public func stopSelectedTrainService() {
        guard let train = requireSelectedTrain() else { return }
        perform(.stopTrainService(train.id)) { _, _, _ in
            language.text("Stopped \(train.name)'s service. It stays where it is.", "已停止 \(train.name) 的服務。它會停在原地。")
        }
    }

    /// The selected line, or `nil` after reporting that there is none.
    func requireSelectedLine() -> ServiceLine? {
        guard let line = selectedLine else {
            message = StatusMessage(kind: .failure, text: language.text("Create or choose a line first.", "請先建立或選擇一條路線。"))
            return nil
        }
        return line
    }

    // MARK: - Actions

    /// Applies the current tool to the selection through the matching
    /// `GameWorld` command, and reports the outcome in ``message``.
    ///
    /// The session does not pre-check game rules: GameCore decides whether an
    /// action is allowed, and a rejected action leaves the world unchanged.
    /// Does nothing without a selection, in ``ConstructionTool/select``
    /// mode, or with the network tool, which acts on what its taps picked.
    public func applyTool() {
        guard selectedPoint != nil else { return }
        switch tool {
        case .select, .network, .building:
            return
        case .train:
            // The selected station is where an unplaced train goes, or
            // where a placed one is sent.
            if selectedTrain?.position == nil {
                placeSelectedTrain()
            } else {
                sendSelectedTrain()
            }
        }
    }

    public func dismissMessage() {
        message = nil
    }

    /// Clears the message posted as `serial` (``messageSerial``) if it is
    /// still the message (the banner's own timer,
    /// ``StatusMessage/autoDismissDelay``): a newer message stays, even
    /// one with the same text.
    public func dismissMessage(posted serial: UInt64) {
        if messageSerial == serial { message = nil }
    }

    /// The status line for `error`, which refused `command` on ``world``
    /// (left as it was). A refusal for want of cash names what `command`
    /// does (``PlayerCommand/actionText(in:)``), and says the whole
    /// command's price against the cash the player has (decision 245),
    /// not one step's price against what the steps before it left:
    /// GameCore builds a command step by step on a copy of the world, and
    /// refuses the first step the cash left does not cover. The price is
    /// `command` run again on a ``GameWorld/pricingCopy()``; refused there
    /// too, for something other than cash, that is what the line says.
    /// Without a command it is that step's price and all paid before it.
    /// The refusal goes once the cash covers it
    /// (``StatusMessage/fundsNeeded``).
    func refusal(_ error: GameError, doing command: PlayerCommand? = nil) -> StatusMessage {
        guard case .insufficientFunds(let required, let available) = error else {
            // Decision 327: a train left standing on no line is named, and
            // the banner offers to sell it.
            if let train = world.idleTrainInTheWay(of: error) {
                return StatusMessage(kind: .failure, text: language.text(
                    "\(train.name) is standing here with no line and is in the way. Sell it to clear the track.",
                    "\(train.name) 沒有路線，停在這裡擋住了。賣掉它就能拆除。"
                ), sellableTrain: train.id)
            }
            return StatusMessage(kind: .failure, text: error.playerMessage(in: language))
        }
        let balance = world.economy.balance
        let total: Money
        if let command {
            do throws(GameError) {
                total = try priced { world throws(GameError) in _ = try apply(command, to: &world) }.cost
            } catch {
                return refusal(error)
            }
        } else {
            let spent = max(0, balance.amount - available.amount)
            let (needed, overflow) = required.amount.addingReportingOverflow(spent)
            total = overflow ? Money(.max) : Money(needed)
        }
        return StatusMessage(
            kind: .failure,
            text: GameError.insufficientFundsText(
                required: total, available: balance, doing: command?.actionText(in: language), in: language
            ),
            fundsNeeded: total
        )
    }

    /// `build` run on a ``GameWorld/pricingCopy()`` of `base` (``world``
    /// unless given), which cash never stops (decision 245): the copy as
    /// built, what `build` returned, and what it cost in all. A preview
    /// builds on it, so its price is the whole build's even where the cash
    /// in hand would stop it part of the way (``shortfallText(_:doing:)``
    /// says so). Throws what refused `build` for anything else.
    func priced<Result>(
        on base: GameWorld? = nil, _ build: (inout GameWorld) throws(GameError) -> Result
    ) throws(GameError) -> (draft: GameWorld, result: Result, cost: Money) {
        var draft = (base ?? world).pricingCopy()
        let result = try build(&draft)
        return (draft, result, Money(GameWorld.pricingBalance.amount - draft.economy.balance.amount))
    }

    /// Why the cash in hand does not pay `cost`, the price of what
    /// `action` (``PlayerCommand/actionText(in:)``) does in all, or `nil`
    /// when it does (decision 245): a preview's problem, as the refusal
    /// will say it (``refusal(_:doing:)``).
    func shortfallText(_ cost: Money, doing action: PlayerCommand?) -> String? {
        guard !world.economy.canAfford(cost) else { return nil }
        return GameError.insufficientFundsText(
            required: cost, available: world.economy.balance, doing: action?.actionText(in: language), in: language
        )
    }

    /// Drops a refusal for want of cash that the cash now covers
    /// (``StatusMessage/fundsNeeded``): at speed the cash can pass it
    /// while the banner still shows it, and its figures are out of date.
    func retireCoveredShortfall() {
        if let needed = message?.fundsNeeded, world.economy.canAfford(needed) { message = nil }
    }

    /// Runs one command against the world through ``performEdit(_:)`` and
    /// records its outcome. Returns whether the command succeeded.
    @discardableResult
    func perform(_ command: (inout GameWorld) throws(GameError) -> String, caller: String = #function) -> Bool {
        do throws(GameError) {
            message = StatusMessage(kind: .success, text: try performEdit(command, caller: caller))
            endFollowIfGone()
            return true
        } catch {
            message = refusal(error)
            return false
        }
    }

    /// Runs `command` (decision 193) as ``perform(_:caller:)`` runs a
    /// closure, through ``apply(_:to:)``, and logs it in its place, refused
    /// or not. `text` says what it did, from its outcome and the world
    /// before and after. Returns its outcome, or `nil` when refused.
    @discardableResult
    func perform(
        _ command: PlayerCommand, message text: (PlayerCommand.Outcome, _ before: GameWorld, _ after: GameWorld) -> String
    ) -> PlayerCommand.Outcome? {
        let before = world
        do throws(GameError) {
            let outcome = try performCommand(command)
            message = StatusMessage(kind: .success, text: text(outcome, before, world))
            endFollowIfGone()
            return outcome
        } catch {
            message = refusal(error, doing: command)
            return nil
        }
    }

    /// Runs `command` through ``performEdit(_:caller:)`` and ``apply(_:to:)``
    /// and logs it in its place, refused or not (decision 193), saying
    /// nothing: for a function with messages of its own. Throws what
    /// refused it.
    @discardableResult
    func performCommand(_ command: PlayerCommand) throws(GameError) -> PlayerCommand.Outcome {
        do throws(GameError) {
            return try performEdit(logging: .command(command), whenUnchanged: true) { world throws(GameError) in
                try apply(command, to: &world)
            }
        } catch {
            log(.command(command), refused: true)
            throw error
        }
    }

    /// ``perform(_:message:)`` for an ``PlayerCommand/Edit``.
    @discardableResult
    func perform(
        _ edit: PlayerCommand.Edit, message text: (PlayerCommand.Outcome, _ before: GameWorld, _ after: GameWorld) -> String
    ) -> PlayerCommand.Outcome? {
        perform(.edit(edit), message: text)
    }

    /// Adds `action` to ``commandLog`` (decision 193), with the game time
    /// it came at (by default, now), after it changed ``world``.
    private func log(_ action: CommandLog.Action, at time: GameTime? = nil, refused: Bool = false) {
        commandLog.append(
            CommandLog.Entry(time: (time ?? world.clock.now).seconds, action: action, refused: refused), now: world, data: realWorldData
        )
    }

    /// Changes ``world`` by `change`, which ``commandLog`` keeps as
    /// `action` (decision 193).
    func logging(_ action: CommandLog.Action, _ change: (inout GameWorld) -> Void) {
        isLogging = true
        change(&world)
        isLogging = false
        log(action)
        // Decision 343: a pause or a change of speed starts or stops the
        // followed train's sound at once, not at the next step.
        updateFollowSounds()
    }

    /// What the weather's sound is worked out from (decision 346).
    private struct WeatherKey: Equatable {
        let day: Int64
        let disruptions: Disruptions?
    }

    /// Tells the app the sound of the weather the map shows
    /// (``WeatherSound``, decision 346) when it changed: worked out again
    /// on a new day or a change of the world's weather (after a step or an
    /// edit, ``endFollowIfGone()``), and when the app's player is set.
    func updateWeatherSound() {
        guard let weatherSound else { return }
        let key = WeatherKey(day: world.clock.now.seconds / GameTime.secondsPerDay, disruptions: world.disruptions)
        guard key != weatherKey else { return }
        weatherKey = key
        let sound = WeatherSound(weather: MapWeather(world: world))
        guard sound != lastWeatherSound else { return }
        lastWeatherSound = sound
        weatherSound(sound)
    }

    // MARK: - Editing and undo

    /// How many edits ``undo()`` can take back: MapBuilder's `B.I6` (25),
    /// the snapshots its `handleUndo` goes back through.
    public static let undoLimit = 25

    /// How many of those edits may have read land in (decision 88): each
    /// keeps a copy of a map's land and buildings, some 110 bytes a cell,
    /// 45 MB with a hundred stations on the whole of Taiwan and 220 MB with
    /// six hundred, so older edits are forgotten past three.
    public static let landReadingUndoLimit = 3

    /// The one way an edit changes the world (ARCHITECTURE decision 82):
    /// runs `command` on a copy of ``world`` and, only if it succeeds,
    /// keeps the world as it was for ``undo()`` and puts the copy in its
    /// place. A command that throws leaves the world and the undo history
    /// as they were, even after it changed part of its copy; one that
    /// succeeds without changing anything leaves no snapshot, so Undo never
    /// takes back nothing. Between ``beginEditGesture()`` and
    /// ``endEditGesture()`` only the first edit that changes the world keeps
    /// a snapshot: the world as it was when the drag began. The oldest
    /// snapshot goes once there are ``undoLimit``.
    ///
    /// Everything the player builds, removes or sets goes through it;
    /// pausing, the speed, the selection, the camera and the map layers do
    /// not, and are not edits. Returns what `command` returns, and throws
    /// what it throws: a `GameError` from a GameWorld command, or nothing
    /// for a command that cannot fail. It shows no message
    /// (``perform(_:)`` does).
    /// Reads in the land round every station whose land is not read yet,
    /// on a map whose land is read in as it is needed (decision 88, see
    /// ``readLand(roundStationsOf:population:places:water:)``). Every edit does
    /// it (``performEdit(_:)``), so a station's land comes with it and
    /// Undo takes both back; a game that starts does it for the stations
    /// built while the app had no population. Not an edit: nothing to undo.
    public func readLandRoundStations() {
        var read = world
        Self.readLand(roundStationsOf: &read, population: population, places: places, water: water, coverage: coverage)
        // Decision 193: the data's arrival is logged even when no land is
        // read, so a replay has it from then on.
        let data = realWorldData
        keepLand(of: read, as: .readLandRoundStations(data), evenUnchanged: data != commandLog.lastData)
    }

    /// The real-world data the session has now (decision 193).
    var realWorldData: RealWorldDataSet {
        RealWorldDataSet(
            population: population != nil, places: places != nil, water: water != nil, heights: heights != nil, coverage: coverage != nil
        )
    }

    /// Reads in the land within `reach` of `point` (decision 95: under a
    /// building's site), as ``readLandRoundStations()`` does round
    /// stations. Not an edit.
    func readLand(within reach: Int64, of point: PlanPoint) {
        var read = world
        Self.readLand(within: reach, of: [point], in: &read, population: population, places: places, water: water, coverage: coverage)
        keepLand(of: read, as: .readLand(reach: reach, at: point))
    }

    /// Takes `read`, the world with land read in, only if land was: any
    /// write drops the tick being worked out (decision 143), and on a map
    /// whose land is all there, or already read here, nothing is.
    private func keepLand(of read: GameWorld, as action: CommandLog.Action, evenUnchanged: Bool = false) {
        guard read.landBlocks != world.landBlocks else {
            if evenUnchanged { log(action) }
            return
        }
        logging(action) { $0 = read }
    }

    @discardableResult
    public func performEdit<Result, Failure: Error>(
        _ command: (inout GameWorld) throws(Failure) -> Result, caller: String = #function
    ) throws(Failure) -> Result {
        try performEdit(logging: .unrecorded(caller), whenUnchanged: false, command)
    }

    /// ``performEdit(_:caller:)``, logging the edit as `action` (decision
    /// 193); one that changes nothing too, `whenUnchanged`.
    private func performEdit<Result, Failure: Error>(
        logging action: CommandLog.Action, whenUnchanged: Bool, _ command: (inout GameWorld) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        var edited = world
        let result = try command(&edited)
        // Decision 88: a new station's land comes with it.
        Self.readLand(roundStationsOf: &edited, population: population, places: places, water: water, coverage: coverage)
        guard edited != world else {
            if whenUnchanged { log(action) }
            return result
        }
        // Decision 100: the new line's route follows the track.
        let trackChanged = lineDraft.count >= 2 && edited.network != world.network
        defer { if trackChanged { refreshLineDraftRoute() } }
        if !editGestureHasSnapshot {
            if undoHistory.count >= Self.undoLimit {
                undoHistory.removeFirst(undoHistory.count - Self.undoLimit + 1)
            }
            undoHistory.append(world)
            editGestureHasSnapshot = isEditGestureOpen
            forgetEditsPastTheLandReadingLimit(before: edited)
        }
        // Decision 184: a new edit ends the line Redo went forward along
        // (the simulator's push clears `future`).
        redoHistory.removeAll()
        let before = world
        logging(action) { $0 = edited }
        editSerial &+= 1
        // CTM study M2: a next step the edit met is answered at once.
        noteNextSteps(since: before)
        // Decision 298: a station built, moved or taken away by a real one.
        refreshTransfers()
        return result
    }

    /// Gives the stations `points` transfer points and every other none
    /// (decision 298), logged with the values so a replay needs no real
    /// railways. Not an edit: nothing to undo. Nothing when the world
    /// refuses them (``GameWorld/setTransfers(_:)``) or has them already.
    func applyTransfers(_ points: [StationID: Int64]) {
        var set = world
        guard (try? set.setTransfers(points)) != nil, set != world else { return }
        logging(.transfers(points)) { $0 = set }
    }

    /// Drops the oldest snapshots until at most ``landReadingUndoLimit``
    /// of the edits up to `latest` read land in (their land's blocks are
    /// not the next world's).
    private func forgetEditsPastTheLandReadingLimit(before latest: GameWorld) {
        guard latest.landBlocks != nil else { return }
        var reads = 0
        var next = latest
        for index in undoHistory.indices.reversed() {
            if undoHistory[index].landBlocks != next.landBlocks {
                reads += 1
                if reads > Self.landReadingUndoLimit {
                    undoHistory.removeFirst(index + 1)
                    return
                }
            }
            next = undoHistory[index]
        }
    }

    /// A drag of a control that edits as it moves (a slider's
    /// `onEditingChanged(true)`) begins: its edits until
    /// ``endEditGesture()`` are one edit to ``undo()``, which goes back to
    /// the world as it was when the drag began. A tick of game time during
    /// the drag empties the history as ever, and the drag's next change
    /// keeps a new snapshot.
    public func beginEditGesture() {
        isEditGestureOpen = true
        editGestureHasSnapshot = false
    }

    /// The drag ends (`onEditingChanged(false)`): each edit after it is
    /// one edit to undo again.
    public func endEditGesture() {
        isEditGestureOpen = false
        editGestureHasSnapshot = false
    }

    /// How many edits ``undo()`` could take back, one at a time, up to
    /// ``undoLimit``.
    public var undoCount: Int {
        undoHistory.count
    }

    /// Whether ``undo()`` has an edit to take back now: there is one since
    /// game time last moved, and no tutorial is on screen.
    public var canUndo: Bool {
        !undoHistory.isEmpty && tutorial == nil && !isLayingDemoRealLines
    }

    /// Takes back the latest edit (MapBuilder's `handleUndo`): the whole
    /// world goes back to the snapshot ``performEdit(_:)`` kept before it,
    /// money included, so what was built is refunded. Only the clock's
    /// speed stays as the player has it now, since pausing and the speed
    /// are not edits; game time is the snapshot's, which it still is (any
    /// tick empties the history). The selection and the drafts let go of
    /// stations, trains, lines, buildings and track the world no longer has.
    ///
    /// Refused, with a message, when there is nothing to take back, and
    /// while the tutorial is on screen: its steps compare the world with
    /// IDs it saw, and an undone station's ID is given to the next one, so
    /// Next could wait for a second station.
    public func undo() {
        guard tutorial == nil else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Undo is off during the tutorial.",
                "教學進行中無法復原。"
            ))
            return
        }
        guard !isLayingDemoRealLines else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Undo waits until the real lines are laid.",
                "真實路線鋪好後才能復原。"
            ))
            return
        }
        guard let restored = undoHistory.popLast() else {
            message = StatusMessage(kind: .failure, text: language.text("Nothing to undo.", "沒有可復原的編輯。"))
            return
        }
        // Decision 184: the edit taken back can be made again.
        redoHistory.append(world)
        if redoHistory.count > Self.undoLimit {
            redoHistory.removeFirst(redoHistory.count - Self.undoLimit)
        }
        step(to: restored, as: .undo)
        message = StatusMessage(kind: .success, text: language.text("Undid the last edit.", "已復原上一步編輯。"))
    }

    /// How many undone edits ``redo()`` could make again, one at a time.
    public var redoCount: Int {
        redoHistory.count
    }

    /// Whether ``redo()`` has an undone edit to make again now (decision
    /// 184): one was undone, no edit has been made since, game time has
    /// not moved, and no tutorial is on screen (the same rule as
    /// ``canUndo``).
    public var canRedo: Bool {
        !redoHistory.isEmpty && tutorial == nil && !isLayingDemoRealLines
    }

    /// Makes again the edit ``undo()`` last took back (decision 184, the
    /// simulator's redo, `future` → `past`): the world goes to what it was
    /// before that undo, money included, and the world it leaves is kept
    /// for ``undo()`` once more. The clock's speed and pause stay as the
    /// player has them, as Undo keeps them. Refused, with a message, when
    /// there is nothing to redo and during the tutorial.
    public func redo() {
        guard tutorial == nil else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Redo is off during the tutorial.",
                "教學進行中無法重做。"
            ))
            return
        }
        guard !isLayingDemoRealLines else { return }
        guard let restored = redoHistory.popLast() else {
            message = StatusMessage(kind: .failure, text: language.text("Nothing to redo.", "沒有可重做的編輯。"))
            return
        }
        undoHistory.append(world)
        if undoHistory.count > Self.undoLimit {
            undoHistory.removeFirst(undoHistory.count - Self.undoLimit)
        }
        step(to: restored, as: .redo)
        message = StatusMessage(kind: .success, text: language.text("Redid the edit.", "已重做編輯。"))
    }

    /// Puts `snapshot`, a world Undo or Redo goes to, in place of
    /// ``world``, keeping the clock's speed and pause as they are now, and
    /// lets go of what the selection names that it does not have.
    private func step(to snapshot: GameWorld, as action: CommandLog.Action) {
        var restored = snapshot
        // A drag still under way keeps a new snapshot at its next change.
        editGestureHasSnapshot = false
        restored.setSpeed(world.clock.runningSpeed)
        if world.clock.isPaused { restored.pause() }
        logging(action) { $0 = restored }
        editSerial &+= 1
        dropSelectionOfMissing()
        // The building shown keeps its land read in, which the undo may
        // have taken back, so its preview counts what stands there.
        if let site = buildingSite {
            readLand(within: Self.buildingLandReach, of: site)
        }
    }

    /// Lets go of what the selection and the drafts name that ``world``
    /// does not have (after ``undo()`` or a demolished station); keeps the
    /// rest.
    func dropSelectionOfMissing() {
        if let id = selectedStationID, world.station(id: id) == nil { selectedStationID = nil }
        if let id = platformStationID, world.station(id: id) == nil { platformStationID = nil }
        lineDraft.removeAll { world.station(id: $0) == nil }
        refreshLineDraftRoute()
        if let id = selectedTrainID, world.train(id: id) == nil { selectedTrainID = nil }
        if let id = tappedTrainID, world.train(id: id) == nil { tappedTrainID = nil }
        endFollowIfGone()
        if let id = selectedLineID, world.line(id: id) == nil { selectedLineID = nil }
        if let id = selectedTrackEdge, world.network.edge(id) == nil { selectedTrackEdge = nil }
        // Undo gives a building's ID out again: the next one is not this.
        if let id = selectedBuildingID, world.placedBuilding(id: id) == nil { selectedBuildingID = nil }
        if let id = saleCandidate, world.placedBuilding(id: id) == nil { saleCandidate = nil }
        func exists(_ anchor: NetworkAnchor?) -> Bool {
            switch anchor {
            case nil, .point: true
            case .node(let id): world.network.node(id) != nil
            case .track(let point): world.network.edge(point.edge) != nil
            }
        }
        if !exists(networkStart) { networkStart = nil }
        if !exists(networkEnd) { networkEnd = nil }
        if let point = networkEdgePoint, world.network.edge(point.edge) == nil { networkEdgePoint = nil }
    }

    /// How close a real railway station must be for a new station to be
    /// named after it (decision 159; 5 km before it): about a ten-minute
    /// walk, the reach of a station's riders. Farther away, a station 3 km
    /// from Taipei Main Station is not "Taipei", but named after the place
    /// it is in.
    nonisolated public static let realStationNamingDistanceMetres = 800.0

    /// A name for a new station at `location`:
    ///
    /// 1. On a real-world map, the nearest real railway station's name, if
    ///    within `maximumDistanceMetres` and not yet taken.
    /// 2. Then (decision 159, MapBuilder's naming after the place) the
    ///    nearest settlement's, village's or ward's name not yet taken
    ///    (``PlaceNames/nearby(_:)``), then the township's or district's
    ///    it is in (``PlaceNames/township(containing:)``). A name a real
    ///    station elsewhere has is never offered: that station may yet be
    ///    built.
    /// 3. Where they are all taken, the nearest of them with the side of
    ///    the station already so named that `location` is on, as Taiwan's
    ///    railways name a second station of a place: 北新竹, "North
    ///    Hsinchu".
    /// 4. "Station N" (or "車站 N") with the lowest N from the next station
    ///    number upward that no existing station uses; the only name on a
    ///    blank map.
    ///
    /// A real station is taken when a station of the world already is it,
    /// whatever language or system's spelling it was named in: 台北, 臺北,
    /// 台北車站, "Taipei" and "Taipei Main Station" near Taipei Main
    /// Station are one place (``RealRailways/stationKey(_:)``), so none of
    /// them is offered again once one is used. A place is taken when a
    /// station has its Chinese or English name, in the same sense.
    nonisolated public static func suggestedStationName(
        for world: GameWorld,
        at location: PlanPoint? = nil,
        in language: DisplayLanguage,
        railways: RealRailways? = nil,
        placeNames: PlaceNames? = nil,
        maximumDistanceMetres: Double = realStationNamingDistanceMetres
    ) -> String {
        let taken = Set(world.stations.map(\.name))
        if let location, let frame = RealWorldFrame(world: world) {
            func coordinate(_ point: PlanPoint) -> RealRailways.Coordinate {
                let coord = frame.coordinate(worldX: Double(point.x), worldY: Double(point.y))
                return RealRailways.Coordinate(latitude: coord.latitude, longitude: coord.longitude)
            }
            // Every name key of the stations of the world, and of the real
            // stations they are.
            var takenKeys = Set(taken.map(RealRailways.stationKey))
            if let railways {
                for station in world.stations {
                    for real in railways.stations(named: station.name, near: coordinate(station.location)) {
                        takenKeys.insert(RealRailways.stationKey(real.chinese))
                        if let english = real.english { takenKeys.insert(RealRailways.stationKey(english)) }
                    }
                }
                let candidates = railways.nearbyStations(to: coordinate(location), maximumDistanceMetres: maximumDistanceMetres)
                for candidate in candidates {
                    let name = candidate.station.name(in: language)
                    let keys = [candidate.station.chinese, candidate.station.english, name].compactMap { $0 }.map(RealRailways.stationKey)
                    if !taken.contains(name), keys.allSatisfy({ !takenKeys.contains($0) }) {
                        return name
                    }
                }
            }
            if let placeNames,
               let name = placeStationName(
                   at: location, coordinate(location), in: world, language: language, placeNames: placeNames, railways: railways,
                   taken: taken, takenKeys: takenKeys
               ) {
                return name
            }
        }
        return suggestedName(language.text("Station", "車站"), from: world.stations.count + 1, taken: taken)
    }

    /// Steps 2 and 3 of
    /// ``suggestedStationName(for:at:in:railways:placeNames:maximumDistanceMetres:)``.
    nonisolated private static func placeStationName(
        at location: PlanPoint, _ here: RealRailways.Coordinate, in world: GameWorld, language: DisplayLanguage,
        placeNames: PlaceNames, railways: RealRailways?, taken: Set<String>, takenKeys: Set<String>
    ) -> String? {
        var places = placeNames.nearby(here)
        if let township = placeNames.township(containing: here) {
            places.append(township)
        }
        // A real station's name is that station's, wherever it is. Only
        // the Chinese names tell: 中山 and 忠山 are both "Zhongshan".
        places.removeAll { railways?.stations(named: $0.chinese, near: nil).isEmpty == false }
        func isFree(_ name: String, keys: [String]) -> Bool {
            !taken.contains(name) && keys.allSatisfy { !takenKeys.contains(RealRailways.stationKey($0)) }
        }
        for place in places {
            let name = place.name(in: language)
            if isFree(name, keys: [place.chinese, place.english, name].compactMap { $0 }) {
                return name
            }
        }
        func distance(to point: PlanPoint) -> Double {
            let dx = Double(point.x - location.x), dy = Double(point.y - location.y)
            return dx * dx + dy * dy
        }
        for place in places {
            let keys = Set([place.chinese, place.english].compactMap { $0 }.map(RealRailways.stationKey))
            let namesake = world.stations
                .filter { keys.contains(RealRailways.stationKey($0.name)) }
                .min { distance(to: $0.location) < distance(to: $1.location) }
            guard let namesake else { continue }
            let dx = location.x - namesake.location.x, dy = location.y - namesake.location.y
            guard dx != 0 || dy != 0 else { continue }
            // The world's y runs south.
            let side: (english: String, chinese: String) = abs(dx) > abs(dy)
                ? (dx > 0 ? ("East", "東") : ("West", "西"))
                : (dy > 0 ? ("South", "南") : ("North", "北"))
            let chinese = side.chinese + place.chinese
            let english = place.english.map { "\(side.english) \($0)" }
            let name = language.text(english ?? chinese, chinese)
            if isFree(name, keys: [chinese, english, name].compactMap { $0 }),
               railways?.stations(named: chinese, near: nil).isEmpty != false {
                return name
            }
        }
        return nil
    }

    /// Suggests a new ``stationName`` for a station at `location` (see
    /// ``suggestedStationName(for:at:in:railways:placeNames:maximumDistanceMetres:)``),
    /// replacing the current one only while it is still the last suggestion.
    func suggestStationName(at location: PlanPoint?) {
        let suggestion = Self.suggestedStationName(for: world, at: location, in: language, railways: railways, placeNames: placeNames)
        if stationName == automaticStationName {
            stationName = suggestion
        }
        automaticStationName = suggestion
    }

    /// "Line N" (or "路線 N") with the lowest N from the next line number
    /// upward that no existing line uses.
    static func suggestedLineName(for world: GameWorld, in language: DisplayLanguage) -> String {
        suggestedName(language.text("Line", "路線"), from: world.lines.count + 1, taken: Set(world.lines.map(\.name)))
    }

    /// "Train N" (or "列車 N") with the lowest N from the next train number
    /// upward that no existing train uses.
    static func suggestedTrainName(for world: GameWorld, in language: DisplayLanguage) -> String {
        suggestedName(language.text("Train", "列車"), from: world.trains.count + 1, taken: Set(world.trains.map(\.name)))
    }

    /// "`prefix` N" with the lowest N from `first` upward that is not in
    /// `taken`.
    nonisolated private static func suggestedName(_ prefix: String, from first: Int, taken: Set<String>) -> String {
        var number = first
        while taken.contains("\(prefix) \(number)") {
            number += 1
        }
        return "\(prefix) \(number)"
    }
}

/// A one-line report of what the last action did.
public struct StatusMessage: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case success
        case failure
    }

    public let kind: Kind
    public let text: String
    /// For a refusal for want of cash, what it would have taken: once the
    /// cash covers it, the refusal is out of date and goes
    /// (``GameSession/refusal(_:doing:)``).
    public let fundsNeeded: Money?
    /// For a refusal by a train standing on no line, that train: the
    /// banner offers to sell it (decision 327).
    public let sellableTrain: TrainID?

    public init(kind: Kind, text: String, fundsNeeded: Money? = nil, sellableTrain: TrainID? = nil) {
        self.kind = kind
        self.text = text
        self.fundsNeeded = fundsNeeded
        self.sellableTrain = sellableTrain
    }

    /// How long the banner shows the message before clearing it: a success
    /// goes after 4 s, so it never stays over the row just edited at the
    /// bottom of a panel; a problem, which explains itself, stays longer
    /// the longer it is: 4 s and a tenth of a second a character, from 6 s
    /// up to 10 s (ARCHITECTURE decision 106, after the reference's
    /// `notify()`, `min(9, 3.2 + length × 0.09)` s). The banner keeps a
    /// problem until dismissed while VoiceOver runs.
    public var autoDismissDelay: Duration {
        switch kind {
        case .success: .seconds(4)
        case .failure: .milliseconds(min(10_000, max(6_000, 4_000 + 100 * text.count)))
        }
    }
}
