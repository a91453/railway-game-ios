import GameCore

// The Neiwan challenge's story (decision 671), after the opening history of
// decision 668. Granny Peng, Uncle Luo and Xiaoyu are made up; the station
// master is the game's (decision 122). Uncle Luo's second memory waits for
// the first.
//
// The station master's advice follows what decision 668 measured (review
// L16-2): this line's difficulty is capacity, not the first months. One
// two-car train stays near 33,000 riders a day for three years and fails
// at the deadline; four cars, or two trains, win gold. So he says to
// lengthen or add early, never to run short or sparingly, and the
// crowding beat comes at 60% of the riders' goal (30,000), which a short
// train reaches, not at 75% (37,500), which it never does.
//
// The history in it is from public sources, checked on 2026-11-09 (decision
// 668 read them; the owner's `tra_special_trains.json` `branchLines`
// `neiwan`; Chinese Wikipedia, 「內灣線」「合興車站」「竹東車站」; English
// Wikipedia, "Neiwan line"):
// - work began in 1944 and stopped in the war; Hsinchu to Zhudong opened in
//   1947, the first branch line built after the war, to carry timber,
//   cement, lime and coal; it reached Neiwan on 1951-09-11 and was named the
//   Neiwan Line;
// - the towns on it are Hakka, and Neiwan's old street grew round the
//   station after the timber and coal trade faded;
// - Hexing's wooden station is still served by trains; what closed in
//   October 2025, when the railway ended the lease, is the "Love Station"
//   park beside it (Chinese Wikipedia, 「合興車站」, its references; the
//   owner's correction, 2026-11-09).
// What the three say of their own lives (the cement works and the forest
// yard where Uncle Luo worked, the noodle shop, the fireflies in spring) is
// colour, not a record, which is why they say "they say" where it is not
// from a source.

extension BranchLineChallenge {
    static let neiwanStory = ChallengeStory(challengeID: neiwan.challengeID, beats: [
        StoryBeat(
            "neiwan.1", .day(3), .stationMaster,
            "Hsinchu is a big city, and plenty of people ride from the first day; only past Zhuzhong does the line climb into the hills. A short train fills up fast here, so lengthen it or add another early, and keep fares kind enough that people along the line will ride.",
            "新竹是大城市，第一天就有很多人要搭車；過了竹中，鐵路才慢慢爬進山裡。短車很快就會坐滿，記得早點把車加長或再加一列；票價也別訂太高，讓沿線的人坐得起。",
            carries: .welcome
        ),
        StoryBeat(
            "neiwan.2", .day(10), .luo,
            "Back in the fifties I rode this line to work every morning, and the freight cars behind us were stacked with timber and cement. The train was never on time, but it never left us behind.",
            "民國四十幾年，我天天坐這條線去上工，後頭的貨車裝的都是木頭和水泥。火車從來不準時，可是也從來沒有丟下我們。"
        ),
        StoryBeat(
            "neiwan.3", .milestone(0), .xiaoYu,
            "I'm back from Taipei for the weekend to help at home, and the little train out of Hsinchu is already passing Zhuzhong. The houses thin out and the hills come up, and I always feel I'm nearly home.",
            "我從台北回來幫家裡的忙，從新竹開出來的小火車已經過了竹中。房子漸漸變少，山一座座冒出來，每次都覺得快到家了。"
        ),
        StoryBeat(
            "neiwan.4", .milestone(1), .luo,
            "Zhudong! They say the cement works and the forest yards were what kept this town busy in my day. We got off here by the hundred, lunch boxes in hand, and the platform was all noise.",
            "到竹東了！聽說我們那時候，鎮上的水泥廠和林場養活了不少人。我們一大群人提著便當在這裡下車，月台上吵得很。",
            after: .beat("neiwan.2")
        ),
        StoryBeat(
            "neiwan.5", .riders(percent: 25), .xiaoYu,
            "Past Zhudong is Hexing, a little wooden station where the trains still stop. People used to come from all over to take photos at the Love Station park beside it. The park closed in October 2025, but I still tell my friends to ride out and see it.",
            "過了竹東就是合興，一座木頭小站，火車到現在還會停。以前很多人專程來旁邊的「愛情車站」園區拍照；園區 2025 年 10 月關了，我還是會叫朋友坐車來看看。"
        ),
        StoryBeat(
            "neiwan.6", .cashBelowZero, .stationMaster,
            "We're out of money, and if this goes on we'll go bankrupt. See that fares aren't so high they keep people away, and that the trains are long enough for everyone waiting: on this line it is full trains that pay.",
            "錢用完了，再這樣下去會破產。看看票價是不是訂得太高、把人擋在車外，車夠不夠長、載不載得完等車的人；這條線要靠坐滿的車賺錢。",
            carries: .debt
        ),
        StoryBeat(
            "neiwan.7", .riders(percent: 50), .luo,
            "Timber and coal came down this same track once. Now the cars are full of people with cameras. I never thought I'd see the day, but a train that carries someone is a good train.",
            "從前木頭和煤都從這條軌道運下山，現在車廂裡坐的是帶著相機的人。我沒想過會有這一天，不過能載人的車就是好車。",
            after: .beat("neiwan.4")
        ),
        StoryBeat(
            "neiwan.8", .milestone(2), .pengPo,
            "Neiwan! Have you eaten yet? Come in, I'll make you a bowl of rice noodles. This was a town for timber and coal once, then it went quiet. Now the old street fills up every weekend, and all of it arrives by train.",
            "內灣到了！食飽未？進來，阿婆煮碗粄條給你吃。這裡以前是運木頭、運煤的小鎮，後來冷清了；現在老街假日又擠滿人，大家都是坐火車來的。"
        ),
        StoryBeat(
            "neiwan.9", .riders(percent: 60), .stationMaster,
            "The line is filling up, and people are waiting on platforms. Lengthen the train or add another: a short train alone cannot carry everyone who wants to ride.",
            "這條線越來越擠，月台上開始有人在等車了。把車加長，或再加一列；只靠短車，載不完想搭車的人。",
            carries: .crowding
        ),
        StoryBeat(
            "neiwan.10", .ridersGoalMet, .pengPo,
            "The street is packed and I've run out of noodles by two o'clock! My mother used to say the railway reached Neiwan in 1951 and the town came alive. I think she'd say it has come alive again.",
            "老街擠得水泄不通，我的粄條下午兩點就賣完了！我阿姆常說，鐵路 1951 年通到內灣，鎮上才活起來；我看這下又活過來了。"
        ),
        StoryBeat(
            "neiwan.11", .firstProfitableDay, .luo,
            "Word is the line made money today. In my day nobody asked if it paid, only whether it came. Both matter, I suppose.",
            "聽說這條線今天賺錢了。我們那時候沒人問划不划算，只問車來了沒。我想兩樣都要緊吧。"
        ),
        StoryBeat(
            "neiwan.12", .yearClosed, .stationMaster,
            "The year's books are closed. See what earned and what lost, and add trains where the platforms are full rather than everywhere.",
            "一年結算了。看看哪裡賺、哪裡賠，月台擠的地方才加車，不要每個地方都加。"
        ),
        StoryBeat(
            "neiwan.gold", .completed(.gold), .pengPo,
            "One year, and the trains to Neiwan run full all week. The old people will tell you the line came for timber and stayed for the people. I'll put an extra egg in your noodles.",
            "才一年，開往內灣的車整個禮拜都坐滿。老人家會說，這條線為了運木頭來，為了人留下。今天你的粄條，阿婆多加顆蛋。"
        ),
        StoryBeat(
            "neiwan.silver", .completed(.silver), .xiaoYu,
            "Two years on, and when the fireflies come out in spring the trains are full of people who came for them. Next time you're up, I'll take you to see Hexing after dark.",
            "兩年下來，春天螢火蟲出來的時候，車上坐滿了專程來看牠們的人。下次你來，我帶你天黑以後去看合興。"
        ),
        StoryBeat(
            "neiwan.bronze", .completed(.bronze), .stationMaster,
            "It took three years, but the Neiwan Line is on its feet. It stopped once for the war, and it was laid again after. This time it was us.",
            "花了三年，內灣線總算站穩了。它因為戰爭停過工，戰後又鋪了起來；這次換我們。"
        ),
        StoryBeat(
            "neiwan.failed", .failed, .stationMaster,
            "This time the Neiwan Line didn't make it. Work stopped on it in the war and began again after, so try again, and this time lengthen the trains or add one early: more people want to ride here than a short train can carry.",
            "這一次，內灣線沒能撐下去。它在戰時停過工，戰後又重新開始；再試一次，這次早點把車加長或加一列：這裡想搭車的人，短車載不完。"
        ),
    ])
}
