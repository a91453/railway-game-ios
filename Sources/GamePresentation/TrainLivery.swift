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
// - Noses (decision 168: the shape is the difference): pointed for the
//   high-speed set only, round for the expresses (the tilting trains' long
//   noses read as round at the map's size), flat for the local trains and
//   the metro.

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

    /// The livery of each train type with one, by the type's code
    /// (``TrainTypeSpec/code``).
    public static let byType: [String: TrainLivery] = ["HSR": highSpeed, "EMU3000": emu3000]
    /// The livery of each real model's performance, by its preset's code
    /// (``TrainPerformanceSpec/code``), for a train whose type has none.
    public static let byPerformance: [String: TrainLivery] = [
        "highSpeed": highSpeed, "emu3000": emu3000, "puyuma": puyuma, "taroko": taroko,
        "emu800": emu800, "metroC381": metroC381,
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
