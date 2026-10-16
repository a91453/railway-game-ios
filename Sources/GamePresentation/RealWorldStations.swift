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
    /// owner's `city_map_reference_clean/source/data/city-catalog.json`, or
    /// Wikidata's point of the city itself.
    static let mainStations: [RealWorldPlace] = [
        // Japan
        RealWorldPlace("tokyo", "JP", .asia, "Tokyo", "東京", population: 33_441, latitude: 356_808_333, longitude: 1_397_669_444), // Q283196
        RealWorldPlace("yokohama", "JP", .asia, "Yokohama", "橫濱", population: 33_441, latitude: 354_658_333, longitude: 1_396_227_778), // Q801658
        RealWorldPlace("osaka", "JP", .asia, "Osaka", "大阪", population: 13_013, latitude: 347_025_000, longitude: 1_354_961_111), // Q801694
        RealWorldPlace("nagoya", "JP", .asia, "Nagoya", "名古屋", population: 7_160, latitude: 351_707_722, longitude: 1_368_816_028), // Q49381
        RealWorldPlace("sapporo", "JP", .asia, "Sapporo", "札幌", population: 1_968, latitude: 430_686_111, longitude: 1_413_507_778), // Q801404
        RealWorldPlace("fukuoka", "JP", .asia, "Fukuoka", "福岡", population: 2_230, latitude: 335_898_030, longitude: 1_304_206_810), // Q800875
        RealWorldPlace("kobe", "JP", .asia, "Kobe", "神戶", population: 13_013, latitude: 346_947_222, longitude: 1_351_950_000), // Q14616729
        RealWorldPlace("kyoto", "JP", .asia, "Kyoto", "京都", population: 13_013, latitude: 349_855_556, longitude: 1_357_586_111), // Q801046
        RealWorldPlace("kawasaki", "JP", .asia, "Kawasaki", "川崎", population: 33_441, latitude: 355_313_889, longitude: 1_396_969_444), // Q80562
        RealWorldPlace("saitama", "JP", .asia, "Saitama", "埼玉", population: 33_441, latitude: 359_063_889, longitude: 1_396_238_889), // Q801692
        RealWorldPlace("hiroshima", "JP", .asia, "Hiroshima", "廣島", population: 1_189, latitude: 343_983_333, longitude: 1_324_758_333), // Q576459
        RealWorldPlace("sendai", "JP", .asia, "Sendai", "仙台", population: 1_260, latitude: 382_602_778, longitude: 1_408_819_444), // Q801429
        RealWorldPlace("kitakyushu", "JP", .asia, "Kitakyushu", "北九州", population: 1_210, latitude: 338_869_230, longitude: 1_308_831_810), // Q801027
        RealWorldPlace("chiba", "JP", .asia, "Chiba", "千葉", population: 33_441, latitude: 356_131_222, longitude: 1_401_131_917), // Q800625
        RealWorldPlace("okayama", "JP", .asia, "Okayama", "岡山", population: 819, latitude: 346_663_694, longitude: 1_339_185_889), // Q801293
        RealWorldPlace("kumamoto", "JP", .asia, "Kumamoto", "熊本", population: 643, latitude: 327_893_389, longitude: 1_306_886_944), // Q969324
        RealWorldPlace("niigata", "JP", .asia, "Niigata", "新潟", population: 423, latitude: 379_120_278, longitude: 1_390_618_889), // Q701753
        RealWorldPlace("shizuoka", "JP", .asia, "Shizuoka", "靜岡", population: 330, latitude: 349_716_667, longitude: 1_383_888_889), // Q801440
        RealWorldPlace("hamamatsu", "JP", .asia, "Hamamatsu", "濱松", population: 283, latitude: 347_036_111, longitude: 1_377_344_444), // Q603640
        RealWorldPlace("kagoshima", "JP", .asia, "Kagoshima", "鹿兒島", population: 485, latitude: 315_836_667, longitude: 1_305_417_222), // Q1316913
        RealWorldPlace("naha", "JP", .asia, "Naha", "那霸", population: 1_060, latitude: 262_144_000, longitude: 1_276_790_000), // Q7484295
        // South Korea
        RealWorldPlace("busan", "KR", .asia, "Busan", "釜山", population: 3_269, latitude: 351_147_222, longitude: 1_290_419_444), // Q53118
        RealWorldPlace("incheon", "KR", .asia, "Incheon", "仁川", population: 22_465, latitude: 374_895_528, longitude: 1_267_240_722), // Q490474
        RealWorldPlace("daegu", "KR", .asia, "Daegu", "大邱", population: 2_339, latitude: 358_797_222, longitude: 1_286_292_167), // Q54288
        RealWorldPlace("daejeon", "KR", .asia, "Daejeon", "大田", population: 1_518, latitude: 363_318_944, longitude: 1_274_345_222), // Q20919
        RealWorldPlace("gwangju", "KR", .asia, "Gwangju", "光州", population: 1_442, latitude: 351_653_278, longitude: 1_269_092_361), // Q489731
        RealWorldPlace("ulsan", "KR", .asia, "Ulsan", "蔚山", population: 884, latitude: 355_391_190, longitude: 1_293_542_140), // Q626465
        RealWorldPlace("suwon", "KR", .asia, "Suwon", "水原", population: 22_465, latitude: 372_661_111, longitude: 1_269_997_222), // Q54306
        // North Korea
        RealWorldPlace("pyongyang", "KP", .asia, "Pyongyang", "平壤", population: 2_898, latitude: 390_047_222, longitude: 1_257_363_889), // Q701162
        // Southeast Asia
        RealWorldPlace("jakarta", "ID", .asia, "Jakarta", "雅加達", population: 41_629, latitude: -61_767_160, longitude: 1_068_305_080), // Q1889128
        RealWorldPlace("bandung", "ID", .asia, "Bandung", "萬隆", population: 8_872, latitude: -69_141_667, longitude: 1_076_025_000), // Q2571158
        RealWorldPlace("surabaya", "ID", .asia, "Surabaya", "泗水", population: 6_845, latitude: -72_653_200, longitude: 1_127_526_900), // Q2355304
        RealWorldPlace("manila", "PH", .asia, "Manila", "馬尼拉", population: 24_663, latitude: 146_114_000, longitude: 1_209_732_000), // Q7857053
        RealWorldPlace("bangkok", "TH", .asia, "Bangkok", "曼谷", population: 18_087, latitude: 138_050_000, longitude: 1_005_416_667), // Q23925684
        RealWorldPlace("kualalumpur", "MY", .asia, "Kuala Lumpur", "吉隆坡", population: 8_386, latitude: 31_340_000, longitude: 1_016_860_000), // Q801042
        RealWorldPlace("hochiminhcity", "VN", .asia, "Ho Chi Minh City", "胡志明市", population: 13_957, latitude: 107_822_200, longitude: 1_066_772_200), // Q2673539
        RealWorldPlace("hanoi", "VN", .asia, "Hanoi", "河內", population: 5_067, latitude: 210_241_700, longitude: 1_058_408_300), // Q1207323
        RealWorldPlace("yangon", "MM", .asia, "Yangon", "仰光", population: 5_599, latitude: 167_817_000, longitude: 961_611_000), // Q8048610
        // South Asia
        RealWorldPlace("dhaka", "BD", .asia, "Dhaka", "達卡", population: 36_191, latitude: 237_305_400, longitude: 904_268_600), // Q6355669
        RealWorldPlace("delhi", "IN", .asia, "Delhi", "德里", population: 30_110, latitude: 286_423_140, longitude: 772_200_040), // Q2742296
        RealWorldPlace("kolkata", "IN", .asia, "Kolkata", "加爾各答", population: 22_500, latitude: 225_828_709, longitude: 883_428_112), // Q986105
        RealWorldPlace("bengaluru", "IN", .asia, "Bengaluru", "班加羅爾", population: 13_159, latitude: 129_775_950, longitude: 775_680_830), // Q3633970
        RealWorldPlace("chennai", "IN", .asia, "Chennai", "清奈", population: 11_130, latitude: 130_847_613, longitude: 802_748_563), // Q257382
        RealWorldPlace("hyderabad", "IN", .asia, "Hyderabad", "海德拉巴", population: 9_173, latitude: 173_933_630, longitude: 784_673_770), // Q3633967
        RealWorldPlace("ahmedabad", "IN", .asia, "Ahmedabad", "艾哈邁達巴德", population: 7_616, latitude: 230_257_150, longitude: 726_017_160), // Q4696124
        RealWorldPlace("surat", "IN", .asia, "Surat", "蘇拉特", population: 6_877, latitude: 212_065_680, longitude: 728_407_930), // Q1851275
        RealWorldPlace("pune", "IN", .asia, "Pune", "浦那", population: 6_792, latitude: 185_293_780, longitude: 738_730_860), // Q3632576
        RealWorldPlace("karachi", "PK", .asia, "Karachi", "喀拉蚩", population: 21_214, latitude: 248_444_080, longitude: 670_425_580), // Q3605245
        RealWorldPlace("lahore", "PK", .asia, "Lahore", "拉合爾", population: 15_043, latitude: 315_772_000, longitude: 743_363_000), // Q3695748
        // West and Central Asia
        RealWorldPlace("istanbul", "TR", .asia, "Istanbul", "伊斯坦堡", population: 14_974, latitude: 410_149_669, longitude: 289_764_566), // Q800974
        RealWorldPlace("ankara", "TR", .asia, "Ankara", "安卡拉", population: 3_601, latitude: 399_359_990, longitude: 328_435_230), // Q800389
        RealWorldPlace("tehran", "IR", .asia, "Tehran", "德黑蘭", population: 9_146, latitude: 356_571_002, longitude: 513_973_437), // Q4453688
        RealWorldPlace("baghdad", "IQ", .asia, "Baghdad", "巴格達", population: 6_365, latitude: 333_236_110, longitude: 443_802_780), // Q3544831
        RealWorldPlace("riyadh", "SA", .asia, "Riyadh", "利雅德", population: 6_854, latitude: 246_504_000, longitude: 467_406_000), // Q30594324
        RealWorldPlace("doha", "QA", .asia, "Doha", "杜哈", population: 2_172, latitude: 252_834_389, longitude: 515_249_667), // Q25343654
        RealWorldPlace("dubai", "AE", .asia, "Dubai", "杜拜", population: 5_198, latitude: 252_547_222, longitude: 553_041_667), // Q4998050
        RealWorldPlace("baku", "AZ", .asia, "Baku", "巴庫", population: 1_973, latitude: 403_802_006, longitude: 498_503_910), // Q4076080
        RealWorldPlace("tbilisi", "GE", .asia, "Tbilisi", "第比利斯", population: 906, latitude: 417_233_333, longitude: 447_977_778), // Q1341835
        RealWorldPlace("yerevan", "AM", .asia, "Yerevan", "葉里溫", population: 1_086, latitude: 401_553_950, longitude: 445_085_390), // Q4176210
        RealWorldPlace("tashkent", "UZ", .asia, "Tashkent", "塔什干", population: 3_907, latitude: 413_123_363, longitude: 692_787_079), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("almaty", "KZ", .asia, "Almaty", "阿拉木圖", population: 2_348, latitude: 432_737_278, longitude: 769_391_111), // Q800371
        RealWorldPlace("astana", "KZ", .asia, "Astana", "阿斯塔納", population: 1_063, latitude: 511_956_750, longitude: 714_090_833), // Q800403
        // Europe
        RealWorldPlace("moscow", "RU", .europe, "Moscow", "莫斯科", population: 14_499, latitude: 557_762_611, longitude: 376_553_278), // Q1344454
        RealWorldPlace("saintpetersburg", "RU", .europe, "Saint Petersburg", "聖彼得堡", population: 4_738, latitude: 599_287_170, longitude: 303_624_330), // Q139318
        RealWorldPlace("barcelona", "ES", .europe, "Barcelona", "巴塞隆納", population: 3_972, latitude: 413_788_889, longitude: 21_400_000), // Q800453
        RealWorldPlace("amsterdam", "NL", .europe, "Amsterdam", "阿姆斯特丹", population: 1_227, latitude: 523_789_500, longitude: 49_001_600), // Q50719
        RealWorldPlace("vienna", "AT", .europe, "Vienna", "維也納", population: 2_026, latitude: 481_850_000, longitude: 163_777_778), // Q697300
        RealWorldPlace("brussels", "BE", .europe, "Brussels", "布魯塞爾", population: 1_404, latitude: 508_455_560, longitude: 43_572_220), // Q800588
        RealWorldPlace("prague", "CZ", .europe, "Prague", "布拉格", population: 1_196, latitude: 500_830_556, longitude: 144_358_333), // Q751174
        RealWorldPlace("budapest", "HU", .europe, "Budapest", "布達佩斯", population: 1_611, latitude: 475_005_556, longitude: 190_836_111), // Q841167
        RealWorldPlace("warsaw", "PL", .europe, "Warsaw", "華沙", population: 1_881, latitude: 522_286_111, longitude: 210_030_556), // Q693034
        RealWorldPlace("athens", "GR", .europe, "Athens", "雅典", population: 3_119, latitude: 379_929_400, longitude: 237_200_600), // Q3560693
        RealWorldPlace("lisbon", "PT", .europe, "Lisbon", "里斯本", population: 1_909, latitude: 387_140_203, longitude: -91_227_400), // Q531789
        RealWorldPlace("oslo", "NO", .europe, "Oslo", "奧斯陸", population: 871, latitude: 599_109_490, longitude: 107_525_360), // Q1410317
        RealWorldPlace("helsinki", "FI", .europe, "Helsinki", "赫爾辛基", population: 1_012, latitude: 601_710_483, longitude: 249_414_487), // Q1044613
        RealWorldPlace("bucharest", "RO", .europe, "Bucharest", "布加勒斯特", population: 1_912, latitude: 444_463_670, longitude: 260_742_080), // Q683346
        RealWorldPlace("sofia", "BG", .europe, "Sofia", "索菲亞", population: 1_068, latitude: 427_121_301, longitude: 233_211_209), // Q2095010
        RealWorldPlace("kyiv", "UA", .europe, "Kyiv", "基輔", population: 2_643, latitude: 504_404_500, longitude: 304_890_400), // Q2105249
        RealWorldPlace("minsk", "BY", .europe, "Minsk", "明斯克", population: 1_953, latitude: 538_906_667, longitude: 275_511_111), // Q801196
        // Africa
        RealWorldPlace("cairo", "EG", .oceaniaAndAfrica, "Cairo", "開羅", population: 25_410, latitude: 300_636_111, longitude: 312_472_222), // Q633754
        RealWorldPlace("alexandria", "EG", .oceaniaAndAfrica, "Alexandria", "亞歷山卓", population: 7_227, latitude: 311_933_333, longitude: 299_063_056), // Q958574
        RealWorldPlace("algiers", "DZ", .oceaniaAndAfrica, "Algiers", "阿爾及爾", population: 3_231, latitude: 367_792_000, longitude: 30_618_200), // Q3095611
        RealWorldPlace("khartoum", "SD", .oceaniaAndAfrica, "Khartoum", "喀土穆", population: 6_771, latitude: 155_517_700, longitude: 325_324_100), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("addisababa", "ET", .oceaniaAndAfrica, "Addis Ababa", "阿迪斯阿貝巴", population: 6_626, latitude: 90_094_722, longitude: 387_532_222), // Q3968826
        RealWorldPlace("kinshasa", "CD", .oceaniaAndAfrica, "Kinshasa", "金夏沙", population: 10_895, latitude: -43_006_000, longitude: 153_190_000), // Q3098110
        RealWorldPlace("luanda", "AO", .oceaniaAndAfrica, "Luanda", "羅安達", population: 11_211, latitude: -88_053_200, longitude: 132_442_720), // Q65170215
        RealWorldPlace("daressalaam", "TZ", .oceaniaAndAfrica, "Dar es Salaam", "三蘭港", population: 7_701, latitude: -68_160_837, longitude: 392_803_583), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("johannesburg", "ZA", .oceaniaAndAfrica, "Johannesburg", "約翰尼斯堡", population: 7_021, latitude: -261_972_220, longitude: 280_419_440), // Q5175720
        // Oceania
        RealWorldPlace("sydney", "AU", .oceaniaAndAfrica, "Sydney", "雪梨", population: 4_143, latitude: -338_825_000, longitude: 1_512_066_667), // Q1585639
        // United States
        RealWorldPlace("houston", "US", .americas, "Houston", "休士頓", population: 3_904, latitude: 297_673_000, longitude: -953_675_000), // Q9294212
        RealWorldPlace("dallas", "US", .americas, "Dallas", "達拉斯", population: 1_517, latitude: 327_753_823, longitude: -968_077_500), // Q5371609
        RealWorldPlace("philadelphia", "US", .americas, "Philadelphia", "費城", population: 2_232, latitude: 399_558_220, longitude: -751_824_000), // Q224214
        RealWorldPlace("atlanta", "US", .americas, "Atlanta", "亞特蘭大", population: 455, latitude: 337_538_000, longitude: -843_916_000), // Q5456094
        // Latin America
        RealWorldPlace("mexicocity", "MX", .americas, "Mexico City", "墨西哥城", population: 17_722, latitude: 194_478_000, longitude: -991_522_000), // Q54867396
        RealWorldPlace("panamacity", "PA", .americas, "Panama City", "巴拿馬城", population: 1_515, latitude: 89_735_000, longitude: -795_495_000), // Q25420956
        RealWorldPlace("santodomingo", "DO", .americas, "Santo Domingo", "聖多明哥", population: 4_581, latitude: 184_711_111, longitude: -699_116_667), // Q25421631
        RealWorldPlace("caracas", "VE", .americas, "Caracas", "卡拉卡斯", population: 2_581, latitude: 105_048_974, longitude: -669_176_005), // Q11294573
        RealWorldPlace("bogota", "CO", .americas, "Bogotá", "波哥大", population: 10_555, latitude: 46_072_778, longitude: -740_832_222), // Q6433290
        RealWorldPlace("quito", "EC", .americas, "Quito", "基多", population: 2_524, latitude: -1_692_388, longitude: -785_043_144), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("lima", "PE", .americas, "Lima", "利馬", population: 10_526, latitude: -120_443_583, longitude: -770_286_083), // Q5201438
        RealWorldPlace("santiago", "CL", .americas, "Santiago", "聖地牙哥", population: 6_710, latitude: -334_519_444, longitude: -706_788_889), // Q28163126
        RealWorldPlace("saopaulo", "BR", .americas, "São Paulo", "聖保羅", population: 18_935, latitude: -235_350_900, longitude: -466_352_800), // Q2983699
        RealWorldPlace("riodejaneiro", "BR", .americas, "Rio de Janeiro", "里約熱內盧", population: 9_492, latitude: -229_034_139, longitude: -431_914_444), // Q1274003
        RealWorldPlace("belohorizonte", "BR", .americas, "Belo Horizonte", "貝洛奧里藏特", population: 4_161, latitude: -199_178_747, longitude: -439_337_187), // Q10275642
        RealWorldPlace("brasilia", "BR", .americas, "Brasília", "巴西利亞", population: 1_508, latitude: -157_933_333, longitude: -478_841_667), // Q10275643
        // More of Asia
        RealWorldPlace("shantou", "CN", .asia, "Shantou", "汕頭", population: 6_384, latitude: 233_746_389, longitude: 1_167_509_444), // Q11133513
        RealWorldPlace("quanzhou", "CN", .asia, "Quanzhou", "泉州", population: 3_288, latitude: 249_766_667, longitude: 1_185_630_556), // Q7269119
        RealWorldPlace("hefei", "CN", .asia, "Hefei", "合肥", population: 4_866, latitude: 318_877_778, longitude: 1_173_116_667), // Q988005
        RealWorldPlace("taiyuan", "CN", .asia, "Taiyuan", "太原", population: 3_999, latitude: 378_599_000, longitude: 1_125_820_000), // Q988020
        RealWorldPlace("lucknow", "IN", .asia, "Lucknow", "勒克瑙", population: 5_028, latitude: 268_306_750, longitude: 809_252_910), // Q3633969
        RealWorldPlace("kozhikode", "IN", .asia, "Kozhikode", "科澤科德", population: 6_098, latitude: 112_462_340, longitude: 757_804_070), // Q6435240
        RealWorldPlace("kochi", "IN", .asia, "Kochi", "科欽", population: 5_055, latitude: 99_695_420, longitude: 762_906_720), // Q5392599
        RealWorldPlace("faisalabad", "PK", .asia, "Faisalabad", "費薩拉巴德", population: 5_530, latitude: 314_172_220, longitude: 730_966_670), // Q5431105
        RealWorldPlace("islamabad", "PK", .asia, "Islamabad", "伊斯蘭馬巴德", population: 4_826, latitude: 336_036_000, longitude: 730_483_000), // Q7296934
        RealWorldPlace("kabul", "AF", .asia, "Kabul", "喀布爾", population: 5_595, latitude: 345_281_300, longitude: 691_723_300), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("colombo", "LK", .asia, "Colombo", "可倫坡", population: 5_198, latitude: 69_336_110, longitude: 798_508_330), // Q5471883
        RealWorldPlace("mashhad", "IR", .asia, "Mashhad", "馬什哈德", population: 5_378, latitude: 363_046_661, longitude: 596_248_039), // Q5941905
        RealWorldPlace("jeddah", "SA", .asia, "Jeddah", "吉達", population: 4_245, latitude: 215_504_432, longitude: 391_742_363), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("amman", "JO", .asia, "Amman", "安曼", population: 6_379, latitude: 319_686_111, longitude: 359_686_111), // Q133456388
        // More of Europe
        RealWorldPlace("essen", "DE", .europe, "Essen", "埃森", population: 2_715, latitude: 514_513_889, longitude: 70_138_889), // Q135607
        // More of Africa
        RealWorldPlace("nairobi", "KE", .oceaniaAndAfrica, "Nairobi", "奈洛比", population: 6_080, latitude: -12_916_640, longitude: 368_286_190), // Q6959799
        RealWorldPlace("abidjan", "CI", .oceaniaAndAfrica, "Abidjan", "阿必尚", population: 6_566, latitude: 54_091_179, longitude: -40_422_099), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("accra", "GH", .oceaniaAndAfrica, "Accra", "阿克拉", population: 5_554, latitude: 55_571_096, longitude: -2_012_376), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("kumasi", "GH", .oceaniaAndAfrica, "Kumasi", "庫馬西", population: 4_269, latitude: 66_884_800, longitude: -16_244_300), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("onitsha", "NG", .oceaniaAndAfrica, "Onitsha", "奧尼查", population: 5_561, latitude: 61_329_559, longitude: 67_923_838), // Q852238 (the city: no station)
        RealWorldPlace("yaounde", "CM", .oceaniaAndAfrica, "Yaoundé", "雅溫德", population: 5_039, latitude: 38_578_000, longitude: 115_181_000), // no station: the city's centre in `city-catalog.json`
        RealWorldPlace("kampala", "UG", .oceaniaAndAfrica, "Kampala", "坎帕拉", population: 4_816, latitude: 3_177_137, longitude: 325_813_539), // no station: the city's centre in `city-catalog.json`
    ]
}
