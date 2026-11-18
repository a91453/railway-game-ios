---
name: estate-kit
description: Generate player-owned amusement, hotel, residential and commercial buildings with native meshes, GLB, seven transparent views and reusable scene layouts.
---

# 自有建築與遊樂設施

這個 kit 的配方、造型做法、座標與接點、審查重點與歷次教訓是獨門做法，2026-11-18 搬到私有素材庫 `a91453/railway-assets-private-2` 的 `docs/studio/skills/estate-kit.md`。**動這個 kit 之前先讀那一份**；這裡只留重建指令與一般的檢查。

做或改模型照 [model-look](../model-look/SKILL.md)。

## 重建

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/estate-kit/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/estate-kit-2026-10-23
```

## 檢查

- `swift build --build-tests -Xswiftc -warnings-as-errors`，再跑這個 kit 的 XCTest（`swift test --skip-build --filter <類別>`）。
- 重建工具的說明與驗證在 `tools/estate-kit/README.md`。大型成品（native、GLB、七向 PNG、viewer）放目前收新素材的素材庫（`docs/ASSET_REPOSITORIES.md`），不放這個 repo。
- 照 CLAUDE.md 寫 VERIFIED／UNVERIFIED：Linux 的 WebGL 預覽不是 Metal，實機效能與地圖接入另驗。
