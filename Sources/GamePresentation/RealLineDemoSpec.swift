import GameCore

/// What a demo of a real double-track line running its real day is built
/// from (decision 240): the high-speed demo's (``HighSpeedDemo``, decisions
/// 170, 197, 221 and 228) and the TRA demo's (``TRADemo``). Both are laid
/// out and run by ``HighSpeedDemo``'s builder: a down track on the real
/// alignment north to south, an up track beside it, loops at the stations
/// between the ends, the ends' platform tracks, the real depots, and one
/// line for each kind of train the real day runs.
struct RealLineDemoSpec: Sendable {
    /// One kind of train: a line of the demo (decision 133: a line with
    /// runs calls at all its stops), and the sets that run it.
    struct Kind: Sendable {
        let english: String
        let chinese: String
        /// The stations it calls at, by index, north to south.
        let stops: [Int]
        /// The real trains it takes, by the model the data names
        /// (``RealDailySchedule/Train/model``); `nil` takes any.
        let models: Set<String>?
        /// Its sets: their type (`nil`, the standard car), cars and
        /// performance, and what each is called before its number.
        let type: TrainType?
        let cars: Int
        let performance: TrainPerformance
        let set: (english: String, chinese: String)
        /// Whether it takes only the trains that run from one end to the
        /// other (decision 240): an express line names its whole way along
        /// the through tracks, which a set turned round between the ends
        /// is not on; such a train goes on the all-stops line.
        var endToEnd = false
    }

    /// The line's centre line, north to south, in the world of `frame`;
    /// empty when `railways` has no such line.
    let path: @Sendable (_ railways: RealRailways, _ frame: RealWorldFrame) -> [WorldVector]
    /// How the stations are named in the data, north to south, and what
    /// their ids begin with (`thsr_sched|`).
    let stationNames: [String]
    let stationIDPrefix: String
    /// The system its line is of (`thsr_sched`), as its stations' ids name
    /// it.
    var system: String { String(stationIDPrefix.dropLast()) }
    /// The scheduled system whose day it runs (`thsr`).
    let schedule: String
    let kinds: [Kind]
    /// How many platform tracks each end has beside the down track's, on
    /// each side of it (``HighSpeedDemo/endTrackSides(_:)`` for the high-speed
    /// demo).
    let endTrackSides: (north: (east: Int, west: Int), south: (east: Int, west: Int))
    /// The stations between the ends where the expresses call on the
    /// through tracks, by index (island platforms serving every track).
    let islandStations: Set<Int>
    let depots: [HighSpeedDemo.RealDepot]
    /// How far the track may stray from the real alignment, and how long
    /// an edge may be (``RealWorldDemo/TrackPlan``).
    let tolerance: Double
    let longestEdge: Double
    /// The minutes of the first day the land round the stations is read in
    /// (before the first set leaves) and the game opens at.
    let landAt: Int64
    let opensAt: Int64
    /// Whether the ramps out to the ends' tracks follow the down track
    /// through each of its nodes, as where the ends lie on a curve (the
    /// TRA demo's): one edge from a node to the next.
    var rampsFollowTrack = false
    /// The sidings a depot has beyond one for each set that stands there on
    /// the first night (``HighSpeedDemo/spareSidings``): more where more
    /// sets wait there by day than stand there at night.
    var spareSidings = HighSpeedDemo.spareSidings
    /// Whether trains keep left where two ways are nearly as short
    /// (decision 202; the high-speed demo's is off, its routes as they were
    /// measured): the TRA demo's empty runs to and from its sidings go
    /// over to their way's own track.
    var keepLeft = false
    /// Whether, with the app's heights, the track is laid over the ground
    /// at the heights the real line's bridges, viaducts and tunnels ask for
    /// (decision 279; both demos', the high-speed demo's from decision
    /// 281), its platforms level; otherwise flat at 0 m.
    var followsRealStructures = false
    /// How far an edge's straight grade may stray from the heights it is
    /// laid at (``TrackRise/fit``; the high-speed demo's looser, decision
    /// 281).
    var heightFit = TrackRise.fit
    /// Whether a depot north of the south end that keeps only its sets
    /// has its own track from the end's throat (decision 281; the
    /// high-speed demo's Zuoying): otherwise its sidings leave the down
    /// track, and the sets reach them along it.
    var depotLeads = false
    /// What a trip between two of its stations pays (decision 325), by
    /// index, north to south: the real fare table's; `nil` pays by the
    /// kilometre (decision 168).
    var fares: [[Money]]? = nil

    /// Cars of the longest sets: every platform takes them.
    var cars: Int { kinds.map(\.cars).max() ?? 1 }
    /// A platform takes a car more than the longest set has.
    var platformLength: Int64 { Int64(cars + 1) * Train.carLength }
    /// How long each siding of a depot runs beside the down track past its
    /// ladder: a set's platform with a margin either side, and a ramp.
    var sidingRun: Double { Double(platformLength) + 2 * RealWorldDemo.platformMargin + HighSpeedDemo.rampLength }
}
