# 自有建築的 EstateKit／CoastalKit 外觀（決策 398）

`overview.png`：玩家自己蓋的飯店（三種外觀）、百貨（兩種）、遊樂園、漁人碼頭、遊艇港近看的模型，遠看的方塊，以及同一棟飯店依建物編號換的四種屋頂色。

- 由 `Map3DScene.Builder.placedKitLayouts` 的網格匯出成 `.m3dmodel`，用 `tools/station-kit/renderer.js`（Chromium WebGL）畫等角圖；每張圖各自縮放到格子大小，所以彼此的大小不能比（遊樂園是 112 m，飯店 32 m）。
- 匯出與排版的腳本放在 session 的 scratchpad，沒有進 repo（art-style skill 的做法）。
- Chromium WebGL 不等於 iPhone 的 Metal；實機的樣子與幀數要在 TestFlight 看。
