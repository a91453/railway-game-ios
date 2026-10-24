# Game Center 的成就圖（決策 396）

38 張 1024×1024 的 PNG（Apple 要的 512×512 pt @2x），一個成就一張，檔名就是 Game Center 的成就 ID（`achievement.<遊戲內 ID>.png`）。作者在 App Store Connect 建成就時上傳（`docs/GAME_CENTER_SETUP.md` 第 4 步）；App 不讀這些檔。

![總覽](overview.png)

## 樣子

- 照 `.claude/skills/art-style/SKILL.md`：扁平、實心色塊、藏青外框，顏色只用 App 圖示的四色（藏青 `#262C57`、綠松 `#12A08F`、暖黃 `#FFC86B`、淺底 `#ECEEF6`）。
- Game Center 把成就圖裁成圓形顯示，所以圖都畫在中間的圓裡：綠松色的底和圈、淺色的圓面，中間一個藏青的圖示。
- 同一系列用同一個圖示，等級寫在下面的暖黃標籤上（1K、10K、10 km、25……）。數字中英文通用，所以兩種語言用同一張。
- 載客的系列照 art-style「等級用同一種人形的人數表示」：1K 一個人、10K 兩個人、100K 三個人，1M 是三個人頭上再加三顆星。
- 用到 App 裡現有的圖示：`MapGlyphPerson`、`MapGlyphCrowd`、`MapGlyphFull`、`MapGlyphStar`、`MapGlyphTyphoon`、`MapGlyphOffice`、`MapGlyphHouse`、`MapGlyphShop`、`MapGlyphDepartmentStore`、`MapGlyphAmusementPark`、`MapGlyphHotel`、`MapGlyphTrain`。其他（車票、軌道、站點、箭頭、停靠點、日出、月亮、環狀軌道、轉乘站、流線車頭、貨箱、地圖格、金牌、天燈、旗子、相機、長條圖、長編組、三種車頭、一疊鈔票）是這次新畫的，同樣 24 格、實心、圓角。
- 沒有用參考庫的圖，也沒有用 SF Symbols（Apple 的授權不准把 SF Symbols 用在 App 以外的圖上）。

## 美術審查後改了什麼（2026-10-24）

審查是 session_01T1XU 做的，總覽在 `claude/art-review-1158:docs/game-center/review/overview.png`。

- 輸出改成 1024×1024。
- 拿掉最外圈 30 px 的藏青，圖示放大約 13%。
- 環狀線：改成首尾相接、帶枕木的環狀軌道（原本像 ♂）。
- 轉乘：一座站，三條方向不同的路線從站穿過（原本中心有殘片，像分子模型）。
- 軌道：1000 km 的標籤只寫 1000。所有標籤都收在圓面裡，不碰綠圈。
- 挑戰金牌：暖黃的牌面。
- 平溪線：天燈，裡面透著暖黃的光，下面有火（原本是號誌燈）。
- 車種齊全：三種不同的車頭並排（原本和車隊成形同圖）。
- 車隊投資：一疊鈔票，中間一個 $（原本像相機）。
- 企業集團：百貨、飯店、遊樂園三個小圖。
- 百萬運量：三個人頭上加三顆星，和 100K 分得開。
- 子彈列車：流線車頭加速度線（原本只有閃電）。
- 夜行者：星星離開月牙。

每張都在 64 和 40 px 的圓形裁切、模糊、灰階下看過。

## 選了哪一種

- **A（用了）**：淺色圓面、藏青圖示、綠松色的圈（`overview.png`，審查後的版本）。
- **B（沒用）**：綠松色圓面、淺色圖示、暖黃的圈（`option-b-teal.png`，審查前的畫法）。

五方：
- 玩家：A 在 Game Center 的白底與深色模式都分得清，圖示是深色的，小尺寸也看得出。B 整片綠松，38 個並排時比較吵。
- 鐵道迷：圖示用軌道、車票、天燈、旗子，看得出是鐵道遊戲。
- 開發：用腳本產生，換成就時重跑就好（腳本留在 scratchpad，照 art-style 不放進 repo）。
- 美術：A 和 App 圖示的淺底藏青一致，B 的大片綠松在 App 裡只當強調色用。
- 音樂：無。
