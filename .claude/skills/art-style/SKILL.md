---
name: art-style
description: 這個遊戲的畫風與畫圖流程。畫或改任何圖時先讀：地圖上的圖示、介面的圖、站長或其他角色、表情、App 裡的插圖、SVG、Asset Catalog 的 imageset。Use before drawing or changing any icon, glyph, character, mascot, expression or illustration for the app (SVG in RailwayGameApp/Resources/Assets.xcassets).
---

# 畫風與畫圖流程

作者在 2026-10-09 定下的畫風（ARCHITECTURE 決策 84、121、122，`docs/UI_THEME.md`）。方向是：玩法照《A 列車》的深度，外觀與操作照 SimCity BuildIt，畫風照 App 圖示。照這份規則畫，不用每次從頭試。

## 1. 畫風

- **跟 App 圖示同一個樣子**（`RailwayGameApp/Resources/Assets.xcassets/AppIcon.appiconset/`）：扁平、實心色塊、粗的藏青外框、圓角；不用漸層、陰影、濾鏡、寫實的質感。
- **顏色只從現有的色票取**，不在 View 裡寫新的色碼：
  - 介面：`Theme`（`RailwayGameApp/Views/Theme.swift`）；
  - 地圖：`Palette`（`Palette.swift`）；
  - 一個國家的樣子：`RegionStyle`（`RegionStyle.swift`，決策 106：地區的樣子只透過它）。
  - 圖示的四個主色：藏青 `#262C57`、綠松 `#12A08F`（深色 `#45D3C0`）、暖黃 `#FFC86B`、淺底 `#ECEEF6`。色票與對比在 `docs/UI_THEME.md`。
- **對比**：圖形對它的底至少 3:1，文字 4.5:1（WCAG 2）。新的顏色組合要算過，寫進 `docs/UI_THEME.md`。

## 2. 兩種圖

| | 單色模板圖示 | 多色插圖 |
| --- | --- | --- |
| 例子 | 地圖上的圖示 `MapGlyph*`（決策 121）、站長的燈 `StationMasterLantern` | 站長 `StationMasterTaiwan*`（決策 122） |
| 尺寸 | `viewBox="0 0 24 24"`，`width`／`height` 也是 24 | `viewBox="0 0 120 120"`，含自己的底色 |
| 顏色 | 全部 `fill="#000000"`，在畫的地方上色 | 寫死在 SVG 裡，淺色、深色共用一張 |
| `Contents.json` 的 `properties` | `"preserves-vector-representation" : true`、`"template-rendering-intent" : "template"` | 只有 `"preserves-vector-representation" : true` |
| Swift | `MapGlyph.x.image`（Canvas 用 `shading`，SwiftUI 用 `foregroundStyle`） | `Image(名稱)`，經 `RegionStyle` 取名 |

- 單色圖示只有實心形狀，挖空用 `fill-rule="evenodd"`（挖空的洞要整個在外形裡面）；筆畫要粗到 10–16 點還看得出來。
- 地圖物件用自己的圖示；工具列、面板、表單的按鈕照舊用 SF Symbols（決策 121 第 4 點）。
- 新的 imageset 放進 `Assets.xcassets` 不用重新產生 xcodeproj（Asset Catalog 在專案裡是一整個資料夾）；**新的 Swift 檔要**（CLAUDE.md 的 XcodeGen 步驟）。

## 3. Xcode 吃得下的 SVG

Xcode 的 Asset Catalog 只支援 SVG 的一部分。這些已經在 CI 的 Release Archive 證明可用：

- 元素只用 `svg`、`path`、`circle`、`ellipse`、`rect`；
- 屬性：`fill`、`stroke`、`stroke-width`、`stroke-linecap`、`stroke-linejoin`、`fill-rule`、`rx`；
- 路徑指令：`M L H V Q A Z`（大寫、絕對座標）。

不要用：`T`、`S` 這類簡寫（自己算出控制點改用 `Q`、`C`）、`transform`、`<g>` 的屬性繼承、`opacity`（改用算好的實心色）、漸層、濾鏡、`mask`、`clipPath`、`<text>`、`<use>`、CSS。

圖用 Python 腳本產生，腳本放在 scratchpad，不放進 repo（決策 121、122 都這樣做）；commit 的是 SVG 與 `Contents.json`。

## 4. 角色：站長（決策 122）

台灣的站長是提著號誌燈的黃山雀（`RegionStyle.stationMasterArt` = `StationMasterTaiwan`）。作者看過正面、3/4、朝右之後選定的樣子，**不要改**：

- 側面、朝左；黑色羽冠就是站長帽，冠上有黃色站徽；黃色身體、灰藍翅膀有白點、喉下一道黑紋；台鐵藍（`#1D4F91`）的領巾配黃色站徽；左手提著黃色號誌燈，燈外一圈淺黃光暈；腳下一段綠松色軌道。
- **表情只換眼睛**（加上表情的小道具），身體、朝向、羽冠、燈都不動：
  - 平常：實心的深藍豆豆眼，帶一點白色反光；
  - 開心：一條 ∩；
  - 擔心：用力閉起的「＜」（尖角朝嘴喙），頭後一滴藍色汗滴，燈變暗、沒有光暈。
- **不要**：白眼球配小黑點（看起來在瞪人）、斜粗眉（像生氣）、腮紅、正面的黃色圓臉配兩顆點點眼睛（作者說太像別的表情符號角色）、眼後太長的黑紋（像眼罩或皺眉）。
- 60 點以下只放大頭部（`StationMasterAvatar`：放大 1.45 倍，錨點 (0.44, 0.3)）。
- 新的表情、新的地區角色，也照這幾條：先維持作者認可的造型，只動被要求的部分。

## 5. 流程

1. **先讀**：`docs/UI_THEME.md`、相關的決策、現有的同類圖（一致比新奇重要）。
2. **給 2–4 種差異明顯的方案讓作者挑**，不是同一個想法的小變化；每種寫一句它的感覺與取捨，說出你推薦哪個、為什麼。
3. **作者說哪裡不好，就只改那裡。** 不要順手改朝向、角度、比例或整個造型：這次站長一路從側面改到正面、3/4，作者說「感覺變了、沒那麼好看了」，最後回到最初那張只換眼睛。
4. **每一版都檢查**：淺色、深色兩種底，從大到小（插圖 120／64／44／28 點，圖示 48／24／16 點）。用這個 skill 的預覽腳本，輸出到 scratchpad：

   ```sh
   # <scratchpad> 是系統提示裡的 scratchpad 目錄
   NODE_PATH="$(npm root -g)" node .claude/skills/art-style/preview.cjs \
     --out <scratchpad>/sheet.png --head a.svg b.svg                  # 角色
   NODE_PATH="$(npm root -g)" node .claude/skills/art-style/preview.cjs \
     --out <scratchpad>/glyphs.png --sizes 48,24,16 --template x.svg  # 單色圖示
   ```

   它用環境裡預裝的 Chromium（Playwright），不下載任何東西。自己先看過（Read 那張 PNG），再用 SendUserFile 傳給作者。
5. **放進 App 之後**，比對 commit 的 SVG 和作者看過的預覽是同一張。
6. **寫下來**：新的決策（或補在原本的決策）、`docs/UI_THEME.md` 的顏色、`docs/RAILWAY_REFERENCE_MAPPING.md` 的參考對照（參考庫有沒有可用的圖、外部參考與授權）。

## 6. 驗證

Linux 不能建置 App：Swift 檔只能 `swiftc -parse`（語法），`Contents.json` 用 JSON 解析檢查。Asset Catalog 的 SVG、Canvas 與按鈕上的樣子要看 CI（`ios-build.yml`、`release-archive.yml`），實機由作者在 TestFlight 確認。照 CLAUDE.md 寫 VERIFIED／UNVERIFIED。

## 7. 素材與授權

- 參考庫（`a91453/railway-reference-private`）的圖：`Ci/` 的小圖示有 icons8 的（要標示出處），`Railway/taipei_gta_reference/` 的標題圖與人物是寫實風、另一個品牌，都和這個畫風不合；取用途、重畫，不搬檔。
- 商業遊戲（SimCity BuildIt、TheoTown 等）只看做法，不取素材。
- 外部的畫圖 skill 也只取做法：`neonwatty/logo-designer-skill`（MIT）的「幾種方案讓人挑、深淺色與小尺寸檢查」已經寫在上面的流程裡；`supermemoryai/skills` 的 `svg-animations` 沒有授權，只讀想法。
