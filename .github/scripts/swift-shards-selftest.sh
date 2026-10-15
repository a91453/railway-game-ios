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

# A pull request's tier (pr_plan). A small tree of test files, shaped like
# the real ones: a campaign whose static generator another campaign calls, a
# helper every campaign uses, a golden loader and the classes that read
# through it, a class another reads a save fixture through, a class that is
# not directly an XCTestCase, and one named only in another file's comments.
tree="$work/tree"
mkdir -p "$tree/Tests/GameCoreTests" "$tree/Tests/GamePresentationTests"
cat >"$tree/Tests/GameCoreTests/PropertySupport.swift" <<'SWIFT'
import XCTest

func runCampaign(_ name: String, cases: Int, _ body: (Int) throws -> Void) rethrows -> Int { 0 }
SWIFT
cat >"$tree/Tests/GameCoreTests/LineDispatchPropertyTests.swift" <<'SWIFT'
@testable import GameCore
import XCTest

final class LineDispatchPropertyTests: XCTestCase {
    static func generate(_ count: Int) -> [Int] { [] }
    func testCampaign() throws { _ = try runCampaign("line.dispatch", cases: 4) { _ in } }
}
SWIFT
cat >"$tree/Tests/GameCoreTests/FlexDispatchPropertyTests.swift" <<'SWIFT'
@testable import GameCore
import XCTest

/// Uses the dispatch campaign's commands (LineDispatchPropertyTests).
final class FlexDispatchPropertyTests: XCTestCase {
    func testCampaign() throws {
        _ = try runCampaign("flex.dispatch", cases: 8) { _ in _ = LineDispatchPropertyTests.generate(70) }
    }

    func testSavable() throws {}
}

private struct Helper {}

private extension FlexDispatchPropertyTests {
    func local() {}
}
SWIFT
cat >"$tree/Tests/GameCoreTests/FreightTests.swift" <<'SWIFT'
@testable import GameCore
import XCTest

final class FreightTests: XCTestCase {
    func testCargo() {} // FlexDispatchPropertyTests does not use this
}

extension FreightTests {
    func testMore() {}
}
SWIFT
cat >"$tree/Tests/GameCoreTests/GoldenScenario.swift" <<'SWIFT'
import Foundation

struct GoldenScenario: Decodable {
    let name: String
    static func load() throws -> [GoldenScenario] { _ = GoldenScenarioFixtures.directory; return [] }
}

extension GoldenScenario: Equatable {}

extension GameTime {
    var minutes: Int64 { 0 }
}

enum GoldenScenarioFixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .appendingPathComponent("GoldenScenarios", isDirectory: true)
}
SWIFT
cat >"$tree/Tests/GameCoreTests/GoldenScenarioTests.swift" <<'SWIFT'
import XCTest

final class GoldenScenarioTests: XCTestCase {
    func testEveryFixture() throws { _ = try GoldenScenario.load() }
}
SWIFT
cat >"$tree/Tests/GameCoreTests/ReferenceWorldGoldenTests.swift" <<'SWIFT'
import XCTest

final class ReferenceWorldGoldenTests: XCTestCase {
    func testTheReferenceAgrees() throws { _ = try GoldenScenario.load().map(\.name) }
}
SWIFT
cat >"$tree/Tests/GameCoreTests/SavedGameTests.swift" <<'SWIFT'
import XCTest

final class SavedGameTests: XCTestCase {
    static let fixtures = URL(fileURLWithPath: #filePath).appendingPathComponent("SaveFixtures")
    func testEveryVersionLoads() {}
}
SWIFT
cat >"$tree/Tests/GameCoreTests/PassengerRoutesTests.swift" <<'SWIFT'
import XCTest

final class PassengerRoutesTests: XCTestCase {
    func testAnOldSave() throws { _ = SavedGameTests.fixtures.appendingPathComponent("v41.json") }
}
SWIFT
cat >"$tree/Tests/GameCoreTests/ShapeTests.swift" <<'SWIFT'
import XCTest

class ShapeTests: ShapeCase {
    func testShapes() {}
}
SWIFT
cat >"$tree/Tests/GameCoreTests/ReplayFixtureTests.swift" <<'SWIFT'
import XCTest

final class ReplayFixtureTests: XCTestCase {
    func testEveryReplay() { _ = "ReplayFixtures" }
}
SWIFT
cat >"$tree/Tests/GameCoreTests/ScheduledTrafficPropertyTests.swift" <<'SWIFT'
import XCTest

final class ScheduledTrafficPropertyTests: XCTestCase {
    func testCampaign() {}
}

final class ScheduledTrafficSecondHalfPropertyTests: XCTestCase {
    func testCampaign() {}
}
SWIFT
cat >"$tree/Tests/GameCoreTests/ServiceRepeatingPropertyTests.swift" <<'SWIFT'
import XCTest

final class ServiceRepeatingPropertyTests: XCTestCase {
    func testCampaign() {}
}
SWIFT
cat >"$tree/Tests/GameCoreTests/DeadlockPropertyTests.swift" <<'SWIFT'
import XCTest

final class DeadlockPropertyTests: XCTestCase {
    func testCampaign() {}
}
SWIFT
cat >"$tree/Tests/GamePresentationTests/TourismSessionTests.swift" <<'SWIFT'
import XCTest

final class TourismSessionTests: XCTestCase {
    func testTheCatalogIsTheToolsFile() { _ = "tools/tourism-spots/taiwan_attractions.json" }
}
SWIFT
cat >"$tree/Tests/GamePresentationTests/FinanceHistoryTests.swift" <<'SWIFT'
import XCTest

@MainActor
final class FinanceHistoryTests: XCTestCase {
    func testBuckets() {}
}
SWIFT

# expect_plan <tier> <tests> <description> <path>...
expect_plan() {
  local want_tier="$1" want_tests="$2" what="$3" got
  shift 3
  got="$(cd "$tree" && printf '%s\n' "$@" | "$script" plan 2>"$work/err.txt")" || got="exit $?"
  if [[ "$(sed -n 's/^tier=//p' <<<"$got")" == "$want_tier" && "$(sed -n 's/^tests=//p' <<<"$got")" == "$want_tests" ]]; then
    echo "ok   pass  plan: $what -> $want_tier"
  else
    echo "FAIL plan: $what: expected tier $want_tier, tests '$want_tests'; got: $(tr '\n' ' ' <<<"$got")"
    sed 's/^/     | /' "$work/err.txt" | tail -8
    failures=$((failures + 1))
  fi
}
present='GamePresentationTests.*'
# The pull requests of 2026-10-12, as they changed the files.
pr398=(Sources/GameCore/Freight/Freight.swift Tests/GameCoreTests/FreightTests.swift docs/ARCHITECTURE.md)
pr401=(Tests/GameCoreTests/FlexDispatchPropertyTests.swift)
pr403=(RailwayGameApp/RailwayGame.xcodeproj/project.pbxproj RailwayGameApp/Views/AchievementsView.swift
  RailwayGameApp/Views/ContentView.swift Sources/GamePresentation/Achievements.swift
  Sources/GamePresentation/CompanyRank.swift Sources/GamePresentation/GameSession.swift
  Tests/GamePresentationTests/AchievementsTests.swift Tests/GamePresentationTests/BalanceReportTests.swift
  docs/ARCHITECTURE.md)
pr406=(RailwayGameApp/App/GameAudio.swift RailwayGameApp/Resources/Audio/refused.wav
  RailwayGameApp/Views/HUDView.swift Sources/GamePresentation/ListSearch.swift
  Tests/GamePresentationTests/ListSearchTests.swift docs/research/REFERENCE_PORT_INVENTORY.md
  tools/audio/README.md tools/audio/make_game_audio.py)
pr414=(Sources/GamePresentation/FinanceHistory.swift Sources/GamePresentation/StationMasterAdvice.swift
  Tests/GamePresentationTests/FinanceHistoryTests.swift Tests/GamePresentationTests/OnboardingTests.swift
  docs/ARCHITECTURE.md)
slim=(GoldenScenarios/city-requests.json GoldenScenarios/README.md)
expect_plan full "" "#398 (two lines of GameCore and a test)" "${pr398[@]}"
expect_plan tests-only FlexDispatchPropertyTests "#401 and #419 (a GameCore campaign file only)" "${pr401[@]}"
expect_plan presentation "$present" "#403 (GamePresentation and the app)" "${pr403[@]}"
expect_plan presentation "$present" "#406 (GamePresentation, the app, its sounds)" "${pr406[@]}"
expect_plan presentation "$present" "#414 (GamePresentation and its tests)" "${pr414[@]}"
expect_plan fixtures "GoldenScenarioTests ReferenceWorldGoldenTests" "#413's golden made smaller" "${slim[@]}"
expect_plan presentation "FlexDispatchPropertyTests $present" "mixed: presentation and a campaign file run both" "${pr414[@]}" "${pr401[@]}"
expect_plan fixtures "FlexDispatchPropertyTests GoldenScenarioTests ReferenceWorldGoldenTests" "mixed: a fixture and a test file" "${slim[@]}" "${pr401[@]}"
expect_plan full "" "mixed: anything with GameCore is full" "${pr403[@]}" Sources/GameCore/World/GameWorld.swift
expect_plan none "" "docs, tools, the app's code and other workflows" docs/ROADMAP.md tools/golden-checks/city_requests.py \
  RailwayGameApp/Views/MapView.swift .github/workflows/ios-build.yml README.md
expect_plan tests-only FreightTests "a test file named only in another file's comments, with its own extension" Tests/GameCoreTests/FreightTests.swift
expect_plan full "" "a campaign whose static generator another campaign calls" Tests/GameCoreTests/LineDispatchPropertyTests.swift
expect_plan full "" "a helper other test files use" Tests/GameCoreTests/PropertySupport.swift
expect_plan full "" "a golden loader" Tests/GameCoreTests/GoldenScenario.swift
expect_plan full "" "a class that is not directly an XCTestCase" Tests/GameCoreTests/ShapeTests.swift
expect_plan full "" "a deleted or renamed test file" Tests/GameCoreTests/GoneTests.swift
expect_plan fixtures "PassengerRoutesTests SavedGameTests" "a save fixture, read through SavedGameTests.fixtures" SaveFixtures/v50-city-requests.json
expect_plan fixtures "ReplayFixtureTests" "a replay fixture" ReplayFixtures/kernel.json
expect_plan presentation "$present" "the app's bundled data" RailwayGameApp/Resources/RealWorld/taiwan_places.json
expect_plan full "" "the package, the CI scripts and ci.yml" Package.resolved .github/scripts/swift-shards.sh
expect_plan full "" "another test module" Tests/OtherTests/X.swift
expect_plan presentation "$present" "a tool's file a GamePresentation test reads" tools/tourism-spots/taiwan_attractions.json
expect_plan tests-only ServiceRepeatingPropertyTests "one campaign file" Tests/GameCoreTests/ServiceRepeatingPropertyTests.swift
expect_plan full "" "a file of two campaigns, which one job cannot hold" Tests/GameCoreTests/ScheduledTrafficPropertyTests.swift
expect_plan tests-only DeadlockPropertyTests "another campaign file" Tests/GameCoreTests/DeadlockPropertyTests.swift
expect_plan full "" "two campaign files" Tests/GameCoreTests/ServiceRepeatingPropertyTests.swift Tests/GameCoreTests/DeadlockPropertyTests.swift
expect_plan full "" "a campaign file beside GamePresentation" Tests/GameCoreTests/ServiceRepeatingPropertyTests.swift "${pr414[@]}"
# Every path `relevant` counts runs some tests, and none it does not count does.
for path in Package.swift Sources/GameCore/World/GameWorld.swift Tests/GameCoreTests/FreightTests.swift \
  GoldenScenarios/line-dispatch.json SaveFixtures/v1-demo-90-minutes.json ReplayFixtures/kernel.json .github/workflows/ci.yml \
  .github/scripts/swift-shards-selftest.sh RailwayGameApp/Resources/RealWorld/taiwan_places.json \
  Sources/GamePresentation/GameSession.swift Tests/GamePresentationTests/FinanceHistoryTests.swift \
  tools/tourism-spots/taiwan_attractions.json; do
  tier="$(cd "$tree" && echo "$path" | "$script" plan 2>/dev/null | sed -n 's/^tier=//p')"
  if [[ "$(relevant "$path")" == true && -n "$tier" && "$tier" != none ]]; then
    echo "ok   pass  plan: $path is tested ($tier)"
  else
    echo "FAIL plan: $path: relevant $(relevant "$path"), tier '$tier'"
    failures=$((failures + 1))
  fi
done
# A part of a selection: each class in one part, heaviest first to the
# lightest part (unweighted classes count the same, in name order).
printf 'M.A/t1\nM.A/t2\nM.B/t\nM.C/t\nN.D/t\n' >"$work/parts.txt"
parts="$(for k in 1 2; do SELECTED_TESTS='M.* D' SELECTED_PART="$k/2" SWIFT_TEST_LIST_FILE="$work/parts.txt" "$script" select selected | tr '\n' ' '; echo; done)"
if [[ "$parts" == $'M.A/t1 M.A/t2 M.C/t \nM.B/t N.D/t ' ]]; then
  echo "ok   pass  selected parts split the classes"
else
  echo "FAIL selected parts: $parts"
  failures=$((failures + 1))
fi
# A weighted class (CLASS_WEIGHTS) fills a part of its own before the light
# ones share the others, and the parts still split the selection exactly.
printf 'M.A/t\nM.B/t\nM.C/t\nM.HighSpeedDemoTests/t1\nM.HighSpeedDemoTests/t2\nM.LineLossFixesTests/t\n' >"$work/weighted.txt"
parts="$(for k in 1 2 3; do SELECTED_TESTS='M.*' SELECTED_PART="$k/3" SWIFT_TEST_LIST_FILE="$work/weighted.txt" "$script" select selected | tr '\n' ' '; echo; done)"
if [[ "$parts" == $'M.HighSpeedDemoTests/t1 M.HighSpeedDemoTests/t2 \nM.LineLossFixesTests/t \nM.A/t M.B/t M.C/t ' ]]; then
  echo "ok   pass  selected parts follow the classes' weights"
else
  echo "FAIL selected weighted parts: $parts"
  failures=$((failures + 1))
fi

# GameCore classes a fixture directory adds to the GamePresentation tests are
# weighted too: the golden scenarios fill a part of their own, not the part
# of the light classes.
printf '%s\n' GameCoreTests.GoldenScenarioTests/t1 GameCoreTests.GoldenScenarioTests/t2 \
  GameCoreTests.ReservationShortcutTests/t GamePresentationTests.HighSpeedDemoTests/t \
  GamePresentationTests.A/t GamePresentationTests.B/t GamePresentationTests.C/t >"$work/fixture-parts.txt"
parts="$(for k in 1 2 3; do SELECTED_TESTS='GamePresentationTests.* GoldenScenarioTests ReservationShortcutTests' SELECTED_PART="$k/3" \
  SWIFT_TEST_LIST_FILE="$work/fixture-parts.txt" "$script" select selected | tr '\n' ' '; echo; done)"
if [[ "$parts" == $'GamePresentationTests.HighSpeedDemoTests/t \nGameCoreTests.GoldenScenarioTests/t1 GameCoreTests.GoldenScenarioTests/t2 \nGameCoreTests.ReservationShortcutTests/t GamePresentationTests.A/t GamePresentationTests.B/t GamePresentationTests.C/t ' ]]; then
  echo "ok   pass  selected parts weigh the GameCore classes a fixture adds"
else
  echo "FAIL selected parts with GameCore classes: $parts"
  failures=$((failures + 1))
fi
SELECTED_TESTS='GoneTests' WHY='GoneTests has no tests' expect fail "a selected class that does not exist fails" "$script" run selected
SELECTED_TESTS='UnitTests GamePresentationTests.*' expect pass "a selection runs exactly its tests" "$script" run selected
SELECTED_TESTS='GamePresentationTests.*' SELECTED_PART=1/2 expect pass "a part of a selection runs exactly its tests" "$script" run selected
FAKE_MODE=drop SELECTED_TESTS='UnitTests' WHY='not the tests the shard selects' expect fail "a selected test that does not run fails the selection" "$script" run selected

# ci.yml's decision (decide): a push to main and a manual run are full
# whenever the Swift jobs run, a pull request runs its tier unless labelled
# full-ci. In the same tree as the plans above.
full_matrix="$("$script" matrix)"
# expect_decision <swift> <tier> <matrix: full, none, or a jq-free fragment
# the matrix must contain> <description> <VAR=value...> -- <path>...
expect_decision() {
  local want_swift="$1" want_tier="$2" want_matrix="$3" what="$4" got matrix ok=true
  shift 4
  local -a vars=()
  while [[ $# -gt 0 && "$1" != -- ]]; do vars+=("$1"); shift; done
  shift
  got="$(cd "$tree" && printf '%s\n' "$@" | env "${vars[@]}" "$script" decide 2>"$work/err.txt")" || got="exit $?"
  matrix="$(sed -n 's/^matrix=//p' <<<"$got")"
  [[ "$(sed -n 's/^swift=//p' <<<"$got")" == "$want_swift" && "$(sed -n 's/^tier=//p' <<<"$got")" == "$want_tier" ]] || ok=false
  case "$want_matrix" in
    full) [[ "$matrix" == "$full_matrix" ]] || ok=false ;;
    none) ;;
    *) [[ "$matrix" == *"$want_matrix"* && "$matrix" != "$full_matrix" ]] || ok=false ;;
  esac
  if [[ "$ok" == true ]]; then
    echo "ok   pass  decide: $what -> $want_tier"
  else
    echo "FAIL decide: $what: expected swift $want_swift, tier $want_tier, matrix $want_matrix; got: $(tr '\n' ' ' <<<"$got")"
    sed 's/^/     | /' "$work/err.txt" | tail -5
    failures=$((failures + 1))
  fi
}
expect_decision true full full "a push to main of GameCore" EVENT=push LISTED=true -- Sources/GameCore/World/GameWorld.swift
expect_decision true full full "a push to main of GamePresentation only is still full" EVENT=push LISTED=true -- "${pr414[@]}"
expect_decision true full full "a push to main of one test file only is still full" EVENT=push LISTED=true -- "${pr401[@]}"
expect_decision false none none "a push to main of docs skips" EVENT=push LISTED=true -- docs/ROADMAP.md
expect_decision true full full "a push to main whose files could not be listed" EVENT=push LISTED=false --
expect_decision true full full "a manual run" EVENT=workflow_dispatch LISTED=false --
expect_decision true presentation '{"shard":"selected-3","tests":"GamePresentationTests.*","part":"3/3"}' \
  "a pull request of GamePresentation runs it in 3 parts" EVENT=pull_request LISTED=true -- "${pr414[@]}"
expect_decision true tests-only '{"include":[{"shard":"selected","tests":"FlexDispatchPropertyTests","part":"1/1"}]}' \
  "a pull request of one campaign file" EVENT=pull_request LISTED=true -- "${pr401[@]}"
expect_decision true full full "a pull request labelled full-ci" EVENT=pull_request LISTED=true LABELS="full-ci" -- "${pr414[@]}"
expect_decision true full full "a pull request with full-ci among other labels" EVENT=pull_request LISTED=true \
  LABELS=$'bug\nfull-ci documentation' -- "${pr401[@]}"
expect_decision true full full "a pull request labelled full-ci with only docs" EVENT=pull_request LISTED=true LABELS="full-ci" -- docs/ROADMAP.md
expect_decision true presentation 'GamePresentationTests' "a label that only looks like full-ci" EVENT=pull_request LISTED=true \
  LABELS="no-full-ci full-cid" -- "${pr414[@]}"
expect_decision false none none "a pull request of docs skips" EVENT=pull_request LISTED=true -- docs/ROADMAP.md README.md
expect_decision true full full "a pull request whose files could not be listed" EVENT=pull_request LISTED=false --

# The gate: red when the detection or any Swift job of the tier did not
# succeed (a failed or cancelled job makes the combined result so), green
# when every job passed or none was needed and none ran.
gate() { env -u CHANGES -u SWIFT_NEEDED -u TIER -u CURRENT "$@" "$script" gate; }
expect pass "gate: every job of a full run passed" gate CHANGES=success SWIFT_NEEDED=true TIER=full CURRENT=success
expect pass "gate: every job of a partial tier passed" gate CHANGES=success SWIFT_NEEDED=true TIER=presentation CURRENT=success
expect pass "gate: nothing needed, nothing ran" gate CHANGES=success SWIFT_NEEDED=false TIER=none CURRENT=skipped
WHY='did not succeed \(Swift 6.4: failure\)' expect fail "gate: a selected job failed" gate CHANGES=success SWIFT_NEEDED=true TIER=tests-only CURRENT=failure
WHY='did not succeed \(Swift 6.4: cancelled\)' expect fail "gate: a selected job was cancelled" gate CHANGES=success SWIFT_NEEDED=true TIER=fixtures CURRENT=cancelled
WHY='did not succeed \(Swift 6.4: skipped\)' expect fail "gate: needed jobs that did not run" gate CHANGES=success SWIFT_NEEDED=true TIER=full CURRENT=skipped
WHY='not needed but did not skip' expect fail "gate: unneeded jobs that ran" gate CHANGES=success SWIFT_NEEDED=false TIER=none CURRENT=success
WHY='change detection did not succeed' expect fail "gate: the detection failed" gate CHANGES=failure SWIFT_NEEDED= TIER= CURRENT=skipped
WHY='change detection did not succeed' expect fail "gate: the detection was cancelled" gate CHANGES=cancelled SWIFT_NEEDED=false TIER=none CURRENT=skipped
WHY='neither' expect fail "gate: no answer from the detection" gate CHANGES=success SWIFT_NEEDED= TIER= CURRENT=skipped

if [[ "$failures" -ne 0 ]]; then
  echo "::error::swift-shards.sh self-test: $failures failures."
  exit 1
fi
echo "swift-shards.sh self-test passed."
