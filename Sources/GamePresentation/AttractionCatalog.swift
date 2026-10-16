import GameCore

// The sights of Taiwan a real-world game starts with (ARCHITECTURE decision
// 174). The list began as OpenWorld's `destination-catalog.js`
// (`OpenWorld/reference_snapshot/play/src/world/destination-catalog.js` of
// the owner's reference repository) without the places a railway cannot
// reach (the offshore islands) and the invented ones, with the hot springs
// and the Pingxi sky lanterns added; decision 249 added the island's famous
// sights round its towns (`t…`), so that a 16 km map where people live
// usually has two to five. The places are put on the map by
// `tools/tourism-spots/build_tourism_spots.py` from OpenStreetMap
// (ODbL 1.0), which writes `tools/tourism-spots/taiwan_attractions.json`;
// `TourismSessionTests` checks this table against that file. It is Swift
// rather than a resource because every new game reads its short rows.

public enum AttractionCatalog {
    /// One place: its reference key, names, kind, rating in hundredths of a
    /// star, and where it is on the Earth in degrees.
    public struct Spot: Hashable, Sendable {
        public let id: String
        public let name: String
        public let englishName: String
        public let kind: AttractionKind
        public let stars: Int
        public let latitude: Double
        public let longitude: Double

        init(_ id: String, _ name: String, _ englishName: String, _ kind: AttractionKind, _ stars: Int, _ latitude: Double, _ longitude: Double) {
            self.id = id
            self.name = name
            self.englishName = englishName
            self.kind = kind
            self.stars = stars
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public static let spots: [Spot] = [
        Spot("s01", "墾丁・小灣", "Kenting Xiaowan", .coast, 400, 21.94509, 120.79897),
        Spot("s02", "九份", "Jiufen", .town, 400, 25.10873, 121.84357),
        Spot("s04", "清水斷崖", "Qingshui Cliff", .mountain, 400, 24.21887, 121.68914),
        Spot("s06", "日月潭", "Sun Moon Lake", .mountain, 450, 23.85472, 120.91679),
        Spot("s07", "阿里山", "Alishan", .mountain, 450, 23.50863, 120.80127),
        Spot("s08", "太魯閣", "Taroko", .mountain, 450, 24.1555, 121.62163),
        Spot("s09", "野柳", "Yehliu", .coast, 350, 25.20535, 121.69142),
        Spot("s11", "合歡山", "Hehuanshan", .mountain, 350, 24.13204, 121.29521),
        Spot("s12", "高美濕地", "Gaomei Wetlands", .coast, 350, 24.31111, 120.56278),
        Spot("s15", "池上伯朗大道", "Chishang Brown Avenue", .mountain, 300, 23.1243, 121.2208),
        Spot("s16", "七星潭", "Qixingtan", .coast, 300, 24.03844, 121.6242),
        Spot("s17", "陽明山擎天崗", "Qingtiangang", .mountain, 300, 25.16498, 121.57558),
        Spot("s18", "清境", "Qingjing", .mountain, 350, 24.04585, 121.15662),
        Spot("s20", "玉山群峰", "Yushan", .mountain, 400, 23.54289, 120.90859),
        Spot("s21", "遠雄海洋公園", "Farglory Ocean Park", .town, 300, 23.90155, 121.60149),
        Spot("s23", "陶朱隱園", "Taozhu Yinyuan", .town, 300, 25.0386, 121.5704),
        Spot("s25", "淡江大橋", "Danjiang Bridge", .town, 250, 25.1753, 121.4178),
        Spot("s26", "麗寶賽車場", "Lihpao Racing Park", .town, 250, 24.32392, 120.69589),
        Spot("s27", "Xpark・水族探索", "Xpark", .town, 350, 25.01713, 121.21404),
        Spot("h01", "北投溫泉", "Beitou Hot Springs", .hotSpring, 350, 25.13661, 121.50713),
        Spot("h02", "烏來溫泉", "Wulai Hot Springs", .hotSpring, 350, 24.86416, 121.55144),
        Spot("h03", "礁溪溫泉", "Jiaoxi Hot Springs", .hotSpring, 350, 24.82117, 121.76991),
        Spot("h04", "關子嶺溫泉", "Guanziling Hot Springs", .hotSpring, 300, 23.33952, 120.50412),
        Spot("h05", "四重溪溫泉", "Sichongxi Hot Springs", .hotSpring, 300, 22.08335, 120.73428),
        Spot("p01", "平溪天燈", "Pingxi Sky Lanterns", .town, 350, 25.04266, 121.77678),
        Spot("t001", "台北101", "Taipei 101", .town, 350, 25.03393, 121.56461),
        Spot("t002", "中正紀念堂", "Chiang Kai-shek Memorial Hall", .town, 350, 25.03479, 121.52149),
        Spot("t003", "國立故宮博物院", "National Palace Museum", .town, 350, 25.10204, 121.54908),
        Spot("t004", "艋舺龍山寺", "Lungshan Temple", .town, 300, 25.03726, 121.49986),
        Spot("t005", "西門町", "Ximending", .town, 300, 25.04203, 121.5073),
        Spot("t006", "士林夜市", "Shilin Night Market", .town, 300, 25.08881, 121.52495),
        Spot("t007", "大稻埕迪化街", "Dadaocheng", .town, 300, 25.05591, 121.51004),
        Spot("t008", "象山", "Elephant Mountain", .mountain, 250, 25.02654, 121.57554),
        Spot("t009", "貓空", "Maokong", .mountain, 300, 24.96891, 121.58821),
        Spot("t010", "臺北市立動物園", "Taipei Zoo", .town, 300, 24.99584, 121.58535),
        Spot("t011", "國父紀念館", "Sun Yat-sen Memorial Hall", .town, 250, 25.04, 121.56028),
        Spot("t012", "饒河街夜市", "Raohe Night Market", .town, 250, 25.05055, 121.57543),
        Spot("t013", "華山1914文創園區", "Huashan 1914", .town, 250, 25.04471, 121.529),
        Spot("t014", "竹子湖", "Zhuzihu", .mountain, 250, 25.16828, 121.53937),
        Spot("t015", "淡水老街", "Tamsui Old Street", .town, 350, 25.16968, 121.44075),
        Spot("t016", "淡水漁人碼頭", "Tamsui Fisherman's Wharf", .coast, 300, 25.18355, 121.40865),
        Spot("t017", "紅毛城", "Fort San Domingo", .town, 300, 25.17534, 121.43292),
        Spot("t018", "猴硐貓村", "Houtong Cat Village", .town, 250, 25.08714, 121.82657),
        Spot("t019", "三峽老街", "Sanxia Old Street", .town, 300, 24.93373, 121.3698),
        Spot("t020", "鶯歌老街", "Yingge Old Street", .town, 300, 24.95164, 121.3488),
        Spot("t021", "深坑老街", "Shenkeng Old Street", .town, 250, 25.0015, 121.6141),
        Spot("t022", "白沙灣", "Baishawan Beach", .coast, 250, 25.28454, 121.51688),
        Spot("t023", "福隆海水浴場", "Fulong Beach", .coast, 300, 25.01987, 121.94825),
        Spot("t024", "鼻頭角", "Bitou Cape", .coast, 250, 25.12693, 121.92238),
        Spot("t025", "三貂角燈塔", "Sandiao Cape Lighthouse", .coast, 250, 25.00742, 122.00108),
        Spot("t026", "碧潭", "Bitan", .town, 250, 24.95523, 121.53537),
        Spot("t027", "朱銘美術館", "Juming Museum", .town, 250, 25.24449, 121.61078),
        Spot("t028", "富貴角燈塔", "Fuguijiao Lighthouse", .coast, 250, 25.29835, 121.53759),
        Spot("t029", "坪林茶鄉", "Pinglin Tea Town", .mountain, 250, 24.93715, 121.71156),
        Spot("t030", "林本源園邸", "Lin Family Garden", .town, 250, 25.0107, 121.45473),
        Spot("t031", "基隆廟口夜市", "Keelung Miaokou Night Market", .town, 300, 25.12855, 121.74285),
        Spot("t032", "和平島", "Heping Island", .coast, 300, 25.16092, 121.76693),
        Spot("t033", "正濱漁港", "Zhengbin Fishing Port", .coast, 250, 25.1525, 121.76899),
        Spot("t034", "八斗子潮境", "Badouzi", .coast, 250, 25.14493, 121.79217),
        Spot("t035", "大溪老街", "Daxi Old Street", .town, 300, 24.88536, 121.28737),
        Spot("t036", "慈湖", "Cihu", .town, 250, 24.84063, 121.29518),
        Spot("t037", "石門水庫", "Shimen Reservoir", .mountain, 250, 24.81315, 121.24555),
        Spot("t038", "小人國", "Window on China", .town, 250, 24.846, 121.212),
        Spot("t039", "拉拉山", "Lalashan", .mountain, 300, 24.73038, 121.43411),
        Spot("t040", "角板山", "Jiaobanshan", .mountain, 250, 24.8166, 121.34971),
        Spot("t041", "永安漁港", "Yong'an Fishing Port", .coast, 200, 24.98899, 121.01425),
        Spot("t042", "桃園忠烈祠", "Taoyuan Martyrs' Shrine", .town, 200, 25.00615, 121.3251),
        Spot("t043", "六福村", "Leofoo Village", .town, 300, 24.82025, 121.18114),
        Spot("t044", "新竹城隍廟", "Hsinchu City God Temple", .town, 300, 24.80433, 120.96602),
        Spot("t045", "南寮漁港", "Nanliao Fishing Port", .coast, 250, 24.84962, 120.92889),
        Spot("t046", "香山濕地", "Xiangshan Wetland", .coast, 250, 24.78355, 120.91498),
        Spot("t047", "內灣老街", "Neiwan Old Street", .town, 300, 24.70621, 121.18102),
        Spot("t048", "北埔老街", "Beipu Old Street", .town, 250, 24.69994, 121.0577),
        Spot("t049", "司馬庫斯", "Smangus", .mountain, 300, 24.578, 121.336),
        Spot("t050", "勝興車站", "Shengxing Station", .town, 300, 24.39264, 120.78819),
        Spot("t051", "龍騰斷橋", "Longteng Bridge Ruins", .mountain, 300, 24.35862, 120.7732),
        Spot("t052", "三義木雕街", "Sanyi Wood Carving Street", .town, 250, 24.40594, 120.76106),
        Spot("t053", "南庄老街", "Nanzhuang Old Street", .town, 300, 24.59906, 120.9992),
        Spot("t054", "泰安溫泉", "Tai'an Hot Springs", .hotSpring, 300, 24.47151, 120.9787),
        Spot("t055", "通霄海水浴場", "Tongxiao Beach", .coast, 250, 24.49612, 120.67093),
        Spot("t056", "好望角", "Haowangjiao", .coast, 200, 24.60194, 120.73119),
        Spot("t057", "逢甲夜市", "Fengjia Night Market", .town, 350, 24.17821, 120.64599),
        Spot("t058", "彩虹眷村", "Rainbow Village", .town, 250, 24.13378, 120.60993),
        Spot("t059", "臺中國家歌劇院", "National Taichung Theater", .town, 250, 24.16287, 120.64039),
        Spot("t060", "宮原眼科", "Miyahara", .town, 250, 24.138, 120.684),
        Spot("t061", "路思義教堂", "Luce Memorial Chapel", .town, 250, 24.17889, 120.60053),
        Spot("t062", "大甲鎮瀾宮", "Dajia Jenn Lann Temple", .town, 300, 24.34527, 120.62346),
        Spot("t063", "梧棲漁港", "Wuqi Fishing Port", .coast, 250, 24.29231, 120.51778),
        Spot("t064", "谷關溫泉", "Guguan Hot Springs", .hotSpring, 300, 24.20353, 121.00684),
        Spot("t065", "武陵農場", "Wuling Farm", .mountain, 300, 24.37663, 121.30872),
        Spot("t066", "新社花海", "Xinshe", .mountain, 250, 24.18826, 120.81167),
        Spot("t067", "后豐鐵馬道", "Houfeng Bikeway", .town, 250, 24.28523, 120.72951),
        Spot("t068", "霧峰林家", "Wufeng Lin Family Mansion", .town, 200, 24.06308, 120.70124),
        Spot("t069", "鹿港老街", "Lukang Old Street", .town, 350, 24.05595, 120.43295),
        Spot("t070", "八卦山大佛", "Baguashan Buddha", .town, 300, 24.07857, 120.54887),
        Spot("t071", "彰化扇形車庫", "Changhua Roundhouse", .town, 300, 24.08611, 120.54013),
        Spot("t072", "田尾公路花園", "Tianwei Highway Garden", .town, 250, 23.89612, 120.53123),
        Spot("t073", "王功漁港", "Wanggong Fishing Port", .coast, 250, 23.96904, 120.32455),
        Spot("t074", "集集車站", "Jiji Station", .town, 300, 23.82688, 120.78543),
        Spot("t075", "溪頭", "Xitou", .mountain, 300, 23.6741, 120.79637),
        Spot("t076", "埔里酒廠", "Puli Winery", .town, 250, 23.9693, 120.96009),
        Spot("t077", "九族文化村", "Formosan Aboriginal Culture Village", .town, 300, 23.86607, 120.94836),
        Spot("t078", "車埕", "Checheng", .town, 250, 23.83335, 120.86576),
        Spot("t079", "奧萬大", "Aowanda", .mountain, 250, 23.95343, 121.17752),
        Spot("t080", "東埔溫泉", "Dongpu Hot Springs", .hotSpring, 300, 23.56519, 120.93197),
        Spot("t081", "中台禪寺", "Chung Tai Chan Monastery", .town, 250, 24.00924, 120.94455),
        Spot("t082", "北港朝天宮", "Beigang Chaotian Temple", .town, 350, 23.56811, 120.30467),
        Spot("t083", "劍湖山世界", "Janfusun Fancyworld", .town, 300, 23.61789, 120.57778),
        Spot("t084", "西螺大橋", "Xiluo Bridge", .town, 250, 23.80616, 120.46073),
        Spot("t085", "虎尾糖廠", "Huwei Sugar Factory", .town, 200, 23.709, 120.432),
        Spot("t086", "斗六太平老街", "Douliu Taiping Old Street", .town, 200, 23.70875, 120.542),
        Spot("t087", "檜意森活村", "Hinoki Village", .town, 250, 23.48574, 120.45433),
        Spot("t088", "奮起湖", "Fenqihu", .mountain, 300, 23.50227, 120.69666),
        Spot("t089", "故宮南院", "Southern Branch of the Palace Museum", .town, 300, 23.47383, 120.29235),
        Spot("t090", "東石漁人碼頭", "Dongshi Fisherman's Wharf", .coast, 250, 23.45109, 120.13529),
        Spot("t091", "新港奉天宮", "Xingang Fengtian Temple", .town, 250, 23.55678, 120.34789),
        Spot("t092", "赤崁樓", "Chihkan Tower", .town, 350, 22.99736, 120.20268),
        Spot("t093", "安平古堡", "Anping Old Fort", .town, 350, 23.0013, 120.16051),
        Spot("t094", "神農街", "Shennong Street", .town, 250, 22.99783, 120.19596),
        Spot("t095", "臺南孔廟", "Tainan Confucius Temple", .town, 250, 22.99036, 120.20406),
        Spot("t096", "奇美博物館", "Chimei Museum", .town, 350, 22.93438, 120.22618),
        Spot("t097", "四草綠色隧道", "Sicao Green Tunnel", .coast, 250, 23.0209, 120.13482),
        Spot("t098", "七股鹽山", "Qigu Salt Mountain", .coast, 300, 23.15418, 120.1042),
        Spot("t099", "井仔腳瓦盤鹽田", "Jingzaijiao Salt Field", .coast, 200, 23.187, 120.079),
        Spot("t100", "烏山頭水庫", "Wushantou Reservoir", .mountain, 250, 23.2078, 120.36983),
        Spot("t101", "新化老街", "Xinhua Old Street", .town, 200, 23.038, 120.31),
        Spot("t102", "十鼓文創園區", "Ten Drum Culture Village", .town, 200, 22.93904, 120.23098),
        Spot("t103", "麻豆代天府", "Madou Daitian Temple", .town, 200, 23.19024, 120.26013),
        Spot("t104", "駁二藝術特區", "The Pier-2 Art Center", .town, 300, 22.61958, 120.28213),
        Spot("t105", "旗津", "Cijin", .coast, 300, 22.61326, 120.26858),
        Spot("t106", "西子灣", "Sizihwan", .coast, 300, 22.6235, 120.26238),
        Spot("t107", "蓮池潭", "Lotus Pond", .town, 300, 22.67865, 120.29704),
        Spot("t108", "六合夜市", "Liuhe Night Market", .town, 250, 22.63233, 120.2998),
        Spot("t109", "佛光山", "Fo Guang Shan", .town, 350, 22.75492, 120.44743),
        Spot("t110", "義大世界", "E-DA World", .town, 300, 22.73089, 120.40897),
        Spot("t111", "高雄85大樓", "85 Sky Tower", .town, 250, 22.61165, 120.30013),
        Spot("t112", "衛武營", "Weiwuying", .town, 250, 22.62671, 120.34326),
        Spot("t113", "美濃", "Meinong", .town, 250, 22.91116, 120.55747),
        Spot("t114", "旗山老街", "Qishan Old Street", .town, 250, 22.88461, 120.48192),
        Spot("t115", "寶來溫泉", "Baolai Hot Springs", .hotSpring, 250, 23.108, 120.702),
        Spot("t116", "茂林", "Maolin", .mountain, 250, 22.88442, 120.66534),
        Spot("t117", "田寮月世界", "Tianliao Moon World", .mountain, 250, 22.88784, 120.38774),
        Spot("t118", "澄清湖", "Chengcing Lake", .town, 250, 22.65631, 120.35166),
        Spot("t119", "鵝鑾鼻燈塔", "Eluanbi Lighthouse", .coast, 350, 21.90196, 120.85163),
        Spot("t120", "國立海洋生物博物館", "National Museum of Marine Biology and Aquarium", .coast, 350, 22.04604, 120.69833),
        Spot("t121", "大鵬灣", "Dapeng Bay", .coast, 250, 22.45426, 120.47636),
        Spot("t122", "台灣原住民族文化園區", "Indigenous Peoples Cultural Park", .town, 250, 22.70771, 120.6569),
        Spot("t123", "勝利星村", "Victory Village", .town, 200, 22.67824, 120.48456),
        Spot("t124", "恆春古城", "Hengchun Old Town", .town, 250, 22.001, 120.746),
        Spot("t125", "佳樂水", "Jialeshui", .coast, 250, 22.00655, 120.877),
        Spot("t126", "國立傳統藝術中心", "National Center for Traditional Arts", .town, 300, 24.68614, 121.82236),
        Spot("t127", "羅東夜市", "Luodong Night Market", .town, 300, 24.67628, 121.76862),
        Spot("t128", "蘇澳冷泉", "Su'ao Cold Spring", .hotSpring, 300, 24.5968, 121.851),
        Spot("t129", "南方澳", "Nanfang'ao", .coast, 250, 24.58523, 121.87186),
        Spot("t130", "太平山", "Taipingshan", .mountain, 350, 24.49282, 121.53502),
        Spot("t131", "外澳海灘", "Waiao Beach", .coast, 250, 24.87736, 121.84328),
        Spot("t132", "蘭陽博物館", "Lanyang Museum", .town, 250, 24.86882, 121.83265),
        Spot("t133", "梅花湖", "Meihua Lake", .mountain, 200, 24.64307, 121.73286),
        Spot("t134", "鳩之澤溫泉", "Jiuzhize Hot Springs", .hotSpring, 250, 24.587, 121.515),
        Spot("t135", "東大門夜市", "Dongdamen Night Market", .town, 300, 23.97239, 121.61067),
        Spot("t136", "鯉魚潭", "Liyu Lake", .mountain, 250, 23.92938, 121.506),
        Spot("t137", "瑞穗溫泉", "Ruisui Hot Springs", .hotSpring, 250, 23.49652, 121.34329),
        Spot("t138", "六十石山", "Liushidan Mountain", .mountain, 300, 23.124, 121.278),
        Spot("t139", "石梯坪", "Shitiping", .coast, 250, 23.4908, 121.51007),
        Spot("t140", "林田山", "Lintianshan", .town, 200, 23.71856, 121.40157),
        Spot("t141", "三仙台", "Sanxiantai", .coast, 300, 23.12363, 121.41272),
        Spot("t142", "多良車站", "Duoliang Station", .coast, 300, 22.50754, 120.9589),
        Spot("t143", "知本溫泉", "Zhiben Hot Springs", .hotSpring, 300, 22.69606, 121.02412),
        Spot("t144", "鹿野高台", "Luye Highland", .mountain, 300, 22.91597, 121.12075),
        Spot("t145", "鐵花村", "Tiehua Village", .town, 250, 22.75322, 121.14605),
        Spot("t146", "小野柳", "Xiaoyeliu", .coast, 250, 22.79448, 121.19585),
        Spot("t147", "新莊廟街", "Xinzhuang Temple Street", .town, 200, 25.03633, 121.45336),
        Spot("t148", "林口竹林山觀音寺", "Zhulinshan Guanyin Temple", .town, 200, 25.0825, 121.39067),
        Spot("t149", "埔心牧場", "Puxin Ranch", .town, 250, 24.92, 121.181),
        Spot("t150", "竹圍漁港", "Zhuwei Fishing Port", .coast, 250, 25.11732, 121.24224),
        Spot("t151", "承天禪寺", "Chengtian Temple", .mountain, 200, 24.975, 121.429),
        Spot("t152", "新瓦屋客家文化保存區", "Xinwawu Hakka Village", .town, 200, 24.81203, 121.02707),
        Spot("t153", "東港東隆宮", "Donglong Temple", .town, 300, 22.46305, 120.44879),
        Spot("t154", "九二一地震教育園區", "921 Earthquake Museum", .town, 250, 24.04229, 120.69888),
        Spot("t155", "汐止拱北殿", "Gongbei Temple", .mountain, 200, 25.09439, 121.64195),
        Spot("t156", "大樹舊鐵橋", "Old Iron Bridge of Dashu", .town, 250, 22.65575, 120.42935),
        Spot("t157", "橋頭糖廠", "Qiaotou Sugar Factory", .town, 250, 22.75522, 120.31552),
        Spot("t158", "國立臺灣歷史博物館", "National Museum of Taiwan History", .town, 250, 23.05887, 120.23387),
        Spot("t159", "望高寮", "Wanggaoliao", .mountain, 200, 24.14514, 120.57807),
        Spot("t160", "嘉義文化路夜市", "Chiayi Wenhua Road Night Market", .town, 250, 23.48081, 120.44939),
        Spot("t161", "蘭潭", "Lantan Lake", .mountain, 200, 23.46562, 120.48099),
        Spot("t162", "百果山", "Baiguoshan", .mountain, 200, 23.94677, 120.60655),
        Spot("t163", "富岡老街", "Fugang Old Street", .town, 200, 24.93517, 121.08306),
        Spot("t164", "虎頭埤", "Hutoupi", .mountain, 250, 23.02847, 120.34075),
        Spot("t165", "豐原廟東夜市", "Fengyuan Miaodong Night Market", .town, 200, 24.25121, 120.7193),
        Spot("t166", "石岡水壩", "Shigang Dam", .mountain, 200, 24.277, 120.781),
        Spot("t167", "崎頂海水浴場", "Qiding Beach", .coast, 200, 24.72288, 120.86524),
        Spot("t168", "苗栗鐵道文物展示館", "Miaoli Railway Museum", .town, 200, 24.57, 120.822),
        Spot("t169", "萬金聖母聖殿", "Wanjin Basilica", .town, 200, 22.59508, 120.61117),
        Spot("t170", "幾米廣場", "Jimmy Square", .town, 200, 24.75249, 121.75692),
        Spot("t171", "冬山河親水公園", "Dongshan River Water Park", .town, 250, 24.63828, 121.79012),
        Spot("t172", "古坑華山", "Gukeng Huashan", .mountain, 200, 23.637, 120.606),
        Spot("t173", "中興新村", "Zhongxing New Village", .town, 200, 23.95721, 120.68769),
        Spot("t174", "湖口老街", "Hukou Old Street", .town, 250, 24.87724, 121.05832),
        Spot("t175", "南鯤鯓代天府", "Nankunshen Daitian Temple", .town, 300, 23.28584, 120.14344),
        Spot("t176", "阿公店水庫", "Agongdian Reservoir", .mountain, 200, 22.82115, 120.3571),
        Spot("t177", "蚵仔寮漁港", "Keziliao Fishing Port", .coast, 200, 22.72549, 120.25244),
        Spot("t178", "菁寮老街", "Jingliao Old Street", .town, 200, 23.355, 120.357),
        Spot("t179", "山上花園水道博物館", "Shanshang Water Museum", .town, 200, 23.0871, 120.35988),
        Spot("t180", "尖山埤", "Jianshanpi", .mountain, 200, 23.26269, 120.39143),
        Spot("t181", "明德水庫", "Mingde Reservoir", .mountain, 200, 24.58652, 120.89707),
        Spot("t182", "草漯沙丘", "Caota Sand Dunes", .coast, 250, 25.07447, 121.13145),
        Spot("t183", "鹽水月津港", "Yueijin Harbor", .town, 250, 23.31745, 120.26603),
        Spot("t184", "吉安慶修院", "Qingxiu Temple", .town, 200, 23.9736, 121.56457),
        Spot("t185", "紅毛港文化園區", "Hongmaogang Cultural Park", .coast, 200, 22.55064, 120.31799),
        Spot("t186", "松柏嶺受天宮", "Songbailing Shoutian Temple", .mountain, 250, 23.889, 120.656),
        Spot("t187", "苑裡藺草文化館", "Yuanli Rush Weaving Museum", .town, 200, 24.414, 120.651),
        Spot("t188", "初鹿牧場", "Chulu Ranch", .mountain, 250, 22.802, 121.074),
        Spot("t189", "雲中街生活聚落", "Yunzhong Street Settlement", .town, 200, 23.70835, 120.53995),
    ]

    /// The spots that lie inside a world of `bounds` laid over the Earth as
    /// `frame` says, as attractions numbered from 1 in the catalog's order.
    /// Empty away from Taiwan.
    public static func attractions(in frame: RealWorldFrame, bounds: WorldBounds, only ids: Set<String>? = nil) -> [Attraction] {
        var found: [Attraction] = []
        for spot in spots where ids?.contains(spot.id) ?? true {
            let position = frame.worldPosition(latitude: spot.latitude, longitude: spot.longitude)
            guard position.x >= 0, position.y >= 0, position.x < Double(bounds.width), position.y < Double(bounds.height) else { continue }
            found.append(Attraction(
                id: AttractionID(rawValue: found.count + 1), name: spot.name, englishName: spot.englishName,
                point: PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded())), kind: spot.kind, baseStars: spot.stars
            ))
        }
        return found
    }
}
