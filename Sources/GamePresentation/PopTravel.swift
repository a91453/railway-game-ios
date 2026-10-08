import Foundation
import GameCore

// The map's population and travel layers: the `Ci/` reference's
// "population and travel data" (`panel-poptravel`, 人口与出行数据) with its
// three tabs, population (`population`), travel demand (`travel`) and demand
// change (`movement`), the 0–23 h timeline with its play button, and the
// opacity slider of each legend. Only presentation: what is drawn is read
// from the population grid (WorldPop, see PopulationGrid.swift) and from
// the world's demand (`GameWorld.hourlyDemand(from:to:)`), never stored.

/// Which of the reference's three layers the map shows (`G.popTravelMode`).
public enum PopTravelMode: String, CaseIterable, Hashable, Sendable {
    /// People per grid cell (`setPopTravelTab('population')`, 人口数据).
    case population
    /// Trips starting in each place in the chosen hour (`travel`, 旅運需求).
    case travel
    /// How those trips grow or fall from the hour before (`movement`,
    /// 需求变化: "相邻小时出行需求量的增减").
    case movement
    /// The city's layers (Phase 6d, ARCHITECTURE decision 76), drawn from
    /// the world's land (``CityMap``), one at a time with the three above:
    /// each cell's use, by its building's density;
    case landUse
    /// what each cell is worth (``GameCore/LandValue``);
    case landValue
    /// which cells the stations' 800 m catchments reach, and which cells
    /// with people none does.
    case coverage

    /// The tab's title (`map.layers.population`, `map.layers.travelDemand`,
    /// `map.layers.demandChange`).
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .population: language.text("Population", "人口資料")
        case .travel: language.text("Travel demand", "交通需求")
        case .movement: language.text("Demand change", "需求變化")
        case .landUse: language.text("Land use", "土地用途")
        case .landValue: language.text("Land value", "地價")
        case .coverage: language.text("Catchment coverage", "腹地涵蓋")
        }
    }

    /// The tab's description (`map.population.travelDescription`,
    /// `map.population.movementDescription`; the population one is the
    /// grid's own source).
    public func description(in language: DisplayLanguage) -> String {
        switch self {
        case .population:
            language.text(
                "WorldPop 2025 population estimates on a grid of about 1 km.",
                "WorldPop 2025 年約 1km 人口格網。"
            )
        case .travel:
            language.text(
                "Trips that start in each area in each hour from 0 to 23, from the stations' demand.",
                "依車站需求推算 0–23 時各區域的交通需求。"
            )
        case .movement:
            language.text(
                "How the trips starting in each area rise or fall from the hour before.",
                "相鄰小時交通需求量的增減。"
            )
        case .landUse:
            language.text(
                "Each 64 m cell's homes, shops or offices; darker for taller buildings.",
                "每個 64 公尺格的住宅、商業或辦公；建物越高顏色越深。"
            )
        case .landValue:
            language.text(
                "What each cell is worth, in dollars a square metre, from its use, density and the nearest good service.",
                "每格的地價（每平方公尺美元），依用途、密度與附近車站的服務推算。"
            )
        case .coverage:
            language.text(
                "The cells within 800 m of a station, and the cells with people that no station reaches.",
                "車站 800 公尺內的格，以及有人但不在任何車站腹地裡的格。"
            )
        }
    }

    /// Whether the layer is one of the city's (Phase 6d), drawn from the
    /// world's land.
    public var isCityLayer: Bool {
        self == .landUse || self == .landValue || self == .coverage
    }

    /// Whether the layer follows the timeline's hour.
    public var usesHour: Bool {
        self == .travel || self == .movement
    }
}

/// The reference's constants and colours for the three layers.
public enum PopTravel {
    public typealias RGB = RealRailways.RGB

    // MARK: Opacity

    /// The opacity a layer starts at (`getPopTravelBaseOpacityForMode`):
    /// 0.72 for population; for travel and demand change 0.85, or 1 on a
    /// narrow screen (`window.innerWidth <= 768`).
    /// The city's layers (Phase 6d) start at 0.8.
    public static func baseOpacity(for mode: PopTravelMode, compactWidth: Bool) -> Double {
        if mode.isCityLayer { return 0.8 }
        return mode == .population ? 0.72 : (compactWidth ? 1 : 0.85)
    }

    /// The opacity slider's range (`clampPopTravelOpacity`: 0.1 … 1, the
    /// legend's `min="0.1" max="1" step="0.01"`).
    public static let opacityRange: ClosedRange<Double> = 0.1 ... 1

    /// `value` within ``opacityRange``, or `nil` when it is not a number.
    public static func clampedOpacity(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    // MARK: The timeline

    /// The hour the timeline starts at (`poptravel-hour-range` `value="8"`).
    public static let defaultHour = 8

    /// How long play shows each hour (`startPopTravelPlay`'s 1,200 ms
    /// interval).
    public static let playInterval: Duration = .milliseconds(1_200)

    /// The hour after `hour`, back to 0 after 23 (`a >= n ? r : a + 1`).
    public static func nextHour(after hour: Int) -> Int {
        hour >= 23 ? 0 : max(0, hour + 1)
    }

    /// `hour` within 0 … 23 (`onPopTravelHourInput`).
    public static func clampedHour(_ hour: Int) -> Int {
        min(max(hour, 0), 23)
    }

    /// "08:00" (`String(a).padStart(2, "0") + ":00"`).
    public static func hourLabel(_ hour: Int) -> String {
        let hour = clampedHour(hour)
        return (hour < 10 ? "0" : "") + "\(hour):00"
    }

    // MARK: Population colours

    /// The reference's 1 km population grid legend (`chinaGrid` in
    /// `syncPopTravelPopulationLegendUi`): a gradient from 0 to "10000+"
    /// people a cell with these stops.
    public static let populationGradient: [(position: Double, color: RGB)] = [
        (0.00, RGB(0xF7FBFF)), (0.10, RGB(0xDEEBF7)), (0.20, RGB(0xC6DBEF)), (0.30, RGB(0x9ECAE1)),
        (0.40, RGB(0x6BAED6)), (0.52, RGB(0x4292C6)), (0.64, RGB(0x2171B5)), (0.76, RGB(0x08519C)),
        (0.88, RGB(0x08306B)), (1.00, RGB(0x041F4A))
    ]

    /// The people a cell at the gradient's end has ("10000+").
    public static let populationGradientMaximum = 10_000.0

    /// How many steps the gradient is drawn in: every 250 people, so cells
    /// of a step are filled together (one path each, not one per cell).
    public static let populationBands = 40

    /// The step of the gradient a cell of `people` falls in: 0 for under
    /// 250, ``populationBands`` − 1 from 9,750 on.
    public static func populationBand(people: Double) -> Int {
        guard people.isFinite, people > 0 else { return 0 }
        return min(populationBands - 1, Int(people / populationGradientMaximum * Double(populationBands)))
    }

    /// A step's colour: the gradient at its middle.
    public static func populationBandColor(_ band: Int) -> RGB {
        let band = min(max(band, 0), populationBands - 1)
        return populationColor(position: (Double(band) + 0.5) / Double(populationBands))
    }

    /// The gradient at `position` (0 … 1), between its two nearest stops.
    public static func populationColor(position: Double) -> RGB {
        let position = position.isFinite ? min(max(position, 0), 1) : 0
        var lower = populationGradient[0]
        for stop in populationGradient.dropFirst() {
            if position <= stop.position {
                let span = stop.position - lower.position
                let t = span > 0 ? (position - lower.position) / span : 0
                return mix(lower.color, stop.color, t)
            }
            lower = stop
        }
        return lower.color
    }

    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        func channel(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8((Double(x) + (Double(y) - Double(x)) * t).rounded())
        }
        return RGB(red: channel(a.red, b.red), green: channel(a.green, b.green), blue: channel(a.blue, b.blue))
    }

    /// The grid's outline (the LandScan grid's `line-color`
    /// `rgba(8,48,107,0.45)`, width 0.4).
    public static let populationOutline = RGB(0x08306B)

    // MARK: Travel and change colours

    /// Travel demand by grade 1 … 10 (`metroHeatmovePmtilesColorExpression`,
    /// heat): grade `g` takes the `g`th colour.
    public static let travelColors: [RGB] = [
        RGB(0x000088), RGB(0x0033FF), RGB(0x0055FF), RGB(0x33FF66), RGB(0xB7FF00),
        RGB(0xFFFF00), RGB(0xFFBB00), RGB(0xFF8800), RGB(0xFF4400), RGB(0xFF1100)
    ]

    /// Falling demand by grade 1 … 10 (the same expression, `sign < 0`).
    public static let decreaseColors: [RGB] = [
        RGB(0xAAD2FF), RGB(0x86BCFF), RGB(0x62A5FF), RGB(0x3E8EFF), RGB(0x1A77F5),
        RGB(0x0F66D8), RGB(0x0A55BC), RGB(0x0745A0), RGB(0x043584), RGB(0x002668)
    ]

    /// Rising demand by grade 1 … 10 (`sign > 0`).
    public static let increaseColors: [RGB] = [
        RGB(0xFFD0D0), RGB(0xFFB5B5), RGB(0xFF9999), RGB(0xFF7E7E), RGB(0xFF6262),
        RGB(0xF54D4D), RGB(0xE23A3A), RGB(0xCC2929), RGB(0xB51B1B), RGB(0x9E1010)
    ]

    /// The travel legend's six swatches (`poptravel-travel-legend`).
    public static let travelLegend: [RGB] = [
        RGB(0x000088), RGB(0x0033FF), RGB(0x33FF66), RGB(0xFFFF00), RGB(0xFF6600), RGB(0xFF1100)
    ]

    /// The grade 1 … 10 of `value` against the largest `maximum`
    /// (`ceil(10 × value / maximum)`), or 0, drawn as nothing, for none.
    /// The reference's tiles carry the grade (`g`, `g_abs`) from its
    /// server, which is not in the snapshot; this is the app's grading.
    public static func grade(_ value: Int64, maximum: Int64) -> Int {
        guard value > 0, maximum > 0 else { return 0 }
        return Int(min(10, (10 * value + maximum - 1) / maximum))
    }
}
