# 台灣公路與鐵路隧道洞口（決策 611／359，revision-3）

本輪只改組景的山體、翼牆接坡、道路與軌道接地；`Map3DRoadTunnelPortals.swift` 的 14 款洞口幾何、內襯漸暗及深色封底維持 revision-2。私有素材庫的 revision-3 沿用 revision-2 的 14 個 GLB 和 98 張七向 PNG，逐檔位元組與 SHA-256 不變。revision-2 只保留 PNG 與 README，完整模型與離線檢視頁移到 revision-3。沒有接進地圖。

## 接地做法

組景地面頂面是 `z = 0.00 m`。放置洞口時，依各模型原有的埋地深度把洞口抬高 0.8 m（公路）或 1.2 m（鐵路），使翼牆底落在地面。洞外道路／軌道在 24 m 的進路內，由地面高度逐漸接到洞口標高。翼牆背後的坡面從山坡蓋到翼牆頂，再沿外側降到地面；山體前緣、兩側和後緣均接地。這些只是組景位置與地形，不更動可供遊戲載入的原生洞口網格。

`tools/road_tunnel_portals.py` 的 `validate_ground_contact()` 量測實際 Blender 頂點：山體、翼牆、路面／軌面各自的最低點與地面頂面，差值必須在 0.05 m 內。`tools/test_road_tunnel_scene.py` 以無渲染模式執行此檢查。修改前測得山腳 0.00 m、地面 −0.41 m，會使測試失敗；修正後四者均為 0.00 m。組景另有正面和獨立側視驗收圖。

## 重建

本輪組景 producer commit：`06726b4d85785535d4b24aa158c435fd28a293c3`。Blender 4.x：

```sh
python3 tools/test_road_tunnel_scene.py
blender -b --python tools/road_tunnel_portals.py -- --output /path/to/revision-3 --composition-only
```

先將私庫 revision-2 的既有模型與七向預覽逐檔複製到 revision-3；原檔來源為私庫 commit `c0ce6a7aa1b4069175fd2ec5b702786480ba474d`，不可重製後取代。上列 Blender 指令只會產生三張組景與 `viewer.html`，不改模型或七向圖。完整模型的原始配方仍見本分支舊 producer commit `bfcf8f16f0f835a230851fbd4bf4559de1b89790`。

[總覽圖](overview.png)和私庫 revision-3 的 `mountain-road-rail-front.png`、`mountain-road-rail-side.png` 供規劃審圖；側視圖隔離組景最左側的同款公路洞口，以免其他入口互相遮擋。離線檢視頁使用本地 PNG 與 GLB 連結，不連外。

## 來源、授權與限制

洞口和組景均是本專案原創，依本庫 `LICENSE.md`（著作權所有）及私有素材庫規範管理。尺寸沿用 `Sources/GamePresentation/Map3DTunnels.swift`（決策 359）與決策 611 指示。照片只作參考，沒有下載或提交：[Wikimedia Commons 台灣公路隧道](https://commons.wikimedia.org/wiki/Category:Road_tunnels_in_Taiwan)、[交通部高速公路局](https://www.freeway.gov.tw/)。沒有使用 Quaternius 或 Polyfork 素材。

組景是低多邊形示意地形；實際 DEM 裁切、iOS 畫面與地圖接線仍待後續 session 驗證。
