# 遊戲的音樂與音效

`make_game_audio.py` 合成 App 的音樂與音效（`RailwayGameApp/Resources/Audio/`）。它和第一支介紹影片的配樂是同一套合成，所以遊戲聽起來和影片一樣（ARCHITECTURE 決策 79）。

```sh
python3 tools/audio/make_game_audio.py RailwayGameApp/Resources/Audio
```

需要 numpy，以及 `PATH` 上的 ffmpeg（把音樂轉成 IMA4 的 CAF）。每次輸出相同。同時寫出 `manifest.json`。

檢查（決策 219）：重新產生到暫存資料夾，每個音檔與 `manifest.json` 都要和提交的一個位元組都不差；`PATH` 上有 Node 時，也檢查樂譜和 MML 原稿一致。

```sh
python3 tools/audio/make_game_audio.py --check RailwayGameApp/Resources/Audio
```

## 產製流程（決策 219）

```
mml/名稱.mml（MML 原稿，MML Studio 寫的瑪奇六格 MML@…;）＋ mml/名稱.json（每一格的合成器聲音、用途、動機）
        │  node tools/audio/mml_to_score.mjs mml/名稱.mml（mml-core/core.js，MML Studio 的核心）
        ▼
scores/名稱.score.json（《沿線》樂譜，提交進 repo）
        │  python3 tools/audio/make_game_audio.py RailwayGameApp/Resources/Audio
        ▼
RailwayGameApp/Resources/Audio/*.wav ＋ manifest.json
```

- **MML 轉樂譜**只需要 Node（不用 npm 套件）。只有改了 MML 原稿才要重轉；Python 這一步與 App 的建置都不需要 Node。落不到整數 tick（每拍 960）的音一律拒絕，不四捨五入；不過 `core.js` 的 strict profile 只接受 1、2、3、4、6、8、12、16、24、32 分音符與單附點，這些都落在整數 tick 上，所以這條目前是保險。換速度（`T` 在中途改變）也拒絕：一首樂譜只有一個速度。V0 的音是靜音，拒絕。
- **MML 的音量 V1–V15** 轉成力度 `round(V × 127 ÷ 15)`。
- **樂譜也可以直接手寫**（`chime-local`、`chime-metro` 就是）：沒有 MML 的樂譜，`source` 寫出處。

## 《沿線》樂譜第 1 版（`*.score.json`）

`score.py` 檢查；之後 GameCore 用 `Codable` 檢查玩家的樂譜（第四階段）時照同一份規則。所有數字都是整數。

| 欄位 | 內容 |
| --- | --- |
| `format` | 1 |
| `role` | `chime`（到站鈴）、`departure`（發車旋律）、`stem`（配樂分軌） |
| `title` | 名稱 |
| `source` | 可省略：MML 原稿的路徑，或手寫樂譜的出處 |
| `tempo` | 每分鐘拍數，整首一個（20–300）。合成器另外要求每個 tick 是整數個取樣（48,000 × 60 是 `tempo` × 960 的倍數，例如 100、120、125、150） |
| `beatsPerBar` | 每小節幾拍（1–16） |
| `length` | 全長（tick）；鈴聲在這裡截斷 |
| `motif` | 高速時播前幾個音：鈴聲與發車旋律 2–3，分軌 0 |
| `fadeOut` | 結尾線性淡出的長度（tick），0 是不淡出 |
| `tracks[]` | 每軌：`voice`（`bell`、`pluck`、`pad`、`clack`）、`gain`（0–100）、`pan`（−100–100）、`notes[]` |
| `notes[]` | `pitch`（MIDI 0–127）、`start`、`length`（tick，結束不超過 `length`）、`velocity`（1–127）；依 `start`、`pitch` 排序，不重複 |

- **每拍 960 tick**：64 分音符 60、三連音 320、五連音 192 都整除。
- **力度是相對的**：合成時一個音的大小是 `velocity ÷ 最大的力度 × gain ÷ 100`，整個檔案再正規化到峰值。
- **撥弦與鐘聲會響過寫的長度**（鐘 2.2 秒、撥弦 0.9 秒，比寫的短時照自然的餘音），到樂譜結尾截斷；`pad` 照寫的長度；`clack` 固定 0.08 秒。所有軌都不左右移時輸出單聲道複製成兩聲道。
- **鈴聲（`role: chime`）另外的規則**（研究文件第 3 節）：最長 3 秒、最多 4 軌、音域 C3–C7（MIDI 48–96）、只用 C 大調五聲音階 C D E G A、動機的音都在前 0.68 秒內開始。
- **動機檔**：只播動機那幾個音，0.8 秒，最後 0.12 秒淡出，峰值同鈴聲 0.6。600 倍速以上在看的列車播它（研究文件第 6 節）。

## 清單（`manifest.json`）

腳本產生，不要手改。每個音檔一列：

- 來源：樂譜與它的 SHA-256；從 MML 轉來的，另記 MML 原稿與它的 SHA-256；沒有樂譜的音效記下合成它的函式；
- 音檔的 SHA-256、取樣數、秒數；
- 峰值與 RMS（dBFS）、相鄰兩個取樣最大的落差（`largestStep`）；
- 循環的音樂、行駛聲與雨聲記 `loopSeam`（最後一個取樣跳回第一個的落差，比 `largestStep` 大就會聽到「喀」一聲），單次的音效記 `endLevel`（最後一個取樣的大小）。

另外記下 `mml-core/core.js` 的來源 commit 與 SHA-256。三種到站鈴的 RMS 差超過 3 dB 時腳本停下（研究文件第 3 節）。

## 檔案

| 檔案 | 內容 | 遊戲裡 |
| --- | --- | --- |
| `music-loop.caf` | 38.4 秒、可無縫循環的音樂：和弦墊、琶音與鐵軌接縫聲，C 大調 I – vi – IV – V，100 bpm；IMA4，48 kHz 立體聲 | App 在前景時循環播放 |
| `station-chime.wav` | 兩個音的到站鈴（C6、G6），樂譜 `scores/chime-local.score.json` | 在看的列車到「地方小站」；沒在看的列車到任何站（小聲，決策 219） |
| `chime-metro.wav` | 四音鐘 C5–E5–G5–C6，每 0.3 秒一個，1.8 秒；照搬參考庫的 `chimeBuffer`，用我們的鐘聲，樂譜 `scores/chime-metro.score.json` | 在看的列車到「都會轉運」站：停靠的客運路線 2 條以上，或有高鐵（決策 219） |
| `chime-tourist.wav` | 撥弦 G5 A5 C6 D6 往上、E6、落在 C6，下面一聲小小的 C5 鐘，五聲音階，2.4 秒；MML 原稿 `mml/chime-tourist.mml` | 在看的列車到「觀光」站：800 m 內有景點（決策 174、219） |
| `chime-local-motif.wav`、`chime-metro-motif.wav`、`chime-tourist-motif.wav` | 各自的動機：前 2、3、3 個音，0.8 秒 | 600 倍速以上，在看的列車到站（決策 219） |
| `rail-joint.wav` | 「喀噠、喀噠」的鐵軌接縫聲 | 建好一段軌道 |
| `whoosh.wav` | 一秒的「咻」聲 | 換工具、開始或離開遊戲 |
| `build-done.wav` | 輕輕的「咚」加上往上的兩個撥弦音（G、高八度的 C） | 放好建物、加好月台或車站（決策 117） |
| `coins.wav` | 兩個相隔五度的高音鈴 | 每小時結算收到車資、每日收到租金（決策 117） |
| `goal-met.wav` | 都會轉運鈴的樂句 C5 E5 G5 用撥弦快速往上，落在 C6 的鐘聲，1.2 秒；樂譜 `scores/goal-met.score.json`（照鈴聲的規則，不做動機檔） | 挑戰目標或城市委託達成（決策 256），跟「音效」的音量 |
| `line-acquired.wav` | 地方小站到站鈴的 C6、G6 兩聲鐘，撥弦 D6、G5 往下落在 C6 的鐘聲，最後一聲低的「蓋章」（接縫聲疊 C4 撥弦），1.5 秒；樂譜 `scores/line-acquired.score.json`（照鈴聲的規則，不做動機檔） | 收購一條真實支線（決策 315），跟「音效」的音量 |
| `ticket-issued.wav` | 0.7 秒的出票聲：售票機印票（帶通雜訊依步進馬達每秒 180 步起伏，下面一聲很小的 360 Hz）、切刀「喀」、票掉進出票口的輕響；全部合成，沒有錄音 | 一日週遊券開賣或改價（決策 373），跟「音效」的音量 |
| `horn-electric.wav` | 1.07 秒的台鐵電車、電力機車汽笛：G4、B4 兩音同時（大三度），帶鋸齒波泛音的「叭——」，起音時音高從低 3% 升上來；全部合成，沒有錄音 | 3D 跟車時按跟車條的鳴笛，或台鐵的車 1 倍速時進站前 1 km、進隧道時自己鳴（決策 403 續二），跟「音效」的音量 |
| `horn-diesel.wav` | 1.57 秒的柴油機車三音汽笛：A3、C4、E4（A 小調和弦），比電車低、長、厚 | 同上，柴油機車拉的莒光、藍皮解憂號 |
| `horn-steam.wav` | 1.86 秒的蒸汽汽笛：D5 與高八度，先「噗」一口氣（300 Hz–2 kHz 的帶通雜訊）再唱出來 | 同上，蒸汽火車、仲夏寶島號 |
| `horn-highSpeed.wav` | 0.74 秒的高鐵電子笛：E5、G5，方波、圓滑短促 | 只有按鈕（高鐵不自己鳴） |
| `horn-metro.wav` | 0.37 秒的捷運電子笛：A5、C#6，參考庫 OpenWorld 汽車喇叭的包絡（25 ms 起、0.18 秒、0.32 秒收） | 只有按鈕（捷運不自己鳴） |
| `refused.wav` | 兩個往下的低音撥弦（E、C#，小三度） | 遊戲拒絕玩家的操作（失敗訊息，決策 184） |
| `warning.wav` | 兩個相隔一個全音的短鈴（A、B） | 新聞紀錄多了一則警訊：負債、期限、颱風、缺建材（決策 184） |
| `run-electric.caf` | 8 秒、可無縫循環的一般電車行駛聲：照兩段台灣列車錄音的頻譜塑形的雜訊，每 1.6 秒一處鐵軌接縫（近的轉向架兩軸「喀噠」、遠的轉向架小聲一次）；IMA4 | 跟隨的列車（不是高速列車）在 60 倍速以下、5 km/h 以上行駛時循環播放，越快越大聲、音調越高（決策 343），跟「音效」的音量 |
| `run-highspeed.caf` | 8 秒、可無縫循環的高速列車行駛聲：照 KTX 車廂連接處錄音的頻譜塑形的雜訊，沒有接縫聲；IMA4 | 同上，跟隨的是高速列車時（決策 343） |
| `rain-steady.caf` | 8 秒、可無縫循環的雨聲：照台北、淡水三段雨聲錄音的頻譜塑形的雜訊，音量照錄音每半秒的起伏（標準差 1.8 dB）緩緩漂動；IMA4 | 地圖下雨時循環播放（雷雨時大聲，下雨小 6 dB），跟「音效」的音量（決策 346） |
| `rain-typhoon.caf` | 12 秒、可無縫循環的颱風風雨聲：照淡水颱風錄音的頻譜塑形的雜訊，一陣一陣的風（每半秒的起伏標準差 3 dB、約一秒一陣）；IMA4 | 颱風吹過地圖時循環播放（決策 346） |
| `thunder.caf` | 10 秒的一聲雷：照三段雷聲錄音第一秒頻譜的「霹」，下面是照隆隆聲頻譜、每 1.5 到 2 秒滾一次、照量到的速度（每秒 −1.2 dB）消失的雷鳴，最後 1.5 秒淡出；IMA4（單次，不循環） | 雷雨與颱風時，地圖每道閃電之後 1 到 4 秒（越遠越小聲、越低沉，決策 346） |
| `garbage-truck.caf` | 9.5 秒、可無縫循環的垃圾車音樂：貝多芬〈給愛麗絲〉（公有領域）開頭兩句，音符照參考庫台灣 3D 城市 `garbage-truck.js`，一個八分音符 0.19 秒；每個音是方波（奇次泛音到 6 kHz），12 ms 起音、到音尾降到一半、25 ms 放開，整段稍微推進軟削波，再濾成車頂喇叭的頻帶（400 Hz–3.2 kHz，1.6 kHz 附近稍亮）；全部合成，沒有錄音；IMA4 | 3D 拉近時，傍晚 18:00–21:00 街上有垃圾車在附近就循環播放，越遠越小聲、左右跟著車的位置（決策 437），跟「音效」的音量 |

## 來源與授權

全部由這支腳本用正弦波與固定種子的雜訊產生，沒有取樣、現成音樂或第三方音源（行駛聲只用了錄音量到的頻譜數字，見下），是本專案自己的素材。都會轉運鈴的音高與節奏照搬作者的參考庫（`a91453/railway-reference-private` 的 `Ci/reference_snapshot/lib/audio/airport-pa/chime.mjs`，也是合成的、沒有音檔）。`mml-core/core.js` 是作者的 `a91453/mml-tools`（MIT），授權在 `mml-core/LICENSE`。

行駛聲（決策 343）照真實錄音的頻譜合成，錄音本身不提交、不打包。`measure_running_spectrum.py` 量錄音一段的三分之一八度頻帶中位數（每 2 秒一窗），結果寫在 `make_game_audio.py` 的 `RUNNING_SPECTRA`；重產不需要錄音。量的錄音（都在 radio aporee ::: maps，Internet Archive 上）：

| 錄音 | 錄音者 | 授權 | 量的段落 | 用在 |
| --- | --- | --- | --- | --- |
| [KTX high speed train to Busan](https://archive.org/details/aporee_65051_75140)（2024-08-10，車廂連接處，`KTX.mp3`） | abyssence | 公眾領域（Public Domain Mark 1.0） | 0–826 秒（全段） | `run-highspeed.caf` |
| [Guishan, Taoyuan - On the train](https://archive.org/details/aporee_17319_20158)（2012-02-01，`SoundMap2012020110.ogg`） | 吳燦政（Wu, Tsan-Cheng） | 公眾領域（Public Domain Mark 1.0） | 0–166 秒（全段） | `run-electric.caf`，兩段的平均 |
| [Banqiao District, New Taipei City - In the train compartment](https://archive.org/details/aporee_34085_39187)（2016-10-19，`soundmap201610191.ogg`） | 吳燦政（Wu, Tsan-Cheng） | CC BY 3.0 | 0–140 秒（行駛中；之後停站） | 同上 |

```sh
python3 -I tools/audio/measure_running_spectrum.py KTX.mp3 0 826
python3 -I tools/audio/measure_running_spectrum.py SoundMap2012020110.ogg 0 166 soundmap201610191.ogg 0 140
```

板橋那段是 CC BY 3.0：遊戲的資料來源頁（`DataSourceCredits` 的「聲音」）寫明錄音者、標題、授權與連結，並說明遊戲的聲音是照它重新合成的。研究文件 §7.2 列的 OtoLogic 與 Freesound 在這個環境打不開（403），維基共享資源的原檔一直回 429，所以改用這三段。

雨聲、颱風與雷聲（決策 346）也一樣：只取錄音的數字，錄音本身不提交、不打包。雨與颱風用同一支 `measure_running_spectrum.py` 量（結果在 `WEATHER_SPECTRA`）；雷聲用 `measure_thunder.py`：給每聲雷開始的秒數與之前一段沒有雷的雨，量雷聲第一秒與 2 到 10 秒後的隆隆聲各自高出雨聲多少（三分之一八度，每 0.25 秒一窗），以及每秒最大的那 0.25 秒照直線消失的速度（結果在 `THUNDER`）。雨聲每半秒起伏的大小與快慢（`WEATHER_SWING`）是同樣的錄音每半秒的音量算的標準差與自相關。量的錄音都是吳燦政（Wu, Tsan-Cheng）錄的、CC BY 3.0，都在 radio aporee ::: maps：

| 錄音 | 量的段落 | 用在 |
| --- | --- | --- |
| [富陽自然生態公園, 大安區,Taipei City - Rain and Thunder](https://archive.org/details/aporee_28503_32842)（2015-07-04，`SoundMap201507044.mp3`） | 0–219 秒（全段） | `rain-steady.caf`，三段的平均 |
| [Taipei Railway Workshop, Taiwan - Thunderstorm](https://archive.org/details/aporee_24967_28963)（2014-09-24，臺北機廠，`SoundMap201409241.mp3`） | 0–80 秒（之後打雷） | 同上 |
| [大仁街, Tamsui District - Rain and Thunder](https://archive.org/details/aporee_27593_31908)（2015-04-21，`SoundMap201504211.mp3`） | 雨 0–74 秒；雷 75.4 秒起（雨 0–74 秒） | 同上；`thunder.caf` |
| [No.20, Daren St., Tamsui Dist., New Taipei City - typhoon](https://archive.org/details/aporee_29264_34673)（2015-09-28，`soundmap201509281.mp3`） | 0–268 秒（全段） | `rain-typhoon.caf` |
| [敦安公園, 大安區, Taipei City - Thunder sound](https://archive.org/details/aporee_28950_33339)（2015-07-23，`SoundMap2015072319.mp3`） | 雷 31.9 秒起（雨 18–23 秒） | `thunder.caf`，三聲的平均 |
| [松山文創園區,Taipei City - Thunder](https://archive.org/details/aporee_33407_38419)（2016-09-09，`soundmap201609091.mp3`） | 雷 46.2 秒起（雨 10–38 秒） | 同上 |

```sh
python3 -I tools/audio/measure_running_spectrum.py SoundMap201507044.mp3 0 219 SoundMap201409241.mp3 0 80 SoundMap201504211.mp3 0 74
python3 -I tools/audio/measure_running_spectrum.py soundmap201509281.mp3 0 268
python3 -I tools/audio/measure_thunder.py SoundMap201504211.mp3 75.4 0 74 SoundMap2015072319.mp3 31.9 18 23 soundmap201609091.mp3 46.2 10 38
```

資料來源頁的「聲音」多了一筆（`DataSourceCredits` 的 `weatherSound`），寫六段的標題、錄音者、授權與連結。

音樂兩輪和弦正好 1,843,200 個取樣，是 IMA4 封包（64 個取樣）的整數倍，所以 CAF 結尾沒有補零；腳本會檢查這一點。改節奏或長度時，要保持這個條件，否則循環會有短暫的空隙。行駛聲每段 384,000 個取樣（8 秒），雨聲 8 秒、颱風 12 秒、雷聲 10 秒，也都是整數倍；而且從零點附近開始：IMA4 的封包從靜音解起，離零點開始的循環每一圈都會「喀」一聲。
