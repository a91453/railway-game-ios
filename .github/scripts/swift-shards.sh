#!/usr/bin/env bash
# The Swift package's test selections for ci.yml, and a proof that each one ran
# exactly the tests it was meant to run.
#
#   swift-shards.sh run <shard>      run one shard after `swift build --build-tests`
#                                    (`selected`: the classes in SELECTED_TESTS)
#   swift-shards.sh select <shard>   print the test IDs a shard selects (offline)
#   swift-shards.sh shards           print the shard names, one per line
#   swift-shards.sh classes          print every class the campaign shards name
#   swift-shards.sh matrix           print them as the JSON matrix ci.yml uses
#   swift-shards.sh relevant         read changed file names on stdin; print
#                                    true if any can change the package's tests
#   swift-shards.sh push-base        print the commit a push to main is compared
#                                    with (push_base below), or nothing
#   swift-shards.sh plan             read a pull request's changed files on
#                                    stdin; print its tier and the tests it
#                                    runs (pr_plan below)
#   swift-shards.sh decide           ci.yml's change detection: whether the
#                                    Swift jobs run, the tier, the matrix
#   swift-shards.sh gate             the "Swift CI (gate)" verdict
#
# Shards (a test ID is `Module.Class/method`, as `swift test list` prints it):
#   campaigns-1 .. campaigns-15   the long property, differential and mutation
#                                campaigns, and the golden scenarios, named
#                                below
#   rest                         every test that no campaign shard names: the
#                                ordinary unit and golden tests, the
#                                GamePresentation tests, and whatever is added
#                                later, which therefore always runs somewhere.
#                                Its campaigns are named too since Stage F3b
#                                (it was the slowest shard once they ran on
#                                the track network)
#   all                          everything, for a local full run
#   selected                     the tests SELECTED_TESTS names: a pull
#                                request's partial tier (pr_plan). Words are
#                                class names, or `Module.*` for a module
#
# Every shard runs on Swift 6.4 only; the Swift 6.0 job, and its `light`
# selection (everything but the campaigns), were removed on 2026-10-05.
#
# The campaign shards run every test of the classes they name and nothing else;
# `rest` runs every other class. Together they are the whole package
# once, which `run` proves before it starts (the selections partition the
# `swift test list` output) and after it finishes (the tests XCTest reports
# starting are exactly the selection). Moving a class to another shard is an
# edit to classes_of below and nothing else.
#
# `run` needs only bash and coreutils besides swift. SWIFT_EXTRA_ARGS is added
# to every swift invocation (for example --scratch-path, locally);
# SWIFT_TEST_LIST_FILE replaces `swift test list` for offline use;
# SWIFT_SHARD_BATCH_CHARS bounds one `swift test` run (batch_classes).
set -euo pipefail

# The balance follows the measured class times; the `run` summary prints the
# slowest classes of every shard, so a rebalance is a look at those and an edit
# of this table. Take each class's time from the slower of several runs: the
# same class takes about 1.8 times as long on a slower runner (EconomyPropertyTests
# 302 s on one, 513 s on another), and the slow runners are the ones that set
# the wall time.
#
# Stage F3b moved the campaigns to the track network, which made several of
# them slower, and five campaign shards no longer fitted the 20-minute job
# limit (campaigns-2 was cancelled after 18 minutes of tests). Seconds on the
# runner of run 37156617604 (2026-10-03), and, marked ~, estimated from a
# local run at 0.81 times the local time (LinePatternPropertyTests: 427 s
# there, 530 s locally):
#   campaigns-1  EconomyPropertyTests 341, ContinuousTrackPropertyTests 34,
#                PassengerPropertyTests 29, KernelDifferentialTests 105
#   campaigns-2  BoardingPropertyTests ~510
#   campaigns-3  SaveMutationTests 538
#   campaigns-4  LinePatternPropertyTests 427
#   campaigns-5  LineDispatchPropertyTests 409, TimetablePropertyTests 106
#   campaigns-6  ServicePropertyTests ~285, VerticalRailwayPropertyTests 132,
#                NetworkSectionPropertyTests ~42 (Stage F3c, 52 s locally)
#   campaigns-7  ServiceRepeatingPropertyTests ~395
#   campaigns-8  NetworkServicePropertyTests 160, ServiceLinePropertyTests 322
#   campaigns-9  TrafficControlPropertyTests ~370 (Stage U2: with the
#                following campaign, 196 s locally, 455 s locally in all,
#                it no longer fitted beside ServiceRepeatingPropertyTests in
#                campaigns-7)
#   rest         GoldenScenarioTests 35, WorldStateMachineTests 31, and the
#                rest, about 170 in all
# so about 400 to 540 s a shard there, up to about 970 s on a slower runner.
# Stage F3c-3b deleted the grid's campaigns (StationFacilityPropertyTests and
# TrackResourcePropertyTests here, and the grid's position, movement, route
# and topology campaigns from rest) with the grid's tests.
#
# Stages V1 to V3 added campaigns-10 to campaigns-12 and made
# TrafficControlPropertyTests slower (1052 s of tests in run 37260822506);
# after the V3 fixes campaigns-9 and campaigns-12 were cancelled at the
# limit (run 37269381885). So traffic.following has a class of its own,
# TrafficFollowingPropertyTests, and traffic.scheduledMeets runs cases 0 to
# 8 of each seed in ScheduledTrafficPropertyTests and 9 to 17 in
# ScheduledTrafficSecondHalfPropertyTests. Seconds locally (Swift 6.4, two
# shards at a time):
#   campaigns-9   TrafficControlPropertyTests 578
#   campaigns-10  OccupiedRoutingPropertyTests 100
#   campaigns-11  DeadlockPropertyTests 153
#   campaigns-12  ScheduledTrafficPropertyTests 563
#   campaigns-13  TrafficFollowingPropertyTests 558
#   campaigns-14  ScheduledTrafficSecondHalfPropertyTests 563
#
# V4a adds all six three-train cases (18 to 23) of traffic.scheduledMeets,
# across four shards, without reducing any existing case. Swift 6.4 local
# measurements on 2026-10-05, two to four shards running at a time:
#   campaigns-12  ScheduledTrafficPropertyTests 375 s
#   campaigns-14  ScheduledTrafficSecondHalfPropertyTests 377 s
#   campaigns-15  ScheduledOvertakeTrackPropertyTests 179 s
#   campaigns-16  ScheduledOvertakeTrackMiddlePropertyTests 191 s
#   campaigns-17  ScheduledOvertakeTrackLastPropertyTests 136 s
#   campaigns-18  ScheduledOvertakeTrackFinalPropertyTests 195 s
# The new shards stay below 560 s even at 1.8 times these local times.
# Runner measurements are reported in the PR; keep the 20-minute job limit.
# Stage V4b adds campaigns-19: LineRoutePreferencePropertyTests, 18.2 s
# locally on Swift 6.4 (680 full-state/batch-second steps). Existing campaigns
# are unchanged. All jobs keep their 20-minute timeout.
# V4b CI run 37316105112: campaigns-5 took 624 s (LineDispatch 488,
# Timetable 135), campaigns-8 586 s (ServiceLine 305, NetworkService 280).
# Put NetworkService/Timetable beside the 20 s new campaign (~435 s),
# and the smaller campaigns from campaigns-1 beside occupied routing.
# campaigns-1 took 976 s, including Economy 657 s, ContinuousTrack 145 s,
# Kernel 115 s, Passenger 58 s. Economy keeps all 12 cases/seed, split at
# case 6 into campaigns-1/20; the halves' event-volume minima sum to the
# original bound. campaigns-10 carries the smaller classes.
# This preserves all original cases, operations and checks without timeout changes.
# V4c: run 37321507070 passed all 780 tests, but SaveMutation took 732 s.
# Keep every method's original cases/seeds/mutations/assertions; seven methods
# stay in SaveMutationTests (campaigns-3), seven run in its second-half class
# (campaigns-21). New line.singleTrackCapacity's 576 steps use campaigns-22.
# Phase 5F R1: PassengerPlanKeyTests (a 40-station network plan worked out
# afresh twice, and a day of minute calls) took 312 s locally on Swift 6.4;
# it runs alone in campaigns-23 rather than lengthen rest.
# 2026-10-08: rest had become the slowest shard (14.1 min of job on #204's run
# 37727430223, the others at most 11.6), and GoldenScenarioTests took 284 s of
# its 728 s of tests there (RealWorldDemoTests 85, ScheduledTrafficTests 71,
# WorldStateMachineTests 55, the rest under 40 each). The golden scenarios run
# alone in campaigns-24, which leaves rest about 444 s.
# 2026-10-09: the account's runners were the bottleneck, not the shards'
# length. Linux shards themselves waited up to 16 minutes for a runner (run
# 37892260732), and every job also spends about 1.8 minutes starting its
# container and building (44 of the run's 190 job-minutes), so 25 jobs a run
# were 25 runners and 25 builds. The short shards were paired with others,
# keeping every class (and so every test) and no shard above the slowest one,
# old campaigns-7 (ServiceRepeatingPropertyTests, 792 s of tests, alone).
# Seconds of tests, the slower of runs 37892260732 and 37883215492; the old
# shard names on the left are the ones the notes above use:
#   campaigns-1   old 7                                       792
#   campaigns-2   old 6 (652) + old 22 (63)                   715
#   campaigns-3   old 5 (579) + old 17 (100)                  679
#   campaigns-4   old 10 (518) + old 11 (133)                 651
#   campaigns-5   old 12 (501) + old 15 (164)                 665
#   campaigns-6   old 21 (413) + old 1 (276)                  689
#   campaigns-7   old 4 (405) + old 3 (240)                   645
#   campaigns-8   old 19 (465) + old 16 (253)                 718
#   campaigns-9   old 20 (330) + old 24 (321)                 651
#   campaigns-10  old 18 (267) + old 23 (261)                 528
#   campaigns-11  old 14                                      500
#   campaigns-12  old 9                                       492
#   campaigns-13  old 2                                       491
#   campaigns-14  old 8                                       488
#   campaigns-15  old 13                                      468
#   rest          (unchanged)                                 488
# 16 jobs instead of 25; the wall time is still the slowest shard's.
# 2026-10-12: rest had grown to 13.8 minutes of job at the median and up to
# 18.9 (ten runs between 17.8 and 18.9) against the 20-minute limit, as the
# GamePresentation tests grew (docs/research/CI_INCIDENT_2026-10-12.md, 4A-3).
# Two of its slowest classes, both GamePresentation demo-map tests, move to
# the shortest campaign shards: HighSpeedDemoTests to campaigns-11 and
# RealWorldDemoTests to campaigns-15. Estimated on a slow runner: rest about
# 18.9 -> 15.8 minutes, campaigns-11 about 9.5 -> 11.4, campaigns-15 about
# 10.1 -> 11.5; the slowest shard is campaigns-1 again.
# 2026-10-12 (NEXT_PRIORITIES §2 item 6): ReservationShortcutTests, which
# asks route reservation the long way it replaced on long legs (about 1.5
# minutes locally), joins campaigns-10, the shortest shard, rather than rest.
# 2026-10-13: rest reached the 20-minute limit on main (run 38382988433:
# 1042 s of tests, all passing, and the job cancelled at its limit while it
# cleaned up). Eight GamePresentation classes leave it for the shortest
# campaign shards; a GamePresentation file runs the presentation tier
# whichever shard runs its class, so a pull request's tier does not change.
# Seconds on that run: NewGameSavePropertyTests 88 to campaigns-15 (259 s of
# tests); OnboardingTests 52 and LineLossFixesTests 27 to campaigns-14
# (272 s); ScreenshotSceneTests 22 and NewGameBalanceTests 21 to campaigns-8
# (387 s); RealWorldDemoGroundTests 18, RealWorldDataLoadTests 15 and
# MonthlyReportTests 14 to campaigns-12 (461 s). rest about 1042 -> 786 s.
classes_of() {
  case "$1" in
    campaigns-1) echo "ServiceRepeatingPropertyTests" ;;
    campaigns-2) echo "ServicePropertyTests VerticalRailwayPropertyTests NetworkSectionPropertyTests SingleTrackCapacityPropertyTests TurnbackPropertyTests" ;;
    campaigns-3) echo "LineDispatchPropertyTests ScheduledOvertakeTrackLastPropertyTests" ;;
    campaigns-4) echo "OccupiedRoutingPropertyTests ContinuousTrackPropertyTests PassengerPropertyTests KernelDifferentialTests DeadlockPropertyTests" ;;
    campaigns-5) echo "ScheduledTrafficPropertyTests ScheduledOvertakeTrackPropertyTests" ;;
    campaigns-6) echo "SaveMutationSecondHalfTests EconomyPropertyTests" ;;
    campaigns-7) echo "LinePatternPropertyTests SaveMutationTests" ;;
    campaigns-8) echo "LineRoutePreferencePropertyTests NetworkServicePropertyTests TimetablePropertyTests ScheduledOvertakeTrackMiddlePropertyTests ScreenshotSceneTests NewGameBalanceTests" ;;
    campaigns-9) echo "EconomySecondHalfPropertyTests GoldenScenarioTests" ;;
    campaigns-10) echo "ScheduledOvertakeTrackFinalPropertyTests PassengerPlanKeyTests ReservationShortcutTests" ;;
    campaigns-11) echo "ScheduledTrafficSecondHalfPropertyTests HighSpeedDemoTests" ;;
    campaigns-12) echo "TrafficControlPropertyTests RealWorldDemoGroundTests RealWorldDataLoadTests MonthlyReportTests" ;;
    campaigns-13) echo "BoardingPropertyTests" ;;
    campaigns-14) echo "ServiceLinePropertyTests OnboardingTests LineLossFixesTests" ;;
    campaigns-15) echo "TrafficFollowingPropertyTests RealWorldDemoTests NewGameSavePropertyTests" ;;
    *) return 1 ;;
  esac
}
CAMPAIGN_SHARDS=(campaigns-1 campaigns-2 campaigns-3 campaigns-4 campaigns-5 campaigns-6 campaigns-7 campaigns-8 campaigns-9 campaigns-10 campaigns-11 campaigns-12 campaigns-13 campaigns-14 campaigns-15)
SHARDS=("${CAMPAIGN_SHARDS[@]}" rest)

WORK=""
trap '[[ -z "$WORK" ]] || rm -rf "$WORK"' EXIT

die() {
  echo "::error::$*"
  exit 1
}

# `\.(A|B)/` for the class names "A B": anchored on both sides, so a class
# named like a prefix of another (ServiceLineTests, ServiceLinePropertyTests)
# is never caught by accident. The same regex goes to grep and to SwiftPM.
pattern_for() {
  local names
  IFS=' ' read -r -a names <<<"$1"
  local IFS='|'
  echo "\\.(${names[*]})/"
}

all_campaign_classes() {
  local shard
  for shard in "${CAMPAIGN_SHARDS[@]}"; do
    classes_of "$shard"
  done
}

is_shard() {
  local shard
  [[ "$1" != selected || -n "${SELECTED_TESTS:-}" ]] || return 1
  for shard in "${SHARDS[@]}" all selected; do
    [[ "$shard" == "$1" ]] && return 0
  done
  return 1
}

# The regex for SELECTED_TESTS: `^Module\.` for `Module.*`, `\.Class/` for
# a class.
selected_pattern() {
  local word words modules=() classes=() parts=()
  read -r -a words <<<"${SELECTED_TESTS:-}"
  for word in "${words[@]}"; do
    if [[ "$word" == *.\* ]]; then modules+=("${word%.\*}"); else classes+=("$word"); fi
  done
  [[ ${#modules[@]} -eq 0 ]] || parts+=("^($(IFS='|'; echo "${modules[*]}"))\\.")
  [[ ${#classes[@]} -eq 0 ]] || parts+=("$(pattern_for "${classes[*]}")")
  local IFS='|'
  echo "${parts[*]}"
}

# With SELECTED_PART=k/n, the test IDs on stdin of the k-th of n parts: the
# classes, sorted by name, dealt out in turn (a class stays in one part).
selected_part() {
  local part="${SELECTED_PART:-1/1}"
  [[ "$part" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ && "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ]] ||
    die "SELECTED_PART '$part' is not k/n."
  sort | awk -v k="${BASH_REMATCH[1]}" -v n="${BASH_REMATCH[2]}" '
    { split($0, id, "/"); if (id[1] != last) { index_ = index_ + 1; last = id[1] } }
    (index_ - 1) % n == k - 1'
}

# The test IDs shard $1 selects from the list file $2.
select_ids() {
  case "$1" in
    all) cat "$2" ;;
    selected) grep -E "$(selected_pattern)" "$2" | selected_part || true ;;
    rest) grep -v -E "$(pattern_for "$(all_campaign_classes | tr '\n' ' ')")" "$2" || true ;;
    *) grep -E "$(pattern_for "$(classes_of "$1")")" "$2" || true ;;
  esac
}

# The classes of shard $1's selection from the list file $2, in batches, one
# line of class names each. SwiftPM hands a test runner the IDs a `swift test`
# selects as one comma-separated argument, and Linux refuses an argument
# longer than 128 KiB ("Argument list too long"): `rest` went past it at 1,656
# tests. So a shard runs one `swift test --filter` per batch, each selecting
# at most SWIFT_SHARD_BATCH_CHARS characters of test IDs (a class bigger than
# that is a batch of its own).
batch_classes() {
  select_ids "$1" "$2" | awk -v limit="${SWIFT_SHARD_BATCH_CHARS:-60000}" '
    {
      split($0, id, "/"); split(id[1], name, ".")
      if (!(name[2] in size)) order[++count] = name[2]
      size[name[2]] += length($0) + 1
    }
    END {
      for (i = 1; i <= count; i++) {
        class = order[i]
        if (used > 0 && used + size[class] > limit) { print line; line = ""; used = 0 }
        line = (line == "" ? class : line " " class)
        used += size[class]
      }
      if (line != "") print line
    }'
}

# Module.Class/method  ->  Class.method, the name XCTest prints while running.
to_xctest_names() {
  sed -E 's#^[^.]+\.([^/]+)/(.*)$#\1.\2#'
}

# Fail unless the named campaign classes exist once each and the shard
# selections split the list exactly (no test twice, none missing).
check_partition() {
  local list="$1" shard class n
  local seen=" "
  for shard in "${CAMPAIGN_SHARDS[@]}"; do
    for class in $(classes_of "$shard"); do
      [[ "$seen" != *" $class "* ]] || die "$class is named in two shards; name it in one."
      seen+="$class "
      n=$(grep -c -E "\\.$class/" "$list" || true)
      [[ "$n" -gt 0 ]] || die "$class (shard $shard) has no tests: it was renamed or removed. Update classes_of in .github/scripts/swift-shards.sh."
    done
  done
  local combined="$WORK/combined.txt"
  : >"$combined"
  for shard in "${SHARDS[@]}"; do
    select_ids "$shard" "$list" >>"$combined"
  done
  if ! diff <(sort "$list") <(sort "$combined") >/dev/null; then
    echo "The shards do not split the test list exactly (< in the package, > selected):"
    diff <(sort "$list") <(sort "$combined") | head -20 || true
    die "Shard selections overlap or miss tests."
  fi
}

run_shard() {
  local shard="$1"
  is_shard "$shard" || die "Unknown shard '$shard'. Shards: ${SHARDS[*]} all."
  WORK="$(mktemp -d)"
  local list="$WORK/list.txt" log="$WORK/test.log"

  # shellcheck disable=SC2086 # SWIFT_EXTRA_ARGS is a word list on purpose
  if [[ -n "${SWIFT_TEST_LIST_FILE:-}" ]]; then
    cp "$SWIFT_TEST_LIST_FILE" "$list"
  else
    swift test list --skip-build ${SWIFT_EXTRA_ARGS:-} >"$list"
  fi
  local bad
  bad="$(grep -v -E '^[A-Za-z0-9_]+\.[A-Za-z0-9_]+/[A-Za-z0-9_]+$' "$list" || true)"
  [[ -z "$bad" ]] || die "Test IDs this script cannot follow (only XCTest's Module.Class/method): $(echo "$bad" | head -3 | tr '\n' ' ')"
  [[ -s "$list" ]] || die "swift test list printed no tests."
  local total
  total="$(wc -l <"$list" | tr -d ' ')"

  check_partition "$list"
  if [[ "$shard" == selected ]]; then
    local word words
    read -r -a words <<<"$SELECTED_TESTS"
    for word in "${words[@]}"; do
      if [[ "$word" == *.\* ]]; then
        grep -q -E "^${word%.\*}\\." "$list" || die "Module ${word%.\*} has no tests."
      else
        grep -q -E "\\.$word/" "$list" || die "$word has no tests: the class was not found (renamed, or not an XCTestCase)."
      fi
    done
  fi

  local expected="$WORK/expected.txt"
  select_ids "$shard" "$list" | to_xctest_names | sort >"$expected"
  local expected_count
  expected_count="$(wc -l <"$expected" | tr -d ' ')"
  [[ "$expected_count" -gt 0 ]] || die "Shard $shard selects no tests."
  echo "Shard $shard: $expected_count of $total tests in the package."

  local batches="$WORK/batches.txt" classes batch_rc started rc=0
  batch_classes "$shard" "$list" >"$batches"
  echo "Shard $shard: $(wc -l <"$batches" | tr -d ' ') swift test runs."
  : >"$log"
  started="$(date +%s)"
  # A failed batch does not stop the others; the shard fails after them.
  while IFS= read -r -u 3 classes; do
    batch_rc=0
    # shellcheck disable=SC2086
    swift test --skip-build ${SWIFT_EXTRA_ARGS:-} --filter "$(pattern_for "$classes")" 2>&1 | tee -a "$log" || batch_rc=${PIPESTATUS[0]}
    [[ "$batch_rc" -eq 0 ]] || rc=$batch_rc
  done 3<"$batches"
  local seconds=$(($(date +%s) - started))

  local executed="$WORK/executed.txt"
  sed -n -E "s/^Test Case '([^']+)' started.*/\\1/p" "$log" | sort >"$executed"
  local executed_count failed_count
  executed_count="$(wc -l <"$executed" | tr -d ' ')"
  failed_count="$(grep -c -E "^Test Case '.*' failed" "$log" || true)"

  echo "::group::Coverage check for shard $shard"
  echo "selected $expected_count, executed $executed_count, failed $failed_count, swift test exit code $rc, ${seconds}s"
  local problems=0
  if ! diff "$expected" "$executed" >"$WORK/diff.txt"; then
    echo "The tests that ran are not the tests the shard selects (< missing, > unexpected):"
    head -40 "$WORK/diff.txt"
    problems=1
  fi
  echo "Slowest classes:"
  sed -n -E "s/^Test Case '([^.']+)\\.[^']*' passed \\(([0-9.]+) seconds\\)/\\2 \\1/p" "$log" |
    awk '{ t[$2] += $1 } END { for (c in t) printf "%8.1fs  %s\n", t[c], c }' | sort -rn | head -5
  echo "::endgroup::"

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### Shard \`$shard\`"
      echo "- selected **$expected_count** of $total tests; executed **$executed_count**; failed **$failed_count**; ${seconds}s"
      if [[ "$shard" == selected ]]; then
        echo "- tests: $SELECTED_TESTS"
      elif [[ "$shard" != rest && "$shard" != all ]]; then
        echo "- classes: $(classes_of "$shard")"
      fi
    } >>"$GITHUB_STEP_SUMMARY"
  fi

  [[ "$rc" -eq 0 ]] || die "swift test failed in shard $shard (exit code $rc)."
  [[ "$failed_count" -eq 0 ]] || die "$failed_count tests failed in shard $shard."
  [[ "$problems" -eq 0 ]] || die "Shard $shard did not run exactly the tests it selects."
  echo "Shard $shard: all $executed_count selected tests ran and passed."
}

# true when a changed path can change what the package builds or tests.
relevant_paths() {
  local path
  while IFS= read -r path; do
    case "$path" in
      Package.swift | Package.resolved | Sources/* | Tests/* | GoldenScenarios/* | SaveFixtures/* | ReplayFixtures/*) echo true; return ;;
      # The package's tests read the app's bundled data (the real-world
      # grids, the railways and their timetables, the licences).
      RailwayGameApp/Resources/*) echo true; return ;;
      .github/workflows/ci.yml | .github/scripts/swift-shards.sh | .github/scripts/swift-shards-selftest.sh) echo true; return ;;
      # A tool's file a test reads (the tourism catalogue, the railways'
      # OSM exceptions).
      tools/*) if grep -rqF -- "$path" Tests 2>/dev/null; then echo true; return; fi ;;
    esac
  done
  echo false
}

# The commit a push to main is compared with: the head of the newest
# successful push run of ci.yml on main, when it is an ancestor of HEAD.
# Pushes to main share one concurrency group in ci.yml, so a run that waits
# is replaced by a newer one and its commit never gets a run of its own;
# comparing with the commit main was at before the push would then miss what
# the replaced commits changed. Comparing with the last success also keeps
# testing after a red run: a later commit that changes only docs does not
# turn main green over an untested change. Prints nothing (and a warning on
# stderr) when no such commit can be found, so the caller tests everything.
# Needs `gh` with a token that can read Actions (GH_TOKEN) and GITHUB_REPOSITORY.
push_base() {
  local head runs sha
  head="$(git rev-parse HEAD)" || { echo "::warning::Cannot read HEAD." >&2; return 0; }
  if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
    echo "::warning::GITHUB_REPOSITORY is not set; cannot look up the last successful run." >&2
    return 0
  fi
  if ! runs="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?branch=main&event=push&status=success&per_page=20" \
    --jq '.workflow_runs[].head_sha')"; then
    echo "::warning::Could not list the successful push runs of ci.yml." >&2
    return 0
  fi
  # A successful run of this very commit (a re-run) is no base for it.
  sha="$(grep -v -x -F "$head" <<<"$runs" | head -n 1 || true)"
  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::warning::No successful push run of ci.yml on main found." >&2
    return 0
  fi
  if ! git cat-file -e "$sha^{commit}" 2>/dev/null &&
    ! git fetch --no-tags --filter=blob:none origin "$sha" >&2; then
    echo "::warning::Cannot fetch $sha, the head of the last successful push run." >&2
    return 0
  fi
  if ! git merge-base --is-ancestor "$sha" "$head"; then
    echo "::warning::$sha, the head of the last successful push run, is not an ancestor of $head." >&2
    return 0
  fi
  echo "$sha"
}

# ---------------------------------------------------------------------------
# Pull request tiers (decision 185). A push to main and a manual run test
# everything; a pull request runs what its changed files can affect:
#
#   full          every shard. Anything GameCore is built from or tested
#                 with: Sources/GameCore, Package.swift and Package.resolved,
#                 the CI scripts and ci.yml, any other Sources/ or Tests/
#                 directory, a deleted or renamed test file, and a GameCore
#                 test file that other test files use (single_owner_classes).
#   presentation  every GamePresentationTests test: Sources/GamePresentation,
#                 Tests/GamePresentationTests, and RailwayGameApp/Resources
#                 (the app's bundled data, which only those tests read). No
#                 GameCore test can see GamePresentation.
#   fixtures      the test classes that read GoldenScenarios/, SaveFixtures/
#                 or ReplayFixtures/ (fixture_readers), for a change there.
#   tests-only    the XCTestCase classes a changed GameCore test file
#                 declares, when no other test file uses it.
#   none          nothing the package builds or tests (the app's code, docs,
#                 tools, other workflows): the Swift jobs are skipped.
#
# A pull request's tier is its largest file's. Below full, the tests of every
# file are run together (the union), so a pull request that changes
# GamePresentation and adds a GameCore test runs both; nothing a changed file
# selects is dropped. A pull request labelled `full-ci` runs everything
# (ci.yml reads the label).
#
# The test files are read as text, not compiled: a top-level declaration is
# one that starts in column 0, the style of every test file here. Anything
# the reading cannot follow counts as shared, which means full.

TIERS=(none tests-only fixtures presentation full)

tier_rank() {
  local i
  for i in "${!TIERS[@]}"; do
    [[ "${TIERS[$i]}" == "$1" ]] && { echo "$i"; return; }
  done
  die "Unknown tier '$1'."
}

# A Swift file's lines without comments (a `//` line, a `*` line of a block
# comment, a ` // ` comment at the end of a line), so that a name in a
# comment is not a use.
code_lines() {
  if [[ -n "${CODE_CACHE:-}" && -f "$CODE_CACHE/$1" ]]; then
    cat "$CODE_CACHE/$1"
  else
    grep -v -E '^[[:space:]]*(//|/\*|\*)' "$1" | sed -E 's#[[:space:]]//.*$##' || true
  fi
}

# Every test file's code_lines, once, under $CODE_CACHE (the same paths).
CODE_CACHE=""
code_cache() {
  [[ -z "$CODE_CACHE" ]] || return 0
  [[ -n "$WORK" ]] || WORK="$(mktemp -d)"
  local file
  mkdir -p "$WORK/code"
  for file in Tests/*/*.swift; do
    [[ -f "$file" ]] || continue
    mkdir -p "$WORK/code/${file%/*}"
    code_lines "$file" >"$WORK/code/$file"
  done
  CODE_CACHE="$WORK/code"
}

# What a test file declares at the top level, one per line:
#   test <Class>   an XCTestCase subclass
#   name <Name>    a type, function or constant, or a member of an extension
#                  of a type from elsewhere, that another file could use by
#                  name
#   opaque         something whose uses cannot be found by a name: a class
#                  that is not directly an XCTestCase (it may be a test), an
#                  init, subscript, operator or conformance added to a type
#                  from elsewhere, or a line this reading does not know
# private and fileprivate declarations (and private extensions) are the
# file's own and are not listed; neither is an extension of a type the file
# declares, whose uses name that type.
swift_declarations() {
  code_lines "$1" | awk '
    function strip_attributes(s) {
      while (s ~ /^@[A-Za-z_]+(\([^)]*\))?[ \t]+/) sub(/^@[A-Za-z_]+(\([^)]*\))?[ \t]+/, "", s)
      return s
    }
    function identifier(s) { match(s, /^[A-Za-z_][A-Za-z0-9_]*/); return substr(s, RSTART, RLENGTH) }
    function top(s) {
      s = strip_attributes(s)
      sub(/^((public|internal|open|final|nonisolated|private|fileprivate)[ \t]+)*/, "", s)
      return s
    }
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (line[i] !~ /^[A-Za-z@]/) continue
        s = top(line[i])
        if (match(s, /^(struct|enum|class|actor|protocol|typealias)[ \t]+/)) own[identifier(substr(s, RLENGTH + 1))] = 1
      }
      extension = 0
      for (i = 1; i <= NR; i++) {
        l = line[i]
        if (l ~ /^[A-Za-z@#]/) {
          extension = 0
          s = strip_attributes(l)
          if (s ~ /^@[A-Za-z_]+(\([^)]*\))?[ \t]*$/ || s ~ /^#/) continue   # an attribute line, #if
          if (s ~ /^(@testable[ \t]+)?import[ \t]/) continue
          if (s ~ /^(private|fileprivate)[ \t]/) continue
          sub(/^((public|internal|open|final|nonisolated)[ \t]+)*/, "", s)
          if (s ~ /^class[ \t]/) {
            sub(/^class[ \t]+/, "", s)
            name = identifier(s)
            if (name != "" && substr(s, length(name) + 1) ~ /^[ \t]*:[ \t]*XCTestCase([ \t{,]|$)/) print "test " name
            else print "opaque"
            continue
          }
          if (s ~ /^extension[ \t]/) {
            sub(/^extension[ \t]+/, "", s)
            name = identifier(s)
            if (name in own) continue
            if (substr(s, length(name) + 1) ~ /^[ \t]*:/) print "opaque"   # a conformance is used without a name
            extension = 1
            continue
          }
          if (match(s, /^(struct|enum|actor|protocol|typealias|func|let|var)[ \t]+/)) {
            name = identifier(substr(s, RLENGTH + 1))
            print (name == "" ? "opaque" : "name " name)
            continue
          }
          print "opaque"
          continue
        }
        if (extension && l ~ /^    [A-Za-z@]/) {
          s = strip_attributes(substr(l, 5))
          if (s ~ /^@[A-Za-z_]+(\([^)]*\))?[ \t]*$/) continue
          if (s ~ /^(private|fileprivate)[ \t]/) continue
          sub(/^((public|internal|static|class|mutating|nonmutating|override|nonisolated|final|convenience|required|lazy)[ \t]+)*/, "", s)
          if (s ~ /^(init|subscript)([ \t(<?!]|$)/) { print "opaque"; continue }
          if (match(s, /^(func|var|let|case|struct|enum|class|typealias)[ \t]+/)) {
            name = identifier(substr(s, RLENGTH + 1))
            print (name == "" ? "opaque" : "name " name)   # an operator has no identifier
          }
        }
      }
    }
  '
}

# The names test file $1 declares that another file could use: its test
# classes (a static generator another campaign calls) and its other
# declarations. Fails if one cannot be followed by name.
usable_names() {
  local declarations
  declarations="$(swift_declarations "$1")"
  ! grep -q -x opaque <<<"$declarations" || return 1
  sed -n -E 's/^(test|name) //p' <<<"$declarations" | sort -u
}

# The other test files of $1's module whose code names one of names $2 (one
# per line).
users_of() {
  local file="$1" names="$2" other
  [[ -n "$names" ]] || return 0
  code_cache
  grep -l -w -F -f <(printf '%s\n' "$names") "$CODE_CACHE/${file%/*}"/*.swift 2>/dev/null |
    while IFS= read -r other; do
      other="${other#"$CODE_CACHE/"}"
      [[ "$other" == "$file" ]] || echo "$other"
    done
}

# The test classes of test file $1 if no other file can use what it
# declares; fails otherwise (a helper, or a class another file calls).
single_owner_classes() {
  local file="$1" names tests
  names="$(usable_names "$file")" || return 1
  tests="$(swift_declarations "$file" | sed -n 's/^test //p')"
  [[ -n "$tests" ]] || return 1
  [[ -z "$(users_of "$file" "$names")" ]] || return 1
  echo $tests
}

# The top-level declarations of the test files in directory $1 whose code
# mentions token $2 (a whole word, or with $3 = text, any text), one per line
# as "<file>|<declaration>", the declaration as swift_declarations prints it;
# a mention inside an extension of a type from elsewhere is `opaque` (which
# of its members uses it is not followed). Reads code_cache.
containers_of() {
  local dir="$1" token="$2" mode="${3:-word}"
  grep -l -F -e "$token" "$CODE_CACHE/$dir"/*.swift 2>/dev/null | xargs -r awk -v token="$token" -v mode="$mode" -v cache="$CODE_CACHE/" '
    function strip_attributes(s) {
      while (s ~ /^@[A-Za-z_]+(\([^)]*\))?[ \t]+/) sub(/^@[A-Za-z_]+(\([^)]*\))?[ \t]+/, "", s)
      return s
    }
    function identifier(s) { match(s, /^[A-Za-z_][A-Za-z0-9_]*/); return substr(s, RSTART, RLENGTH) }
    function mentions(l,   at, before, after) {
      if (mode == "text") return index(l, token) > 0
      while ((at = index(l, token)) > 0) {
        before = at == 1 ? "" : substr(l, at - 1, 1)
        after = substr(l, at + length(token), 1)
        if (before !~ /[A-Za-z0-9_]/ && after !~ /[A-Za-z0-9_]/) return 1
        l = substr(l, at + length(token))
      }
      return 0
    }
    function file_done(   i, l, s, rest, name, current, n) {
      split("", own); split("", printed)
      for (i = 1; i <= count; i++) {
        if (line[i] !~ /^[A-Za-z@]/) continue
        s = strip_attributes(line[i])
        sub(/^((public|internal|open|final|nonisolated|private|fileprivate)[ \t]+)*/, "", s)
        if (match(s, /^(struct|enum|class|actor|protocol|typealias)[ \t]+/)) own[identifier(substr(s, RLENGTH + 1))] = 1
      }
      n = substr(file, length(cache) + 1)
      current = ""
      for (i = 1; i <= count; i++) {
        l = line[i]
        if (l ~ /^[A-Za-z@]/) {
          s = strip_attributes(l)
          if (s !~ /^@[A-Za-z_]+(\([^)]*\))?[ \t]*$/ && s !~ /^(@testable[ \t]+)?import[ \t]/) {
            sub(/^((public|internal|open|final|nonisolated|private|fileprivate)[ \t]+)*/, "", s)
            current = "opaque"
            if (match(s, /^class[ \t]+/)) {
              rest = substr(s, RLENGTH + 1); name = identifier(rest)
              if (name != "") current = (substr(rest, length(name) + 1) ~ /^[ \t]*:[ \t]*XCTestCase([ \t{,]|$)/ ? "test " : "name ") name
            } else if (match(s, /^extension[ \t]+/)) {
              name = identifier(substr(s, RLENGTH + 1))
              if (name in own) current = "name " name
            } else if (match(s, /^(struct|enum|actor|protocol|typealias|func|let|var)[ \t]+/)) {
              name = identifier(substr(s, RLENGTH + 1))
              if (name != "") current = "name " name
            }
          }
        }
        if (current != "" && mentions(l) && !(current in printed)) { printed[current] = 1; print n "|" current }
      }
    }
    FNR == 1 && NR > 1 { file_done() }
    FNR == 1 { file = FILENAME; count = 0 }
    { line[++count] = $0 }
    END { if (NR > 0) file_done() }
  '
}

# The test classes that can read fixture directory $1 (GoldenScenarios,
# SaveFixtures or ReplayFixtures): those whose code names it, and those that
# use, by name, a declaration that names it or uses one that does, and so on
# (a loader such as GoldenScenarioFixtures, a `SavedGameTests.fixtures`
# another class reads through). Followed at the granularity of top-level
# declarations, within each test module. Fails if a mention is somewhere
# this cannot follow.
fixture_readers() {
  local dir="$1" file module entry kind name
  local -a queue=() classes=()
  local seen=" "
  code_cache
  for module in Tests/*/; do
    module="${module%/}"
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      queue+=("$module|${entry#*|}")
    done < <(containers_of "$module" "$dir" text)
  done
  local i=0
  while [[ $i -lt ${#queue[@]} ]]; do
    entry="${queue[$i]}"
    i=$((i + 1))
    module="${entry%%|*}"
    entry="${entry#*|}"
    [[ "$entry" != opaque ]] || return 1
    kind="${entry%% *}"
    name="${entry#* }"
    [[ "$seen" != *" $module:$name "* ]] || continue
    seen+="$module:$name "
    [[ "$kind" != test ]] || classes+=("$name")
    while IFS= read -r entry; do
      [[ -n "$entry" ]] || continue
      queue+=("$module|${entry#*|}")
    done < <(containers_of "$module" "$name")
  done
  printf '%s\n' "${classes[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# The tier of one changed path, and the tests it selects below full:
# prints "<tier>[ <test>...]".
path_plan() {
  local path="$1" classes dir
  case "$path" in
    Package.swift | Package.resolved | Sources/GameCore/* | .github/scripts/* | .github/workflows/ci.yml)
      echo full ;;
    Sources/GamePresentation/* | Tests/GamePresentationTests/*)
      echo "presentation GamePresentationTests.*" ;;
    RailwayGameApp/Resources/*)
      # Only the GamePresentation tests read the app's bundled data; if a
      # GameCore test ever does, this is full.
      if grep -l -F 'RailwayGameApp' Tests/GameCoreTests/*.swift 2>/dev/null | while read -r f; do code_lines "$f"; done | grep -q -F 'RailwayGameApp'; then
        echo full
      else
        echo "presentation GamePresentationTests.*"
      fi ;;
    GoldenScenarios/* | SaveFixtures/* | ReplayFixtures/*)
      dir="${path%%/*}"
      if [[ -z "${FIXTURE_PLANS[$dir]:-}" ]]; then
        if classes="$(fixture_readers "$dir")" && [[ -n "$classes" ]]; then
          FIXTURE_PLANS[$dir]="fixtures $classes"
        else
          FIXTURE_PLANS[$dir]=full
        fi
      fi
      echo "${FIXTURE_PLANS[$dir]}" ;;
    Tests/GameCoreTests/*.swift)
      if [[ -f "$path" ]] && classes="$(single_owner_classes "$path")"; then
        echo "tests-only $classes"
      else
        echo full
      fi ;;
    Sources/* | Tests/*)
      echo full ;;
    tools/*)
      # Most of tools/ is only run by hand, but a test may read a tool's
      # file (TourismSessionTests the tourism catalogue, RealRailwaysTests
      # the railways' OSM exceptions): those tests' module then runs.
      if grep -rlF -- "$path" Tests 2>/dev/null | grep -qv '^Tests/GamePresentationTests/'; then
        echo full
      elif grep -rqF -- "$path" Tests/GamePresentationTests 2>/dev/null; then
        echo "presentation GamePresentationTests.*"
      else
        echo none
      fi ;;
    *)
      echo none ;;
  esac
}

# A pull request's plan from its changed files on stdin, read in the
# repository root:
#   tier=<tier>
#   tests=<what `selected` runs (SELECTED_TESTS); empty for full and none>
#   parts=<how many jobs share it (SELECTED_PART)>
# with one line per file on stderr: its tier and why.
declare -A FIXTURE_PLANS=()
PRESENTATION_PARTS=3
pr_plan() {
  local path line tier rank best=0 tests="" edited="" plans
  code_cache
  plans="$WORK/plans.txt"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    path_plan "$path" >"$plans"
    line="$(cat "$plans")"
    tier="${line%% *}"
    echo "  $path: $line" >&2
    rank="$(tier_rank "$tier")"
    [[ "$rank" -le "$best" ]] || best="$rank"
    [[ "$line" != *" "* ]] || tests+=" ${line#* }"
    [[ "$tier" != tests-only ]] || edited+=" ${line#* }"
  done
  tier="${TIERS[$best]}"
  local parts=1
  if [[ "$tier" == full || "$tier" == none ]]; then
    tests=""
  else
    tests="$(tr ' ' '\n' <<<"$tests" | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/ $//')"
    # All the GamePresentation tests take longer than the rest of a partial
    # tier (452 s of tests locally on 2026-10-12, up to about 1.8 times that
    # on a slow runner, after a build of about 5 minutes); PRESENTATION_PARTS
    # jobs share them (selected_part), so a job stays near 10 minutes.
    [[ " $tests " != *" GamePresentationTests.* "* ]] || parts="$PRESENTATION_PARTS"
    # An edited campaign file's class can take most of a job's 20 minutes
    # on its own (ServiceRepeatingPropertyTests 792 s of tests); two of
    # them, or one beside a part of the GamePresentation tests, would share
    # a job and reach the limit (ScheduledTrafficPropertyTests.swift
    # declares six campaigns, about 30 minutes of tests in one job). Those
    # run every shard, where each campaign has its own place. The fixtures'
    # readers are measured as they are (the golden scenarios' three
    # campaigns, about 370 s).
    local campaigns=0 class
    for class in $(all_campaign_classes); do
      [[ " $edited " != *" $class "* ]] || campaigns=$((campaigns + 1))
    done
    if [[ "$campaigns" -ge 2 || ( "$campaigns" -ge 1 && "$parts" -gt 1 ) ]]; then
      echo "  Edited campaign classes ($campaigns) would share a job: every shard runs." >&2
      tier=full
      tests=""
      parts=1
    fi
  fi
  echo "tier=$tier"
  echo "tests=$tests"
  echo "parts=$parts"
}

# What ci.yml's change detection decides, from the event and what it found:
#   EVENT    push, pull_request or workflow_dispatch
#   LISTED   true when the changed files (on stdin) could be listed
#   LABELS   the pull request's labels, separated by spaces or new lines
# Prints swift=<true|false>, tier=<tier> and matrix=<JSON> for $GITHUB_OUTPUT
# (and the tests and tier on stderr). A push to main and a manual run are
# full whenever the Swift jobs run; only a pull request has a smaller tier,
# and only when its files were listed and it is not labelled full-ci.
ci_decide() {
  local files swift=true tier=full matrix plan tests parts k sep
  files="$(cat)"
  matrix="$("$0" matrix)"
  if [[ "${LISTED:-false}" == true ]]; then
    swift="$(relevant_paths <<<"$files")"
    if [[ "${EVENT:-}" == pull_request ]]; then
      if [[ " $(tr '\n' ' ' <<<"${LABELS:-}") " == *" full-ci "* ]]; then
        echo "Label full-ci: every shard runs." >&2
        swift=true
      elif plan="$("$0" plan <<<"$files")"; then
        tier="$(sed -n 's/^tier=//p' <<<"$plan")"
        tests="$(sed -n 's/^tests=//p' <<<"$plan")"
        parts="$(sed -n 's/^parts=//p' <<<"$plan")"
        case "$tier" in
          full) swift=true ;;
          none) swift=false ;;
          tests-only | fixtures | presentation)
            swift=true
            [[ "$tests" =~ ^[A-Za-z0-9_.*\ ]+$ && "$parts" =~ ^[1-9][0-9]*$ ]] || die "Bad plan: tests '$tests', parts '$parts'."
            echo "Tests: $tests" >&2
            matrix='{"include":['
            sep=""
            for ((k = 1; k <= parts; k++)); do
              matrix+="$sep{\"shard\":\"selected$([[ "$parts" -eq 1 ]] || echo "-$k")\",\"tests\":\"$tests\",\"part\":\"$k/$parts\"}"
              sep=","
            done
            matrix+=']}' ;;
          *) die "Unknown tier '$tier' from plan." ;;
        esac
      else
        echo "::warning::Could not plan the pull request's tier; running every shard." >&2
        tier=full
        swift=true
      fi
    fi
  fi
  [[ "$swift" == true ]] || tier=none
  echo "swift=$swift"
  echo "tier=$tier"
  echo "matrix=$matrix"
}

# The gate's verdict ("Swift CI (gate)", the check main's branch rule
# requires), from the jobs' results:
#   CHANGES       the change detection's result
#   SWIFT_NEEDED  its swift output
#   TIER          its tier output
#   CURRENT       the Swift jobs' combined result (failure if any job failed,
#                 cancelled if any was cancelled, skipped if none ran)
# Passes only when the detection succeeded and either every Swift job of the
# tier succeeded or none was needed and none ran.
ci_gate() {
  echo "changes: ${CHANGES:-}; Swift needed: ${SWIFT_NEEDED:-}; tier: ${TIER:-}; Swift 6.4: ${CURRENT:-}"
  [[ "${CHANGES:-}" == success ]] || die "The change detection did not succeed (${CHANGES:-no result})."
  if [[ "${SWIFT_NEEDED:-}" == true ]]; then
    [[ "${CURRENT:-}" == success ]] || die "A Swift job of tier ${TIER:-?} did not succeed (Swift 6.4: ${CURRENT:-no result})."
    echo "Every Swift 6.4 job of tier ${TIER:-?} passed."
  elif [[ "${SWIFT_NEEDED:-}" == false ]]; then
    [[ "${CURRENT:-}" == skipped ]] || die "The Swift jobs were not needed but did not skip (Swift 6.4: ${CURRENT:-no result})."
    echo "No file that can change the Swift package changed; the Swift jobs were skipped."
  else
    die "The change detection said neither that the Swift jobs are needed nor that they are not ('${SWIFT_NEEDED:-}')."
  fi
}

case "${1:-}" in
  run)
    [[ $# -eq 2 ]] || die "usage: $0 run <shard>"
    run_shard "$2"
    ;;
  select)
    [[ $# -eq 2 && -n "${SWIFT_TEST_LIST_FILE:-}" ]] || die "usage: SWIFT_TEST_LIST_FILE=<list> $0 select <shard>"
    is_shard "$2" || die "Unknown shard '$2'."
    select_ids "$2" "$SWIFT_TEST_LIST_FILE"
    ;;
  shards)
    printf '%s\n' "${SHARDS[@]}"
    ;;
  classes)
    all_campaign_classes | tr ' ' '\n'
    ;;
  matrix)
    printf '{"include":['
    sep=""
    for shard in "${SHARDS[@]}"; do
      printf '%s{"shard":"%s"}' "$sep" "$shard"
      sep=","
    done
    printf ']}\n'
    ;;
  relevant)
    relevant_paths
    ;;
  push-base)
    push_base
    ;;
  plan)
    pr_plan
    ;;
  decide)
    ci_decide
    ;;
  gate)
    ci_gate
    ;;
  *)
    die "usage: $0 run <shard> | select <shard> | shards | classes | matrix | relevant | push-base | plan | decide | gate"
    ;;
esac
