# ISLAND-ACQUIRE（決策 792）交接

- 2026-11-16，雲端 session，分支 `claude/compassionate-fermat-qyuc1u`。來源 REVIEW-L23 P2-3。存檔版本、golden、GameCore 不動。
- 做了：收購台鐵支線時，真實島式、剛好兩股的站直接鋪島式（十分；竹中、竹東、九讚頭；二水、濁水）；島式清單不再把輕軌、捷運的站對到同名的台鐵島式站（臺鐵美術館、鶯歌車站）；`RealLineIslandSweepTests` 掃 15 條在售路線。細節在 [`decisions/792.md`](../decisions/792.md)。
- 還留下：
  1. 中洲、沙崙（三股）照舊，第三股放 16 m 外在彎道上鋪不出來。
  2. 已買下的十分仍改不了：評估月台外漸寬段縮短。
  3. 台灣輕軌、捷運的真實島式站沒有資料。
  4. 實景示範的瑞芳、猴硐、十分是示範自己鋪的，沒動。
- UNVERIFIED：買下後的 3D 島式月台沒在 App、模擬器、實機看過；只有 Linux 測試。

## 2026-11-17 ISLAND-ACQUIRE-2

- 雲端 project thread「修已買車站改不成島式」，分支 `claude/project-thread-muw65g`。細節在 [`decisions/792.md`](../decisions/792.md) 的「後來」。
- 上面的第 1、2 項做了：已買下的十分（和實景示範的瑞芳、猴硐、十分）能改島式；中洲、沙崙收購時鋪三股島式，沙崙線買得成。
- 還留下：中洲在急彎上，3D 仍畫成三座岸式月台（股道數正確）；台灣輕軌、捷運的真實島式站沒有資料。
- UNVERIFIED：只有 Linux 測試，沒在 App、模擬器、實機看過。
