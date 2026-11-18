---
name: residential-kit
description: 台灣住宅街廓、界牆、庭院設施與四組景的原生 3D 配方、接點和七向透明圖。
---

# ResidentialKit

這個 kit 的配方、造型做法、座標與接點、審查重點與歷次教訓是獨門做法，2026-11-18 搬到私有素材庫 `a91453/railway-assets-private-2` 的 `docs/studio/skills/residential-kit.md`。**動這個 kit 之前先讀那一份**；這裡只留重建指令與一般的檢查。

做或改模型照 [model-look](../model-look/SKILL.md)。

## 重建

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/residential-kit/rebuild.sh /path/to/railway-assets-private/game-art-previews/docs/art/residential-kit-2026-10-21
```

## 檢查

- `swift build --build-tests -Xswiftc -warnings-as-errors`，再跑這個 kit 的 XCTest（`swift test --skip-build --filter <類別>`）。
- 重建工具的說明與驗證在 `tools/residential-kit/README.md`。大型成品（native、GLB、七向 PNG、viewer）放目前收新素材的素材庫（`docs/ASSET_REPOSITORIES.md`），不放這個 repo。
- 照 CLAUDE.md 寫 VERIFIED／UNVERIFIED：Linux 的 WebGL 預覽不是 Metal，實機效能與地圖接入另驗。
