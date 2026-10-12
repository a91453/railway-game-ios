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
# SwiftPM passes the selected IDs to the test runner as one argument, which
# Linux refuses past a length (FAKE_ARG_MAX plays it).
if [[ -n "${FAKE_ARG_MAX:-}" && "$(sort -u "$selected" | paste -s -d , | wc -c)" -gt "$FAKE_ARG_MAX" ]]; then
  echo "error: posix_spawn error: Argument list too long (7)"
  exit 1
fi
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

for shard in $("$script" shards) all; do
  expect pass "$shard runs exactly its tests" "$script" run "$shard"
done
FAKE_MODE=drop WHY='not the tests the shard selects' expect fail "a selected test that does not run fails the shard" "$script" run campaigns-2
FAKE_MODE=extra WHY='not the tests the shard selects' expect fail "a test outside the selection that runs fails the shard" "$script" run campaigns-2
FAKE_MODE=exit1 WHY='swift test failed in shard rest' expect fail "swift test exiting non-zero fails the shard" "$script" run rest
FAKE_MODE=failline WHY='tests failed in shard campaigns-1' expect fail "a failed test fails the shard" "$script" run campaigns-1

SWIFT_SHARD_BATCH_CHARS=60 FAKE_ARG_MAX=80 expect pass "a shard too long for one argument runs in batches" "$script" run rest
SWIFT_SHARD_BATCH_CHARS=100000 FAKE_ARG_MAX=80 WHY='swift test failed in shard rest' expect fail "one batch too long for an argument fails the shard" "$script" run rest

grep -v 'NetworkServicePropertyTests' "$work/list.txt" >"$work/renamed.txt"
FAKE_LIST="$work/renamed.txt" WHY='NetworkServicePropertyTests .* has no tests' expect fail "a campaign class that no longer exists fails" "$script" run rest

{ cat "$work/list.txt"; echo 'GameCoreTests.SwiftTestingSuite/test()'; } >"$work/other-format.txt"
FAKE_LIST="$work/other-format.txt" WHY='cannot follow' expect fail "a test ID in another format fails" "$script" run rest

WHY="Unknown shard 'campaigns-99'" expect fail "an unknown shard fails" "$script" run campaigns-99

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
  .github/scripts/swift-shards-selftest.sh RailwayGameApp/Resources/RealWorld/taiwan_places.json \
  RailwayGameApp/Resources/RealRailways/tra_pingxi_runs.json; do
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

# The base a push to main is compared with. A small repository (A, B, then
# HEAD; and X, which is no ancestor of HEAD) and a fake `gh` that lists the
# successful push runs FAKE_RUNS names, or fails when FAKE_GH_FAIL is set.
repo="$work/repo"
git init -q "$repo"
commit() { git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1"; git -C "$repo" rev-parse HEAD; }
sha_a="$(commit A)"
sha_b="$(commit B)"
git -C "$repo" checkout -q --orphan other
sha_x="$(commit X)"
git -C "$repo" checkout -q -B main "$sha_b"
sha_head="$(commit HEAD)"
cat >"$work/bin/gh" <<'FAKE'
#!/usr/bin/env bash
[[ -z "${FAKE_GH_FAIL:-}" ]] || { echo "gh: HTTP 502" >&2; exit 1; }
# Only the query push_base must make is answered.
[[ "$1 $2" == "api repos/owner/repo/actions/workflows/ci.yml/runs?branch=main&event=push&status=success&per_page=20" ]] ||
  { echo "gh: unexpected query: $*" >&2; exit 1; }
for sha in ${FAKE_RUNS:-}; do echo "$sha"; done
FAKE
chmod +x "$work/bin/gh"
# expect_base <expected base, or "" for none> <description> [VAR=value...]
# With no base, the warning must match $WHY, as in expect.
expect_base() {
  local want="$1" what="$2" got
  shift 2
  got="$(cd "$repo" && env PATH="$work/bin:$PATH" GITHUB_REPOSITORY=owner/repo "$@" "$script" push-base 2>"$work/err.txt")" || got="exit $?"
  if [[ "$got" == "$want" ]] && { [[ -n "$want" ]] || grep -q -E "${WHY:-.}" "$work/err.txt"; }; then
    echo "ok   pass  push-base: $what"
  else
    echo "FAIL push-base: $what: got '$got', expected '$want'"
    sed 's/^/     | /' "$work/err.txt" | tail -5
    failures=$((failures + 1))
  fi
}
expect_base "$sha_b" "the newest successful run's commit, an ancestor" FAKE_RUNS="$sha_b $sha_a"
expect_base "$sha_b" "a successful run of HEAD itself is passed over" FAKE_RUNS="$sha_head $sha_b"
WHY='No successful push run' expect_base "" "no successful run: test everything" FAKE_RUNS=""
WHY='is not an ancestor' expect_base "" "a commit that is not an ancestor: test everything" FAKE_RUNS="$sha_x $sha_a"
WHY='Cannot fetch' expect_base "" "a commit that cannot be fetched: test everything" FAKE_RUNS="0123456789abcdef0123456789abcdef01234567"
WHY='Could not list' expect_base "" "the API failing: test everything" FAKE_RUNS="$sha_b" FAKE_GH_FAIL=1
WHY='GITHUB_REPOSITORY is not set' expect_base "" "no repository name: test everything" FAKE_RUNS="$sha_b" GITHUB_REPOSITORY=

if [[ "$failures" -ne 0 ]]; then
  echo "::error::swift-shards.sh self-test: $failures failures."
  exit 1
fi
echo "swift-shards.sh self-test passed."
