---
name: park-kit
description: 公園遊具、運動設施、庭園的原生 3D 配方、四組景及七向透明圖。
---

# 公園、遊具與運動設施

先讀 CLAUDE.md、art-style、station-kit 與 #231 最新工作登記。只延伸 Map3DParkKit*.swift、tools/park-kit、本skill、對應測試與文件；不改其他Kit、地圖、GameCore或其他代理的整合工作。

36件（三類各12）＋4組景。Map3DParkKit.model(for:)與Map3DModelPack(parkKit:)按需產生，不加入standard常駐。內部x前/y上/z右；native模型與connectors為x前/y左/z上、公尺。盒子的y是底。沿用StationKitBuilder、CivicKit的封閉civicTube/civicLegs與既有色票，不新增引擎依賴。

所有單件ground底z=0。鞦韆繩下端接座椅最高面，上端嵌入橫樑。繩橋下段吊桿必須進入1.1m寬橋板邊，不能只懸在外側；保留接合回歸測試。滑梯斜面需封底、封邊，滑道／平台／階梯／支腳要接合。步橋弧面上下層相差.12；端面deck接點在x±2.5、z=.12，橋端接步道。庭園組景跨水池短邊，兩端橋台有落地基礎；不要讓橋台懸在池面上。球架與球網獨立，組景依地坪高度／connector放置。這是靜態遊戲資產，不是遊具安全、結構或運動模擬。

新素材需獨立輪廓與組件結構，不能只換色改名。私有來源讀取實際factory並保存SHA與來源尺寸，重組比例、支架、輪廓及現有霧面頂點色；無原始factory／mesh／貼圖公開，不送外部生成服務。遵守來源ASSET_LICENSE.txt。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/park-kit/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/park-kit-2026-10-21
```

40 native／40 GLB／280張384px七向RGBA。沿用station-kit renderer及GLB工具，快取只接受native＋renderer＋七PNG全部SHA相符。執行Swift6.4 warnings-as-errors、指定Park／Station／ModelFile測試、4項Node編碼測試；逐頂點native讀回、完整GLB重編、PNG解碼／hash／非空不裁邊、viewer全模型／分類搜尋／旋轉縮放／下載／390px都要驗證。

人工看三分類、四組景、七向、下斜視、四底色／小尺寸，特別檢查吊繩、滑梯、橋面、網架與底面。公開留程式／工具／測試／skill／一張總覽及小驗證；大型成品、來源對照、viewer及ZIP放私有批次資料夾。兩庫各開draft PR，不推main、不自行合併。VERIFIED與UNVERIFIED分開；真機Metal／效能、來源瀏覽器並排、App放置碰撞與動畫需另行驗證。
