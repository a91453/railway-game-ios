# EMU800 原生重建

Swift6.4，warnings-as-errors。Node＋既有 Playwright/Chromium，Python NumPy/Pillow，Blender。
先讀專案原生車輛手冊；四設備角色＋反向近遠，八輛M3DAssembly，軌面Z=0。
配方獨立；格式、PNG、GLB與viewer通用工具沿用已交付流程。不改共用預算／營運。

```sh
export PATH=/workspace/scratch/swift-6.4/usr/bin:$PATH
export NODE_PATH=/opt/codex/cua_node/lib/node_modules
E8_ACCEPTED=ACCEPTED_E500_V3_AND_EMU3000_V5 E8_BASELINE=BASE_CAPTURE PRODUCER_COMMIT=COMMIT tools/emu800-native/export.sh OUT
node tools/emu800-native/review.mjs OUT
# 親自查看所有近遠四向，再全量輸出，不用測試代替外觀。
node tools/emu800-native/render.mjs OUT
```

接受模型必須從固定私包直接取原生，不以當前工作區重造；baseline是base fba93033真正set-emu800-head，屬接入前顯示、並非獨立EMU800前版。

最終順序：固定producer後重新export、verify、surface-audit、coexistence、review、render，實看近遠四向／近景與編組；Blender glb-audit、verify-png、standalone、browser-check（資料夾與離線）後bundle。ZIP下載驗證會更新verification，須再次bundle並另存包外下載驗證。包內source.json核producer來源bytes與公開唯一總覽；SHA256SUMS核成員。不得把WORKING-TREE候選當成固定交付。

```sh
node tools/emu800-native/verify.mjs OUT
python3 tools/emu800-native/surface-audit.py OUT
python3 tools/emu800-native/coexistence.py BASE CURRENT OUT fba93033
blender -b --python tools/emu800-native/glb-audit.py -- OUT
python3 tools/emu800-native/verify-png.py OUT
node tools/emu800-native/standalone.mjs OUT
node tools/emu800-native/browser-check.mjs OUT --standalone
python3 tools/emu800-native/bundle.py OUT PRODUCER
node tools/emu800-native/browser-check.mjs OUT
python3 tools/emu800-native/bundle.py OUT PRODUCER
```

本工具未引入新依賴；使用環境既有工具。Native/GLB/PNG/viewer互相核對，沒有另一份替代mesh。獨立GLB importer為Blender，PNG為Pillow。玻璃最多160真三角樣點／模型，正面與側面朝外表面分開，排除背面／薄邊、只允許實際橡膠雨刷命中；輪胎為8個真正連通橡膠體，查Z=0、860mm輪徑及向上殼面淨空。不是完整支承圖或動態碰撞認證。
