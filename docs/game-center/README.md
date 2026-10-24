# Game Center 的成就圖（決策 396）

38 張 512×512 的 PNG，一個成就一張，檔名就是 Game Center 的成就 ID（`achievement.<遊戲內 ID>.png`）。作者在 App Store Connect 建成就時上傳（`docs/GAME_CENTER_SETUP.md` 第 4 步）；App 不讀這些檔。

![總覽](overview.png)

## 樣子

- 照 `.claude/skills/art-style/SKILL.md`：扁平、實心色塊、藏青外框，顏色只用 App 圖示的四色（藏青 `#262C57`、綠松 `#12A08F`、暖黃 `#FFC86B`、淺底 `#ECEEF6`）。
- Game Center 把成就圖裁成圓形顯示，所以圖都畫在中間的圓裡：藏青底、綠松色的圈、淺色的圓面，中間一個藏青的圖示。
- 同一系列用同一個圖示，等級寫在下面的暖黃標籤上（1K、10K、10 km、25……）。數字中英文通用，所以兩種語言用同一張。
- 載客的系列照 art-style「等級用同一種人形的人數表示」：1K 一個人、10K 兩個人、100K 與 1M 三個人。
- 用到 App 裡現有的圖示：`MapGlyphPerson`、`MapGlyphCrowd`、`MapGlyphFull`、`MapGlyphStar`、`MapGlyphTyphoon`、`MapGlyphOffice`、`MapGlyphHouse`、`MapGlyphShop`、`MapGlyphDepartmentStore`、`MapGlyphAmusementPark`、`MapGlyphTrain`、`StationMasterLantern`（平溪線的天燈）。其他 18 個（車票、軌道、站點、箭頭、停靠點、日出、月亮、環狀線、轉乘、閃電、貨箱、地圖格、獎牌、旗子、相機、長條圖、長編組、鈔票）是這次新畫的，同樣 24 格、實心、圓角。
- 沒有用參考庫的圖，也沒有用 SF Symbols（Apple 的授權不准把 SF Symbols 用在 App 以外的圖上）。

## 選了哪一種

- **A（用了）**：淺色圓面、藏青圖示、綠松色的圈（`overview.png`）。
- **B（沒用）**：綠松色圓面、淺色圖示、暖黃的圈（`option-b-teal.png`）。

五方：
- 玩家：A 在 Game Center 的白底與深色模式都分得清，圖示是深色的，小尺寸也看得出。B 整片綠松，38 個並排時比較吵。
- 鐵道迷：圖示用軌道、車票、天燈、旗子，看得出是鐵道遊戲。
- 開發：用腳本產生，換成就時重跑就好（腳本留在 scratchpad，照 art-style 不放進 repo）。
- 美術：A 和 App 圖示的淺底藏青一致，B 的大片綠松在 App 裡只當強調色用。
- 音樂：無。
