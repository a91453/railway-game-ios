import GameCore

// The sandbox challenges' stories (decision 387): Three Towns, Railway
// Town and Railway Tycoon, written for the game and passed on by the owner.
// Mr Chou, Fang and Mayor Chen are made up, and the same three in all
// three; the station master is the game's (decision 122). The player names
// the company (`NetworkPostcard.companyName`), so the lines say "our
// company", and the towns are drawn from the seed, so no line names one.
// Three Towns has no year's-end beat: its deadline is its first year's
// end, the day its ending is told.

extension Challenge {
    static let sandboxStories = [threeTownsStory, cityBuilderStory, tycoonStory]

    /// Goals: link the three towns (0), riders a day (1).
    static let threeTownsStory = ChallengeStory(challengeID: threeTowns.id, beats: [
        StoryBeat(
            "threeTowns.1", .day(2), .chou,
            "The company's brand new and this is all the money we've got, so the three towns are in your hands. Start with a line between two of them and show everyone what a train can do.",
            "公司剛成立，帳上的錢就這些，三座鎮全靠你了。先在兩座鎮之間鋪第一條線，讓大家看看火車有多方便。",
            carries: .welcome
        ),
        StoryBeat(
            "threeTowns.2", .day(10), .mayorChen,
            "All my years as mayor, I watched young people rattle off to the next town on the bus every morning. If only there'd been a train.",
            "我當鎮長那些年，年輕人每天搭客運去隔壁鎮上班，一路搖搖晃晃。要是有火車就好了。"
        ),
        StoryBeat(
            "threeTowns.3", .riders(percent: 25), .stationMaster,
            "More people are starting to take the train. Put stations where the people are, and right in the middle of town is best.",
            "坐火車的人開始變多了。車站要蓋在人多的地方，鎮中心最好。"
        ),
        StoryBeat(
            "threeTowns.4", .milestone(0), .fang,
            "Extra, extra! All three towns are connected by rail as of today, and the bus queues have vanished because everyone's on the platforms.",
            "號外！三座鎮今天全部通車，客運站前的人龍不見了，大家都跑去月台了。"
        ),
        StoryBeat(
            "threeTowns.5", .riders(percent: 50), .fang,
            "I met a schoolkid on the train today who used to see his friends in the next town only on weekends. Now he just hops on after class.",
            "我今天在車上遇到一個中學生，他說以前週末才見得到隔壁鎮的朋友，現在放學就能去找他們。",
            after: .beat("threeTowns.4")
        ),
        StoryBeat(
            "threeTowns.6", .riders(percent: 75), .stationMaster,
            "The platforms are filling up. Rather than laying more lines, make every train longer so each run carries more people.",
            "月台上等車的人越來越多了。與其再鋪新路線，不如把每一列車加長，一趟載更多人。"
        ),
        StoryBeat(
            "threeTowns.7", .cashBelowZero, .chou,
            "Accounting says we're broke, and if this keeps up the company goes under! Shut down the lines that lose money and hold off on building anything new.",
            "會計說帳上沒錢了，再這樣下去公司會破產！先停掉賠錢的路線，新的東西暫時別蓋。",
            carries: .debt
        ),
        StoryBeat(
            "threeTowns.8", .firstProfitableDay, .chou,
            "We turned a profit today for the first time! I'm framing today's ledger and hanging it on the office wall.",
            "今天第一次賺錢！我要把今天的帳單裱框，掛在辦公室牆上。"
        ),
        StoryBeat(
            "threeTowns.gold", .completed(.gold), .mayorChen,
            "I never dreamed it would happen so fast: three towns that feel like one city. This old mayor can rest easy now.",
            "沒想到這麼快，三座鎮就像一座城了。我這個老鎮長，可以安心了。"
        ),
        StoryBeat(
            "threeTowns.silver", .completed(.silver), .fang,
            "I've already got tomorrow's front page: 'Rail Ties Three Towns Together — No More Bumpy Bus Rides.'",
            "明天的頭版標題我想好了：『鐵路串起三座鎮，通勤不再搖大半天』。"
        ),
        StoryBeat(
            "threeTowns.bronze", .completed(.bronze), .chou,
            "It took a while, but we got there. Next, I want to watch these little towns grow into a real city!",
            "花了不少時間，總算做到了。下一步，我想看這些小鎮長成大城市！"
        ),
        StoryBeat(
            "threeTowns.failed", .failed, .stationMaster,
            "This time the railway didn't bring the three towns together. Next time, connect all three first, then lengthen the trains, and give it another go.",
            "這一次，鐵路沒能把三座鎮串起來。下次先把三座鎮都接通，再把列車加長，重新試一次吧。"
        ),
    ])

    /// Goals: population (0), high-rises (1), riders a day (2).
    static let cityBuilderStory = ChallengeStory(challengeID: cityBuilder.id, beats: [
        StoryBeat(
            "cityBuilder.1", .day(2), .chou,
            "This time the board wants more than passengers. They want a city, and wherever the railway goes, the buildings will follow.",
            "這次董事會要的不只是乘客，是一座城市。鐵路鋪到哪裡，房子就會蓋到哪裡。",
            carries: .welcome
        ),
        StoryBeat(
            "cityBuilder.2", .day(15), .mayorChen,
            "When I was young this was all rice paddies, and the tallest thing around was the co-op's grain silo. I'd love to see a real high-rise before I go.",
            "我年輕時這裡全是稻田，最高的建築是農會的穀倉。真想在有生之年看到一棟高樓。"
        ),
        StoryBeat(
            "cityBuilder.3", .progress(goal: 0, percent: 25), .fang,
            "Our investigation finds more and more people moving near the stations, and agents say land by the station is the hottest property in town.",
            "本報調查：搬到車站附近的人越來越多，房仲說站前的地最搶手。"
        ),
        StoryBeat(
            "cityBuilder.4", .progress(goal: 1, percent: 25), .mayorChen,
            "From my window I can't even count the towers anymore. Turns out a train really can bring a city with it.",
            "從我家窗戶看出去，已經數不清有幾棟高樓了。原來火車真的會把城市載來。",
            after: .beat("cityBuilder.2")
        ),
        StoryBeat(
            "cityBuilder.5", .progress(goal: 0, percent: 50), .stationMaster,
            "If you want towers around a station, you have to carry everyone off its platform. Wherever people are left waiting, add trains there first.",
            "車站周邊要長高樓，月台上的人就得載得走。哪一站有人等不到車，就先幫那一站加車。",
            carries: .crowding
        ),
        StoryBeat(
            "cityBuilder.6", .progress(goal: 1, percent: 75), .stationMaster,
            "The towers keep going up, and the people living in them need trains too. Put another station near the new high-rise blocks.",
            "高樓越來越多，住在裡面的人也要坐車。在新的高樓區附近再設一站吧。",
            after: .beat("cityBuilder.4")
        ),
        StoryBeat(
            "cityBuilder.7", .cashBelowZero, .chou,
            "The city's growing but our money's gone, and if this goes on we'll go bankrupt! Cut the trains running empty and save the money for the lines people actually fill.",
            "城市在長，公司的錢卻見底了，再這樣下去會破產！先把空蕩蕩的班次減掉，把錢留給坐得滿的路線。",
            carries: .debt
        ),
        StoryBeat(
            "cityBuilder.8", .yearClosed, .fang,
            "Year-end feature: another year, and a few more streets along the line. From the hills at night, the lights now run together into one.",
            "年終特稿：這一年，沿線又多了好幾條街；晚上從山上往下看，燈火已經連成一片。"
        ),
        StoryBeat(
            "cityBuilder.gold", .completed(.gold), .mayorChen,
            "I lived to see it, and not just one tower either. This city came here by train.",
            "我在有生之年看到了，而且還不只一棟。這座城市，是鐵路載來的。"
        ),
        StoryBeat(
            "cityBuilder.silver", .completed(.silver), .fang,
            "Today's front page: 'From Rice Paddies to Skyline — All Thanks to a Railway.'",
            "今天的頭版標題：『從稻田到天際線，只靠一條鐵路』。"
        ),
        StoryBeat(
            "cityBuilder.bronze", .completed(.bronze), .chou,
            "Took a bit longer than I'd hoped, but the city's here. Now it's time for the company to grow too.",
            "慢了點，但城市真的長出來了。接下來，該讓公司也長大了。"
        ),
        StoryBeat(
            "cityBuilder.failed", .failed, .stationMaster,
            "The city didn't grow this time. Next time, look after the stations where people can't get on, and the towers will follow.",
            "這次城市沒能長起來。下次先顧好那些擠不上車的車站，高樓自然會跟著來。"
        ),
    ])

    /// Goals: net profit in a year (0), company worth (1).
    static let tycoonStory = ChallengeStory(challengeID: tycoon.id, beats: [
        StoryBeat(
            "tycoon.1", .day(2), .chou,
            "My dream is to make our company the biggest railway company in the country. Make money, reinvest it, make more. You know how it goes.",
            "我的夢想，是把我們公司做成全國最大的鐵道企業。賺錢、再投資、再賺錢，你懂我的意思。",
            carries: .welcome
        ),
        StoryBeat(
            "tycoon.2", .day(20), .fang,
            "The business desk wants me covering a young railway company, and that's you. What readers really want to know is how far you can go.",
            "財經版要我追蹤一家剛起步的鐵道公司，就是你們。讀者最想知道的是：你們能走多遠？"
        ),
        StoryBeat(
            "tycoon.3", .firstProfitableDay, .chou,
            "We're finally in the black! Don't celebrate yet; put that money into the next line that'll earn.",
            "終於賺錢了！先別急著慶祝，把錢拿去鋪下一條會賺錢的線。"
        ),
        StoryBeat(
            "tycoon.4", .progress(goal: 0, percent: 25), .stationMaster,
            "Your earning lines are the company's capital. Find the one that makes the most and run more trains on it.",
            "賺錢的路線是公司的本錢。看看哪條線最賺，就在那條線上加車。"
        ),
        StoryBeat(
            "tycoon.5", .progress(goal: 1, percent: 25), .mayorChen,
            "Your company's putting up more and more around town. Back when I was mayor, the biggest business here was a soy sauce factory.",
            "你們公司在鎮上蓋的東西越來越多了。我當鎮長的時候，這裡最大的公司是一間醬油廠。"
        ),
        // The script's "businesses of your own" named as the building
        // tool names them (decision 173), so the player can find them.
        StoryBeat(
            "tycoon.6", .progress(goal: 1, percent: 50), .stationMaster,
            "The company's money isn't only for laying track. Use the Buildings tool to open a department store, hotel or amusement park beside a station, and the more passengers there are, the better it'll do.",
            "公司的錢不只能拿來鋪鐵路。用建物工具在車站旁開百貨公司、飯店或遊樂園，乘客越多，生意就越好。",
            after: .beat("tycoon.5")
        ),
        StoryBeat(
            "tycoon.7", .cashBelowZero, .chou,
            "We grew too fast and the money's gone, and if this goes on we'll go bankrupt! Stop the new projects and close the lines that lose money.",
            "擴張得太快，帳上沒錢了，再這樣下去會破產！新工程先停下來，把賠錢的路線收掉。",
            carries: .debt
        ),
        StoryBeat(
            "tycoon.8", .yearClosed, .fang,
            "Year-end business special: the whole industry is watching to see what this railway company delivered this year.",
            "年終財經特刊：這家鐵道公司今年交出什麼成績，整個業界都在看。"
        ),
        StoryBeat(
            "tycoon.gold", .completed(.gold), .chou,
            "When I started out we had one line and a handful of trains, and now the whole industry is watching us. Thank you. Next stop: the whole country!",
            "我創業的時候只有一條線、幾列車，現在整個業界都在看我們。謝謝你，下一站，全國！"
        ),
        StoryBeat(
            "tycoon.silver", .completed(.silver), .fang,
            "Business headline: 'From Little Local Railway to Industry Giant.' Best story I've written all year.",
            "財經版頭條：『從地方小鐵路到大企業』。這是我今年最滿意的一篇報導。"
        ),
        StoryBeat(
            "tycoon.bronze", .completed(.bronze), .mayorChen,
            "From a soy-sauce-factory town to home of a railway giant. It took you a while, but you made it.",
            "從醬油廠的小鎮，到有鐵道大企業的城市，你們花了些時間，但做到了。"
        ),
        StoryBeat(
            "tycoon.failed", .failed, .stationMaster,
            "The company didn't make the big time this time. Next time, look after your best-earning lines first, then grow one step at a time.",
            "這次公司沒能成為大企業。下次先顧好最賺錢的路線，再一步一步擴張。"
        ),
    ])
}
