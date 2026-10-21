---
name: shuttle-bus
description: 高頂短車鼻小型接駁公車，原生3D造型、街景車流接入及七向預覽。
---

# 高頂接駁小巴

讀CLAUDE.md、art-style、station-kit與#231後再改。作者提供4張綠色高頂小巴的前／後／左右圖，授權微調顏色形狀；保留高頂、短車鼻、右側乘客門，改遊戲藍綠＋米白、無品牌車頭、分離後窗／直立尾燈。不要擅自改成大型低地板公車。

Map3DShuttleBus.model()產生life-shuttleBus；Map3DStreetModel.shuttleBus追加在原有街景類型後，standard模型包自動收錄。Map3DStreetLife在原本5%公車池中取30%小巴，其餘大型市區公車；isBus統一統計／顏色／上限，不增加交通量或變更17m保守間距。小巴固定不透明藍綠／米白塗裝，不受instance換色；既有大型公車仍由Map3DCityBus讀Meshy檔替換。這是街景視覺車型，不新增GameCore可購買／營運車輛。

內部x前/y上/z右；輸出native為x前/y左/z上、公尺。右側車門在native負y。車長約6.78m、身寬2.08m（含鏡低於2.8m）、高2.88m，輪底z=0。

shuttleShell用CCW側面輪廓、ear clipping與封閉外圈保留凹輪拱；不能用整個多邊形triangle fan填掉輪拱。輪胎半徑.36m、輪拱.44m；測試射線穿過胎頂／拱頂間空隙。風擋沿實際斜面法線偏移.012/.014m，向內射線須打到實體背板；不能把玻璃貼在空中。門、燈、後窗、後視鏡均附實體車身／支架。頭尾燈保留glow，無品牌徽章／文字／原始貼圖。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/shuttle-bus/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/shuttle-bus-2026-10-21
```

輸出1款新車＋1款既有大型公車對照，共2 native／2 GLB／14七向RGBA；不要把對照算新車型。另附900px立體前／後／底、造型總覽、七向、大小車對照、四底色小尺寸／灰階與可旋轉viewer。原生positions／colors／glow逐頂點讀回，法線容許1e-5浮點誤差（既有公車先經非等比fit），GLB完整重建、PNG解碼／SHA／非空不裁邊、viewer操作與37指定XCTest均要驗證。外部參考factory只讀方法與尺寸，來源SHA與使用範圍存私有，不原樣打包或送外部生成服務。

公開配方／工具／測試／skill／一張總覽及小驗證；大型輸出、來源對照、viewer和ZIP放私有。兩庫draft PR互鏈，不推main、不自行合併。回報VERIFIED／UNVERIFIED；街景位置／兩車型統計可Linux測，Metal／真機效能、開門／車輪動畫未驗證。
