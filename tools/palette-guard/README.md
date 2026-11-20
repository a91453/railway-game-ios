# 色票檢查（決策 891）

`Tests/GamePresentationTests/Map3DPaletteGuardTests.swift` 讀 `Sources/GamePresentation/*.swift`：

- `Map3DPalette` 的 `enum` 與 `extension` 區塊裡寫的 `0xRRGGBB` 是色票。
- 區塊外用 `rgb(0x…)` 或 `rgbColor(0x…)` 寫、又不是色票的顏色，「檔名 色碼」必須在 `baseline.txt` 裡，否則測試紅。
- `baseline.txt` 是 2026-11-20 已有的 471 個，**只能刪，不能加**。程式裡已經沒有的列也會讓測試紅，提醒刪掉。
- 新顏色：用色票已有的格位；真的沒有，寫進 `Map3DPalette`（附理由與決策），不要寫進 `baseline.txt`。

```sh
swift test --skip-build --filter Map3DPaletteGuardTests
```
