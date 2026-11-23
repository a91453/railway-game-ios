# LEVEL-CROSSING-SURFACE（決策 941）交接

2026-11-23，session_01JMHz9ZJqAsW6pQuFrLFs2F。平交道的黃色網狀線、順軌道的橡膠板、隨列車升降的柵欄桿已做完（`docs/decisions/941.md`）。

留下的（都未派，要評分再排）：

1. 平交道警鈴聲：`Map3DCrossingCycle.State.bells` 已算好，沒接 `GameAudio`。
2. 警示燈閃爍：工作室警示柱（決策 929）的紅燈沒有夜間發光版。
3. 參考的白色 X 型標誌：警示柱沒有位置放，要工作室改模型。
4. 街上的車與行人在桿放下時不停（決策 596 的號誌等待沒接平交道）。
5. `crossings.json` 的 384 處台鐵平交道真實位置沒用：先要決定真實線上的街道怎麼穿越軌道。
