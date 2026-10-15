import Foundation
import GameCore

// The TRA demo (ARCHITECTURE decision 240, the planning session's §14
// item 5): the Taiwan Railway's Yilan Line from Toucheng to Su'aoxin, its
// ten stations where they stand, built as the game's own double track on
// its real alignment over the whole of Taiwan, with a weekday's real
// trains running: the local trains, the local expresses and the Tze-Chiang
// expresses, EMU3000, Puyuma and Taroko among them. It is built as the
// high-speed demo is (decisions 170, 197, 221 and 228), from its own
// ``RealLineDemoSpec``.

/// A whole-Taiwan game with the Yilan Line, Toucheng to Su'aoxin, built and
/// running a weekday's real trains (decision 240).
///
/// - The track is double, as on the real line, flat and on the ground: the
///   down track (southbound) on the real alignment, the up track beside it,
///   west of it, as the real trains keep left.
/// - The ten stations that trains call at stand where the real ones do
///   (Xinma, where none called that weekday, is left out). Each between the
///   ends has a loop beside each track with a platform; the local trains
///   call on the loops, and the expresses call at Jiaoxi, Yilan and Luodong
///   on the through tracks, as their island platforms serve every track.
/// - The trains are the real weekday's (`tra-yilan-schedule.json`, from the
///   TRA's open data, 2026-10-05), on eight lines, one for each kind of
///   train and stopping pattern: a train runs on the line of its model
///   whose stops take the fewest calls to add or drop (decision 197). An
///   express that runs on beyond Toucheng or Su'aoxin starts or ends there.
/// - Each line has its own sets, of the real model: the locals' EMU800s
///   (decision 237), the EMU3000s, the Puyumas, the Tarokos, and the other
///   expresses as push-pull sets.
/// - The sets stand at night in two depots by the real yards OpenStreetMap
///   has beside Yilan and Su'aoxin stations, the sidings laid just beyond
///   each station's own tracks.
/// - Traffic control is off, as in the high-speed demo (decision 228).
public enum TRADemo {
    /// The scheduled system whose day it runs: `tra-yilan-schedule.json`.
    public static let schedule = "tra-yilan"

    /// The stations, north to south, as the data names them.
    static let stationNames = ["頭城", "頂埔", "礁溪", "四城", "宜蘭", "二結", "中里", "羅東", "冬山", "蘇澳新"]

    /// How far beyond Toucheng and Su'aoxin the demo's track runs along the
    /// real line, for the ends' tracks and the north end's sidings.
    static let runOn = (north: 3_000.0 * RealWorldDemo.metre, south: 1_500.0 * RealWorldDemo.metre)

    /// The real trains' models by kind, as the data names them.
    static let models = (
        local: Set(["區間車"]),
        localExpress: Set(["區間快"]),
        emu3000: Set(["自強(3000障)", "自強(3000親障)"]),
        puyuma: Set(["自強(普,障)"]),
        taroko: Set(["自強(太,障)"]),
        other: Set(["自強(PP障)", "自強(PP障12)", "自強(D31)", "自強(商專)", "莒光"])
    )

    /// The demo's lines: by station index, 0 Toucheng to 9 Su'aoxin.
    static let kinds: [RealLineDemoSpec.Kind] = {
        let all = Array(0..<10), localExpress = [0, 2, 4, 7, 8, 9], yilanLuodong = [0, 4, 7, 9], jiaoxi = [0, 2, 4, 7, 9]
        return [
            // The local expresses that turn back at Yilan or Luodong run as
            // locals, with the same sets.
            .init(english: "TRA Local", chinese: "台鐵 區間車", stops: all, models: models.local.union(models.localExpress),
                  type: nil, cars: 8, performance: .emu800, set: ("Local", "區間車")),
            .init(english: "TRA Local Express", chinese: "台鐵 區間快", stops: localExpress, models: models.localExpress,
                  type: nil, cars: 8, performance: .emu800, set: ("Local Express", "區間快"), endToEnd: true),
            .init(english: "TRA EMU3000 (Yilan, Luodong)", chinese: "台鐵 EMU3000（宜蘭、羅東）", stops: yilanLuodong, models: models.emu3000,
                  type: .emu3000, cars: 12, performance: .emu3000, set: ("EMU3000", "EMU3000")),
            .init(english: "TRA EMU3000 (Jiaoxi, Yilan, Luodong)", chinese: "台鐵 EMU3000（礁溪、宜蘭、羅東）", stops: jiaoxi, models: models.emu3000,
                  type: .emu3000, cars: 12, performance: .emu3000, set: ("EMU3000", "EMU3000")),
            .init(english: "TRA Puyuma (Yilan, Luodong)", chinese: "台鐵 普悠瑪（宜蘭、羅東）", stops: yilanLuodong, models: models.puyuma,
                  type: nil, cars: 8, performance: .tiltingPuyuma, set: ("Puyuma", "普悠瑪")),
            .init(english: "TRA Puyuma (Jiaoxi, Yilan, Luodong)", chinese: "台鐵 普悠瑪（礁溪、宜蘭、羅東）", stops: jiaoxi, models: models.puyuma,
                  type: nil, cars: 8, performance: .tiltingPuyuma, set: ("Puyuma", "普悠瑪")),
            .init(english: "TRA Taroko", chinese: "台鐵 太魯閣", stops: yilanLuodong, models: models.taroko,
                  type: nil, cars: 8, performance: .tiltingTaroko, set: ("Taroko", "太魯閣")),
            .init(english: "TRA Tze-Chiang", chinese: "台鐵 自強／莒光", stops: jiaoxi, models: models.other,
                  type: nil, cars: 12, performance: .pushPull, set: ("Tze-Chiang", "自強")),
        ]
    }()

    /// Where the demo keeps its sets. Two are real yards: where OpenStreetMap
    /// has the yard tracks beside Yilan and Su'aoxin stations (the centre of
    /// each cluster of `service=yard` ways, read from the whole extract of
    /// Taiwan, ODbL 1.0), the sidings laid clear of the stations' own tracks
    /// and of the curve north of Su'aoxin: south of Yilan, on the straight
    /// north of Xinma. The third is the demo's own: OpenStreetMap has no
    /// yard by Toucheng, where the real trains come from Taipei's depots;
    /// sidings beyond the north end stand in for them, so its sets need not
    /// run along the wrong track from Yilan's.
    static let depots = [
        HighSpeedDemo.RealDepot(english: "North End Sidings", chinese: "北端留置線", latitude: 24.867724, longitude: 121.829668),
        HighSpeedDemo.RealDepot(english: "Yilan Sidings", chinese: "宜蘭側線", latitude: 24.754210, longitude: 121.758450, shift: 2_500 * RealWorldDemo.metre, leavesSouthbound: true),
        HighSpeedDemo.RealDepot(english: "Su'aoxin Sidings", chinese: "蘇澳新側線", latitude: 24.610150, longitude: 121.827340, shift: -3_400 * RealWorldDemo.metre, leavesSouthbound: true),
    ]

    /// What the demo is built from.
    static let spec = RealLineDemoSpec(
        path: { railways, frame in
            // The site's Yilan Line runs from Su'ao to Badu: north to south
            // reversed, from `runOn` north of Toucheng to south of Su'aoxin.
            guard let line = railways.lines.first(where: { $0.name.hasPrefix("宜蘭線") }) else { return [] }
            let path = WorldPath(line.points.reversed().map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
            func along(_ name: String) -> Double? {
                railways.stations.first { $0.id == "tra_sched|\(name)" }.map {
                    path.project(WorldVector(frame.worldPosition(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)))
                }
            }
            guard let north = along("頭城"), let south = along("蘇澳新") else { return [] }
            return path.points(from: max(0, north - runOn.north), to: min(path.length, south + runOn.south))
        },
        stationNames: stationNames,
        stationIDPrefix: "tra_sched|",
        schedule: schedule,
        kinds: kinds,
        endTrackSides: (north: (east: 3, west: 1), south: (east: 4, west: 1)),
        // Jiaoxi, Yilan and Luodong: the expresses call on the through
        // tracks.
        islandStations: [2, 4, 7],
        depots: depots,
        tolerance: 5 * RealWorldDemo.metre,
        longestEdge: 2_000 * RealWorldDemo.metre,
        // The first train leaves at 04:45.
        landAt: 4 * 60 + 30,
        opensAt: 7 * 60,
        // Toucheng and Su'aoxin stand on curves.
        rampsFollowTrack: true,
        // By day more sets wait at the ends than stand there at night.
        spareSidings: 4
    )

    /// The demo: a new whole-Taiwan game with the Yilan Line built,
    /// running from 07:00, its land read in as the high-speed demo's
    /// (``HighSpeedDemo/make(in:railways:population:places:water:coverage:eventSeed:)``).
    ///
    /// - Throws: ``HighSpeedDemo/Failure/noHighSpeedRail`` when `railways`
    ///   has no Yilan Line or not its stations, ``HighSpeedDemo/Failure/noTimetable``
    ///   when it has no day of its trains.
    public static func make(
        in language: DisplayLanguage, railways: RealRailways, population: PopulationGrid? = nil, places: PlaceGrid? = nil,
        water: WaterGrid? = nil, coverage: CoverageGrid? = nil, eventSeed: UInt32 = 1
    ) throws(HighSpeedDemo.Failure) -> GameWorld {
        try HighSpeedDemo.make(spec, in: language, railways: railways, population: population, places: places, water: water, coverage: coverage, eventSeed: eventSeed)
    }
}
