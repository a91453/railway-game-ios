# R200 專用資料與驗收

使用共用 train-models，不複製匯出或viewer實作。

`PATH=/path/to/swift6.4/usr/bin:$PATH tools/tra-r200/build.sh /absolute/output`

原生完整近遠單機（不是完整牽引列車），端別／比例資料缺口見 docs/art/tra-r200/README.md。

第二輪：先按公開README在65464b23的獨立checkout重建並render真正第一輪到BEFORE；再build/render本輪到OUT，執行：

```sh
python3 tools/tra-r200/curate.py OUT /tmp/overview.png BEFORE
python3 tools/tra-r200/deliver.py OUT DEST/tra-r200/revision-2 BEFORE PRODUCER
```

本型wrapper只固定來源／四態／配置／前稿預覽SHA，呼叫共用deliver.py；不另造loader、GLB或viewer。producer以40位SHA指定，README／狀態等輸入也從該commit讀取，避免用後來工作樹的metadata覆蓋。
