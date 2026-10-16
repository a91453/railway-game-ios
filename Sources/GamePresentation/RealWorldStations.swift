import GameCore

// Decision 262: the main railway stations of the cities a real-world game
// can start at besides `Ci/`'s and Taiwan's (RealWorldMap.swift): Japan's
// and South Korea's large cities, and every city past the decision's
// threshold that neither list had.

extension RealWorldPlace {
    /// Each city's main railway station (its central metro station where
    /// it has no main line station), at Wikidata's point (its coordinate
    /// location, P625, seven decimals; the item is on each line). Where
    /// Wikidata has no station with a point, the city's centre in the
    /// owner's `city_map_reference_clean/source/data/city-catalog.json`.
    static let mainStations: [RealWorldPlace] = [
        // Japan
        RealWorldPlace("tokyo", .eastAsia, "Tokyo", "東京", latitude: 356_808_333, longitude: 1_397_669_444), // Q283196
        RealWorldPlace("yokohama", .eastAsia, "Yokohama", "橫濱", latitude: 354_658_333, longitude: 1_396_227_778), // Q801658
        RealWorldPlace("osaka", .eastAsia, "Osaka", "大阪", latitude: 347_025_000, longitude: 1_354_961_111), // Q801694
        RealWorldPlace("nagoya", .eastAsia, "Nagoya", "名古屋", latitude: 351_707_722, longitude: 1_368_816_028), // Q49381
        RealWorldPlace("sapporo", .eastAsia, "Sapporo", "札幌", latitude: 430_686_111, longitude: 1_413_507_778), // Q801404
        RealWorldPlace("fukuoka", .eastAsia, "Fukuoka", "福岡", latitude: 335_898_030, longitude: 1_304_206_810), // Q800875
        RealWorldPlace("kobe", .eastAsia, "Kobe", "神戶", latitude: 346_947_222, longitude: 1_351_950_000), // Q14616729
        RealWorldPlace("kyoto", .eastAsia, "Kyoto", "京都", latitude: 349_855_556, longitude: 1_357_586_111), // Q801046
        RealWorldPlace("kawasaki", .eastAsia, "Kawasaki", "川崎", latitude: 355_313_889, longitude: 1_396_969_444), // Q80562
        RealWorldPlace("saitama", .eastAsia, "Saitama", "埼玉", latitude: 359_063_889, longitude: 1_396_238_889), // Q801692
        RealWorldPlace("hiroshima", .eastAsia, "Hiroshima", "廣島", latitude: 343_983_333, longitude: 1_324_758_333), // Q576459
        RealWorldPlace("sendai", .eastAsia, "Sendai", "仙台", latitude: 382_602_778, longitude: 1_408_819_444), // Q801429
        RealWorldPlace("kitakyushu", .eastAsia, "Kitakyushu", "北九州", latitude: 338_869_230, longitude: 1_308_831_810), // Q801027
        RealWorldPlace("chiba", .eastAsia, "Chiba", "千葉", latitude: 356_131_222, longitude: 1_401_131_917), // Q800625
        RealWorldPlace("okayama", .eastAsia, "Okayama", "岡山", latitude: 346_663_694, longitude: 1_339_185_889), // Q801293
        RealWorldPlace("kumamoto", .eastAsia, "Kumamoto", "熊本", latitude: 327_893_389, longitude: 1_306_886_944), // Q969324
        RealWorldPlace("niigata", .eastAsia, "Niigata", "新潟", latitude: 379_120_278, longitude: 1_390_618_889), // Q701753
        RealWorldPlace("shizuoka", .eastAsia, "Shizuoka", "靜岡", latitude: 349_716_667, longitude: 1_383_888_889), // Q801440
        RealWorldPlace("hamamatsu", .eastAsia, "Hamamatsu", "濱松", latitude: 347_036_111, longitude: 1_377_344_444), // Q603640
        RealWorldPlace("kagoshima", .eastAsia, "Kagoshima", "鹿兒島", latitude: 315_836_667, longitude: 1_305_417_222), // Q1316913
        RealWorldPlace("naha", .eastAsia, "Naha", "那霸", latitude: 262_144_000, longitude: 1_276_790_000), // Q7484295
        // South Korea
        RealWorldPlace("busan", .eastAsia, "Busan", "釜山", latitude: 351_147_222, longitude: 1_290_419_444), // Q53118
        RealWorldPlace("incheon", .eastAsia, "Incheon", "仁川", latitude: 374_895_528, longitude: 1_267_240_722), // Q490474
        RealWorldPlace("daegu", .eastAsia, "Daegu", "大邱", latitude: 358_797_222, longitude: 1_286_292_167), // Q54288
        RealWorldPlace("daejeon", .eastAsia, "Daejeon", "大田", latitude: 363_318_944, longitude: 1_274_345_222), // Q20919
        RealWorldPlace("gwangju", .eastAsia, "Gwangju", "光州", latitude: 351_653_278, longitude: 1_269_092_361), // Q489731
        RealWorldPlace("ulsan", .eastAsia, "Ulsan", "蔚山", latitude: 355_391_190, longitude: 1_293_542_140), // Q626465
        RealWorldPlace("suwon", .eastAsia, "Suwon", "水原", latitude: 372_661_111, longitude: 1_269_997_222), // Q54306
        // North Korea
        RealWorldPlace("pyongyang", .eastAsia, "Pyongyang", "平壤", latitude: 390_047_222, longitude: 1_257_363_889), // Q701162
        // China
        RealWorldPlace("jinan", .eastAsia, "Jinan", "濟南", latitude: 366_704_167, longitude: 1_169_854_167), // Q5975526
        // Southeast Asia
        RealWorldPlace("jakarta", .southAndSoutheastAsia, "Jakarta", "雅加達", latitude: -61_767_160, longitude: 1_068_305_080), // Q1889128
        RealWorldPlace("bandung", .southAndSoutheastAsia, "Bandung", "萬隆", latitude: -69_141_667, longitude: 1_076_025_000), // Q2571158
        RealWorldPlace("surabaya", .southAndSoutheastAsia, "Surabaya", "泗水", latitude: -72_653_200, longitude: 1_127_526_900), // Q2355304
        RealWorldPlace("manila", .southAndSoutheastAsia, "Manila", "馬尼拉", latitude: 146_114_000, longitude: 1_209_732_000), // Q7857053
        RealWorldPlace("bangkok", .southAndSoutheastAsia, "Bangkok", "曼谷", latitude: 138_050_000, longitude: 1_005_416_667), // Q23925684
        RealWorldPlace("kualalumpur", .southAndSoutheastAsia, "Kuala Lumpur", "吉隆坡", latitude: 31_340_000, longitude: 1_016_860_000), // Q801042
        RealWorldPlace("hochiminhcity", .southAndSoutheastAsia, "Ho Chi Minh City", "胡志明市", latitude: 107_822_200, longitude: 1_066_772_200), // Q2673539
        RealWorldPlace("hanoi", .southAndSoutheastAsia, "Hanoi", "河內", latitude: 210_241_700, longitude: 1_058_408_300), // Q1207323
        RealWorldPlace("yangon", .southAndSoutheastAsia, "Yangon", "仰光", latitude: 167_817_000, longitude: 961_611_000), // Q8048610
        // South Asia
        RealWorldPlace("dhaka", .southAndSoutheastAsia, "Dhaka", "達卡", latitude: 237_305_400, longitude: 904_268_600), // Q6355669
        RealWorldPlace("delhi", .southAndSoutheastAsia, "Delhi", "德里", latitude: 286_423_140, longitude: 772_200_040), // Q2742296
        RealWorldPlace("kolkata", .southAndSoutheastAsia, "Kolkata", "加爾各答", latitude: 225_828_709, longitude: 883_428_112), // Q986105
        RealWorldPlace("bengaluru", .southAndSoutheastAsia, "Bengaluru", "班加羅爾", latitude: 129_775_950, longitude: 775_680_830), // Q3633970
        RealWorldPlace("chennai", .southAndSoutheastAsia, "Chennai", "清奈", latitude: 130_847_613, longitude: 802_748_563), // Q257382
        RealWorldPlace("hyderabad", .southAndSoutheastAsia, "Hyderabad", "海德拉巴", latitude: 173_933_630, longitude: 784_673_770), // Q3633967
        RealWorldPlace("ahmedabad", .southAndSoutheastAsia, "Ahmedabad", "艾哈邁達巴德", latitude: 230_257_150, longitude: 726_017_160), // Q4696124
        RealWorldPlace("surat", .southAndSoutheastAsia, "Surat", "蘇拉特", latitude: 212_065_680, longitude: 728_407_930), // Q1851275
        RealWorldPlace("pune", .southAndSoutheastAsia, "Pune", "浦那", latitude: 185_293_780, longitude: 738_730_860), // Q3632576
        RealWorldPlace("karachi", .southAndSoutheastAsia, "Karachi", "喀拉蚩", latitude: 248_444_080, longitude: 670_425_580), // Q3605245
        RealWorldPlace("lahore", .southAndSoutheastAsia, "Lahore", "拉合爾", latitude: 315_772_000, longitude: 743_363_000), // Q3695748
        // West and Central Asia
        RealWorldPlace("istanbul", .centralAndWestAsia, "Istanbul", "伊斯坦堡", latitude: 410_149_669, longitude: 289_764_566), // Q800974
        RealWorldPlace("ankara", .centralAndWestAsia, "Ankara", "安卡拉", latitude: 399_359_990, longitude: 328_435_230), // Q800389
        RealWorldPlace("tehran", .centralAndWestAsia, "Tehran", "德黑蘭", latitude: 356_571_002, longitude: 513_973_437), // Q4453688
        RealWorldPlace("baghdad", .centralAndWestAsia, "Baghdad", "巴格達", latitude: 333_236_110, longitude: 443_802_780), // Q3544831
        RealWorldPlace("riyadh", .centralAndWestAsia, "Riyadh", "利雅德", latitude: 246_504_000, longitude: 467_406_000), // Q30594324
        RealWorldPlace("doha", .centralAndWestAsia, "Doha", "杜哈", latitude: 252_834_389, longitude: 515_249_667), // Q25343654
        RealWorldPlace("dubai", .centralAndWestAsia, "Dubai", "杜拜", latitude: 252_547_222, longitude: 553_041_667), // Q4998050
        RealWorldPlace("baku", .centralAndWestAsia, "Baku", "巴庫", latitude: 403_802_006, longitude: 498_503_910), // Q4076080
        RealWorldPlace("tbilisi", .centralAndWestAsia, "Tbilisi", "第比利斯", latitude: 417_233_333, longitude: 447_977_778), // Q1341835
        RealWorldPlace("yerevan", .centralAndWestAsia, "Yerevan", "葉里溫", latitude: 401_553_950, longitude: 445_085_390), // Q4176210
        RealWorldPlace("tashkent", .centralAndWestAsia, "Tashkent", "塔什干", latitude: 413_123_363, longitude: 692_787_079), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("almaty", .centralAndWestAsia, "Almaty", "阿拉木圖", latitude: 432_737_278, longitude: 769_391_111), // Q800371
        RealWorldPlace("astana", .centralAndWestAsia, "Astana", "阿斯塔納", latitude: 511_956_750, longitude: 714_090_833), // Q800403
        // Europe
        RealWorldPlace("moscow", .europe, "Moscow", "莫斯科", latitude: 557_762_611, longitude: 376_553_278), // Q1344454
        RealWorldPlace("saintpetersburg", .europe, "Saint Petersburg", "聖彼得堡", latitude: 599_287_170, longitude: 303_624_330), // Q139318
        RealWorldPlace("barcelona", .europe, "Barcelona", "巴塞隆納", latitude: 413_788_889, longitude: 21_400_000), // Q800453
        RealWorldPlace("amsterdam", .europe, "Amsterdam", "阿姆斯特丹", latitude: 523_789_500, longitude: 49_001_600), // Q50719
        RealWorldPlace("vienna", .europe, "Vienna", "維也納", latitude: 481_850_000, longitude: 163_777_778), // Q697300
        RealWorldPlace("brussels", .europe, "Brussels", "布魯塞爾", latitude: 508_455_560, longitude: 43_572_220), // Q800588
        RealWorldPlace("prague", .europe, "Prague", "布拉格", latitude: 500_830_556, longitude: 144_358_333), // Q751174
        RealWorldPlace("budapest", .europe, "Budapest", "布達佩斯", latitude: 475_005_556, longitude: 190_836_111), // Q841167
        RealWorldPlace("warsaw", .europe, "Warsaw", "華沙", latitude: 522_286_111, longitude: 210_030_556), // Q693034
        RealWorldPlace("athens", .europe, "Athens", "雅典", latitude: 379_929_400, longitude: 237_200_600), // Q3560693
        RealWorldPlace("lisbon", .europe, "Lisbon", "里斯本", latitude: 387_140_203, longitude: -91_227_400), // Q531789
        RealWorldPlace("oslo", .europe, "Oslo", "奧斯陸", latitude: 599_109_490, longitude: 107_525_360), // Q1410317
        RealWorldPlace("helsinki", .europe, "Helsinki", "赫爾辛基", latitude: 601_710_483, longitude: 249_414_487), // Q1044613
        RealWorldPlace("bucharest", .europe, "Bucharest", "布加勒斯特", latitude: 444_463_670, longitude: 260_742_080), // Q683346
        RealWorldPlace("sofia", .europe, "Sofia", "索菲亞", latitude: 427_121_301, longitude: 233_211_209), // Q2095010
        RealWorldPlace("kyiv", .europe, "Kyiv", "基輔", latitude: 504_404_500, longitude: 304_890_400), // Q2105249
        RealWorldPlace("minsk", .europe, "Minsk", "明斯克", latitude: 538_906_667, longitude: 275_511_111), // Q801196
        // Africa
        RealWorldPlace("cairo", .africa, "Cairo", "開羅", latitude: 300_636_111, longitude: 312_472_222), // Q633754
        RealWorldPlace("alexandria", .africa, "Alexandria", "亞歷山卓", latitude: 311_933_333, longitude: 299_063_056), // Q958574
        RealWorldPlace("algiers", .africa, "Algiers", "阿爾及爾", latitude: 367_792_000, longitude: 30_618_200), // Q3095611
        RealWorldPlace("khartoum", .africa, "Khartoum", "喀土穆", latitude: 155_517_700, longitude: 325_324_100), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("addisababa", .africa, "Addis Ababa", "阿迪斯阿貝巴", latitude: 90_094_722, longitude: 387_532_222), // Q3968826
        RealWorldPlace("kinshasa", .africa, "Kinshasa", "金夏沙", latitude: -43_006_000, longitude: 153_190_000), // Q3098110
        RealWorldPlace("luanda", .africa, "Luanda", "羅安達", latitude: -88_053_200, longitude: 132_442_720), // Q65170215
        RealWorldPlace("daressalaam", .africa, "Dar es Salaam", "三蘭港", latitude: -68_160_837, longitude: 392_803_583), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("johannesburg", .africa, "Johannesburg", "約翰尼斯堡", latitude: -261_972_220, longitude: 280_419_440), // Q5175720
        // Oceania
        RealWorldPlace("sydney", .oceania, "Sydney", "雪梨", latitude: -338_825_000, longitude: 1_512_066_667), // Q1585639
        // North America
        RealWorldPlace("houston", .northAmerica, "Houston", "休士頓", latitude: 297_673_000, longitude: -953_675_000), // Q9294212
        RealWorldPlace("dallas", .northAmerica, "Dallas", "達拉斯", latitude: 327_753_823, longitude: -968_077_500), // Q5371609
        RealWorldPlace("philadelphia", .northAmerica, "Philadelphia", "費城", latitude: 399_558_220, longitude: -751_824_000), // Q224214
        RealWorldPlace("atlanta", .northAmerica, "Atlanta", "亞特蘭大", latitude: 337_538_000, longitude: -843_916_000), // Q5456094
        // Latin America
        RealWorldPlace("mexicocity", .latinAmerica, "Mexico City", "墨西哥城", latitude: 194_478_000, longitude: -991_522_000), // Q54867396
        RealWorldPlace("guadalajara", .latinAmerica, "Guadalajara", "瓜達拉哈拉", latitude: 206_747_220, longitude: -1_033_547_220), // Q5816925
        RealWorldPlace("panamacity", .latinAmerica, "Panama City", "巴拿馬城", latitude: 89_735_000, longitude: -795_495_000), // Q25420956
        RealWorldPlace("santodomingo", .latinAmerica, "Santo Domingo", "聖多明哥", latitude: 184_711_111, longitude: -699_116_667), // Q25421631
        RealWorldPlace("caracas", .latinAmerica, "Caracas", "卡拉卡斯", latitude: 105_048_974, longitude: -669_176_005), // Q11294573
        RealWorldPlace("bogota", .latinAmerica, "Bogotá", "波哥大", latitude: 46_072_778, longitude: -740_832_222), // Q6433290
        RealWorldPlace("quito", .latinAmerica, "Quito", "基多", latitude: -1_692_388, longitude: -785_043_144), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("lima", .latinAmerica, "Lima", "利馬", latitude: -120_443_583, longitude: -770_286_083), // Q5201438
        RealWorldPlace("santiago", .latinAmerica, "Santiago", "聖地牙哥", latitude: -334_519_444, longitude: -706_788_889), // Q28163126
        RealWorldPlace("saopaulo", .latinAmerica, "São Paulo", "聖保羅", latitude: -235_350_900, longitude: -466_352_800), // Q2983699
        RealWorldPlace("riodejaneiro", .latinAmerica, "Rio de Janeiro", "里約熱內盧", latitude: -229_034_139, longitude: -431_914_444), // Q1274003
        RealWorldPlace("belohorizonte", .latinAmerica, "Belo Horizonte", "貝洛奧里藏特", latitude: -199_178_747, longitude: -439_337_187), // Q10275642
        RealWorldPlace("brasilia", .latinAmerica, "Brasília", "巴西利亞", latitude: -157_933_333, longitude: -478_841_667), // Q10275643
    ]
}
