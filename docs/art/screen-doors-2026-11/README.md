# 月台門預覽（決策 847）

`overview.jpg`：三種月台門各一列（全高 2.5 m、台北舊站半高 1.45 m、港鐵地面站半高 1.55 m），每列三張：白天地圖鏡頭、晚上（只有玻璃亮）、站在月台上。

是 Linux 上用遊戲自己的網格（`Map3DScene.Builder.addScreenDoors`，測試 `Map3DScreenDoorsTests.testWriteThePreviewsMeshes` 匯出）以平塗深度緩衝畫的示意圖，不是 Metal、不是 App 截圖：沒有太陽陰影、霧、光暈。列車是一節一個盒子，深藍是車門位置。

重做：

```sh
SCREEN_DOORS_PREVIEW=/tmp/doors.json swift test --skip-build --filter Map3DScreenDoorsTests/testWriteThePreviewsMeshes
python3 -I tools/screen-doors/preview.py /tmp/doors.json docs/art/screen-doors-2026-11/overview.jpg
```
