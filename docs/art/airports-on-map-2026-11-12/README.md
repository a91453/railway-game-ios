# 機場接進 3D 地圖：看圖四輪（決策 699，2026-11-12）

![五座航廈的遊戲鏡頭（日、夜）與降落中的一架](overview.jpg)

規矩在 [model-look skill](../../../.claude/skills/model-look/SKILL.md)。程式是 `Sources/GamePresentation/Map3DAirfields.swift`（場面）與 `Map3DAircraft.swift`（飛機），資料是 `tools/airfields/`。這裡只放一張總覽圖；每一輪的截圖、高處與遠景、fps 對照、2D 標記與面板的截圖、參考照片在私有素材庫 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/airports-on-map-2026-11-12/`。

圖都是這台 Mac 的 iPhone 模擬器（iPhone 18 Pro，iOS 27.2，橫放）拍的，沒有開 CI 的截圖 run。重拍：

```sh
xcodebuild build-for-testing -project RailwayGameApp/RailwayGame.xcodeproj -scheme RailwayGame -destination 'id=<模擬器>'
xcodebuild test-without-building … -only-testing:RailwayGameUITests/WebsiteScreenshotTests/testAirportsIn3D -resultBundlePath out.xcresult
xcrun xcresulttool export attachments --path out.xcresult --output-path shots
```

`TEST_RUNNER_AIRPORT_SHOTS=airportSongshan,airportSongshanNight` 只拍指定的場景，`TEST_RUNNER_AIRPORT_VIEWS=game` 只拍指定的鏡頭（`game` 800 m、`game1` 桃園一航廈、`high` 2,600 m、`far` 9,000 m）。

## 參考與特徵

這次不是做一個新模型（飛機、塔台、地勤車的外觀是決策 698 看過四輪的），而是把它們和真實的場面擺進地圖，所以對的是**整座機場從空中看的樣子**。照片都來自 Wikimedia Commons，只拿來比對配置與顏色，沒有當貼圖、沒有放進這個 repo：

| 照片 | 作者 | 授權 | 用來看 |
| --- | --- | --- | --- |
| [Taiwan Taoyuan Airport from departing flight May 2025.jpg](https://commons.wikimedia.org/wiki/File:Taiwan_Taoyuan_Airport_from_departing_flight_May_2025.jpg) | 4300streetcar | CC BY 4.0 | 桃園全場：兩條平行跑道夾著航廈與登機廊 |
| [Taoyuan Airport Terminal 1 Aerial View.jpg](https://commons.wikimedia.org/wiki/File:Taoyuan_Airport_Terminal_1_Aerial_View.jpg) | 交通部鐵道局 | Attribution | 一航廈與登機廊、空橋與停著的飛機 |
| [Taoyuan Airport from above at night.jpg](https://commons.wikimedia.org/wiki/File:Taoyuan_Airport_from_above_at_night.jpg) | Jidanni | CC0 | 夜間：機坪的泛光與跑道燈 |
| [Taichung Airport Airfield color.jpg](https://commons.wikimedia.org/wiki/File:Taichung_Airport_Airfield_color.jpg) | 写真小僧 | CC BY-SA 3.0 | 臺中全場：一條南北向跑道、平行滑行道 |
| [Remote view of Taipei 101, Taipei City and Taipei Songshan Airport at sunset.jpg](https://commons.wikimedia.org/wiki/File:Remote_view_of_Taipei_101,_Taipei_City_and_Taipei_Songshan_Airport_at_sunset.jpg) | Wei-Te Wong | CC BY-SA 2.0 | 松山：市區裡的一條東西向跑道 |
| [Taipei skyline from Songshan Airport 20170611.jpg](https://commons.wikimedia.org/wiki/File:Taipei_skyline_from_Songshan_Airport_20170611.jpg) | Rutger van der Maar | CC BY 2.0 | 松山機坪 |
| [EVA Air MD-90 Landing down Taipei Songshan Airport Runway 20090926.jpg](https://commons.wikimedia.org/wiki/File:EVA_Air_MD-90_Landing_down_Taipei_Songshan_Airport_Runway_20090926.jpg) | 玄史生 | CC BY-SA 3.0 | 降落的姿態 |
| [Kaohsiung Airport Terminal.jpg](https://commons.wikimedia.org/wiki/File:Kaohsiung_Airport_Terminal.jpg) | Alec @ Taiwan | CC BY 2.0 | 高雄航廈 |

尺寸與位置：全部照 OpenStreetMap（© OpenStreetMap contributors，ODbL 1.0）。跑道的長、寬、方向、號碼是 OSM 的；航廈的平面是建物足跡；高度是足跡的樓層數（至少四層），不是量的。

憑什麼認得出是機場，以及是哪一座：

- 一條又長又直的深灰跑道，白色的邊線、中線、跑道頭的斑馬線與號碼；旁邊有平行的滑行道與黃線。
- 一大片淺灰的停機坪，上面一排一排停著飛機，機鼻對著航廈。
- 航廈：藍灰屋頂、白邊，伸出一根根空橋。
- 晚上：兩排跑道邊燈拉成一條線，機坪上一團一團的泛光。
- **桃園**：兩條平行跑道（05L／23R、05R／23L）夾著中間的航廈與長長的登機廊，廣體機多。**松山**：市區裡一條東西向跑道（10／28），航廈在南側。**臺中**：一條南北向跑道（18／36），航廈在西南角。**高雄**：一條東西向跑道（09／27），U 形的國際航廈與一字形的國內航廈在北側。

## 每一輪

| 輪 | 看圖找到的毛病 | 改了什麼 |
|---|---|---|
| 0（接之前） | 機場在 3D 地圖上是一片白：沒有跑道、沒有停機坪，航廈是和地面同色的矮盒子 | — |
| 1 | 跑道、滑行道、標線、飛機都有了，但柏油被 3D 畫風調成中灰、停機坪和地面幾乎同色；航廈還是白的；白飛機在淺色地上看不到；松山的遊戲鏡頭對著跑道中段的草地，看不到航廈 | 鋪面與標線的顏色列進畫風「不調淡」的那一組；航廈改成白牆、藍灰屋頂（加深一階）；鏡頭對準機位 |
| 2 | 桃園的主航廈（登機廊後面的大廳）還是白的：它不靠空橋，沒被認成航廈；航廈屋頂是一整片平的藍；夜間機坪的光池太大太亮，高處看像一排圓點；起降的飛機落地後在跑道上消失、起飛前憑空出現 | 緊貼航廈的大建物也算航廈；屋頂加白邊，方正的大廳與登機廊加採光帶與白色橫肋；光池縮小調暗；飛機沿滑行道進出機位、後推；加地勤車 |
| 3 | 松山跑道頭上站著幾棟房子（足跡資料裡有，沒有清掉）；改成一半機位給航班輪用之後，桃園的機位空了一大半；降落那張的鏡頭沒對到飛機，而且算的是桃園的班次 | 跑道佔的格子不留建物；固定停著的機位從四分之一加到一半；降落場景改用地圖中央那座機場的班次，鏡頭對準跑道頭外 |
| 4 | 見下面「還有哪裡不好」 | — |

清單現況（事實，不是評分）：

1. **像盒子**：航廈是真實輪廓拉高的平頂量體，屋頂只有白邊、採光帶、橫肋，沒有拱頂。形狀不規則的航廈（高雄國際線的 U 形、桃園的折線登機廊）只有白邊。
2. **比例不對**：平面是 OSM 的，照真的。高度是樓層數推的，桃園二航廈的大廳實際比登機廊高得多，這裡差不多高。
3. **窗戶太平**：航廈的牆是一整面玻璃格的貼圖，沒有進出。
4. **屋頂與牆接不起來**：過（平頂，白邊壓在牆頂）。
5. **零件浮空**：空橋兩端有支柱；飛機、地勤車站在停機坪上。臺中補的機位有兩架飛機的翼尖碰到航廈的邊。
6. **顏色灰、糊成一片**：深灰跑道、中灰滑行道、淺灰停機坪、淺色地面、藍灰屋頂、綠草，分得開。
7. **光太平**：鋪面本來就是平的；靠顏色分。
8. **遠看認不出來**：9 km 高處看得出兩條跑道與航廈的藍色，機場標記在上面；2.6 km 看得到滑行道的黃線與停著的飛機（很小）。

## 效能

`testAirportsFrameCost`（模擬器，桃園，畫質「高」，打開幀數的細節；有機場與加 `-map3D.noAirfields` 沒有機場各一次）。數字見 PR；圖在私庫 `app/airport-cost-*.jpg`。模擬器的幀數不代表實機。

## 還有哪裡不好

- **航廈沒有自己的樣子**：五座都是「藍灰平頂加白邊」，分得出機場，分不出桃園一航廈的斜屋頂、二航廈的弧形屋面、松山的老航廈。真的輪廓救了平面，救不了立面。
- **桃園二航廈大廳的橫肋太密、太白**，像百葉窗；登機廊上的採光帶在折角的地方會斷。
- **停機坪偏空**：桃園在 09:30 實際上接近滿，這裡一半左右；松山、高雄也偏少。
- **飛機小**：800 m 鏡頭下窄體機只有二十幾點寬，七十座與十九座更小；白機身在淺灰停機坪上只靠尾翼色與影子認。
- **夜景只有地上的光**：飛機沒有航行燈與客艙窗，航廈的窗不亮，塔台只有桃園與臺中有。
- **滑行不讓路**：兩架飛機會在滑行道上交錯穿過；轉彎是在 16 m 內硬轉，不是沿弧線。
- **地勤車太小**：遊戲鏡頭下幾乎看不到，只有拉到最近才看得出是車。
- **臺中的機位是補的**：排在最靠近航廈的停機坪上，和實際的機位位置不同。
- **只在模擬器看過**：實機的顏色、遠處標線的閃爍（細帶子在遠處會不會閃）、幀數都沒驗。
