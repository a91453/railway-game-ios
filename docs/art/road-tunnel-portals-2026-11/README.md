# 台灣公路隧道洞口（決策 611，素材先行）

`Map3DRoadTunnelPortals.make(_:width:)` 產生 4 種洞口、各單向與雙向寬度的原生 `Map3DMesh`。不接入場景或道路資料；ROADTUNNEL session 依 `Part.connector` 放置。

| 款式 | 開口 | 單向淨寬 | 雙向淨寬 | 淨高 |
| --- | --- | ---: | ---: | ---: |
| dividedExpressway | 雙孔、中央實體分隔牆 | 每孔 7.5 m | 每孔 10.5 m | 5.2 m |
| mountainArch | 單孔折面拱、護坡翼牆 | 6.2 m | 9.2 m | 5.2 m |
| nameplate | 大型單孔、無字名牌面 | 8.0 m | 11.0 m | 5.2 m |
| narrowLane | 單線窄孔 | 5.0 m | 7.0 m | 4.7 m |

共同尺寸：牆厚 1.2 m、洞頂上方加高 1.3 m、基礎埋入 0.8 m、翼牆長 8 m 且外張 2 m；翼牆端點高於路面 0.6 m。局部座標以公尺計，`+x` 指向洞內、`+y` 向上、`+z` 指道路右側，路面高度 `y=0`，接點在正面中心。雙孔開口中心對稱，中央牆厚 1.4 m。山坡與路面由地圖接線時提供；組景圖只作美術審查。

## 重建

本分支提交 `072a6aa7b071c45c14bc81ab9fd399077555571f` 提供 Swift 配方和 Blender 預覽腳本。從該 commit checkout 後執行：

```sh
blender -b --python tools/road_tunnel_portals.py -- --output /path/to/railway-assets-private/game-art-previews/docs/art/road-tunnel-portals-2026-11/revision-1
```

預覽及 GLB 在私有素材庫的 `game-art-previews/docs/art/road-tunnel-portals-2026-11/revision-1/`。GLB 為審查模型；遊戲原生版本由 Swift 建構。每個寬度有七張透明 PNG，另有一張山坡道路組景圖。七個方位相機從路外看向洞口：−75、−50、−25、0、25、50、75 度。

## 來源與授權

造型及幾何為本專案原創，依本庫 `LICENSE.md`（著作權所有）及私有素材庫授權管理；未引入第三方模型或貼圖。尺寸沿用本庫 `Sources/GamePresentation/Map3DTunnels.swift` 的決策 359 鐵路洞口參數，公路淨高依本工作指示採 4.6 m 以上。照片只作視覺參考，未下載或收入素材庫：

- [維基共享資源：台灣公路隧道類別](https://commons.wikimedia.org/wiki/Category:Road_tunnels_in_Taiwan)
- [交通部高速公路局](https://www.freeway.gov.tw/)

已知限制：尚未在 iOS 3D 地圖與真實地形上驗收；ROADTUNNEL 應依道路淨寬選款、將洞口及翼牆接至實際山坡並處理路面延伸。
