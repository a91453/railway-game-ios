#!/usr/bin/env bash
# The Swift package's test selections for ci.yml, and a proof that each one ran
# exactly the tests it was meant to run.
#
#   swift-shards.sh build            `swift build --build-tests -Xswiftc
#                                    -warnings-as-errors`, once more when
#                                    swift-build itself crashes (build_package)
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
#   swift-shards.sh ios-gate         a pull request's gate waits for its
#                                    iOS App Build run (ios_gate below)
#   swift-shards.sh superseded       whether a cancelled pull request run was
#                                    replaced by a newer push (superseded)
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
classes_of() {
  case "$1" in
    campaigns-1) echo "ServiceRepeatingPropertyTests ScheduledTrafficPropertyTests WorldStateMachineTests" ;;
    campaigns-2) echo "ServicePropertyTests VerticalRailwayPropertyTests NetworkSectionPropertyTests SingleTrackCapacityPropertyTests RealLineAcquisitionTests Map3DOpenEveryStartTests LessonTests" ;;
    campaigns-3) echo "LineDispatchPropertyTests IdleTrainDeadlockTests LineRoutePreferencePropertyTests TRADemoTests" ;;
    campaigns-4) echo "OccupiedRoutingPropertyTests ContinuousTrackPropertyTests PassengerPropertyTests KernelDifferentialTests DeadlockPropertyTests RealWorldDemoTests" ;;
    campaigns-5) echo "SaveMutationSecondHalfTests ScheduledOvertakeTrackPropertyTests LineLossFixesTests" ;;
    campaigns-6) echo "ServiceRepeatingSecondHalfPropertyTests EconomyPropertyTests CityRequestsTests DemoRealLinesTests Map3DStreetLifeTests StationCommerceCardTests Map3DTests LineLossDiagnosisTests" ;;
    campaigns-7) echo "LinePatternPropertyTests NetworkServicePropertyTests" ;;
    campaigns-8) echo "GoldenScenarioTests ScheduledOvertakeTrackMiddlePropertyTests TimetablePropertyTests ScreenshotSceneTests NewGameBalanceTests" ;;
    campaigns-9) echo "SaveMutationTests EconomySecondHalfPropertyTests NightSkipTests PolicyTests" ;;
    campaigns-10) echo "PassengerPlanKeyTests ReservationShortcutTests FlexDispatchPropertyTests" ;;
    campaigns-11) echo "ScheduledTrafficSecondHalfPropertyTests HighSpeedDemoTests LongLegReplayTests LoopLineBoardingTests" ;;
    campaigns-12) echo "TrafficControlPropertyTests ScheduledOvertakeTrackFinalPropertyTests RealWorldDemoGroundTests RealWorldDataLoadTests MonthlyReportTests Map3DStreetsTests LineConfirmationTests FreightSessionTests Map3DRealGroundTests SparseCityLandTests LinePanelMemoTests Map3DStationKitTests" ;;
    campaigns-13) echo "BoardingPropertyTests TurnbackPropertyTests Map3DSceneMemoryTests Map3DCoarseChunkTests RealRailwayTracingTests Map3DStreamingTests" ;;
    campaigns-14) echo "ServiceLinePropertyTests OnboardingTests CommandLogTests ScheduledTrafficTests TurnbackTests" ;;
    campaigns-15) echo "TrafficFollowingPropertyTests ScheduledOvertakeTrackLastPropertyTests Map3DRealBuildingsTests MetroStructuresTests NewGameCampaignTests PingxiChallengeTests RealWorldExpansionTests Map3DShadowTests ShortTurnCardTests" ;;
    campaigns-16) echo "HighSpeedDemoDayTests TRADemoDayTests HighSpeedDemoBatchTests LocalPassTests LineAccountsTests LoadJourneyCacheTests NewsSessionTests DemoAtTests Map3DNextDepartureTests TutorialSessionTests Map3DSignTests Map3DPropsTests Map3DSurfaceTests SeededStreetPlanTests Map3DBuildingsTests AutoServiceTests Map3DHandoffTests Map3DDetailTests Map3DNightAndGroundTests" ;;
    *) return 1 ;;
  esac
}
CAMPAIGN_SHARDS=(campaigns-1 campaigns-2 campaigns-3 campaigns-4 campaigns-5 campaigns-6 campaigns-7 campaigns-8 campaigns-9 campaigns-10 campaigns-11 campaigns-12 campaigns-13 campaigns-14 campaigns-15 campaigns-16)
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
# (selected_part). GameCore's: the slowest of each class in the five full
# runs of main the balance note above names, 2026-10-14. GamePresentation's
# (from HighSpeedDemoTests on): the slowest of each class in the nine
# selected-N jobs of pull request runs 39980434405, 39981278980 and
# 39983144028, 2026-10-23, where TRADemoTests (121 s) and LessonGuideTests
# (62 s) had no weight and counted as a second each. Every class of 3 s or
# more, in either module, is listed: a partial tier is not only GamePresentation's
# classes, as a fixture directory or an edited test file adds GameCore ones
# (GoldenScenarioTests 333 s, ReservationShortcutTests 154 s), which with the
# default weight once counted like a class of a second and could load one
# part with minutes more than the others. Any other class counts
# CLASS_WEIGHT_DEFAULT (the 272 GamePresentation classes under 3 s took
# 0.5 s each on average, 2026-10-23). Only the proportions matter: a stale or missing weight moves a
# class to another part, never out of the selection.
CLASS_WEIGHTS="BoardingPropertyTests:624 LineDispatchPropertyTests:602
  ServiceLinePropertyTests:487 SaveMutationSecondHalfTests:478
  TrafficControlPropertyTests:475 TrafficFollowingPropertyTests:434
  PassengerPlanKeyTests:405 LinePatternPropertyTests:401
  ServicePropertyTests:398 ServiceRepeatingSecondHalfPropertyTests:395
  ServiceRepeatingPropertyTests:390 SaveMutationTests:359
  EconomySecondHalfPropertyTests:350 GoldenScenarioTests:333
  NetworkServicePropertyTests:289 EconomyPropertyTests:288
  ScheduledTrafficSecondHalfPropertyTests:268
  ScheduledTrafficPropertyTests:260 VerticalRailwayPropertyTests:217
  ScheduledOvertakeTrackFinalPropertyTests:177
  ScheduledOvertakeTrackMiddlePropertyTests:175 TimetablePropertyTests:168
  ScheduledOvertakeTrackPropertyTests:165 ContinuousTrackPropertyTests:165
  KernelDifferentialTests:163 FlexDispatchPropertyTests:161
  ReservationShortcutTests:154 DeadlockPropertyTests:135
  PassengerPropertyTests:132 ScheduledOvertakeTrackLastPropertyTests:128
  OccupiedRoutingPropertyTests:78 WorldStateMachineTests:65
  NetworkSectionPropertyTests:50 IdleTrainDeadlockTests:48
  ScheduledTrafficTests:46 LineAccountsTests:35 TurnbackPropertyTests:33
  TurnbackTests:32 ReplayFixtureTests:28 CityRequestsTests:26
  LoadJourneyCacheTests:25 LineRoutePreferencePropertyTests:24
  SingleTrackCapacityPropertyTests:24 LoadTrackCheckIndexTests:17
  CityGrowthTests:13 TrainTripLogTests:12 TownGrowthTests:10
  ScheduledOvertakeTrackTests:10 PassengerTransferTests:9
  EconomyAccountsTests:9 CurveSpeedRunTests:8 ReferenceWorldGoldenTests:8
  LoadFoulingIndexTests:7 LineRoutePreferenceTests:7 RunDepotTests:6
  SavedGameTests:6 DeadlockTests:6 LineDispatchTests:5 TrafficControlTests:5
  TrackCheckShortcutTests:4 ContinuousTrackTests:4 BuildingTests:4
  BlockSectionsTests:4 LandDemandTests:4 HighSpeedTests:4 BoardingTests:3
  LocalPassTests:59 LongLegReplayTests:16
  HighSpeedDemoTests:393 HighSpeedDemoDayTests:328 TRADemoTests:121
  HighSpeedDemoBatchTests:120 NewGameSavePropertyTests:89 TRADemoDayTests:75
  OnboardingTests:70 CommandLogTests:66 LessonGuideTests:62
  RealLineAcquisitionTests:62 NetworkPostcardTests:61 Map3DSceneMemoryTests:57
  NightSkipTests:57 RealWorldDemoTests:51 LineLossFixesTests:49
  Map3DCoarseChunkTests:31 Map3DStreetLifeTests:29 RealRailwayTracingTests:29
  DemoRealLinesTests:26 Map3DStreamingTests:25 Map3DStreetsTests:25
  Map3DOpenEveryStartTests:23 MonthlyReportTests:19 Map3DSurfaceTests:18
  Map3DTests:18 RealWorldDataLoadTests:18 LessonTests:17
  NewGameBalanceTests:17 NewsSessionTests:17 PolicyTests:17
  RealWorldDemoGroundTests:17 Map3DRealBuildingsTests:15
  StationCommerceCardTests:14 LineConfirmationTests:13
  LineLossDiagnosisTests:13 ScreenshotSceneTests:13 DemoAtTests:12
  MetroStructuresTests:12 AchievementsTests:11 SeededStreetPlanTests:11
  FreightSessionTests:10 LoopLineBoardingTests:10 Map3DRealGroundTests:10
  AutoServiceTests:9 Map3DBuildingsTests:9 MapMarksTests:9
  PingxiChallengeTests:9 Map3DHandoffTests:8 Map3DNextDepartureTests:8
  Map3DSignTests:8 NewGameCampaignTests:8 SparseCityLandTests:8
  TrainSessionPropertyTests:8 TutorialSessionTests:8 CompanyRankTests:7
  LinePanelMemoTests:7 Map3DModelTests:7 Map3DNightAndGroundTests:7
  Map3DPropsTests:7 Map3DStationKitTests:7 Map3DDetailTests:6
  Map3DRealTrainsTests:6 Map3DShadowTests:6 RealWorldExpansionTests:6
  ScreenFactsTests:6 StationDemandSessionTests:6 DepartureBoardTests:5
  HeadlessGameTests:5 HolidayTextTests:5 NextStepsTests:5 ShortTurnCardTests:5
  StationOperationsTests:5 BackgroundSaveTests:4 LineSatisfactionTests:4
  Map3DTaipeiLandmarksTests:4 Map3DTrainLabelsTests:4 MenuChoicesTests:4
  TrainRosterTests:4 WaterGridTests:4 WebsiteTimelineTests:4
  WholeTaiwanTests:4 AutosaveSlotsTests:3 DemoWorldTests:3
  DoubleTrackUpgradeTests:3 GameLauncherTests:3 JourneyTraceTests:3
  LandImportTests:3 LineDraftSummaryTests:3 Map3DParksTests:3
  Map3DSceneKitTests:3 Map3DStationsTests:3 SimpleRulesTests:3
  TodayAccountTests:3 TrafficOverlayTests:3"
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
  # A batch whose swift test was killed by a signal before any test started
  # runs once more (decision 329): no test result is thrown away. Once a test
  # has started, a crash may be the test's own and fails the shard.
  local attempt batch_log="$WORK/batch.log"
  while IFS= read -r -u 3 classes; do
    for attempt in 1 2; do
      batch_rc=0
      # shellcheck disable=SC2086
      swift test --skip-build ${SWIFT_EXTRA_ARGS:-} --filter "$(pattern_for "$classes")" 2>&1 | tee "$batch_log" || batch_rc=${PIPESTATUS[0]}
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
PRESENTATION_PARTS=5
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
    # a job). When a part nears 15 minutes again, add a part.
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
    build_package
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
    die "usage: $0 build | run <shard> | select <shard> | shards | classes | matrix | relevant | push-base | plan | decide | gate | ios-gate | superseded"
    ;;
esac
