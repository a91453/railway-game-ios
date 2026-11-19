# 月台站名牌預覽（決策 882）

`overview.jpg`：決策 874 的三座站（平面島式「高雄」、平面側式「板橋」、高架側式「松山機場」），
左欄從列車停的位置看站名牌，右欄沿月台看。網格是遊戲自己的
（`Map3DPlatformPropsTests/testWriteTheFurniturePreviewsMeshes`），平塗算圖，不是 Metal：

```sh
PLATFORM_FURNITURE_PREVIEW=/tmp/furniture.json swift test --skip-build \
    --filter Map3DPlatformPropsTests/testWriteTheFurniturePreviewsMeshes
python3 -I tools/platform-name-board/preview.py /tmp/furniture.json docs/art/platform-name-board-2026-11/overview.jpg
```

字形：Noto Sans TC Bold（SIL Open Font License 1.1），`tools/platform-name-board/build_glyphs.py` 轉成方塊。
