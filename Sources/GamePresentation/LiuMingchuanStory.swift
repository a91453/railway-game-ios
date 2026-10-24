import GameCore

// The Liu Mingchuan challenge's story (decision 387), written for the game
// and passed on by the owner. Ah-Shui, Mr Walsh and Manager Ye are made up
// (the railway's drivers were mostly British, as Walsh is); the station
// master is the game's (decision 122).
//
// The history in it is from public sources, checked on 2026-10-23
// (decision 387 lists what was checked and what differed):
// - Shiqiuling's tunnel was dug from both ends; where they met the two were
//   at different heights and had to be evened out, so the north portal's
//   arch is the taller; Liu wrote 「曠宇天開」 over the south portal
//   (Chinese Wikipedia, "獅球嶺隧道");
// - Teng-Yun was built in Germany (Chinese Wikipedia, "騰雲號");
// - the line's staff, its drivers among them, were largely foreign
//   (Chinese Wikipedia, "全臺鐵路商務總局");
// - a test train ran from Twatutia to Xikou in July 1888 before thousands
//   of onlookers (Taipei Times, Han Cheung, 2016-08-14);
// - Twatutia's oolong sold in New York as "Formosa Tea" (Chinese
//   Wikipedia, "大稻埕");
// - the wooden bridge over the Tamsui was finished in 1889, the Twatutia
//   to Hsinchu side ran before the Keelung side opened in 1891, and Taipei
//   Bridge stands where it was (Chinese Wikipedia, "臺北橋": finished in
//   August 1889, wood because iron cost too much); Liu left office through
//   ill health in 1891 (Chinese and English Wikipedia, "劉銘傳" / "Liu
//   Mingchuan");
// - the line reached Hsinchu in 1893 and his successor Shao Youlian built
//   no further, for its cost and the hard ground (Chinese Wikipedia,
//   "新竹車站"; the Taipei Times gives 1894, and Wikipedia is not
//   consistent: the challenge keeps its opening's 1893).

extension LiuMingchuanChallenge {
    static let story = ChallengeStory(challengeID: Challenge.liuMingchuan.id, beats: [
        StoryBeat(
            "liu.1", .day(5), .ahShui,
            "The governor's railway has to get past Shiqiuling first, so start by laying track from Keelung to Badu. We're digging that hill from both ends at once, and whether the two halves meet is anyone's guess.",
            "巡撫的鐵路得先過獅球嶺，先從基隆鋪到八堵吧。那座山要從南北兩頭一起挖，挖到中間能不能對上，全看運氣。"
        ),
        StoryBeat(
            "liu.2", .milestone(0), .ahShui,
            "When the two ends met, one was well above the other, and we had to even it out. That's why the north arch stands taller. The governor had 'the heavens open onto a vast land' carved over the south portal.",
            "兩頭挖到中間，高低差了一大截，只好再修平，所以北口的拱頂比較高。巡撫在南口題了『曠宇天開』四個字。",
            after: .beat("liu.1")
        ),
        StoryBeat(
            "liu.3", .riders(percent: 25), .walsh,
            "My engine, Teng-Yun, came all the way from Germany. She's a little thing and wheezes on every steep grade, but hook on more coaches and each run carries a lot more people.",
            "我開的騰雲號是從德國運來的，小小一台，坡一陡就喘。車廂多掛幾節，一趟就能多載不少人。",
            carries: .shortSteamTrains
        ),
        StoryBeat(
            "liu.4", .milestone(1), .ye,
            "The railway's reached Twatutia! Our oolong has sold in New York as 'Formosa Tea' for years, and now people and goods have another way to travel.",
            "火車開到大稻埕了！我們的烏龍茶早就以『Formosa Tea』的名號賣到紐約，往後人和貨都多了一條路。"
        ),
        StoryBeat(
            "liu.5", .riders(percent: 50), .stationMaster,
            "When the first test train ran from Twatutia to Xikou in 1888, thousands turned out just to watch. More people want to ride every day, so run the trains more often.",
            "1888 年列車從大稻埕試開到錫口，聽說來看熱鬧的有好幾千人。想坐的人越來越多了，讓列車多跑幾趟吧。"
        ),
        StoryBeat(
            "liu.6", .milestone(2), .walsh,
            "This wooden bridge over the Tamsui was finished in 1889, two years before the Keelung line opened, and it was the forerunner of today's Taipei Bridge. Now that we're across, put a station at Taoyuan, because folks there are waiting to ride too.",
            "淡水河上這座木橋 1889 年就搭好了，比基隆那段還早兩年通車，後來的台北大橋就蓋在這裡。過了河，記得在桃仔園蓋個站，那邊的人也等著坐車。"
        ),
        StoryBeat(
            "liu.7", .riders(percent: 75), .ye,
            "More and more customers come into town by train to buy tea. Shouldn't the ones who ride further pay a bit more?",
            "搭火車進城買茶的客人越來越多了。坐得越遠，車票是不是也該收得多一點？"
        ),
        StoryBeat(
            "liu.8", .cashBelowZero, .stationMaster,
            "The treasury's empty, and if this goes on we'll be bankrupt. Take out a loan, lengthen the trains, or cut the runs that lose money.",
            "庫銀見底了，再這樣下去會破產。可以先借一筆錢、把列車加長，或減掉賠錢的班次。",
            carries: .debt
        ),
        StoryBeat(
            "liu.9", .milestone(3), .stationMaster,
            "Liu resigned through ill health in 1891, before the Keelung–Taipei line even opened. When the railway reached Hsinchu in 1893, his successor stopped there, citing cost and hard engineering. The track is done; now bring more riders aboard each day.",
            "劉銘傳 1891 年因病辭官，沒等到基隆—台北通車；鐵路 1893 年到了新竹，接任的邵友濂以經費不足、工程困難為由，不再往南鋪。路通了，接下來要讓每天坐車的人再多一些。"
        ),
        StoryBeat(
            "liu.10", .yearClosed, .ahShui,
            "Another year gone. Shiqiuling cost many lives to dig, so let's make this railway last: check this year's books and start with whichever stretch loses money.",
            "又過了一年。當年挖獅球嶺死傷了不少人，這條路要好好經營下去：看看今年的帳，從賠錢的那一段改起。"
        ),
        StoryBeat(
            "liu.gold", .completed(.gold), .ahShui,
            "Keelung to Hsinchu in just a few months, when it took us six years. The governor would want to push on to Tainan the moment he saw it.",
            "才短短幾個月就從基隆通到新竹，當年我們可是花了六年。巡撫要是看到，一定想接著往台南鋪下去。"
        ),
        StoryBeat(
            "liu.silver", .completed(.silver), .walsh,
            "Keelung to Hsinchu inside a year, and Teng-Yun's become famous for it. Tell this story back in England and no one would believe me.",
            "一年就從基隆跑到新竹，騰雲號都跑出名了。這故事帶回英國，大概沒人會相信。"
        ),
        StoryBeat(
            "liu.bronze", .completed(.bronze), .stationMaster,
            "It took years, much as it did back then, but Keelung to Hsinchu is open at last. The line may never make money, but people and tea have a new road from now on.",
            "花了好幾年，基隆到新竹總算通了，跟當年差不多。這條線不賺錢，但從此人和茶都多了一條路。"
        ),
        StoryBeat(
            "liu.failed", .failed, .stationMaster,
            "This time the railway didn't get finished. The real one ran short of money too and stopped at Hsinchu instead of reaching Tainan, so settle the books and try again.",
            "這一次，鐵路沒能完成。當年它也因為缺錢停在新竹，沒能鋪到台南；整理好帳本，再試一次吧。"
        ),
    ])
}
