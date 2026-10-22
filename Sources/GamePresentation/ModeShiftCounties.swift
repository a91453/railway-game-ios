import GameCore

// Decision 332: how many of a pair's trips at most take a scooter or a car
// instead under the realistic rule, by the county or city a real-world
// map starts in.
//
// Ministry of Transportation and Communications, Department of
// Statistics, 2024 National Travel Survey (113 年民眾日常使用運具狀況調查,
// summary analysis of June 2025), table 4: the private motor vehicles'
// share of trips by the county or city people live in, 2024
// (data.gov.tw dataset 6248, Open Government Data License, version 1.0;
// credited in `DataSourceCredits`). Written here rather than bundled as a
// file: 22 numbers the app need not read at launch.

public enum ModeShiftCounties {
    /// Table 4's 2024 column, in thousandths, by county or city.
    public static let shares: [String: Int64] = [
        "臺北市": 370, "基隆市": 545, "新北市": 548, "桃園市": 731,
        "連江縣": 743, "金門縣": 804, "宜蘭縣": 805, "高雄市": 812,
        "新竹市": 814, "臺中市": 816, "新竹縣": 822, "澎湖縣": 826,
        "苗栗縣": 836, "花蓮縣": 841, "臺南市": 851, "嘉義市": 853,
        "嘉義縣": 857, "雲林縣": 864, "臺東縣": 867, "南投縣": 872,
        "屏東縣": 888, "彰化縣": 891,
    ]

    /// The realistic rule's cap for a new game round `anchor`: the share
    /// of the county or city it is in, or the national one
    /// (``ModeShift/nationalShare``) on a blank map, abroad, at sea or
    /// without the place names.
    public static func cap(at anchor: GeoAnchor?, in names: PlaceNames?) -> Int64 {
        guard let anchor, let names else { return ModeShift.nationalShare }
        let point = RealRailways.Coordinate(latitude: anchor.latitudeDegrees, longitude: anchor.longitudeDegrees)
        return names.county(containing: point).flatMap { shares[$0] } ?? ModeShift.nationalShare
    }
}
