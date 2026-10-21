---
name: civic-kit
description: 公共建築、室內家具、台式廟宇與市場的原生 3D 配方、安裝接點與七向透明圖。
---

# 公共建築、家具、廟宇市場

先讀 CLAUDE.md、art-style、station-kit 與工作登記 #231。只延伸 Map3DCivicKit*.swift、tools/civic-kit、本skill、對應測試及文件；不要改既有車站、地圖放置或商店街。

48件：building12、furniture24、culture12；4個組景。內部 x前/y上/z右；輸出模型與connector是native x前/y左/z上，公尺。Map3DCivicKit.model(for:) 按需建置；Map3DModelPack(civicKit:) 不自動加入常駐standard。

新素材必須改輪廓、比例與組件布局，使用既有霧面色票。私有來源只取建模方法，不能原樣複製factory、模型、貼圖、標誌或文字；來源SHA與改造對照只放私有庫。不得把私有原始資產送外部生成服務。

地面件腳底z=0；wall件背板x=0；ceiling件最高點z=0向下吊掛。寫字桌desktop接點z=.80，先放桌再將桌燈mount對齊desktop。壁鐘、窗簾、投影幕、吸音板必須貼實體牆，不當落地物。天花投影機先有承重橫樑或天花。窗戶附背板，走廊附立柱。屋簷封閉底面與裙邊；不能用大幅抬高掩蓋穿插。廟門紅柱、燕尾屋脊與廟埕為重新組合的遊戲造型，非實測名勝。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/civic-kit/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/civic-kit-2026-10-21
```

沿用station-kit的native、GLB、renderer；52模型、364張384px透明圖。Swift6.4 warnings-as-errors；21項指定XCTest、4項既有Node編碼測試；逐頂點native讀回、完整GLB重編、圖片SHA/非空/不裁邊、分類、安裝面、桌面、窗戶背板、預算與決定性都要通過。瀏覽器測試搜尋分類、52模型、七向、旋轉縮放、下載hash、390px排版。快取需native、renderer及每張PNG的SHA全相同。

人工看parts、三類表、examples、directions、undersides、style-checks，檢查腳、背板、吊架、屋簷。公開只放配方／工具／測試／單一總覽／小驗證JSON。大型native、GLB、PNG、viewer與來源對照放私有庫。各開draft PR，不推main、不自行合併。報告VERIFIED／UNVERIFIED；WebGL不等於真機Metal或App已採用。正式採用前仍需來源並排與實機效能、場景碰撞驗證。
