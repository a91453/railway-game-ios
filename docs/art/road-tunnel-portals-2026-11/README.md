# 台灣公路與鐵路隧道洞口（決策 611／359，revision-2）

`Map3DRoadTunnelPortals` 是供接線 session 使用的原生 `Map3DMesh` 配方，目前沒有接進地圖。公路有五款各單向／雙向，鐵路有單線／雙線各普通洞口和明洞，共 14 個模型。所有洞口內有 8 m 分四段漸暗的牆、頂與底，最深處以雙面不透光面封住。接線時應由 ROADTUNNEL 處理與實際隧道內路／軌的遮擋關係。

| 模型 | 開口與寬度 | 淨高 | 特徵 |
| --- | --- | ---: | --- |
| dividedExpressway | 雙孔，每孔 7.5／10.5 m | 5.2 m | 1.4 m 中央分隔牆 |
| mountainArch | 單孔 6.2／9.2 m | 5.2 m | 折面拱與翼牆 |
| nameplate | 單孔 8.0／11.0 m | 5.2 m | 空白名牌面 |
| narrowLane | 單孔 5.0／7.0 m | 4.7 m | 鄉道與產業道路 |
| daylightGallery | 單孔 7.5／10.5 m | 5.2 m | 12 m 箱型頂蓋、兩側擋土牆 |
| rail single／double | 單孔 6.4／12.6 m | 6.0 m | 決策 359 的折面頂 |
| rail daylight single／double | 單孔 6.4／12.6 m | 6.0 m | 12 m 明洞頂蓋與擋土牆 |

共同尺寸：牆厚 1.2 m、洞頂上方加高 1.3 m、基礎埋入 0.8 m、翼牆長 8 m 外張 2 m。鐵路洞頂、拱起點、淨寬採 `Map3DTunnels.swift` 的決策 359 尺寸；雙線為共用寬孔的素材研究版。局部 Swift 座標以公尺計，`+x` 入洞、`+y` 向上、`+z` 道路／軌道右側；`Part.connector` 是外側入口路面／軌面中心，標高 0。明洞從山壁外伸 12 m，其接點為 `(-12,0,0)`；其他款為 `(0,0,0)`。

## 重建與審查

本分支 producer commit `f232a2e30ceb6c66af96b654d334f2bde6b99730` 含 Swift 配方與 Blender 4.x 工具。從該 commit checkout 後執行：

```sh
blender -b --python tools/road_tunnel_portals.py -- --output /path/to/railway-assets-private/game-art-previews/docs/art/road-tunnel-portals-2026-11/revision-2
```

私庫同路徑 `revision-2/` 收 14 個 GLB、每模型七張透明 PNG 和一張公路／鐵路同山組景圖。第 1 向是正面（0°），第 2–7 向依序 −30°、+30°、−60°、+60°、−120°、+120°。舊 `revision-1/` 僅留 PNG 與 README；舊 GLB 在同一素材 PR 刪除。

## 來源、授權與限制

本專案原創幾何與配色，依本庫 `LICENSE.md`（著作權所有）及私庫規範管理，未使用第三方模型或貼圖。規格參考本庫 `Sources/GamePresentation/Map3DTunnels.swift`（決策 359）及使用者的決策 611 指示；照片僅看來源連結，沒有下載或提交：[Wikimedia Commons 台灣公路隧道](https://commons.wikimedia.org/wiki/Category:Road_tunnels_in_Taiwan)、[交通部高速公路局](https://www.freeway.gov.tw/)。沒有使用 Quaternius 或 Polyfork。

組景使用低多邊形示意山體與路軌，不代表真實 DEM 切面；遊戲地圖的實際接線、地形裁切、iOS Metal 表現仍待後續 session 驗證。
