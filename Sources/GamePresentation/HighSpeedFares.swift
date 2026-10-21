import GameCore

/// The High Speed Rail's real fares (decision 325), for the demo's trips:
/// the standard car's adult single ticket between each two stations, from
/// the owner's reference (`Railway/taiwan-rail-reference-clean/`,
/// `source/data/thsr_fare.json`, MD5 `3945fbe83c174d40dee022af41f1a1b0`),
/// which took them from the Ministry of Transportation and Communications'
/// TDX (`Rail/THSR/ODFare`, v2, read 2026-09-11; Open Government Data
/// License 1.0, credited in ``DataSourceCredits``). The table is the same
/// either way.
///
/// The game has one class of car, so the business car's fares (and the
/// unreserved car's, a few dollars less) are not used. Its money is not
/// yet the New Taiwan dollar: NT$10 is the game's $1, which keeps the
/// level of decision 168's kilometre fare (Taipei to Zuoying $153 by the
/// kilometre, NT$1,490 here and so $149).
enum HighSpeedFares {
    /// The real fares in New Taiwan dollars, by the demo's stations
    /// (``HighSpeedDemo/stationNames``), north to south.
    static let newTaiwanDollars: [[Int64]] = [
        [    0,    40,    70,   200,   330,   480,   750,   870,   970,  1120,  1390,  1530], // 南港
        [   40,     0,    40,   160,   290,   430,   700,   820,   930,  1080,  1350,  1490], // 台北
        [   70,    40,     0,   130,   260,   400,   670,   790,   900,  1050,  1320,  1460], // 板橋
        [  200,   160,   130,     0,   130,   280,   540,   670,   780,   920,  1190,  1330], // 桃園
        [  330,   290,   260,   130,     0,   140,   410,   540,   640,   790,  1060,  1200], // 新竹
        [  480,   430,   400,   280,   140,     0,   270,   390,   500,   640,   920,  1060], // 苗栗
        [  750,   700,   670,   540,   410,   270,     0,   130,   230,   380,   650,   790], // 台中
        [  870,   820,   790,   670,   540,   390,   130,     0,   110,   250,   530,   670], // 彰化
        [  970,   930,   900,   780,   640,   500,   230,   110,     0,   150,   420,   560], // 雲林
        [ 1120,  1080,  1050,   920,   790,   640,   380,   250,   150,     0,   280,   410], // 嘉義
        [ 1390,  1350,  1320,  1190,  1060,   920,   650,   530,   420,   280,     0,   140], // 台南
        [ 1530,  1490,  1460,  1330,  1200,  1060,   790,   670,   560,   410,   140,     0], // 左營
    ]

    /// The game's cents in a New Taiwan dollar: NT$10 is $1.
    static let centsPerNewTaiwanDollar: Int64 = 10

    /// The fares the demo's trips pay, in the game's money.
    static let standard: [[Money]] = newTaiwanDollars.map { row in row.map { Money($0 * centsPerNewTaiwanDollar) } }
}
