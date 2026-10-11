#!/usr/bin/env bash
# The Swift package's test selections for ci.yml, and a proof that each one ran
# exactly the tests it was meant to run.
#
#   swift-shards.sh run <shard>      run one shard after `swift build --build-tests`
#   swift-shards.sh select <shard>   print the test IDs a shard selects (offline)
#   swift-shards.sh shards           print the shard names, one per line
#   swift-shards.sh classes          print every class the campaign shards name
#   swift-shards.sh matrix           print them as the JSON matrix ci.yml uses
#   swift-shards.sh relevant         read changed file names on stdin; print
#                                    true if any can change the package's tests
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
classes_of() {
  case "$1" in
    campaigns-1) echo "ServiceRepeatingPropertyTests" ;;
    campaigns-2) echo "ServicePropertyTests VerticalRailwayPropertyTests NetworkSectionPropertyTests SingleTrackCapacityPropertyTests TurnbackPropertyTests" ;;
    campaigns-3) echo "LineDispatchPropertyTests ScheduledOvertakeTrackLastPropertyTests" ;;
    campaigns-4) echo "OccupiedRoutingPropertyTests ContinuousTrackPropertyTests PassengerPropertyTests KernelDifferentialTests DeadlockPropertyTests" ;;
    campaigns-5) echo "ScheduledTrafficPropertyTests ScheduledOvertakeTrackPropertyTests" ;;
    campaigns-6) echo "SaveMutationSecondHalfTests EconomyPropertyTests" ;;
    campaigns-7) echo "LinePatternPropertyTests SaveMutationTests" ;;
    campaigns-8) echo "LineRoutePreferencePropertyTests NetworkServicePropertyTests TimetablePropertyTests ScheduledOvertakeTrackMiddlePropertyTests" ;;
    campaigns-9) echo "EconomySecondHalfPropertyTests GoldenScenarioTests" ;;
    campaigns-10) echo "ScheduledOvertakeTrackFinalPropertyTests PassengerPlanKeyTests" ;;
    campaigns-11) echo "ScheduledTrafficSecondHalfPropertyTests" ;;
    campaigns-12) echo "TrafficControlPropertyTests" ;;
    campaigns-13) echo "BoardingPropertyTests" ;;
    campaigns-14) echo "ServiceLinePropertyTests" ;;
    campaigns-15) echo "TrafficFollowingPropertyTests" ;;
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
  for shard in "${SHARDS[@]}" all; do
    [[ "$shard" == "$1" ]] && return 0
  done
  return 1
}

# The test IDs shard $1 selects from the list file $2.
select_ids() {
  case "$1" in
    all) cat "$2" ;;
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
      if [[ "$shard" != rest && "$shard" != all ]]; then
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
    esac
  done
  echo false
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
  *)
    die "usage: $0 run <shard> | select <shard> | shards | classes | matrix | relevant"
    ;;
esac
