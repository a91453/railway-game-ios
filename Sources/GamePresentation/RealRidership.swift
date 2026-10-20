import Foundation

// How many people use each real station a day (ARCHITECTURE decision 298):
// the official yearly averages `tools/real-ridership/` writes, which the
// transfer points of a station by a real one follow. Taiwan Railway's by
// station code (`tra_ridership.json`), the others by station name: the High
// Speed Rail's, Taipei Metro's, Kaohsiung Metro's, Taichung Metro's, the
// Taoyuan Airport MRT's (`thsr_ridership.json`, `trtc_ridership.json`,
// `krtc_ridership.json`, `tmrt_ridership.json`, `tymc_ridership.json`) and
// New Taipei Metro's: the Danhai and Ankeng
// light rails and the Circular Line (`ntdlrt_ridership.json`,
// `ntalrt_ridership.json`, `ntmc_circular_ridership.json`).
// Each file is optional; a station none of them has keeps its system's rule.

/// Real stations' average riders a day, (entries + exits) / 2 over a year.
public struct RealRidership: Sendable {
    /// One file: its riders and the period they are the average of.
    public struct Table: Sendable {
        /// Riders a day, by Taiwan Railway's station code or, for the
        /// others, by ``RealRailways/stationKey(_:)`` of the station's name.
        public let riders: [String: Int]
        /// The first and last day averaged, as `yyyyMMdd`.
        public let from: String
        public let to: String

        /// A file of `tools/real-ridership/`, its stations keyed as the
        /// file keys them (`byName`: by name, made a station key).
        public init(data: Data, byName: Bool) throws {
            struct File: Decodable {
                struct Period: Decodable {
                    let from: String
                    let to: String
                }
                let period: Period
                let riders: [String: Int]
            }
            let file = try JSONDecoder().decode(File.self, from: data)
            var riders: [String: Int] = [:]
            for (key, count) in file.riders {
                let key = byName ? RealRailways.stationKey(key) : key
                // Two spellings of one name: the larger, a station's own.
                riders[key] = max(riders[key] ?? 0, count)
            }
            self.riders = riders
            from = file.period.from
            to = file.period.to
        }
    }

    public let tra: Table?
    public let thsr: Table?
    public let trtc: Table?
    public let krtc: Table?
    public let tmrt: Table?
    public let tymc: Table?
    public let ntdlrt: Table?
    public let ntalrt: Table?
    /// New Taipei Metro's own count of the Circular Line's stations: Taipei
    /// Metro's file has them too, but only the trips it counts at its own
    /// gates, a fraction of them (Zhongyuan 701 a day against 2,831).
    public let circular: Table?

    public init(tra: Table?, thsr: Table?, trtc: Table?, krtc: Table? = nil, tmrt: Table? = nil, tymc: Table? = nil, ntdlrt: Table? = nil, ntalrt: Table? = nil, circular: Table? = nil) {
        self.tra = tra
        self.thsr = thsr
        self.trtc = trtc
        self.krtc = krtc
        self.tmrt = tmrt
        self.tymc = tymc
        self.ntdlrt = ntdlrt
        self.ntalrt = ntalrt
        self.circular = circular
    }

    /// The riders a day of real station `station`: Taiwan Railway's by its
    /// code in `data`, the High Speed Rail's and the metros' by name.
    /// `nil` for a system with no file, or a station its file does not have.
    public func riders(of station: RealRailways.Station, data: RealStationData?) -> Int? {
        switch station.system.id {
        case "tra_sched":
            guard let code = data?.stationInfo(forStation: station.chinese)?.id else { return nil }
            return tra?.riders[code]
        case "thsr_sched":
            return thsr?.riders[RealRailways.stationKey(station.chinese)]
        case "mrt":
            // A station of both companies (Banqiao, Jing'an) has each one's
            // count of it; the larger, so no trip is counted twice.
            let key = RealRailways.stationKey(station.chinese)
            let counts = [trtc?.riders[key], circular?.riders[key]].compactMap { $0 }
            return counts.max()
        case "krtc":
            return krtc?.riders[RealRailways.stationKey(station.chinese)]
        case "tmrt":
            return tmrt?.riders[RealRailways.stationKey(station.chinese)]
        case "tymc":
            return tymc?.riders[RealRailways.stationKey(station.chinese)]
        case "ntdlrt":
            return ntdlrt?.riders[RealRailways.stationKey(station.chinese)]
        case "ntalrt":
            return ntalrt?.riders[RealRailways.stationKey(station.chinese)]
        default:
            return nil
        }
    }
}
