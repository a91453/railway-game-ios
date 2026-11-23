# 台灣紅綠郵筒（決策 940）

3D 地圖人行道上的郵筒（`Map3DSceneryProp.postBoxes`，檔名照舊 `meshy-post-boxes.m3dmodel`）。從決策 940 起是本地工作室做的模型，取代決策 467 的 Meshy 郵筒。

```sh
# 從 repo 根目錄；只用 Python 標準庫
python3 -I tools/tw-post-boxes/build.py [--output RailwayGameApp/Resources/Models/meshy-post-boxes.m3dmodel]
```

- `source/tw-post-boxes.glb`：`a91453/railway-assets-private-2` `game-art-previews/docs/art/tw-post-boxes-2026-11/revision-2/`（工作室任務 `tw-post-boxes-r2`，交件 `d7bb4e6`，換家重審通過），SHA-256 `1121f8777872671543d92b63b9443620ef9fa26f2e29fc183e99cb4c8a685b44`。作者為遊戲做的模型，沒有用 AI 生成。
- 每個三角形照 GLB 的位置（glTF 的 +y 朝上轉成檔案的 +z 朝上），顏色照材質名換成遊戲已有的格位，GLB 自己的顏色不讀：

| 材質 | 部位 | 遊戲的顏色 |
|---|---|---|
| `postRed` | 紅郵筒（−x） | `Map3DSceneryProp.postRed` #C8382E |
| `postGreen` | 綠郵筒（+x） | `Map3DSceneryProp.postGreen` #2E8B4E |
| `slotFrame` | 投信口外框 | `Map3DSceneryProp.signWhite` #F2F3F1 |
| `slot` | 投信口底 | `Map3DPalette.dark` #2B2F36 |

產出 352 個三角形，1.04 × 0.43 × 1.15 m，投信口朝 +y（馬路）。同樣的輸入，輸出逐位元相同。經驗：assets-2 `docs/studio/lessons/tw-post-boxes.md`。
