# 月台家具三種站統一（決策 874）

`overview.jpg`：平面島式、平面側式、高架側式月台各兩個角度（從上方、站在月台上）。家具是作者舊版的地下島式月台模組
（SwiftRailMac `item_0c73a21f9828496928f986a3.glb`，決策 860；決策 767 的 B：白模尺寸、現有色票），
每座月台放面向自己軌道的那一半。

重建（在這個 repo 的 commit 上）：

```sh
PLATFORM_FURNITURE_PREVIEW=/tmp/furniture.json swift test --skip-build \
    --filter Map3DPlatformPropsTests/testWriteTheFurniturePreviewsMeshes
python3 -I tools/platform-furniture/preview.py /tmp/furniture.json overview.jpg
```

平塗算圖，不是 Metal：沒有陰影、霧與泛光。模型是遊戲作者自己的，經作者同意使用。
