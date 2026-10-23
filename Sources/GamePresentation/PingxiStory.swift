import GameCore

// The Pingxi challenge's story (decision 387), written for the game and
// passed on by the owner. Uncle Song, Xiaowei and Mia are made up; the
// station master is the game's (decision 122).
//
// The history in it is from public sources, checked on 2026-10-23:
// - the line was built for the Tai-Yang mining company (臺陽礦業) to carry
//   Shidi's coal, Jingtong its end, and when the mines closed in the 1980s
//   the railway administration meant to stop it and local people kept it
//   (Chinese Wikipedia, "平溪線"; Mirror Media, 2023-05-17, "一見菁桐遊記
//   （上）");
// - the lanterns' legend: villagers fled bandits into the hills and those
//   who went back sent up a lantern to say it was safe (Chinese Wikipedia,
//   "平溪天燈節");
// - for the 2026 festival (27 February at Pingxi, 3 March at Shifen) TRA
//   added cars and trains, and on 3 March ran some trains Ruifang–Shifen
//   and Shifen–Jingtong (United Daily News, 2026-02-24 and 2026-02-27;
//   Chinese Wikipedia, "十分車站");
// - the New Pingxi Coal Mine near Shifen stopped mining in 1997 and opened
//   as the Taiwan Coal Mine Museum in 2002 (Chinese Wikipedia,
//   "新平溪煤礦博物園區").

extension PingxiChallenge {
    static let story = ChallengeStory(challengeID: Challenge.pingxi.id, beats: [
        StoryBeat(
            "pingxi.1", .day(3), .ahSong,
            "My father spent his whole life digging coal at Shidi, and the coal trains left Jingtong every day. Now the cargo is people, so give them a reason to come back.",
            "我阿爸在石底坑挖了一輩子的煤，那時候煤車天天從菁桐開出去。現在車上載的是人，你得讓他們願意再來。"
        ),
        StoryBeat(
            "pingxi.2", .day(15), .stationMaster,
            "When the mines shut one by one in the 1980s, the railway considered closing this line, and it was the locals who kept it alive. Start by finding the trains that run empty and the stations where people get left on the platform.",
            "1980 年代礦坑一個個關門，鐵路局曾經考慮停掉這條線，是地方的人把它留了下來。先看看哪些班次空著、哪些站的人擠不上車吧。"
        ),
        StoryBeat(
            "pingxi.3", .day(40), .xiaoWei,
            "Legend says villagers once hid in the hills from bandits, and whoever went back first sent up a lantern to say all was safe. Lantern season's nearly here, and more people come in to write their wishes every day.",
            "傳說清朝時村民躲進山裡避山賊，回村察看的人放天燈報平安，天燈就是這樣來的。元宵快到了，來店裡寫願望的人一天比一天多。"
        ),
        StoryBeat(
            "pingxi.4", .festivalAnnounced, .stationMaster,
            "The Sky Lantern Festival is next week, and Shifen and Pingxi will be packed. The railway always added trains for it and turned some back at Shifen, so let's get extra trains ready while there's still time.",
            "下週就是天燈節，十分和平溪會擠滿人。以前每到這時候，鐵路局都會加開班次，還讓一部分列車只開到十分就折返，我們也趁現在多準備幾班車吧。",
            carries: .festival
        ),
        StoryBeat(
            "pingxi.5", .festivalBegins, .mia,
            "I saw photos of this back in Melbourne, and the train really does roll right down the middle of the street! Everyone writes a wish on their lantern. Mine says 'Come back next year.'",
            "我在墨爾本就看過照片，火車真的從老街正中間開過去！大家都在天燈上寫願望，我寫的是『明年還要再來』。"
        ),
        StoryBeat(
            "pingxi.6", .festivalOver, .xiaoWei,
            "The lanterns are gone and the tracks are quiet again. People still come for the falls and Jingtong's old street on ordinary days, so don't plan for the festival alone.",
            "天燈都飛走了，鐵道邊又安靜下來。平常日子也有人來看十分瀑布、逛菁桐老街，別只顧著節日。"
        ),
        StoryBeat(
            "pingxi.7", .firstProfitableDay, .ahSong,
            "Word is the line finally made money today! My father's generation used to say a railway only lives as long as people ride it.",
            "聽說這條線今天終於沒在賠錢了！我阿爸那代人常說：火車要有人坐，才活得下去。"
        ),
        StoryBeat(
            "pingxi.8", .ridersGoalMet, .stationMaster,
            "The platforms overflowed today, and the trains were as full as the old coal wagons. We've got the crowds; now the books need to catch up.",
            "今天月台上的人多到站不下，車廂擠得跟當年的煤車一樣滿。人潮有了，接下來要讓帳本也跟上。"
        ),
        StoryBeat(
            "pingxi.9", .cashBelowZero, .stationMaster,
            "We're out of money, and if this goes on the company will go bankrupt. Cut the trains that run empty, then take a hard look at fares and costs.",
            "帳上已經沒錢了，再這樣下去公司會破產。先把空車的班次減掉，再把票價和開支重新看一遍。",
            carries: .debt
        ),
        StoryBeat(
            "pingxi.10", .yearClosed, .ahSong,
            "The New Pingxi Coal Mine near Shifen stopped digging in 1997 and became a museum, but the line kept running. See where this year made and lost money, and start next year from there.",
            "十分附近的新平溪煤礦在 1997 年停採，後來改成煤礦博物館；礦坑關了，路線卻還在跑。看看今年哪裡賺、哪裡賠，明年就從那裡改起。"
        ),
        StoryBeat(
            "pingxi.gold", .completed(.gold), .ahSong,
            "One year, and Jingtong's platform is as lively as when I was a boy. My father would say the line struck a new seam, and this one's made of passengers.",
            "才一年，菁桐的月台就跟我小時候一樣熱鬧。我阿爸要是看到，一定會說這條線挖到新的煤了，就是這些乘客。"
        ),
        StoryBeat(
            "pingxi.silver", .completed(.silver), .xiaoWei,
            "Two years on, every shop on the old street says business is steady. Next Lantern Festival, I'll write 'Safe travels, Pingxi Line' on a lantern for you.",
            "兩年下來，老街的店家都說生意穩了。明年元宵，我幫你在天燈上寫『平溪線一路平安』。"
        ),
        StoryBeat(
            "pingxi.bronze", .completed(.bronze), .stationMaster,
            "It took three years, but the Pingxi Line is finally on its feet. The locals never gave up on it back then, and neither did we.",
            "花了三年，平溪線總算站穩了。當年地方的人沒有放棄它，我們也沒有。"
        ),
        StoryBeat(
            "pingxi.failed", .failed, .stationMaster,
            "This time the Pingxi Line didn't make it. It nearly closed in the 1980s too and survived because someone refused to give up, so take it on again.",
            "這一次，平溪線沒能撐下去。但它在 1980 年代也差點停駛，是有人不肯放棄才留下來的，再接手一次吧。"
        ),
    ])
}
