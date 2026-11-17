# E200-REDO

## 進度

- 做了什麼：決策 825，修 bug 並重做 E200。
  - DR1000／DR3100 從 500 m 起畫遠景版。
  - E200 照真車重做，加遠景版。
  - 鳴日號的 E200 照 #1480 的分區重漆。
- 已驗證（Linux，Swift 6.4，見 PR）：
  - `swift build --build-tests -Xswiftc -warnings-as-errors`。
  - 下面 12 類的 `swift test --skip-build --filter` 全過：
    - `Map3DModelPackLockTests`、`Map3DModelPackSizeTests`、`Map3DTrainSetTests`
    - `Map3DHighSpeedSetsTests`、`Map3DDR3100Tests`、`Map3DE200MingriStyleTests`
    - `Map3DMetroSets483Tests`、`Map3DChuKuangIntegrationTests`、`Map3DChristmasLiveryTests`
    - `Map3DFarSets420Tests`、`Map3DTrainShapeRefreshTests`、`Map3DModelTests`
  - `tools/train-models/check.mjs` 全包 ok。
- 下一步：等遊戲規劃看 `docs/art/e200-redo-2026-11-17/overview.jpg`，然後合併。

## 派工

- 派工：遊戲規劃 session_01JMHz9ZJWaKh8kjuNDLtvar，NEXT_PRIORITIES §29.15 的 bug 列（2.30）與第 2 列（3.40）。
- session：session_01JMHz9Yzqh7zPKkn1zZsWPQ。
- 分支：`claude/e200-redo`。
- 決策：825。
- 存檔版本、golden schema：不動；GameCore 不動。

## 留下的

分數見 NEXT_PRIORITIES §29.28。
- E200 的菱形集電弓：現在是單臂。
- 側面通風百葉。
- 夜景頭燈的實機確認：UNVERIFIED，雲端拍圖工具不畫發光。
- 莒光號、鳴日號客車的遠景版仍超過 50%（決策 420 grandfathered）。

Mac 的工作室從雲端連不到。這次看圖用 Linux 的 `tools/model-look/shoot.mjs`，沒有經過工作室的審查者。
