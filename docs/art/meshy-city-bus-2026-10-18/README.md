# Meshy 試做：市區公車（2026-10-18）

作者 2026-10-18：「Meshy 用圖片+對話生成的模型 比較好 你用搜尋圖片的方式加描述請meshy生成一個」。規格：`docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md`；prompt 與設定：`tools/meshy/models.json` 的 `city-bus`；任務與點數：`tools/meshy/generated.json`。

| 檔案 | 是什麼 |
| --- | --- |
| `reference-cc0.jpg` | 參考照片（縮到 800 px）：Wikimedia Commons，[Capital Bus 735-FW right side and TWTC ITB (46106172592).jpg](https://commons.wikimedia.org/wiki/File:Capital_Bus_735-FW_right_side_and_TWTC_ITB_(46106172592).jpg)，玄史生（Flickr f999999_key），CC0 1.0。只當外型參考 |
| `concept.jpg` | 第一步 image-to-image（nano-banana-pro，9 點）：照片加描述，畫成無字、無標誌、無廣告、無車牌的通用市區公車 |
| `preview.png` | 第二步 image-to-3d（smart topology，目標 1,500 面，2K 貼圖，15 點）的 Meshy 縮圖 |
| `city-bus.glb` | Meshy 交付的原檔：1,545 個三角形、1 個材質、1 張貼圖；長軸 x（約 0.95）、高 y、寬 z，比例 12 : 3.7 : 3.0 |
| `city-bus.m3dmodel` | `tools/glb-to-m3dmodel/` 從上面的 GLB 轉出：去掉 2 個零面積三角形後是 1,543 面、8 色；車頭轉成 +x、長 12 m，檔頭保留兩筆 Meshy 任務與原檔 SHA-256。已由 `Map3DModelFile` 的 Linux 測試讀取；尚未放進 App |

合計 24 點（作者付費方案，輸出歸作者；Meshy 條款 §3.2）。

## 接進 App 之前要知道的
- GLB 的 `asset` 是 `pygltflib`，沒有 `extras`：smart topology 的輸出裡沒有 AI 識別資訊可以保留（條款 §2.4）。出處改由 `tools/meshy/generated.json` 的任務紀錄證明；規格說「來源紀錄沒有就拒絕」要改成讀這份紀錄。
- 三角形 1,545，比 1,500 多 3%：30 台全畫約 4.6 萬，仍在預算內。
- 轉檔結果是 1,543 面；兩個零面積三角形依規格不輸出。原 GLB 沒有獨立命名的車頭燈材質，轉檔器沒有憑顏色猜燈，所以目前沒有夜裡發光的旗標。
- 車頭朝 **−x**（3D 生活感 2026-10-18 確認，`models.json` 的 `front` 填 `-x`）：`views.png` 是原檔從 +x、−x、+z、−z 四個方向的平行投影（每個三角形取貼圖中點的顏色）。
  - −x 那頭：大片擋風玻璃，下緣兩角有頭燈；+x 那頭：較小的後窗，沒有頭燈。
  - 前門在 −x 那頭、前輪的前面。
  - 轉換器要把 −x 轉成模型空間的 +x（前）。
- 呼叫時 smart topology 不接受 `remove_lighting`（API 400，沒扣點）；CLI 預設會送，要用 `--data '{"remove_lighting": null}'` 清掉。
