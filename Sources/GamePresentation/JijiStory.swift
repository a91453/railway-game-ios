import GameCore

// The Jiji challenge's story (decision 387), written for the game and
// passed on by the owner. Ah-Kun (who speaks only in his letters to his
// mother), Master Lin and Xiulan are made up; the station master is the
// game's (decision 122). Ah-Kun's letters come in order: each waits for the
// one before, and the beat about Jiji's station waits until the line
// reaches Jiji.
//
// The history in it is from public sources, checked on 2026-10-23
// (decision 387 lists what was checked and what differed):
// - the Taiwan Electric Power Company (臺灣電力株式會社) laid the line to
//   carry materials for the Sun Moon Lake works, finished in 1921 and open
//   in January 1922 (Chinese Wikipedia, "集集線"; English Wikipedia, "Jiji
//   line"; "臺灣電力株式會社");
// - the works began in 1919, malaria and dysentery took many workers,
//   recession and the Great Kanto Earthquake stopped them in 1926, and they
//   started again in 1931 and were finished in 1934, and the plant was
//   called "first in the East" (東洋第一; the script had "the biggest in
//   Asia") (nippon.com, 2018-01-22, on Matsuki Kan'ichirō; Chinese
//   Wikipedia, "大觀發電廠");
//   that the railway was sold to the Government-General because the works
//   stopped is a guess, which is why the letter says "they say";
// - Jiji's station was moved in 1930 from the old Yangmei station on the
//   main line, left leaning by the 921 earthquake and rebuilt as it was in
//   2001 (Chinese Wikipedia, "集集車站");
// - Checheng's name and its timber yard, the timber from Mount Danda
//   (Chinese and English Wikipedia, "車埕車站" / "Jiji line"), and its old
//   mill now a museum (TVBS Supertaste, undated).

extension BranchLineChallenge {
    static let jijiStory = ChallengeStory(challengeID: jiji.challengeID, beats: [
        StoryBeat(
            "jiji.1", .day(3), .stationMaster,
            "It's a long line and the towns along it are still small, so the first few months will be hard. Get by with one short train for now, and keep fares low enough that townsfolk will actually ride.",
            "這條線很長，沿線的鎮都還小，頭幾個月一定難熬。先用一列短車撐著，票價也別訂太高，讓鎮上的人願意坐。",
            carries: .welcome
        ),
        StoryBeat(
            "jiji.2", .day(10), .ahKun,
            "Dear Ma, work on the Sun Moon Lake power plant began this year, and soon everything the mountains need will come up from Ershui on the railway they're laying. Malaria and dysentery are everywhere, and the stretchers carrying men down the hill never stop.",
            "阿娘：日月潭的工程今年開工了，山裡要的材料，以後都靠正在鋪的鐵路從二水運進來。工地瘧疾、赤痢很多，被擔架抬下山的人沒停過。"
        ),
        StoryBeat(
            "jiji.3", .milestone(0), .xiulan,
            "When the 921 quake hit, this wooden station was left leaning badly, and it broke the whole town's heart. It was rebuilt just as it had been in 2001, and today trains are stopping here again.",
            "921 那年，這座木造車站被震得歪向一邊，全鎮的人看了都心疼。2001 年照原樣蓋了回來，今天又有火車停靠了。"
        ),
        StoryBeat(
            "jiji.4", .riders(percent: 25), .xiulan,
            "Did you know this station was taken down at the old Yangmei station on the main line and put back up here in 1930? With more people coming by train, the shops out front are getting busier too.",
            "你知道嗎？這座站房是 1930 年從縱貫線的舊楊梅車站拆過來重蓋的。坐車來的人多了，站前的店也跟著熱鬧起來。",
            after: .milestone(0)
        ),
        StoryBeat(
            "jiji.5", .cashBelowZero, .stationMaster,
            "We're out of money, and if this goes on we'll go bankrupt. Don't add trains yet: keep one short train running and hold on, because riders will come as the towns grow.",
            "錢用完了，再這樣下去會破產。先別加車，只留一列短車撐著，等沿線的鎮長大，乘客自然會多起來。",
            carries: .debt
        ),
        StoryBeat(
            "jiji.6", .milestone(1), .ahKun,
            "Dear Ma, with times so hard and the Great Kanto Earthquake on top of it, the company can't raise the money, so the works have stopped. They say even the railway is to be sold to the Government-General.",
            "阿娘：景氣不好，又碰上關東大地震，公司籌不到錢，工程只好停下來。聽說連這條鐵路都要賣給總督府了。",
            after: .beat("jiji.2")
        ),
        StoryBeat(
            "jiji.7", .riders(percent: 50), .lin,
            "Back in the day, the timber cut up on Mount Danda all rode this line out of the mountains. The 'cheng' in Checheng is Taiwanese for 'yard', and the yard out front used to be packed with push cars.",
            "從前丹大山上砍下來的木頭，都是坐這條線出山的。車埕的『埕』是台語『場』的意思，以前站前停滿了台車。"
        ),
        StoryBeat(
            "jiji.8", .milestone(2), .lin,
            "The trains are back in Checheng! I sawed timber in the mill here when I was young, and the old mill is a museum now, so bring the visitors round.",
            "火車又開到車埕了！我年輕時在木業工廠裡鋸木頭，現在舊廠房改成了展示館，帶遊客來看看吧。"
        ),
        StoryBeat(
            "jiji.9", .riders(percent: 75), .stationMaster,
            "The towns along the line have grown and the trains are getting crowded. Now's the time to think about adding another train so fewer people are left waiting.",
            "沿線的鎮長大了，車上越來越擠。現在可以考慮再加一列車，讓等車的人少一些。",
            carries: .crowding
        ),
        StoryBeat(
            "jiji.10", .ridersGoalMet, .ahKun,
            "Dear Ma, the works started again in 1931 and were finally finished in 1934, and they say it's the greatest power station in the East. Power from these mountains is going to light up the whole island, and it's time I came home.",
            "阿娘：工程 1931 年復工，1934 年終於完工，聽說是東洋第一的發電所。山裡的電要點亮全島了，我也該回家了。",
            after: .beat("jiji.6")
        ),
        StoryBeat(
            "jiji.11", .firstProfitableDay, .xiulan,
            "Word is the railway made money today! The town keeps growing, and the hardest days are finally behind us.",
            "聽說鐵路今天開始賺錢了！鎮上的人越來越多，最難熬的日子總算過去了。"
        ),
        StoryBeat(
            "jiji.12", .yearClosed, .stationMaster,
            "The year's books are closed, so see what we earned and where we're still losing money. As the towns grow, add trains bit by bit so more people get a seat.",
            "一年結算了，看看今年賺了多少、哪裡還在賠。鎮長大了，就慢慢加車，讓更多人坐得上車。"
        ),
        StoryBeat(
            "jiji.gold", .completed(.gold), .lin,
            "One year, and the trains from Ershui to Checheng are full every day. When I was young I watched timber ride this line out of the hills; now it's visitors riding in.",
            "才一年，從二水到車埕的列車天天坐滿。我年輕時看木頭坐這條線出山，現在換成遊客坐車進山來了。"
        ),
        StoryBeat(
            "jiji.silver", .completed(.silver), .xiulan,
            "Two years on, the square in front of Jiji station is lively again. Earthquake or landslide, this line always finds its way back.",
            "兩年下來，集集站前又熱鬧起來了。地震也好，坍方也好，這條線每次都回得來。"
        ),
        StoryBeat(
            "jiji.bronze", .completed(.bronze), .stationMaster,
            "It took three years, but the Jiji Line is on its feet at last. It has stopped running more than once, and every time someone brought it back. This time it was us.",
            "花了三年，集集線總算站穩了。它停駛過好幾次，每次都有人把它修回來，這次換我們。"
        ),
        StoryBeat(
            "jiji.failed", .failed, .stationMaster,
            "This time the Jiji Line didn't make it. The Sun Moon Lake works stopped for years too and were finished in the end, so try again, and go easy on spending in the first few months.",
            "這一次，集集線沒能撐下去。日月潭的工程也停過好幾年，最後還是完工了；再試一次，頭幾個月記得省著點。"
        ),
    ])
}
