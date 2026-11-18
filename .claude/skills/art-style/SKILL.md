---
name: art-style
description: 這個遊戲的畫風與畫圖流程。畫或改任何圖時先讀：地圖上的圖示、介面的圖、站長或其他角色、表情、App 裡的插圖、SVG、Asset Catalog 的 imageset。Use before drawing or changing any icon, glyph, character, mascot, expression or illustration for the app (SVG in RailwayGameApp/Resources/Assets.xcassets).
---

# 畫圖：公開的程式規則

畫風、色票、角色、畫圖流程、素材組合與授權的規矩是獨門做法，2026-11-18 搬到私有素材庫 `a91453/railway-assets-private-2` 的 `docs/studio/art-style.md`。**畫或改任何圖之前先讀那一份**；這裡只留 Xcode 與程式要的格式。

## 1. 兩種圖的格式

| | 單色模板圖示 | 多色插圖 |
| --- | --- | --- |
| 例子 | 地圖上的圖示 `MapGlyph*`（決策 121）、站長的燈 `StationMasterLantern` | 站長 `StationMasterTaiwan*`（決策 122） |
| 尺寸 | `viewBox="0 0 24 24"`，`width`／`height` 也是 24 | `viewBox="0 0 120 120"`，含自己的底色 |
| 顏色 | 全部 `fill="#000000"`，在畫的地方上色 | 寫死在 SVG 裡，淺色、深色共用一張 |
| `Contents.json` 的 `properties` | `"preserves-vector-representation" : true`、`"template-rendering-intent" : "template"` | 只有 `"preserves-vector-representation" : true` |
| Swift | `MapGlyph.x.image`（Canvas 用 `shading`，SwiftUI 用 `foregroundStyle`） | `Image(名稱)`，經 `RegionStyle` 取名 |

新的 imageset 放進 `Assets.xcassets` 不用重新產生 xcodeproj（Asset Catalog 在專案裡是一整個資料夾）；**新的 Swift 檔要**（CLAUDE.md 的 XcodeGen 步驟）。

## 2. Xcode 吃得下的 SVG

Xcode 的 Asset Catalog 只支援 SVG 的一部分。這些已經在 CI 的 Release Archive 證明可用：

- 元素只用 `svg`、`path`、`circle`、`ellipse`、`rect`；
- 屬性：`fill`、`stroke`、`stroke-width`、`stroke-linecap`、`stroke-linejoin`、`fill-rule`、`rx`；
- 路徑指令：`M L H V Q C A Z`（大寫、絕對座標）。

不要用：`T`、`S` 這類簡寫（自己算出控制點改用 `Q`、`C`）、`transform`、`<g>` 的屬性繼承、`opacity`（改用算好的實心色）、漸層、濾鏡、`mask`、`clipPath`、`<text>`、`<use>`、CSS。

圖用 Python 腳本產生，腳本放在 scratchpad，不放進 repo（決策 121、122 都這樣做）；commit 的是 SVG 與 `Contents.json`。

## 3. 預覽腳本

```sh
# <scratchpad> 是系統提示裡的 scratchpad 目錄
NODE_PATH="$(npm root -g)" node .claude/skills/art-style/preview.cjs \
  --out <scratchpad>/sheet.png --head a.svg b.svg                  # 角色
NODE_PATH="$(npm root -g)" node .claude/skills/art-style/preview.cjs \
  --out <scratchpad>/glyphs.png --sizes 48,24,16 --template x.svg  # 單色圖示
```

每一列最後兩格是模糊與灰階（`--no-checks` 拿掉）。它用環境裡預裝的 Chromium（Playwright），不下載任何東西；輸出放 scratchpad，自己先看過再給作者。

## 4. 驗證

Linux 不能建置 App：Swift 檔只能 `swiftc -parse`（語法），`Contents.json` 用 JSON 解析檢查。Asset Catalog 的 SVG、Canvas 與按鈕上的樣子要看 CI（`ios-build.yml`、`release-archive.yml`），實機由作者在 TestFlight 確認。照 CLAUDE.md 寫 VERIFIED／UNVERIFIED。
