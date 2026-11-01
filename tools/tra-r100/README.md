# R100 專用配置與驗收

沿用 `tools/train-models` 的匯出、assembly、GLB、拓樸、渲染與 viewer。
`build.sh OUT` 固定本輪十二個獨立近遠單元和資料描述配置；
`verify.mjs` 檢實際玻璃／輪軌／長短端／設備／近遠與故障反例；
`assembly-check.swift` 獨立解析原生單元與配置，核對展開 Float32 payload。
`review.mjs` 只補共同公尺相機，`curate.py` 將完整檢查圖限量成全輪20張sheet。
`deliver.py` 固定 producer 的來源／狀態／配置輸入再呼叫共用交付，不另造 loader 或 viewer。

完整來源、限制、遊戲選用與重建命令見 [R100 README](../../docs/art/tra-r100/README.md)。
