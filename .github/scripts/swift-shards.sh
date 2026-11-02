#!/usr/bin/env bash
# The Swift package's test selections for ci.yml, and a proof that each one ran
# exactly the tests it was meant to run.
#
#   swift-shards.sh build            `swift build --build-tests -Xswiftc
#                                    -warnings-as-errors`, once more when
#                                    swift-build itself crashes (build_package)
#                                    (CI_BUILD_CACHE=restored: a build from
#                                    the cache that fails is built again
#                                    from nothing, decision 545)
#   swift-shards.sh stamp            set every tracked file's modification
#                                    time from .build's source stamps, so a
#                                    build restored from the cache recompiles
#                                    exactly the changed files (decision 545;
#                                    CI only: it rewrites the checkout's times)
#   swift-shards.sh pack <file>      pack .build into <file> (tar, gzip -1)
#   swift-shards.sh unpack <file>    unpack it where it was built (decision
#                                    411, shared build)
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
#   swift-shards.sh head-full-run    print a successful full ci.yml run of
#                                    HEAD (head_full_run below), or nothing
#   swift-shards.sh gate             the "Swift CI (gate)" verdict
#   swift-shards.sh ios-gate         a pull request's gate waits for its
#                                    iOS App Build run (ios_gate below)
#   swift-shards.sh superseded       whether a cancelled pull request run was
#                                    replaced by a newer push (superseded)
#
# Shards (a test ID is `Module.Class/method`, as `swift test list` prints it):
#   campaigns-1 .. campaigns-13   the long property, differential and mutation
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
# 2026-10-14: campaigns-14 had become the slowest shard (784 s of tests on
# run 38524235458: ServiceLinePropertyTests 480, LineLossFixesTests 231,
# OnboardingTests 72) while campaigns-3, -5 and -9 took 6 to 6.5 minutes.
# Seconds of tests, the slower of runs 38524235458 and 38521807996:
#   campaigns-14  784 -> 552   LineLossFixesTests (231) to campaigns-5
#   campaigns-5   361 -> 592   ScheduledTraffic 219, ScheduledOvertakeTrack
#                              142, LineLossFixes 231
#   campaigns-6   735 -> 450   EconomyPropertyTests (285) to campaigns-3
#   campaigns-3   405 -> 692   LineDispatch 339, ScheduledOvertakeTrackLast
#                              68, Economy 285
# campaigns-9 (EconomySecondHalfPropertyTests 323, GoldenScenarioTests 281)
# was the other place for EconomyPropertyTests, but would have reached 889.
# The slowest shards are now rest (865) and campaigns-1 (801), unchanged.
# LineLossFixesTests is being made faster (about 30 s); campaigns-5 then
# drops to about 390.
# 2026-10-14, later: on a slow runner campaigns-3 took 1000 s of tests
# (run 38533025112: LineDispatchPropertyTests 590, not 339; Economy 284,
# ScheduledOvertakeTrackLast 125), its job about 19.6 of its 20 minutes.
# LineDispatch alone swings from 322 to 590, so it keeps no large class
# beside it: EconomyPropertyTests moves on to campaigns-12 (TrafficControl
# 476 at most; 508 to 524 s of tests in all), about 800 s with it.
# #571 made LineLossFixesTests about 38 s (231 before): campaigns-5 about
# 450 s. campaigns-1, ServiceRepeatingPropertyTests alone, took up to 802 s
# of tests (run 38521807996) and timed #571's first run out on a slow
# runner. Its campaign now runs as two halves (cases 0 to 14 and 15 to 29
# of every seed): the first stays in campaigns-1 (about 400 s), the second,
# ServiceRepeatingSecondHalfPropertyTests, joins campaigns-6
# (SaveMutationSecondHalfTests 272 to 450 s), about 850 s at most.
# 2026-10-14, later still: rest took 15:45 to 17:01 of tests (1013 s of
# classes in run 38617840641) and, with a 4:25 build on a slow runner, ran
# out of its 20 minutes on main (run 38615317464). Four of its larger
# GameCore classes move to the shortest shards: WorldStateMachineTests (66 s)
# and IdleTrainDeadlockTests (48 s) to campaigns-1 (4:46 to 6:25 of tests),
# ScheduledTrafficTests (45 s) and TurnbackTests (32 s) to campaigns-14
# (5:32 to 7:44); rest drops to about 820 s. FlexDispatchPropertyTests
# (160 s) stays: the self-test's plans use it as a class no campaign names.
# 2026-10-14, after #627: campaigns-6 (SaveMutationSecondHalf 478,
# ServiceRepeatingSecondHalf 395) took up to 873 s of tests and 1060 s of job
# (run 38634945104), campaigns-12 up to 810 s and rest up to 836 s, all
# within three minutes of the limit once the build (up to 2.3 minutes) and
# the job's start are added. Rebalanced on the slowest time of each class in
# the five full runs of main 38634945104, 38634446023, 38631310379,
# 38625192268 and 38615317464 (a shard's sum of those maxima: what a slow
# runner takes for all of it). No shard goes over 715 s (12 minutes), and
# the two halves of each split campaign stay in different shards:
#   campaigns-1   ServiceRepeating 390, ScheduledTraffic 260, WSM 65      715
#   campaigns-2   Service 398, VerticalRailway 217, NetworkSection 50,
#                 SingleTrackCapacity 24 (TurnbackProperty to -13)       690
#   campaigns-3   LineDispatch 602, IdleTrainDeadlock 48,
#                 LineRoutePreference 24 (no large class beside it)       675
#   campaigns-4   unchanged                                               672
#   campaigns-5   SaveMutationSecondHalf 478, ScheduledOvertakeTrack 165,
#                 LineLossFixes 31                                        674
#   campaigns-6   ServiceRepeatingSecondHalf 395, Economy 288             683
#   campaigns-7   LinePattern 401, NetworkService 289                     689
#   campaigns-8   GoldenScenario 333, ScheduledOvertakeTrackMiddle 175,
#                 Timetable 168, NewGameBalance 17, ScreenshotScene 14    708
#   campaigns-9   SaveMutation 359, EconomySecondHalf 350                 708
#   campaigns-10  PassengerPlanKey 405, ReservationShortcut 154, and from
#                 rest NetworkPostcard 63, StationCommerceCard 18,
#                 LineLossDiagnosis 13                                    653
#   campaigns-11  unchanged                                               711
#   campaigns-12  TrafficControl 475, ScheduledOvertakeTrackFinal 177,
#                 the three small GamePresentation classes 47             699
#   campaigns-13  Boarding 624, TurnbackProperty 33                       657
#   campaigns-14  ServiceLine 487, Onboarding 77, CommandLog 59 (from
#                 rest), ScheduledTrafficTests 46, Turnback 32            701
#   campaigns-15  TrafficFollowing 434, ScheduledOvertakeTrackLast 128,
#                 NewGameSave 87, RealWorldDemo 56                        705
#   rest          the other classes                                       703
# The classes taken from rest are GamePresentation's, whose files run the
# presentation tier wherever their class runs, so no pull request's tier
# changes.
# 2026-10-15 (ARCHITECTURE decision 228): the high-speed demo's real day
# runs minute by minute (so no two sets on one edge go unseen) and keeps
# its sets apart, which takes a debug build about 480 s locally for the day
# where it took 140 (main's HighSpeedDemoTests 567 s locally, 443 on CI:
# about 0.78). The day's tests move to a class of their own,
# HighSpeedDemoDayTests, with the demo built and opened again for it: about
# 660 s locally, some 520 on CI. No shard has room for that (each is about
# 700 s), so it is a shard of its own, campaigns-16: one job more. What
# stays of HighSpeedDemoTests in campaigns-11 is about 530 s locally,
# some 415 on CI, as before.
# Later (the #647–#684 review, decision 228 later): a minute moved in one
# go now moves the trains second by second where a set may be held up, as
# sixty one-second steps do (decision 37): HighSpeedDemoDayTests takes
# about 760 s locally where it took 401, TRADemoDayTests 185 where it took
# 162 (CI runs these about as fast as a local debug build: 395 and 164 on
# main's #684 run). Together they passed campaigns-16's 20 minutes (run
# 38822987126). TRADemoDayTests went to campaigns-12 first: its job took
# 18m11s of 20 (run 38825240720), so it goes to campaigns-8, the shortest
# job on that run (9m07s); campaigns-16 keeps the high-speed day alone
# (its job 16m59s).
# On main after #687 (run 38830182218, against #684's 38813149430) the
# longest jobs were campaigns-11 16m58s and campaigns-16 16m57s, past the
# 15m47s of rest before it. Each train's way is now kept while the trains
# move a second (decision 228 later), some 12% off both demos' days, and
# HighSpeedDemoBatchTests goes to campaigns-14 (9m09s on that run), where
# it opens the demo for itself (about a minute). On this branch's run
# (38845130413) campaigns-8 took 18m33s with TRADemoDayTests (186 s of its
# 923), so the TRA day goes to campaigns-12, the lightest shard by
# CLASS_WEIGHTS (about 620 s; a single run's job times swing by minutes). HighSpeedDemoBatchTests, which checks
# that, opens the same demo as HighSpeedDemoTests, so it goes with it to
# campaigns-11 (8m42s with it on run 38822987126).
# 2026-10-16 (the #685–#711 review): after decision 248 (#702) the
# high-speed day is fast again, and campaigns-16 the shortest job (median
# 9.8 min of main's last ten full push runs, 38856199600–38878358538),
# while campaigns-12 ended last in nine of them (median 17.8: its test step
# 14.4, TRADemoDayTests 2.8 of it) and campaigns-14 next (16.6,
# HighSpeedDemoBatchTests 1.5). Both demo classes go to campaigns-16 (about
# 14 min with them); rest (15.7) is then the longest.
# 2026-10-19 (ARCHITECTURE decision 283): the high-speed demo is built over
# the ground at its real structures, about three times as many edges.
# Local debug, each class alone, main fa1e360 against the branch:
# HighSpeedDemoTests 334.6 -> about 517 s, HighSpeedDemoDayTests 240.1 ->
# 443.6, HighSpeedDemoBatchTests 88.6 -> 196.2; TRADemoDayTests 113.9 ->
# 115.8 (unchanged). CI ran main's HighSpeedDemoTests and
# HighSpeedDemoBatchTests about 1.24 times as long as this machine
# (CLASS_WEIGHTS 415 and 110), so their weights are the branch's times
# times 1.24 (HighSpeedDemoDayTests' 780 was from before decision 248).
# campaigns-16 would then hold some 1,150 s of tests (the day and the batch
# test share one build of the demo, so a little less), so
# FlexDispatchPropertyTests (161) goes to campaigns-10, the lightest
# (about 650).
# 2026-10-21: rest timed out on main 4a9685b (run 39603500311): a slow
# runner took its tests about 1.34 times as long as #912's run of the same
# classes (746 s there, past 958 s and unfinished at the 20 minutes on
# main), and a fast runner's rest job was already 12m40s (c841882). Eight
# GamePresentation classes leave rest for the three shortest jobs of
# c841882's run (campaigns-9 8m39s, campaigns-2 9m07s, campaigns-10
# 9m36s); seconds of tests on #912's run (job 119249810901):
#   campaigns-2   RealLineAcquisition 38, Map3DOpenEveryStart 17, Lesson 13
#   campaigns-9   NightSkip 40, Policy 18
#   campaigns-10  RealRailwayTracing 31, Map3DStreetLife 14, Map3D 11
# Rest loses about 182 s (some 245 on a slow runner). These are
# GamePresentation's, so no pull request's tier changes (see 2026-10-14).
# 2026-10-23 (decision 368): two new GamePresentation classes,
# Map3DSceneMemoryTests (it opens the high-speed demo and builds the 3D
# scene round Banqiao: 154 s locally, about 190 on CI) and
# Map3DCoarseChunkTests (26 s locally), go to campaigns-13, the shortest
# job of main eb251ee's run 39889912827 (9 min, 5.6 of tests), not to rest
# (19 min of its 20 on that run). The memory test sat in HighSpeedDemoTests
# first and timed #1070's selected-3 out (run 39894227203); a class of its
# own is dealt by its weight.
# 2026-10-23 (decision 364): rest timed out at its 20 minutes twice on
# #1065's run 39907268084, its tests still passing when cut off. That pull
# request adds LongLegReplayTests' three hours without a deadlock (13 s
# locally) and LoopLineBoardingTests (15 s), both in rest. They go to
# campaigns-11, the shortest job of that run (10.5 min).
# 2026-10-23, later: rest reached the 20-minute limit again on main 43852fa
# (run 39906598034: cancelled after 15.9 minutes of tests; the re-run's
# rest job 19m54s, 953 s of tests for 3526 tests in 469 classes), where
# ffb3ee8's rest took 11 minutes on a fast runner. No class dominates: the
# five slowest took 172 s, the 440 classes under 6 s about 400. So 33
# classes of 6 s or more leave rest for the four shortest jobs of that run
# (campaigns-16 4.8, -7 5.9, -15 6.5, -12 6.6 minutes of tests): every
# GamePresentation class of 6 s or more, whose file runs the presentation
# tier wherever its class runs, and the four GameCore classes over 25 s
# (LocalPass 59, LineAccounts 33, CityRequests 28, LoadJourneyCache 27).
# The smaller GameCore classes stay, as a class a campaign shard names
# counts as an edited campaign in pr_plan; AchievementsTests and
# TrainSessionPropertyTests stay as the self-test's ordinary classes.
# Seconds of tests on that run, dealt heaviest first to the lightest shard
# (the classes in the order they were dealt):
#   campaigns-16  288 -> about 467 (LocalPass, LineAccounts, LoadJourney-
#                 Cache, NewsSession, DemoAt, Map3DNextDeparture,
#                 TutorialSession, Map3DSign, Map3DProps)
#   campaigns-7   354 -> about 474 (CityRequests, DemoRealLines,
#                 Map3DSurface, SeededStreetPlan, Map3DBuildings,
#                 AutoService, Map3DHandoff, Map3DDetail, Map3DNightAndGround)
#   campaigns-15  390 -> about 476 (Map3DStreaming, Map3DRealBuildings,
#                 MetroStructures, NewGameCampaign, PingxiChallenge,
#                 RealWorldExpansion, Map3DShadow, ShortTurnCard)
#   campaigns-12  396 -> about 470 (Map3DStreets, LineConfirmation,
#                 FreightSession, Map3DRealGround, SparseCityLand,
#                 LinePanelMemo, Map3DStationKit)
#   rest          953 -> about 490
# On this change's first run (39919727863) rest took 510 s of tests (its
# classes as fast as on 43852fa's run: TrafficSpeedTests 17.9 s there, 17.1
# here), but campaigns-7's own two campaigns took 603 s (LinePattern 337,
# NetworkService 266) where they had taken 354, and with the nine classes
# 721 s (12.1 minutes). So those nine go on to the two shards that were
# short on both runs: CityRequests and DemoRealLines to campaigns-6 (8.2
# and 5.9 minutes of tests), the seven Map3D and street classes (about
# 66 s) to campaigns-16 (6.3 minutes with its first nine). Rest is some 11
# minutes on a runner 1.34 times slower (see 2026-10-21); the longest job
# stays campaigns-10 (13.6 and 13.8 minutes of tests on the two runs).
# 2026-10-23, after #1087: on main 4d2c8ce's run 39932184002 campaigns-10's
# job took 19.0 minutes (891 s of tests), campaigns-11 812 s and
# campaigns-15 793 s. Every runner can be some 1.9 times slower than
# another on the same classes (campaigns-1 384 s there, 738 on 43852fa's),
# so a shard's room is read from its longest run, not that one. Only
# GamePresentation classes move (no pull request's tier changes);
# FlexDispatchPropertyTests (GameCore, in the self-test) stays. Seconds of
# tests on 39932184002, the destination's at its longest run:
#   campaigns-3   552 -> about 675 (TRADemo 123, from -11)
#   campaigns-4   684 -> about 733 (RealWorldDemo 49, from -15)
#   campaigns-6   660 -> about 725 (Map3DStreetLife, StationCommerceCard,
#                 Map3D, LineLossDiagnosis: about 65, from -10)
#   campaigns-13  666 -> about 725 (RealRailwayTracing 36 from -10,
#                 Map3DStreaming 23 from -15)
#   rest          510 -> about 661 (NetworkPostcard 61 from -10,
#                 NewGameSaveProperty 90 from -15)
#   campaigns-10  891 -> about 729; -11 812 -> about 690; -15 793 -> 632
# campaigns-1, -2 and -14 (12.3 to 13.5 minutes of tests on their longest
# runs) take nothing.
# 2026-10-24: rest timed out on main 82fffc7 (run 40081281220): 15m03s of
# tests, 458 classes passed (868 s) and 26 small ones (TransferGroupSession
# to Zoning, some 30 s) not reached, after a 4m17s build. A new class,
# Map3DPlatformClearanceTests (113 s), had landed in rest. campaigns-13 took
# 19m16s of its 20 (825 s of tests: BoardingProperty 421 and
# Map3DSceneMemoryTests 274, whose weight said 57; #1070's runs had 258).
# The shortest jobs' test steps on that run: campaigns-3 393 s (left alone:
# LineDispatchPropertyTests swings 322 to 602), campaigns-1 397, -11 412,
# -12 434, -4 434, -8 440. Five GamePresentation classes move (no pull
# request's tier changes), seconds on that run:
#   campaigns-11  412 -> about 686 (Map3DSceneMemory 274, from -13)
#   campaigns-1   397 -> about 510 (Map3DPlatformClearance 113, from rest)
#   campaigns-4   434 -> about 526 (NewGameSaveProperty 92, from rest)
#   campaigns-12  434 -> about 498 (NetworkPostcard 64, from rest)
#   campaigns-8   440 -> about 500 (LessonGuide 60, from rest)
#   rest          some 900 -> about 570; campaigns-13 825 -> about 551
# The longest jobs are then campaigns-2 (749 s of tests) and -10 (745).
# 2026-10-24, later: #1184's full run (40083863654) passed, but on slow
# runners (every build over 4 minutes) six jobs took 18m42s to 19m31s, and
# all 17 shards together held 11,712 s of tests, about 650 s a shard if
# spread over 18. So campaigns-17, one job more (a full tier is 20 jobs;
# game planning's call, decision 404). Seconds of tests on that run, and
# where a class's slower run elsewhere was longer, that one:
#   campaigns-17  new: ScheduledOvertakeTrackFinal 168 and five small
#                 GamePresentation classes 103 (from -12), Timetable 169
#                 (from -8), Map3DSceneMemory 156 (274 on main's run, from
#                 -11): about 596, 714 at the slower
#   campaigns-12  857 -> about 586
#   campaigns-8   827 -> about 658
#   campaigns-11  838 -> about 682
#   campaigns-4   818 -> about 652 (OccupiedRouting 78 to -13,
#                 NewGameSaveProperty 88 to rest)
#   campaigns-2   831 -> about 627 (VerticalRailway 204 to -10)
#   campaigns-1   819 -> about 656 (Map3DPlatformClearance 101 and
#                 WorldStateMachine 62 to -15)
#   campaigns-10  432 -> about 636; -13 559 -> about 637; -15 469 ->
#                 about 632; rest 559 -> about 647
# The longest shard is then about 690 s of tests, some 16.5 minutes of job
# with a 4.5-minute build. Campaign classes moved only between campaign
# shards, so no pull request's tier changes.
# That PR's own full run (40085496377, builds about 4m15s) put campaigns-15
# at 815 s of tests (18m46s of job: TrafficFollowing 440 there), -14 at
# 737, -17 at 734, -5 at 712 and -16 at 706, while -1 had 362, -11 402,
# -7 419, -4 485 and -9 501. So, by that run's seconds:
#   Map3DPlatformClearance 109, WorldStateMachine 64   -15 -> -11
#   Onboarding 93                                      -14 -> -1
#   Map3DStreets, RealWorldDemoGround, RealWorldDataLoad, Map3DRealGround,
#   MonthlyReport (103 together)                       -17 -> -7
#   LineLossFixes 47                                   -5  -> -4
#   LocalPass 58                                       -16 -> -9
# -15 then about 642, -14 644, -17 631, -5 665, -16 648, -11 575, -1 455,
# -7 522, -4 532, -9 559; the longest are -6 (694) and -3 (676), about
# 16.5 minutes of job.
# The next full run (40087061202) put campaigns-10 past 20 minutes twice
# (over 15 minutes of tests each time). Its classes took 839 s of tests on a
# 4-core Linux machine (PassengerPlanKey 343, ReservationShortcut 209,
# VerticalRailway 194, FlexDispatch 84), not the 596 the fast runner gave, so
# VerticalRailway moved on to -11 (519 to about 575 s before it), and the
# run after that (40090204048) put -11 past 20 minutes in turn while -10
# took 428. The same shard takes up to twice as long on one runner as on
# another, so VerticalRailway goes to -12, the shortest shard on all three
# full runs (593, 423 and 333 s): about 800 at its slowest.
# 2026-10-24, later (decision 405): on #1189's last run (40108236578, slow
# runners, builds up to 4m33s) campaigns-11 took 19m09s of job (852 s of
# tests) and -12 18m31s, and the same class swings up to 1.8 times from one
# run to the next (ServiceRepeating 222 to 397 s), so a shard balanced on
# one run is not balanced on the next. Each shard's seconds of tests were
# summed per run over four full runs (40108236578, 40093112308, 40091661566,
# 40083863654) and the classes dealt out to keep the largest of those sums
# low: with 17 campaign shards the best found was 661 s (about 16 minutes
# of job), with 18 it is 631 s. So campaigns-18, one job more (a full tier
# is 21 jobs). Before and after, the four runs' sums (s):
#   -1  747 426 544 747 -> 573 490 449 600   -10 562 428 414 427 -> 623 626 522 627
#   -2  466 620 626 627 -> 503 612 567 618   -11 843 552 850 844 -> 626 594 585 566
#   -3  656 666 668 666 -> 625 423 525 628   -12 793 784 787 789 -> 625 622 626 631
#   -4  427 692 416 700 -> 606 616 589 617   -13 470 636 481 628 -> 471 624 479 619
#   -5  396 378 387 665 -> 408 359 402 606   -14 626 623 471 634 -> 609 608 466 620
#   -6  394 744 746 743 -> 338 627 577 630   -15 357 628 642 462 -> 398 619 623 564
#   -7  557 744 441 455 -> 627 584 481 593   -16 648 615 625 658 -> 621 588 600 631
#   -8  659 654 466 658 -> 576 600 576 600   -17 644 358 641 492 -> 624 550 605 627
#   -9  733 437 539 733 -> 608 497 546 626   -18 new             -> 605 403 615 616
#   rest 637 421 654 618 -> 550 365 567 530 (NewGameSavePropertyTests, 88 s,
#        back to a campaign shard, -3)
# 30 classes moved, all between campaign shards but that one, so no pull
# request's tier changes. HighSpeedDemoTests (400 s, its fixture built once
# for the class) has -18 with two shorter campaigns; HighSpeedDemoDay and
# HighSpeedDemoBatch stay in -16 with the small GamePresentation classes.
# Its own full run (40111697925) still had -17 at 18m08s (767 s) and -4
# at 17m29s (756 s): classes that were slow on different runs before were
# slow on the same one (PassengerPlanKey 380, Economy 190, Timetable 164).
# So the shards are now dealt on each class's slowest of five runs added
# up, not on one run's sum: 14 more classes moved (-16 and -18 kept as
# they were), and the largest such sum went from 778 to 684 s. With 18
# campaign shards it cannot go much lower (all of them add up to 11,960 s,
# 664 a shard), so about 16 minutes of job is the slow runners' worst.
# 2026-10-25 (decision 411): rest's job took 19m44s on main 647d799 (run
# 40190946365: 859 s of tests) as two new GamePresentation classes landed
# there, DemoRealLinesTrackTests (160 s) and SharedNetworkTests (46 s).
# On each class's slowest of ten full push runs of main (40154741372 to
# 40190946365, decision 411 lists them) the shards add up to 13,106 s, 690
# a shard; eight classes moved (DemoRealLinesTrack and Map3DModel out of
# rest, the rest between campaign shards, so no pull request's tier
# changes) and the largest sum went from 871 s (rest) to 700. A slow
# runner's job is that plus a build of about 5 minutes, some 17.5 minutes;
# one more shard would save only some 35 s. The build, 29% of the Swift
# jobs' time, is the room left (docs/research/CI_SHARED_BUILD_2026-10-25.md).
# 2026-10-28 (decision 400, 10j-3): the Sanying Line's two real days, a
# class for each rule: SanyingLineSimpleDayTests 365 s locally and
# SanyingLineRealisticDayTests 229-243 s (debug, this Linux container;
# about 1.24 times that on CI), too long together for one shard's 20
# minutes. The simple one goes to campaigns-9 and the realistic one to
# campaigns-2, two of the shortest jobs above (8m39s and 9m07s).
# 2026-10-29: rest timed out at 20 minutes on main 6ff5ffe (run
# 40866614287, in ViewingSpeedTests with every earlier test passed); its job
# had taken 12.5, 15.5, 13 and 17.7 minutes on the nights before, as the
# Sanying Line's classes (SanyingDepot 40 s, BusOneWayAndTunnelRealMap 27,
# SanyingLineFreeze 27) and others landed there. On each class's slowest of
# runs 40586990177, 40775591241 and 40866614287 (the last one's rest log was
# lost with the cancel, so the new classes count at the seconds its job
# showed), rest added up to about 907 s (787 s on the nightly 40775591241).
# 20 GamePresentation classes move (no pull request's tier changes), seconds
# of tests on those runs, the destination's before -> after:
#   campaigns-6   578 -> about 698 (SanyingDepot, BusOneWayAndTunnelRealMap,
#                 SanyingLineFreeze, Map3DSceneryProps: 120)
#   campaigns-18  642 -> about 698 (Achievements, RealWorldDemoRoads,
#                 TrainNightLightsReadBack, RealBuses: 56)
#   campaigns-14  652 -> about 698 (Map3DRealTracks, Map3DEMU3000, MapMarks,
#                 Map3DC341Integration, Map3DBoxInstance: 46)
#   campaigns-17  664 -> about 696 (Map3DTaipeiLandmarks, TrainPack,
#                 Map3DParks, Map3DSceneKit: 32)
#   campaigns-1   683 -> about 698 (Map3DTrainLabels, Map3DRealTrains: 15)
#   campaigns-10  683 -> about 690 (Map3DEMU900Integration: 7)
#   rest          907 -> about 631 (787 -> about 511 on the nightly)
# campaigns-2, -4, -5, -7 and -9 were already above 700 on their slowest
# runs (Sanying Line's two real days sit in -2 and -9); they take nothing.
# 2026-10-29 (decision 489): the Danhai Light Rail's real days, a class
# for each pair of lines: DanhaiGreenLineDayTests about 165 s locally and
# DanhaiBothLinesDayTests about 245 s (debug, this Linux container; about
# 1.24 times that on CI), to campaigns-11 and campaigns-13, which have
# taken none of the late additions above; DanhaiDepotTests (some 20 s)
# stays in rest.
# 2026-10-30: those three and LiujiaLineTrainsTests, Map3DBusLayerTests had
# no CLASS_WEIGHTS entry, so a pull request's tier counted them 1 s each and
# put DanhaiBothLinesDayTests beside HighSpeedDemoDayTests: selected-3 hit
# the 20-minute limit on main (run 40925534792) and on #1514 and #1515. The
# weights are CI's times where a run reported them (DanhaiGreenLineDay 107,
# LiujiaLineTrains 108, Map3DBusLayer 65) and 1.24 times the local ones
# otherwise (DanhaiBothLinesDay 245 -> 300, DanhaiDepot 20 -> 25).
# 2026-10-30, later: #1515's six selected jobs (head 738494a) measured
# them again, with the classes of 10 s or more that had no weight or one
# off by a third: RealLineAcquisition 165 -> 290, DanhaiGreenLineDay
# 110 -> 185, Map3DBuses (none) 59, SharedNetwork (none) 47 and others,
# and the ones that ran a third shorter there than their weight said
# (SanyingLineSimpleDay 450 -> 192, SanyingLineRealisticDay 300 -> 226,
# Map3DSceneMemory 310 -> 136, HighSpeedDemoBatch 146 -> 95, TRADemoDay
# 93 -> 59): only the proportions matter, so one run's times keep them in
# step. Dealt into seven parts by these weights, that run's classes come to
# 658 to 738 s each (six parts by the old weights: 493 to 1,026).
# 2026-10-29 (decision 493): the Blue Coast Line, then the Green Mountain
# Line, a class for each rule, some 330 s each locally (debug), about 410 on
# CI: too long together for one shard. On the full run 40917483376 (main
# a0a4ebe, campaigns not reduced) campaigns-12 took 10 minutes and
# campaigns-8 8, so the simple one goes to campaigns-12 and the realistic
# one to campaigns-8 (campaigns-3, at 14 minutes there, would pass 20 with
# about 7 more); weights 1.24 times the local times.
# The same day, for the release's full run: RealLineAcquisitionTests (about
# 290 s) from campaigns-9 to campaigns-7, campaigns-9 having taken 14, 17
# and 19 minutes on the full runs 40866614287, 40910293493 and 40917483376
# and campaigns-7 10 on the last; LiujiaLineTrainsTests (about 108 s) from
# rest to campaigns-13, rest having taken 16 to 19 minutes on those runs and
# campaigns-13 9 (with DanhaiBothLinesDayTests about 14 from now on).
# 2026-10-30: campaigns-13 took 19 minutes on #1519's full tier (run of
# 9d455a3: BoardingPropertyTests 414 s, DanhaiBothLinesDayTests 253,
# LiujiaLineTrainsTests 104 and six more, 1,061 s of tests), one slow
# runner from the job's 20; DanhaiBothLinesDayTests to campaigns-5, 11
# minutes on the full run of a0a4ebe (run 40917483376).
# Decision 495 (2026-10-30): #1521's full tiers cancelled campaigns-7 at 20
# minutes with RealLineAcquisitionTests in it (run 40961584034) and took
# campaigns-14 to 19.7 with it there (run 40965386985): the runners were
# up to 1.7 times slower than on run 40917483376, and every shard holds
# 700 to 1,000 s of tests. So the three classes the real lines added this
# week, RealLineAcquisitionTests (about 290 s), DanhaiBothLinesDayTests
# (about 190 to 250) and LiujiaLineTrainsTests (about 105), get a shard of
# their own, campaigns-19, about 590 s; campaigns-5, -13 and -14 go back to
# 584, 438 and 564 s on run 40917483376. A full tier is 23 jobs.
# 2026-10-31: rest timed out at its 20 minutes three times on #1593's
# run 41181157543 (head 019a9c3) and once on #1599's (b398816), its tests
# still passing when cut off; the script's warning named the slowest
# classes: PassengerCheckOnceTests 81 s, DeadlockSearchCostTests 66 s,
# PassengerRouteSearchTests 35 s. They go to the shortest jobs of #1593's
# run: campaigns-9 (8.5 minutes), campaigns-8 (10.7) and campaigns-18 (11).
# 2026-10-31, later (CIREST): rest still took 958 s of tests on main
# 171cd7b's full run 41187751239 (job 17.5 minutes) and 962 on #1593's
# 41185968556, but its classes added up to only 665 and 669 s: no class
# over 24 s, 595 classes. The other ~290 s were the starts of its six
# swift test runs, 37 s each and up to 73 on those runners (and 37 more
# for swift test list in every shard): SwiftPM lists the tests to apply
# --filter, and GamePresentationTests' runner, listing, makes an instance
# of every test, whose `let pack = Map3DModelPack.standard` (or
# `.unbaked`) built the whole train model pack. 26 such properties in 23
# classes are now computed (`var pack: Map3DModelPack { .standard }`; the
# packs are static, built once a process either way). Locally the listing
# went from 33 s to 0.1 and a swift test start from 35 s to 1.4. The pack is
# now built by the first test that reads it, so those classes (14 of them,
# and Map3DC371C381Tests and Map3DE500Tests, which read it first once the
# others had gone) go together to campaigns-10, and rest builds no pack.
# Then 35 classes were dealt on each class's slower time of the two runs,
# 35 s added for a shard that builds a pack, keeping the split campaigns'
# halves apart and taking only GamePresentation classes from rest (s):
#   shard  before -> after     shard  before -> after
#   -1      715 -> 796          -11     873 -> 796
#   -2      889 -> 796          -12     911 -> 792
#   -3      694 -> 794          -13     718 -> 788
#   -4      863 -> 799          -14     773 -> 798
#   -5      785 -> 796          -15     722 -> 792
#   -6      771 -> 792          -16     754 -> 789
#   -7      845 -> 792          -17     628 -> 799
#   -8      980 -> 791          -18     767 -> 785
#   -9      791 -> 791          -19     661 -> 791
#   -10     637 -> 797          rest    678 -> 592 (and no ~290 s of starts)
# A job is about a minute more than its tests, so some 14.5 minutes on
# those runners at most, rest about 11. Locally (this change, Linux, about
# 1.1 times run 41187751239's times) rest took 652 s of tests in its six
# runs with Map3DC371C381Tests (30 s) and Map3DE500Tests (15 s) still in
# it, campaigns-10 857 s without them. No shard was added; a full tier
# stays 23 jobs.
# 2026-11-01 (run 41318166302, full tier): rest took 18m38s (894 s of tests in
# 600 classes) and campaigns-12 17m23s (952 s); campaigns-1, 3, 4, 6, 9 and 15
# were above 780 s of tests. About 90 s (campaigns) to 220 s (rest) of a shard
# is not test time. A first rebalance (PR 1679, run 41320779892) left
# campaigns-11 at 726 s on a slow runner (LinePatternPropertyTests 362 s
# against 205 s): cancelled at 20 minutes. So the 18 campaigns with a
# measurement were dealt out again by their seconds in run 41318166302, each
# now 664 to 687 s (before: 421 to 952 s), and DemoSightsAndTransfersTests
# 142, AnkengLineTests 74, WeeklyPunctualityTests 30, ReplayFixtureTests 22,
# TrafficSpeedTests 18, LoadTrackCheckIndexTests 17, BusRouteTests 14,
# CityGrowthTests 14 and TownGrowthTests 12 left rest (894 s to about 550 s).
# campaigns-19 (no measurement in that run) is unchanged. Twenty shards
# cannot hold every shard under 15 minutes on a runner 1.8 times slower: the
# next step is another shard (decision 495's way).
# 2026-11-02 (decision 544, continued): with GameCore and GameCoreTests
# built -O on Linux, the whole package's tests fell from about 14,500 s to
# 3,500-3,900 s, and every weight above was a debug time: on the full tiers
# of runs 41370019390, 41374181013 and 41376957404 rest took 8.6, 6.8 and
# 8.7 minutes, campaigns-9 and -12 as little as 2.5. Each job also spends
# about 95 s before its tests (container, checkout, download and unpacking
# of the build, `swift test list`) and about 26 s to start each `swift
# test` batch. So the shards went from 19 campaigns to 13: every class of
# 2 s or more (176, the slowest of its three times in those runs, 3,985 s
# together) was dealt out heaviest first to the lightest shard, about 307 s
# each, with no other rule (the old rules kept halves of a split campaign
# apart and pack readers together; with about 300 s a shard neither moves
# the slowest job by more than half a minute). rest keeps the 551 smaller
# classes (160 s of tests, more in starts) and anything added later. A job
# should take about 7 minutes on top of the build, and a full tier is 17
# jobs.
classes_of() {
  case "$1" in
    campaigns-1) echo "Map3DSceneMemoryTests KernelDifferentialTests ScheduledOvertakeTrackLastPropertyTests BusReadAheadTests RoadDrawRealMapTests NightSkipTests RoadsTurnOnTests CityRequestsTests TraceDragCostTests BusRouteTests" ;;
    campaigns-2) echo "SaveMutationSecondHalfTests Map3DBuildingsTests Map3DSurfaceTests Map3DRealBuildingsTests ScheduledOvertakeTrackMiddlePropertyTests VerticalRailwayPropertyTests OnboardingTests Map3DChuKuangPassengerTests Map3DPPIntegrationTests Map3DStationsTests SingleTrackCapacityPropertyTests PolicyTests PingxiChallengeTests" ;;
    campaigns-3) echo "Map3DBusesTests DemoRealLinesTrackTests ScheduledTrafficSecondHalfPropertyTests Map3DBoxInstanceTests EconomySecondHalfPropertyTests Map3DPropsTests RealWorldDataLoadTests FlexDispatchPropertyTests Map3DC341Tests LessonGuideTests RealRoadCellsTests RealWorldExpansionTests Map3DTEMU2000Tests CityGrowthTests" ;;
    campaigns-4) echo "Map3DBusLayerTests NetworkServicePropertyTests TrafficFollowingPropertyTests Map3DRealTracksTests Map3DC341IntegrationTests TRADemoTests Map3DSignTests RealBusesTests NetworkSectionPropertyTests Map3DEMU500Tests RealWorldDemoRoadsTests Map3DRoadBridgeTests CoverageGridTests Map3DLandmarksTests" ;;
    campaigns-5) echo "Map3DModelTests GoldenScenarioTests Map3DDetailTests SeededStreetPlanTests DemoSightsAndTransfersTests DeadlockPropertyTests Map3DBreezyBlueIntegrationTests Map3DTaichungGreenTests Map3DTaipeiLandmarksTests PassengerRouteSearchTests SanyingLineFreezeTests RealLineOfferPreparingTests Map3DEstateKitTests RealLineStockTests" ;;
    campaigns-6) echo "RealLineAcquisitionTests Map3DTests DanhaiBlueThenGreenSimpleDayTests Map3DStreetsTests EconomyPropertyTests DanhaiGreenLineDayTests NewGameSavePropertyTests MetroStructuresTests FrameTimeBenchTests Map3DTrainLabelsTests TurnbackTests WeeklyPunctualityTests Map3DLotGroundTests Map3DEMU800Tests" ;;
    campaigns-7) echo "HighSpeedDemoTests Map3DStreetLifeTests Map3DBuildReturnTests HighSpeedDemoBatchTests Map3DTrainSetTests Map3DNextDepartureTests DanhaiDepotTests Map3DC371C381Tests ScreenshotSceneTests DemoRealLinesTests WorldStateMachineTests ReplayFixtureTests Map3DMeshSimplifierTests TraceOverlapTests" ;;
    campaigns-8) echo "LineDispatchPropertyTests BoardingPropertyTests ReservationShortcutTests Map3DFrontageTests Map3DSceneryPropsTests ScheduledOvertakeTrackFinalPropertyTests AnkengLineTests LocalPassTests OccupiedRoutingPropertyTests Map3DEMU900IntegrationTests BusRoadsRealMapTests LineAccountsTests LessonTests LoopLineBoardingTests" ;;
    campaigns-9) echo "SaveMutationTests Map3DPlatformClearanceTests ScheduledTrafficPropertyTests DanhaiBothLinesDayTests SanyingLineRealisticDayTests RealRailwayTracingTests ContinuousTrackPropertyTests DeadlockSearchCostTests LineLossFixesTests NetworkPostcardTests LoadJourneyCacheTests WaterGridTests BusStopLabelsRealMapTests Map3DTrainShapeRefreshTests" ;;
    campaigns-10) echo "ServiceLinePropertyTests ServiceRepeatingSecondHalfPropertyTests BusOneWayAndTunnelRealMapTests PassengerPlanKeyTests Map3DTEMU1000Tests ScheduledOvertakeTrackPropertyTests TRADemoDayTests CommandLogTests RealWorldDemoTests ScheduledTrafficTests SparseCityLandTests WholeTaiwanTests Map3DFreightTrainTests Map3DKaohsiungLightRailTests" ;;
    campaigns-11) echo "LiujiaLineTrainsTests Map3DCoarseChunkTests SanyingLineSimpleDayTests Map3DRealTrainsTests Map3DEMU800IntegrationTests TimetablePropertyTests Map3DTourismEMU500Tests Map3DShadowTests Map3DEMU3000Tests Map3DStationKitTests SharedNetworkTests LineRoutePreferencePropertyTests MoneyTextSourceTests" ;;
    campaigns-12) echo "ServicePropertyTests TrafficControlPropertyTests HighSpeedDemoDayTests Map3DParksTests DanhaiBlueThenGreenRealisticDayTests Map3DRealGroundTests Map3DHandoffTests PassengerPropertyTests RealWorldDemoGroundTests Map3DSceneKitTests Map3DEMU900Tests LandImportTests Map3DTrainMaterialTests OneRowPerGameTests" ;;
    campaigns-13) echo "ServiceRepeatingPropertyTests LinePatternPropertyTests PassengerCheckOnceTests Map3DTrainOcclusionTests Map3DStreamingTests Map3DChuKuangIntegrationTests Map3DNightAndGroundTests Map3DOpenEveryStartTests IdleTrainDeadlockTests SanyingDepotTests TurnbackPropertyTests TrafficSpeedTests SavedGameTests NewGameBalanceTests" ;;
    *) return 1 ;;
  esac
}
CAMPAIGN_SHARDS=(campaigns-1 campaigns-2 campaigns-3 campaigns-4 campaigns-5 campaigns-6 campaigns-7 campaigns-8 campaigns-9 campaigns-10 campaigns-11 campaigns-12 campaigns-13)
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
  local classes
  IFS=' ' read -r -a classes <<<"$1"
  local IFS='|'
  echo "\\.(${classes[*]})/"
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
  local word words modules=() classes=() alternatives=()
  read -r -a words <<<"${SELECTED_TESTS:-}"
  for word in "${words[@]}"; do
    if [[ "$word" == *.\* ]]; then modules+=("${word%.\*}"); else classes+=("$word"); fi
  done
  [[ ${#modules[@]} -eq 0 ]] || alternatives+=("^($(IFS='|'; echo "${modules[*]}"))\\.")
  [[ ${#classes[@]} -eq 0 ]] || alternatives+=("$(pattern_for "${classes[*]}")")
  local IFS='|'
  echo "${alternatives[*]}"
}

# Seconds of tests per class, for dealing a selection out into parts
# (selected_part): every class that took 2 s or more, the slowest of its
# three times in the full-tier runs 41370019390, 41374181013 and
# 41376957404 (2026-11-02, the first with GameCore and GameCoreTests built
# -O, decision 544 continued),
# rounded; heaviest first. A partial tier is not only GamePresentation's
# classes, as a fixture directory or an edited test file adds GameCore
# ones, so both modules are listed. Any other class counts
# CLASS_WEIGHT_DEFAULT (the 551 classes under 2 s took 0.3 s each on
# average). Only the proportions matter: a stale or missing weight moves a
# class to another part, never out of the selection. The debug weights
# before (decisions 404, 405 and the 2026-10-23 measurement) are in this
# file's history.
CLASS_WEIGHTS="Map3DSceneMemoryTests:226 SaveMutationSecondHalfTests:111
  Map3DBusesTests:91 Map3DBusLayerTests:84 Map3DModelTests:82
  RealLineAcquisitionTests:80 HighSpeedDemoTests:78
  LineDispatchPropertyTests:78 SaveMutationTests:74
  ServiceLinePropertyTests:74 LiujiaLineTrainsTests:70
  ServicePropertyTests:70 ServiceRepeatingPropertyTests:66
  LinePatternPropertyTests:62 Map3DCoarseChunkTests:62
  TrafficControlPropertyTests:62 ServiceRepeatingSecondHalfPropertyTests:61
  Map3DPlatformClearanceTests:59 BoardingPropertyTests:56
  Map3DStreetLifeTests:50 Map3DTests:46 GoldenScenarioTests:44
  NetworkServicePropertyTests:42 DemoRealLinesTrackTests:41
  Map3DBuildingsTests:40 DanhaiBlueThenGreenSimpleDayTests:40
  Map3DDetailTests:40 TrafficFollowingPropertyTests:40
  Map3DBuildReturnTests:39 PassengerCheckOnceTests:37
  HighSpeedDemoDayTests:37 SanyingLineSimpleDayTests:37
  ScheduledTrafficSecondHalfPropertyTests:36 ReservationShortcutTests:36
  ScheduledTrafficPropertyTests:36 BusOneWayAndTunnelRealMapTests:36
  Map3DSurfaceTests:36 Map3DStreetsTests:36 Map3DTrainOcclusionTests:35
  SeededStreetPlanTests:34 Map3DRealTracksTests:34 HighSpeedDemoBatchTests:33
  Map3DBoxInstanceTests:33 Map3DParksTests:32 Map3DRealTrainsTests:32
  DanhaiBothLinesDayTests:32 Map3DFrontageTests:32 PassengerPlanKeyTests:32
  Map3DRealBuildingsTests:32 DemoSightsAndTransfersTests:31
  Map3DC341IntegrationTests:31 Map3DTrainSetTests:30 Map3DStreamingTests:30
  DanhaiBlueThenGreenRealisticDayTests:30 Map3DEMU800IntegrationTests:29
  EconomySecondHalfPropertyTests:29 EconomyPropertyTests:29
  SanyingLineRealisticDayTests:28 Map3DSceneryPropsTests:26
  Map3DTEMU1000Tests:26 ScheduledOvertakeTrackMiddlePropertyTests:24
  KernelDifferentialTests:24 ScheduledOvertakeTrackFinalPropertyTests:23
  ScheduledOvertakeTrackPropertyTests:22 Map3DPropsTests:22
  DanhaiGreenLineDayTests:21 TimetablePropertyTests:20
  Map3DRealGroundTests:20 RealRailwayTracingTests:20
  Map3DChuKuangIntegrationTests:19 Map3DNextDepartureTests:19 TRADemoTests:19
  DeadlockPropertyTests:19 VerticalRailwayPropertyTests:18
  ScheduledOvertakeTrackLastPropertyTests:17 Map3DNightAndGroundTests:17
  Map3DBreezyBlueIntegrationTests:17 Map3DSignTests:17 DanhaiDepotTests:16
  ContinuousTrackPropertyTests:15 Map3DHandoffTests:15
  Map3DTourismEMU500Tests:14 NewGameSavePropertyTests:14 AnkengLineTests:13
  RealWorldDataLoadTests:13 TRADemoDayTests:13 OnboardingTests:13
  Map3DShadowTests:12 MetroStructuresTests:12 CommandLogTests:11
  FlexDispatchPropertyTests:11 LocalPassTests:11 DeadlockSearchCostTests:11
  Map3DC371C381Tests:11 PassengerPropertyTests:11 BusReadAheadTests:11
  Map3DOpenEveryStartTests:11 RealBusesTests:11 Map3DTaichungGreenTests:10
  Map3DChuKuangPassengerTests:10 Map3DC341Tests:10
  OccupiedRoutingPropertyTests:10 RealWorldDemoTests:9 FrameTimeBenchTests:9
  Map3DEMU3000Tests:9 LineLossFixesTests:9 ScreenshotSceneTests:9
  RealWorldDemoGroundTests:8 Map3DTaipeiLandmarksTests:8
  RoadDrawRealMapTests:8 IdleTrainDeadlockTests:8
  NetworkSectionPropertyTests:8 Map3DPPIntegrationTests:8
  Map3DSceneKitTests:8 SanyingDepotTests:8 Map3DEMU500Tests:8
  Map3DTrainLabelsTests:8 PassengerRouteSearchTests:8 ScheduledTrafficTests:7
  NightSkipTests:7 DemoRealLinesTests:7 Map3DStationKitTests:7
  NetworkPostcardTests:7 Map3DEMU900IntegrationTests:7 LessonGuideTests:7
  Map3DStationsTests:7 WorldStateMachineTests:6 RoadsTurnOnTests:6
  SharedNetworkTests:6 LoadJourneyCacheTests:5 BusRoadsRealMapTests:5
  SparseCityLandTests:5 RealWorldDemoRoadsTests:5 RealRoadCellsTests:5
  TurnbackTests:5 TurnbackPropertyTests:5 SanyingLineFreezeTests:4
  Map3DEMU900Tests:4 RealLineOfferPreparingTests:4 LandImportTests:4
  TrafficSpeedTests:4 RealWorldExpansionTests:4 WeeklyPunctualityTests:4
  LineAccountsTests:4 WaterGridTests:4 WholeTaiwanTests:4
  Map3DRoadBridgeTests:4 LineRoutePreferencePropertyTests:3
  SingleTrackCapacityPropertyTests:3 CityRequestsTests:3 ReplayFixtureTests:3
  Map3DEstateKitTests:3 MoneyTextSourceTests:3 Map3DTrainMaterialTests:3
  CoverageGridTests:3 PolicyTests:3 TraceDragCostTests:3 LessonTests:3
  BusStopLabelsRealMapTests:2 Map3DFreightTrainTests:2 Map3DLotGroundTests:2
  Map3DMeshSimplifierTests:2 Map3DTEMU2000Tests:2 SavedGameTests:2
  Map3DEMU800Tests:2 Map3DTrainShapeRefreshTests:2
  Map3DKaohsiungLightRailTests:2 PingxiChallengeTests:2 TraceOverlapTests:2
  BusRouteTests:2 LoopLineBoardingTests:2 Map3DLandmarksTests:2
  CityGrowthTests:2 NewGameBalanceTests:2 OneRowPerGameTests:2
  RealLineStockTests:2 LongLegReplayTests:2 Map3DWorksKitTests:2
  StationCommerceCardTests:2 DemoAtTests:2 Map3DTaipeiMetro461Tests:2
  NewsSessionTests:2 TrainSessionPropertyTests:2 Map3DTrenchTests:2
  RealTRAScheduleTests:2 TrainTripLogTests:2 AchievementsTests:2
  Map3DSimplifiedCacheTests:2 NewGameCampaignTests:2 LineLossDiagnosisTests:2
  Map3DBreezyBlueTests:2 Map3DFarSets422Tests:2 MonthlyReportTests:2
  ScheduledOvertakeTrackTests:2"
CLASS_WEIGHT_DEFAULT=1

# With SELECTED_PART=k/n, the test IDs on stdin of the k-th of n parts. Each
# class stays in one part; the classes, heaviest first (CLASS_WEIGHTS; ties
# by name), each go to the part with the least weight so far (ties to the
# lowest part). Every part works this out from the same list, so the n parts
# split the selection exactly. Dealing the classes out in turn by name had
# put HighSpeedDemoTests, RealWorldDemoTests and LineLossDiagnosisTests in
# one part: 2.9, 7.2 and 9.6 minutes of tests on run 38525866535.
selected_part() {
  local part="${SELECTED_PART:-1/1}"
  [[ "$part" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ && "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ]] ||
    die "SELECTED_PART '$part' is not k/n."
  sort | awk -v k="${BASH_REMATCH[1]}" -v n="${BASH_REMATCH[2]}" \
    -v weights="$CLASS_WEIGHTS" -v fallback="$CLASS_WEIGHT_DEFAULT" '
    BEGIN {
      count = split(weights, pairs, /[ \n]+/)
      for (i = 1; i <= count; i++) if (split(pairs[i], pair, ":") == 2) weight[pair[1]] = pair[2] + 0
    }
    {
      ids[NR] = $0
      split($0, id, "/"); split(id[1], name, ".")
      class_of[NR] = id[1]
      if (!(id[1] in seen)) {
        seen[id[1]] = 1
        classes[++class_count] = id[1]
        w[id[1]] = (name[2] in weight) ? weight[name[2]] : fallback
      }
    }
    END {
      # Heaviest first, then by name: an insertion sort, as the classes are
      # a few hundred at most.
      for (i = 2; i <= class_count; i++) {
        c = classes[i]
        for (j = i - 1; j >= 1 && (w[classes[j]] < w[c] || (w[classes[j]] == w[c] && classes[j] > c)); j--)
          classes[j + 1] = classes[j]
        classes[j + 1] = c
      }
      for (p = 1; p <= n; p++) load[p] = 0
      for (i = 1; i <= class_count; i++) {
        best = 1
        for (p = 2; p <= n; p++) if (load[p] < load[best]) best = p
        load[best] += w[classes[i]]
        part_of[classes[i]] = best
      }
      for (i = 1; i <= NR; i++) if (part_of[class_of[i]] == k) print ids[i]
    }'
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
# that is a batch of its own). It was 60,000 until 2026-11-02; each batch
# costs about 26 s to start, and rest's 4,334 tests (some 350,000
# characters) took six, so it is 100,000, still 31,000 under the limit.
batch_classes() {
  select_ids "$1" "$2" | awk -v limit="${SWIFT_SHARD_BATCH_CHARS:-100000}" '
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

# A tool that dies of a signal (exit code above 128: 139 is SIGSEGV) is not
# a compile error or a failed test, which exit 1 (decision 329). On main
# b28a790 (run 39682926653, 2026-10-21) swift-build crashed in libdispatch
# (_dispatch_event_loop_drain, signal 11) 19 seconds into planning, before
# it had compiled anything, in one shard of 17; that was 1 of 2,320 shard
# jobs in three days.
killed_by_signal() { (($1 > 128)); }

# The build every Swift job runs, once more when swift-build itself was
# killed by a signal. A compile error exits 1 and is not tried again, and
# neither is a second crash.
build_package() {
  local attempt rc
  for attempt in 1 2; do
    rc=0
    # shellcheck disable=SC2086
    swift build --build-tests -Xswiftc -warnings-as-errors ${SWIFT_EXTRA_ARGS:-} || rc=$?
    ((rc != 0)) || return 0
    if ! killed_by_signal "$rc" || ((attempt == 2)); then
      die "swift build failed (exit code $rc)."
    fi
    echo "::warning::swift build was killed by signal $((rc - 128)) (exit code $rc): the tool crashed, this is not a compile error. Building once more."
  done
}

# Decision 545: ci.yml's swift-build job restores .build from the cache
# (actions/cache) and builds on it. SwiftPM's compiler driver skips a source
# file whose modification time equals the one its build record holds, and a
# checkout sets every file's time to now, so the job first sets each tracked
# file's time from SOURCE_STAMPS, the list the cached build was built from
# (time, blob, path for every file): a file with the same blob (git's hash of
# its contents) gets the time the record holds and is not compiled again; a
# changed or new file gets a time later than every time in the list, so it
# cannot equal any time a record holds and is compiled again, along with
# whatever depends on it (the driver's own dependency tracking). Without a
# list (no cache, or a build from nothing) every file gets STAMP_EPOCH.
# The new list is written into .build, so the cache saved after the build
# carries the times its build record holds. Content decides, not the time a
# commit was made, so no git history is needed.
SOURCE_STAMPS="${SOURCE_STAMPS:-.build/ci-source-stamps}"
STAMP_EPOCH=946684800 # 2000-01-01T00:00:00Z
stamp_sources() {
  local old="" new
  [[ -s "$SOURCE_STAMPS" ]] && old="$SOURCE_STAMPS"
  mkdir -p "$(dirname "$SOURCE_STAMPS")"
  new="$SOURCE_STAMPS.new"
  # Records end in NUL, so any path is safe. Links (120000) and
  # submodules (160000) are left alone: utime would follow the link.
  git ls-files -s -z | perl -0 -e '
    my ($old, $new, $epoch) = @ARGV;
    my (%time, %blob);
    my $latest = $epoch;
    if ($old ne "") {
      open(my $in, "<", $old) or die "cannot read $old: $!";
      local $/ = "\0";
      while (my $r = <$in>) {
        chomp $r;
        my ($t, $b, $p) = split(/ /, $r, 3);
        $time{$p} = $t; $blob{$p} = $b;
        $latest = $t if $t > $latest;
      }
    }
    my $later = $latest + 1;
    open(my $out, ">", $new) or die "cannot write $new: $!";
    my ($same, $changed) = (0, 0);
    local $/ = "\0";
    while (my $r = <STDIN>) {
      chomp $r;
      my ($meta, $p) = split(/\t/, $r, 2);
      my ($mode, $b) = split(/ /, $meta);
      next if $mode eq "120000" || $mode eq "160000";
      my $t;
      if ($old eq "") { $t = $epoch; }
      elsif (exists $blob{$p} && $blob{$p} eq $b) { $t = $time{$p}; $same++; }
      else { $t = $later; $changed++; }
      utime($t, $t, $p) or die "cannot set the time of $p: $!";
      print $out "$t $b $p\0";
    }
    close($out) or die "cannot write $new: $!";
    if ($old eq "") { print "No source stamps: every file stamped $epoch (a build from nothing).\n"; }
    else { print "Source stamps: $same files unchanged since the cached build, $changed changed or new (stamped $later).\n"; }
  ' "$old" "$new" "$STAMP_EPOCH"
  mv "$new" "$SOURCE_STAMPS"
}

# Decision 545: with CI_BUILD_CACHE=restored, a build on the restored
# .build that fails (a compile error, or a crash built twice) is built once
# more from nothing, so a stale cache can never be the reason a change turns
# red; a real compile error fails again and is reported as before.
build_with_cache() {
  if [[ "${CI_BUILD_CACHE:-}" != restored ]]; then
    build_package
    return
  fi
  if (build_package); then
    return 0
  fi
  echo "::warning::The build on the cached .build failed; building once more from nothing, to rule the cache out (decision 545)."
  rm -rf .build
  stamp_sources
  build_package
}

# Decision 411, shared build: ci.yml's swift-build job builds once and packs
# .build; each shard job unpacks it in the same container and workspace path
# and runs swift test --skip-build, which reads the built products and does
# not look at the sources' times (the checkout's are newer than the build's).
# tar keeps .build's links (debug points into swift-build's own layout).
pack_build() {
  local file="$1"
  [[ -d .build ]] || die "No .build to pack: build first."
  tar -cf - .build | gzip -1 >"$file"
  echo "Packed .build ($(du -sh .build | cut -f1)) into $file ($(du -h "$file" | cut -f1))."
}

unpack_build() {
  local file="$1"
  [[ -s "$file" ]] || die "No build to unpack at $file: did the swift-build job upload it?"
  [[ ! -e .build ]] || die ".build already exists; the shard would not run the downloaded build."
  gzip -dc "$file" | tar -xf -
  rm -f "$file"
  echo "Unpacked the build into .build ($(du -sh .build | cut -f1))."
}

# Decision 404: say so before a shard reaches its job limit, not after.
# Every rebalance above came after a red main, when a shard had drifted
# past ci.yml's 20 minutes (timeout-minutes) as classes were added or grew;
# a cancelled job prints no summary, so its class times had to be read off
# the whole job log. JOB_STARTED (epoch seconds, set by the job's first step
# in ci.yml) gives the job's time so far; the container's start, some 40 s,
# comes before it. Without it (locally) only the class checks run.
# The warning line was 15 minutes; decision 405 put it at 17, since the
# rebalanced shards run to about 16.5 on slow runners and a warning on
# most runs goes unread.
SHARD_WARN_SECONDS="${SHARD_WARN_SECONDS:-1020}"
SHARD_WATCHDOG_SECONDS="${SHARD_WATCHDOG_SECONDS:-1110}"
# A class this long whose weight is missing, or less than half its time,
# is reported: the selected parts are dealt by weight (selected_part).
CLASS_WARN_SECONDS="${CLASS_WARN_SECONDS:-60}"

# Seconds per class from XCTest's lines in the given logs, slowest first:
# "<seconds> <class>".
class_seconds() {
  cat "$@" 2>/dev/null |
    sed -n -E "s/^Test Case '([^.']+)\\.[^']*' (passed|failed) \\(([0-9.]+) seconds\\)/\\3 \\1/p" |
    awk '{ t[$2] += $1 } END { for (c in t) printf "%.0f %s\n", t[c], c }' | sort -rn
}

# Decision 404: SWIFT_TEST_WORKERS > 1 runs each batch with swift test
# --parallel on that many workers (auto: the machine's cores); 1, the
# default and what ci.yml sets, is the serial run of decisions 185 and 329.
# Each test then runs in a test runner process of its own, so a class's
# static fixture is built once per test: on CI that made the shards with
# costly fixtures slower, not faster (decision 404, the table). With
# --verbose swift test prints each test's whole XCTest output (started,
# passed or failed, seconds), one test at a time, so the coverage check,
# the failure count and class_seconds read the log as before; on Swift 6.4
# it prints them all when the batch ends, so the watchdog sees none. (Its --xunit-output report is no help: it gives tests
# that ran side by side the same time, the moment their results came in.)
# Sets WORKERS (not a subshell: die has to end the script).
test_workers() {
  WORKERS="${SWIFT_TEST_WORKERS:-1}"
  [[ "$WORKERS" != auto ]] || WORKERS="$(nproc 2>/dev/null || echo 1)"
  [[ "$WORKERS" =~ ^[1-9][0-9]*$ ]] || die "SWIFT_TEST_WORKERS must be a positive number or auto, not '$WORKERS'."
}

# The Class.method names XCTest's lines in the given logs say have started:
# in a parallel run, the tests that have ended.
started_tests() {
  cat "$@" 2>/dev/null | sed -n -E "s/^Test Case '([^']+)' started.*/\\1/p" | sort -u
}

# "a 274 s, b 113 s, c 92 s" from class_seconds lines on stdin.
slowest_text() {
  awk 'NR <= 3 { printf "%s%s %s s", (NR > 1 ? ", " : ""), $2, $1 }'
}

job_seconds() {
  [[ "${JOB_STARTED:-}" =~ ^[0-9]+$ ]] || return 1
  echo $(($(date +%s) - JOB_STARTED))
}

# time_warnings <shard> <class seconds file>: the warnings decision 404
# prints once a shard's tests are done (they show on the run's summary and
# on a pull request's checks).
time_warnings() {
  local shard="$1" times="$2" job
  if job="$(job_seconds)" && ((job >= SHARD_WARN_SECONDS)); then
    echo "::warning title=Shard $shard near its 20-minute limit::$shard took $((job / 60))m$(printf '%02d' $((job % 60)))s of its 20 minutes (slowest: $(slowest_text <"$times")). Move a class to a shorter shard in classes_of (.github/scripts/swift-shards.sh, decision 404)."
    [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "- :warning: $((job / 60))m$(printf '%02d' $((job % 60)))s of the job's 20 minutes (warns from $((SHARD_WARN_SECONDS / 60)))" >>"$GITHUB_STEP_SUMMARY"
  fi
  local secs class weight
  while read -r secs class; do
    ((secs >= CLASS_WARN_SECONDS)) || break
    weight="$(tr -s ' \n' '\n' <<<"$CLASS_WEIGHTS" | sed -n "s/^$class:\\([0-9]*\\)$/\\1/p")"
    if [[ -z "$weight" ]]; then
      echo "::warning title=$class has no weight::$class took $secs s in $shard and has no CLASS_WEIGHTS entry (.github/scripts/swift-shards.sh, decision 404)."
    elif ((secs > 2 * weight)); then
      echo "::warning title=$class weight out of date::$class took $secs s in $shard; CLASS_WEIGHTS says $weight (.github/scripts/swift-shards.sh, decision 404)."
    fi
  done <"$times"
}

# Runs in the background while a shard's tests run: shortly before the job
# limit cancels the job (and its summary with it), print what ran slowest
# so far.
watchdog() {
  local shard="$1" job
  shift
  job="$(job_seconds)" || return 0
  ((job < SHARD_WATCHDOG_SECONDS)) || return 0
  # Killed when the tests end first: take the sleep with it.
  sleep $((SHARD_WATCHDOG_SECONDS - job)) &
  local nap=$!
  trap 'kill "$nap" 2>/dev/null; exit 0' TERM
  wait "$nap"
  local what="slowest classes so far: $(class_seconds "$@" | slowest_text)"
  if [[ -n "${WATCH_EXPECTED:-}" ]]; then
    # A parallel run prints a test only once it ends: name those still running.
    what="$what; still running: $(started_tests "$@" | comm -23 "$WATCH_EXPECTED" - | awk 'NR <= 4 { printf "%s%s", (NR > 1 ? ", " : ""), $0 }')"
  fi
  echo "::warning title=Shard $shard about to reach its 20-minute limit::$shard has run $((SHARD_WATCHDOG_SECONDS / 60))m$(printf '%02d' $((SHARD_WATCHDOG_SECONDS % 60)))s; $what. Move a class to a shorter shard in classes_of (.github/scripts/swift-shards.sh, decision 404)."
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

  local batches="$WORK/batches.txt" classes batch_rc started rc=0 workers parallel=()
  test_workers
  workers="$WORKERS"
  ((workers == 1)) || parallel=(--parallel --num-workers "$workers" --verbose)
  batch_classes "$shard" "$list" >"$batches"
  echo "Shard $shard: $(wc -l <"$batches" | tr -d ' ') swift test runs$( ((workers == 1)) || echo ", each on $workers workers")."
  : >"$log"
  started="$(date +%s)"
  local batch_log="$WORK/batch.log" watcher=""
  : >"$batch_log"
  if ((workers > 1)); then
    WATCH_EXPECTED="$expected" watchdog "$shard" "$log" "$batch_log" &
  else
    watchdog "$shard" "$log" "$batch_log" &
  fi
  watcher=$!
  # A failed batch does not stop the others; the shard fails after them.
  # A batch whose swift test was killed by a signal before any test started
  # runs once more (decision 329): no test result is thrown away. Once a test
  # has started, a crash may be the test's own and fails the shard.
  local attempt
  while IFS= read -r -u 3 classes; do
    for attempt in 1 2; do
      batch_rc=0
      # shellcheck disable=SC2086
      swift test --skip-build ${SWIFT_EXTRA_ARGS:-} ${parallel[@]+"${parallel[@]}"} --filter "$(pattern_for "$classes")" 2>&1 | tee "$batch_log" || batch_rc=${PIPESTATUS[0]}
      cat "$batch_log" >>"$log"
      if ((attempt == 1)) && killed_by_signal "$batch_rc" && ! grep -q -E "^Test Case '.*' started" "$batch_log"; then
        echo "::warning::swift test was killed by signal $((batch_rc - 128)) (exit code $batch_rc) before any test started: the tool crashed. Running this batch once more."
        continue
      fi
      break
    done
    [[ "$batch_rc" -eq 0 ]] || rc=$batch_rc
  done 3<"$batches"
  local seconds=$(($(date +%s) - started))
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true

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
  # awk, not head: head stops reading after five lines, and sort, still
  # writing a long list (rest's), dies of SIGPIPE, which pipefail turns into
  # a failed shard whose tests all passed.
  sed -n -E "s/^Test Case '([^.']+)\\.[^']*' passed \\(([0-9.]+) seconds\\)/\\2 \\1/p" "$log" |
    awk '{ t[$2] += $1 } END { for (c in t) printf "%8.1fs  %s\n", t[c], c }' | sort -rn | awk 'NR <= 5'
  echo "::endgroup::"
  class_seconds "$log" >"$WORK/class-seconds.txt"

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

  time_warnings "$shard" "$WORK/class-seconds.txt"

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
# Pull request tiers (decision 185), which a push to main uses too (decision
# 413). A manual run and the nightly run test everything; a pull request and
# a push run what their changed files can affect:
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
  # One line, the names split on whitespace.
  # shellcheck disable=SC2086
  echo $tests
}

# The top-level declarations of the test files in directory $1 whose code
# mentions token $2 (a whole word, or with $3 = text, any text), one per line
# as "<file>|<declaration>", the declaration as swift_declarations prints it;
# a mention inside an extension of a type from elsewhere is `opaque` (which
# of its members uses it is not followed). Reads code_cache.
containers_of() {
  local dir="$1" token="$2" mode="${3:-word}"
  # The awk program is in single quotes: its $ are awk's, not the shell's.
  # shellcheck disable=SC2016
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
PRESENTATION_PARTS=8
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
    # jobs share them by the classes' weights (selected_part). They grew from
    # 1,169 s on 2026-10-14 to about 2,450 s on 2026-10-23, when three parts
    # of up to 947 s plus about 4.5 minutes of container and build reached
    # the job's 20 minutes; five parts are about 510 s each (about 13 minutes
    # a job). When a part nears 15 minutes again, add a part. Six since
    # 2026-10-29: the Sanying Line's two real days (decision 400, 10j-3,
    # weights 450 and 300) brought the five parts to about 854 each, and
    # pull request #1448's selected-4 took 18 minutes of tests and
    # selected-5 reached the job's 20 (run 40790641310); six are about 710.
    # Seven since 2026-10-30: #1515's six parts took 493 to 1,026 s of tests
    # (run of 738494a), its selected-3 19.5 minutes of the job's 20, with
    # the Danhai and Liujia classes added; seven are about 700.
    # Eight since 2026-11-01: main 7b09afa's selected-7 reached the 20 minutes
    # (run 41314182024) because DanhaiDepotTests (110 s, weight 11),
    # DemoSightsAndTransfersTests (146 s), HighSpeedDemoBatchTests (137 s) and
    # AnkengLineTests (76 s) were missing or far too light in CLASS_WEIGHTS;
    # with those and a few more refreshed the weights sum to about 6,600 s,
    # 940 s a part for seven and 825 for eight.
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
#   EVENT    push, pull_request, workflow_dispatch or schedule
#   LISTED   true when the changed files (on stdin) could be listed
#   LABELS   the pull request's labels, separated by spaces or new lines
# Prints swift=<true|false>, tier=<tier> and matrix=<JSON> for $GITHUB_OUTPUT
# (and the tests and tier on stderr). A pull request and a push to main run
# the tier of their listed files (decision 185 for pull requests, decision
# 413 for pushes: a push is compared with the last successful push run, so
# the files are everything since); a pull request labelled full-ci, a push
# whose files could not be listed, a manual run and the nightly run are full.
ci_decide() {
  local files swift=true tier=full matrix plan tests parts k sep
  files="$(cat)"
  matrix="$("$0" matrix)"
  if [[ "${LISTED:-false}" == true ]]; then
    swift="$(relevant_paths <<<"$files")"
    if [[ "${EVENT:-}" == pull_request || "${EVENT:-}" == push ]]; then
      if [[ "${EVENT:-}" == pull_request && " $(tr '\n' ' ' <<<"${LABELS:-}") " == *" full-ci "* ]]; then
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
        echo "::warning::Could not plan the tier; running every shard." >&2
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

# Has HEAD already passed every shard? Prints the URL of a successful ci.yml
# run of HEAD whose `rest` shard job (only the full tier has one) succeeded,
# or nothing. The nightly run (decision 413) is skipped when there is one: a
# manual run, a push run whose tier was full, or an earlier nightly run of
# the same commit. Nothing (a warning on stderr) when the API fails, so the
# nightly run then tests everything.
# Needs `gh` with a token that can read Actions (GH_TOKEN) and GITHUB_REPOSITORY.
head_full_run() {
  local head runs id url jobs
  head="$(git rev-parse HEAD)" || { echo "::warning::Cannot read HEAD." >&2; return 0; }
  if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
    echo "::warning::GITHUB_REPOSITORY is not set; cannot look up the runs of HEAD." >&2
    return 0
  fi
  if ! runs="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?head_sha=$head&status=success&per_page=20" \
    --jq '.workflow_runs[] | "\(.id) \(.html_url)"')"; then
    echo "::warning::Could not list the successful ci.yml runs of $head." >&2
    return 0
  fi
  while read -r id url; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    if ! jobs="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$id/jobs?per_page=100" \
      --jq '.jobs[] | select(.conclusion == "success") | .name')"; then
      echo "::warning::Could not list the jobs of run $id." >&2
      continue
    fi
    if grep -q -x -F "Swift 6.4 (Linux) / rest" <<<"$jobs"; then
      echo "$url"
      return 0
    fi
  done <<<"$runs"
  echo "No successful full ci.yml run of $head." >&2
}

# The gate's verdict ("Swift CI (gate)", the check main's branch rule
# requires), from the jobs' results:
#   CHANGES       the change detection's result
#   SWIFT_NEEDED  its swift output
#   TIER          its tier output
#   BUILD         the swift-build job's result (decision 411, shared build)
#   CURRENT       the test jobs' combined result (failure if any job failed,
#                 cancelled if any was cancelled, skipped if none ran)
# Passes only when the detection succeeded and either the build and every
# test job of the tier succeeded or none was needed and none ran.
ci_gate() {
  echo "changes: ${CHANGES:-}; Swift needed: ${SWIFT_NEEDED:-}; tier: ${TIER:-}; build: ${BUILD:-}; Swift 6.4: ${CURRENT:-}"
  [[ "${CHANGES:-}" == success ]] || die "The change detection did not succeed (${CHANGES:-no result})."
  if [[ "${SWIFT_NEEDED:-}" == true ]]; then
    [[ "${BUILD:-}" == success ]] || die "The Swift build did not succeed (${BUILD:-no result}); the test jobs need it."
    [[ "${CURRENT:-}" == success ]] || die "A Swift job of tier ${TIER:-?} did not succeed (Swift 6.4: ${CURRENT:-no result})."
    echo "The build and every Swift 6.4 job of tier ${TIER:-?} passed."
  elif [[ "${SWIFT_NEEDED:-}" == false ]]; then
    [[ "${BUILD:-}" == skipped ]] || die "The Swift jobs were not needed but the build did not skip (${BUILD:-no result})."
    [[ "${CURRENT:-}" == skipped ]] || die "The Swift jobs were not needed but did not skip (Swift 6.4: ${CURRENT:-no result})."
    echo "No file that can change the Swift package changed; the Swift jobs were skipped."
  else
    die "The change detection said neither that the Swift jobs are needed nor that they are not ('${SWIFT_NEEDED:-}')."
  fi
}

# A pull request's gate also waits for ios-build.yml on the same commit
# (decision 265). main's branch rule requires only "Swift CI (gate)", so
# without this a pull request set to merge automatically, or merged by hand
# as soon as the gate turned green, went into main before its Xcode build
# and UI tests had finished: on 2026-10-16 #746 merged six minutes before
# its iOS run failed (RealWorldMapUITests), and #753 three minutes after it
# opened. Passes when the newest pull request run of ios-build.yml for
# HEAD_SHA passed or skipped, or when there is none (a change the app cannot
# see: that workflow's paths-ignore). The two runs start from the same
# event, so one that is coming is already listed; an empty list is looked
# at once more after a poll before it counts as none. A run by hand
# (workflow_dispatch) is not the pull request's. Waits while the run is
# queued or running (ci.yml's timeout bounds it); a run that failed, was
# cancelled or did not start fails the gate. The API failing IOS_GATE_TRIES
# times in a row fails it too: green must mean the iOS run was seen.
ios_gate() {
  local poll="${IOS_GATE_POLL_SECONDS:-30}" tries="${IOS_GATE_TRIES:-10}"
  local errors=0 empty=0 run status conclusion url
  [[ -n "${GITHUB_REPOSITORY:-}" ]] || die "GITHUB_REPOSITORY is not set."
  [[ "${HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || die "HEAD_SHA is not a commit ('${HEAD_SHA:-}')."
  while true; do
    if ! run="$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ios-build.yml/runs?head_sha=$HEAD_SHA&event=pull_request&per_page=20" \
      --jq '[.workflow_runs[]] | sort_by(.run_number) | last // empty | "\(.status) \(.conclusion // "-") \(.html_url)"')"; then
      errors=$((errors + 1))
      (( errors < tries )) || die "Could not list the iOS App Build runs of $HEAD_SHA ($errors tries)."
      echo "::warning::Could not list the iOS App Build runs; trying again in $poll s."
      sleep "$poll"
      continue
    fi
    errors=0
    if [[ -z "$run" ]]; then
      if (( empty == 0 )); then
        empty=1
        sleep "$poll"
        continue
      fi
      echo "No iOS App Build run for $HEAD_SHA: the change is one the app cannot see."
      return 0
    fi
    read -r status conclusion url <<<"$run"
    if [[ "$status" != completed ]]; then
      echo "iOS App Build is $status ($url); looking again in $poll s."
      sleep "$poll"
      continue
    fi
    case "$conclusion" in
      success | skipped)
        echo "iOS App Build passed ($conclusion): $url"
        return 0
        ;;
      cancelled)
        # A gate already waiting here when a newer push cancelled the run
        # cannot be skipped any more (decision 329): say why it is red.
        if [[ -n "${PR:-}" ]] && superseded 2>/dev/null | grep -q -x 'superseded=true'; then
          die "iOS App Build was cancelled because a newer push replaced this commit of pull request #$PR: not a test failure; the newer commit's run gives the verdict ($url)."
        fi
        die "iOS App Build did not pass ($conclusion): $url. After a re-run of it passes, re-run this gate (Re-run failed jobs)."
        ;;
      *)
        die "iOS App Build did not pass ($conclusion): $url. After a re-run of it passes, re-run this gate (Re-run failed jobs)."
        ;;
    esac
  done
}

# Prints superseded=true (the only line on stdout, for $GITHUB_OUTPUT) when this cancelled pull request run is for a
# commit that is no longer the pull request's head: a newer push replaced it
# (ci.yml's cancel-in-progress), and the newer run gives the verdict, so the
# gate is skipped rather than red on a commit no test failed on (decision
# 329; 33 of 36 cancelled runs from 2026-10-19 to 10-21 had a red gate).
# superseded=false otherwise: a run cancelled by hand on the head, or the
# head unreadable, keeps the red gate, which keeps the head from merging.
superseded() {
  local head
  [[ -n "${GITHUB_REPOSITORY:-}" ]] || die "GITHUB_REPOSITORY is not set."
  [[ "${HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || die "HEAD_SHA is not a commit ('${HEAD_SHA:-}')."
  [[ "${PR:-}" =~ ^[0-9]+$ ]] || die "PR is not a pull request number ('${PR:-}')."
  if ! head="$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR" --jq .head.sha)" || [[ ! "$head" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::warning::Could not read the head of pull request #$PR; the gate gives its verdict." >&2
    echo "superseded=false"
  elif [[ "$head" != "$HEAD_SHA" ]]; then
    echo "Pull request #$PR moved on to $head; the run of that commit gives the verdict." >&2
    echo "superseded=true"
  else
    echo "$HEAD_SHA is still the head of pull request #$PR; the gate gives its verdict." >&2
    echo "superseded=false"
  fi
}

case "${1:-}" in
  build)
    build_with_cache
    ;;
  stamp)
    stamp_sources
    ;;
  pack)
    [[ $# -eq 2 ]] || die "usage: $0 pack <file>"
    pack_build "$2"
    ;;
  unpack)
    [[ $# -eq 2 ]] || die "usage: $0 unpack <file>"
    unpack_build "$2"
    ;;
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
  head-full-run)
    head_full_run
    ;;
  gate)
    ci_gate
    ;;
  ios-gate)
    ios_gate
    ;;
  superseded)
    superseded
    ;;
  *)
    die "usage: $0 build | stamp | pack <file> | unpack <file> | run <shard> | select <shard> | shards | classes | matrix | relevant | push-base | plan | decide | head-full-run | gate | ios-gate | superseded"
    ;;
esac
