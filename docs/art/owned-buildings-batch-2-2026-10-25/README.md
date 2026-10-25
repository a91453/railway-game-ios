# 自有建築第 2 批：學校、醫院、夜市（決策 361 續）

`overview.png`：上排是三種新建物的 2D 地圖圖示（`MapGlyphSchool`、`MapGlyphHospital`、`MapGlyphNightMarket`，24 pt 模板，16 pt 與灰階一起看）與建造選單的卡片（`BuildingSchool`、`BuildingHospital`、`BuildingNightMarket`，120 pt，art-style 的色票與 3 pt 線）；下排是每種的兩個 3D 外觀近看（`Map3DScene.Builder.placedKitLayouts`）：

- 學校：國小（`primarySchool`、體育館、迷你足球場與看台、遊具）、幼兒園（`kindergarten`、遊戲屋、遊具、籃球場、涼亭）。
- 醫院：社區醫院（`clinic`＋`dayCareCenter`、戶外桌）、醫療照護中心（同兩棟換位置與涼亭）。市政套件沒有醫院大樓，兩個外觀都是診所與照護中心組成的；一棟真的醫院大樓留在決策 361 的下一步。
- 夜市：夜市街（拉麵攤、炸物、水果、遊戲攤、餐車、立牌、燈箱）、市場小吃廣場（棚子、攤位、推車、陽傘桌、燈串）。

- 圖示與卡片是手寫的 SVG（art-style skill 的流程，`preview.cjs` 看過 16 pt、模糊與灰階）；3D 由佈局的網格匯出成 `.m3dmodel`，用 `tools/station-kit/renderer.js`（Chromium WebGL）畫等角圖，每張各自縮放，所以大小不能互比（學校 48 m，醫院與夜市 32 m）。
- 匯出與排版的腳本放在 session 的 scratchpad，沒有進 repo（和 `owned-building-kits-2026-10-24` 一樣）。
- 沒選的圖示：醫院用紅十字（紅色不在色票裡，而且紅十字是受保護的標誌）、夜市用燈籠（16 pt 看起來像廟的圖示）。
- Chromium WebGL 不等於 iPhone 的 Metal；實機的樣子要在 TestFlight 看。
