#!/usr/bin/env bash
# Manual CI proof using the real app and the same English smoke test.
set -euo pipefail
# Decision 114: the tools are in the rail at the map's edge, and Select is
# its Done button.
source_file=RailwayGameApp/Views/BuildToolRail.swift
backup="$(mktemp)"
cp "$source_file" "$backup"
trap 'cp "$backup" "$source_file"; rm -f "$backup"' EXIT

python3 - "$source_file" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1])
text = source.read_text()
original = "                doneButton\n"
if text.count(original) != 1:
    raise SystemExit("Could not remove exactly one Select (Done) toolbar button")
source.write_text(text.replace(original, ""))
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
