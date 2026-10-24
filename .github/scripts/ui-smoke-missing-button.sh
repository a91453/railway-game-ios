#!/usr/bin/env bash
# Manual CI proof using the real app and the same English smoke test.
set -euo pipefail
# Decision 114: the tools are in the rail at the map's edge, and Select is
# its Done button. Decision 382 pinned Done over Build where the building
# column scrolls, so BuildDoneButton is called from both files; remove it
# from each.
source_files=(RailwayGameApp/Views/BuildToolRail.swift RailwayGameApp/Views/ContentView.swift)
backup_dir="$(mktemp -d)"
for f in "${source_files[@]}"; do cp "$f" "$backup_dir/$(basename "$f")"; done
trap 'for f in "${source_files[@]}"; do cp "$backup_dir/$(basename "$f")" "$f"; done; rm -rf "$backup_dir"' EXIT

python3 - "${source_files[@]}" <<'PY'
from pathlib import Path
import re
import sys
# Each file's one BuildDoneButton call, with the modifier lines under it.
pattern = re.compile(r"^[ \t]*BuildDoneButton\([^)\n]*\)[ \t]*\n(?:[ \t]*\.[A-Za-z][^\n]*\n)*", re.MULTILINE)
for name in sys.argv[1:]:
    source = Path(name)
    text = source.read_text()
    if len(pattern.findall(text)) != 1:
        raise SystemExit(f"Could not remove exactly one Select (Done) toolbar button from {name}")
    source.write_text(pattern.sub("", text, count=1))
PY

set +e
xcodebuild test \
  -project RailwayGameApp/RailwayGame.xcodeproj \
  -scheme RailwayGame \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" \
  -resultBundlePath "$RUNNER_TEMP/ui-smoke-missing-button.xcresult" \
  -only-testing:RailwayGameUITests/ToolbarSmokeTests/testEnglishToolbar \
  -parallel-testing-enabled NO \
  -disableAutomaticPackageResolution \
  CODE_SIGN_IDENTITY=- 2>&1 | tee "$RUNNER_TEMP/ui-smoke-missing-button.log"
test_status=${PIPESTATUS[0]}
set -e
if [[ "$test_status" == 0 ]]; then
  echo "::error::The smoke test passed despite the missing Select (Done) button."
  exit 1
fi

# A compiler or Simulator failure does not count as the regression proof.
xcrun xcresulttool get test-results summary \
  --path "$RUNNER_TEMP/ui-smoke-missing-button.xcresult" \
  > "$RUNNER_TEMP/ui-smoke-missing-button-summary.json"
python3 - "$RUNNER_TEMP/ui-smoke-missing-button-summary.json" <<'PY'
import json, sys
from pathlib import Path
summary = json.loads(Path(sys.argv[1]).read_text())
assert summary["failedTests"] == 1, summary
assert any("Missing toolbar button: Done building" in failure["failureText"]
           for failure in summary["testFailures"]), summary
print("VERIFIED: removing Select (Done) fails testEnglishToolbar at its missing-button assertion.")
PY
