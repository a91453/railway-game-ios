#!/usr/bin/env bash
# Tests swift-shards.sh without Swift. A fake `swift` on PATH plays the real one,
# correctly and then broken in each way that matters, to show that `run` passes
# when a shard runs exactly its tests and fails when it does not. A check that
# cannot fail proves nothing.
#
# Run by ci.yml's change-detection job on every run that tests the package.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/swift-shards.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
unset GITHUB_STEP_SUMMARY SWIFT_EXTRA_ARGS SWIFT_TEST_LIST_FILE

# A package that names every class the campaign shards name, plus ordinary
# ones, including a GamePresentation class with "PropertyTests" in its name.
make_list() {
  local class
  {
    for class in $("$script" classes); do
      printf 'GameCoreTests.%s/testOne\nGameCoreTests.%s/testTwo\n' "$class" "$class"
    done
    printf 'GameCoreTests.UnitTests/testA\nGameCoreTests.GoldenTests/testB\n'
    printf 'GamePresentationTests.SessionTests/testC\n'
    printf 'GamePresentationTests.TrainSessionPropertyTests/testD\n'
  } >"$1"
}
make_list "$work/list.txt"

# The fake swift. `swift test list` prints the list. `swift test --skip-build
# [--filter R | --skip R]...` prints XCTest's started/passed lines for the
# tests the arguments select (filters OR together, skips remove), then
# misbehaves as FAKE_MODE says.
cat >"$work/bin/swift" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2" == "test list" ]]; then
  cat "$FAKE_LIST"
  exit 0
fi
shift # test
filters=() skips=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter) filters+=("$2"); shift 2 ;;
    --skip) skips+=("$2"); shift 2 ;;
    *) shift ;;
  esac
done
selected="$(mktemp)"
if [[ ${#filters[@]} -eq 0 ]]; then
  cat "$FAKE_LIST" >"$selected"
else
  : >"$selected"
  for f in "${filters[@]}"; do grep -E "$f" "$FAKE_LIST" >>"$selected" || true; done
fi
for k in ${skips[@]+"${skips[@]}"}; do
  grep -v -E "$k" "$selected" >"$selected.next" || true
  mv "$selected.next" "$selected"
done
sed -E 's#^[^.]+\.([^/]+)/(.*)$#\1.\2#' "$selected" | sort -u >"$selected.names"
case "${FAKE_MODE:-ok}" in
  drop) sed -i '1d' "$selected.names" ;;                      # one selected test never runs
  extra) echo "UnitTests.testA" >>"$selected.names" ;;        # a test the shard did not select runs
esac
while IFS= read -r name; do
  echo "Test Case '$name' started at 2026-01-01 00:00:00.000"
  if [[ "${FAKE_MODE:-ok}" == failline && "$name" == *testOne ]]; then
    echo "Test Case '$name' failed (0.001 seconds)"
  else
    echo "Test Case '$name' passed (0.001 seconds)"
  fi
done <"$selected.names"
[[ "${FAKE_MODE:-ok}" != exit1 ]] || exit 1
FAKE
chmod +x "$work/bin/swift"

failures=0
# expect <pass|fail> <description> <command...>
# A failing run must also say why: its output has to match $WHY, so a run
# that fails for some other reason does not pass as the failure under test.
expect() {
  local want="$1" what="$2"
  shift 2
  local rc=0
  PATH="$work/bin:$PATH" FAKE_LIST="${FAKE_LIST:-$work/list.txt}" "$@" >"$work/out.txt" 2>&1 || rc=$?
  if [[ "$want" == pass && "$rc" -eq 0 ]] ||
    [[ "$want" == fail && "$rc" -ne 0 ]] && grep -q -E "${WHY:-.}" "$work/out.txt"; then
    echo "ok   $want  $what"
  else
    echo "FAIL expected $want (because: ${WHY:-any}), exit code $rc: $what"
    sed 's/^/     | /' "$work/out.txt" | tail -15
    failures=$((failures + 1))
  fi
}

for shard in $("$script" shards) light all; do
  expect pass "$shard runs exactly its tests" "$script" run "$shard"
done
FAKE_MODE=drop WHY='not the tests the shard selects' expect fail "a selected test that does not run fails the shard" "$script" run campaigns-2
FAKE_MODE=extra WHY='not the tests the shard selects' expect fail "a test outside the selection that runs fails the shard" "$script" run campaigns-2
FAKE_MODE=exit1 WHY='swift test failed in shard rest' expect fail "swift test exiting non-zero fails the shard" "$script" run rest
FAKE_MODE=failline WHY='tests failed in shard campaigns-1' expect fail "a failed test fails the shard" "$script" run campaigns-1

grep -v 'NetworkServicePropertyTests' "$work/list.txt" >"$work/renamed.txt"
FAKE_LIST="$work/renamed.txt" WHY='NetworkServicePropertyTests .* has no tests' expect fail "a campaign class that no longer exists fails" "$script" run rest

{ cat "$work/list.txt"; echo 'GameCoreTests.SwiftTestingSuite/test()'; } >"$work/other-format.txt"
FAKE_LIST="$work/other-format.txt" WHY='cannot follow' expect fail "a test ID in another format fails" "$script" run rest

WHY="Unknown shard 'campaigns-13'" expect fail "an unknown shard fails" "$script" run campaigns-13

# The shard selections must split a list exactly; a class named twice would not.
# (Checked offline: the five selections of the synthetic list add up to it.)
total="$(wc -l <"$work/list.txt" | tr -d ' ')"
sum=0
for shard in $("$script" shards); do
  n="$(SWIFT_TEST_LIST_FILE="$work/list.txt" "$script" select "$shard" | wc -l | tr -d ' ')"
  sum=$((sum + n))
done
if [[ "$sum" -eq "$total" ]]; then
  echo "ok   pass  the shard selections add up to all $total tests"
else
  echo "FAIL the shard selections add up to $sum tests, not $total"
  failures=$((failures + 1))
fi

# The change filter.
relevant() { printf '%s\n' "$@" | "$script" relevant; }
for path in Package.swift Sources/GameCore/World/GameWorld.swift Tests/GameCoreTests/X.swift \
  GoldenScenarios/line-dispatch.json SaveFixtures/v1-demo-90-minutes.json ReplayFixtures/kernel.json .github/workflows/ci.yml .github/scripts/swift-shards.sh \
  .github/scripts/swift-shards-selftest.sh; do
  if [[ "$(relevant docs/ROADMAP.md "$path")" == true ]]; then
    echo "ok   pass  $path is relevant"
  else
    echo "FAIL $path should be relevant"
    failures=$((failures + 1))
  fi
done
for path in README.md docs/ROADMAP.md CLAUDE.md RailwayGameApp/Views/MapView.swift \
  .github/workflows/testflight.yml .github/scripts/testflight-archive.sh .github/workflows/ios-build.yml; do
  if [[ "$(relevant "$path")" == false ]]; then
    echo "ok   pass  $path is not relevant"
  else
    echo "FAIL $path should not be relevant"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -ne 0 ]]; then
  echo "::error::swift-shards.sh self-test: $failures failures."
  exit 1
fi
echo "swift-shards.sh self-test passed."
