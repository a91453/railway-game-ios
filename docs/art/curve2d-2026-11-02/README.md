# 2D 地圖車廂沿軌道放（決策 538 續，CURVE2D）

`overview.png`：

- 上兩列：`WebsiteScreenshotTests.testTrainCarsOnCurves2D`（iPhone Pro 模擬器、橫拿、深色），改前 run 41370610865（`claude/curve2d-screenshot-before`，main + 這支截圖測試）、改後 run 41373560446（`claude/curve2d-train-on-curve`）。截圖情境 `acquired` 停住時，跟隨的兩列車都停在直線的終點月台，前後相同：直線上的樣子沒有變。
- 下面：竹中六家線彎道，2D 每節 20 m 的車廂，從 Linux 測試（`LiujiaLineTrainsTests`，06:00–09:00 中舊放法離軌最遠的那一刻，3 號車）取出的座標用 Pillow 畫出：改前車尾直直伸出 8.2 m，改後每節沿軌道 0 m。

截圖情境裡沒有停在彎道上的車，所以彎道的前後對照用測試資料畫；實機上彎道的樣子 UNVERIFIED。
