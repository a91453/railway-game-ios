---
name: station-kit
description: 產生台灣車站完整遊戲站型、月台站廳與建築小零件，匯出原生模型、GLB 與七方向透明 PNG。Use when extending the station catalog, generating modular station/building assets, or checking roof, wall and floor connections.
---

# 車站與建築組件

這個 kit 的配方、造型做法、座標與接點、審查重點與歷次教訓是獨門做法，2026-11-18 搬到私有素材庫 `a91453/railway-assets-private-2` 的 `docs/studio/skills/station-kit.md`。**動這個 kit 之前先讀那一份**；這裡只留重建指令與一般的檢查。

做或改模型照 [model-look](../model-look/SKILL.md)。

## 重建

```sh
python3 tools/station-kit/catalog.py      # 站點來源或對照有改時
tools/station-kit/rebuild.sh ../railway-reference-private/Railway/game-art-previews/docs/art/station-kit-2026-10-21
PATH=/workspace/scratch/swift/usr/bin:$PATH bash tools/station-kit/rebuild-keelung.sh ../railway-assets-private/game-art-previews/docs/art/station-exteriors-batch2/revision-2
```

## 檢查

- `swift build --build-tests -Xswiftc -warnings-as-errors`，再跑這個 kit 的 XCTest（`swift test --skip-build --filter <類別>`）。
- 重建工具的說明與驗證在 `tools/station-kit/README.md`。大型成品（native、GLB、七向 PNG、viewer）放目前收新素材的素材庫（`docs/ASSET_REPOSITORIES.md`），不放這個 repo。
- 照 CLAUDE.md 寫 VERIFIED／UNVERIFIED：Linux 的 WebGL 預覽不是 Metal，實機效能與地圖接入另驗。
