import GameCore

// The real models' paint (decision 243): each model's body, stripe and cab
// colour and its nose's shape, so that an EMU3000, a Puyuma, a local train
// and a high-speed set tell themselves apart on the map. Only how a train
// looks: GameCore's rules and saves do not know it. The 2D map draws a
// model's body and cab in its colours with a band in the line's colour
// (the line still tells which line a train is on); the 3D view is to read
// the same fields.
//
// Where the colours come from:
//
// - The high-speed set's white and orange and the EMU3000's cream, wine
//   stripe and dark front are the owner's city view
//   (`Web/CityView/src/world/trains.js`, `LIVERIES`: `hsr`, `emu3000`,
//   its glass `#222a38`), as is the Taipei Metro's stainless with a grey
//   stripe (the default).
// - The EMU800's blue front and yellow band on stainless and the Puyuma's
//   red front and red band on white are the owner's fleet catalogue
//   (`fleet/catalog.json`, `livery` of `emu800` and `temu2000`); the
//   shades are this project's.
// - The Taroko's orange-red on white is this project's, from the train's
//   paint (gap: the references do not have it).
// - Decision 252's Taiwan Railway models start from the owner's simulator
//   (`Simulator/reference_snapshot/_next/static/chunks/2694-*.js`, the
//   liveries `tra-emu100`, `tra-e201`, `tra-e500`, `tra-r100`, `tra-r200`,
//   `tra-sea-breeze`: `bodyColor`, `stripeColor`, `cabShape`) and the fleet
//   catalogue's Chu-Kuang coach (「白線以上米黃、以下橘色」). A Chu-Kuang
//   set's body is its coaches' orange and its front its locomotive's mark:
//   the E200's cream, the E500's dark cab, the R100's red, the R200's navy.
//   Where the simulator's shade sits too near the map's warm yellow or
//   teal, or another front of the same shape, the shade is this project's:
//   the EMU100's cream and orange, the R100's red darkened, the R200's navy
//   lightened, the Hai-Feng's sea green kept for its stripe, its body a
//   pale mint and its front a pale sea blue.
// - Noses (decision 168: the shape is the difference): pointed for the
//   high-speed set only, round for the expresses (the tilting trains' long
//   noses read as round at the map's size), flat for the local trains and
//   the metro; for decision 252's, the simulator's `cabShape`: "boxy" flat,
//   "streamlined" (the R200) round.

/// The shape of a train's nose on the map (decision 243).
public enum TrainNose: String, CaseIterable, Hashable, Sendable {
    /// A high-speed set's long point.
    case pointed
    /// An express's rounded front.
    case round
    /// A local train's or a metro car's flat front.
    case flat
}

/// How a model of train is painted (decision 243). Colours are `0xRRGGBB`.
public struct TrainLivery: Hashable, Sendable {
    /// Its body's colour; `nil` for a train of no particular model, whose
    /// body is its line's colour.
    public let body: Int?
    /// Its stripe's colour, the real one (the 2D map's band is the line's
    /// colour instead); `nil` with no model.
    public let stripe: Int?
    /// Its front's colour: the nose on the 2D map; `nil` with no model.
    public let cab: Int?
    public let nose: TrainNose

    /// A train of no particular model: its line's colour, a round nose.
    public static let plain = TrainLivery(body: nil, stripe: nil, cab: nil, nose: .round)
    /// THSR's 700T.
    public static let highSpeed = TrainLivery(body: 0xF6F6F4, stripe: 0xEA6A1E, cab: 0xEA6A1E, nose: .pointed)
    /// The Taiwan Railway's EMU3000.
    public static let emu3000 = TrainLivery(body: 0xF6F3EE, stripe: 0x9C385C, cab: 0x222A38, nose: .round)
    /// The Puyuma (TEMU2000).
    public static let puyuma = TrainLivery(body: 0xF6F6F4, stripe: 0xD7282F, cab: 0xD7282F, nose: .round)
    /// The Taroko (TEMU1000).
    public static let taroko = TrainLivery(body: 0xF6F6F4, stripe: 0xE2591E, cab: 0x8A939C, nose: .round)
    /// The EMU800 and EMU900 local trains.
    public static let emu800 = TrainLivery(body: 0xC9CCCE, stripe: 0xF2C230, cab: 0x2F6FB7, nose: .flat)
    /// Taipei Metro's C371 and C381.
    public static let metroC381 = TrainLivery(body: 0xC9CCCE, stripe: 0x7B8794, cab: 0x222A38, nose: .flat)
    /// The EMU100 express (decision 252).
    public static let emu100 = TrainLivery(body: 0xF3E9C6, stripe: 0xF09B28, cab: 0xDD7424, nose: .flat)
    /// Chu-Kuang coaches behind an E200 (decision 252).
    public static let e200ChuKuang = TrainLivery(body: chuKuangCoach, stripe: 0xECE2BC, cab: 0xECE2BC, nose: .flat)
    /// Chu-Kuang coaches behind an E500 (decision 252).
    public static let e500ChuKuang = TrainLivery(body: chuKuangCoach, stripe: 0xECE2BC, cab: 0x262E33, nose: .flat)
    /// Chu-Kuang coaches behind an R100 (decision 252).
    public static let r100ChuKuang = TrainLivery(body: chuKuangCoach, stripe: 0xECE2BC, cab: 0x9B2F23, nose: .flat)
    /// Chu-Kuang coaches behind an R200 (decision 252).
    public static let r200ChuKuang = TrainLivery(body: chuKuangCoach, stripe: 0xECE2BC, cab: 0x2A4E9A, nose: .round)
    /// The Hai-Feng tourist train (decision 252).
    public static let haiFeng = TrainLivery(body: 0xE4EEE6, stripe: 0x7DBBB0, cab: 0x9ACBE6, nose: .flat)
    /// The Blue Train (decision 286): the old coaches' blue, their cream
    /// line, the R100-class diesel's navy (the reference's garage models
    /// `bluecoach` and `blue`).
    public static let blueTrain = TrainLivery(body: 0x345B7A, stripe: 0xE9EBE5, cab: 0x232E48, nose: .flat)
    /// The Shan-Lan (decision 286, later): the paddy yellow-green of the
    /// reference's garage model `shanlan`, with a deeper rice-field green
    /// for its line and front (this project's).
    public static let shanLan = TrainLivery(body: 0xD4E48B, stripe: 0x7FA845, cab: 0x5E8C3A, nose: .flat)
    /// The Ming-Ri (decision 286, later): black and orange, the reference's
    /// garage models `mingricoach` (its `body` and `accent`) and `mingri`
    /// (the locomotive's orange, its front on the map).
    public static let mingRi = TrainLivery(body: 0x292F31, stripe: 0xD1773D, cab: 0xD57638, nose: .flat)
    /// The Formosa Star (decision 286, later, third): its coaches' pastel
    /// pink with a deeper pink line and front (this project's, after the
    /// character wraps of its Sanrio years; the E500's orange front would
    /// be the EMU100's on the map).
    public static let formosaStar = TrainLivery(body: 0xF3D3DF, stripe: 0xD9467E, cab: 0xD9467E, nose: .flat)
    /// A Chu-Kuang coach's orange (the cream above its white line is the
    /// stripe).
    static let chuKuangCoach = 0xE2662A

    /// The livery of each train type with one, by the type's code
    /// (``TrainTypeSpec/code``).
    public static let byType: [String: TrainLivery] = [
        "HSR": highSpeed, "EMU3000": emu3000,
        "EMU100": emu100, "E200CK": e200ChuKuang, "E500CK": e500ChuKuang, "R100CK": r100ChuKuang, "R200CK": r200ChuKuang,
        "HAIFENG": haiFeng, "BLUE": blueTrain, "SHANLAN": shanLan, "MINGRI": mingRi, "STAR": formosaStar,
    ]
    /// The livery of each real model's performance, by its preset's code
    /// (``TrainPerformanceSpec/code``), for a train whose type has none.
    public static let byPerformance: [String: TrainLivery] = [
        "highSpeed": highSpeed, "emu3000": emu3000, "puyuma": puyuma, "taroko": taroko,
        "emu800": emu800, "metroC381": metroC381,
        "emu100": emu100, "e200ChuKuang": e200ChuKuang, "e500ChuKuang": e500ChuKuang, "r100ChuKuang": r100ChuKuang,
        "r200ChuKuang": r200ChuKuang, "haiFeng": haiFeng, "mingRi": mingRi, "formosaStar": formosaStar,
    ]

    /// A train's livery: its type's, else its performance's model's
    /// (``PerformancePreset/init(matching:)``, whatever its top speed),
    /// else ``plain``.
    public static func of(type: TrainType?, performance: TrainPerformance) -> TrainLivery {
        if let type, let livery = byType[type.rawValue] { return livery }
        if let preset = PerformancePreset(matching: performance), let livery = byPerformance[preset.code] { return livery }
        return plain
    }
}
