# 地下車站的月台（決策 860）

`overview.jpg`：自建的島式地下站（兩股隧道軌道相距 10 m、月台 220 m、地下 15 m），四個角度：上方剖開（天花板與地面不畫）、
站在島上往前看、從駕駛室進站、端牆與隧道口。島上每 40 m 一組作者舊版的地下島式月台模組
（SwiftRailMac `item_0c73a21f9828496928f986a3.glb`，決策 767 的 B：白模尺寸、現有色票）。

重建（在這個 repo 的 commit 上）：

```sh
UNDERGROUND_PREVIEW=/tmp/underground.json swift test --skip-build \
    --filter UndergroundStationsTests/testWriteThePreviewsMeshes
python3 -I tools/underground-station/preview.py /tmp/underground.json overview.jpg
```

平塗算圖，不是 Metal：沒有陰影、霧與泛光；燈照原色畫。月台門、停車位置牌等近景小物不在 base mesh，預覽裡沒有。
模型是遊戲作者自己的，經作者同意使用。
