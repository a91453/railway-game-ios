// The data sources page: the 3D city preview, the music and the sounds.
// One file of `DataSourceCredits` (DATA-CREDITS-PER-MAP): `sections(in:)` in
// DataSourceCredits.swift lists the sections in their order; the shared
// links and notices are there too.

extension DataSourceCredits {
    /// Decision 152: the 3D city view of the settings' preview.
    static func cityViewSection(in language: DisplayLanguage) -> DataSourceSection {
        DataSourceSection(
            id: "cityView",
            title: language.text("3D City Preview", "3D 城市預覽"),
            credits: [
                DataSourceCredit(
                    id: "proceduralTokyo",
                    title: "Procedural Tokyo",
                    detail: language.text(
                        "Draws the 3D city round Kaohsiung and Taichung Stations: buildings, street furniture, traffic, trains, sky and light.",
                        "畫出高雄車站與台中車站周圍的 3D 城市：建物、街道設施、車流、列車、天空與光線。"
                    ),
                    notice: language.text(
                        "Copyright (c) 2026 Yong Su, under the MIT License. It bundles three.js, postprocessing, N8AO, takram three-geospatial, ez-tree, lil-gui and earcut; the page is on the game's website, and their licences (MIT, Zlib, ISC) are next to it, at the link below.",
                        "Copyright (c) 2026 Yong Su，依 MIT 授權使用。內含 three.js、postprocessing、N8AO、takram three-geospatial、ez-tree、lil-gui 與 earcut；網頁放在遊戲官網，這些程式庫的授權條款（MIT、Zlib、ISC）也在官網，可以從下方連結閱讀。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: "Procedural Tokyo", url: proceduralTokyoURL),
                    ] + (cityViewNoticesURL.map { [DataSourceCredit.Link(title: language.text("Licences", "授權條款"), url: $0)] } ?? [])
                ),
                DataSourceCredit(
                    id: "polyHaven",
                    title: "Poly Haven",
                    detail: language.text(
                        "The textures of the 3D city’s walls, roofs, roads, pavements and grass.",
                        "3D 城市的牆面、屋頂、道路、人行道與草地材質。"
                    ),
                    notice: language.text(
                        "Under CC0 1.0 (public domain dedication).",
                        "依 CC0 1.0（公眾領域貢獻宣告）使用。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: "Poly Haven", url: polyHavenURL),
                        DataSourceCredit.Link(title: "CC0 1.0", url: cc0URL),
                    ]
                ),
            ]
        )
    }

    /// Decision 343: the running sounds are the game's own, made to
    /// the spectra of these recordings (tools/audio/README.md); none
    /// of them is bundled. CC BY 3.0 asks for the author, the title,
    /// the licence and that the work was changed.
    static func soundsSection(in language: DisplayLanguage) -> DataSourceSection {
        DataSourceSection(
            id: "sounds",
            title: language.text("Sounds", "聲音"),
            credits: [
                // Decision 815's later note: the theme is the game's own
                // composition and the winter tune its own arrangement of
                // a tune in the public domain, both the developer's;
                // the instruments are sample banks' (the piano, the
                // strings and the harp recorded ones, THEME-PLAIN
                // item 1).
                DataSourceCredit(
                    id: "music",
                    title: language.text("Music", "音樂"),
                    detail: language.text(
                        "The theme and the departure melodies are original compositions for the game. The winter tune is the game’s own arrangement of Jingle Bells (James Lord Pierpont, 1857, in the public domain). The piano is the Salamander Grand Piano, the strings and harp are from VS Chamber Orchestra: Community Edition, and the other instruments are from GeneralUser GS.",
                        "主題曲與發車旋律是為遊戲原創的曲子；冬季曲是遊戲自己編曲的〈Jingle Bells〉（James Lord Pierpont 1857 年作，屬公眾領域）。鋼琴是 Salamander Grand Piano，弦樂與豎琴取自 VS Chamber Orchestra: Community Edition，其他樂器取自 GeneralUser GS。"
                    ),
                    notice: language.text(
                        "Music © 2026 \(musicHolder.english). All rights reserved. Instrument samples: Salamander Grand Piano V3 by Alexander Holm, under CC BY 3.0, changed (one microphone, levels and tone); VS Chamber Orchestra: Community Edition by Versilian Studios, under CC0 1.0; GeneralUser GS by S. Christian Collins, under the GeneralUser GS License v2.0.",
                        "音樂版權所有 © 2026 \(musicHolder.chinese)，保留一切權利。樂器取樣：Alexander Holm 的 Salamander Grand Piano V3，依 CC BY 3.0 使用，經修改（只取一支麥克風、調整音量與音色）；Versilian Studios 的 VS Chamber Orchestra: Community Edition，依 CC0 1.0；S. Christian Collins 的 GeneralUser GS，依 GeneralUser GS 授權第 2.0 版使用。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: "Salamander Grand Piano", url: salamanderPianoURL),
                        DataSourceCredit.Link(title: "CC BY 3.0", url: ccBy3URL),
                        DataSourceCredit.Link(title: "VS Chamber Orchestra: Community Edition", url: vscoURL),
                        DataSourceCredit.Link(title: "GeneralUser GS", url: generalUserGSURL),
                    ]
                ),
                DataSourceCredit(
                    id: "runningSound",
                    title: language.text("Train recordings", "列車錄音"),
                    detail: language.text(
                        "The sound of a train you follow, which the game makes to sound like these recordings: a KTX in Korea and two trains in Taiwan.",
                        "跟隨列車時的行駛聲，遊戲照這些錄音自己合成：韓國的 KTX 與台灣的兩班列車。"
                    ),
                    notice: language.text(
                        "“Banqiao District, New Taipei City - In the train compartment” by Wu, Tsan-Cheng, under CC BY 3.0. “Guishan, Taoyuan - On the train” by Wu, Tsan-Cheng and “KTX high speed train to Busan” by abyssence, in the public domain. All three on radio aporee ::: maps. The game plays none of the recordings themselves: its sounds are made after them.",
                        "〈Banqiao District, New Taipei City - In the train compartment〉，吳燦政錄音，依 CC BY 3.0 使用。〈Guishan, Taoyuan - On the train〉，吳燦政錄音，與〈KTX high speed train to Busan〉，abyssence 錄音，屬公眾領域。三者都在 radio aporee ::: maps。遊戲不播放錄音本身，聲音是照它們合成的。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Banqiao recording", "板橋錄音"), url: banqiaoRecordingURL),
                        DataSourceCredit.Link(title: language.text("Guishan recording", "龜山錄音"), url: guishanRecordingURL),
                        DataSourceCredit.Link(title: language.text("KTX recording", "KTX 錄音"), url: ktxRecordingURL),
                        DataSourceCredit.Link(title: "CC BY 3.0", url: ccBy3URL),
                    ]
                ),
                // Decision 567: the diesel railcar's running sounds, made
                // the same way. The site's terms ask for its name, as
                // written here, and its address wherever its sounds are
                // used, changed or not.
                DataSourceCredit(
                    id: "dieselSound",
                    title: language.text("Diesel railcar recordings", "柴油客車錄音"),
                    detail: language.text(
                        "The engine of a diesel train you follow, idling, pulling away and coasting, which the game makes to sound like these recordings of a KiHa 40 series railcar in Japan.",
                        "跟隨柴油車時的引擎聲：怠轉、起步加速與惰行，遊戲照這些日本キハ40 系柴油客車的錄音自己合成。"
                    ),
                    notice: language.text(
                        "Railway sound materials (てつおん素材), KiHa 40 series (renewed), from Simulation Country GAPAN 月本國, https://gepponkoku.nation.jp. The game plays none of the recordings themselves: its sounds are made after them.",
                        "てつおん素材「キハ40系旧国鉄一般形気動車(更新車)」，出自 Simulation Country GAPAN 月本國，https://gepponkoku.nation.jp。遊戲不播放錄音本身，聲音是照它們合成的。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: "Simulation Country GAPAN 月本國", url: gepponkokuURL),
                    ]
                ),
                // Decision 664: an electric train's motors, made the
                // same way from the same site's 313 series recordings.
                DataSourceCredit(
                    id: "motorSound",
                    title: language.text("Electric train recordings", "電車錄音"),
                    detail: language.text(
                        "The motors of an electric train you follow, pulling away and braking, which the game makes to sound like these recordings of a 313 series train in Japan.",
                        "跟隨電車時的馬達聲：起步加速與煞車，遊戲照這些日本 313 系電車的錄音自己合成。"
                    ),
                    notice: language.text(
                        "Railway sound materials (てつおん素材), 313 series (3000 番台), from Simulation Country GAPAN 月本國, https://gepponkoku.nation.jp. The game plays none of the recordings themselves: its sounds are made after them.",
                        "てつおん素材「313系(3000番台)近郊型直流電車」，出自 Simulation Country GAPAN 月本國，https://gepponkoku.nation.jp。遊戲不播放錄音本身，聲音是照它們合成的。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: "Simulation Country GAPAN 月本國", url: gepponkokuURL),
                    ]
                ),
                // Decision 346: the weather's sounds, made the same way.
                DataSourceCredit(
                    id: "weatherSound",
                    title: language.text("Rain and thunder recordings", "雨聲與雷聲錄音"),
                    detail: language.text(
                        "The rain, the typhoon’s wind and the thunder, which the game makes to sound like these recordings in Taipei and Tamsui.",
                        "雨聲、颱風的風雨聲與雷聲，遊戲照這些在台北與淡水錄的聲音自己合成。"
                    ),
                    notice: language.text(
                        weatherRecordings.map { "“\($0.title)”" }.joined(separator: ", ") + ", all by Wu, Tsan-Cheng, under CC BY 3.0, on radio aporee ::: maps. The game plays none of the recordings themselves: its sounds are made after them.",
                        weatherRecordings.map { "〈\($0.title)〉" }.joined(separator: "、") + "，都是吳燦政錄音，依 CC BY 3.0 使用，在 radio aporee ::: maps。遊戲不播放錄音本身，聲音是照它們合成的。"
                    ),
                    links: weatherRecordings.map {
                        DataSourceCredit.Link(title: language.text($0.place.english, $0.place.chinese), url: "https://archive.org/details/\($0.id)")
                    } + [DataSourceCredit.Link(title: "CC BY 3.0", url: ccBy3URL)]
                ),
            ]
        )
    }
}
