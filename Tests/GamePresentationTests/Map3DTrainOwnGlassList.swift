@testable import GamePresentation

/// The trains whose recipes mark their own glass face by face (decision
/// 615, decision 450's later note and the trains after them), one train a
/// line in each list. `.gitattributes` merges this file with `merge=union`,
/// so two branches that each add a train keep both lines, as the trains'
/// and landmarks' registries do (decisions 782, 895): every line ends with
/// a comma, and nothing else goes between the brackets.
/// `Map3DTrainOwnGlassListTests` checks that no line came in twice.
///
/// A new train that marks its own glass adds a line to ``prefixes``; a
/// studio car checked face by face (`Map3DTrainOwnGlassTests`) adds one
/// to ``studioCars``; a car whose dark faces were never taken for glass
/// adds one to ``darkNeverGlass``.
enum Map3DTrainOwnGlassList {
    /// The name prefixes of the pack's recipes that may mark their own
    /// glass (`Map3DTrainMaterialTests`): a cabin or a studio train.
    static let prefixes: [String] = [
        "cablecar-cabin-", // Decision 615: a cable car cabin.
        "set-mtr", // Decision 450's later note: the studio's Hong Kong trains.
        "set-finlandIntercity", // Decision 864.
        "set-finlandNight", // Decision 900.
        "set-fukuoka", // Decision 893.
        "set-emu900-head", // Decision 904: the EMU900's cab.
        "set-emu900-tail", // Decision 904.
        "set-puyuma", // Decision 905.
        "set-taroko", // Decision 906.
        "temu1000-", // Decision 906.
        "set-EMU100", // Decision 930.
        "set-MONORAIL", // Decision 930.
        "set-MAGLEV", // Decision 930.
        "set-SKYRAIL", // Decision 930.
        "set-hkPeakTram", // Decision 930.
        "set-SUMMER-head", // Decision 930.
        "set-SUMMERFar-head", // Decision 930.
        "set-STEAM-car", // Decision 957: the steam train's wooden coaches.
        "set-STEAM-tail", // Decision 957.
        "set-STEAMFar-car", // Decision 957.
        "set-STEAMFar-tail", // Decision 957.
        "set-redCommuter", // Decision 956: the Keikyu New 1000, near and far.
        "set-keikyuNew1000", // Decision 986: the same cars at 18 m.
        "set-kyushuN700", // Decision 977: the Kyushu Shinkansen's N700 series.
        "set-n700s-", // Decision 979: the N700S.
        "set-n700st-", // N700ST-PAINT: the N700S in the N700ST's paint.
        "set-highSpeed-", // Decision 988: the 700T, the owner's old 700 series.
        "set-series700-", // Decision 989: the 700 series in its own paint.
        "set-kyushu800", // Decision 978: the Kyushu Shinkansen's 800 series.
        "set-n700sKamome-", // Decision 998 (continued): the N700S Kamome.
        "set-kyushu885-", // Decision 1028 (continued): the Relay Kamome's 885 series.
        "set-kyushu787-", // Decision 1028 (continued): and its 787 series.
    ]

    /// Every studio car checked face by face (`Map3DTrainOwnGlassTests`):
    /// each line gives a train's cars near (`far` false) and far (`far`
    /// true); a train drawn near only gives none far.
    static let studioCars: [@Sendable (_ far: Bool) -> [Map3DModelPack.Model?]] = [
        { far in Map3DMTRUrbanLine.Unit.allCases.map { Map3DMTRUrbanLine.model($0, far: far) } },
        { far in Map3DMTRTuenMaLine.Unit.allCases.map { Map3DMTRTuenMaLine.model($0, far: far) } },
        { far in Map3DMTRAirportLine.Unit.allCases.map { Map3DMTRAirportLine.model($0, far: far) } },
        { far in Map3DMTREastRailLine.Unit.allCases.map { Map3DMTREastRailLine.model($0, far: far) } },
        { far in Map3DMTRSouthIslandLine.Unit.allCases.map { Map3DMTRSouthIslandLine.model($0, far: far) } },
        { far in Map3DMTRDisneylandLine.Unit.allCases.map { Map3DMTRDisneylandLine.model($0, far: far) } },
        { far in [Map3DFinlandDoubleDeck.model(far: far)] }, // Decision 864: the Finnish double-deck coach.
        { far in [Map3DFinlandControlCar.model(far: far)] }, // Decision 900: the control car.
        { far in [Map3DFinlandSleeper.model(far: far)] }, // Decision 900: the sleeping car.
        { far in Map3DFukuokaAirportLine.Unit.allCases.map { Map3DFukuokaAirportLine.model($0, far: far) } }, // Decision 893.
        { far in Map3DFukuokaKaizukaLine.Unit.allCases.map { Map3DFukuokaKaizukaLine.model($0, far: far) } }, // Decision 893.
        { far in Map3DFukuokaNanakumaLine.Unit.allCases.map { Map3DFukuokaNanakumaLine.model($0, far: far) } }, // Decision 893.
        { far in Map3DSteamCoach.Unit.allCases.map { Map3DSteamCoach.model($0, far: far) } }, // Decision 957: the steam train's wooden coaches.
        { far in [Map3DRedCommuter.cab(far: far), Map3DRedCommuter.middle(far: far)] }, // Decision 956: the Keikyu New 1000.
        { far in far ? [] : Map3DKyushuN700.Unit.allCases.map { Map3DKyushuN700.model($0) } }, // Decision 977: near only.
        { far in far ? [] : Map3DN700S.Unit.allCases.map { Map3DN700S.model($0) } }, // Decision 979: near only.
        { far in far ? [] : Map3DN700S.Unit.allCases.map { Map3DN700ST.model($0) } }, // N700ST-PAINT: near only.
        { far in far ? [] : Map3DKyushu800.Unit.allCases.map { Map3DKyushu800.model($0) } }, // Decision 978: near only.
        { far in far ? [] : Map3DN700SKamome.Unit.allCases.map { Map3DN700SKamome.model($0) } }, // Decision 998 (continued): near only.
        { far in far ? [] : Map3DKyushu885.Unit.allCases.map { Map3DKyushu885.model($0) } }, // Decision 1028 (continued): near only.
        { far in far ? [] : Map3DKyushu787.Unit.allCases.map { Map3DKyushu787.model($0) } }, // Decision 1028 (continued): near only.
    ]

    /// The studio cars whose dark faces were never taken for glass, so
    /// that marking their own glass lights no fewer panes than guessing by
    /// colour (`Map3DTrainOwnGlassTests.testOnlyTheWindowsLightAtNight`),
    /// by name prefix. The Tuen Ma line's are navy; the Keikyu New 1000's
    /// (decision 956) dark is its underframe's and gangways'; so is the
    /// Kyushu Shinkansen's N700's (decision 977), the N700S's (decision
    /// 979) and the 800's (decision 978: its cab mask and car ends too);
    /// the 885's and the 787's (decision 1028, continued) are their masks,
    /// lamp housings, bogies and floors.
    static let darkNeverGlass: [String] = [
        "mtr-tuen-ma",
        "keikyu-new1000",
        "kyushu-n700",
        "n700s-",
        "n700st-",
        "kyushu-800",
        "kyushu-885",
        "kyushu-787",
    ]
}
