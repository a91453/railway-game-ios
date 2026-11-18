---
name: commercial-kit
description: 台灣商業建築、街邊店鋪、夜市招牌與商用接駁載具 3D 素材的擴充、檢查與重建流程。擴充商業套件或審查新模型時使用。
---

# 商業建築、店鋪夜市與商用載具素材 (Commercial Kit)

這個 kit 的配方、造型做法、座標與接點、審查重點與歷次教訓是獨門做法，2026-11-18 搬到私有素材庫 `a91453/railway-assets-private-2` 的 `docs/studio/skills/commercial-kit.md`。**動這個 kit 之前先讀那一份**；這裡只留重建指令與一般的檢查。

做或改模型照 [model-look](../model-look/SKILL.md)。

## 重建

```sh
tools/commercial-kit/rebuild.sh /path/to/private/output/commercial-kit-2026-10-21
```

## 檢查

- `swift build --build-tests -Xswiftc -warnings-as-errors`，再跑這個 kit 的 XCTest（`swift test --skip-build --filter <類別>`）。
- 重建工具的說明與驗證在 `tools/commercial-kit/README.md`。大型成品（native、GLB、七向 PNG、viewer）放目前收新素材的素材庫（`docs/ASSET_REPOSITORIES.md`），不放這個 repo。
- 照 CLAUDE.md 寫 VERIFIED／UNVERIFIED：Linux 的 WebGL 預覽不是 Metal，實機效能與地圖接入另驗。
