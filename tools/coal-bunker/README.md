# 儲煤台（決策 767）

3D 地圖老磚廠空地上的高架儲煤台：紅磚煤槽架在兩排石柱上，槽裡堆著煤，一端有輸送帶從地面斜上來。這是遊戲作者自己做的模型，來自作者舊版的「建築一般」#001。

```sh
# 從 repo 根目錄；Node 22；先在 tools/glb-to-m3dmodel 跑過 npm ci --ignore-scripts
node tools/coal-bunker/build.mjs [--output RailwayGameApp/Resources/Models/coal-bunker.m3dmodel]
```

`source/b001-b.glb` 已經是平塗版本。它來自作者本機工作室的試做 b001（B 版），經過三輪 Codex 審查，作法如下：

- 沿用作者原本的白模，拿掉貼圖與 UV，三角形位置不動。
- 為了照部位上色，切了一些面，並在輸送帶加上橫條：251 → 679 個三角形。
- 每個顏色一個材質，材質名稱就是色票值。

`build.mjs` 依材質名稱，把顏色換成 3D 地圖已有的顏色：

| 材質 | 部位 | 遊戲的顏色 |
|---|---|---|
| `#C9CCD5` | 煤槽的牆 | `Map3DPalette.brick` `#B8735A`（老磚廠廠房的磚） |
| `#CFCBC2` | 柱子 | `Map3DPalette.granite` `#D3CDC1` |
| `#8A9099` | 槽底、輸送帶 | 鋼灰 `#8A9099`，不變 |
| `#2B2F36` | 煤 | `#2B2F36`，不變 |
| `#2F6DB5` | 輸送帶兩端 | 木頭 `#8E6E52`（櫃台、纜車用的木色） |

換好色以後，交給 `tools/glb-to-m3dmodel/bridge.mjs` 轉檔（`manifest.json`）。設定是 `front: "+z"`，所以長邊在模型的 +x。產出 679 個三角形、5 色，大小 31.51 × 11.00 × 8.91 m。重跑會逐位元相同。

5 色能逐色保留，是靠 `glb-to-m3dmodel` 的修正：8 色以內的平塗模型不經過 median cut。在那之前，鋼灰和藍會被混成一色。

檔案讀不到時，改畫 `Map3DModelPack.standard` 裡同尺寸的程式替身（`Map3DSceneryProp.coalBunker`）：一樣是石柱、磚槽、煤和斜的輸送帶。
