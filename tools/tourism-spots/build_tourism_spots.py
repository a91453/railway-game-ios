#!/usr/bin/env python3
"""Coordinates of the game's tourist attractions (ARCHITECTURE decisions 174
and 250).

The spots are the ones in the owner's OpenWorld `destination-catalog.js`
(27 rows) a railway can reach, plus the hot springs and the Pingxi sky
lanterns the game adds. The catalog has no coordinates, so each spot is
looked up by name in the OpenStreetMap extract of Taiwan (osmtoday.com's
`asia/taiwan.pbf`, ODbL 1.0) among objects tagged `tourism`, `natural`,
`historic`, `leisure` or `place`, nearest to where the spot is known to be
(`approx`, within `RADIUS_KM`); if nothing matches, `approx` stays and
`source` says so.

Skipped on purpose (a railway cannot get there, or the place is invented):
s03 Penghu Qimei, s05 Matsu coast, s10 Lanyu, s13 Xiaoliuqiu, s14 Green
Island, s19 Kinmen Shuitou; s22 "Danhai light rail, future", s24 "Taipei
landmark 303, an original future landmark".

    pip install osmium
    curl -LO https://osmtoday.com/asia/taiwan.pbf
    python3 -I tools/tourism-spots/build_tourism_spots.py taiwan.pbf \
        tools/tourism-spots/taiwan_attractions.json

Decision 250 adds `MORE_SPOTS`, looked for nearer (see there);
`coverage.py` counts how many a 16 km map gets.

Stars are in hundredths (100 to 500). Kinds: coast, mountain, hotSpring, town.
"""
import json
import math
import sys

import osmium

RADIUS_KM = 12.0
NEAR_KM = 3.0
CLASS_TAGS = ("tourism", "natural", "historic", "leisure", "place")

# id, Chinese name, English name, kind, stars, names to look for, approx (lat, lon)
SPOTS = [
    ("s01", "墾丁・小灣", "Kenting Xiaowan", "coast", 400, ["墾丁", "小灣", "Kenting"], (21.9437, 120.7890)),
    ("s02", "九份", "Jiufen", "town", 400, ["九份", "Jiufen"], (25.1090, 121.8440)),
    ("s04", "清水斷崖", "Qingshui Cliff", "mountain", 400, ["清水斷崖", "Qingshui Cliff"], (24.2200, 121.6720)),
    ("s06", "日月潭", "Sun Moon Lake", "mountain", 450, ["日月潭", "Sun Moon Lake"], (23.8586, 120.9150)),
    ("s07", "阿里山", "Alishan", "mountain", 450, ["阿里山", "Alishan"], (23.5100, 120.8030)),
    ("s08", "太魯閣", "Taroko", "mountain", 450, ["太魯閣", "Taroko"], (24.1590, 121.6215)),
    ("s09", "野柳", "Yehliu", "coast", 350, ["野柳", "Yehliu"], (25.2062, 121.6908)),
    ("s11", "合歡山", "Hehuanshan", "mountain", 350, ["合歡山", "Hehuan"], (24.1430, 121.2720)),
    ("s12", "高美濕地", "Gaomei Wetlands", "coast", 350, ["高美濕地", "Gaomei"], (24.3125, 120.5497)),
    ("s15", "池上伯朗大道", "Chishang Brown Avenue", "mountain", 300, ["伯朗大道", "池上", "Chishang"], (23.1220, 121.2240)),
    ("s16", "七星潭", "Qixingtan", "coast", 300, ["七星潭", "Qixingtan"], (24.0300, 121.6270)),
    ("s17", "陽明山擎天崗", "Qingtiangang", "mountain", 300, ["擎天崗", "Qingtiangang"], (25.1610, 121.5670)),
    ("s18", "清境", "Qingjing", "mountain", 350, ["清境", "Qingjing"], (24.0560, 121.1620)),
    ("s20", "玉山群峰", "Yushan", "mountain", 400, ["玉山", "Yushan", "Jade Mountain"], (23.4700, 120.9570)),
    ("s21", "遠雄海洋公園", "Farglory Ocean Park", "town", 300, ["遠雄海洋公園", "Farglory Ocean Park"], (23.9456, 121.6112)),
    ("s23", "陶朱隱園", "Taozhu Yinyuan", "town", 300, ["陶朱隱園"], (25.0386, 121.5704)),
    ("s25", "淡江大橋", "Danjiang Bridge", "town", 250, [], (25.1753, 121.4178)),
    ("s26", "麗寶賽車場", "Lihpao Racing Park", "town", 250, ["麗寶", "Lihpao"], (24.3300, 120.6980)),
    ("s27", "Xpark・水族探索", "Xpark", "town", 350, ["Xpark", "青埔"], (25.0139, 121.1980)),
    ("h01", "北投溫泉", "Beitou Hot Springs", "hotSpring", 350, ["北投溫泉", "北投", "Beitou"], (25.1370, 121.5086)),
    ("h02", "烏來溫泉", "Wulai Hot Springs", "hotSpring", 350, ["烏來", "Wulai"], (24.8630, 121.5490)),
    ("h03", "礁溪溫泉", "Jiaoxi Hot Springs", "hotSpring", 350, ["礁溪", "Jiaoxi"], (24.8260, 121.7740)),
    ("h04", "關子嶺溫泉", "Guanziling Hot Springs", "hotSpring", 300, ["關子嶺", "Guanziling"], (23.3350, 120.5090)),
    ("h05", "四重溪溫泉", "Sichongxi Hot Springs", "hotSpring", 300, ["四重溪", "Sichongxi"], (22.0668, 120.7977)),
    ("p01", "平溪天燈", "Pingxi Sky Lanterns", "town", 350, ["十分", "平溪", "Shifen", "Pingxi"], (25.0415, 121.7745)),
]

# Decision 250: the famous sights round the island, so that a 16 km map
# where people live usually has two to five. Picked by hand from the
# sights a guide of Taiwan lists (the reference has only OpenWorld's 27 and
# its Taipei landmark names, `taipei-landmark-catalog.js`, some of which are
# here), north to south, each looked for within `NEAR_KM` of where it is
# known to be, so that a common name (a temple, an old street) finds the
# right one. Stars: 350 a sight the whole island knows, 300 a county's best,
# 250 a well-known local one, 200 a small one; none reaches the 400 of the
# map's alert bubbles (`MapAlerts.alertedSightStars`).
MORE_SPOTS = [
    # Taipei
    ("t001", "台北101", "Taipei 101", "town", 350, ["台北101", "臺北101", "Taipei 101"], (25.0340, 121.5645)),
    ("t002", "中正紀念堂", "Chiang Kai-shek Memorial Hall", "town", 350, ["中正紀念堂", "Chiang Kai-shek Memorial Hall"], (25.0346, 121.5217)),
    ("t003", "國立故宮博物院", "National Palace Museum", "town", 350, ["故宮", "Palace Museum"], (25.1024, 121.5485)),
    ("t004", "艋舺龍山寺", "Lungshan Temple", "town", 300, ["龍山寺", "Lungshan Temple"], (25.0372, 121.4999)),
    ("t005", "西門町", "Ximending", "town", 300, ["西門町", "西門紅樓", "Ximending"], (25.0421, 121.5081)),
    ("t006", "士林夜市", "Shilin Night Market", "town", 300, ["士林夜市", "Shilin Night Market"], (25.0880, 121.5241)),
    ("t007", "大稻埕迪化街", "Dadaocheng", "town", 300, ["迪化街", "大稻埕", "Dihua"], (25.0560, 121.5100)),
    ("t008", "象山", "Elephant Mountain", "mountain", 250, ["象山", "Elephant Mountain", "Xiangshan"], (25.0273, 121.5767)),
    ("t009", "貓空", "Maokong", "mountain", 300, ["貓空纜車", "貓空站", "貓空", "Maokong"], (24.9686, 121.5880)),
    ("t010", "臺北市立動物園", "Taipei Zoo", "town", 300, ["動物園", "Taipei Zoo"], (24.9983, 121.5810)),
    ("t011", "國父紀念館", "Sun Yat-sen Memorial Hall", "town", 250, ["國父紀念館", "Sun Yat-sen Memorial Hall"], (25.0400, 121.5603)),
    ("t012", "饒河街夜市", "Raohe Night Market", "town", 250, ["饒河", "Raohe"], (25.0510, 121.5775)),
    ("t013", "華山1914文創園區", "Huashan 1914", "town", 250, ["華山", "Huashan"], (25.0441, 121.5294)),
    ("t014", "竹子湖", "Zhuzihu", "mountain", 250, ["竹子湖", "Zhuzihu"], (25.1650, 121.5380)),
    # New Taipei
    ("t015", "淡水老街", "Tamsui Old Street", "town", 350, ["淡水老街", "淡水", "Tamsui Old Street"], (25.1696, 121.4398)),
    ("t016", "淡水漁人碼頭", "Tamsui Fisherman's Wharf", "coast", 300, ["漁人碼頭", "Fisherman"], (25.1830, 121.4111)),
    ("t017", "紅毛城", "Fort San Domingo", "town", 300, ["紅毛城", "Fort San Domingo"], (25.1754, 121.4329)),
    ("t018", "猴硐貓村", "Houtong Cat Village", "town", 250, ["猴硐", "Houtong"], (25.0868, 121.8273)),
    ("t019", "三峽老街", "Sanxia Old Street", "town", 300, ["三峽老街", "三峽", "Sanxia"], (24.9346, 121.3690)),
    ("t020", "鶯歌老街", "Yingge Old Street", "town", 300, ["鶯歌", "Yingge"], (24.9530, 121.3460)),
    ("t021", "深坑老街", "Shenkeng Old Street", "town", 250, ["深坑", "Shenkeng"], (25.0021, 121.6157)),
    ("t022", "白沙灣", "Baishawan Beach", "coast", 250, ["白沙灣", "Baishawan"], (25.2840, 121.5150)),
    ("t023", "福隆海水浴場", "Fulong Beach", "coast", 300, ["福隆", "Fulong"], (25.0210, 121.9470)),
    ("t024", "鼻頭角", "Bitou Cape", "coast", 250, ["鼻頭角步道", "鼻頭角燈塔", "鼻頭角", "Bitou"], (25.1270, 121.9200)),
    ("t025", "三貂角燈塔", "Sandiao Cape Lighthouse", "coast", 250, ["三貂角", "Sandiao"], (25.0080, 122.0020)),
    ("t026", "碧潭", "Bitan", "town", 250, ["碧潭", "Bitan"], (24.9560, 121.5380)),
    ("t027", "朱銘美術館", "Juming Museum", "town", 250, ["朱銘", "Juming"], (25.2480, 121.6160)),
    ("t028", "富貴角燈塔", "Fuguijiao Lighthouse", "coast", 250, ["富貴角", "Fuguijiao"], (25.2980, 121.5360)),
    ("t029", "坪林茶鄉", "Pinglin Tea Town", "mountain", 250, ["坪林", "Pinglin"], (24.9370, 121.7110)),
    ("t030", "林本源園邸", "Lin Family Garden", "town", 250, ["林本源", "林家花園", "Lin Family"], (25.0110, 121.4550)),
    # Keelung
    ("t031", "基隆廟口夜市", "Keelung Miaokou Night Market", "town", 300, ["廟口", "奠濟宮", "Miaokou"], (25.1283, 121.7434)),
    ("t032", "和平島", "Heping Island", "coast", 300, ["和平島", "Heping Island"], (25.1600, 121.7630)),
    ("t033", "正濱漁港", "Zhengbin Fishing Port", "coast", 250, ["正濱", "Zhengbin"], (25.1510, 121.7730)),
    ("t034", "八斗子潮境", "Badouzi", "coast", 250, ["八斗子", "潮境", "Badouzi"], (25.1440, 121.8020)),
    # Taoyuan
    ("t035", "大溪老街", "Daxi Old Street", "town", 300, ["大溪老街", "和平老街", "大溪", "Daxi"], (24.8830, 121.2870)),
    ("t036", "慈湖", "Cihu", "town", 250, ["慈湖", "Cihu"], (24.8430, 121.2950)),
    ("t037", "石門水庫", "Shimen Reservoir", "mountain", 250, ["石門水庫", "Shimen Reservoir"], (24.8130, 121.2440)),
    ("t038", "小人國", "Window on China", "town", 250, ["小人國", "Window on China"], (24.8460, 121.2120)),
    ("t039", "拉拉山", "Lalashan", "mountain", 300, ["拉拉山", "Lalashan"], (24.7080, 121.4300)),
    ("t040", "角板山", "Jiaobanshan", "mountain", 250, ["角板山", "Jiaobanshan"], (24.8170, 121.3500)),
    ("t041", "永安漁港", "Yong'an Fishing Port", "coast", 200, ["永安漁港", "Yong'an"], (24.9890, 121.0130)),
    ("t042", "桃園忠烈祠", "Taoyuan Martyrs' Shrine", "town", 200, ["忠烈祠", "Martyrs"], (25.0010, 121.3050)),
    # Hsinchu
    ("t043", "六福村", "Leofoo Village", "town", 300, ["六福村", "Leofoo"], (24.8000, 121.1740)),
    ("t044", "新竹城隍廟", "Hsinchu City God Temple", "town", 300, ["城隍廟", "City God"], (24.8040, 120.9655)),
    ("t045", "南寮漁港", "Nanliao Fishing Port", "coast", 250, ["南寮", "Nanliao"], (24.8480, 120.9260)),
    ("t046", "香山濕地", "Xiangshan Wetland", "coast", 250, ["香山濕地", "香山", "Xiangshan"], (24.7800, 120.9100)),
    ("t047", "內灣老街", "Neiwan Old Street", "town", 300, ["內灣", "Neiwan"], (24.7050, 121.1830)),
    ("t048", "北埔老街", "Beipu Old Street", "town", 250, ["北埔", "Beipu"], (24.6990, 121.0570)),
    ("t049", "司馬庫斯", "Smangus", "mountain", 300, ["司馬庫斯", "Smangus"], (24.5780, 121.3360)),
    # Miaoli
    ("t050", "勝興車站", "Shengxing Station", "town", 300, ["勝興車站", "勝興", "Shengxing"], (24.3890, 120.7840)),
    ("t051", "龍騰斷橋", "Longteng Bridge Ruins", "mountain", 300, ["龍騰斷橋", "龍騰", "Longteng"], (24.3670, 120.7740)),
    ("t052", "三義木雕街", "Sanyi Wood Carving Street", "town", 250, ["木雕", "三義", "Sanyi"], (24.4230, 120.7650)),
    ("t053", "南庄老街", "Nanzhuang Old Street", "town", 300, ["南庄", "Nanzhuang"], (24.5960, 121.0000)),
    ("t054", "泰安溫泉", "Tai'an Hot Springs", "hotSpring", 300, ["泰安溫泉", "Tai'an Hot Spring"], (24.4670, 120.9900)),
    ("t055", "通霄海水浴場", "Tongxiao Beach", "coast", 250, ["通霄", "Tongxiao"], (24.4980, 120.6750)),
    ("t056", "好望角", "Haowangjiao", "coast", 200, ["好望角", "Haowangjiao"], (24.6230, 120.7460)),
    # Taichung
    ("t057", "逢甲夜市", "Fengjia Night Market", "town", 350, ["逢甲夜市", "逢甲", "Fengjia", "Feng Chia"], (24.1750, 120.6460)),
    ("t058", "彩虹眷村", "Rainbow Village", "town", 250, ["彩虹", "Rainbow"], (24.1340, 120.6110)),
    ("t059", "臺中國家歌劇院", "National Taichung Theater", "town", 250, ["歌劇院", "Taichung Theater"], (24.1630, 120.6400)),
    ("t060", "宮原眼科", "Miyahara", "town", 250, ["宮原眼科", "Miyahara"], (24.1380, 120.6840)),
    ("t061", "路思義教堂", "Luce Memorial Chapel", "town", 250, ["路思義", "Luce"], (24.1790, 120.6000)),
    ("t062", "大甲鎮瀾宮", "Dajia Jenn Lann Temple", "town", 300, ["鎮瀾宮", "Jenn Lann", "Zhenlan"], (24.3460, 120.6230)),
    ("t063", "梧棲漁港", "Wuqi Fishing Port", "coast", 250, ["梧棲漁港", "梧棲", "Wuqi"], (24.2930, 120.5160)),
    ("t064", "谷關溫泉", "Guguan Hot Springs", "hotSpring", 300, ["谷關", "Guguan"], (24.2040, 121.0080)),
    ("t065", "武陵農場", "Wuling Farm", "mountain", 300, ["武陵", "Wuling"], (24.3540, 121.3110)),
    ("t066", "新社花海", "Xinshe", "mountain", 250, ["新社", "Xinshe"], (24.1640, 120.8110)),
    ("t067", "后豐鐵馬道", "Houfeng Bikeway", "town", 250, ["后豐", "Houfeng"], (24.2830, 120.7230)),
    ("t068", "霧峰林家", "Wufeng Lin Family Mansion", "town", 200, ["霧峰林", "林家宅園", "Wufeng"], (24.0640, 120.7000)),
    # Changhua
    ("t069", "鹿港老街", "Lukang Old Street", "town", 350, ["鹿港", "Lukang"], (24.0540, 120.4320)),
    ("t070", "八卦山大佛", "Baguashan Buddha", "town", 300, ["八卦山", "大佛", "Bagua"], (24.0810, 120.5490)),
    ("t071", "彰化扇形車庫", "Changhua Roundhouse", "town", 300, ["扇形車庫", "Roundhouse"], (24.0850, 120.5370)),
    ("t072", "田尾公路花園", "Tianwei Highway Garden", "town", 250, ["公路花園", "Tianwei Highway Garden"], (23.9050, 120.5310)),
    ("t073", "王功漁港", "Wanggong Fishing Port", "coast", 250, ["王功", "Wanggong"], (23.9660, 120.3240)),
    # Nantou
    ("t074", "集集車站", "Jiji Station", "town", 300, ["集集", "Jiji"], (23.8270, 120.7850)),
    ("t075", "溪頭", "Xitou", "mountain", 300, ["溪頭", "Xitou"], (23.6740, 120.7970)),
    ("t076", "埔里酒廠", "Puli Winery", "town", 250, ["埔里酒廠", "Puli Winery"], (23.9810, 120.9660)),
    ("t077", "九族文化村", "Formosan Aboriginal Culture Village", "town", 300, ["九族", "Formosan Aboriginal"], (23.8710, 120.9420)),
    ("t078", "車埕", "Checheng", "town", 250, ["車埕", "Checheng"], (23.8330, 120.8660)),
    ("t079", "奧萬大", "Aowanda", "mountain", 250, ["奧萬大", "Aowanda"], (23.9510, 121.1760)),
    ("t080", "東埔溫泉", "Dongpu Hot Springs", "hotSpring", 300, ["東埔", "Dongpu"], (23.5660, 120.9300)),
    ("t081", "中台禪寺", "Chung Tai Chan Monastery", "town", 250, ["中台禪寺", "Chung Tai Chan"], (23.9980, 120.9440)),
    # Yunlin
    ("t082", "北港朝天宮", "Beigang Chaotian Temple", "town", 350, ["朝天宮", "Chaotian"], (23.5680, 120.3040)),
    ("t083", "劍湖山世界", "Janfusun Fancyworld", "town", 300, ["劍湖山", "Janfusun"], (23.6230, 120.5800)),
    ("t084", "西螺大橋", "Xiluo Bridge", "town", 250, ["西螺大橋", "Xiluo Bridge"], (23.8090, 120.4660)),
    ("t085", "虎尾糖廠", "Huwei Sugar Factory", "town", 200, ["虎尾糖廠", "Huwei Sugar"], (23.7090, 120.4320)),
    ("t086", "斗六太平老街", "Douliu Taiping Old Street", "town", 200, ["太平老街", "太平路", "Taiping"], (23.7100, 120.5420)),
    # Chiayi
    ("t087", "檜意森活村", "Hinoki Village", "town", 250, ["檜意", "Hinoki"], (23.4860, 120.4530)),
    ("t088", "奮起湖", "Fenqihu", "mountain", 300, ["奮起湖", "Fenqihu"], (23.5050, 120.6950)),
    ("t089", "故宮南院", "Southern Branch of the Palace Museum", "town", 300, ["故宮南院", "南部院區", "Southern Branch"], (23.4720, 120.2870)),
    ("t090", "東石漁人碼頭", "Dongshi Fisherman's Wharf", "coast", 250, ["東石", "Dongshi"], (23.4580, 120.1450)),
    ("t091", "新港奉天宮", "Xingang Fengtian Temple", "town", 250, ["奉天宮", "Fengtian"], (23.5560, 120.3470)),
    # Tainan
    ("t092", "赤崁樓", "Chihkan Tower", "town", 350, ["赤崁樓", "Chihkan"], (22.9975, 120.2025)),
    ("t093", "安平古堡", "Anping Old Fort", "town", 350, ["安平古堡", "Fort Zeelandia", "Anping"], (23.0015, 120.1605)),
    ("t094", "神農街", "Shennong Street", "town", 250, ["神農街", "Shennong"], (22.9970, 120.1970)),
    ("t095", "臺南孔廟", "Tainan Confucius Temple", "town", 250, ["孔廟", "Confucius"], (22.9905, 120.2040)),
    ("t096", "奇美博物館", "Chimei Museum", "town", 350, ["奇美博物館", "Chimei"], (22.9350, 120.2260)),
    ("t097", "四草綠色隧道", "Sicao Green Tunnel", "coast", 250, ["綠色隧道", "Green Tunnel"], (23.0230, 120.1370)),
    ("t098", "七股鹽山", "Qigu Salt Mountain", "coast", 300, ["七股鹽山", "鹽山", "Qigu"], (23.1540, 120.1000)),
    ("t099", "井仔腳瓦盤鹽田", "Jingzaijiao Salt Field", "coast", 200, ["井仔腳", "Jingzaijiao"], (23.1870, 120.0790)),
    ("t100", "烏山頭水庫", "Wushantou Reservoir", "mountain", 250, ["烏山頭", "Wushantou"], (23.2050, 120.3890)),
    ("t101", "新化老街", "Xinhua Old Street", "town", 200, ["新化老街", "Xinhua Old Street"], (23.0380, 120.3100)),
    ("t102", "十鼓文創園區", "Ten Drum Culture Village", "town", 200, ["十鼓", "Ten Drum"], (22.9550, 120.2370)),
    ("t103", "麻豆代天府", "Madou Daitian Temple", "town", 200, ["代天府", "Daitian"], (23.1810, 120.2420)),
    # Kaohsiung
    ("t104", "駁二藝術特區", "The Pier-2 Art Center", "town", 300, ["駁二", "Pier-2", "Pier 2"], (22.6200, 120.2820)),
    ("t105", "旗津", "Cijin", "coast", 300, ["旗津", "Cijin"], (22.6130, 120.2670)),
    ("t106", "西子灣", "Sizihwan", "coast", 300, ["西子灣", "Sizihwan"], (22.6240, 120.2650)),
    ("t107", "蓮池潭", "Lotus Pond", "town", 300, ["蓮池潭", "Lotus Pond"], (22.6810, 120.2940)),
    ("t108", "六合夜市", "Liuhe Night Market", "town", 250, ["六合", "Liuhe"], (22.6320, 120.2990)),
    ("t109", "佛光山", "Fo Guang Shan", "town", 350, ["佛光山", "佛陀紀念館", "Fo Guang"], (22.7550, 120.4430)),
    ("t110", "義大世界", "E-DA World", "town", 300, ["義大", "E-DA", "E-Da"], (22.7290, 120.4040)),
    ("t111", "高雄85大樓", "85 Sky Tower", "town", 250, ["85大樓", "Sky Tower", "東帝士"], (22.6116, 120.3002)),
    ("t112", "衛武營", "Weiwuying", "town", 250, ["衛武營", "Weiwuying"], (22.6230, 120.3410)),
    ("t113", "美濃", "Meinong", "town", 250, ["美濃客家文物館", "Meinong Hakka"], (22.8960, 120.5420)),
    ("t114", "旗山老街", "Qishan Old Street", "town", 250, ["旗山", "Qishan"], (22.8880, 120.4830)),
    ("t115", "寶來溫泉", "Baolai Hot Springs", "hotSpring", 250, ["寶來溫泉", "Baolai Hot Spring"], (23.1080, 120.7020)),
    ("t116", "茂林", "Maolin", "mountain", 250, ["茂林", "Maolin"], (22.8870, 120.6640)),
    ("t117", "田寮月世界", "Tianliao Moon World", "mountain", 250, ["月世界", "Moon World"], (22.8870, 120.3750)),
    ("t118", "澄清湖", "Chengcing Lake", "town", 250, ["澄清湖", "Chengcing"], (22.6560, 120.3550)),
    # Pingtung
    ("t119", "鵝鑾鼻燈塔", "Eluanbi Lighthouse", "coast", 350, ["鵝鑾鼻", "Eluanbi"], (21.9020, 120.8530)),
    ("t120", "國立海洋生物博物館", "National Museum of Marine Biology and Aquarium", "coast", 350, ["海洋生物博物館", "海生館", "Marine Biology"], (22.0460, 120.6980)),
    ("t121", "大鵬灣", "Dapeng Bay", "coast", 250, ["大鵬灣", "Dapeng"], (22.4440, 120.4750)),
    ("t122", "台灣原住民族文化園區", "Indigenous Peoples Cultural Park", "town", 250, ["原住民族文化園區", "Indigenous Peoples Cultural"], (22.7020, 120.6410)),
    ("t123", "勝利星村", "Victory Village", "town", 200, ["勝利星村", "Victory"], (22.6720, 120.4920)),
    ("t124", "恆春古城", "Hengchun Old Town", "town", 250, ["恆春古城", "恆春南門", "Hengchun Old"], (22.0010, 120.7460)),
    ("t125", "佳樂水", "Jialeshui", "coast", 250, ["佳樂水", "Jialeshui"], (21.9900, 120.8620)),
    # Yilan
    ("t126", "國立傳統藝術中心", "National Center for Traditional Arts", "town", 300, ["傳統藝術", "傳藝", "Traditional Arts"], (24.6850, 121.8240)),
    ("t127", "羅東夜市", "Luodong Night Market", "town", 300, ["羅東夜市", "羅東", "Luodong"], (24.6780, 121.7700)),
    ("t128", "蘇澳冷泉", "Su'ao Cold Spring", "hotSpring", 300, ["冷泉", "Cold Spring"], (24.5960, 121.8520)),
    ("t129", "南方澳", "Nanfang'ao", "coast", 250, ["南方澳", "Nanfang"], (24.5850, 121.8670)),
    ("t130", "太平山", "Taipingshan", "mountain", 350, ["太平山", "Taipingshan"], (24.5000, 121.5330)),
    ("t131", "外澳海灘", "Waiao Beach", "coast", 250, ["外澳沙灘", "外澳海", "Waiao Beach"], (24.8720, 121.8410)),
    ("t132", "蘭陽博物館", "Lanyang Museum", "town", 250, ["蘭陽博物館", "Lanyang Museum"], (24.8680, 121.8320)),
    ("t133", "梅花湖", "Meihua Lake", "mountain", 200, ["梅花湖", "Meihua"], (24.6490, 121.7330)),
    ("t134", "鳩之澤溫泉", "Jiuzhize Hot Springs", "hotSpring", 250, ["鳩之澤", "仁澤", "Jiuzhize"], (24.5870, 121.5150)),
    # Hualien
    ("t135", "東大門夜市", "Dongdamen Night Market", "town", 300, ["東大門夜市", "東大門國際", "Dongdamen Night"], (23.9750, 121.6100)),
    ("t136", "鯉魚潭", "Liyu Lake", "mountain", 250, ["鯉魚潭", "Liyu"], (23.9310, 121.5050)),
    ("t137", "瑞穗溫泉", "Ruisui Hot Springs", "hotSpring", 250, ["瑞穗溫泉", "瑞穗", "Ruisui"], (23.4930, 121.3600)),
    ("t138", "六十石山", "Liushidan Mountain", "mountain", 300, ["六十石山", "Liushidan"], (23.1240, 121.2780)),
    ("t139", "石梯坪", "Shitiping", "coast", 250, ["石梯坪", "Shitiping"], (23.4890, 121.5110)),
    ("t140", "林田山", "Lintianshan", "town", 200, ["林田山", "Lintian"], (23.7340, 121.4040)),
    # Taitung
    ("t141", "三仙台", "Sanxiantai", "coast", 300, ["三仙台", "Sanxiantai"], (23.1240, 121.4140)),
    ("t142", "多良車站", "Duoliang Station", "coast", 300, ["多良", "Duoliang"], (22.5130, 120.9600)),
    ("t143", "知本溫泉", "Zhiben Hot Springs", "hotSpring", 300, ["知本溫泉", "Zhiben Hot Spring"], (22.6900, 121.0030)),
    ("t144", "鹿野高台", "Luye Highland", "mountain", 300, ["鹿野高台", "高台", "Luye"], (22.9150, 121.1260)),
    ("t145", "鐵花村", "Tiehua Village", "town", 250, ["鐵花", "Tiehua"], (22.7560, 121.1490)),
    ("t146", "小野柳", "Xiaoyeliu", "coast", 250, ["小野柳", "Xiaoyeliu"], (22.7930, 121.1950)),
    # More round the towns the first pass left with one or none (coverage.py)
    ("t147", "新莊廟街", "Xinzhuang Temple Street", "town", 200, ["新莊廟街", "新莊老街", "Xinzhuang"], (25.0368, 121.4497)),
    ("t148", "林口竹林山觀音寺", "Zhulinshan Guanyin Temple", "town", 200, ["竹林山", "Zhulinshan"], (25.0645, 121.3780)),
    ("t149", "埔心牧場", "Puxin Ranch", "town", 250, ["埔心牧場", "Puxin Ranch"], (24.9200, 121.1810)),
    ("t150", "竹圍漁港", "Zhuwei Fishing Port", "coast", 250, ["竹圍漁港", "Zhuwei"], (25.1170, 121.2420)),
    ("t151", "承天禪寺", "Chengtian Temple", "mountain", 200, ["承天禪寺", "Chengtian Temple"], (24.9750, 121.4290)),
    ("t152", "新瓦屋客家文化保存區", "Xinwawu Hakka Village", "town", 200, ["新瓦屋", "Xinwawu"], (24.8180, 121.0250)),
    ("t153", "東港東隆宮", "Donglong Temple", "town", 300, ["東隆宮", "Donglong"], (22.4659, 120.4510)),
    ("t154", "九二一地震教育園區", "921 Earthquake Museum", "town", 250, ["921地震", "九二一", "921 Earthquake"], (24.0430, 120.6900)),
    ("t155", "汐止拱北殿", "Gongbei Temple", "mountain", 200, ["拱北殿", "Gongbei"], (25.0920, 121.6550)),
    ("t156", "大樹舊鐵橋", "Old Iron Bridge of Dashu", "town", 250, ["舊鐵橋", "Old Iron Bridge"], (22.6480, 120.4270)),
    ("t157", "橋頭糖廠", "Qiaotou Sugar Factory", "town", 250, ["橋頭糖廠", "Qiaotou Sugar", "糖業博物館"], (22.7570, 120.3070)),
    ("t158", "國立臺灣歷史博物館", "National Museum of Taiwan History", "town", 250, ["臺灣歷史博物館", "台灣歷史博物館", "Taiwan History"], (23.0590, 120.2050)),
    ("t159", "望高寮", "Wanggaoliao", "mountain", 200, ["望高寮", "Wanggaoliao"], (24.1450, 120.5770)),
    ("t160", "嘉義文化路夜市", "Chiayi Wenhua Road Night Market", "town", 250, ["文化路夜市", "Wenhua Road"], (23.4795, 120.4490)),
    ("t161", "蘭潭", "Lantan Lake", "mountain", 200, ["蘭潭", "Lantan"], (23.4720, 120.4880)),
    ("t162", "百果山", "Baiguoshan", "mountain", 200, ["百果山", "Baiguo"], (23.9580, 120.6080)),
    ("t163", "富岡老街", "Fugang Old Street", "town", 200, ["富岡老街", "富岡", "Fugang"], (24.9350, 121.0820)),
    ("t164", "虎頭埤", "Hutoupi", "mountain", 250, ["虎頭埤", "Hutoupi"], (23.0300, 120.3290)),
    ("t165", "豐原廟東夜市", "Fengyuan Miaodong Night Market", "town", 200, ["廟東", "Miaodong"], (24.2520, 120.7200)),
    ("t166", "石岡水壩", "Shigang Dam", "mountain", 200, ["石岡水壩", "Shigang Dam"], (24.2770, 120.7810)),
    ("t167", "崎頂海水浴場", "Qiding Beach", "coast", 200, ["崎頂", "Qiding"], (24.7190, 120.8710)),
    ("t168", "苗栗鐵道文物展示館", "Miaoli Railway Museum", "town", 200, ["鐵道文物", "Railway Museum"], (24.5700, 120.8220)),
    ("t169", "萬金聖母聖殿", "Wanjin Basilica", "town", 200, ["萬金", "Wanjin"], (22.6180, 120.5960)),
    ("t170", "幾米廣場", "Jimmy Square", "town", 200, ["幾米", "Jimmy"], (24.7550, 121.7580)),
    ("t171", "冬山河親水公園", "Dongshan River Water Park", "town", 250, ["冬山河", "Dongshan River"], (24.6620, 121.7930)),
    ("t172", "古坑華山", "Gukeng Huashan", "mountain", 200, ["華山", "Huashan"], (23.6370, 120.6060)),
    ("t173", "中興新村", "Zhongxing New Village", "town", 200, ["中興新村", "Zhongxing"], (23.9580, 120.6860)),
    ("t174", "湖口老街", "Hukou Old Street", "town", 250, ["湖口老街", "Hukou Old Street"], (24.8860, 121.0420)),
    ("t175", "南鯤鯓代天府", "Nankunshen Daitian Temple", "town", 300, ["南鯤鯓", "Nankunshen"], (23.2830, 120.1440)),
    ("t176", "阿公店水庫", "Agongdian Reservoir", "mountain", 200, ["阿公店", "Agongdian"], (22.8040, 120.3550)),
    ("t177", "蚵仔寮漁港", "Keziliao Fishing Port", "coast", 200, ["蚵仔寮", "Keziliao"], (22.7270, 120.2480)),
    ("t178", "菁寮老街", "Jingliao Old Street", "town", 200, ["菁寮老街", "Jingliao Old Street"], (23.3550, 120.3570)),
    ("t179", "山上花園水道博物館", "Shanshang Water Museum", "town", 200, ["水道博物館", "Water Museum"], (23.0960, 120.3540)),
    ("t180", "尖山埤", "Jianshanpi", "mountain", 200, ["尖山埤", "Jianshanpi"], (23.2880, 120.3920)),
    ("t181", "明德水庫", "Mingde Reservoir", "mountain", 200, ["明德水庫", "Mingde"], (24.5800, 120.9100)),
    ("t182", "草漯沙丘", "Caota Sand Dunes", "coast", 250, ["草漯沙丘", "沙丘", "Caota"], (25.0740, 121.1050)),
    ("t183", "鹽水月津港", "Yueijin Harbor", "town", 250, ["月津港", "Yuejin", "Yueijin"], (23.3190, 120.2670)),
    ("t184", "吉安慶修院", "Qingxiu Temple", "town", 200, ["慶修院", "Qingxiu"], (23.9590, 121.5640)),
    ("t185", "紅毛港文化園區", "Hongmaogang Cultural Park", "coast", 200, ["紅毛港", "Hongmaogang"], (22.5560, 120.3060)),
    ("t186", "松柏嶺受天宮", "Songbailing Shoutian Temple", "mountain", 250, ["受天宮", "Shoutian"], (23.8890, 120.6560)),
    ("t187", "苑裡藺草文化館", "Yuanli Rush Weaving Museum", "town", 200, ["藺草", "Rush"], (24.4140, 120.6510)),
    ("t188", "初鹿牧場", "Chulu Ranch", "mountain", 250, ["初鹿牧場", "Chulu"], (22.8020, 121.0740)),
    ("t189", "雲中街生活聚落", "Yunzhong Street Settlement", "town", 200, ["雲中街", "Yunzhong"], (23.7050, 120.5450)),
]


RADII = [(spot, RADIUS_KM) for spot in SPOTS] + [(spot, NEAR_KM) for spot in MORE_SPOTS]


def km(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    return math.hypot((a[0] - b[0]) * 110.574, (a[1] - b[1]) * 111.320 * math.cos(lat))


def score(tags):
    """Higher is a better kind of object to put a spot on."""
    if tags.get("tourism") in ("attraction", "viewpoint", "theme_park", "zoo", "aquarium", "museum"):
        return 4
    if tags.get("natural") in ("peak", "water", "bay", "beach", "cliff", "hot_spring", "wetland"):
        return 3
    if any(k in tags for k in ("historic", "leisure")):
        return 2
    if tags.get("place") in ("village", "town", "suburb", "neighbourhood", "hamlet", "locality"):
        return 1
    return 0


def more_score(tags):
    """The class of an object to put one of `MORE_SPOTS` on (decision 250):
    as `score`, with temples, markets, stations and streets, but not a
    township's or a village's node, whose name a sight often shares."""
    quality = score(tags)
    if quality > 1:
        return quality
    if tags.get("amenity") in ("place_of_worship", "marketplace") or tags.get("railway") in ("station", "halt"):
        return 2
    if tags.get("highway") in ("pedestrian", "residential", "tertiary", "secondary", "unclassified", "living_street") or "building" in tags:
        return 1
    return 0


class Finder(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.best = {}

    def consider(self, kind, oid, tags, lat, lon, more_only=False):
        names = " ".join(tags.get(k, "") for k in ("name", "name:zh", "name:en", "name:zh-Hant", "alt_name"))
        if not names:
            return
        quality = score(tags) if any(k in tags for k in CLASS_TAGS) else 0
        more = more_score(tags)
        if quality == 0 and more == 0:
            return
        for spot, radius in RADII:
            if not any(word in names for word in spot[5]):
                continue
            distance = km((lat, lon), spot[6])
            if distance > radius:
                continue
            if radius == RADIUS_KM:
                if more_only:
                    continue
                # A better class wins; within a class the nearer to where it is known to be.
                if quality == 0:
                    continue
                key = (-quality, distance)
            else:
                # Decision 250: the sight's own name first, then the class.
                if more == 0:
                    continue
                key = (0 if spot[5][0] in names else 1, -more, distance)
            if spot[0] not in self.best or key < self.best[spot[0]][0]:
                self.best[spot[0]] = (key, lat, lon, f"{kind}/{oid}", names.strip()[:60])

    def node(self, n):
        if n.location.valid():
            self.consider("node", n.id, n.tags, n.location.lat, n.location.lon)

    def way(self, w):
        # A street, for `MORE_SPOTS` only (decision 250): an old street or a
        # night market is often only that. Its middle node.
        if w.is_closed() or "name" not in w.tags:
            return
        points = [node.location for node in w.nodes if node.location.valid()]
        if points:
            middle = points[len(points) // 2]
            self.consider("way", w.id, w.tags, middle.lat, middle.lon, more_only=True)

    def area(self, a):
        try:
            outer = next(iter(a.outer_rings()))
        except StopIteration:
            return
        lats = [p.lat for p in outer]
        lons = [p.lon for p in outer]
        self.consider("area", a.orig_id(), a.tags, sum(lats) / len(lats), sum(lons) / len(lons))


def main():
    source, target = sys.argv[1], sys.argv[2]
    finder = Finder()
    finder.apply_file(source, locations=True)
    spots = []
    for sid, name, english, kind, stars, _, approx in SPOTS + MORE_SPOTS:
        found = finder.best.get(sid)
        lat, lon, origin, matched = (found[1], found[2], found[3], found[4]) if found else (approx[0], approx[1], "approx", "")
        spots.append({
            "id": sid, "name": name, "englishName": english, "kind": kind, "stars": stars,
            "lat": round(lat, 5), "lon": round(lon, 5), "source": origin, "matched": matched,
        })
        print(f"{sid} {name:12} {origin:16} {lat:.5f} {lon:.5f} {km((lat, lon), approx):5.2f} km  {matched}")
    with open(target, "w", encoding="utf-8") as handle:
        json.dump({"license": "OpenStreetMap contributors, ODbL 1.0", "attractions": spots}, handle, ensure_ascii=False, indent=1)
        handle.write("\n")


if __name__ == "__main__":
    main()
