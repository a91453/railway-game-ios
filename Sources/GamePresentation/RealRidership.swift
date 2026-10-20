import Foundation

// How many people use each real station a day (ARCHITECTURE decision 298):
// the official yearly averages `tools/real-ridership/` writes, which the
// transfer points of a station by a real one follow. Taiwan Railway's by
// station code (`tra_ridership.json`), the High Speed Rail's and Taipei
// Metro's by station name (`thsr_ridership.json`, `trtc_ridership.json`).
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

    public init(tra: Table?, thsr: Table?, trtc: Table?) {
        self.tra = tra
        self.thsr = thsr
        self.trtc = trtc
    }

    /// The riders a day of real station `station`: Taiwan Railway's by its
    /// code in `data`, the High Speed Rail's and Taipei Metro's by name.
    /// `nil` for a system with no file, or a station its file does not have.
    public func riders(of station: RealRailways.Station, data: RealStationData?) -> Int? {
        switch station.system.id {
        case "tra_sched":
            guard let code = data?.stationInfo(forStation: station.chinese)?.id else { return nil }
            return tra?.riders[code]
        case "thsr_sched":
            return thsr?.riders[RealRailways.stationKey(station.chinese)]
        case "mrt":
            return trtc?.riders[RealRailways.stationKey(station.chinese)]
        default:
            return nil
        }
    }
}
